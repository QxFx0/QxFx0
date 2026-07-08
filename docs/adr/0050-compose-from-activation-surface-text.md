# ADR-0050: Full `composeFromActivation` Integration into Surface Text

**Status:** Proposed  
**Date:** 2026-07-08  
**Replaces:** acknowledged tech debt item #1 from post-audit fix round  
**Related:** ADR-0011 (Deliberation), ADR-0009 (Field), Axis 2 Spreading Activation spec

---

## Problem Statement

`composeFromActivation` (`Semantic/ContentSelector.hs:96–120`) returns `[SemanticPredicate]`
(top-3 predicates from activation-composed multi-topic traversal), but **no rendering
path consumes its output**. The semantic-first rendering path in `generateFromFrame`
(`Render/Dialogue.hs:1904`) calls `semanticSupplement` → `selectPredicates` (single-topic,
single-best-predicate), not `composeFromActivation` (multi-topic, top-3). The spreading
activation result is computed and discarded — or never computed at all in the live
render path.

Two parallel semantic worlds exist with **zero bridge**:

```
World A (Legacy): AtomGraph / Relation / PropositionParser / GraphEngagement
    → ContextualComposer → composeContextual → GeneratedSurface (verb + relation edges)
    → [DEAD CODE — excised in commit 442007a]

World B (Semantic-first): SemanticNetwork / ContentSelector
    → composeFromActivation → [SemanticPredicate]
    → [STOP — no consumer]
    → generateFromFrame → appendSupplement → flat Text from spRu strings
```

**Goal:** Build a bridge from `composeFromActivation`'s multi-topic `[SemanticPredicate]`
output to surface Russian text, then wire it as the primary generation path in
`generateFromFrame`.

---

## Design

### Phase 1: `accumulateSurface` — Predicate→Text Verbalizer

**New module:** `QxFx0.Semantic.SurfaceAccumulator`

**Signature:**
```haskell
accumulateSurface
  :: MorphologyData        -- for case/declension resolution
  -> Field                  -- for tone/stance modulation
  -> [SemanticPredicate]    -- ranked predicates from composeFromActivation
  -> Text                   -- flat Russian surface text
```

**Algorithm:**

1. For each `SemanticPredicate` in order:
   a. Extract `spRu` (base Russian text, e.g. "свобода предполагает возможность выбора")
   b. Resolve topic form via `spTopicForm` and `MorphologyData` (declension to
      Nominative/Genitive as appropriate)
   c. Apply stance modulation from `Field`:
      - High confidence (>0.7): wrap in confidence marker ("Известно, что ...")
      - High counterfactual (>0.6): wrap in counterfactual marker ("Но вместе с тем ...")
      - High angst (>0.7): add hedging ("возможно, ...")
      - Low conatus (<5.0): shorten to only highest-weight predicate
   d. Deduplicate: skip predicates textually identical to already-emitted ones
      (via `T.isInfixOf` on normalized lowercase)

2. Join with conjunctions, NOT concatenation:
   - Same topic as previous predicate → `". Кроме того, "` (additive)
   - Different topic → `". Вместе с тем, "` (contrastive join)
   - Irreducible contradiction (spSynthesis present) → `". Однако "` (adversative),
     then append synthesis at end

3. Wrap in frame-specific framing prefix:
   - DefinitionFrame: no extra wrap (predicates ARE the definition)
   - ChallengeFrame: `"Я вижу это так: "` prefix
   - ReflectFrame: `"Когда я думаю о <topic>, "` prefix
   - DistinctionFrame: `"Различая <left> и <right>: "` prefix

**No sentence planning, no GF grammar.** This is a data-driven verbalizer: it takes
existing `spRu` strings and uses conjunction markers + Field-modulated stance
wrappers to assemble a coherent multi-predicate surface. The sentence-level
grammar is already encoded in `spRu` — the verbalizer only handles inter-predicate
coherence.

**Why no GF sentence planning:** Full GF-based sentence planning requires building
`Utterance` ASTs with RGL agreement, linearization to every grammatical case, and
coordination rules for multi-clause structures. This is a separate architectural
feature (estimated 2–4 weeks). The proposed `accumulateSurface` is a ~200-line
pragmatic solution that yields multi-predicate output immediately.

---

### Phase 2: Wire into `generateFromFrame`

**File:** `src/QxFx0/Render/Dialogue.hs` (lines 1904–2054)

**Change for DefinitionFrame, ChallengeFrame, ReflectFrame, DistinctionFrame:**

```haskell
-- BEFORE (current):
semanticSupplement cs field topic mNetwork isEn
-- calls selectPredicates (single topic, single predicate)

-- AFTER:
case mNetwork of
  Just network | spreadingActivationActive -> do
    let composed = composeFromActivation cs field topic network
    if null composed
      then semanticSupplement cs field topic mNetwork isEn  -- fallback to single-predicate
      else accumulateSurface morph field composed
  _ -> semanticSupplement cs field topic mNetwork isEn  -- no network available
```

**Feature flag:** `spreadingActivationActive :: Bool` — constant `True` in
`QxFx0.Semantic.Network` (matches existing pattern: `substrateEnabled = True`,
`contentSalienceActive = True`). Default-on, default-off tested via flag toggle
in anti-rot tests.

**Fallback chain:**
1. `composeFromActivation` + `SemanticNetwork` available → `accumulateSurface`
2. `composeFromActivation` returns empty (no overlapping topics) → `selectPredicates`
   (single-topic, as today)
3. No `SemanticNetwork` available → `selectPredicates` (as today)
4. No predicates at all → current hardcoded fallback strings (for gate failure)

---

### Phase 3: Frame-specific verbalization modes

`accumulateSurface` accepts a `VerbalizationMode` parameter:

```haskell
data VerbalizationMode
  = VmDefinition    -- topic-centric: "свобода — это ..."
  | VmChallenge     -- stance-bearing: "Я вижу это так: ..."
  | VmReflection    -- meditative: "Когда я думаю о ..., "
  | VmDistinction   -- contrastive: "Различая X и Y: ..."
```

The mode controls:
1. Framing prefix (see Phase 1)
2. Whether to include `spRationale` for each predicate (`VmDefinition` = yes,
   others = no)
3. Whether to include `spSynthesis` for contradictions (`VmDefinition`,
   `VmReflection` = yes; `VmChallenge` = no)
4. Maximum predicate count (`VmDefinition`: 3, `VmChallenge`: 1–2,
   `VmReflection`: 2, `VmDistinction`: 1 per side)

---

### Phase 4: Anti-rot test suite

**New file:** `test/Test/Suite/SpreadingActivationSurface.hs`

Test categories:

1. **Basic verbalization:** `accumulateSurface` with 3 predicates from same topic
   → produces `A. Кроме того, B. Кроме того, C.`
2. **Cross-topic verbalization:** predicates from 2 topics → `A. Вместе с тем, B.`
3. **Contradiction synthesis:** predicates with `spSynthesis` → `A. Однако B. <synthesis>.`
4. **Stance modulation:** High confidence (>0.7) → "Известно, что ..." wrapper
5. **Stance modulation:** High counterfactual → "Но вместе с тем ..." wrapper
6. **Low conatus truncation:** conatus < 5.0 → only highest-weight predicate
7. **Empty result fallback:** empty `[SemanticPredicate]` → "" (caller falls
   through to selectPredicates)
8. **Deduplication:** duplicate predicates skipped
9. **End-to-end integration:** `generateFromFrame` with `SemanticNetwork` →
   multi-predicate output
10. **Flag-disabled:** `spreadingActivationActive = False` → falls back to
    `selectPredicates` (current behavior preserved)
11. **Determinism:** same inputs → same output (no randomness)

**Golden tests:** 5 golden inputs with expected output strings in
`test/golden/spreading_activation_surface.jsonl`.

---

## Files Affected

| File | Change |
|------|--------|
| `src/QxFx0/Semantic/SurfaceAccumulator.hs` | **New module** — `accumulateSurface`, `VerbalizationMode` |
| `src/QxFx0/Render/Dialogue.hs` | Wire `composeFromActivation` + `accumulateSurface` into 4 frame handlers |
| `src/QxFx0/Semantic/Network.hs` | Export `spreadingActivationActive :: Bool` |
| `qxfx0.cabal` | Register new module + new test suite module |
| `test/Test/Suite/SpreadingActivationSurface.hs` | **New test suite** (11 test categories) |
| `test/golden/spreading_activation_surface.jsonl` | **New golden file** (5 entries) |
| `test/TestMainFast.hs` | Import new test suite |

---

## Non-Goals (explicitly deferred)

1. **GF-based sentence planning** — requires `Utterance` AST, RGL coordination,
   multi-clause linearization. Separate ADR.
2. **English surface accumulation** — Russian only. English path can reuse the
   same verbalizer with `spEn` instead of `spRu`.
3. **Contextual dialogue threading** — predicates are assembled per-turn only;
   no cross-turn coherence tracking beyond what `SemanticNetwork` activation
   already provides.
4. **Substrate-edge-driven surface** — substrate edges route spreading activation
   only; output predicates come exclusively from explicit layer. This preserves
   the existing substrate≠output doctrine.
5. **ChallengeFrame full argumentation** — the existing `challengeResponseCorpus`
   keyword-triggered path remains as-is; `composeFromActivation` supplements
   with broader predicate selection but does not replace the structured
   challenge-response format.
6. **`structuredBody` update** — the legacy template path (`structuredBody` in
   `Dialogue.hs:444−795`) is not modified. Only `generateFromFrame` semantic-first
   path gets the new wiring.

---

## Verification Gates

- [ ] `cabal build qxfx0` passes clean (no warnings)
- [ ] `cabal test qxfx0-test-fast` passes all tests (existing + new tests)
- [ ] **Golden tests (critical):** 5 surface outputs match expected strings — human-validated against linguistic quality criteria
- [ ] Determinism test: same `(network, field, topic)` triple → identical output across 10 runs
- [ ] Flag-disabled test: `spreadingActivationActive = False` → output identical to pre-fix baseline (no regression)
- [ ] Live session manual check: философский запрос → multi-predicate output без пунктуационных или согласовательных ошибок
- [ ] **Semantic compatibility test:** top-3 предиката из `composeFromActivation` семантически проверены на совместимость (dialectical пары обрабатываются adversative-конъюнкциями, не additive)
- [ ] Fallback chain: удалён `brain_kb.jsonl` → нет `SemanticNetwork` → fallback на `selectPredicates` single-predicate path

---

## Review Amendments (2026-07-08)

1. **Scope reduction (MVP first):** Phase 4 тесты — сокращены с 11 категорий до 5 critical tests.
   Начать с одного `VerbalizationMode` (`VmDefinition`), остальные режимы по мере необходимости.
2. **Лингвистическое качество:** `T.isInfixOf` deduplication и фиксированные конъюнкции — признаны
   ограниченными. Golden tests должны включать human-validated expected output. Пунктуация и
   согласование должны проверяться вручную на живых сессиях.
3. **Dialectical predicate handling:** Топ-3 предиката могут быть семантически несовместимы
   (additive vs dialectical пары). `accumulateSurface` должен различать: additive — `". Кроме того, "`,
   dialectical — `". Однако "` (с synthesis). Проверяется в golden tests.
4. **Estimate revised:** 1–2 рабочих дня (не «200 строк»). `VerbalizationMode` adds hidden complexity.