"""
Domain layer for the AERO platform.

All licensing/ken logic lives here so the HTTP API, the Discord bot bridge
and the import tool share the exact same rules (server-side only).
"""
import json
import os
import secrets
import sqlite3
import string
import time
from datetime import datetime, timezone

import config
import db
import security

KEY_ALPHABET = string.ascii_letters + string.digits
KEY_LENGTH = 32

_started_at = time.time()


def uptime_seconds() -> int:
    return int(time.time() - _started_at)


def now() -> int:
    return int(time.time())


# ---------------------------------------------------------------------------
# Audit + event logging
# ---------------------------------------------------------------------------
def audit(actor_kind: str, actor: str | None, action: str, target: str | None = None,
          detail: str | None = None) -> None:
    db.execute(
        "INSERT INTO audit_logs (ts, actor_kind, actor, action, target, detail)"
        " VALUES (?, ?, ?, ?, ?, ?)",
        (now(), actor_kind, actor, action, target, detail),
    )


def recent_audit(limit: int = 50, action: str | None = None) -> list[dict]:
    if action:
        return db.query(
            "SELECT * FROM audit_logs WHERE action = ? ORDER BY ts DESC LIMIT ?",
            (action, limit),
        )
    return db.query("SELECT * FROM audit_logs ORDER BY ts DESC LIMIT ?", (limit,))


def log_event(kind: str, *, result: str | None = None, reason: str | None = None,
              key: str | None = None, discord_id: int | None = None,
              hwid: str | None = None, ip: str | None = None,
              game_id: int | None = None, script_id: int | None = None,
              detail: str | None = None) -> None:
    db.execute(
        """INSERT INTO auth_events
           (ts, kind, result, reason, key, discord_id, hwid, ip,
            game_id, script_id, detail)
           VALUES (?,?,?,?,?,?,?,?,?,?,?)""",
        (now(), kind, result, reason, key, discord_id, hwid, ip,
         game_id, script_id, detail),
    )


def recent_events(limit: int = 50, kind: str | None = None,
                  result: str | None = None, key: str | None = None) -> list[dict]:
    sql = "SELECT * FROM auth_events"
    where, params = [], []
    if kind:
        where.append("kind = ?")
        params.append(kind)
    if result:
        where.append("result = ?")
        params.append(result)
    if key:
        where.append("key = ?")
        params.append(key)
    if where:
        sql += " WHERE " + " AND ".join(where)
    sql += " ORDER BY ts DESC LIMIT ?"
    params.append(limit)
    return db.query(sql, params)


def event_counts(days: int = 7) -> dict:
    """For the API dashboard: ok vs denied per day + totals."""
    since = now() - days * 86400
    rows = db.query(
        """SELECT kind, result, COUNT(*) AS n FROM auth_events
           WHERE ts >= ? GROUP BY kind, result""",
        (since,),
    )
    total_ok = sum(r["n"] for r in rows if r["result"] == "ok")
    total_denied = sum(
        r["n"] for r in rows
        if r["result"] and r["result"] != "ok"
    )
    rate_limited = sum(
        r["n"] for r in rows if r["kind"] == "rate_limited"
    )
    per_day: dict[str, dict[str, int]] = {}
    day_rows = db.query(
        """SELECT CAST(ts/86400 AS INT) AS day, result, COUNT(*) AS n
           FROM auth_events WHERE ts >= ? GROUP BY day, result""",
        (since,),
    )
    for r in day_rows:
        label = datetime.fromtimestamp(r["day"] * 86400, tz=timezone.utc).strftime("%d/%m")
        slot = per_day.setdefault(label, {"ok": 0, "denied": 0})
        slot["denied" if (r["result"] and r["result"] != "ok") else "ok"] += r["n"]
    return {
        "ok_total": total_ok,
        "denied_total": total_denied,
        "rate_limited_total": rate_limited,
        "per_day": per_day,
    }


# ---------------------------------------------------------------------------
# Games
# ---------------------------------------------------------------------------
def list_games(include_inactive: bool = True) -> list[dict]:
    sql = "SELECT * FROM games"
    if not include_inactive:
        sql += " WHERE active = 1"
    return db.query(sql + " ORDER BY name")


def get_game(game_id: int) -> dict | None:
    return db.one("SELECT * FROM games WHERE id = ?", (game_id,))


def game_place_ids(game: dict) -> list[int]:
    try:
        return [int(x) for x in json.loads(game["place_ids"] or "[]")]
    except (ValueError, TypeError):
        return []


def create_game(name: str, place_ids: list[int] | None = None, icon_url: str | None = None,
                actor: str = "system") -> dict:
    gid = db.execute(
        "INSERT INTO games (name, place_ids, icon_url, active, created_at)"
        " VALUES (?,?,?,1,?)",
        (name, json.dumps(place_ids or []), icon_url, now()),
    )
    audit("dashboard", actor, "game.create", target=name)
    return get_game(gid)


def update_game(game_id: int, name: str | None = None, place_ids: list[int] | None = None,
                icon_url: str | None = None, active: int | None = None,
                actor: str = "system") -> dict | None:
    row = get_game(game_id)
    if row is None:
        return None
    sets, params = [], []
    if name is not None:
        sets.append("name = ?")
        params.append(name)
    if place_ids is not None:
        sets.append("place_ids = ?")
        params.append(json.dumps(place_ids))
    if icon_url is not None:
        sets.append("icon_url = ?")
        params.append(icon_url)
    if active is not None:
        sets.append("active = ?")
        params.append(1 if active else 0)
    if sets:
        params.append(game_id)
        db.execute(f"UPDATE games SET {', '.join(sets)} WHERE id = ?", params)
        audit("dashboard", actor, "game.update", target=row["name"])
    return get_game(game_id)


