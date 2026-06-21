# Технические роадмапы: 10 концепций → конкретные планы

> **Статус:** ОБСУЖДАЕМ. Документ для принятия решений, не для исполнения.
> **Дата:** 2026-06-25
> **Контекст:** QxFx0 — 403 модуля, ~70k LOC, Phase 1 (CI gates) завершена, Phase 2 не начата.
> 3 подтверждённых бага: декоративный гейт (PathFinder.hs:289), NixGuard fail-open, нет -Werror.

---

## Концепция 1: Дисциплина раньше скорости → Roadmap: Wire & Harden

**Цель:** Каждый механизм безопасности выполняется в production-пути, а не только в тестах.

### Задачи

| # | Задача | Файлы | Оценка | DoD | Зависимости |
|---|--------|-------|--------|-----|-------------|
| 1.1 | Wire gate verdict в composeDefinition | PathFinder.hs:289 — заменить _gateVerdict на проверку gvOverall | 0.5д | Если gvOverall=False → GeneratedSurface "" [] []. Тест: gate-fail → пустой output | — |
| 1.2 | NixGuard fail-closed по умолчанию | NixGuard.hs — fallback на Blocked вместо unrestricted | 0.5д | Без env-var NixGuard блокирует. Тест: default → Blocked | — |
| 1.3 | Включить -Werror для redundant patterns | cabal.project / package.yaml | 1–3д | cabal build без warnings. 207 redundant patterns исправлены | — |
| 1.4 | Content quality gate (минимальный) | ContentQualityGate.hs + 10 эталонных вопросов | 3–5д | CI запускает 10 вопросов, проверяет релевантность. Red build при провале | 1.1 |
| 1.5 | Устранить unsafePerformIO (6 модулей) | grep unsafePerformIO → IO-монада или NOINLINE | 2–4д | 0 unsafePerformIO без NOINLINE+обоснования | — |

### Обсуждение
- Q1: -Werror на весь проект или поэтапно? Поэтапно безопаснее.
- Q2: Content quality — LLM-судья ($0.05/запрос) или эвристика? Начать с эвристики.
- Q3: unsafePerformIO — некоторые случаи могут быть performance-critical.

---

## Концепция 2: Хирургическая декомпозиция → Roadmap: Layer Extraction

**Цель:** Разбить god-record SystemState (44 поля) на layer-specific records, выделить cabal-пакеты.

### Задачи

| # | Задача | Файлы | Оценка | DoD | Зависимости |
|---|--------|-------|--------|-----|-------------|
| 2.1 | Инвентаризация полей SystemState | Types/State/SystemState.hs — таблица: поле→слой→читатель→писатель | 1д | 44 строки, каждое поле привязано к слою | — |
| 2.2 | Спроектировать layer-specific records | ADR: TypesState, CoreState, SelfState, SemanticState, RenderState, LearningState | 1д | ADR accepted | 2.1 |
| 2.3 | Создать QxFx0-Types cabal-пакет | QxFx0-Types.cabal — export SystemState (временный), GateVerdict, базовые типы | 2д | cabal build QxFx0-Types succeeds | 2.2 |
| 2.4 | Мигрировать поля по слоям | По 5–8 полей за PR | 5–8д | SystemState = композиция layer records. Все тесты зелёные | 2.3 |
| 2.5 | Выделить QxFx0-Core, QxFx0-Self, QxFx0-Semantic | Каждый cabal-пакет с exposed-modules whitelist | 3–5д/пакет | Circular deps устранены. cabal build всех пакетов | 2.4 |

### Обсуждение
- Q1: Порядок извлечения? Types→Core→Self→Semantic→Render.
- Q2: SystemState — композиция (ssSelf, ssCore) или ReaderT LayerState?
- Q3: ssRuntimeGraph (новое поле, circular dep) — перенести в SemanticState или удалить?

---

## Концепция 3: Контент вместо труб → Roadmap: Semantic Test Suite

**Цель:** Тесты проверяют семантическое содержание ответов, а не только структуру.

### Задачи

