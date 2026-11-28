"""
Bot entry point.

Starts four things in the same process:
  1. Discord client (slash commands + buttons)
  2. The public API (script delivery / execution tracking) - API_PORT
  3. The private server (admin dashboard + private bot API) - DASHBOARD_PORT,
     loopback only. The bot gets loaders from it through bot_api.py
  4. SQLite database (with automatic daily backups)

Usage: python bot.py
"""
import asyncio
import logging
import os
import sys
import time

import discord
from discord import app_commands
from discord.ext import commands, tasks
from aiohttp import web

import catalog
import config
import platform_bridge as db  # key storage: platform over HTTP, or local
import logger as logmod
from api import start_api
from bot_api import BotApiClient, BotApiError
from dashboard import start_dashboard
from roles import sync_buyer_roles
from utils import error_embed, info_embed, mask_key

# Logs go to the console (when there is one) and to bot.log
_handlers: list = []
if sys.stderr:
    _handlers.append(logging.StreamHandler())
_handlers.append(
    logging.FileHandler(os.path.join(config.BASE_DIR, "bot.log"), encoding="utf-8")
)
logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] %(levelname)-7s %(name)s: %(message)s",
    handlers=_handlers,
)
log = logging.getLogger("keybot")


class KeyBot(commands.Bot):
    def __init__(self) -> None:
        intents = discord.Intents.default()
        super().__init__(
            command_prefix=commands.when_mentioned,  # prefixes not used
            intents=intents,
            application_id=None,
        )
        self.api_runner: web.AppRunner | None = None
        self.dashboard_runner: web.AppRunner | None = None
        # Private loader API client (used by the panel and /loader)
        self.bot_api = BotApiClient()
        self.started_at = int(time.time())

    # ------------------------------------------------------------------
    async def setup_hook(self) -> None:
        await self.load_extension("cogs.lang")
        await self.load_extension("cogs.panel")
        await self.load_extension("cogs.admin")
        await self.load_extension("cogs.shop")
        await self.load_extension("cogs.embeds")
        await self.load_extension("cogs.executions")
        await self.load_extension("cogs.shop_editor")

        # Sync the slash commands (never fatal: the bot must stay online)
        try:
            if config.GUILD_ID:
                guild = discord.Object(id=config.GUILD_ID)
                self.tree.copy_global_to(guild=guild)
                synced = await self.tree.sync(guild=guild)
                log.info(
                    "Commands synced to guild %s (%d commands)",
                    config.GUILD_ID,
                    len(synced),
                )
            else:
                synced = await self.tree.sync()
                log.info(
                    "Commands synced globally (%d commands). "
                    "Can take up to 1 hour to appear.",
                    len(synced),
                )
        except discord.HTTPException as exc:
            log.error(
                "Slash-command sync failed (%s). Re-invite the bot with the "
                "applications.commands scope and restart to sync again.", exc,
            )

        if db.using_platform():
            log.info(
                "Aero Platform bridge ACTIVE (%s) — embedded API and local "
                "dashboard are disabled; the platform serves /v1 and the "
                "admin dashboard.", config.PLATFORM_API_URL,
            )
            return

        # Start the HTTP API together with the bot
        holder: dict = {}
        await start_api(holder)
        self.api_runner = holder["runner"]
        log.info(
            "API running at http://%s:%s (public: %s)",
            config.API_HOST,
            config.API_PORT,
            config.PUBLIC_API_URL,
        )

        # Private server: dashboard + private bot API (loopback only)
        private: dict = {}
        await start_dashboard(private)
        self.dashboard_runner = private["runner"]
        log.info(
            "Dashboard running at http://%s:%s/",
            config.DASHBOARD_HOST,
            config.DASHBOARD_PORT,
        )

    # ------------------------------------------------------------------
    @tasks.loop(hours=24)
    async def backup_loop(self) -> None:
        """Daily database backup (keeps the newest 7 files).

        In bridge mode the platform owns the license database and its own
        rotating backups, so db.backup() returns None and we skip the copy.
        """
        try:
            path = db.backup(config.BACKUP_DIR)
            if path is None:
                log.info("Backup skipped: the Aero Platform manages it.")
            else:
                db.prune_backups(config.BACKUP_DIR, keep=7)
                log.info("Database backup created: %s", path)
                if config.BACKUP_SYNC_DIR:
                    copy = db.sync_backup(path, config.BACKUP_SYNC_DIR, keep=7)
                    log.info("Backup copied to %s", copy)
        except Exception:
            log.exception("Database backup failed")
        try:
            removed = catalog.prune_logs(config.ACCESS_LOG_DAYS)
            if removed:
                log.info("Pruned %d old request/activity log rows", removed)
        except Exception:
            log.exception("Log pruning failed")

    # ------------------------------------------------------------------
    @tasks.loop(minutes=config.ROLE_SYNC_MINUTES)
    async def role_sync_loop(self) -> None:
        """Takes the @Buyer role from users whose keys are all unusable."""
        try:
            removed = await sync_buyer_roles(self)
            if removed:
                log.info("Buyer role removed from %d user(s)", removed)
        except Exception:
            log.exception("Buyer role sync failed")

    @role_sync_loop.before_loop
    async def before_role_sync_loop(self) -> None:
        await self.wait_until_ready()

    # ------------------------------------------------------------------
    @tasks.loop(seconds=60)
    async def heartbeat_loop(self) -> None:
        """Reports the bot status to the private API (shown in the dashboard)."""
        if db.using_platform():
            return  # private dashboard disabled in bridge mode
        try:
            await self.bot_api.heartbeat({
                "user": str(self.user) if self.user else "",
                "user_id": str(self.user.id) if self.user else "",
                "guilds": len(self.guilds),
                "latency_ms": int(self.latency * 1000) if self.latency == self.latency else 0,
                "started_at": self.started_at,
            })
        except BotApiError as exc:
            log.warning("Heartbeat to the private API failed: %s", exc)

    @heartbeat_loop.before_loop
    async def before_heartbeat_loop(self) -> None:
        await self.wait_until_ready()

    @backup_loop.before_loop
    async def before_backup_loop(self) -> None:
        await self.wait_until_ready()

    # ------------------------------------------------------------------
    @tasks.loop(hours=1)
    async def reminder_loop(self) -> None:
        """DMs buyers whose key expires within 24 hours (once)."""
        try:
            rows = db.due_expiration_reminders()
        except Exception:
            log.exception("Expiration reminder query failed")
            return

        for row in rows:
            # Marks first so a crash/restart never double-sends
            db.mark_expiration_reminded(row["key"])
            try:
                user = await self.fetch_user(row["discord_id"])
                embed = discord.Embed(
                    title="⏳ Your key expires soon",
                    description=(
                        f"Your key `{row['key'][:8]}…` expires on "
                        f"**{db.fmt_date(row['expires_at'])}**.\n\n"
                        "Talk to the staff to renew it and keep "
                        "your access."
                    ),
                    color=config.PANEL_COLOR,
                )
                await user.send(embed=embed)
                log.info(
                    "Expiration reminder sent to %s", row["discord_id"]
                )
            except Exception:
                log.warning(
                    "Could not send expiration reminder to %s",
                    row["discord_id"],
                )

    @reminder_loop.before_loop
    async def before_reminder_loop(self) -> None:
        await self.wait_until_ready()

    # ------------------------------------------------------------------
    async def on_ready(self) -> None:
        log.info("Logged in as %s (ID %s)", self.user, self.user and self.user.id)
        log.info("Servers: %d", len(self.guilds))
        logmod.configure(
            self, config.LOG_CHANNEL_ID, config.SECURITY_LOG_CHANNEL_ID
        )
        if config.LOG_CHANNEL_ID:
            log.info("Log channel: %s", config.LOG_CHANNEL_ID)
        else:
            log.info("Log channel not configured (LOG_CHANNEL_ID empty)")
        if config.SECURITY_LOG_CHANNEL_ID:
            log.info("Security log channel: %s", config.SECURITY_LOG_CHANNEL_ID)
        logmod.log_event(
            info_embed(
                "Bot online",
                f"Logged in as {self.user} — {len(self.guilds)} server(s)\n"
                f"Mode: {'Aero Platform' if db.using_platform() else 'local'}",
            )
        )
        if not self.backup_loop.is_running():
            self.backup_loop.start()
        if not self.reminder_loop.is_running():
            self.reminder_loop.start()
        if not self.heartbeat_loop.is_running():
            self.heartbeat_loop.start()
        if not self.role_sync_loop.is_running():
            self.role_sync_loop.start()
        await self.change_presence(
            activity=discord.Activity(
                type=discord.ActivityType.watching,
                name="the key panel",
            )
        )

    # ------------------------------------------------------------------
    async def on_app_command_completion(
        self,
        interaction: discord.Interaction,
        command: app_commands.Command | app_commands.ContextMenu,
    ) -> None:
        """Audit log: every staff/admin command that ran successfully."""
        if not getattr(command, "checks", None):
            return  # public command (no permission check): not audited
        logmod.log_event(
            info_embed(
                f"Command used: /{command.qualified_name}",
                f"By: {interaction.user.mention} (`{interaction.user.id}`)\n"
                f"Channel: {getattr(interaction.channel, 'mention', '-')}\n"
                f"Options: {_describe_options(interaction)}",
            )
        )

    # ------------------------------------------------------------------
    async def close(self) -> None:
        if self.backup_loop.is_running():
            self.backup_loop.cancel()
        if self.reminder_loop.is_running():
            self.reminder_loop.cancel()
        if self.heartbeat_loop.is_running():
            self.heartbeat_loop.cancel()
        if self.role_sync_loop.is_running():
            self.role_sync_loop.cancel()
        await self.bot_api.close()
        if self.api_runner is not None:
            await self.api_runner.cleanup()
        if self.dashboard_runner is not None:
            await self.dashboard_runner.cleanup()
        await super().close()


