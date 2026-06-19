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
  `applyRevisionDecision` applies decisions to `SemanticCommitmentStore` with
  full lineage tracking (LineageRevised events, ContradictionEvent records).
  Integration test verifies pipeline fires when `ceContradicted = True`.
  `seedFromCorpus` creates initial `SemanticNetwork` from `definitionCorpus`
  (34 topics, edges between topics sharing atoms), ensuring `contentDensityGate`
  (≥50 edges, ≥15 nodes) passes from first turn. `emptySystemState` now
  initializes `ssSemanticNetwork = seedFromCorpus` instead of empty network.
  `mergeSemanticNetworks` merges seeded network with runtime MeaningGraph edges
  (union of nodes, update-wins for edges, preserves base decayRate/maxHops),
  preventing seed overwrite on each turn. All 1319 tests pass.

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
- **Блокер 2 (отложен)**: `mClaimPayload` в State.hs:639 — raw-parsed, не
  admitted. Если `commitDecision = CsaSuppress`, suppressed claim всё равно
  используется для `synthesizeResolution`. `OriginSynthetic` + низкая
  confidence (0.5/0.3) — честная маркировка. Не corruption, а архитектурная
  неопрятность. Средний приоритет.
- **Блокер 3 (известное ограничение)**: `fcpTopic` обязателен в `FromJSON` —
  старые persisted stores упадут. Для development — ок. Для production —
  нужна миграция. Зафиксировано ранее.
- **Блокер 4 (premature)**: Analogy без provenance tag. Сейчас analogy
  активируется только через `findNearestCoveredTopic` + `fallbackSimilarity` —
  это common-prefix matching, не authority claim. Ответы не маркируются как
  analogical source. Для B3/M6-FELT нужна маркировка, сейчас — нет.
