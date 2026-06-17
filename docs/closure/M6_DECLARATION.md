# M6 Declaration: Algorithmic Subject Structure

**Status:** BOUNDED PUBLIC CLAIM (partial) — see §3 status table.
**Version:** QxFx0 `0.1.0`
**Regime:** mathVersion=1, constitutionVersion=44, familyDivergenceActive=True
**Reconciled:** 2026-06-16 (supersedes the 2026-06-03 "all contours ✅" draft)

> **Provenance note.** The 2026-06-03 draft declared all four contours closed and
> cited test functions (`M6Witness.c1CanonicalContourCoverage`,
> `.c4GfTopicCoverage`, `.c4CTSAdmissionChainComplete`) and result records
> (`docs/results/*`) that are **not present in public commits**. This revision
> repoints every citation to a real, in-repo public test or script, and marks the
> remaining contours as *pending public evidence* rather than asserting them.
> Private result records were **not** restored to public commits (the public/private
> boundary is intentional); contours that rely only on them are marked pending.

---

## 1. The bounded final claim

> **QxFx0, at the above regime, sustains the *core* of an algorithmic subject
> structure for meaningful domain dialogue with a human under governed, publicly
> checkable, replay-visible conditions — with three named sub-contours still
> pending public evidence.**

This claim is:

- **Scope-bound** — Russian and English philosophical dialogue domain
- **Contour-bound** — four explicit evidence contours (C1–C4), each split into
  *publicly evidenced* rows (a real in-repo test/script) and *pending* rows
- **Evidence-bound** — machine-checkable, not narrated; falsifiable by running
  `cabal test`, `scripts/check_architecture.sh`, and `scripts/check_replay_gate.sh`
- **Partial, not total** — it is **not** asserted that all contours are closed;
  see the pending column in §3
- **Not metaphysical** — no claim to consciousness, personhood, sentience,
  or general intelligence of any kind

**What is publicly evidenced today:** C1 (continuity) in full; the core of C2
(restart integrity), C3 (commitment store + corpus + CTS-42/43/44 admission,
quarantine, promotion), and C4 (bidirectional GF round-trip + live family divergence).

**What is pending public evidence:** the C4 "5 topics × 3 languages" topic-matrix
and the CTS-01–40 aggregate record (held privately); the H2 / SR-03/04/05
deferred-queue records (held privately).

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
   `scripts/check_architecture.sh` and the live CTS admission chain
5. **Bidirectional semantic participation** — words → atoms → families → words,
   with each stage having an explicit admission seam and a bidirectional GF
   parser (`parseClaimAstGf` closes the loop)

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

## 3. Evidence contours (public status)

**Legend:** ✅ = backed by a real, in-repo public test suite or runnable script
(the public falsification path). ⏳ = *pending public evidence* — the claim holds
in code or in a privately-held record, but has no public test/artifact yet.

> Test **pass/fail is not asserted here** — suites were not re-run for this
> revision (an unrelated slice is in progress). ✅ means "a public check targets
> this claim," i.e. it is publicly falsifiable, per the declaration's own
> evidence-bound rule.

### C1 — Continuity and coherence — **publicly evidenced**

| Claim | Evidence (code) | Public check |
|-------|-----------------|--------------|
| All canonical contours carry trace fields | `TurnProjection.hs:192–204` | ✅ `scripts/check_replay_gate.sh` + `Test.Suite.TraceSchema` |
| trcConatusEnergy in every trace | `TurnProjection.hs:192` | ✅ `Test.Suite.TraceSchema` |
| trcField in every trace | `TurnProjection.hs:200` | ✅ `Test.Suite.TraceSchema` |
| trcRegimeVersion in every trace | `TurnProjection.hs` (M5) | ✅ `Test.Suite.M5Regime.m5RegimeVersionIsStamped` |
| Regime version matches currentMathVersion | `defaultRuntimeRegime` | ✅ `Test.Suite.M5Regime.m5RegimeVersionMatchesCurrent` |
| Evidence admissibility classified per turn (SLICE-012) | `trcEvidenceAdmissibility` in `TurnProjection.hs`; `EvidenceAdmissibility.hs` | ✅ `Test.Suite.ReplayDeterminism` (trace round-trip includes field); `QXFX0_GOVERNED_EVIDENCE=1` fail-closes on Unavailable guard |

### C2 — Restart integrity — **core publicly evidenced**

