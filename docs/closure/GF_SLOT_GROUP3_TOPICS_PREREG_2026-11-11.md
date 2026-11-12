# Pre-registration — GF slot batch, group 3: +12 covered topics (2026-11-11)

- **Status**: EXECUTED 2026-11-12 — see `## Result`. Bars B1–B9 all pass on
  the landing tree; the 500-prompt gate stays **BLOCKED** (it needs labeled rows
  and a second independent rater, not code).
- **Trigger**: owner decision 2026-11-11. Of the three presented paths to the
  500-prompt gate, the owner chose **(1) +12 topics** — not (2) +5 verified
  carriers and not (3) a re-scope of the gate to N=360.
- **Scope**: coverage only. No runtime semantics, no new GF construction, no
  corpus edit, no prompt-file change, no frame freeze.
- **Why exactly 12**: the GF-enriched ceiling is
  `covered topics × verified carriers` = `topics × 12`. The gate needs ≥ 500
  rows, so ≥ 42 topics (`⌈500/12⌉`). The table covers 30 today, so the minimum
  honest step is +12 → 42 × 12 = **504**.

## Measurement rule (deterministic, committed tooling)

The selection must be reproducible from committed tools. The 2026-11-06
prereg's 286/207/116/91 figures were not reproducible because the measuring
script was never committed; that failure must not repeat.

1. `scripts/eval/gf_slot_gap.py` gains `--select-topics N`: rank the runtime
   dump's topics that are (a) not already slot-covered, (b) single-word, by the
   number of **group-1-classifiable** predicates — the predicate surface is
   `<topic> <existing relation> <object>` — descending; ties broken by topic
   string ascending; take the first `N`. The ranking is printed and the
   selection is frozen together with the gap list.
2. Rule rationale for (b): all 30 existing subjects are single-word and the
   carrier is a prefix of «что такое <topic>?». A multi-word topic changes the
   extraction surface (`oov-005` D-1 exact span) and would confound a
   phrasing-robustness frame.
3. **Corrected 2026-11-12 — the pre-registered estimate was not reproducible.**
   The 2026-11-11 figures came from an ad-hoc snippet that counted raw dump
   lines; the committed tool de-duplicates `(topic, surface)` pairs and applies
   the tie-break, which moves both the counts and the 12th-boundary selection.
   The tool's numbers are authoritative:

   | | ad-hoc 2026-11-11 (superseded) | committed tool 2026-11-12 |
   |---|---|---|
   | topics | экономика 15, закон 14, нация 14, анализ 13, гнев 13, здоровье 13, класс 13, музыка 13, наука 13, общество 13, технология 13, цель 13 | закон 14, нация 14, экономика 14, анализ 13, здоровье 13, музыка 13, наука 13, общество 13, технология 13, цель 13, биология 12, география 12 |
   | rows | 160 | **157** |

   The boundary is a real tie at 12 rows: биология, география, гнев and класс
   all have 12, and the name tie-break picks биология and география. The
   ceiling is unaffected — it is still 12 topics, so 42 × 12 = **504**.
   Measured over `reports/eval_runs/_logs/harness-20261111/corpus-dump.tsv`
   (12 325 lines, 4 070 topics, 2 642 candidate topics); all 12 selected topics
   are in the merged corpus **and** in the curated topic list, so each counts
   toward `corpus.gf` in `prompt_frame_500.py`.
4. Freeze: `spec/gf/gf_slot_gap_group3_2026-11-11.tsv` + `.sha256` sidecar.

## Tooling change required (spec tooling, not runtime)

`scripts/add_gf_slot_rows.py` group-1 mode currently refuses a topic with no
existing `subject_id` (`subject {topic!r} has no existing id`). The 12 new
topics have none, so the generator gains subject-id minting with the **same**
rule it already uses for objects: `unique(slug(transliterate(topic)))`, with
the minted ids printed and covered by a self-test case. No other behaviour
changes: existing rows are still refused unless they reconstruct `source_ru`
byte for byte, and relations must still exist.

## Bars

| # | Bar | Measure |
|---|---|---|
| B1 | Selection is reproducible | two runs of `gf_slot_gap.py --select-topics 12` over the same dump print the same ranking and the same frozen digest |
| B2 | Exactly 157 rows appended | table 305 → **462** data rows (157 rows; corrected 2026-11-12 from the ad-hoc 160 — see the measurement rule); the generator reports 0 problems; every row reconstructs `source_ru` from `topic + relation + object` byte for byte |
| B3 | New subject ids are deterministic | the generator prints the 12 minted ids; a second run over the same inputs is byte-identical; 0 id collisions with existing subjects |
| B4 | No new relation surfaces, no new constructions | group-1 mode only uses existing relations; `git diff` on the regenerated `QxFx0Syntax.gf` / `QxFx0SyntaxRus.gf` shows only new `Subject*` / `Object*` constructors, no new `fun` and no new `cat` |
| B5 | 4-point realizability | `gf_slot_realizability.py` on the new table: **462/462** on constructors, generated Haskell, GF round-trip and corpus identity; the known-failure baseline stays empty |
| B6 | Pins updated | `Test.Suite.ResponsePlan` `curatedPredicateSlotCount` 305 → **462** (the only pinned count in the tree) |
| B7 | The 30-prompt packet is untouched | gate **30/30**, `gf_mapped_fallback` **0/30**, determinism **0/30** predicate and **0/30** surface mismatches against `m7-harness-20261111`; the packet's own rows still realize |
| B8 | Ceiling reached | `prompt_frame_500.py --enriched --max` reports ceiling **504** over **42** topics; `--size 500` succeeds |
| B9 | Landing matrix | full matrix on the landing tree (unit / fast / property / integration / main runtime+http / slow groups) |

