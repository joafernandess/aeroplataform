"""
Interactive embed builder backed by the Aero Platform.

Everything the admin builds (embed + link/action buttons) is stored as JSON
in the platform's ``embed_templates`` table, so templates survive restarts
and can be reused by every bot process:

  /embed builder          opens the live builder (ephemeral)
  /embed list             lists saved templates
  /embed send <name>      posts a saved template
  /embed delete <name>    removes a template

Button actions (no external service needed):
  role     toggles a role on whoever clicks
  channel  points the user to a channel
  user     tells the user who to contact

Action buttons use ``aeroembed:<kind>:<id>`` custom_ids and are handled by
``on_interaction``, so they keep working after a restart without a
persistent view registration.
"""
from __future__ import annotations

import asyncio
import json

import discord
from discord import app_commands
from discord.ext import commands
from discord import ui

import i18n
import platform_bridge as db
from utils import admin_only, error_embed, info_embed, success_embed

PREFIX = "aeroembed"
DEFAULT_COLOR = 0x5865F2
MAX_FIELDS = 25
MAX_BUTTONS = 25

STYLES = {
    "primary": discord.ButtonStyle.primary,
    "secondary": discord.ButtonStyle.secondary,
    "success": discord.ButtonStyle.success,
    "danger": discord.ButtonStyle.danger,
}


# ---------------------------------------------------------------------------
# State helpers
# ---------------------------------------------------------------------------
def new_state() -> dict:
    return {
        "embed": {
            "title": "",
            "description": "",
            "color": DEFAULT_COLOR,
            "footer": "",
            "author": "",
            "thumbnail": "",
            "image": "",
            "fields": [],
        },
        "buttons": [],
    }


def normalize_state(raw) -> dict:
    """Accepts any JSON-ish dict and returns a valid builder state."""
    state = new_state()
    if not isinstance(raw, dict):
        return state
    emb = raw.get("embed")
    if isinstance(emb, dict):
        target = state["embed"]
        for key in ("title", "description", "footer", "author",
                    "thumbnail", "image"):
            value = emb.get(key)
            if isinstance(value, str):
                target[key] = value
        try:
            target["color"] = int(emb.get("color") or DEFAULT_COLOR)
        except (TypeError, ValueError):
            target["color"] = DEFAULT_COLOR
        fields = emb.get("fields")
        if isinstance(fields, list):
            for f in fields[:MAX_FIELDS]:
                if not isinstance(f, dict):
                    continue
                name = str(f.get("name") or "")[:256]
                value = str(f.get("value") or "")[:1024]
                if name and value:
                    target["fields"].append({
                        "name": name,
                        "value": value,
                        "inline": bool(f.get("inline")),
                    })
    buttons = raw.get("buttons")
    if isinstance(buttons, list):
        for b in buttons[:MAX_BUTTONS]:
            if not isinstance(b, dict):
                continue
            kind = str(b.get("type") or "")
            if kind == "link":
                url = str(b.get("url") or "")
                if not url.startswith(("http://", "https://")):
                    continue
                state["buttons"].append({
                    "type": "link",
                    "label": str(b.get("label") or "Link")[:80],
                    "url": url,
                    "emoji": str(b.get("emoji") or ""),
                })
            elif kind in ("role", "channel", "user"):
                try:
                    target_id = int(b.get("target_id"))
                except (TypeError, ValueError):
                    continue
                style = str(b.get("style") or "secondary")
                state["buttons"].append({
                    "type": kind,
                    "label": str(b.get("label") or kind.title())[:80],
                    "target_id": target_id,
                    "style": style if style in STYLES else "secondary",
                    "emoji": str(b.get("emoji") or ""),
                })
    return state


def state_to_embed(state: dict, lang: str, preview: bool = True) -> discord.Embed:
    emb = state["embed"]
    title = emb.get("title") or (i18n.tl(lang, "emb_title") if preview else "")
    embed = discord.Embed(
        title=title[:256] or None,
        description=(emb.get("description") or "")[:4096] or None,
        color=emb.get("color") or DEFAULT_COLOR,
    )
    if not embed.description and preview:
        embed.description = i18n.tl(lang, "emb_empty")
    if emb.get("footer"):
        embed.set_footer(text=emb["footer"][:2048])
    if emb.get("author"):
        embed.set_author(name=emb["author"][:256])
    if emb.get("thumbnail", "").startswith(("http://", "https://")):
        embed.set_thumbnail(url=emb["thumbnail"])
    if emb.get("image", "").startswith(("http://", "https://")):
        embed.set_image(url=emb["image"])
    for field in emb.get("fields", [])[:MAX_FIELDS]:
        embed.add_field(
            name=field["name"][:256] or "—",
            value=field["value"][:1024] or "—",
            inline=bool(field.get("inline")),
        )
    buttons = state.get("buttons") or []
    if buttons:
        lines = []
        for b in buttons:
            if b["type"] == "link":
                lines.append(f"🔗 {b['label']} → {b['url']}")
            else:
                lines.append(f"⚙️ {b['label']} ({b['type']})")
        embed.add_field(
            name=i18n.tl(lang, "emb_buttons"),
            value="\n".join(lines)[:1024],
            inline=False,
        )
    return embed


