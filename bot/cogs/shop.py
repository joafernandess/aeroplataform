"""
Sales panel with PRIVATE BUY TICKETS (Luarmor-style shop):

  /postshop - posts the shop panel (product + price + buy button)

Shop panel buttons:
  🛒 Open ticket  - creates a private channel (buyer + staff only)
  📖 How to buy   - step-by-step instructions (ephemeral)

Inside the ticket:
  - the bot pre-selects the product (single price = no menu)
  - 💳 Pix / PayPal  -> posts the payment details (private channel)
  - ✅ I already paid -> pings the staff with an approval message
  - ✅ Approve & deliver key (staff) -> modal (validity/note) ->
    the bot GENERATES the key and DMs it to the buyer automatically
  - ❌ Reject (staff)
  - 🔒 Close ticket (staff) -> confirmation modal, deletes the channel

Also:
  /deliver - sends a purchased key to the buyer by DM (staff)
"""
import asyncio
import io
import json
import logging

import discord
from discord import app_commands
from discord.ext import commands, tasks
from discord import ui

import catalog
import config
import platform_bridge as db
import logger
from payments import MercadoPagoClient, PaymentError
from roles import grant_buyer_role
from utils import (
    error_embed,
    success_embed,
    info_embed,
    admin_only,
    staff_only,
    mask_key,
    price_to_cents,
)


log = logging.getLogger("keybot.shop")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def _is_staff(user) -> bool:
    ids = {role.id for role in getattr(user, "roles", [])}
    if config.ADMIN_ROLE_ID in ids:
        return True
    return bool(config.STAFF_ROLE_ID and config.STAFF_ROLE_ID in ids)


def _load_shop() -> dict:
    """Reads shop.json (raises OSError/ValueError when missing or invalid)."""
    with open(config.SHOP_FILE, "r", encoding="utf-8") as fh:
        return json.load(fh)


def _safe_shop() -> dict:
    try:
        return _load_shop()
    except (OSError, ValueError):
        return {}


def _products(data: dict) -> list[dict]:
    products = data.get("products") or []
    return [p for p in products if isinstance(p, dict)]


def _product_id(product: dict) -> str:
    return str(product.get("id") or product.get("name") or "product")


def build_shop_embed(data: dict) -> discord.Embed:
    embed = discord.Embed(
        title=data.get("title", "Script Shop"),
        description=data.get("description", ""),
        color=config.PANEL_COLOR,
    )
    for product in _products(data):
        embed.add_field(
            name=product.get("name", "Product"),
            value=(
                f"`{product.get('price', '-')}`\n"
                f"{product.get('description', '')}"
            ),
            inline=True,
        )
    payments = data.get("payments") or {}
    methods = []
    if payments.get("pix_key"):
        methods.append("💳 Pix")
    if (payments.get("paypal_url") or "").startswith("http"):
        methods.append("🅿️ PayPal")
    embed.add_field(
        name="Payment methods",
        value=("\n".join(methods) if methods else "Ask a staff member"),
        inline=False,
    )
    embed.set_footer(
        text="Click Open ticket to buy - the ticket is private "
        "(only you and the staff can see it)."
    )
    return embed


def _delivery_embed(result: dict, title: str) -> discord.Embed:
    """What the ticket channel shows after a key was delivered or renewed."""
    dm = (
        " (DM sent ✅)" if result["dm_sent"]
        else " (DM closed ❌ - copy the key from this ticket)"
    )
    if result["renewed"]:
        expiry = (
            "never (permanent)" if not result["expires_at"]
            else db.fmt_date(result["expires_at"])
        )
        return success_embed(
            f"✅ {title} — key renewed",
            f"**Buyer:** <@{result['buyer_id']}>{dm}\n"
            f"**Key:** `{mask_key(result['key'])}`\n"
            f"**New expiration:** {expiry}\n"
            f"**Product:** {result['product'].get('name', 'Product')} "
            f"({result['product'].get('price', '-')})",
        )
    return success_embed(
        f"✅ {title} — key delivered",
        f"**Buyer:** <@{result['buyer_id']}>{dm}\n"
        f"**Key:** `{result['key']}`\n"
        f"**Validity:** {result['days'] if result['days'] else 'permanent'}\n"
        f"**Product:** {result['product'].get('name', 'Product')} "
        f"({result['product'].get('price', '-')})",
    )


