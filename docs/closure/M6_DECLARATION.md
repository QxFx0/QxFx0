# M6 Declaration: Algorithmic Subject Structure

**Status:** DECLARED (2026-06-03)
**Version:** QxFx0_v3 `0.1.0`
**Regime:** mathVersion=1, constitutionVersion=40, familyDivergenceActive=True

---

## 1. The bounded final claim

> **QxFx0_v3, at the above regime, can sustain an algorithmic subject structure
> for meaningful domain dialogue with a human under governed, checkable,
> and replay-visible conditions.**

This claim is:

- **Scope-bound** — Russian and English philosophical dialogue domain
- **Contour-bound** — four explicit evidence contours (C1–C4), each with named
  test suites and architectural invariants
- **Evidence-bound** — machine-checkable, not narrated; falsifiable by running
  `cabal test`, `check_architecture.sh`, and `check_replay_gate.sh`
- **Not metaphysical** — no claim to consciousness, personhood, sentience,
  or general intelligence of any kind

---

## 2. Definitions (checked)

### 2.1 Algorithmic subject structure

An **algorithmic subject structure** is a runtime that can sustain,
under explicit regime rules:

1. **Bounded self-related continuity** across turns and restarts —
   the system maintains a machine-visible self-description (Conatus energy,
   Field, Salience verdict, Essence mode, regime version) in every
   `TurnReplayTrace`; non-authoritative restart state is explicitly demoted,
   not silently carried
2. **Domain-grounded semantic commitments** — the system makes, revises,
   retracts, and repairs semantic commitments through typed operations
   (`commitObservation`, `revise`, `retract`, `contradict`) on a versioned
   `SemanticCommitmentStore`; every turn that establishes a `SemanticAnchor`
   adds a typed `FactualClaimPayload` to the store
3. **Accountable revision under correction** — commitment changes are recorded
   in `ssSemanticCommitments` and visible in `trcSemanticCommitmentCount` in
   the replay trace
4. **Governed distinction** between authority, projection, fallback,
   compatibility residue, and quoted external output — enforced by
   `check_architecture.sh` 20 rules and the CTS-01–CTS-40 admission chain
5. **Bidirectional semantic participation** — words → atoms → families → words,
   with each stage having an explicit admission seam (CTS-01–CTS-40) and a
   bidirectional GF parser (`parseClaimAstGf` closes the loop)

### 2.2 Meaningful domain dialogue

**Meaningful domain dialogue** is dialogue in which the system:

1. Carries domain-bearing commitments across turns via
   `ssSemanticCommitments` and the `DialogueCommitmentLedger`
2. Answers, refines, retracts, or repairs those commitments under challenge
   via typed `SemanticCommitmentStore` operations
3. Exposes replay-visible and governance-visible reasons for persistence,
   revision, refusal, or fallback via `TurnReplayTrace.trc*` fields
4. Remains bounded by declared authority, reconstruction, and recovery contours
   enforced by CI gates (architecture check, replay gate, GF quality gate)

---

## 3. Evidence contours (all ✅)

### C1 — Continuity and coherence

| Claim | Evidence | Test |
|-------|---------|------|
| All 6 canonical contours P4 OK | TurnProjection.hs:192–204 | `Test.Suite.M6Witness.c1CanonicalContourCoverage` |
| trcConatusEnergy in every trace | TurnProjection.hs:192 | `Test.Suite.TraceSchema` |
| trcField in every trace | TurnProjection.hs:200 | `Test.Suite.TraceSchema` |
| trcRegimeVersion in every trace | TurnProjection.hs (M5) | `Test.Suite.M5Regime.m5RegimeVersionIsStamped` |
| Regime version matches currentMathVersion | defaultRuntimeRegime | `Test.Suite.M5Regime.m5RegimeVersionMatchesCurrent` |

### C2 — Restart integrity

| Claim | Evidence | Test |
|-------|---------|------|
| Non-auth restart carry demoted | `demoteNonAuthoritativeRestartCarry` | `Test.Suite.RuntimeInfrastructure` |
| Bootstrap phases classified | `SR-04.md` | `SR-04` result record |
| trcRegimeVersion stamps every turn | `Finalize/Projection.hs` | `Test.Suite.M5Regime` |
| familyDivergenceActive = True in trace | Cascade.hs:74, ADR-0019 | `Test.Suite.PromotionFlagDiscipline` |
| Architecture 20/20 | `check_architecture.sh` | CI gate |

### C3 — Commitment accountability