def _emoji(value: str | None):
    if not value:
        return None
    try:
        return discord.PartialEmoji.from_str(str(value))
    except Exception:
        return None


def state_to_view(state: dict, lang: str) -> ui.View:
    """A plain view with the configured buttons (link + actions)."""
    view = ui.View(timeout=None)
    for b in state.get("buttons", [])[:MAX_BUTTONS]:
        if b["type"] == "link":
            button = ui.Button(
                style=discord.ButtonStyle.link,
                label=b["label"][:80],
                url=b["url"],
                emoji=_emoji(b.get("emoji")),
            )
        else:
            button = ui.Button(
                style=STYLES.get(b.get("style"), discord.ButtonStyle.secondary),
                label=b["label"][:80],
                custom_id=f"{PREFIX}:{b['type']}:{int(b['target_id'])}",
                emoji=_emoji(b.get("emoji")),
            )
        view.add_item(button)
    return view


async def _guard(interaction: discord.Interaction, owner_id: int) -> bool:
    if interaction.user.id == owner_id:
        return True
    lang = i18n.get_lang(interaction.user.id)
    await interaction.response.send_message(
        embed=error_embed(
            i18n.tl(lang, "not_your_menu"),
            i18n.tl(lang, "not_your_menu_desc"),
        ),
        ephemeral=True,
    )
    return False


# ---------------------------------------------------------------------------
# Modals
# ---------------------------------------------------------------------------
class TextModal(ui.Modal):
    """One text field applied to a builder slot."""

    def __init__(self, builder: "BuilderView", field: str, title: str,
                 label: str, max_length: int, value: str = "",
                 placeholder: str = "") -> None:
        super().__init__(title=title[:45])
        self.builder = builder
        self.field = field
        self.input = ui.TextInput(
            label=label[:45],
            placeholder=placeholder[:100],
            default=value[:max_length] if value else None,
            style=discord.TextStyle.paragraph if max_length > 200
            else discord.TextStyle.short,
            max_length=max_length,
            required=False,
        )
        self.add_item(self.input)

    async def on_submit(self, interaction: discord.Interaction) -> None:
        value = str(self.input.value or "").strip()
        if self.field in ("thumbnail", "image") and value and not value.startswith(
            ("http://", "https://")
        ):
            lang = i18n.get_lang(interaction.user.id)
            await interaction.response.send_message(
                embed=error_embed(
                    i18n.tl(lang, "emb_url_invalid"),
                    i18n.tl(lang, "emb_url_invalid_desc"),
                ),
                ephemeral=True,
            )
            return
        self.builder.state["embed"][self.field] = value
        await interaction.response.edit_message(
            embed=self.builder.preview_embed(), view=self.builder
        )


class ColorModal(ui.Modal):
    def __init__(self, builder: "BuilderView", lang: str) -> None:
        super().__init__(title=i18n.tl(lang, "emb_edit_color")[:45])
        self.builder = builder
        self.input = ui.TextInput(
            label=i18n.tl(lang, "emb_edit_color")[:45],
            placeholder="#5865F2",
            default=f"#{builder.state['embed']['color']:06X}",
            max_length=9,
            required=True,
        )
        self.add_item(self.input)

    async def on_submit(self, interaction: discord.Interaction) -> None:
        lang = i18n.get_lang(interaction.user.id)
        raw = str(self.input.value or "").strip().lstrip("#")
        try:
            color = int(raw, 16)
            if not 0 <= color <= 0xFFFFFF:
                raise ValueError
        except ValueError:
            await interaction.response.send_message(
                embed=error_embed(
                    i18n.tl(lang, "emb_color_invalid"),
                    i18n.tl(lang, "emb_color_invalid_desc"),
                ),
                ephemeral=True,
            )
            return
        self.builder.state["embed"]["color"] = color
        await interaction.response.edit_message(
            embed=self.builder.preview_embed(), view=self.builder
        )


