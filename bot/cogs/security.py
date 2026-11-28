"""
Security tools.

  * Action buttons on security alerts: 🔨 Ban · 🔄 Reset HWID · 🚫 Revoke.
    They keep working after restarts (dynamic custom_id with the key).
    Ban and Revoke need the admin role; Reset HWID works for staff.
  * /blacklist add | remove | list  - HWID, Roblox account or IP.
  * Discord ban = key ban: banning someone from the server bans their key and
    blacklists their HWIDs / Roblox accounts.
  * Buyer left the server (needs MEMBERS_INTENT=1 + "Server Members Intent"
    enabled in the Discord Developer Portal).
  * Platform watchdog: alerts when the Aero Platform stops answering (and
    when it comes back), optionally also to WATCHDOG_WEBHOOK_URL.
"""
from __future__ import annotations

import asyncio
import json
import logging
import time
import urllib.request

import aiohttp
import discord
from discord import app_commands, ui
from discord.ext import commands, tasks

import blacklist
import config
import logger
import platform_bridge as db
import theme
from roles import remove_buyer_role
from utils import admin_only, error_embed, info_embed, mask_key, success_embed, warning_embed

log = logging.getLogger("keybot.security")

_ACTIONS = {
    # action: (label, slot, style, admin only)
    "ban": ("Ban", "ban", discord.ButtonStyle.danger, True),
    "reset": ("Reset HWID", "hwid", discord.ButtonStyle.secondary, False),
    "revoke": ("Revoke key", "revoke", discord.ButtonStyle.danger, True),
}


def _role_ids(user) -> set[int]:
    return {r.id for r in getattr(user, "roles", [])}


def _is_admin(user) -> bool:
    return config.ADMIN_ROLE_ID in _role_ids(user)


def _is_staff(user) -> bool:
    ids = _role_ids(user)
    return config.ADMIN_ROLE_ID in ids or bool(config.STAFF_ROLE_ID and config.STAFF_ROLE_ID in ids)


async def run_action(bot: discord.Client, action: str, key: str, actor: str) -> str:
    """Executes a security action on a key. Returns a result sentence."""
    row = await asyncio.to_thread(db.get_key, key)
    if row is None:
        return "Key not found."
    owner = row["discord_id"]
    if action == "reset":
        ok = await asyncio.to_thread(db.reset_key_hwid, key)
        return "HWID reset." if ok else "The platform refused the HWID reset."
    if action == "ban":
        ok = await asyncio.to_thread(db.ban_key, key, f"Security alert (by {actor})", 0)
        if not ok:
            return "The platform refused the ban."
        listed = await asyncio.to_thread(
            blacklist.add_key_identity, key, "Banned from a security alert", actor,
            row["hwid"],
        )
        if owner:
            await remove_buyer_role(bot, int(owner), "Key banned (security)")
        return f"Key banned. {listed} HWID/Roblox ID(s) blacklisted."
    if action == "revoke":
        ok = await asyncio.to_thread(db.revoke_key, key)
        if not ok:
            return "The platform refused the revoke."
        if owner:
            await remove_buyer_role(bot, int(owner), "Key revoked (security)")
        return "Key revoked."
    return "Unknown action."


class AlertAction(
    ui.DynamicItem[ui.Button],
    template=r"sec:(?P<action>ban|reset|revoke):(?P<key>[A-Za-z0-9_\-]{4,64})",
):
    def __init__(self, action: str, key: str) -> None:
        label, slot, style, _admin = _ACTIONS[action]
        super().__init__(
            ui.Button(
                label=label, style=style, emoji=theme.pe(slot),
                custom_id=f"sec:{action}:{key}",
            )
        )
        self.action = action
        self.key = key

    @classmethod
    async def from_custom_id(cls, interaction, item, match):  # type: ignore[override]
        return cls(match["action"], match["key"])

    async def interaction_check(self, interaction: discord.Interaction) -> bool:
        needs_admin = _ACTIONS[self.action][3]
        allowed = _is_admin(interaction.user) if needs_admin else _is_staff(interaction.user)
        if not allowed:
            await interaction.response.send_message(
                embed=error_embed(
                    "No permission",
                    "Only administrators can do this." if needs_admin
                    else "Only staff can do this.",
                ),
                ephemeral=True,
            )
        return allowed

    async def callback(self, interaction: discord.Interaction) -> None:
        await interaction.response.defer(ephemeral=True, thinking=True)
        result = await run_action(
            interaction.client, self.action, self.key, str(interaction.user)
        )
        await interaction.followup.send(
            embed=info_embed(_ACTIONS[self.action][0], result), ephemeral=True
        )
        # Stamp the alert so the staff sees it was handled
        message = interaction.message
        if message is not None and message.embeds:
            embed = message.embeds[0]
            embed.add_field(
                name=f"{theme.e('success')} Action taken",
                value=f"{_ACTIONS[self.action][0]} by {interaction.user.mention} — {result}",
                inline=False,
            )
            try:
                await message.edit(embed=embed)
            except discord.HTTPException:
                pass
        logger.log_event(
            info_embed(
                f"Security action: {_ACTIONS[self.action][0]}",
                f"By: {interaction.user.mention}\nKey: `{mask_key(self.key)}`\n{result}",
            )
        )


