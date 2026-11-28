"""
Main panel with the 5 buttons (Project Rain / Luarmor style):

  🎫 Redeem Key   - redeems the key and links it to the user (modal)
  📜 Get Script   - delivers the script with the key already embedded
  ⛅ Get Role     - grants the @Buyer role
  🔄 Reset HWID   - clears the registered HWID
  📊 Get Stats    - key statistics
"""
import asyncio
import io
import sqlite3

import discord
from discord import app_commands
from discord.ext import commands
from discord import ui

import catalog
import config
import platform_bridge as db
import i18n
import logger
from bot_api import BotApiClient, BotApiError
from ratelimit import RateLimiter
from cogs.lang import open_language_menu
from utils import error_embed, success_embed, info_embed, ago, admin_only, mask_key

# Used when the bot object has no client of its own (tests, standalone runs)
_fallback_client: BotApiClient | None = None


def api_client(interaction: discord.Interaction) -> BotApiClient:
    """The bot's private-API client (see bot.py), or a shared fallback."""
    global _fallback_client
    client = getattr(interaction.client, "bot_api", None)
    if isinstance(client, BotApiClient):
        return client
    if _fallback_client is None:
        _fallback_client = BotApiClient()
    return _fallback_client


# ---------------------------------------------------------------------------
# Loader delivery (shared by the Get Script button and /loader)
# ---------------------------------------------------------------------------
async def _send_loader(interaction: discord.Interaction, data: dict) -> None:
    script = data["script"]
    game = data.get("game") or {}
    loader = data.get("loader") or {}
    header = f"Here is your loader for **{game.get('name', 'your game')}**:"
    content = f"{header}\n```lua\n{script}\n```"
    if len(content) <= 2000:
        await interaction.followup.send(content, ephemeral=True)
    else:
        # Script too large for a message: send it as a file
        file = discord.File(
            io.BytesIO(script.encode("utf-8")),
            filename=f"loader-{game.get('slug', 'game')}.lua",
        )
        await interaction.followup.send(
            content=f"{header} (as a file — it is too large for a message)",
            file=file,
            ephemeral=True,
        )
    logger.log_event(
        success_embed(
            "Loader delivered",
            f"User: {interaction.user.mention}\n"
            f"Game: {game.get('name', '-')}\n"
            f"Loader: `{loader.get('id', '-')}` (v{loader.get('version', '?')})",
        )
    )


async def deliver_loader(
    interaction: discord.Interaction, key: str, game_slug: str | None
) -> None:
    """
    Delivers the loader. With the Aero Platform bridge active, sends the
    platform's own loader URL (single entry point, key never leaves the
    player's machine in a public message). Otherwise asks the private API
    for the legacy per-game loader. The interaction must already be deferred.
    """
    if db.using_platform():
        lang = i18n.get_lang(interaction.user.id)
        url = f"{db.public_url()}/loader/aero_loader.lua"
        # Personalised one-liner: the key is already filled in, so it just runs
        # (the loader also remembers the key for later runs).
        snippet = f'script_key="{key}"\nloadstring(game:HttpGet("{url}"))()'
        texts = {
            "pt": "Copie e execute no seu executor, **dentro do jogo**. Sua key já vai preenchida, é só executar. Funciona em todos os jogos suportados (o jogo é detectado sozinho).",
            "es": "Copia y ejecuta en tu executor, **dentro del juego**. Tu key ya va incluida. Funciona en todos los juegos soportados (el juego se detecta solo).",
            "en": "Copy and run this in your executor, **inside the game**. Your key is already filled in. Works in every supported game (the game is detected automatically).",
        }
        desc = texts.get(lang, texts["en"]) + f"\n```lua\n{snippet}\n```\n⚠️ " + {
            "pt": "Não compartilhe: contém a sua key.",
            "es": "No lo compartas: contiene tu key.",
        }.get(lang, "Do not share it: it contains your key.")
        await interaction.followup.send(
            embed=info_embed(i18n.tl(lang, "loader_title"), desc),
            ephemeral=True,
        )
        logger.log_event(
            info_embed(
                "Loader delivered",
                f"User: {interaction.user.mention}\nSource: Aero Platform",
            )
        )
        return

    client = api_client(interaction)
    try:
        # No game given -> the universal loader (game picked by PlaceId)
        data = await client.loader(key, game_slug or "", interaction.user.id)
    except BotApiError as exc:
        lang = i18n.get_lang(interaction.user.id)
        await interaction.followup.send(
            embed=error_embed(i18n.tl(lang, "loader_error"), str(exc)),
            ephemeral=True,
        )
        return
    await _send_loader(interaction, data)


