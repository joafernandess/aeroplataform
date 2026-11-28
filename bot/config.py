"""
Bot configuration - loads variables from the .env file and defines defaults.
"""
import os

BASE_DIR = os.path.dirname(os.path.abspath(__file__))


def _load_dotenv(path: str) -> None:
    """Loads the .env file manually (no external dependencies)."""
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
            # Does not overwrite variables already defined in the environment
            if key and key not in os.environ:
                os.environ[key] = value


_load_dotenv(os.path.join(BASE_DIR, ".env"))


def _int(name: str, default: int = 0) -> int:
    raw = os.environ.get(name, "").strip()
    try:
        return int(raw) if raw else default
    except ValueError:
        return default


def _color(name: str, default: int) -> int:
    """Accepts decimal, 0x... or #RRGGBB."""
    raw = os.environ.get(name, "").strip()
    if not raw:
        return default
    try:
        if raw.startswith("#"):
            return int(raw[1:], 16)
        if raw.lower().startswith("0x"):
            return int(raw, 16)
        return int(raw)
    except ValueError:
        return default


# ---------------------------------------------------------------------------
# Required
# ---------------------------------------------------------------------------
# Bot token (Discord Developer Portal -> Bot -> Reset Token / Copy)
DISCORD_TOKEN = os.environ.get("DISCORD_TOKEN", "").strip()

# ---------------------------------------------------------------------------
# Server IDs
# ---------------------------------------------------------------------------
# Test server ID (recommended: slash commands appear immediately).
# Leave empty to sync globally (can take up to 1 hour).
GUILD_ID = _int("GUILD_ID", 0)

# The "@Buyer" role granted by the "Get Role" button
BUYER_ROLE_ID = _int("BUYER_ROLE_ID", 0)

# Role with access to EVERYTHING (owner): /ban /unban /postpanel /extend /postshop
ADMIN_ROLE_ID = _int("ADMIN_ROLE_ID", 0)

# Staff role (lower level): /genkey /keyinfo /userinfo /listkeys /setnote /deliver
STAFF_ROLE_ID = _int("STAFF_ROLE_ID", 0)

# Default channel for /postpanel (can also be given in the command)
PANEL_CHANNEL_ID = _int("PANEL_CHANNEL_ID", 0)

# Channel that receives event logs (redemptions, executions, bans...).
# 0 = logging disabled.
LOG_CHANNEL_ID = _int("LOG_CHANNEL_ID", 0)

# ---------------------------------------------------------------------------
# Panel
# ---------------------------------------------------------------------------
PANEL_TITLE = os.environ.get(
    "PANEL_TITLE", "Script Panel - Click below"
)
PANEL_DESCRIPTION = os.environ.get(
    "PANEL_DESCRIPTION",
    "Click the buttons below to redeem your key, get the script, "
    "claim your role, reset your HWID or view your key stats.",
)
PANEL_COLOR = _color("PANEL_COLOR", 0x5865F2)

# Maximum HWID resets per key (anti key-sharing)
MAX_HWID_RESETS = _int("MAX_HWID_RESETS", 3)

# ---------------------------------------------------------------------------
# API (script delivery + execution/HWID tracking)
# ---------------------------------------------------------------------------
# Local port of the HTTP server embedded in the bot
API_PORT = _int("API_PORT", 8720)

# Max requests per IP per minute on /v1/execute (anti brute-force)
API_RATE_LIMIT = _int("API_RATE_LIMIT", 30)

# Interface the API listens on. Loopback by default: the Cloudflare tunnel
# runs on this machine and connects locally, so the API should not be open
# to the network. Use 0.0.0.0 only if you really need direct access.
API_HOST = os.environ.get("API_HOST", "127.0.0.1").strip() or "127.0.0.1"

# Public URL that the script loader will reach.
# Local/test:  http://127.0.0.1:8720
# Production:  https://your-domain.com  (must be HTTPS and public)
PUBLIC_API_URL = os.environ.get(
    "PUBLIC_API_URL", f"http://127.0.0.1:{API_PORT}"
).rstrip("/")

# ---------------------------------------------------------------------------
# Aero Platform (central license server)
# ---------------------------------------------------------------------------
# When BOTH are set, every key operation goes to the platform over HTTP
# (platform_bridge.py) and the bot stops serving its own embedded API.
# Create a "service" token in the platform dashboard (Settings -> API tokens).
# Leave both empty to keep the legacy local-database behavior.
PLATFORM_API_URL = os.environ.get("PLATFORM_API_URL", "").strip().rstrip("/")
PLATFORM_API_TOKEN = os.environ.get("PLATFORM_API_TOKEN", "").strip()
PLATFORM_ENABLED = bool(PLATFORM_API_URL and PLATFORM_API_TOKEN)

# ---------------------------------------------------------------------------
# Script files
# ---------------------------------------------------------------------------
# Template delivered by the "Get Script" button ({script_key}/{api_url} are
# replaced automatically)
LOADER_TEMPLATE = os.environ.get(
    "LOADER_TEMPLATE", os.path.join(BASE_DIR, "scripts", "loader.lua")
)

# The real payload returned by the API when the loader runs
PAYLOAD_FILE = os.environ.get(
    "PAYLOAD_FILE", os.path.join(BASE_DIR, "scripts", "payload.lua")
)

# Sales panel settings (products, prices, Pix, PayPal)
SHOP_FILE = os.environ.get(
    "SHOP_FILE", os.path.join(BASE_DIR, "shop.json")
)

