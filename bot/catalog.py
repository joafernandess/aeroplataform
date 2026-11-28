"""
Games, loaders and request logs (the "catalog" behind the central loader).

  games    - each game has a slug, a name and optional Roblox PlaceIds
  loaders  - the script served for a game. Metadata lives in the
             database, the content in <LOADERS_DIR>/<loader_id>.lua so
             multi-megabyte scripts stay out of SQLite
  access   - every loader request (public execute API and private bot API)
  activity - admin/system actions shown in the dashboard

How a request picks its loader (resolve_target):
  explicit loader id -> game slug -> Roblox PlaceId -> default game
and the game's newest enabled loader is served.
"""
import hashlib
import json
import os
import re
import secrets
import sqlite3

import config
import database as db

SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9-]{1,39}$")
LOADER_ID_RE = re.compile(r"^[A-Za-z0-9_-]{16,64}$")
MAX_LOADER_BYTES = 16 * 1024 * 1024

_content_cache: dict[str, tuple[float, str]] = {}


class CatalogError(ValueError):
    """Invalid input from the dashboard (shown to the admin as-is)."""


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def _parse_place_ids(raw: str | list | None) -> str:
    """'123, 456' or [123, 456] -> '123,456' (digits only)."""
    if raw is None:
        return ""
    parts = raw if isinstance(raw, list) else str(raw).replace(" ", ",").split(",")
    ids = []
    for part in parts:
        part = str(part).strip()
        if not part:
            continue
        if not part.isdigit() or len(part) > 20:
            raise CatalogError(f"Invalid PlaceId: {part!r}")
        if part not in ids:
            ids.append(part)
    return ",".join(ids)


def _loader_path(loader_id: str) -> str:
    if not LOADER_ID_RE.match(loader_id or ""):
        raise CatalogError("Invalid loader id.")
    return os.path.join(config.LOADERS_DIR, f"{loader_id}.lua")


def game_dict(row: sqlite3.Row) -> dict:
    return {
        "id": row["id"],
        "slug": row["slug"],
        "name": row["name"],
        "place_ids": [p for p in row["place_ids"].split(",") if p],
        "enabled": bool(row["enabled"]),
        "is_default": bool(row["is_default"]),
        "created_at": row["created_at"],
        "updated_at": row["updated_at"],
    }


def loader_dict(row: sqlite3.Row) -> dict:
    return {
        "id": row["id"],
        "game_id": row["game_id"],
        "name": row["name"],
        "enabled": bool(row["enabled"]),
        "version": row["version"],
        "size": row["size"],
        "sha256": row["sha256"],
        "created_at": row["created_at"],
        "updated_at": row["updated_at"],
    }


# ---------------------------------------------------------------------------
# Games
# ---------------------------------------------------------------------------
def list_games() -> list[sqlite3.Row]:
    return db._db().execute(
        "SELECT * FROM games ORDER BY is_default DESC, name COLLATE NOCASE"
    ).fetchall()


def get_game(game_id: int) -> sqlite3.Row | None:
    return db._db().execute(
        "SELECT * FROM games WHERE id = ?", (game_id,)
    ).fetchone()


def get_game_by_slug(slug: str) -> sqlite3.Row | None:
    return db._db().execute(
        "SELECT * FROM games WHERE slug = ?", ((slug or "").strip().lower(),)
    ).fetchone()


def get_default_game() -> sqlite3.Row | None:
    return db._db().execute(
        "SELECT * FROM games WHERE is_default = 1 LIMIT 1"
    ).fetchone()


def find_game_by_place(place_id: str) -> sqlite3.Row | None:
    place_id = (place_id or "").strip()
    if not place_id.isdigit():
        return None
    for row in list_games():
        if place_id in row["place_ids"].split(","):
            return row
    return None