class GamePickerView(ui.View):
    """Ephemeral game menu shown when a key has access to several games."""

    def __init__(self, owner_id: int, key: str, games: list[dict]) -> None:
        super().__init__(timeout=180)
        self.owner_id = owner_id
        self.key = key
        lang = i18n.get_lang(owner_id)
        select = ui.Select(
            placeholder=i18n.tl(lang, "loader_pick"),
            options=[
                discord.SelectOption(
                    label=str(g["name"])[:100], value=str(g["slug"])[:100], emoji="🎮"
                )
                for g in games[:25]
            ],
            min_values=1,
            max_values=1,
        )
        select.callback = self._on_select
        self.add_item(select)

    async def _on_select(self, interaction: discord.Interaction) -> None:
        if interaction.user.id != self.owner_id:
            lang = i18n.get_lang(interaction.user.id)
            await interaction.response.send_message(
                embed=error_embed(
                    i18n.tl(lang, "not_your_menu"),
                    i18n.tl(lang, "not_your_menu_desc"),
                ),
                ephemeral=True,
            )
            return
        values = interaction.data.get("values") or []
        if not values:
            return
        await interaction.response.defer(ephemeral=True, thinking=True)
        await deliver_loader(interaction, self.key, values[0])


# ---------------------------------------------------------------------------
# Redeem modal
# ---------------------------------------------------------------------------
# Anti brute-force: 5 wrong keys per user, then a 10 minute pause
_redeem_limiter = RateLimiter(limit=4, window=600.0)
_REDEEM_BLOCKED = {
    "pt": ("Muitas tentativas", "Você errou a key várias vezes. Tente de novo em alguns minutos."),
    "es": ("Demasiados intentos", "Fallaste la key varias veces. Inténtalo de nuevo en unos minutos."),
    "en": ("Too many attempts", "You entered a wrong key several times. Try again in a few minutes."),
}


class RedeemModal(ui.Modal):
    def __init__(self, lang: str = "en") -> None:
        super().__init__(title=i18n.tl(lang, "redeem_modal_title"))
        self.lang = lang
        self.key_input = ui.TextInput(
            label=i18n.tl(lang, "redeem_label"),
            placeholder=i18n.tl(lang, "redeem_placeholder"),
            style=discord.TextStyle.short,
            max_length=64,
            required=True,
        )
        self.add_item(self.key_input)

    async def on_submit(self, interaction: discord.Interaction) -> None:
        lang = i18n.get_lang(interaction.user.id)
        key = str(self.key_input.value).strip()
        bucket = f"redeem:{interaction.user.id}"
        if _redeem_limiter.over(bucket):
            title, text = _REDEEM_BLOCKED.get(lang, _REDEEM_BLOCKED["en"])
            await interaction.response.send_message(
                embed=error_embed(title, text), ephemeral=True
            )
            return
        code, _row = await asyncio.to_thread(db.redeem, key, interaction.user.id)
        if code == "not_found":
            _redeem_limiter.hit(bucket)

        if code == "ok":
            embed = success_embed(
                i18n.tl(lang, "redeem_ok"),
                i18n.tl(lang, "redeem_ok_desc", user=interaction.user.mention),
            )
            logger.log_event(
                success_embed(
                    "Key redeemed",
                    f"User: {interaction.user.mention}\nKey: `{mask_key(key)}`",
                )
            )
        elif code == "not_found":
            embed = error_embed(
                i18n.tl(lang, "redeem_not_found"),
                i18n.tl(lang, "redeem_not_found_desc"),
            )
        elif code == "already":
            embed = error_embed(
                i18n.tl(lang, "redeem_already"),
                i18n.tl(lang, "redeem_already_desc"),
            )
        elif code == "taken":
            embed = error_embed(
                i18n.tl(lang, "redeem_taken"),
                i18n.tl(lang, "redeem_taken_desc"),
            )
        elif code == "banned":
            embed = error_embed(
                i18n.tl(lang, "redeem_banned"),
                i18n.tl(lang, "redeem_banned_desc"),
            )
        elif code == "inactive":
            embed = error_embed(
                i18n.tl(lang, "redeem_inactive"),
                i18n.tl(lang, "redeem_inactive_desc"),
            )
        else:  # expired
            embed = error_embed(
                i18n.tl(lang, "redeem_expired"),
                i18n.tl(lang, "redeem_expired_desc"),
            )

        await interaction.response.send_message(embed=embed, ephemeral=True)


