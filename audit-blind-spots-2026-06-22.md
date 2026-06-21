# QxFx0 Blind Spots Audit — 2026-06-22

## Метод

Полная инвентаризация всех ~420 нетестовых Haskell модулей. Каждый модуль прочитан (заголовок + экспорты + ключевые секции). Цель: найти слепые пятна в знании системы — модули и паттерны, которые предыдущие аудиты упустили.

---

## Найденные слепые пятна

### 1. Types/State/Governance.hs — 1117 LOC, незамеченный гигант

**Проблема:** Ни один предыдущий аудит не упоминал этот модуль, хотя он второй по размеру hand-written модуль в системе.

**Содержимое:** Полноценная event-sourcing система:
- GovernanceEvent, GovernanceEventEnvelope — typed event spine
- GovernanceDecision (8 вариантов: ObserveOnly, Quarantine, AcceptBounded, Promote, Freeze, Suspend, Rollback, Deny)
- GovernanceLifecycleStatus (6 стадий: Intent -> Evaluated -> Committed -> Denied -> RolledBack -> Archived)
- GovernanceActor (Runtime, Operator, OfflineGovernance, ReplayRebuild)
- GovernedSubject (Perspective, ClaimStance, Capability, CrossSessionCarry, Freeze, NormativeProfile)
- GovernanceProjection, ProjectionMeta, ProjectionVersion, ReducerVersion, EvaluatorVersion
- FreezeScope (Global, PerspectiveScope, Contour)
- RollbackPlan, GovernanceRuntimeFault, GovernanceSchemaEvolutionContract
- CapabilityModel, CapabilityEvidence, CapabilityEntry
- ConfidenceBand, ConfidenceSnapshot, DriftSignal, MetaEvaluationSignal
- BudgetWindow, StaleStatus
- GovernancePermission с governancePermissionAllowed
- canonicalizeGovernanceHistory, normalizeGovernanceEventChecked, validateGovernanceEventContract
- governanceProjectionChecksum, governanceProvenanceTrail
- Schema evolution contracts, replay ordering contracts, archive contracts

**Вывод:** Это не «1 governance модуль» из предыдущих аудитов. Это полноценная governance-инфраструктура, сопоставимая по сложности с TurnPipeline. Предыдущие аудиты говорили «Governance = 1 модуль, декоративный» — это глубоко неверно. Модуль определяет 40+ типов и 20+ функций. Вопрос: wired ли это в runtime, или это ещё один drafted-but-not-landed?

### 2. Semantic/Input/Assemble.hs — 1638 LOC, незамеченный гигант #2

**Проблема:** Ни один аудит не выделял этот модуль, хотя он третий по размеру в системе.

**Содержимое:** buildUtteranceSemanticFrame, buildUtteranceSemanticFrameMorph — сборка semantic frames из морфологических данных. Это входная точка всей семантической обработки: парсинг -> нормализация -> классификация -> сборка frame.

**Вывод:** Semantic/Input/ — это полноценный NLP pipeline внутри системы. Assemble.hs — его ядро. 1638 LOC в одном модуле — серьёзное SRP нарушение, сопоставимое с Render/Dialogue (2004 LOC).

### 3. SystemState — god record (~50 полей)

**Проблема:** Types/State/System.hs (757 LOC) определяет SystemState с ~50 полями, объединяющими состояние ВСЕХ слоёв:
- Dialogue: history, rawInputHistory, turnCount, lastFamily, lastTopic, lastForce, lastLayer, consecutiveReflect, recentFamilies, activeScene
- Identity: ego, identityClaims, orbitalMemory, lastGuardReport
- Semantic: trace, meaningGraph, discourse, semanticConfig, kernelPulse, blockedConcepts, clusters, semanticAnchor, lastTurnDecision
- Intuition: intuitConfidence, intuitionState, lastSalienceBias, holisticStreak
- Dream: dreamState, dreamAxiom
- Learning: learningNeedState, recentNarrativeSuccess
- Governance: governanceRuntimeFault, semanticCommitments
- Metacognition: metacognition
- User: userModel, mood, userState
- Runtime: currentRegime, runtimeParadigms

**Вывод:** SystemState — это god object, нарушающий любой layer boundary. Любой модуль, импортирующий SystemState, получает доступ к состоянию всех слоёв. Это структурный root cause для circular dependencies (Types<->Self, Core<->Semantic), обнаруженных в архитектурном аудите.

### 4. Self слой — формальная феноменология, не «философский диалог»

**Проблема:** Предыдущие аудиты описывали Self как «слой само-моделирования», не раскрывая его математическую структуру.

