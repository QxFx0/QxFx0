# Execution Board

Status: Active
Purpose: authoritative source for what to do next.

## Update rule

- update frequently
- keep brutally current
- do not use this document for historical packet dumps or broad doctrine

## Current front

- `front_id`: `SLICE-014 — runtime persistence residuals (40/45/50/51)`
- `current_state`: SLICE-013 landed on `main` via `1cc5752`. state 36/36 ✅, runtime 93/93 tried (4 pre-existing deferred: 40/45/50/51), unit 1216/1217 with 1 pre-existing GF-compile failure. CRLF mismatch in runtime schema fixture fixed post-merge. SLICE-014 opened for triage of the 4 deferred failures.
- `last_updated`: `2026-06-17`
- `evidence_or_result_ref`: `docs/closure/SLICE-014_PLAN.md`, `docs/closure/SLICE-013_PLAN.md`, gate logs `/home/liskil/slice013-merge-*.log`

## Immediate next action

1. Classify each of the 4 deferred failures as code regression vs known non-regression.
2. For regressions: identify a minimal fix that does not violate the SLICE-013 policy.
3. For non-regressions: decide whether to implement missing summary fields or defer.

## Completed this session (2026-06-17)

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
