"""
Private server: admin dashboard + private bot API.

Listens on DASHBOARD_HOST:DASHBOARD_PORT (127.0.0.1:8721 by default). The
Cloudflare tunnel only maps the public API port, so this server is not
reachable from the internet. On top of that:

  - Host header check (blocks DNS-rebinding from a malicious web page)
  - Admin login with scrypt passwords and login throttling
  - Session cookie: HttpOnly + SameSite=Strict, stored hashed
  - CSRF token required on every write request
  - Strict Content-Security-Policy (no inline scripts)

Routes:
  /                      dashboard single-page app (dashboard_static/)
  /admin/api/...         JSON API used by the dashboard (session required)
  /internal/v1/...       private bot API (bot token required, internal_api.py)

Run standalone (public API + dashboard, without Discord):  python dashboard.py
"""
import asyncio
import hmac
import os

from aiohttp import web

import admin_auth
import catalog
import config
import database as db
import internal_api
import shop_config
from catalog import CatalogError
from ratelimit import RateLimiter

STATIC_DIR = os.path.join(config.BASE_DIR, "dashboard_static")
COOKIE = "kb_session"
ADMIN_PREFIX = "/admin/api/"
KEY_PATTERN = "{key:[A-Za-z0-9]{8,64}}"
LOADER_PATTERN = "{loader_id:[A-Za-z0-9_-]{16,64}}"
MAX_INLINE_CONTENT = 1024 * 1024  # bigger loaders are uploaded/downloaded as files

_login_ip_limiter = RateLimiter(10, window=900)
_login_user_limiter = RateLimiter(10, window=900)

_LOOPBACK_NAMES = {"127.0.0.1", "localhost", "[::1]", "::1"}
_SAFE_METHODS = {"GET", "HEAD", "OPTIONS"}

_CSP = (
    "default-src 'self'; script-src 'self'; style-src 'self'; "
    "img-src 'self' data:; connect-src 'self'; font-src 'self'; "
    "object-src 'none'; frame-ancestors 'none'; base-uri 'none'; "
    "form-action 'self'"
)


# ---------------------------------------------------------------------------
# Middlewares
# ---------------------------------------------------------------------------
def _host_name(host: str) -> str:
    host = (host or "").strip().lower()
    if host.startswith("["):
        return host.split("]", 1)[0] + "]"
    return host.rsplit(":", 1)[0] if ":" in host else host


@web.middleware
async def host_middleware(request: web.Request, handler):
    name = _host_name(request.host)
    if name not in _LOOPBACK_NAMES and name not in config.DASHBOARD_ALLOWED_HOSTS:
        return web.Response(status=421, text="Misdirected request")
    return await handler(request)


@web.middleware
async def security_headers_middleware(request: web.Request, handler):
    try:
        response = await handler(request)
    except web.HTTPException as exc:
        response = exc
    response.headers["Content-Security-Policy"] = _CSP
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "no-referrer"
    if request.path.startswith(ADMIN_PREFIX) or request.path.startswith("/internal/"):
        response.headers["Cache-Control"] = "no-store"
    if isinstance(response, web.HTTPException):
        raise response
    return response


def _same_origin(request: web.Request) -> bool:
    origin = request.headers.get("Origin")
    if not origin:
        return True  # same-origin fetches from older browsers / non-browsers
    expected = f"{request.scheme}://{request.host}".lower()
    return origin.lower() == expected


@web.middleware
async def admin_middleware(request: web.Request, handler):
    if not request.path.startswith(ADMIN_PREFIX):
        return await handler(request)

    if request.method not in _SAFE_METHODS:
        if not _same_origin(request):
            return _error("Cross-origin request blocked.", 403)

    if request.path == ADMIN_PREFIX + "login":
        return await handler(request)

    session = await asyncio.to_thread(
        admin_auth.get_session, request.cookies.get(COOKIE)
    )
    if session is None:
        return _error("Not logged in.", 401)
    if request.method not in _SAFE_METHODS:
        given = request.headers.get("X-CSRF-Token", "")
        if not hmac.compare_digest(given.encode(), session["csrf"].encode()):
            return _error("Invalid CSRF token. Reload the page.", 403)
    request["admin"] = session
    return await handler(request)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def _error(message: str, status: int = 400) -> web.Response:
    return web.json_response({"ok": False, "error": message}, status=status)


