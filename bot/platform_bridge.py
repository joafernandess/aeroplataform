"""
Aero Platform bridge — drop-in replacement for ``database.py``.

When ``PLATFORM_API_URL`` + ``PLATFORM_API_TOKEN`` are set in the bot's
``.env``, every key operation is delegated to the Aero Platform (the central
license server) over HTTP. When they are empty, this module re-exports the
legacy local SQLite implementation, so existing installs keep working.

What goes where
---------------
* Keys, users, bans, HWID, extensions, reminders  -> platform (HTTP).
* Buy tickets (shop)                              -> LOCAL (the platform has
  no tickets table; they are bot-specific workflow state).
* Database backups                               -> platform owns its own
  rotating backups; ``backup()`` returns None to signal "nothing to copy".

Deliberate mappings
-------------------
* The platform calls a revoked key "revoked"; the old bot called the same
  state "inactive". ``redeem()`` maps it back to keep the panel wording.
* Per-key game allowlists (``key_games``/``all_games``) no longer exist:
  the platform resolves the game through the key's product. ``key_game_ids``
  returns [] and ``set_key_games`` is a no-op.
* ``register_execution`` validates (state + strong-HWID rule) but does not
  increment counters: the platform is authoritative and increments
  executions itself when the loader really executes the script.

Row compatibility
-----------------
The cogs treat rows like ``sqlite3.Row`` (``row["field"]``). The platform
returns JSON dicts with different names, so every platform row is converted
into an old-schema ``Row`` (``revoked_at``, ``active``, ``all_games``... are
derived) — no cog code had to change.
"""
from __future__ import annotations

import json
import logging
import time
import urllib.error
import urllib.request

import config

log = logging.getLogger("keybot.bridge")

PLATFORM_URL = config.PLATFORM_API_URL
PLATFORM_TOKEN = config.PLATFORM_API_TOKEN
HTTP_MODE = bool(PLATFORM_URL and PLATFORM_TOKEN)

# Legacy implementation: fallback + tickets + backups.
import database as _local  # noqa: E402

MIN_HWID_LENGTH = _local.MIN_HWID_LENGTH


# ---------------------------------------------------------------------------
# HTTP client
# ---------------------------------------------------------------------------
class PlatformError(RuntimeError):
    """Raised when the platform is unreachable or answers with an error."""


def _call(method: str, path: str, body: dict | None = None,
          timeout: float = 15.0) -> dict:
    """Calls /api/v1<path> and returns the ``data`` payload.

    Raises PlatformError on transport failures; HTTP errors surface as
    PlatformError with the server's message so the cogs can show it.
    """
    url = f"{PLATFORM_URL}/api/v1{path}"
    data = None
    headers = {
        "Authorization": f"Bearer {PLATFORM_TOKEN}",
        "Accept": "application/json",
        "User-Agent": "aero-bot-bridge/1.0",
    }
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    last_exc: Exception | None = None
    for attempt in range(2):
        try:
            req = urllib.request.Request(url, data=data, headers=headers,
                                         method=method)
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                payload = json.loads(resp.read().decode("utf-8"))
            break
        except urllib.error.HTTPError as exc:
            try:
                payload = json.loads(exc.read().decode("utf-8"))
            except Exception:
                payload = {"ok": False, "error": f"HTTP {exc.code}"}
            if exc.code >= 500:
                last_exc = PlatformError(payload.get("error") or f"HTTP {exc.code}")
                time.sleep(0.4)
                continue
            raise PlatformError(payload.get("error") or f"HTTP {exc.code}")
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            last_exc = PlatformError(f"platform unreachable: {exc}")
            time.sleep(0.4)
            continue
    else:
        raise last_exc or PlatformError("platform unreachable")

    if not payload.get("ok"):
        raise PlatformError(payload.get("error") or "platform error")
    return payload.get("data")


# ---------------------------------------------------------------------------
# Public URL (loader entry point)
# ---------------------------------------------------------------------------
_PUBLIC_URL: dict = {"value": "", "ts": 0.0}


