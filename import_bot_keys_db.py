r"""
Imports keys from the legacy bot database (``data/keys.db``) into the Aero
Platform. Safe to run twice: existing keys are skipped, never overwritten.

Usage (from the platform root):

  py tools\import_bot_keys_db.py --db "C:\path\to\keys.db" --dry-run
  py tools\import_bot_keys_db.py --db "C:\path\to\keys.db"
  py tools\import_bot_keys_db.py --db ... --product 1        # attach keys
  py tools\import_bot_keys_db.py --db ... --product 1 --license 2 --script 3

What is preserved
-----------------
key, discord_id (as a platform user), HWID, executions, hwid_resets,
first/last execution, expiration (NULL = permanent), created/redeemed dates,
banned + reason + ban_until, note, revoked state and the reminder flag.

What is not
-----------
Tickets (bot-only workflow), per-key game allowlists (the platform derives
game access from the product/script) and the legacy admin accounts (the
dashboard has its own logins — use tools/create_admin.py).
"""
from __future__ import annotations

import argparse
import os
import sqlite3
import sys

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(BASE_DIR, "backend"))

import db  # noqa: E402
import services  # noqa: E402

FIELDS = (
    "key", "discord_id", "hwid", "executions", "hwid_resets",
    "first_exec", "last_exec", "expires_at", "created_at", "redeemed_at",
    "banned", "ban_reason", "ban_until", "note", "exp_reminded",
    "active", "revoked_at",
)


def _open_legacy(path: str) -> sqlite3.Connection:
    if not os.path.isfile(path):
        raise SystemExit(f"legacy database not found: {path}")
    conn = sqlite3.connect(path)
    conn.row_factory = sqlite3.Row
    cols = {r["name"] for r in conn.execute("PRAGMA table_info(keys)")}
    missing = {"key", "discord_id", "created_at"} - cols
    if missing:
        raise SystemExit(
            f"{path} does not look like the bot database (missing {missing})")
    return conn


def _row_value(row: sqlite3.Row, name: str, default=None):
    return row[name] if name in row.keys() else default


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Import legacy bot keys into the Aero Platform.")
    parser.add_argument("--db", required=True, help="path to the bot keys.db")
    parser.add_argument("--product", type=int, default=None,
                        help="product id to attach the imported keys to")
    parser.add_argument("--license", type=int, default=None,
                        help="license id (optional, needs --product)")
    parser.add_argument("--script", type=int, default=None,
                        help="script id (optional, needs --product)")
    parser.add_argument("--dry-run", action="store_true",
                        help="show what would happen without writing")
    args = parser.parse_args()

    db.migrate()

    if args.product is not None and db.one(
            "SELECT id FROM products WHERE id = ?", (args.product,)) is None:
        raise SystemExit(f"product {args.product} does not exist")
    if args.license is not None and db.one(
            "SELECT id FROM licenses WHERE id = ?", (args.license,)) is None:
        raise SystemExit(f"license {args.license} does not exist")
    if args.script is not None and db.one(
            "SELECT id FROM scripts WHERE id = ?", (args.script,)) is None:
        raise SystemExit(f"script {args.script} does not exist")

    legacy = _open_legacy(args.db)
    rows = legacy.execute("SELECT * FROM keys ORDER BY created_at").fetchall()
    print(f"legacy keys: {len(rows)}")

    created = skipped = users_created = 0
    for row in rows:
        key = str(_row_value(row, "key") or "").strip()
        if not key:
            skipped += 1
            continue
        if db.one("SELECT key FROM keys WHERE key = ?", (key,)) is not None:
            skipped += 1
            continue

        discord_id = _row_value(row, "discord_id")
        try:
            discord_id = int(discord_id) if discord_id is not None else None
        except (TypeError, ValueError):
            discord_id = None

        user_id = None
        if discord_id:
            user = db.one("SELECT id FROM users WHERE discord_id = ?",
                          (discord_id,))
            if user is None and not args.dry_run:
                user_id = db.execute(
                    "INSERT INTO users (discord_id, display_name, role,"
                    " created_at) VALUES (?,?,?,?)",
                    (discord_id, None, "buyer", services.now()),
                )
                users_created += 1
            elif user is not None:
                user_id = user["id"]

        revoked = 1 if (
            _row_value(row, "revoked_at") is not None
            or _row_value(row, "active", 1) == 0
        ) else 0

        values = (
            key,
            user_id,
            args.product,
            args.license,
            args.script,
            _row_value(row, "hwid"),
            int(_row_value(row, "hwid_resets") or 0),
            int(_row_value(row, "executions") or 0),
            _row_value(row, "first_exec"),
            _row_value(row, "last_exec"),
            _row_value(row, "expires_at"),
            int(_row_value(row, "created_at") or services.now()),
            _row_value(row, "redeemed_at"),
            revoked,
            int(_row_value(row, "banned") or 0),
            _row_value(row, "ban_reason"),
            _row_value(row, "ban_until"),
            _row_value(row, "note"),
            int(_row_value(row, "exp_reminded") or 0),
        )
        created += 1
        if args.dry_run:
            print(f"  would import {key[:8]}… "
                  f"discord={discord_id} revoked={revoked} "
                  f"expires={_row_value(row, 'expires_at')}")
            continue
        db.execute(
            """INSERT INTO keys
               (key, user_id, product_id, license_id, script_id, hwid,
                hwid_resets, executions, first_exec, last_exec, expires_at,
                created_at, redeemed_at, revoked, banned, ban_reason,
                ban_until, note, exp_reminded)
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            values,
        )
        services.audit("cli", "import_keys", "key.import", target=key,
                       detail=f"from {os.path.basename(args.db)}")

    if not args.dry_run:
        # one summary audit line for the whole import
        services.audit(
            "cli", "import_keys", "key.import.batch",
            target=os.path.basename(args.db),
            detail=f"created={created} skipped={skipped} users={users_created}",
        )

    print(
        f"{'would import' if args.dry_run else 'imported'}: {created} | "
        f"skipped (already present): {skipped} | users created: {users_created}"
    )
    if args.product is None:
        print("note: keys have no product; attach one from the dashboard "
              "before they can execute a script")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