class FieldModal(ui.Modal):
    def __init__(self, builder: "BuilderView", lang: str) -> None:
        super().__init__(title=i18n.tl(lang, "emb_add_field")[:45])
        self.builder = builder
        self.name = ui.TextInput(
            label=i18n.tl(lang, "emb_field_name")[:45], max_length=256,
            required=True,
        )
        self.value = ui.TextInput(
            label=i18n.tl(lang, "emb_field_value")[:45],
            style=discord.TextStyle.paragraph, max_length=1024, required=True,
        )
        self.inline = ui.TextInput(
            label=i18n.tl(lang, "emb_field_inline")[:45],
            placeholder="yes / no", default="no", max_length=3, required=False,
        )
        self.add_item(self.name)
        self.add_item(self.value)
        self.add_item(self.inline)

    async def on_submit(self, interaction: discord.Interaction) -> None:
        lang = i18n.get_lang(interaction.user.id)
        fields = self.builder.state["embed"]["fields"]
        if len(fields) >= MAX_FIELDS:
            await interaction.response.send_message(
                embed=error_embed(
                    i18n.tl(lang, "emb_full"),
                    i18n.tl(lang, "emb_full_fields"),
                ),
                ephemeral=True,
            )
            return
        fields.append({
            "name": str(self.name.value or "").strip()[:256] or "—",
            "value": str(self.value.value or "").strip()[:1024] or "—",
            "inline": str(self.inline.value or "").strip().lower()
            in ("yes", "y", "sim", "s", "sí", "true", "1"),
        })
        await interaction.response.edit_message(
            embed=self.builder.preview_embed(), view=self.builder
        )


class LinkButtonModal(ui.Modal):
    def __init__(self, builder: "BuilderView", lang: str) -> None:
        super().__init__(title=i18n.tl(lang, "emb_add_link")[:45])
        self.builder = builder
        self.label = ui.TextInput(
            label=i18n.tl(lang, "emb_link_label")[:45], max_length=80,
            required=True,
        )
        self.url = ui.TextInput(
            label=i18n.tl(lang, "emb_link_url")[:45],
            placeholder="https://aero.gg", max_length=512, required=True,
        )
        self.emoji = ui.TextInput(
            label=i18n.tl(lang, "emb_link_emoji")[:45],
            max_length=64, required=False,
        )
        self.add_item(self.label)
        self.add_item(self.url)
        self.add_item(self.emoji)

    async def on_submit(self, interaction: discord.Interaction) -> None:
        lang = i18n.get_lang(interaction.user.id)
        buttons = self.builder.state["buttons"]
        if len(buttons) >= MAX_BUTTONS:
            await interaction.response.send_message(
                embed=error_embed(
                    i18n.tl(lang, "emb_full"),
                    i18n.tl(lang, "emb_full_buttons"),
                ),
                ephemeral=True,
            )
            return
        url = str(self.url.value or "").strip()
        if not url.startswith(("http://", "https://")):
            await interaction.response.send_message(
                embed=error_embed(
                    i18n.tl(lang, "emb_url_invalid"),
                    i18n.tl(lang, "emb_url_invalid_desc"),
                ),
                ephemeral=True,
            )
            return
        buttons.append({
            "type": "link",
            "label": str(self.label.value or "Link").strip()[:80] or "Link",
            "url": url,
            "emoji": str(self.emoji.value or "").strip(),
        })
        await interaction.response.edit_message(
            embed=self.builder.preview_embed(), view=self.builder
        )


class RenameButtonModal(ui.Modal):
    def __init__(self, builder: "BuilderView", lang: str) -> None:
        buttons = builder.state["buttons"]
        current = buttons[-1]["label"] if buttons else ""
        super().__init__(title=i18n.tl(lang, "emb_action_label")[:45])
        self.builder = builder
        self.input = ui.TextInput(
            label=i18n.tl(lang, "emb_link_label")[:45],
            default=current[:80] or None, max_length=80, required=True,
        )
        self.add_item(self.input)

    async def on_submit(self, interaction: discord.Interaction) -> None:
        buttons = self.builder.state["buttons"]
        if buttons:
            buttons[-1]["label"] = str(self.input.value or "").strip()[:80] \
                or buttons[-1]["label"]
        await interaction.response.edit_message(
            embed=self.builder.preview_embed(), view=self.builder
        )


class SaveModal(ui.Modal):
    def __init__(self, builder: "BuilderView", lang: str) -> None:
        super().__init__(title=i18n.tl(lang, "emb_save")[:45])
        self.builder = builder
        self.input = ui.TextInput(
            label=i18n.tl(lang, "emb_name_label")[:45],
            placeholder=i18n.tl(lang, "emb_name_placeholder")[:100],
            default=(builder.template_name or "")[:100] or None,
            max_length=100,
            required=True,
        )
        self.add_item(self.input)

    async def on_submit(self, interaction: discord.Interaction) -> None:
        lang = i18n.get_lang(interaction.user.id)
        name = str(self.input.value or "").strip()
        if not name:
            return
        payload = json.dumps(self.builder.state, ensure_ascii=False)
        try:
            row = await asyncio.to_thread(
                db.embed_save, name, payload,
                self.builder.template_id, str(interaction.user),
            )
        except Exception as exc:  # platform unreachable / local mode
            await interaction.response.send_message(
                embed=error_embed(
                    i18n.tl(lang, "emb_saved"),
                    i18n.tl(lang, "emb_no_platform") + f"\n`{exc}`",
                ),
                ephemeral=True,
            )
            return
        self.builder.template_id = int(row["id"])
        self.builder.template_name = row["name"]
        await interaction.response.edit_message(
            embed=self.builder.preview_embed(), view=self.builder
        )
        await interaction.followup.send(
            embed=success_embed(
                i18n.tl(lang, "emb_saved"),
                i18n.tl(lang, "emb_saved_desc", name=row["name"]),
            ),
            ephemeral=True,
        )


