"""
Administration commands, split in two levels:

  OWNER (ADMIN_ROLE_ID):
    /ban /unban /extend /unlink /broadcast /postpanel /postshop /addscript

  STAFF (STAFF_ROLE_ID or ADMIN_ROLE_ID):
    /genkey /keyinfo /userinfo /listkeys /setnote /deliver /games

  /genkey    - generates keys in bulk (expiration, note, optional game)
  /games     - lists the games and the loader each one is serving
  /ban       - bans a user (blocks redemption and execution)
  /unban     - removes the ban
  /extend    - extends a key's validity (0 = permanent)
  /unlink    - unbinds a key from a user (refund / transfer)
  /broadcast - DMs an announcement to every buyer
  /keyinfo   - shows the data of a specific key
  /userinfo  - shows the key data of a user
  /listkeys  - lists the most recently created keys
  /setnote   - sets an internal note on a key (buyer name, etc.)
"""
import asyncio
import io
import sqlite3

import discord
from discord import app_commands
from discord.ext import commands

import catalog
import config
import platform_bridge as db
import logger
from roles import remove_buyer_role
from utils import (
    error_embed,
    success_embed,
    info_embed,
    ago,
    admin_only,
    staff_only,
    mask_key,
)


_STATUS_LABEL = {
    "ok": "🟢 Active",
    "inactive": "⚪ Disabled",
    "revoked": "⛔ Revoked",
    "banned": "🔴 Banned",
    "expired": "🟠 Expired",
}
_STATUS_ICON = {
    "ok": "🟢", "inactive": "⚪", "revoked": "⛔", "banned": "🔴", "expired": "🟠",
}


def _games_text(row: sqlite3.Row) -> str:
    if row["all_games"]:
        return "All games"
    names = []
    for game_id in db.key_game_ids(row["key"]):
        game = catalog.get_game(game_id)
        if game is not None:
            names.append(game["name"])
    return ", ".join(names) or "None"


async def _platform_games() -> list[dict]:
    """Games + their scripts from the Aero Platform: [{name, slug, enabled, scripts: [...]}]."""
    from bot_api import BotApiClient
    client = BotApiClient()
    try:
        games = await client._platform("/api/v1/games")
        scripts = await client._platform("/api/v1/scripts")
    finally:
        await client.close()
    out = []
    for g in games or []:
        out.append({
            "id": g["id"], "name": g["name"], "slug": client._slug(g["name"]),
            "enabled": bool(g.get("active")),
            "scripts": [sc for sc in (scripts or []) if sc.get("game_id") == g["id"]],
        })
    return out


async def _game_choices(current: str) -> list[app_commands.Choice[str]]:
    current = current.lower()
    if db.using_platform():
        try:
            rows = await _platform_games()
        except Exception:
            return []
        return [
            app_commands.Choice(name=g["name"][:100], value=g["slug"])
            for g in rows if current in g["name"].lower() or current in g["slug"]
        ][:25]
    return [
        app_commands.Choice(name=str(g["name"])[:100], value=g["slug"])
        for g in catalog.list_games()
        if current in g["name"].lower() or current in g["slug"]
    ][:25]


