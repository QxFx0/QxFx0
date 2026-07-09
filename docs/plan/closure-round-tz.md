# QxFx0 — Техническое задание: Closure Round

**Дата:** 2026-07-09
**Основание:** Финальный аудит + приоритеты после ADR-0050/0051/0052 + Variant A/C
**Диагностированный паттерн:** write-without-read ×3 (salience tuning → relation weights → atom-graph seed)

---

## P0.1 — Atom-graph seed: wiring + default-on

### Диагноз

`buildNetworkFromAtomGraph` (`Ingest.hs:360`) построен и протестирован, но `useAtomGraphSeed = False` (`Seed.hs:149`) — 311 концептов из 666 curated relations не участвуют в spreading activation. Система живёт на старом co-occurrence-графе от `seedFromCorpus` (30 тем).

### Задача

1. Включить `useAtomGraphSeed = True` по умолчанию
2. Убедиться, что сеть строится из `buildNetworkFromAtomGraph seedGraph`, а не из `seedFromCorpus`
3. Добавить `contentDensityGate` (≥50 edges, ≥15 nodes) с fallback на `seedFromCorpus` при отказе
4. Снять старый `QXFX0_USE_ATOM_GRAPH_SEED` env-var — сеть теперь всегда atom-graph

### Файлы

| Файл | Изменение |
|------|-----------|
| `src/QxFx0/Semantic/Network/Seed.hs` | `useAtomGraphSeed = True`; удалить `QXFX0_USE_ATOM_GRAPH_SEED` lookup; добавить densityGate fallback |
| `src/QxFx0/Runtime/Session/Bootstrap.hs` | Вызов `bootstrapSemanticNetwork` с `useAtomGraphSeedFlag = True` |
| `test/Test/Suite/SemanticNetwork.hs` | Обновить тесты, ожидающие старый seed (если есть) |
| `test/Test/Suite/AtomGraphSeed.hs` | Новый тест: `buildNetworkFromAtomGraph` → `contentDensityGate` → True |

### Проверка

- [ ] `cabal test qxfx0-test-fast` passes
- [ ] `snNodes` сети ≥ 311 (концепты из relations.jsonl)
- [ ] `snEdges` сети ≥ 633 (из ingest CLI вывода)
- [ ] `contentDensityGate` возвращает True
- [ ] `grep useAtomGraphSeed src/` → только `useAtomGraphSeed = True`, без env-var lookup

---

## P0.2 — Dogfooding: замер coverage дыр после wiring

### Диагноз

После включения atom-graph-сети spreading activation будет проходить по 311 концептам, но `composeFromActivation` для вербализации требует surface-предикатов (`spRu`), которые есть только у 30 тем в `definitionCorpus`. Неизвестно, сколько из 311 концептов реально активируются в типичных диалогах и сколько из них не имеют предикатов.

### Задача

1. Добавить `trcActivatedConcepts :: [Text]` в `TurnReplayTrace` — список концептов, активированных в текущем ходе (activation > 0.05)
2. Добавить `trcMissingPredicates :: [Text]` — список активированных концептов, для которых нет `spRu` в `definitionCorpus`
3. Запустить 10 диалогов на философские темы → собрать `trcMissingPredicates`
4. Составить `GAPS.md` — список концептов, требующих курации предикатов, отсортированный по частоте активации

### Файлы

| Файл | Изменение |
|------|-----------|
| `src/QxFx0/Types/Trace/TurnReplayTrace.hs` | Добавить `trcActivatedConcepts`, `trcMissingPredicates` |
| `src/QxFx0/Core/TurnPipeline/Finalize/Projection.hs` | Заполнить из `snActivation` + `definitionCorpus` lookup |
| `docs/GAPS.md` | Новый файл — результаты dogfooding |

### Проверка

- [ ] `trcMissingPredicates` непуст для ≥3 диалогов из 10
- [ ] `GAPS.md` содержит ≥5 концептов с частотой активации

---

## P1.1 — Feedback read-side: weight-overlay на persisted confidence

### Диагноз

**Write-without-read ×3.** Feedback loop изменяет `seConfidence` в `SemanticNetwork` в памяти. `System.hs:413` сериализует `ssSemanticNetwork` — confidence сохраняется. `System.hs:537` десериализует. Но `Bootstrap.hs:461` безусловно перезатирает `ssSemanticNetwork = finalNetwork` — загруженные веса выбрасываются.

Параллельно: `tuned_relation_weights.jsonl` пишется (`Precommit.hs:187`), но не читается нигде. Тот же анти-паттерн, что был с `tuned_salience_weights.json` до ADR-0051.

### Задача

1. Исправить `Bootstrap.hs:461`: если `ssSemanticNetwork` (persisted) непуст и `contentDensityGate` проходит, наложить `seConfidence` из persisted-сети на свежую `finalNetwork` как weight-overlay:
   ```haskell
   ssSemanticNetwork = overlayConfidence finalNetwork restoredNetwork
   ```
   Где `overlayConfidence` для каждого общего ребра: `seConfidence = max (seConfidence fresh) (seConfidence restored)`, остальные поля от fresh. Это защита от schema-drift: структура всегда свежая, веса — накопленные.

