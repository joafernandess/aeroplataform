"""
AERO Platform - HTTP application.

Serves, in one process:
  /v1/...             -> loader-facing endpoints (Lua): auth, execute, heartbeat,
                         ping (+ the legacy /v1/execute contract from the old bot API)
  /api/v1/...         -> JSON API for the dashboard and the Discord bot
  /dashboard/...      -> static dashboard SPA
  /loader/aero_loader.lua -> the single loader entry point (plain Lua)

Run:  python backend/app.py
"""
import asyncio
import json
import os
import time

from aiohttp import web

import config
import db
import security
import services

BACKEND_DIR = os.path.dirname(os.path.abspath(__file__))
PLATFORM_DIR = os.path.dirname(BACKEND_DIR)
DASH_DIR = os.path.join(PLATFORM_DIR, "dashboard")
LOADER_DIR = os.path.join(PLATFORM_DIR, "loader")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def client_ip(request: web.Request) -> str:
    if config.TRUST_PROXY:
        fwd = request.headers.get("X-Forwarded-For", "")
        if fwd:
            return fwd.split(",")[0].strip()
    return request.remote or "unknown"


def json_ok(data, status: int = 200) -> web.Response:
    return web.json_response({"ok": True, "data": data}, status=status)


def json_err(status: int, message: str) -> web.Response:
    return web.json_response({"ok": False, "error": message}, status=status)


async def read_json(request: web.Request) -> dict:
    try:
        if request.content_length in (None, 0):
            return {}
        raw = await request.read()
        data = json.loads(raw.decode("utf-8"))
        return data if isinstance(data, dict) else {}
    except (json.JSONDecodeError, UnicodeDecodeError, ValueError):
        return {}


SECURITY_HEADERS = {
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "no-referrer",
}


@web.middleware
async def harden_mw(request: web.Request, handler):
    response = await handler(request)
    for key, value in SECURITY_HEADERS.items():
        response.headers.setdefault(key, value)
    return response


@web.middleware
async def error_mw(request: web.Request, handler):
    """Turns unexpected handler exceptions into a 500 JSON (logged once)."""
    import logging
    try:
        return await handler(request)
    except web.HTTPException:
        raise
    except asyncio.CancelledError:
        raise
    except Exception:
        logging.getLogger("aero").exception(
            "500 on %s %s", request.method, request.path)
        return json_err(500, "Internal server error")


# ---------------------------------------------------------------------------
# Auth: dashboard session cookie OR service API token (Bearer / X-API-Token)
# ---------------------------------------------------------------------------
def current_actor(request: web.Request) -> dict | None:
    cookie = request.cookies.get("aero_session")
    if cookie:
        user = services.session_user(cookie)
        if user:
            return {"id": user["id"], "email": user["email"], "role": user["role"]}
    auth_header = request.headers.get("Authorization", "")
    token = auth_header[7:].strip() if auth_header.startswith("Bearer ") else \
        request.headers.get("X-API-Token", "").strip()
    if token:
        row = services.verify_api_token(token)
        if row:
            return {"id": 0, "email": f"token:{row['name']}",
                    "role": "service" if row["role"] == "service" else "loader",
                    "token_name": row["name"]}
    return None


def require_auth(level: str = "any"):
    def deco(func):
        async def wrapper(request: web.Request):
            actor = current_actor(request)
            if actor is None:
                return json_err(401, "Not authenticated")
            if actor["role"] == "loader":
                # loader tokens are delivery-only: they never touch /api/v1
                return json_err(403, "Loader tokens cannot access this API")
            request["actor"] = actor
            request["actor_email"] = actor["email"]
            if level == "owner" and actor["role"] != "owner":
                return json_err(403, "Owner permission required")
            return await func(request)
        return wrapper
    return deco


# ---------------------------------------------------------------------------
# Loader endpoints (Lua-facing)
# ---------------------------------------------------------------------------
def _lua_error(message: str) -> str:
    safe = (str(message).replace("\r", " ").replace("\n", " ")
            .replace("\\", "\\\\").replace('"', '\\"'))
    return f'error("[Aero] {safe}", 0)\n'


def _parse_loader_args(args: dict) -> tuple[str, str, int | None, int | None, str | None]:
    key = str(args.get("key", "") or "").strip()
    hwid = str(args.get("hwid", "") or "").strip()
    raw_place = args.get("place_id") or args.get("place") or args.get("game")
    try:
        place_id = int(str(raw_place))
    except (TypeError, ValueError):
        place_id = None
    raw_game = args.get("game_id") or args.get("universe_id")
    try:
        game_id = int(str(raw_game))
    except (TypeError, ValueError):
        game_id = None
    lv = str(args.get("lv") or args.get("loader_version") or "").strip() or None
    return key, hwid, place_id, game_id, lv


def _loader_args_from(request: web.Request, body: dict) -> tuple:
    args = dict(request.rel_url.query)
    args.update({k: v for k, v in body.items() if v not in (None, "")})
    return _parse_loader_args(args)


