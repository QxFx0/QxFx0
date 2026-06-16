# M6 Evidence Index

Status: Reconciled 2026-06-16 (consistent with `docs/closure/M6_DECLARATION.md`)
Purpose: index of evidence artifacts supporting the M6 **bounded** declaration.

**Legend:** ✅ = real, in-repo public test/script targets this claim (publicly
falsifiable). ⏳ = *pending public evidence* — holds in code or a privately-held
record, but no public test/artifact yet. Test pass/fail is not asserted here.

> The 2026-06-03 index cited test functions (`M6Witness.c1CanonicalContourCoverage`,
> `c4GfTopicCoverage`, `c4CTSAdmissionChainComplete`) and `docs/results/*` records
> that are not in public commits. Those rows are repointed to real public suites or
> marked ⏳ below. `docs/results/` was **not** restored — privately-held records stay ⏳.

## C1 — Continuity and coherence — ✅ publicly evidenced

| # | Evidence | Location | Public check | Status |
|---|----------|----------|--------------|--------|
| 1 | Canonical contours carry trace fields | `CONTOUR_INDEX.md` | `scripts/check_replay_gate.sh` | ✅ |
| 2 | `trcConatusEnergy` in TurnReplayTrace | `src/QxFx0/Types/TurnProjection.hs:192` | `Test.Suite.TraceSchema` | ✅ |
| 3 | `trcField` in TurnReplayTrace | `src/QxFx0/Types/TurnProjection.hs:200` | `Test.Suite.TraceSchema` | ✅ |
| 4 | `trcSalienceDriver` in TurnReplayTrace | `src/QxFx0/Types/TurnProjection.hs` | `Test.Suite.TraceSchema` | ✅ |
| 5 | `trcEssenceMode` in TurnReplayTrace | `src/QxFx0/Types/TurnProjection.hs` | `Test.Suite.TraceSchema` | ✅ |
| 6 | `trcIdentityClaims` in TurnReplayTrace | `src/QxFx0/Types/TurnProjection.hs:204` | `Test.Suite.TraceSchema` | ✅ |
| 7 | Regime version stamped + matches current | `src/QxFx0/Types/RuntimeRegime.hs` | `Test.Suite.M5Regime` | ✅ |

## C2 — Restart integrity — ✅ core publicly evidenced

| # | Evidence | Location | Public check | Status |
|---|----------|----------|--------------|--------|
| 1 | Non-auth persisted state rejected at bootstrap | `src/QxFx0/Bridge/StatePersistence.hs` | `Test.Suite.StatePersistence.testBootstrapRejectsNonAuthoritativePersistedState` | ✅ |
| 2 | `trcRegimeVersion` in TurnReplayTrace | `src/QxFx0/Types/TurnProjection.hs` | `Test.Suite.M5Regime` | ✅ |
| 3 | `trcFamilyDivergenceActive` in TurnReplayTrace | `src/QxFx0/Types/TurnProjection.hs` | `Test.Suite.PromotionFlagDiscipline` | ✅ |
| 4 | `ssCurrentRegime` in SystemState | `src/QxFx0/Types/State/System.hs` | `Test.Suite.M5Regime` | ✅ |
| 5 | M5Regime integration tests | `test/Test/Suite/M5Regime.hs` | `cabal test qxfx0-test-fast` | ✅ |
| 6 | Bootstrap phases classified | SR-04 record (private) | result record | ⏳ pending |

## C3 — Commitment accountability — ✅ publicly evidenced