# ---------------------------------------------------------------------------
# Persistent view with the 5 buttons
# ---------------------------------------------------------------------------
class PanelView(ui.View):
    def __init__(self) -> None:
        # timeout=None + fixed custom_ids = the buttons keep working
        # even after the bot restarts.
        super().__init__(timeout=None)

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------
    @staticmethod
    def _require_key(discord_id: int) -> tuple[discord.Embed | None, sqlite3.Row | None]:
        """Returns (error_embed, row) — embed is None when everything is fine."""
        lang = i18n.get_lang(discord_id)
        row = db.get_user_key(discord_id)
        if row is None:
            return (
                error_embed(
                    i18n.tl(lang, "panel_no_key"),
                    i18n.tl(lang, "panel_no_key_desc"),
                ),
                None,
            )
        st = db.status(row)
        if st in ("revoked", "inactive"):
            return (
                error_embed(
                    i18n.tl(lang, "panel_key_disabled"),
                    i18n.tl(lang, "panel_key_disabled_desc"),
                ),
                None,
            )
        if st == "banned":
            reason = row["ban_reason"] or i18n.tl(lang, "panel_no_reason")
            return (
                error_embed(
                    i18n.tl(lang, "panel_key_banned"),
                    i18n.tl(lang, "panel_key_banned_desc", reason=reason),
                ),
                None,
            )
        if st == "expired":
            return (
                error_embed(
                    i18n.tl(lang, "panel_key_expired"),
                    i18n.tl(lang, "panel_key_expired_desc"),
                ),
                None,
            )
        return None, row

    @staticmethod
    def _render_loader(key: str, game_slug: str = "") -> str:
        """Local render of the loader template (the API uses the same code)."""
        return catalog.render_loader(key, game_slug)

    # ------------------------------------------------------------------
    # 🎫 Redeem Key
    # ------------------------------------------------------------------
    @ui.button(
        label="Redeem Key",
        emoji="🎫",
        style=discord.ButtonStyle.success,
        custom_id="panel:redeem_key",
    )
    async def redeem_key(
        self, interaction: discord.Interaction, item: discord.ui.Button
    ) -> None:
        await interaction.response.send_modal(
            RedeemModal(i18n.get_lang(interaction.user.id))
        )

    # ------------------------------------------------------------------
    # 📜 Get Script
    # ------------------------------------------------------------------
    @ui.button(
        label="Get Script",
        emoji="📜",
        style=discord.ButtonStyle.primary,
        custom_id="panel:get_script",
    )
    async def get_script(
        self, interaction: discord.Interaction, item: discord.ui.Button
    ) -> None:
        err, row = self._require_key(interaction.user.id)
        if err:
            await interaction.response.send_message(
                embed=err, ephemeral=True
            )
            return

        # The loader comes from the private API (key + game validation)
        await interaction.response.defer(ephemeral=True, thinking=True)
        await deliver_loader(interaction, row["key"], None)

    # ------------------------------------------------------------------
    # ⛅ Get Role
    # ------------------------------------------------------------------
    @ui.button(
        label="Get Role",
        emoji="⛅",
        style=discord.ButtonStyle.secondary,
        custom_id="panel:get_role",
    )
    async def get_role(
        self, interaction: discord.Interaction, item: discord.ui.Button
    ) -> None:
        lang = i18n.get_lang(interaction.user.id)
        err, _row = self._require_key(interaction.user.id)
        if err:
            await interaction.response.send_message(
                embed=err, ephemeral=True
            )
            return

        role = (
            interaction.guild.get_role(config.BUYER_ROLE_ID)
            if interaction.guild
            else None
        )
        if role is None:
            await interaction.response.send_message(
                embed=error_embed(
                    i18n.tl(lang, "panel_misconfig"),
                    i18n.tl(lang, "panel_role_missing"),
                ),
                ephemeral=True,
            )
            return

        if role in interaction.user.roles:
            await interaction.response.send_message(
                embed=error_embed(
                    i18n.tl(lang, "panel_role_already"),
                    i18n.tl(lang, "panel_role_already_desc", role=role.mention),
                ),
                ephemeral=True,
            )
            return

        try:
            await interaction.user.add_roles(
                role, reason="Get Role via panel"
            )
        except discord.Forbidden:
            await interaction.response.send_message(
                embed=error_embed(
                    i18n.tl(lang, "panel_role_forbidden"),
                    i18n.tl(lang, "panel_role_forbidden_desc", role=role.mention),
                ),
                ephemeral=True,
            )
            return

        logger.log_event(
            success_embed(
                "Role granted",
                f"User: {interaction.user.mention}\nRole: {role.mention}",
            )
        )
        await interaction.response.send_message(
            embed=success_embed(
                i18n.tl(lang, "success"),
                i18n.tl(lang, "panel_role_granted", role=role.mention),
            ),
            ephemeral=True,
        )

    # ------------------------------------------------------------------
    # 🔄 Reset HWID
    # ------------------------------------------------------------------
    @ui.button(
        label="Reset HWID",
        emoji="🔄",
        style=discord.ButtonStyle.secondary,
        custom_id="panel:reset_hwid",
    )
    async def reset_hwid(
        self, interaction: discord.Interaction, item: discord.ui.Button
    ) -> None:
        lang = i18n.get_lang(interaction.user.id)
        err, row = self._require_key(interaction.user.id)
        if err:
            await interaction.response.send_message(
                embed=err, ephemeral=True
            )
            return

        if row["hwid_resets"] >= config.MAX_HWID_RESETS:
            await interaction.response.send_message(
                embed=error_embed(
                    i18n.tl(lang, "panel_limit"),
                    i18n.tl(lang, "panel_limit_desc",
                            max=config.MAX_HWID_RESETS),
                ),
                ephemeral=True,
            )
            return

        db.reset_hwid(interaction.user.id)
        logger.log_event(
            info_embed(
                "HWID reset",
                f"User: {interaction.user.mention}\n"
                f"Resets used: {row['hwid_resets'] + 1}/"
                f"{config.MAX_HWID_RESETS}",
            )
        )
        await interaction.response.send_message(
            embed=success_embed(
                i18n.tl(lang, "success"),
                i18n.tl(lang, "panel_hwid_reset"),
            ),
            ephemeral=True,
        )

    # ------------------------------------------------------------------
    # 📊 Get Stats
    # ------------------------------------------------------------------
    @ui.button(
        label="Get Stats",
        emoji="📊",
        style=discord.ButtonStyle.secondary,
        custom_id="panel:get_stats",
    )
    async def get_stats(
        self, interaction: discord.Interaction, item: discord.ui.Button
    ) -> None:
        lang = i18n.get_lang(interaction.user.id)
        err, row = self._require_key(interaction.user.id)
        if err:
            await interaction.response.send_message(
                embed=err, ephemeral=True
            )
            return

        hwid_status = (
            i18n.tl(lang, "panel_stats_hwid_none")
            if not row["hwid"]
            else i18n.tl(lang, "panel_stats_hwid_set", hwid=row["hwid"])
        )
        banned = db.status(row) == "banned"

        embed = discord.Embed(
            title=i18n.tl(lang, "panel_stats_title"),
            color=config.PANEL_COLOR,
        )
        embed.add_field(
            name=i18n.tl(lang, "panel_stats_exec"),
            value=str(row["executions"]),
            inline=True,
        )
        embed.add_field(
            name=i18n.tl(lang, "panel_stats_hwid"),
            value=hwid_status, inline=True,
        )
        embed.add_field(
            name=i18n.tl(lang, "panel_stats_key"),
            value=f"||{row['key']}|| 🔒",
            inline=False,
        )
        embed.add_field(
            name=i18n.tl(lang, "panel_stats_resets"),
            value=f"{row['hwid_resets']} 🔄",
            inline=True,
        )
        embed.add_field(
            name=i18n.tl(lang, "panel_stats_last"),
            value=ago(row["last_exec"]),
            inline=True,
        )
        embed.add_field(
            name=i18n.tl(lang, "panel_stats_expires"),
            value=(
                f"{i18n.tl(lang, 'never')} 📅"
                if not row["expires_at"]
                else db.fmt_date(row["expires_at"]) + " 📅"
            ),
            inline=True,
        )
        embed.add_field(
            name=i18n.tl(lang, "panel_stats_banned"),
            value=(
                i18n.tl(lang, "panel_stats_yes")
                if banned
                else i18n.tl(lang, "panel_stats_no")
            ),
            inline=True,
        )
        embed.add_field(
            name=i18n.tl(lang, "panel_stats_note"),
            value=(row["note"] or i18n.tl(lang, "panel_stats_note_none")),
            inline=False,
        )
        if row["ban_reason"] and banned:
            embed.add_field(
                name=i18n.tl(lang, "panel_stats_ban_reason"),
                value=row["ban_reason"],
                inline=False,
            )

        await interaction.response.send_message(
            embed=embed, ephemeral=True
        )

    # ------------------------------------------------------------------
    # 🌐 Language
    # ------------------------------------------------------------------
    @ui.button(
        label="Language",
        emoji="🌐",
        style=discord.ButtonStyle.secondary,
        custom_id="panel:language",
        row=1,
    )
    async def language(
        self, interaction: discord.Interaction, item: discord.ui.Button
    ) -> None:
        await open_language_menu(interaction)