# ---------------------------------------------------------------------------
# Target pickers for action buttons
# ---------------------------------------------------------------------------
class ActionMenuView(ui.View):
    def __init__(self, builder: "BuilderView", lang: str) -> None:
        super().__init__(timeout=180)
        self.builder = builder
        self.lang = lang

    async def _start(self, interaction: discord.Interaction, kind: str) -> None:
        if not await _guard(interaction, self.builder.owner_id):
            return
        picker = TargetPickerView(self.builder, self.lang, kind)
        await interaction.response.edit_message(
            embed=info_embed(
                self.builder.preview_embed().title or i18n.tl(
                    self.lang, "emb_add_action"),
                i18n.tl(self.lang, {
                    "role": "emb_pick_role",
                    "channel": "emb_pick_target_channel",
                    "user": "emb_pick_user",
                }[kind]),
            ),
            view=picker,
        )

    @ui.button(label="Role", emoji="🎭", style=discord.ButtonStyle.primary)
    async def role(self, interaction: discord.Interaction, item: ui.Button):
        await self._start(interaction, "role")

    @ui.button(label="Channel", emoji="📢", style=discord.ButtonStyle.secondary)
    async def channel(self, interaction: discord.Interaction, item: ui.Button):
        await self._start(interaction, "channel")

    @ui.button(label="User", emoji="👤", style=discord.ButtonStyle.secondary)
    async def user(self, interaction: discord.Interaction, item: ui.Button):
        await self._start(interaction, "user")


class TargetPickerView(ui.View):
    def __init__(self, builder: "BuilderView", lang: str, kind: str) -> None:
        super().__init__(timeout=180)
        self.builder = builder
        self.lang = lang
        self.kind = kind
        if kind == "role":
            select = ui.RoleSelect(
                placeholder=i18n.tl(lang, "emb_pick_role"),
                min_values=1, max_values=1,
            )
        elif kind == "channel":
            select = ui.ChannelSelect(
                placeholder=i18n.tl(lang, "emb_pick_target_channel"),
                channel_types=[discord.ChannelType.text],
                min_values=1, max_values=1,
            )
        else:
            select = ui.UserSelect(
                placeholder=i18n.tl(lang, "emb_pick_user"),
                min_values=1, max_values=1,
            )
        select.callback = self._on_pick
        self.add_item(select)

    async def _on_pick(self, interaction: discord.Interaction) -> None:
        if not await _guard(interaction, self.builder.owner_id):
            return
        values = interaction.data.get("values") or []
        if not values:
            return
        raw_id = int(values[0])
        label = self.kind.title()
        emoji = ""
        if self.kind == "role":
            role = interaction.guild.get_role(raw_id) if interaction.guild else None
            label = role.name if role else "Role"
            emoji = "🎭"
        elif self.kind == "channel":
            channel = interaction.guild.get_channel(raw_id) if interaction.guild else None
            label = channel.name if channel else "Channel"
            emoji = "📢"
        else:
            member = interaction.guild.get_member(raw_id) if interaction.guild else None
            label = member.display_name if member else "Support"
            emoji = "👤"

        if len(self.builder.state["buttons"]) >= MAX_BUTTONS:
            await interaction.response.edit_message(
                embed=error_embed(
                    i18n.tl(self.lang, "emb_full"),
                    i18n.tl(self.lang, "emb_full_buttons"),
                ),
                view=None,
            )
            return

        self.builder.state["buttons"].append({
            "type": self.kind,
            "label": str(label)[:80],
            "target_id": raw_id,
            "style": "secondary",
            "emoji": emoji,
        })
        await interaction.response.edit_message(
            embed=success_embed(
                i18n.tl(self.lang, "success"),
                i18n.tl(self.lang, "emb_add_action"),
            ),
            view=None,
        )
        await self.builder.push_update()


