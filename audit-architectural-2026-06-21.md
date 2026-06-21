# Архитектурный аудит QxFx0

**Дата:** 2026-06-21  
**Тип:** Архитектурный (структурный, не дефектный)  
**Объём:** 403 модуля, ~159K LOC (70K hand-written + 89K generated), 17 пакетов-слойёв

---

## Резюме

Архитектура QxFx0 заявлена как 8-слойная (Types → Core → Semantic → Self → Bridge → Render → Learning → CLI), но фактический анализ импортов показывает, что **слои не образуют иерархию**. Это связный граф с циклическими зависимостями на уровне пакетов. Три структурных проблемы доминируют:

1. **Types не является фундаментом** — он импортирует из 5 вышележащих слоёв
2. **Core не является ядром** — он зависит от Semantic и Self сильнее, чем от Types
3. **Types раздут до 31% кодовой базы** — 124 модуля, 50 Admission-типов

---

## 1. СЛОИ: ИЕРАРХИЯ ИЛИ ГРАФ?

### Заявленная архитектура

```
Types → Core → Semantic → Self → Bridge → Render → Learning → CLI
```

### Фактическая карта зависимостей

| Слой | Импортирует из (кол-во) | Нарушения |
|------|------------------------|----------|
| **Types** | Self (7), Semantic (6), Policy (1), Memory (2), Learning (4) | **Критическое** — фундамент зависит от 5 вышележащих слоёв |
| **Core** | Types (255), Core (251), Semantic (93), Self (61), Learning (15), Policy (14) | **Высокое** — Core↔Semantic, Core↔Self циклы |
| **Semantic** | Semantic (111), Types (100), Policy (10), Core (1) | Core→Semantic обратно |
| **Self** | Self (24), Types (19), Learning (2), Governance (1) | Types↔Self цикл |
| **Bridge** | Types (31), Bridge (14), ExceptionPolicy (12), Learning (5) | Чистый относительно Types, но Learning — вышележащий |
| **Runtime** | Runtime (39), Types (29), Semantic (18), Core (14), Bridge (13), Self (8) | Ожидаемо — Runtime — верхний слой |
| **Learning** | Learning (23), Types (16), Self (10), Core (3) | Self→Learning обратно |
| **Policy** | Policy (4), Types (3) | **Чистый** — единственный слой без нарушений |
| **Governance** | Types (4), Self (1), Core (1) | Self→Governance обратно |

### Циклические зависимости (подтверждённые)

**Types ↔ Self:**
- `Types/State/System.hs` → `Self.Essence`, `Self.Salience`, `Self.Field`
- `Types/State/SelfState.hs` → `Self.Essence`, `Self.Salience`, `Self.Field`
- `Types/TurnProjection.hs` → `Self.Conatus`, `Self.Field`
- `Types/Domain/R5.hs` → `Self.Field`
- `Self/Essence.hs` → `Types.Decision.Enums.Render`, `Types.Domain`
- `Self/Salience.hs` → `Types.*`
- `Self/Field.hs` → (через Self.ConfigLoad)

**Core ↔ Semantic:**
- `Core` импортирует Semantic 93 раза
- `Semantic/Network.hs` → `Core.MeaningGraph`

**Self ↔ Learning:**
- `Self` импортирует Learning (2)
- `Learning` импортирует Self (10)

### Вердикт

**Архитектура не слоистая, а граф с циклами.** Заявленная 8-слойная иерархия — это документация, не код. Haskell компилятор разрешает это потому, что циклы на уровне модулей (а не пакетов) допустимы через `.hs-boot` файлы или взаимную рекурсию. Но архитектурно это означает:
- Нельзя заменить слой, не затрагивая другие
- Нельзя тестировать слой изоляции
- Любое изменение в Types может сломать Self, и наоборот

---

## 2. TYPES: ФУНДАМЕНТ ИЛИ БОЛОТО?

### Размер