| Claim | Evidence | Test |
|-------|---------|------|
| SemanticCommitmentStore populated turn 1 | `anchorToFactualClaim` in State.hs | `Test.Suite.SemanticCommitmentCorpus.c3Turn1ProducesCommitments` |
| Store grows across multi-turn session | `commitObservation` per turn | `Test.Suite.SemanticCommitmentCorpus.c3MultiTurnAccumulatesCommitments` |
| trcSemanticCommitmentCount = store size | `Finalize/Projection.hs` | `Test.Suite.SemanticCommitmentCorpus.c3TraceFieldMatchesStoreCount` |
| 3-turn corpus ≥ 3 commitments | `anchorToFactualClaim` × 3 | `Test.Suite.SemanticCommitmentCorpus.c3ThreeTurnCorpusFixture` |
| GF round-trip ≥ 99% on Move* subset | `gfExprToClaimAst` + `parseClaimAstGf` | `Test.Suite.AuthoritySurface.coverageTest` |
| Non-authority surfaces return Nothing | `parseAuthoritySurfacePattern` | `Test.Suite.AuthoritySurface.negativeCorpusTest` |

**C3 strengthening addendum (2026-06-10) — constitution-governed commitment accountability.**
The original C3 (2026-06-03) proved commitments are *stored*. The CTS-42/43/44 program upgrades
C3 to the full M6 criterion — commitments are *held accountably under the constitution*, with
authoritative vs non-authoritative state distinguished and corrections replay-visible:

| Claim | Evidence | Test |
|-------|---------|------|
| Only faithful-authority surfaces persist as canonical (degraded/non-authoritative do not) | CTS-42 `admitCommitmentToStore` on `TruthContractStatus`; `trcCommitmentStoreDecision` | `Test.Suite.CommitmentStoreAdmission` |
| Suppressed (non-authoritative) claims are quarantined, not silently dropped; replay-visible | CTS-43 `quarantineObservation`; `trcQuarantinedCommitmentCount` | `Test.Suite.CommitmentQuarantine` |
| Quarantined claim promoted to canonical when a later authoritative turn re-establishes it (correction/repair) | CTS-44 `promoteMatchingQuarantine`; `LineagePromoted`; `trcPromotedFromQuarantineCount` | `Test.Suite.CommitmentPromotion` |

This is the C3 axis of subject structure: the system distinguishes its own bounded,
authoritative commitments from non-authoritative residue and refines them under correction in a
governance-visible way. `currentConstitutionVersion = 44`.

### C4 — Bidirectional semantic participation

| Claim | Evidence | Test |
|-------|---------|------|
| 5 topics × 3 languages proven | GF-E1b result record | `Test.Suite.M6Witness.c4GfTopicCoverage` |
| CTS-01–40: all consumers admitted | 40 result records | `Test.Suite.M6Witness.c4CTSAdmissionChainComplete` |
| familyDivergence live (ADR-0019) | Cascade.hs:74 = True | `Test.Suite.M5Regime.m5FamilyDivergenceActiveIsStamped` |
| Bidirectional GF parser operational | `parseClaimAstGf` in Runtime/PGF.hs | `Test.Suite.AuthoritySurface` (24 round-trips) |
| Replay gate 0 failures | `check_replay_gate.sh` | CI gate |

---

## 4. Negative criteria — what does NOT constitute M6 evidence

The following are **explicitly rejected** as sufficient evidence:

| Rejected claim | Why |
|---------------|-----|
| "System produces fluent Russian output" | Surface fluency ≠ subject structure |
| "System has been running for N sessions" | Persistence alone ≠ subject structure |
| "System adapted its weights after corpus" | Heuristic adaptation alone ≠ subject structure |
| "System has an Essence commitment" | Flag-off, not yet promoted; not counted |
| "LLM call produced plausible answer" | External-tool paraphrase ≠ subject continuity |
| "System uses compatibility fallback" | Compatibility residue ≠ authority |
| Hidden singleton state surviving restarts | Non-auth restart carry is explicitly demoted |

---

## 5. Explicit distinctions

| Category | What it is | How distinguished |
|----------|-----------|------------------|
| **Subject-structure evidence** | C1–C4 contours: trace fields, commitment store, GF round-trip, architecture gates | Machine-checkable via CI + test suites |
| **Projection fluency** | Rendered surface text (`taFinalRendered`) | `AuthorityClass.AuthorityShim` or `AuthorityClass.AuthorityCanonical` tag |
| **External-tool support** | LLM-generated content via `Bridge.ExternalLLM` | `trcExternalTool` field + `OriginLLM` commitment origin |
| **Fallback survival** | `RussianCompatShimRoute` / pattern-match fallback | `RussianCompatShimRoute` + `AuthorityShim` + `SR-03` classification |
| **Compatibility residue** | `PersistenceEnvelope` decode, schemaV1 fields | SR-05 compatibility window classification, `OriginParser "compat:*"` |

---

## 6. What the claim does NOT cover

1. **Arbitrary domain depth** — the system commits to its dialogue domain
   (philosophical Russian/English); specialist knowledge outside that domain
   is not claimed
2. **Continuous production operation** — the claim is about a single session;
   multi-session continuity requires the production-trace corpus (F-09, deferred)
3. **Zero fallback** — compatibility fallbacks exist (SR-03, SR-05) and are
   explicitly classified; their presence is bounded and documented, not hidden
