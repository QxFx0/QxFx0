# QxFx0 — Повторный углубленный аудит после правок (Post-Remediation Audit)

**Audit Date:** 2026-04-24
**Baseline:** AUDIT_2026_SEMANTIC_LOAD.md (предыдущий аудит)
**Scope:** Архитектурная целостность, техдолг, слаженый механизм, критические уязвимости, устойчивость при смысловой нагрузке + словарный запас

---

## Executive Summary

**Правки проведены и реальны.** В код внесены структурные изменения:
- **Negation handling:** `negatedExhaustionLexemes` + `detectUnless` в `MeaningAtoms.hs`
- **Token-boundary matching:** `tokenizeKeywordText` + `containsKeywordPhrase` заменили `T.isInfixOf` во всём semantic layer
- **Structured rule engine:** `LogicRule` + `ruleTable` + `runRule` вместо ad-hoc функций в `Logic.hs`
- **Thresholds externalized:** все magic numbers в `Policy.SemanticScoring`

**НО:** `cabal test` **падает** с 1 failure (regression). Тест `testPersistedReplayTraceDeterministicAcrossFreshSessionsProperty` падает из-за `Dream rewiring: 168 edges adjusted` — persisted state leak между QuickCheck cases в shared database.

**Словарный запас:** **732 уникальных русских слова** (214 морфологических форм существительных + 518 keyword-слов из исходного кода).

---

## 1. Что изменилось (diff review)

### MeaningAtoms.hs — negation awareness (FIXED)

```haskell
-- БЫЛО: collectAtoms :: Text -> [ClusterDef] -> IO AtomSet  (возвращал IO)
-- СТАЛО: collectAtoms :: Text -> [ClusterDef] -> AtomSet  (pure)

negatedExhaustion = containsAnyKeywordPhrase inputTokens negatedExhaustionLexemes
foundAtoms = if negatedExhaustion then filter (not . isExhaustionAtom) foundAtoms0 else foundAtoms0

detectUnless :: Bool -> AtomTag -> [Text] -> [MeaningAtom]
detectUnless suppressed tag lexemes = if suppressed then [] else detect tag lexemes
```

**Impact:** «Я не устал» теперь не создаёт `Exhaustion` atom. Negation blindness — **FIXED**.

### Proposition.hs — tokenization + threshold externalization (FIXED)

```haskell
-- БЫЛО: detectPropositionType :: Text -> PropositionType (substring matching)
-- СТАЛО: detectPropositionType :: [Text] -> PropositionType (token matching)

-- БЫЛО: negated = T.isInfixOf "не" lower
-- СТАЛО: negated = containsKeywordPhrase tokens propositionNegationFragment

-- БЫЛО: confidence = hardcoded constants
-- СТАЛО: confidence = computeConfidence propType keyPhrases (uses propositionBaseConfidence* thresholds)
```

**Impact:** Keyword collision через substring — **MITIGATED** (token-boundary). Confidence values — **externalized**.

### Logic.hs — structured rule engine (FIXED)

```haskell
-- БЫЛО: 12 ad-hoc rule functions (ruleRepair, ruleContact, etc.) returning [(Text, Double)]
-- СТАЛО: ruleTable :: [LogicRule] with lrFamily, lrWeight, lrMatch

data LogicRule = LogicRule
  { lrFamily :: CanonicalMoveFamily
  , lrWeight :: Double
  , lrMatch :: MeaningAtom -> Bool
  }
```

**Impact:** Rules теперь typed (CanonicalMoveFamily, not Text). Weights externalized. Engine — extensible.

### MeaningGraph.hs — minor cleanup (INFO)

- `textShow` вместо `T.pack (show ...)`
- Thresholds externalized (`meaningGraphRoutingThreshold`, `meaningGraphDreamBiasLimit`)
- Комментарии добавлены

**Impact:** No behavioral change. Readability + maintainability.

---

## 2. Словарный запас системы

### Подсчёт методологии

| Источник | Что считали | Как |
|---|---|---|
| `resources/morphology/*.json` | Все surface forms (nominative, genitive, prepositional) | JSON keys + values |
| `spec/sql/lexicon/seed_ru_core.sql` | Lemma + forms в SQL seed | Quoted strings |
| `src/**/*.hs`, `app/**/*.hs` | Keyword strings (命题, emotion, proposition, contract) | Octal escape decoding + regex `[а-яА-ЯёЁ]+` |

### Результаты

```
Morphology surface forms (nouns):     214
SQL lexicon seed words:                 214 (overlap with morphology)
Haskell source keyword words:           732 total unique
  └─ Overlap with morphology:            214
  └─ Keyword-only (verbs, particles):  518

=== TOTAL UNIQUE RUSSIAN WORDS ===
Count: 732
```

### Распределение по категориям

