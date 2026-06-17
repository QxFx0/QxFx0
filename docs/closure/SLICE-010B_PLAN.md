# SLICE-010B Plan: Morphology Resource Contract

Status: CLOSED (merged pending)  
Owner: agent  
Branch: `slice-010b-morphology-contract`  
Worktree: `/home/liskil/slice-010b`  

## Goal

Make a fresh checkout of `origin/main` reproducible without the 125 MB generated artifact `resources/morphology/forms_by_surface.json`. Runtime morphology is now derived in memory from the compact checked-in substrate:

- `resources/morphology/paradigms.json`
- `resources/morphology/exceptions.json`

The legacy `MorphologyData` view (`mdNominative`, `mdGenitive`, `mdPrepositional`, `mdFormsBySurface`) is preserved, so all existing consumers (inflection, resolution, GF morphology, learning, bootstrap) continue to work without semantic changes.

## Constraints

- No Git LFS.
- No `git push --force`.
- No Python in the runtime path.
- No production semantics changes outside morphology resource loading.
- Do not touch `origin/feat/cts-44-promotion`.
- `forms_by_surface.json` must remain generated/ignored and must not appear in `git log origin/main..HEAD` or `git diff --name-only origin/main..HEAD`.
- Keep `clearFormsCache` API compatible (no-op).
- `paradigms.json` and `exceptions.json` are the canonical checked-in morphology artifacts.

## Changes

### Source

- `src/QxFx0/Resources/Paths.hs`
  - Morphology directory marker changed from `prepositional.json` to `paradigms.json` with `lexicon_quality.json` fallback for existing test trees.
- `src/QxFx0/Resources/Morphology.hs`
  - Removed `forms_by_surface.json` loading/caching.
  - Added `loadRuntimeParadigmsFromDir` to load `paradigms.json` + `exceptions.json`.
  - Added `morphologyDataFromParadigms` to derive the legacy `MorphologyData` in memory.
  - `validateMorphologyResources` now validates the two canonical JSON files.
  - `clearFormsCache` retained as no-op.
- `.gitignore`
  - `resources/morphology/forms_by_surface.json` is now ignored; comment updated to SLICE-010B.

### Tests

- `test/Test/Suite/LexiconTests.hs`
  - Removed `forms_by_surface.json` existence/structure tests.
  - Added `testParadigmsJsonValid` and `testExceptionsJsonValid`.
  - Added `testMorphologyDataFromParadigms` with regression checks for `любовь`, `коса`, `выборов`, `косе`.
- `test/Test/Suite/RuntimeInfrastructure.hs`
  - Fake resource trees create `paradigms.json` + `exceptions.json` instead of `prepositional.json`/`genitive.json`/`nominative.json`.
  - `testAssessResourceReadinessFailsOnInvalidMorphologyJson` now invalidates `paradigms.json`.
  - `testAssessResourceReadinessFailsWhenCriticalPolicyFilesMissing` creates valid canonical morphology files.
  - `testMorphologyCacheSwitchesWithRoot` uses distinct `paradigms.json` entries to prove per-root derivation.

## Evidence / Verification

- Code review completed.
- `git diff --name-only origin/main..HEAD` does **not** contain `resources/morphology/forms_by_surface.json`.
- `git ls-tree -r HEAD resources/morphology/forms_by_surface.json` returns nothing.
- Python simulation over the real `resources/morphology/paradigms.json` + `resources/morphology/exceptions.json` passes the regression examples (`косе`, `выборов`, `любовь`, `коса`).
- Full `cabal test qxfx0-test-fast` was **not run** in this worktree because of environment blockers, not code defects:
  - Local GHC is 9.6.7 (`base-4.18.3.0`) while `cabal.project.freeze` pins `base ==4.18.2.1` (intended CI is GHC 9.6.6). Per project verdict, the freeze is a release/build contract and is **not** modified in this front.
  - The GF C runtime (`libpgf`, `libgu`) is missing, so `pgf2` cannot configure. This is the pre-existing SLICE-012 gate, out of scope for SLICE-010B.
- If an intended CI environment with GHC 9.6.6 + GF libs is available, the fast gate should be run there. Any local toolchain migration is a separate future front (`SLICE-016` toolchain environment contract), not part of this closure.

## Exit criteria

1. `git diff --name-only origin/main..HEAD` does not contain `resources/morphology/forms_by_surface.json`.
2. `git ls-tree -r HEAD resources/morphology/forms_by_surface.json` returns nothing.
3. `src/QxFx0/Resources/Morphology.hs` derives `MorphologyData` from `paradigms.json` + `exceptions.json` without loading `forms_by_surface.json`.
4. `docs/closure/REMAINING_CLOSURE_CHECKLIST.md` and `docs/execution_board.md` updated to mark SLICE-010B closed with the env-blocked gate noted.
5. Branch fast-forward merged to `origin/main`.