async def _json(request: web.Request) -> dict:
    if request.content_type != "application/json":
        raise web.HTTPUnsupportedMediaType(
            text='{"ok": false, "error": "Expected JSON."}',
            content_type="application/json",
        )
    try:
        data = await request.json()
    except ValueError:
        raise web.HTTPBadRequest(
            text='{"ok": false, "error": "Invalid JSON."}',
            content_type="application/json",
        )
    if not isinstance(data, dict):
        raise web.HTTPBadRequest(
            text='{"ok": false, "error": "Expected a JSON object."}',
            content_type="application/json",
        )
    return data


def _actor(request: web.Request) -> str:
    return request["admin"]["username"]


def _activity(request: web.Request, action: str, detail: str) -> None:
    catalog.log_activity(_actor(request), action, detail)


def _int_or_none(value) -> int | None:
    if value is None or value == "":
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        raise CatalogError(f"Expected a number, got {value!r}.")


def _client_ip(request: web.Request) -> str:
    return (request.remote or "unknown")[:64]


def _bot_status() -> dict:
    found = catalog.get_kv("bot_status")
    if found is None:
        return {"online": False, "last_seen": None, "info": None}
    info, updated = found
    return {
        "online": db.now() - updated < 150,  # heartbeat every 60 s
        "last_seen": updated,
        "info": info,
    }


def _access_dict(row, games_by_id: dict) -> dict:
    game = games_by_id.get(row["game_id"]) if row["game_id"] else None
    return {
        "id": row["id"],
        "ts": row["ts"],
        "source": row["source"],
        "key": row["key"],
        "game": game["name"] if game else None,
        "loader_id": row["loader_id"],
        "ip": row["ip"],
        "ok": bool(row["ok"]),
        "reason": row["reason"],
    }


def _activity_dict(row) -> dict:
    return {
        "id": row["id"], "ts": row["ts"], "actor": row["actor"],
        "action": row["action"], "detail": row["detail"],
    }


# ---------------------------------------------------------------------------
# Pages
# ---------------------------------------------------------------------------
async def index(request: web.Request) -> web.FileResponse:
    return web.FileResponse(os.path.join(STATIC_DIR, "index.html"))


# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------
async def login(request: web.Request) -> web.Response:
    data = await _json(request)
    username = str(data.get("username") or "").strip()[:32]
    password = str(data.get("password") or "")[:256]
    ip = _client_ip(request)

    if _login_ip_limiter.hit(ip) or _login_user_limiter.hit(username.lower()):
        return _error("Too many attempts. Wait 15 minutes and try again.", 429)

    admin = await asyncio.to_thread(admin_auth.authenticate, username, password)
    if admin is None:
        await asyncio.to_thread(
            catalog.log_activity, username or "?", "login_failed", f"IP {ip}"
        )
        return _error("Invalid username or password.", 401)

    if admin["totp_secret"]:
        # Password is right; the second factor is still needed
        code = str(data.get("code") or "")
        if not code.strip():
            return web.json_response(
                {"ok": False, "need_code": True,
                 "error": "Enter the 6-digit code from your authenticator app."},
                status=401,
            )
        valid = await asyncio.to_thread(
            admin_auth.verify_totp, admin["id"], admin["totp_secret"], code
        )
        if not valid:
            await asyncio.to_thread(
                catalog.log_activity, admin["username"], "login_failed",
                f"IP {ip} (bad 2FA code)",
            )
            return web.json_response(
                {"ok": False, "need_code": True, "error": "Invalid or already used code."},
                status=401,
            )

    _login_user_limiter.reset(username.lower())
    token, csrf = await asyncio.to_thread(admin_auth.create_session, admin["id"], ip)
    await asyncio.to_thread(catalog.log_activity, admin["username"], "login", f"IP {ip}")
    response = web.json_response({"ok": True, "username": admin["username"], "csrf": csrf})
    response.set_cookie(
        COOKIE, token,
        max_age=config.DASHBOARD_SESSION_HOURS * 3600,
        httponly=True, samesite="Strict", secure=request.secure, path="/",
    )
    return response