| Claim | Evidence (code) | Public check |
|-------|-----------------|--------------|
| Non-authoritative restart state rejected at bootstrap | `demoteNonAuthoritativeRestartCarry`, `Bridge/StatePersistence.hs` | ✅ `Test.Suite.StatePersistence.testBootstrapRejectsNonAuthoritativePersistedState` |
| trcRegimeVersion stamps every turn | `Finalize/Projection.hs` | ✅ `Test.Suite.M5Regime` |
| familyDivergenceActive = True in trace | `Cascade.hs:74`, ADR-0019 | ✅ `Test.Suite.PromotionFlagDiscipline` |
| Architecture authority rules hold | `scripts/check_architecture.sh` | ✅ CI gate (`scripts/check_architecture.sh`) |
| Bootstrap phases classified (SR-04) | SR-04 record | ⏳ pending public evidence — record held privately |

### C3 — Commitment accountability — **publicly evidenced**

| Claim | Evidence (code) | Public check |
|-------|-----------------|--------------|
| SemanticCommitmentStore populated turn 1 | `anchorToFactualClaim` in `Finalize/State.hs` | ✅ `Test.Suite.SemanticCommitmentCorpus.c3Turn1ProducesCommitments` |
| Store grows across multi-turn session | `commitObservation` per turn | ✅ `…c3MultiTurnAccumulatesCommitments` |
| trcSemanticCommitmentCount = store size | `Finalize/Projection.hs` | ✅ `…c3TraceFieldMatchesStoreCount` |
| 3-turn corpus ≥ 3 commitments | `anchorToFactualClaim` × 3 | ✅ `…c3ThreeTurnCorpusFixture` |
| GF round-trip ≥ 99% on Move* subset | `gfExprToClaimAst` + `parseClaimAstGf` | ✅ `Test.Suite.AuthoritySurface.coverageTest` |
| Non-authority surfaces return Nothing | `parseAuthoritySurfacePattern` | ✅ `Test.Suite.AuthoritySurface.negativeCorpusTest` |

**C3 strengthening addendum — constitution-governed commitment accountability.**
The base C3 proves commitments are *stored*. The CTS-42/43/44 program upgrades C3
toward the full M6 criterion — commitments *held accountably under the constitution*,
authoritative vs non-authoritative distinguished, corrections replay-visible:

| Claim | Evidence (code) | Public check |
|-------|-----------------|--------------|
| Only faithful-authority surfaces persist as canonical (CTS-42) | `admitCommitmentToStore` on `TruthContractStatus`; `trcCommitmentStoreDecision` | ✅ `Test.Suite.CommitmentStoreAdmission` |
| Suppressed claims quarantined, not dropped; replay-visible (CTS-43) | `quarantineObservation`; `trcQuarantinedCommitmentCount` | ✅ `Test.Suite.CommitmentQuarantine` |
| Quarantined claim promoted to canonical on re-establishment (CTS-44) | `promoteMatchingQuarantine`; `LineagePromoted`; `trcPromotedFromQuarantineCount` | ✅ `Test.Suite.CommitmentQuarantine` (`unitPromoteMatchingQuarantine`, `unitPromoteNormalizedMatch`, `unitPromoteNoMatch`, `unitPromoteEmptyQuarantine`) |

The CTS-44 *promotion/repair* axis — the system refining a quarantined commitment
under a later authoritative correction — is publicly tested by the four
`unitPromote*` cases in `Test.Suite.CommitmentQuarantine`. `currentConstitutionVersion = 44`.

### C4 — Bidirectional semantic participation — **core publicly evidenced**

| Claim | Evidence (code) | Public check |
|-------|-----------------|--------------|
| Bidirectional GF parser operational | `parseClaimAstGf` in `Runtime/PGF.hs` | ✅ `Test.Suite.AuthoritySurface` (24 round-trips) |
| GF round-trip coverage ≥ 99% | `gfExprToClaimAst` ↔ `parseClaimAstGf` | ✅ `Test.Suite.AuthoritySurface.coverageTest` |
| familyDivergence live (ADR-0019) | `Cascade.hs:74` = True | ✅ `Test.Suite.M5Regime.m5FamilyDivergenceActiveIsStamped` |
| Replay gate covers canonical contours | `scripts/check_replay_gate.sh` | ✅ CI gate |
| 5 topics × 3 languages proven | GF-E1b record | ⏳ pending public evidence — record private; no public topic-matrix test |
| CTS-01–40: all consumers admitted (aggregate) | per-stage admission modules (live, wired in `Core/TurnPipeline/*`) | ⏳ pending public *aggregate* test — per-stage suites are public (`CommitmentStoreAdmission`, `ResponseContentAdmission`, `AdmissionEquivalence`); the 40-record aggregate is private |

