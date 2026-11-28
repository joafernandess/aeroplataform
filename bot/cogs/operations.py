"""
Operations: kill switch, script status panel and sales.

  /control                    - control panel (admin): every script with its
                                state, 🔌 Shutdown ALL, ▶️ Turn back on, and a
                                menu to switch a single script on/off
  /status post [channel]      - posts the public script status panel
  /status set <game> <state>  - 🟢 Working · 🟡 Updating · 🔴 Detected/Offline
  /status remove <game>
  /sales                      - revenue today / 7 days / 30 days, top products

How the shutdown works: the bot switches the scripts OFF on the Aero
Platform. From that moment every new execution is refused with "This script
is disabled by the staff", and players already in game are kicked at their
next AutoKick check (every few minutes, on scripts with AutoKick enabled).
The status panel shows a big OFFLINE banner until it is turned back on.
"""
from __future__ import annotations

import asyncio
import datetime
import logging
import time
from collections import Counter

import discord
from discord import app_commands, ui
from discord.ext import commands

import catalog
import config
import logger
import platform_bridge as db
import theme
from utils import admin_only, error_embed, info_embed, success_embed, warning_embed

log = logging.getLogger("keybot.operations")

_KILL = "killswitch"
_GAMES = "status:games"
_PANEL = "status:panel"

STATES = {
    # state: (label, emoji slot)
    "working": ("Working", "online"),
    "updating": ("Updating", "updating"),
    "detected": ("Detected — don't use", "offline"),
    "offline": ("Offline", "offline"),
}


def _kv(name: str, default=None):
    found = catalog.get_kv(name)
    return found[0] if found else default


def _is_admin(user) -> bool:
    return any(r.id == config.ADMIN_ROLE_ID for r in getattr(user, "roles", []))


# ---------------------------------------------------------------------------
# Status panel
# ---------------------------------------------------------------------------
def build_status_embed() -> discord.Embed:
    e = theme.e
    games: dict = _kv(_GAMES, {}) or {}
    kill = _kv(_KILL) or {}
    lines = []
    if kill.get("on"):
        lines.append(
            f"## {e('offline')} Aero is temporarily OFFLINE\n"
            f"{kill.get('reason') or 'Maintenance'} — since <t:{int(kill.get('ts', time.time()))}:R>\n"
            f"{theme.divider()}"
        )
    for name, info in sorted(games.items(), key=lambda kv: kv[0].lower()):
        state = "offline" if kill.get("on") else info.get("state", "working")
        label, slot = STATES.get(state, STATES["working"])
        line = f"{e(slot)} **{name}** — {label}"
        if info.get("note"):
            line += f"\n╰ {info['note']}"
        line += f" · <t:{int(info.get('ts', time.time()))}:R>"
        lines.append(line)
    if not games and not kill.get("on"):
        lines.append("No games listed yet. Staff: `/status set`.")
    color = theme.ERROR if kill.get("on") else theme.AERO
    embed = discord.Embed(
        title=f"{e('aero')} Aero • Script status",
        description="\n\n".join(lines)[:4000],
        color=color,
        timestamp=datetime.datetime.now(datetime.timezone.utc),
    )
    embed.set_footer(text=f"{theme.BRAND} • Updated")
    return embed


async def refresh_status_panel(bot: discord.Client) -> None:
    panel = await asyncio.to_thread(_kv, _PANEL)
    if not panel:
        return
    channel_id, message_id = panel
    try:
        channel = bot.get_channel(channel_id) or await bot.fetch_channel(channel_id)
        message = await channel.fetch_message(message_id)  # type: ignore[union-attr]
        await message.edit(embed=await asyncio.to_thread(build_status_embed))
    except discord.NotFound:
        await asyncio.to_thread(catalog.del_kv, _PANEL)
    except discord.HTTPException as exc:
        log.warning("Could not refresh the status panel: %s", exc)


# ---------------------------------------------------------------------------
# Kill switch
# ---------------------------------------------------------------------------
async def shutdown_all(bot: discord.Client, actor: discord.abc.User, reason: str) -> str:
    scripts = await asyncio.to_thread(db.list_scripts)
    turned_off, failed = [], []
    for s in scripts:
        if not s.get("enabled"):
            continue
        try:
            await asyncio.to_thread(db.set_script_enabled, s["id"], False)
            turned_off.append(s["id"])
        except db.PlatformError:
            failed.append(s.get("name", s["id"]))
    previous = await asyncio.to_thread(_kv, _KILL) or {}
    ids = sorted(set(previous.get("ids", []) if previous.get("on") else []) | set(turned_off))
    await asyncio.to_thread(catalog.set_kv, _KILL, {
        "on": True, "ids": ids, "reason": reason, "by": str(actor), "ts": int(time.time()),
    })
    await refresh_status_panel(bot)
    text = f"{len(turned_off)} script(s) switched OFF."
    if failed:
        text += f" Failed: {', '.join(map(str, failed))}."
    logger.log_event(
        error_embed(
            "SHUTDOWN — Aero switched off",
            f"By: {actor.mention}\nReason: {reason}\n{text}\n"
            "New executions are refused; running players are kicked at their "
            "next AutoKick check.",
        ),
        security=True,
    )
    return text


