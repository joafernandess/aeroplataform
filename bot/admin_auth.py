"""
Dashboard administrators: password hashing, accounts and sessions.

  - Passwords: scrypt (stdlib), random 16-byte salt, constant-time check
  - Sessions: random token in an HttpOnly cookie; only its SHA-256 is
    stored, so a leaked database does not give live sessions
  - Each session has its own CSRF token, required on every write request

Accounts are created from the terminal (python manage.py create-admin),
never from the web, so there is no sign-up page to attack.
"""
import base64
import hashlib
import hmac
import secrets
import sqlite3
import struct
import time

import config
import database as db

MIN_PASSWORD_LENGTH = 12
_SCRYPT_N, _SCRYPT_R, _SCRYPT_P = 2 ** 14, 8, 1

# Used to spend the same time when the username does not exist
_DUMMY_HASH: str | None = None


# ---------------------------------------------------------------------------
# Passwords
# ---------------------------------------------------------------------------
def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.scrypt(
        password.encode("utf-8"), salt=salt,
        n=_SCRYPT_N, r=_SCRYPT_R, p=_SCRYPT_P, dklen=32,
    )
    return f"scrypt${_SCRYPT_N}${_SCRYPT_R}${_SCRYPT_P}${salt.hex()}${digest.hex()}"


def verify_password(password: str, stored: str) -> bool:
    try:
        algo, n, r, p, salt_hex, hash_hex = stored.split("$")
        if algo != "scrypt":
            return False
        digest = hashlib.scrypt(
            password.encode("utf-8"), salt=bytes.fromhex(salt_hex),
            n=int(n), r=int(r), p=int(p), dklen=len(bytes.fromhex(hash_hex)),
        )
    except (ValueError, TypeError):
        return False
    return hmac.compare_digest(digest.hex(), hash_hex)


def password_problem(password: str) -> str | None:
    if len(password) < MIN_PASSWORD_LENGTH:
        return f"Password must have at least {MIN_PASSWORD_LENGTH} characters."
    return None


# ---------------------------------------------------------------------------
# Accounts
# ---------------------------------------------------------------------------
def create_admin(username: str, password: str) -> None:
    username = (username or "").strip()
    if not username or len(username) > 32 or not username.replace("_", "").replace("-", "").isalnum():
        raise ValueError("Username: 1-32 letters, digits, '-' or '_'.")
    problem = password_problem(password)
    if problem:
        raise ValueError(problem)
    conn = db._db()
    with db._lock:
        try:
            conn.execute(
                "INSERT INTO admins (username, password_hash, created_at) VALUES (?, ?, ?)",
                (username, hash_password(password), db.now()),
            )
        except sqlite3.IntegrityError as exc:
            raise ValueError(f"Admin '{username}' already exists.") from exc
        conn.commit()


def set_password(username: str, password: str) -> bool:
    problem = password_problem(password)
    if problem:
        raise ValueError(problem)
    conn = db._db()
    with db._lock:
        cur = conn.execute(
            "UPDATE admins SET password_hash = ? WHERE username = ?",
            (hash_password(password), username),
        )
        row = conn.execute(
            "SELECT id FROM admins WHERE username = ?", (username,)
        ).fetchone()
        if row is not None:
            # A new password ends every open session of that admin
            conn.execute("DELETE FROM admin_sessions WHERE admin_id = ?", (row["id"],))
        conn.commit()
        return cur.rowcount > 0


def delete_admin(username: str) -> bool:
    conn = db._db()
    with db._lock:
        row = conn.execute(
            "SELECT id FROM admins WHERE username = ?", (username,)
        ).fetchone()
        if row is None:
            return False
        conn.execute("DELETE FROM admin_sessions WHERE admin_id = ?", (row["id"],))
        conn.execute("DELETE FROM admins WHERE id = ?", (row["id"],))
        conn.commit()
        return True


def list_admins() -> list[sqlite3.Row]:
    return db._db().execute(
        """SELECT id, username, created_at, last_login,
                  totp_secret IS NOT NULL AS has_2fa
           FROM admins ORDER BY username"""
    ).fetchall()


def admin_count() -> int:
    return db._db().execute("SELECT COUNT(*) AS n FROM admins").fetchone()["n"]


def authenticate(username: str, password: str) -> sqlite3.Row | None:
    global _DUMMY_HASH
    row = db._db().execute(
        "SELECT * FROM admins WHERE username = ?", ((username or "").strip(),)
    ).fetchone()
    if row is None:
        if _DUMMY_HASH is None:
            _DUMMY_HASH = hash_password(secrets.token_hex(16))
        verify_password(password or "", _DUMMY_HASH)  # same timing either way
        return None
    if not verify_password(password or "", row["password_hash"]):
        return None
    return row