| # | Evidence | Location | Public check | Status |
|---|----------|----------|--------------|--------|
| 1 | `SemanticCommitmentStore` type | `src/QxFx0/Types/State/SemanticCommitment.hs` | compile + `Test.Suite.SemanticCommitmentCorpus` | ✅ |
| 2 | `ssSemanticCommitments` in SystemState | `src/QxFx0/Types/State/System.hs` | `Test.Suite.SemanticCommitmentCorpus` | ✅ |
| 3 | `trcSemanticCommitmentCount` in TurnReplayTrace | `src/QxFx0/Types/TurnProjection.hs` | `Test.Suite.SemanticCommitmentCorpus.c3TraceFieldMatchesStoreCount` | ✅ |
| 4 | `commit`/`revise`/`retract`/`contradict` ops | `src/QxFx0/Types/State/SemanticCommitment.hs` | `Test.Suite.SemanticCommitmentCorpus` | ✅ |
| 5 | Anchor-to-commitment bridge (`anchorToFactualClaim`) | `src/QxFx0/Core/TurnPipeline/Finalize/State.hs` | `Test.Suite.SemanticCommitmentCorpus` | ✅ |
| 6 | Multi-turn corpus fixture (3-turn ≥3 commitments) | `test/Test/Suite/SemanticCommitmentCorpus.hs` | `Test.Suite.SemanticCommitmentCorpus.c3ThreeTurnCorpusFixture` | ✅ |
| 7 | GF round-trip ≥99% + negative corpus | `src/QxFx0/Render/Authority.hs` | `Test.Suite.AuthoritySurface.coverageTest` / `.negativeCorpusTest` | ✅ |
| 8 | CTS-42 truth-contract admission (`trcCommitmentStoreDecision`) | `src/QxFx0/Core/CommitmentStoreAdmission.hs` | `Test.Suite.CommitmentStoreAdmission` | ✅ |
| 9 | CTS-43 quarantine (`trcQuarantinedCommitmentCount`) | `src/QxFx0/Semantic/Commitment.hs` | `Test.Suite.CommitmentQuarantine` | ✅ |
| 10 | CTS-44 promotion on re-establishment (`LineagePromoted`, `trcPromotedFromQuarantineCount`) | `src/QxFx0/Semantic/Commitment.hs` | `Test.Suite.CommitmentQuarantine` (`unitPromoteMatchingQuarantine`, `unitPromoteNormalizedMatch`, `unitPromoteNoMatch`, `unitPromoteEmptyQuarantine`) | ✅ |

## C4 — Bidirectional semantic participation — ✅ core publicly evidenced

| # | Evidence | Location | Public check | Status |
|---|----------|----------|--------------|--------|
| 1 | Bidirectional GF parser (24 round-trips) | `src/QxFx0/Runtime/PGF.hs`, `Semantic/Authority/GfExprParse.hs` | `Test.Suite.AuthoritySurface` | ✅ |
| 2 | GF round-trip coverage ≥99% | `src/QxFx0/Render/Authority.hs` | `Test.Suite.AuthoritySurface.coverageTest` | ✅ |
| 3 | `familyDivergenceEnabled = True` | `src/QxFx0/Core/TurnRouting/Cascade.hs:74`, ADR-0019 | `Test.Suite.M5Regime.m5FamilyDivergenceActiveIsStamped` | ✅ |
| 4 | GF dual-surface: 5 topics × 3 languages | GF-E1b record (private) | topic-matrix test (none) | ⏳ pending |
| 5 | CTS-01–40 admission chain (aggregate) | per-stage admission modules (live, wired) | aggregate record (private); per-stage suites public | ⏳ pending |

## Build/CI verification

Run to verify or falsify — pass/fail not asserted here (suites not re-run this revision):

| Evidence | Command | Public? |
|----------|---------|---------|
| Build | `cabal build all` | ✅ public |
| Fast tests | `cabal test qxfx0-test-fast` | ✅ public |
| Architecture check | `bash scripts/check_architecture.sh` | ✅ public |
| Replay gate | `bash scripts/check_replay_gate.sh` | ✅ public |
| GF quality gate | `bash scripts/gf_quality_gate.sh` | ✅ public |

## Pending public evidence (summary)

- C4 5-topic × 3-language public topic-matrix test
- Public status of SR-03/04/05, GF-E1b, and CTS-01–40 aggregate records (currently private)

## References

- M6 declaration: `docs/closure/M6_DECLARATION.md`
- M6 claim package: `docs/closure/M6_CLAIM_PACKAGE.md`
- Witness protocol: `docs/closure/M6_WITNESS_PROTOCOL.md`
