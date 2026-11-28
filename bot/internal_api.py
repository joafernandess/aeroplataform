"""
Private API used by the bot (never by browsers, never public).

Served on the loopback-only dashboard server, under /internal/v1/.
Every request needs:  Authorization: Bearer <BOT_API_TOKEN>

  GET  /internal/v1/health      -> {"ok": true}
  POST /internal/v1/games       {"key"}                      -> games the key can use
  POST /internal/v1/loader      {"key", "game", "discord_id"} -> loader script for that game
  POST /internal/v1/heartbeat   {"user", "guilds", ...}      -> bot status for the dashboard

Loader flow: validate key -> identify game -> check the key may use it ->
check the key belongs to the Discord user asking -> render the loader.
"""
import asyncio
import hmac

from aiohttp import web

import catalog
import config
import database as db
from ratelimit import RateLimiter

_limiter = RateLimiter(config.BOT_API_RATE_LIMIT)

PREFIX = "/internal/"


def _authorized(request: web.Request) -> bool:
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        return False
    given = header[len("Bearer "):].strip().encode("utf-8")
    return hmac.compare_digest(given, config.BOT_API_TOKEN.encode("utf-8"))


@web.middleware
async def bot_auth_middleware(request: web.Request, handler):
    if request.path.startswith(PREFIX) and not _authorized(request):
        return web.json_response(
            {"ok": False, "code": "unauthorized", "error": "Invalid bot token."},
            status=401,
        )
    return await handler(request)


def _fail(code: str, error: str, status: int) -> web.Response:
    return web.json_response({"ok": False, "code": code, "error": error}, status=status)


async def _body(request: web.Request) -> dict:
    try:
        data = await request.json()
    except ValueError:
        return {}
    return data if isinstance(data, dict) else {}


# ---------------------------------------------------------------------------
async def health(request: web.Request) -> web.Response:
    return web.json_response({"ok": True})


async def games(request: web.Request) -> web.Response:
    data = await _body(request)
    key = str(data.get("key") or "").strip()
    if not key:
        return _fail("bad_request", "Missing key.", 400)
    if _limiter.hit(f"key:{key}"):
        return _fail("rate_limited", "Too many requests. Try again in a minute.", 429)
    rows = await asyncio.to_thread(catalog.games_for_key, key)
    return web.json_response({
        "ok": True,
        "games": [{"id": g["id"], "slug": g["slug"], "name": g["name"]} for g in rows],
    })


def _universal_sync(key: str, discord_id: str) -> tuple[int, dict]:
    """
    One loader for every game: the delivered script pins no game, so the
    public API picks the game from the Roblox PlaceId at execution time.
    """
    source_ip = f"discord:{discord_id}" if discord_id else "bot"
    row, problem = db.check_key(key)
    if row is None or problem:
        reason = problem or "Invalid or unknown key."
        catalog.log_access("bot", key, False, reason, None, None, source_ip)
        code = "invalid_key" if row is None else "forbidden"
        return (404 if row is None else 403), {"ok": False, "code": code, "error": reason}
    if discord_id and row["discord_id"] and str(row["discord_id"]) != discord_id:
        reason = "This key belongs to another user."
        catalog.log_access("bot", key, False, reason, None, None, source_ip)
        return 403, {"ok": False, "code": "forbidden", "error": reason}
    if not catalog.games_for_key(key):
        error = "No game with a loader is available for your key right now."
        catalog.log_access("bot", key, False, error, None, None, source_ip)
        return 404, {"ok": False, "code": "unavailable", "error": error}
    try:
        script = catalog.render_loader(key, "")
    except (OSError, ValueError):
        return 500, {
            "ok": False, "code": "server_error",
            "error": "The loader template was not found on the server.",
        }
    db.touch_key_access(key, None)
    catalog.log_access("bot", key, True, None, None, None, source_ip)
    return 200, {
        "ok": True,
        "script": script,
        "game": {"id": 0, "slug": "all", "name": "all games"},
        "loader": {"id": "universal", "version": 1, "updated_at": 0},
    }


def _loader_sync(key: str, game_slug: str, discord_id: str) -> tuple[int, dict]:
    if not game_slug:
        return _universal_sync(key, discord_id)
    game, loader, error = catalog.resolve_target(game_slug or None)
    game_id = game["id"] if game is not None else None
    source_ip = f"discord:{discord_id}" if discord_id else "bot"

    row, problem = db.check_key(key, game_id if not error else None)
    if row is None or problem:
        reason = problem or "Invalid or unknown key."
        catalog.log_access("bot", key, False, reason, game_id, None, source_ip)
        code = "invalid_key" if row is None else "forbidden"
        return (404 if row is None else 403), {"ok": False, "code": code, "error": reason}

    # The key must belong to the Discord user asking for it
    if discord_id and row["discord_id"] and str(row["discord_id"]) != discord_id:
        reason = "This key belongs to another user."
        catalog.log_access("bot", key, False, reason, game_id, None, source_ip)
        return 403, {"ok": False, "code": "forbidden", "error": reason}

    if error:
        catalog.log_access("bot", key, False, error, game_id, None, source_ip)
        return 404, {"ok": False, "code": "unavailable", "error": error}

    try:
        script = catalog.render_loader(key, game["slug"])
    except (OSError, ValueError):
        catalog.log_access("bot", key, False, "template missing", game_id, loader["id"], source_ip)
        return 500, {
            "ok": False, "code": "server_error",
            "error": "The loader template was not found on the server.",
        }

    db.touch_key_access(key, loader["id"])
    catalog.log_access("bot", key, True, None, game_id, loader["id"], source_ip)
    return 200, {
        "ok": True,
        "script": script,
        "game": {"id": game["id"], "slug": game["slug"], "name": game["name"]},
        "loader": {
            "id": loader["id"],
            "version": loader["version"],
            "updated_at": loader["updated_at"],
        },
    }


async def loader(request: web.Request) -> web.Response:
    data = await _body(request)
    key = str(data.get("key") or "").strip()
    game_slug = str(data.get("game") or "").strip().lower()[:40]
    discord_id = str(data.get("discord_id") or "").strip()[:32]
    if not key:
        return _fail("bad_request", "Missing key.", 400)
    if _limiter.hit(f"key:{key}"):
        return _fail("rate_limited", "Too many requests. Try again in a minute.", 429)
    status, payload = await asyncio.to_thread(_loader_sync, key, game_slug, discord_id)
    return web.json_response(payload, status=status)


async def heartbeat(request: web.Request) -> web.Response:
    data = await _body(request)
    status = {
        "user": str(data.get("user") or "")[:100],
        "user_id": str(data.get("user_id") or "")[:32],
        "guilds": int(data.get("guilds") or 0),
        "latency_ms": int(data.get("latency_ms") or 0),
        "started_at": int(data.get("started_at") or 0),
    }
    await asyncio.to_thread(catalog.set_kv, "bot_status", status)
    return web.json_response({"ok": True})


def add_routes(app: web.Application) -> None:
    app.router.add_get("/internal/v1/health", health)
    app.router.add_post("/internal/v1/games", games)
    app.router.add_post("/internal/v1/loader", loader)
    app.router.add_post("/internal/v1/heartbeat", heartbeat)
