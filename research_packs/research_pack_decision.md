# QxFx0 Decision Semantics Research Pack

## Goal

Strengthen the current decision semantics around legitimacy and warrantedness without inventing a second policy engine.

## Curated files

- `src/QxFx0/Types/Domain.hs`
- `src/QxFx0/Types/Decision.hs`
- `src/QxFx0/Types/Decision/Enums.hs`
- `src/QxFx0/Core/Legitimacy/Scoring.hs`
- `src/QxFx0/Core/TurnLegitimacy/Plans.hs`
- `src/QxFx0/Core/TurnLegitimacy/Output.hs`
- `spec/R5Core.agda`
- `spec/Legitimacy.agda`
- `scripts/verify_agda_sync.py`
- `test/Test/Suite/CoreBehavior.hs`

## Key excerpt: warrantedness is already explicit, but coarse

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

## Key excerpt: legitimacy reasons are explicit

From `src/QxFx0/Types/Decision/Enums.hs`:

```haskell
data LegitimacyReason
  = ReasonShadowDivergence
  | ReasonShadowUnavailable
  | ReasonLowParserConfidence
  | ReasonOk
```

## Repo-grounded reading

What clearly exists:

- family-level warrantedness
- verdict objects
- legitimacy reasons
- legitimacy scoring logic
- tests around legitimacy penalties and recovery bonuses

What still looks under-modeled:

- explicit `ActionClass`
- explicit `GateVerdict` algebra beyond scattered outputs
- clear distinction between:
  - allowed
  - sufficiently supported
  - advisory-only
  - deny
- evidence-quality and independence logic as first-class semantics

## Research questions

1. Is `WarrantedMoveMode` sufficient, or does QxFx0 need a richer warrant model?
2. Where is legitimacy currently a score and where is it a gate?
3. Where can current semantics blur "allowed" and "supported"?
4. What is the minimum ADT expansion to make the model explicit without destabilizing the current pipeline?

## Desired output

- formal decision matrix
- minimal Haskell ADT additions
- pure decision function shape
- Agda alignment guidance
- property-tests and scenario tests
- migration path that preserves current gates

## External prompt

```text
Treat this as a repo-grounded decision-semantics pack for QxFx0.

The task is not to design a universal ethics engine.
The task is to clarify the existing decision semantics around:
- Legitimacy
- Warrantedness
- Verdicts
- Reasons
- Advisories

You must:
1. map what is already explicit,
2. identify what is still implicit or conflated,
3. design the smallest viable formal model that makes the semantics operational and testable.

Prioritize:
- ADTs
- pure decision functions
- invariants
- tests
- spec alignment
```
