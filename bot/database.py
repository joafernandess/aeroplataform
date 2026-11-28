"""
SQLite database for the key system.

Tables:
  keys - one row per generated key
"""
import os
import secrets
import string
import sqlite3
import threading
import time
from datetime import datetime, timezone

import config

KEY_ALPHABET = string.ascii_letters + string.digits
KEY_LENGTH = 32

_lock = threading.Lock()
_conn: sqlite3.Connection | None = None


def _add_column(conn: sqlite3.Connection, table: str, column_def: str) -> None:
    """ALTER TABLE ... ADD COLUMN that is a no-op when the column exists."""
    try:
        conn.execute(f"ALTER TABLE {table} ADD COLUMN {column_def}")
    except sqlite3.OperationalError:
        pass  # column already exists


def _migrate_loader_system(conn: sqlite3.Connection) -> None:
    """Tables for games, loaders, key permissions, logs and the dashboard."""
    # Key state managed from the dashboard. all_games=1 keeps the old
    # behavior: existing keys keep access to every game.
    _add_column(conn, "keys", "active INTEGER NOT NULL DEFAULT 1")
    _add_column(conn, "keys", "revoked_at INTEGER")
    _add_column(conn, "keys", "all_games INTEGER NOT NULL DEFAULT 1")
    _add_column(conn, "keys", "last_loader_id TEXT")
    _add_column(conn, "keys", "last_access INTEGER")

    conn.executescript("""
        CREATE TABLE IF NOT EXISTS games (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            slug        TEXT NOT NULL UNIQUE,
            name        TEXT NOT NULL,
            place_ids   TEXT NOT NULL DEFAULT '',
            enabled     INTEGER NOT NULL DEFAULT 1,
            is_default  INTEGER NOT NULL DEFAULT 0,
            created_at  INTEGER NOT NULL,
            updated_at  INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS loaders (
            id          TEXT PRIMARY KEY,
            game_id     INTEGER,
            name        TEXT NOT NULL,
            enabled     INTEGER NOT NULL DEFAULT 1,
            version     INTEGER NOT NULL DEFAULT 1,
            size        INTEGER NOT NULL DEFAULT 0,
            sha256      TEXT,
            created_at  INTEGER NOT NULL,
            updated_at  INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_loaders_game ON loaders (game_id);

        CREATE TABLE IF NOT EXISTS key_games (
            key      TEXT NOT NULL,
            game_id  INTEGER NOT NULL,
            PRIMARY KEY (key, game_id)
        );

        CREATE TABLE IF NOT EXISTS access_log (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            ts         INTEGER NOT NULL,
            source     TEXT NOT NULL,
            key        TEXT,
            game_id    INTEGER,
            loader_id  TEXT,
            ip         TEXT,
            hwid       TEXT,
            ok         INTEGER NOT NULL,
            reason     TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_access_ts ON access_log (ts);
        CREATE INDEX IF NOT EXISTS idx_access_key ON access_log (key);

        CREATE TABLE IF NOT EXISTS activity (
            id      INTEGER PRIMARY KEY AUTOINCREMENT,
            ts      INTEGER NOT NULL,
            actor   TEXT NOT NULL,
            action  TEXT NOT NULL,
            detail  TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_activity_ts ON activity (ts);

        CREATE TABLE IF NOT EXISTS admins (
            id             INTEGER PRIMARY KEY AUTOINCREMENT,
            username       TEXT NOT NULL UNIQUE,
            password_hash  TEXT NOT NULL,
            created_at     INTEGER NOT NULL,
            last_login     INTEGER
        );

        CREATE TABLE IF NOT EXISTS admin_sessions (
            token_hash  TEXT PRIMARY KEY,
            admin_id    INTEGER NOT NULL,
            csrf        TEXT NOT NULL,
            ip          TEXT,
            created_at  INTEGER NOT NULL,
            expires_at  INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS kv (
            k           TEXT PRIMARY KEY,
            v           TEXT,
            updated_at  INTEGER NOT NULL
        );
    """)
    # Renewal tickets, automatic Pix payments and 2FA for dashboard admins
    _add_column(conn, "tickets", "renew_key TEXT")
    _add_column(conn, "tickets", "pay_id TEXT")
    _add_column(conn, "tickets", "pay_amount REAL")
    _add_column(conn, "admins", "totp_secret TEXT")
    _add_column(conn, "admins", "totp_last_step INTEGER NOT NULL DEFAULT 0")