async def loader_health(request: web.Request) -> web.Response:
    return web.json_response({
        "ok": True,
        "service": "aero-platform",
        "version": config.AERO_VERSION,
        "uptime": services.uptime_seconds(),
        "time": int(time.time()),
        # Public base URL used by the loader (HTTPS in production).
        "public_url": config.PUBLIC_API_URL,
    })


async def legacy_ping(request: web.Request) -> web.Response:
    return web.Response(text="ok", content_type="text/plain")


def _rate_check(request: web.Request, kind: str) -> web.Response | None:
    ip = client_ip(request)
    if security.rate_limited(f"loader:{ip}", config.RATE_LOADER_MIN, 60):
        services.log_event("rate_limited", result=None, ip=ip)
        return json_err(429, "Too many requests, wait a minute.")
    return None


async def loader_auth(request: web.Request) -> web.Response:
    guard = _rate_check(request, "loader_auth")
    if guard:
        return guard
    body = await read_json(request) if request.method == "POST" else dict(request.rel_url.query)
    key, hwid, place_id, game_id, lv = _loader_args_from(request, body)
    if not key:
        services.log_event("loader_auth", result="denied", reason="missing key",
                           ip=client_ip(request))
        return web.json_response({"status": "denied", "reason": "No key provided."})
    allowed, reason, krow, script = services.validate_execution(
        key, hwid, place_id, lv, "loader_auth", ip=client_ip(request),
        game_id=game_id)
    if not allowed:
        return web.json_response({"status": "denied", "reason": reason})
    srow = script or {}
    return web.json_response({
        "status": "ok",
        "expires_at": krow["expires_at"],
        "expires_text": services.fmt_date(krow["expires_at"]),
        "hwid": krow["hwid"],
        "script": ({
            "name": srow.get("name"),
            "version": srow.get("current_version"),
            "game": srow.get("game_name"),
            "autokick": int(srow.get("autokick_enabled") or 0),
            "recheck_minutes": int(srow.get("recheck_minutes") or 5),
        } if srow else None),
    })


async def loader_heartbeat(request: web.Request) -> web.Response:
    guard = _rate_check(request, "heartbeat")
    if guard:
        return guard
    body = await read_json(request) if request.method == "POST" else dict(request.rel_url.query)
    key, hwid, place_id, game_id, lv = _loader_args_from(request, body)
    if not key:
        return web.json_response({"status": "denied", "reason": "No key provided."})
    allowed, reason, krow, script = services.validate_execution(
        key, hwid, place_id, lv, "heartbeat", ip=client_ip(request),
        game_id=game_id)
    if not allowed:
        return web.json_response({"status": "denied", "reason": reason})
    return web.json_response({"status": "ok"})


async def _deliver_source(request: web.Request, kind: str) -> web.Response:
    ip = client_ip(request)
    if security.rate_limited(f"loader:{ip}", config.RATE_LOADER_MIN, 60):
        services.log_event("rate_limited", ip=ip)
        return web.Response(
            text=_lua_error("Too many requests. Wait a minute and try again."),
            content_type="text/plain")

    body = await read_json(request) if request.method == "POST" else {}
    key, hwid, place_id, game_id, lv = _loader_args_from(request, body)
    if not key:
        services.log_event(kind, result="denied", reason="missing key", ip=ip)
        return web.Response(text=_lua_error("No key provided."), content_type="text/plain")

    allowed, reason, krow, script = services.validate_execution(
        key, hwid, place_id, lv, kind, ip=ip, game_id=game_id)
    if not allowed:
        message = reason or "Key rejected."
        return web.Response(text=_lua_error(message), content_type="text/plain")

    source = services.current_source(script["id"]) if script else None
    if not source:
        fallback_path = os.environ.get("AERO_FALLBACK_PAYLOAD", "")
        if fallback_path and os.path.exists(fallback_path):
            with open(fallback_path, "r", encoding="utf-8") as fh:
                source = fh.read()
    if not source:
        return web.Response(
            text=_lua_error("No script source published for your key yet. Contact support."),
            content_type="text/plain")
    headers = {}
    if script:
        headers["X-Aero-Script"] = str(script["id"])
        headers["X-Aero-Version"] = str(script.get("current_version") or "")
        headers["X-Aero-Autokick"] = str(int(script.get("autokick_enabled") or 0))
        headers["X-Aero-Recheck"] = str(int(script.get("recheck_minutes") or 5))
    return web.Response(text=source, headers=headers)


async def loader_execute(request: web.Request) -> web.Response:
    return await _deliver_source(request, "execute_ok")


async def legacy_execute(request: web.Request) -> web.Response:
    return await _deliver_source(request, "execute_ok")


async def loader_entry(request: web.Request) -> web.Response:
    path = os.path.join(LOADER_DIR, "aero_loader.lua")
    if not os.path.exists(path):
        return json_err(404, "loader file missing")
    with open(path, "r", encoding="utf-8") as fh:
        source = fh.read()
    # The Lua file ships with the localhost default so it also works when
    # opened directly; the served copy always points at PUBLIC_API_URL
    # (the tunnel/HTTPS domain in production).
    source = source.replace(
        'local API_URL = "http://127.0.0.1:8720"',
        f'local API_URL = "{config.PUBLIC_API_URL}"',
        1,
    )
    return web.Response(
        body=source.encode("utf-8"), content_type="text/plain",
        headers={"X-Aero-Loader-Version": config.LOADER_VERSION})