| # | Задача | Файлы | Оценка | DoD | Зависимости |
|---|--------|-------|--------|-----|-------------|
| 3.1 | 10 стартовых эталонных вопросов | test/semantic/benchmarks/ — YAML: вопрос+темы+свойства | 1д | 10 вопросов с метаданными | — |
| 3.2 | Эвристический валидатор | test/semantic/ContentValidator.hs — keyword overlap, длина, аргументация | 2д | Валидатор: ответ+эталон→Pass/Fail с причиной | 3.1 |
| 3.3 | CI integration | test/semantic/SemanticSpec.hs — Tasty, slow-tests | 1д | cabal test --pattern=semantic — 10 тестов | 3.2 |
| 3.4 | Расширить до 50 вопросов | test/semantic/benchmarks/ — 50 вопросов по 10 темам | 2д | 50 тестов, baseline зафиксирован | 3.3 |
| 3.5 | LLM-судья (opt-in) | test/semantic/LLMJudge.hs — внешний API, оценка 0–10 | 3д | При QXFX0_LLM_JUDGE=1 — LLM оценивает | 3.4 |
| 3.6 | Регрессионный baseline | test/semantic/baseline.json — метрики для 50 вопросов | 1д | PR не может ухудшить baseline >10% без обоснования | 3.5 |

### Обсуждение
- Q1: Keyword overlap порог? 0.3 для начала.
- Q2: LLM-судья — API? 50×$0.05=$2.50/CI run.
- Q3: False positives — ручной review при fail.

---

## Концепция 4: Нулевой долг → Roadmap: Aggressive Cleanup

**Цель:** Удалить ~15K LOC мёртвого и дублированного кода.

### Задачи

| # | Задача | Файлы | Оценка | DoD | Зависимости |
|---|--------|-------|--------|-----|-------------|
| 4.1 | Удалить 4 dead Haskell модуля | grep + cabal build | 0.5д | 199 LOC удалено, build succeeds | — |
| 4.2 | Удалить 5 dead Thresholds sub-modules | Thresholds/ — проверить импорты | 0.5д | 574 LOC удалено, build succeeds | — |
| 4.3 | Объединить 23 Proposition*Admission типа | Admission/Proposition*.hs — canonical + замена импортов | 2–3д | Один PropositionAdmission тип. 799→~150 LOC | — |
| 4.4 | Удалить 23 мёртвых Python-скрипта | scripts/python/ — проверить Makefile/flake.nix | 0.5д | 13,495 LOC удалено | — |
| 4.5 | Решить судьбу 19 proposed ADR | docs/adr/proposed/ — review каждый | 1д | 0 ADR в proposed/. Все accepted/ или rejected/ | — |
| 4.6 | Очистить 45+ old gate result reports | docs/gate-results/ | 0.5д | Только актуальные reports | — |
| 4.7 | Включить -Werror (дублирует 1.3) | — | — | — | 1.3 |

### Обсуждение
- Q1: Proposition*Admission — canonical = самый используемый (grep import count).
- Q2: Python-скрипты — проверить Makefile, flake.nix, CI config.
- Q3: ADR — нужен ADR review session.

---

## Концепция 5: Event-Sourcing → Roadmap: Event-Driven State

**Цель:** Состояние = свёртка событий. SystemState → EventLog + projectedState.

### Задачи

| # | Задача | Файлы | Оценка | DoD | Зависимости |
|---|--------|-------|--------|-----|-------------|
| 5.1 | Инвентаризация 40+ типов событий | Types/State/Governance.hs (1117 LOC) | 1д | Таблица: тип→поля→генератор→потребитель | — |
| 5.2 | Спроектировать unified Event тип | ADR: data Event = GovernanceEvent | TurnEvent | ... | 1д | ADR accepted. Event покрывает 40+ типов | 5.1 |
| 5.3 | Реализовать foldEvent | foldEvent :: Event→SystemState→SystemState | 3–5д | foldEvent обрабатывает все варианты. Тест: events→expected state | 5.2 |
| 5.4 | TurnPipeline генерирует события | Каждый этап emit events вместо мутации | 5–8д | TurnPipeline возвращает ([Event], Result) | 5.3 |
| 5.5 | Governance = validateEvent | validateEvent :: Event→GateVerdict | 2д | Blocked events не применяются. Тест: blocked→state unchanged | 5.4, 1.1 |
| 5.6 | Воспроизведение журнала = тестирование | replay :: EventLog→SystemState + property tests | 2д | replay(generateEvents)==directExecution для 10 сценариев | 5.5 |

