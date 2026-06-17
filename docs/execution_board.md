# Execution Board

Status: Active
Purpose: authoritative source for what to do next.

## Update rule

- update frequently
- keep brutally current
- do not use this document for historical packet dumps or broad doctrine

## Current front

- `front_id`: `SLICE-010B — morphology resource contract (re-applied from 0219d0e)`
- `current_state`: SLICE-010B code (Morphology.hs, Paths.hs, LexiconTests, RuntimeInfrastructure) re-applied from `0219d0e` onto current `origin/main` (which includes B2/B3/SLICE-012). Morphology now derives from `paradigms.json` + `exceptions.json`; `forms_by_surface.json` is gitignored. Next: verify fast gate in intended env.
- `last_updated`: `2026-06-17`
- `evidence_or_result_ref`: `docs/closure/SLICE-010B_PLAN.md`, `audit-objective-2026-06-17.md`

## Immediate next action

- Verify `cabal test qxfx0-test-fast` in intended env (GHC 9.6.6 + GF runtime).
- Expected: morphology errors gone; GF issue not mixed if env configured.
- After SLICE-010B closes: M4 semantic-core deepening (Gates 1-2 first).
- M6-FELT remains NOT PROVEN.

## Completed this session (2026-06-17, second pass)

- **SLICE-012 governed evidence admissibility** — closed (commits `b12cafb` + `6755b0e` pushed to `origin/main`).
  - `EvidenceAdmissibility` type: `EvidenceGoverned` / `EvidenceDegradedGuardUnavailable` / `EvidenceInadmissible` (`src/QxFx0/Types/Evidence.hs`).
  - `QXFX0_GOVERNED_EVIDENCE=1` env var: governed-evidence mode fail-closes on Unavailable guard (`EvidenceInadmissibleFailure`); normal mode preserves fail-open degraded behavior.
  - Every `TurnReplayTrace` now carries `trcEvidenceAdmissibility`.
  - CI extended contract: `QXFX0_GOVERNED_EVIDENCE=1` + `QXFX0_CONCEPTS_PATH`; core contract explicitly disclaims governed evidence (nix not installed).
  - Docs: `ENV_CONTRACT.md`, `M6_DECLARATION.md` C1 evidence-admissibility row, `SLICE-012_PLAN.md`.
  - **Pre-existing morphology blocker**: fast gate 1124 cases, 8 errors + 2 failures all pre-existing (`Morphology resource_load MORPHOLOGY_ERROR` + `forms_by_surface.json` — SLICE-010B). 0 new failures from SLICE-012.
  - Status: **closed-with-pre-existing-morphology-blocker**. The morphology resource issue (SLICE-010B) blocks local fresh-runtime runs but does not affect SLICE-012's evidence-admissibility contract.

- **ESSENCE-REGIME-RECONCILE (Policy A)** — closed (commit `b12cafb` pushed).
  - Essence is law-driven (unconditional `shouldCommit`/`validatePlan`/`EssenceRupture` since 2026-05-19); `essenceCommitmentEnabled` flag was never implemented.
  - 19 docs + 1 discipline test reconciled; `Self.Essence` reclassified `canonical-flag-off` → `canonical`.
  - Essence = structural/runtime scaffold only, NOT M6-FELT evidence.

## Completed this session (2026-06-17, first pass)

- **SLICE-010B morphology resource contract** — closed on `slice-010b-morphology-contract` (commit `0219d0e`).
  - `src/QxFx0/Resources/Paths.hs`: morphology directory marker switched from `prepositional.json` to `paradigms.json` with `lexicon_quality.json` fallback for test-tree compatibility.
  - `src/QxFx0/Resources/Morphology.hs`: rewritten to load `paradigms.json` + `exceptions.json` and derive `MorphologyData` via `morphologyDataFromParadigms`. No cache; `clearFormsCache` kept as no-op.
  - `.gitignore`: `resources/morphology/forms_by_surface.json` now ignored; comment updated to SLICE-010B contract.
  - `test/Test/Suite/LexiconTests.hs`: removed `forms_by_surface.json` existence tests; added canonical artifact tests for `paradigms.json`/`exceptions.json` and a regression test for derived forms (`косе`, `выборов`, `любовь`, `коса`).
  - `test/Test/Suite/RuntimeInfrastructure.hs`: fake resource trees now create `paradigms.json`/`exceptions.json`; readiness-invalid and morphology-cache tests updated to exercise the new substrate.
  - Evidence: code reviewed; `git diff --name-only origin/main..HEAD` does not contain `forms_by_surface.json`; `git ls-tree -r HEAD resources/morphology/forms_by_surface.json` is empty; Python simulation over real `paradigms.json`/`exceptions.json` passes the regression examples.
  - Gate status: full `cabal test qxfx0-test-fast` NOT RUN due to environment blockers, not code defects:
    - GHC 9.6.7 / `base-4.18.3.0` locally vs `cabal.project.freeze` `base ==4.18.2.1` (intended CI is GHC 9.6.6).
    - Missing GF C runtime (`libpgf`, `libgu`) for `pgf2` — tracked by SLICE-012, out of scope for SLICE-010B.
  - If a CI/intended environment with GHC 9.6.6 + GF libs is available, the fast gate should run there. A separate future front (`SLICE-012` toolchain environment contract) is needed for any local toolchain migration.