**Реальность:**
- Adjunction.hs — категорная теория: Holistic dashv Formal adjunction (product-exponential, currying). ADR-0008.
- Conatus.hs — Spinozan conatus: скалярный функционал C(b,v) = w_m*log(1+m) + w_c*log(1+c) + w_t*log(1+t) - lambda*|v| с градиентом. ADR-0007.
- Field.hs (582 LOC) — 5-component right-hemispheric observation: Resonance, Atmosphere (valence/arousal), FieldConfidence, Consolidation, Counterfactual. ADR-0009.
- Essence.hs — Phase 9 essence commitment: trajectory -> irrevocable commitment. Anomaly-3: self-referential collapse. ADR-0012.
- Deliberation.hs (590 LOC) — Phase 8: symbiotic reconciliation of Holistic/Formal proposals -> Plan. ADR-0011.
- Perspective.hs (768 LOC) — OpinionCore, PerspectiveOperator, admissibility, promotion, projection.
- AdaptivePosition.hs — FMAR Phase 2: 8D adaptive state position over Field.

**Вывод:** Self — это не «философский текст», а формальная модель с категорной алгеброй, скалярными функционалами, и phase-gated commitment. Это знание критично для понимания системы.

### 5. Learning — полный WP1-WP5 pipeline, статус неизвестен

**Модули:**
- WP1: Need (endogenous diagnostic drive), KnowledgeTree (grafting/pruning/quarantine)
- WP2: Tool (external tool selection: LLM, human mentor, script)
- WP3: Validator (strict response validator, fail-closed), Parser (JSON schema parse)
- WP4: Calibration (versioned calibration loop), Signal (bounded calibration signal)
- WP5: Sandbox (simulation gate before graft), Guardrails (rate limit, circuit breaker, quarantine)
- Phase 8: Loop (end-to-end: transport->validator->parser->sandbox->graft->telemetry)
- Phase 10: TrainingCycle (offline training: extract->generate->evaluate->promote->rollback)
- DialogueDevelopment (outcome-derived dialogue development)

**Вывод:** Learning — это не «13 модулей», а структурированный pipeline из 6 work packages. Ни один аудит не проверял, wired ли он в production pipeline.

### 6. Admission type explosion — 71 модуль (~17% кодовой базы)

**Распределение:**
- Types/Admission/ — 28 модулей (Proposition*Admission variants)
- Types/ root — 23 duplicate Proposition*Admission types
- Core/ — ~20 *Admission modules (AtomContribution, AtomExtraction, AtomFinding, CommitmentStore, EarlyFamily, Family, Interpretation, LexicalCluster*, ResponseContent, RouteHint, SemanticContribution, SemanticFrame, SemanticLogic, SenseVector, StructuralAtom)

**Вывод:** Admission types — это не «50 вариантов» из архитектурного аудита, а 71 модуль. Каждый CanonicalMoveFamily порождает n*3 типов (Proposition + Admission + Pattern). Это крупнейший структурный риск: изменение в одном family требует каскадных изменений.

### 7. Render/Dialogue.hs — 2004 LOC, подтверждённый god module

**Содержимое:** DialogueRenderArtifact, GenerationAttempt, renderDialogueArtifact, renderDialogueUtterance, renderOperatorAwareDialogue, moveToText. Claim linearization + stance framing + fallback text assembly — три ответственности в одном модуле.

### 8. Lexicon/Generated.hs — 84971 LOC, крупнейший файл в системе

**Проблема:** Ни один аудит не упоминал масштаб этого файла.

