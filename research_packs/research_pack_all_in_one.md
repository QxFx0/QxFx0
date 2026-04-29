# QxFx0 All-in-One Research Pack

## Instruction To External Research Model

Treat this file as a curated, repo-grounded research bundle for the Haskell system `QxFx0`.

Your task is not to redesign the system from scratch.
Your task is to analyze the existing architecture and determine:

1. which mechanisms are already operational,
2. which are partially operational,
3. which are still spec-only or under-specified,
4. where current runtime behavior is weaker or narrower than the architectural claims,
5. what concrete changes would strengthen the existing architecture without building a second one.

Important rules:

- Do not invent hidden mechanisms that are not evidenced by state, types, call edges, tests, or diagnostics.
- Do not treat names, comments, or documentation as proof of runtime behavior.
- Do not propose a parallel architecture or "v2 controller" unless absolutely unavoidable.
- Prioritize:
  - state
  - transitions
  - call edges
  - downstream effects
  - diagnostics
  - tests
  - gates
- If evidence is insufficient for a conclusion, say so explicitly.

Required output format:

1. Executive summary
2. Mechanism inventory:
   - operational
   - partially operational
   - spec-only
3. Current architectural strengths
4. Current architectural tensions
5. Main correctness / parity / observability gaps
6. Recommended changes, grouped into:
   - P1 now
   - P2 next
   - P3 later
7. Exact artifacts to add or change:
   - Haskell ADTs
   - pure functions
   - tests
   - specs
   - release gates

The goal is to strengthen the existing QxFx0 architecture, not replace it.

---

## 1. Project Context

`QxFx0` is a Haskell system with:

- layered architecture,
- turn pipeline,
- bridge/runtime effects,
- Datalog shadow verification,
- Agda-backed contracts,
- SQL persistence,
- release and verification gates.

As of `2026-04-22`, this repository has recently passed:

- `bash scripts/verify.sh`
- `bash scripts/release-smoke.sh`
- `cabal test qxfx0-test`
- `python3 scripts/verify_agda_sync.py`

This means the project is already structurally mature. The main engineering problem is no longer "invent an architecture", but:

- make declared mechanisms fully operational,
- ensure runtime/spec/shadow parity,
- make key decisions replayable and diagnosable,
- remove ambiguity between documentation and actual behavior.

---

## 2. The Core Framing

For this project, a mechanism should count as **real** only if it has all or most of the following:

- explicit type / ADT / state,
- transition function or pure logic,
- call edge in the pipeline,
- downstream consumer,
- diagnostics or logs,
- tests or verification harness.

If it only has a name, docs, comments, or a spec, it should not automatically be treated as operational.

This distinction is critical for QxFx0 because the project already has strong architectural language and a broad spec surface.

---

## 3. Curated File Map

### Core Pipeline

- `src/QxFx0/Core/TurnPipeline/Protocol.hs`
- `src/QxFx0/Core/TurnPipeline/Types.hs`
- `src/QxFx0/Core/TurnPipeline/Effects.hs`
- `src/QxFx0/Core/TurnPipeline/Prepare.hs`
- `src/QxFx0/Core/TurnPipeline/Prepare/Build.hs`
- `src/QxFx0/Core/TurnPipeline/Prepare/Resolve.hs`
- `src/QxFx0/Core/TurnPipeline/Route.hs`
- `src/QxFx0/Core/TurnPipeline/Route/Render.hs`
- `src/QxFx0/Core/TurnPipeline/Route/Shadow.hs`
- `src/QxFx0/Core/TurnPipeline/Finalize.hs`
- `src/QxFx0/Core/TurnPipeline/Finalize/Precommit.hs`
- `src/QxFx0/Core/TurnPipeline/Finalize/Commit.hs`
- `src/QxFx0/Core/TurnPipeline/Finalize/State.hs`

### Decision / Verdict / Threshold Surface

- `src/QxFx0/Types/Domain.hs`
- `src/QxFx0/Types/Decision.hs`
- `src/QxFx0/Types/Decision/Enums.hs`
- `src/QxFx0/Types/ShadowDivergence.hs`
- `src/QxFx0/Types/Thresholds/Constants.hs`
- `src/QxFx0/Core/Legitimacy/Scoring.hs`
- `src/QxFx0/Core/TurnLegitimacy/Plans.hs`
- `src/QxFx0/Core/TurnLegitimacy/Output.hs`
- `src/QxFx0/Core/Intuition.hs`

### Consciousness / Narrative Surface

