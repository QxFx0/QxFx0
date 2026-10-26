# M7 Bounded Evidence Packet — Governed GF Release Corpus (2026-10-26)

- **Status**: **FAIL (bounded packet)** — routing classification PASS, GF surface/canonical FAIL; **M7 remains OPEN**.
- **Scope**: 30 Russian definition prompts from `spec/gf/release_corpus_prompts.txt` (the governed GF release corpus).
- **Runtime**: `QXFX0_RUNTIME_MODE=strict`, `QXFX0_EVAL_SESSION_MODE=isolated`, GHC 9.6.7, substrate active.
- **Expected family**: `CMDefine` for all 30 prompts (definition questions).
- **Command**: `QXFX0_RUNTIME_MODE=strict QXFX0_EVAL_SESSION_MODE=isolated bash scripts/run_dialogue_eval_200.sh m7-gf-release-20261026 <tsv>`
- **Artifacts**: `reports/eval_runs/m7-gf-release-20261026/` (gitignored) and `/tmp/opencode/qxfx0-m7-gf-release-20261026/` (ephemeral).

## Headline result

| metric | value | threshold / expectation | verdict |
|---|---:|---:|---|
| total prompts | 30 | 30 | PASS |
| routing family `CMDefine` | 30/30 (1.000) | 30/30 | PASS |
| runtime/parse errors | 0 | 0 | PASS |
| morphology defects (script markers) | 0 | 0 | PASS |
| fallback/template drift (script markers) | 0 (0.000) | <= 0.05 | PASS (but see instrumentation gap) |
| trace `AuthorityCanonical` | 16/30 | 30/30 | **FAIL** |
| trace `AuthorityShim` | 14/30 | 0/30 | **FAIL** |
| `unmapped_curated_predicate` fallback | 14/30 | 0/30 | **FAIL** |
| exact golden surface | 4/30 (0.133) | 30/30 | **FAIL** |

The routing layer classifies all 30 prompts as `CMDefine`, but the rendered surface is not a canonical definition for 14 of them. `trcContentSource=covered_exact` on all 30 is therefore **not** sufficient evidence of a definitional response: the GF response-plan layer can still fail and fall back to `AuthorityShim`.

## Supplemental trace smoke (5 prompts)

`gf_release_audit.py --mode latency` on the first 5 prompts (persistent worker, strict runtime) recorded canonical rate `1.0`, fallback histogram `{"none": 5}`, quality issues `0`, semantic substitutions `0`; warm wall median `34,491 ms`, warm p95 `43,185 ms` — above the audit’s `10,000 ms` threshold. Cold CLI wall was `64,005 ms`, bootstrap `20,217 ms`. This smoke did not hit the 14 unmapped predicates (the first five are canonical), so it does not contradict the 30-prompt failure; it is a latency/observability smoke only.

## Root cause 1 — 14/30 curated predicates are unmapped by the GF response plan

The trace records `gf_response_plan:unmapped_curated_predicate:<predicate>` and `trcLinearizationOk=false` for these turns; the surface falls back to an exploratory/hypothesis form (`Гипотеза: ... Следующий ход: вернуться к открытому вопросу ...`). This is a **GF response-plan coverage gap**, not a routing-family error.

| # | prompt | selected predicate | exact golden |
|---:|---|---|---|
| gf-rel-007 | что такое воспоминание? | воспоминание восстанавливает прошлое в настоящем | no |
| gf-rel-008 | что такое сознание? | сознание есть основание субъектности | no |
| gf-rel-013 | что такое доверие? | доверие открывает возможность сотрудничества | no |
| gf-rel-016 | что такое справедливость? | справедливость требует равенства возможностей | no |
| gf-rel-017 | что такое время? | время устанавливает границы между прошлим и будущим | no |
| gf-rel-020 | что такое история? | история складывается из событий и их интерпретации | no |
| gf-rel-021 | что такое язык? | язык выражает и структурирует мысль | no |
| gf-rel-023 | что такое смерть? | смерть выражает конечность бытия | no |
| gf-rel-024 | что такое одиночество? | одиночество обнаруживает границу между я и другими | no |
| gf-rel-025 | что такое любовь? | любовь преодолевает границу между я и другим | no |
| gf-rel-026 | что такое труд? | труд выражает целенаправленное усилие | no |
| gf-rel-027 | что такое покой? | покой выражает отсутствие напряжения | no |
| gf-rel-028 | что такое власть? | власть это способность и возможность влиять на поведение людей | no |
| gf-rel-030 | что такое молчание? | молчание выражает позицию через отсутствие слов | no |