# ---------------------------------------------------------------------------
# Dashboard auth
# ---------------------------------------------------------------------------
async def auth_login(request: web.Request) -> web.Response:
    ip = client_ip(request)
    if security.rate_limited(f"login:{ip}", config.RATE_LOGIN_MIN, config.RATE_LOGIN_WINDOW):
        services.log_event("rate_limited", ip=ip, detail="dashboard login")
        return json_err(429, "Too many attempts. Try again in a few minutes.")
    body = await read_json(request)
    email = str(body.get("email", "")).strip().lower()
    password = str(body.get("password", ""))
    if not email or not password:
        return json_err(400, "Email and password are required.")
    user = services.dashboard_login(email, password, ip=ip)
    if user is None:
        return json_err(401, "Invalid credentials.")
    session_id, expires_at = services.create_session(user["id"], ip)
    response = json_ok({
        "id": user["id"], "email": user["email"], "role": user["role"],
        "must_change": user["must_change"],
    })
    response.set_cookie(
        "aero_session", session_id,
        max_age=config.SESSION_TTL_HOURS * 3600,
        httponly=True, samesite="Lax", path="/",
    )
    services.audit("dashboard", user["email"], "dash.login", target=ip)
    return response


async def auth_me(request: web.Request) -> web.Response:
    actor = current_actor(request)
    if actor is None:
        return json_err(401, "Not authenticated")
    return json_ok({"id": actor["id"], "email": actor["email"], "role": actor["role"]})


async def auth_logout(request: web.Request) -> web.Response:
    cookie = request.cookies.get("aero_session", "")
    if cookie:
        services.destroy_session(cookie)
    response = json_ok({"logout": True})
    response.del_cookie("aero_session", path="/")
    return response


@require_auth()
async def auth_change_password(request: web.Request) -> web.Response:
    body = await read_json(request)
    actor = request["actor"]
    old_password = str(body.get("old", "")) if actor["id"] else None
    new_password = str(body.get("new", ""))
    if len(new_password) < 8:
        return json_err(400, "New password needs at least 8 characters.")
    if not services.change_password(actor["id"], old_password, new_password):
        return json_err(400, "Password not changed (wrong current password?)")
    return json_ok({"changed": True})


# ---------------------------------------------------------------------------
# Games
# ---------------------------------------------------------------------------
@require_auth()
async def games_list(request: web.Request) -> web.Response:
    return json_ok(services.list_games())


@require_auth()
async def games_create(request: web.Request) -> web.Response:
    body = await read_json(request)
    name = str(body.get("name", "")).strip()
    if not name:
        return json_err(400, "name is required")
    if db.one("SELECT 1 FROM games WHERE name = ?", (name,)):
        return json_err(409, "A game with this name already exists")
    place_ids = body.get("place_ids")
    if isinstance(place_ids, str):
        place_ids = [int(x) for x in place_ids.replace(" ", "")
                     .split(",") if x.strip().isdigit()]
    elif isinstance(place_ids, list):
        try:
            place_ids = [int(x) for x in place_ids]
        except (TypeError, ValueError):
            return json_err(400, "place_ids must be numbers")
    else:
        place_ids = []
    game = services.create_game(name, place_ids, body.get("icon_url"),
                                actor=request["actor_email"])
    return json_ok(game, 201)


@require_auth()
async def games_update(request: web.Request) -> web.Response:
    body = await read_json(request)
    game_id = int(request.match_info["game_id"])
    place_ids = body.get("place_ids")
    if isinstance(place_ids, str):
        place_ids = [int(x) for x in place_ids.replace(" ", "").split(",")
                     if x.strip().isdigit()]
    elif isinstance(place_ids, list):
        try:
            place_ids = [int(x) for x in place_ids]
        except (TypeError, ValueError):
            return json_err(400, "place_ids must be numbers")
    elif body.get("place_ids") == "":
        place_ids = []
    else:
        place_ids = None
    active = body.get("active")
    if active is not None and active not in (0, 1):
        active = 1 if active else 0
    game = services.update_game(
        game_id, name=body.get("name"), place_ids=place_ids,
        icon_url=body.get("icon_url"), active=active,
        actor=request["actor_email"])
    if game is None:
        return json_err(404, "Game not found")
    return json_ok(game)


@require_auth("owner")
async def games_delete(request: web.Request) -> web.Response:
    game_id = int(request.match_info["game_id"])
    if not services.delete_game(game_id, actor=request["actor_email"]):
        return json_err(404, "Game not found")
    return json_ok({"deleted": True})


# ---------------------------------------------------------------------------
# Licenses / products
# ---------------------------------------------------------------------------
@require_auth()
async def licenses_list(request: web.Request) -> web.Response:
    return json_ok(services.list_licenses())