async def logout(request: web.Request) -> web.Response:
    await asyncio.to_thread(admin_auth.delete_session, request.cookies.get(COOKIE))
    response = web.json_response({"ok": True})
    response.del_cookie(COOKIE, path="/")
    return response


async def me(request: web.Request) -> web.Response:
    session = request["admin"]
    return web.json_response({
        "ok": True, "username": session["username"], "csrf": session["csrf"],
    })


# ---------------------------------------------------------------------------
# Overview + activity
# ---------------------------------------------------------------------------
def _overview_sync() -> dict:
    data = catalog.overview()
    games_by_id = {g["id"]: g for g in catalog.list_games()}
    data["bot"] = _bot_status()
    data["recent_access"] = [
        _access_dict(r, games_by_id) for r in catalog.recent_access(10)
    ]
    data["recent_activity"] = [_activity_dict(r) for r in catalog.recent_activity(10)]
    data["share_threshold"] = config.SHARE_ALERT_IPS
    data["suspects"] = (
        catalog.share_suspects(config.SHARE_ALERT_IPS, limit=8)
        if config.SHARE_ALERT_IPS > 0 else []
    )
    return data


async def overview(request: web.Request) -> web.Response:
    data = await asyncio.to_thread(_overview_sync)
    return web.json_response({"ok": True, **data})


def _activity_sync(limit: int) -> dict:
    games_by_id = {g["id"]: g for g in catalog.list_games()}
    return {
        "activity": [_activity_dict(r) for r in catalog.recent_activity(limit)],
        "access": [_access_dict(r, games_by_id) for r in catalog.recent_access(limit)],
    }


async def activity(request: web.Request) -> web.Response:
    try:
        limit = max(1, min(int(request.query.get("limit", "100")), 500))
    except ValueError:
        limit = 100
    data = await asyncio.to_thread(_activity_sync, limit)
    return web.json_response({"ok": True, **data})


# ---------------------------------------------------------------------------
# Games
# ---------------------------------------------------------------------------
def _games_sync() -> list[dict]:
    loaders = catalog.list_loaders()
    result = []
    for g in catalog.list_games():
        item = catalog.game_dict(g)
        own = [l for l in loaders if l["game_id"] == g["id"]]
        active = catalog.active_loader(g["id"])
        item["loader_count"] = len(own)
        item["active_loader_id"] = active["id"] if active else None
        item["restricted_keys"] = db._db().execute(
            "SELECT COUNT(*) AS n FROM key_games WHERE game_id = ?", (g["id"],)
        ).fetchone()["n"]
        result.append(item)
    return result


async def games_list(request: web.Request) -> web.Response:
    return web.json_response({"ok": True, "games": await asyncio.to_thread(_games_sync)})


async def games_create(request: web.Request) -> web.Response:
    data = await _json(request)
    try:
        row = await asyncio.to_thread(
            catalog.create_game,
            data.get("slug"), data.get("name"), data.get("place_ids"),
            bool(data.get("enabled", True)), bool(data.get("is_default", False)),
        )
    except CatalogError as exc:
        return _error(str(exc))
    await asyncio.to_thread(_activity, request, "game_create", f"{row['name']} ({row['slug']})")
    return web.json_response({"ok": True, "game": catalog.game_dict(row)}, status=201)


async def games_update(request: web.Request) -> web.Response:
    game_id = int(request.match_info["game_id"])
    data = await _json(request)
    allowed = {k: data[k] for k in ("slug", "name", "place_ids", "enabled", "is_default") if k in data}
    try:
        row = await asyncio.to_thread(lambda: catalog.update_game(game_id, **allowed))
    except CatalogError as exc:
        return _error(str(exc), 404 if "not found" in str(exc) else 400)
    await asyncio.to_thread(
        _activity, request, "game_update", f"{row['name']} ({row['slug']}): {', '.join(allowed)}"
    )
    return web.json_response({"ok": True, "game": catalog.game_dict(row)})


