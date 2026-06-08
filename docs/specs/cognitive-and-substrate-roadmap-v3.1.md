# Roadmap — Cognitive wiring + Substrate (SQL-GF) migration

**Version:** 3.1 · **Date:** 2026-06-04 · **Status:** active · **Strategic decision R-M3e: CLEAN INVENTORY RELOCATION, staged (not generativity).**

This roadmap derives from a code-verified audit of QxFx0 against the rubric of "complexity of human thinking." It addresses 11 confirmed defects (Track I) plus the offline-Python word-generation coupling and the SQL→GF migration (Track II). It is the single source of truth for the effort; the **Status ledger** below is the cross-session progress record (update it as items move).

---

## Status ledger (update on every state change)

| ID | Item | Track | State | Notes |
|---|---|---|---|---|
| **F** | Essence threshold unit-fix | I | ✅ done | R-F1 already in code (`defaultEssenceModulation = 7.0`); R-F2 unit-guard + R-F3 deferred-contract tests added to `Test.Suite.SelfEssence`; `qxfx0-test-fast` compiles+links (commit on branch) |
| **B** | Episodic recall (`retrieve`) | I | ✅ done (incr.2) | `recallForTrace` living consumer of `retrieve` on projection trace, flag `episodicRecallActive`=off (ADR-0043), anti-rot test (`Test.Suite.MemoryEpisodic`) + registry + flag-discipline reg; **incr.2 (2026-06-04):** fixed compilation errors (`EpisodicUserText` constructor, `rebuildIndex` call, import name); 6 anti-rot tests passing. Suite green vs 17 pre-existing baseline. cosine cue-rank (R-B2) + decision-feed = follow-up increments |
| **A** | ToM core (Bayesian + slots) | I | ✅ done (incr.1) | `ssUserModel :: BeliefState` persisted (backward-compat JSON); `updateUserModel` living consumer of `bayesianUpdateFromText` in Finalize, flag `userModelActive`=off (ADR-0044); `dominantIntent` reader overrides write-only `dtIntentHypothesis`; Bayesian modules exposed; anti-rot test (`Test.Suite.UserModel`) + registry + flag-discipline reg; suite 1018 cases, 17 baseline unchanged. Routing/`dtUserGoal` consumption + likelihood calibration (G3) = follow-up |
| **S** | CognitiveSignals seam | I | ✅ done | `Types.CognitiveSignals` record (counterfactual entropy, field confidence, shadow disagreement, max posterior); `buildCognitiveSignals` computes once on Finalize, surfaced on `trcCognitiveSignals`. Anti-rot test (`Test.Suite.CognitiveSignals`) + registry. Suite 1020 cases, 17 baseline. Ready for D/E to read instead of re-deriving |
| **D** | clDoubtScore + metaloop | I | ✅ done (incr.1) | `computeDoubt` derives `clDoubtScore` from salience verdict (was init-0.0, never written); reader suppresses narrative when doubt ≥0.75 under flag `doubtLoopActive`=off (ADR-0045). Anti-rot test (`Test.Suite.DoubtLoop`) + registry. Suite 1024 cases, 17 baseline. Outcome-calibration (G3) + clarify-question response = follow-up |
| **E** | Affect valence/arousal + mood | I | ✅ done (incr.2) | `computeAtmosphereDecoupled` (arousal←input intensity, not tension; valence independent) + `ssMood` EMA (`updateMood`, window 12, spike-resistant), flag `affectDecoupledActive`=off (ADR-0046). Anti-rot test (`Test.Suite.AffectModel`) + registry. **incr.2 (2026-06-04):** integrated test suite into `TestMainUnit.hs`, 4 anti-rot tests passing. Suite 1028 cases, 17 baseline. Behavioural consumer of mood + discrete emotions = follow-up/Deferred |
| **H3** | Family divergence real | I | ✅ done | Divergence already real since ADR-0019 promotion (familyDivergenceEnabled=True, Cascade.hs:74): holisticFamily ≠ formalFamily, reconcile picks between them, rdFamily flows through to render. Stale "behaviour-preserving baseline" comment at TurnRouting.hs:165-175 corrected. No code change needed |
| **C** | Content-saliency (Spectral) | I | ✅ done (incr.1) | `computeContentSaliency` wires `detectClusters` into `CognitiveSignals.csContentSaliency` (trace-observable) behind flag `contentSalienceActive`=off. Spectral exposed-modules, zero-importers resolved. Anti-rot test (`Test.Suite.ContentSalience`) + registry. Suite 1031 cases, 17 baseline. Salience-controller weighting = increment-2 |
| **G** | Semantic inference (Datalog) | I | ✅ done (incr.1) | `deriveAtoms` (3 multi-step rules: NeedContact+Exhaustion, Contradiction+Doubt, AgencyLost+Searching) feeds derived atoms into `runSemanticLogic` behind flag `derivedInferenceActive`=off (ADR-0047). Anti-rot test (`Test.Suite.DerivedInference`) + registry. Datalog-rule expansion = increment-2 |
| **H1** | ExternalLLM cache/Deferred | I | ⬜ planned | dep: corpus + M2 |
| **I** | Rename campaign | I | ✅ done Tier-0 | **Spectral→ContentCluster** (module + 5 imports + cabal); ADR-0043. **Rejected:** Consciousness (active lexicon, not dead), Dream/Counterfactual (Tier-1, serialized). Tier-1 requires schema migration (deferred). Suite green, 0 errors |
| **M1** | SQL canon + provenance | II | ✅ done (incr.1) | requirements.txt pinned to exact versions (pymorphy3==2.0.6, spacy==3.8.13); Generated.hs provenance header (X6); README clarified (runtime pure Haskell, data-dependent on offline Python pipeline). SQL already canonical (check_generated_artifacts.sh). Full regeneration-byte-identical check = follow-up |
| **M2** | GF/RGL runtime morphology | II | ✅ done (incr.1) | runtimeMorphologyActive flag + paradigmGenitive resolver (genitiveForm-first, no hardcoded exceptions); legacy path preserved behind flag. Registry + flag-discipline reg. Full RGL runtime path = increment-2 |
| **H2** | GF boot-probe + default-on | II | ✅ done | `PgfHealth` probe integrated into `SystemHealth` (R-H2.1); `Runtime.PGFStatus` module (circular dep fix); `linearizeOrFallbackTagged` checks both `gfMapFallbackReason` AND `pgfFallbackReason` → GF default-on when PGF valid (R-H2.2); ADR-0044. Telemetry (R-H2.3) → Phase II. Suite green |
| **M3** | GF renderer, relocation, staged | II | 🟡 M3.0 harness done | `GFParityHarness` module (reference table + `verifyParity` gate); anti-rot test (`Test.Suite.GFParityHarness`) + registry. Table starts empty; `captureParityFixture` + per-move GF migration = M3.1 |
| **X1** | Anti-rot standard + gate rule #21 | x | ✅ done | ADR-0042 + `docs/anti_rot_registry.tsv` + `check_architecture.sh` rule [21] (syntax-clean, rule verified in isolation; WP-F seeded) |
| **X6** | Word-gen provenance (pin python) | x | ⬜ planned | |

