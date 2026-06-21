# Рекомендации по дальнейшей работе в системе QxFx0

*Составлено на основе: skeptical audit (2026-06-24), blind-spots audit (2026-06-22), Phase 0 report, architecture map*

---

## Текущее состояние (кратко)

| Метрика | Значение |
|---------|----------|
| Build | ✅ проходит (первый успешный в истории) |
| Release artifact | ❌ никогда не существовало |
| Test suites | ⚠️ 1161 кейс, не завершается за 30с |
| Haskell модулей | ~399 (после Phase 0) |
| LOC (hand-written) | ~85K |
| LOC (generated) | ~85K (Lexicon/Generated.hs = 84971 LOC) |
| ADR proposed | 0 (19 архивировано) |
| Фаза 1–5 | не начаты |

---

## 🔴 Приоритет 0 — Немедленные блокеры (сегодня)

### 0.1. Тест-сьют таймаут = CI-блокер

**Проблема:** 1161 тест-кейс, за 28с достигнуто ~614, 0 failures. Ни один CI pipeline не пройдёт таймаут.

**Действия:**
1. Разделить тесты на `fast` (unit, <1с каждый) и `slow` (property, integration) через Cabal test-suites или Tasty patterns
2. Установить CI-таймаут 60с на fast suite, 300с на slow suite
3. Профилировать: какие тесты самые медленные? Вероятно — property tests на GeneratedLexicon или round-trip на большие структуры
4. **Не добавлять новые тесты** пока таймаут не исправлен

### 0.2. Мораторий на новый код без ADR

**Проблема:** +6787 LOC за 7 дней (Content/ + GeneratedLexicon) без единого ADR. Проект повторяет свой failure mode.

**Действия:**
1. Ввести правило: **ни один merge без ADR** (accepted/, не proposed/)
2. ADR должен содержать: что добавляется, зачем, какие модули затрагивает, как тестируется
3. Проверить: есть ли CI-хук для блокировки? Если нет — добавить pre-commit проверку наличия ADR

### 0.3. Инвентаризация generative-подсистемы

**Проблема:** Content/ (2841 LOC) + GeneratedLexicon (3946 LOC) добавлены, но:
- 0 ADR
- 0 content quality gate
- Неизвестно, встроены ли в pipeline

**Действия:**
1. Прочитать код (не документацию!) — определить, как Content/ и GeneratedLexicon подключены к TurnPipeline
2. Если не подключены — пометить как experimental, не добавлять в main branch
3. Если подключены — написать ADR с описанием контракта и quality gate

---

## 🟠 Приоритет 1 — Структурный долг (1–2 недели)

### 1.1. Расщепить SystemState

**Проблема:** SystemState — god record с ~85 полями из всех слоёв. Корневая причина циклических зависимостей.

**План:**
```
SystemState → RuntimeState (turn, pipeline, timing)
            → DialogueState (history, context, render)
            → GovernanceState (events, proposals, votes)
            → SelfState (essence, conatus, field, perspective)
            → LearningState (needs, tools, validators, knowledge)
```

**Порядок:**
1. Создать новые record types
2. Сделать SystemState новым type, содержащим под-record'ы
3. Обновить все паттерн-матчи и accessors
4. Зафиксировать build на каждом шаге

### 1.2. Разделить на cabal-пакеты

```
qxfx0-types → qxfx0-core → qxfx0-semantic / qxfx0-self / qxfx0-render / qxfx0-learning → qxfx0-runtime
```

**Цель:** компилятор автоматически ловит нарушения границ слоёв.

**Порядок:**
1. Начать с выделения `qxfx0-types` (все Types/ модули)
2. Затем `qxfx0-core` (TurnPipeline, Admission, концептуальные модули)
3. Каждый пакет — отдельный `cabal build` и `cabal test`

### 1.3. Устранить дубликат Proposition*Admission

**Проблема:** 24 типа в `Types/` (799 LOC) дублированы 25 типами в `Types/Admission/` (1039 LOC). Detectors.hs импортирует оба набора.

**Действие:**
1. Оставить `Types/Admission/` версии (более полные)
2. Удалить `Types/Proposition*Admission.hs` из корня Types/
3. Обновить импорты в Detectors.hs и других потребителях
4. Зафиксировать build

---

## 🟡 Приоритет 2 — Критические дефекты (1 неделя)

### 2.1. Guard fail-open → fail-closed