async def turn_on(bot: discord.Client, actor: discord.abc.User) -> str:
    kill = await asyncio.to_thread(_kv, _KILL) or {}
    ids = kill.get("ids", [])
    back, failed = 0, []
    for sid in ids:
        try:
            await asyncio.to_thread(db.set_script_enabled, sid, True)
            back += 1
        except db.PlatformError:
            failed.append(sid)
    await asyncio.to_thread(catalog.set_kv, _KILL, {"on": False, "ids": [], "ts": int(time.time())})
    await refresh_status_panel(bot)
    text = f"{back} script(s) switched back ON."
    if failed:
        text += f" Failed: {failed}."
    logger.log_event(
        success_embed("Aero is back ON", f"By: {actor.mention}\n{text}"), security=True
    )
    return text


class ShutdownModal(ui.Modal, title="Shutdown Aero"):
    reason = ui.TextInput(
        label="Reason (shown on the status panel)", default="Maintenance", max_length=150
    )
    confirm = ui.TextInput(label='Type "SHUTDOWN" to confirm', max_length=10)

    def __init__(self, panel: "ControlView") -> None:
        super().__init__()
        self.panel = panel

    async def on_submit(self, interaction: discord.Interaction) -> None:
        if str(self.confirm.value).strip().upper() != "SHUTDOWN":
            await interaction.response.send_message(
                embed=error_embed("Cancelled", 'You must type "SHUTDOWN".'), ephemeral=True
            )
            return
        await interaction.response.defer(ephemeral=True, thinking=True)
        try:
            text = await shutdown_all(interaction.client, interaction.user, str(self.reason.value))
        except db.PlatformError as exc:
            await interaction.followup.send(embed=error_embed("Shutdown failed", str(exc)), ephemeral=True)
            return
        await interaction.followup.send(embed=warning_embed("Aero is OFF", text), ephemeral=True)
        await self.panel.redraw()


class ControlView(ui.View):
    def __init__(self, bot: discord.Client, scripts: list[dict]) -> None:
        super().__init__(timeout=900)
        self.bot = bot
        self.message: discord.WebhookMessage | None = None
        self._build(scripts)

    def _build(self, scripts: list[dict]) -> None:
        self.clear_items()
        kill = _kv(_KILL) or {}
        if kill.get("on"):
            on = ui.Button(label="Turn Aero back ON", style=discord.ButtonStyle.success,
                           emoji=theme.pe("online"), row=0)
            on.callback = self._on_turn_on
            self.add_item(on)
        else:
            off = ui.Button(label="Shutdown ALL", style=discord.ButtonStyle.danger,
                            emoji=theme.pe("power"), row=0)
            off.callback = self._on_shutdown
            self.add_item(off)
        refresh = ui.Button(label="Refresh", style=discord.ButtonStyle.secondary, emoji="🔁", row=0)
        refresh.callback = self._on_refresh
        self.add_item(refresh)
        if scripts:
            toggle = ui.Select(
                placeholder="Switch one script on/off…",
                options=[
                    discord.SelectOption(
                        label=f"{s.get('name', '?')}"[:100],
                        value=str(s["id"]),
                        description=(
                            f"{'ON' if s.get('enabled') else 'OFF'} • "
                            f"{s.get('game_name') or 'no game'}"
                        )[:100],
                        emoji=theme.pe("online" if s.get("enabled") else "offline"),
                    )
                    for s in scripts[:25]
                ],
                row=1,
            )
            toggle.callback = self._on_toggle
            self.add_item(toggle)

    async def interaction_check(self, interaction: discord.Interaction) -> bool:
        if _is_admin(interaction.user):
            return True
        await interaction.response.send_message(
            embed=error_embed("No permission", "Only administrators can use the control panel."),
            ephemeral=True,
        )
        return False

    async def redraw(self) -> None:
        try:
            scripts = await asyncio.to_thread(db.list_scripts)
        except db.PlatformError:
            scripts = []
        self._build(scripts)
        if self.message is not None:
            try:
                await self.message.edit(embed=control_embed(scripts), view=self)
            except discord.HTTPException:
                pass

    async def _on_shutdown(self, interaction: discord.Interaction) -> None:
        await interaction.response.send_modal(ShutdownModal(self))

    async def _on_turn_on(self, interaction: discord.Interaction) -> None:
        await interaction.response.defer(ephemeral=True, thinking=True)
        text = await turn_on(interaction.client, interaction.user)
        await interaction.followup.send(embed=success_embed("Aero is ON", text), ephemeral=True)
        await self.redraw()

    async def _on_refresh(self, interaction: discord.Interaction) -> None:
        await interaction.response.defer()
        await self.redraw()

    async def _on_toggle(self, interaction: discord.Interaction) -> None:
        values = (interaction.data or {}).get("values") or []
        if not values:
            return
        await interaction.response.defer(ephemeral=True, thinking=True)
        scripts = await asyncio.to_thread(db.list_scripts)
        script = next((s for s in scripts if str(s["id"]) == values[0]), None)
        if script is None:
            await interaction.followup.send(embed=error_embed("Not found", "Script not found."), ephemeral=True)
            return
        new_state = not bool(script.get("enabled"))
        try:
            await asyncio.to_thread(db.set_script_enabled, script["id"], new_state)
        except db.PlatformError as exc:
            await interaction.followup.send(embed=error_embed("Failed", str(exc)), ephemeral=True)
            return
        word = "ON" if new_state else "OFF"
        logger.log_event(
            (success_embed if new_state else error_embed)(
                f"Script switched {word}",
                f"By: {interaction.user.mention}\nScript: **{script.get('name')}** "
                f"({script.get('game_name') or 'no game'})",
            ),
            security=not new_state,
        )
        await interaction.followup.send(
            embed=info_embed(f"{script.get('name')} is {word}", "Saved on the platform."),
            ephemeral=True,
        )
        await self.redraw()