@require_auth()
async def licenses_create(request: web.Request) -> web.Response:
    body = await read_json(request)
    name = str(body.get("name", "")).strip()
    if not name:
        return json_err(400, "name is required")
    try:
        days = int(body.get("days", 0) or 0)
        price = int(body["price_cents"]) if body.get("price_cents") is not None else None
    except (TypeError, ValueError):
        return json_err(400, "days/price must be numbers")
    lic = services.create_license(name, days, price, actor=request["actor_email"])
    return json_ok(lic, 201)


@require_auth()
async def products_list(request: web.Request) -> web.Response:
    return json_ok(services.list_products())


@require_auth()
async def products_create(request: web.Request) -> web.Response:
    body = await read_json(request)
    name = str(body.get("name", "")).strip()
    if not name:
        return json_err(400, "name is required")
    parsed: dict = {
        "description": body.get("description"),
        "price_cents": None,
        "game_id": None,
        "license_id": None,
    }
    for field, source in (("price_cents", "price_cents"),
                          ("game_id", "game_id"),
                          ("license_id", "license_id")):
        if body.get(source) not in (None, ""):
            try:
                parsed[field] = int(body[source])
            except (TypeError, ValueError):
                return json_err(400, f"{field} must be an integer")
    product = services.create_product(
        name, parsed["description"], parsed["price_cents"],
        parsed["game_id"], parsed["license_id"], actor=request["actor_email"])
    return json_ok(product, 201)


@require_auth()
async def products_update(request: web.Request) -> web.Response:
    body = await read_json(request)
    product_id = int(request.match_info["product_id"])
    for field in ("price_cents", "game_id", "license_id"):
        if field in body and body[field] not in (None, ""):
            try:
                body[field] = int(body[field])
            except (TypeError, ValueError):
                return json_err(400, f"{field} must be an integer")
    if body.get("active") is not None and body["active"] not in (0, 1):
        body["active"] = 1 if body["active"] else 0
    product = services.update_product(product_id, actor=request["actor_email"], **body)
    if product is None:
        return json_err(404, "Product not found")
    return json_ok(product)


@require_auth("owner")
async def products_delete(request: web.Request) -> web.Response:
    product_id = int(request.match_info["product_id"])
    if not services.delete_product(product_id, actor=request["actor_email"]):
        return json_err(404, "Product not found")
    return json_ok({"deleted": True})


# ---------------------------------------------------------------------------
# Scripts + versions
# ---------------------------------------------------------------------------
@require_auth()
async def scripts_list(request: web.Request) -> web.Response:
    return json_ok(services.list_scripts())


@require_auth()
async def scripts_create(request: web.Request) -> web.Response:
    body = await read_json(request)
    name = str(body.get("name", "")).strip()
    if not name:
        return json_err(400, "name is required")
    game_id = None
    product_id = None
    try:
        if body.get("game_id") not in (None, ""):
            game_id = int(body["game_id"])
        if body.get("product_id") not in (None, ""):
            product_id = int(body["product_id"])
        recheck = max(1, int(body.get("recheck_minutes", 5) or 5))
    except (TypeError, ValueError):
        return json_err(400, "game_id/product_id/recheck must be integers")
    autokick = 1 if body.get("autokick_enabled", 1) else 0
    script = services.create_script(name, body.get("description"), game_id,
                                    product_id, autokick, recheck,
                                    actor=request["actor_email"])
    assert script is not None
    source = str(body.get("source", "") or "").strip()
    if source:
        services.add_version(script["id"], str(body.get("version") or "1.0.0"),
                             source, body.get("changelog"),
                             actor=request["actor_email"])
    return json_ok(services.get_script(script["id"]), 201)


@require_auth()
async def scripts_update(request: web.Request) -> web.Response:
    body = await read_json(request)
    script_id = int(request.match_info["script_id"])
    for field in ("game_id", "product_id", "recheck_minutes"):
        if field in body and body[field] not in (None, ""):
            try:
                body[field] = int(body[field])
            except (TypeError, ValueError):
                return json_err(400, f"{field} must be an integer")
    if body.get("enabled") is not None:
        body["enabled"] = 1 if body["enabled"] else 0
    if body.get("autokick_enabled") is not None:
        body["autokick_enabled"] = 1 if body["autokick_enabled"] else 0
    script = services.update_script(script_id, actor=request["actor_email"], **body)
    if script is None:
        return json_err(404, "Script not found")
    return json_ok(script)


@require_auth("owner")
async def scripts_delete(request: web.Request) -> web.Response:
    script_id = int(request.match_info["script_id"])
    if not services.delete_script(script_id, actor=request["actor_email"]):
        return json_err(404, "Script not found")
    return json_ok({"deleted": True})


@require_auth()
async def script_versions_list(request: web.Request) -> web.Response:
    script_id = int(request.match_info["script_id"])
    return json_ok(services.script_versions(script_id))


@require_auth()
async def script_version_create(request: web.Request) -> web.Response:
    body = await read_json(request)
    script_id = int(request.match_info["script_id"])
    source = str(body.get("source", "")).strip()
    version = str(body.get("version", "")).strip()
    if not source:
        return json_err(400, "source (Lua code) is required")
    if not version:
        return json_err(400, "version is required")
    row = services.add_version(script_id, version, source, body.get("changelog"),
                               actor=request["actor_email"])
    if row is None:
        return json_err(404, "Script not found")
    return json_ok(row, 201)