# ---------------------------------------------------------------------------
# Slash command error handling (e.g. missing permission)
# ---------------------------------------------------------------------------
async def on_app_command_error(
    interaction: discord.Interaction,
    error: app_commands.AppCommandError,
) -> None:
    original = getattr(error, "original", error)
    name = interaction.command.qualified_name if interaction.command else "?"
    if isinstance(error, app_commands.CheckFailure):
        message = str(original) or "You don't have permission to do that."
        embed = error_embed("No permission", message)
        logmod.log_event(
            error_embed(
                f"Permission denied: /{name}",
                f"User: {interaction.user.mention} (`{interaction.user.id}`)\n"
                f"Channel: {getattr(interaction.channel, 'mention', '-')}\n"
                f"Options: {_describe_options(interaction)}",
            ),
            security=True,
        )
    else:
        log.exception("Error in slash command", exc_info=original)
        logmod.log_event(
            error_embed(
                f"Command error: /{name}",
                f"User: {interaction.user.mention}\n"
                f"Error: `{type(original).__name__}: {str(original)[:500]}`",
            ),
            security=True,
        )
        embed = error_embed(
            "Internal error",
            "Something went wrong while running the command. Please try again.",
        )

    try:
        if interaction.response.is_done():
            await interaction.followup.send(embed=embed, ephemeral=True)
        else:
            await interaction.response.send_message(
                embed=embed, ephemeral=True
            )
    except discord.HTTPException:
        pass


_SECRET_OPTIONS = ("key", "token", "password", "secret")


def _describe_options(interaction: discord.Interaction) -> str:
    """Slash command options for the logs, with keys masked."""
    parts = []
    for name, value in vars(interaction.namespace).items():
        if any(word in name.lower() for word in _SECRET_OPTIONS):
            value = mask_key(str(value))
        elif getattr(value, "mention", None):
            value = value.mention  # users, roles, channels
        text = str(value).replace("`", "'")
        parts.append(f"`{name}`={text[:200]}")
    return ", ".join(parts) or "-"


def main() -> None:
    errors = config.validate()
    if errors:
        print("Incomplete configuration:")
        for err in errors:
            print(f"  - {err}")
        print("\nCopy '.env.example' to '.env' and fill in the values.")
        sys.exit(1)

    bot = KeyBot()
    bot.tree.on_error = on_app_command_error
    bot.run(config.DISCORD_TOKEN, log_handler=None)


if __name__ == "__main__":
    main()
