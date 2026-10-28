# M7 GF mapped-predicate fallback — bounded packet result (2026-10-26)

- **Status**: **PASS on the canonical-mapping gate; M7 remains OPEN**.
  `AuthorityCanonical` is 30/30, but exact golden replay is 5/30 and one
  fallback-selected surface exposes a pre-existing GF case defect.
- **Pre-registration**: `docs/closure/M7_GF_MAPPING_FALLBACK_PREREG_2026-10-26.md`.
- **Trigger evidence**: `docs/closure/M7_BOUNDED_PACKET_2026-10-26.md`.
- **Run id**: `m7-gf-fallback-20261026`.
- **Runtime**: `QXFX0_RUNTIME_MODE=strict`, `QXFX0_EVAL_SESSION_MODE=isolated`,
  GHC 9.6.7, substrate active.
- **Scope**: 30 Russian definition prompts from
  `spec/gf/release_corpus_prompts.txt`; expected family `CMDefine`.
- **Command**:
  `QXFX0_RUNTIME_MODE=strict QXFX0_EVAL_SESSION_MODE=isolated bash scripts/run_dialogue_eval_200.sh m7-gf-fallback-20261026 <tsv>`
- **Artifacts** (gitignored): `reports/eval_runs/m7-gf-fallback-20261026/`
  (`summary.json`, `results.jsonl`, `raw/`, `surface_match_fallback.json`).
- **Recorded**: 2026-10-28, from the 2026-10-26 run.

## Headline result

| metric | pre-fix | post-fix | expectation | verdict |
|---|---:|---:|---:|---|
| total prompts | 30 | 30 | 30 | PASS |
| routing family `CMDefine` | 30/30 | 30/30 | 30/30 | PASS |
| trace `AuthorityCanonical` | 16/30 | **30/30** | 30/30 | **PASS** |
| trace `AuthorityShim` | 14/30 | **0/30** | 0/30 | **PASS** |
| `unmapped_curated_predicate` | 14/30 | **0/30** | 0/30 | **PASS** |
| `trcLinearizationOk = true` | n/a | **30/30** | 30/30 | **PASS** |
| `trcFallbackReason = null` | n/a | **30/30** | 30/30 | **PASS** |
| `DeriveGfMappedFallback` derivations | 0 | 14 | only where needed | PASS |
| exact golden surface | 4/30 | **5/30** | 30/30 | **FAIL (content acceptance)** |
| runtime/parse errors | 0 | 0 | 0 | PASS |
| morphology defects (script markers) | 0 | 0 | 0 | PASS |
| fallback/template drift (script markers) | 0 | 0 | <= 0.05 | PASS (instrumentation caveat below) |

The mapped-predicate fallback closes the hard GF mapping failure: every turn
now linearizes through the canonical GF path. It does **not** close M7: the
exact golden surface remains 5/30, and the remaining divergence is content
selection/structure, not a mapping shim.

## What changed in the trace

Across the 30 isolated turns:

- `trcAuthorityClass`: `AuthorityCanonical` 30/30;
- `trcLinearizationOk`: `true` 30/30;
- `trcFallbackReason`: `null` 30/30;
- `trcContentSource`: `covered_exact` 30/30 (still not sufficient evidence on
  its own — the trace authority is the authoritative signal);
- `trcResponseSurfaceKind`: `SurfaceAuthoritative` 30/30;
- derivation rules: `DeriveSelectedPredicate` 30,
  `DeriveGfMappedFallback` 14, `DeriveContrast` 6,
  `DeriveQualification` 4, `DeriveQuestion` 30.

The 14 fallback turns are exactly the pre-fix `unmapped_curated_predicate`
topics:

| # | prompt | rejected original predicate | mapped replacement (selected) |
|---:|---|---|---|
| gf-rel-007 | что такое воспоминание? | воспоминание восстанавливает прошлое в настоящем | воспоминание есть акт обращения к личному прошлому |
| gf-rel-008 | что такое сознание? | сознание есть основание субъектности | сознание объединяет восприятие и рефлексию |
| gf-rel-013 | что такое доверие? | доверие открывает возможность сотрудничества | доверие предполагает уязвимость перед другим |
| gf-rel-016 | что такое справедливость? | справедливость требует равенства возможностей | справедливость требует соразмерности между деянием и воздаянием |
| gf-rel-017 | что такое время? | время устанавливает границы между прошлим и будущим | время задаёт порядок следования событий |
| gf-rel-020 | что такое история? | история складывается из событий и их интерпретации | история связывает прошлое с настоящим через интерпретацию |
| gf-rel-021 | что такое язык? | язык выражает и структурирует мысль | язык структурирует опыт через различение и именование |
| gf-rel-023 | что такое смерть? | смерть выражает конечность бытия | смерть обозначает необратимое прекращение существования |
| gf-rel-024 | что такое одиночество? | одиночество обнаруживает границу между я и другими | одиночество выражает отсутствие значимого другого |
| gf-rel-025 | что такое любовь? | любовь преодолевает границу между я и другим | любовь направлена на конкретного другого как на безусловно ценного |
| gf-rel-026 | что такое труд? | труд выражает целенаправленное усилие | труд преобразует материал через целенаправленное усилие |
| gf-rel-027 | что такое покой? | покой выражает отсутствие напряжения | покой обозначает отсутствие движения и напряжения |
| gf-rel-028 | что такое власть? | власть это способность и возможность влиять на поведение людей | власть требует легитимности для устойчивости |
| gf-rel-030 | что такое молчание? | молчание выражает позицию через отсутствие слов | молчание может быть актом отказа или знаком присутствия |

