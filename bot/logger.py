"""
Fire-and-forget logging to Discord channels (and to bot.log).

Configure once at startup (bot.on_ready) and then call log_event()
from anywhere: it sends the embed to the log channel without blocking.

Two channels:
  * LOG_CHANNEL_ID           - every event (redemptions, deliveries, staff
                               commands, role changes...)
  * SECURITY_LOG_CHANNEL_ID  - security events only (failed redemptions,
                               key-sharing attempts, permission denials,
                               lockouts, errors). Falls back to the main
                               channel when empty.

Every event is also written to bot.log, so there is a record even when the
channel is missing, the bot lacks permission there, or Discord is down.
"""
import asyncio
import datetime
import logging

import discord

log = logging.getLogger("keybot.logger")
_events = logging.getLogger("keybot.events")

_bot: discord.Client | None = None
_channel_id: int = 0
_security_channel_id: int = 0
# Strong references: asyncio only keeps weak ones, so a pending send could
# otherwise be garbage collected before it runs.
_pending: set[asyncio.Task] = set()


def configure(
    bot: discord.Client, channel_id: int, security_channel_id: int = 0
) -> None:
    global _bot, _channel_id, _security_channel_id
    _bot = bot
    _channel_id = channel_id
    _security_channel_id = security_channel_id


def _send_done(task: asyncio.Task) -> None:
    _pending.discard(task)
    if task.cancelled():
        return
    exc = task.exception()
    if exc is not None:
        log.warning("Could not send event to the log channel: %s", exc)


async def _send(channel_id: int, embed: discord.Embed) -> None:
    assert _bot is not None
    channel = _bot.get_channel(channel_id)
    if channel is None:
        # Not cached (e.g. right after startup or a thread): fetch it once
        channel = await _bot.fetch_channel(channel_id)
    await channel.send(embed=embed)  # type: ignore[union-attr]


def _to_file(embed: discord.Embed, security: bool) -> None:
    text = " | ".join(
        part.replace("\n", " / ")
        for part in (embed.title or "", embed.description or "")
        if part
    )
    if security:
        _events.warning("[SECURITY] %s", text)
    else:
        _events.info("[EVENT] %s", text)


def log_event(embed: discord.Embed, *, security: bool = False) -> None:
    """
    Sends `embed` to the log channel. security=True routes it to the
    security channel (or the main one when no security channel is set).
    Always written to bot.log as well.
    """
    _to_file(embed, security)
    if _bot is None:
        return
    channel_id = (_security_channel_id or _channel_id) if security else _channel_id
    if not channel_id:
        return
    if embed.timestamp is None:
        embed.timestamp = datetime.datetime.now(datetime.timezone.utc)
    if security and not embed.footer.text:
        embed.set_footer(text="🛡️ Security")
    try:
        task = _bot.loop.create_task(_send(channel_id, embed))
    except RuntimeError:
        return  # loop closed (shutdown)
    _pending.add(task)
    task.add_done_callback(_send_done)