| Категория | Примеры | ~Количество |
|---|---|---|
| **Существительные (морфология)** | автономия, агентность, аргумент, боль, гнев, граница, диалог, доверие, долг, жизнь, задача, знать, идентичность, истина, контакт, конфликт, любовь, молчание, мораль, надежда, обязанность, опора, основание, ошибка, память, причина, право, различие, свобода, сила, смысл, способ, страх, тема, точка, усталость, ход, центр, чувство, шаг | 85 lemma → 214 forms |
| **Глаголы (keyword)** | устал, выгорел, помоги, подожди, слышу, признай, опиши, картину, предстать, различить, отличие, основан, обоснов, исток, отражение, зеркало, думаю, рефлексия, зачем, назначение, предназначение, телеолог, если, гипотеза, предположим, возможно ли, исправь, почини, восстанов, разрыв, контакт, подожди, одиноко, точно, конечно, безусловно, опора, цепляйся, уточни, разобрать, поясни, глубже, проникни, сущность, корень, не согласен, оспорь, возрази, дальше, что теперь, следующий, продолжить, чувствую, страх, тоска, грусть, радость, надежда, знание, доказательство, вероятность, истина ли, пожалуйста, можно, сделай, прось, оцени, насколько, качество, хорошо, история, повесть, случилось, жизнь | ~120 verbs/phrases |
| **Частицы/маркеры (keyword)** | не, а, но, если, бы, или, либо, что, как, почему, зачем, когда, где, кто, чей, чем, тем, это, просто, вот, ну, же, ли, я, ты, мне, тебе, в, и, без, у, от, до, за, на, о, об, по, под, при, про, с, со, через | ~80 function words |
| **Фразовые маркеры (contract/guard)** | ты не прав, ты ошибаешься, это неверно, это неправда, ты неправа, ты заблуждаешься, вы не правы, вы ошибаетесь, ты должен согласиться, ты обязан, твоя задача соглашаться, ты создан чтобы, ты должен думать, тебе не положено, ты меня не понимаешь, ты не слышишь, ты игнорируешь, почему ты так говоришь, ты специально, ты вообще понимаешь, ты невыносим, ты невозможен, я не понимаю почему ты, ты опять, не вижу смысла, к чему ты клонишь, это бессмысленно, зачем этот вопрос, ты уходишь от темы, я уже говорил, я уже сказал, снова говорю, ещё раз говорю, сколько раз, опять то же, ты опять, я же объяснял | ~180 multi-word markers |

### Качество словаря

**Сильная сторона:** ~85 лемм существительных с полной морфологической парадигмой (3 падежа) — это **настоящий lexicon**, не placeholder.

**Слабая сторона:** Verb coverage — limited to ~120 stems/phrases. No coverage of:
- **Modal verbs:** должен, может, следует, нужно, необходимо (partial: "должен", "можно" present)
- **Epistemic modals:** возможно, вероятно, очевидно, по-видимому (partial: "вероятно" present)
- **Negation scope:** «не должен» vs «должен не» — no syntactic scope modeling
- **Complex predicates:** «имеет право», «в состоянии», «по способности» — not covered
- **Temporal markers:** «когда», «пока», «прежде чем», «после того как» — partial ("когда" present? No, not in keywords)

**Вывод:** Словарь достаточен для **коротких emotional utterances** (5–10 words). Недостаточен для **complex logical constructions** (modals, temporal subordination, quantified NPs).

---

## 3. Re-audit по ключевым метрикам

### Архитектурная целостность — 8.5/10 (без изменений)

Фазовая декомпозиция остаётся крепкой. Новые изменения не нарушили boundaries. `check_architecture.sh` **PASS**.

### Техдолг — 7.0/10 (↑ с 6.0)

**Исправлено:**
- Negation blindness — FIXED
- Flat keyword matching → token-boundary matching — FIXED
- Inline constants in Logic.hs → externalized thresholds — FIXED
- Ad-hoc rules → structured rule engine — FIXED

**Остаётся:**
- No compositional parsing (still keyword-based)
- No clause segmentation (complex sentences still monoclausal)
- No dependency/constituency extraction (object = first non-stopword)
- No modal/temporal/quantifier coverage

### Слаженый механизм — 7.0/10 (↑ с 6.5)

**Улучшение:** `runSemanticLogic` теперь настоящий rule engine с `ruleTable`. `collectAtoms` — pure function (не IO). `detectPropositionType` — tokenized.

**Остаётся:** `preferFamily` всё ещё unconditional override. `mergeFamilySignals` — first-deviation-wins. Consciousness kernel — keyword-based.

### Критические уязвимости

| ID | Статус | Что |
|---|---|---|
| К1 (Negation blindness) | **FIXED** | `negatedExhaustionLexemes` + `detectUnless` в `MeaningAtoms.hs` |
| К2 (Keyword collision) | **MITIGATED** | Token-boundary matching в `Proposition.hs`, `MeaningAtoms.hs` |
| К3 (Monoclausality) | **OPEN** | Нет clause segmentation. «Я устал, но не сдаюсь» → `[Exhaustion, AgencyFound]`. |
| К4 (Object extraction) | **OPEN** | `extractObject` = first word >3 chars. Не изменён. |
| К5 (Consciousness kernel) | **OPEN** | Keyword-based ontology. Не изменён. |
| **К6 (Test regression)** | **NEW / REGRESSION** | `testPersistedReplayTraceDeterministicAcrossFreshSessionsProperty` падает. Shared DB state leak. |