class SendPickerView(ui.View):
    def __init__(self, builder: "BuilderView", lang: str) -> None:
        super().__init__(timeout=180)
        self.builder = builder
        self.lang = lang
        select = ui.ChannelSelect(
            placeholder=i18n.tl(lang, "emb_pick_channel"),
            channel_types=[discord.ChannelType.text],
            min_values=1, max_values=1,
        )
        select.callback = self._on_pick
        self.add_item(select)

    async def _on_pick(self, interaction: discord.Interaction) -> None:
        if not await _guard(interaction, self.builder.owner_id):
            return
        values = interaction.data.get("values") or []
        if not values:
            return
        channel = interaction.guild.get_channel(int(values[0])) if interaction.guild else None
        if channel is None:
            await interaction.response.edit_message(
                embed=error_embed(
                    i18n.tl(self.lang, "panel_channel_not_found"),
                    i18n.tl(self.lang, "panel_channel_not_found_desc"),
                ),
                view=None,
            )
            return
        try:
            await channel.send(
                embed=state_to_embed(self.builder.state, self.lang, preview=False),
                view=state_to_view(self.builder.state, self.lang),
            )
        except discord.HTTPException as exc:
            await interaction.response.edit_message(
                embed=error_embed(
                    i18n.tl(self.lang, "emb_sent"), str(exc)),
                view=None,
            )
            return
        # Keep the builder open; confirm in a separate ephemeral message.
        await interaction.response.edit_message(
            embed=self.builder.preview_embed(), view=self.builder)
        await interaction.followup.send(
            embed=success_embed(
                i18n.tl(self.lang, "emb_sent"),
                i18n.tl(self.lang, "emb_sent_desc", channel=channel.mention),
            ),
            ephemeral=True,
        )


class LoadPickerView(ui.View):
    def __init__(self, builder: "BuilderView", lang: str,
                 templates: list[dict], delete: bool = False) -> None:
        super().__init__(timeout=180)
        self.builder = builder
        self.lang = lang
        self.delete_mode = delete
        options = [
            discord.SelectOption(
                label=str(t["name"])[:100],
                value=str(t["id"]),
                description=(f"#{t['id']}" if not t.get("updated_at")
                             else f"#{t['id']} • {t['updated_at']}"),
            )
            for t in templates[:25]
        ]
        select = ui.Select(
            placeholder=i18n.tl(lang, "emb_pick_template"),
            options=options, min_values=1, max_values=1,
        )
        select.callback = self._on_pick
        self.add_item(select)

    async def _on_pick(self, interaction: discord.Interaction) -> None:
        if not await _guard(interaction, self.builder.owner_id):
            return
        values = interaction.data.get("values") or []
        if not values:
            return
        template_id = int(values[0])
        try:
            row = await asyncio.to_thread(db.embed_get, template_id)
        except Exception:
            row = None
        if row is None:
            await interaction.response.edit_message(
                embed=error_embed(
                    i18n.tl(self.lang, "emb_not_found"),
                    i18n.tl(self.lang, "emb_list_empty_desc"),
                ),
                view=None,
            )
            return
        if self.delete_mode:
            try:
                await asyncio.to_thread(db.embed_delete, template_id)
            except Exception as exc:
                await interaction.response.edit_message(
                    embed=error_embed(i18n.tl(self.lang, "emb_not_found"), str(exc)),
                    view=None,
                )
                return
            await interaction.response.edit_message(
                embed=self.builder.preview_embed(), view=self.builder)
            await interaction.followup.send(
                embed=success_embed(
                    i18n.tl(self.lang, "emb_deleted"),
                    i18n.tl(self.lang, "emb_deleted_desc", name=row["name"]),
                ),
                ephemeral=True,
            )
            if self.builder.template_id == template_id:
                self.builder.template_id = None
                self.builder.template_name = None
            return

        try:
            parsed = json.loads(row.get("data") or "{}")
        except (json.JSONDecodeError, TypeError):
            parsed = {}
        self.builder.state = normalize_state(parsed)
        self.builder.template_id = int(row["id"])
        self.builder.template_name = row["name"]
        await interaction.response.edit_message(
            embed=self.builder.preview_embed(), view=self.builder
        )


