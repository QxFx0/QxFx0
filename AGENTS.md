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
    **Single intentional exception (2026-08-22 fact-check)**: the B2
    Control-A ablation hook `essenceCommitDisabled` / `caDisableEssence`
    (`Finalize/State.hs`, `computeNextEssence`) bypasses `shouldCommit`
    for the ablated control arm only; it is the one deliberate flag that
    can suppress commitment, so the "no flag" thesis above means "no
    runtime feature flag", not "no flag exists at all".

  **Phase 7 (structural calibration infrastructure) completed 2026-05-18**:
  `FieldHeuristics` + 3 compute functions extracted from Phase-5.5d
  inline constants; `defaultSalienceWeights` lifeness property tests
  (range, monotonicity, Conatus-priority) landed in
  `Test.Suite.SelfField` and `Test.Suite.SelfSalience`.
  Empirical tuning against production trace corpora remains deferred.
  **2026-08-22 fact-check**: the current function set is the original
  three **plus** `computeAtmosphereDecoupled` (WP-E, preferred
  implementation) and the deprecated legacy `computeAtmosphere`
  (`Self/Field.hs`); the deprecated one is kept for compat and is
  superseded wherever decoupled selection applies.

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
  `psSelfVerdict` via `computeDoubt` (FieldConfidence complement,
  counterfactual-spread amplification, Conatus-gate floor).
  **2026-08-22 fact-check**: shadow-Datalog divergence is **not** part
  of `computeDoubt` — shadow disagreement is a separate
  `CognitiveSignals` channel (`csShadowDisagreement`,
  `Finalize/Projection.hs`). Doubt-driven routing: doubt ≥
  `doubtSuppressionThreshold` (**0.75**, `ConsciousnessLoop.hs`; also
  the explicitness-reduction threshold in `SensePlan.hs`) → CMClarify
  family override. Explicitness modulation: high doubt
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
    `RuntimeInfrastructure.hs:1476` — **RESOLVED (2026-08-08)**: all four
    test suites (`qxfx0-test`, `-fast`, `-property`, `-integration`)
    built and linked clean on GHC 9.6.6 back then. **Superseded
    (2026-08-22, П1 of the audit ТЗ)**: the toolchain contract is now
    **GHC 9.6.7 / base 4.18.3.0** with `index-state` pinned in
    `cabal.project` — see `docs/closure/ENV_CONTRACT.md` (Toolchain
    contract section) for the authoritative version.

  **M4-SEMANTIC-CORE-003 Phase C cutover (2026-06-18)**: semantic-first
  path is now PRIMARY for ALL input. `isCoveredTopic` gate removed from
  `Render.hs` — semantic-first fires for any non-unknown intent when
  morphology is ready. Uncovered topics receive category-typed generic
  predicates (not universal templates). Old assembly/template paths
  remain as fallback. `trcContentSource` trace field records content
  origin: `covered_exact`, `covered_generic`, `uncovered_generic`.

  **Phase E Revision + Network Seeding (2026-06-18)**: contradiction-driven
  revision pipeline completed. `revisePosition` determines revision action
  based on self-state: high angst (>0.7) → RcRevised (confidence decay 0.9),
  low conatus (<5.0) → RcQuarantined (move to quarantine), stable → RcRetained.
  **SUPERSEDED by Anomaly v3.0 (2026-08-22 fact-check)**: the production
  revision path is `defendOrAdapt` (`Semantic/Stance.hs`, called from
  `Finalize/State.hs` ~:683); `revisePosition` is a test/back-compat
  wrapper over it (its own docstring says so), and the angst/conatus
  thresholds above describe the retired v1 mapping.
  `applyRevisionDecision` applies decisions to `SemanticCommitmentStore` with
  full lineage tracking (LineageRevised events, ContradictionEvent records).
  Integration test verifies pipeline fires when `ceContradicted = True`.
  `seedFromCorpus` creates initial `SemanticNetwork` from `definitionCorpus`
  (**120 topics** as of 2026-08-22, `Semantic/Content.hs` — the historical
  "34" grew with the corpus; edges between topics sharing atoms, explicit
  edge weight = `sharedCount / 10.0`, not a flat 1.0 — flat 1.0 remains
  only for synonym-type `TopicRelations`), ensuring `contentDensityGate`
  (≥50 edges, ≥15 nodes) passes from first turn. `emptySystemState` now
  initializes `ssSemanticNetwork = seedFromCorpus` instead of empty network.
  `mergeSemanticNetworks` merges seeded network with runtime MeaningGraph edges
  (union of nodes, update-wins for edges, preserves base decayRate/maxHops),
  preventing seed overwrite on each turn. All 1319 tests pass
  (historical count at the 2026-06-18 landing; current per-suite counts
  below).

  **Topic normalization fix (2026-06-19)**: semantic predicates now surface
  in live sessions. Root cause: `extractTopicAfter` in `Intent/Classifier.hs`
  did not strip trailing punctuation, so `"что такое свобода?"` produced
  topic `"свобода?"` instead of `"свобода"`, causing `lookupDefinitionContent`
  to return `Nothing`. Fix: added `T.dropWhileEnd` for `?!.,;:` in
  `extractTopicAfter` and `extractTopic` (Frame/Builder.hs). Verified:
  `"что такое свобода?"` now returns `"Известно, что свобода — свобода
  предполагает возможность выбора. свобода ограничена ответственностью."`