States: ⬜ planned · 🟡 in-progress · ✅ done · ⛔ blocked (note blocker) · 🔁 deferred (corpus).

---

## 1. Diagnosis (two tracks)

- **Track I — cognitive gaps:** mechanism/type exists but is not wired / computes a degenerate value / is in the wrong scale (11 verified defects).
- **Track II — substrate Python coupling:** all runtime word forms are produced offline by pymorphy3/spacy/OpenCorpora; SQL is already canonical; GF/RGL already does morphology; F-11 proved runtime PGF — yet production rendering runs hardcoded Haskell, GF off by default.

**Goal:** zero write-only cognitive fields; zero exposed modules without a consumer; zero wrong-scale values; names match implementation; and a managed path toward `SQL → GF/RGL → PGF` with honest generation provenance — **relocating the existing bounded inventory, not raising the generativity ceiling.**

---

## 2. Invariants

| ID | Invariant |
|---|---|
| **I1** | Deterministic turn trace (no wallclock/random). ⚠️DET points flagged |
| **I2** | Fail-closed + flag-promotions; default-off until replay-gate green |
| **I3** | Append-only governance; state changes via typed payload + versioned `fromJSON` migration |
| **I4** | ADR per WP/M; replay-gate + architecture-gate green |
| **I5** | Anti-rot: living consumer (+ anti-rot test), or removal, or explicit `Deferred` contract pinned by a test |

