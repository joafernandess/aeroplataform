"""
Fire-and-forget logging to a Discord channel.

Configure once at startup (bot.on_ready) and then call log_event()
from anywhere: it sends the embed to the log channel without blocking.
When LOG_CHANNEL_ID is not set, every call is a no-op.
"""
import asyncio
import logging

import discord

log = logging.getLogger("keybot.logger")

_bot: discord.Client | None = None
_channel_id: int = 0
# Strong references: asyncio only keeps weak ones, so a pending send could
# otherwise be garbage collected before it runs.
_pending: set[asyncio.Task] = set()


def configure(bot: discord.Client, channel_id: int) -> None:
    global _bot, _channel_id
    _bot = bot
    _channel_id = channel_id


def _send_done(task: asyncio.Task) -> None:
    _pending.discard(task)
    if task.cancelled():
        return
    exc = task.exception()
    if exc is not None:
        log.warning("Could not send event to the log channel: %s", exc)


def log_event(embed: discord.Embed) -> None:
    """Sends `embed` to the log channel (no-op when not configured)."""
    if _bot is None or not _channel_id:
        return
    channel = _bot.get_channel(_channel_id)
    if channel is None:
        return
    task = _bot.loop.create_task(channel.send(embed=embed))
    _pending.add(task)
    task.add_done_callback(_send_done)
