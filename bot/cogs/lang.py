"""
Language selector (English / Português / Español).

The choice is stored on the Aero Platform (``lang_prefs``) and applied to
every response the bot sends to that user. Two entry points share the same
view: the ``/language`` command and the 🌐 button on the panel.
"""
from __future__ import annotations

import discord
from discord import app_commands
from discord.ext import commands
from discord import ui

import i18n
from utils import error_embed, info_embed


def language_embed(lang: str) -> discord.Embed:
    embed = discord.Embed(
        title=i18n.tl(lang, "lang_title"),
        description=(
            f"{i18n.tl(lang, 'lang_desc')}\n\n"
            f"{i18n.tl(lang, 'lang_current', flag=i18n.LANG_FLAGS[lang], name=i18n.LANG_NAMES[lang])}"
        ),
        color=0x5865F2,
    )
    return embed


class LanguageSelect(ui.Select):
    def __init__(self, owner_id: int, current: str) -> None:
        self.owner_id = owner_id
        options = [
            discord.SelectOption(
                label=i18n.LANG_NAMES[code],
                value=code,
                emoji=i18n.LANG_FLAGS[code],
                default=(code == current),
            )
            for code in i18n.LANGS
        ]
        super().__init__(
            placeholder=i18n.tl(current, "lang_title"),
            min_values=1,
            max_values=1,
            options=options,
            custom_id=f"lang:pick:{owner_id}",
        )

    async def callback(self, interaction: discord.Interaction) -> None:
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
        code = self.values[0]
        try:
            saved = i18n.set_lang(interaction.user.id, code)
        except Exception:
            lang = i18n.get_lang(interaction.user.id)
            await interaction.response.send_message(
                embed=error_embed(
                    i18n.tl(lang, "lang_invalid"),
                    i18n.tl(lang, "lang_invalid_desc"),
                ),
                ephemeral=True,
            )
            return
        # Rebuild the menu in the language just chosen
        view = LanguageView(self.owner_id, saved)
        embed = language_embed(saved)
        await interaction.response.edit_message(embed=embed, view=view)
        await interaction.followup.send(
            embed=info_embed(
                i18n.tl(saved, "lang_title"),
                i18n.tl(saved, "lang_updated",
                        flag=i18n.LANG_FLAGS[saved],
                        name=i18n.LANG_NAMES[saved]),
            ),
            ephemeral=True,
        )


class LanguageView(ui.View):
    def __init__(self, owner_id: int, lang: str | None = None) -> None:
        super().__init__(timeout=180)
        self.owner_id = owner_id
        self.add_item(LanguageSelect(owner_id, lang or i18n.get_lang(owner_id)))


async def open_language_menu(interaction: discord.Interaction) -> None:
    """Shared by /language and the 🌐 panel button (not deferred)."""
    lang = i18n.get_lang(interaction.user.id)
    await interaction.response.send_message(
        embed=language_embed(lang),
        view=LanguageView(interaction.user.id, lang),
        ephemeral=True,
    )


class LangCog(commands.Cog):
    def __init__(self, bot: commands.Bot) -> None:
        self.bot = bot

    @app_commands.command(
        name="language",
        description="Choose the bot language (English / Português / Español)",
    )
    async def language(self, interaction: discord.Interaction) -> None:
        await open_language_menu(interaction)

    @app_commands.command(
        name="lang",
        description="Shortcut for /language",
    )
    async def lang(self, interaction: discord.Interaction) -> None:
        await open_language_menu(interaction)


async def setup(bot: commands.Bot) -> None:
    await bot.add_cog(LangCog(bot))