# ---------------------------------------------------------------------------
# Builder view
# ---------------------------------------------------------------------------
class BuilderView(ui.View):
    def __init__(self, owner_id: int, lang: str, state: dict | None = None,
                 template_id: int | None = None,
                 template_name: str | None = None) -> None:
        super().__init__(timeout=900)
        self.owner_id = owner_id
        self.lang = lang
        self.state = normalize_state(state or new_state())
        self.template_id = template_id
        self.template_name = template_name
        self.message: discord.Message | None = None

    # -- rendering -----------------------------------------------------
    def preview_embed(self) -> discord.Embed:
        return state_to_embed(self.state, self.lang, preview=True)

    async def push_update(self) -> None:
        if self.message is None:
            return
        try:
            await self.message.edit(embed=self.preview_embed(), view=self)
        except discord.HTTPException:
            pass

    def _label(self, key: str) -> str:
        return i18n.tl(self.lang, key)

    # -- simple text slots --------------------------------------------
    @ui.button(label="Title", emoji="📝", style=discord.ButtonStyle.primary)
    async def edit_title(self, interaction: discord.Interaction, item: ui.Button):
        await interaction.response.send_modal(TextModal(
            self, "title", self._label("emb_edit_title"),
            self._label("emb_edit_title"), 256,
            self.state["embed"]["title"]))

    @ui.button(label="Description", emoji="📄", style=discord.ButtonStyle.primary)
    async def edit_description(self, interaction: discord.Interaction, item: ui.Button):
        await interaction.response.send_modal(TextModal(
            self, "description", self._label("emb_edit_description"),
            self._label("emb_edit_description"), 4000,
            self.state["embed"]["description"]))

    @ui.button(label="Color", emoji="🎨", style=discord.ButtonStyle.secondary)
    async def edit_color(self, interaction: discord.Interaction, item: ui.Button):
        await interaction.response.send_modal(ColorModal(self, self.lang))

    @ui.button(label="Footer", emoji="📌", style=discord.ButtonStyle.secondary)
    async def edit_footer(self, interaction: discord.Interaction, item: ui.Button):
        await interaction.response.send_modal(TextModal(
            self, "footer", self._label("emb_edit_footer"),
            self._label("emb_edit_footer"), 2048,
            self.state["embed"]["footer"]))

    @ui.button(label="Author", emoji="✍️", style=discord.ButtonStyle.secondary)
    async def edit_author(self, interaction: discord.Interaction, item: ui.Button):
        await interaction.response.send_modal(TextModal(
            self, "author", self._label("emb_edit_author"),
            self._label("emb_edit_author"), 256,
            self.state["embed"]["author"]))

    @ui.button(label="Thumbnail", emoji="🖼️", style=discord.ButtonStyle.secondary)
    async def edit_thumbnail(self, interaction: discord.Interaction, item: ui.Button):
        await interaction.response.send_modal(TextModal(
            self, "thumbnail", self._label("emb_edit_thumb"),
            self._label("emb_edit_thumb"), 512,
            self.state["embed"]["thumbnail"], placeholder="https://..."))

    @ui.button(label="Image", emoji="🏞️", style=discord.ButtonStyle.secondary)
    async def edit_image(self, interaction: discord.Interaction, item: ui.Button):
        await interaction.response.send_modal(TextModal(
            self, "image", self._label("emb_edit_image"),
            self._label("emb_edit_image"), 512,
            self.state["embed"]["image"], placeholder="https://..."))

    @ui.button(label="Add field", emoji="➕", style=discord.ButtonStyle.success)
    async def add_field(self, interaction: discord.Interaction, item: ui.Button):
        await interaction.response.send_modal(FieldModal(self, self.lang))

    @ui.button(label="Clear fields", emoji="🧹", style=discord.ButtonStyle.danger)
    async def clear_fields(self, interaction: discord.Interaction, item: ui.Button):
        self.state["embed"]["fields"] = []
        await interaction.response.edit_message(
            embed=self.preview_embed(), view=self)

    @ui.button(label="Rename", emoji="✏️", style=discord.ButtonStyle.secondary)
    async def rename_last(self, interaction: discord.Interaction, item: ui.Button):
        if not self.state["buttons"]:
            await interaction.response.send_message(
                embed=error_embed(
                    i18n.tl(self.lang, "emb_remove_last"),
                    i18n.tl(self.lang, "emb_no_buttons"),
                ),
                ephemeral=True,
            )
            return
        await interaction.response.send_modal(RenameButtonModal(self, self.lang))

    @ui.button(label="Link", emoji="🔗", style=discord.ButtonStyle.success)
    async def add_link(self, interaction: discord.Interaction, item: ui.Button):
        await interaction.response.send_modal(LinkButtonModal(self, self.lang))

    @ui.button(label="Action", emoji="⚙️", style=discord.ButtonStyle.success)
    async def add_action(self, interaction: discord.Interaction, item: ui.Button):
        await interaction.response.edit_message(
            embed=info_embed(
                i18n.tl(self.lang, "emb_add_action"),
                i18n.tl(self.lang, "emb_action_kind"),
            ),
            view=ActionMenuView(self, self.lang),
        )

    @ui.button(label="Remove", emoji="🗑️", style=discord.ButtonStyle.danger)
    async def remove_last(self, interaction: discord.Interaction, item: ui.Button):
        if self.state["buttons"]:
            self.state["buttons"].pop()
        await interaction.response.edit_message(
            embed=self.preview_embed(), view=self)

    @ui.button(label="Send", emoji="📤", style=discord.ButtonStyle.primary)
    async def send(self, interaction: discord.Interaction, item: ui.Button):
        await interaction.response.edit_message(
            embed=info_embed(
                i18n.tl(self.lang, "emb_send"),
                i18n.tl(self.lang, "emb_pick_channel"),
            ),
            view=SendPickerView(self, self.lang),
        )

    @ui.button(label="Save", emoji="💾", style=discord.ButtonStyle.success)
    async def save(self, interaction: discord.Interaction, item: ui.Button):
        await interaction.response.send_modal(SaveModal(self, self.lang))

    @ui.button(label="Load", emoji="📂", style=discord.ButtonStyle.secondary)
    async def load(self, interaction: discord.Interaction, item: ui.Button):
        try:
            templates = await asyncio.to_thread(db.embed_list)
        except Exception as exc:
            await interaction.response.send_message(
                embed=error_embed(
                    i18n.tl(self.lang, "emb_list_empty"),
                    i18n.tl(self.lang, "emb_no_platform") + f"\n`{exc}`",
                ),
                ephemeral=True,
            )
            return
        if not templates:
            await interaction.response.send_message(
                embed=info_embed(
                    i18n.tl(self.lang, "emb_list_empty"),
                    i18n.tl(self.lang, "emb_list_empty_desc"),
                ),
                ephemeral=True,
            )
            return
        await interaction.response.edit_message(
            embed=info_embed(
                i18n.tl(self.lang, "emb_load"),
                i18n.tl(self.lang, "emb_pick_template"),
            ),
            view=LoadPickerView(self, self.lang, templates),
        )

    @ui.button(label="Delete", emoji="❌", style=discord.ButtonStyle.danger)
    async def delete_template(self, interaction: discord.Interaction, item: ui.Button):
        try:
            templates = await asyncio.to_thread(db.embed_list)
        except Exception as exc:
            await interaction.response.send_message(
                embed=error_embed(
                    i18n.tl(self.lang, "emb_not_found"), str(exc)),
                ephemeral=True,
            )
            return
        if not templates:
            await interaction.response.send_message(
                embed=info_embed(
                    i18n.tl(self.lang, "emb_list_empty"),
                    i18n.tl(self.lang, "emb_list_empty_desc"),
                ),
                ephemeral=True,
            )
            return
        await interaction.response.edit_message(
            embed=info_embed(
                i18n.tl(self.lang, "emb_delete_tpl"),
                i18n.tl(self.lang, "emb_pick_template"),
            ),
            view=LoadPickerView(self, self.lang, templates, delete=True),
        )

    @ui.button(label="Close", emoji="🚪", style=discord.ButtonStyle.secondary)
    async def close(self, interaction: discord.Interaction, item: ui.Button):
        await interaction.response.edit_message(
            embed=info_embed(
                i18n.tl(self.lang, "emb_title"),
                i18n.tl(self.lang, "close"),
            ),
            view=None,
        )


