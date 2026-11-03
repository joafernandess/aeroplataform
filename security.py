"""
Security helpers: password hashing, sessions, API tokens, rate limiting.

- Passwords: PBKDF2-HMAC-SHA256, 200k iterations, random salt (stdlib only).
- Sessions:  random 128-bit id stored server-side (revocable), HttpOnly cookie.
- API tokens: `aero_<32 chars>`, stored as sha256 hash, prefix kept for display.
- Rate limit: sliding window per IP (in-memory; single process is fine).
"""
import base64
import hashlib
import hmac
import os
import secrets
import time

import config

_PBKDF2_ITERATIONS = 200_000


# ---------------------------------------------------------------------------
# Passwords
# ---------------------------------------------------------------------------
def hash_password(password: str) -> str:
    salt = os.urandom(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode("utf-8"), salt, _PBKDF2_ITERATIONS)
    return (
        f"pbkdf2_sha256${_PBKDF2_ITERATIONS}$"
        f"{base64.b64encode(salt).decode()}$"
        f"{base64.b64encode(digest).decode()}"
    )


def verify_password(password: str, stored: str) -> bool:
    try:
        algo, iterations, salt_b64, digest_b64 = stored.split("$", 3)
        if algo != "pbkdf2_sha256":
            return False
        salt = base64.b64decode(salt_b64)
        expected = base64.b64decode(digest_b64)
        actual = hashlib.pbkdf2_hmac(
            "sha256", password.encode("utf-8"), salt, int(iterations)
        )
        return hmac.compare_digest(actual, expected)
    except (ValueError, TypeError):
        return False


# ---------------------------------------------------------------------------
# Sessions (dashboard)
# ---------------------------------------------------------------------------
def hash_session_id(session_id: str) -> str:
    key = config.secret()
    return hmac.new(key, session_id.encode("ascii"), hashlib.sha256).hexdigest()


def new_session_id() -> str:
    return secrets.token_urlsafe(32)


# ---------------------------------------------------------------------------
# API tokens
# ---------------------------------------------------------------------------
def new_api_token() -> str:
    return config.new_api_token()


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("ascii")).hexdigest()


def token_prefix(token: str) -> str:
    return token[:12]


# ---------------------------------------------------------------------------
# Sliding-window rate limiter
# ---------------------------------------------------------------------------
_hits: dict[str, list[float]] = {}


def clear_rate_limit() -> None:
    """Test helper."""
    _hits.clear()


def _gc_rate_limit() -> None:
    # Drop stale IPs when the map gets big (single-process server).
    if len(_hits) > 5000:
        cutoff = time.time() - max(config.RATE_LOADER_MIN, 60) * 2
        for ip in list(_hits):
            if not _hits[ip] or _hits[ip][-1] < cutoff:
                _hits.pop(ip, None)


def rate_limited(bucket: str, limit: int, window: float) -> bool:
    """True when this IP would exceed `limit` hits inside `window` seconds."""
    ip = bucket
    now_ts = time.time()
    _gc_rate_limit()
    hits = [t for t in _hits.get(ip, []) if now_ts - t < window]
    if len(hits) >= limit:
        _hits[ip] = hits + [now_ts]
        return True
    _hits[ip] = hits + [now_ts]
    return False
