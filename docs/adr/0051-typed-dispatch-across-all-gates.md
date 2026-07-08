# ADR-0051: Full Typed Dispatch Across All Gates

**Status:** Proposed  
**Date:** 2026-07-08  
**Replaces:** acknowledged tech debt item #2 from post-audit fix round  
**Reference pattern:** `ExternalActionDecisionReason` in `Guardrails.hs:53-61`
(successful prior typed-dispatch refactor)

---

## Problem Statement

The audit identified 13+ dispatch sites across 7 files where `Text` string
comparison (`== "user"`, `== "symbolic"`, `== "degraded"`) controls runtime
decisions, instead of pattern-matching on algebraic sum types.

The reference successful pattern (`Guardrails.hs:53-61`) replaced:
```haskell
-- BEFORE: string dispatch
if reasonText == "guardrail_rate_limit" then ... else ...
```
with:
```haskell
data ExternalActionDecisionReason
  = AllowedRequestDriven | AllowedExploratory
  | DeniedGuardrailRateLimit | DeniedGuardrailCircuitBreaker
  | DeniedNoEligibleNeed | DeniedNoExecutableTool | DeniedNoActionSelected

-- AFTER: structural pattern match
case reason of
  DeniedGuardrailRateLimit -> ...
  DeniedGuardrailCircuitBreaker -> ...
```

The remaining untyped dispatches fall into two categories: **field-level**
(a `Text` field on a record that should be a sum type) and **local-computed**
(`Text` computed locally and immediately dispatched).

---

## Design

### Category A: `ipfSemanticTarget :: Text` → `SemanticFrameTarget` sum type

**Affected type:** `InputPropositionFrame` in `Types/InputSemantic.hs` (or
`Semantic/Input/Model.hs`)

**Affected dispatch sites (13):**
- `Core/TurnPlanning/Builders.hs:95,96,97` — `topicFromFrame`
- `Core/TurnPlanning/Builders.hs:183,187,189` — `primaryClaimFromFrame`
- `Core/TurnPlanning/Builders.hs:357,358,359` — `contrastAxisFromFrame`
- `Render/Dialogue.hs:524,530,534` — `SelfKnowledgeQ` branch
- `Render/Dialogue.hs:542` — `elem [...]` target dispatch

**New sum type:**
```haskell
data SemanticFrameTarget
  = SftUser              -- "user"
  | SftUserHelp          -- "user_help"
  | SftSelfCapability    -- "self_capability"
  | SftSelfIntentions    -- "self_intentions"
  | SftSelfValues        -- "self_values"
  | SftSelfFuture        -- "self_future"
  | SftSelfFreedom       -- "self_freedom"
  | SftSelfReflection    -- "self_reflection"
  deriving (Eq, Ord, Show, Read, Generic)

instance FromJSON SemanticFrameTarget where ...
instance ToJSON SemanticFrameTarget where ...
```

**Migration strategy:**
1. Add `SemanticFrameTarget` type to `Types/InputSemantic.hs`
2. Add JSON instances (backward-compatible: parse both string and new tagged form)
3. Change `ipfSemanticTarget :: Text` to `ipfSemanticTarget :: SemanticFrameTarget`
4. Replace `== "user"` → `SftUser`, `elem ["self_intentions", ...]` →
   `elem [SftSelfIntentions, ...]` at all 13 sites
5. Keep `Show`/`Read` instances for persistence round-trip compatibility

**`elem` consolidation for the Self-family:**
```haskell
isSelfFamily :: SemanticFrameTarget -> Bool
isSelfFamily = \case
  SftSelfIntentions -> True
  SftSelfValues -> True
  SftSelfFuture -> True
  SftSelfFreedom -> True
  SftSelfReflection -> True
  _ -> False
```
Replaces the `elem ["self_intentions", "self_values", ...]` at `Dialogue.hs:542` with
`isSelfFamily target`.

---

### Category B: `dccKind :: Text` → `DreamCandidateKind` sum type

**Affected type:** `DreamCorrectionCandidate` in `Types/DreamPressure.hs:100`

**Affected dispatch sites (6):**
- `Core/TopicDrift/Pressure.hs:188,190,192,194` — `evaluateDreamCandidateWithClasses`
   (== "symbolic", == "affective", == "conflict", == "none")
- `Core/TopicDrift/Pressure.hs:196` — `/="graph_bias"` negation
- `Core/TopicDrift/Pressure.hs:234` — `== "graph_bias"` bias application

**New sum type:**
```haskell
data DreamCandidateKind
  = DckGraphBias    -- "graph_bias"
  | DckSymbolic     -- "symbolic"
  | DckAffective    -- "affective"
  | DckConflict     -- "conflict"
  | DckNone         -- "none"
  deriving (Eq, Ord, Show, Read, Generic)

instance FromJSON DreamCandidateKind where ...
instance ToJSON DreamCandidateKind where ...
```