def create_game(
    slug: str,
    name: str,
    place_ids: str | list | None = None,
    enabled: bool = True,
    is_default: bool = False,
) -> sqlite3.Row:
    slug = (slug or "").strip().lower()
    name = (name or "").strip()
    if not SLUG_RE.match(slug):
        raise CatalogError(
            "Slug must be 2-40 characters: lowercase letters, digits and '-'."
        )
    if not name or len(name) > 80:
        raise CatalogError("Name is required (max 80 characters).")
    places = _parse_place_ids(place_ids)
    conn = db._db()
    ts = db.now()
    with db._lock:
        if conn.execute("SELECT 1 FROM games WHERE slug = ?", (slug,)).fetchone():
            raise CatalogError(f"A game with slug '{slug}' already exists.")
        if is_default:
            conn.execute("UPDATE games SET is_default = 0")
        cur = conn.execute(
            """INSERT INTO games (slug, name, place_ids, enabled, is_default,
                                  created_at, updated_at)
               VALUES (?, ?, ?, ?, ?, ?, ?)""",
            (slug, name, places, int(enabled), int(is_default), ts, ts),
        )
        conn.commit()
        return conn.execute(
            "SELECT * FROM games WHERE id = ?", (cur.lastrowid,)
        ).fetchone()


def update_game(game_id: int, **fields) -> sqlite3.Row:
    row = get_game(game_id)
    if row is None:
        raise CatalogError("Game not found.")
    updates: dict = {}
    if "slug" in fields and fields["slug"] is not None:
        slug = str(fields["slug"]).strip().lower()
        if not SLUG_RE.match(slug):
            raise CatalogError(
                "Slug must be 2-40 characters: lowercase letters, digits and '-'."
            )
        other = get_game_by_slug(slug)
        if other is not None and other["id"] != game_id:
            raise CatalogError(f"A game with slug '{slug}' already exists.")
        updates["slug"] = slug
    if "name" in fields and fields["name"] is not None:
        name = str(fields["name"]).strip()
        if not name or len(name) > 80:
            raise CatalogError("Name is required (max 80 characters).")
        updates["name"] = name
    if "place_ids" in fields and fields["place_ids"] is not None:
        updates["place_ids"] = _parse_place_ids(fields["place_ids"])
    if "enabled" in fields and fields["enabled"] is not None:
        updates["enabled"] = int(bool(fields["enabled"]))
    if "is_default" in fields and fields["is_default"] is not None:
        updates["is_default"] = int(bool(fields["is_default"]))

    conn = db._db()
    with db._lock:
        if updates.get("is_default"):
            conn.execute("UPDATE games SET is_default = 0")
        if updates:
            updates["updated_at"] = db.now()
            cols = ", ".join(f"{k} = ?" for k in updates)
            conn.execute(
                f"UPDATE games SET {cols} WHERE id = ?",
                (*updates.values(), game_id),
            )
        conn.commit()
    return get_game(game_id)


def delete_game(game_id: int) -> bool:
    """Deletes a game. Its loaders become unassigned, key permissions go."""
    conn = db._db()
    with db._lock:
        cur = conn.execute("DELETE FROM games WHERE id = ?", (game_id,))
        if cur.rowcount == 0:
            return False
        conn.execute(
            "UPDATE loaders SET game_id = NULL, updated_at = ? WHERE game_id = ?",
            (db.now(), game_id),
        )
        conn.execute("DELETE FROM key_games WHERE game_id = ?", (game_id,))
        conn.commit()
        return True


# ---------------------------------------------------------------------------
# Loaders
# ---------------------------------------------------------------------------
def list_loaders(game_id: int | None = None) -> list[sqlite3.Row]:
    if game_id is None:
        return db._db().execute(
            "SELECT * FROM loaders ORDER BY updated_at DESC"
        ).fetchall()
    return db._db().execute(
        "SELECT * FROM loaders WHERE game_id = ? ORDER BY updated_at DESC",
        (game_id,),
    ).fetchall()


def get_loader(loader_id: str) -> sqlite3.Row | None:
    if not LOADER_ID_RE.match(loader_id or ""):
        return None
    return db._db().execute(
        "SELECT * FROM loaders WHERE id = ?", (loader_id,)
    ).fetchone()