---

## 4. Negative criteria — what does NOT constitute M6 evidence

The following are **explicitly rejected** as sufficient evidence:

| Rejected claim | Why |
|---------------|-----|
| "System produces fluent Russian output" | Surface fluency ≠ subject structure |
| "System has been running for N sessions" | Persistence alone ≠ subject structure |
| "System adapted its weights after corpus" | Heuristic adaptation alone ≠ subject structure |
| "System has an Essence commitment" | Essence is now **structural/runtime law** (Policy A, 2026-06-17: law-driven, `rrEssenceActive = True`), but it is **not M6-FELT evidence** — no felt-evidence gate has passed, and guard-unavailable stale evidence is inadmissible. Structural status ≠ felt subjecthood evidence. |
| "LLM call produced plausible answer" | External-tool paraphrase ≠ subject continuity |
| "System uses compatibility fallback" | Compatibility residue ≠ authority |
| Hidden singleton state surviving restarts | Non-auth restart carry is explicitly demoted |
| "A result record asserts it" (no public test) | Privately-held record ≠ public, reproducible evidence — marked ⏳ |

---

## 5. Explicit distinctions

| Category | What it is | How distinguished |
|----------|-----------|------------------|
| **Subject-structure evidence** | C1–C4 contours: trace fields, commitment store, GF round-trip, architecture gates | Machine-checkable via CI + public test suites |
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
4. **Essence as M6-FELT evidence** — Essence is **structural/runtime law**
   (Policy A, 2026-06-17: law-driven, `rrEssenceActive = True`, unconditionally
   active since 2026-05-19). It is counted as **M6-STRUCTURAL scaffold** (the
   runtime sustains Essence commitment as a governed law). It is **not** counted
   as **M6-FELT** (felt subjecthood) evidence until (a) SLICE-012 makes governed
   conditions provably hold in real runs, and (b) a felt-evidence gate
   (M6-FELT / B3) is defined and passes. The stale AB/guard-unavailable evidence
   (`audit-objective-2026-06-17.md §3`) is inadmissible for any felt claim.
5. **Calibrated parameters** — all thresholds remain hand-set (CALIBRATION_BACKLOG.md);
   empirical calibration requires the production-trace corpus
6. **The pending contours of §3** — the C4 topic-matrix and the private SR /
   CTS-aggregate records are **not** claimed as closed

---

## 7. Evidence package index

All publicly-checkable evidence lives in the repository and is reproducible by
running the standard CI suite. Pass/fail is **not asserted here** — run the
commands to verify or falsify:

```bash
cabal build all                      # builds the library
cabal test qxfx0-test-fast           # the public fast suite — run to verify
bash scripts/check_architecture.sh   # authority-boundary rules
bash scripts/check_replay_gate.sh    # canonical-contour trace-field coverage
bash scripts/gf_quality_gate.sh      # GF surface generation
```

| Evidence item | Location | Public check | Status |
|---------------|----------|--------------|--------|
| TurnReplayTrace fields (C1, C2, C3) | `src/QxFx0/Types/TurnProjection.hs` | `check_replay_gate.sh`, `Test.Suite.TraceSchema` | ✅ |
| SemanticCommitmentStore operations | `src/QxFx0/Types/State/SemanticCommitment.hs` | `Test.Suite.SemanticCommitmentCorpus` | ✅ |
| anchorToFactualClaim bridge | `src/QxFx0/Core/TurnPipeline/Finalize/State.hs` | `Test.Suite.SemanticCommitmentCorpus` | ✅ |
| GF bidirectional parser | `src/QxFx0/Runtime/PGF.hs`, `Semantic/Authority/GfExprParse.hs` | `Test.Suite.AuthoritySurface` | ✅ |
| AuthoritySurface round-trip | `src/QxFx0/Render/Authority.hs` | `Test.Suite.AuthoritySurface` | ✅ |
| RuntimeRegime machine-visible | `src/QxFx0/Types/RuntimeRegime.hs` | `Test.Suite.M5Regime` | ✅ |
| Restart non-auth rejection | `src/QxFx0/Bridge/StatePersistence.hs` | `Test.Suite.StatePersistence` | ✅ |
| CTS-42 commitment admission | `src/QxFx0/Core/CommitmentStoreAdmission.hs` | `Test.Suite.CommitmentStoreAdmission` | ✅ |
| CTS-43 commitment quarantine | `src/QxFx0/Semantic/Commitment.hs` | `Test.Suite.CommitmentQuarantine` | ✅ |
| ADR-0019 family divergence live | `src/QxFx0/Core/TurnRouting/Cascade.hs:74` | `Test.Suite.M5Regime` | ✅ |
| Architecture authority rules | `scripts/check_architecture.sh` | CI gate | ✅ |
| CTS-44 commitment promotion | `promoteMatchingQuarantine`; `LineagePromoted` | `Test.Suite.CommitmentQuarantine` (`unitPromote*`) | ✅ |
| GF dual-surface 5 topics × 3 langs | `spec/gf/`, GF-E1b record (private) | topic-matrix test (none) | ⏳ pending |
| CTS-01–40 admission aggregate | per-stage admission modules (live) | aggregate record (private) | ⏳ pending |
| H2 deferred queue (SR-03/04/05) | SR result records (private) | result records | ⏳ pending |