async def games_delete(request: web.Request) -> web.Response:
    game_id = int(request.match_info["game_id"])
    row = await asyncio.to_thread(catalog.get_game, game_id)
    if row is None:
        return _error("Game not found.", 404)
    await asyncio.to_thread(catalog.delete_game, game_id)
    await asyncio.to_thread(_activity, request, "game_delete", f"{row['name']} ({row['slug']})")
    return web.json_response({"ok": True})


# ---------------------------------------------------------------------------
# Loaders
# ---------------------------------------------------------------------------
def _loaders_sync() -> list[dict]:
    games_by_id = {g["id"]: g for g in catalog.list_games()}
    active_ids = {
        (catalog.active_loader(gid) or {"id": None})["id"] for gid in games_by_id
    }
    result = []
    for row in catalog.list_loaders():
        item = catalog.loader_dict(row)
        game = games_by_id.get(row["game_id"])
        item["game_name"] = game["name"] if game else None
        item["serving"] = row["id"] in active_ids
        result.append(item)
    return result


async def loaders_list(request: web.Request) -> web.Response:
    return web.json_response({"ok": True, "loaders": await asyncio.to_thread(_loaders_sync)})


async def loaders_create(request: web.Request) -> web.Response:
    data = await _json(request)
    try:
        game_id = _int_or_none(data.get("game_id"))
        row = await asyncio.to_thread(
            catalog.create_loader,
            data.get("name"), str(data.get("content") or ""), game_id,
            bool(data.get("enabled", True)),
        )
    except CatalogError as exc:
        return _error(str(exc))
    await asyncio.to_thread(
        _activity, request, "loader_create", f"{row['name']} ({row['id']})"
    )
    return web.json_response({"ok": True, "loader": catalog.loader_dict(row)}, status=201)


def _loader_detail_sync(loader_id: str) -> dict | None:
    row = catalog.get_loader(loader_id)
    if row is None:
        return None
    item = catalog.loader_dict(row)
    if row["size"] <= MAX_INLINE_CONTENT:
        try:
            item["content"] = catalog.read_content(loader_id)
        except OSError:
            item["content"] = None
            item["missing"] = True
    else:
        item["content"] = None
        item["too_large"] = True
    return item


async def loaders_get(request: web.Request) -> web.Response:
    item = await asyncio.to_thread(_loader_detail_sync, request.match_info["loader_id"])
    if item is None:
        return _error("Loader not found.", 404)
    return web.json_response({"ok": True, "loader": item})


async def loaders_update(request: web.Request) -> web.Response:
    loader_id = request.match_info["loader_id"]
    data = await _json(request)
    fields: dict = {}
    try:
        if "name" in data:
            fields["name"] = data["name"]
        if "enabled" in data:
            fields["enabled"] = bool(data["enabled"])
        if "game_id" in data:
            fields["game_id"] = _int_or_none(data["game_id"])
        if "content" in data and data["content"] is not None:
            fields["content"] = str(data["content"])
        row = await asyncio.to_thread(lambda: catalog.update_loader(loader_id, **fields))
    except CatalogError as exc:
        return _error(str(exc), 404 if "not found" in str(exc) else 400)
    changed = ", ".join("content" if k == "content" else k for k in fields) or "nothing"
    await asyncio.to_thread(
        _activity, request, "loader_update", f"{row['name']} ({loader_id}): {changed}"
    )
    return web.json_response({"ok": True, "loader": catalog.loader_dict(row)})


async def loaders_upload(request: web.Request) -> web.Response:
    """Replaces the content with the raw request body (for large files)."""
    loader_id = request.match_info["loader_id"]
    raw = await request.read()
    try:
        content = raw.decode("utf-8")
    except UnicodeDecodeError:
        return _error("The file must be UTF-8 text.")
    try:
        row = await asyncio.to_thread(
            lambda: catalog.update_loader(loader_id, content=content)
        )
    except CatalogError as exc:
        return _error(str(exc), 404 if "not found" in str(exc) else 400)
    await asyncio.to_thread(
        _activity, request, "loader_upload",
        f"{row['name']} ({loader_id}): {row['size']} bytes, v{row['version']}",
    )
    return web.json_response({"ok": True, "loader": catalog.loader_dict(row)})


