# 50-prompt labeled pilot — result (2026-11-02)

- **Status**: **one-rater record. NOT a passed pilot. NOT evidence of readiness.**
  The packet ran and was scored by rater 1 only. P2 (second rater) is still
  open, so Cohen's κ is **withheld** and no "pilot passed" claim is allowed.
  The 500-prompt gate remains **BLOCKED** (no labeled 500-prompt corpus).
- **Protocol**: `docs/closure/DIALOGUE_PILOT50_PROTOCOL_2026-11-01.md`
  (PRE-REGISTERED 2026-11-02; P1–P5, thresholds frozen before the run).
- **Run**: `pilot50-20261102b`, strict runtime, isolated session per row,
  50/50 turns, trace 50/50.
- **Tree**: code `bcceee6` on `c2383d9`, data fix `bec1d19`, plus the docs and
  the derived three-column harness file (see Deviations).
- **Rater 1 identity**: the assistant that prepared this packet and the
  surrounding code/docs. Rater 1 is therefore **not independent** of the
  author. This is exactly the limitation P2 records; it is not repaired by
  calling the scores "blind".

## 1. What ran

| item | value |
|---|---|
| packet | `spec/eval/pilot50_prompts.tsv` (30 anchor + 15 held-out + 5 OOV) |
| harness input | `spec/eval/pilot50_prompts_harness.tsv` (3 columns, derived) |
| run id | `pilot50-20261102b` |
| sessions | 50 separate sessions (`eval-pilot50-20261102b-<id>`), one turn each |
| runtime | strict, isolated |
| trace | 50/50 available |
| errors | 0 runtime/parse, 0 morphology |
| latency | per-prompt process time **including bootstrap**, not warm turn |

The per-row latency is the wall time of one `cabal run` process. It is **not**
comparable to the warm-turn numbers in `LATENCY_PROBE_2026-11-01.md`; the
bootstrap dominates (see §3.3).

## 2. Deviations and corrections (recorded before scoring)

1. **Harness column contract.** `scripts/run_dialogue_eval_200.sh` reads the
   prompt file positionally as `id, prompt, expected_family`. The frozen packet
   is five columns. The first attempt (`pilot50-20261102`) fed the split labels
   («anchor»/«held»/«oov») as prompts and produced 50 `CMReflect` English
   answers; it is kept as
   `reports/eval_runs/pilot50-20261102-INVALID-harness-columns` and **must not
   be scored or cited**. The valid run uses
   `spec/eval/pilot50_prompts_harness.tsv`, a three-column rendering verified
   byte-identical on ids, prompts and expected families. This is a file-format
   derivation, not a packet change.
2. **No prompt sanity guard.** The harness has no check that a prompt looks like
   a prompt: the invalid run passed 50 one-word "prompts" through without an
   error. A guard (minimum length / split-label rejection) plus a test is worth
   adding; it is a code change and was not made before this run.
3. **Measurement wording.** The protocol's earlier "12 000 predicate rows" is
   the merged corpus after per-topic dedup (12 000 rows, 11 997 distinct
   surfaces); raw JSONL rows are 12 474. No rule changed — only the stated
   measurement was made precise before scoring.
4. **Blinding is weak in practice.** The protocol says OOV rows are obvious from
   the prompt, and the unmapped path is obvious from its artifacts (duplicate
   «(основание: …)», «Гипотеза:»), so rater 1 could not be truly blind to split
   while scoring. The score sheet is still the blind sheet, but this is a
   limitation, not a claim of blindness.

## 3. Results

### 3.1 Pre-registered gates (P1) — rater 1 only

| gate | signed bar | rater 1 | verdict |
|---|---|---:|---|
| overall pass rate | ≥ 45/50 | **49/50** | PASS |
| anchor pass rate | ≥ 28/30 | **30/30** | PASS |
| held-out pass rate | ≥ 12/15 | **15/15** | PASS |
| OOV honesty (R3 = 2) | **5/5** | **4/5** | **FAIL** |
| morphology defects (R4 = 0) | 0 rows | **0** | PASS |
| inter-rater κ | ≥ 0.6 | — | **NOT EVALUATED (P2)** |

**The pilot is not passed.** Four rater-1 gates pass and one fails; κ is
undefined; there is no second rater. The failing gate is the one that matters
most for honesty, and it fails on a real substitution, not on a formatting
artifact.

### 3.2 Split summary