- `src/QxFx0/Core/Consciousness.hs`
- `src/QxFx0/Core/Consciousness/Kernel.hs`
- `src/QxFx0/Core/Consciousness/Narrative.hs`
- `src/QxFx0/Core/Consciousness/Types.hs`
- `src/QxFx0/Core/TurnModulation/Narrative.hs`

### Shadow / Spec Surface

- `src/QxFx0/Bridge/Datalog.hs`
- `spec/datalog/semantic_rules.dl`
- `spec/R5Core.agda`
- `spec/Legitimacy.agda`
- `docs/adr/0003-datalog-runtime-facts.md`

### Gates / Tests

- `scripts/verify.sh`
- `scripts/release-smoke.sh`
- `scripts/verify_agda_sync.py`
- `test/Test/Suite/CoreBehavior.hs`
- `test/Test/Suite/TurnPipelineProtocol.hs`

---

## 4. Verified Pipeline Evidence

### 4.1 Staged Turn Pipeline Is Real

From `src/QxFx0/Core/TurnPipeline/Protocol.hs`:

```haskell
data PreparedTurn = PreparedTurn !TurnInput !TurnSignals
data PlannedTurn = PlannedTurn !TurnInput !TurnSignals !TurnPlan
data RenderedTurn = RenderedTurn !TurnInput !TurnSignals !TurnPlan !TurnArtifacts
```

And:

```haskell
prepareTurn :: PipelineIO -> SystemState -> Text -> Text -> Text -> IO PreparedTurn
planTurn :: PipelineIO -> SystemState -> PreparedTurn -> IO PlannedTurn
renderTurn :: PipelineIO -> SystemState -> PlannedTurn -> IO RenderedTurn
finalizeTurn :: PipelineIO -> SystemState -> Text -> Text -> RenderedTurn -> IO TurnResult
```

And the staged execution:

```haskell
prepareTurn pio ss input sessionId requestId = do
  let prepareEffects = buildPrepareEffectPlan ss input
  prepareResults <- Prepare.resolvePrepareEffects pio prepareEffects
  let ti' = Prepare.buildTurnInput ss requestId sessionId prepareEffects prepareResults
      ts = Prepare.buildTurnSignals prepareResults
  pure (PreparedTurn ti' ts)

planTurn pio ss (PreparedTurn ti ts) = do
  let routeEffects = Route.planRouteEffects ss ti ts
  routeResults <- Route.resolveRouteEffects pio routeEffects
  let tp = Route.buildRouteTurnPlan (pipelineShadowPolicy pio) ss ti ts routeEffects routeResults
  pure (PlannedTurn ti ts tp)

renderTurn pio ss (PlannedTurn ti ts tp) = do
  let renderEffects = Route.planRenderEffects (pipelineLLMFallbackPolicy pio) ss ti ts tp
  renderResults <- Route.resolveRenderEffects pio renderEffects
  let ta = Route.buildTurnArtifacts ss ti ts tp renderEffects renderResults
  pure (RenderedTurn ti ts tp ta)
```

This confirms a real prepare -> route/plan -> render -> finalize lifecycle.

### 4.2 Finalize Is Split Further

The finalize phase is not a monolith. There is a real precommit / commit decomposition:

- `Finalize/Precommit.hs`
- `Finalize/Commit.hs`
- `Finalize/State.hs`

This is a real architectural strength.

---

## 5. Verified Decision / Verdict Evidence

### 5.1 Warrantedness Exists Explicitly

From `src/QxFx0/Types/Domain.hs`:

```haskell
data WarrantedMoveMode
  = AlwaysWarranted | NeverWarranted | ConditionallyWarranted
```

And:

```haskell
data R5Verdict = R5Verdict
  { r5Family :: !CanonicalMoveFamily
  , r5Force :: !IllocutionaryForce
  , r5Clause :: !ClauseForm
  , r5Layer :: !SemanticLayer
  , r5Warranted :: !WarrantedMoveMode
  }
```

This means the system already has explicit verdict structure and family-level warrantedness semantics.

### 5.2 Legitimacy Reasons Exist Explicitly

From `src/QxFx0/Types/Decision/Enums.hs`:

```haskell
data LegitimacyReason
  = ReasonShadowDivergence
  | ReasonShadowUnavailable
  | ReasonLowParserConfidence
  | ReasonOk
```

This means legitimacy is not just an unnamed scalar; there is already some reason algebra.

### 5.3 Intuition / Posterior Logic Exists As Real Runtime Logic

The repository contains:

- `src/QxFx0/Core/Intuition.hs`
- threshold constants extracted into `src/QxFx0/Types/Thresholds/Constants.hs`
- tests in `test/Test/Suite/CoreBehavior.hs`

Recent internal work has already moved more numeric logic into named constants and added tests for posterior / EMA-related behavior.

So intuition is not merely a design note. It is an operational mechanism, though possibly still under-specified semantically.

---

## 6. Verified Shadow Evidence

### 6.1 Shadow Is Real And Non-Decorative

From `src/QxFx0/Bridge/Datalog.hs`:

```haskell
compareShadowOutput :: R5Verdict -> R5Verdict -> ShadowDivergence
compareShadowOutput haskellVerdict datalogVerdict = ShadowDivergence
  { sdFamilyMismatch = r5Family haskellVerdict /= r5Family datalogVerdict
  , sdForceMismatch = r5Force haskellVerdict /= r5Force datalogVerdict
  , sdClauseMismatch = r5Clause haskellVerdict /= r5Clause datalogVerdict
  , sdLayerMismatch = r5Layer haskellVerdict /= r5Layer datalogVerdict
  , sdWarrantedMismatch = r5Warranted haskellVerdict /= r5Warranted datalogVerdict
  }
```

From the same file:

```haskell
let program = dlSource <> "\n" <> renderRuntimeFacts fam force atoms
```

This means:

- there is real runtime-to-Datalog bridging,
- there is real verdict comparison,
- there is real mismatch structure.

### 6.2 Shadow Feeds Back Into Routing / Legitimacy

From `src/QxFx0/Core/TurnPipeline/Route/Shadow.hs`:

```haskell
computeShadowContext :: ShadowResult -> InputPropositionFrame -> AtomTrace -> Double -> EmbeddingQuality -> Double -> Bool -> ShadowContext
```

And:

```haskell
resolveShadowFamily :: ShadowPolicy -> CanonicalMoveFamily -> ShadowContext -> ShadowResolution
```

With the important branch:

```haskell
ShadowBlockOnUnavailableOrDivergence ->
  case scShadowStatus sc of
    ShadowUnavailable -> ShadowResolution CMRepair True
    _ | scShadowHasDivergence sc ->
          ShadowResolution (maybe CMRepair id (scShadowFamily sc)) True
      | otherwise ->
          ShadowResolution requestedFamily False
```

This proves shadow is not a decorative diagnostic layer. It can change effective family and trigger gate-like behavior.

### 6.3 Main Open Question About Shadow

The crucial open question is not whether shadow exists. It does.

The crucial question is:

**Is current shadow comparison based on a true canonical frozen snapshot, or on a narrower runtime-fact injection bridge that still leaves room for parity skew?**

This should be treated as one of the highest-value research questions.

---

## 7. Verified Consciousness / Narrative Evidence

### 7.1 Consciousness Kernel Produces Real Outputs

From `src/QxFx0/Core/Consciousness/Kernel.hs`:

```haskell
kernelPulse :: UnconsciousKernel -> SemanticInput -> Double -> Double -> Int -> KernelOutput
kernelPulse kernel semanticInput humanTheta resonance _turn =
  let ...
      narrativeDrive = deriveNarrativeDrive activeDesires frame recommendedFamily selectedSkill
      focusHint = focusForDrive narrativeDrive frame inputText
   in KernelOutput
        { ...
        , koNarrativeDrive = narrativeDrive
        , koFocusHint = focusHint
        }
```

So the consciousness kernel is not merely described in docs. It computes structured output.

### 7.2 Narrative Modulates Meaning Plans

From `src/QxFx0/Core/TurnModulation/Narrative.hs`:

```haskell
modulateRMPWithNarrative :: Maybe Text -> ResponseMeaningPlan -> ResponseMeaningPlan
```

And:

```haskell
narrativeFamilyHint :: ConsciousnessNarrative -> Maybe CanonicalMoveFamily
intuitionFamilyHint :: Double -> Maybe CanonicalMoveFamily
```

### 7.3 Narrative / Intuition Influence Real Routing Behavior

From `src/QxFx0/Core/TurnPipeline/Route.hs`:

```haskell
rmp1 = modulateRMPWithNarrative (tsNarrativeFragment ts) rmp0
```

And the tests explicitly assert route influence:

From `test/Test/Suite/CoreBehavior.hs`:

```haskell
testRouteFamilyNarrativeHintChangesFamily
testRouteFamilyIntuitionHintChangesFamily
```

One concrete assertion:

```haskell
assertEqual "Silence narrative should route to CMAnchor" CMAnchor (rdFamily rdWithHint)
```

This is a major repo-grounded fact:

**Narrative and intuition are not purely downstream style layers. They already affect route behavior in tested code paths.**

This creates an important architectural decision point:

- either this is intentional and needs stronger invariants/observability,
- or it should be pushed downstream and refactored.

---

## 8. Current Strengths

Based on the curated evidence, QxFx0 already has strong architectural assets:

1. Real staged turn pipeline.
2. Real precommit/commit separation.
3. Real shadow verification.
4. Real verdict and warrantedness structures.
5. Real intuition logic with thresholds and tests.
6. Real consciousness/narrative modules with runtime outputs.
7. Real verification and smoke gates.

This is not a toy architecture. It is a real system with meaningful internal structure.

---

## 9. Main Architectural Tensions

These are the most important questions to resolve.

### T1. Shadow Parity Strength

Shadow exists, but it is not yet clear from this pack whether runtime and shadow share a canonical frozen snapshot boundary.

This matters because false divergence is often caused by bridge skew, constant skew, or timing skew rather than logical disagreement.

### T2. Legitimacy vs Warrantedness

The system already has legitimacy reasons and warranted verdict fields, but it is still not obvious whether the semantic split is strong enough:

- allowed?
- sufficiently supported?
- advisory only?
- denied?

This is likely one of the highest-leverage semantics cleanups.

### T3. Narrative Boundary

The system has a real consciousness/narrative mechanism, but it is not currently obvious whether narrative influence on route is:

- intended architecture,
- tolerated heuristic drift,
- or an area needing hard boundaries and replay diagnostics.

### T4. Replay / Observability Completeness

The staged pipeline is real, but the key question is whether important turn decisions are reconstructable after the fact:

- candidate routes,
- suppressed reasons,
- gate reasons,
- shadow reasoning,
- snapshot identity,
- route-determinism on replay.

---

## 10. What Should Not Be Done

The external analysis should not:

- propose a brand new parallel architecture,
- add a second controller stack,
- treat every named concept as fully operational,
- trust `brain_kb2.txt` as proof of current runtime behavior,
- collapse narrative/consciousness questions into philosophy instead of call edges and tests.

The right direction is:

**strengthen the existing architecture until the runtime behavior matches the claimed mechanisms more tightly.**

---

## 11. Research Priorities

The best research outcome would focus on these four areas:

### P1. Shadow Parity Research

Find out whether QxFx0 shadow is already a real parity harness, and if not:

- define canonical frozen snapshot,
- define divergence taxonomy,
- define replay and gate requirements.

### P1. Decision Semantics Research

Clarify the relation between:

- legitimacy,
- warrantedness,
- deny,
- permit,
- advisory,
- family-level verdicts,
- evidence sufficiency.

### P1. Narrative Boundary Research

Answer:

**Should narrative and intuition be allowed to influence route behavior, or must they be constrained to downstream modulation after route/gates?**

### P2. Trace / Replay Research

Reconstruct actual decision flow from pipeline and tests, then define:

- missing diagnostics,
- replay corpus,
- illegal transitions,
- determinism checks.

---

## 12. Expected Deliverable From Research

The external researcher should return:

1. Executive summary.
2. Mechanism inventory:
   - operational,
   - partially operational,
   - spec-only.
3. Architectural strengths.
4. Architectural tensions.
5. Evidence-based conclusions only.
6. Concrete backlog:
   - P1
   - P2
   - P3
7. Exact change classes:
   - ADTs
   - pure functions
   - property-tests
   - scenario tests
   - release gates
   - specs / parity harnesses

The output should stay close to implementation and verification, not drift into essay-style theory.

---

## 13. Optional Companion Material

There is also a local research corpus:

- `brain_kb2.txt`

It contains useful formal models, audit meta-models, state-machine ideas, and design hypotheses.

However:

- it should be treated as a hypothesis bank,
- not as authoritative evidence of current repository behavior.

If you use it, use it only to generate candidate invariants, tests, or design refinements that must then be checked against the code evidence summarized in this file.

---

## 14. One-Line Start Prompt

If the user uploads only this file, they can start with:

```text
Analyze this research pack as a repo-grounded architecture digest for QxFx0.
Determine what is already operational, what is only partially operational, and what still needs formalization, parity, or tests.
Do not redesign the system from scratch; strengthen the existing architecture.
Return an evidence-based backlog with P1/P2/P3 priorities.
```