def active_loader(game_id: int) -> sqlite3.Row | None:
    """The loader served for a game: its newest enabled one."""
    return db._db().execute(
        """SELECT * FROM loaders WHERE game_id = ? AND enabled = 1
           ORDER BY updated_at DESC LIMIT 1""",
        (game_id,),
    ).fetchone()


def _write_content(loader_id: str, content: str) -> tuple[int, str]:
    data = content.encode("utf-8")
    if len(data) > MAX_LOADER_BYTES:
        raise CatalogError("Loader is too large (max 16 MB).")
    os.makedirs(config.LOADERS_DIR, exist_ok=True)
    path = _loader_path(loader_id)
    tmp = path + ".tmp"
    with open(tmp, "wb") as fh:
        fh.write(data)
    os.replace(tmp, path)  # atomic: a request never reads half a file
    _content_cache.pop(loader_id, None)
    return len(data), hashlib.sha256(data).hexdigest()


def read_content(loader_id: str) -> str:
    """Loader content, cached until the file changes on disk."""
    path = _loader_path(loader_id)
    mtime = os.path.getmtime(path)
    cached = _content_cache.get(loader_id)
    if cached is not None and cached[0] == mtime:
        return cached[1]
    with open(path, "r", encoding="utf-8") as fh:
        text = fh.read()
    _content_cache[loader_id] = (mtime, text)
    return text


def create_loader(
    name: str,
    content: str,
    game_id: int | None = None,
    enabled: bool = True,
) -> sqlite3.Row:
    name = (name or "").strip()
    if not name or len(name) > 80:
        raise CatalogError("Name is required (max 80 characters).")
    if game_id is not None and get_game(game_id) is None:
        raise CatalogError("Game not found.")
    loader_id = secrets.token_urlsafe(16)
    size, digest = _write_content(loader_id, content or "")
    ts = db.now()
    conn = db._db()
    with db._lock:
        conn.execute(
            """INSERT INTO loaders (id, game_id, name, enabled, version, size,
                                    sha256, created_at, updated_at)
               VALUES (?, ?, ?, ?, 1, ?, ?, ?, ?)""",
            (loader_id, game_id, name, int(enabled), size, digest, ts, ts),
        )
        conn.commit()
    return get_loader(loader_id)


def update_loader(loader_id: str, **fields) -> sqlite3.Row:
    """
    Updates metadata and/or content. Passing game_id=None explicitly
    unassigns the loader; leave the key out to keep the current game.
    """
    row = get_loader(loader_id)
    if row is None:
        raise CatalogError("Loader not found.")
    updates: dict = {}
    if fields.get("name") is not None:
        name = str(fields["name"]).strip()
        if not name or len(name) > 80:
            raise CatalogError("Name is required (max 80 characters).")
        updates["name"] = name
    if "game_id" in fields:
        game_id = fields["game_id"]
        if game_id is not None and get_game(int(game_id)) is None:
            raise CatalogError("Game not found.")
        updates["game_id"] = int(game_id) if game_id is not None else None
    if fields.get("enabled") is not None:
        updates["enabled"] = int(bool(fields["enabled"]))
    if fields.get("content") is not None:
        size, digest = _write_content(loader_id, str(fields["content"]))
        updates["size"] = size
        updates["sha256"] = digest
        updates["version"] = row["version"] + 1

    if updates:
        updates["updated_at"] = db.now()
        cols = ", ".join(f"{k} = ?" for k in updates)
        conn = db._db()
        with db._lock:
            conn.execute(
                f"UPDATE loaders SET {cols} WHERE id = ?",
                (*updates.values(), loader_id),
            )
            conn.commit()
    return get_loader(loader_id)


def delete_loader(loader_id: str) -> bool:
    if get_loader(loader_id) is None:
        return False
    conn = db._db()
    with db._lock:
        conn.execute("DELETE FROM loaders WHERE id = ?", (loader_id,))
        conn.commit()
    _content_cache.pop(loader_id, None)
    try:
        os.remove(_loader_path(loader_id))
    except OSError:
        pass
    return True