@require_auth()
async def script_version_get(request: web.Request) -> web.Response:
    vid = int(request.match_info["vid"])
    row = services.get_version(vid)
    if row is None:
        return json_err(404, "Version not found")
    return web.json_response(row)


@require_auth("owner")
async def script_version_delete(request: web.Request) -> web.Response:
    vid = int(request.match_info["vid"])
    row = services.get_version(vid)
    if row is None:
        return json_err(404, "Version not found")
    script = services.get_script(row["script_id"])
    if script and script["current_version"] == row["version"]:
        return json_err(409, "This is the current version - publish a newer one first")
    if len(services.script_versions(row["script_id"])) == 1:
        return json_err(409, "A script needs at least one published version")
    db.execute("DELETE FROM script_versions WHERE id = ?", (vid,))
    services.audit("dashboard", request["actor_email"], "script.version.delete",
                   target=f"{row['script_id']}:{row['version']}")
    return json_ok({"deleted": True})


# ---------------------------------------------------------------------------
# Keys
# ---------------------------------------------------------------------------
@require_auth()
async def keys_generate(request: web.Request) -> web.Response:
    body = await read_json(request)
    actor = request["actor_email"]
    try:
        count = int(body.get("count", 1) or 1)
        days = int(body["days"]) if body.get("days") not in (None, "") else None
        product_id = int(body["product_id"]) if body.get("product_id") not in (None, "") else None
        license_id = int(body["license_id"]) if body.get("license_id") not in (None, "") else None
        script_id = int(body["script_id"]) if body.get("script_id") not in (None, "") else None
    except (TypeError, ValueError):
        return json_err(400, "count/days/ids must be integers")
    try:
        rows = services.generate_keys(
            count, days, product_id=product_id, license_id=license_id,
            script_id=script_id, note=str(body.get("note") or "") or None,
            actor=actor)
    except ValueError as exc:
        return json_err(400, str(exc))
    except RuntimeError:
        return json_err(500, "Could not allocate unique keys")
    return json_ok(rows, 201)


@require_auth()
async def keys_list(request: web.Request) -> web.Response:
    q = request.rel_url.query
    try:
        limit = min(int(q.get("limit", 50) or 50), 500)
        offset = int(q.get("offset", 0) or 0)
        product_id = int(q["product_id"]) if q.get("product_id") else None
    except (TypeError, ValueError):
        return json_err(400, "limit/offset/product_id must be integers")
    rows, total = services.list_keys(
        search=q.get("search"), status=q.get("status"),
        product_id=product_id, limit=limit, offset=offset)
    return json_ok({"rows": rows, "total": total, "limit": limit, "offset": offset})


@require_auth()
async def key_action(request: web.Request) -> web.Response:
    action = request.match_info["action"]
    body = await read_json(request)
    key = str(body.get("key", "")).strip()
    actor = request["actor_email"]
    if not key:
        return json_err(400, "key is required")

    if action == "redeem":
        discord_id = body.get("discord_id")
        if not str(discord_id or "").strip().isdigit():
            return json_err(400, "discord_id (numeric) is required")
        try:
            discord_id_int = int(str(discord_id))
        except (TypeError, ValueError):
            return json_err(400, "discord_id must be a number")
        code, row = services.redeem_key(
            key, discord_id_int, body.get("display_name"), actor=actor)
        if code == "not_found":
            return json_err(404, "Key not found")
        return json_ok({"code": code, "key": row})

    if action == "view":
        services.audit("dashboard", actor, "key.view", target=key)
        row = services.get_key(key)
        if row is None:
            return json_err(404, "Key not found")
        return json_ok(row)

    if action == "reset-hwid":
        ok, code = services.reset_hwid_key(key, actor=actor, allow_unredeemed=True)
        if ok:
            return json_ok({"reset": True})
        messages = {"not_found": "Key not found", "limit": "Reset limit reached",
                    "not_redeemed": "Key not redeemed"}
        return json_err(400, messages.get(code, code))

    if action == "extend":
        try:
            days = int(body.get("days", 0) or 0)
        except (TypeError, ValueError):
            return json_err(400, "days must be an integer")
        found, new_exp = services.extend_key(key, days, actor=actor)
        if not found:
            return json_err(404, "Key not found")
        return json_ok({"expires_at": new_exp, "expires_text": services.fmt_date(new_exp)})

    if action == "revoke":
        return json_ok({"revoked": services.revoke_key(key, actor=actor)})
    if action == "restore":
        return json_ok({"restored": services.restore_key(key, actor=actor)})
    if action == "ban":
        try:
            days = int(body.get("days", 0) or 0)
        except (TypeError, ValueError):
            return json_err(400, "days must be an integer")
        return json_ok({"banned": services.ban_key(
            key, str(body.get("reason", "")), days, actor=actor)})
    if action == "unban":
        return json_ok({"unbanned": services.unban_key(key, actor=actor)})
    if action == "unbind":
        return json_ok({"unbound": services.unbind_key(key, actor=actor)})
    if action == "set-note":
        return json_ok({"noted": services.set_note(
            key, str(body.get("note", "")), actor=actor)})
    if action == "set-expiration":
        raw = body.get("expires_at")
        if raw is None:
            expires_at = None
        else:
            try:
                expires_at = int(raw)
            except (TypeError, ValueError):
                return json_err(400, "expires_at must be an integer or null")
        ok = services.set_key_expiration(key, expires_at, actor=actor)
        if not ok:
            return json_err(404, "Key not found")
        return json_ok({"expires_at": expires_at,
                        "expires_text": services.fmt_date(expires_at)})
    return json_err(404, "Unknown action")