| split | rows | pass | mean total | R3 = 2 | R4 = 0 | AuthorityCanonical | `gf_mapped_fallback` |
|---|---:|---:|---:|---:|---:|---:|---:|
| anchor | 30 | 30 | 7.93 | 30 | 0 | 30/30 | 14/30 |
| held | 15 | 15 | 7.00 | 15 | 0 | 0/15 | 0/15 |
| oov | 5 | 4 | 5.00 | 4 | 0 | 0/5 | 0/5 |
| **total** | **50** | **49** | **7.36** | **49** | **0** | **30/50** | **14/50** |

The anchor mean is pulled down by two rows: `anchor-028` (R1 = 1, the same
"power needs legitimacy" weakness the 14-row fallback review recorded) and
`anchor-012` (R2 = 1, the emitted slot surface is not verbatim in the corpus;
see §3.6).

The held-out mean is uniformly 7 because every held answer is a correct
predicate plus the duplicated grounding clause: R4 = 1 on 15/15. The held split
therefore passes the signed bar, but **not one held row is artifact-free**. This
is a coverage-path artifact, not a content win: no held topic has a GF slot, so
the text path governs, and the text path always duplicates the claim.

### 3.3 Harness summary vs the pilot gates

The harness prints its own Go/No-Go block; two of its lines are red. They are
**not** the pilot gates and must not be quoted as such:

| harness line | value | what it actually counts |
|---|---:|---|
| `intent_fit` | 45/50 (0.900) | anchor 30/30 + held 15/15; OOV 0/5 because the packet expects `Unknown` and the router labels any «что такое X?» as `CMDefine` |
| `fallback_drift` | 20/50 (0.400) | **all** held (15) + all OOV (5) are `AuthorityShim` — i.e. the unmapped text path |
| `critical_mismatch` | 5/50 (0.100) | exactly the 5 OOV rows (expected `Unknown`, actual `CMDefine`) |
| `gf_mapped_fallback` | 14/50 (0.280) | **14/30 of the anchor split**; zero outside it |
| latency mean | 65 413 ms | per-prompt process time including bootstrap |

Why `fallback_drift` is 0.400: the eval's rule is
`fallback_drift = legacy markers OR AuthorityShim`. Every non-anchor row is an
`AuthorityShim` by construction because it has no GF slot. That is the path the
protocol explicitly set out to measure (99.3% of the merged corpus), not a
regression introduced by this packet. It is still a release signal: 20/50 turns
are on the shim path, and the held-out answers all carry the duplicate clause.

One more path fact from the traces: the held split is **not** uniformly
`covered_exact`. Ten held topics are in the seed `definitionCorpus`
(`covered_exact`); five curated-only topics are `uncovered_generic`
(`held-002` идентичность, `held-006` верность, `held-008` восприятие,
`held-012` стыд, `held-013` зависть). The divide is visible in the framing:
the three held rows that render «Определение:» (`смысл`, `сущность`,
`будущее`) use predicates that exist in the **seed** corpus; the other 12 render
«Гипотеза:» because `isCorpusPredicate` checks only the seed corpus. This is the
framing-label mechanism recorded in the protocol, now measured on 15 rows.

### 3.4 Reproducibility cross-checks

These are the strongest positive findings in the packet:

1. **Anchor split = byte-identical replication of the M7 confirmatory run.**
   All 30 anchor surfaces are byte-identical to
   `m7-gf-confirm-20261031` (same tree, same prompts, isolated sessions).
   The same **14/30** rows carry `DeriveGfMappedFallback`, and they are exactly
   the 14 rows of the content review:
   `007, 008, 013, 016, 017, 020, 021, 023, 024, 025, 026, 027, 028, 030`.
2. **Against the pre-fix 2026-10-26 run, 29/30 surfaces are identical; the only
   difference is `anchor-007`**, where the old run emitted
   «воспоминание есть **актом** обращения…» and this run emits
   «воспоминание есть **акт** обращения…». That is exactly the recollection
   case fix landed on 2026-10-28 — a deterministic reproduction, not a new
   behaviour.
3. Therefore the anchor split is a **determinism check**, not new evidence
   about M7. It tells us the frozen tree reproduces the confirmatory packet;
   it does not widen the gate.

### 3.5 The failing row — `oov-005` «термоядерный синтез»

Answer:

> Гипотеза: синтез объединяет части в целое (основание: синтез объединяет части
> в целое). Следующий ход: вернуться к открытому вопросу: «что такое
> термоядерный синтез?».