---

## 3. Two tracks, work classes, gating

- **Track I:** Phase I (wiring, no corpus) → Phase II (calibration, needs corpus F-09/F-10).
- **Track II:** **NOT corpus-gated** — gated by grammar coverage, runnable in parallel.
- **Output-churn (re-bless golden):** E, H3, C(output-level), G. **Parity-preserving:** M3 (relocation; per-move re-bless only on cosmetic diffs). **Additive-behind-flag:** B, A, D, C(verdict), M2.

---

## 4. Posture & priority

| WP/M | Track | Defect | Posture | Prio | Depends |
|---|---|---|---|---|---|
| F | I | #9 Essence units | Wire-in | 1 | — |
| B | I | #10 retrieve dead | Wire-in | 2 | — |
| A | I | #1,#3 ToM+slots | Wire-in | 3 | — |
| S | I | seam | Wire-in | 4 | A |
| D | I | #2 doubt loop | Wire-in | 5 | A,S |
| E | I | #4 affect degenerate | Wire-in | 6 | S |
| H3 | I | #11 divergence | Wire-in/Rename | 7 | — |
| C | I | #8 Spectral dead | Wire-in/Retire | 8 | H3 |
| G | I | #7 10-rule routing | Datalog productive | 9 | — |
| H1 | I | #5 LLM disabled | Cache/Deferred | 10 | corpus + M2 |
| I | I | naming | Rename Tier-0/1 | par | A (Tier-1) |
| M1 | II | python canon | SQL freeze + provenance | 1′ | — |
| **M2** | GF/RGL runtime morphology | II | ✅ done (incr.1) | runtimeMorphologyActive flag + paradigmGenitive resolver; legacy path preserved behind flag. Registry + flag-discipline reg. Full RGL runtime path = increment-2 |
| M3 | II | hardcoded render (⊇H2) | GF renderer, relocation, staged | 3′ | M3-slot→M2 |

**Execution order:** `F → B → A → S → D → E → H3 → C → G → H1`; in parallel `M1 → M3.0 → M3.1/2 → M3.3`, `M2` alongside. Cross-nodes: **M2 → H1(live)**, **A → I(Tier-1)**, **H3 → C(output)**, **X1 before first wire (B/M1)**.

---

## 5. TRACK I — Cognitive wiring

### WP-F — Essence threshold unit-fix `[#9]` · Wire-in · S · churn:none
**Finding (refined by code):** `phase9EssenceModulation.emConatusStructuralFloor = 0.5` was a unit-mismatch (calibrated vs `arbitraryUnitDouble`~[0,1] not production `ceScalar` log-scale ~[5,20+]). **R-F1 already implemented:** `defaultEssenceModulation = phase9… { emConatusStructuralFloor = 7.0 }` (ADR-0012 §15.1). The `0.5` is intentionally kept as a regression-lock reference.
- **R-F1.** DONE in code (floor 7.0 in live default).
- **R-F2.** Add unit-guard property test: live `emConatusStructuralFloor` lies within the achievable `computeConatusEnergy` codomain (below healthy ~14-15, above degenerate) — locks the fix, blocks 0.5 regression.
- **R-F3.** Angst-side params (`emAngstCommitmentThreshold` etc.) are uncalibrated (code admits, §15.2) → explicit `Deferred` contract + test asserting we don't silently rely on the angst trigger.
**Acceptance:** unit-guard test green; deferred contract explicit. **Pilot flow.**

