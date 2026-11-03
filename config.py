"""
AERO Platform - backend configuration.

Environment (or .env file at the platform root) with sane defaults.
Everything self-hosted: SQLite database, no external services.
"""
import os
import secrets
import string

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # platform root
BACKEND_DIR = os.path.join(BASE_DIR, "backend")
DATA_DIR = os.path.join(BASE_DIR, "data")


def _load_env(path: str) -> None:
    """Tiny .env loader (no external dependency). Existing env vars win."""
    if not os.path.exists(path):
        return
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            key = key.strip()
            value = value.strip().strip('"').strip("'")
            if key and key not in os.environ:
                os.environ[key] = value


_load_env(os.path.join(BASE_DIR, ".env"))


def _int(name: str, default: int) -> int:
    raw = os.environ.get(name, "").strip()
    try:
        return int(raw) if raw else default
    except ValueError:
        return default


# ---------------------------------------------------------------------------
# Server
# ---------------------------------------------------------------------------
# Bind address. Keep 127.0.0.1 by default -> the machine is not exposed to
# the LAN by accident. For a Cloudflare Tunnel, 127.0.0.1 is exactly right.
AERO_HOST = os.environ.get("AERO_HOST", "127.0.0.1").strip()
AERO_PORT = _int("AERO_PORT", 8720)

# Public URL that the Lua loader reaches (HTTPS in production).
# Local/test:  http://127.0.0.1:8720
PUBLIC_API_URL = os.environ.get(
    "PUBLIC_API_URL", f"http://127.0.0.1:{AERO_PORT}"
).rstrip("/")

# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------
AERO_DB = os.environ.get(
    "AERO_DB", os.path.join(DATA_DIR, "aero.db")
)
BACKUP_DIR = os.environ.get("AERO_BACKUP_DIR", os.path.join(DATA_DIR, "backups"))

# ---------------------------------------------------------------------------
# Bootstrap admin (dashboard login). Created on first run when the
# dashboard_users table is empty, then the password SHOULD be changed
# from the dashboard (settings) - the account is marked must_change.
# ---------------------------------------------------------------------------
AERO_ADMIN_EMAIL = os.environ.get("AERO_ADMIN_EMAIL", "admin@aero.local").strip().lower()
AERO_ADMIN_PASSWORD = os.environ.get("AERO_ADMIN_PASSWORD", "aero-admin")

# ---------------------------------------------------------------------------
# Security limits
# ---------------------------------------------------------------------------
SESSION_TTL_HOURS = _int("AERO_SESSION_TTL_HOURS", 24 * 7)  # 7 days
MAX_HWID_RESETS = _int("AERO_MAX_HWID_RESETS", 3)

# Sliding-window rate limits (requests per window, per IP)
RATE_LOADER_MIN = _int("AERO_RATE_LOADER_MIN", 30)       # /v1/loader/* per minute
RATE_LOGIN_MIN = _int("AERO_RATE_LOGIN_MIN", 10)         # dashboard login per 5 min
RATE_LOGIN_WINDOW = 300

# ---------------------------------------------------------------------------
# Misc
# ---------------------------------------------------------------------------
AERO_VERSION = "1.0.0"
LOADER_VERSION = "2.0"       # matches loader/aero_loader.lua self-identification
TRUST_PROXY = os.environ.get("AERO_TRUST_PROXY", "1") == "1"  # read X-Forwarded-For

# Generate/reject decisions are text used by the loader error() calls.
DEFAULT_BAN_MESSAGE = (
    "This key has been banned. Contact support."  # shown in the executor console
)


def secret() -> bytes:
    """
    Session signing secret. Generated once and stored in
    data/secret.key (never committed).
    """
    os.makedirs(DATA_DIR, exist_ok=True)
    path = os.path.join(DATA_DIR, "secret.key")
    if os.path.exists(path):
        with open(path, "rb") as fh:
            data = fh.read().strip()
            if data:
                return data
    data = secrets.token_hex(32).encode("ascii")
    with open(path, "wb") as fh:
        fh.write(data)
    return data


def new_api_token() -> str:
    """Format: aero_<32 random chars> (visible once at creation)."""
    alphabet = string.ascii_letters + string.digits
    body = "".join(secrets.choice(alphabet) for _ in range(32))
    return f"aero_{body}"


def validate() -> list[str]:
    """Startup problems the operator should know about."""
    problems: list[str] = []
    if not AERO_ADMIN_EMAIL or "@" not in AERO_ADMIN_EMAIL:
        problems.append("AERO_ADMIN_EMAIL looks invalid")
    if not AERO_ADMIN_PASSWORD or len(AERO_ADMIN_PASSWORD) < 8:
        problems.append(
            "AERO_ADMIN_PASSWORD is too weak (min 8 chars) - set it in .env"
        )
    if (os.environ.get("PUBLIC_API_URL", "") or "").startswith("http://127.0.0.1"):
        # Only a warning for loader reachability outside this machine.
        problems.append(
            "PUBLIC_API_URL is localhost: the loader only works on this PC "
            "(set a https:// domain behind a tunnel for other users)"
        )
    return problems
