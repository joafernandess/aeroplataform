"""
Shop editor inside Discord — change products, prices and payment details
without touching shop.json by hand.

  /shopedit  - opens the editor (admin)
  /postshop  - posts the shop panel and opens the editor right below it

The editor shows a live preview of the shop panel plus:
  ✏️ Edit product (menu)  - name, price, price in BRL, validity, description
  ➕ Add product / 🗑️ Remove product
  📝 Texts                - title, description, how-to-buy instructions
  💳 Payments             - Pix key type, Pix key, PayPal link

Every save is validated (shop_config.normalize), written atomically, logged
with what changed, and every shop panel the bot posted is updated in place,
so new prices show up immediately in all channels.
"""
from __future__ import annotations

import asyncio
import logging
import re

import discord
from discord import app_commands, ui
from discord.ext import commands

import catalog
import config
import logger
import shop_config
from utils import admin_only, error_embed, info_embed, success_embed

log = logging.getLogger("keybot.shop_editor")

_PANELS = "shop:panels"  # [[channel_id, message_id], ...] of posted shop panels


def _is_admin(user) -> bool:
    return any(r.id == config.ADMIN_ROLE_ID for r in getattr(user, "roles", []))


def _kv(name: str):
    found = catalog.get_kv(name)
    return found[0] if found else None


def remember_panel(message: discord.Message) -> None:
    """Called by /postshop so later edits can refresh this panel."""
    panels = _kv(_PANELS) or []
    entry = [message.channel.id, message.id]
    if entry not in panels:
        panels.append(entry)
    catalog.set_kv(_PANELS, panels[-25:])


def _slug(name: str, taken: set[str]) -> str:
    base = re.sub(r"[^A-Za-z0-9_-]+", "-", name.strip().lower()).strip("-")[:30] or "product"
    slug, n = base, 2
    while slug in taken:
        slug, n = f"{base}-{n}", n + 1
    return slug


def _changes(old: dict, new: dict) -> str:
    """Human summary of what a save changed (for the log channel)."""
    lines = []
    for field in ("title", "description", "instructions"):
        if (old.get(field) or "") != (new.get(field) or ""):
            lines.append(f"• {field} changed")
    old_p = {p.get("id"): p for p in old.get("products") or []}
    new_p = {p.get("id"): p for p in new.get("products") or []}
    for pid, p in new_p.items():
        before = old_p.get(pid)
        if before is None:
            lines.append(f"• added **{p.get('name')}** ({p.get('price')})")
            continue
        for f in ("name", "price", "price_brl", "days", "description"):
            if before.get(f) != p.get(f):
                lines.append(f"• {p.get('name')}: {f} `{before.get(f)}` → `{p.get(f)}`")
    for pid, p in old_p.items():
        if pid not in new_p:
            lines.append(f"• removed **{p.get('name')}**")
    op, np_ = old.get("payments") or {}, new.get("payments") or {}
    for f in ("pix_type", "pix_key", "paypal_url"):
        if (op.get(f) or "") != (np_.get(f) or ""):
            lines.append(f"• payments: {f} changed")
    return "\n".join(lines) or "• no changes"


# ---------------------------------------------------------------------------
# Saving + refreshing everything that shows the shop
# ---------------------------------------------------------------------------
async def apply_changes(
    bot: commands.Bot, interaction: discord.Interaction, new_data: dict
) -> dict | None:
    """Validates + saves, refreshes posted panels and ticket menus, logs."""
    old = await asyncio.to_thread(shop_config.load)
    try:
        saved = await asyncio.to_thread(shop_config.save, new_data)
    except shop_config.ShopConfigError as exc:
        await interaction.followup.send(
            embed=error_embed("Not saved", str(exc)), ephemeral=True
        )
        return None

    from cogs import shop as shop_cog  # late import: avoids a cycle

    # 1. Posted shop panels
    panels = await asyncio.to_thread(_kv, _PANELS) or []
    alive = []
    cog = bot.get_cog("ShopCog")
    for channel_id, message_id in panels:
        try:
            channel = bot.get_channel(channel_id) or await bot.fetch_channel(channel_id)
            message = await channel.fetch_message(message_id)  # type: ignore[union-attr]
            await message.edit(
                embed=shop_cog.build_shop_embed(saved), view=shop_cog.ShopView(cog)
            )
            alive.append([channel_id, message_id])
        except discord.NotFound:
            continue  # panel deleted: forget it
        except discord.HTTPException as exc:
            log.warning("Could not refresh shop panel %s: %s", message_id, exc)
            alive.append([channel_id, message_id])
    await asyncio.to_thread(catalog.set_kv, _PANELS, alive)

    # 2. Ticket product menu (persistent view) follows the new product list
    bot.add_view(shop_cog.TicketView(cog, shop_cog._products(saved)))

    logger.log_event(
        info_embed(
            "Shop edited",
            f"By: {interaction.user.mention}\n{_changes(old, saved)}\n"
            f"Panels refreshed: {len(alive)}",
        )
    )
    return saved