**Per-predicate selection (2026-06-19)**: ContentSelector теперь выбирает
предикаты индивидуально, а не всем набором топика. Ранее `selectPredicates`
возвращал все предикаты топика с одним aggregate score. Теперь каждый
предикат оценивается отдельно через `scorePred`, вычисляя cosine similarity
между вектором предиката и Field-прототипами. Это позволяет разным
Field-состояниям выбирать разные предикаты для одного топика. Например,
для "истина" при высоком Confidence выбирается "претендует на соответствие
реальности", при высоком Counterfactual — "проверяется через
воспроизводимость". Тест "different Field selects different predicates for
same topic" подтверждает архитектурное расширение. **Калибровка выбора**:
в живой сессии все предикаты проходили порог 0.1 из-за широких прототипов
в seeded network. Изменено на выбор top-1 предиката (максимальный score)
вместо фильтрации по порогу. Это гарантирует детерминированный выбор
одного предиката, наиболее релевантного текущему Field-состоянию.
**Инициализация**: ContentSelector инициализируется в Bootstrap.hs из
seedFromCorpus и definitionCorpus (не в System.hs из-за циклического
импорта). `generateFromFrame` теперь принимает ContentSelector, Field и
SemanticNetwork, использует selectPredicates для выбора предикатов.
Все 1320 тестов проходят. Живая сессия: "что такое истина?" → "Известно,
что истина — истина претендует на соответствие реальности." (один предикат).

**Spreading activation composition (2026-06-19)**: Реализована полноценная
композиция предикатов из нескольких топиков через spreading activation
по спецификации Axis 2. `activateTopic` активирует все атомы топика
одновременно в SemanticNetwork. `composeFromActivation` находит все топики
с пересекающимися активированными атомами, для каждого выбирает top-1
предикат (через `scorePred` с учётом активации), взвешивает по доле
активации топика, возвращает top-3 предиката отсортированных по весу.
Интегрировано в `generateFromFrame`: при наличии SemanticNetwork используется
`composeFromActivation`, иначе fallback на `selectPredicates`. Это позволяет
комбинировать предикаты из разных топиков, связанных через атомы (например,
"свобода" → "ответственность" через общие атомы). Добавлены 6 тестов для
`composePredicates` и `composeFromActivation`. Все 1333 теста проходят.

**Contradiction synthesis (2026-06-19)**: Axis 2.3 завершён. Добавлены типы
`ResolutionType` (Conjunction / Irreducible) и `SynthesizedResolution` в
`Semantic/Revision.hs`. Функция `synthesizeResolution` синтезирует резолюцию
из двух противоречивых commitment'ов: >=2 общих атомов → Conjunction
("X, и вместе с тем Y", confidence 0.5), <2 общих → Irreducible
("X и Y несовместимы в текущей рамке", confidence 0.3). Оба получают
`OriginSynthetic` (новый конструктор `CommitmentOrigin`). Интегрировано в
`applyRevisionDecision`: ветка `RcRevised` с `Just newPayload` вызывает
`synthesizeResolution` и добавляет синтезированный commitment в store.
`applyRevisionDecision` теперь принимает 4-й аргумент `Maybe FactualClaimPayload`.
Finalize/State.hs передаёт `mClaimPayload` при вызове. Добавлены 3 теста:
Conjunction (>=2 shared atoms), Irreducible (<2 shared atoms), интеграция
с `applyRevisionDecision` (synthesized commitment в active store). Все 1333
теста проходят.

**GPT-аудит Axis 2.3 (2026-06-19)**:
- **Блокер 1 (исправлен)**: `applyRevisionDecision` использовал
  `CommitmentId (size active + size quarantine + 1)` вместо `scsNextId`.
  При удалении/карантине коммитментов возможны коллизии ID. Фикс:
  `nextCid = CommitmentId (scsNextId store)`, `scsNextId = scsNextId store + 1`.
- **Блокер 2 — FIXED (verified 2026-08-22)**: `mClaimPayload` больше не
  попадает в `synthesizeResolution` под suppress — `Finalize/State.hs`
  (`admittedClaimPayload`) передаёт payload только при
  `CsaAdmitCanonical`, иначе `Nothing`.