def delete_game(game_id: int, actor: str = "system") -> bool:
    row = get_game(game_id)
    if row is None:
        return False
    db.execute("DELETE FROM games WHERE id = ?", (game_id,))
    audit("dashboard", actor, "game.delete", target=row["name"])
    return True


def game_for_place(place_id: int | None, game_id: int | None = None) -> dict | None:
    """The configured game for a Roblox PlaceId **or** Universe/GameId.

    Games that span many places (Deepwoken, for example) can register their
    universe id in ``place_ids``; the loader then sends both ids and either
    one is enough to identify the game.
    """
    for g in list_games():
        ids = game_place_ids(g)
        if (place_id and place_id in ids) or (game_id and game_id in ids):
            return g
    return None


# ---------------------------------------------------------------------------
# Licenses / products
# ---------------------------------------------------------------------------
def list_licenses() -> list[dict]:
    return db.query("SELECT * FROM licenses ORDER BY days, id")


def get_license(license_id: int) -> dict | None:
    return db.one("SELECT * FROM licenses WHERE id = ?", (license_id,))


def create_license(name: str, days: int = 0, price_cents: int | None = None,
                   actor: str = "system") -> dict:
    lid = db.execute(
        "INSERT INTO licenses (name, days, price_cents, created_at) VALUES (?,?,?,?)",
        (name, max(0, days), price_cents, now()),
    )
    audit("dashboard", actor, "license.create", target=name)
    return get_license(lid)


def delete_license(license_id: int, actor: str = "system") -> bool:
    row = get_license(license_id)
    if row is None:
        return False
    try:
        db.execute("DELETE FROM licenses WHERE id = ?", (license_id,))
    except sqlite3.IntegrityError:
        return False
    audit("dashboard", actor, "license.delete", target=row["name"])
    return True


def list_products(include_inactive: bool = True) -> list[dict]:
    sql = ("SELECT p.*, g.name AS game_name, l.name AS license_name, l.days AS license_days"
           " FROM products p"
           " LEFT JOIN games g ON g.id = p.game_id"
           " LEFT JOIN licenses l ON l.id = p.license_id")
    if not include_inactive:
        sql += " WHERE p.active = 1"
    return db.query(sql + " ORDER BY p.name")


def get_product(product_id: int) -> dict | None:
    return db.one(
        """SELECT p.*, g.name AS game_name, l.name AS license_name, l.days AS license_days
           FROM products p
           LEFT JOIN games g ON g.id = p.game_id
           LEFT JOIN licenses l ON l.id = p.license_id
           WHERE p.id = ?""",
        (product_id,),
    )


def create_product(name: str, description: str | None, price_cents: int | None,
                   game_id: int | None, license_id: int | None,
                   actor: str = "system") -> dict | None:
    pid = db.execute(
        """INSERT INTO products
           (name, description, price_cents, game_id, license_id, active, created_at)
           VALUES (?,?,?,?,?,1,?)""",
        (name, description, price_cents, game_id, license_id, now()),
    )
    audit("dashboard", actor, "product.create", target=name)
    return get_product(pid)


def update_product(product_id: int, actor: str = "system", **fields) -> dict | None:
    allowed = ("name", "description", "price_cents", "game_id", "license_id", "active")
    sets, params = [], []
    for field in allowed:
        if field in fields and fields[field] is not None:
            sets.append(f"{field} = ?")
            params.append(fields[field])
    if sets:
        row = get_product(product_id)
        if row is None:
            return None
        params.append(product_id)
        db.execute(
            f"UPDATE products SET {', '.join(sets)} WHERE id = ?", params
        )
        audit("dashboard", actor, "product.update", target=row["name"])
    return get_product(product_id)


def delete_product(product_id: int, actor: str = "system") -> bool:
    row = get_product(product_id)
    if row is None:
        return False
    try:
        db.execute("DELETE FROM products WHERE id = ?", (product_id,))
    except sqlite3.IntegrityError:
        return False
    audit("dashboard", actor, "product.delete", target=row["name"])
    return True


# ---------------------------------------------------------------------------
# Scripts + versions
# ---------------------------------------------------------------------------
def list_scripts(include_disabled: bool = True) -> list[dict]:
    sql = (
        """SELECT s.*, g.name AS game_name, p.name AS product_name,
                  (SELECT COUNT(*) FROM script_versions v WHERE v.script_id = s.id)
                      AS version_count
           FROM scripts s
           LEFT JOIN games g ON g.id = s.game_id
           LEFT JOIN products p ON p.id = s.product_id"""
    )
    if not include_disabled:
        sql += " WHERE s.enabled = 1"
    return db.query(sql + " ORDER BY s.name")


def get_script(script_id: int) -> dict | None:
    return db.one(
        """SELECT s.*, g.name AS game_name, p.name AS product_name
           FROM scripts s
           LEFT JOIN games g ON g.id = s.game_id
           LEFT JOIN products p ON p.id = s.product_id
           WHERE s.id = ?""",
        (script_id,),
    )


def create_script(name: str, description: str | None = None, game_id: int | None = None,
                  product_id: int | None = None, autokick_enabled: int = 1,
                  recheck_minutes: int = 5, actor: str = "system") -> dict | None:
    sid = db.execute(
        """INSERT INTO scripts
           (name, description, game_id, product_id, enabled, autokick_enabled,
            recheck_minutes, current_version, updated_at, created_at)
           VALUES (?,?,?,?,1,?,?,?,?,?)""",
        (name, description, game_id, product_id, autokick_enabled,
         max(1, recheck_minutes), "1.0.0", now(), now()),
    )
    audit("dashboard", actor, "script.create", target=name)
    return get_script(sid)