# ---------------------------------------------------------------------------
# Confirmation modal to close the ticket
# ---------------------------------------------------------------------------
class CloseTicketModal(ui.Modal, title="Close ticket"):
    reason_input = ui.TextInput(
        label="Reason (optional)",
        style=discord.TextStyle.short,
        required=False,
        max_length=200,
    )

    async def on_submit(self, interaction: discord.Interaction) -> None:
        reason = str(self.reason_input.value).strip() or "Not provided"
        channel_name = getattr(interaction.channel, "name", "?")
        logger.log_event(
            info_embed(
                "Ticket closed",
                f"By: {interaction.user.mention}\n"
                f"Channel: {channel_name}\n"
                f"Reason: {reason}",
            )
        )
        try:
            await interaction.response.send_message(
                embed=success_embed(
                    "Ticket closed",
                    "This channel will be deleted in 3 seconds.",
                ),
                delete_after=3,
            )
        except discord.HTTPException:
            pass
        db.delete_ticket(interaction.channel_id)
        await asyncio.sleep(3)
        try:
            await interaction.channel.delete(
                reason=f"Ticket closed by {interaction.user}"
            )
        except (discord.HTTPException, AttributeError):
            pass


# ---------------------------------------------------------------------------
# Modal: approve the payment and DELIVER THE KEY (auto-generated)
# ---------------------------------------------------------------------------
class ApproveTicketModal(ui.Modal, title="Deliver key"):
    days_input = ui.TextInput(
        label="Validity in days (0 = permanent)",
        style=discord.TextStyle.short,
        default="30",
        max_length=5,
        required=True,
    )
    note_input = ui.TextInput(
        label="Note (optional)",
        style=discord.TextStyle.short,
        required=False,
        max_length=100,
    )

    def __init__(self, cog: "ShopCog") -> None:
        super().__init__()
        self.cog = cog

    async def on_submit(self, interaction: discord.Interaction) -> None:
        try:
            days = int(str(self.days_input.value).strip() or "30")
        except ValueError:
            days = 30
        days = max(0, min(days, 3650))
        note = str(self.note_input.value).strip() or None

        result = await self.cog.fulfill_ticket(
            interaction.channel_id, days, note, str(interaction.user)
        )
        if result is None:
            await interaction.response.send_message(
                embed=error_embed(
                    "Already delivered",
                    "A key was already delivered in this ticket.",
                ),
                ephemeral=True,
            )
            return

        await interaction.response.send_message(
            embed=_delivery_embed(result, "Payment approved")
        )


# ---------------------------------------------------------------------------
# Approval message buttons (staff only)
# ---------------------------------------------------------------------------
class ApprovalView(ui.View):
    def __init__(self, cog: "ShopCog") -> None:
        super().__init__(timeout=None)
        self.cog = cog

    @ui.button(
        label="Approve & deliver key",
        emoji="✅",
        style=discord.ButtonStyle.success,
        custom_id="shop:approve",
    )
    async def approve(
        self, interaction: discord.Interaction, item: discord.ui.Button
    ) -> None:
        if not _is_staff(interaction.user):
            await interaction.response.send_message(
                embed=error_embed(
                    "No permission",
                    "Only staff can approve payments.",
                ),
                ephemeral=True,
            )
            return
        ticket = db.get_ticket(interaction.channel_id)
        if ticket is not None and ticket["approved"]:
            await interaction.response.send_message(
                embed=error_embed(
                    "Already delivered",
                    "A key was already delivered in this ticket.",
                ),
                ephemeral=True,
            )
            return
        await interaction.response.send_modal(ApproveTicketModal(self.cog))

    @ui.button(
        label="Reject",
        emoji="❌",
        style=discord.ButtonStyle.danger,
        custom_id="shop:reject",
    )
    async def reject(
        self, interaction: discord.Interaction, item: discord.ui.Button
    ) -> None:
        if not _is_staff(interaction.user):
            await interaction.response.send_message(
                embed=error_embed(
                    "No permission",
                    "Only staff can reject payments.",
                ),
                ephemeral=True,
            )
            return
        await interaction.response.send_message(
            embed=info_embed(
                "Payment rejected",
                "The buyer was not approved. Explain what happened "
                "in this channel (only you and the buyer can see it).",
            ),
            ephemeral=True,
        )
        logger.log_event(
            error_embed(
                "Ticket payment rejected",
                f"By: {interaction.user.mention}\n"
                f"Channel: {getattr(interaction.channel, 'name', '?')}",
            )
        )


