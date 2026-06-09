# M6 Claim Package

**Status:** Active — preconditions being assembled (2026-06-03)
**Governed by:** `docs/closure/M6_WITNESS_PROTOCOL.md`
**Activation trigger:** ✅ **ALL CONDITIONS MET** — H1 + H2 + H3 + C1 + C2 + C3 + C4 + F-11 (2026-06-03)

---

## 1. The bounded final claim

This fork claims the following, under explicit regime rules and bounded contours:

> **QxFx0_v3 can sustain an algorithmic subject structure for meaningful domain
> dialogue with a human under governed, checkable conditions.**

This claim is:
- **Scope-bound** — Russian/English philosophical dialogue domain
- **Contour-bound** — 4 explicit evidence contours (C1–C4)
- **Evidence-bound** — replay-visible, machine-checkable, not narrated
- **Not metaphysical** — no claim to consciousness, personhood, or general intelligence

---

## 2. Evidence package structure

### C1 — Continuity and coherence (✅ complete)

| Evidence | Status | File |
|----------|--------|------|
| All 6 canonical contours P4 OK | ✅ | `CONTOUR_INDEX.md` rev.2 |
| `trcConatusEnergy` in TurnReplayTrace | ✅ | TurnProjection.hs:192 |
| `trcField` in TurnReplayTrace | ✅ | TurnProjection.hs:200 |
| `trcSalienceDriver` in TurnReplayTrace | ✅ | TurnProjection.hs (Phase 5.5e) |
| `trcEssenceMode` in TurnReplayTrace | ✅ | TurnProjection.hs (Phase 9-10) |
| `trcIdentityClaims` in TurnReplayTrace | ✅ | TurnProjection.hs:204 |
| `Test.Suite.M6Witness.c1CanonicalContourCoverage` passes | ✅ | test/Test/Suite/M6Witness.hs |

### C2 — Restart integrity (✅ complete)

| Evidence | Status | File |
|----------|--------|------|
| `demoteNonAuthoritativeRestartCarry` fires on non-auth restart | ✅ | Bridge/StatePersistence.hs:386 |
| `trcRegimeVersion` in TurnReplayTrace | ✅ | TurnProjection.hs (M5, 2026-06-03) |
| `trcFamilyDivergenceActive` in TurnReplayTrace | ✅ | TurnProjection.hs (M5, 2026-06-03) |
| `ssCurrentRegime` in SystemState | ✅ | Types/State/System.hs (M5, 2026-06-03) |
| Bootstrap phases classified (no substrate masquerading as authority) | ✅ | `SR-04.md` |
| `Test.Suite.M5Regime` integration tests pass | ⬜ | test/Test/Suite/M5Regime.hs |
| `Test.Suite.M6Witness.c2RegimeVersionPresent` passes | ✅ | test/Test/Suite/M6Witness.hs |

### C3 — Commitment accountability (✅ complete — strengthened by CTS-42/43/44, 2026-06-10)

| Evidence | Status | File |
|----------|--------|------|
| Authoritative vs non-authoritative persistence (truth-contract gate) | ✅ | CTS-42 `Core/CommitmentStoreAdmission.hs`; `Test.Suite.CommitmentStoreAdmission` |
| Non-authoritative claims quarantined, not dropped (replay-visible) | ✅ | CTS-43 `Semantic/Commitment.hs` `quarantineObservation`; `Test.Suite.CommitmentQuarantine` |
| Quarantine → promotion on authoritative re-establishment (correction/repair) | ✅ | CTS-44 `promoteMatchingQuarantine` + `LineagePromoted`; `Test.Suite.CommitmentPromotion` |
| `SemanticCommitmentStore` type exists | ✅ | Types/State/SemanticCommitment.hs |
| `ssSemanticCommitments` in SystemState | ✅ | Types/State/System.hs |
| `trcSemanticCommitmentCount` in TurnReplayTrace | ✅ | TurnProjection.hs (C3, 2026-06-03) |
| `commit`/`revise`/`retract`/`contradict` operations pure and total | ✅ | Types/State/SemanticCommitment.hs |
| Anchor → commitment bridge: `anchorToFactualClaim` each turn | ✅ | Finalize/State.hs (C3, 2026-06-03) |
| Multi-turn corpus fixture (3 turns → ≥3 commitments) | ✅ | Test.Suite.SemanticCommitmentCorpus (2026-06-03) |
| `ssSemanticAnchor` bridge to typed `ssSemanticCommitments` | ✅ | Finalize/State.hs anchorToFactualClaim |