async def loaders_download(request: web.Request) -> web.StreamResponse:
    loader_id = request.match_info["loader_id"]
    row = await asyncio.to_thread(catalog.get_loader, loader_id)
    if row is None:
        return _error("Loader not found.", 404)
    try:
        content = await asyncio.to_thread(catalog.read_content, loader_id)
    except OSError:
        return _error("Loader file is missing on disk.", 404)
    return web.Response(
        text=content,
        content_type="text/plain",
        headers={"Content-Disposition": f'attachment; filename="{loader_id}.lua"'},
    )


async def loaders_delete(request: web.Request) -> web.Response:
    loader_id = request.match_info["loader_id"]
    row = await asyncio.to_thread(catalog.get_loader, loader_id)
    if row is None:
        return _error("Loader not found.", 404)
    await asyncio.to_thread(catalog.delete_loader, loader_id)
    await asyncio.to_thread(
        _activity, request, "loader_delete", f"{row['name']} ({loader_id})"
    )
    return web.json_response({"ok": True})


# ---------------------------------------------------------------------------
# Keys
# ---------------------------------------------------------------------------
_KEY_STATUSES = {"", "ok", "revoked", "inactive", "banned", "expired"}


async def keys_list(request: web.Request) -> web.Response:
    q = request.query.get("q", "")[:100]
    status = request.query.get("status", "")
    if status not in _KEY_STATUSES:
        return _error("Unknown status filter.")
    try:
        game_id = _int_or_none(request.query.get("game"))
        page = max(1, int(request.query.get("page", "1")))
    except (CatalogError, ValueError):
        return _error("Invalid filter.")
    per_page = 50
    items, total = await asyncio.to_thread(
        catalog.list_keys, q, status, game_id, per_page, (page - 1) * per_page
    )
    return web.json_response({
        "ok": True, "items": items, "total": total, "page": page, "per_page": per_page,
    })


def _validate_game_ids(raw) -> list[int]:
    if not isinstance(raw, list):
        raise CatalogError("game_ids must be a list.")
    ids = []
    for value in raw:
        gid = _int_or_none(value)
        if gid is None or catalog.get_game(gid) is None:
            raise CatalogError(f"Unknown game id {value!r}.")
        ids.append(gid)
    return ids


async def keys_create(request: web.Request) -> web.Response:
    data = await _json(request)
    try:
        count = int(data.get("count") or 1)
        days = int(data.get("days") or 0)
    except (TypeError, ValueError):
        return _error("count and days must be numbers.")
    if not 1 <= count <= 100:
        return _error("count must be between 1 and 100.")
    if not 0 <= days <= 3650:
        return _error("days must be between 0 and 3650.")
    note = str(data.get("note") or "")[:200]
    try:
        game_ids = None
        if not data.get("all_games", True):
            game_ids = await asyncio.to_thread(_validate_game_ids, data.get("game_ids") or [])
            if not game_ids:
                return _error("Pick at least one game, or allow all games.")
    except CatalogError as exc:
        return _error(str(exc))
    keys = await asyncio.to_thread(db.generate_keys, count, days, note, game_ids)
    scope = "all games" if game_ids is None else f"games {game_ids}"
    await asyncio.to_thread(
        _activity, request, "keys_generate",
        f"{count} key(s), {days or 'permanent'} day(s), {scope}, note: {note or '-'}",
    )
    return web.json_response({"ok": True, "keys": keys}, status=201)


def _key_detail_sync(key: str) -> dict | None:
    row = db.get_key(key)
    if row is None:
        return None
    games_by_id = {g["id"]: g for g in catalog.list_games()}
    item = catalog.key_dict(row, games_by_id)
    item["hwid"] = row["hwid"]
    item["ban_until"] = row["ban_until"]
    item["ips_24h"] = catalog.distinct_ips(key)
    item["share_threshold"] = config.SHARE_ALERT_IPS
    item["access"] = [
        _access_dict(r, games_by_id) for r in catalog.recent_access(50, key=key)
    ]
    return item


async def keys_get(request: web.Request) -> web.Response:
    item = await asyncio.to_thread(_key_detail_sync, request.match_info["key"])
    if item is None:
        return _error("Key not found.", 404)
    return web.json_response({"ok": True, "key": item})


