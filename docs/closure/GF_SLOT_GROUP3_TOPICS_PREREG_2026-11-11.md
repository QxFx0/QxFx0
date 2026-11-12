# Pre-registration — GF slot batch, group 3: +12 covered topics (2026-11-11)

- **Status**: PRE-REGISTERED; **not executed** (the batch must not start until
  the tmp-fsync matrix has finished — the tree stays fixed during a matrix run).
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
3. Measured 2026-11-11 from
   `reports/eval_runs/_logs/harness-20261111/corpus-dump.tsv` (12 325 lines,
   4 070 topics, 2 642 candidate topics): the top 12 are экономика 15, закон
   14, нация 14, анализ 13, гнев 13, здоровье 13, класс 13, музыка 13, наука
   13, общество 13, технология 13, цель 13 = **160 rows**. There is no tie at
   the 12th boundary (the 13th, биология, has 12). All 12 topics are in the
   merged corpus **and** in the curated topic list, so each one counts toward
   `corpus.gf` in `prompt_frame_500.py`.
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
| B2 | Exactly 160 rows appended | table 305 → **465** data rows; the generator reports 0 problems; every row reconstructs `source_ru` from `topic + relation + object` byte for byte |
| B3 | New subject ids are deterministic | the generator prints the 12 minted ids; a second run over the same inputs is byte-identical; 0 id collisions with existing subjects |
| B4 | No new relation surfaces, no new constructions | group-1 mode only uses existing relations; `git diff` on the regenerated `QxFx0Syntax.gf` / `QxFx0SyntaxRus.gf` shows only new `Subject*` / `Object*` constructors, no new `fun` and no new `cat` |
| B5 | 4-point realizability | `gf_slot_realizability.py` on the new table: **465/465** on constructors, generated Haskell, GF round-trip and corpus identity; the known-failure baseline stays empty |
| B6 | Pins updated | `Test.Suite.ResponsePlan` `curatedPredicateSlotCount` 305 → **465** (the only pinned count in the tree) |
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

_To be filled in after execution._
