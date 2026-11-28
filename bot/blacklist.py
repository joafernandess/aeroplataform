"""
Blacklist of identities that survive a new key: HWID, Roblox account and IP.

A ban on the platform blocks a Discord user and their keys. A banned person
who buys another key with an alt would be back, so when staff bans someone
(button on an alert, /ban, or a ban from the Discord server) the HWIDs and
Roblox accounts seen on their key are blacklisted too. When any key later
runs with a blacklisted HWID or Roblox account, the execution log bans that
key automatically (BLACKLIST_AUTO_BAN) and alerts the staff.

IPs are alert-only: many people can share one IP (mobile carriers, families).

Stored in the bot's kv table:
  bl:<type>:<value>  -> {"reason", "by", "ts", "key"}
  bl:index           -> [[type, value], ...]  (for /blacklist list)
"""
from __future__ import annotations

import time

import catalog

TYPES = ("hwid", "roblox", "ip")
_INDEX = "bl:index"


def _slot(kind: str, value: str) -> str:
    return f"bl:{kind}:{str(value).strip()}"


def get(kind: str, value) -> dict | None:
    if value in (None, "", 0):
        return None
    found = catalog.get_kv(_slot(kind, value))
    return found[0] if found and isinstance(found[0], dict) else None


def add(kind: str, value, reason: str, by: str, key: str | None = None) -> bool:
    """Adds an entry. False when it was already there."""
    if kind not in TYPES or value in (None, "", 0):
        return False
    value = str(value).strip()
    if get(kind, value) is not None:
        return False
    catalog.set_kv(_slot(kind, value), {
        "reason": reason[:200], "by": by[:100], "ts": int(time.time()), "key": key,
    })
    index = (catalog.get_kv(_INDEX) or [[]])[0] or []
    if [kind, value] not in index:
        index.append([kind, value])
    catalog.set_kv(_INDEX, index[-2000:])
    return True


def remove(kind: str, value) -> bool:
    value = str(value).strip()
    if get(kind, value) is None:
        return False
    catalog.del_kv(_slot(kind, value))
    index = (catalog.get_kv(_INDEX) or [[]])[0] or []
    catalog.set_kv(_INDEX, [e for e in index if e != [kind, value]])
    return True


def entries() -> list[tuple[str, str, dict]]:
    index = (catalog.get_kv(_INDEX) or [[]])[0] or []
    out = []
    for kind, value in index:
        info = get(kind, value)
        if info is not None:
            out.append((kind, value, info))
    return out


def seen_hwids(key: str) -> list[str]:
    found = catalog.get_kv(f"exec_hwid:{key}")
    return list(found[0]) if found and isinstance(found[0], list) else []


def seen_roblox(key: str) -> list[int]:
    found = catalog.get_kv(f"exec_rbx:{key}")
    return list(found[0]) if found and isinstance(found[0], list) else []


def remember_hwid(key: str, hwid: str) -> None:
    if not key or not hwid:
        return
    seen = seen_hwids(key)
    if hwid not in seen:
        catalog.set_kv(f"exec_hwid:{key}", (seen + [hwid])[-10:])


def add_key_identity(key: str, reason: str, by: str, extra_hwid: str | None = None) -> int:
    """Blacklists every HWID / Roblox account seen on `key`. Returns how many."""
    added = 0
    hwids = seen_hwids(key)
    if extra_hwid and extra_hwid not in hwids:
        hwids.append(extra_hwid)
    for hwid in hwids:
        added += add("hwid", hwid, reason, by, key)
    for rbx in seen_roblox(key):
        added += add("roblox", rbx, reason, by, key)
    return added


def match(ev: dict) -> list[tuple[str, str, dict]]:
    """Blacklist entries hit by one execution event."""
    hits = []
    tel = ev.get("telemetry") or {}
    for kind, value in (
        ("hwid", ev.get("hwid")),
        ("roblox", tel.get("user_id")),
        ("ip", ev.get("ip")),
    ):
        info = get(kind, value)
        if info is not None:
            hits.append((kind, str(value), info))
    return hits
