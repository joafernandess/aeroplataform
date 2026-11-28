"""
Execution logs in a Discord FORUM channel — one post per buyer.

Every time the loader runs, the Aero Platform records the attempt (key, HWID,
IP, result) plus the telemetry the loader reports (Roblox account, server,
device). This cog pulls those events every EXEC_LOG_POLL_SECONDS and:

  * posts each execution inside the buyer's own forum post
    ("<name> • <discord id>"), created on first use, so every user has
    their full history in one place;
  * executions with an unknown / unredeemed key go to a shared
    "❓ Unknown keys" post;
  * raises security alerts in the security log channel:
      - the key was used by a different Roblox account than before
      - the key ran from SHARE_ALERT_IPS+ different IPs in 24 h
      - one IP used IP_MULTI_KEY_ALERT+ different keys in 24 h
      - HWID mismatches, banned/revoked keys still being run, autokicks
      - floods of invalid-key attempts / rate limiting from an IP

Staff commands:
  /executions <user> [count]  - a user's latest executions
  /ipcheck <ip>               - every key / user seen from an IP

Telemetry comes from the user's client, so a modified loader could lie about
it. The IP, key, HWID and result are recorded by the server and are reliable.
"""
from __future__ import annotations

import asyncio
import datetime
import logging
import time

import discord
from discord import app_commands
from discord.ext import commands, tasks

import catalog
import config
import logger
import platform_bridge as db
from utils import error_embed, info_embed, mask_key, staff_only

log = logging.getLogger("keybot.executions")

_LAST_ID = "exec_log:last_id"
_UNKNOWN = "unknown"
_BATCH = 50
_NO_PINGS = discord.AllowedMentions.none()


# ---------------------------------------------------------------------------
# Formatting helpers
# ---------------------------------------------------------------------------
def _clean(value, limit: int = 100) -> str:
    """Client data -> safe inline code (no backticks, no mentions)."""
    if value is None or value == "":
        return "`-`"
    text = str(value).replace("`", "'").replace("@", "@​")
    text = " ".join(text.split())[:limit]
    return f"`{text}`"


class Raw(str):
    """Markdown built by the bot itself (trusted), shown as-is."""


def _plain(value, limit: int = 80) -> str:
    """Client data for running text: markdown escaped, no mentions."""
    text = " ".join(str(value or "").split())[:limit]
    return discord.utils.escape_markdown(text).replace("@", "@\u200b")


def _section(title: str, rows: list[tuple[str, object]]) -> str:
    lines = [f"**{title}**", "━━━━━━━━━━━━━━━━━━"]
    for name, value in rows:
        shown = value if isinstance(value, Raw) else _clean(value)
        lines.append(f"**{name}**\n{shown}")
    return "\n".join(lines)


def _kv(name: str):
    found = catalog.get_kv(name)
    return found[0] if found else None


def _cooldown(name: str, seconds: int) -> bool:
    """True (and arms the cooldown) when an alert `name` may fire now."""
    found = catalog.get_kv(f"alert:{name}")
    if found is not None and time.time() - found[1] < seconds:
        return False
    catalog.set_kv(f"alert:{name}", True)
    return True