@require_auth()
async def key_stats(request: web.Request) -> web.Response:
    return json_ok(services.count_keys())


@require_auth()
async def reminders_due(request: web.Request) -> web.Response:
    return json_ok(services.due_expiration_reminders())


@require_auth()
async def reminder_mark(request: web.Request) -> web.Response:
    body = await read_json(request)
    services.mark_expiration_reminded(str(body.get("key", "")).strip())
    return json_ok({"marked": True})


@require_auth()
async def user_action(request: web.Request) -> web.Response:
    action = request.match_info["action"]
    body = await read_json(request)
    actor = request["actor_email"]

    if action in ("ban", "unban"):
        try:
            discord_id = int(str(body.get("discord_id", "0") or 0))
            days = int(body.get("days", 0) or 0) if action == "ban" else 0
        except (TypeError, ValueError):
            return json_err(400, "discord_id/days must be numbers")
        if not discord_id:
            return json_err(400, "discord_id is required")
        ok = (services.ban_user(discord_id, str(body.get("reason", "")), days, actor=actor)
              if action == "ban"
              else services.unban_user(discord_id, actor=actor))
        if not ok:
            return json_err(404, "User has no keys / does not exist")
        return json_ok({action: True})

    if action == "notes":
        try:
            user_id = int(body.get("user_id", 0) or 0)
        except (TypeError, ValueError):
            return json_err(400, "user_id must be a number")
        user = services.update_user(user_id, actor=actor,
                                    notes=str(body.get("notes", "")))
        if user is None:
            return json_err(404, "User not found")
        return json_ok(user)
    return json_err(404, "Unknown action")


# ---------------------------------------------------------------------------
# Users
# ---------------------------------------------------------------------------
@require_auth()
async def users_list(request: web.Request) -> web.Response:
    q = request.rel_url.query
    try:
        limit = min(int(q.get("limit", 50) or 50), 500)
        offset = int(q.get("offset", 0) or 0)
    except (TypeError, ValueError):
        return json_err(400, "limit/offset must be integers")
    rows, total = services.list_users(search=q.get("search"), limit=limit, offset=offset)
    return json_ok({"rows": rows, "total": total})


@require_auth()
async def user_detail(request: web.Request) -> web.Response:
    user_id = int(request.match_info["user_id"])
    user = services.get_user(user_id)
    if user is None:
        return json_err(404, "User not found")
    return json_ok({
        "user": user,
        "keys": services.user_keys(user_id),
        "events": services.user_events(user_id, limit=100),
    })


@require_auth("owner")
async def users_grant(request: web.Request) -> web.Response:
    body = await read_json(request)
    try:
        user_id = int(body.get("user_id", 0) or 0)
    except (TypeError, ValueError):
        return json_err(400, "user_id must be a number")
    role = str(body.get("role", "buyer"))
    if role not in ("buyer", "staff", "owner"):
        return json_err(400, "Invalid role")
    user = services.update_user(user_id, actor=request["actor_email"], role=role)
    if user is None:
        return json_err(404, "User not found")
    return json_ok(user)


# ---------------------------------------------------------------------------
# Stats, events, sales, tokens, embeds, langs
# ---------------------------------------------------------------------------
@require_auth()
async def overview(request: web.Request) -> web.Response:
    return json_ok(services.overview())


@require_auth()
async def events_list(request: web.Request) -> web.Response:
    q = request.rel_url.query
    try:
        limit = min(int(q.get("limit", 100) or 100), 500)
    except (TypeError, ValueError):
        limit = 100
    rows = services.recent_events(limit=limit, kind=q.get("kind"),
                                  result=q.get("result"), key=q.get("key"))
    return json_ok(rows)


@require_auth()
async def audit_list(request: web.Request) -> web.Response:
    q = request.rel_url.query
    try:
        limit = min(int(q.get("limit", 100) or 100), 500)
    except (TypeError, ValueError):
        limit = 100
    return json_ok(services.recent_audit(limit=limit, action=q.get("action")))


@require_auth()
async def sales_list(request: web.Request) -> web.Response:
    return json_ok(services.list_sales())


@require_auth()
async def sales_create(request: web.Request) -> web.Response:
    body = await read_json(request)
    try:
        amount = int(body.get("amount_cents", 0) or 0)
        discord_id = int(str(body["discord_id"])) if body.get("discord_id") else None
    except (TypeError, ValueError):
        return json_err(400, "amount/discord_id must be numbers")
    row = services.record_sale(
        buyer=str(body.get("buyer") or "unknown"), discord_id=discord_id,
        game=body.get("game"), product=body.get("product"),
        amount_cents=amount, status=str(body.get("status") or "paid"),
        note=body.get("note"), actor=request["actor_email"])
    return json_ok(row, 201)