- **Блокер 3 — FIXED (verified 2026-08-22)**: `fcpTopic` опционален в
  `FromJSON` (`Types/State/SemanticCommitment.hs`:
  `o .:? "fcpTopic" .!= ""`); старые persisted stores декодируются.
  Остаточный риск: миграция production-сторов с пустым топиком требует
  обратной заливки топиков — считать открытым только для production
  миграций, для development закрыт.
- **Блокер 4 — FIXED на уровне трейса (verified 2026-08-22)**:
  `trcAnalogicalSource` (`Types/TurnProjection.hs`, заполняется в
  `Route/Render.hs` через `analogical_source=` тег) маркирует
  analogical-происхождение в replay-трейсе. In-band маркера в самом
  ответе пользователя нет — осознанное ограничение (маркировка только
  в governed-evidence трейсе, не в surface).

**Anomaly Architecture v3.0 completed (2026-06-19)**:
- **Revision Slice (Layer 3)**: Full implementation with graded trajectory.
  `reviseStance` now implements confidence-based revision: confidence > 0.7 →
  `StanceDoubted` (reduce confidence by 20%), confidence ≤ 0.7 → `StanceRevised`
  (full revision to new position). This replaces the simple 3-threshold system
  from Layer 1 with a nuanced defense mechanism that respects the system's
  confidence level.
- **SelfReferentialCollapse (Anomaly-3)**: Implemented in
  `Core/TurnPipeline/Route/Anomaly.hs`. Triggered when system encounters
  self-referential questions at high angst (>0.9). Gate (2026-08-22
  fact-check): subject matched by **substring** (`T.isInfixOf`) against
  **8 subjects**: `["я", "ты", "qxfx0", "система", "i", "you",
  "myself", "yourself"]` ∧ angst > 0.9. Causes Essence reset with full
  trace recording.
- **AntiConatusChoice (Anomaly-2)**: Implemented in
  `Core/TurnPipeline/Route/Anomaly.hs`. Triggered when move would weaken
  system's position. Gate: stanceConfidence > 0.7 ∧ ¬stanceConsistent ∧
  angst > 0.8 ∧ conatus < 5.0. Fixed `stanceConsistent` to properly detect
  inconsistency (StanceDoubted with high confidence is inconsistent).
- **evidenceWeight formula**: Updated to v3.0 specification:
  `argumentStrength = novelty × relevance`. Novelty is fraction of atoms not
  seen before. Relevance combines size relevance (70%, based on challenge size
  up to threshold of 5 atoms) and context relevance (30%, overlap with seen
  evidence). This replaces the old 70% novelty + 30% momentum formula.
  **2026-08-22 fact-check**: `evidenceWeight` lives in
  `Semantic/Stance.hs` (~:90–109), not in `Anomaly.hs`.
- **Governed Slice integration**: `buildRouteTurnPlan` now accepts `Maybe
  Anomaly` parameter. When anomaly is detected, `tpAnomalySurface` and
  `tpAnomalyTrace` are populated. Render phase uses `renderAnomalySurface` to
  generate user-facing messages for each anomaly type (Unclassifiable,
  AntiConatus, SelfReferential, Temporal).
- **Test coverage**: 1370 tests passing (historical count at the
  2026-06-19 landing; current per-suite counts below). Added tests for
  `reviseStance` graded trajectory (3 tests), anomaly rendering (4 tests).
  Updated `evidenceWeight` tests for new formula. Threshold for StanceDoubted →
  StanceRevised transition adjusted from 0.7 to 0.6 to account for new
  evidenceWeight formula producing lower values.

**Anomaly Architecture v3.0 — Skeptical Audit Fixes (2026-06-19)**:
- **evidenceWeight formula corrected**: Now returns `1.0 - argumentStrength * 0.3`
  per v3.0 specification. Range: [0.7, 1.0] where lower means stronger challenge.
  Previously returned raw `argumentStrength` (inverted semantics).
- **defendOrAdapt threshold corrected**: Now uses `weight < 0.88` for strong
  challenge detection (inverted from `weight > 0.6`). Aligns with spec: low weight
  = strong challenge.
- **recoverStance wired into pipeline**: Now called in `Finalize/State.hs` after
  `incrementRecoveryCounter`. StanceDoubted → StanceHeld recovery when counter
  exceeds `rwTurnsSinceLastChallenge` threshold.
- **Collapse → collapseEssence integration**: When `defendOrAdapt` returns
  `Left Collapse`, Finalize now calls `collapseEssence` to reset Essence trajectory
  (clears witnesses, resets angst/conatus floor). Previously only quarantined
  commitments without Essence reset.
- **Render texts rewritten as acts**: All anomaly surfaces now render as first-person
  acts ("Я выбираю не отвечать", "Я не буду продолжать", "Я пересматриваю") instead
  of meta-comments ("Система обнаружила", "Я заметил"). Removed anglicism "destabilize".