# ---------------------------------------------------------------------------
# Cog
# ---------------------------------------------------------------------------
class EmbedCog(commands.Cog):
    def __init__(self, bot: commands.Bot) -> None:
        self.bot = bot

    embed_group = app_commands.Group(
        name="embed", description="Embed builder and templates")

    @embed_group.command(name="builder", description="Open the embed builder")
    @admin_only()
    async def builder(self, interaction: discord.Interaction) -> None:
        lang = i18n.get_lang(interaction.user.id)
        view = BuilderView(interaction.user.id, lang)
        await interaction.response.send_message(
            embed=view.preview_embed(), view=view, ephemeral=True)
        view.message = await interaction.original_response()

    @embed_group.command(name="list", description="List saved embed templates")
    @admin_only()
    async def list_templates(self, interaction: discord.Interaction) -> None:
        lang = i18n.get_lang(interaction.user.id)
        await interaction.response.defer(ephemeral=True, thinking=True)
        try:
            templates = await asyncio.to_thread(db.embed_list)
        except Exception as exc:
            await interaction.followup.send(
                embed=error_embed(
                    i18n.tl(lang, "emb_list_empty"),
                    i18n.tl(lang, "emb_no_platform") + f"\n`{exc}`",
                ),
                ephemeral=True,
            )
            return
        if not templates:
            await interaction.followup.send(
                embed=info_embed(
                    i18n.tl(lang, "emb_list_empty"),
                    i18n.tl(lang, "emb_list_empty_desc"),
                ),
                ephemeral=True,
            )
            return
        lines = [
            f"`#{t['id']}` **{t['name']}** — {t.get('updated_at') or '-'}"
            for t in templates[:25]
        ]
        await interaction.followup.send(
            embed=info_embed(
                i18n.tl(lang, "emb_load"),
                "\n".join(lines)[:4000],
            ),
            ephemeral=True,
        )

    @embed_group.command(name="send", description="Post a saved template")
    @app_commands.describe(name="Template name", channel="Where to post it")
    @admin_only()
    async def send_template(
        self, interaction: discord.Interaction, name: str,
        channel: discord.TextChannel | None = None,
    ) -> None:
        lang = i18n.get_lang(interaction.user.id)
        target = channel or interaction.channel
        await interaction.response.defer(ephemeral=True, thinking=True)
        try:
            templates = await asyncio.to_thread(db.embed_list)
            match = next(
                (t for t in templates if t["name"].lower() == name.strip().lower()),
                None,
            )
            if match is None:
                await interaction.followup.send(
                    embed=error_embed(
                        i18n.tl(lang, "emb_not_found"),
                        i18n.tl(lang, "emb_pick_template"),
                    ),
                    ephemeral=True,
                )
                return
            row = await asyncio.to_thread(db.embed_get, int(match["id"]))
            if row is None:
                raise ValueError("template not found")
            state = normalize_state(json.loads(row.get("data") or "{}"))
            await target.send(
                embed=state_to_embed(state, lang, preview=False),
                view=state_to_view(state, lang),
            )
        except Exception as exc:
            await interaction.followup.send(
                embed=error_embed(
                    i18n.tl(lang, "emb_sent"), str(exc)),
                ephemeral=True,
            )
            return
        await interaction.followup.send(
            embed=success_embed(
                i18n.tl(lang, "emb_sent"),
                i18n.tl(lang, "emb_sent_desc", channel=target.mention),
            ),
            ephemeral=True,
        )

    @embed_group.command(name="delete", description="Delete a saved template")
    @app_commands.describe(name="Template name")
    @admin_only()
    async def delete_template(
        self, interaction: discord.Interaction, name: str
    ) -> None:
        lang = i18n.get_lang(interaction.user.id)
        await interaction.response.defer(ephemeral=True, thinking=True)
        try:
            templates = await asyncio.to_thread(db.embed_list)
            match = next(
                (t for t in templates if t["name"].lower() == name.strip().lower()),
                None,
            )
            if match is None or not await asyncio.to_thread(
                db.embed_delete, int(match["id"])
            ):
                await interaction.followup.send(
                    embed=error_embed(
                        i18n.tl(lang, "emb_not_found"), name),
                    ephemeral=True,
                )
                return
        except Exception as exc:
            await interaction.followup.send(
                embed=error_embed(
                    i18n.tl(lang, "emb_not_found"), str(exc)),
                ephemeral=True,
            )
            return
        await interaction.followup.send(
            embed=success_embed(
                i18n.tl(lang, "emb_deleted"),
                i18n.tl(lang, "emb_deleted_desc", name=name),
            ),
            ephemeral=True,
        )

    # -- action buttons (role / channel / user) ------------------------
    @commands.Cog.listener()
    async def on_interaction(self, interaction: discord.Interaction) -> None:
        if interaction.type != discord.InteractionType.component:
            return
        custom_id = str((interaction.data or {}).get("custom_id") or "")
        if not custom_id.startswith(f"{PREFIX}:"):
            return
        parts = custom_id.split(":")
        if len(parts) != 3:
            return
        kind, raw_target = parts[1], parts[2]
        if not raw_target.isdigit():
            return
        target_id = int(raw_target)
        lang = i18n.get_lang(interaction.user.id)

        if interaction.guild is None:
            await interaction.response.send_message(
                embed=error_embed(
                    i18n.tl(lang, "no_permission"),
                    i18n.tl(lang, "emb_role_denied"),
                ),
                ephemeral=True,
            )
            return

        if kind == "role":
            role = interaction.guild.get_role(target_id)
            if role is None:
                await interaction.response.send_message(
                    embed=error_embed(
                        i18n.tl(lang, "emb_role_ok"),
                        i18n.tl(lang, "emb_role_denied"),
                    ),
                    ephemeral=True,
                )
                return
            try:
                if role in interaction.user.roles:
                    await interaction.user.remove_roles(
                        role, reason="Embed button")
                    text = i18n.tl(lang, "emb_role_removed", role=role.mention)
                else:
                    await interaction.user.add_roles(
                        role, reason="Embed button")
                    text = i18n.tl(lang, "emb_role_added", role=role.mention)
            except (discord.Forbidden, discord.HTTPException):
                await interaction.response.send_message(
                    embed=error_embed(
                        i18n.tl(lang, "emb_role_ok"),
                        i18n.tl(lang, "emb_role_denied"),
                    ),
                    ephemeral=True,
                )
                return
            await interaction.response.send_message(
                embed=success_embed(
                    i18n.tl(lang, "emb_role_ok"), text),
                ephemeral=True,
            )
            return

        if kind == "channel":
            channel = interaction.guild.get_channel(target_id)
            mention = channel.mention if channel else f"`{target_id}`"
            await interaction.response.send_message(
                embed=info_embed(
                    i18n.tl(lang, "emb_action_channel"),
                    i18n.tl(lang, "emb_channel_hint", channel=mention),
                ),
                ephemeral=True,
            )
            return

        if kind == "user":
            member = interaction.guild.get_member(target_id)
            mention = member.mention if member else f"<@{target_id}>"
            await interaction.response.send_message(
                embed=info_embed(
                    i18n.tl(lang, "emb_action_user"),
                    i18n.tl(lang, "emb_user_hint", user=mention),
                ),
                ephemeral=True,
            )
            return


async def setup(bot: commands.Bot) -> None:
    await bot.add_cog(EmbedCog(bot))
