"""
Validation and saving of shop.json (edited from the dashboard).

The bot reads shop.json every time it needs it, so a saved change shows up
right away. The one exception: whether a ticket shows a product menu is
decided when the bot starts (1 product = no menu), so going from one product
to several (or back) needs a bot restart for old ticket messages.
"""
import json
import os
import re

import config

PRODUCT_ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,40}$")


class ShopConfigError(ValueError):
    """Invalid shop settings (shown to the admin as-is)."""


def load() -> dict:
    try:
        with open(config.SHOP_FILE, "r", encoding="utf-8") as fh:
            data = json.load(fh)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def _text(value, field: str, limit: int, required: bool = False) -> str:
    text = str(value if value is not None else "").strip()
    if required and not text:
        raise ShopConfigError(f"{field} is required.")
    if len(text) > limit:
        raise ShopConfigError(f"{field} is too long (max {limit} characters).")
    return text


def normalize(data: dict) -> dict:
    """Validates the editable fields and returns them in shop.json shape."""
    if not isinstance(data, dict):
        raise ShopConfigError("Expected an object.")
    raw_products = data.get("products")
    if not isinstance(raw_products, list) or not 1 <= len(raw_products) <= 25:
        raise ShopConfigError("Add between 1 and 25 products.")

    products, seen = [], set()
    for index, raw in enumerate(raw_products, start=1):
        if not isinstance(raw, dict):
            raise ShopConfigError(f"Product {index} is invalid.")
        pid = _text(raw.get("id"), f"Product {index} id", 40, required=True)
        if not PRODUCT_ID_RE.match(pid):
            raise ShopConfigError(
                f"Product {index} id: only letters, digits, '-' and '_'."
            )
        if pid in seen:
            raise ShopConfigError(f"Two products use the id '{pid}'.")
        seen.add(pid)
        product = {
            "id": pid,
            "name": _text(raw.get("name"), f"Product {index} name", 80, required=True),
            "price": _text(raw.get("price"), f"Product {index} price", 30, required=True),
            "description": _text(raw.get("description"), f"Product {index} description", 200),
        }
        brl = raw.get("price_brl")
        if brl not in (None, ""):
            try:
                brl = round(float(brl), 2)
            except (TypeError, ValueError):
                raise ShopConfigError(f"Product {index}: price in BRL must be a number.")
            if not 0.01 <= brl <= 100000:
                raise ShopConfigError(f"Product {index}: price in BRL is out of range.")
            product["price_brl"] = brl
        days = raw.get("days", 30)
        try:
            days = int(days if days not in (None, "") else 30)
        except (TypeError, ValueError):
            raise ShopConfigError(f"Product {index}: validity must be a number of days.")
        if not 0 <= days <= 3650:
            raise ShopConfigError(f"Product {index}: validity must be 0-3650 days.")
        product["days"] = days
        products.append(product)

    payments_in = data.get("payments") or {}
    if not isinstance(payments_in, dict):
        raise ShopConfigError("Payments are invalid.")
    paypal = _text(payments_in.get("paypal_url"), "PayPal link", 300)
    if paypal and not re.match(r"^https?://", paypal, re.I):
        raise ShopConfigError("The PayPal link must start with http:// or https://.")

    return {
        "title": _text(data.get("title"), "Title", 100, required=True),
        "description": _text(data.get("description"), "Description", 1000),
        "products": products,
        "payments": {
            "pix_type": _text(payments_in.get("pix_type"), "Pix key type", 60),
            "pix_key": _text(payments_in.get("pix_key"), "Pix key", 200),
            "paypal_url": paypal,
        },
        "instructions": _text(data.get("instructions"), "Instructions", 2000),
    }


def save(data: dict) -> dict:
    """Validates and writes shop.json atomically. Unknown keys are kept."""
    clean = normalize(data)
    merged = load()
    merged.update(clean)
    tmp = config.SHOP_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(merged, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    os.replace(tmp, config.SHOP_FILE)
    return merged
