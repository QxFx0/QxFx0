#!/usr/bin/env python3
"""Verify cumulative migrations produce the same schema as spec/sql/schema.sql."""

from __future__ import annotations

import sqlite3
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
MIGRATIONS_DIR = ROOT / "migrations"
CANONICAL_SCHEMA = ROOT / "spec" / "sql" / "schema.sql"


def normalize_sql(sql_text: str | None) -> str:
    if not sql_text:
        return ""
    collapsed = " ".join(sql_text.strip().split())
    return collapsed.rstrip(";")


def apply_sql_file(db_path: Path, sql_path: Path) -> None:
    sql_text = sql_path.read_text(encoding="utf-8")
    conn = sqlite3.connect(db_path)
    try:
        conn.executescript(sql_text)
        conn.commit()
    finally:
        conn.close()


def dump_schema_signature(db_path: Path) -> list[tuple[str, str, str, str]]:
    conn = sqlite3.connect(db_path)
    try:
        rows = conn.execute(
            """
            SELECT type, name, tbl_name, sql
            FROM sqlite_master
            WHERE type IN ('table', 'index', 'trigger', 'view')
              AND name NOT LIKE 'sqlite_%'
            ORDER BY type, name
            """
        ).fetchall()
    finally:
        conn.close()
    return [(t, n, tbl, normalize_sql(sql)) for (t, n, tbl, sql) in rows]


def main() -> int:
    migration_files = sorted(MIGRATIONS_DIR.glob("*.sql"))
    if not migration_files:
        print(f"FAIL: no migration files in {MIGRATIONS_DIR}", file=sys.stderr)
        return 1
    if not CANONICAL_SCHEMA.exists():
        print(f"FAIL: missing canonical schema: {CANONICAL_SCHEMA}", file=sys.stderr)
        return 1

    with tempfile.TemporaryDirectory(prefix="qxfx0-schema-check-") as tmpdir:
        tmp = Path(tmpdir)
        db_migrations = tmp / "migrations.db"
        db_canonical = tmp / "canonical.db"

        for migration in migration_files:
            apply_sql_file(db_migrations, migration)
        apply_sql_file(db_canonical, CANONICAL_SCHEMA)

        migration_sig = dump_schema_signature(db_migrations)
        canonical_sig = dump_schema_signature(db_canonical)

    if migration_sig != canonical_sig:
        print("FAIL: cumulative migrations schema differs from spec/sql/schema.sql", file=sys.stderr)
        migration_only = sorted(set(migration_sig) - set(canonical_sig))
        canonical_only = sorted(set(canonical_sig) - set(migration_sig))
        if migration_only:
            print("  Objects only in migrations result:", file=sys.stderr)
            for row in migration_only[:20]:
                print(f"    {row}", file=sys.stderr)
        if canonical_only:
            print("  Objects only in canonical schema:", file=sys.stderr)
            for row in canonical_only[:20]:
                print(f"    {row}", file=sys.stderr)
        return 1

    print(
        f"OK: cumulative migrations ({len(migration_files)} files) match canonical schema ({len(canonical_sig)} objects)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