def update_script(script_id: int, actor: str = "system", **fields) -> dict | None:
    allowed = ("name", "description", "game_id", "product_id", "enabled",
               "autokick_enabled", "recheck_minutes", "current_version")
    sets, params = [], []
    for field in allowed:
        if field in fields and fields[field] is not None:
            sets.append(f"{field} = ?")
            params.append(fields[field])
    if sets:
        if get_script(script_id) is None:
            return None
        params.append(script_id)
        db.execute(f"UPDATE scripts SET {', '.join(sets)} WHERE id = ?", params)
        audit("dashboard", actor, "script.update", target=str(script_id))
    return get_script(script_id)


def delete_script(script_id: int, actor: str = "system") -> bool:
    row = get_script(script_id)
    if row is None:
        return False
    db.execute("DELETE FROM scripts WHERE id = ?", (script_id,))  # versions cascade
    audit("dashboard", actor, "script.delete", target=row["name"])
    return True


def script_versions(script_id: int) -> list[dict]:
    return db.query(
        """SELECT id, script_id, version, changelog, created_at,
                  LENGTH(source) AS source_size
           FROM script_versions WHERE script_id = ? ORDER BY created_at DESC, id DESC""",
        (script_id,),
    )


def get_version(version_id: int) -> dict | None:
    return db.one("SELECT * FROM script_versions WHERE id = ?", (version_id,))


def add_version(script_id: int, version: str, source: str, changelog: str | None,
                actor: str = "system") -> dict | None:
    """Publish a new version and make it current (immutability: old ones stay)."""
    if get_script(script_id) is None:
        return None
    vid = db.execute(
        """INSERT INTO script_versions (script_id, version, source, changelog, created_at)
           VALUES (?,?,?,?,?)""",
        (script_id, version, source, changelog, now()),
    )
    db.execute(
        "UPDATE scripts SET current_version = ?, updated_at = ? WHERE id = ?",
        (version, now(), script_id),
    )
    audit("dashboard", actor, "script.version.publish",
          target=f"{script_id}:{version}", detail=f"{len(source)} bytes")
    return get_version(vid)


def publish_from_file(script_id: int, version: str, path: str,
                      changelog: str | None, actor: str = "system") -> dict | None:
    with open(path, "r", encoding="utf-8") as fh:
        return add_version(script_id, version, fh.read(), changelog, actor)


def current_source(script_id: int) -> str | None:
    row = db.one(
        """SELECT v.source FROM script_versions v
           JOIN scripts s ON s.id = v.script_id
           WHERE v.script_id = ?
           ORDER BY v.created_at DESC, v.id DESC LIMIT 1""",
        (script_id,),
    )
    return row["source"] if row else None


# ---------------------------------------------------------------------------
# Keys
# ---------------------------------------------------------------------------
def new_random_key() -> str:
    return "".join(secrets.choice(KEY_ALPHABET) for _ in range(KEY_LENGTH))


def key_status(row: dict) -> str:
    if row["revoked"]:
        return "revoked"
    if row["banned"] == 1 and (row["ban_until"] is None or now() < row["ban_until"]):
        return "banned"
    if row["expires_at"] is not None and now() >= row["expires_at"]:
        return "expired"
    return "active"


def _key_view(row: dict) -> dict:
    """Adds status + owner identity to a key row.

    get_key/list_keys already JOIN the user's discord_id/display_name into the
    row; rows without the join (generated keys) fetch the owner if bound.
    """
    out = dict(row)
    if "discord_id" not in out and out.get("user_id"):
        owner = db.one(
            "SELECT discord_id, display_name FROM users WHERE id = ?",
            (out["user_id"],),
        )
        if owner:
            out["discord_id"] = owner["discord_id"]
            out["display_name"] = owner["display_name"]
    out.setdefault("discord_id", None)
    out.setdefault("display_name", None)
    out["status"] = key_status(out)
    return out


def generate_keys(count: int, days: int | None = None, product_id: int | None = None,
                  license_id: int | None = None, script_id: int | None = None,
                  note: str | None = None,
                  actor: str = "system") -> list[dict]:
    """Generates `count` keys. days=None/0 keeps the license plan default."""
    if count < 1 or count > 500:
        raise ValueError("count must be 1-500")
    product = get_product(product_id) if product_id else None
    license_row = get_license(license_id) if license_id else None
    resolved_days = days if days else (license_row["days"] if license_row else 0)
    expires_at = now() + resolved_days * 86400 if resolved_days > 0 else None

    created: list[str] = []
    conn = db._db()
    with db._lock:
        for _ in range(count):
            key = None
            for _attempt in range(20):
                candidate = new_random_key()
                exists = conn.execute(
                    "SELECT 1 FROM keys WHERE key = ?", (candidate,)
                ).fetchone()
                if not exists:
                    key = candidate
                    break
            if key is None:
                raise RuntimeError("could not allocate a unique key")
            conn.execute(
                """INSERT INTO keys
                   (key, product_id, license_id, script_id, expires_at, note, created_at)
                   VALUES (?,?,?,?,?,?,?)""",
                (key, product_id if product_id else None,
                 license_id if license_id else None,
                 script_id, expires_at, note or None, now()),
            )
            created.append(key)
        conn.commit()
    audit(actor_kind="dashboard", actor=actor, action="key.generate",
          target=f"{count} keys", detail=f"product={product and product['name']} days={resolved_days}")
    rows = [db.one("SELECT * FROM keys WHERE key = ?", (k,)) for k in created]
    return [_key_view(r) for r in rows]


def get_key(key: str) -> dict | None:
    row = db.one(
        """SELECT k.*, u.discord_id, u.display_name
           FROM keys k LEFT JOIN users u ON u.id = k.user_id
           WHERE k.key = ?""",
        (key.strip(),),
    )
    return row


