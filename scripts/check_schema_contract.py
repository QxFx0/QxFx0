#!/usr/bin/env python3
"""Verify the runtime-critical SQLite schema contract.

The manifest in spec/sql/runtime_critical_contract.tsv is the review checklist
for objects that must be validated by QxFx0.Bridge.SQLite.SchemaContract.
This checker ensures the manifest, canonical SQL, and Haskell contract stay in
lockstep.
"""

from __future__ import annotations

import re
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "spec/sql/runtime_critical_contract.tsv"
SCHEMA_SQL = ROOT / "spec/sql/schema.sql"
SCHEMA_CONTRACT_HS = ROOT / "src/QxFx0/Bridge/SQLite/SchemaContract.hs"


@dataclass(frozen=True, order=True)
class ContractItem:
    kind: str
    parent: str
    name: str


def read_manifest(path: Path) -> set[ContractItem]:
    items: set[ContractItem] = set()
    for lineno, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 3:
            raise SystemExit(f"{path}:{lineno}: expected 3 tab-separated fields")
        kind, parent, name = parts
        if kind not in {"table", "column", "index", "trigger", "fts"}:
            raise SystemExit(f"{path}:{lineno}: unsupported contract kind: {kind}")
        if not name:
            raise SystemExit(f"{path}:{lineno}: empty object name")
        items.add(ContractItem(kind, parent, name))
    return items


def quoted(name: str) -> str:
    return re.escape(name)


def extract_haskell_list(source: str, binding: str) -> set[str]:
    pattern = re.compile(
        rf"{re.escape(binding)}\s*::.*?\n{re.escape(binding)}\s*=\s*(.*?)(?:\n\n|\n-- \||\Z)",
        re.S,
    )
    match = pattern.search(source)
    if not match:
        raise SystemExit(f"{SCHEMA_CONTRACT_HS}: cannot find binding {binding}")
    return set(re.findall(r'"([^"]+)"', match.group(1)))


def extract_haskell_columns(source: str) -> set[ContractItem]:
    match = re.search(
        r"schemaContractColumns\s*::.*?\nschemaContractColumns\s*=\s*Map\.fromList\s*(.*?)(?:\n\n|\n-- \||\Z)",
        source,
        re.S,
    )
    if not match:
        raise SystemExit(f"{SCHEMA_CONTRACT_HS}: cannot find binding schemaContractColumns")
    body = match.group(1)
    items: set[ContractItem] = set()
    for table, columns_body in re.findall(r'\(\s*"([^"]+)"\s*,\s*\[(.*?)\]\s*\)', body, re.S):
        for col in re.findall(r'"([^"]+)"', columns_body):
            items.add(ContractItem("column", table, col))
    return items


def has_sql_table(sql: str, name: str) -> bool:
    return re.search(rf"CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+{quoted(name)}\s*\(", sql, re.I) is not None


def has_sql_fts(sql: str, name: str) -> bool:
    return re.search(rf"CREATE\s+VIRTUAL\s+TABLE\s+IF\s+NOT\s+EXISTS\s+{quoted(name)}\s+USING\s+fts5\s*\(", sql, re.I) is not None


def has_sql_index(sql: str, name: str) -> bool:
    return re.search(rf"CREATE\s+INDEX\s+IF\s+NOT\s+EXISTS\s+{quoted(name)}\s+ON\s+", sql, re.I) is not None


def has_sql_trigger(sql: str, name: str) -> bool:
    return re.search(rf"CREATE\s+TRIGGER\s+IF\s+NOT\s+EXISTS\s+{quoted(name)}\s+", sql, re.I) is not None


def has_sql_column(sql: str, table: str, column: str) -> bool:
    table_match = re.search(
        rf"CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+{quoted(table)}\s*\((.*?)\n\);",
        sql,
        re.I | re.S,
    )
    if not table_match:
        return False
    return re.search(rf"^\s*{quoted(column)}\b", table_match.group(1), re.I | re.M) is not None


def manifest_items_from_haskell(source: str) -> set[ContractItem]:
    tables = {
        ContractItem("table", "-", name)
        for name in extract_haskell_list(source, "schemaContractTables")
    }
    indexes = {
        ContractItem("index", "-", name)
        for name in extract_haskell_list(source, "schemaContractIndexes")
    }
    triggers = {
        ContractItem("trigger", "-", name)
        for name in extract_haskell_list(source, "schemaContractTriggers")
    }
    fts = {
        ContractItem("fts", "-", name)
        for name in extract_haskell_list(source, "schemaContractFTS")
    }
    return tables | extract_haskell_columns(source) | indexes | triggers | fts


def validate_sql_coverage(manifest: set[ContractItem], sql: str) -> list[str]:
    errors: list[str] = []
    for item in sorted(manifest):
        if item.kind == "table" and not has_sql_table(sql, item.name):
            errors.append(f"manifest table missing from schema.sql: {item.name}")
        elif item.kind == "column" and not has_sql_column(sql, item.parent, item.name):
            errors.append(f"manifest column missing from schema.sql: {item.parent}.{item.name}")
        elif item.kind == "index" and not has_sql_index(sql, item.name):
            errors.append(f"manifest index missing from schema.sql: {item.name}")
        elif item.kind == "trigger" and not has_sql_trigger(sql, item.name):
            errors.append(f"manifest trigger missing from schema.sql: {item.name}")
        elif item.kind == "fts" and not has_sql_fts(sql, item.name):
            errors.append(f"manifest fts table missing from schema.sql: {item.name}")
    return errors


def main() -> int:
    manifest = read_manifest(MANIFEST)
    sql = SCHEMA_SQL.read_text(encoding="utf-8")
    haskell = SCHEMA_CONTRACT_HS.read_text(encoding="utf-8")
    hs_items = manifest_items_from_haskell(haskell)

    errors = validate_sql_coverage(manifest, sql)
    missing_in_haskell = sorted(manifest - hs_items)
    extra_in_haskell = sorted(hs_items - manifest)
    errors.extend(
        f"manifest item missing from SchemaContract.hs: {item.kind} {item.parent} {item.name}"
        for item in missing_in_haskell
    )
    errors.extend(
        f"SchemaContract.hs item missing from manifest: {item.kind} {item.parent} {item.name}"
        for item in extra_in_haskell
    )

    if errors:
        for err in errors:
            print(f"ERROR: {err}", file=sys.stderr)
        return 1
    print(f"OK: runtime schema contract manifest matches schema.sql and SchemaContract.hs ({len(manifest)} objects)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