def _key_embed(row: sqlite3.Row, title: str) -> discord.Embed:
    """Embed with all of a key's data (admin view)."""
    banned = db.status(row) == "banned"
    embed = discord.Embed(title=title, color=config.PANEL_COLOR)

    embed.add_field(name="Key", value=f"`{row['key']}`", inline=False)
    embed.add_field(
        name="User",
        value=(
            f"<@{row['discord_id']}> ({row['discord_id']})"
            if row["discord_id"]
            else "Not redeemed"
        ),
        inline=True,
    )
    embed.add_field(
        name="Status",
        value=_STATUS_LABEL.get(db.status(row), db.status(row)),
        inline=True,
    )
    embed.add_field(
        name="Expires on",
        value=(
            "Never"
            if not row["expires_at"]
            else db.fmt_date(row["expires_at"])
        ),
        inline=True,
    )
    embed.add_field(
        name="HWID",
        value=(f"`{row['hwid']}`" if row["hwid"] else "Not registered"),
        inline=False,
    )
    embed.add_field(
        name="Executions",
        value=str(row["executions"]),
        inline=True,
    )
    embed.add_field(
        name="HWID resets",
        value=str(row["hwid_resets"]),
        inline=True,
    )
    embed.add_field(
        name="Created",
        value=db.fmt_date(row["created_at"]),
        inline=True,
    )
    embed.add_field(
        name="Redeemed",
        value=(
            db.fmt_date(row["redeemed_at"])
            if row["redeemed_at"]
            else "Not redeemed"
        ),
        inline=True,
    )
    embed.add_field(
        name="Last execution",
        value=ago(row["last_exec"]),
        inline=True,
    )
    embed.add_field(
        name="Note",
        value=(row["note"] or "Not specified"),
        inline=False,
    )
    embed.add_field(name="Games", value=_games_text(row), inline=True)
    embed.add_field(
        name="Last loader",
        value=(f"`{row['last_loader_id']}`" if row["last_loader_id"] else "None yet"),
        inline=True,
    )
    if banned:
        embed.add_field(
            name="Ban reason",
            value=(row["ban_reason"] or "Not provided"),
            inline=False,
        )
        if row["ban_until"]:
            embed.add_field(
                name="Banned until",
                value=db.fmt_date(row["ban_until"]),
                inline=True,
            )
    return embed