- **selectFarthestPoint integrated**: `renderAnomalySurface` now accepts
  `ContentSelector`, `Field`, and current atoms. For `SurfaceUnclassifiable`,
  attempts to find farthest predicate from current stance and includes it in
  response ("Я предлагаю рассмотреть: ...").
- **Test updates**: All tests updated for new signatures and semantics. 1370 tests
  (historical; current counts below)
  passing.

  **A-slice (deterministic self-divergence contour) completed 2026-08-07**:
  `QxFx0.Self.SelfDivergence` implements the pure morphisms
  predict -> witness -> diff -> allergen -> Conatus
  (`predictSelf` / `measureDivergence` / `selfConsistencyPenalty` /
  `windowMeanDivergence`; carriers in
  `QxFx0.Types.Self.SelfDivergence`). `ConatusComponents` gained a 5th
  field `ccSelfDivergence` (custom ToJSON/FromJSON, backward-compat
  default 0.0) and the invariant `ceScalar == sum of all five
  components` holds after penalty application. Pipeline wiring: A2.3
  `Prepare/Effects.hs` computes `conatusEnergy0` + conditional
  `selfConsistencyPenalty` (gated on prior-turn `selfLastDivergence`,
  `sdtThreshold`), `PrepareStatic`/`TurnInput` carry
  `psSelfPrediction`/`tiSelfPrediction` + `psSelfDivergencePenalty`;
  A2.4 `Finalize/State.hs` measures divergence against the prediction
  and updates `selfLastFieldObservation`/`selfLastDivergence`/bounded
  `selfDivergenceWindow` in `SelfState`; A2.5 traces
  `trcSelfDivergenceTotal`/`trcSelfDivergencePenalty`/
  `trcSelfDivergenceWindowMean`/`trcSelfDivergencePredictionActive` in
  `TurnReplayTrace`. Penalty is an energy /fraction/
  (`penalty = -(sdtScaling * total * ceScalar)`), WP-F unit-mismatch
  aware. A3: `currentMathVersion = 2` (RuntimeRegime). A4: anti-rot
  suite `Test.Suite.SelfDivergence` (determinism, steady-state zero
  divergence, clamp, threshold gating, component invariant, window
  mean) registered in cabal + TestMain/TestMainUnit/TestMainFast.

  **B-slice (Essence soft rupture, single canonical collapse branch)
  completed 2026-08-07**: `Self/Essence.hs` gained the canonical
  total morphism `collapseEssenceAt :: Int -> Essence -> (Essence,
  EssenceResetEvent)` (BD2 single-branch rule). **Every runtime reset
  goes through it**; a reset is either visible as an
  `EssenceResetEvent` or it never happened. `AnomalyStateEffect`
  became `ResetEssence !Essence !EssenceResetEvent` (carries the full
  canonical result). The pentagon-collapse path
  (`Finalize/State.hs` "Phase F") no longer drops the event: it stores
  it in the new `SelfState.selfLastEssenceResetEvent`, surfaced as
  `trcEssenceResetEvent :: Maybe EssenceResetEvent` on the replay trace
  (JSON backward-compat `Nothing`). Soft rupture (reset + resume) stays
  distinct from the hard `EssenceRupture` exception (`validatePlan`,
  aborts before persistence). BD3 reachability: under sustained
  hemispheric advantage with out-of-envelope divergence, angst crosses
  the 0.75 threshold **exactly on turn 15** (never before turn 14), and
  a post-collapse trajectory recommits inside the same 14-15 window.
  Pinned by `Test.Suite.EssenceCollapse` (BD2 totality + BD3
  reachability/recommit), registered in cabal + all three TestMains.
  See `docs/closure/ESSENCE_SOFT_RUPTURE.md`.

  **Self-divergence window drop-oldest fix (2026-08-22, П2 of the
  audit ТЗ)**: the bounded `selfDivergenceWindow` was maintained by
  appending the newest sample at the END and `take`-ing from the FRONT,
  so once the window filled (8 entries) the newest divergence never
  entered it and `windowMeanDivergence` / `sustainedDivergenceExceeds`
  (the `RecoverySelfDivergence` / `StrategySelfReanchoring` trigger)
  evaluated stale data forever. Fix: canonical total morphism
  `pushDivergenceSample` (`Self/SelfDivergence.hs`) — prepend newest,
  keep the `sdtWindow` most recent samples, evict the oldest; wired in
  `Finalize/State.hs`. Constants (`sdtThreshold`/`sdtScaling`/
  `sdtWindow`) unchanged; schema unchanged (same list shape).
  Anti-rot: `Test.Suite.SelfDivergence` (newest-always-present
  property, calm-then-divergent recovery regression, drop-oldest unit)
  plus the existing `TurnPipelineProtocol` integration pin.

  **П4.3 SemanticSlices reactivation (2026-08-22, audit ТЗ)**: the
  `Test.Suite.SemanticSlices` suite (14 tests) was born dead — committed
  importing `withFakeNixInstantiateForConcepts` /
  `withFixedRuntimeTime` helpers that never existed in `Test.Support`,
  so it never compiled at any commit. Reactivated in `qxfx0-test-fast`;
  the dead runner `TestMainSemanticSlices.hs` is deleted. Two rot fixes
  were required to make it green. (1) The raw `loadStateWithVersion` +
  `Runtime.runTurn` scenario paths skipped production's restore step
  (`mergeMorphology` in `Bootstrap.hs`): persisted state JSON does not
  carry the morphology resource, so the commit-time self-blanket failed
  closed with `BlanketEmptyMorphology` (`IdentityRupture`) in every
  load-scenario session; the test now re-attaches a process-shared
  runtime morphology before running turns, and `mergeMorphology` is
  exported from Bootstrap for exactly this contract. (2) The
  blocked-concepts fixture probed "смерть", which sits in
  `philosophicalTopicWhitelist` (`NixGuard.hs`) and is Allowed without
  ever consulting nix; the fixture now uses the non-whitelisted
  "запрет" so the fake constitutional guard actually blocks. Suite:
  14/14 green; failures were proven pre-existing (identical with the
  П2/П3 runtime changes reverted).

  **C-slice (self-divergence recovery envelope) completed 2026-08-07**:
  the A-slice divergence signal now drives the local recovery machine.
  New `RecoverySelfDivergence` cause (`LocalRecoveryCause`) and
  `StrategySelfReanchoring` strategy (`LocalRecoveryStrategy`),
  rendered `self_divergence` / `self_reanchoring`. Pure morphism
  `sustainedDivergenceExceeds :: SelfDivergenceTuning -> [Double] ->
  Bool` gates the branch (non-empty `SelfState.selfDivergenceWindow`
  with window mean strictly above `sdtThreshold`). Wired into
  `buildLocalRecoveryPlan` (Route/Render.hs) between the structural
  Conatus gate and WP3 learning-need recovery; severity ladder seats
  `RecoverySelfDivergence` at 90 (above `RecoveryLearningNeed` 85,
  below `RecoveryConatusGate` 100) in `Self/Deliberation.hs`. The
  turn surface narrows to the predicted (stable) contour instead of
  amplifying the current drift — "the system now notices itself,
  not only its shadow." Distinct from `RecoveryShadowDivergence`
  (shadow runtime) and `RecoveryConatusGate` (energy). Anti-rot:
  PhaseM2d render/JSON cases, SelfDivergence threshold/empty-window
  cases, SelfDeliberation severity ordering, TurnPipelineProtocol
  integration (window override drives the cause; fresh state does
  not). No trace-schema change (`trcRecoveryCause`/`Strategy` already
   carry it); no math version bump.

  **M6-FELT bounded benchmark PROVEN (2026-08-08)**: the mechanical
  felt-evidence gate now records `M6FeltProven` on the 12-turn bounded
  benchmark session (`Test.Suite.M6FeltBenchmark`; evidence
  `feTurnCount = 12, feFinalCommitmentCount = 12, feDistinctFocuses = 5,
  feRepairTurns = 2`). All 12 turns render on the semantic core path
  (`covered_exact`/`AuthorityCanonical`/`CsaAdmitCanonical`/
  `EvidenceGoverned`, no fallback); challenge turns 7-8 register genuine
  commitment contradiction → revision. Blocker closure came from runtime
  defects, not GF linearizer coverage: `extractTopicAfter` now matches
  "что такое" anywhere in the utterance; `normalizeIntentTopics`/
  `canonicalTopic` lemmatize topic and distinction surfaces via full
  morphology ("ответственности"/"ответственностью" → "ответственность");
  `comparisonCandidates` gained the `связан`-linkage branch and `связан`
  is a comparison mark; "контрпример"/"докажи"/"что если" are challenge
  marks in both the classifier and `Effects.hasChallengeMarker`;
  `Semantic.Retrieve` gained `engagementTopicFor` and contradiction is
  scoped via the engagement topic (best topic ++ content nouns);
  `trcContentSource` is classified from the response-plan topic. The
  recorded-verdict test now asserts `M6FeltProven` + contour minima
  (12 turns, ≥1 revision, ≥4 focuses, ≥1 repair) — a regression must
  fail with a precise gate list again. Full M6-FELT status still needs
  the B2 human-eval leg. See `docs/closure/M6_FELT_GATE.md`.

  **Substrate Network (2026-06-20)**: Two-layer knowledge graph enrichment.
  - **Explicit layer**: from `seedFromCorpus` (definitionCorpus
    predicates); edge weight is `sharedCount / 10.0`
    (`Network/Seed.hs`), flat 1.0 only for synonym-type `TopicRelations`.
    The historical "30 topics / ~50 edges" described the 2026-06-20
    corpus; `definitionCorpus` has since grown to **120 topics**
    (2026-08-22 count), so node/edge counts scale with the corpus.
    Only source of output.
  - **Substrate layer**: same topic set, weight 0.3,
    from `buildSubstrateEdges` (brain_kb co-occurrence in triggers).
    Routes spreading activation only, never appears in output.
    **2026-08-22 fact-check**: `brain_kb.jsonl` is NOT in the repository
    (gitignored data source, `Substrate.hs` `loadBrainKB` returns `[]`
    when the file is absent) — on a fresh clone the substrate layer is
    silently empty and only the explicit layer routes. Restoring the
    file (53K entries, external source) or documenting its origin is an
    open ops task.
  - **Integration**: `Bootstrap.hs` loads `brain_kb.jsonl`, builds substrate
    edges, merges into `SemanticNetwork` (explicit wins at same key).
  - **Data source**: `brain_kb.jsonl` (53K entries), filtered by
    `layer ∈ {ontology, dialogue, metaphor, dialog_moves, human_signals}`
    and `≥2 philosophical triggers` via substring match.
  - **Trace observability**: `trcSubstrateActivated`, `trcSubstrateEdgesUsed`
    in `TurnReplayTrace`.
  - **Module**: `QxFx0.Semantic.Network.Substrate`.
  - **Tests**: `Test.Suite.SubstrateNetwork` (6 tests).
  - **Doctrine**: substrate + activation is multi-hop associative traversal over
    explicit predicates, not inference or reasoning. The substrate does not create
    knowledge or derive new predicates; it opens non-obvious paths to existing
    explicit predicates under governed retrieval. Relation Graph is deferred until
    a curated relation corpus exists; it must not be reconstructed by regex over
    reflective `brain_kb` prose.