### WP-B — Episodic recall `[#10]` · Wire-in · M · additive
`retrieve` uncalled; live read = 2 events (`Projection.hs:263`); `ssEpisodic=Nothing`.
- R-B1 build `EpisodicQuery` from frame on Prepare, call `retrieve`. R-B2 cue-rank via existing `cosineSimilarity`. R-B3 ⚠️DET top-k cap + tie-break (cosine→recency/id). R-B4 fill `trcEpisodicRetrieval/Forgetting`; fix `ssEpisodic` init. R-B5 flag `episodicRecallActive`.
- Nescope→Deferred: working memory, episodic→semantic consolidation. Anti-rot: removing `retrieve` breaks a behavioral test.

### WP-A — ToM core `[#1,#3]` · Wire-in · L · Phase I(+II) · additive
`bayesianUpdate` off-pipeline (`Bayesian.hs:5`); `dtIntentHypothesis/dtUserGoal/dtActiveQuestion` write-only.
- R-A1 `ssUserModel` persistent posterior (⚠️I3 reuse versioned `fromJSON` Phase-2 + migration). R-A2 update via `bayesianUpdateFromText`; drop/parametrize `*0.08` (`Intuition.hs:136`). R-A3 bind slots to posterior + living reader (SensePlan/TurnPlanning). R-A4 flag `userModelActive`. R-A5(II) likelihoods→`UserModelWeights`.
- Anti-rot: removing the `dtIntentHypothesis` reader breaks a test.

### WP-S — CognitiveSignals seam · Wire-in · S/M · churn:none
- R-S1 compute once on Prepare (counterfactual entropy, shadow-Datalog disagreement, max-posterior, FieldConfidence); read by A/D/E. R-S2 components from named records (X2).

### WP-D — clDoubtScore + metaloop `[#2]` · Wire-in · M · additive · dep A,S
`clDoubtScore` write-only; "confidence" = input agreement, not correctness.
- R-D1 compute doubt from `CognitiveSignals` (degrades without A; posterior term added after A). R-D2 reader: `doubt>thr` → `CMClarify`/↓explicitness. R-D3 outcome calibration via `acceptanceMarkers` — replace "placeholder until P8". R-D4 flag `doubtLoopActive`. Anti-rot: yes.

### WP-E — Affect: split valence/arousal + mood `[#4]` · Wire-in · M · output
`arousal≡tension`, `valence=agency−tension+legit` (`Field.hs:340`).
- R-E1 arousal ← input intensity (not tension identity). R-E2 valence ← appraisal (outcome/distress/legit), independent of agency. R-E3 mood = EMA, window 10–20 turns (config); test: single spike not > 2× window. R-E4 ≥1 behavioral effect beyond tone. R-E5(II) coeffs→record.
- Nescope→Deferred: discrete emotions. Anti-rot: yes.

### WP-H3 — Family divergence real `[#11]` · Wire/Rename · M/S · output (before C)
- R-H3a `holisticFamily≠formalFamily` affects render, not only trace. R-H3b re-bless golden under flag. Alt(Rename): rename `DivergeOnTone`, do not claim two modes (→WP-I).

### WP-C — Content-saliency (Spectral) `[#8]` · Wire/Retire · M/L · dep H3
- R-C1 cluster MeaningGraph → top-down weight into Salience. R-C2 ⚠️DET deterministic eigen-order (index tie-break). R-C3 threshold `0.1`→calibratable(II). R-C4 flag `contentSalienceActive`.
- Acceptance two-level: pre-H3 verdict changes with cluster; post-H3 answer changes. Alt: Retire (remove from exposed).

