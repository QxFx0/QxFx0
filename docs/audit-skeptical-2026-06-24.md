# Скептичный аудит системы — 2026-06-24

## Методология

Аудит проводился по коду, не по документации. Проверены: git-история (30 коммитов), сборка (0 ошибок, 299 предупреждений), новые модули (2526 LOC), тесты (78 новых ассертов), wiring в Core/Render/Runtime, сериализация, обработка ошибок.

## Сводка

| Категория | Кол-во | Статус |
|-----------|--------|--------|
| CRITICAL | 2 | Новые + незакрытые |
| HIGH | 4 | Незакрытые + новые |
| MEDIUM | 3 | Новые |
| INFO | 2 | Незакрытые |

---

## CRITICAL

### C1. Gate verdict вычислен, но НЕ ПРИМЕНЯЕТСЯ в composeDefinition

**Файл:** `src/QxFx0/Semantic/Content/PathFinder.hs:289`

```haskell
combinedProof = PathProof allEdges (T.pack (show topic))
_gateVerdict = validatePath combinedProof  -- ← underscore = игнорируется
in GeneratedSurface fullText allProofs allSources  -- ← возвращается всегда
```

**Суть:** Построена система из 5 гейтов (180 LOC `GeneratedPredicateGate.hs`), написаны 24 тест-ассерта на гейты, но в главной функции генерации определений (`composeDefinition`) вердикт гейтов **вычисляется и выбрасывается**. `GeneratedSurface` с `fullText` возвращается независимо от того, прошли гейты или нет.

**Контраст:** В `composeArgument` (строка 491) тот же вердикт **применяется корректно**:
```haskell
if gvOverall combinedVerdict
  then GeneratedSurface fullText allProofs allSources
  else GeneratedSurface "" [] []  -- gate failed, fall back
```

**Это тот же мета-паттерн «информационное разрушение на границах»:** система генерирует информацию (вердикт гейтов), но уничтожает её на границе между валидацией и выводом. Гейты — декоративные в определениях, рабочие в аргументах. Несоответствие, которое не ловится тестами, потому что тесты `PathFinder.hs` проверяют `non-empty text` и `contains 'свобода'`, но не проверяют, что гейты отсекают недопустимый вывод.

**Риск:** Система может выводить сырой substrate (Gate G5), тавтологии (Gate G2) и универсальные шаблоны (Gate G1) в определениях, и все 21 ассертов PathFinder-тестов пройдут.

### C2. NixGuard: silent security downgrade — НЕ ИСПРАВЛЕН

**Файл:** `src/QxFx0/Bridge/NixGuard.hs:88-93`

```haskell
runNixEval nixExpr = do
  restrictedResult <- runNixInstantiate True nixExpr
  case restrictedResult of
    Left err
      | isRestrictedFlagUnsupported err ->
          runNixInstantiate False nixExpr  -- ← silent fallback to unrestricted
    _ -> pure restrictedResult
```

При отсутствии флага `--restricted` у nix-instantiate, система **тихо** падает до unrestricted режима. Это тройная деградация: restricted → unrestricted → Unavailable → fail-open. Фикс из Phase 2 roadmap не реализован.

---

## HIGH

### H1. unsafePerformIO + global mutable state — НЕ ИСПРАВЛЕН

**Файлы:** `Lexicon/PGFStatus.hs`, `Lexicon/GfMap.hs`, `Self/ConfigLoad.hs`, `Self/Salience.hs`, `Self/FamilyTargets.hs`, `Self/Field.hs`

6 модулей создают глобальное состояние при загрузке модуля через `unsafePerformIO`. Race conditions, недетерминированный порядок инициализации. Phase 2 не начата.

### H2. 299 предупреждений компилятора (207 redundant patterns, 117 unused bindings)

**Сборка:** 0 ошибок, но 299 предупреждений. Из них:
- 207 — избыточные паттерн-матчи (мёртвый код в логике ветвления)
- 117 — неиспользуемые bindings (параметры функций, let-bindings)

Топ неиспользуемых: `ti` (12), `ts` (8), `tp` (8), `ss` (8), `nom` (6), `ss0` (4), `semanticFrame` (4), `selfState` (4).

**Риск:** Избыточные паттерн-матчи означают, что ветки логики никогда не выполняются — это скрытые мёртвые пути. Неиспользуемые параметры `ss`/`ti`/`ts`/`tp` в TurnPipeline означают, что функции получают состояние, но не используют его — pipeline может работать на stale данных.

### H3. SystemState продолжает расти — 757 LOC, ~85 полей

**Файл:** `src/QxFx0/Types/State/System.hs`

Добавлено поле `ssRuntimeGraph :: !AtomGraph` (новый god-record field). SystemState теперь импортирует `Semantic.Content.AtomStore`, создавая новую циклическую зависимость между Types и Semantic. Ранее отмеченный «god-record с ~50 полей» теперь ~85 полей.