# ---------------------------------------------------------------------------
# Modals
# ---------------------------------------------------------------------------
class ProductModal(ui.Modal):
    def __init__(self, editor: "ShopEditorView", product: dict | None) -> None:
        super().__init__(title="Edit product" if product else "Add product")
        self.editor = editor
        self.product_id = product.get("id") if product else None
        p = product or {}
        self.name = ui.TextInput(label="Name", default=p.get("name"), max_length=80)
        self.price = ui.TextInput(
            label="Price (as shown, e.g. $9.00)", default=p.get("price"), max_length=30
        )
        self.price_brl = ui.TextInput(
            label="Price in BRL for auto Pix (optional)",
            default=str(p["price_brl"]) if p.get("price_brl") is not None else None,
            required=False, max_length=12,
        )
        self.days = ui.TextInput(
            label="Key validity in days (0 = permanent)",
            default=str(p.get("days", 30)), max_length=4,
        )
        self.description = ui.TextInput(
            label="Description", default=p.get("description"), required=False,
            style=discord.TextStyle.paragraph, max_length=200,
        )
        for item in (self.name, self.price, self.price_brl, self.days, self.description):
            self.add_item(item)

    async def on_submit(self, interaction: discord.Interaction) -> None:
        await interaction.response.defer(ephemeral=True)
        data = await asyncio.to_thread(shop_config.load)
        products = [dict(p) for p in data.get("products") or []]
        fields = {
            "name": str(self.name.value).strip(),
            "price": str(self.price.value).strip(),
            "price_brl": str(self.price_brl.value).strip().replace(",", ".") or None,
            "days": str(self.days.value).strip(),
            "description": str(self.description.value).strip(),
        }
        if self.product_id:
            for p in products:
                if p.get("id") == self.product_id:
                    p.update(fields)
                    if fields["price_brl"] is None:
                        p.pop("price_brl", None)
                    break
            else:
                await interaction.followup.send(
                    embed=error_embed("Not found", "That product was removed meanwhile."),
                    ephemeral=True,
                )
                return
        else:
            taken = {str(p.get("id")) for p in products}
            new = {"id": _slug(fields["name"], taken), **fields}
            if new["price_brl"] is None:
                new.pop("price_brl")
            products.append(new)
        data["products"] = products
        await self.editor.save(interaction, data)


class TextsModal(ui.Modal, title="Shop texts"):
    def __init__(self, editor: "ShopEditorView", data: dict) -> None:
        super().__init__()
        self.editor = editor
        self.shop_title = ui.TextInput(label="Title", default=data.get("title"), max_length=100)
        self.description = ui.TextInput(
            label="Description", default=data.get("description"), required=False,
            style=discord.TextStyle.paragraph, max_length=1000,
        )
        self.instructions = ui.TextInput(
            label="How to buy (instructions)", default=data.get("instructions"),
            required=False, style=discord.TextStyle.paragraph, max_length=2000,
        )
        for item in (self.shop_title, self.description, self.instructions):
            self.add_item(item)

    async def on_submit(self, interaction: discord.Interaction) -> None:
        await interaction.response.defer(ephemeral=True)
        data = await asyncio.to_thread(shop_config.load)
        data["title"] = str(self.shop_title.value).strip()
        data["description"] = str(self.description.value).strip()
        data["instructions"] = str(self.instructions.value).strip()
        await self.editor.save(interaction, data)


class PaymentsModal(ui.Modal, title="Payment details"):
    def __init__(self, editor: "ShopEditorView", data: dict) -> None:
        super().__init__()
        self.editor = editor
        pay = data.get("payments") or {}
        self.pix_type = ui.TextInput(
            label="Pix key type (E-mail / CPF / Phone...)", default=pay.get("pix_type"),
            required=False, max_length=60,
        )
        self.pix_key = ui.TextInput(
            label="Pix key (empty = no Pix)", default=pay.get("pix_key"),
            required=False, max_length=200,
        )
        self.paypal = ui.TextInput(
            label="PayPal link (empty = no PayPal)", default=pay.get("paypal_url"),
            required=False, max_length=300,
        )
        for item in (self.pix_type, self.pix_key, self.paypal):
            self.add_item(item)

    async def on_submit(self, interaction: discord.Interaction) -> None:
        await interaction.response.defer(ephemeral=True)
        data = await asyncio.to_thread(shop_config.load)
        data["payments"] = {
            "pix_type": str(self.pix_type.value).strip(),
            "pix_key": str(self.pix_key.value).strip(),
            "paypal_url": str(self.paypal.value).strip(),
        }
        await self.editor.save(interaction, data)