**Проблема:** Если guard недоступен, ход выполняется без governance. Это security/decorative gap.

**Действие:**
- Изменить логику: guard недоступен → ход НЕ выполняется, возвращается ошибка
- Добавить тест: guard offline → ход блокируется

### 2.2. Essence drift — удалить rrEssenceActive

**Проблема:** Флаг `rrEssenceActive` всегда True, write-only. Комментарий ADR-0036 не решает проблему.

**Действие:**
- Удалить поле из SystemState
- Зафиксировать поведение (essence всегда active)
- Обновить все ссылки

### 2.3. Round-trip тесты

**Действие:**
- Добавить `Arbitrary` instances для всех `ToJSON/FromJSON` пар
- Property test: `decode . encode === identity`
- Включить в fast suite (если быстро) или slow suite

### 2.4. Content quality gate

**Проблема:** Generative-подсистема не имеет golden tests.

**Действие:**
- Golden tests с качественными критериями на выходы диалога
- Проверка: coherence, relevance, safety
- Включить в slow suite

---

## 🟢 Приоритет 3 — Первый релиз (3–5 дней)

### 3.1. Release checklist

1. `cabal build` без ошибок ✅ (уже)
2. `cabal test` — все suites проходят (после 0.1)
3. `cabal sdist` — создать source distribution
4. Версия **0.1.0.0**
5. CHANGELOG.md с описанием что входит / что не входит
6. Отметить в README: "First release. Experimental. Not production-ready."

### 3.2. Что НЕ входит в 0.1.0.0

- Bayesian (не встроена)
- GameTheory (не встроена)
- Learning WP1-WP5 (wiring status unknown)
- Governance event-sourcing (1117 LOC, не подключён)
- Self layer (category theory, не подключён к pipeline)

Эти подсистемы должны быть либо помечены как experimental, либо вынесены в отдельный cabal-пакет `qxfx0-experimental`.

---

## 🔵 Приоритет 4 — Невстроенные подсистемы (после релиза)

Для каждой подсистемы — бинарное решение: **встроить и протестировать** OR **вынести в experimental**.

| Подсистема | LOC | Статус | Рекомендация |
|-----------|-----|--------|--------------|
| Bayesian | ? | flag-gated off | Встроить или удалить flag |
| GameTheory | ? | не в pipeline | Встроить или experimental |
| Learning WP1-WP5 | ? | wiring unknown | Прочитать код, определить статус |
| Governance event-sourcing | 1117 | не подключён | Встроить (структурно готов) |
| Self layer | ? | category theory | Встроить или experimental |

**Принцип:** не оставлять в промежуточном состоянии. Phase 4 предписывал это явно.

---

## ⚪ Приоритет 5 — Дисциплина документации

### 5.1. Анти-рот

**Проблема:** 325 markdown vs 403 source files. Anti-rot registry существует потому что docs гниют.

**Действия:**
1. Удалить или пометить `outdated` все markdown, не соответствующие коду
2. Заменить anti-rot registry на CI-проверку: docs генерируются из code (Haddock)
3. ADR-процесс: **ни один ADR без кода, ни один код без ADR**

### 5.2. 3 Python-скрипта без CI

**Проблема:** check_concepts_schema, check_replay_trace, check_runtime_contract — без CI. Паттерн накопления мёртвых скриптов повторяется.

**Действие:**
- Если скрипты полезны → добавить в CI pipeline
- Если нет → удалить
- Не оставлять в промежуточном состоянии

---

## Ключевой принцип

> **Проект повторяет свой failure mode: быстрое добавление функциональности без структурной дисциплины. Долг растёт быстрее, чем погашается. Build проходит, но это необходимое, не достаточное условие.**

> **Никогда не аудитируй эту систему по документации. Читай код, собирай, запускай.**

---

## Рекомендуемый порядок действий

```
Сегодня:  0.1 (тест-таймаут) + 0.2 (мораторий) + 0.3 (инвентаризация generative)
Эта неделя: 1.3 (дубликаты Admission) → 2.1 (guard) → 2.2 (essence)
Следующая: 1.1 (SystemState) → 1.2 (cabal-пакеты)
После:    3.1 (релиз 0.1.0.0) → 4 (невстроенные подсистемы) → 5 (документация)
```

**Главное:** не добавлять новый код, пока не исправлены блокеры (0.1–0.3). Каждый новый ADR без структурной дисциплины — это новый долг.
