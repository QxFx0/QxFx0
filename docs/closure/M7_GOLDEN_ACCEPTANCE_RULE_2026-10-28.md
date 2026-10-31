# M7 golden acceptance rule — PRE-REGISTERED (2026-10-28)

- **Status**: **PRE-REGISTERED.** Decisions D1–D4 signed by the owner on
  2026-10-28; admissible sets frozen in
  `spec/gf/m7_admissible_predicates.tsv`
  (sha256 `ef75231d65b1bf4bae20a55c93721c034dd020e2a6da66654848a34945033766`,
  45 data rows = 30 golden + 15 approved alternatives).
- **This document is not itself evidence that M7 passed.** M7 is accepted only
  if the confirmatory run below satisfies every gate.
- **Trigger evidence**: `docs/closure/M7_GF_MAPPING_FALLBACK_RESULT_2026-10-26.md`
  (canonical 30/30, shim 0/30, exact golden 5/30); reproduced on
  `bcceee6` as run `m7-gf-case-20261028` with identical metrics and the same
  15 mismatch ids.
- **Scope**: acceptance semantics for the bounded 30-prompt GF release
  corpus. It does not change runtime behavior, the golden file, or the
  500-prompt gate.

## Why a rule is needed

The post-fix packet is canonical on every turn, but only 5/30 surfaces match
the golden file exactly. Two independent questions are currently conflated:

1. **Structure** — the golden file uses a four-section template
   (thesis, counterpoint, consequence, check); the runtime usually emits
   thesis + check.
2. **Predicate selection** — the runtime is allowed to select a different
   curated predicate for the same topic than the one recorded in the golden.

Exact-surface replay therefore cannot serve as the only M7 rule without
either a documented re-baseline or an explicit semantic rule. This rule
takes the latter path.

## Descriptive evidence from the committed fallback packet

Source: run `m7-gf-case-20261028` on `bcceee6` (GF case fix + eval trace
instrumentation), 30 isolated strict turns, exit 0.

The same packet was run earlier as `m7-gf-fallback-20261026` on `2144a6a`.
Both runs reproduce the metrics below and the same 15 mismatch ids, so the
GF case fix changed surface grammar only (see the reproducibility note at the
end of this section).

| metric | value |
|---|---:|
| exact golden surface | 5/30 |
| runtime `AuthorityCanonical` | 30/30 |
| runtime `AuthorityShim` | 0/30 |
| runtime has `Тезис:` + `Проверка:` | 30/30 |
| runtime has `Контрпункт:` + `Следствие:` | 6/30 |
| golden has `Контрпункт:` | 30/30 |
| golden has `Следствие:` | 9/30 |
| semantic predicate equals the golden thesis | **15/30** |
| runtime predicate is a GF-mapped curated slot | 30/30 |

Of the 25 non-exact turns, **24 are thesis + check only**; `gf-rel-003` has
counterpoint + consequence but a different predicate.

The 15 semantic mismatches split into:

- **9 fallback substitutions** (`DeriveGfMappedFallback`);
- **6 Field-selected alternatives** from the curated corpus (no fallback).

The 14 fallback derivations in the packet therefore include 5 turns whose
mapped predicate happens to equal the golden predicate. The fallback content
review remains a 14-row task; the semantic-gate review is a 15-row task.

**Reproducibility note.** `m7-gf-case-20261028` (HEAD `bcceee6`) and
`m7-gf-fallback-20261026` (HEAD `2144a6a`) agree on every metric above and on
the exact set of 15 mismatch ids. The only observed difference is surface
grammar: `gf-rel-007` now renders the nominative form
(«воспоминание есть акт обращения к личному прошлому») instead of the
oblique case. Because the golden row for that prompt also expects a
counterpoint and a consequence, the fix does not raise the exact-surface
count — it remains 5/30.

## The rule (signed 2026-10-28)

### Tier 1 — structural gate (blocking)

For every prompt in the packet:

- `trcAuthorityClass == "AuthorityCanonical"`;
- `trcLinearizationOk == true`;
- `trcFallbackReason == null`;
- `AuthorityShim == 0`;
- the surface contains a thesis and a check (`Тезис:` + `Проверка:`);
- no template/fallback markers from the eval harness.