def _key_update_sync(key: str, data: dict) -> list[str]:
    if db.get_key(key) is None:
        raise LookupError
    changed = []
    if "active" in data:
        if not db.set_key_active(key, bool(data["active"])):
            raise CatalogError("A revoked key cannot be re-enabled.")
        changed.append("enabled" if data["active"] else "disabled")
    if "expires_at" in data:
        expires = _int_or_none(data["expires_at"])
        if expires is not None and expires <= db.now():
            raise CatalogError("The expiration must be in the future.")
        db.set_key_expiration(key, expires)
        changed.append(f"expires {db.fmt_date(expires) if expires else 'never'}")
    if "note" in data:
        db.set_note(key, str(data["note"] or "")[:200])
        changed.append("note")
    if "all_games" in data or "game_ids" in data:
        all_games = bool(data.get("all_games", False))
        ids = [] if all_games else _validate_game_ids(data.get("game_ids") or [])
        if not all_games and not ids:
            raise CatalogError("Pick at least one game, or allow all games.")
        db.set_key_games(key, all_games, ids)
        changed.append("games: all" if all_games else f"games {ids}")
    return changed


async def keys_update(request: web.Request) -> web.Response:
    key = request.match_info["key"]
    data = await _json(request)
    try:
        changed = await asyncio.to_thread(_key_update_sync, key, data)
    except LookupError:
        return _error("Key not found.", 404)
    except CatalogError as exc:
        return _error(str(exc))
    await asyncio.to_thread(
        _activity, request, "key_update", f"{key[:8]}…: {', '.join(changed) or 'nothing'}"
    )
    item = await asyncio.to_thread(_key_detail_sync, key)
    return web.json_response({"ok": True, "key": item})


async def keys_revoke(request: web.Request) -> web.Response:
    key = request.match_info["key"]
    row = await asyncio.to_thread(db.get_key, key)
    if row is None:
        return _error("Key not found.", 404)
    if not await asyncio.to_thread(db.revoke_key, key):
        return _error("Key is already revoked.")
    await asyncio.to_thread(_activity, request, "key_revoke", f"{key[:8]}…")
    item = await asyncio.to_thread(_key_detail_sync, key)
    return web.json_response({"ok": True, "key": item})


async def keys_ban(request: web.Request) -> web.Response:
    key = request.match_info["key"]
    data = await _json(request)
    try:
        days = int(data.get("days") or 0)
    except (TypeError, ValueError):
        return _error("days must be a number.")
    if not 0 <= days <= 3650:
        return _error("days must be between 0 and 3650.")
    reason = str(data.get("reason") or "")[:200]
    if not await asyncio.to_thread(db.ban_key, key, reason, days):
        return _error("Key not found.", 404)
    await asyncio.to_thread(
        _activity, request, "key_ban",
        f"{key[:8]}…: {reason or 'no reason'}, {days or 'permanent'} day(s)",
    )
    item = await asyncio.to_thread(_key_detail_sync, key)
    return web.json_response({"ok": True, "key": item})


async def keys_unban(request: web.Request) -> web.Response:
    key = request.match_info["key"]
    if not await asyncio.to_thread(db.unban_key, key):
        return _error("Key not found.", 404)
    await asyncio.to_thread(_activity, request, "key_unban", f"{key[:8]}…")
    item = await asyncio.to_thread(_key_detail_sync, key)
    return web.json_response({"ok": True, "key": item})


async def keys_reset_hwid(request: web.Request) -> web.Response:
    key = request.match_info["key"]
    if not await asyncio.to_thread(db.reset_key_hwid, key):
        return _error("Key not found.", 404)
    await asyncio.to_thread(_activity, request, "hwid_reset", f"{key[:8]}…")
    item = await asyncio.to_thread(_key_detail_sync, key)
    return web.json_response({"ok": True, "key": item})


# ---------------------------------------------------------------------------
# Shop settings (shop.json)
# ---------------------------------------------------------------------------
async def shop_get(request: web.Request) -> web.Response:
    shop = await asyncio.to_thread(shop_config.load)
    return web.json_response({
        "ok": True,
        "shop": shop,
        "auto_pix": bool(config.MERCADOPAGO_ACCESS_TOKEN),
    })