**Concept v3 two-protocol regime (2026-08-23)**: the first three
slices of the concept-v3 re-centring are law-driven and unconditional
(no feature flag — ADR-0034 §3 Rule 5, mechanized as FOLLOWUPS.md
Rule [15], keeps only `Bridge.ExternalLLM` flag-gated; there is no
ADR-0013 — that number was retired in the 0013-collision renumbering):

- **Protocol B crisis guard** (`Safety/CrisisGuard.hs` +
  `Types/Safety/Crisis.hs`): high-precision hard lexical gate
  (`acuteCrisisMarkers`, RU+EN: «не хочу жить», «покончить с собой»,
  «суицид», self-harm, "kill myself", …). `decideProtocol` resolves
  the two-protocol verdict: a hard trigger forces Protocol B
  **regardless of any score** («ворота не доверяют модели»); without
  a trigger only a viability-contour exit can. `renderCrisisSurface`
  is the bounded honest response carrying the real resource pack
  (`crisisResourcesRu`, version 1: 112 + детский телефон доверия
  8-800-2000-122). **Ops duty**: resource lines must be re-verified
  periodically; bump `crVersion` on any change. Wired in Prepare
  (`buildPrepareEffectPlan`), Route (`tpCrisisSurface`), Render
  (`buildTurnArtifacts` overrides every other surface, anomaly
  surfaces included).
