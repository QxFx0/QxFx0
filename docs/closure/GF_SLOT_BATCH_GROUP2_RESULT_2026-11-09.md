# GF slot batch, group 2 — measurement result (2026-11-09)

- **Status**: **landed 2026-11-09** as `73cd1c7` (batch) + `fe9c802`
  (admissible-set amendment). The batch is the second half of S2 (S3 scope)
  and closes bars 1, 2, 3, 5, 6, 7 for the bounded 30-prompt packet.
- **Scope measured**: group 2 — 98 rows appended to
  `spec/gf/curated_predicate_slots.tsv` (305 data rows total, 62 new relation
  surfaces), 4 rows deferred as schema-incompatible, three regenerated files
  (`QxFx0Syntax.gf`, `QxFx0SyntaxRus.gf`, `SemanticSlots.hs`), GF recompiled
  (`QxFx0Syntax.pgf` + manifest, 687 266 bytes), test pin `207` → `305`,
  `scripts/add_gf_slot_rows.py` gained `--group2`/`--splits`.
- **Runs**: `reports/eval_runs/m7-gf-batch-20261108c` and `…d`, strict /
  isolated, 30-prompt packet (`spec/gf/m7_gf_case_30.tsv`, blob sha256
  `d1a66154…62d9cb`), same harness and checker as `m7-gf-batch-20261108a/b`.
- **Packet line endings**: `core.autocrlf=true` checks the packet out as CRLF;
  the prompt is column 2, so no `\r` reaches the CLI (verified: 0 prompts with
  CR in both result sets). The pinned digest is the committed blob.

## What was authored

The frozen gap (`spec/gf/gf_slot_gap_2026-11-06.tsv`, sha256
`10ecdb6a…765cdc6`) has 102 group-2 rows and 65 head hints, none of which is
an existing relation surface. The head hint is explicitly *not* the relation,
so the split is authored and frozen:

`spec/gf/gf_slot_group2_splits_2026-11-08.tsv` — 102 rows = 98 `authored` +
4 `deferred`, sha256 `540d7472…c1ce50`. The generator refuses the batch
unless every group-2 row has exactly one entry, every authored row
reconstructs `source_ru` byte for byte, and every deferred row carries a
reason. An independent second script re-derived the 98 appended rows from the
frozen gap: 0 reconstruction failures, 0 topic mismatches, 62 distinct new
relation surfaces, 0 overlap with the previous 48.

Relation convention: the relation is the predicate head and prepositions stay
with the object (`основана` + `на доверии`, `учит` + `на ошибках`), matching
the existing table (`ориентирует` + `на возможность будущего`). The two
negations are the exception (`не сводится` + `к полезности`, `не является` +
`отсутствием движения`). `opredelyaet` was already taken by the existing
relation `определяет,` (with comma), so the new surface is `opredelyaet_2`.

### The 4 deferred rows

| row | reason |
|---|---|
| бытие основная категория философии | attributive long-form adjective; the schema has no copula, so it cannot head a predicate |
| память избирательна и реконструктивна | compound predicative adjective, no object |
| красота в глазах смотрящего | prepositional phrase; no predicate |
| любовь вдохновляет | intransitive verb; no object |

Deferral is an owner decision (2026-11-08/09): the count was corrected from
3 to 4 when `любовь вдохновляет` was found to be intransitive. The frozen gap
still contains these 4 rows; they are the only group-2 rows without slots.

## 4-point realizability (bar 4)

`scripts/eval/gf_slot_realizability.py --dump <runtime dump>` on 305 rows:

```
constructors:      PASS (305/305 rows)
generated_haskell: PASS (305/305 rows)
gf_round_trip:     PASS (305/305 rows)
corpus_identity:   PASS (305/305 rows)
```

The dump is reproducible from the embedded program in
`scripts/eval/gf_slot_gap.py` (`extendedDefinitionCorpus`, 12 325 lines) —
the `/tmp` copy from 2026-11-08 was lost with the temp dir and regenerated.

The known-failure baseline (`spec/gf/gf_slot_realizability_baseline.tsv`) is
now **empty** (0 known failures, sha256 `510406fd…483c99`): the two defects
group 1 fixed (duplicate object id, broken round-trip) are gone, so a pinned
red set would have rotted. `--baseline` mode passes.

## Bars (S2, signed 2026-11-06)

| # | bar | measured | verdict |
|---|---|---|---|
| 1 | gate pass 30/30 | **30/30** in both runs after the 2026-11-09 signature of 5 own-selection rows | **PASS** |
| 2 | `gf_mapped_fallback` ≤ 2 | **0/30** (was 5/30) | **PASS** |
| 3 | emitted = system's own selection ≥ 28/30 | **30/30** (was 25/30); `DeriveGfMappedFallback` appears 0 times | **PASS** |
| 4 | new rows failing the 4-point check = 0 | **305/305**, 0 failures | **PASS** |
| 5 | determinism, two runs | **0/30** predicate mismatches, **0/30** surface mismatches | **PASS** |
| 6 | full test matrix on the landing tree | **10/10 steps green**; 4 359 cases, 0 errors, 0 failures | **PASS** |
| 7 | no new `drift`/`weak` row vs the 14-row verdicts | 5 turns changed, all to the system's own selection; owner signed the content 2026-11-09 | **PASS** |