def list_keys(search: str | None = None, status: str | None = None,
              product_id: int | None = None, limit: int = 50,
              offset: int = 0) -> tuple[list[dict], int]:
    """Pagination-safe key listing: status is filtered in SQL so LIMIT/OFFSET
    and the returned total always agree."""
    ts = now()
    status_expr = (
        "CASE WHEN k.revoked = 1 THEN 'revoked' "
        f"WHEN k.banned = 1 AND (k.ban_until IS NULL OR k.ban_until > {ts}) THEN 'banned' "
        f"WHEN k.expires_at IS NOT NULL AND k.expires_at <= {ts} THEN 'expired' "
        "ELSE 'active' END"
    )
    where, params = [], []
    if search:
        where.append("(k.key LIKE ? OR u.display_name LIKE ? OR "
                     "CAST(u.discord_id AS TEXT) LIKE ? OR k.note LIKE ?)")
        like = f"%{search}%"
        params += [like, like, like, like]
    if product_id:
        where.append("k.product_id = ?")
        params.append(product_id)
    if status:
        where.append(f"({status_expr}) = ?")
        params.append(status)

    base = "FROM keys k LEFT JOIN users u ON u.id = k.user_id"
    where_sql = "WHERE " + " AND ".join(where) + " " if where else ""
    total = int(
        db.scalar(f"SELECT COUNT(*) {base} {where_sql}", params) or 0)
    rows = db.query(
        """SELECT k.*, u.discord_id, u.display_name, ("""
        + status_expr + ") AS status_row "
        + base + " " + where_sql
        + "ORDER BY k.created_at DESC, k.key LIMIT ? OFFSET ?",
        params + [limit, offset],
    )
    views = []
    for r in rows:
        view = _key_view(r)
        view["status"] = r["status_row"]
        views.append(view)
    return views, total


def redeem_key(key: str, discord_id: int, display_name: str | None = None,
               actor: str = "bot") -> tuple[str, dict | None]:
    """Links a key to a Discord user. Codes: ok|not_found|already|taken|banned|expired|revoked."""
    key = key.strip()
    row = get_key(key)
    if row is None:
        return "not_found", None
    if row["user_id"]:
        if row["discord_id"] == discord_id:
            return "already", row
        return "taken", row
    if row["revoked"]:
        return "revoked", row
    st = key_status(row)
    if st == "banned":
        return "banned", row
    if st == "expired":
        return "expired", row

    user_id = get_or_create_user(discord_id, display_name)["id"]
    db.execute(
        "UPDATE keys SET user_id = ?, redeemed_at = ? WHERE key = ?",
        (user_id, now(), key),
    )
    audit(actor, str(discord_id), "key.redeem", target=key)
    return "ok", get_key(key)


def reset_hwid_key(key: str, actor: str = "bot", allow_unredeemed: bool = False) -> tuple[bool, str]:
    """Clear the HWID of one key (counted against MAX_HWID_RESETS)."""
    row = get_key(key)
    if row is None:
        return False, "not_found"
    if not allow_unredeemed and not row["user_id"]:
        return False, "not_redeemed"
    if row["hwid_resets"] >= config.MAX_HWID_RESETS:
        return False, "limit"
    db.execute(
        "UPDATE keys SET hwid = NULL, hwid_resets = hwid_resets + 1 WHERE key = ?",
        (key,),
    )
    audit(actor, (actor or "system"), "key.reset_hwid", target=key)
    return True, "ok"


def extend_key(key: str, days: int, actor: str = "system") -> tuple[bool, int | None]:
    """days > 0 adds days (to the later of now/expiration); days = 0 -> permanent."""
    row = get_key(key)
    if row is None:
        return False, None
    if days <= 0:
        new_exp = None
    else:
        base = max(now(), row["expires_at"] or 0)
        new_exp = base + days * 86400
    db.execute("UPDATE keys SET expires_at = ? WHERE key = ?", (new_exp, key))
    audit(actor, actor, "key.extend", target=key, detail=f"days={days or 'permanent'}")
    return True, new_exp


def revoke_key(key: str, actor: str = "system") -> bool:
    if get_key(key) is None:
        return False
    db.execute("UPDATE keys SET revoked = 1 WHERE key = ?", (key,))
    audit(actor, actor, "key.revoke", target=key)
    return True


def restore_key(key: str, actor: str = "system") -> bool:
    if get_key(key) is None:
        return False
    db.execute("UPDATE keys SET revoked = 0 WHERE key = ?", (key,))
    audit(actor, actor, "key.restore", target=key)
    return True


def set_key_expiration(key: str, expires_at: int | None,
                       actor: str = "system") -> bool:
    """Sets an exact expiration (None = permanent) and re-arms the reminder."""
    if get_key(key) is None:
        return False
    db.execute(
        "UPDATE keys SET expires_at = ?, exp_reminded = 0 WHERE key = ?",
        (expires_at, key),
    )
    audit(actor, actor, "key.set_expiration", target=key,
          detail=f"expires_at={expires_at if expires_at is not None else 'permanent'}")
    return True


def ban_key(key: str, reason: str = "", days: int = 0, actor: str = "system") -> bool:
    if get_key(key) is None:
        return False
    ban_until = now() + days * 86400 if days > 0 else None
    db.execute(
        "UPDATE keys SET banned = 1, ban_reason = ?, ban_until = ? WHERE key = ?",
        (reason or None, ban_until, key),
    )
    audit(actor, actor, "key.ban", target=key, detail=reason)
    return True


