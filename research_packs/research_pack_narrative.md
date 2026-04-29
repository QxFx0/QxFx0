# QxFx0 Narrative Boundary Research Pack

## Goal

Decide whether narrative is allowed to influence the decision core, or whether it should be strictly downstream after route and gates.

## Curated files

- `src/QxFx0/Core/Consciousness/Kernel.hs`
- `src/QxFx0/Core/Consciousness/Narrative.hs`
- `src/QxFx0/Core/Consciousness/Types.hs`
- `src/QxFx0/Core/TurnModulation/Narrative.hs`
- `src/QxFx0/Core/TurnPipeline/Prepare/Resolve.hs`
- `src/QxFx0/Core/TurnPipeline/Route.hs`
- `src/QxFx0/Core/TurnPipeline/Types.hs`
- `test/Test/Suite/CoreBehavior.hs`

## Key excerpt: kernel produces narrative-related output

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

Meaning: consciousness/kernel is not just static flavor text; it computes directional outputs.

## Key excerpt: narrative modulation changes meaning plan

From `src/QxFx0/Core/TurnModulation/Narrative.hs`:

```haskell
modulateRMPWithNarrative :: Maybe Text -> ResponseMeaningPlan -> ResponseMeaningPlan
```

And family hint logic:

```haskell
narrativeFamilyHint :: ConsciousnessNarrative -> Maybe CanonicalMoveFamily
intuitionFamilyHint :: Double -> Maybe CanonicalMoveFamily
```

## Key excerpt: route uses narrative-derived modulation

From `src/QxFx0/Core/TurnPipeline/Route.hs`:

```haskell
rmp1 = modulateRMPWithNarrative (tsNarrativeFragment ts) rmp0
```

## Key excerpt: tests prove route influence

From `test/Test/Suite/CoreBehavior.hs`:

```haskell
testRouteFamilyNarrativeHintChangesFamily
testRouteFamilyIntuitionHintChangesFamily
```

One concrete assertion:

```haskell
assertEqual "Silence narrative should route to CMAnchor" CMAnchor (rdFamily rdWithHint)
```

Meaning: narrative and intuition already influence route behavior in tested code paths.

## The architectural question

Two valid but incompatible readings exist:

### Option A: narrative is downstream-only

- route/gates decide first
- narrative only affects rendering and style
- strongest separation of decision core from self-story

### Option B: narrative is an allowed decision hint

- consciousness/kernel can influence route priors or family hints
- narrative is part of cognition, not only presentation
- requires stronger observability, invariants and tests

QxFx0 currently appears closer to Option B in parts of the code.

## Research questions

1. Is current narrative influence intentional architecture or accidental drift?
2. Which exact edges are allowed and which should become illegal?
3. If narrative remains in the decision core, what invariants and diagnostics are mandatory?
4. If narrative must become downstream-only, what must be refactored first?

## Desired output

- current narrative influence map
- option A vs option B comparison
- recommended boundary
- illegal transition list
- tests and gates for narrative feedback
- concrete refactor plan

## External prompt

```text
Treat this as a focused pack on the narrative boundary in QxFx0.

Your task:
1. reconstruct the current call graph of kernel -> narrative -> route/render influence,
2. identify which decision edges are real,
3. recommend whether narrative should remain a route hint or be pushed strictly downstream.

Do not speak abstractly about selfhood.
Answer the concrete architecture question:
Does narrative influence the decision core, and if so, should that remain legal?

Ground every conclusion in:
- existing call edges,
- existing tests,
- state ownership,
- failure modes,
- observability requirements.
```