# ---------------------------------------------------------------------------
# Panel building
# ---------------------------------------------------------------------------
def build_panel_embed() -> discord.Embed:
    embed = discord.Embed(
        title=config.PANEL_TITLE,
        description=config.PANEL_DESCRIPTION,
        color=config.PANEL_COLOR,
    )
    return embed


# ---------------------------------------------------------------------------
# Command to post the panel
# ---------------------------------------------------------------------------
class PanelCog(commands.Cog):
    def __init__(self, bot: commands.Bot) -> None:
        self.bot = bot

    @app_commands.command(
        name="postpanel",
        description="Posts the panel with the buttons to the specified channel",
    )
    @app_commands.describe(channel="Channel where the panel will be posted")
    @admin_only()
    async def postpanel(
        self,
        interaction: discord.Interaction,
        channel: discord.TextChannel | None = None,
    ) -> None:
        target = channel
        if target is None:
            if config.PANEL_CHANNEL_ID:
                target = interaction.guild.get_channel(
                    config.PANEL_CHANNEL_ID
                )
            else:
                target = interaction.channel  # type: ignore[assignment]

        if target is None:
            lang = i18n.get_lang(interaction.user.id)
            await interaction.response.send_message(
                embed=error_embed(
                    i18n.tl(lang, "panel_channel_not_found"),
                    i18n.tl(lang, "panel_channel_not_found_desc"),
                ),
                ephemeral=True,
            )
            return

        await target.send(
            embed=build_panel_embed(), view=PanelView()
        )
        lang = i18n.get_lang(interaction.user.id)
        await interaction.response.send_message(
            embed=success_embed(
                i18n.tl(lang, "panel_posted"),
                i18n.tl(lang, "panel_posted_desc", channel=target.mention),
            ),
            ephemeral=True,
        )

    # ------------------------------------------------------------------
    # /loader (everyone with a redeemed key)
    # ------------------------------------------------------------------
    @app_commands.command(
        name="loader",
        description="Get your script loader for a game",
    )
    @app_commands.describe(game="The game (leave empty to pick from a list)")
    async def loader(
        self,
        interaction: discord.Interaction,
        game: str | None = None,
    ) -> None:
        err, row = PanelView._require_key(interaction.user.id)
        if err:
            await interaction.response.send_message(embed=err, ephemeral=True)
            return
        await interaction.response.defer(ephemeral=True, thinking=True)
        await deliver_loader(interaction, row["key"], (game or "").strip().lower() or None)

    @loader.autocomplete("game")
    async def loader_game_autocomplete(
        self, interaction: discord.Interaction, current: str
    ) -> list[app_commands.Choice[str]]:
        row = db.get_user_key(interaction.user.id)
        if row is None:
            return []
        try:
            games = await api_client(interaction).games(row["key"])
        except BotApiError:
            return []
        current = current.lower()
        return [
            app_commands.Choice(name=str(g["name"])[:100], value=str(g["slug"]))
            for g in games
            if current in str(g["name"]).lower() or current in str(g["slug"])
        ][:25]


async def setup(bot: commands.Bot) -> None:
    # Registers the persistent view: old panel messages keep
    # working after the bot restarts.
    bot.add_view(PanelView())
    await bot.add_cog(PanelCog(bot))