def unban_key(key: str, actor: str = "system") -> bool:
    if get_key(key) is None:
        return False
    db.execute(
        "UPDATE keys SET banned = 0, ban_reason = NULL, ban_until = NULL WHERE key = ?",
        (key,),
    )
    audit(actor, actor, "key.unban", target=key)
    return True


def unbind_key(key: str, actor: str = "system") -> bool:
    """Transfer/refund: clears the owner + HWID + reset counter (keeps history)."""
    row = get_key(key)
    if row is None or not row["user_id"]:
        return False
    db.execute(
        """UPDATE keys SET user_id = NULL, redeemed_at = NULL, hwid = NULL,
                  hwid_resets = 0, exp_reminded = 0 WHERE key = ?""",
        (key,),
    )
    audit(actor, actor, "key.unbind", target=key)
    return True


def set_note(key: str, note: str | None, actor: str = "system") -> bool:
    if get_key(key) is None:
        return False
    db.execute("UPDATE keys SET note = ? WHERE key = ?", (note or None, key))
    audit(actor, actor, "key.set_note", target=key)
    return True


def count_keys() -> dict:
    rows = db.query("SELECT * FROM keys")
    out = {"total": len(rows), "active": 0, "redeemed": 0, "expired": 0,
           "revoked": 0, "banned": 0}
    users = {r["id"]: r["discord_id"] for r in db.query("SELECT id, discord_id FROM users")}
    for r in rows:
        st = key_status(r)
        if st in out:
            out[st] += 1
        if r["user_id"]:
            out["redeemed"] += 1
    return out


# ---------------------------------------------------------------------------
# Users
# ---------------------------------------------------------------------------
def get_or_create_user(discord_id: int, display_name: str | None = None,
                       actor: str = "system") -> dict:
    row = db.one("SELECT * FROM users WHERE discord_id = ?", (discord_id,))
    if row:
        if display_name and display_name != row["display_name"]:
            db.execute("UPDATE users SET display_name = ? WHERE id = ?",
                       (display_name, row["id"]))
            return db.one("SELECT * FROM users WHERE id = ?", (row["id"],))
        return row
    uid = db.execute(
        "INSERT INTO users (discord_id, display_name, role, created_at)"
        " VALUES (?,?, 'buyer', ?)",
        (discord_id, display_name, now()),
    )
    return db.one("SELECT * FROM users WHERE id = ?", (uid,))


def list_users(search: str | None = None, limit: int = 50, offset: int = 0) -> tuple[list[dict], int]:
    where, params = [], []
    if search:
        where.append("(u.display_name LIKE ? OR CAST(u.discord_id AS TEXT) LIKE ?)")
        like = f"%{search}%"
        params += [like, like]
    rows = db.query(
        """SELECT u.*,
                  COUNT(k.key) AS total_keys,
                  SUM(CASE WHEN k.revoked = 0 THEN 1 ELSE 0 END) AS active_keys
           FROM users u LEFT JOIN keys k ON k.user_id = u.id
           """ + ("WHERE " + " AND ".join(where) + " " if where else "")
        + " GROUP BY u.id ORDER BY u.created_at DESC LIMIT ? OFFSET ?",
        params + [limit, offset],
    )
    total = db.scalar("SELECT COUNT(*) FROM users u "
                      + ("WHERE " + " AND ".join(where) + " " if where else ""), params) or 0
    return rows, int(total)


def get_user(user_id: int) -> dict | None:
    return db.one("SELECT * FROM users WHERE id = ?", (user_id,))


def user_by_discord(discord_id: int) -> dict | None:
    return db.one("SELECT * FROM users WHERE discord_id = ?", (discord_id,))


def user_keys(user_id: int) -> list[dict]:
    rows = db.query("SELECT * FROM keys WHERE user_id = ? ORDER BY redeemed_at DESC", (user_id,))
    return [_key_view(r) for r in rows]


def user_events(user_id: int, limit: int = 50) -> list[dict]:
    user = get_user(user_id)
    if not user or not user["discord_id"]:
        return []
    return db.query(
        "SELECT * FROM auth_events WHERE discord_id = ? ORDER BY ts DESC LIMIT ?",
        (user["discord_id"], limit),
    )


def update_user(user_id: int, actor: str = "system", **fields) -> dict | None:
    allowed = ("display_name", "role", "banned", "ban_reason", "notes", "roblox_id")
    sets, params = [], []
    for field in allowed:
        if field in fields and fields[field] is not None:
            sets.append(f"{field} = ?")
            params.append(fields[field])
    if sets:
        if get_user(user_id) is None:
            return None
        params.append(user_id)
        db.execute(f"UPDATE users SET {', '.join(sets)} WHERE id = ?", params)
        audit(actor, actor, "user.update", target=str(user_id))
    return get_user(user_id)


def ban_user(discord_id: int, reason: str = "", days: int = 0, actor: str = "bot") -> bool:
    user = user_by_discord(discord_id)
    if user is None:
        return False
    ban_until = now() + days * 86400 if days > 0 else None
    db.execute("UPDATE users SET banned = 1, ban_reason = ? WHERE id = ?",
               (reason or None, user["id"]))
    rows = db.query("SELECT key FROM keys WHERE user_id = ?", (user["id"],))
    for r in rows:
        db.execute(
            "UPDATE keys SET banned = 1, ban_reason = ?, ban_until = ? WHERE key = ?",
            (reason or None, ban_until, r["key"]),
        )
    audit(actor, str(discord_id), "user.ban", detail=reason)
    return True


def unban_user(discord_id: int, actor: str = "bot") -> bool:
    user = user_by_discord(discord_id)
    if user is None:
        return False
    db.execute("UPDATE users SET banned = 0, ban_reason = NULL WHERE id = ?", (user["id"],))
    db.execute(
        """UPDATE keys SET banned = 0, ban_reason = NULL, ban_until = NULL
           WHERE user_id = ?""",
        (user["id"],),
    )
    audit(actor, str(discord_id), "user.unban")
    return True