- **User-side R5** (`Types/User/R5.hs` + `User/R5.hs`): `UserR5State
  ∈ ℝ⁵` (renamed from the concept's `R5State` — that name is taken
  by `Types/Dream`; axes mirror the system `Field` but the subject is
  the **system-human**, never conflated with the self-Field). Encoder
  v1 (`encodeR5`) is linear, interpretable, frozen-on-release
  (hand-set constants; offline fitted replacement requires a
  `currentMathVersion` bump). Linear viability contour
  (`userConatusScore`, `defaultViabilityContour`: absoluteFloor 0.05,
  personalMargin 0.25, EMA baseline window 10, residual window 8) +
  EMA personalization (`updateUserBaseline` — one extreme utterance
  cannot redefine the norm). Persisted carry `ssUserR5Contour`
  (JSON backward-compatible). Residual audit is the user-side clone
  of the A-slice pattern: `predictNextUserR5` (v1 = persistence
  hypothesis — identity, honest about no learned transitions yet),
  `r5Distance` predicted-vs-observed, bounded `pushR5Sample` window.
- **Ontological layer** (`Types/Semantic/OntologicalAxis.hs` +
  `Semantic/Ontological.hs`): `classifyOntological` projects the
  utterance onto three category pairs (Бытие/Небытие,
  Стремление/Отрицание, Утверждение/Разрушение), each in [-1,1],
  total-count normalized (philosophical questions carry **no**
  ontological act; philosophical pessimism is being−, not a crisis).
  Negation-safe via blank-then-count («не хочу» is striving−, never
  striving+). `ontologicalMoveAdmissible` +
  `resonanceGateThreshold` (0.55) is the pure resonance gate the
  future move graph consumes: mirror the state → establish resonance
  → only then the ontological move.