Notes:

- Bars 2 and 3 are two views of the same substitution. Group 1 cut it from
  14 to 5; group 2 removes it entirely.
- Bar 1's five new rows are `curated-approved` (the system's own corpus
  selection, not a fallback substitute). The five old substitutes stay in the
  admissible set: the gate is a membership test, not an exclusive list. Set:
  59 rows, sha256 `7c3576f2…7ed10f`, dates 2026-10-28 / 2026-11-08 / 2026-11-09.
- Exact-surface match stays informational (D4): 4/30.

## The 5 changed turns (bar 7 input)

| id | topic | group-1 emitted (substitute) | group-2 emitted (own selection) |
|---|---|---|---|
| gf-rel-013 | доверие | доверие требует уязвимости | доверие открывает возможность сотрудничества |
| gf-rel-017 | время | время выражает последовательность становления | время устанавливает границы между прошлым и будущим |
| gf-rel-020 | история | история сохраняет память о прошлом | история складывается из событий и их интерпретации |
| gf-rel-024 | одиночество | одиночество выражает отсутствие значимого другого | одиночество обнаруживает границу между я и другими |
| gf-rel-025 | любовь | любовь это глубокое чувство привязанности | любовь преодолевает границу между я и другим |

The other 25 turns are byte-identical to the group-1 run. All 30 emitted
predicates are in the 305-row table: 16 pre-existing, 9 group-1, 5 group-2.

## Bar 6 — full test matrix (2026-11-09)

Ten steps, same shape as `docs/closure/TEST_MATRIX_2026-11-01.md`,
sequential, tree fixed (`tree.before` == `tree.after`). Logs:
`reports/eval_runs/_logs/matrix-20261109/`.

| step | command | cases | exit | wall |
|---|---|---:|---:|---:|
| unit | `cabal test qxfx0-test-unit` | 1828 | 0 | 100 s |
| fast | `cabal test qxfx0-test-fast` | 1921 | 0 | 3 323 s |
| property | `cabal test qxfx0-test-property` | 244 | 0 | 44 s |
| integration | `cabal test qxfx0-test-integration` | 47 | 0 | 643 s |
| main-runtime | `QXFX0_AGGREGATE_GROUP=runtime` | 106 | 0 | 5 070 s |
| main-http | `QXFX0_AGGREGATE_GROUP=http` | 23 | 0 | 611 s |
| slow-runtime | `QXFX0_SLOW_GROUP=runtime` | 106 | 0 | 4 938 s |
| slow-state | `QXFX0_SLOW_GROUP=state` | 50 | 0 | 3 791 s |
| slow-http | `QXFX0_SLOW_GROUP=http` | 23 | 0 | 543 s |
| slow-lifecycle | `QXFX0_SLOW_GROUP=lifecycle` | 11 | 0 | 453 s |

Total: **4 359 cases**, 0 errors, 0 failures. The fast suite that flaked once
on the group-1 tree (`testPersistentWorkerRetainsPendingTasks`, pre-existing
SQLITE_BUSY close race) passed first try here.

## Latency outlier (honest note)

Run `c` had one turn (`gf-rel-010`, «что такое вера?») take **4 987 s**
(83 min); the run's average is 238 s and run `d`'s average is 77 s. The run
completed with 0 errors and the turn's trace and surface are byte-identical to
run `d`'s fast execution. This is not a slot-batch regression: no code on the
turn path changed. Diagnosed in
`docs/closure/TURN_STALL_DIAGNOSIS_2026-11-09.md` — 99.94 % of the turn is the
render phase, which is a ~49 s / ~69 GB-allocation pure computation with no
blocking construct on its path; the 100× slowdown itself is not attributable to
a code path and is not root-caused. An earlier draft of this section said the
process was "alive and progressing (observed in `ps`)"; no such observation
artifact exists, so that claim was removed.

## What this establishes

- Group 2 is mechanically realizable: 305/305 on the 4-point rule, identical
  surfaces and predicates across two runs.
- It closes bars 1, 2, 3, 5, 6 and 7. Bar 4 was already green for group 1 and
  stays green with the larger table.
- S2 is closed **for the bounded 30-prompt packet**. The 500-prompt gate stays
  BLOCKED: no labeled GF-enriched 500-row frame exists. This is not a release
  gate and not M6-FELT evidence.

## Artifacts

- `spec/gf/gf_slot_group2_splits_2026-11-08.tsv` — the authored 102-row split.
- `spec/gf/curated_predicate_slots.tsv` — 305 data rows.
- `reports/eval_runs/m7-gf-batch-20261108c/` — results, summary, raw logs,
  `gate-check.txt` (30/30), `slot-realizability.txt` (305/305).
- `reports/eval_runs/m7-gf-batch-20261108d/` — determinism replica, same gate.
- `reports/eval_runs/_logs/matrix-20261109/` — per-step matrix logs and
  `summary.txt`.