2. Загружать `tuned_relation_weights.jsonl` как weight-overlay в `bootstrapSemanticNetwork` (зеркало `loadTunedOrDefault` для salience):
   ```haskell
   loadRelationWeightOverlay :: FilePath -> SemanticNetwork -> IO SemanticNetwork
   ```
   Приоритет: tuned > persisted feedback > curated baseline.

3. Удалить запись `tuned_relation_weights.jsonl` из `Precommit.hs` (если она не используется для offline-анализа).

### Файлы

| Файл | Изменение |
|------|-----------|
| `src/QxFx0/Semantic/Network/Seed.hs` | `overlayConfidence`, `loadRelationWeightOverlay` |
| `src/QxFx0/Runtime/Session/Bootstrap.hs` | `overlayConfidence` на `:461`; вызов `loadRelationWeightOverlay` |
| `src/QxFx0/Core/TurnPipeline/Finalize/Precommit.hs` | Удалить запись `tuned_relation_weights.jsonl` (или оставить с комментарием) |
| `test/Test/Suite/FeedbackPersistence.hs` | Новый тест: Accept → persist → restart → confidence сохранён |
| `test/Test/Suite/RelationWeightOverlay.hs` | Новый тест: tuned JSON → overlay → confidence отличается от baseline |

### Проверка

- [ ] `cabal test qxfx0-test-fast` passes
- [ ] FeedbackPersistence: Accept в сессии → confidence рёбер +0.1 → перезапуск → confidence не сброшен
- [ ] RelationWeightOverlay: `tuned_relation_weights.jsonl` → `overlayConfidence` → edge weight изменён
- [ ] `grep tuned_relation_weights.jsonl src/` → только read-side (load) и комментарий в Precommit

---

## P1.2 — Точечная курация предикатов под GAPS.md

### Диагноз

После P0.1 + P0.2 станет известен список концептов без surface-предикатов, отсортированный по частоте активации.

### Задача

1. Для топ-20 концептов из `GAPS.md` (наибольшая частота активации) написать 1–2 `SemanticPredicate` на русском
2. Добавить в `definitionCorpus` в `Content.hs` (или в отдельный `extendedDefinitionCorpus` в `relations.jsonl`)
3. Проверить, что `composeFromActivation` теперь вербализует эти концепты

### Формат курации

Для каждого концепта:
```json
{
  "topic": "алгоритм",
  "predicates": [
    {"spRole": "RoleProperty", "spRu": "алгоритм задаёт конечную последовательность шагов"},
    {"spRole": "RoleRelation", "spRu": "алгоритм реализует вычислимую функцию"}
  ]
}
```

### Файлы

| Файл | Изменение |
|------|-----------|
| `resources/knowledge/curated_predicates.jsonl` | Новый файл — предикаты для концептов без spRu |
| `src/QxFx0/Semantic/Content.hs` | `extendedDefinitionCorpus` — загрузка из JSONL (или inline для малого числа) |
| `docs/GAPS.md` | Обновить: отметить закрытые концепты |

### Проверка

- [ ] Запрос «что такое алгоритм?» → непустой output с предикатами
- [ ] Топ-20 концептов имеют ≥1 предикат

---

## P2.1 — Selfplay: морфологическая нормализация

### Диагноз

Selfplay-relations (`selfplay_relations.jsonl`, 80 штук) содержат LLM-артефакты: `"вечность в мгновении"`, `"на возможность будущего"`, `"к обобщению и абстракции"`. Проблема на стыке LLM-экстракции (извлекает phrase, а не лемму) и GF/RGL (ожидает лемму). За флагом `QXFX0_USE_SELFPLAY = off`.

### Задача

1. Добавить `normalizeRelationText :: Text -> Text` в `Ingest.hs` — очистка предлогов, падежных окончаний, приведение к Nominative через `lookupLemmaForm`
2. Применить при загрузке selfplay-relations
3. Admission gate: `normalizeRelationText` → если результат не в `atomStore` → reject
4. Включить `QXFX0_USE_SELFPLAY = True` по умолчанию (после нормализации)

### Файлы

| Файл | Изменение |
|------|-----------|
| `src/QxFx0/Semantic/Network/Ingest.hs` | `normalizeRelationText`, admission gate с atomStore lookup |
| `src/QxFx0/Semantic/Network/Seed.hs` | `useSelfPlay = True` (после нормализации) |
| `test/Test/Suite/SelfPlayNormalization.hs` | Новый тест: `"вечность в мгновении"` → reject или нормализация |

### Проверка

- [ ] `cabal test qxfx0-test-fast` passes
- [ ] `mergeSelfPlayRelations` → rejected < 80 (часть отсеялась)
- [ ] Admission gate: `"на возможность будущего"` → reject (не в atomStore)
- [ ] `QXFX0_USE_SELFPLAY = True` → сеть содержит selfplay-рёбра