**Содержимое:** Auto-generated из spec/sql/lexicon/*.sql via scripts/generate_haskell_from_tsv.py. Содержит generatedLexemeEntries, generatedCandidateForms, generatedFiniteVerbMap.

**Вывод:** 85K LOC сгенерированного кода — это ~55% от общего LOC. Предыдущие оценки «~70k hand-written + ~89k generated» близки, но Generated.hs — это один файл, что может быть проблемой для компилятора и IDE.

### 9. Semantic/Input/GeneratedLexicon.hs — 3946 LOC

Второй сгенерированный файл, auto-generated из scripts/build_input_lexicon.py. Содержит generatedFormToLemma, generatedLemmaToPos. Ни один аудит не упоминал его.

### 10. Policy — текстовые константы, не логика

**Реальность:** Большая часть Policy — это не «политики», а текстовые константы на русском:
- Contracts.hs — missionTexts (маппинг CM* -> русские фразы)
- ParserKeywords.hs (362 LOC) — keyword lists для layer inference
- RenderLexicon.hs (236 LOC) — stance prefixes, transition phrases
- Consciousness/* (4 модуля) — текстовые фрагменты для consciousness layer

Только Metacognition.hs (179 LOC), EndpointAllowlist.hs (103 LOC), SemanticScoring.hs содержат логику.

**Вывод:** Policy слой — это в основном data, не code. Это не плохо, но предыдущие аудиты не различали data-модули от logic-модулей.

---

## Структурная карта (обновлённая)

```
Layer          | Modules | Total LOC  | Key modules
---------------|---------|------------|----------------------------------
Types          |    124  |  ~15K      | State/Governance (1117), State/System (757), State/Perspective (378), Observability (462), TurnProjection (452), Sense (232), Stance (352)
Core           |     50  |  ~12K      | TurnPipeline/* (20+), *Admission (20), Ego (107), Intuition (284), FMAR (139), R5Dynamics (161), PrincipledCore (147), Bayesian (133, NOT WIRED), ConsciousnessLoop (236)
Semantic       |     26+ |  ~10K      | Input/Assemble (1638!), DialogAssembly (712), MeaningAssembly (513), MeaningAtoms (504), Content/AtomStore (885), Content/PathFinder (548), Content/Argued (512), Morphology (313)
Self           |     14  |  ~3.5K     | Perspective (768), Deliberation (590), Field (582), Essence (~300), Adjunction (~200), Conatus (~200)
Learning       |     13  |  ~2.5K     | KnowledgeTree (388), Calibration (265), GameTheory (217, NOT WIRED), TrainingCycle, Loop, Sandbox, Validator, Guardrails, Need, Signal, Tool, Parser, DialogueDevelopment
Bridge         |     13  |  ~3K      | ExternalLLM (780), StatePersistence (493), AgdaWitness (274), SQLite/* (4 modules), Datalog/* (4 modules), Morphology (141), NixGuard, NixCache
Policy         |     11  |  ~1.5K     | Mostly text constants; Metacognition (179), EndpointAllowlist (103)
Render         |      5  |  ~2.4K     | Dialogue (2004!), Authority (184), FieldModulation (143), Semantic (50), Text (32)
Runtime        |     12  |  ~2K      | Engine (243), Health (365), PGF (362), Wiring/Context (268), Wiring/Handlers (243), Session/*
Lexicon        |      9  |  ~86K      | Generated (84971!), GfMap (228), Inflection (182), Resolver (79), Loader (45), Runtime (46), PGFStatus (53), Analyze (17)
CLI            |      8  |  ~0.9K    | Worker (355), Turn (183), Http (106), Protocol (104), Health (30), State (19)
Other          |      6  |  ~1.3K    | Observability/* (3), Memory/Episodic (291), Governance/Replay (213), Legal/Adapter (92), Resources/* (3), ExceptionPolicy
```

---

## Что предыдущие аудиты упустили — сводка

| # | Слепое пятно | Предыдущий аудит | Реальность
|---|-------------|------------------|----------
| 1 | Types/State/Governance.hs | «1 governance модуль, декоративный» | 1117 LOC, 40+ типов, event-sourcing система
| 2 | Semantic/Input/Assemble.hs | не упомянут | 1638 LOC, 3-й по размеру модуль
| 3 | SystemState god record | не выделен | ~50 полей, объединяет все слои
| 4 | Self = формальная феноменология | «слой само-моделирования» | Категорная алгебра, Spinozan conatus, 5-component Field
| 5 | Learning WP1-WP5 pipeline | «13 модулей» | 6 work packages, end-to-end pipeline
| 6 | Admission = 71 модуль | «50 типов» | 71 модуль (~17% кодовой базы)
| 7 | Lexicon/Generated = 85K LOC | «~89K generated» | Один файл 85K LOC
| 8 | Policy = data, not logic | «7 модулей» | Большинство — текстовые константы
| 9 | Render/Dialogue = 2004 LOC | «Route/Render 1352 LOC» | Render/Dialogue ещё больше
| 10 | Bayesian + GameTheory NOT WIRED | «flag-off but wired in» | Явно помечены «Not wired into production»

---

## Рекомендации

1. Types/State/Governance.hs — проверить wired ли governance event spine в runtime. Если нет — это крупнейший drafted-but-not-landed компонент.
2. SystemState — разделить на layer-specific state records. God record — root cause circular deps.
3. Semantic/Input/Assemble.hs — разбить на подмодули (parse -> classify -> morph -> assemble).
4. Render/Dialogue.hs — разбить на ClaimLinearizer + StanceFramer + FallbackAssembler.
5. Admission types — параметризовать вместо 71 модуля.
6. Learning pipeline — проверить wired ли Loop.hs в TurnPipeline/Finalize.