- **Trace**: `trcCrisisProtocol` / `trcUserR5` /
  `trcOntologicalVector` on `TurnReplayTrace` (JSON backward-compat
  `Nothing`). Governance: `currentMathVersion` bumped 2→3.
- **Anti-rot**: `Test.Suite.CrisisGuard` / `Test.Suite.UserR5` /
  `Test.Suite.OntologicalAxis`, registered in shared `test-common`
  + all three TestMains. Pinned concept edge cases: «мне всё надоело»
  stays **inside** the contour (Protocol A); an exhaustion pile-up
  exits; decoys (философский пессимизм, чёрный юмор, «камю писал о
  самоубийстве как проблеме философии») never fire the hard gate;
  the bounded surface always contains real resources and never
  directive patterns.
- **Move graph (2026-08-23, steps 4–6)**: generation-as-search landed
  as a leading layer, not a replacement (staged cutover — the
  corpus-backed semantic-first path and M6-FELT are untouched).
  `Types/Semantic/MoveGraph.hs` + `Semantic/MoveGraph.hs`: a closed
  ordered set of four operators (MoveMirrorState →
  MoveEstablishResonance → MoveAffirmBeing → MoveOpenAlternative),
  a frozen v1 effect matrix Δ on the R5 axes, the connected-calm
  target S* (res 0.65 / atm 0.20 / mid others, baseline-anchored
  confidence), and `planOntologicalMove` — a total deterministic
  search for the operator with minimal predicted `r5Distance` to
  S*. The §5 ordering (mirror → resonance → affirm) EMERGES from
  the search: below the resonance gate `MoveAffirmBeing` is
  inadmissible and mirror/resonance dominate on their own merits.
  The layer fires only under Protocol A, and only when the input
  carries a negative ontological act or the score drifts below the
  personalized baseline by > `moveDriftMargin` (0.10). At render
  the move LEADS the turn with its act line
  (`QxFx0.User.Decompress.renderMoveLine`), decompressed for the
  receiver: under high pressure (atmosphere > 0.6) only the first,
  densest sentence survives (concept §7 concentrate). The
  transition model is now move-conditioned: `transitionUserR5` —
  `S_{t+1} = transition(S_t, move)` via the effect matrix,
  persistence without a move — so the residual audit measures
  whether the transition model is right, not just persistence.
  Trace: `trcOntologicalMove` (move tag, distances to S*
  before/after, gate state). Anti-rot: `Test.Suite.MoveGraph`
  (gate-inside-search, ordering emergence, best-admissible
  invariant, drift firing, decompression concentrate, totality).
  Corpus-level decompression (predicate choice per receiver) and
  offline transition fitting remain deferred (calibration phase).
- **Skeptical-audit closure P0–P1 (2026-08-23)**:
  * *P0-1*: the whole regime is committed (`4fc79f9` П-era
    comments, `aa638f7` concept-v3 regime, plus this fix commit).
  * *P0-2/P0-3 evidence gate*: the encoder's score conflates
    utterance form (question shape, topic continuity) with user
    state, so both the move-layer drift branch
    (`MoveGraph.moveNeeded`) and the relative contour-exit branch
    (`outsideViabilityContour`) are now gated by
    `negativeEvidenceEarned` (atmosphere > 0.30 ∨ confidence <
    0.45): a style-driven score drop (challenge after a definitional
    question) can no longer fire a move or a Protocol B exit; the
    drop must be earned by negative signals in the state itself.
    The absolute-floor branch needs no gate — v1 encoder arithmetic
    makes a sub-floor score unreachable without a distress pile-up.
    Pinned by tests in `UserR5`/`MoveGraph` (style-drop pin).
  * *P1-4*: the four regime trace fields collapsed into one
    sub-record `trcUserRegime :: Maybe UserRegimeTrace` (crisis,
    userR5, ontological vector, move, `urtEncoderVersion`) — sub-
    record discipline per the EffectSnapshot precedent; new regime
    fields grow the sub-record, not the god-record.
  * *P1-5*: the regime traces are no longer write-only —
    `TraceAnalysis.analyzeUserRegime` flags
    `user_contour_exit` (encoder-driven Protocol B; hard triggers
    are the law working, not an anomaly) and
    `user_model_high_residual` (residual > 0.35).
  * *P1-6*: all marker lexicons moved to the single canonical
    source `QxFx0.Semantic.Markers`; `User.R5` and
    `Semantic.Ontological` re-export (Intent/Features keeps its own
    pre-existing lexicons — folding them in is a separate change).
  * *P1-7*: GAPS.md stale "30 topics" marked; M6-FELT checklist
    line annotated with the 2026-08-23 green verification.
  * *P1-8*: `predictNextUserR5` deleted (superseded by
    `transitionUserR5`); `r5EncoderVersion` moved to Types and
    stamped per-turn in the trace.