| Подкаталог | Модулей | Доля |
|-----------|---------|------|
| Types/Admission/ | 28 | 23% |
| Types/State/ | 12 | 10% |
| Types/Thresholds/ | 10 | 8% |
| Types/Config/ | 8 | 6% |
| Types/Decision/ | 7 | 6% |
| Types/Domain/ | 3 | 2% |
| Types/ (top-level) | 56 | 45% |
| **Итого** | **124** | **31% всей кодовой базы** |

### Admission-пролиферация

**50 файлов** с `Admission` в имени, 28 в `Types/Admission/`. Примеры:
- `PropositionAffectiveSupportPhraseAdmission`
- `PropositionAffectiveSupportProbeAdmission`
- `PropositionComparisonPlausibilityAdmission`
- `PropositionConceptKnowledgeAdmission`
- `PropositionConfrontAdmission`
- `PropositionContactAdmission`
- `PropositionContemplativeTopicAdmission`
- ... (ещё 22)

**Диагноз:** Каждый речевой акт получает собственный тип-допуск. Это не типобезопасность, это энтропия. 28 Admission-типов для ~20 CanonicalMoveFamily — почти 1:1, но без общей абстракции. Если добавить новый CanonicalMoveFamily, нужно создать новый Admission-тип, новый конвертер, новый сериализатор — **n×3 взрыв сложности**.

### Вердикт

Types — не фундамент, а **самый большой и самый связный слой**. Он:
- Содержит 31% всех модулей
- Имеет циклические зависимости с Self
- Раздут Admission-типами без общей абстракции
- Должен быть разделён на: (а) примитивные типы (без зависимостей), (б) state-типы (могут зависеть от Self), (в) Admission-фабрику (генерируется из CanonicalMoveFamily)

---

## 3. CORE: ЯДРО ИЛИ КЛЕЙ?

### Размер

102 модуля, 12 подкаталогов:

| Подкаталог | Назначение |
|-----------|-----------|
| TurnPipeline/ | Основной конвейер (22 файла) |
| Guard/ | Пост-рендер проверки (3 файла) |
| Legitimacy/ | Легитимность хода |
| PipelineIO/ | IO-эффекты |
| StanceClassifier/ | Классификация позиции |
| TopicDrift/ | Отслеживание дрейфа темы |
| TurnLegitimacy/ | (дублирует Legitimacy?) |
| TurnModulation/ | Модуляция хода |
| TurnPlanning/ | Планирование хода |
| TurnRender/ | Рендеринг хода |
| TurnRouting/ | Маршрутизация хода |

### Конвейер

```
Prepare → Plan → Route → Render → Finalize
  │        │       │        │         │
  Build   (logic) Build   Render    Commit
  Resolve        Effects  Render    Dream
                 Shadow             Orchestrate
                 Anomaly            Precommit
                                    Projection
                                    State
```

**Наблюдение:** `TurnPipeline/Route/Render.hs` — 1352 LOC. Рендеринг внутри маршрутизации внутри конвейера. Это нарушение SRP — Route должен решать *куда*, а не *как рендерить*.

### Связанность

Core импортирует:
- Types: 255 (ожидаемо)
- Core: 251 (внутренние — нормально)
- **Semantic: 93** (Core зависит от Semantic почти так же сильно, как от Types)
- **Self: 61** (Core зависит от Self)

**Вердикт:** Core — не ядро, а **оркестратор, связанный со всеми слоями**. Он не может быть протестирован или заменён изолированно. Semantic и Self — не вышележащие слои, а встроенные зависимости Core.

---

## 4. GUARD: FAIL-OPEN ПО АРХИТЕКТУРЕ

### NixGuard

```haskell
checkConstitution :: FilePath -> Text -> Double -> Double -> IO NixGuardStatus
-- Возвращает: Allowed | Blocked | Unavailable
```

При `Unavailable` (concept unsupported, lenient mode, nix not found) — **система продолжает работу без конституционного управления**. Это не дефект, а архитектурное решение: guard — пост-рендер проверка, не превентивный гейт.

### Guard scope