def list_buyer_ids() -> list[int]:
    return [r["discord_id"] for r in db.query(
        """SELECT DISTINCT u.discord_id FROM users u
           JOIN keys k ON k.user_id = u.id
           WHERE u.discord_id IS NOT NULL"""
    )]


# ---------------------------------------------------------------------------
# Execution validation (called by the loader API - never the client)
# ---------------------------------------------------------------------------
# A real HWID is a long unique ID (executor gethwid() hashes, Roblox client
# ids...). Executor names ("Synapse X", "Wave") are not one: everyone running
# the same executor would share the same "PC". Mirrors the legacy bot rule.
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


def validate_execution(key: str, hwid: str, place_id: int | None = None,
                       loader_version: str | None = None,
                       kind: str = "execute",
                       ip: str | None = None,
                       game_id: int | None = None) -> tuple[bool, str | None, dict | None, dict | None]:
    """
    Single source of truth for granting access.

    Returns (allowed, refusal_reason, key_row, script).
    Rules: exists -> not revoked -> not banned -> not expired -> redeemed ->
           hwid bound (when a hwid was provided) -> product/script enabled ->
           game match (place_id, when provided) -> autokick gates for rechecks.
    """
    key = (key or "").strip()
    hwid = (hwid or "").strip()[:128]

    def deny(reason: str, krow: dict | None, script_row: dict | None = None,
              event_kind: str | None = None):
        game = game_for_place(place_id, game_id)
        log_event(event_kind or kind, result="denied", reason=reason, key=key,
                  discord_id=(krow or {}).get("discord_id"), hwid=hwid, ip=ip,
                  script_id=(script_row or {}).get("id"),
                  game_id=game["id"] if game else None)
        return False, reason, krow, script_row

    row = get_key(key)
    if row is None:
        return deny("Invalid or unknown key.", None)

    script = get_script(row["script_id"]) if row["script_id"] else None
    if script is None and row["product_id"]:
        # resolve the script through the key's product (game-aware)
        candidates = db.query(
            "SELECT * FROM scripts WHERE product_id = ? AND enabled = 1 ORDER BY id",
            (row["product_id"],),
        )
        if place_id or game_id:
            for cand in candidates:
                g = get_game(cand["game_id"]) if cand["game_id"] else None
                if not g:
                    continue
                ids = game_place_ids(g)
                if (place_id and place_id in ids) or (game_id and game_id in ids):
                    script = cand
                    break
        elif len(candidates) == 1:
            script = candidates[0]

    if row["revoked"]:
        return deny("This key has been revoked.", row, script, "autokick_denied" if kind == "heartbeat" else kind)
    st = key_status(row)
    if st == "banned":
        return deny("This key has been banned." + (f" ({row['ban_reason']})" if row["ban_reason"] else ""), row, script, "autokick_denied" if kind == "heartbeat" else kind)
    if st == "expired":
        return deny("This key has expired.", row, script, "autokick_denied" if kind == "heartbeat" else kind)
    if not row["user_id"]:
        return deny("This key has not been redeemed on Discord yet.", row, script)
    user = get_user(row["user_id"])
    if user and user.get("banned"):
        return deny("This account is banned from the service.", row, script,
                    "autokick_denied" if kind == "heartbeat" else kind)

    # HWID
    stored = (row["hwid"] or "").strip()
    if hwid:
        weak = hwid_problem(hwid)
        if weak:
            return deny(weak, row, script,
                        "autokick_denied" if kind == "heartbeat" else kind)
        if stored and hwid_problem(stored):
            # registered before HWIDs were validated (e.g. executor name):
            # upgrade it to the real one instead of locking the buyer out
            stored = ""
    if hwid and stored and hwid != stored:
        return deny(
            "This HWID does not match the registered one. "
            "Reset your HWID from the Discord panel or restore this PC.",
            row, script,
        )

    if script is not None:
        if not script["enabled"]:
            return deny("This script is disabled by the staff.", row, script)
        if script["game_id"]:
            game = get_game(script["game_id"])
            if game and (place_id or game_id):
                allowed_places = game_place_ids(game)
                if (allowed_places
                        and place_id not in allowed_places
                        and game_id not in allowed_places):
                    return deny("This game is not supported for your key.", row, script)

    # bind HWID on first use
    ts = now()
    if hwid and not stored:
        db.execute(
            """UPDATE keys SET hwid = ?, executions = executions + 1,
               first_exec = COALESCE(first_exec, ?), last_exec = ? WHERE key = ?""",
            (hwid, ts, ts, key),
        )
    elif kind == "execute" or kind == "heartbeat":
        db.execute(
            """UPDATE keys SET executions = executions + 1,
               first_exec = COALESCE(first_exec, ?), last_exec = ? WHERE key = ?""",
            (ts, ts, key),
        )

    log_event(kind, result="ok", key=key, discord_id=row["discord_id"], hwid=hwid,
              ip=ip, script_id=script and script["id"],
              game_id=game_for_place(place_id, game_id)["id"] if game_for_place(place_id, game_id) else None,
              detail=f"loader={loader_version or '-'}")
    return True, None, get_key(key), script


# ---------------------------------------------------------------------------
# Sales
# ---------------------------------------------------------------------------
def record_sale(buyer: str, discord_id: int | None = None, game: str | None = None,
                product: str | None = None, amount_cents: int = 0,
                status: str = "paid", note: str | None = None,
                actor: str = "bot") -> dict:
    sid = db.execute(
        """INSERT INTO sales (created_at, buyer, discord_id, game, product,
                              amount_cents, status, note)
           VALUES (?,?,?,?,?,?,?,?)""",
        (now(), buyer, str(discord_id) if discord_id else None, game, product,
         amount_cents, status, note),
    )
    audit(actor, str(discord_id or ""), "sale.record", target=product or "")
    return db.one("SELECT * FROM sales WHERE id = ?", (sid,))