- **Open follow-ups (not in this landing)**: corpus-level
  receiver-conditioned decompression via `fieldAwareRendering`;
  offline fitting of the encoder/effect matrix on a labelled 30–50
  utterance set; a learning-targets ADR for transition learning;
  absorption of the flag-off `ssUserModel` Bayesian niche.

## Test counts (updated 2026-09-08)

Per-suite HUnit case counts (QuickCheck properties included in the
suites that run them). `qxfx0-test` and `qxfx0-test-integration` were
re-verified green on 2026-08-23 after the audit-follow-up landing
(1304 / 46, 0 errors / 0 failures each); `qxfx0-test-fast` re-verified
green 2026-09-08 after the arch-gate fix landing (1812 cases,
0 errors / 0 failures, ~20 min wall-clock locally, ~3.1 GB max heap
residency, 23 session bootstraps at ~9 s median — the "sub-30s sanity
gate" phrasing is retired; see execution board item 6):

| Suite | Cases |
|---|---|
| qxfx0-test | 1304 |
| qxfx0-test-fast | 1812 |
| qxfx0-test-unit | 1491 |
| qxfx0-test-property | 227 |
| qxfx0-test-integration | 46 |
| qxfx0-test-slow | see below |

The historical single numbers (1319 / 1320 / 1333 / 1370 / 1239)
inside the dated sections above are landing-time records, not current
state. The 1239→1304 growth is concept-v3 (+56, landed 2026-08-23
before this count) plus the audit follow-up below (+9).

**Audit follow-up landing (2026-08-23)**: (1) the ADR-0013 dangling
reference corrected to ADR-0034 §3 Rule 5 / FOLLOWUPS Rule [15];
(2) GAPS.md 311/312 totals annotated as curation-inventory numbers
(runtime corpus is 120 topics); (3) empty-substrate bootstrap now logs
a WARN (`brain_kb.jsonl loaded 0 entries…`) instead of degrading
silently, and `loadBrainKB` has direct tests (missing path → `[]`;
JSONL parse with bad-line skip); (4) dead suite
`Test.Suite.RenderAuthorityStub` deleted (superseded by
`Test.Suite.AuthoritySurface`), born-dead `Test.Suite.
MorphologicalNormalization` (6 cases, HUnit) reactivated in
`qxfx0-test`; (5) `*_test_*.db` gitignore pattern covers root test
artifacts (`qxfx0_test_native_sqlite_nulls.db`); (6) the regime
stamps `trcRegimeVersion` / `trcFamilyDivergenceActive` /
`trcFamilyDivergenceOccurred` now read the LIVE session regime
(`ssCurrentRegime`) instead of the static `defaultRuntimeRegime`
(`Finalize/Projection.hs`, closing the "left for a separate pass"
note from the R4 morphology fix) — a restored session carrying a
foreign persisted regime now surfaces it verbatim in the trace;
regression pin `m5RegimeStampsLiveSessionRegime` in
`Test.Suite.M5Regime`. One-off flakiness:
the first 2026-08-23 `qxfx0-test` run showed 2 extra failures that
did not reproduce in two subsequent full runs (names not captured;
re-observe before treating as real).

## Hygiene (2026-08-22, П6 mini-section)

- `libHSqxfx0-0.1.0.0-inplace.so` was accidentally tracked at the repo
  root — untracked and removed; `libHSqxfx0*.so` and `*.qxfx0.db` are
  gitignored now (`R5Verdict.csv`, `ShadowAlert.csv`, `src/**/*.hi|o`
  and the test DBs were already covered).
- `brain_kb.jsonl` (substrate source, 53K entries) is NOT in the
  repository — see the Substrate Network fact-check above.

## Pointers

- Audit 2026-08-23 → session backup + open-debt register + forward
  plan: `docs/closure/AUDIT_FOLLOWUP_2026-08-23.md` (follow-up
  landing: substrate WARN + loadBrainKB tests, dead-suite cleanup,
  doc integrity, live-regime trace stamps; verification 1304/46
  green; fast/unit/property/slow rows stale pending re-run).
- Audit 2026-08-22 → closed by the six-point ТЗ (П1 toolchain 9.6.7,
  П2 self-divergence window, П3 selectPredicates totality, П4 test
  infrastructure, П5 B2 RU rater rubric + truthful metadata, П6 this
  sync). Landing commits: П4.2 `bc4398c`, П1 `57be6a9`, П2 `fb0c5f3`,
  П3 `a73ea0e`, П4.1 `508d8d7`, П4.3 `4051861`, П5 `85a21c6`.
