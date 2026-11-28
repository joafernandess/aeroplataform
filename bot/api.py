"""
Public HTTP server (the only one exposed through the Cloudflare tunnel).

This is the "heart" of script delivery (equivalent to
api.luarmor.net from the video):

  GET /v1/ping            -> "ok" (liveness check)
  GET /v1/execute?key=..&hwid=..[&game=slug][&place=PlaceId][&loader=id]
      -> 200 with the Lua code of the loader for that game (validates the
         key, its permission for the game, and records the execution/HWID)
      -> 200 on error too, but with a Lua `error("...")`, so the
         loader shows the exact message to the user.

The game is chosen by: loader id -> game slug -> Roblox PlaceId -> the
default game. Loaders delivered before games existed send no game, so
they get the default game, which bootstrap() created from payload.lua.

Includes a per-IP rate limit (anti brute-force), request logging and
events for the Discord log channel. The dashboard and the private bot API
are NOT here: they live on a separate loopback-only server (dashboard.py).
"""
import asyncio

from aiohttp import web

import catalog
import config
import database as db
import logger
from ratelimit import RateLimiter
from utils import error_embed, success_embed, mask_key

_limiter = RateLimiter(config.API_RATE_LIMIT)

# The Cloudflare tunnel connects from loopback, so requests reaching us from
# loopback may carry the real visitor IP in this header.
_LOOPBACK = ("127.0.0.1", "::1")
_REAL_IP_HEADER = "CF-Connecting-IP"


def _lua_error(message: str) -> str:
    """Generates a Lua file that raises an error with the given message."""
    safe = (
        message.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", " ")
        .replace("\r", " ")
    )
    return f'error("[KeyBot] {safe}", 0)\n'


def client_ip(request: web.Request) -> str:
    """
    Real visitor IP. Behind the tunnel every request arrives from loopback,
    so the header is trusted only in that case. Requests from anywhere else
    cannot forge it.
    """
    remote = request.remote or "unknown"
    if remote in _LOOPBACK:
        forwarded = request.headers.get(_REAL_IP_HEADER, "").strip()
        if forwarded:
            return forwarded[:64]
    return remote


def _lua(text: str) -> web.Response:
    return web.Response(text=text, content_type="text/plain")


async def ping(request: web.Request) -> web.Response:
    return web.Response(text="ok", content_type="text/plain")


def _share_alert(key: str) -> dict | None:
    """Alert data when this key ran from too many IPs lately (once a day)."""
    limit = config.SHARE_ALERT_IPS
    if limit <= 0:
        return None
    ips = catalog.distinct_ips(key)
    if ips < limit or not catalog.claim_share_alert(key):
        return None
    row = db.get_key(key)
    return {
        "ips": ips,
        "discord_id": row["discord_id"] if row is not None else None,
    }


def _execute_sync(
    key: str, hwid: str, game_slug: str, place: str, loader_id: str, ip: str
) -> tuple[str | None, str | None, int | None, str | None, dict | None]:
    """
    All the database work of one execution. Runs in a thread.
    Returns (content, refusal_reason, game_id, loader_id, share_alert).
    """
    game, loader, error = catalog.resolve_target(game_slug, place, loader_id)
    game_id = game["id"] if game is not None else None
    if error:
        # Validate the key anyway so an invalid key is reported as such
        row, problem = db.check_key(key)
        reason = problem or error
        catalog.log_access("execute", key, False, reason, game_id, None, ip, hwid)
        return None, reason, game_id, None, None

    allowed, reason = db.register_execution(
        key, hwid, game_id=game_id, loader_id=loader["id"]
    )
    if not allowed:
        catalog.log_access(
            "execute", key, False, reason, game_id, loader["id"], ip, hwid
        )
        return None, reason or "Key rejected.", game_id, loader["id"], None

    try:
        content = catalog.read_content(loader["id"])
    except (OSError, ValueError):
        catalog.log_access(
            "execute", key, False, "loader file missing", game_id, loader["id"],
            ip, hwid,
        )
        return (
            None, "The loader file is missing on the server.",
            game_id, loader["id"], None,
        )

    catalog.log_access("execute", key, True, None, game_id, loader["id"], ip, hwid)
    return content, None, game_id, loader["id"], _share_alert(key)


async def execute(request: web.Request) -> web.Response:
    ip = client_ip(request)
    key = request.query.get("key", "").strip()
    hwid = request.query.get("hwid", "").strip()
    game_slug = request.query.get("game", "").strip().lower()[:40]
    place = request.query.get("place", "").strip()[:20]
    loader_id = request.query.get("loader", "").strip()[:64]

    if _limiter.hit(ip):
        return _lua(_lua_error("Too many requests. Wait a minute and try again."))

    if not key:
        logger.log_event(error_embed("API: missing key", f"IP: `{ip}`"))
        return _lua(_lua_error("No key provided."))

    # Database work runs in a thread so it never blocks the Discord loop
    content, reason, _game_id, served, share = await asyncio.to_thread(
        _execute_sync, key, hwid, game_slug, place, loader_id, ip
    )

    if content is None:
        reason = reason or "Key rejected."
        if "does not match" in reason:
            title = "HWID mismatch (possible key sharing)"
        elif "HWID" in reason:
            title = "Executor sent no valid HWID"
        elif "Invalid" in reason:
            title = "Invalid key attempt"
        else:
            title = "API refused execution"
        logger.log_event(
            error_embed(
                title,
                f"Key: `{mask_key(key)}`\nHWID sent: `{hwid or '-'}`\n"
                f"Game: `{game_slug or place or 'default'}`\n"
                f"IP: `{ip}`\nReason: {reason}",
            )
        )
        return _lua(_lua_error(reason))

    logger.log_event(
        success_embed(
            "Script delivered",
            f"Key: `{mask_key(key)}`\nHWID: `{hwid or '-'}`\n"
            f"Loader: `{served}`\nIP: `{ip}`",
        )
    )
    if share:
        owner = f"<@{share['discord_id']}>" if share["discord_id"] else "not redeemed"
        logger.log_event(
            error_embed(
                "Possible key sharing",
                f"Key: `{mask_key(key)}` (owner: {owner})\n"
                f"Ran from **{share['ips']}** different IPs in the last 24 h.\n"
                "Check the key's request history in the dashboard before acting.",
            )
        )
    return _lua(content)


def create_app() -> web.Application:
    catalog.bootstrap()
    app = web.Application()
    app.router.add_get("/v1/ping", ping)
    app.router.add_get("/v1/execute", execute)
    return app


async def start_api(runner_holder: dict) -> None:
    """Starts the public HTTP server on the configured host and port."""
    # access_log=None: aiohttp would write every URL, including the key, to bot.log
    runner = web.AppRunner(create_app(), access_log=None)
    await runner.setup()
    site = web.TCPSite(runner, config.API_HOST, config.API_PORT)
    await site.start()
    runner_holder["runner"] = runner


if __name__ == "__main__":
    # Standalone mode (to test the API without Discord):
    #   python api.py
    print(f"Test API running at http://127.0.0.1:{config.API_PORT}/v1/ping")
    web.run_app(
        create_app(), host=config.API_HOST, port=config.API_PORT, access_log=None
    )