### Обсуждение
- Q1: Производительность — snapshot + incremental replay.
- Q2: Существующая система в Governance.hs — полная или частичная?
- Q3: Миграция — поэтапно (Governance сначала) или big-bang?

---

## Концепция 6: Адверсариальное упрочение → Roadmap: Red Team Sprint

**Цель:** Найти и исправить все fail-open пути и границы, уничтожающие информацию.

### Задачи

| # | Задача | Файлы | Оценка | DoD | Зависимости |
|---|--------|-------|--------|-----|-------------|
| 6.1 | Red team аудит: все fail-open пути | grep unsafePerformIO, NixGuard, _gateVerdict, catch...return () | 1д | Список fail-open путей с ущербом | — |
| 6.2 | Эксплойты для каждого fail-open | Тест: последовательность действий, демонстрирующая обход | 2–3д | N эксплойтов (тестов), red build | 6.1 |
| 6.3 | Исправить fail-open→fail-closed | По приоритету ущерба | 3–5д | Все эксплойты из 6.2 — зелёные | 6.2, 1.1, 1.2, 1.5 |
| 6.4 | Аудит: границы, уничтожающие информацию | grep T.pack.show, show в error handlers, 14 silent swallow sites | 1д | Список information-destroying boundaries | — |
| 6.5 | Эксплойты для потери данных | Тест: structured error→boundary→loss of provenance | 1–2д | N тестов, демонстрирующих потерю | 6.4 |
| 6.6 | Structured error channel | data StructuredError = StructuredError { seProvenance, seContext, seMessage } | 3–5д | Ошибки сохраняют provenance. Тесты из 6.5 зелёные | 6.5 |
| 6.7 | Аудит: декоративные механизмы | Найти механизмы, тестыемые но не вызываемые из production | 1д | Список decorative mechanisms | — |
| 6.8 | Wire decorative mechanisms | Для каждого — wire или удалить | 2–3д | 0 decorative mechanisms | 6.7, 1.1 |

### Обсуждение
- Q1: Кто red team? Один разработчик на sprint, потом ротация.
- Q2: Эксплойты — integration level (fail-open проявляется на границах).
- Q3: Structured error channel — независимый трек, ортогонален декомпозиции.

---

## Концепция 7: Минимальный релиз → Roadmap: v0.1.0 Cut & Ship

**Цель:** Вырезать работающий минимум, выпустить v0.1.0, получить обратную связь.

### Задачи

| # | Задача | Файлы | Оценка | DoD | Зависимости |
|---|--------|-------|--------|-----|-------------|
| 7.1 | Определить минимальный сценарий | ADR: вопрос→ответ, input/output format, expected quality | 0.5д | ADR accepted | — |
| 7.2 | Вырезать нефункциональное за флаги | GameTheory, Learning, Dream, Orbital — CPP или cabal flags | 1–2д | cabal build -f minimal — без GameTheory/Learning/Dream/Orbital | — |
| 7.3 | Wire базовый путь с gate enforcement | Prepare→Plan→Route→Render→Finalize, gates enforced | 1д | Smoke test: 10 вопросов→10 ответов, gates не bypassed | 1.1 |
| 7.4 | LLM circuit breaker | CircuitBreaker.hs — timeout N сек, max M токенов, abort→fallback | 1–2д | При timeout/overflow — graceful abort. Тест: mock LLM с delay | — |
| 7.5 | Smoke test suite | test/integration/SmokeSpec.hs — 10 вопросов, ручная проверка | 1д | 10 вопросов, ответы проверены, результаты зафиксированы | 7.3, 7.4 |
| 7.6 | Tag v0.1.0 | git tag v0.1.0, cabal sdist, binary artifact | 0.5д | v0.1.0 tag. cabal install работает. Binary запускается | 7.5 |
| 7.7 | Сбор обратной связи | GitHub Issues template, 10 вопросов для пользователей | 0.5д | Issue template создан. 3+ тестировщика получили доступ | 7.6 |

### Обсуждение
- Q1: Single-turn для v0.1.0? Да.
- Q2: Circuit breaker пороги? 30 сек timeout, 4096 токенов для начала.
- Q3: Релиз с известными дефектами — да, с явным KNOWN_ISSUES.md.