def public_url() -> str:
    """Base URL users reach: the platform's PUBLIC_API_URL when bridged.

    Cached for 5 minutes so a tunnel/domain change picked up by the platform
    also updates the loader link shown by the bot without a restart.
    """
    if not HTTP_MODE:
        return config.PUBLIC_API_URL or f"http://127.0.0.1:{config.API_PORT}"
    now_ts = time.time()
    if _PUBLIC_URL["value"] and now_ts - _PUBLIC_URL["ts"] < 300:
        return _PUBLIC_URL["value"]
    url = PLATFORM_URL
    try:
        req = urllib.request.Request(
            f"{PLATFORM_URL}/v1/health",
            headers={"User-Agent": "aero-bot-bridge/1.0"},
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        if isinstance(data, dict) and data.get("public_url"):
            url = str(data["public_url"])
    except Exception:
        # platform temporarily unreachable: keep the last known/fallback URL
        pass
    url = url.rstrip("/")
    _PUBLIC_URL.update(value=url, ts=now_ts)
    return url


# ---------------------------------------------------------------------------
# sqlite3.Row-compatible wrapper
# ---------------------------------------------------------------------------
class Row(dict):
    """dict that behaves like sqlite3.Row for ``row["field"]`` access."""

    def __getitem__(self, key):
        try:
            return dict.__getitem__(self, key)
        except KeyError:
            raise IndexError(key) from None

    def keys(self):  # sqlite3.Row API
        return dict.keys(self)


def _map_key(view: dict | None) -> Row | None:
    """Converts a platform key JSON into the legacy bot row shape."""
    if not view:
        return None
    revoked = bool(view.get("revoked"))
    expires_at = view.get("expires_at")
    return Row(
        key=view.get("key"),
        discord_id=view.get("discord_id"),
        user_id=view.get("user_id"),
        hwid=view.get("hwid"),
        execution=view.get("executions") or 0,
        executions=view.get("executions") or 0,
        hwid_resets=view.get("hwid_resets") or 0,
        first_exec=view.get("first_exec"),
        last_exec=view.get("last_exec"),
        last_access=view.get("last_exec"),
        last_loader_id=None,
        expires_at=expires_at,
        banned=1 if view.get("banned") else 0,
        ban_reason=view.get("ban_reason"),
        ban_until=view.get("ban_until"),
        note=view.get("note"),
        created_at=view.get("created_at"),
        redeemed_at=view.get("redeemed_at"),
        revoked_at=view.get("created_at") if revoked else None,
        active=0 if revoked else 1,
        all_games=1,
        exp_reminded=view.get("exp_reminded") or 0,
        product_id=view.get("product_id"),
        license_id=view.get("license_id"),
        script_id=view.get("script_id"),
        display_name=view.get("display_name"),
    )


def _all_keys(search: str | None = None, page: int = 500,
              max_pages: int = 40) -> list[dict]:
    """Pages through /keys (used by access_by_user/list_buyer_ids)."""
    rows: list[dict] = []
    offset = 0
    for _ in range(max_pages):
        query = f"?limit={page}&offset={offset}"
        if search:
            query += f"&search={search}"
        data = _call("GET", f"/keys{query}")
        batch = data.get("rows") or []
        rows.extend(batch)
        total = int(data.get("total") or 0)
        offset += len(batch)
        if not batch or offset >= total:
            break
    return rows


# ---------------------------------------------------------------------------
# Shared helpers (local logic, identical in both modes)
# ---------------------------------------------------------------------------
def now() -> int:
    return int(time.time())


def fmt_date(ts: int | None) -> str:
    return _local.fmt_date(ts)


def hwid_problem(hwid: str) -> str | None:
    return _local.hwid_problem(hwid)


def _is_expired(row) -> bool:
    return row["expires_at"] is not None and now() >= row["expires_at"]


def _active_ban(row) -> bool:
    if row["banned"] != 1:
        return False
    until = row["ban_until"]
    return until is None or now() < until


def status(row) -> str:
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


def _problem_reason(row) -> str | None:
    st = status(row)
    if st == "revoked":
        return "This key has been revoked."
    if st == "inactive":
        return "This key is disabled. Contact support."
    if st == "banned":
        return "This key has been banned."
    if st == "expired":
        return "This key has expired."
    return None


# ===========================================================================
# LOCAL MODE — transparent passthrough to database.py
# ===========================================================================
if not HTTP_MODE:
    from database import *  # noqa: F401,F403

    def using_platform() -> bool:
        return False

    def record_sale(buyer: str, discord_id: int | None = None, game: str | None = None,
                    product: str | None = None, amount_cents: int = 0,
                    status: str = "paid", note: str | None = None) -> None:
        # Local legacy mode has no sales ledger (no Aero Platform to log
        # into) — the dashboard's "Sales" tab only exists on the platform.
        return None

else:
    # =======================================================================
    # HTTP MODE
    # =======================================================================
    def using_platform() -> bool:
        return True

    # --------------------------------------------------------------- sales
    def record_sale(buyer: str, discord_id: int | None = None, game: str | None = None,
                    product: str | None = None, amount_cents: int = 0,
                    status: str = "paid", note: str | None = None) -> None:
        """
        Logs a completed ticket sale on the Aero Platform's "Sales" tab —
        automatic, so staff never re-type what the ticket already shows.
        Never raises: a sale is already fulfilled (key generated/delivered)
        by the time this runs, and losing a dashboard row must never look
        like a failed delivery to the buyer or the staff approving it.
        """
        try:
            _call("POST", "/sales", {
                "buyer": buyer, "discord_id": str(discord_id) if discord_id else None,
                "game": game, "product": product, "amount_cents": int(amount_cents),
                "status": status, "note": note,
            })
        except PlatformError as exc:
            log.warning("could not record sale on the platform: %s", exc)

    # ---------------------------------------------------------------- keys
    def generate_keys(count: int, days: int = 0, note: str = "",
                      game_ids: list[int] | None = None) -> list[str]:
        if game_ids:
            log.info(
                "generate_keys(game_ids=%s): the platform binds keys to the "
                "product/license instead of per-key games — ignored.", game_ids)
        rows = _call("POST", "/keys/generate", {
            "count": count, "days": days or 0, "note": note or "",
        })
        return [r["key"] for r in rows]

    def get_key(key: str) -> Row | None:
        try:
            return _map_key(_call("POST", "/keys/view", {"key": key}))
        except PlatformError as exc:
            if "not found" in str(exc).lower():
                return None
            raise

    def get_user_key(discord_id: int) -> Row | None:
        try:
            rows = _all_keys(search=str(discord_id), page=100, max_pages=5)
        except PlatformError:
            return None
        mine = [r for r in rows if r.get("discord_id") == discord_id]
        if not mine:
            return None
        mine.sort(key=lambda r: (r.get("redeemed_at") or 0,
                                 r.get("created_at") or 0), reverse=True)
        return _map_key(mine[0])

    def list_recent(limit: int = 15) -> list[Row]:
        data = _call("GET", f"/keys?limit={limit}&offset=0")
        return [_map_key(r) for r in data.get("rows") or []]

    def count_keys() -> tuple[int, int, int]:
        stats = _call("GET", "/stats/keys")
        return (int(stats.get("total") or 0),
                int(stats.get("redeemed") or 0),
                int(stats.get("banned") or 0))

    _REDEEM_CODES = {"revoked": "inactive"}  # platform name -> legacy name

    def redeem(key: str, discord_id: int) -> tuple[str, Row | None]:
        try:
            data = _call("POST", "/keys/redeem", {
                "key": key, "discord_id": str(discord_id),
            })
        except PlatformError as exc:
            if "not found" in str(exc).lower():
                return "not_found", None
            raise
        code = _REDEEM_CODES.get(data.get("code"), data.get("code"))
        return code, _map_key(data.get("key"))

    # -------------------------------------------------------------- checks
    def check_key(key: str, game_id: int | None = None):
        row = get_key(key)
        if row is None:
            return None, "Invalid or unknown key."
        problem = _problem_reason(row)
        # game permissions are derived from the product on the platform;
        # the loader validates the PlaceId at execution time.
        return row, problem

    def key_game_ids(key: str) -> list[int]:
        return []

    def set_key_games(key: str, all_games: bool, game_ids: list[int]) -> bool:
        log.info("set_key_games ignored: game access follows the product.")
        return get_key(key) is not None

    def set_key_active(key: str, active: bool) -> bool:
        action = "restore" if active else "revoke"
        try:
            _call("POST", f"/keys/{action}", {"key": key})
            return True
        except PlatformError:
            return False

    def revoke_key(key: str) -> bool:
        try:
            return bool(_call("POST", "/keys/revoke", {"key": key})["revoked"])
        except PlatformError:
            return False

    def set_key_expiration(key: str, expires_at: int | None) -> bool:
        try:
            _call("POST", "/keys/set-expiration",
                  {"key": key, "expires_at": expires_at})
            return True
        except PlatformError:
            return False

    def touch_key_access(key: str, loader_id: str | None) -> None:
        # recorded by the platform when the loader really executes
        return None

    # ---------------------------------------------------------------- HWID
    def reset_hwid(discord_id: int) -> bool:
        try:
            rows = _all_keys(search=str(discord_id), page=100, max_pages=5)
        except PlatformError:
            return False
        mine = [r for r in rows if r.get("discord_id") == discord_id]
        reset_any = False
        for r in mine:
            try:
                _call("POST", "/keys/reset-hwid", {"key": r["key"]})
                reset_any = True
            except PlatformError:
                continue
        return reset_any

    def reset_key_hwid(key: str, count: bool = False) -> bool:
        try:
            _call("POST", "/keys/reset-hwid", {"key": key})
            return True
        except PlatformError:
            return False

    def register_execution(key: str, hwid: str, game_id: int | None = None,
                           loader_id: str | None = None):
        """Validates without recording (the platform counts real executions)."""
        row, problem = check_key(key, game_id)
        if row is None:
            return False, "Invalid or unknown key."
        if problem:
            return False, problem
        weak = hwid_problem(hwid)
        if weak:
            return False, weak
        stored = (row["hwid"] or "").strip()
        if stored and hwid_problem(stored):
            stored = ""
        if stored and hwid.strip()[:128] != stored:
            return False, (
                "This HWID does not match the registered one. "
                "Reset your HWID from the Discord panel or restore this PC."
            )
        return True, None

    # ------------------------------------------------------------- banning
    def ban_user(discord_id: int, reason: str = "", days: int = 0) -> bool:
        try:
            return bool(_call("POST", "/users/ban", {
                "discord_id": str(discord_id), "reason": reason, "days": days,
            })["ban"])
        except PlatformError:
            return False

    def unban_user(discord_id: int) -> bool:
        try:
            return bool(_call("POST", "/users/unban", {
                "discord_id": str(discord_id),
            })["unban"])
        except PlatformError:
            return False

    def ban_key(key: str, reason: str = "", days: int = 0) -> bool:
        try:
            return bool(_call("POST", "/keys/ban", {
                "key": key, "reason": reason, "days": days,
            })["banned"])
        except PlatformError:
            return False

    def unban_key(key: str) -> bool:
        try:
            return bool(_call("POST", "/keys/unban", {"key": key})["unbanned"])
        except PlatformError:
            return False

    # ---------------------------------------------------------- role sync
    def access_by_user() -> dict[int, bool]:
        result: dict[int, bool] = {}
        try:
            rows = _all_keys()
        except PlatformError:
            log.exception("access_by_user failed")
            return result
        for r in rows:
            uid = r.get("discord_id")
            if uid is None:
                continue
            row = _map_key(r)
            result[uid] = result.get(uid, False) or status(row) == "ok"
        return result

    def set_note(key: str, note: str) -> bool:
        try:
            return bool(_call("POST", "/keys/set-note", {
                "key": key, "note": note or "",
            })["noted"])
        except PlatformError:
            return False

    def extend_key(key: str, days: int) -> tuple[bool, int | None]:
        try:
            data = _call("POST", "/keys/extend", {"key": key, "days": days})
            return True, data.get("expires_at")
        except PlatformError:
            return False, None

    def unlink_key(key: str) -> bool:
        try:
            return bool(_call("POST", "/keys/unbind", {"key": key})["unbound"])
        except PlatformError:
            return False

    # ---------------------------------------------------------- reminders
    def due_expiration_reminders() -> list[Row]:
        try:
            rows = _call("GET", "/keys/due-reminders")
        except PlatformError:
            log.exception("due_expiration_reminders failed")
            return []
        return [_map_key(r) for r in rows]

    def mark_expiration_reminded(key: str) -> None:
        try:
            _call("POST", "/keys/marked-reminded", {"key": key})
        except PlatformError:
            log.exception("mark_expiration_reminded failed")

    def list_buyer_ids() -> list[int]:
        try:
            rows = _all_keys()
        except PlatformError:
            return []
        return sorted({r["discord_id"] for r in rows
                       if r.get("discord_id") is not None})

    # ------------------------------------------------------------ backups
    def backup(dest_dir: str) -> str | None:
        """The platform runs its own rotating backup; nothing to copy here."""
        log.info("backup skipped: the Aero Platform owns its backups.")
        return None

    def sync_backup(backup_path: str, sync_dir: str, keep: int = 7) -> str:
        return ""

    def prune_backups(dest_dir: str, keep: int = 7) -> None:
        return None


# ===========================================================================
# EMBED TEMPLATES + LANGUAGES
# Stored on the platform (shared by every bot process and the dashboard).
# There are no local tables for these, so local mode explains how to enable
# them instead of silently losing the builder data.
# ===========================================================================
def _needs_platform(feature: str) -> PlatformError:
    return PlatformError(
        f"{feature} is stored on the Aero Platform. Set PLATFORM_API_URL and "
        "PLATFORM_API_TOKEN in the bot .env to enable it."
    )


if HTTP_MODE:
    def embed_list() -> list[dict]:
        return _call("GET", "/embeds") or []

    def embed_get(template_id: int) -> dict | None:
        try:
            return _call("GET", f"/embeds/{int(template_id)}")
        except PlatformError as exc:
            if "not found" in str(exc).lower():
                return None
            raise

    def embed_save(name: str, data: str, template_id: int | None = None,
                   created_by: str = "bot") -> dict:
        body = {"name": name, "data": data, "created_by": created_by}
        if template_id:
            body["id"] = int(template_id)
        return _call("POST", "/embeds", body)

    def embed_delete(template_id: int) -> bool:
        try:
            return bool(_call("DELETE", f"/embeds/{int(template_id)}")
                        .get("deleted"))
        except PlatformError as exc:
            if "not found" in str(exc).lower():
                return False
            raise

    def lang_get(discord_id: int) -> str:
        try:
            return _call("GET", f"/lang/{int(discord_id)}")["lang"]
        except PlatformError:
            return "en"

    def lang_set(discord_id: int, lang: str) -> str:
        return _call("PUT", f"/lang/{int(discord_id)}", {"lang": lang})["lang"]

else:
    def embed_list() -> list[dict]:
        raise _needs_platform("The embed builder")

    def embed_get(template_id: int) -> dict | None:
        raise _needs_platform("The embed builder")

    def embed_save(name: str, data: str, template_id: int | None = None,
                   created_by: str = "bot") -> dict:
        raise _needs_platform("The embed builder")

    def embed_delete(template_id: int) -> bool:
        raise _needs_platform("The embed builder")

    def lang_get(discord_id: int) -> str:
        # Local mode: remember the choice in memory so the session still
        # respects it (lost on restart, which is why the platform is the
        # recommended setup).
        return _LOCAL_LANGS.get(int(discord_id), "en")

    def lang_set(discord_id: int, lang: str) -> str:
        if lang not in ("en", "pt", "es"):
            raise PlatformError("lang must be en, pt or es")
        _LOCAL_LANGS[int(discord_id)] = lang
        return lang


_LOCAL_LANGS: dict[int, str] = {}


# ===========================================================================
# LOCAL-ONLY features — always handled by database.py
# (buy tickets are bot workflow state, not license data)
# ===========================================================================
create_ticket = _local.create_ticket
set_ticket_payment = _local.set_ticket_payment
clear_ticket_payment = _local.clear_ticket_payment
pending_payments = _local.pending_payments
get_ticket = _local.get_ticket
set_ticket_product = _local.set_ticket_product
mark_ticket_paid = _local.mark_ticket_paid
claim_ticket_approval = _local.claim_ticket_approval
release_ticket_approval = _local.release_ticket_approval
delete_ticket = _local.delete_ticket


def _db():
    """Direct SQL handle — only valid in local mode."""
    if HTTP_MODE:
        raise RuntimeError(
            "Direct SQL is unavailable when the Aero Platform bridge is "
            "active; use the public db.* functions instead."
        )
    return _local._db()


# ===========================================================================
# Execution log feed (platform only)
# ===========================================================================
def executions(after_id: int = 0, limit: int = 50, ip: str | None = None,
               discord_id: int | None = None, key: str | None = None,
               newest_first: bool = False) -> list[dict]:
    """
    Execution/auth events from the platform (telemetry, IP, HWID, result).
    Raises PlatformError in local mode or when the platform is unreachable.
    """
    if not HTTP_MODE:
        raise PlatformError("Execution logs need the Aero Platform bridge.")
    from urllib.parse import urlencode
    params: dict = {"after_id": int(after_id), "limit": int(limit)}
    if ip:
        params["ip"] = ip
    if discord_id:
        params["discord_id"] = int(discord_id)
    if key:
        params["key"] = key
    if newest_first:
        params["order"] = "desc"
    return _call("GET", f"/executions?{urlencode(params)}") or []