**Consolidated dispatch:**
```haskell
dreamKindWeight :: DreamCandidateKind -> Double
dreamKindWeight = \case
  DckSymbolic -> 0.75
  DckAffective -> 0.65
  DckConflict -> 0.55
  DckNone -> 0.0
  DckGraphBias -> 1.0    -- full weight for graph bias

isGraphBias :: DreamCandidateKind -> Bool
isGraphBias DckGraphBias = True
isGraphBias _ = False
```

---

### Category C: `npConflictPolicy :: Text` → `ConflictPolicy` sum type

**Affected type:** `NormativeProfile` in `Types/State/Perspective.hs:113`

**Affected dispatch sites (2):**
- `Self/Perspective.hs:161` — `== "invalid"` early return
- `Self/Perspective.hs:570` — `== "permissive"` penalty computation

**New sum type:**
```haskell
data ConflictPolicy
  = CpInvalid     -- "invalid"
  | CpPermissive  -- "permissive"
  | CpStrict      -- "strict" (future-proof)
  deriving (Eq, Ord, Show, Read, Generic)

instance FromJSON ConflictPolicy where ...
instance ToJSON ConflictPolicy where ...
```

---

### Category D: `eqcTransportMode :: Text` → `TransportMode` sum type

**Affected type:** `ExternalQueryConfig` in `Types/ExternalQuery.hs:80`

**Affected dispatch sites (1):**
- `Bridge/ExternalLLM.hs:448` — `== "fireworks"` transport selection

**New sum type:**
```haskell
data TransportMode
  = TmFireworks   -- "fireworks"
  | TmOpenAI      -- "openai" (future-proof)
  | TmDirect      -- "direct" (future-proof)
  deriving (Eq, Ord, Show, Read, Generic)

instance FromJSON TransportMode where ...
instance ToJSON TransportMode where ...
```

---

### Category E: `runtimeMode` — fix downstream consumers to use typed `RuntimeMode`

**Existing type:** `RuntimeMode` = `DegradedRuntime | StrictRuntime` is already
defined in `Runtime/Mode.hs`, but `runtimeModeText :: RuntimeMode -> Text` converts
back to `Text`, and downstream consumers use `Text` comparison.

**Affected dispatch sites (2):**
- `Core/TurnPipeline/Finalize/Projection.hs:165` — `== "degraded"`
- `Runtime/Gate.hs:40` — `shStatus health == "ok"` (shStatus is Text)

**Fix:**
1. Eliminate `runtimeModeText` or mark it deprecated
2. Change `trcRuntimeMode :: Text` to `trcRuntimeMode :: RuntimeMode`
3. Change `fprRuntimeMode :: Text` → `fprRuntimeMode :: RuntimeMode`
4. Change consumers to pattern-match: `== "degraded"` → `DegradedRuntime`
5. For `shStatus health == "ok"`: define `HealthStatus` sum type
   (`HsOk | HsDegraded | HsFailed`)

---

### Category F: `parserStatus :: Text` → `ParserStatus` sum type (local refactor)

**Affected location:** `Core/TurnPipeline/Finalize/Projection.hs:131-136`
(locally computed `Text`)

**New sum type:**
```haskell
data ParserStatus
  = PsOk
  | PsConstitutionAdmitted
  | PsDegraded Text  -- reason
```

---

### Category G (Structural): Effect scheduling labels → `PipelineEffectLabel` sum type

**Affected pattern:** `[(Text, TurnEffectRequest)]` string-keyed effect bus in
Prepare (`Prepare/Resolve.hs:51-55,72-88`), Route (`Route/Effects.hs:95-107`,
`Route/Render.hs:554-570`), Finalize (`Finalize/Precommit.hs:103-119`).

**New sum type:**
```haskell
data PipelineEffectLabel
  = PelEmbedding | PelNix | PelConsciousness | PelIntuition | PelApiHealth
  | PelShadow | PelAgda
  | PelRequest | PelExplore
  | PelSemanticIntrospection | PelWarnMorphology | PelFmarMode
  deriving (Eq, Ord, Show, Read, Generic)
```

**Migration:** Replace `[(Text, TurnEffectRequest)]` with `[(PipelineEffectLabel, TurnEffectRequest)]`.
Replace `firstMatch` string-keyed lookup with direct `lookup` on sum-type key.
This is a **structural** refactor touching ~30 lines across 3 files.

**Risk:** Low. Sum-type equality is deterministic; no behavioral change.

---

### Category H: `PropositionFallbackType` → direct type matching (low priority)

**Affected location:** `Types/Admission/PropositionPhraseDecisionAdmission.hs:38,48-53`

`PropositionFallbackType` is already a sum type, but `pacTriggerLabel` converts
it to `Text` via `pack (show pt)`, and `safeFallbackTypes :: [Text]` contains
`pack "PfContactSignal"` etc.

**Fix:** Change `pacTriggerLabel :: RawPropositionPhraseDecision pt -> Text` to
return the type directly:
```haskell
pacTriggerLabel :: RawPropositionPhraseDecision pt -> PropositionFallbackType
```
Change `safeFallbackTypes :: [Text]` to `safeFallbackTypes :: [PropositionFallbackType]`
with `[PfContactSignal, PfDistinguisher, ...]`.

---

## Implementation Order (revised after review)