def list_sales(limit: int = 200) -> list[dict]:
    return db.query("SELECT * FROM sales ORDER BY created_at DESC LIMIT ?", (limit,))


def sales_stats(days: int = 30) -> dict:
    since = now() - days * 86400
    total_revenue = db.scalar("SELECT COALESCE(SUM(amount_cents),0) FROM sales WHERE status='paid'") or 0
    rev30 = db.scalar(
        "SELECT COALESCE(SUM(amount_cents),0) FROM sales WHERE status='paid' AND created_at >= ?",
        (since,),
    ) or 0
    count = db.scalar("SELECT COUNT(*) FROM sales") or 0
    buyers = db.scalar("SELECT COUNT(DISTINCT COALESCE(discord_id, buyer)) FROM sales") or 0
    return {"revenue_total_cents": int(total_revenue), "revenue_30d_cents": int(rev30),
            "count": int(count), "buyers": int(buyers)}


# ---------------------------------------------------------------------------
# Overview (dashboard home)
# ---------------------------------------------------------------------------
def overview() -> dict:
    keys = count_keys()
    users_total = db.scalar("SELECT COUNT(*) FROM users") or 0
    scripts_all = db.query("SELECT * FROM scripts")
    games_all = list_games()
    events = event_counts(days=7)
    return {
        "users": int(users_total),
        "keys": keys,
        "scripts": {
            "total": len(scripts_all),
            "enabled": sum(1 for s in scripts_all if s["enabled"]),
            "versions": db.scalar("SELECT COUNT(*) FROM script_versions") or 0,
        },
        "games": {"total": len(games_all), "active": sum(1 for g in games_all if g["active"])},
        "api": {"uptime_seconds": uptime_seconds(), "events_7d": events},
        "sales": sales_stats(30),
        "recent": recent_events(limit=10),
        "audit": recent_audit(limit=10),
    }


# ---------------------------------------------------------------------------
# Expiration reminders (bot DMs)
# ---------------------------------------------------------------------------
def due_expiration_reminders() -> list[dict]:
    limit = now() + 86400
    return db.query(
        """SELECT k.*, u.discord_id FROM keys k JOIN users u ON u.id = k.user_id
           WHERE k.expires_at IS NOT NULL AND k.expires_at > ?
             AND k.expires_at <= ? AND k.exp_reminded = 0 AND k.revoked = 0""",
        (now(), limit),
    )


def mark_expiration_reminded(key: str) -> None:
    db.execute("UPDATE keys SET exp_reminded = 1 WHERE key = ?", (key,))