### WP-G — Semantic inference vs 10 rules `[#7]` · Datalog productive · L · Risk Medium-High · output
- R-G1 multi-step rules in `semantic_rules.dl` → derived atoms into routing. R-G2 ⚠️DET (critical — Datalog now affects output): stratification check on load; canonical atom order set→list + tie-break on equal priority-max; per-turn cache; determinism test ×10. R-G3 weights→`RoutingWeights`(II). R-G4 flag `derivedInferenceActive`, re-bless golden. Anti-rot: yes.

### WP-H1 — ExternalLLM cache/Deferred `[#5]` · L · dep corpus + M2
- R-H1a authoritative: allowlist + ⚠️DET append-only cache with replay-from-cache. R-H1b if not enabled — document explicitly that the learning loop is dead. R-H1c ADR activation criterion. R-H1d full word acquisition requires **M2** (else learned forms stay noun/singular/0.55).

### WP-I — Rename campaign · Tier-0:S / Tier-1:S/M+migration · dep A(Tier-1)
Rename only the **residual** after A…H/M (if M2/E make a type real, keep its name).
| Now | Candidate | Tier | Risk |
|---|---|---|---|
| `Core.Consciousness` (module) | `StanceClassifier` | 0 | imports+exposed-modules |
| `Core.Dream` (module) | `TopicDrift` | 0 | imports+exposed-modules |
| `Core.Spectral` (if not wired) | `ContentCluster` | 0 | imports+exposed-modules |
| `Counterfactual` (newtype ToJSON; field `fieldCounterfactual`) | `ParseEntropy` | **1** | **breaks JSON/replay** |
- R-I1(Tier-0) compiler-checked, safe. R-I2(Tier-1) stable wire-format (`fieldLabelModifier`/custom instances) OR migration via versioned `fromJSON` (R-A1). R-I3 ADR rename-migration policy.

---

## 6. TRACK II — Substrate / SQL-GF (R-M3e = relocation, staged)

> SQL is canonical (`check_generated_artifacts.sh`). GF is partially RGL-compositional already (`MoveDefine subj rel obj = mkS (mkCl …)`). F-11 proved runtime PGF. **Not corpus-gated.**

### M1 — SQL = single source of word data · S/M · churn:none
- R-M1a freeze SQL as canon; `Generated.hs`/`*.gf`/`paradigms.json` as derivatives of one pipeline. R-M1b Python → offline importer (freezable post-import). R-M1c `check_generated_artifacts.sh` green; provenance per X6.
- Acceptance: regeneration is byte-identical (or hashed snapshot).

### M2 — GF/RGL runtime morphology (= WP-J) · L · output · dep M1
The lever: solves open vocabulary, demotes pymorphy3.
- R-M2a put `ParadigmsRus/Eng` (RGL inflection) on the runtime path: `SQL(lemma+class) → GF/RGL → PGF`. R-M2b pymorphy3 → offline paradigm-class classifier (or GF smart-paradigms). R-M2c open vocab: new word inflected via RGL, not suffix heuristics/"этого объекта". R-M2d ⚠️DET PGF-load health-gate; deterministic linearization. R-M2e unblocks R-H1d.
- Alt J-b (rejected by default): call `services/morphology/server.py` → puts Python on runtime path; needs allowlist + append-only cache + README correction. **Recommend GF-RGL (J-a).**
- Acceptance: runtime correctly inflects a word absent from `Generated.hs`; pymorphy3 not on the live path.