- **SLICE-010B morphology resource contract** — closed on `slice-010b-morphology-contract`.
  - `src/QxFx0/Resources/Paths.hs`: morphology directory marker switched from `prepositional.json` to `paradigms.json` with `lexicon_quality.json` fallback for test-tree compatibility.
  - `src/QxFx0/Resources/Morphology.hs`: rewritten to load `paradigms.json` + `exceptions.json` and derive `MorphologyData` via `morphologyDataFromParadigms`. No cache; `clearFormsCache` kept as no-op.
  - `.gitignore`: `resources/morphology/forms_by_surface.json` now ignored; comment updated to SLICE-010B contract.
  - `test/Test/Suite/LexiconTests.hs`: removed `forms_by_surface.json` existence tests; added canonical artifact tests for `paradigms.json`/`exceptions.json` and a regression test for derived forms (`косе`, `выборов`, `любовь`, `коса`).
  - `test/Test/Suite/RuntimeInfrastructure.hs`: fake resource trees now create `paradigms.json`/`exceptions.json`; readiness-invalid and morphology-cache tests updated to exercise the new substrate.
  - Evidence: code reviewed; `git diff --name-only origin/main..HEAD` does not contain `forms_by_surface.json`; `git ls-tree -r HEAD resources/morphology/forms_by_surface.json` is empty; Python simulation over real `paradigms.json`/`exceptions.json` passes the regression examples.
  - Gate status: full `cabal test qxfx0-test-fast` NOT RUN due to environment blockers, not code defects:
    - GHC 9.6.7 / `base-4.18.3.0` locally vs `cabal.project.freeze` `base ==4.18.2.1` (intended CI is GHC 9.6.6).
    - Missing GF C runtime (`libpgf`, `libgu`) for `pgf2` — tracked by SLICE-012, out of scope for SLICE-010B.
  - If a CI/intended environment with GHC 9.6.6 + GF libs is available, the fast gate should run there. A separate future front (`SLICE-016` toolchain environment contract) is needed for any local toolchain migration.

- **Push to `origin/main`** — `62cf43a..c46ebb5` fast-forward pushed.
  - Removed `resources/morphology/forms_by_surface.json` (125 MB blob) from local history via `git filter-branch` before push; backup branch `backup/main-with-forms-blob-20260617` retained.
  - `git log origin/main..HEAD -- resources/morphology/forms_by_surface.json` empty; `git diff --name-only origin/main..HEAD` does not contain the file.

- **SLICE-014 runtime persistence residuals** — closed.
  - 40: switched `testBootstrapSessionCorruptStateFailsClosed` to `withStrictRuntimeEnv`; strict corrupt-state bootstrap now fails closed as expected.
  - 45: `Commit.hs` now emits `PERSISTENCE_CONFLICT` for `PdStateRevisionConflict`, restoring the stale-writer CAS contract.
  - 50/51: classified as documented feature gaps and moved to SLICE-015.
  - Result: `runtime` 93/93 tried with only 50/51 failures; `unit` unchanged at 1216/1217 with 1 pre-existing GF failure.

- **SLICE-013 truth-contract persistence/load policy (Option 1)** — landed on `main` via merge commit `1cc5752`.
  - Reconciled local `main` to `origin/main`, resolved `.gitattributes` merge conflict, and merged `slice-013-truthcontract-fix`.
  - Ran relevant gates: state 36/36 ✅, runtime 93/93 tried with 4 deferred failures (40/45/50/51), unit 1216/1217 with 1 pre-existing GF-compile failure.
  - Post-merge fix: normalized CRLF line endings in `testEmbeddedSqlMatchesCanonicalSpec` to keep runtime case 0 green.
  - Policy: "strict rejects corruption, not compatibility." Persistence cleanup never manufactures truth-contract authority.
  - Save path: `canonicalizePersistedState` preserves `ssTruthContractStatus` verbatim (removed unconditional `=AssembledSurfacePreserved`).
  - Load path: removed duplicate non-auth reject gate from `loadState`; non-auth state → `LoadStateRestored` (demoted), not `LoadStateCorrupt`.
  - Tests: 3 StatePersistence tests renamed+rewritten (Rejects/Recovers→Restores); RuntimeInfrastructure tests 17/25 rewritten with explicit auth fixture marker (symmetric to non-auth twins, breaking nix-capability dependency).
  - Doctrine: `docs/commit_restore_state_machine.md §6.3` updated.
  - Result: SLICE-013 closed; 4 deferred failures moved to SLICE-014.