async def shop_save(request: web.Request) -> web.Response:
    data = await _json(request)
    try:
        saved = await asyncio.to_thread(shop_config.save, data)
    except shop_config.ShopConfigError as exc:
        return _error(str(exc))
    names = ", ".join(p["name"] for p in saved["products"])
    await asyncio.to_thread(_activity, request, "shop_update", f"products: {names}")
    return web.json_response({"ok": True, "shop": saved})


# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------
def create_private_app() -> web.Application:
    catalog.bootstrap()
    app = web.Application(
        middlewares=[
            security_headers_middleware,
            host_middleware,
            internal_api.bot_auth_middleware,
            admin_middleware,
        ],
        client_max_size=catalog.MAX_LOADER_BYTES + 1024 * 1024,
    )
    app.router.add_get("/", index)
    app.router.add_static("/static/", STATIC_DIR, show_index=False, follow_symlinks=False)

    p = ADMIN_PREFIX
    app.router.add_post(p + "login", login)
    app.router.add_post(p + "logout", logout)
    app.router.add_get(p + "me", me)
    app.router.add_get(p + "overview", overview)
    app.router.add_get(p + "activity", activity)

    app.router.add_get(p + "games", games_list)
    app.router.add_post(p + "games", games_create)
    app.router.add_patch(p + "games/{game_id:\\d+}", games_update)
    app.router.add_delete(p + "games/{game_id:\\d+}", games_delete)

    app.router.add_get(p + "loaders", loaders_list)
    app.router.add_post(p + "loaders", loaders_create)
    app.router.add_get(p + f"loaders/{LOADER_PATTERN}", loaders_get)
    app.router.add_patch(p + f"loaders/{LOADER_PATTERN}", loaders_update)
    app.router.add_put(p + f"loaders/{LOADER_PATTERN}/content", loaders_upload)
    app.router.add_get(p + f"loaders/{LOADER_PATTERN}/download", loaders_download)
    app.router.add_delete(p + f"loaders/{LOADER_PATTERN}", loaders_delete)

    app.router.add_get(p + "keys", keys_list)
    app.router.add_post(p + "keys", keys_create)
    app.router.add_get(p + f"keys/{KEY_PATTERN}", keys_get)
    app.router.add_patch(p + f"keys/{KEY_PATTERN}", keys_update)
    app.router.add_post(p + f"keys/{KEY_PATTERN}/revoke", keys_revoke)
    app.router.add_post(p + f"keys/{KEY_PATTERN}/ban", keys_ban)
    app.router.add_post(p + f"keys/{KEY_PATTERN}/unban", keys_unban)
    app.router.add_post(p + f"keys/{KEY_PATTERN}/reset-hwid", keys_reset_hwid)

    app.router.add_get(p + "shop", shop_get)
    app.router.add_put(p + "shop", shop_save)

    internal_api.add_routes(app)
    return app


async def start_dashboard(runner_holder: dict) -> None:
    """Starts the private server (dashboard + bot API) on loopback."""
    runner = web.AppRunner(create_private_app(), access_log=None)
    await runner.setup()
    site = web.TCPSite(runner, config.DASHBOARD_HOST, config.DASHBOARD_PORT)
    await site.start()
    runner_holder["runner"] = runner


async def _standalone() -> None:
    from api import start_api

    public: dict = {}
    private: dict = {}
    await start_api(public)
    await start_dashboard(private)
    print(f"Public API: http://{config.API_HOST}:{config.API_PORT}/v1/ping")
    print(f"Dashboard:  http://{config.DASHBOARD_HOST}:{config.DASHBOARD_PORT}/")
    if admin_auth.admin_count() == 0:
        print("No admin yet: run  python manage.py create-admin <username>")
    try:
        await asyncio.Event().wait()
    finally:
        await public["runner"].cleanup()
        await private["runner"].cleanup()


if __name__ == "__main__":
    try:
        asyncio.run(_standalone())
    except KeyboardInterrupt:
        pass