# ---------------------------------------------------------------------------
# Editor view
# ---------------------------------------------------------------------------
class ShopEditorView(ui.View):
    def __init__(self, bot: commands.Bot, data: dict) -> None:
        super().__init__(timeout=900)
        self.bot = bot
        self.message: discord.InteractionMessage | None = None
        self._build(data)

    def _build(self, data: dict) -> None:
        self.clear_items()
        products = [p for p in data.get("products") or [] if isinstance(p, dict)]
        if products:
            edit = ui.Select(
                placeholder="✏️ Edit a product / price…",
                options=[
                    discord.SelectOption(
                        label=str(p.get("name", "?"))[:100],
                        value=str(p.get("id"))[:100],
                        description=f"{p.get('price', '-')} • {p.get('days', 30) or 'permanent'} days"[:100],
                    )
                    for p in products[:25]
                ],
                row=0,
            )
            edit.callback = self._on_edit
            self.add_item(edit)
            remove = ui.Select(
                placeholder="🗑️ Remove a product…",
                options=[
                    discord.SelectOption(label=str(p.get("name", "?"))[:100], value=str(p.get("id"))[:100])
                    for p in products[:25]
                ],
                row=1,
            )
            remove.callback = self._on_remove
            self.add_item(remove)
        for label, emoji, cb in (
            ("Add product", "➕", self._on_add),
            ("Texts", "📝", self._on_texts),
            ("Payments", "💳", self._on_payments),
        ):
            button = ui.Button(label=label, emoji=emoji, style=discord.ButtonStyle.secondary, row=2)
            button.callback = cb
            self.add_item(button)

    async def interaction_check(self, interaction: discord.Interaction) -> bool:
        if _is_admin(interaction.user):
            return True
        await interaction.response.send_message(
            embed=error_embed("No permission", "Only administrators can edit the shop."),
            ephemeral=True,
        )
        return False

    async def save(self, interaction: discord.Interaction, data: dict) -> None:
        saved = await apply_changes(self.bot, interaction, data)
        if saved is None:
            return
        await self.refresh(saved)
        await interaction.followup.send(
            embed=success_embed("Shop saved", "Every posted shop panel was updated."),
            ephemeral=True,
        )

    async def refresh(self, data: dict) -> None:
        self._build(data)
        if self.message is not None:
            try:
                await self.message.edit(embeds=editor_embeds(data), view=self)
            except discord.HTTPException:
                pass

    # -- callbacks ------------------------------------------------------
    @staticmethod
    def _picked(interaction: discord.Interaction) -> str | None:
        values = (interaction.data or {}).get("values") or []
        return values[0] if values else None

    async def _on_edit(self, interaction: discord.Interaction) -> None:
        pid = self._picked(interaction)
        data = await asyncio.to_thread(shop_config.load)
        product = next((p for p in data.get("products") or [] if p.get("id") == pid), None)
        if product is None:
            await interaction.response.send_message(
                embed=error_embed("Not found", "That product no longer exists."), ephemeral=True
            )
            return
        await interaction.response.send_modal(ProductModal(self, product))

    async def _on_remove(self, interaction: discord.Interaction) -> None:
        pid = self._picked(interaction)
        await interaction.response.defer(ephemeral=True)
        data = await asyncio.to_thread(shop_config.load)
        products = [p for p in data.get("products") or [] if p.get("id") != pid]
        if len(products) == len(data.get("products") or []):
            return
        if not products:
            await interaction.followup.send(
                embed=error_embed("Not removed", "The shop needs at least one product."),
                ephemeral=True,
            )
            return
        data["products"] = products
        await self.save(interaction, data)

    async def _on_add(self, interaction: discord.Interaction) -> None:
        await interaction.response.send_modal(ProductModal(self, None))

    async def _on_texts(self, interaction: discord.Interaction) -> None:
        data = await asyncio.to_thread(shop_config.load)
        await interaction.response.send_modal(TextsModal(self, data))

    async def _on_payments(self, interaction: discord.Interaction) -> None:
        data = await asyncio.to_thread(shop_config.load)
        await interaction.response.send_modal(PaymentsModal(self, data))


def editor_embeds(data: dict) -> list[discord.Embed]:
    from cogs import shop as shop_cog
    head = info_embed(
        "🛠️ Shop editor",
        "Change products, prices and payment details below. Saving updates "
        "every shop panel already posted. Preview:",
    )
    return [head, shop_cog.build_shop_embed(data)]


async def open_editor(bot: commands.Bot, interaction: discord.Interaction) -> None:
    """Sends the editor as a follow-up (the interaction must be deferred)."""
    data = await asyncio.to_thread(shop_config.load)
    view = ShopEditorView(bot, data)
    view.message = await interaction.followup.send(
        embeds=editor_embeds(data), view=view, ephemeral=True, wait=True
    )


class ShopEditorCog(commands.Cog):
    def __init__(self, bot: commands.Bot) -> None:
        self.bot = bot

    @app_commands.command(name="shopedit", description="Edit the shop: products, prices, payments")
    @admin_only()
    async def shopedit(self, interaction: discord.Interaction) -> None:
        await interaction.response.defer(ephemeral=True, thinking=True)
        await open_editor(self.bot, interaction)


async def setup(bot: commands.Bot) -> None:
    await bot.add_cog(ShopEditorCog(bot))