`gf-rel-016` is the only fallback turn that also matches the golden surface
exactly: the mapped replacement is the golden predicate and the plan carries
the golden counterpoint/consequence. The other 13 fallback turns are canonical
but choose a different mapped predicate or omit golden sections.

## Exact golden surface — 5/30

Matches: `gf-rel-001` (свобода), `gf-rel-005` (мнение), `gf-rel-010` (вера),
`gf-rel-012` (долг), `gf-rel-016` (справедливость). The pre-fix packet matched
4/30; `gf-rel-016` was added by the fallback.

The other 25 turns are **not** mapping failures. They split into:

- **24/25** are thesis + check only, missing the golden
  `Контрпункт`/`Следствие` sections and often selecting a different top-1
  predicate (e.g. `gf-rel-004` истина, `gf-rel-006` память, `gf-rel-013`
  доверие);
- **1/25** (`gf-rel-003`, ответственность) carries counterpoint and
  consequence but selects a different full definition than the golden.

This is the unresolved content-acceptance question from the pre-fix packet:
Field-driven per-predicate top-1 selection is allowed to choose a different
predicate than the golden file. Exact-surface replay therefore cannot be used
as the only M7 acceptance rule without a documented re-baseline or a
semantic-predicate match rule. **No golden re-baseline was performed.**

## Grammar-quality caveat — one exposed GF case defect

`gf-rel-007` renders:

```text
Тезис: воспоминание есть актом обращения к личному прошлому. Проверка: верно ли это?
```

The trace predicate is nominative (`воспоминание есть акт обращения к личному
прошлому`), and `spec/gf/curated_predicate_slots.tsv:17` also records the
nominative surface. The instrumental form comes from the GF concrete syntax:
`spec/gf/QxFx0SyntaxRus.gf:163` hardcodes
`ObjectAktObrashcheniya = { s = "актом обращения к личному прошлому" }`.
This is a **pre-existing GF linearization/case defect**, exposed (not caused)
by the fallback selecting that already-mapped predicate. It was not fixed in
this slice because the pre-registration explicitly excludes GF grammar
changes. Follow-up: correct the concrete-syntax case and re-run the packet;
do not change the TSV to match the defective surface.

No other surface in this packet shows the `есть <instrumental>` pattern.

## Latency

The eval harness reports per-prompt end-to-end latency with isolated session
bootstrap: average `83,191.7 ms`, median `82,568.5 ms`, max `119,617 ms`
(30 prompts). This is **not** a warm-turn latency measurement and is far
above the audit's `10,000 ms` warm p95 threshold. Isolated bootstrap and
render cost dominate; latency remains an open performance item, not part of
this fallback slice.

## Gate-instrumentation caveat

`summary.json` reports `fallback_drift_rate=0.000`,
`critical_mismatch_rate=0.000`, and `morphology_defect_count=0`. Those
counters were blind to `AuthorityShim` in the pre-fix run and remain
insufficient as content evidence. For this packet the authoritative signals
are the replay trace (`trcAuthorityClass`, `trcLinearizationOk`,
`trcFallbackReason`) and the golden comparison in
`surface_match_fallback.json`.

## Verification

- `Test.Suite.ResponsePlan` targeted: **38/38 green**, including
  mapped-fallback selection, no-mapping retention, JSON round-trip, and GF
  addressability.
- Full unit suite on the new code: **1820/1820 green**.
- Fallback-tree re-verification (2026-10-28): fast **1918/1918**, property
  **244/244**, integration **47/47**, main core **1254/1254** — all exit 0;
  main runtime/http and slow not re-run. Matrix recorded in
  `docs/closure/CALIBRATION_REPORT.md`.

## What this packet proves

- The mapped-predicate fallback removes the `unmapped_curated_predicate` shim
  class on the 30 official definition prompts: `AuthorityCanonical` 30/30,
  `AuthorityShim` 0/30, `trcLinearizationOk=true` 30/30.
- The fallback is visible and auditable in `rspDerivation`; it does not
  silently rewrite the selected predicate.
- The remaining exact-golden gap is content selection/structure, not GF
  mapping coverage.

## What this packet does not prove

- It does **not** close M7. M7 remains OPEN until the content-acceptance rule
  is decided and the grammar caveat is resolved.
- It is **not** the 500-prompt dialogue release gate. The labeled 500-prompt
  Russian set is still absent; the script's fallback remains the ~60-prompt
  English baseline.
- It does not prove warm-turn latency, production traffic behavior, or
  challenge/repair coverage.

## Recommended next steps

1. Decide the golden acceptance rule for the 25 non-exact canonical turns:
   exact-surface, semantic-predicate match, or a documented re-baseline.
2. Fix the `ObjectAktObrashcheniya` case in `QxFx0SyntaxRus.gf` under a
   separate pre-registration, then re-run this packet.
3. Keep M7 OPEN and the 500-prompt gate BLOCKED until both are resolved.
