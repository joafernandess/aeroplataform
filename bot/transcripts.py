"""
Ticket transcripts: the whole ticket conversation saved as an HTML file
before the channel is deleted (proof for chargebacks / disputes).

Discord only gives bots the text of other people's messages when the
"Message Content Intent" is enabled (MESSAGE_CONTENT_INTENT=1 + the toggle in
the Developer Portal). Without it the transcript still has every message's
author and time, the bot's own messages (payment details, approvals...)
and attachments' names are kept when Discord sends them.
"""
from __future__ import annotations

import html
import io

import discord

import config

_CSS = """
body{background:#050508;color:#f1f0ff;font-family:system-ui,'Segoe UI',sans-serif;margin:0;padding:24px}
h1{color:#8fa2f9;font-size:20px;margin:0 0 4px} .meta{color:#a5a7c8;font-size:13px;margin-bottom:20px}
.msg{display:flex;gap:12px;padding:10px 12px;border-radius:10px;margin-bottom:6px;background:rgba(134,136,255,.045)}
.msg img.av{width:36px;height:36px;border-radius:50%} .who{font-weight:600;color:#a9b8ff}
.bot{font-size:10px;background:#6f86f3;color:#fff;border-radius:4px;padding:1px 4px;margin-left:4px}
.time{color:#6d7090;font-size:12px;margin-left:6px} .text{white-space:pre-wrap;margin-top:2px}
.embed{border-left:4px solid #8fa2f9;background:#0b0b16;border-radius:6px;padding:8px 10px;margin-top:6px}
.embed b{color:#f1f0ff} .hidden{color:#6d7090;font-style:italic} a{color:#8fa2f9}
"""


def _esc(text: str | None) -> str:
    return html.escape(text or "")


def _message_html(m: discord.Message) -> str:
    parts = []
    if m.content:
        parts.append(f'<div class="text">{_esc(m.content)}</div>')
    for e in m.embeds:
        body = [f"<b>{_esc(e.title)}</b>"] if e.title else []
        if e.description:
            body.append(f'<div class="text">{_esc(e.description)}</div>')
        for f in e.fields:
            body.append(f'<div><b>{_esc(f.name)}</b><div class="text">{_esc(f.value)}</div></div>')
        color = f"#{e.color.value:06x}" if e.color else "#8fa2f9"
        parts.append(f'<div class="embed" style="border-color:{color}">{"".join(body)}</div>')
    for a in m.attachments:
        parts.append(f'<div>📎 <a href="{_esc(a.url)}">{_esc(a.filename)}</a></div>')
    if not parts:
        parts.append(
            '<div class="hidden">(text not available — enable the Message Content '
            "intent to include it)</div>"
            if not config.MESSAGE_CONTENT_INTENT else '<div class="hidden">(empty)</div>'
        )
    avatar = _esc(m.author.display_avatar.url)
    badge = '<span class="bot">BOT</span>' if m.author.bot else ""
    when = m.created_at.strftime("%Y-%m-%d %H:%M UTC")
    return (
        f'<div class="msg"><img class="av" src="{avatar}" alt="">'
        f'<div><span class="who">{_esc(m.author.display_name)}</span>{badge}'
        f'<span class="time">{when} · {m.author.id}</span>{"".join(parts)}</div></div>'
    )


async def build(channel: discord.abc.Messageable, title: str) -> tuple[discord.File, int, set[int]]:
    """HTML transcript file, message count and the IDs of who talked."""
    messages = [m async for m in channel.history(limit=1000, oldest_first=True)]
    people = {m.author.id for m in messages if not m.author.bot}
    body = "".join(_message_html(m) for m in messages)
    doc = (
        f"<!doctype html><html><head><meta charset='utf-8'><title>{_esc(title)}</title>"
        f"<style>{_CSS}</style></head><body><h1>{_esc(title)}</h1>"
        f"<div class='meta'>{len(messages)} messages · Aero ticket transcript</div>"
        f"{body}</body></html>"
    )
    name = f"transcript-{getattr(channel, 'name', 'ticket')}.html"
    return discord.File(io.BytesIO(doc.encode("utf-8")), filename=name), len(messages), people