## Root cause 2 — mapped responses still diverge from the golden surface

The remaining 16/30 turns are `AuthorityCanonical`, but only 4/30 match the golden surface exactly. The divergence is not one class:

- **Exact golden matches**: 4/30 (`gf-rel-001`, `gf-rel-005`, `gf-rel-010`, `gf-rel-012`).
- **Definitional but incomplete** (missing `Контрпункт`/`Следствие` from the golden): 11/30 — gf-rel-002, gf-rel-004, gf-rel-006, gf-rel-009, gf-rel-011, gf-rel-014, gf-rel-015, gf-rel-018, gf-rel-019, gf-rel-022, gf-rel-029.
- **Different full definition** (all four sections, different predicate): 1/30 — gf-rel-003.
- **Exploratory/open-question shim**: 14/30 — gf-rel-007, gf-rel-008, gf-rel-013, gf-rel-016, gf-rel-017, gf-rel-020, gf-rel-021, gf-rel-023, gf-rel-025, gf-rel-026, gf-rel-027, gf-rel-028, gf-rel-030, gf-rel-024.

The 4 exact matches and the 11 partial definitions show that Field-driven per-predicate top-1 selection can legitimately choose a different predicate than the golden file. That makes exact golden replay a **stability/acceptance** question for the 16 mapped turns. It does **not** explain the 14 shim turns: those are a hard GF mapping failure and would fail any definitional-content acceptance criterion.

## Gate-instrumentation gap

The dialogue-eval script reports `fallback_drift_rate=0.000` and `critical_mismatch_rate=0.000` for this run, yet 14/30 surfaces are exploratory shims. Its fallback markers do not include `AuthorityShim`, `Гипотеза`, `Следующий ход`, or `unmapped_curated_predicate`; the trace is the authoritative signal here. Do not cite the script’s fallback/critical counters as content-completeness evidence without adding a trace-level canonical-rate check.

## Per-prompt evidence

