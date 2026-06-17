# QxFx0 Operator Notes

- Decision and response generation are local-first and deterministic.
- Runtime recovery is represented via local recovery trace fields (`trcLocalRecoveryPolicy`, `trcRecoveryCause`, `trcRecoveryStrategy`, `trcRecoveryEvidence`).
- Verification/release gates must keep replay envelope fields aligned with runtime contracts.
- ADR-0032 dialogue-development contours are live but conservative: outcome learning, speech policy, and claim-stance memory are separate; finalize/precommit persists updates; route reads speech policy; weak acknowledgement phrases are observational and must not trigger strong mutation without a shared `AdaptiveMutationRecord` in the bounded `ssAdaptiveMutationLog`.
- P4 perspective cognition is `OpinionCore / PerspectiveOperator`, not a raw store: `PerspectiveRegistry` is the canonical versioned lineage source, finalize/precommit emits `MutPerspective`, and replay/render may consume only `PerspectiveProjection`.
- The `QxFx0.Self.*` subtree is the pure self-layer of the dual-mode runtime. Landed phases:
  - **Phases 1–2** — `SelfBlanket` invariants and the `Conatus` functional (commits `62d0338`, `a5fad49`).
  - **Phase 3** — `Holistic ⊣ Formal` adjunction (ADR-0008, commit `20d5611`).
  - **Phase 4** — right-hemispheric `Field` record with five components (ADR-0009, commit `036f70f`).
  - **Phase 5** — salience controller (ADR-0010); **Phases 5.5d/5.5e** wire the pre-turn `Field` and trace observability.
  - **Phase 6 / M6.1** — single-source-of-truth Conatus refactor: `tiConatusEnergy` / `tiConatusGateFired` / `tiField` are computed once in `PrepareStatic` and shared across the turn.
  - **Phase 8** (Packages A/B/C/D) — deliberation framework (ADR-0011): `reconcile` replaces priority-switching in routing; Package C introduced observability-grade tone divergence; Package D corrected the adjunction caller mapping, removed `applySalienceEscalation`, and introduced family divergence control via two distinct flags: `salienceGuardDivergenceEnabled` (constant `True` in Cascade.hs, controls salience-modulated guards) and `reconcileFamilyDivergence` (dynamic in TurnRouting.hs, depends on self-verdict and family support).
  - **Phase 9–10 (essence commitment) landed 2026-05-19**: pure
    `QxFx0.Self.Essence` module with `Essence` Σ-type, `witness` /
    `shouldCommit` / `extractMode` / `commit` morphisms,
    `EssenceModulation` tunables, `validatePlan` post-commitment guard,
    trajectory threading through `SystemState` / `TurnInput` /
    `PrepareStatic`, four nullable trace fields in `TurnReplayTrace`,
    `EssenceRupture` exception in `QxFx0.ExceptionPolicy`,
    reconcile-time courtesy via optional predicate to `reconcile`.
    `essenceCommitmentEnabled` (designed in ADR-0012 §10.1 but **never
    implemented** — Essence is law-driven, not flag-gated). Essence is
    unconditionally active since 2026-05-19: `shouldCommit` evaluates every
    turn, `validatePlan` is reachable, `EssenceRupture` is a real
    exception. `rrEssenceActive = True` stamps the regime. Policy A
    (2026-06-17, `ESSENCE-REGIME-RECONCILE.md`) accepts this as structural
    runtime law; it is **not** M6-FELT evidence until SLICE-012 + a
    felt-evidence gate land.

  **Phase 7 (structural calibration infrastructure) completed 2026-05-18**:
  `FieldHeuristics` + 3 compute functions extracted from Phase-5.5d
  inline constants; `defaultSalienceWeights` lifeness property tests
  (range, monotonicity, Conatus-priority) landed in
  `Test.Suite.SelfField` and `Test.Suite.SelfSalience`.
  Empirical tuning against production trace corpora remains deferred.

  **WP-C (Content Saliency) completed 2026-06-04**: Spectral clustering
  wired into Salience controller as 6th contribution
  (`contribContentSaliency`). `computeSalience` signature extended with
  `contentSaliency :: Double` parameter (top-down signal from
  `computeContentSaliency` over `MeaningGraph`). Deterministic
  eigen-order via `sort` on graph nodes (R-C2). Flag
  `contentSalienceActive` promoted to default-on (True) in
  `QxFx0.Core.ContentCluster` as of 2026-06-04. Anti-rot tests in
  `Test.Suite.ContentSalience`. Calibration of `weightContentSaliency`
  (default 0.6) and `threshold` (0.1) deferred to Phase II corpus-driven
  tuning.

  **WP-D (Doubt Loop) completed 2026-06-04**: Metacognitive doubt loop
  closed. `tiDoubtScore :: Double` added to `TurnInput`, computed from
  `psSelfVerdict` via `computeDoubt` (FieldConfidence, counterfactual
  entropy, shadow-Datalog divergence). Doubt-driven routing: doubt ≥ 0.7
  → CMClarify family override. Explicitness modulation: high doubt
  reduces explicitness by up to 0.20. Anti-rot tests in
  `Test.Suite.DoubtLoop`. Outcome calibration (predicted success vs
  acceptance markers) deferred to Phase II.
  **WP-B (Episodic Recall) completed 2026-06-04**: Frame-driven episodic
  memory retrieval wired into routing pipeline. `tiRetrievedEpisodes ::
  [EpisodicEvent]` added to `TurnInput`, populated via `retrieve` with
  `ByTurnRange` query (last 20 turns). R-B4: `ssEpisodic` explicitly
  initialized (not lazy `Nothing`). R-B3: Behavioral influence via
  `hasRecentSystemDecision` — suppresses doubt-driven CMClarify override
  when recent system decision exists (don't re-ask established facts).
  Flag `episodicRecallActive` promoted to default-on (True) in
  `QxFx0.Memory.Episodic` as of 2026-06-04. Anti-rot tests in
  `Test.Suite.MemoryEpisodic` (6 tests). R-B2 (cue-ranking via
  `cosineSimilarity`) deferred to Phase II.
  **WP-F (Essence Threshold Unit-Fix) completed 2026-06-04**:
  `emConatusStructuralFloor` corrected from 0.5 (unit-mismatch against
  test generators) to 7.0 (production log-scale codomain of
  `ceScalar`). R-F2: Unit-guard property test in
  `Test.Suite.SelfEssence` enforces floor > 1.0 and floor < 14
  (healthy band), preventing regression to [0,1] scale. R-F3:
  Angst-trigger explicitly marked Deferred (ADR-0012 §15.1). Math
  version bumped to 1 in `RuntimeRegime.hs`.

  **P2-2 two-guard admission modules completed 2026-06-07**:
  `twoBranchChecks` generic helper added to `Test.Suite.AdmissionEquivalence`.
  Four modules with no PreserveAmbiguous branch pinned via
  `twoBranchChecks`: ComparisonPlausibility, DialogueInvitation,
  ExploratoryPrompt, GenerativePrompt. Additionally, `PropositionContactAdmission`
  (3-guard variant) and `PropositionPhraseDecisionAdmission`
  (FallbackType-based labels) converted and tested manually.

  **Pattern B (family→LowerConfidence admission) completed 2026-06-07**:
  Four modules tested with family→LowerConfidence pattern at
  `Test.Suite.AdmissionEquivalence:424–552`:
  RouteHintAdmission (single-item, 4 branches, 3 tests),
  PropositionAdmission (single-frame, 4 branches, 3 tests),
  SemanticFrameAdmission (single-frame, 2 tests),
  SenseVectorAdmission (single-vector, 4 branches, 3 tests).

  **Pattern C (family→CMClarify admission) completed 2026-06-07**:
  Five modules tested with family→CMClarify pattern at
  `Test.Suite.AdmissionEquivalence:563–749`:
  EarlyFamilyAdmission (3 tests), FamilyAdmission (4 tests, incl. conatus gate),
  SemanticLogicAdmission (3 tests), SemanticContributionAdmission (3 tests),
  InterpretationAdmission (3 tests, incl. FallbackClarify branch).
  Total: 16 new tests, all green.

  **Pattern D (Atom/Lexical/Structural admission) completed 2026-06-07**:
  Eight module triples pinned at
  `Test.Suite.AdmissionEquivalence:751–956`:
  AtomContributionAdmission (3 tests), AtomExtractionAdmission (3 tests),
  AtomFindingAdmission (3 tests), StructuralAtomAdmission (3 tests),
  LexicalClusterHitAdmission (3 tests), LexicalClusterMatchAdmission (3 tests),
  LexicalClusterPhraseAdmission (3 tests),
  LexicalClusterPhraseDecisionAdmission (3 tests).
  All 24 tests use authentic `MeaningAtom`/`AtomTag`/`RawAtomFindings`/
  `RawLexicalCluster*` fixtures; the soften-vs-filter distinction in
  PhraseDecision is tested via matched/unmatched flags.
  Total: 24 new tests, all green.

  **Observability: FamilyDerivationChain + GenerationTrace + FmarMode (2026-06-07)**:
  Three new `TurnReplayTrace` fields landed across 12 files (141 insertions):
  - `trcFmarMode :: Maybe FmarMode` — wired through `FINALIZE_TYPES_FMAR_MODE` from
    `Projection.hs` to `Dialogue.hs` render
  - `trcFamilyDerivationChain :: [FamilyDerivationEntry]` — populated in
    `Projection.hs` and `Route/Build.hs` from turn-time family resolution
  - `trcGenerationTrace :: [GenerationTraceEntry]` — populated in
    `Route/Build.hs` and `Route/Render.hs` from narrative generation
  - Aeson instances updated in `TurnProjection.hs`
  - `buildTurnProjection` signature extended with `FmarMode` argument
  - Test defaults updated in `StatePersistence.hs`, `TraceAnalysis.hs`,
    `ReplayDeterminism.hs`
  - Library builds clean; test-suite recompile blocked by pre-existing
    GHC 9.6 `BlockArguments`/`do`-in-pattern issue in
    `RuntimeInfrastructure.hs:1476`