**Decision D1 — structural minimum. Signed: D1-A (thesis + check).**
The minimum is **thesis + check**, not the golden's four-section template.
Rationale: the discourse planner emits a counterpoint only when a contrast
candidate exists (`DeriveContrast`); forcing one on every turn would produce
filler, which is worse than an honest shorter answer. This is a deliberate
relaxation of the golden template, approved explicitly.

- **D1-A (signed)**: thesis + check. Descriptive pass: 30/30.
- **D1-B (rejected)**: thesis + counterpoint + check. Descriptive pass: 6/30.
- **D1-C (rejected)**: full four-section template. Descriptive pass: ~5/30.

### Tier 2 — semantic gate (blocking)

For every prompt, the emitted predicate (from
`trcResponsePlan.rspPropositions`, normalized) must belong to a
**pre-registered admissible set** for that topic.

**Decision D2 — semantic rule. Signed: D2-A (owner-approved admissible
sets).**

- **D2-A (signed)**: owner-approved admissible sets. The set starts with
  the golden predicate and may add curated, GF-mapped alternatives after
  content review. Each addition carries provenance and an approver.
- **D2-B (rejected)**: any GF-mapped curated predicate for the topic.
  Descriptive pass: 30/30, but the gate becomes tautological with the fallback
  and cannot catch a weak selection.
- **D2-C (rejected)**: documented golden re-baseline to the Field-selected
  predicates. Would be 30/30, but the golden stops functioning as a
  content-regression signal.

**Decision D3 — threshold. Signed: 30/30 semantic** for this bounded,
curated packet. No exceptions were pre-declared, so any single miss fails the
gate.

### Tier 3 — informational (non-blocking)

- exact-surface match count;
- latency (bootstrap and warm reported separately);
- grammar-quality flags.

**Decision D4 — signed: exact-surface remains informational.** It is reported
on every run but never blocks M7.

## Admissible sets (frozen 2026-10-28)

Frozen file: `spec/gf/m7_admissible_predicates.tsv`
(sha256 `ef75231d65b1bf4bae20a55c93721c034dd020e2a6da66654848a34945033766`).

Columns: `id`, `topic`, `admissible_predicate`, `provenance`, `approver`,
`date`. Construction rules applied:

1. Every one of the 30 topics starts with its golden predicate
   (`provenance = golden`).
2. Exactly one alternative was added per mismatching topic — the predicate the
   runtime actually emitted in the descriptive run — for the 15 mismatches in
   the appendix. Provenance is `curated-approved` (6 rows, no fallback
   involved) or `fallback-approved` (9 rows, `DeriveGfMappedFallback`).
3. Every added alternative is a curated predicate of the same topic and is
   present in `curated_predicate_slots.tsv` (GF-mapped); this was verified for
   all 30 emitted predicates, not only the 15.
4. No topic carries more than 2 admissible predicates (cap is 4).
5. The owner approved all 15 rows on 2026-10-28; `approver = owner`,
   `date = 2026-10-28` on every row.

The 14-row fallback content review tracked in the result document is a
separate, still-open task; it does not block this gate.

## Pre-registration record

Order of operations, as executed:

1. Owner signed D1–D4 and the 15 admissible rows on 2026-10-28.
2. This document and the frozen TSV were committed **before** the
   confirmatory run (commit recorded in the run report).
3. The TSV sha256 above is the one checked by the confirmatory checker; a
   mismatch aborts the run as invalid. Line endings are normalized to LF
   before hashing, so a CRLF checkout cannot invalidate the digest.
4. Confirmatory run (command frozen here):

   ```
   QXFX0_RUNTIME_MODE=strict QXFX0_EVAL_SESSION_MODE=isolated \
     bash scripts/run_dialogue_eval_200.sh m7-gf-confirm-20261031 \
     /tmp/opencode/m7-gf-case-30.tsv
   ```

   The 30-prompt packet file is derived mechanically from
   `spec/gf/release_corpus_prompts.txt` (`gf-rel-NNN` + prompt + `CMDefine`),
   in the same order.