## Completed this session (2026-06-16)

- **SLICE-011 infra/harness triage** — closed with separate commit on `slice-011`.
  - Scope: `.gitattributes`, LF rules, SQL/EmbeddedSQL sync, `.test-tmp` symlink, witness path, resource root, fake nix/souffle/gf-map isolation, CLI/Http option parsing, sidecar `executeFile`, sidecar SIGTERM/SIGKILL group cleanup, HTTP proxy bypass, runtime readiness probe timeout, slow-gate group split (`runtime`/`http`/`state`).
  - Evidence: 135 slow cases reached a clean final summary; 93/93 runtime, 22/22 http, 20/20 state.
  - Deferred: 11 persistence-behavior failures moved to `SLICE-013`.

## Completed this session (2026-06-03, full session)

- **C3 SemanticAnchor bridge** — `anchorToFactualClaim` in Finalize/State.hs: every turn that establishes a SemanticAnchor commits a typed `FactualClaimPayload` to `ssSemanticCommitments`
- **Test.Suite.SemanticCommitmentCorpus** — 4 tests: Turn1 commits, multi-turn accumulates, trace field matches store, 3-turn corpus ≥3 commitments
- **F-11 Real GF Haskell parser:**
  - `gfExprToClaimAst` in Runtime/PGF.hs — inverts astToGfExpr for all 24 Move* constructors + stance wrapping
  - `parseClaimAstGf` / `parseClaimAstGfLang` — uses PGF.parse on live `.pgf` grammar
  - `Render/Authority.hs` updated — GF path first, pattern-match fallback second; added `parseAuthoritySurfaceIO`, `claimAstToFactualClaim`, `parseAuthoritySurfacePattern`
  - `Semantic/AuthorityParse.hs` — production handle with cached PGF grammar
  - `Test.Suite.AuthoritySurface` — 24 gfExpr round-trip tests + 4 pattern tests + coverage ≥99% + negative corpus

**Total: 956/956 tests pass. M6 activation checklist: all ✅**

## Completed this session (2026-06-03, second pass)

- **Test.Suite.M5Regime** — 3 integration tests using real in-memory turn; `trcRegimeVersion > 0`, equals `currentMathVersion`, `trcFamilyDivergenceActive = True`. **H3 gate closed.**
- **trcSemanticCommitmentCount** added to TurnReplayTrace — C3 trace field, counts active `SemanticCommitmentStore` entries.
- **Test.Suite.M6Witness** updated — 9 tests (added `c4ClaimPackageExists`).
- **M6_CLAIM_PACKAGE.md** created — bounded final claim, evidence package structure, activation checklist, declaration template.
- **REGIME_GOVERNANCE.md** — `Test.Suite.M5Regime` checkbox closed.

## Current state of M6 activation gate

| Gate | Status |
|------|--------|
| H1 (SLICE-NA-001) | ✅ closed |
| H2 (deferred arch queue) | ✅ SR-03/04/05 classified |
| H3 (M5 governed regime) | ✅ M5Regime tests pass |
| C1 (continuity + 6 contours P4) | ✅ |
| C2 (restart integrity + regime markers) | ✅ |
| C3 (commitment accountability) | ✅ CTS-42 admission + CTS-43 quarantine + CTS-44 promotion |
| C4 (bidirectional semantic) | ✅ GF-E1b + CTS-40 + ADR-0019 |

**M6 declaration:** ready after C3 full completion.

## Active architecture queue

1. Keep CTS layer stable — no new proposition consumers without admission module
2. When math constants change → follow MATH_CHANGE_PROTOCOL.md
3. Legacy decode windows (SR-05) — monitor for retirement triggers

## Notes

- This file is the execution coordinator.
- Historical summaries belong in `docs/front_archive.md`.
- Program doctrine belongs in `ROADMAP.md`.
- Deferred architecture follow-ups stay in `ROADMAP.md` until a new bounded front is explicitly activated.