def control_embed(scripts: list[dict]) -> discord.Embed:
    e = theme.e
    kill = _kv(_KILL) or {}
    lines = []
    if kill.get("on"):
        lines.append(
            f"### {e('offline')} SHUTDOWN ACTIVE\n{kill.get('reason')} — by {kill.get('by')} "
            f"<t:{int(kill.get('ts', 0))}:R>"
        )
    for s in scripts:
        state = e("online") + " ON" if s.get("enabled") else e("offline") + " OFF"
        kick = (
            f"AutoKick {s.get('recheck_minutes', 5)} min" if s.get("autokick_enabled")
            else "AutoKick off (running players are not kicked)"
        )
        lines.append(f"**{s.get('name')}** · {s.get('game_name') or 'no game'}\n{state} · {kick}")
    if not scripts:
        lines.append("No scripts found on the platform.")
    embed = discord.Embed(
        title=f"{e('power')} Aero control panel",
        description="\n\n".join(lines)[:4000],
        color=theme.ERROR if kill.get("on") else theme.AERO,
    )
    embed.set_footer(text=f"{theme.BRAND} • Shutdown refuses new executions and kicks at the next check")
    return embed


# ---------------------------------------------------------------------------
# Cog
# ---------------------------------------------------------------------------
class OperationsCog(commands.Cog):
    status = app_commands.Group(name="status", description="Public script status panel")

    def __init__(self, bot: commands.Bot) -> None:
        self.bot = bot

    # /control ----------------------------------------------------------
    @app_commands.command(name="control", description="Control panel: shutdown / turn on the script")
    @admin_only()
    async def control(self, interaction: discord.Interaction) -> None:
        await interaction.response.defer(ephemeral=True, thinking=True)
        try:
            scripts = await asyncio.to_thread(db.list_scripts)
        except db.PlatformError as exc:
            await interaction.followup.send(embed=error_embed("Unavailable", str(exc)), ephemeral=True)
            return
        view = ControlView(self.bot, scripts)
        view.message = await interaction.followup.send(
            embed=control_embed(scripts), view=view, ephemeral=True, wait=True
        )

    # /status -----------------------------------------------------------
    @status.command(name="post", description="Post the script status panel")
    @admin_only()
    async def status_post(
        self, interaction: discord.Interaction, channel: discord.TextChannel | None = None
    ) -> None:
        target = channel or interaction.channel
        await interaction.response.defer(ephemeral=True, thinking=True)
        message = await target.send(embed=await asyncio.to_thread(build_status_embed))  # type: ignore[union-attr]
        await asyncio.to_thread(catalog.set_kv, _PANEL, [message.channel.id, message.id])
        await interaction.followup.send(
            embed=success_embed("Status panel posted", f"In {message.channel.mention}. "
                                "It updates by itself with `/status set` and `/control`."),
            ephemeral=True,
        )

    @status.command(name="set", description="Set a game's status")
    @app_commands.describe(game="Game name", state="New status", note="Optional note")
    @app_commands.choices(state=[
        app_commands.Choice(name=label, value=key) for key, (label, _slot) in STATES.items()
    ])
    @admin_only()
    async def status_set(
        self, interaction: discord.Interaction, game: str, state: str, note: str = ""
    ) -> None:
        games = await asyncio.to_thread(_kv, _GAMES, {}) or {}
        name = game.strip()[:60]
        games[name] = {"state": state, "note": note.strip()[:150], "ts": int(time.time())}
        await asyncio.to_thread(catalog.set_kv, _GAMES, games)
        await refresh_status_panel(self.bot)
        label, slot = STATES[state]
        logger.log_event(info_embed(
            "Script status changed",
            f"By: {interaction.user.mention}\n{theme.e(slot)} **{name}** → {label}"
            + (f"\nNote: {note}" if note else ""),
        ))
        await interaction.response.send_message(
            embed=success_embed("Status saved", f"{theme.e(slot)} **{name}** — {label}"),
            ephemeral=True,
        )

    @status_set.autocomplete("game")
    async def _game_autocomplete(self, interaction: discord.Interaction, current: str):
        names = set((await asyncio.to_thread(_kv, _GAMES, {}) or {}).keys())
        try:
            for s in await asyncio.to_thread(db.list_scripts):
                if s.get("game_name"):
                    names.add(s["game_name"])
        except Exception:
            pass
        cur = current.lower()
        return [app_commands.Choice(name=n[:100], value=n[:100])
                for n in sorted(names) if cur in n.lower()][:25]

    @status.command(name="remove", description="Remove a game from the status panel")
    @admin_only()
    async def status_remove(self, interaction: discord.Interaction, game: str) -> None:
        games = await asyncio.to_thread(_kv, _GAMES, {}) or {}
        removed = games.pop(game.strip(), None) is not None
        await asyncio.to_thread(catalog.set_kv, _GAMES, games)
        await refresh_status_panel(self.bot)
        await interaction.response.send_message(
            embed=success_embed("Removed", game) if removed
            else error_embed("Not found", f"`{game}` is not on the panel."),
            ephemeral=True,
        )

    @status_remove.autocomplete("game")
    async def _remove_autocomplete(self, interaction: discord.Interaction, current: str):
        names = (await asyncio.to_thread(_kv, _GAMES, {}) or {}).keys()
        return [app_commands.Choice(name=n[:100], value=n[:100])
                for n in sorted(names) if current.lower() in n.lower()][:25]

    # /sales ------------------------------------------------------------
    @app_commands.command(name="sales", description="Revenue and sales summary")
    @admin_only()
    async def sales(self, interaction: discord.Interaction) -> None:
        await interaction.response.defer(ephemeral=True, thinking=True)
        try:
            rows = await asyncio.to_thread(db.list_sales)
        except db.PlatformError as exc:
            await interaction.followup.send(embed=error_embed("Unavailable", str(exc)), ephemeral=True)
            return
        await interaction.followup.send(embed=sales_embed(rows), ephemeral=True)


