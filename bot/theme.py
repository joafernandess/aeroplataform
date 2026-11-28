"""
Aero look: brand colors + emojis.

Emojis come from YOUR server when they exist. For every slot below the bot
looks for a server emoji named  aero_<slot>  (e.g. aero_success, aero_key,
aero_shield). Upload emojis with those names and the bot uses them
everywhere: embeds, panels and buttons. Missing ones fall back to the
standard emoji in DEFAULTS.

You can also point a slot at any emoji in .env:
    EMOJI_SUCCESS=<:check:123456789012345678>
    EMOJI_PREFIX=aero_          (change the name prefix the bot looks for)

load() runs once at startup (setup_hook), before the panels are built, so
buttons get the custom emojis too.
"""
from __future__ import annotations

import logging
import os

import discord

log = logging.getLogger("keybot.theme")

# Brand palette (from the Aero logo / dashboard)
AERO = 0x8FA2F9        # main periwinkle
AERO_DEEP = 0x6F86F3   # deeper accent
SUCCESS = 0x6EE7B7     # mint
ERROR = 0xF47185       # rose
WARNING = 0xF5C46B     # amber
DARK = 0x0B0B16        # panel background

BRAND = "Aero"

DEFAULTS: dict[str, str] = {
    "aero": "✦",
    "success": "✅",
    "error": "⛔",
    "warning": "⚠️",
    "info": "💠",
    "key": "🔑",
    "redeem": "🎫",
    "script": "📜",
    "role": "🎖️",
    "hwid": "🔄",
    "stats": "📊",
    "language": "🌐",
    "shield": "🛡️",
    "user": "👤",
    "server": "🌍",
    "device": "💻",
    "game": "🎮",
    "shop": "🛒",
    "howto": "📖",
    "pix": "💳",
    "paypal": "🅿️",
    "money": "💸",
    "paid": "🧾",
    "close": "🔒",
    "coupon": "🏷️",
    "ban": "🔨",
    "revoke": "🚫",
    "online": "🟢",
    "updating": "🟡",
    "offline": "🔴",
    "power": "🔌",
    "log": "📒",
    "rocket": "🚀",
    "clock": "⏳",
    "link": "🔗",
}

_resolved: dict[str, str] = {}


def _prefix() -> str:
    return os.environ.get("EMOJI_PREFIX", "aero_").strip() or "aero_"


def load(emojis: list[discord.Emoji]) -> int:
    """Maps slots to server emojis named <prefix><slot>. Returns how many."""
    by_name = {e.name.lower(): e for e in emojis if e.available}
    _resolved.clear()
    prefix = _prefix().lower()
    for slot in DEFAULTS:
        override = os.environ.get(f"EMOJI_{slot.upper()}", "").strip()
        if override:
            _resolved[slot] = override
            continue
        found = by_name.get(f"{prefix}{slot}")
        if found is not None:
            _resolved[slot] = str(found)
    log.info("Theme: %d custom emoji(s) in use", len(_resolved))
    return len(_resolved)


def e(slot: str) -> str:
    """Emoji text for a slot (server emoji when available)."""
    return _resolved.get(slot) or DEFAULTS.get(slot, "")


def pe(slot: str) -> discord.PartialEmoji:
    """Emoji for buttons / select options."""
    return discord.PartialEmoji.from_str(e(slot))


def skin(view: discord.ui.View, mapping: dict[str, str]) -> discord.ui.View:
    """Sets button emojis by custom_id ({custom_id: slot})."""
    for item in view.children:
        cid = getattr(item, "custom_id", None)
        if cid in mapping and hasattr(item, "emoji"):
            item.emoji = pe(mapping[cid])
    return view


def titled(slot: str, title: str) -> str:
    """'<emoji> Title' unless the title already starts with an emoji."""
    if not title:
        return e(slot)
    first = title[0]
    if first.isalnum() or first in "\"'(":
        return f"{e(slot)} {title}"
    return title


def footer(embed: discord.Embed, section: str | None = None) -> discord.Embed:
    """Brand footer (kept when the embed already has one)."""
    if not embed.footer.text:
        embed.set_footer(text=f"{BRAND} • {section}" if section else BRAND)
    return embed


def divider() -> str:
    return "▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬"