**Новая циклическая зависимость:** `Types.State.System` → `Semantic.Content.AtomStore` → `Semantic.Network.Substrate` → (косвенно) `Types.*`. Это усугубляет корневую причину циклических зависимостей.

### H4. Round-trip serialization gap: 361 ToJSON vs 328 FromJSON (33 write-only)

Предыдущий аудит: 49 write-only типов. Текущий: 33 write-only (улучшение, но не закрыто). Система всё ещё пишет данные, которые не может прочитать обратно. Новые типы AtomStore имеют `FromJSON` — это хорошо, но 33 типа всё ещё без обратного чтения.

---

## MEDIUM

### M1. Stale comment: «Uses seedGraph for now» — но код передаёт runtimeGraph

**Файл:** `src/QxFx0/Render/Dialogue.hs:1853`

```haskell
-- Uses seedGraph for now; runtimeGraph integration in Step A5.
-- ...
genSurface = composeDefinition morph fp 3 runtimeGraph (AtomId topic)
```

Комментарий говорит «seedGraph for now», но код передаёт `runtimeGraph`. Это документация, которая лжёт о коде — тот же паттерн «documentation–reality gap».

### M2. Новые тесты проверяют структуру, не качество контента

**78 новых ассертов** в 4 тест-файлах. Паттерны:
- `assertBool "non-empty text"` — проверяет, что текст не пустой
- `assertBool "contains 'свобода'"` — проверяет наличие слова, но не релевантность
- `assertEqual "all relations have topic" True` — проверяет структуру, не семантику

Ни один тест не проверяет:
- Грамматику сгенерированного текста
- Связность (определение → контраргумент → синтез)
- Точность (соответствие графу отношений)
- Отсутствие substrate в выводе (Gate G5 не тестируется end-to-end)
- Что ответ на «что такое свобода» действительно о свободе

### M3. 14+ silent error swallowing sites — НЕ ИСПРАВЛЕН

Те же 9+ сайтов `_ -> pure ()` в Engine, Governance, SQLite, Datalog, TxStatement. Ни один не был исправлен с прошлого аудита.

---

## INFO

### I1. ADR directories empty — НЕ ИСПРАВЛЕН

### I2. Bayesian + GameTheory explicitly NOT wired — без изменений

---

## Мета-паттерн: «декоративная безопасность»

Новый мета-паттерн, обнаруженный в этом аудите: **система строит механизмы безопасности/качества, тестирует их изолированно, но не подключает к основному пути выполнения.**

| Механизм | Построен | Тесты есть | Подключён? |
|----------|----------|------------|------------|
| Gate G1-G5 (GeneratedPredicateGate) | ✅ 180 LOC | ✅ 24 ассерта | ❌ в composeDefinition, ✅ в composeArgument |
| NixGuard restricted mode | ✅ | ✅ | ❌ silent fallback |
| Content quality gate | ❌ | ❌ | ❌ |
| Round-trip FromJSON | частично | частично | частично |

**Принцип:** Наличие тестов на механизм не означает, что механизм работает в продакшене. Тесты на гейтах проверяют гейты в изоляции, но не проверяют, что гейты вызываются из `composeDefinition`. Это **тесты труб, а не воды** — тот же мета-паттерн из предыдущих аудитов, теперь в новом контексте.

---

## Что изменилось с прошлого аудита

| Проблема | Прошлый аудит | Сейчас | Тренд |
|-----------|--------------|--------|-------|
| Write-only types | 49 | 33 | ↑ улучшение |
| unsafePerformIO | 5 модулей | 6 модулей | ↓ ухудшение |
| Silent swallowing | 14 сайтов | 14 сайтов | → без изменений |
| NixGuard fail-open | найдено | не исправлено | → без изменений |
| SystemState size | ~50 полей | ~85 полей | ↓ ухудшение |
| Warnings | не считалось | 299 | ? неизвестно |
| Content quality gate | отсутствует | отсутствует | → без изменений |
| Gate enforcement | N/A | частичное | ↓ новая проблема |

## Рекомендации (приоритезированные)

1. **C1: Подключить gate verdict в composeDefinition** — заменить `_gateVerdict` на проверку `if gvOverall combinedVerdict then ... else GeneratedSurface "" [] []`. 1 строка.
2. **C2: NixGuard fail-closed** — при отсутствии `--restricted` возвращать `Blocked`, не fallback.
3. **H2: Включить `-Werror` для redundant patterns и unused bindings** — 299 предупреждений скрывают мёртвый код.
4. **H3: Вынести `ssRuntimeGraph` из SystemState** — в отдельный runtime-контекст, не god-record.
5. **M1: Удалить stale comment** — или обновить, или удалить.
6. **M2: Добавить end-to-end тест** — `composeDefinition` → проверить, что Gate G5 блокирует substrate в выводе.