def _money(cents: int) -> str:
    return f"{config.SALES_CURRENCY}{cents / 100:,.2f}"


def sales_embed(rows: list[dict], now_ts: float | None = None) -> discord.Embed:
    e = theme.e
    now_ts = now_ts or time.time()
    today = datetime.datetime.fromtimestamp(now_ts, datetime.timezone.utc).replace(
        hour=0, minute=0, second=0, microsecond=0
    ).timestamp()
    paid = [r for r in rows if (r.get("status") or "paid") == "paid"]

    def window(since: float) -> tuple[int, int]:
        sel = [r for r in paid if int(r.get("created_at") or 0) >= since]
        return sum(int(r.get("amount_cents") or 0) for r in sel), len(sel)

    periods = [
        ("Today", today), ("7 days", now_ts - 7 * 86400), ("30 days", now_ts - 30 * 86400),
    ]
    embed = discord.Embed(title=f"{e('money')} Aero • Sales", color=theme.AERO)
    for label, since in periods:
        cents, n = window(since)
        embed.add_field(name=label, value=f"## {_money(cents)}\n{n} sale(s)", inline=True)
    month = [r for r in paid if int(r.get("created_at") or 0) >= now_ts - 30 * 86400]
    top = Counter(str(r.get("product") or "-") for r in month).most_common(5)
    embed.add_field(
        name=f"{e('stats')} Top products (30 days)",
        value="\n".join(f"**{p}** — {n}x" for p, n in top) or "No sales yet.",
        inline=False,
    )
    recent = "\n".join(
        f"<t:{int(r.get('created_at') or 0)}:R> • {_money(int(r.get('amount_cents') or 0))} • "
        f"{r.get('product') or '-'} • "
        + (f"<@{r['discord_id']}>" if r.get("discord_id") else str(r.get("buyer") or "-"))
        for r in rows[:6]
    )
    embed.add_field(name=f"{e('paid')} Latest", value=recent or "-", inline=False)
    embed.set_footer(text=f"{theme.BRAND} • Based on the last {len(rows)} sales on the platform")
    return embed


async def setup(bot: commands.Bot) -> None:
    await bot.add_cog(OperationsCog(bot))