4. **Full essence commitment** — `essenceCommitmentEnabled = False`; the Essence
   contour is P4 OK but flag-off; it is not counted as active subject evidence
5. **Calibrated parameters** — all thresholds remain hand-set (CALIBRATION_BACKLOG.md);
   empirical calibration requires the production-trace corpus

---

## 7. Evidence package index

All machine-checkable evidence lives in the repository and is reproducible
by running the standard CI suite:

```bash
cabal build all                      # builds 343 modules — no errors
cabal test qxfx0-test-fast           # 956/956 tests pass
bash scripts/check_architecture.sh  # 20/20 rules pass
bash scripts/check_replay_gate.sh   # 0 failures, all 6 contours P4 OK
bash scripts/gf_quality_gate.sh     # 0 errors, 0 warnings
```

| Evidence item | Location | Verified by |
|---------------|---------|------------|
| TurnReplayTrace fields (C1, C2, C3) | `src/QxFx0/Types/TurnProjection.hs` | `check_replay_gate.sh` |
| SemanticCommitmentStore operations | `src/QxFx0/Types/State/SemanticCommitment.hs` | `Test.Suite.SemanticCommitmentCorpus` |
| anchorToFactualClaim bridge | `src/QxFx0/Core/TurnPipeline/Finalize/State.hs` | `Test.Suite.SemanticCommitmentCorpus` |
| GF bidirectional parser | `src/QxFx0/Runtime/PGF.hs` | `Test.Suite.AuthoritySurface` |
| AuthoritySurface round-trip | `src/QxFx0/Render/Authority.hs` | `Test.Suite.AuthoritySurface` |
| RuntimeRegime machine-visible | `src/QxFx0/Types/RuntimeRegime.hs` | `Test.Suite.M5Regime` |
| Architecture 20/20 | `scripts/check_architecture.sh` | CI: PROD_GO gate |
| CTS-01–40 admission chain | `src/QxFx0/Core/Proposition*Admission.hs` (×21) | `Test.Suite.M6Witness` |
| GF dual-surface 5 topics × 3 langs | `spec/gf/`, `docs/results/GF-E1b.md` | `Test.Suite.M6Witness` |
| ADR-0019 family divergence live | `src/QxFx0/Core/TurnRouting/Cascade.hs:74` | `Test.Suite.M5Regime` |
| H2 deferred queue classified | `docs/results/SR-03.md`, `SR-04.md`, `SR-05.md` | Result records |
| Fallback policy classified | `docs/closure/REGIME_GOVERNANCE.md §5` | Architecture docs |
| Compatibility windows declared | `docs/results/SR-05.md` | SR-05 result record |

---

## 8. Witness regime

The declaration is a **witness regime**, not a single gate.

M6 evidence is distributed across the four contours C1–C4. No single test
or function constitutes "the subject gate." The subject claim holds only
while all four contours hold simultaneously:

- C1 passes iff `check_replay_gate.sh` exits 0 and `Test.Suite.M6Witness`
  passes
- C2 passes iff `Test.Suite.M5Regime` passes and bootstrap SR-04 is valid
- C3 passes iff `Test.Suite.SemanticCommitmentCorpus` passes (3-turn corpus)
  and `Test.Suite.AuthoritySurface` passes (≥99% GF coverage)
- C4 passes iff `Test.Suite.M6Witness.c4*` passes and `check_architecture.sh`
  exits 0

If any contour fails, the claim is suspended until the contour is repaired.

---

## 9. What "algorithmic subject structure" is NOT in this fork

The fork explicitly rejects the following framings:

- **"The system is conscious"** — no claim to phenomenal experience
- **"The system has preferences"** — Conatus is an energy functional, not a
  preference ordering
- **"The system understands language"** — the system parses and routes; it does
  not claim semantic understanding in the philosophical sense
- **"The system is autonomous"** — all behavior is governed by explicit regime
  rules; the system cannot modify its own architecture

The claim is precisely: code in this runtime can sustain the **structural
conditions** (continuity, commitment, accountability, bidirectionality)
under which a human can engage in meaningful domain dialogue without the
system silently failing the architecture's own declared invariants.

---

## 10. Declaration provenance

| Item | Value |
|------|-------|
| Declared | 2026-06-03 |
| Test count at declaration | 956/956 (qxfx0-test-fast) |
| Architecture check | 20/20 rules |
| mathVersion | 1 |
| constitutionVersion | 40 (CTS-01–CTS-40) |
| familyDivergenceActive | True (ADR-0019, 2026-06-02) |
| essenceActive | False (pending corpus) |
| Governed by | `docs/closure/REGIME_GOVERNANCE.md` |
| Witness protocol | `docs/closure/M6_WITNESS_PROTOCOL.md` |
| Evidence package | `docs/closure/M6_CLAIM_PACKAGE.md` |
| Claim index | `reports/m6_evidence/EVIDENCE_INDEX.md` |