def build_execution_embed(ev: dict) -> discord.Embed:
    """The execution log card (layout of the classic Luarmor-style logs)."""
    tel = ev.get("telemetry") or {}
    ok = ev.get("result") == "ok"
    kind = ev.get("kind") or "execute"
    username = tel.get("username") or "Unknown player"
    place_name = tel.get("place_name") or "an unknown game"
    place_id = tel.get("place_id")
    rbx_id = tel.get("user_id")
    job_id = tel.get("job_id")

    if ok:
        title = "🚀 Script executed"
        intro = (
            f"**{_plain(username, 40)}** just executed Aero in "
            f"**{_plain(place_name)}** ({_clean(place_id)})."
        )
        color = 0x57F287
    else:
        title = "⛔ Kicked by AutoKick" if kind == "autokick_denied" else "⛔ Execution refused"
        intro = (
            f"**{_plain(username, 40)}** tried to run Aero in "
            f"**{_plain(place_name)}** ({_clean(place_id)}).\n"
            f"**Reason:** {_clean(ev.get('reason'), 200)}"
        )
        color = 0xED4245

    profile = (
        Raw(f"[{rbx_id}](https://www.roblox.com/users/{rbx_id}/profile)")
        if isinstance(rbx_id, int) and rbx_id > 0 else rbx_id
    )
    age = tel.get("account_age")
    locale = " / ".join(
        x for x in (tel.get("roblox_locale"), tel.get("system_locale")) if x
    )
    players = (
        f"{tel.get('players')}/{tel.get('max_players')}"
        if tel.get("players") is not None else None
    )
    join = None
    if isinstance(place_id, int) and job_id:
        from urllib.parse import quote
        join = Raw(
            f"[Join server](https://www.roblox.com/games/start?placeId={place_id}"
            f"&gameInstanceId={quote(str(job_id), safe='')})"
        )
    executor = " ".join(
        x for x in (tel.get("executor"), tel.get("executor_version")) if x
    )

    owner = ev.get("discord_id")
    key = ev.get("key")
    parts = [
        intro,
        _section("👤 ACCOUNT", [
            ("Username", username),
            ("Display Name", tel.get("display_name")),
            ("User ID", profile),
            ("Account Age", f"{age} days" if isinstance(age, int) and age >= 0 else None),
            ("Membership", tel.get("membership")),
            ("Country", tel.get("country")),
        ]),
        _section("🌍 SERVER", [
            ("Place ID", place_id),
            ("Universe ID", tel.get("universe_id")),
            ("Job ID", job_id),
            ("Place Version", tel.get("place_version")),
            ("Place Name", place_name),
            ("Locale", locale),
            ("Players", players),
        ] + ([("Join", join)] if join else [])),
        _section("💻 DEVICE", [
            ("Executor", executor),
            ("Device", tel.get("device")),
            ("Resolution", tel.get("viewport")),
            ("HWID", ev.get("hwid")),
            ("IP", ev.get("ip")),
            ("Loader", ev.get("loader_version") or tel.get("loader_version")),
        ]),
        _section("🔑 KEY", [
            ("Owner", Raw(f"<@{owner}>") if owner else "not redeemed"),
            ("Key", mask_key(key)),
            ("IPs on this key (24 h)", ev.get("key_ips_24h")),
            ("Keys on this IP (24 h)", ev.get("ip_keys_24h")),
        ]),
    ]
    embed = discord.Embed(title=title, description="\n\n".join(parts)[:4000], color=color)
    ts = ev.get("ts")
    if ts:
        embed.timestamp = datetime.datetime.fromtimestamp(
            int(ts), tz=datetime.timezone.utc
        )
    embed.set_footer(text=f"Event #{ev.get('event_id')} • {kind}")
    return embed


