r"""
Creates (or resets) a dashboard administrator on the Aero Platform.

Usage (from the platform root):

  py tools\create_admin.py --email you@example.com --password "strong-pass"
  py tools\create_admin.py --email staff@example.com --password "..." --role staff
  py tools\create_admin.py --email you@example.com --password "..." --force

Notes
-----
* Passwords are hashed with PBKDF2-SHA256 (``security.hash_password``);
  nothing is stored in plain text.
* New/reset accounts are flagged ``must_change`` so the dashboard forces a
  password change on the next login.
* Use ``--force`` to update an existing account (role / password).
"""
from __future__ import annotations

import argparse
import os
import sys

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(BASE_DIR, "backend"))

import db  # noqa: E402
import security  # noqa: E402
import services  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Create or reset a dashboard administrator.")
    parser.add_argument("--email", required=True,
                        help="login e-mail (lowercase is enforced)")
    parser.add_argument("--password", required=True,
                        help="plain password (min 8 chars)")
    parser.add_argument("--role", choices=("owner", "staff"), default="owner")
    parser.add_argument("--force", action="store_true",
                        help="update the account if it already exists")
    args = parser.parse_args()

    email = args.email.strip().lower()
    password = args.password
    if "@" not in email:
        print("error: invalid e-mail", file=sys.stderr)
        return 2
    if len(password) < 8:
        print("error: password must have at least 8 characters", file=sys.stderr)
        return 2

    db.migrate()
    row = db.one("SELECT id, role FROM dashboard_users WHERE email = ?", (email,))
    password_hash = security.hash_password(password)

    if row is None:
        db.execute(
            """INSERT INTO dashboard_users
               (email, password_hash, role, must_change, created_at)
               VALUES (?, ?, ?, 1, ?)""",
            (email, password_hash, args.role, services.now()),
        )
        services.audit("cli", "create_admin", "dash.user.create", target=email)
        print(f"created {args.role} account: {email}")
    elif not args.force:
        print(f"error: {email} already exists (use --force to update it)",
              file=sys.stderr)
        return 1
    else:
        db.execute(
            """UPDATE dashboard_users
               SET password_hash = ?, role = ?, must_change = 1
               WHERE id = ?""",
            (password_hash, args.role, row["id"]),
        )
        services.audit("cli", "create_admin", "dash.user.reset", target=email)
        print(f"updated {args.role} account: {email}")

    print("password change is required on the next login")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