| Order | Category | Dispatch sites | Complexity | Effort |
|--------|----------|---------------|------------|--------|
| 1 (warm-up) | H: `PropositionFallbackType` | 1 admission module | Small | ~30m |
| 2 | C: `ConflictPolicy` | 2 | Small | ~30m |
| 3 | D: `TransportMode` | 1 | Small | ~30m |
| 4 | F: `ParserStatus` | 1 (local) | Small | ~15m |
| 5 | B: `DreamCandidateKind` | 6 | Medium, isolated | ~1.5h |
| 6 (biggest) | A: `SemanticFrameTarget` | 13 | Medium-large (type + JSON + 13 sites + persistence) | ~4–6h |
| 7 | E: `RuntimeMode` consumers | 2 | Medium (touches persistence types) | ~1.5h |
| 8 (separate PR) | G: `PipelineEffectLabel` | ~30 lines, 3 files | Structural, effect bus core | ~2h |

**Total estimated effort:** ~2–3 рабочих дня, не 7 часов.

**PipelineEffectLabel (G) — отдельный PR после A–F.** Замена `Text` ключей на sum type
в effect bus затрагивает Prepare/Route/Finalize ядро. Риск implicit sequencing.

---

## Review Amendments (2026-07-08)

1. **Persistence migration test — обязателен.** Старый persisted `SystemState` с `"user"` строкой
   (до миграции) должен десериализоваться после миграции. Добавлено в verification gates.
2. **Порядок изменён:** H (warm-up) → C, D, F (маленькие) → B (изолировано) → A (крупный) → E → G (отдельный PR).
3. **PipelineEffectLabel выделен в отдельный PR.** Effect bus — сердце pipeline. Менять `Text` на
   sum type в сигнатурах Prepare/Route/Finalize опасно из-за возможного implicit sequencing.
4. **Оценка пересмотрена:** 2–3 рабочих дня, а не 7 часов. Только `SemanticFrameTarget` — 4–6 часов.

---

## Files Affected

| File | Change |
|------|--------|
| `src/QxFx0/Types/InputSemantic.hs` or equivalent | Add `SemanticFrameTarget`, change `ipfSemanticTarget` field |
| `src/QxFx0/Core/TurnPlanning/Builders.hs` | Replace 9 string matches with pattern matches |
| `src/QxFx0/Render/Dialogue.hs` | Replace 4 string matches + `elem` with pattern match + `isSelfFamily` |
| `src/QxFx0/Types/DreamPressure.hs` | Add `DreamCandidateKind`, change `dccKind` field |
| `src/QxFx0/Core/TopicDrift/Pressure.hs` | Replace 6 string matches with pattern matches |
| `src/QxFx0/Types/State/Perspective.hs` | Add `ConflictPolicy`, change `npConflictPolicy` field |
| `src/QxFx0/Self/Perspective.hs` | Replace 2 string matches |
| `src/QxFx0/Types/ExternalQuery.hs` | Add `TransportMode`, change `eqcTransportMode` field |
| `src/QxFx0/Bridge/ExternalLLM.hs` | Replace 1 string match |
| `src/QxFx0/Runtime/Mode.hs` | Deprecate/remove `runtimeModeText` |
| `src/QxFx0/Core/TurnPipeline/Finalize/Projection.hs` | Change `trcRuntimeMode` type, `parserStatus` refactor |
| `src/QxFx0/Runtime/Gate.hs` | Add `HealthStatus`, replace `shStatus` type |
| `src/QxFx0/Core/TurnPipeline/Prepare/Resolve.hs` | Replace `Text` labels with `PipelineEffectLabel` |
| `src/QxFx0/Core/TurnPipeline/Route/Effects.hs` | Replace `Text` labels |
| `src/QxFx0/Core/TurnPipeline/Route/Render.hs` | Replace `Text` labels |
| `src/QxFx0/Core/TurnPipeline/Finalize/Precommit.hs` | Replace `Text` labels |
| `src/QxFx0/Types/Admission/PropositionPhraseDecisionAdmission.hs` | Direct type match instead of `Text` proxy |

**Aeson instances must be backward-compatible:** each new sum type's `FromJSON`
instance must accept both the old string format (`"user"`) and the new tagged
format (`{"tag": "SftUser"}`). `ToJSON` emits the new tagged format.

---

## Verification Gates

- [ ] `cabal build qxfx0` passes clean (no warnings)
- [ ] `cabal test qxfx0-test-fast` passes all tests
- [ ] No `Text` equality checks on the refactored fields remain in the codebase
   (verify with `rg '== "(user|symbolic|affective|degraded|ok|fireworks|permissive|invalid)"' src/`)
- [ ] JSON round-trip test: serialize `SystemState` with new types, deserialize,
   verify equality
- [ ] **Persistence migration test (critical):** старый persisted `SystemState` с `"user"` строкой (до миграции) десериализуется корректно после миграции всех типов
- [ ] Backward compatibility: old persisted JSON (with string values) for ALL refactored fields still deserializes correctly
- [ ] Pattern-match exhaustiveness: GHC `-Wincomplete-patterns` produces no warnings for any `case` over the new sum types