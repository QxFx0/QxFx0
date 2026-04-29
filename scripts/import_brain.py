#!/usr/bin/env python3
"""Import brain_kb.jsonl into SQLite — create identity_claims with topics and triggers.

From QxFx4: reads JSONL, upserts into identity_claims table.
"""

import json
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_JL = ROOT / "data" / "brain_kb.jsonl"
DEFAULT_DB = ROOT / "qxfx0.db"
SCHEMA = ROOT / "spec" / "sql" / "schema.sql"

def ensure_schema(conn):
    if SCHEMA.exists():
        conn.executescript(SCHEMA.read_text())

def import_jsonl(jl_path, db_path):
    if not jl_path.exists():
        print(f"ERROR: {jl_path} not found", file=sys.stderr)
        sys.exit(1)
    conn = sqlite3.connect(str(db_path))
    ensure_schema(conn)
    count = 0
    with open(jl_path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                print(f"  SKIP: bad JSON line {count+1}", file=sys.stderr)
                continue
            claim_id = rec.get("id", rec.get("claim_id", f"claim_{count}"))
            topic = rec.get("topic", rec.get("theme", ""))
            trigger = rec.get("trigger", rec.get("pattern", ""))
            content = rec.get("content", rec.get("text", ""))
            stance = rec.get("stance", "neutral")
            agency = rec.get("agency", 0.5)
            tension = rec.get("tension", 0.3)
            conn.execute(
                """INSERT OR REPLACE INTO identity_claims
                   (claim_id, topic, trigger, content, stance, agency, tension)
                   VALUES (?, ?, ?, ?, ?, ?, ?)""",
                (claim_id, topic, trigger, content, stance, agency, tension),
            )
            count += 1
    conn.commit()
    row_count = conn.execute("SELECT count(*) FROM identity_claims").fetchone()[0]
    conn.close()
    print(f"Imported {count} claims into {db_path} (total rows: {row_count})")

def main():
    jl_path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_JL
    db_path = Path(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_DB
    import_jsonl(jl_path, db_path)

if __name__ == "__main__":
    main()
