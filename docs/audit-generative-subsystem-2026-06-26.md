# Аудит генеративной подсистемы — 2026-06-26

**Дата:** 2026-06-26
**Коммит:** 17f8c3d (после cleanup)
**Объём аудита:** ~4000 LOC generative modules + integration points

## Резюме

| # | Находка | Серьёзность | Статус |
|---|---------|-------------|--------|
| G-1 | `checkTopicRelevanceBlock` не подключён к `firstBlockingCheck` | **КРИТИЧНАЯ** | NEW |
| G-2 | `composeDefinitionWithGates` — мёртвый код (экспортируется, тестируется, не вызывается) | Средняя | Known |
| G-3 | Старый путь `renderDialogueArtifact` -> `structuredBody` (строки 490-686) использует unguarded `selectPredicates`/`lookupDefinitionContent` | Средняя | Known |
| G-4 | `SystemState` god-record: 77 уникальных полей (включая `ssRuntimeGraph`) | Средняя | Known |
| G-5 | `composeArgument` не проходит gate validation (нет `validatePath` для аргументов) | **КРИТИЧНАЯ** | NEW |
| G-6 | `guessRelationType` fallback на `RelIsA` для неизвестных глаголов | Низкая | Known |

## Детали находок

### G-1: `checkTopicRelevanceBlock` не подключён (КРИТИЧНАЯ)

**Файл:** `src/QxFx0/Core/Guard/ContentQuality.hs`

Функция `checkTopicRelevanceBlock` реализована (строка 131) и работает:
проверяет overlap токенов с topic для outputs с 6+ токенами.
Однако она **отсутствует** в списке `firstBlockingCheck` (строки 57-63):

```haskell
firstBlockingCheck =
  foldr orElse Nothing
    [ checkEmpty trimmed
    , checkTemplatePlaceholders rendered
    , checkGenericFiller trimmed
    -- <-- ЗДЕСЬ ДОЛЖНО БЫТЬ: checkTopicRelevanceBlock rendered topic
    , checkContentDensity tokens
    , checkSemanticSaturation tokens
    ]
```

На её месте — пустая строка. Память утверждает, что Н-3 исправлен, но это
**представление без исполнения** — классический representation-execution gap (L5 principle).

**Воздействие:** Output может быть полностью не связан с темой и пройдёт
content quality gate, если он не пустой, не содержит шаблонных плейсхолдеров
и не состоит только из filler-фраз.

**Исправление:** Добавить `checkTopicRelevanceBlock rendered topic` в список
`firstBlockingCheck`.

### G-2: `composeDefinitionWithGates` — мёртвый код

**Файл:** `src/QxFx0/Semantic/Content/PathFinder.hs:407`

Функция экспортируется и тестируется, но **не вызывается** из production-кода.
Production использует `composeDefinition`, которая имеет gate enforcement внутри.
`composeDefinitionWithGates` дублирует логику с другой сигнатурой `(Text, Int, Int)`.

**Рекомендация:** Удалить или объединить с `composeDefinition`.

### G-3: Старый путь `structuredBody` — unguarded fallback

**Файл:** `src/QxFx0/Render/Dialogue.hs:371+`

Production pipeline в `Render.hs:310-320`:
1. `viaSemantic` (generateFromFrame) — приоритетный путь, gated
2. `viaAssembly` — fallback
3. `renderDialogueArtifact` -> `structuredBody` — последний fallback

`structuredBody` (строки 490-686) использует `selectPredicates` и
`lookupDefinitionContent` **без** gate validation. `finalizeOutputWithTopic`
всё равно применяется, но topic coherence не работает (см. G-1).

**Рекомендация:** Документировать как известный долг или добавить gate.

### G-4: SystemState god-record — 77 полей

**Файл:** `src/QxFx0/Types/State/System.hs`

77 уникальных полей `ss*`, включая `ssRuntimeGraph`. Root cause круговых
зависимостей. **Статус:** Known structural debt (Phase 3 roadmap).

### G-5: `composeArgument` не валидирует через gates (КРИТИЧНАЯ)

**Файл:** `src/QxFx0/Semantic/Content/PathFinder.hs:443-497`

`composeDefinition` вызывает `validatePath` и возвращает пустую поверхность
при gate failure. Однако `composeArgument` **не вызывает** `validatePath`
для своего результата. Возвращается `GeneratedSurface fullText allProofs allSources`
без gate проверки.

**Воздействие:** Аргументы challenge-response могут содержать
SubstrateExtractedRaw edges (G4 violation) или тавтологические edges (G2).

**Исправление:** Добавить `validatePath` для `combinedProof` в `composeArgument`,
аналогично `composeDefinition`.

### G-6: `guessRelationType` fallback на `RelIsA`

**Файл:** `src/QxFx0/Semantic/Content/SubstrateCandidate.hs:340`

Для неизвестных глаголов возвращается `RelIsA`. Низкий риск — admission
verb whitelist фильтрует неизвестные глаголы. **Рекомендация:** `RelRelatedTo`
как более нейтральный fallback.

## Положительные находки

1. **Gate enforcement в `composeDefinition`: РАБОТАЕТ** — `validatePath` вызывается.
2. **`generateFromFrame`: fail-closed** — placeholder при пустом результате.
3. **NixGuard: fail-closed** — пустой concept -> Blocked.
4. **Substrate pipeline: properly gated** — `SubstrateExtractedRaw` блокируется G4.
5. **Тесты gate enforcement существуют** — `gateEnforcementTests`.
6. **Нет `unsafePerformIO`** в generative modules.
7. **`finalizeOutputWithTopic`** применяется к финальному output.

## Архитектура потока

```
Input -> semanticIntent -> buildFrame -> generateFromFrame
  -> composeDefinition (gated: G1-G5 via validatePath)
  -> composeArgument (NOT gated -- G-5)
  -> semanticText
  -> finalizeOutputWithTopic (content quality: empty/template/filler/density/saturation)
  -> BUT topic coherence NOT checked (G-1)

Fallback chain:
  1. viaSemantic (gated) -> 2. viaAssembly -> 3. renderDialogueArtifact (unguarded, G-3)
```

## Приоритеты исправления

1. **G-1:** Подключить `checkTopicRelevanceBlock` — 1 строка, блокирующая находка
2. **G-5:** Добавить `validatePath` в `composeArgument` — ~5 строк, блокирующая находка
3. **G-2:** Удалить `composeDefinitionWithGates` — cleanup
4. **G-3:** Документировать или добавить gate в `structuredBody`
5. **G-6:** Изменить fallback `guessRelationType` на `RelRelatedTo`
6. **G-4:** SystemState decomposition (Phase 3 roadmap)
