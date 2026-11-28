"""
Keeps the @Buyer role honest.

The role is granted by the "Get Role" button. Nothing used to take it back, so
a buyer kept the buyer channels after the key expired, was revoked, disabled
or banned. sync_buyer_roles() removes it from every user who has no usable key
left. It runs every ROLE_SYNC_MINUTES and is safe to run repeatedly:

  - a user is processed once; the result is remembered in the kv table
    (role_removed:<id>) so expired users are not re-fetched forever
  - when the user gets a usable key again (renewal) the memory is cleared, so
    the next expiry removes the role again
  - a failure (missing permission, API error) is not remembered, so it is
    retried on the next run
"""
import asyncio
import logging

import discord

import catalog
import config
import platform_bridge as db
import logger
from utils import info_embed

log = logging.getLogger("keybot.roles")

_PAUSE = 1.0  # seconds between Discord calls (stay far from rate limits)


def _flag(user_id: int) -> str:
    return f"role_removed:{user_id}"


async def sync_buyer_roles(bot: discord.Client, pause: float = _PAUSE) -> int:
    """Removes the buyer role from users without a usable key. Returns removals."""
    if not config.BUYER_ROLE_ID:
        return 0
    guilds = [
        g for g in bot.guilds
        if not config.GUILD_ID or g.id == config.GUILD_ID
    ]
    access = await asyncio.to_thread(db.access_by_user)
    removed = 0

    for user_id, has_access in access.items():
        flagged = await asyncio.to_thread(catalog.get_kv, _flag(user_id)) is not None
        if has_access:
            if flagged:
                await asyncio.to_thread(catalog.del_kv, _flag(user_id))
            continue
        if flagged:
            continue

        done = True
        for guild in guilds:
            role = guild.get_role(config.BUYER_ROLE_ID)
            if role is None:
                continue
            member = guild.get_member(user_id)
            try:
                if member is None:
                    member = await guild.fetch_member(user_id)
            except discord.NotFound:
                continue  # left the server: nothing to remove
            except discord.HTTPException as exc:
                log.warning("Could not look up %s in %s: %s", user_id, guild.id, exc)
                done = False
                continue
            if role not in member.roles:
                continue
            try:
                await member.remove_roles(role, reason="Key expired / revoked / disabled")
            except discord.Forbidden:
                log.warning(
                    "Missing permission to remove the buyer role from %s "
                    "(the bot's role must be above it)", user_id,
                )
                done = False
                continue
            except discord.HTTPException as exc:
                log.warning("Could not remove the buyer role from %s: %s", user_id, exc)
                done = False
                continue
            removed += 1
            logger.log_event(
                info_embed(
                    "Buyer role removed",
                    f"User: <@{user_id}>\nReason: no usable key "
                    "(expired, revoked, disabled or banned).",
                )
            )
            await asyncio.sleep(pause)

        if done:
            await asyncio.to_thread(catalog.set_kv, _flag(user_id), True)

    return removed


async def grant_buyer_role(bot: discord.Client, user_id: int) -> bool:
    """Gives the buyer role back (after a renewal). Best effort."""
    if not config.BUYER_ROLE_ID:
        return False
    for guild in bot.guilds:
        if config.GUILD_ID and guild.id != config.GUILD_ID:
            continue
        role = guild.get_role(config.BUYER_ROLE_ID)
        if role is None:
            continue
        try:
            member = guild.get_member(user_id) or await guild.fetch_member(user_id)
            if role not in member.roles:
                await member.add_roles(role, reason="Key renewed")
            await asyncio.to_thread(catalog.del_kv, _flag(user_id))
            return True
        except discord.HTTPException as exc:
            log.warning("Could not grant the buyer role to %s: %s", user_id, exc)
    return False



async def give_buyer_role(member: discord.abc.User, reason: str) -> str:
    """
    Gives the buyer role to a guild member right away (used on redeem).
    Returns "granted", "already", "missing" (role not configured / not in
    this server), "forbidden" (bot role below the buyer role) or "error".
    """
    if not config.BUYER_ROLE_ID or not isinstance(member, discord.Member):
        return "missing"
    role = member.guild.get_role(config.BUYER_ROLE_ID)
    if role is None:
        return "missing"
    if role in member.roles:
        await asyncio.to_thread(catalog.del_kv, _flag(member.id))
        return "already"
    try:
        await member.add_roles(role, reason=reason)
    except discord.Forbidden:
        log.warning(
            "Missing permission to give the buyer role to %s "
            "(the bot's role must be above it and have Manage Roles)", member.id,
        )
        return "forbidden"
    except discord.HTTPException as exc:
        log.warning("Could not give the buyer role to %s: %s", member.id, exc)
        return "error"
    await asyncio.to_thread(catalog.del_kv, _flag(member.id))
    return "granted"


async def remove_buyer_role(bot: discord.Client, user_id: int, reason: str) -> bool:
    """
    Takes the buyer role away immediately (ban / unlink), instead of waiting
    for the next sync_buyer_roles run. Best effort; True when removed.
    """
    if not config.BUYER_ROLE_ID:
        return False
    removed = False
    for guild in bot.guilds:
        if config.GUILD_ID and guild.id != config.GUILD_ID:
            continue
        role = guild.get_role(config.BUYER_ROLE_ID)
        if role is None:
            continue
        try:
            member = guild.get_member(user_id) or await guild.fetch_member(user_id)
        except discord.HTTPException:
            continue
        if role not in member.roles:
            continue
        try:
            await member.remove_roles(role, reason=reason)
            removed = True
        except discord.HTTPException as exc:
            log.warning("Could not remove the buyer role from %s: %s", user_id, exc)
    if removed:
        await asyncio.to_thread(catalog.set_kv, _flag(user_id), True)
        logger.log_event(
            info_embed("Buyer role removed", f"User: <@{user_id}>\nReason: {reason}")
        )
    return removed