def _connect() -> sqlite3.Connection:
    os.makedirs(os.path.dirname(config.DATABASE_PATH), exist_ok=True)
    conn = sqlite3.connect(config.DATABASE_PATH, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("""
        CREATE TABLE IF NOT EXISTS keys (
            key          TEXT PRIMARY KEY,
            discord_id   INTEGER,
            hwid         TEXT,
            executions   INTEGER NOT NULL DEFAULT 0,
            hwid_resets  INTEGER NOT NULL DEFAULT 0,
            first_exec   INTEGER,
            last_exec    INTEGER,
            expires_at   INTEGER,
            banned       INTEGER NOT NULL DEFAULT 0,
            ban_reason   TEXT,
            ban_until    INTEGER,
            note         TEXT,
            created_at   INTEGER NOT NULL,
            redeemed_at  INTEGER
        )
    """)
    conn.execute("""
        CREATE INDEX IF NOT EXISTS idx_keys_discord
        ON keys (discord_id)
    """)
    # Migration: expiration reminder flag (added later)
    try:
        conn.execute(
            "ALTER TABLE keys ADD COLUMN "
            "exp_reminded INTEGER NOT NULL DEFAULT 0"
        )
    except sqlite3.OperationalError:
        pass  # column already exists
    # Buy tickets live here (not in memory) so they survive restarts
    conn.execute("""
        CREATE TABLE IF NOT EXISTS tickets (
            channel_id  INTEGER PRIMARY KEY,
            buyer_id    INTEGER NOT NULL,
            product_id  TEXT,
            paid        INTEGER NOT NULL DEFAULT 0,
            approved    INTEGER NOT NULL DEFAULT 0,
            created_at  INTEGER NOT NULL
        )
    """)
    _migrate_loader_system(conn)
    conn.commit()
    return conn


def _db() -> sqlite3.Connection:
    global _conn
    if _conn is None:
        _conn = _connect()
    return _conn


def _new_key() -> str:
    return "".join(secrets.choice(KEY_ALPHABET) for _ in range(KEY_LENGTH))


def now() -> int:
    return int(time.time())


# ---------------------------------------------------------------------------
# Generation / lookup
# ---------------------------------------------------------------------------
def generate_keys(
    count: int,
    days: int = 0,
    note: str = "",
    game_ids: list[int] | None = None,
) -> list[str]:
    """
    Generates `count` keys. days=0 means the expiration is permanent.
    game_ids=None gives access to every game; a list restricts the key
    to those games.
    """
    conn = _db()
    expires_at = now() + days * 86400 if days > 0 else None
    all_games = 1 if game_ids is None else 0
    created: list[str] = []
    with _lock:
        for _ in range(count):
            for _attempt in range(10):
                key = _new_key()
                exists = conn.execute(
                    "SELECT 1 FROM keys WHERE key = ?", (key,)
                ).fetchone()
                if not exists:
                    break
            conn.execute(
                """INSERT INTO keys (key, expires_at, note, created_at, all_games)
                   VALUES (?, ?, ?, ?, ?)""",
                (key, expires_at, note or None, now(), all_games),
            )
            for game_id in game_ids or []:
                conn.execute(
                    "INSERT OR IGNORE INTO key_games (key, game_id) VALUES (?, ?)",
                    (key, game_id),
                )
            created.append(key)
        conn.commit()
    return created


def get_key(key: str) -> sqlite3.Row | None:
    return _db().execute(
        "SELECT * FROM keys WHERE key = ?", (key.strip(),)
    ).fetchone()


def get_user_key(discord_id: int) -> sqlite3.Row | None:
    """Returns the most recently redeemed key for that user."""
    return _db().execute(
        """SELECT * FROM keys WHERE discord_id = ?
           ORDER BY redeemed_at DESC LIMIT 1""",
        (discord_id,),
    ).fetchone()


def list_recent(limit: int = 15) -> list[sqlite3.Row]:
    return _db().execute(
        "SELECT * FROM keys ORDER BY created_at DESC LIMIT ?", (limit,)
    ).fetchall()


def count_keys() -> tuple[int, int, int]:
    """Returns (total, redeemed, banned)."""
    row = _db().execute(
        """SELECT COUNT(*) AS total,
                  SUM(CASE WHEN discord_id IS NOT NULL THEN 1 ELSE 0 END) AS redeemed,
                  SUM(CASE WHEN banned = 1 THEN 1 ELSE 0 END) AS banned
           FROM keys"""
    ).fetchone()
    return row["total"] or 0, row["redeemed"] or 0, row["banned"] or 0


# ---------------------------------------------------------------------------
# Redemption
# ---------------------------------------------------------------------------
def redeem(key: str, discord_id: int) -> tuple[str, sqlite3.Row | None]:
    """
    Links a key to a user.
    Returns (code, row):
      ok | not_found | already | taken | banned | expired
    """
    conn = _db()
    key = key.strip()
    with _lock:
        row = conn.execute(
            "SELECT * FROM keys WHERE key = ?", (key,)
        ).fetchone()
        if row is None:
            return "not_found", None
        if row["discord_id"] == discord_id:
            return "already", row
        if row["discord_id"] is not None:
            return "taken", row
        if row["revoked_at"] or not row["active"]:
            return "inactive", row
        if _active_ban(row):
            return "banned", row
        if _is_expired(row):
            return "expired", row

        conn.execute(
            "UPDATE keys SET discord_id = ?, redeemed_at = ? WHERE key = ?",
            (discord_id, now(), key),
        )
        conn.commit()
        row = conn.execute(
            "SELECT * FROM keys WHERE key = ?", (key,)
        ).fetchone()
        return "ok", row


# ---------------------------------------------------------------------------
# Key status
# ---------------------------------------------------------------------------
def _is_expired(row: sqlite3.Row) -> bool:
    return (
        row["expires_at"] is not None and now() >= row["expires_at"]
    )


def _active_ban(row: sqlite3.Row) -> bool:
    if row["banned"] != 1:
        return False
    if row["ban_until"] is not None and now() >= row["ban_until"]:
        return False  # temporary ban already expired
    return True


def status(row: sqlite3.Row) -> str:
    """ok | revoked | inactive | banned | expired"""
    if row["revoked_at"]:
        return "revoked"
    if not row["active"]:
        return "inactive"
    if _active_ban(row):
        return "banned"
    if _is_expired(row):
        return "expired"
    return "ok"


def _key_problem(row: sqlite3.Row) -> str | None:
    """Refusal reason for the key's state, or None when it can be used."""
    if row["revoked_at"]:
        return "This key has been revoked."
    if not row["active"]:
        return "This key is disabled. Contact support."
    if _active_ban(row):
        return "This key has been banned."
    if _is_expired(row):
        return "This key has expired."
    return None


def _allows_game(conn: sqlite3.Connection, row: sqlite3.Row, game_id: int) -> bool:
    if row["all_games"]:
        return True
    return conn.execute(
        "SELECT 1 FROM key_games WHERE key = ? AND game_id = ?",
        (row["key"], game_id),
    ).fetchone() is not None


def check_key(
    key: str, game_id: int | None = None
) -> tuple[sqlite3.Row | None, str | None]:
    """
    Validates a key (state + optional game permission) without recording
    an execution. Returns (row, refusal_reason); reason None = allowed.
    """
    conn = _db()
    row = conn.execute(
        "SELECT * FROM keys WHERE key = ?", ((key or "").strip(),)
    ).fetchone()
    if row is None:
        return None, "Invalid or unknown key."
    problem = _key_problem(row)
    if problem:
        return row, problem
    if game_id is not None and not _allows_game(conn, row, game_id):
        return row, "This key does not have access to this game."
    return row, None


def key_game_ids(key: str) -> list[int]:
    rows = _db().execute(
        "SELECT game_id FROM key_games WHERE key = ? ORDER BY game_id",
        (key.strip(),),
    ).fetchall()
    return [r["game_id"] for r in rows]


def set_key_games(key: str, all_games: bool, game_ids: list[int]) -> bool:
    """Replaces the key's game permissions. False when the key is unknown."""
    conn = _db()
    key = key.strip()
    with _lock:
        cur = conn.execute(
            "UPDATE keys SET all_games = ? WHERE key = ?",
            (1 if all_games else 0, key),
        )
        if cur.rowcount == 0:
            return False
        conn.execute("DELETE FROM key_games WHERE key = ?", (key,))
        if not all_games:
            for game_id in game_ids:
                conn.execute(
                    "INSERT OR IGNORE INTO key_games (key, game_id) VALUES (?, ?)",
                    (key, game_id),
                )
        conn.commit()
        return True


def set_key_active(key: str, active: bool) -> bool:
    conn = _db()
    with _lock:
        cur = conn.execute(
            "UPDATE keys SET active = ? WHERE key = ? AND revoked_at IS NULL",
            (1 if active else 0, key.strip()),
        )
        conn.commit()
        return cur.rowcount > 0


def revoke_key(key: str) -> bool:
    """Permanently disables a key (kept for history, cannot be re-enabled)."""
    conn = _db()
    with _lock:
        cur = conn.execute(
            """UPDATE keys SET revoked_at = ?, active = 0
               WHERE key = ? AND revoked_at IS NULL""",
            (now(), key.strip()),
        )
        conn.commit()
        return cur.rowcount > 0


def set_key_expiration(key: str, expires_at: int | None) -> bool:
    """Sets an exact expiration (None = permanent) and re-arms the reminder."""
    conn = _db()
    with _lock:
        cur = conn.execute(
            """UPDATE keys SET expires_at = ?, exp_reminded = 0
               WHERE key = ?""",
            (expires_at, key.strip()),
        )
        conn.commit()
        return cur.rowcount > 0


def touch_key_access(key: str, loader_id: str | None) -> None:
    """Records that the key was used to request a loader (bot path)."""
    conn = _db()
    with _lock:
        conn.execute(
            """UPDATE keys SET last_access = ?,
                   last_loader_id = COALESCE(?, last_loader_id)
               WHERE key = ?""",
            (now(), loader_id, key.strip()),
        )
        conn.commit()


# ---------------------------------------------------------------------------
# HWID / executions
# ---------------------------------------------------------------------------
def reset_hwid(discord_id: int) -> bool:
    conn = _db()
    with _lock:
        cur = conn.execute(
            """UPDATE keys SET hwid = NULL, hwid_resets = hwid_resets + 1
               WHERE discord_id = ?""",
            (discord_id,),
        )
        conn.commit()
        return cur.rowcount > 0


def reset_key_hwid(key: str, count: bool = False) -> bool:
    """
    Admin reset of one key's HWID (dashboard). Does not use up the buyer's
    self-service reset allowance unless count=True.
    """
    conn = _db()
    with _lock:
        cur = conn.execute(
            f"""UPDATE keys SET hwid = NULL
                {", hwid_resets = hwid_resets + 1" if count else ""}
                WHERE key = ?""",
            (key.strip(),),
        )
        conn.commit()
        return cur.rowcount > 0


# A real HWID is a long unique ID (gethwid() hashes, Roblox client ids...).
# Executor names ("Synapse X", "Wave") are not one: everyone running the same
# executor would share the same "PC".
MIN_HWID_LENGTH = 16


def hwid_problem(hwid: str) -> str | None:
    """Why this HWID cannot be used to lock a key, or None when it is fine."""
    hwid = (hwid or "").strip()
    if not hwid:
        return (
            "No HWID was received from your executor, so the key cannot be "
            "locked to this PC. Use an executor with HWID support."
        )
    if (
        len(hwid) < MIN_HWID_LENGTH
        or not any(c.isdigit() for c in hwid)
        or len(set(hwid)) < 6
    ):
        return (
            "Your executor did not provide a valid HWID (it must be a unique "
            "ID of your PC, not the executor's name). Use an executor with "
            "HWID support."
        )
    return None


def register_execution(
    key: str,
    hwid: str,
    game_id: int | None = None,
    loader_id: str | None = None,
) -> tuple[bool, str | None]:
    """
    Validates the key and records an execution.
    Returns (allowed, refusal_reason).

    game_id, when given, must be a game the key has access to.
    loader_id is recorded as the last loader requested with the key.

    HWID rules:
      - First execution with a non-empty HWID: registers it.
      - HWID already stored and the given one differs: refused (the user
        must reset the HWID from the Discord panel).
      - Empty HWID: refused. Accepting it would let any client skip the
        lock by simply not sending a HWID.
    """
    conn = _db()
    hwid = (hwid or "").strip()[:128]
    with _lock:
        row = conn.execute(
            "SELECT * FROM keys WHERE key = ?", (key,)
        ).fetchone()
        if row is None:
            return False, "Invalid or unknown key."
        problem = _key_problem(row)
        if problem:
            return False, problem
        if game_id is not None and not _allows_game(conn, row, game_id):
            return False, "This key does not have access to this game."
        weak = hwid_problem(hwid)
        if weak:
            return False, weak

        stored = (row["hwid"] or "").strip()
        if stored and hwid_problem(stored):
            # Registered before HWIDs were validated (e.g. an executor name):
            # upgrade it to the real one instead of locking the buyer out.
            stored = ""
        if stored and hwid != stored:
            return False, (
                "This HWID does not match the registered one. "
                "Reset your HWID from the Discord panel or restore this PC."
            )

        ts = now()
        conn.execute(
            """UPDATE keys SET hwid = ?,
                   executions = executions + 1,
                   first_exec = COALESCE(first_exec, ?),
                   last_exec = ?,
                   last_access = ?,
                   last_loader_id = COALESCE(?, last_loader_id)
               WHERE key = ?""",
            (stored or hwid, ts, ts, ts, loader_id, key),
        )
        conn.commit()
        return True, None


# ---------------------------------------------------------------------------
# Administration
# ---------------------------------------------------------------------------
def ban_user(discord_id: int, reason: str = "", days: int = 0) -> bool:
    conn = _db()
    ban_until = now() + days * 86400 if days > 0 else None
    with _lock:
        cur = conn.execute(
            """UPDATE keys SET banned = 1, ban_reason = ?, ban_until = ?
               WHERE discord_id = ?""",
            (reason or None, ban_until, discord_id),
        )
        conn.commit()
        return cur.rowcount > 0


def unban_user(discord_id: int) -> bool:
    conn = _db()
    with _lock:
        cur = conn.execute(
            """UPDATE keys SET banned = 0, ban_reason = NULL,
               ban_until = NULL
               WHERE discord_id = ?""",
            (discord_id,),
        )
        conn.commit()
        return cur.rowcount > 0


def ban_key(key: str, reason: str = "", days: int = 0) -> bool:
    """Bans one key (dashboard). ban_user() bans every key of a Discord user."""
    conn = _db()
    ban_until = now() + days * 86400 if days > 0 else None
    with _lock:
        cur = conn.execute(
            """UPDATE keys SET banned = 1, ban_reason = ?, ban_until = ?
               WHERE key = ?""",
            (reason or None, ban_until, key.strip()),
        )
        conn.commit()
        return cur.rowcount > 0


def unban_key(key: str) -> bool:
    conn = _db()
    with _lock:
        cur = conn.execute(
            """UPDATE keys SET banned = 0, ban_reason = NULL, ban_until = NULL
               WHERE key = ?""",
            (key.strip(),),
        )
        conn.commit()
        return cur.rowcount > 0


def access_by_user() -> dict[int, bool]:
    """
    {discord_id: has at least one usable key}. A user whose keys are all
    expired / revoked / disabled / banned maps to False (loses the buyer role).
    """
    rows = _db().execute(
        "SELECT * FROM keys WHERE discord_id IS NOT NULL"
    ).fetchall()
    result: dict[int, bool] = {}
    for row in rows:
        uid = row["discord_id"]
        result[uid] = result.get(uid, False) or status(row) == "ok"
    return result


def set_note(key: str, note: str) -> bool:
    conn = _db()
    with _lock:
        cur = conn.execute(
            "UPDATE keys SET note = ? WHERE key = ?",
            (note or None, key.strip()),
        )
        conn.commit()
        return cur.rowcount > 0


# ---------------------------------------------------------------------------
# Date helpers
# ---------------------------------------------------------------------------
def fmt_date(ts: int | None) -> str:
    if not ts:
        return "Never"
    return datetime.fromtimestamp(ts, tz=timezone.utc).strftime(
        "%d/%m/%Y %H:%M UTC"
    )


# ---------------------------------------------------------------------------
# Key extension / backups
# ---------------------------------------------------------------------------
def extend_key(key: str, days: int) -> tuple[bool, int | None]:
    """
    Extends a key's validity.
      days > 0 -> adds days to the current expiration (or to now if the
                  key is already expired). A permanent key stays permanent.
      days = 0 -> makes the key permanent
    Returns (found, new_expires_at). A permanent key extended with
    days > 0 returns (True, None), so the caller can tell it was not changed.
    """
    conn = _db()
    key = key.strip()
    with _lock:
        row = conn.execute(
            "SELECT * FROM keys WHERE key = ?", (key,)
        ).fetchone()
        if row is None:
            return False, None
        if days <= 0:
            new_exp = None
        elif row["expires_at"] is None:
            return True, None
        else:
            new_exp = max(now(), row["expires_at"]) + days * 86400
        conn.execute(
            """UPDATE keys SET expires_at = ?, exp_reminded = 0
               WHERE key = ?""",
            (new_exp, key),
        )
        conn.commit()
        return True, new_exp


def backup(dest_dir: str) -> str:
    """Safely copies the database (SQLite backup API) to dest_dir."""
    os.makedirs(dest_dir, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    dest_path = os.path.join(dest_dir, f"keys-{stamp}.db")
    dest = sqlite3.connect(dest_path)
    try:
        _db().backup(dest)
    finally:
        dest.close()
    return dest_path


def sync_backup(backup_path: str, sync_dir: str, keep: int = 7) -> str:
    """
    Copies a finished backup to another folder (a synced OneDrive / Google
    Drive folder, another disk...) so one dead disk does not take the keys.
    """
    import shutil

    os.makedirs(sync_dir, exist_ok=True)
    target = os.path.join(sync_dir, os.path.basename(backup_path))
    shutil.copy2(backup_path, target)
    prune_backups(sync_dir, keep=keep)
    return target


def prune_backups(dest_dir: str, keep: int = 7) -> None:
    """Keeps only the newest `keep` backup files."""
    if not os.path.isdir(dest_dir):
        return
    files = sorted(
        os.path.join(dest_dir, name)
        for name in os.listdir(dest_dir)
        if name.startswith("keys-") and name.endswith(".db")
    )
    excess = files[:-keep] if keep > 0 else files
    for old in excess:
        try:
            os.remove(old)
        except OSError:
            pass


# ---------------------------------------------------------------------------
# Unlink (refund / transfer) + expiration reminders + broadcast list
# ---------------------------------------------------------------------------
def unlink_key(key: str) -> bool:
    """
    Unbinds a key from a user (refund or transfer to another buyer):
    clears the owner, the redemption date, the HWID and the reset
    counter so someone else can redeem it. Keeps executions/history.
    """
    conn = _db()
    with _lock:
        cur = conn.execute(
            """UPDATE keys
               SET discord_id = NULL, redeemed_at = NULL,
                   hwid = NULL, hwid_resets = 0, exp_reminded = 0
               WHERE key = ? AND discord_id IS NOT NULL""",
            (key.strip(),),
        )
        conn.commit()
        return cur.rowcount > 0


def due_expiration_reminders() -> list[sqlite3.Row]:
    """Redeemed keys expiring within 24h that were not reminded yet."""
    limit = now() + 86400
    return _db().execute(
        """SELECT * FROM keys
           WHERE discord_id IS NOT NULL
             AND expires_at IS NOT NULL
             AND expires_at > ?
             AND expires_at <= ?
             AND exp_reminded = 0""",
        (now(), limit),
    ).fetchall()


def mark_expiration_reminded(key: str) -> None:
    conn = _db()
    with _lock:
        conn.execute(
            "UPDATE keys SET exp_reminded = 1 WHERE key = ?",
            (key.strip(),),
        )
        conn.commit()


def list_buyer_ids() -> list[int]:
    """Distinct Discord IDs of every user with a redeemed key."""
    rows = _db().execute(
        "SELECT DISTINCT discord_id FROM keys "
        "WHERE discord_id IS NOT NULL"
    ).fetchall()
    return [row["discord_id"] for row in rows]


# ---------------------------------------------------------------------------
# Buy tickets (shop). Stored in the database so a restart does not lose them.
# ---------------------------------------------------------------------------
def create_ticket(
    channel_id: int, buyer_id: int, renew_key: str | None = None
) -> None:
    """renew_key set = a renewal: approval extends that key, no new key."""
    conn = _db()
    with _lock:
        conn.execute(
            """INSERT OR IGNORE INTO tickets
               (channel_id, buyer_id, renew_key, created_at)
               VALUES (?, ?, ?, ?)""",
            (channel_id, buyer_id, renew_key, now()),
        )
        conn.commit()


def set_ticket_payment(channel_id: int, pay_id: str, amount: float) -> None:
    """Remembers the automatic Pix charge created for this ticket."""
    conn = _db()
    with _lock:
        conn.execute(
            "UPDATE tickets SET pay_id = ?, pay_amount = ? WHERE channel_id = ?",
            (pay_id, amount, channel_id),
        )
        conn.commit()


def clear_ticket_payment(channel_id: int) -> None:
    conn = _db()
    with _lock:
        conn.execute(
            "UPDATE tickets SET pay_id = NULL, pay_amount = NULL WHERE channel_id = ?",
            (channel_id,),
        )
        conn.commit()


def pending_payments(max_age_seconds: int = 86400) -> list[sqlite3.Row]:
    """Tickets with an automatic charge that is not delivered yet."""
    return _db().execute(
        """SELECT * FROM tickets
           WHERE pay_id IS NOT NULL AND approved = 0 AND created_at >= ?""",
        (now() - max_age_seconds,),
    ).fetchall()


def get_ticket(channel_id: int) -> sqlite3.Row | None:
    return _db().execute(
        "SELECT * FROM tickets WHERE channel_id = ?", (channel_id,)
    ).fetchone()


def set_ticket_product(channel_id: int, product_id: str) -> None:
    conn = _db()
    with _lock:
        conn.execute(
            "UPDATE tickets SET product_id = ? WHERE channel_id = ?",
            (product_id, channel_id),
        )
        conn.commit()


def mark_ticket_paid(channel_id: int) -> bool:
    """True only the first time (so the staff is pinged once)."""
    conn = _db()
    with _lock:
        cur = conn.execute(
            "UPDATE tickets SET paid = 1 WHERE channel_id = ? AND paid = 0",
            (channel_id,),
        )
        conn.commit()
        return cur.rowcount > 0


def claim_ticket_approval(channel_id: int) -> bool:
    """
    Atomically marks the ticket as delivered. Returns False when another
    approval already claimed it, so two staff clicks cannot create two keys.
    """
    conn = _db()
    with _lock:
        cur = conn.execute(
            "UPDATE tickets SET approved = 1 WHERE channel_id = ? AND approved = 0",
            (channel_id,),
        )
        conn.commit()
        return cur.rowcount > 0


def release_ticket_approval(channel_id: int) -> None:
    """Undoes a claim when key generation failed."""
    conn = _db()
    with _lock:
        conn.execute(
            "UPDATE tickets SET approved = 0 WHERE channel_id = ?",
            (channel_id,),
        )
        conn.commit()


def delete_ticket(channel_id: int) -> None:
    conn = _db()
    with _lock:
        conn.execute("DELETE FROM tickets WHERE channel_id = ?", (channel_id,))
        conn.commit()