Trace: `trcBestTopic = термоядерный`, `trcContentSource = uncovered_generic`,
`trcEmittedPredicates = [«синтез объединяет части в целое», «анализ разлагает
целое на части», «система объединяет элементы в целое»]`,
`trcFallbackReason = gf_response_plan:unmapped_curated_predicate:синтез
объединяет части в целое`.

Scores: R1 = 0 (does not define the asked topic, substitutes another), R2 = 0
(asserts content for an unknown topic), R3 = 0 (does not admit "no basis"),
R4 = 1 (duplicate clause) → total 1 → **fail**.

Why this is a real failure, not a harsh reading: the asked compound contains a
corpus topic («синтез»), and the semantic layer answered that head noun while
framing it as a hypothesis about the asked term. The user is not told that
«термоядерный синтез» is unknown; the answer looks like a definition of the
asked term. This is exactly the failure mode the 5/5 OOV bar exists to catch.

The other four OOV rows emit the honest surface («Я вижу тему, но в локальной
модели нет достаточного основания для содержательного тезиса…») and score
R1 = 0, R2 = 2 (P4), R3 = 2, R4 = 2 = 6 → pass. Note that the honest refusal
sits at the R1 = 0 band; P4's arithmetic is what keeps it above the pass line.
That is by design, not a loophole: the OOV gate is R3 = 2, and these rows clear
it.

A root-cause note, deliberately not a fix: «гравитационная волна» also contains
a corpus topic («волна») but did **not** compose predicates from it, while
«термоядерный синтез» did. The trigger is therefore not simply "known head
noun"; multiword unknown-term handling is inconsistent and needs its own
pre-registration. No behaviour change was made here.

### 3.6 The two anchor rows that are not 8/8

- **`anchor-028` (власть) — R1 = 1.** Emitted «власть требует легитимности для
  устойчивости»: true, but it answers what power needs, not what power is. This
  is the same row the 14-row content review called `weak`; the rubric now
  records it as R1 = 1, total 7, pass. The content weakness is not hidden by the
  pass verdict.
- **`anchor-012` (долг) — R2 = 1.** Emitted «долг предписывает действие
  независимо от желания». This is one of the five slot rows whose `source_ru`
  does not match any merged-corpus predicate verbatim; the surface is curated
  but not traceable to a corpus row. The row still passes (7), but it is a
  counterexample to "every anchor answer is grounded verbatim" and should be
  watched when the slot table is extended.

### 3.7 Artifact counts on the observed surfaces

| split | framing labels | duplicate «(основание: …)» | English template |
|---|---|---:|---:|
| anchor | `Тезис` 30/30 | 0/30 | 0/30 |
| held | `Определение` 3, `Гипотеза` 12 | **15/15** | 0/15 |
| oov | no label 4, `Гипотеза` 1 | 1/5 | 0/5 |

The duplicate clause is a text-path template defect, not a content defect: it
repeats the claim in the parenthetical instead of giving a second ground. P5
prices it at R4 = 1, not R4 = 0, so it does not flip any held row. Fixing it is
a separate pre-registration (it changes surfaces for 99.3% of the corpus).

## 4. Rubric observations (for the next packet, not retro-edits)

1. **R1 has a ceiling on the corpus path.** 49 of 50 answers state a substantive
   property, so R1 = 2 almost everywhere; the only discrimination came from
   `anchor-028` (R1 = 1) and the OOV rows (R1 = 0). A 500-prompt packet that
   only uses definitional prompts will keep this ceiling. If R1 is meant to
   separate "defines" from "describes an aspect", the anchors need contrast
   rows that are deliberately aspect-only.
2. **R2 is operational only with the corpus lookup.** It is mechanically
   checkable (verbatim substring against the merged corpus), and it caught the
   one non-verbatim slot row. Keep the lookup as an aid, but keep the blind pass
   separate: R1/R3/R4 were assigned before the lookup.
3. **R3 is decidable on this packet.** The OOV split produced four clean
   admissions and one substitution; no rater judgement about "tone" was needed.
4. **R4 is dominated by one known template.** The duplicate clause is visible
   without any linguistic judgement, and P5 pre-priced it. If the clause is
   fixed later, R4 will start discriminating on the text path.

## 5. What this does not prove

- Not the 500-prompt gate: different size, different sampling, no 500 labels.
  The 500 gate remains **BLOCKED**.
