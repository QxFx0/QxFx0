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
  (brain-KB dump), recovered 2026-09-21 from sibling workdirs on the
  same machine: identical 44 MB copies at
  `Grid_cod/QxFx1/brain_kb.jsonl` (+ `QxFx1_1`, `QXFX0_V5`,
  `QxFx3/data`). Installed copy: repo-root `brain_kb.jsonl`
  (53 146 lines, 0 parse errors; layers ontology 17425 / dialogue
  8342 / dialog_moves 6006 / metaphor 343 / human_signals 309, plus
  non-substrate layers the filter skips).
- The substrate layer built from it routes associative traversal
  only; it never surfaces in output (doctrine: Substrate Network,
  AGENTS.md 2026-06-20 section).

## Integration record (2026-09-21, operator decision: substrate ON)

- Restore steps 1–3 executed: file at root (gitignored — the rule
  was missing from `.gitignore` and has been added), bootstrap INFO
  `loaded entries=53146`, live turn activates the layer
  (`trcSubstrateEdgesUsed=166`, `trcSubstrateHops=3`), canonical
  response surfaces byte-identical.
- Full verification WITH substrate: unit 1605, fast 1817 (incl.
  M6 benchmark), integration 46, slow 94+45+23+11 — all green.
- Two substrate costs measured and absorbed (both harness-side, no
  runtime change):
  1. Cold-worker bootstrap 11.4s → 19.3s (wall 26s → 44s on a
     first turn) trips the default HTTP client timeout: `/turn`
     posts in `Test.Suite.HttpRuntime` now carry an explicit 120s
     budget (calibration, not masking — no turn-latency SLA exists).
  2. State group needs `-M10G` (`-M8G` heap-exhausts at 29/45,
     `-M12G` lets the box OOM-killer fire): per-group caps are now
     runtime/state-heterogeneous — see AGENTS.md test-counts note.
- Calibration note: all 130 response labels were collected WITHOUT
  substrate. Response-level judgments (`response_acceptable`) stand
  (surfaces verified identical on sampled turns); predicate-fit
  numbers from `eval_structscore.py` describe the explicit-layer
  selection regime. Re-baselining selection under substrate is open
  future work, not a silent invalidation — recorded here explicitly.

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
