"""
Low-level SQLite layer for the AERO platform.

- Single WAL connection guarded by a lock (server is one process).
- Every query is parameterized (no string building with user input).
- Helpers return plain dicts (easy JSON) unless _raw=True.
"""
import os
import sqlite3
import threading
import time

import config

_conn: sqlite3.Connection | None = None
_lock = threading.Lock()


def _connect() -> sqlite3.Connection:
    os.makedirs(os.path.dirname(config.AERO_DB), exist_ok=True)
    conn = sqlite3.connect(config.AERO_DB, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    return conn


def _db() -> sqlite3.Connection:
    global _conn
    if _conn is None:
        _conn = _connect()
    return _conn


def close() -> None:
    global _conn
    with _lock:
        if _conn is not None:
            _conn.close()
            _conn = None


def now() -> int:
    return int(time.time())


# ---------------------------------------------------------------------------
# Migrations
# ---------------------------------------------------------------------------
def migrate(migrations_dir: str | None = None) -> list[str]:
    """Applies migration SQL files that did not run yet, in filename order."""
    migrations_dir = migrations_dir or os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "migrations"
    )
    conn = _db()
    with _lock:
        conn.execute(
            "CREATE TABLE IF NOT EXISTS _migrations ("
            "  name TEXT PRIMARY KEY, applied_at INTEGER NOT NULL)"
        )
        conn.commit()

    applied = {
        row["name"]
        for row in conn.execute("SELECT name FROM _migrations").fetchall()
    }
    if not os.path.isdir(migrations_dir):
        return []

    ran: list[str] = []
    for name in sorted(os.listdir(migrations_dir)):
        if not name.endswith(".sql") or name in applied:
            continue
        with open(os.path.join(migrations_dir, name), "r", encoding="utf-8") as fh:
            sql = fh.read()
        with _lock:
            conn.execute("BEGIN")
            try:
                conn.executescript(sql)
                conn.execute(
                    "INSERT INTO _migrations (name, applied_at) VALUES (?, ?)",
                    (name, now()),
                )
                conn.commit()
            except Exception:
                conn.rollback()
                raise
        ran.append(name)
    return ran


# ---------------------------------------------------------------------------
# Query helpers
# ---------------------------------------------------------------------------
def query(sql: str, params: tuple | list = ()) -> list[dict]:
    """SELECT -> list of dicts."""
    rows = _db().execute(sql, tuple(params)).fetchall()
    return [dict(r) for r in rows]


def one(sql: str, params: tuple | list = ()) -> dict | None:
    row = _db().execute(sql, tuple(params)).fetchone()
    return dict(row) if row is not None else None


def scalar(sql: str, params: tuple | list = ()) -> object:
    row = _db().execute(sql, tuple(params)).fetchone()
    return row[0] if row is not None else None


def execute(sql: str, params: tuple | list = ()) -> int:
    """Write statement -> lastrowid. Commits."""
    with _lock:
        cur = _db().execute(sql, tuple(params))
        _db().commit()
        return cur.lastrowid or cur.rowcount


def execute_many(sql: str, rows: list[tuple]) -> None:
    with _lock:
        _db().executemany(sql, rows)
        _db().commit()


def transaction(writes: list[tuple[str, tuple | list]]) -> None:
    """Apply several writes atomically."""
    with _lock:
        conn = _db()
        conn.execute("BEGIN")
        try:
            for sql, params in writes:
                conn.execute(sql, tuple(params))
            conn.commit()
        except Exception:
            conn.rollback()
            raise


# ---------------------------------------------------------------------------
# Settings kv
# ---------------------------------------------------------------------------
def get_setting(key: str, default: str | None = None) -> str | None:
    row = one("SELECT value FROM settings WHERE key = ?", (key,))
    return row["value"] if row else default


def set_setting(key: str, value: str) -> None:
    execute(
        "INSERT INTO settings (key, value, updated_at) VALUES (?, ?, ?) "
        "ON CONFLICT(key) DO UPDATE SET value = excluded.value, "
        "updated_at = excluded.updated_at",
        (key, value, now()),
    )