@require_auth()
async def tokens_list(request: web.Request) -> web.Response:
    if request["actor"]["role"] not in ("owner", "service"):
        return json_err(403, "Owner permission required")
    return json_ok(services.list_api_tokens())


@require_auth("owner")
async def tokens_create(request: web.Request) -> web.Response:
    body = await read_json(request)
    name = str(body.get("name", "")).strip()
    role = str(body.get("role", "service"))
    if not name:
        return json_err(400, "name is required")
    if role not in ("service", "loader"):
        return json_err(400, "role must be 'service' or 'loader'")
    row, plaintext = services.create_api_token(name, role, request["actor_email"])
    return json_ok({**row, "token": plaintext}, 201)  # plaintext shown exactly once


@require_auth("owner")
async def tokens_revoke(request: web.Request) -> web.Response:
    token_id = int(request.match_info["token_id"])
    if not services.revoke_api_token(token_id, actor=request["actor_email"]):
        return json_err(404, "Token not found")
    return json_ok({"revoked": True})


@require_auth()
async def embeds_list(request: web.Request) -> web.Response:
    return json_ok(services.list_embeds())


@require_auth()
async def embed_get(request: web.Request) -> web.Response:
    embed_id = int(request.match_info["embed_id"])
    row = services.get_embed(embed_id)
    if row is None:
        return json_err(404, "Template not found")
    return json_ok(row)


@require_auth()
async def embed_save(request: web.Request) -> web.Response:
    body = await read_json(request)
    name = str(body.get("name", "")).strip()
    data = body.get("data")
    if not name or not isinstance(data, str):
        return json_err(400, "name and data (JSON text) are required")
    try:
        json.loads(data)
    except (json.JSONDecodeError, ValueError):
        return json_err(400, "data must be valid JSON stored as a string")
    template_id = int(body["id"]) if str(body.get("id") or "").strip().isdigit() else None
    try:
        row = services.save_embed(name, data, created_by=request["actor_email"],
                                  template_id=template_id)
    except ValueError as exc:
        return json_err(404, str(exc))
    return json_ok(row, 201)


@require_auth()
async def embed_delete(request: web.Request) -> web.Response:
    embed_id = int(request.match_info["embed_id"])
    if not services.delete_embed(embed_id, actor=request["actor_email"]):
        return json_err(404, "Template not found")
    return json_ok({"deleted": True})


@require_auth()
@require_auth()
async def lang_get(request: web.Request) -> web.Response:
    discord_id = int(request.match_info["discord_id"])
    return json_ok({"discord_id": discord_id, "lang": services.get_lang(discord_id)})


@require_auth()
async def lang_set(request: web.Request) -> web.Response:
    discord_id = int(request.match_info["discord_id"])
    body = await read_json(request)
    try:
        lang = services.set_lang(discord_id, str(body.get("lang", "")))
    except ValueError:
        return json_err(400, "lang must be en, pt or es")
    return json_ok({"discord_id": discord_id, "lang": lang})


# ---------------------------------------------------------------------------
# Dashboard users management
# ---------------------------------------------------------------------------
@require_auth()
async def dashboard_users_list(request: web.Request) -> web.Response:
    if request["actor"]["role"] not in ("owner", "service"):
        return json_err(403, "Owner permission required")
    return json_ok(services.list_dashboard_users())


@require_auth("owner")
async def dashboard_users_create(request: web.Request) -> web.Response:
    body = await read_json(request)
    email = str(body.get("email", "")).strip().lower()
    password = str(body.get("password", ""))
    role = str(body.get("role", "staff"))
    if not email or "@" not in email or len(password) < 8 or role not in ("owner", "staff"):
        return json_err(400, "email, password (8+) and role (owner|staff) required")
    for r in services.list_dashboard_users():
        if r["email"] == email:
            db.execute("UPDATE dashboard_users SET role = ? WHERE id = ?", (role, r["id"]))
            services.audit("dashboard", request["actor_email"],
                           "dash.user.update", target=email)
            return json_ok({"updated": True})
    db.execute(
        """INSERT INTO dashboard_users (email, password_hash, role, must_change, created_at)
           VALUES (?,?,?,1,?)""",
        (email, security.hash_password(password), role, services.now()))
    services.audit("dashboard", request["actor_email"], "dash.user.create", target=email)
    return json_ok({"created": True}, 201)


# ---------------------------------------------------------------------------
# Static dashboard
# ---------------------------------------------------------------------------
async def dashboard_index(request: web.Request) -> web.Response:
    return web.FileResponse(os.path.join(DASH_DIR, "index.html"))


def register_dashboard(app: web.Application) -> None:
    if not os.path.isdir(DASH_DIR):
        return
    app.router.add_get("/dashboard/", dashboard_index)
    app.router.add_get("/dashboard", dashboard_index)
    app.router.add_static("/dashboard/", DASH_DIR)


async def root_redirect(request: web.Request) -> web.Response:
    raise web.HTTPFound("/dashboard/")