# ---------------------------------------------------------------------------
# Cog
# ---------------------------------------------------------------------------
class ExecutionLogCog(commands.Cog):
    def __init__(self, bot: commands.Bot) -> None:
        self.bot = bot
        self._thread_lock = asyncio.Lock()

    async def cog_load(self) -> None:
        if not config.EXEC_LOG_FORUM_ID:
            log.info("Execution log disabled (EXEC_LOG_FORUM_ID empty)")
            return
        if not db.using_platform():
            log.warning("Execution log needs the Aero Platform bridge; disabled")
            return
        self.poll_loop.change_interval(seconds=config.EXEC_LOG_POLL_SECONDS)
        self.poll_loop.start()

    async def cog_unload(self) -> None:
        if self.poll_loop.is_running():
            self.poll_loop.cancel()

    # ------------------------------------------------------------------
    # Forum posts (one per user)
    # ------------------------------------------------------------------
    async def _forum(self) -> discord.ForumChannel | None:
        channel = self.bot.get_channel(config.EXEC_LOG_FORUM_ID)
        if channel is None:
            try:
                channel = await self.bot.fetch_channel(config.EXEC_LOG_FORUM_ID)
            except discord.HTTPException as exc:
                log.warning("Execution log forum not reachable: %s", exc)
                return None
        if not isinstance(channel, discord.ForumChannel):
            log.warning("EXEC_LOG_FORUM_ID is not a forum channel")
            return None
        return channel

    async def _user_label(self, discord_id: int) -> str:
        user = self.bot.get_user(discord_id)
        if user is None:
            try:
                user = await self.bot.fetch_user(discord_id)
            except discord.HTTPException:
                user = None
        return user.name if user else "user"

    async def _starter_embed(self, owner: int | None, key: str | None) -> discord.Embed:
        if owner is None:
            return info_embed(
                "❓ Unknown / unredeemed keys",
                "Executions with invalid keys, or keys nobody has redeemed yet, "
                "are logged here.",
            )
        row = await asyncio.to_thread(db.get_user_key, owner)
        lines = [f"**User:** <@{owner}> (`{owner}`)"]
        shown_key = row["key"] if row is not None else key
        if shown_key:
            lines.append(f"**Key:** ||`{shown_key}`||")
        if row is not None:
            expires = row["expires_at"]
            lines.append(f"**Status:** `{db.status(row)}`")
            lines.append(
                f"**Expires:** {db.fmt_date(expires) if expires else 'never'}"
            )
            if row["redeemed_at"]:
                lines.append(f"**Redeemed:** <t:{int(row['redeemed_at'])}:R>")
        lines.append("\nEvery execution of this user's key is logged below.")
        return info_embed("📒 Execution log", "\n".join(lines))

    async def _thread_for(self, owner: int | None, key: str | None) -> discord.Thread | None:
        """The user's forum post (created on first use)."""
        slot = f"exec_thread:{owner or _UNKNOWN}"
        async with self._thread_lock:
            thread_id = await asyncio.to_thread(_kv, slot)
            if thread_id:
                thread = self.bot.get_channel(int(thread_id))
                if thread is None:
                    try:
                        thread = await self.bot.fetch_channel(int(thread_id))
                    except discord.NotFound:
                        thread = None  # deleted: create a new one below
                    except discord.HTTPException:
                        return None
                if isinstance(thread, discord.Thread):
                    if thread.archived and not thread.locked:
                        try:
                            await thread.edit(archived=False)
                        except discord.HTTPException:
                            pass
                    return thread

            forum = await self._forum()
            if forum is None:
                return None
            name = (
                f"{await self._user_label(owner)} • {owner}"
                if owner else "❓ Unknown keys"
            )
            try:
                created = await forum.create_thread(
                    name=name[:100],
                    embed=await self._starter_embed(owner, key),
                    allowed_mentions=_NO_PINGS,
                )
            except discord.HTTPException as exc:
                log.warning("Could not create the forum post for %s: %s", owner, exc)
                return None
            await asyncio.to_thread(catalog.set_kv, slot, created.thread.id)
            return created.thread

    # ------------------------------------------------------------------
    # Security analysis
    # ------------------------------------------------------------------
    def _alerts(self, ev: dict) -> list[discord.Embed]:
        """Security alerts for one event. Runs in a thread (kv access)."""
        alerts: list[discord.Embed] = []
        tel = ev.get("telemetry") or {}
        key, ip = ev.get("key"), ev.get("ip")
        owner = ev.get("discord_id")
        who = f"<@{owner}>" if owner else "not redeemed"
        base = (
            f"Owner: {who}\nKey: `{mask_key(key)}`\nIP: `{ip or '-'}`\n"
            f"Roblox: {_clean(tel.get('username'))} ({_clean(tel.get('user_id'))})"
        )
        reason = (ev.get("reason") or "").lower()
        ok = ev.get("result") == "ok"

        if ev.get("kind") == "rate_limited":
            if ip and _cooldown(f"ratelimit:{ip}", 600):
                alerts.append(error_embed(
                    "IP rate limited",
                    f"IP `{ip}` is flooding the loader API (possible brute-force).",
                ))
            return alerts

        if not ok:
            if "does not match" in reason:
                alerts.append(error_embed("HWID mismatch (possible key sharing)", base))
            elif "invalid or unknown key" in reason:
                if ip and _cooldown(f"badkey:{ip}", 300):
                    alerts.append(error_embed("Invalid key used", base))
            elif any(w in reason for w in ("banned", "revoked")):
                alerts.append(error_embed("Banned / revoked key still being run", base))
            if ev.get("kind") == "autokick_denied":
                alerts.append(error_embed("Player autokicked", f"{base}\nReason: {reason}"))
            return alerts

        # Different Roblox account on the same key = shared key
        rbx = tel.get("user_id")
        if key and isinstance(rbx, int) and rbx > 0:
            slot = f"exec_rbx:{key}"
            seen = _kv(slot) or []
            if rbx not in seen:
                if seen:
                    alerts.append(error_embed(
                        "Key used by a different Roblox account",
                        f"{base}\nPreviously seen accounts: "
                        + ", ".join(f"`{x}`" for x in seen[-5:]),
                    ))
                catalog.set_kv(slot, (seen + [rbx])[-20:])

        if key and (ev.get("key_ips_24h") or 0) >= max(2, config.SHARE_ALERT_IPS):
            if _cooldown(f"share:{key}", 86400):
                alerts.append(error_embed(
                    "Possible key sharing",
                    f"{base}\nRan from **{ev['key_ips_24h']}** different IPs in 24 h.",
                ))
        if ip and config.IP_MULTI_KEY_ALERT > 0 and (
            (ev.get("ip_keys_24h") or 0) >= config.IP_MULTI_KEY_ALERT
        ):
            if _cooldown(f"multikey:{ip}", 86400):
                alerts.append(error_embed(
                    "One IP is using several keys",
                    f"IP `{ip}` used **{ev['ip_keys_24h']}** different keys in 24 h "
                    f"(alts or a reseller). Run `/ipcheck {ip}`.\n{base}",
                ))
        return alerts

    # ------------------------------------------------------------------
    # Polling
    # ------------------------------------------------------------------
    @tasks.loop(seconds=15)
    async def poll_loop(self) -> None:
        try:
            await self.poll_once()
        except Exception:
            log.exception("Execution log poll failed")

    @poll_loop.before_loop
    async def _before_poll(self) -> None:
        await self.bot.wait_until_ready()

    async def poll_once(self) -> int:
        last = await asyncio.to_thread(_kv, _LAST_ID)
        if last is None:
            # First start: begin from now instead of flooding old history
            newest = await asyncio.to_thread(db.executions, 0, 1, None, None, None, True)
            start = int(newest[0]["event_id"]) if newest else 0
            await asyncio.to_thread(catalog.set_kv, _LAST_ID, start)
            log.info("Execution log starting after event #%s", start)
            return 0

        events = await asyncio.to_thread(db.executions, int(last), _BATCH)
        posted = 0
        for ev in events:
            await self.handle_event(ev)
            await asyncio.to_thread(catalog.set_kv, _LAST_ID, int(ev["event_id"]))
            posted += 1
            await asyncio.sleep(0.4)  # stay far from Discord rate limits
        return posted

    async def handle_event(self, ev: dict) -> None:
        if ev.get("kind") == "loader_auth":
            return  # the loader's pre-check; the execute event right after covers it
        for alert in await asyncio.to_thread(self._alerts, ev):
            logger.log_event(alert, security=True)

        if ev.get("kind") == "rate_limited":
            return  # no key: alert only
        if ev.get("result") != "ok" and not config.EXEC_LOG_DENIED:
            return
        thread = await self._thread_for(ev.get("discord_id"), ev.get("key"))
        if thread is None:
            return
        try:
            await thread.send(
                embed=build_execution_embed(ev), allowed_mentions=_NO_PINGS
            )
        except discord.HTTPException as exc:
            log.warning("Could not post execution #%s: %s", ev.get("event_id"), exc)

    # ------------------------------------------------------------------
    # Staff lookups
    # ------------------------------------------------------------------
    @app_commands.command(
        name="executions", description="Shows a user's latest script executions"
    )
    @app_commands.describe(user="The buyer", count="How many (1-15)")
    @staff_only()
    async def executions(
        self,
        interaction: discord.Interaction,
        user: discord.User,
        count: app_commands.Range[int, 1, 15] = 10,
    ) -> None:
        await interaction.response.defer(ephemeral=True, thinking=True)
        try:
            rows = await asyncio.to_thread(
                db.executions, 0, count, None, user.id, None, True
            )
        except db.PlatformError as exc:
            await interaction.followup.send(
                embed=error_embed("Unavailable", str(exc)), ephemeral=True
            )
            return
        if not rows:
            await interaction.followup.send(
                embed=info_embed("No executions", f"{user.mention} has no executions yet."),
                ephemeral=True,
            )
            return
        lines = []
        for r in rows:
            tel = r.get("telemetry") or {}
            icon = "✅" if r.get("result") == "ok" else "⛔"
            lines.append(
                f"{icon} <t:{int(r['ts'])}:R> • {_clean(tel.get('username'))} • "
                f"{_clean(tel.get('place_name'), 40)} • IP {_clean(r.get('ip'))}"
                + ("" if r.get("result") == "ok" else f"\n  ↳ {_clean(r.get('reason'), 120)}")
            )
        thread_id = await asyncio.to_thread(_kv, f"exec_thread:{user.id}")
        if thread_id:
            lines.append(f"\nFull log: <#{thread_id}>")
        await interaction.followup.send(
            embed=info_embed(f"Executions — {user}", "\n".join(lines)[:4000]),
            ephemeral=True,
        )

    @app_commands.command(
        name="ipcheck", description="Lists every key and user seen from an IP"
    )
    @app_commands.describe(ip="The IP address")
    @staff_only()
    async def ipcheck(self, interaction: discord.Interaction, ip: str) -> None:
        await interaction.response.defer(ephemeral=True, thinking=True)
        try:
            rows = await asyncio.to_thread(
                db.executions, 0, 200, ip.strip(), None, None, True
            )
        except db.PlatformError as exc:
            await interaction.followup.send(
                embed=error_embed("Unavailable", str(exc)), ephemeral=True
            )
            return
        if not rows:
            await interaction.followup.send(
                embed=info_embed("Nothing found", f"No executions from `{ip}`."),
                ephemeral=True,
            )
            return
        seen: dict[str, dict] = {}
        accounts: set[str] = set()
        for r in rows:
            k = r.get("key") or "-"
            entry = seen.setdefault(k, {"owner": r.get("discord_id"), "n": 0, "last": r["ts"]})
            entry["n"] += 1
            name = (r.get("telemetry") or {}).get("username")
            if name:
                accounts.add(str(name))
        lines = [f"**{len(rows)}** events from `{ip}`\n"]
        for k, e in list(seen.items())[:20]:
            owner = f"<@{e['owner']}>" if e["owner"] else "not redeemed"
            lines.append(
                f"`{mask_key(k)}` • {owner} • {e['n']}x • last <t:{int(e['last'])}:R>"
            )
        if accounts:
            lines.append("\n**Roblox accounts:** " + ", ".join(
                _clean(a, 30) for a in sorted(accounts)[:15]
            ))
        await interaction.followup.send(
            embed=info_embed("IP check", "\n".join(lines)[:4000]), ephemeral=True
        )


async def setup(bot: commands.Bot) -> None:
    await bot.add_cog(ExecutionLogCog(bot))