Guard проверяет только **отрендеренный текст** (`postRenderSafetyCheck`). Он не проверяет:
- Семантическое содержание (что система «думает»)
- Маршрутизацию (какой CanonicalMoveFamily выбран)
- Качество мысли (есть ли мысль вообще)

**Вердикт:** Guard архитектурно расположен **после** рендеринга, а не **до** принятия решения. Это означает, что система может принять плохое решение, отрендерить его, и только потом guard может заблокировать вывод. Но если guard unavailable — плохой вывод проходит.

---

## 5. ADR-СИСТЕМА: ПРИНЯТЫЕ ИЛИ НЕТ?

### Статус

| Диапазон | Статус | Количество |
|----------|--------|------------|
| 0001-0012 | Приняты | 12 |
| 0013-0016 | **Только proposed/** | 4 |
| 0017-0019 | Приняты (0019 дублируется в proposed/) | 3 |
| 0020-0024 | **Только proposed/** | 5 |
| 0025-0033 | Приняты | 9 |
| 0034-0041 | **Только proposed/** | 8 |
| 0042-0046 | Приняты | 5 |

**Итого:** 29 принятых, 17 в proposed/ (никогда не приняты).

### Критичные непринятые ADR

- **ADR-0034** (self-core-role-split) — разделение Self и Core. Не принято, но код уже живёт в обоих слоях с циклическими зависимостями.
- **ADR-0036** (promote-essence-commitment) — Essence promoted. Не принято (в proposed/), но код всегда включает Essence.
- **ADR-0020** (promote-perspective-operator) — не принято.
- **ADR-0021** (promote-external-llm-transport) — не принято, но `Bridge/ExternalLLM.hs` существует (780 LOC).

**Вердикт:** ADR-система формально существует, но **архитектурные решения принимаются в коде раньше, чем в документации**. ADR — пост-фактум рационализация, не превентивный контроль.

---

## 6. МОДУЛЬНАЯ СЛОЖНОСТЬ

### God-модули (>500 LOC, не generated)

| Модуль | LOC | Проблема |
|--------|-----|---------|
| `Lexicon/Generated.hs` | 84,971 | Generated — не проблема сам по себе, но 53% кодовой базы |
| `Semantic/Input/GeneratedLexicon.hs` | 3,946 | Generated — дублирует Generated.hs? |
| `Render/Dialogue.hs` | 2,004 | Рендеринг — слишком много для одного модуля |
| `Semantic/MeaningDecompose/Domains.hs` | 1,785 | Декомпозиция смысла — god-модуль |
| `Semantic/Input/Assemble.hs` | 1,638 | Сборка ввода — god-модуль |
| `Semantic/Proposition/Detectors.hs` | 1,458 | Детекторы пропозиций — god-модуль |
| `Core/TurnPipeline/Route/Render.hs` | 1,352 | Рендеринг внутри маршрутизации |
| `Types/State/Governance.hs` | 1,117 | State-тип — god-тип |
| `Core/TurnPipeline/Finalize/State.hs` | 935 | State-тип внутри finalize |
| `Semantic/Content/AtomStore.hs` | 885 | Хранилище атомов |
| `Bridge/ExternalLLM.hs` | 780 | Внешний LLM — god-модуль |
| `Self/Perspective.hs` | 768 | Перспектива — god-модуль |
| `Types/State/System.hs` | 757 | SystemState — god-тип |

**13 модулей >500 LOC** (без generated). Из них 3 — state-типы, 4 — semantic, 2 — core pipeline, 2 — bridge/self, 1 — render.

### Вердикт

God-модули концентрируются в **Semantic** (4 из 13) и **Core/TurnPipeline** (2). `Types/State/System.hs` (757 LOC) — god-тип, который импортирует из Self, создавая цикл.

---

## 7. ВХОДНЫЕ ТОЧКИ И RUNTIME

### CLI

```
app/CLI/
  Main.hs (entry)
  State.hs (state JSON)
  Worker.hs (stdio worker protocol)
  Protocol.hs (protocol types)
```

### Runtime

```
Runtime.hs (facade)
Runtime/
  Engine.hs (runTurn, loop)
  Gate.hs (readiness checks)
  Health.hs (system health)
  Mode.hs (runtime mode)
  Paths.hs (path resolution)
  Session/ (session management)
  Wiring/ (DB wiring, pipeline IO)
  GF/ (GF runtime)
```

### Поток выполнения

```
CLI.Main → Runtime.runTurn → Core.TurnPipeline
  → prepareTurn → planTurn → routeTurn → renderTurn → finalizeTurn
  → Guard.postRenderSafetyCheck
  → StatePersistence.save
```

**Вердикт:** Поток выполнения чистый и понятный. Runtime — единственный слой, который правильно занимает верхнюю позицию (импортирует из всех нижних). Это **единственная часть архитектуры, которая работает как заявлено**.

---

## 8. ТЕСТОВАЯ АРХИТЕКТУРА

### Конфигурация

6 test-suites в cabal:
- `qxfx0-test-unit`
- `qxfx0-test-property`
- `qxfx0-test-integration`
- `qxfx0-test-slow`
- `qxfx0-test-fast`
- `qxfx0-test` (общий?)

99 тестовых файлов, 79 suite-модулей.

### Проблема

Из предыдущего аудита: **7 test-suites wired but not run**. Ни один релиз не был сделан. Тесты проверяют routing family (маршрутизацию), а не качество мысли.

### Архитектурный аспект

Тестовая архитектура **не отражает слои**. Нет тестов:
- Types ↔ Self циклических зависимостей
- Guard fail-open поведения
- Admission-типов на полноту (все ли CanonicalMoveFamily покрыты)
- Сериализационной симметрии (decode.encode == id)

**Вердикт:** Тесты существуют, но не покрывают архитектурные риски. Они тестируют поведение, а не структуру.

---

## 9. СТРУКТУРНЫЕ РИСКИ

### 9.1. Bridge — не мост, а стяжка

Bridge (21 модуль) импортирует из Types (31), Learning (5), ExceptionPolicy (12). Он связан с Learning — вышележащим слоем. Bridge должен быть чистым адаптером (DB, Agda, Datalog, ExternalLLM), но он зависит от Learning.

### 9.2. Observability — минимальный

3 модуля. Импортирует из Types (2), Self (2). Наблюдаемость системы — практически отсутствует архитектурно. Нет метрик, нет трейсинга (только Log.logDebug).

### 9.3. Governance — декоративный

1 модуль. Импортирует из Types (4), Self (1), Core (1). Это фасад, не архитектурный компонент. NixGuard живёт в Bridge, не в Governance.

### 9.4. Memory — минимальный

1 модуль (`Episodic`). Эпизодическая память — 1 файл. При этом Types импортирует из Memory — цикл.

### 9.5. Legal — минимальный

1 модуль. Правовой слой — 1 файл.

---

## 10. АРХИТЕКТУРНЫЙ ДОЛГ

### Критический

1. **Types ↔ Self цикл** — фундамент и Self зависят друг от друга. Решение: выделить `Types.Primitive` (без зависимостей) и `Types.State` (может зависеть от Self). Или: перенести Self-типы в Self, убрать из Types.

2. **Core ↔ Semantic цикл** — Core зависит от Semantic (93 импорта), Semantic от Core (1, но есть). Решение: выделить `Core.MeaningGraph` в отдельный слой или в Semantic.

3. **Admission-пролиферация** — 50 типов без общей абстракции. Решение: параметризовать через тип-параметр или GADT, сократить до 1-3 модулей.

### Высокий

4. **God-модули в Semantic** — 4 модуля >1000 LOC. Решение: декомпозиция по доменам.

5. **Route/Render смешение** — `Core/TurnPipeline/Route/Render.hs` (1352 LOC). Решение: вынести рендеринг в Render-слой.

6. **ADR-0034 не принят** — Self/Core split не формализован. Решение: принять или отвергнуть, привести код в соответствие.

### Средний

7. **Bridge → Learning зависимость** — Bridge не должен зависеть от вышележащих слоёв.

8. **Observability — 3 модуля** — недостаточно для системы такого размера.

9. **17 ADR в proposed/** — архитектурные решения не формализованы.

10. **Тесты не покрывают архитектурные риски** — нет тестов циклических зависимостей, нет тестов Admission-полноты.

---

## 11. РЕКОМЕНДАЦИИ

### Немедленные (1-2 дня)

1. **Разорвать Types ↔ Self цикл.** Перенести `Self.Essence`, `Self.Salience`, `Self.Field` типы в `Types.Self` (или `Self.Types`), убрать импорты из `Types/State/System.hs`.
2. **Принять или отвергнуть ADR-0034.** Если Self/Core split — принят, формализовать границу. Если отвергнут — объединить.

### Краткосрочные (1-2 недели)

3. **Сократить Admission-типы.** Создать параметризованный `Admission a` тип, заменить 50 файлов на 1-3.
4. **Вынести `Core.MeaningGraph` в Semantic.** Разорвать Core ↔ Semantic цикл.
5. **Декомпозировать Route/Render.** Перенести рендеринг из Route в Render-слой.

### Среднесрочные (1-2 месяца)

6. **Ввести layer-tests.** Тест, который проверяет, что Types не импортирует из Self/Semantic/Core.
7. **Декомпозировать god-модули Semantic.** MeaningDecompose/Domains (1785 LOC) → по доменам.
8. **Формализовать ADR-процесс.** 17 ADR в proposed/ — принять или отвергнуть.

### Стратегические

9. **Ввести package-level разделение.** Сейчас всё в одном cabal-пакете. Разделить на `qxfx0-types`, `qxfx0-core`, `qxfx0-semantic`, `qxfx0-self`, `qxfx0-runtime`. Циклы станут невозможны на уровне пакетов.
10. **Вырезать release.** Без релиза архитектура — теория. Нужно скомпилировать, запустить, найти что ломается.

---

## 12. СВОДНАЯ ТАБЛИЦА

| Архитектурный риск | Уровень | Статус |
|-------------------|---------|--------|
| Types ↔ Self цикл | CRITICAL | Открыт |
| Core ↔ Semantic цикл | CRITICAL | Открыт |
| Admission-пролиферация (50 типов) | CRITICAL | Открыт |
| Core не ядро, а оркестратор | HIGH | Дизайн |
| God-модули Semantic (4×>1000 LOC) | HIGH | Открыт |
| Route/Render смешение | HIGH | Открыт |
| ADR-0034 не принят | HIGH | Открыт |
| Bridge → Learning зависимость | MEDIUM | Открыт |
| Observability минимальна (3 модуля) | MEDIUM | Дизайн |
| 17 ADR в proposed/ | MEDIUM | Открыт |
| Guard fail-open по архитектуре | MEDIUM | Дизайн |
| Тесты не покрывают структуру | MEDIUM | Открыт |
| Governance — 1 модуль (декоративно) | LOW | Дизайн |
| Memory — 1 модуль | LOW | Дизайн |

---

## 13. ЗАКЛЮЧЕНИЕ

QxFx0 — это **монолит с документированной слоистостью, которой нет в коде**. 403 модуля в одном cabal-пакете, с циклическими зависимостями между «слоями», 31% кода в Types, 50 Admission-типов без абстракции, и 17 ADR, которые никогда не были приняты.

Архитектурно система **работает** (поток выполнения чист), но **не эволюционирует** — любое изменение в Types может сломать Self, и наоборот. Добавление нового CanonicalMoveFamily требует создания 3+ новых файлов (Admission, детектор, рендерер).

**Главная рекомендация:** Разделить на cabal-пакеты. Это единственный способ превратить документированные слои в реальные границы. Пока всё в одном пакете, компилятор не будет ловить нарушения.

---

*Аудит проведён по исходному коду. Build не верифицирован (cabal build timeout из предыдущего аудита).*