# ---------------------------------------------------------------------------
# Resolution: which loader does a request get?
# ---------------------------------------------------------------------------
def resolve_target(
    game_slug: str | None = None,
    place_id: str | None = None,
    loader_id: str | None = None,
) -> tuple[sqlite3.Row | None, sqlite3.Row | None, str | None]:
    """Returns (game, loader, error). error is None on success."""
    if loader_id:
        loader = get_loader(loader_id)
        if loader is None or not loader["enabled"]:
            return None, None, "This loader is not available."
        game = get_game(loader["game_id"]) if loader["game_id"] else None
        if game is None:
            return None, None, "This loader is not assigned to a game."
        if not game["enabled"]:
            return game, None, "This game is currently disabled."
        return game, loader, None

    game = None
    if game_slug:
        game = get_game_by_slug(game_slug)
        if game is None:
            return None, None, "Unknown game."
    elif place_id:
        game = find_game_by_place(place_id)
    if game is None:
        game = get_default_game()
    if game is None:
        return None, None, "No game is configured for this place."
    if not game["enabled"]:
        return game, None, "This game is currently disabled."
    loader = active_loader(game["id"])
    if loader is None:
        return game, None, "No loader is available for this game right now."
    return game, loader, None


def games_for_key(key: str) -> list[sqlite3.Row]:
    """Enabled games that have a loader and that the key may use."""
    row, problem = db.check_key(key)
    if row is None or problem:
        return []
    allowed = None if row["all_games"] else set(db.key_game_ids(key))
    result = []
    for game in list_games():
        if not game["enabled"]:
            continue
        if allowed is not None and game["id"] not in allowed:
            continue
        if active_loader(game["id"]) is None:
            continue
        result.append(game)
    return result


# ---------------------------------------------------------------------------
# Loader script delivered to the user (the template with the key embedded)
# ---------------------------------------------------------------------------
def render_loader(key: str, game_slug: str = "") -> str:
    """
    Fills scripts/loader.lua. game_slug pins the game; empty means the
    API picks the game from the Roblox PlaceId when the script runs.
    """
    with open(config.LOADER_TEMPLATE, "r", encoding="utf-8") as fh:
        template = fh.read()
    if game_slug and not SLUG_RE.match(game_slug):
        raise CatalogError("Invalid game slug.")
    return (
        template.replace("{script_key}", key)
        .replace("{api_url}", config.PUBLIC_API_URL.rstrip("/"))
        .replace("{game}", game_slug or "")
    )