| # | prompt | family | authority | fallback / note | exact golden |
|---:|---|---|---|---|---|
| gf-rel-001 | что такое свобода? | `CMDefine` | `AuthorityCanonical` | canonical | yes |
| gf-rel-002 | что такое произвол? | `CMDefine` | `AuthorityCanonical` | canonical | no |
| gf-rel-003 | что такое ответственность? | `CMDefine` | `AuthorityCanonical` | canonical | no |
| gf-rel-004 | что такое истина? | `CMDefine` | `AuthorityCanonical` | canonical | no |
| gf-rel-005 | что такое мнение? | `CMDefine` | `AuthorityCanonical` | canonical | yes |
| gf-rel-006 | что такое память? | `CMDefine` | `AuthorityCanonical` | canonical | no |
| gf-rel-007 | что такое воспоминание? | `CMDefine` | `AuthorityShim` | unmapped_curated_predicate | no |
| gf-rel-008 | что такое сознание? | `CMDefine` | `AuthorityShim` | unmapped_curated_predicate | no |
| gf-rel-009 | что такое самосознание? | `CMDefine` | `AuthorityCanonical` | canonical | no |
| gf-rel-010 | что такое вера? | `CMDefine` | `AuthorityCanonical` | canonical | yes |
| gf-rel-011 | что такое красота? | `CMDefine` | `AuthorityCanonical` | canonical | no |
| gf-rel-012 | что такое долг? | `CMDefine` | `AuthorityCanonical` | canonical | yes |
| gf-rel-013 | что такое доверие? | `CMDefine` | `AuthorityShim` | unmapped_curated_predicate | no |
| gf-rel-014 | что такое страх? | `CMDefine` | `AuthorityCanonical` | canonical | no |
| gf-rel-015 | что такое надежда? | `CMDefine` | `AuthorityCanonical` | canonical | no |
| gf-rel-016 | что такое справедливость? | `CMDefine` | `AuthorityShim` | unmapped_curated_predicate | no |
| gf-rel-017 | что такое время? | `CMDefine` | `AuthorityShim` | unmapped_curated_predicate | no |
| gf-rel-018 | что такое разум? | `CMDefine` | `AuthorityCanonical` | canonical | no |
| gf-rel-019 | что такое бытие? | `CMDefine` | `AuthorityCanonical` | canonical | no |
| gf-rel-020 | что такое история? | `CMDefine` | `AuthorityShim` | unmapped_curated_predicate | no |
| gf-rel-021 | что такое язык? | `CMDefine` | `AuthorityShim` | unmapped_curated_predicate | no |
| gf-rel-022 | что такое воля? | `CMDefine` | `AuthorityCanonical` | canonical | no |
| gf-rel-023 | что такое смерть? | `CMDefine` | `AuthorityShim` | unmapped_curated_predicate | no |
| gf-rel-024 | что такое одиночество? | `CMDefine` | `AuthorityShim` | unmapped_curated_predicate | no |
| gf-rel-025 | что такое любовь? | `CMDefine` | `AuthorityShim` | unmapped_curated_predicate | no |
| gf-rel-026 | что такое труд? | `CMDefine` | `AuthorityShim` | unmapped_curated_predicate | no |
| gf-rel-027 | что такое покой? | `CMDefine` | `AuthorityShim` | unmapped_curated_predicate | no |
| gf-rel-028 | что такое власть? | `CMDefine` | `AuthorityShim` | unmapped_curated_predicate | no |
| gf-rel-029 | что такое правда? | `CMDefine` | `AuthorityCanonical` | canonical | no |
| gf-rel-030 | что такое молчание? | `CMDefine` | `AuthorityShim` | unmapped_curated_predicate | no |

## What this packet proves

- The routing classifier is stable on the 30 official definition prompts: `CMDefine` 30/30.
- The GF response-plan layer is **not** complete for the selected curated predicates: 14/30 fall to `AuthorityShim` with `unmapped_curated_predicate`.
- Exact golden replay is not stable even for mapped turns: 4/30 exact; 11/30 are definitional but omit golden counterpoint/consequence sections.
- The current dialogue-eval fallback/critical counters are blind to this class; trace-level canonical rate must be part of the acceptance check.

## What this packet does not prove

- It is **not** the 500-prompt dialogue release gate. `reports/dialogue_eval_500_prompts.tsv` is absent, and `scripts/run_release_dialogue_gate.sh` falls back to the ~60-prompt English baseline; no labeled 500-prompt Russian set exists in the tree.
- It does not exercise challenge/repair, commitment accountability, distinction breadth, or production traffic.
- It does **not** close M7. M7 remains OPEN; this is one bounded evidence packet that failed its definitional-content acceptance.

## 500-prompt gate status

**BLOCKED as specified.** The missing labeled 500-prompt Russian corpus is a prerequisite. Do not cite this packet as a 500-prompt eval or as M7 closure.

## Recommended next step

1. Pre-register a bounded GF response-plan coverage fix for the 14 `unmapped_curated_predicate` entries above (mapping/rendering only; no routing or safety change). The proposed mapped-predicate fallback is pre-registered in `docs/closure/M7_GF_MAPPING_FALLBACK_PREREG_2026-10-26.md`.
2. Re-run this 30-prompt packet and require `AuthorityCanonical` 30/30 before discussing exact golden.
3. Decide the golden acceptance rule for the 16 mapped turns: exact-surface baseline, semantic predicate match, or a documented re-baseline after per-predicate selection. Do not silently re-baseline before that decision.
4. Keep M7 OPEN and the 500-prompt gate BLOCKED until both the content fix and the labeled corpus exist.