def alert_view(key: str | None) -> ui.View | None:
    """Ban / Reset HWID / Revoke buttons for an alert about `key`."""
    if not key or not 4 <= len(key) <= 64:
        return None
    view = ui.View(timeout=None)
    for action in ("ban", "reset", "revoke"):
        view.add_item(AlertAction(action, key))
    return view


# ---------------------------------------------------------------------------
# Cog
# ---------------------------------------------------------------------------
class SecurityCog(commands.Cog):
    blacklist_group = app_commands.Group(
        name="blacklist", description="HWID / Roblox account / IP blacklist"
    )

    def __init__(self, bot: commands.Bot) -> None:
        self.bot = bot
        self._fails = 0
        self._down_since: float | None = None

    async def cog_load(self) -> None:
        if db.using_platform():
            self.watchdog.start()

    async def cog_unload(self) -> None:
        if self.watchdog.is_running():
            self.watchdog.cancel()

    # ------------------------------------------------------------------
    # /blacklist
    # ------------------------------------------------------------------
    @blacklist_group.command(name="add", description="Blacklist an HWID, Roblox user ID or IP")
    @app_commands.describe(kind="What to blacklist", value="The HWID / Roblox user ID / IP", reason="Why")
    @app_commands.choices(kind=[app_commands.Choice(name=k, value=k) for k in blacklist.TYPES])
    @admin_only()
    async def bl_add(self, interaction: discord.Interaction, kind: str, value: str, reason: str = "") -> None:
        added = await asyncio.to_thread(
            blacklist.add, kind, value, reason or "Manual", str(interaction.user)
        )
        if added:
            logger.log_event(
                warning_embed(
                    "Blacklist entry added",
                    f"By: {interaction.user.mention}\n{kind}: `{value}`\nReason: {reason or '-'}",
                ),
                security=True,
            )
        await interaction.response.send_message(
            embed=success_embed("Blacklisted", f"{kind}: `{value}`") if added
            else error_embed("Already blacklisted", f"{kind}: `{value}`"),
            ephemeral=True,
        )

    @blacklist_group.command(name="remove", description="Remove a blacklist entry")
    @app_commands.choices(kind=[app_commands.Choice(name=k, value=k) for k in blacklist.TYPES])
    @admin_only()
    async def bl_remove(self, interaction: discord.Interaction, kind: str, value: str) -> None:
        removed = await asyncio.to_thread(blacklist.remove, kind, value)
        if removed:
            logger.log_event(
                info_embed(
                    "Blacklist entry removed",
                    f"By: {interaction.user.mention}\n{kind}: `{value}`",
                )
            )
        await interaction.response.send_message(
            embed=success_embed("Removed", f"{kind}: `{value}`") if removed
            else error_embed("Not found", f"{kind}: `{value}` is not blacklisted."),
            ephemeral=True,
        )

    @blacklist_group.command(name="list", description="Show the blacklist")
    @admin_only()
    async def bl_list(self, interaction: discord.Interaction) -> None:
        rows = await asyncio.to_thread(blacklist.entries)
        if not rows:
            await interaction.response.send_message(
                embed=info_embed("Blacklist", "The blacklist is empty."), ephemeral=True
            )
            return
        lines = [
            f"`{kind}` `{value[:40]}` — {info.get('reason', '-')} "
            f"(<t:{int(info.get('ts', 0))}:R>)"
            for kind, value, info in rows[-40:]
        ]
        await interaction.response.send_message(
            embed=info_embed(f"Blacklist ({len(rows)})", "\n".join(lines)[:4000]),
            ephemeral=True,
        )

    # ------------------------------------------------------------------
    # Discord ban = key ban
    # ------------------------------------------------------------------
    @commands.Cog.listener()
    async def on_member_ban(self, guild: discord.Guild, user: discord.User) -> None:
        if config.GUILD_ID and guild.id != config.GUILD_ID:
            return
        row = await asyncio.to_thread(db.get_user_key, user.id)
        if row is None:
            return
        await asyncio.to_thread(db.ban_user, user.id, "Banned from the Discord server", 0)
        listed = await asyncio.to_thread(
            blacklist.add_key_identity, row["key"], "Banned from the Discord server",
            "discord-ban", row["hwid"],
        )
        logger.log_event(
            error_embed(
                "Server ban → key banned",
                f"User: {user.mention} (`{user.id}`)\nKey: `{mask_key(row['key'])}`\n"
                f"{listed} HWID/Roblox ID(s) blacklisted.",
            ),
            security=True,
        )

    @commands.Cog.listener()
    async def on_member_unban(self, guild: discord.Guild, user: discord.User) -> None:
        if config.GUILD_ID and guild.id != config.GUILD_ID:
            return
        logger.log_event(
            info_embed(
                "Server unban",
                f"User: {user.mention} (`{user.id}`)\nTheir key stays banned — "
                "use `/unban` if they should get access back.",
            )
        )

    @commands.Cog.listener()
    async def on_raw_member_remove(self, payload: discord.RawMemberRemoveEvent) -> None:
        # Only fires with MEMBERS_INTENT=1 (privileged intent)
        if config.GUILD_ID and payload.guild_id != config.GUILD_ID:
            return
        row = await asyncio.to_thread(db.get_user_key, payload.user.id)
        if row is None:
            return
        logger.log_event(
            warning_embed(
                "Buyer left the server",
                f"User: {payload.user.mention} (`{payload.user.id}`)\n"
                f"Key: `{mask_key(row['key'])}` • status `{db.status(row)}`",
            )
        )

    # ------------------------------------------------------------------
    # Platform watchdog
    # ------------------------------------------------------------------
    @staticmethod
    def _platform_ok() -> bool:
        try:
            req = urllib.request.Request(
                f"{config.PLATFORM_API_URL}/v1/health",
                headers={"User-Agent": "aero-bot-watchdog/1.0"},
            )
            with urllib.request.urlopen(req, timeout=8) as resp:
                return bool(json.loads(resp.read().decode("utf-8")).get("ok"))
        except Exception:
            return False

    async def _notify(self, embed: discord.Embed) -> None:
        logger.log_event(embed, security=True)
        if not config.WATCHDOG_WEBHOOK_URL:
            return
        try:
            async with aiohttp.ClientSession() as session:
                await session.post(
                    config.WATCHDOG_WEBHOOK_URL,
                    json={"embeds": [embed.to_dict()], "allowed_mentions": {"parse": []}},
                    timeout=aiohttp.ClientTimeout(total=10),
                )
        except Exception as exc:
            log.warning("Watchdog webhook failed: %s", exc)

    @tasks.loop(seconds=60)
    async def watchdog(self) -> None:
        ok = await asyncio.to_thread(self._platform_ok)
        if ok:
            if self._down_since is not None:
                minutes = int((time.time() - self._down_since) / 60)
                await self._notify(success_embed(
                    "Aero Platform is back online",
                    f"It was unreachable for about **{max(1, minutes)} min**.",
                ))
            self._fails, self._down_since = 0, None
            return
        self._fails += 1
        if self._fails == max(1, config.WATCHDOG_FAILS):
            self._down_since = time.time() - 60 * (self._fails - 1)
            await self._notify(error_embed(
                "Aero Platform is DOWN",
                f"No answer from the platform for {self._fails} minute(s).\n"
                "Nobody can execute the script or redeem keys until it is back.",
            ))

    @watchdog.before_loop
    async def _before_watchdog(self) -> None:
        await self.bot.wait_until_ready()


async def setup(bot: commands.Bot) -> None:
    bot.add_dynamic_items(AlertAction)
    await bot.add_cog(SecurityCog(bot))