### M3 — GF/PGF renderer, RELOCATION, staged (⊇ WP-H2) · L · parity-preserving · dep M3-slot→M2
**The existing Haskell-template output is the oracle; every step is mechanically verifiable as `GF(move) ≡ reference(move)`. Relocation does NOT change output → golden corpus does not churn (per-move re-bless only on accepted cosmetic diffs).**
- **M3.0 — Parity harness:** capture current Haskell-template output per `CanonicalMoveFamily × PropositionType × {RU,EN}` as reference.
- **M3.1 — Per-move GF parity:** GF concrete reproduces the reference string. Gate: `GF(move) ≡ reference(move)`.
- **M3.2 — Move-by-move fallback retirement:** on parity-gate pass, switch move to GF-primary, remove its Haskell branch; replay-gated.
- **M3.3 — Default-on + degraded-only:** all moves migrated → GF runtime default-on; residual Haskell = logged emergency fallback.
- **Staging:** (1) low-slot/fixed moves first (M2-independent); (2) RU before weaker EN, per-move gated; (3) slot-heavy moves after M2 or keep heuristic as degraded.
- **Honesty (record in THEORY/ROADMAP):** relocation deliberately does NOT raise the 14-family ceiling; gain = single source of truth + determinism + provenance + removal of hardcoded Haskell strings. Consistent with QxFx0's stated "not an LLM, narrow domains, deterministic by design." Open generativity stays explicit `Deferred`.

---

## 7. Cross-cutting requirements

- **X1. Anti-rot standard:** ADR + **rule #21 in `check_architecture.sh`** + HUnit registry of "disconnect consumer → test fails".
- **X2. Calibration extraction:** all magic constants → named `*Weights`/`*Thresholds` with provenance (pattern exists: `ConatusWeights`/`FieldHeuristics`/`SalienceWeights`); calibration = Phase II.
- **X3. Determinism checklist (⚠️DET):** Spectral eigen-order (C2), Datalog set→list+stratification+cache (G2), ExternalLLM append-only cache (H1a), retrieve top-k (B3), PGF-load+linearization (M2d).
- **X4. Governance:** append-only payload + versioned migration; gates green; ADR; update THEORY/ROADMAP.
- **X5. CognitiveSignals seam (WP-S)** before D/E.
- **X6. Word-gen provenance:** pin `pymorphy3`/`spacy` to exact versions + snapshot OpenCorpora; provenance (versions/source hash) in artifact headers; pipeline pinned in Nix/flake; README correction: "runtime is data-dependent on an offline Python generation pipeline; M2-J-b would put Python on the runtime path".

---

## 8. Sequence

```
Track I:  F → B → A → S → D → E → H3 → C → G → H1
Track II: M1 → M3.0 → M3.1/M3.2 → M3.3   (parallel; M2 alongside)
Cross:    M2 → H1(live);  A → I(Tier-1);  H3 → C(output);  M3-slot → M2
X1 (anti-rot gate #21) before first wire (B/M1)
Phase II (needs corpus F-09/F-10): calibration A/E/F-angst/C-thr/G/H1.  M3 relocation NOT corpus-gated.
```

## 9. Definition of Done

1. 0 write-only cognitive fields (living reader + anti-rot test, or removed).
2. 0 exposed cognitive modules with zero importers.
3. Degenerate/mis-scaled values (Atmosphere, Essence-floor) fixed + guard tests.
4. All touched constants in calibratable records with provenance.
5. Each deferred path: enabled with proven behavior change, or explicit `Deferred` + anti-rot.
6. Names match implementation (WP-I).
7. Track II: SQL canon + provenance (X6); GF/RGL runtime morphology (M2); GF renderer with move-by-move fallback retirement (M3, relocation).
8. All gates green (incl. #21); ADR per WP/M + anti-rot + rename-migration.

## 10. Appendices
- **A. Constants registry:** `ConatusWeights`/`FieldHeuristics`/`SalienceWeights`/`EssenceThresholds`/`UserModelWeights`/`RoutingWeights`/`PerspectiveWeights`/`EpisodicLimits`/`SurfacingParams`.
- **B. Rename Tier-0/1:** §5 WP-I.
- **C. GF migration sub-stages:** §6 M3.0–M3.3.

---
*Generated as the execution roadmap; the Status ledger (top) is the live progress record.*