---

## Концепция 8: Формальная верификация → Roadmap: Agda Proofs

**Цель:** Формально доказать корректность критических путей в Agda.

### Задачи

| # | Задача | Файлы | Оценка | DoD | Зависимости |
|---|--------|-------|--------|-----|-------------|
| 8.1 | TurnPipeline как композиция морфизмов | agda/TurnPipeline.agda — prepare>=>plan>=>route>=>render>=>finalize | 5–8д | Agda proof checks | — |
| 8.2 | Доказать: gates Approved→non-empty surface | agda/GateEnforcement.agda | 3–5д | Proof: forall gv. gvOverall gv=True → content≠empty | 8.1, 1.1 |
| 8.3 | Доказать: NixGuard fail-closed→no bypass | agda/NixGuard.agda | 2–3д | Proof: forall mode=Strict → NixGuard returns Blocked | 8.2, 1.2 |
| 8.4 | Формализовать error propagation | agda/ErrorPropagation.agda | 3–5д | Proof: forall e. provenance(propagate e)=provenance e | 8.1 |
| 8.5 | CI: Agda proof checking | .github/workflows/agda.yml | 1д | CI запускает agda --check. Red build при провале | 8.2, 8.3, 8.4 |
| 8.6 | Extract Haskell из Agda (опционально) | agda/extract/ | 5–10д | Сгенерированный Haskell компилируется и проходит тесты | 8.5 |

### Обсуждение
- Q1: Agda в стеке — но есть ли экспертиза? 2–4 недели обучения если нет.
- Q2: Доказывать реальный код или спецификацию? Спецификацию + refinement.
- Q3: Начинать после 1.1–1.2. Доказывать неисправный код бессмысленно.

---

## Концепция 9: Генеративный рост → Roadmap: Feature-First Expansion

**Цель:** Новый функционал self-contained модулями + параллельное погашение долга (ratio 3:1).

### Задачи

| # | Задача | Файлы | Оценка | DoD | Зависимости |
|---|--------|-------|--------|-----|-------------|
| 9.1 | Определить новые возможности | ADR: multi-turn memory, cross-topic reasoning, user modeling | 1д | ADR accepted. 3 фичи с acceptance criteria | — |
| 9.2 | Multi-turn dialogue memory | Core/Memory/DialogueMemory.hs — self-contained, gates, тесты | 5–8д | 3-turn dialogue сохраняет контекст. Не зависит от SystemState напрямую | 1.1 |
| 9.3 | Cross-topic reasoning | Core/Reasoning/CrossTopic.hs | 5–8д | Тест: вопрос о свободе→ссылка на предыдущий разговор о справедливости | 9.2 |
| 9.4 | User modeling | Core/User/UserModel.hs — профиль пользователя | 3–5д | Тест: после 3 вопросов — профиль обновлён | 9.2 |
| 9.5 | Debt repayment track | 1 день/неделю: composeDefinition, NixGuard, -Werror, dead code | непрерывно | Ratio новый:погашенный ≤3:1 | 1.1–1.5 |
| 9.6 | Метрика ratio | CI report: LOC added vs LOC removed | 1д | CI выводит ratio. PR с ratio>3:1 — warning | — |

### Обсуждение
- Q1: Интерфейс вместо SystemState — MonadState constraint.
- Q2: Ratio 3:1 — начать с 1:1, поднять после стабилизации.
- Q3: Multi-turn memory — самая востребованная фича для диалоговой системы.

---

## Концепция 10: Мульти-режимная governance → Roadmap: GovernanceMode

**Цель:** data GovernanceMode = Strict | Permissive | Experimental как first-class тип.

### Задачи

