# ADR-0042: Anti-Rot Standard for Cognitive Field Consumers

- **Status**: Proposed (2026-06-04)
- **Date**: 2026-06-04
- **Related**:
  - `docs/specs/cognitive-and-substrate-roadmap-v3.1.md` (cross-cutting requirement X1)
  - `docs/anti_rot_registry.tsv` (the machine-checked registry)
  - `scripts/check_architecture.sh` (gate rule [21])

## 1. Context

The 2026-06 cognitive audit found a recurring defect class: a **rich type or
mechanism exists, but its consumer is dead**. Concretely:

- write-only cognitive fields — `clDoubtScore`, `dtIntentHypothesis`,
  `dtUserGoal`, `dtActiveQuestion` are assigned and serialized but never read
  to influence a decision;
- unwired modules — `Core.Bayesian`, `Core.Spectral` have no production
  consumer;
- dead entry points — `Memory.Episodic.retrieve` is defined but never called.

These survive type-checking and the existing suites because **nothing asserts a
living consumer**. As the roadmap (Track I) wires these mechanisms in, we need a
structural guard that the consumer stays connected, so the same rot cannot be
re-introduced silently by a later refactor.

## 2. Decision

### 2.1 Guarded artifact

A **guarded artifact** is a state field or computed signal whose value is
intended to influence a runtime decision (a cognitive field), OR a calibrated
constant / deferred contract whose scale or status matters for correctness.

For every guarded artifact that the roadmap touches, there MUST exist a test
registered in `docs/anti_rot_registry.tsv`.

### 2.2 Guard kinds

| kind | meaning | strength |
|---|---|---|
| `consumer` | a behavioral test that drives the path with the artifact at a value that should change the decision, and asserts the decision changes | strongest — proves a living consumer |
| `reader-exists` | a test that references the consumer symbol so removing the reader breaks build/test | weaker fallback when a behavioral test is disproportionately heavy |
| `value-guard` | asserts a constant lives in its valid (e.g. production-scale) codomain | catches unit/scale regressions |
| `deferred-contract` | pins the values/status of an explicitly uncalibrated path so any change is a conscious act | makes `Deferred` honest, not silent |

`consumer` is preferred for every wired field; `reader-exists` is permitted only
when noted in the registry `notes` column with a justification.

### 2.3 Registry

`docs/anti_rot_registry.tsv` is append-only, tab-separated, with columns:

```
artifact <TAB> kind <TAB> site <TAB> test_name <TAB> wp <TAB> adr <TAB> notes
```

`test_name` is the exact HUnit/QuickCheck label as it appears in `test/`.

### 2.4 Gate

`check_architecture.sh` rule **[21]** validates that every registry entry's
`test_name` appears literally in `test/`. A registered guard therefore cannot be
silently deleted: removing the test fails the architecture gate.

### 2.5 Scope

Applies to fields wired by roadmap Track I (WP-B, A, D, E, C, H3) and any future
cognitive wiring. Pre-existing fields are registered opportunistically. WP-F
(merged) is the first registered artifact (`value-guard` + `deferred-contract`).

## 3. Consequences

- **+** Write-only cognitive fields become structurally hard to reintroduce: a
  reviewer/CI gets a machine-checkable "is this still wired?" signal.
- **+** `Deferred` paths are pinned, not silent.
- **−** Small per-WP overhead: one registry line + one test.
- **−** `reader-exists` guards are weaker than behavioral `consumer` guards; the
  registry surfaces which form each entry uses so the weakness is visible.

## 4. Rollout

1. ADR Proposed (this commit); rule [21] + registry land alongside, seeded with
   the WP-F guards.
2. Each subsequent wiring WP appends its `consumer` guard line as part of its
   Definition-of-Done (roadmap §9 item 1).