# ---------------------------------------------------------------------------
# Backups
# ---------------------------------------------------------------------------
def backup(dest_dir: str) -> str:
    os.makedirs(dest_dir, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    dest_path = os.path.join(dest_dir, f"aero-{stamp}.db")
    dest = sqlite3.connect(dest_path)
    try:
        db._db().backup(dest)
    finally:
        dest.close()
    return dest_path


def prune_backups(dest_dir: str, keep: int = 7) -> None:
    if not os.path.isdir(dest_dir):
        return
    files = sorted(
        os.path.join(dest_dir, name)
        for name in os.listdir(dest_dir)
        if name.startswith("aero-") and name.endswith(".db")
    )
    for old in files[:-keep] if keep > 0 else []:
        try:
            os.remove(old)
        except OSError:
            pass


# ---------------------------------------------------------------------------
# Dashboard auth
# ---------------------------------------------------------------------------
def bootstrap_admin() -> dict | None:
    """Creates the first owner account from config when the table is empty."""
    count = db.scalar("SELECT COUNT(*) FROM dashboard_users") or 0
    if int(count) > 0:
        return None
    uid = db.execute(
        """INSERT INTO dashboard_users
           (email, password_hash, role, must_change, created_at)
           VALUES (?,?, 'owner', 1, ?)""",
        (config.AERO_ADMIN_EMAIL, security.hash_password(config.AERO_ADMIN_PASSWORD), now()),
    )
    audit("system", "bootstrap", "dash.user.create", target=config.AERO_ADMIN_EMAIL)
    return db.one("SELECT * FROM dashboard_users WHERE id = ?", (uid,))


def dashboard_login(email: str, password: str, ip: str | None = None) -> dict | None:
    row = db.one("SELECT * FROM dashboard_users WHERE email = ?",
                 (email.strip().lower(),))
    if row is None:
        return None
    if not security.verify_password(password, row["password_hash"]):
        log_event("dash_login_failed", ip=ip, detail=email)
        return None
    db.execute("UPDATE dashboard_users SET last_login = ? WHERE id = ?", (now(), row["id"]))
    log_event("dash_login", result="ok", ip=ip, detail=email)
    return row


def create_session(user_id: int, ip: str | None = None) -> tuple[str, int]:
    session_id = security.new_session_id()
    expires_at = now() + config.SESSION_TTL_HOURS * 3600
    db.execute(
        """INSERT INTO dashboard_sessions (id, user_id, created_at, expires_at, ip)
           VALUES (?,?,?,?,?)""",
        (security.hash_session_id(session_id), user_id, now(), expires_at, ip),
    )
    return session_id, expires_at


def session_user(session_id: str) -> dict | None:
    if not session_id:
        return None
    row = db.one(
        "SELECT s.*, u.email, u.role, u.must_change FROM dashboard_sessions s"
        " JOIN dashboard_users u ON u.id = s.user_id WHERE s.id = ?",
        (security.hash_session_id(session_id),),
    )
    if row is None or row["expires_at"] < now():
        if row:
            db.execute("DELETE FROM dashboard_sessions WHERE id = ?", (row["id"],))
        return None
    return {"id": row["user_id"], "email": row["email"], "role": row["role"],
            "must_change": row["must_change"]}


def destroy_session(session_id: str) -> None:
    db.execute("DELETE FROM dashboard_sessions WHERE id = ?",
               (security.hash_session_id(session_id),))


def change_password(user_id: int, old_password: str | None, new_password: str) -> bool:
    row = db.one("SELECT * FROM dashboard_users WHERE id = ?", (user_id,))
    if row is None:
        return False
    if old_password is not None and not security.verify_password(old_password, row["password_hash"]):
        return False
    if len(new_password) < 8:
        return False
    db.execute(
        "UPDATE dashboard_users SET password_hash = ?, must_change = 0 WHERE id = ?",
        (security.hash_password(new_password), user_id),
    )
    audit("dashboard", row["email"], "dash.password_change")
    return True


def list_dashboard_users() -> list[dict]:
    return db.query(
        """SELECT id, email, role, must_change, created_at, last_login
           FROM dashboard_users ORDER BY created_at"""
    )


# ---------------------------------------------------------------------------
# API tokens
# ---------------------------------------------------------------------------
def create_api_token(name: str, role: str, created_by: str) -> tuple[dict, str]:
    token = security.new_api_token()
    tid = db.execute(
        """INSERT INTO api_tokens (name, token_prefix, token_hash, role, created_by, created_at)
           VALUES (?,?,?,?,?,?)""",
        (name, security.token_prefix(token), security.token_hash(token), role, created_by, now()),
    )
    audit("dashboard", created_by, "token.create", target=name)
    return db.one("SELECT * FROM api_tokens WHERE id = ?", (tid,)), token


def verify_api_token(token: str) -> dict | None:
    if not token or not token.startswith("aero_"):
        return None
    row = db.one(
        "SELECT * FROM api_tokens WHERE token_hash = ? AND revoked = 0",
        (security.token_hash(token),),
    )
    if row is None:
        return None
    db.execute("UPDATE api_tokens SET last_used = ? WHERE id = ?", (now(), row["id"]))
    return row


def revoke_api_token(token_id: int, actor: str) -> bool:
    row = db.one("SELECT * FROM api_tokens WHERE id = ?", (token_id,))
    if row is None:
        return False
    db.execute("UPDATE api_tokens SET revoked = 1 WHERE id = ?", (token_id,))
    audit("dashboard", actor, "token.revoke", target=row["name"])
    return True


def list_api_tokens() -> list[dict]:
    return db.query(
        """SELECT id, name, token_prefix, role, created_by, created_at,
                  last_used, revoked FROM api_tokens ORDER BY created_at DESC"""
    )


# ---------------------------------------------------------------------------
# Embed templates (bot embed builder)
# ---------------------------------------------------------------------------
def list_embeds() -> list[dict]:
    return db.query(
        """SELECT id, name, created_by, created_at, updated_at FROM embed_templates
           ORDER BY updated_at DESC"""
    )


def get_embed(template_id: int) -> dict | None:
    return db.one("SELECT * FROM embed_templates WHERE id = ?", (template_id,))


def save_embed(name: str, data: str, created_by: str = "bot",
               template_id: int | None = None) -> dict:
    now_ts = now()
    if template_id:
        row = get_embed(template_id)
        if row is None:
            raise ValueError("template not found")
        db.execute(
            "UPDATE embed_templates SET name = ?, data = ?, updated_at = ? WHERE id = ?",
            (name, data, now_ts, template_id),
        )
    else:
        existing = db.one("SELECT id FROM embed_templates WHERE name = ?", (name,))
        if existing:
            db.execute(
                "UPDATE embed_templates SET data = ?, updated_at = ?, created_by = ? WHERE id = ?",
                (data, now_ts, created_by, existing["id"]),
            )
        else:
            template_id = db.execute(
                "INSERT INTO embed_templates (name, data, created_by, created_at, updated_at)"
                " VALUES (?,?,?,?,?)",
                (name, data, created_by, now_ts, now_ts),
            )
    audit("bot", created_by, "embed.save", target=name)
    return get_embed(template_id)


def delete_embed(template_id: int, actor: str = "bot") -> bool:
    row = get_embed(template_id)
    if row is None:
        return False
    db.execute("DELETE FROM embed_templates WHERE id = ?", (template_id,))
    audit("bot", actor, "embed.delete", target=row["name"])
    return True


# ---------------------------------------------------------------------------
# Languages (bot EN/PT/ES)
# ---------------------------------------------------------------------------
VALID_LANGS = ("en", "pt", "es")


def get_lang(discord_id: int) -> str:
    row = db.one("SELECT lang FROM lang_prefs WHERE discord_id = ?", (discord_id,))
    return row["lang"] if row else "en"


def set_lang(discord_id: int, lang: str) -> str:
    if lang not in VALID_LANGS:
        raise ValueError("unsupported language")
    db.execute(
        """INSERT INTO lang_prefs (discord_id, lang, updated_at) VALUES (?,?,?)
           ON CONFLICT(discord_id) DO UPDATE SET lang = excluded.lang,
           updated_at = excluded.updated_at""",
        (discord_id, lang, now()),
    )
    return lang


def fmt_date(ts: int | None) -> str:
    if not ts:
        return "Never"
    return datetime.fromtimestamp(ts, tz=timezone.utc).strftime("%d/%m/%Y %H:%M UTC")