# Category where buy tickets are created (0 = auto-creates "Tickets")
TICKET_CATEGORY_ID = _int("TICKET_CATEGORY_ID", 0)

# ---------------------------------------------------------------------------
# Database
# ---------------------------------------------------------------------------
DATABASE_PATH = os.environ.get(
    "DATABASE_PATH", os.path.join(BASE_DIR, "data", "keys.db")
)

# Folder for automatic daily backups (last 7 are kept)
BACKUP_DIR = os.environ.get(
    "BACKUP_DIR", os.path.join(BASE_DIR, "backups")
)

# ---------------------------------------------------------------------------
# Loader system (games + loaders managed from the dashboard)
# ---------------------------------------------------------------------------
# Loader contents are stored as files: <LOADERS_DIR>/<loader_id>.lua
LOADERS_DIR = os.environ.get(
    "LOADERS_DIR", os.path.join(BASE_DIR, "scripts", "loaders")
)

# Days of request logs kept in the database (older rows are pruned daily)
ACCESS_LOG_DAYS = _int("ACCESS_LOG_DAYS", 30)

# ---------------------------------------------------------------------------
# Private server: admin dashboard + private bot API
# ---------------------------------------------------------------------------
# Loopback only. The Cloudflare tunnel maps API_PORT, never this port, so
# the dashboard is not reachable from the internet.
DASHBOARD_HOST = os.environ.get("DASHBOARD_HOST", "127.0.0.1").strip() or "127.0.0.1"
DASHBOARD_PORT = _int("DASHBOARD_PORT", 8721)

# Extra Host headers accepted by the dashboard (comma separated), e.g. a
# hostname protected by Cloudflare Access. Loopback names always work.
DASHBOARD_ALLOWED_HOSTS = [
    h.strip().lower()
    for h in os.environ.get("DASHBOARD_ALLOWED_HOSTS", "").split(",")
    if h.strip()
]

# Admin session lifetime in hours
DASHBOARD_SESSION_HOURS = _int("DASHBOARD_SESSION_HOURS", 12)

# Where the bot reaches the private API
INTERNAL_API_URL = os.environ.get(
    "INTERNAL_API_URL", f"http://127.0.0.1:{DASHBOARD_PORT}"
).rstrip("/")

# Max private API requests per minute per key (the bot is trusted, this only
# stops one user hammering the loader button)
BOT_API_RATE_LIMIT = _int("BOT_API_RATE_LIMIT", 20)


def _bot_api_token() -> str:
    """
    Token the bot uses on the private API. Taken from BOT_API_TOKEN, or
    generated once and kept next to the database (data/ is gitignored).
    """
    token = os.environ.get("BOT_API_TOKEN", "").strip()
    if token:
        return token
    import secrets

    path = os.path.join(os.path.dirname(DATABASE_PATH), "bot_api_token")
    try:
        with open(path, "r", encoding="utf-8") as fh:
            token = fh.read().strip()
    except OSError:
        token = ""
    if len(token) < 32:
        token = secrets.token_urlsafe(48)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(token)
    return token


BOT_API_TOKEN = _bot_api_token()

# ---------------------------------------------------------------------------
# Anti key-sharing, roles, backups, alerts
# ---------------------------------------------------------------------------
# A key that runs from this many different IPs within 24 h triggers an alert
# in the log channel (once per key per day). Dynamic IPs can change legitimately,
# so this alerts a human instead of banning.
SHARE_ALERT_IPS = _int("SHARE_ALERT_IPS", 3)

# How often (minutes) the @Buyer role is removed from users with no usable key
ROLE_SYNC_MINUTES = max(1, _int("ROLE_SYNC_MINUTES", 30))

# Second copy of every daily backup (a synced OneDrive/Drive folder, another
# disk...). Empty = disabled.
BACKUP_SYNC_DIR = os.environ.get("BACKUP_SYNC_DIR", "").strip()

# Discord webhook URL (Channel settings > Integrations > Webhooks). The
# watchdog posts here when the bot crashes or is restarted. Empty = disabled.
WATCHDOG_WEBHOOK_URL = os.environ.get("WATCHDOG_WEBHOOK_URL", "").strip()

# ---------------------------------------------------------------------------
# Automatic Pix (Mercado Pago). Empty token = feature off, manual flow only.
# ---------------------------------------------------------------------------
MERCADOPAGO_ACCESS_TOKEN = os.environ.get("MERCADOPAGO_ACCESS_TOKEN", "").strip()
MERCADOPAGO_API_URL = (
    os.environ.get("MERCADOPAGO_API_URL", "https://api.mercadopago.com").strip().rstrip("/")
)
# Mercado Pago requires a payer e-mail on every charge
MERCADOPAGO_PAYER_EMAIL = (
    os.environ.get("MERCADOPAGO_PAYER_EMAIL", "cliente@email.com").strip()
)
# Seconds between checks of pending Pix charges
PAYMENT_POLL_SECONDS = _int("PAYMENT_POLL_SECONDS", 15)


def validate() -> list[str]:
    """Returns a list of configuration errors (empty = all good)."""
    errors = []
    if not DISCORD_TOKEN:
        errors.append("DISCORD_TOKEN not set (create the .env file)")
    if not BUYER_ROLE_ID:
        errors.append("BUYER_ROLE_ID not set (the @Buyer role ID)")
    if not ADMIN_ROLE_ID:
        errors.append("ADMIN_ROLE_ID not set (the admin role ID)")
    return errors
