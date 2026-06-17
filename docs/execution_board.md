# Execution Board

Status: Active
Purpose: authoritative source for what to do next.

## Update rule

- update frequently
- keep brutally current
- do not use this document for historical packet dumps or broad doctrine

## Current front

- `front_id`: `None — awaiting next approved front`
- `current_state`: SLICE-013/014 landed and pushed to `origin/main` (`62cf43a..c46ebb5`). `runtime` 93/93 tried with 2 known feature gaps (50/51). SLICE-015 is explicitly deferred; morphology resource contract (`forms_by_surface.json`) remains unresolved and belongs to SLICE-010B.
- `last_updated`: `2026-06-17`
- `evidence_or_result_ref`: `docs/closure/SLICE-014_PLAN.md`, `docs/closure/SLICE-015_PLAN.md`, gate log `/home/liskil/slice014-fix-runtime.log`

## Immediate next action

- No active front. Return to roadmap/public coherence only via a separate approved front.
- SLICE-015 remains a documented deferred feature gap; do not implement without a new approved front.

## Completed this session (2026-06-17)

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
