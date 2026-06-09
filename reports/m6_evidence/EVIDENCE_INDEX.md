# M6 Evidence Index

Status: Complete (2026-06-08)
Purpose: index of all evidence artifacts supporting the M6 bounded declaration.

## C1 — Continuity and coherence

| # | Evidence | Location | Verification |
|---|----------|----------|--------------|
| 1 | 6 canonical contours P4 OK | `CONTOUR_INDEX.md` rev.2 | `check_replay_gate.sh` |
| 2 | `trcConatusEnergy` in TurnReplayTrace | `src/QxFx0/Types/TurnProjection.hs:192` | `check_replay_gate.sh` |
| 3 | `trcField` in TurnReplayTrace | `src/QxFx0/Types/TurnProjection.hs:200` | `check_replay_gate.sh` |
| 4 | `trcSalienceDriver` in TurnReplayTrace | `src/QxFx0/Types/TurnProjection.hs` | `check_replay_gate.sh` |
| 5 | `trcEssenceMode` in TurnReplayTrace | `src/QxFx0/Types/TurnProjection.hs` | `check_replay_gate.sh` |
| 6 | `trcIdentityClaims` in TurnReplayTrace | `src/QxFx0/Types/TurnProjection.hs:204` | `check_replay_gate.sh` |
| 7 | C1 test passes | `test/Test/Suite/M6Witness.hs` | `cabal test qxfx0-test-fast` |

## C2 — Restart integrity

| # | Evidence | Location | Verification |
|---|----------|----------|--------------|
| 1 | `demoteNonAuthoritativeRestartCarry` fires on non-auth restart | `src/QxFx0/Bridge/StatePersistence.hs:386` | `Test.Suite.StatePersistence` |
| 2 | `trcRegimeVersion` in TurnReplayTrace | `src/QxFx0/Types/TurnProjection.hs` | `check_replay_gate.sh` |
| 3 | `trcFamilyDivergenceActive` in TurnReplayTrace | `src/QxFx0/Types/TurnProjection.hs` | `check_replay_gate.sh` |
| 4 | `ssCurrentRegime` in SystemState | `src/QxFx0/Types/State/System.hs` | `Test.Suite.M5Regime` |
| 5 | Bootstrap phases classified | `docs/results/SR-04.md` | Result record |
| 6 | M5Regime integration tests | `test/Test/Suite/M5Regime.hs` | `cabal test qxfx0-test-fast` |
| 7 | C2 test passes | `test/Test/Suite/M6Witness.hs` | `cabal test qxfx0-test-fast` |

## C3 — Commitment accountability

| # | Evidence | Location | Verification |
|---|----------|----------|--------------|
| 1 | `SemanticCommitmentStore` type | `src/QxFx0/Types/State/SemanticCommitment.hs` | Compile check |
| 2 | `ssSemanticCommitments` in SystemState | `src/QxFx0/Types/State/System.hs` | Compile check |
| 3 | `trcSemanticCommitmentCount` in TurnReplayTrace | `src/QxFx0/Types/TurnProjection.hs` | `check_replay_gate.sh` |
| 4 | `commit`/`revise`/`retract`/`contradict` ops | `src/QxFx0/Types/State/SemanticCommitment.hs` | `Test.Suite.SemanticCommitmentCorpus` |
| 5 | Anchor-to-commitment bridge (`anchorToFactualClaim`) | `src/QxFx0/Core/TurnPipeline/Finalize/State.hs` | `Test.Suite.SemanticCommitmentCorpus` |
| 6 | Multi-turn corpus fixture | `test/Test/Suite/SemanticCommitmentCorpus.hs` | `cabal test qxfx0-test-fast` |
| 7 | C3 test passes | `test/Test/Suite/M6Witness.hs` | `cabal test qxfx0-test-fast` |
| 8 | CTS-42 truth-contract admission of commitments (`trcCommitmentStoreDecision`) | `src/QxFx0/Core/CommitmentStoreAdmission.hs` | `Test.Suite.CommitmentStoreAdmission` |
| 9 | CTS-43 quarantine of non-authoritative claims (`trcQuarantinedCommitmentCount`) | `src/QxFx0/Semantic/Commitment.hs` | `Test.Suite.CommitmentQuarantine` |
| 10 | CTS-44 promotion on re-establishment (`LineagePromoted`, `trcPromotedFromQuarantineCount`) | `src/QxFx0/Semantic/Commitment.hs` | `Test.Suite.CommitmentPromotion` |

## C4 — Bidirectional semantic participation

| # | Evidence | Location | Verification |
|---|----------|----------|--------------|
| 1 | GF dual-surface: 5 topics × 3 languages | `docs/results/GF-E1b.md` | Result record |
| 2 | CTS-01 through CTS-40 admission chain | `docs/results/CTS-*.md` | `Test.Suite.M6Witness` |
| 3 | `familyDivergenceEnabled = True` | `src/QxFx0/Core/TurnRouting/Cascade.hs:74`, `ADR-0019` | `Test.Suite.M5Regime` |
| 4 | C4 GF topic coverage test | `test/Test/Suite/M6Witness.hs` | `cabal test qxfx0-test-fast` |
| 5 | C4 CTS admission chain test | `test/Test/Suite/M6Witness.hs` | `cabal test qxfx0-test-fast` |

## Build/CI verification

| Evidence | Command | Status |
|----------|---------|--------|
| Build clean | `cabal build all` (343 modules, 0 errors) | ✅ |
| Fast tests | `cabal test qxfx0-test-fast` (956/956 pass baseline) | ✅ |
| Architecture check | `bash scripts/check_architecture.sh` (20/20 rules) | ✅ |
| Replay gate | `bash scripts/check_replay_gate.sh` (0 failures, 6 contours P4) | ✅ |
| GF quality gate | `bash scripts/gf_quality_gate.sh` (0 errors, 0 warnings) | ✅ |

## References

- M6 declaration: `docs/closure/M6_DECLARATION.md`
- M6 claim package: `docs/closure/M6_CLAIM_PACKAGE.md`
- Precedent evidence index: `reports/baseline_v2/final_gates/CANONICAL_EVIDENCE_INDEX.md`