# ---------------------------------------------------------------------------
# View INSIDE the ticket
# ---------------------------------------------------------------------------
class TicketView(ui.View):
    def __init__(self, cog: "ShopCog | None", products: list[dict]) -> None:
        # timeout=None + fixed custom_ids = keeps working after restarts
        super().__init__(timeout=None)
        self.cog = cog

        # The automatic Pix button only exists when Mercado Pago is configured
        if not config.MERCADOPAGO_ACCESS_TOKEN:
            self.remove_item(self.pay_pix_auto)

        # The product menu only appears when there is MORE THAN ONE
        # product (with a single price the ticket goes straight to
        # the payment buttons).
        if len(products) > 1:
            options = [
                discord.SelectOption(
                    label=str(p.get("name", "Product"))[:100],
                    value=_product_id(p)[:100],
                    description=str(p.get("price", ""))[:100] or None,
                    emoji="🎮",
                )
                for p in products[:25]
            ] or [discord.SelectOption(label="Product", value="none")]

            select = ui.Select(
                placeholder="1) Select the product...",
                custom_id="shop:product",
                options=options,
                min_values=1,
                max_values=1,
            )
            select.callback = self._on_select
            self.add_item(select)

    # ------------------------------------------------------------------
    async def _on_select(self, interaction: discord.Interaction) -> None:
        if self.cog is None:
            return
        values = interaction.data.get("values") or []
        if not values:
            return
        product = next(
            (p for p in _products(_safe_shop())
             if _product_id(p) == values[0]),
            None,
        )
        if product is None:
            await interaction.response.send_message(
                embed=error_embed(
                    "Unknown product",
                    "Ask a staff member for help.",
                ),
                ephemeral=True,
            )
            return
        db.set_ticket_product(interaction.channel_id, _product_id(product))
        await interaction.response.send_message(
            embed=success_embed(
                "Product selected",
                f"**{product.get('name', '?')}** — "
                f"`{product.get('price', '-')}`\n"
                "Now choose the **payment method** below.",
            ),
            ephemeral=True,
        )

    # ------------------------------------------------------------------
    async def _payment(self, interaction: discord.Interaction, method: str) -> None:
        if self.cog is None:
            return
        product = self.cog.selected_product(interaction.channel_id)
        if product is None:
            await interaction.response.send_message(
                embed=error_embed(
                    "Select a product first",
                    "Use the menu above to select the product, "
                    "then choose the payment method.",
                ),
                ephemeral=True,
            )
            return

        payments = (_safe_shop().get("payments")) or {}
        price = product.get("price", "-")
        name = product.get("name", "Product")

        if method == "pix":
            pix_key = payments.get("pix_key", "not configured")
            pix_type = payments.get("pix_type", "")
            embed = discord.Embed(
                title=f"💳 Pay with Pix — {name}",
                description=(
                    f"**Price:** `{price}`\n"
                    f"**Pix type:** {pix_type or '-'}\n\n"
                    f"```{pix_key}```\n"
                    "Copy the key and pay in your bank app.\n"
                    "**After paying, send the receipt here and click "
                    "\"I already paid\".**"
                ),
                color=config.PANEL_COLOR,
            )
        else:  # paypal
            url = (payments.get("paypal_url") or "").strip()
            if not url.startswith("http"):
                await interaction.response.send_message(
                    embed=error_embed(
                        "PayPal not configured",
                        "Ask a staff member for the payment details.",
                    ),
                    ephemeral=True,
                )
                return
            embed = discord.Embed(
                title=f"🅿️ Pay with PayPal — {name}",
                description=(
                    f"**Price:** `{price}`\n\n"
                    f"Pay here: {url}\n\n"
                    "**After paying, send the receipt here and click "
                    "\"I already paid\".**"
                ),
                color=config.PANEL_COLOR,
            )

        await interaction.response.send_message(embed=embed)
        logger.log_event(
            info_embed(
                "Payment details requested",
                f"Buyer: {interaction.user.mention}\n"
                f"Product: {name} ({price})\nMethod: {method.upper()}",
            )
        )

    # ------------------------------------------------------------------
    @ui.button(
        label="Pix (automatic)",
        emoji="⚡",
        style=discord.ButtonStyle.success,
        custom_id="shop:pay_pix_auto",
    )
    async def pay_pix_auto(
        self, interaction: discord.Interaction, item: discord.ui.Button
    ) -> None:
        if self.cog is None:
            return
        await self.cog.start_auto_pix(interaction)

    @ui.button(
        label="Pix",
        emoji="💳",
        style=discord.ButtonStyle.success,
        custom_id="shop:pay_pix",
    )
    async def pay_pix(
        self, interaction: discord.Interaction, item: discord.ui.Button
    ) -> None:
        await self._payment(interaction, "pix")

    @ui.button(
        label="PayPal",
        emoji="🅿️",
        style=discord.ButtonStyle.primary,
        custom_id="shop:pay_paypal",
    )
    async def pay_paypal(
        self, interaction: discord.Interaction, item: discord.ui.Button
    ) -> None:
        await self._payment(interaction, "paypal")

    @ui.button(
        label="I already paid",
        emoji="✅",
        style=discord.ButtonStyle.primary,
        custom_id="shop:paid",
    )
    async def paid(
        self, interaction: discord.Interaction, item: discord.ui.Button
    ) -> None:
        if self.cog is None:
            return
        await self.cog.notify_paid(interaction)

    @ui.button(
        label="Close ticket",
        emoji="🔒",
        style=discord.ButtonStyle.danger,
        custom_id="shop:close",
    )
    async def close_ticket(
        self, interaction: discord.Interaction, item: discord.ui.Button
    ) -> None:
        if not _is_staff(interaction.user):
            await interaction.response.send_message(
                embed=error_embed(
                    "No permission",
                    "Only staff can close tickets.",
                ),
                ephemeral=True,
            )
            return
        await interaction.response.send_modal(CloseTicketModal())


