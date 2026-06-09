# Execution Board

Status: Active
Purpose: authoritative source for what to do next.

## Update rule

- update frequently
- keep brutally current
- do not use this document for historical packet dumps or broad doctrine

## Current front

- `front_id`: `M6-DECLARE — write final bounded evidence declaration`
- `current_state`: **All M6 activation conditions met** (2026-06-03). H1+H2+H3+C1+C2+C3+C4 all closed. F-11 real GF parser implemented. 956/956 tests pass. Remaining: write the formal M6 declaration document and create the evidence index under `reports/m6_evidence/`.
- `last_updated`: `2026-06-03T04:00:00+03:00`
- `evidence_or_result_ref`: `docs/closure/M6_CLAIM_PACKAGE.md`

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

## Immediate next action

1. Write `docs/closure/M6_DECLARATION.md` — the formal bounded claim package
2. Create `reports/m6_evidence/` index with pointers to all evidence artifacts
3. Optional: run `bash scripts/check_replay_gate.sh` to confirm 0 failures

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