## What this does NOT do

- **Does not freeze the 500-row frame.** Freezing needs a separate owner
  decision (2026-11-09: build the tooling first, do not freeze a frame).
- **Does not unblock the gate.** It needs 500 *labeled* rows and a second
  independent rater — ~11 h of eval at current latency plus ~17 h of two-rater
  labeling. The gate stays **BLOCKED** after this batch.
- **Is not M6-FELT, M7 or release evidence.** S2/M7 remains closed only for the
  bounded 30-prompt packet.
- **Does not cover the 4 deferred group-2 rows** — they are out of scope by the
  2026-11-11 amendment in
  `GF_SLOT_BATCH_GROUP2_RESULT_2026-11-09.md`.

## Result

**Verdict: bars B1–B9 all PASS on the landing tree (`a53228f` + the change set,
tree byte-identical start→end).** The table grows 305 → **462** data rows, the
GF-enriched ceiling reaches **504** over **42** topics, and the bounded M7
30-prompt packet is unchanged to the surface. The 500-prompt gate is still
**BLOCKED** (see "What this does NOT do").

| # | Bar | Result | Evidence |
|---|---|---|---|
| B1 | Selection is reproducible | **PASS** — two runs over the pre-batch (305-row) table and the frozen dump print the same ranking and the same digest `fa5fd7cb…0b843d87`, byte-identical to the committed `.tsv`/`.sha256` | `reports/eval_runs/_logs/matrix-20261112/b1-prebatch-{a,b}.txt` |
| B2 | Exactly 157 rows appended | **PASS** — 305 → **462** data rows; generator reports `candidates: 157  skipped: 42  problems: 0`; every row reconstructs `source_ru` from `topic + relation + object` (the generator refuses otherwise, and the 4-point `corpus_identity` check re-proves it) | generator output; `slot-realizability.txt` |
| B3 | New subject ids are deterministic | **PASS** — 12 minted ids (`analiz`, `biologiya`, `geografiya`, `zakon`, `zdorove`, `muzyka`, `nauka`, `natsiya`, `obshchestvo`, `tehnologiya`, `tsel`, `ekonomika`), no collision with the 30 existing subjects; two dry-runs over the same inputs are byte-identical | `b3-run-{a,b}.txt` |
| B4 | No new relation surfaces, no new constructions | **PASS** — abstract `QxFx0Syntax.gf` gained exactly 12 `Subject*` + 147 `Object*` constructor lines and nothing else (0 `cat`/`fun` lines); concrete `QxFx0SyntaxRus.gf` gained exactly the matching 12 + 147 linearizations | `b4-b5-evidence.txt` |
| B5 | 4-point realizability | **PASS** — **462/462** on constructors, generated Haskell, GF round-trip and corpus identity; the known-failure baseline is still header-only (empty) | `reports/eval_runs/m7-gf-group3-20261112/slot-realizability.txt` |
| B6 | Pins updated | **PASS** — `curatedPredicateSlotCount` 305 → **462**; `Test.Suite.ResponsePlan` 41/41 green | `QXFX0_UNIT_SUITE=ResponsePlan` run |
| B7 | The 30-prompt packet is untouched | **PASS** — gate **30/30** (structural + predicate), `authority_canonical` 30/30, `gf_mapped_fallback` **0/30**, `fallback_drift` 0; determinism **0/30** predicate and **0/30** surface mismatches both run-vs-replica and run-vs-`m7-harness-20261111`; the packet's own rows realize 462/462 | `reports/eval_runs/m7-gf-group3-20261112{,-replica}/`, `determinism.txt`, `determinism-vs-20261111.txt` |
| B8 | Ceiling reached | **PASS** — `prompt_frame_500.py --enriched --max` reports **ceiling 504** over **42** topics; `--size 500` succeeds and writes 500 rows, all `gf_mapped` (12 carriers × 42 topics, 0 multiword) | `reports/eval_runs/_logs/matrix-20261112/frame500-manifest.json`, `frame500.tsv` |
| B9 | Landing matrix | **PASS** — 10/10 steps exit 0, **4 379** cases: unit 1838, fast 1931, property 244, integration 47, main http 23, slow http 23, slow lifecycle 11, main runtime 106, slow state 50, slow runtime 106. `check_architecture.sh` and `check_generated_artifacts.sh` also green | `reports/eval_runs/_logs/matrix-20261112/` |

### Notes on the measurement and the freeze

- **The frozen row list is a point-in-time artifact.** Re-running
  `gf_slot_gap.py` against the *post-batch* table is expected to produce a
  different gap list, because the 157 new surfaces are now `mapped`
  (`note = slot_exists`) instead of group 1. That is why B1 is measured against
  the pre-batch table (`git show a53228f:spec/gf/curated_predicate_slots.tsv`)
  and why `add_gf_slot_rows.py` pins the frozen digest instead of re-deriving
  it. It is the same contract the 2026-11-06 gap file already follows.
- **M7 is a bounded packet, not breadth evidence.** B7 says the 30-prompt
  packet is unchanged; it says nothing about the 4 070-topic corpus. S2/M7
  remains closed only for that packet.
- **Latency numbers from the B7 runs are not stall evidence.** The two passes
  ran while the test binaries were being rebuilt on the same box, so their
  `avg_latency_ms` (77 s / 81 s per turn) is contended. The stall question is
  governed by `TURN_STALL_DIAGNOSIS_2026-11-09.md`, not by this run.

### Follow-up this batch creates

`gf_slot_gap.py` now needs a documented convention for re-freezing a gap list
after a coverage batch lands (today the digest simply stops matching and the
tool prints a different list). This is tooling hygiene, not a gate blocker, and
it is not part of this batch.