class AdminCog(commands.Cog):
    def __init__(self, bot: commands.Bot) -> None:
        self.bot = bot

    # ------------------------------------------------------------------
    # /genkey (staff)
    # ------------------------------------------------------------------
    @app_commands.command(
        name="genkey",
        description="Generates new keys (up to 20 at a time)",
    )
    @app_commands.describe(
        days="Validity in days (0 = permanent)",
        count="Number of keys (1-20)",
        note="Optional internal note (e.g. the buyer's name)",
        game="Limit the keys to one game (empty = all games)",
    )
    @app_commands.choices(
        count=[
            app_commands.Choice(name=str(n), value=n)
            for n in (1, 3, 5, 10, 20)
        ]
    )
    @staff_only()
    async def genkey(
        self,
        interaction: discord.Interaction,
        days: app_commands.Range[int, 0, 3650] = 0,
        count: app_commands.Range[int, 1, 20] = 1,
        note: str | None = None,
        game: str | None = None,
    ) -> None:
        game_row = None
        if game:
            game_row = catalog.get_game_by_slug(game)
            if game_row is None:
                await interaction.response.send_message(
                    embed=error_embed(
                        "Unknown game",
                        f"No game with slug `{game}`. Pick one from the list.",
                    ),
                    ephemeral=True,
                )
                return
        keys = db.generate_keys(
            count, days, note or "",
            game_ids=[game_row["id"]] if game_row is not None else None,
        )
        scope = game_row["name"] if game_row is not None else "all games"
        logger.log_event(
            success_embed(
                "Keys generated",
                f"By: {interaction.user.mention}\n"
                f"Count: {len(keys)}\n"
                f"Validity: {days if days else 'permanent'}\n"
                f"Games: {scope}\n"
                f"Note: {note or '-'}",
            )
        )
        catalog.log_activity(
            str(interaction.user), "keys_generate",
            f"{len(keys)} key(s) via Discord, {days or 'permanent'} day(s), {scope}",
        )

        expira = (
            "permanent" if days == 0 else f"{days} day(s)"
        )
        header = (
            f"🔑 **{len(keys)} key(s) generated** "
            f"— validity: {expira} — {scope}\n"
        )

        if len(keys) <= 5:
            body = "\n".join(f"`{k}`" for k in keys)
            embed = success_embed(
                "Keys generated!", header + "\n" + body
            )
            await interaction.response.send_message(
                embed=embed, ephemeral=True
            )
        else:
            data = ("\n".join(keys)).encode("utf-8")
            file = discord.File(
                io.BytesIO(data), filename="keys.txt"
            )
            embed = success_embed(
                "Keys generated!",
                header + "See the attached file.",
            )
            await interaction.response.send_message(
                embed=embed, file=file, ephemeral=True
            )

    @genkey.autocomplete("game")
    async def genkey_game_autocomplete(
        self, interaction: discord.Interaction, current: str
    ) -> list[app_commands.Choice[str]]:
        return await _game_choices(current)

    # ------------------------------------------------------------------
    # /games (staff)
    # ------------------------------------------------------------------
    @app_commands.command(
        name="games",
        description="Lists the games and the loader each one is serving",
    )
    @staff_only()
    async def games(self, interaction: discord.Interaction) -> None:
        if db.using_platform():
            await interaction.response.defer(ephemeral=True)
            embed = discord.Embed(title="Games", color=config.PANEL_COLOR)
            try:
                rows = await _platform_games()
            except Exception:
                await interaction.followup.send("The platform is unavailable right now.", ephemeral=True)
                return
            if not rows:
                embed.description = "No games yet. Create them in the dashboard."
            for g in rows[:25]:
                state = "🟢 Enabled" if g["enabled"] else "⚪ Disabled"
                lines = [
                    f"`{sc['name']}` v{sc.get('current_version') or '?'}"
                    + ("" if sc.get("enabled") else " (disabled)")
                    for sc in g["scripts"]
                ] or ["⚠️ no script"]
                embed.add_field(name=f"{g['name']} (`{g['slug']}`)",
                                value=f"{state}\nServing: " + ", ".join(lines), inline=False)
            embed.set_footer(text="Games and scripts are managed in the Aero dashboard.")
            await interaction.followup.send(embed=embed, ephemeral=True)
            return
        rows = catalog.list_games()
        embed = discord.Embed(title="Games", color=config.PANEL_COLOR)
        if not rows:
            embed.description = "No games yet. Create them in the dashboard."
        for game in rows[:25]:
            loader = catalog.active_loader(game["id"])
            state = "🟢 Enabled" if game["enabled"] else "⚪ Disabled"
            default = " · ⭐ default" if game["is_default"] else ""
            serving = (
                f"`{loader['id']}` v{loader['version']} "
                f"(updated {db.fmt_date(loader['updated_at'])})"
                if loader else "⚠️ no loader"
            )
            embed.add_field(
                name=f"{game['name']} (`{game['slug']}`)",
                value=f"{state}{default}\nServing: {serving}",
                inline=False,
            )
        embed.set_footer(text="Manage games, loaders and keys in the private dashboard.")
        await interaction.response.send_message(embed=embed, ephemeral=True)

    # ------------------------------------------------------------------
    # /addscript (owner)
    # ------------------------------------------------------------------
    @app_commands.command(
        name="addscript",
        description="Adds or updates a game's script in the central loader",
    )
    @app_commands.describe(
        game="Game slug (pick an existing one or type a new one, e.g. blox-fruits)",
        script="The .lua / .txt file with the game's script",
        name="Display name (only needed when creating a new game)",
        place_ids="Roblox PlaceIds, separated by comma (auto-detects the game)",
    )
    @admin_only()
    async def addscript(
        self,
        interaction: discord.Interaction,
        game: str,
        script: discord.Attachment,
        name: str | None = None,
        place_ids: str | None = None,
    ) -> None:
        if db.using_platform():
            await interaction.response.send_message(
                embed=error_embed(
                    "Use the dashboard",
                    "Scripts are managed in the Aero dashboard now: "
                    f"{config.PLATFORM_API_URL}/dashboard/ → Scripts → Publish version.",
                ),
                ephemeral=True,
            )
            return
        if script.size > catalog.MAX_LOADER_BYTES:
            await interaction.response.send_message(
                embed=error_embed("File too big", "The script exceeds 16 MB."),
                ephemeral=True,
            )
            return
        await interaction.response.defer(ephemeral=True)
        try:
            content = (await script.read()).decode("utf-8-sig")
            slug = game.strip().lower()
            row = catalog.get_game_by_slug(slug)
            created = row is None
            if created:
                row = catalog.create_game(
                    slug,
                    name or slug,
                    place_ids,
                    is_default=not catalog.list_games(),
                )
            elif place_ids:
                row = catalog.update_game(row["id"], place_ids=place_ids)

            loader = catalog.active_loader(row["id"])
            if loader is None:
                loader = catalog.create_loader(
                    row["name"], content, game_id=row["id"]
                )
            else:
                loader = catalog.update_loader(loader["id"], content=content)
        except UnicodeDecodeError:
            await interaction.followup.send(
                embed=error_embed("Invalid file", "The file must be UTF-8 text."),
                ephemeral=True,
            )
            return
        except catalog.CatalogError as exc:
            await interaction.followup.send(
                embed=error_embed("Could not save", str(exc)), ephemeral=True
            )
            return

        catalog.log_activity(
            str(interaction.user.id),
            "addscript",
            f"{row['slug']} v{loader['version']} ({loader['size']} bytes)",
        )
        places = ", ".join(row["place_ids"].split(",")) if row["place_ids"] else "none"
        await interaction.followup.send(
            embed=success_embed(
                "Game created" if created else "Script updated",
                f"Game: **{row['name']}** (`{row['slug']}`)\n"
                f"Version: v{loader['version']} · {loader['size']} bytes\n"
                f"PlaceIds: {places}\n"
                "Every buyer with access to this game now gets this script "
                "through the same loader.",
            ),
            ephemeral=True,
        )

    @addscript.autocomplete("game")
    async def addscript_game_autocomplete(
        self, interaction: discord.Interaction, current: str
    ) -> list[app_commands.Choice[str]]:
        return await _game_choices(current)

    # ------------------------------------------------------------------
    # /ban (owner)
    # ------------------------------------------------------------------
    @app_commands.command(
        name="ban",
        description="Bans a user (blocks key redemption/execution)",
    )
    @app_commands.describe(
        user="The user to ban",
        reason="Reason for the ban",
        days="Ban duration in days (0 = permanent)",
    )
    @admin_only()
    async def ban(
        self,
        interaction: discord.Interaction,
        user: discord.Member,
        reason: str = "",
        days: app_commands.Range[int, 0, 3650] = 0,
    ) -> None:
        await interaction.response.defer(ephemeral=True, thinking=True)
        if await asyncio.to_thread(db.ban_user, user.id, reason, days):
            # Banned keys are unusable: take the buyer role away now
            await remove_buyer_role(self.bot, user.id, f"Banned: {reason or '-'}")
            logger.log_event(
                error_embed(
                    "User banned",
                    f"By: {interaction.user.mention}\n"
                    f"User: {user.mention}\n"
                    f"Reason: {reason or '-'}\n"
                    f"Days: {days if days else 'permanent'}",
                ),
                security=True,
            )
            expira = "permanent" if days == 0 else f"{days} day(s)"
            await interaction.followup.send(
                embed=success_embed(
                    "User banned!",
                    f"**User:** {user.mention}\n"
                    f"**Reason:** {reason or 'Not provided'}\n"
                    f"**Duration:** {expira}",
                ),
                ephemeral=True,
            )
        else:
            await interaction.followup.send(
                embed=error_embed(
                    "Nothing to ban",
                    f"{user.mention} has no redeemed key.",
                ),
                ephemeral=True,
            )

    # ------------------------------------------------------------------
    # /unban (owner)
    # ------------------------------------------------------------------
    @app_commands.command(
        name="unban",
        description="Removes a user's ban",
    )
    @app_commands.describe(user="The user to unban")
    @admin_only()
    async def unban(
        self, interaction: discord.Interaction, user: discord.Member
    ) -> None:
        await interaction.response.defer(ephemeral=True, thinking=True)
        if await asyncio.to_thread(db.unban_user, user.id):
            logger.log_event(
                success_embed(
                    "User unbanned",
                    f"By: {interaction.user.mention}\nUser: {user.mention}",
                )
            )
            await interaction.followup.send(
                embed=success_embed(
                    "User unbanned!",
                    f"{user.mention} can now use their key again.",
                ),
                ephemeral=True,
            )
        else:
            await interaction.followup.send(
                embed=error_embed(
                    "Nothing to unban",
                    f"{user.mention} has no redeemed key.",
                ),
                ephemeral=True,
            )

    # ------------------------------------------------------------------
    # /extend (owner)
    # ------------------------------------------------------------------
    @app_commands.command(
        name="extend",
        description="Extends a key's validity (0 = permanent)",
    )
    @app_commands.describe(
        key="The full key",
        days="Days to add (0 = makes the key permanent)",
    )
    @admin_only()
    async def extend(
        self,
        interaction: discord.Interaction,
        key: str,
        days: app_commands.Range[int, 0, 3650] = 30,
    ) -> None:
        found, new_exp = db.extend_key(key, days)
        if not found:
            await interaction.response.send_message(
                embed=error_embed(
                    "Key not found",
                    "Check that you typed the key correctly.",
                ),
                ephemeral=True,
            )
            return

        if days > 0 and new_exp is None:
            # Permanent key: extending it does not change anything
            await interaction.response.send_message(
                embed=info_embed(
                    "Key not changed",
                    f"Key: `{key.strip()}`\n"
                    "This key is permanent, so there is no expiration to "
                    "extend. Use days=0 only if you want to make a timed key "
                    "permanent.",
                ),
                ephemeral=True,
            )
            return

        expiry_text = db.fmt_date(new_exp) if new_exp else "Never (permanent)"
        await interaction.response.send_message(
            embed=success_embed(
                "Key extended!",
                f"Key: `{key.strip()}`\n"
                f"New expiration: {expiry_text}",
            ),
            ephemeral=True,
        )
        logger.log_event(
            info_embed(
                "Key extended",
                f"By: {interaction.user.mention}\n"
                f"Key: `{mask_key(key.strip())}`\n"
                f"Added: {days if days else 'made permanent'}\n"
                f"New expiration: {expiry_text}",
            )
        )

    # ------------------------------------------------------------------
    # /keyinfo (staff)
    # ------------------------------------------------------------------
    @app_commands.command(
        name="keyinfo",
        description="Shows all information about a key",
    )
    @app_commands.describe(key="The full key")
    @staff_only()
    async def keyinfo(
        self, interaction: discord.Interaction, key: str
    ) -> None:
        row = db.get_key(key)
        if row is None:
            await interaction.response.send_message(
                embed=error_embed(
                    "Key not found",
                    "Check that you typed the key correctly.",
                ),
                ephemeral=True,
            )
            return
        await interaction.response.send_message(
            embed=_key_embed(row, "Key information"),
            ephemeral=True,
        )

    # ------------------------------------------------------------------
    # /userinfo (staff)
    # ------------------------------------------------------------------
    @app_commands.command(
        name="userinfo",
        description="Shows the key redeemed by a user",
    )
    @app_commands.describe(user="The user to look up")
    @staff_only()
    async def userinfo(
        self, interaction: discord.Interaction, user: discord.Member
    ) -> None:
        row = db.get_user_key(user.id)
        if row is None:
            await interaction.response.send_message(
                embed=error_embed(
                    "No key",
                    f"{user.mention} has not redeemed any key.",
                ),
                ephemeral=True,
            )
            return
        await interaction.response.send_message(
            embed=_key_embed(row, f"Key of {user}"),
            ephemeral=True,
        )

    # ------------------------------------------------------------------
    # /listkeys (staff)
    # ------------------------------------------------------------------
    @app_commands.command(
        name="listkeys",
        description="System summary + latest keys created",
    )
    @staff_only()
    async def listkeys(self, interaction: discord.Interaction) -> None:
        total, redeemed, banned = db.count_keys()
        recent = db.list_recent(15)

        embed = discord.Embed(
            title="Key system summary",
            color=config.PANEL_COLOR,
        )
        embed.add_field(
            name="Total keys",
            value=str(total),
            inline=True,
        )
        embed.add_field(
            name="Redeemed",
            value=str(redeemed),
            inline=True,
        )
        embed.add_field(
            name="Banned",
            value=str(banned),
            inline=True,
        )

        if recent:
            lines = []
            for row in recent:
                owner = (
                    f"<@{row['discord_id']}>"
                    if row["discord_id"]
                    else "*not redeemed*"
                )
                icon = _STATUS_ICON.get(db.status(row), "🟢")
                lines.append(
                    f"{icon} `{row['key'][:8]}…` → {owner}"
                )
            embed.add_field(
                name="Recent keys",
                value="\n".join(lines),
                inline=False,
            )
        else:
            embed.add_field(
                name="Recent keys",
                value="No keys generated yet.",
                inline=False,
            )

        await interaction.response.send_message(
            embed=embed, ephemeral=True
        )

    # ------------------------------------------------------------------
    # /unlink (owner)
    # ------------------------------------------------------------------
    @app_commands.command(
        name="unlink",
        description="Unbinds a key from a user (refund / transfer)",
    )
    @app_commands.describe(
        key="The full key",
        note="Optional reason (recorded in the logs)",
    )
    @admin_only()
    async def unlink(
        self,
        interaction: discord.Interaction,
        key: str,
        note: str | None = None,
    ) -> None:
        await interaction.response.defer(ephemeral=True, thinking=True)
        try:
            before = await asyncio.to_thread(db.get_key, key.strip())
        except Exception:
            before = None
        owner_id = before["discord_id"] if before is not None else None
        if not await asyncio.to_thread(db.unlink_key, key):
            await interaction.followup.send(
                embed=error_embed(
                    "Nothing to unlink",
                    "Key not found, or the key is not bound to anyone.",
                ),
                ephemeral=True,
            )
            return
        await interaction.followup.send(
            embed=success_embed(
                "Key unbound!",
                f"Key: `{key.strip()}`\n"
                "The owner, HWID and reset counter were cleared — "
                "someone else can redeem it now.",
            ),
            ephemeral=True,
        )
        if owner_id:
            # Old owner keeps the role only if another usable key is left
            other = await asyncio.to_thread(db.get_user_key, owner_id)
            if other is None or db.status(other) != "ok":
                await remove_buyer_role(self.bot, owner_id, "Key unlinked")
        logger.log_event(
            info_embed(
                "Key unbound",
                f"By: {interaction.user.mention}\n"
                f"Previous owner: {f'<@{owner_id}>' if owner_id else '-'}\n"
                f"Key: `{mask_key(key.strip())}`\n"
                f"Reason: {note or '-'}",
            )
        )

    # ------------------------------------------------------------------
    # /broadcast (owner)
    # ------------------------------------------------------------------
    @app_commands.command(
        name="broadcast",
        description="Sends an announcement by DM to every buyer",
    )
    @app_commands.describe(message="The message to send")
    @admin_only()
    async def broadcast(
        self, interaction: discord.Interaction, message: str
    ) -> None:
        ids = db.list_buyer_ids()
        await interaction.response.send_message(
            embed=success_embed(
                "Broadcast started",
                f"Sending your announcement to **{len(ids)}** buyer(s) "
                "(about 1 second each)...",
            ),
            ephemeral=True,
        )
        if not ids:
            return

        embed = discord.Embed(
            title="📢 Announcement",
            description=message,
            color=config.PANEL_COLOR,
        )
        sent = failed = 0
        for user_id in ids:
            try:
                user = await self.bot.fetch_user(user_id)
                await user.send(embed=embed)
                sent += 1
            except (discord.Forbidden, discord.NotFound, discord.HTTPException):
                failed += 1
            await asyncio.sleep(1.0)

        logger.log_event(
            success_embed(
                "Broadcast finished",
                f"By: {interaction.user.mention}\n"
                f"Sent: {sent}\nFailed: {failed}",
            )
        )

    # ------------------------------------------------------------------
    # /setnote (staff)
    # ------------------------------------------------------------------
    @app_commands.command(
        name="setnote",
        description="Sets an internal note on a key (buyer name, etc.)",
    )
    @app_commands.describe(
        key="The full key",
        note="The note (leave empty to clear it)",
    )
    @staff_only()
    async def setnote(
        self, interaction: discord.Interaction, key: str, note: str = ""
    ) -> None:
        if not db.set_note(key, note):
            await interaction.response.send_message(
                embed=error_embed(
                    "Key not found",
                    "Check that you typed the key correctly.",
                ),
                ephemeral=True,
            )
            return
        await interaction.response.send_message(
            embed=success_embed(
                "Note updated",
                f"Key: `{key.strip()}`\nNote: {note or '(cleared)'}",
            ),
            ephemeral=True,
        )


async def setup(bot: commands.Bot) -> None:
    await bot.add_cog(AdminCog(bot))

