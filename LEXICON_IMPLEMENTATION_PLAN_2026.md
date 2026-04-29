# QxFx0 Lexicon Implementation Plan 2026

## Goal
Extract Russian lexical data from hardcoded Haskell into a SQL/GF/Agda pipeline, making the system multilingual-ready without rewriting Core.

## Canonical Direction
SQL (source of truth) → GF (generation) → normalized artifact → Haskell runtime

## Package Summary

| Pkg | Status | Description |
|---|---|---|
| P0 | DONE | Baseline: plan doc, golden fixtures, lexical test harness |
| P1 | DONE | Language-neutral model: `Lexicon/Types.hs`, `Lexicon/Loader.hs` |
| P2 | PARTIAL | SQL lexicon base: schema + seed (needs `lex_languages`, `lex_templates`, etc.) |
| P3 | DONE | GF layer: `QxFx0Lexicon.gf`, `QxFx0LexiconRus.gf` |
| P4 | DONE | Export pipeline: `export_lexicon.py`, `build_lexicon.sh`, `check_lexicon.sh`, `resources/lexicon/ru.lexicon.json` |
| P5 | PARTIAL | Haskell adapters: `Lexicon/Runtime.hs`, `Analyze.hs` are live; `Realize.hs` and full runtime cutover remain |
| P6 | PARTIAL | Agda contract: `LexiconData.agda`, `LexiconProof.agda`, `LexiconContract.agda` exist; proof contour still needs consolidation |
| P7 | PARTIAL | Lexicon gate is live in `verify.sh` and `release-smoke.sh`; CI workflow unification remains |
| P8 | TODO | Multilingual-ready cleanup: `language_code` in SQL, neutral ids |

## Rules
- No Core contract changes. Replace lexical backend, not turn pipeline.
- GF is NOT a runtime dependency. GF + SQL work as build/export contour.
- Agda proves lexical contract, not "Russian beauty".
- After each package: `cabal test qxfx0-test`, `bash scripts/check_architecture.sh`, `bash scripts/check_lexicon.sh`.

## Definition of Done
- RU lexical contour lives outside hardcoded Haskell
- GF and SQL serve as raw base and generation; Agda proves lexical contract
- Runtime uses exported lexical artifact
- Architectural blast radius limited to lexical vertical slice
- English added as new language pack, not as new project