---

## 8. Witness regime

The declaration is a **witness regime**, not a single gate.

M6 evidence is distributed across the four contours C1–C4. No single test
or function constitutes "the subject gate." The *publicly-evidenced core* of the
claim holds while these public checks pass simultaneously:

- C1 holds iff `scripts/check_replay_gate.sh` exits 0 and `Test.Suite.TraceSchema`
  + `Test.Suite.M5Regime` pass
- C2 (core) holds iff `Test.Suite.StatePersistence` and `Test.Suite.M5Regime` and
  `Test.Suite.PromotionFlagDiscipline` pass
- C3 (core) holds iff `Test.Suite.SemanticCommitmentCorpus` (3-turn corpus),
  `Test.Suite.AuthoritySurface` (≥99% GF coverage), `Test.Suite.CommitmentStoreAdmission`
  (CTS-42), and `Test.Suite.CommitmentQuarantine` (CTS-43 + CTS-44 promotion) pass
- C4 (core) holds iff `Test.Suite.AuthoritySurface` and
  `Test.Suite.M5Regime.m5FamilyDivergenceActiveIsStamped` pass and
  `scripts/check_architecture.sh` exits 0

> `Test.Suite.M6Witness` exists, but it contains drift/retention/fallback **metric**
> tests (`testIdentityDrift`, `testCommitmentRetention`, `testCompositeFallback*`,
> `testRestartContinuity`, …), **not** the contour functions cited by the 2026-06-03
> draft (`c1CanonicalContourCoverage`, `c4GfTopicCoverage`,
> `c4CTSAdmissionChainComplete` — which do not exist). The contour checks above are
> the real public path.

If any core contour fails, the claim is suspended until repaired. The pending
contours (§3) are not part of the publicly-evidenced core and must be closed
before a *total* M6 claim can be made.

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
system silently failing the architecture's own declared invariants — with the
public-evidence scope and pending exceptions named in §3.

---

## 10. Declaration provenance

| Item | Value |
|------|-------|
| Reconciled to public truth | 2026-06-16 |
| Supersedes | 2026-06-03 "all contours ✅" draft (phantom citations) |
| Test pass/fail | not re-run this revision (unrelated slice in progress) |
| Architecture check | `scripts/check_architecture.sh` (public, run to verify) |
| mathVersion | 1 |
| constitutionVersion | 44 |
| familyDivergenceActive | True (ADR-0019, 2026-06-02) |
| essenceActive | True (Policy A, 2026-06-17 — structural law; not FELT evidence) |
| Governed by | `docs/closure/REGIME_GOVERNANCE.md` |
| Witness protocol | `docs/closure/M6_WITNESS_PROTOCOL.md` |
| Evidence package | `docs/closure/M6_CLAIM_PACKAGE.md` |
| Claim index | `reports/m6_evidence/EVIDENCE_INDEX.md` |

### Reconciliation log (2026-06-16)

- Removed 3 phantom test citations (`M6Witness.c1CanonicalContourCoverage`,
  `.c4GfTopicCoverage`, `.c4CTSAdmissionChainComplete`); repointed C1/C4 to real
  public suites (`TraceSchema`, `M5Regime`, `AuthoritySurface`, `check_replay_gate.sh`).
- CTS-44 promotion is publicly tested by `Test.Suite.CommitmentQuarantine`
  (`unitPromote*`, already on `origin/main` as `fc4db34`); no separate
  `Test.Suite.CommitmentPromotion` is required.
- Marked private records (SR-03/04/05, GF-E1b, CTS-01–40 aggregate) as **pending
  public evidence**; did **not** restore them to public commits.
- Downgraded the blanket "all contours ✅" claim to a **bounded/partial** public
  claim; pass/fail tallies that could not be re-verified this session were removed.
- Project name normalized `QxFx0_v3` → `QxFx0`.