# ---------------------------------------------------------------------------
# View of the SHOP PANEL (what buyers click)
# ---------------------------------------------------------------------------
class ShopView(ui.View):
    def __init__(self, cog: "ShopCog | None" = None) -> None:
        super().__init__(timeout=None)
        self.cog = cog

    @ui.button(
        label="Open ticket",
        emoji="🛒",
        style=discord.ButtonStyle.success,
        custom_id="shop:buy",
    )
    async def buy(
        self, interaction: discord.Interaction, item: discord.ui.Button
    ) -> None:
        if self.cog is None:
            return
        await self.cog.open_ticket(interaction)

    @ui.button(
        label="How to buy",
        emoji="📖",
        style=discord.ButtonStyle.secondary,
        custom_id="shop:howto",
    )
    async def how_to_buy(
        self, interaction: discord.Interaction, item: discord.ui.Button
    ) -> None:
        data = _safe_shop()
        products = _products(data)
        lines = [
            f"- **{p.get('name', '?')}** — `{p.get('price', '-')}`"
            for p in products
        ]
        products_text = "\n".join(lines) if lines else "- Ask a staff member"
        instructions = data.get(
            "instructions", "Open a ticket and ask a staff member."
        )
        embed = info_embed(
            "How to buy",
            f"**Products:**\n{products_text}\n\n**Steps:**\n{instructions}",
        )
        await interaction.response.send_message(embed=embed, ephemeral=True)


