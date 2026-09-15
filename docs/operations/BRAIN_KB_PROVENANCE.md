# brain_kb.jsonl — provenance and restore contract

Status: **OPEN OPS TASK** (audit 2026-08-23, register item P3-8).
The file is NOT in the repository (gitignored external data source).

## What the runtime expects

- Path: repo root `brain_kb.jsonl` (loaded by
  `QxFx0.Runtime.Session.Bootstrap` → `QxFx0.Semantic.Network.Substrate.loadBrainKB`).
- Format: JSONL, one JSON object per line; bad lines are skipped
  (tested in `Test.Suite.SubstrateNetwork`).
- Entry shape consumed: `layer` (string) + `triggers` (list of strings)
  + free-text reflective prose. Filtering contract:
  `layer ∈ {ontology, dialogue, metaphor, dialog_moves, human_signals}`
  and **≥ 2 philosophical triggers** (substring match).
- Scale at last known-good use: **53K entries** (2026-06-20 landing).
- Behavior when absent: `loadBrainKB` returns `[]`; Bootstrap logs
  `WARN brain_kb.jsonl loaded 0 entries…` (since 2026-08-23); the
  substrate layer is then empty and only the explicit corpus layer
  routes spreading activation. This is a **silent capability loss**
  on fresh clones, not an error.

## What the file is

- Origin: external curated knowledge base of reflective prose
  (brain-KB dump). **The original source/export pipeline is
  undocumented** — this note is the honest record of that gap.
- The substrate layer built from it routes associative traversal
  only; it never surfaces in output (doctrine: Substrate Network,
  AGENTS.md 2026-06-20 section).

## Restore procedure (when a copy is found)

1. Place the file at the repo root; do NOT commit it (gitignored by
   design — 53K entries of external data).
2. Verify the WARN disappears and the bootstrap INFO line reports a
   nonzero entry count.
3. Re-run `Test.Suite.SubstrateNetwork` (6 tests) as a smoke check.
4. Record the entry count and acquisition source in this file,
   replacing the "undocumented" sentence above.

## Alternatives if no copy exists

Rebuilding from scratch requires a new curated source and must go
through the Relation Graph doctrine constraint (no regex
reconstruction from reflective prose — see AGENTS.md, Substrate
Network section). Until then the system runs honestly on the
explicit layer alone.