---

## P2.2 — Cross-turn coherence: inhibit emitted predicates

### Диагноз

`composeFromActivation` каждый ход заново активирует граф. Система может повторить предикат, который уже выдала 2 хода назад. `ssHistory` существует, но не влияет на semantic selection.

### Задача

1. Добавить `ssEmittedPredicates :: Set Text` в `SystemState` — `spRu` предикатов, выданных в предыдущих ходах
2. В `composeFromActivation` (или `frameSupplement`): вычитать `ssEmittedPredicates` из кандидатов
3. Очищать `ssEmittedPredicates` при смене темы (topic change detection)
4. Размер буфера: последние 5 ходов

### Файлы

| Файл | Изменение |
|------|-----------|
| `src/QxFx0/Types/State/SystemState.hs` | Добавить `ssEmittedPredicates :: Set Text` |
| `src/QxFx0/Render/Dialogue.hs` | `frameSupplement`: вычитание emitted из кандидатов |
| `src/QxFx0/Core/TurnPipeline/Finalize/State.hs` | Запись выданных `spRu` в `ssEmittedPredicates` |
| `test/Test/Suite/CrossTurnCoherence.hs` | Новый тест: 2 хода на одну тему → предикаты не повторяются |

### Проверка

- [ ] `cabal test qxfx0-test-fast` passes
- [ ] Два последовательных запроса «что такое свобода?» → разные предикаты
- [ ] Смена темы (свобода → истина) → буфер очищен

---

## P2.3 — Ontology: sibling borrowing + depth-weighting

### Диагноз

Онтология (336 нод, hierarchy) загружена, но используется только `lookupCategory`. Sibling borrowing, depth-weighted predicate selection, category-level generic predicates — не реализованы.

### Задача

1. **Sibling borrowing:** если `composeFromActivation` вернул < 2 предикатов для темы, найти sibling-темы (same parent, same category) через `lookupChildren` и добавить их предикаты с weight × 0.5
2. **Depth-weighting:** более глубокие ноды онтологии получают +10% activation boost (специфичность)
3. **Category-level predicates:** заменить hardcoded `genericDefinitionPredicates` (`Content.hs:560`) на онтологический lookup: `categoryFromOntology cat → genericPredicatesForCategory cat`

### Файлы

| Файл | Изменение |
|------|-----------|
| `src/QxFx0/Semantic/Ontology.hs` | `siblingTopics`, `genericPredicatesForCategory` |
| `src/QxFx0/Semantic/ContentSelector.hs` | `composeFromActivation`: sibling borrowing fallback |
| `src/QxFx0/Semantic/Network.hs` | `spreadActivationWithField`: depth-weight boost |
| `src/QxFx0/Semantic/Content.hs` | `classifyConceptCategory`: заменить lexical fallback на ontology категории |
| `test/Test/Suite/OntologyFull.hs` | Новый тест: sibling borrowing, depth-weighting, category predicates |

### Проверка

- [ ] `cabal test qxfx0-test-fast` passes
- [ ] Тема с 1 предикатом → sibling borrowing добавляет ещё 1–2
- [ ] `depth > 2` → +10% activation boost
- [ ] `classifyConceptCategory` → ontology-first, lexical fallback только при `Nothing`

---

## Сводный план по приоритетам

| Этап | Задача | Приоритет | Оценка | Зависит от |
|------|--------|-----------|--------|------------|
| P0.1 | Atom-graph wiring default-on | 🔴 P0 | ~1 день | — |
| P0.2 | Dogfooding: замер coverage дыр | 🔴 P0 | ~0.5 дня | P0.1 |
| P1.1 | Feedback read-side: weight-overlay | 🟡 P1 | ~1.5 дня | — |
| P1.2 | Точечная курация предикатов | 🟡 P1 | ~2 дня (ручная работа) | P0.2 |
| P2.1 | Selfplay: морфонормализация | 🟢 P2 | ~1.5 дня | — |
| P2.2 | Cross-turn coherence | 🟢 P2 | ~1 день | — |
| P2.3 | Ontology: full use | 🟢 P2 | ~2 дня | — |

**Общая оценка:** ~9.5 дней (code + curation). P0 — 1.5 дня, P1 — 3.5 дня, P2 — 4.5 дня.

---

## Финальные verification gates

- [ ] `cabal test qxfx0-test-fast` — все тесты проходят на каждом этапе
- [ ] P0.1: `snNodes` ≥ 311, `contentDensityGate` = True
- [ ] P0.2: `GAPS.md` содержит ≥5 концептов
- [ ] P1.1: Feedback confidence сохраняется между сессиями
- [ ] P1.2: Топ-20 концептов имеют ≥1 предикат
- [ ] P2.1: Selfplay-рёбра проходят admission gate
- [ ] P2.2: Повторные запросы на одну тему → разные предикаты
- [ ] P2.3: Sibling borrowing работает для тем с <2 предикатами
- [ ] `write-without-read` паттерн устранён: все три случая (salience, relation weights, feedback) имеют read-side