# ---------------------------------------------------------------------------
# Cog: /postshop + ticket management
# ---------------------------------------------------------------------------
class ShopCog(commands.Cog):
    def __init__(self, bot: commands.Bot, payments: MercadoPagoClient | None = None) -> None:
        self.bot = bot
        # Automatic Pix (optional). None = only the manual flow exists.
        if payments is None and config.MERCADOPAGO_ACCESS_TOKEN:
            payments = MercadoPagoClient()
        self.payments = payments

    async def cog_load(self) -> None:
        if self.payments is not None:
            self.payment_loop.start()

    async def cog_unload(self) -> None:
        if self.payment_loop.is_running():
            self.payment_loop.cancel()

    # ------------------------------------------------------------------
    # Delivery (manual approval AND automatic payment use this)
    # ------------------------------------------------------------------
    async def fulfill_ticket(
        self, channel_id: int, days: int, note: str | None, actor: str
    ) -> dict | None:
        """
        Delivers a new key, or renews the buyer's key when the ticket is a
        renewal. Returns None when this ticket was already delivered.
        """
        ticket = db.get_ticket(channel_id)
        product = self.selected_product(channel_id) or {"name": "Product", "price": "-"}
        note = note or f"{product.get('name', 'Product')} - ticket"

        # Claim first: a second staff click, or the automatic payment check
        # racing a manual approval, cannot create a second key
        if not db.claim_ticket_approval(channel_id):
            return None

        buyer_id = ticket["buyer_id"] if ticket else None
        renew_key = ticket["renew_key"] if ticket else None
        try:
            if renew_key:
                found, expires_at = db.extend_key(renew_key, days)
                if not found:
                    raise LookupError("The key to renew no longer exists.")
                key = renew_key
            else:
                key = db.generate_keys(1, days, note)[0]
                expires_at = db.get_key(key)["expires_at"]
        except Exception:
            db.release_ticket_approval(channel_id)
            raise
        renewed = bool(renew_key)

        dm_sent = False
        if buyer_id:
            try:
                user = await self.bot.fetch_user(buyer_id)
                if renewed:
                    when = "never (permanent)" if not expires_at else db.fmt_date(expires_at)
                    embed = success_embed(
                        "✅ Payment approved — key renewed",
                        f"**{product.get('name', 'Product')}** "
                        f"(`{product.get('price', '-')}`)\n\n"
                        f"Your key `{mask_key(key)}` is now valid until **{when}**.",
                    )
                else:
                    embed = success_embed(
                        "✅ Payment approved — here is your key",
                        f"**{product.get('name', 'Product')}** "
                        f"(`{product.get('price', '-')}`)\n\n"
                        f"Your key:\n```{key}```\n"
                        "Redeem it with **Redeem Key** on the key "
                        "panel, then click **Get Script**.",
                    )
                await user.send(embed=embed)
                dm_sent = True
            except (discord.Forbidden, discord.NotFound, discord.HTTPException):
                dm_sent = False
        if renewed and buyer_id:
            await grant_buyer_role(self.bot, buyer_id)

        logger.log_event(
            success_embed(
                "Ticket approved — key renewed" if renewed else "Ticket approved — key delivered",
                f"By: {actor}\nBuyer: <@{buyer_id}>\n"
                f"Key: `{mask_key(key)}`\nDays: {days if days else 'permanent'}\n"
                f"Note: {note}",
            )
        )
        await asyncio.to_thread(
            catalog.log_activity, actor,
            "ticket_renewed" if renewed else "ticket_delivered",
            f"{mask_key(key)} for {buyer_id}, {days if days else 'permanent'} day(s)",
        )
        # Logs the sale on the Aero Platform's dashboard automatically —
        # nobody has to re-type what this ticket already proves. Never
        # blocks/breaks delivery: the key is already generated and the
        # buyer already notified by this point, win or lose here.
        try:
            await asyncio.to_thread(
                db.record_sale,
                buyer=str(buyer_id) if buyer_id else "unknown",
                discord_id=buyer_id,
                game=None,
                product=product.get("name"),
                amount_cents=price_to_cents(product.get("price")),
                status="paid",
                note=("renewal - " if renewed else "") + note,
            )
        except Exception:
            logger.log_event(
                error_embed(
                    "Sale not recorded on the platform",
                    f"Key `{mask_key(key)}` was delivered fine; the Sales "
                    "tab just didn't get this one. Check the platform.",
                )
            )
        return {
            "key": key, "renewed": renewed, "days": days, "product": product,
            "buyer_id": buyer_id, "dm_sent": dm_sent, "expires_at": expires_at,
        }

    # ------------------------------------------------------------------
    # Automatic Pix (Mercado Pago)
    # ------------------------------------------------------------------
    async def start_auto_pix(self, interaction: discord.Interaction) -> None:
        if self.payments is None:
            await interaction.response.send_message(
                embed=error_embed(
                    "Not available",
                    "Automatic Pix is not enabled. Use the **Pix** button.",
                ),
                ephemeral=True,
            )
            return
        channel_id = interaction.channel_id
        ticket = db.get_ticket(channel_id)
        if ticket is None:
            await interaction.response.send_message(
                embed=error_embed(
                    "Not available for this ticket",
                    "This ticket was opened before automatic Pix existed. "
                    "Use the **Pix** button.",
                ),
                ephemeral=True,
            )
            return
        if interaction.user.id != ticket["buyer_id"]:
            await interaction.response.send_message(
                embed=error_embed("Not your ticket", "Only the buyer can start the payment."),
                ephemeral=True,
            )
            return
        if ticket["approved"]:
            await interaction.response.send_message(
                embed=info_embed("Already delivered", "Your key was already delivered. Check your DMs!"),
                ephemeral=True,
            )
            return
        product = self.selected_product(channel_id)
        if product is None:
            await interaction.response.send_message(
                embed=error_embed(
                    "Select a product first",
                    "Use the menu above to select the product, then pay.",
                ),
                ephemeral=True,
            )
            return
        try:
            amount = float(product.get("price_brl"))
        except (TypeError, ValueError):
            amount = 0.0
        if amount <= 0:
            await interaction.response.send_message(
                embed=error_embed(
                    "Not configured",
                    "Automatic Pix needs a BRL price for this product. "
                    "Use the **Pix** button for now.",
                ),
                ephemeral=True,
            )
            return

        await interaction.response.defer()
        name = product.get("name", "Product")
        try:
            if ticket["pay_id"]:
                payment = await self.payments.get_payment(ticket["pay_id"])
                amount = ticket["pay_amount"] or amount
            else:
                payment = await self.payments.create_pix(
                    amount, f"{name} - ticket {channel_id}",
                    str(channel_id), f"ticket-{channel_id}",
                )
                db.set_ticket_payment(channel_id, payment["id"], amount)
            if not payment["qr_code"]:
                raise PaymentError("No Pix code available for this charge.")
        except PaymentError as exc:
            log.warning("Automatic Pix failed for ticket %s: %s", channel_id, exc)
            await interaction.followup.send(
                embed=error_embed(
                    "Could not create the Pix",
                    "Try again in a moment, or use the **Pix** button.",
                ),
                ephemeral=True,
            )
            return

        embed = discord.Embed(
            title=f"⚡ Pay with Pix — {name}",
            description=(
                f"**Amount:** `R$ {amount:.2f}`\n\n"
                "Open your bank app, choose **Pix copia e cola** and paste:\n"
                f"```{payment['qr_code']}```\n"
                "Your key arrives **automatically** a few seconds after the "
                "payment is confirmed. No need to send a receipt."
            ),
            color=config.PANEL_COLOR,
        )
        file = None
        if payment["qr_png"]:
            file = discord.File(io.BytesIO(payment["qr_png"]), filename="pix.png")
            embed.set_image(url="attachment://pix.png")
        await interaction.followup.send(embed=embed, **({"file": file} if file else {}))
        logger.log_event(
            info_embed(
                "Automatic Pix created",
                f"Buyer: {interaction.user.mention}\nProduct: {name}\n"
                f"Amount: R$ {amount:.2f}",
            )
        )

    async def check_payments_once(self) -> int:
        """Asks Mercado Pago about every pending charge. Returns deliveries."""
        if self.payments is None:
            return 0
        delivered = 0
        for ticket in db.pending_payments():
            channel_id = ticket["channel_id"]
            try:
                pay = await self.payments.get_payment(ticket["pay_id"])
            except PaymentError as exc:
                log.warning("Could not check payment %s: %s", ticket["pay_id"], exc)
                continue

            if pay["status"] in ("cancelled", "rejected", "refunded", "charged_back"):
                db.clear_ticket_payment(channel_id)  # buyer can start a new one
                continue
            if pay["status"] != "approved":
                continue

            # Never deliver on a mismatch: wrong ticket or wrong amount
            expected = float(ticket["pay_amount"] or 0)
            if (
                pay["reference"] != str(channel_id)
                or abs(pay["amount"] - expected) > 0.009
            ):
                log.error(
                    "Payment %s does not match ticket %s (ref=%r amount=%s expected=%s)",
                    pay["id"], channel_id, pay["reference"], pay["amount"], expected,
                )
                db.clear_ticket_payment(channel_id)
                logger.log_event(
                    error_embed(
                        "Payment does not match the ticket",
                        f"Payment `{pay['id']}` was approved but its reference or "
                        f"amount differs from the ticket <#{channel_id}>. "
                        "Nothing was delivered. Check it manually.",
                    )
                )
                continue

            product = self.selected_product(channel_id) or {}
            try:
                days = max(0, min(int(product.get("days", 30)), 3650))
            except (TypeError, ValueError):
                days = 30
            result = await self.fulfill_ticket(channel_id, days, None, "Pix (automatic)")
            if result is None:
                continue  # staff approved it manually in the meantime
            delivered += 1
            channel = self.bot.get_channel(channel_id)
            if channel is not None:
                try:
                    await channel.send(embed=_delivery_embed(result, "Pix confirmed"))
                except discord.HTTPException:
                    pass
        return delivered

    @tasks.loop(seconds=config.PAYMENT_POLL_SECONDS)
    async def payment_loop(self) -> None:
        try:
            await self.check_payments_once()
        except Exception:
            log.exception("Checking Pix payments failed")

    @payment_loop.before_loop
    async def before_payment_loop(self) -> None:
        await self.bot.wait_until_ready()

    # ------------------------------------------------------------------
    # /renew
    # ------------------------------------------------------------------
    @app_commands.command(
        name="renew",
        description="Renew your key (opens a private ticket)",
    )
    async def renew(self, interaction: discord.Interaction) -> None:
        row = db.get_user_key(interaction.user.id)
        if row is None:
            await interaction.response.send_message(
                embed=error_embed(
                    "No key to renew",
                    "You have not redeemed a key yet. Use the shop to buy one.",
                ),
                ephemeral=True,
            )
            return
        if db.status(row) in ("revoked", "inactive", "banned"):
            await interaction.response.send_message(
                embed=error_embed(
                    "Cannot renew this key",
                    "Your key was disabled or banned. Contact support.",
                ),
                ephemeral=True,
            )
            return
        if row["expires_at"] is None:
            await interaction.response.send_message(
                embed=info_embed("Nothing to renew", "Your key is permanent."),
                ephemeral=True,
            )
            return
        await self.open_ticket(interaction, renew_key=row["key"])

    def selected_product(self, channel_id: int) -> dict | None:
        """Product chosen in a ticket (the ticket state lives in the database)."""
        products = _products(_safe_shop())
        ticket = db.get_ticket(channel_id)
        if ticket is None or not ticket["product_id"]:
            # Tickets opened before the product was stored: with a single
            # product the answer is unambiguous
            return products[0] if len(products) == 1 else None
        return next(
            (p for p in products if _product_id(p) == ticket["product_id"]),
            None,
        )

    # ------------------------------------------------------------------
    # Payment reported by the buyer -> approval message for the staff
    # ------------------------------------------------------------------
    async def notify_paid(self, interaction: discord.Interaction) -> None:
        channel_id = interaction.channel_id
        ticket = db.get_ticket(channel_id)
        if ticket is not None and ticket["approved"]:
            await interaction.response.send_message(
                embed=info_embed(
                    "Already approved",
                    "Your key was already delivered. Check your DMs!",
                ),
                ephemeral=True,
            )
            return
        if not db.mark_ticket_paid(channel_id):
            await interaction.response.send_message(
                embed=info_embed(
                    "Already reported",
                    "The staff was already notified about your "
                    "payment. Hold on!",
                ),
                ephemeral=True,
            )
            return

        product = self.selected_product(channel_id) or {
            "name": "Product",
            "price": "-",
        }

        # Pings the staff roles (falls back to no ping if the bot
        # cannot mention them)
        mentions = []
        for role_id in (config.STAFF_ROLE_ID, config.ADMIN_ROLE_ID):
            if role_id and interaction.guild:
                role = interaction.guild.get_role(role_id)
                if role:
                    mentions.append(role.mention)

        embed = info_embed(
            "💰 Payment reported",
            f"{interaction.user.mention} reports the payment of "
            f"**{product.get('name', 'Product')}** "
            f"(`{product.get('price', '-')}`).\n\n"
            "Staff: check the receipt in this channel and click "
            "**✅ Approve & deliver key** (the key is generated and "
            "sent automatically) or **❌ Reject**.",
        )
        try:
            await interaction.channel.send(
                content=" ".join(mentions) or None,
                embed=embed,
                view=ApprovalView(self),
            )
        except discord.HTTPException:
            await interaction.channel.send(
                embed=embed, view=ApprovalView(self)
            )

        await interaction.response.send_message(
            embed=success_embed(
                "Payment reported ✅",
                "The staff was notified. Your key will arrive here "
                "as soon as your payment is approved.",
            ),
            ephemeral=True,
        )
        logger.log_event(
            success_embed(
                "Payment reported",
                f"Buyer: {interaction.user.mention}\n"
                f"Product: {product.get('name', 'Product')} "
                f"({product.get('price', '-')})",
            )
        )

    # ------------------------------------------------------------------
    # Ticket creation
    # ------------------------------------------------------------------
    async def _get_category(self, guild: discord.Guild) -> discord.CategoryChannel | None:
        if config.TICKET_CATEGORY_ID:
            cat = guild.get_channel(config.TICKET_CATEGORY_ID)
            if isinstance(cat, discord.CategoryChannel):
                return cat
        for cat in guild.categories:
            if cat.name.lower() == "tickets":
                return cat
        try:
            return await guild.create_category(
                "Tickets", reason="Buy tickets"
            )
        except discord.HTTPException:
            return None

    async def open_ticket(
        self, interaction: discord.Interaction, renew_key: str | None = None
    ) -> None:
        if interaction.guild is None:
            return
        guild = interaction.guild
        user = interaction.user

        # Reuses an open ticket of this user, when it exists
        base = f"ticket-{user.name}".lower().replace(" ", "-")[:80]
        for channel in guild.text_channels:
            if channel.name.startswith(base):
                if channel.overwrites_for(user).view_channel:
                    await interaction.response.send_message(
                        embed=info_embed(
                            "You already have an open ticket",
                            f"Go to {channel.mention} to continue.",
                        ),
                        ephemeral=True,
                    )
                    return

        everyone = guild.default_role
        overwrites: dict = {
            everyone: discord.PermissionOverwrite(view_channel=False),
            user: discord.PermissionOverwrite(
                view_channel=True,
                send_messages=True,
                embed_links=True,
                attach_files=True,
                read_message_history=True,
            ),
        }
        for role_id in (config.STAFF_ROLE_ID, config.ADMIN_ROLE_ID):
            if role_id:
                role = guild.get_role(role_id)
                if role:
                    overwrites[role] = discord.PermissionOverwrite(
                        view_channel=True,
                        send_messages=True,
                        embed_links=True,
                        attach_files=True,
                        read_message_history=True,
                        manage_messages=True,
                    )

        category = await self._get_category(guild)
        try:
            channel = await guild.create_text_channel(
                name=base,
                category=category,
                overwrites=overwrites,
                reason=f"Buy ticket from {user}",
            )
        except discord.HTTPException:
            await interaction.response.send_message(
                embed=error_embed(
                    "Could not create the ticket",
                    "I need the **Manage Channels** permission to "
                    "create private channels.",
                ),
                ephemeral=True,
            )
            return

        data = _safe_shop()
        products = _products(data)

        # Ticket state (used by the approval flow), kept in the database
        db.create_ticket(channel.id, user.id, renew_key)

        # Single product = pre-selected, the ticket goes straight
        # to the payment buttons.
        if len(products) == 1:
            db.set_ticket_product(channel.id, _product_id(products[0]))
            steps = "Select the **payment method** below."
        else:
            steps = (
                "Select the **product** and the **payment method** "
                "below."
            )

        welcome = discord.Embed(
            title=(
                f"🔁 Renewal ticket — {user.display_name}" if renew_key
                else f"🎫 Purchase ticket — {user.display_name}"
            ),
            description=(
                f"Welcome, {user.mention}!\n\n"
                + (
                    "This ticket **renews your current key**: after the "
                    "payment is approved its validity is extended, you do "
                    "not get a new key.\n\n"
                    if renew_key else ""
                )
                + f"{steps}\n\n"
                "Only **you and the staff** can see this channel.\n\n"
                "After paying, send the receipt here and click "
                "**✅ I already paid** — your key is delivered "
                "automatically once the staff approves it."
            ),
            color=config.PANEL_COLOR,
        )
        await channel.send(
            content=f"{user.mention}",
            embed=welcome,
            view=TicketView(self, products),
        )

        await interaction.response.send_message(
            embed=success_embed(
                "Ticket created!",
                f"Your ticket is open: {channel.mention}\n"
                "Select the payment method there.",
            ),
            ephemeral=True,
        )
        logger.log_event(
            success_embed(
                "Ticket opened",
                f"Buyer: {user.mention}\nChannel: {channel.mention}",
            )
        )

    # ------------------------------------------------------------------
    # /postshop
    # ------------------------------------------------------------------
    @app_commands.command(
        name="postshop",
        description="Posts the shop panel (private buy tickets)",
    )
    @app_commands.describe(channel="Channel where the shop panel will be posted")
    @admin_only()
    async def postshop(
        self,
        interaction: discord.Interaction,
        channel: discord.TextChannel | None = None,
    ) -> None:
        try:
            data = _load_shop()
        except (OSError, ValueError):
            await interaction.response.send_message(
                embed=error_embed(
                    "Shop config missing",
                    "Could not read shop.json (missing file or invalid JSON).",
                ),
                ephemeral=True,
            )
            return

        target = channel or interaction.channel
        await target.send(embed=build_shop_embed(data), view=ShopView(self))
        await interaction.response.send_message(
            embed=success_embed(
                "Shop panel posted!",
                f"The shop panel has been sent to {target.mention}.",
            ),
            ephemeral=True,
        )
        logger.log_event(
            success_embed(
                "Shop panel posted",
                f"By: {interaction.user.mention}\nChannel: {target.mention}",
            )
        )

    # ------------------------------------------------------------------
    # /deliver
    # ------------------------------------------------------------------
    @app_commands.command(
        name="deliver",
        description="Sends a purchased key to a user by DM",
    )
    @app_commands.describe(user="The buyer", key="The key to deliver")
    @staff_only()
    async def deliver(
        self,
        interaction: discord.Interaction,
        user: discord.Member,
        key: str,
    ) -> None:
        await interaction.response.defer(ephemeral=True, thinking=True)
        row = await asyncio.to_thread(db.get_key, key.strip())
        if row is not None and row["discord_id"] and row["discord_id"] != user.id:
            # Never DM a key that is already bound to another buyer
            logger.log_event(
                error_embed(
                    "Blocked: delivering someone else's key",
                    f"Staff: {interaction.user.mention}\n"
                    f"Target: {user.mention}\n"
                    f"Key owner: <@{row['discord_id']}>\n"
                    f"Key: `{mask_key(row['key'])}`",
                ),
                security=True,
            )
            await interaction.followup.send(
                embed=error_embed(
                    "Key already bound",
                    f"That key belongs to <@{row['discord_id']}>. "
                    "Use `/unlink` first if this is a transfer.",
                ),
                ephemeral=True,
            )
            return
        if row is None:
            await interaction.followup.send(
                embed=error_embed(
                    "Key not found",
                    "Check that you typed the key correctly.",
                ),
                ephemeral=True,
            )
            return

        dm_embed = success_embed(
            "Your key",
            "Here is your key:\n"
            f"```{row['key']}```\n"
            "Redeem it with **Redeem Key** on the key panel, then "
            "click **Get Script**.",
        )
        try:
            await user.send(embed=dm_embed)
        except discord.Forbidden:
            await interaction.followup.send(
                embed=error_embed(
                    "DMs closed",
                    f"{user.mention} cannot receive direct messages.",
                ),
                ephemeral=True,
            )
            return

        await interaction.followup.send(
            embed=success_embed(
                "Key delivered",
                f"{user.mention} received the key by DM.",
            ),
            ephemeral=True,
        )
        logger.log_event(
            info_embed(
                "Key delivered",
                f"Staff: {interaction.user.mention}\n"
                f"Buyer: {user.mention}\nKey: `{mask_key(row['key'])}`",
            )
        )


async def setup(bot: commands.Bot) -> None:
    cog = ShopCog(bot)
    await bot.add_cog(cog)
    # Persistent views: old panel/ticket/approval messages keep
    # working after the bot restarts.
    bot.add_view(ShopView(cog))
    bot.add_view(TicketView(cog, _products(_safe_shop())))
    bot.add_view(ApprovalView(cog))