# ---------------------------------------------------------------------------
# Request log + activity + small key/value store (bot heartbeat)
# ---------------------------------------------------------------------------
def log_access(
    source: str,
    key: str | None,
    ok: bool,
    reason: str | None = None,
    game_id: int | None = None,
    loader_id: str | None = None,
    ip: str | None = None,
    hwid: str | None = None,
) -> None:
    conn = db._db()
    with db._lock:
        conn.execute(
            """INSERT INTO access_log (ts, source, key, game_id, loader_id,
                                       ip, hwid, ok, reason)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                db.now(), source, (key or "")[:64] or None, game_id,
                loader_id, (ip or "")[:64] or None, (hwid or "")[:128] or None,
                int(ok), (reason or "")[:200] or None,
            ),
        )
        conn.commit()


def recent_access(limit: int = 50, key: str | None = None) -> list[sqlite3.Row]:
    if key:
        return db._db().execute(
            "SELECT * FROM access_log WHERE key = ? ORDER BY id DESC LIMIT ?",
            (key.strip(), limit),
        ).fetchall()
    return db._db().execute(
        "SELECT * FROM access_log ORDER BY id DESC LIMIT ?", (limit,)
    ).fetchall()


def log_activity(actor: str, action: str, detail: str = "") -> None:
    conn = db._db()
    with db._lock:
        conn.execute(
            "INSERT INTO activity (ts, actor, action, detail) VALUES (?, ?, ?, ?)",
            (db.now(), actor[:64], action[:64], detail[:500]),
        )
        conn.commit()


def recent_activity(limit: int = 50) -> list[sqlite3.Row]:
    return db._db().execute(
        "SELECT * FROM activity ORDER BY id DESC LIMIT ?", (limit,)
    ).fetchall()


def prune_logs(days: int) -> int:
    """Deletes request/activity rows older than `days`. Returns rows removed."""
    if days <= 0:
        return 0
    cutoff = db.now() - days * 86400
    conn = db._db()
    with db._lock:
        a = conn.execute("DELETE FROM access_log WHERE ts < ?", (cutoff,)).rowcount
        b = conn.execute("DELETE FROM activity WHERE ts < ?", (cutoff,)).rowcount
        conn.commit()
    return a + b


def set_kv(k: str, value) -> None:
    conn = db._db()
    with db._lock:
        conn.execute(
            """INSERT INTO kv (k, v, updated_at) VALUES (?, ?, ?)
               ON CONFLICT(k) DO UPDATE SET v = excluded.v,
                                            updated_at = excluded.updated_at""",
            (k, json.dumps(value), db.now()),
        )
        conn.commit()


def del_kv(k: str) -> None:
    conn = db._db()
    with db._lock:
        conn.execute("DELETE FROM kv WHERE k = ?", (k,))
        conn.commit()


# ---------------------------------------------------------------------------
# Key-sharing detection
# ---------------------------------------------------------------------------
def distinct_ips(key: str, window_seconds: int = 86400) -> int:
    """Different IPs that successfully ran this key recently."""
    row = db._db().execute(
        """SELECT COUNT(DISTINCT ip) AS n FROM access_log
           WHERE key = ? AND source = 'execute' AND ok = 1 AND ts >= ?
             AND ip IS NOT NULL""",
        (key, db.now() - window_seconds),
    ).fetchone()
    return row["n"] or 0


def share_suspects(min_ips: int, window_seconds: int = 86400, limit: int = 20) -> list[dict]:
    """Keys that ran from at least `min_ips` different IPs recently."""
    rows = db._db().execute(
        """SELECT key, COUNT(DISTINCT ip) AS ips, COUNT(*) AS runs
           FROM access_log
           WHERE source = 'execute' AND ok = 1 AND ts >= ? AND ip IS NOT NULL
           GROUP BY key HAVING COUNT(DISTINCT ip) >= ?
           ORDER BY ips DESC, runs DESC LIMIT ?""",
        (db.now() - window_seconds, min_ips, limit),
    ).fetchall()
    return [{"key": r["key"], "ips": r["ips"], "runs": r["runs"]} for r in rows]


def claim_share_alert(key: str, cooldown_seconds: int = 86400) -> bool:
    """True when an alert for this key may be sent now (once per cooldown)."""
    found = get_kv(f"share_alert:{key}")
    if found is not None and db.now() - found[1] < cooldown_seconds:
        return False
    set_kv(f"share_alert:{key}", True)
    return True


def get_kv(k: str) -> tuple[object, int] | None:
    row = db._db().execute("SELECT v, updated_at FROM kv WHERE k = ?", (k,)).fetchone()
    if row is None:
        return None
    try:
        return json.loads(row["v"]), row["updated_at"]
    except (TypeError, ValueError):
        return None, row["updated_at"]


# ---------------------------------------------------------------------------
# Dashboard queries
# ---------------------------------------------------------------------------
def key_dict(row: sqlite3.Row, games_by_id: dict[int, sqlite3.Row] | None = None) -> dict:
    game_ids = [] if row["all_games"] else db.key_game_ids(row["key"])
    names = []
    if games_by_id is not None:
        names = [games_by_id[g]["name"] for g in game_ids if g in games_by_id]
    return {
        "key": row["key"],
        "status": db.status(row),
        "active": bool(row["active"]),
        "revoked_at": row["revoked_at"],
        "discord_id": str(row["discord_id"]) if row["discord_id"] else None,
        "note": row["note"],
        "all_games": bool(row["all_games"]),
        "game_ids": game_ids,
        "game_names": names,
        "expires_at": row["expires_at"],
        "created_at": row["created_at"],
        "redeemed_at": row["redeemed_at"],
        "executions": row["executions"],
        "hwid_set": bool(row["hwid"]),
        "hwid_resets": row["hwid_resets"],
        "last_exec": row["last_exec"],
        "last_access": row["last_access"],
        "last_loader_id": row["last_loader_id"],
        "banned": bool(row["banned"]),
        "ban_reason": row["ban_reason"],
    }


def list_keys(
    q: str = "",
    status: str = "",
    game_id: int | None = None,
    limit: int = 50,
    offset: int = 0,
) -> tuple[list[dict], int]:
    """Filtered key list for the dashboard. Returns (page, total_matches)."""
    sql = "SELECT * FROM keys"
    args: list = []
    where = []
    q = (q or "").strip()
    if q:
        like = f"%{q}%"
        where.append("(key LIKE ? OR note LIKE ? OR CAST(discord_id AS TEXT) = ?)")
        args += [like, like, q]
    if game_id is not None:
        where.append(
            "(all_games = 1 OR key IN (SELECT key FROM key_games WHERE game_id = ?))"
        )
        args.append(game_id)
    if where:
        sql += " WHERE " + " AND ".join(where)
    sql += " ORDER BY created_at DESC"
    rows = db._db().execute(sql, args).fetchall()
    if status:
        rows = [r for r in rows if db.status(r) == status]
    games_by_id = {g["id"]: g for g in list_games()}
    page = rows[offset: offset + limit]
    return [key_dict(r, games_by_id) for r in page], len(rows)


def overview() -> dict:
    rows = db._db().execute(
        """SELECT key, active, revoked_at, banned, ban_until, expires_at,
                  discord_id FROM keys"""
    ).fetchall()
    counts = {"ok": 0, "revoked": 0, "inactive": 0, "banned": 0, "expired": 0}
    redeemed = 0
    for r in rows:
        counts[db.status(r)] += 1
        if r["discord_id"]:
            redeemed += 1
    day_ago = db.now() - 86400
    req = db._db().execute(
        """SELECT COUNT(*) AS total, SUM(ok) AS ok FROM access_log
           WHERE ts >= ?""",
        (day_ago,),
    ).fetchone()
    games = list_games()
    loaders = list_loaders()
    return {
        "games": {
            "total": len(games),
            "enabled": sum(1 for g in games if g["enabled"]),
        },
        "loaders": {
            "total": len(loaders),
            "enabled": sum(1 for l in loaders if l["enabled"]),
            "unassigned": sum(1 for l in loaders if l["game_id"] is None),
        },
        "keys": {
            "total": len(rows),
            "active": counts["ok"],
            "inactive": len(rows) - counts["ok"],
            "by_status": counts,
            "redeemed": redeemed,
        },
        "requests_24h": {
            "total": req["total"] or 0,
            "ok": req["ok"] or 0,
        },
    }


# ---------------------------------------------------------------------------
# First run: turn the old single payload into the default game + loader
# ---------------------------------------------------------------------------
def bootstrap() -> None:
    """
    Idempotent. When no game exists yet, creates the default game and a
    loader with the current scripts/payload.lua, so loaders delivered
    before the dashboard existed keep working unchanged.
    """
    conn = db._db()
    if conn.execute("SELECT 1 FROM games LIMIT 1").fetchone():
        return
    name = "Default game"
    try:
        with open(config.SHOP_FILE, "r", encoding="utf-8") as fh:
            products = (json.load(fh).get("products") or [])
        if products and isinstance(products[0], dict) and products[0].get("name"):
            name = str(products[0]["name"])[:80]
    except (OSError, ValueError):
        pass
    game = create_game("default", name, is_default=True)
    try:
        with open(config.PAYLOAD_FILE, "r", encoding="utf-8") as fh:
            content = fh.read()
    except OSError:
        content = None
    if content is not None:
        loader = create_loader("Main loader", content, game_id=game["id"])
        log_activity(
            "system", "bootstrap",
            f"Created game '{name}' and loader {loader['id']} from payload.lua",
        )
    else:
        log_activity("system", "bootstrap", f"Created game '{name}' (no payload)")
