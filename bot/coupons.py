"""
Discount coupons for the shop.

Created in the shop editor (/shopedit → 🏷️ Coupons). A buyer applies one
inside their ticket (🏷️ Coupon button); from then on every price shown in that
ticket, the automatic Pix amount and the sale recorded on the platform use the
discounted price. A use is counted when the key is delivered.

Stored in the bot's kv table:
  shop:coupons          -> {"CODE": {"percent": 20, "max_uses": 10, "used": 3}}
  ticket_coupon:<chan>  -> "CODE"
"""
from __future__ import annotations

import re

import catalog

_ALL = "shop:coupons"
_CODE_RE = re.compile(r"^[A-Z0-9_-]{3,24}$")
_NUM_RE = re.compile(r"\d+(?:[.,]\d+)?")


def normalize_code(code: str) -> str:
    return str(code or "").strip().upper()


def valid_code(code: str) -> bool:
    return bool(_CODE_RE.match(normalize_code(code)))


def all_coupons() -> dict:
    found = catalog.get_kv(_ALL)
    return dict(found[0]) if found and isinstance(found[0], dict) else {}


def get(code: str) -> dict | None:
    return all_coupons().get(normalize_code(code))


def upsert(code: str, percent: int, max_uses: int | None) -> None:
    data = all_coupons()
    code = normalize_code(code)
    old = data.get(code) or {}
    data[code] = {"percent": int(percent), "max_uses": max_uses, "used": int(old.get("used", 0))}
    catalog.set_kv(_ALL, data)


def delete(code: str) -> bool:
    data = all_coupons()
    if data.pop(normalize_code(code), None) is None:
        return False
    catalog.set_kv(_ALL, data)
    return True


def usable(coupon: dict | None) -> bool:
    if not coupon or not 1 <= int(coupon.get("percent", 0)) <= 100:
        return False
    limit = coupon.get("max_uses")
    return limit in (None, 0) or int(coupon.get("used", 0)) < int(limit)


def consume(code: str) -> None:
    data = all_coupons()
    code = normalize_code(code)
    if code in data:
        data[code]["used"] = int(data[code].get("used", 0)) + 1
        catalog.set_kv(_ALL, data)


def ticket_coupon(channel_id: int) -> str | None:
    found = catalog.get_kv(f"ticket_coupon:{channel_id}")
    return found[0] if found and isinstance(found[0], str) else None


def set_ticket_coupon(channel_id: int, code: str) -> None:
    catalog.set_kv(f"ticket_coupon:{channel_id}", normalize_code(code))


def clear_ticket_coupon(channel_id: int) -> None:
    catalog.del_kv(f"ticket_coupon:{channel_id}")


def discounted_price(price: str, percent: int) -> str:
    """'$9.00' at 20% -> '$7.20' (keeps the currency text and decimal mark)."""
    match = _NUM_RE.search(str(price or ""))
    if not match:
        return str(price)
    raw = match.group(0)
    comma = "," in raw
    value = float(raw.replace(",", ".")) * (100 - int(percent)) / 100
    text = f"{value:.2f}"
    if comma:
        text = text.replace(".", ",")
    return price[: match.start()] + text + price[match.end():]


def apply(product: dict, code: str, coupon: dict) -> dict:
    """Copy of `product` with the coupon discount applied."""
    percent = int(coupon.get("percent", 0))
    out = dict(product)
    out["original_price"] = product.get("price")
    out["price"] = discounted_price(str(product.get("price", "")), percent)
    if product.get("price_brl") is not None:
        out["price_brl"] = round(float(product["price_brl"]) * (100 - percent) / 100, 2)
    out["coupon"] = normalize_code(code)
    out["coupon_percent"] = percent
    return out