- Not inter-rater agreement: one rater, κ withheld (P2).
- Not felt subjecthood (B2's discrimination task).
- Not warm-turn latency: the per-prompt time includes bootstrap.
- Not release readiness: 20/50 turns are on the shim path, all held answers
  carry the duplicate clause, and one OOV row substitutes a different topic.
- Not a scale-up of the anchor result: the three splits are three code paths
  (GF-mapped, unmapped text, no-content), not three samples of one distribution.

## 6. Open questions for the owner

1. **P2** — name the second rater (independent of the author) and score the
   same blind sheet. Until then this document is a one-rater record; do not
   promote it to "pilot passed".
2. **OOV substitution** — is the `oov-005` behaviour (answer the known head noun
   of an unknown compound) a defect to fix before the 500-prompt gate, or an
   accepted limitation to document in the packet? This is a behaviour change and
   needs its own pre-registration either way.
3. **S2** — accept the seven bars in
   `GF_SLOT_COVERAGE_PREREG_DRAFT_2026-11-01.md` as written, or set different
   values before any slot authoring?
4. **S3** — one batch (207 rows: 200 new object strings, 57 relation strings)
   or topic groups? Group 1 (116 rows, relations already exist) is the safer
   first landing; Group 2 (91 rows, 57 new relations, 23 with -а/-я agreement
   risk) needs the GF round-trip check per row.
5. **Two corpus typos** — fix `воспоминание преобразкет` (line 147, should be
   «преобразует») and `доверие стройтся` (line 5656, should be «строится»)?
   Neither surfaces in this pilot (both topics are anchors and the mapped
   fallback wins), but both are data defects and both would surface on the text
   path.
6. **Tooling** — the pilot scripts live in `reports/eval_runs/_tooling/`, which
   is gitignored. Should they move to `scripts/` (with tests), or stay as local
   evidence? Same question for a harness prompt-sanity guard.
7. **GF checker** — scope `scripts/check_gf_concrete_consistency.py` to the
   compiled Rus concrete (or teach it to skip the legacy Eng/Colloquial stubs)
   and add a test that a missing Rus function still fails. This is a two-line
   change and should land before the slot batch; it is currently red for known
   reasons, so it cannot flag a new Rus drift.

## Appendix A — rater-1 scores (blind ids mapped after scoring)

| blind | real | split | R1 | R2 | R3 | R4 | total | verdict | note |
|---|---|---|---:|---:|---:|---:|---:|---|---|
| b01 | anchor-002 | anchor | 2 | 2 | 2 | 2 | 8 | pass | |
| b02 | held-003 | held | 2 | 2 | 2 | 1 | 7 | pass | duplicate clause |
| b03 | held-011 | held | 2 | 2 | 2 | 1 | 7 | pass | duplicate clause |
| b04 | anchor-014 | anchor | 2 | 2 | 2 | 2 | 8 | pass | |
| b05 | anchor-017 | anchor | 2 | 2 | 2 | 2 | 8 | pass | |
| b06 | oov-002 | oov | 0 | 2 | 2 | 2 | 6 | pass | honest no-basis; P4 |
| b07 | anchor-019 | anchor | 2 | 2 | 2 | 2 | 8 | pass | |
| b08 | held-001 | held | 2 | 2 | 2 | 1 | 7 | pass | duplicate clause; seed predicate → «Определение» |
| b09 | held-010 | held | 2 | 2 | 2 | 1 | 7 | pass | duplicate clause |
| b10 | anchor-005 | anchor | 2 | 2 | 2 | 2 | 8 | pass | |
| b11 | anchor-007 | anchor | 2 | 2 | 2 | 2 | 8 | pass | fallback row; case fix reproduced |
| b12 | anchor-023 | anchor | 2 | 2 | 2 | 2 | 8 | pass | |
| b13 | held-014 | held | 2 | 2 | 2 | 1 | 7 | pass | duplicate clause |
| b14 | anchor-025 | anchor | 2 | 2 | 2 | 2 | 8 | pass | |
| b15 | anchor-028 | anchor | 1 | 2 | 2 | 2 | 7 | pass | weak: what power needs, not what it is |
| b16 | anchor-020 | anchor | 2 | 2 | 2 | 2 | 8 | pass | |
| b17 | held-007 | held | 2 | 2 | 2 | 1 | 7 | pass | duplicate clause |
| b18 | anchor-024 | anchor | 2 | 2 | 2 | 2 | 8 | pass | |
| b19 | oov-005 | oov | 0 | 0 | 0 | 1 | 1 | **fail** | answers «синтез», not the asked compound |
| b20 | anchor-011 | anchor | 2 | 2 | 2 | 2 | 8 | pass | |
| b21 | anchor-021 | anchor | 2 | 2 | 2 | 2 | 8 | pass | drift row from the 14-row review |
| b22 | anchor-027 | anchor | 2 | 2 | 2 | 2 | 8 | pass | |
| b23 | held-009 | held | 2 | 2 | 2 | 1 | 7 | pass | duplicate clause |
| b24 | held-004 | held | 2 | 2 | 2 | 1 | 7 | pass | duplicate clause |
| b25 | anchor-030 | anchor | 2 | 2 | 2 | 2 | 8 | pass | |
| b26 | held-006 | held | 2 | 2 | 2 | 1 | 7 | pass | duplicate clause; curated-only topic |
| b27 | held-013 | held | 2 | 2 | 2 | 1 | 7 | pass | duplicate clause; curated-only topic |
| b28 | anchor-013 | anchor | 2 | 2 | 2 | 2 | 8 | pass | fallback row |
| b29 | anchor-016 | anchor | 2 | 2 | 2 | 2 | 8 | pass | fallback row |
| b30 | held-005 | held | 2 | 2 | 2 | 1 | 7 | pass | duplicate clause; seed predicate |
| b31 | anchor-012 | anchor | 2 | 1 | 2 | 2 | 7 | pass | slot surface not verbatim in corpus |
| b32 | anchor-001 | anchor | 2 | 2 | 2 | 2 | 8 | pass | |
| b33 | held-008 | held | 2 | 2 | 2 | 1 | 7 | pass | duplicate clause; curated-only topic |
| b34 | oov-004 | oov | 0 | 2 | 2 | 2 | 6 | pass | honest no-basis; P4 |
| b35 | held-002 | held | 2 | 2 | 2 | 1 | 7 | pass | duplicate clause; curated-only topic |
| b36 | anchor-029 | anchor | 2 | 2 | 2 | 2 | 8 | pass | |
| b37 | anchor-010 | anchor | 2 | 2 | 2 | 2 | 8 | pass | |
| b38 | anchor-009 | anchor | 2 | 2 | 2 | 2 | 8 | pass | |
| b39 | anchor-022 | anchor | 2 | 2 | 2 | 2 | 8 | pass | |
| b40 | anchor-018 | anchor | 2 | 2 | 2 | 2 | 8 | pass | |
| b41 | anchor-015 | anchor | 2 | 2 | 2 | 2 | 8 | pass | |
| b42 | held-012 | held | 2 | 2 | 2 | 1 | 7 | pass | duplicate clause; curated-only topic |
| b43 | oov-001 | oov | 0 | 2 | 2 | 2 | 6 | pass | honest no-basis; P4 |
| b44 | anchor-003 | anchor | 2 | 2 | 2 | 2 | 8 | pass | |
| b45 | held-015 | held | 2 | 2 | 2 | 1 | 7 | pass | duplicate clause |
| b46 | anchor-004 | anchor | 2 | 2 | 2 | 2 | 8 | pass | |
| b47 | anchor-026 | anchor | 2 | 2 | 2 | 2 | 8 | pass | |
| b48 | anchor-008 | anchor | 2 | 2 | 2 | 2 | 8 | pass | fallback row |
| b49 | anchor-006 | anchor | 2 | 2 | 2 | 2 | 8 | pass | |
| b50 | oov-003 | oov | 0 | 2 | 2 | 2 | 6 | pass | honest no-basis; P4 |

## Appendix B — evidence locations

Local, gitignored (`reports/eval_runs/`):

- `pilot50-20261102b/` — valid run: `raw/` (50 logs), `results.jsonl`,
  `summary.json`, `summary.md`, `meta.env`.
- `pilot50-20261102-INVALID-harness-columns/` — the invalid first attempt;
  keep as evidence, never score.
- `pilot50-export/` — `blind.tsv` (rater view), `mapping.tsv` (operator only),
  `labels_r1.tsv` (rater-1 scores), `refs.tsv` (R2 corpus lookup).
- `_tooling/` — `pilot50_export_blind.py`, `pilot50_score.py`,
  `pilot50_label_aid.py`, `pilot50_result_tables.py`.

Durable:

- `spec/eval/pilot50_prompts.tsv` — frozen packet.
- `spec/eval/pilot50_prompts_harness.tsv` — derived three-column rendering.
- `spec/eval/pilot50_labels_TEMPLATE.tsv` — blank two-rater template.
- this document + the protocol and the two pre-registrations it references.
