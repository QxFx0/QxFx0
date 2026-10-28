# Pre-registration — GF recollection nominative-case fix (2026-10-28)

- **Status**: PRE-REGISTERED; implementation and verification recorded below.
- **Trigger evidence**:
  `docs/closure/M7_GF_MAPPING_FALLBACK_RESULT_2026-10-26.md`
  (grammar-quality caveat) and the mapped-predicate fallback packet
  `m7-gf-fallback-20261026`.
- **Scope**: one curated predicate slot and one GF concrete-syntax literal.
  No runtime logic, routing, safety, crisis, morphology, or eval change.
- **Owner decision**: fix the case defect under a separate pre-registration
  (not inside the fallback slice), 2026-10-28.

## Problem

`gf-rel-007` ("что такое воспоминание?") renders:

```text
Тезис: воспоминание есть актом обращения к личному прошлому. Проверка: верно ли это?
```

The nominative form is expected after `есть`. Root cause is a two-place
inconsistency, not a single GF typo:

- `spec/gf/curated_predicate_slots.tsv` row `recollection_past` has
  `source_ru = "воспоминание есть акт обращения к личному прошлому"`
  (nominative) but `object_ru = "актом обращения к личному прошлому"`
  (instrumental);
- `spec/gf/QxFx0SyntaxRus.gf:163` defines
  `ObjectAktObrashcheniya = { s = "актом обращения к личному прошлому" }`,
  i.e. it follows the inconsistent `object_ru` column;
- `src/QxFx0/Lexicon/Generated/SemanticSlots.hs` only carries constructor
  names, so the generated lookup is unaffected by the text fix.

Audit of all 84 curated rows: `recollection_past` is the **only** row where
`source_ru` differs from `subject_ru + relation_ru + object_ru`. No other
object literal needs a case change in this slice.

## Proposed change

1. `spec/gf/curated_predicate_slots.tsv`: set the `recollection_past`
   `object_ru` to `акт обращения к личному прошлому` (nominative). Keep
   `source_ru` unchanged.
2. `spec/gf/QxFx0SyntaxRus.gf`: set `ObjectAktObrashcheniya` to
   `"акт обращения к личному прошлому"`.
3. Regenerate the tracked PGF (`spec/gf/QxFx0Syntax.pgf`) and its manifest
   with `scripts/compile_gf_grammar.sh`; the PGF is the runtime grammar and
   must not stay stale.
4. Do **not** regenerate `SemanticSlots.hs` content by hand; run
   `scripts/export_lexicon.py --check` to prove the generated artifacts are
   still consistent (constructor names unchanged).

## Acceptance

- `python3 scripts/check_gf_concrete_consistency.py` passes.
- `bash scripts/check_generated_artifacts.sh` passes (includes
  `export_lexicon.py --check` and a GF recompile).
- New unit pin in `Test.Suite.ResponsePlan`: a plan whose claim is
  `воспоминание есть акт обращения к личному прошлому` linearizes through the
  compiled PGF to a surface containing `есть акт обращения к личному
  прошлому` and **not** `актом обращения`.
- Targeted `Test.Suite.ResponsePlan` green.
- Isolated `gf-rel-007` smoke: `AuthorityCanonical`,
  `trcFallbackReason=null`, surface contains the nominative form.
- The 30-prompt packet is **not** re-run in this slice; it remains an M7
  follow-up after the golden acceptance rule is decided.

## Non-goals

- No change to `source_ru` (persisted plan surfaces and the curated lookup key
  must stay stable).
- No new GF constructors or slots; no lexicon expansion.
- No change to the mapped-predicate fallback or `DeriveGfMappedFallback`.
- No golden re-baseline.
- No claim that M7 is closed.

## Risks and rollback

- The PGF is a tracked binary artifact; the commit must include the
  regenerated PGF and manifest, otherwise the runtime keeps the old surface.
- If any other predicate unexpectedly shares the constructor (none does
  today), its surface would change too; the audit above bounds the blast
  radius to one slot.
- Rollback is a revert of the TSV row, GF literal, PGF/manifest, and the new
  test.

## Implementation and verification (2026-10-28)

Implemented exactly as scoped:

- `spec/gf/curated_predicate_slots.tsv` `recollection_past`:
  `object_ru` → `акт обращения к личному прошлому`; `source_ru` unchanged.
- `spec/gf/QxFx0SyntaxRus.gf:163`:
  `ObjectAktObrashcheniya = { s = "акт обращения к личному прошлому" }`.
- `spec/gf/QxFx0Syntax.pgf` + `.manifest` recompiled with
  `scripts/compile_gf_grammar.sh` (exit 0; PGF sha256
  `35de64e4468f1e8c94c0be8a9f5ec119ad806cc23d424e49d771a7f7dc4bae2a`,
  toolchain `gf2`).
- New unit pin `testGfRecollectionNominativeCase` in
  `Test.Suite.ResponsePlan`.

Verification:

| check | result |
|---|---|
| TSV internal consistency (`source_ru == subject+relation+object`) | 84/84 rows consistent (was 83/84) |
| targeted `Test.Suite.ResponsePlan` | **39/39 green** |
| `cabal run qxfx0-main -- --check-embedded-sql` | exit 0 |
| `python3 scripts/export_lexicon.py --check --min-score 8.0` | exit 0 |
| `python3 scripts/check_input_lexicon.py` + provenance markers | exit 0 |
| isolated `gf-rel-007` smoke (strict, isolated) | `AuthorityCanonical`, `trcLinearizationOk=true`, `trcFallbackReason=null`; surface `Тезис: воспоминание есть акт обращения к личному прошлому. Проверка: верно ли это?` |
| full unit suite | **1821/1821 green** (`qxfx0-test-unit`, `-M6G`, exit 0; was 1820 before the new pin) |

`bash scripts/check_generated_artifacts.sh` does **not** pass end-to-end, but
the failure is pre-existing and unrelated: step 5
(`scripts/check_gf_concrete_consistency.py`) reports `QxFx0SyntaxEng.gf` and
`QxFx0SyntaxRusColloquial.gf` as missing almost every abstract constructor
(including `ObjectAktObrashcheniya` at `HEAD`) because those files use a
partial `lin` layout. Steps 1–4 (including the PGF recompile) and 4b–4d pass.
The Russian concrete, which this slice touched, is consistent. The
Eng/Colloquial alignment remains separate debt; the acceptance item above is
amended accordingly rather than silently dropped.