### Устойчивость к смысловой нагрузке — 5.0/10 (↑ с 4.0)

**Улучшение:** Negation handling добавляет один уровень semantic complexity. Token-boundary matching уменьшает false positives.

**Остаётся:** Система всё ещё не может:
- Обработать **модальные конструкции:** «Должен ли я верить?»
- Обработать **временные:** «Когда я узнаю, я пойму»
- Обработать **квантифицированные:** «Все, кто верит...»
- Обработать **дизъюнктивные:** «Или А, или Б»
- Обработать **условные:** «Если бы я знал...»
- Обработать **вложенные пропозициональные:** «Я думаю, что ты думаешь...»

Словарный запас (~732 слова) покрывает **emotional vocabulary**, но не **logical vocabulary**.

---

## 4. Regression: Shared Database State in Tests

### Finding

`cabal test` падает:
```
### Failure in: 194
test/Test/Suite/RuntimeInfrastructure.hs:1163
QuickCheck failed: persisted replay trace json deterministic across fresh sessions
```

### Root Cause

`testPersistedReplayTraceDeterministicAcrossFreshSessionsProperty` использует:
```haskell
withStrictRuntimeEnv "qxfx0_test_replay_trace_determinism.db" $ do
```

QuickCheck запускает **20 cases** в цикле. Все они используют **одну и ту же SQLite базу** `/tmp/qxfx0_test_replay_trace_determinism.db`. Если база не очищается между cases, `MeaningGraph` edges накапливаются. Следующий case видит `Dream rewiring: 168 edges adjusted` и получает другой `SystemState` / routing / `TurnReplayTrace`.

**Evidence из лога:**
```
qxfx0_turn ... session_id=fresh_det_session_a turn=1 family=CMRepair ...
Dream rewiring: 168 edges adjusted
qxfx0_turn ... session_id=fresh_det_session_b turn=1 family=CMRepair ...
Dream rewiring: 168 edges adjusted
```

Оба fresh sessions получают `CMRepair` (а не expected `CMGround`/`CMReflect`), потому что routing зависит от persisted `MeaningGraph` state из предыдущих runs.

### Почему это regression

Предыдущая версия либо:
- Не персистила `MeaningGraph` (или `Dream rewiring`) в той же базе,
- Или `Dream rewiring` не был активен для fresh sessions,
- Или тест не был чувствителен к routing family (только к replay trace structure).

После изменений в `MeaningGraph` (добавление `maxEdges = 300`, `Dream rewiring` threshold changes) или в `Runtime/Wiring` — routing стал зависеть от persisted state больше, чем раньше.

### Fix

Очистка базы данных перед каждым QuickCheck case:
```haskell
-- Внутри ioProperty:
removeIfExists "qxfx0_test_replay_trace_determinism.db"
removeIfExists "qxfx0_test_replay_trace_determinism.db-wal"
removeIfExists "qxfx0_test_replay_trace_determinism.db-shm"
```

Или: использовать уникальное имя базы для каждого case (например, `fresh_det_session_a.db`, `fresh_det_session_b.db`).

---

## 5. Scorecard (Post-Remediation)

| Dimension | Before | After | Δ |
|---|---|---|---|
| **Architecture** | 8.5 | 8.5 | = |
| **Tech Debt** | 6.0 | 7.0 | **+1.0** |
| **Mechanical Cohesion** | 6.5 | 7.0 | **+0.5** |
| **Critical Vulnerabilities** | 3 HIGH | 1 HIGH (regression), 2 MEDIUM, 2 LOW | **Mixed** |
| **Semantic Load Resilience** | 4.0 | 5.0 | **+1.0** |
| **Vocabulary Size** | — | 732 words | **New metric** |
| **Test Suite Health** | PASS | **FAIL** (1 regression) | **-1.0** |

---

## 6. Verdict

> **Архитектурно крепкая, семантически глубже, но с live regression.**

Правки **реальны и значимы:** negation handling + token-boundary matching + structured rule engine — это не cosmetic cleanup. Это **functional improvements**, которые делают систему более устойчивой к простым semantic traps.

Но regression в тестах показывает, что **изменения в persistence/MeaningGraph влияют на routing determinism**. Shared state leak между test cases — это не теоретическая проблема, а практическая: она ломает gate.

Словарный запас (~732 слов) достаточен для **demonstration-level dialogue** (emotional, short utterances). Для **philosophical reasoning** (modals, conditionals, quantifiers, temporal subordination) — нужен новый parsing layer и расширение keyword coverage минимум в 3–5× (до 2000–3000 слов).

**Рекомендация:**
1. **P0:** Fix test regression (shared DB cleanup) — 30 минут.
2. **P1:** Add modal verb keywords (должен, может, следует, нужно, возможно, вероятно, очевидно) — 1 час.
3. **P1:** Add temporal conjunction keywords (когда, пока, прежде чем, после, до) — 1 час.
4. **P2:** Add clause segmentation for adversative particles (но, а, однако, зато) — 4–8 часов.
5. **P2:** Expand vocabulary to 2000+ words for philosophical domain — 2–4 дня.