5. Mechanical checker (no manual judgement during the run):
   - **Predicate extraction**: first leaf with tag `PropositionPredicate` in
     `trcResponsePlan.rspPropositions`, `contents` joined with single spaces.
   - **Normalization**: lowercase, delete `[.!?;:,]`, collapse whitespace,
     strip.
   - **Gate**: for each of the 30 ids, all of
     `trcAuthorityClass == "AuthorityCanonical"`,
     `trcLinearizationOk == true`,
     `trcFallbackReason == null`,
     `AuthorityShim == 0` (aggregate),
     surface contains `Тезис:` and `Проверка:`,
     no eval-harness fallback markers (`fallback_drift_count == 0`),
     and the normalized predicate ∈ admissible set for that id.
   - **Pass rule**: 30/30 ids satisfy the gate. No exceptions were
     pre-declared.
6. Any rule change after the run requires a new pre-registration. The
   descriptive packets (`m7-gf-fallback-20261026`, `m7-gf-case-20261028`)
   cannot serve as the confirmatory test because the rule was defined after
   seeing them.

## What the existing packet can and cannot prove

- **Can**: describe the baseline, identify the 15 semantic mismatches, and
  support construction of the admissible sets.
- **Cannot**: prove M7 acceptance. Applying a rule invented after the data is
  post-hoc; the confirmatory run must follow the frozen rule.

## Risks

- **Set inflation**: admissible sets can be widened until everything passes.
  Mitigation: provenance per row, max 4 per topic, owner sign-off, and a
  reported count of alternatives added.
- **Structural relaxation**: thesis + check can hide the loss of
  counterpoint/consequence. Mitigation: report `DeriveContrast` coverage and
  require a counterpoint whenever a contrast candidate exists.
- **Re-baseline**: removes the only content-regression signal; not
  recommended.

## Appendix — 15 semantic mismatches (descriptive, run `m7-gf-case-20261028`)

| id | golden predicate | runtime predicate | source |
|---|---|---|---|
| gf-rel-003 | ответственность — это необходимость отвечать за свои действия | ответственность требует осознания последствий | Field-selected |
| gf-rel-004 | истина претендует на соответствие реальности | истина проверяется доказательствами | Field-selected |
| gf-rel-006 | память это процесс запоминания хранения и воспроизведения информации | память сохраняет прошлое для настоящего | Field-selected |
| gf-rel-007 | воспоминание восстанавливает пережитое в новой рамке | воспоминание есть акт обращения к личному прошлому | fallback |
| gf-rel-008 | сознание это способность осознавать окружающий мир и самого себя | сознание объединяет восприятие и рефлексию | fallback |
| gf-rel-013 | доверие строится через повторяемый позитивный опыт | доверие предполагает уязвимость перед другим | fallback |
| gf-rel-014 | страх может парализовать действие или мобилизовать его | страх сигнализирует об угрозе целостности субъекта | Field-selected |
| gf-rel-017 | время необратимо — прошлое недоступно для изменения | время задаёт порядок следования событий | fallback |
| gf-rel-019 | бытие обозначает сам факт существования | бытие рассматривается как условие возможности любого суждения | Field-selected |
| gf-rel-020 | история зависит от точки зрения рассказчика | история связывает прошлое с настоящим через интерпретацию | fallback |
| gf-rel-021 | язык связан с мышлением — он не только выражает, но и формирует мысль | язык структурирует опыт через различение и именование | fallback |
| gf-rel-022 | воля направляет действие к выбранной цели | воля требует преодоления препятствий и конкурирующих мотивов | Field-selected |
| gf-rel-026 | труд связан с потребностью и распределением ресурсов | труд преобразует материал через целенаправленное усилие | fallback |
| gf-rel-028 | власть означает способность влиять на действия других | власть требует легитимности для устойчивости | fallback |
| gf-rel-030 | молчание контрастирует с речью, но не тождественно пустоте | молчание может быть актом отказа или знаком присутствия | fallback |

## Decisions (signed 2026-10-28)

| id | decision | signed choice |
|---|---|---|
| D1 | structural minimum | D1-A — thesis + check |
| D2 | semantic rule | D2-A — owner-approved admissible sets |
| D3 | semantic threshold | 30/30, no pre-declared exceptions |
| D4 | exact-surface role | informational only |

M7 stays **OPEN** until the confirmatory run satisfies every gate; the
500-prompt gate stays **BLOCKED** (no labeled corpus).
