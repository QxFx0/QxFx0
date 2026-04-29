# QxFx0 Shadow Parity Research Pack

## Goal

Determine whether QxFx0 shadow verification is already a true parity harness, and if not, define the minimum path to a canonical frozen-snapshot model.

## Curated files

- `src/QxFx0/Bridge/Datalog.hs`
- `src/QxFx0/Core/TurnPipeline/Route.hs`
- `src/QxFx0/Core/TurnPipeline/Route/Shadow.hs`
- `src/QxFx0/Types/ShadowDivergence.hs`
- `src/QxFx0/Types/Domain.hs`
- `src/QxFx0/Types/Decision.hs`
- `spec/datalog/semantic_rules.dl`
- `docs/adr/0003-datalog-runtime-facts.md`
- `scripts/verify.sh`
- `scripts/release-smoke.sh`

## Key excerpt: runtime facts are appended into the Datalog program

From `src/QxFx0/Bridge/Datalog.hs`:

```haskell
let program = dlSource <> "\n" <> renderRuntimeFacts fam force atoms
```

And shadow verdict comparison:

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

## Key excerpt: shadow affects legitimacy and family resolution

From `src/QxFx0/Core/TurnPipeline/Route/Shadow.hs`:

```haskell
computeShadowContext :: ShadowResult -> InputPropositionFrame -> AtomTrace -> Double -> EmbeddingQuality -> Double -> Bool -> ShadowContext
```

And:

```haskell
resolveShadowFamily :: ShadowPolicy -> CanonicalMoveFamily -> ShadowContext -> ShadowResolution
```

With branch:

```haskell
ShadowBlockOnUnavailableOrDivergence ->
  case scShadowStatus sc of
    ShadowUnavailable -> ShadowResolution CMRepair True
    _ | scShadowHasDivergence sc ->
          ShadowResolution (maybe CMRepair id (scShadowFamily sc)) True
      | otherwise ->
          ShadowResolution requestedFamily False
```

Meaning: shadow is not decorative. It can gate or alter effective family.

## What is already real

- shadow result type exists
- divergence fields exist
- shadow affects legitimacy context
- shadow can trigger repair/block-like routing behavior
- shadow diagnostics are surfaced as text tags

## What is not yet proven by this pack

- that runtime and shadow read the exact same canonical frozen snapshot
- that bridge fact coverage is complete for all hard paths
- that constant skew between runtime and shadow is explicitly detected
- that replay parity corpus exists

## Research questions

1. Is the current `renderRuntimeFacts fam force atoms` boundary sufficient for true parity?
2. What data used by runtime decisions is not currently represented as canonical shadow facts?
3. Which divergences are logic divergences vs bridge/encoding/version divergences?
4. What should fail build, fail turn, or only warn?

## Desired output

- frozen snapshot schema
- verdict normalization algebra
- divergence taxonomy
- parity property-tests
- replay corpus design
- release gate design

## External prompt

```text
Treat this as a focused shadow-parity pack for QxFx0.

Your job:
1. reconstruct current shadow behavior from the snippets and file map,
2. determine whether it is a full parity harness or a thinner runtime-fact bridge,
3. design the minimum canonical frozen-snapshot model needed for reliable parity.

You must produce:
- snapshot schema,
- normalized runtime/shadow verdict algebra,
- divergence taxonomy,
- property-tests,
- replay harness requirements,
- fail-vs-warn gate policy.

Do not replace Datalog.
Strengthen parity around the existing Datalog shadow.
```