# ---------------------------------------------------------------------------
# Two-factor authentication (TOTP, RFC 6238: Google Authenticator, Authy, ...)
# ---------------------------------------------------------------------------
_TOTP_PERIOD = 30


def new_totp_secret() -> str:
    return base64.b32encode(secrets.token_bytes(20)).decode("ascii").rstrip("=")


def _hotp(secret_b32: str, counter: int, digits: int = 6) -> str:
    key = base64.b32decode(secret_b32 + "=" * (-len(secret_b32) % 8), casefold=True)
    mac = hmac.new(key, struct.pack(">Q", counter), hashlib.sha1).digest()
    offset = mac[-1] & 0x0F
    value = struct.unpack(">I", mac[offset:offset + 4])[0] & 0x7FFFFFFF
    return str(value % (10 ** digits)).zfill(digits)


def totp_at(secret_b32: str, ts: float | None = None, digits: int = 6) -> str:
    return _hotp(secret_b32, int((ts if ts is not None else time.time()) // _TOTP_PERIOD), digits)


def totp_uri(username: str, secret_b32: str) -> str:
    return (
        f"otpauth://totp/LoaderControl:{username}"
        f"?secret={secret_b32}&issuer=LoaderControl"
    )


def verify_totp(
    admin_id: int, secret_b32: str, code: str, ts: float | None = None
) -> bool:
    """
    Accepts the code of the previous, current or next 30 s step (clock drift).
    Each step works once: a code that was already used is refused, so a
    shoulder-surfed or intercepted code cannot be replayed.
    """
    code = (code or "").strip().replace(" ", "")
    if len(code) != 6 or not code.isdigit():
        return False
    step_now = int((ts if ts is not None else time.time()) // _TOTP_PERIOD)
    conn = db._db()
    with db._lock:
        row = conn.execute(
            "SELECT totp_last_step FROM admins WHERE id = ?", (admin_id,)
        ).fetchone()
        last = row["totp_last_step"] if row is not None else 0
        for step in (step_now - 1, step_now, step_now + 1):
            if step > last and hmac.compare_digest(_hotp(secret_b32, step), code):
                conn.execute(
                    "UPDATE admins SET totp_last_step = ? WHERE id = ?", (step, admin_id)
                )
                conn.commit()
                return True
    return False


def set_totp_secret(username: str, secret_b32: str | None) -> bool:
    """Turns 2FA on (secret) or off (None) and ends the admin's sessions."""
    conn = db._db()
    with db._lock:
        row = conn.execute(
            "SELECT id FROM admins WHERE username = ?", (username,)
        ).fetchone()
        if row is None:
            return False
        conn.execute(
            "UPDATE admins SET totp_secret = ?, totp_last_step = 0 WHERE id = ?",
            (secret_b32, row["id"]),
        )
        conn.execute("DELETE FROM admin_sessions WHERE admin_id = ?", (row["id"],))
        conn.commit()
        return True


# ---------------------------------------------------------------------------
# Sessions
# ---------------------------------------------------------------------------
def _token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def create_session(admin_id: int, ip: str | None) -> tuple[str, str]:
    """Returns (session_token, csrf_token)."""
    token = secrets.token_urlsafe(32)
    csrf = secrets.token_urlsafe(32)
    ts = db.now()
    conn = db._db()
    with db._lock:
        conn.execute("DELETE FROM admin_sessions WHERE expires_at < ?", (ts,))
        conn.execute(
            """INSERT INTO admin_sessions (token_hash, admin_id, csrf, ip,
                                           created_at, expires_at)
               VALUES (?, ?, ?, ?, ?, ?)""",
            (
                _token_hash(token), admin_id, csrf, (ip or "")[:64], ts,
                ts + config.DASHBOARD_SESSION_HOURS * 3600,
            ),
        )
        conn.execute("UPDATE admins SET last_login = ? WHERE id = ?", (ts, admin_id))
        conn.commit()
    return token, csrf


def get_session(token: str | None) -> sqlite3.Row | None:
    """Session joined with its admin, or None when missing/expired."""
    if not token:
        return None
    return db._db().execute(
        """SELECT s.token_hash, s.csrf, s.expires_at, a.id AS admin_id,
                  a.username
           FROM admin_sessions s JOIN admins a ON a.id = s.admin_id
           WHERE s.token_hash = ? AND s.expires_at > ?""",
        (_token_hash(token), db.now()),
    ).fetchone()


def delete_session(token: str | None) -> None:
    if not token:
        return
    conn = db._db()
    with db._lock:
        conn.execute(
            "DELETE FROM admin_sessions WHERE token_hash = ?", (_token_hash(token),)
        )
        conn.commit()
