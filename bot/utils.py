"""
Shared utilities: colored-bar embeds (video style) and time formatting.
"""
import re
import time

import discord
from discord import app_commands

import config
import theme

_PRICE_RE = re.compile(r"[\d]+(?:[.,]\d+)?")

GREEN = theme.SUCCESS
RED = theme.ERROR
ORANGE = theme.WARNING
BLUE = theme.AERO


def admin_only():
    """
    Decorator for slash commands restricted to the ADMIN_ROLE_ID role.
    The failure becomes an ephemeral embed in the bot's error handler.
    """

    async def predicate(interaction: discord.Interaction) -> bool:
        if not config.ADMIN_ROLE_ID:
            raise app_commands.CheckFailure(
                "ADMIN_ROLE_ID is not configured in the .env file."
            )
        roles = getattr(interaction.user, "roles", [])
        if any(role.id == config.ADMIN_ROLE_ID for role in roles):
            return True
        raise app_commands.CheckFailure(
            "Only administrators can use this command."
        )

    return app_commands.check(predicate)


def staff_only():
    """
    Decorator for slash commands restricted to the STAFF or ADMIN role.
    Staff level: /genkey /keyinfo /userinfo /listkeys /setnote /deliver
    """

    async def predicate(interaction: discord.Interaction) -> bool:
        if not config.ADMIN_ROLE_ID:
            raise app_commands.CheckFailure(
                "ADMIN_ROLE_ID is not configured in the .env file."
            )
        roles = getattr(interaction.user, "roles", [])
        ids = {role.id for role in roles}
        if config.ADMIN_ROLE_ID in ids:
            return True
        if config.STAFF_ROLE_ID and config.STAFF_ROLE_ID in ids:
            return True
        raise app_commands.CheckFailure(
            "Only staff or administrators can use this command."
        )

    return app_commands.check(predicate)


def success_embed(title: str = "Success!", description: str = "") -> discord.Embed:
    """Green-mint card for confirmations (Aero theme)."""
    embed = discord.Embed(
        title=theme.titled("success", title), description=description, color=theme.SUCCESS
    )
    return theme.footer(embed)


def error_embed(title: str, description: str = "") -> discord.Embed:
    """Rose card for errors and security events (Aero theme)."""
    embed = discord.Embed(
        title=theme.titled("error", title), description=description, color=theme.ERROR
    )
    return theme.footer(embed)


def warning_embed(title: str, description: str = "") -> discord.Embed:
    embed = discord.Embed(
        title=theme.titled("warning", title), description=description, color=theme.WARNING
    )
    return theme.footer(embed)


def info_embed(title: str, description: str = "") -> discord.Embed:
    """Aero-blue card for information."""
    embed = discord.Embed(
        title=theme.titled("info", title), description=description, color=theme.AERO
    )
    return theme.footer(embed)


def price_to_cents(price: str | None) -> int:
    """
    'shop.json' stores a display price like "$9.00". Pulls the first
    number out of it for the Aero Platform's sales ledger (USD cents).
    '-', empty or unparseable -> 0 (the sale is still recorded, just
    with no amount, instead of not recording it at all).
    """
    m = _PRICE_RE.search(str(price or ""))
    if not m:
        return 0
    try:
        return round(float(m.group(0).replace(",", ".")) * 100)
    except ValueError:
        return 0


def mask_key(key: str | None) -> str:
    """Shortened key for logs, so a log channel never holds full keys."""
    if not key:
        return "-"
    return f"{key[:8]}…"


def ago(ts: int | None) -> str:
    """Formats a timestamp as 'X ... ago' (or 'Never')."""
    if not ts:
        return "Never"
    delta = int(time.time()) - ts
    if delta < 0:
        return "Soon"
    if delta < 5:
        return "just now"
    if delta < 60:
        return f"{delta} seconds ago"
    if delta < 3600:
        minutes = delta // 60
        return f"{minutes} minute" + ("s" if minutes > 1 else "") + " ago"
    if delta < 86400:
        hours = delta // 3600
        return f"{hours} hour" + ("s" if hours > 1 else "") + " ago"
    days = delta // 86400
    return f"{days} day" + ("s" if days > 1 else "") + " ago"