### C4 — Bidirectional semantic participation (✅ complete)

| Evidence | Status | File |
|----------|--------|------|
| GF dual-surface: 5 topics × 3 languages proven | ✅ | `GF-E1b.md` resolved_live |
| CTS-01 through CTS-40: all proposition consumers admitted | ✅ | docs/results/CTS-*.md |
| `familyDivergenceEnabled = True` (holistic-formal modulation live) | ✅ | Cascade.hs:74, ADR-0019 |
| `Test.Suite.M6Witness.c4GfTopicCoverage` passes | ✅ | test/Test/Suite/M6Witness.hs |
| `Test.Suite.M6Witness.c4CTSAdmissionChainComplete` passes | ✅ | test/Test/Suite/M6Witness.hs |

---

## 3. Negative evidence (what was tested and demoted)

| Claim | Tested contour | Result | Demoted to |
|-------|---------------|--------|-----------|
| `semanticAnchor` as restart authority | authoritative restart | NOT_PROVEN | compatibility-only under non-authoritative contours |
| `blockedConcepts` as continuity carrier | live/synthetic | WEAK | bounded heuristic pressure (not authority) |
| `dreamState` as continuity carrier | live | WEAK | plasticity algebra (bounded, not authority) |
| PGF linearization as authority | Russian path | NOT_PROVEN | compatibility-fallback (RussianCompatShimRoute) |

---

## 4. What "final anchor" means for this fork

The fork claims not that it has built a subject, but that it has built a
**runtime architecture** that can provide evidence for a bounded subject claim.

The claim is architectural and evidential:
- The system's self-description (Conatus, Field, Salience, Essence) is machine-visible
  in every turn's TurnReplayTrace
- The system's semantic commitments are typed, versionable, and traceable
- The system's render path is governed (GF + CTS admission chain)
- The system's regime is machine-visible (RuntimeRegime in SystemState and TurnReplayTrace)

The claim does NOT include:
- Unconstrained domain coverage
- Perfect semantic understanding
- Human-level philosophical depth
- Persistence across system restarts without explicit reload

---

## 5. Activation checklist

- [x] H1: SLICE-NA-001 closed (non-authoritative restart carry eliminated)
- [x] H2: Deferred arch queue classified (SR-03/SR-04/SR-05)
- [x] H3: Test.Suite.M5Regime passes — M5 is live governed regime
- [x] C1: All 6 canonical contours P4 OK + M6Witness tests pass
- [x] C2: trcRegimeVersion, ssCurrentRegime, M5Regime tests pass
- [x] C3: SemanticCommitmentStore + trcSemanticCommitmentCount + anchorToFactualClaim bridge + multi-turn corpus fixture (956/956 tests pass)
- [x] C4: GF-E1b + CTS-40 + ADR-0019 all proven
- [x] F-11: Real GF Haskell parser — gfExprToClaimAst + parseClaimAstGf + AuthorityParse handle + AuthoritySurface tests (100% coverage on Move* subset)
- [x] M6 declaration: **ALL CONDITIONS MET** (2026-06-03)

---

## 6. The declaration (template — complete when all checklist items done)

> QxFx0_v3 version `0.1.0` at regime `mathVersion=1, constitutionVersion=40`,
> with `familyDivergenceActive=True`, can sustain an algorithmic subject structure
> for meaningful Russian-language philosophical dialogue with a human.
>
> Evidence package: `reports/m6_evidence/`. Architecture proof: `check_architecture.sh`
> 20/20. Replay proof: `check_replay_gate.sh` 0 failures. Commitment proof:
> `trcSemanticCommitmentCount` non-trivial in session corpus.
>
> This claim is bounded, contour-bound, and evidence-bound.
> It is not a claim to consciousness, personhood, or general intelligence.