# ---------------------------------------------------------------------------
# Background backup
# ---------------------------------------------------------------------------
async def backup_loop(app: web.Application) -> None:
    try:
        while True:
            await asyncio.sleep(6 * 3600)
            try:
                path = services.backup(config.BACKUP_DIR)
                services.prune_backups(config.BACKUP_DIR, keep=7)
                services.audit("system", "scheduler", "db.backup", target=path)
            except Exception:
                services.audit("system", "scheduler", "db.backup_failed")
    except asyncio.CancelledError:
        return


async def on_startup(app: web.Application) -> None:
    app["backup_task"] = asyncio.create_task(backup_loop(app))


async def on_cleanup(app: web.Application) -> None:
    task = app.get("backup_task")
    if task:
        task.cancel()


# ---------------------------------------------------------------------------
# Assembly
# ---------------------------------------------------------------------------
def new_app() -> web.Application:
    db.migrate()
    services.bootstrap_admin()

    app = web.Application(client_max_size=12 * 1024 * 1024)  # Lua source up to ~12 MB
    app.middlewares.append(harden_mw)
    app.middlewares.append(error_mw)

    app.add_routes([
        web.get("/v1/health", loader_health),
        web.get("/v1/ping", legacy_ping),
        web.get("/v1/execute", legacy_execute),
        web.post("/v1/execute", legacy_execute),
        web.get("/v1/loader/execute", loader_execute),
        web.post("/v1/loader/execute", loader_execute),
        web.get("/v1/loader/auth", loader_auth),
        web.post("/v1/loader/auth", loader_auth),
        web.get("/v1/loader/heartbeat", loader_heartbeat),
        web.post("/v1/loader/heartbeat", loader_heartbeat),
        web.get("/loader/aero_loader.lua", loader_entry),
        web.post("/api/v1/login", auth_login),
        web.get("/api/v1/me", auth_me),
        web.post("/api/v1/logout", auth_logout),
        web.post("/api/v1/change-password", auth_change_password),
        web.get("/api/v1/games", games_list),
        web.post("/api/v1/games", games_create),
        web.post("/api/v1/games/{game_id}", games_update),
        web.delete("/api/v1/games/{game_id}", games_delete),
        web.get("/api/v1/licenses", licenses_list),
        web.post("/api/v1/licenses", licenses_create),
        web.get("/api/v1/products", products_list),
        web.post("/api/v1/products", products_create),
        web.post("/api/v1/products/{product_id}", products_update),
        web.delete("/api/v1/products/{product_id}", products_delete),
        web.get("/api/v1/scripts", scripts_list),
        web.post("/api/v1/scripts", scripts_create),
        web.post("/api/v1/scripts/{script_id}", scripts_update),
        web.delete("/api/v1/scripts/{script_id}", scripts_delete),
        web.get("/api/v1/scripts/{script_id}/versions", script_versions_list),
        web.post("/api/v1/scripts/{script_id}/versions", script_version_create),
        web.get("/api/v1/versions/{vid}", script_version_get),
        web.delete("/api/v1/versions/{vid}", script_version_delete),
        web.post("/api/v1/keys/generate", keys_generate),
        web.get("/api/v1/keys", keys_list),
        web.get("/api/v1/keys/due-reminders", reminders_due),
        web.post("/api/v1/keys/marked-reminded", reminder_mark),
        web.post("/api/v1/keys/{action}", key_action),
        web.get("/api/v1/stats/keys", key_stats),
        web.post("/api/v1/users/grant", users_grant),
        web.post("/api/v1/users/{action}", user_action),
        web.get("/api/v1/users", users_list),
        web.get("/api/v1/users/{user_id}", user_detail),
        web.get("/api/v1/overview", overview),
        web.get("/api/v1/events", events_list),
        web.get("/api/v1/audit", audit_list),
        web.get("/api/v1/sales", sales_list),
        web.post("/api/v1/sales", sales_create),
        web.get("/api/v1/tokens", tokens_list),
        web.post("/api/v1/tokens", tokens_create),
        web.post("/api/v1/tokens/{token_id}/revoke", tokens_revoke),
        web.get("/api/v1/embeds", embeds_list),
        web.get("/api/v1/embeds/{embed_id}", embed_get),
        web.post("/api/v1/embeds", embed_save),
        web.delete("/api/v1/embeds/{embed_id}", embed_delete),
        web.get("/api/v1/lang/{discord_id}", lang_get),
        web.put("/api/v1/lang/{discord_id}", lang_set),
        web.get("/api/v1/dashboard-users", dashboard_users_list),
        web.post("/api/v1/dashboard-users", dashboard_users_create),
        web.get("/", root_redirect),
    ])
    register_dashboard(app)

    app.on_startup.append(on_startup)
    app.on_cleanup.append(on_cleanup)
    return app


def main() -> None:
    problems = config.validate()
    for problem in problems:
        print(f"[Aero] WARNING: {problem}")
    web.run_app(new_app(), host=config.AERO_HOST, port=config.AERO_PORT,
                print=lambda msg: print(f"[Aero] {msg}"))


if __name__ == "__main__":
    main()