| # | Задача | Файлы | Оценка | DoD | Зависимости |
|---|--------|-------|--------|-----|-------------|
| 10.1 | Определить GovernanceMode тип | Types/GovernanceMode.hs — data GovernanceMode = Strict|Permissive|Experimental | 0.5д | Тип определён, компилируется | — |
| 10.2 | Добавить в SystemState | ssGovernanceMode :: GovernanceMode — immutable after init | 0.5д | SystemState содержит поле. Init — единственное место записи | 10.1 |
| 10.3 | Gate functions принимают GovernanceMode | validatePath :: GovernanceMode→Path→GateVerdict — для G1–G5 | 1–2д | Все 5 gates принимают GovernanceMode. Strict→enforced, Permissive→logged, Experimental→bypassed | 10.2 |
| 10.4 | CLI флаг | --governance=strict|permissive|experimental — default: strict | 0.5д | CLI парсит флаг. Default=strict | 10.3 |
| 10.5 | Тесты для каждого режима | test/governance/StrictSpec.hs, PermissiveSpec.hs, ExperimentalSpec.hs | 2–3д | 3 test-suites, каждый проверяет свой режим | 10.3 |
| 10.6 | NixGuard + GovernanceMode | NixGuard.hs — Strict→Blocked, Permissive→Warn, Experimental→Unrestricted | 1д | Тест: 3 режима → 3 поведения | 10.3, 1.2 |

### Обсуждение
- Q1: Легитимизация fail-open? Permissive логирует warnings, не молчит.
- Q2: Режим immutable после init — restart required для смены.
- Q3: Experimental — только --governance=experimental + warning в stderr.

---

## Сводная таблица зависимостей

```
Концепция 1 (Wire & Harden) — БЛОКИРУЮЩАЯ
  1.1 composeDefinition gate → блокирует 7.3, 8.2, 9.2, 5.5, 6.3, 6.8
  1.2 NixGuard fail-closed → блокирует 8.3, 10.6
  1.3 -Werror → дублирует 4.7
  1.4 Content quality gate → блокирует 7.5
  1.5 unsafePerformIO → блокирует 6.3

Концепция 2 (Layer Extraction) — независимый трек, 2.4 зависит от 1.3
Концепция 3 (Semantic Tests) — 3.3 зависит от 1.4
Концепция 4 (Cleanup) — независимый трек, 4.7=1.3
Концепция 5 (Event-Sourcing) — 5.5 зависит от 1.1
Концепция 6 (Red Team) — 6.3 зависит от 1.1, 1.2, 1.5; 6.8 от 1.1
Концепция 7 (Release) — 7.3 от 1.1; 7.5 от 1.4, 7.4
Концепция 8 (Agda) — 8.2 от 1.1; 8.3 от 1.2
Концепция 9 (Growth) — 9.2 от 1.1; 9.5=1.1–1.5
Концепция 10 (GovernanceMode) — 10.6 от 1.2
```

## Критический путь

Концепция 1 — блокирующая для 7 из 10 концепций. Без wire gates (1.1) и NixGuard fail-closed (1.2) нельзя: релизить, доказывать, развивать, red team, event-source, multi-mode governance.

### Рекомендуемая последовательность (для обсуждения):

```
Неделя 1–2:  Концепция 1 (1.1, 1.2, 1.3) + Концепция 4 (4.1–4.6) параллельно
Неделя 3:    Концепция 1 (1.4, 1.5) + Концепция 3 (3.1–3.3) параллельно
Неделя 4–5:  Концепция 7 (7.1–7.6) — релиз v0.1.0
Неделя 6+:   Концепция 2 (декомпозиция) ИЛИ 5 (event-sourcing) ИЛИ 8 (Agda)
Параллельно: Концепция 9 (новый функционал, ratio 3:1)
Ортогонально: Концепция 10 (в любой момент после 1.2)
```

## Открытые вопросы для обсуждения

1. **Приоритет:** Концепция 1 — единственный блокирующий путь. Начинаем с неё?
2. **Релиз:** Готовы ли выпустить v0.1.0 с известными дефектами (после 1.1, 1.2)?
3. **Архитектура:** Концепция 2 vs 5 vs 8 — какая архитектура следующего поколения?
4. **Команда:** Есть ли ресурсы на параллельные треки (1+3+4) или строго последовательно?
5. **Agda:** Есть ли экспертиза формальных методов? Если нет — Концепция 8 откладывается.
6. **Red team:** Кто играет роль red team? Один человек или ротация?
7. **Content quality:** LLM-судья ($2.50/CI run) или эвристика (бесплатно, грубо)?
8. **GovernanceMode:** Легитимизация fail-open — риск или инструмент?
