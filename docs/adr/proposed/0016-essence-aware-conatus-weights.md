# ADR-0016 (proposed): Essence-Aware Conatus Weights

- **Status**: Proposed (triage stub, not yet a full ADR)
- **Date**: 2026-05-19
- **Refines**:
  - [ADR-0012 — Essence Commitment](../0012-essence-commitment.md)
  - [ADR-0007 — Dual-Mode Conatus](../0007-dual-mode-conatus.md)

## 1. Problem statement

ADR-0012 §10 lists "Essence-aware Conatus weights" as out of scope:
"Tuning weights to the committed mode (e.g. `EssenceContemplative` weights
consolidation more) is a natural extension but is deferred until Phase 9
observational data exists."  The current `ConatusWeights`
(`src/QxFx0/Self/Conatus.hs:102-111`) are global constants:
`cwMorphology = 1.0`, `cwIdentity = 0.5`, `cwTurns = 0.25`,
`cwViolation = 10.0`.  These weights encode a single editorial judgement
about what matters for self-preservation, regardless of *what kind of
self* the system has committed to.

A `EssenceContemplative` system (formal-led, low arousal, high
consolidation) might reasonably value `cwIdentity` (structural claim
count) more than `cwMorphology` (raw atom size), because its identity
is built on principled coherence rather than breadth of vocabulary.
Conversely, a `EssenceDialogical` system might value `cwMorphology`
higher, because its identity is sustained by rich, varied dialogue
presence.  The current fixed weights ignore this distinction, treating
all committed modes as identical in their conatus calculus.

## 2. Current architecture (what would change)

- `src/QxFx0/Self/Conatus.hs:102-111` — `ConatusWeights` would need a
  mode-specific variant, or `defaultConatusWeights` would become a
  function `EssenceMode -> ConatusWeights`.
- `src/QxFx0/Self/Conatus.hs:178-205` — `computeConatusEnergy` and
  `computeConatusEnergyWith` would need to accept an optional
  `Maybe EssenceMode` (or `Maybe EssenceCommitment`) to select the
  correct weight set.  The default (uncommitted) path would retain the
  current global weights.
- `src/QxFx0/Self/Essence.hs:176-183` — `EssenceMode` enumeration
  (`EssenceWitnessing`, `EssenceContemplative`, `EssenceDialogical`,
  `EssenceIntegrative`) is the lookup key for mode-specific weights.
- `src/QxFx0/Core/TurnPipeline/Effects.hs:207-209` —
  `computeConatusEnergy blanket violations` is called in
  `buildPrepareEffectPlan`; it would need access to the current
  `EssenceMode`, which is available via `ssEssence` but currently
  not passed to `computeConatusEnergy`.
- `src/QxFx0/Core/TurnPipeline/Finalize/State.hs:88-136` — The
  `buildNextSystemState` witness ingestion site recomputes or carries
  conatus; mode-aware weights would need to be recomputed every turn
  because the `EssenceMode` may have just committed this turn.
- `test/Test/Suite/SelfConatus.hs` — All existing conatus tests assume
  `defaultConatusWeights` is a constant.  These would need to be
  parameterised over a weight set, or split into mode-specific suites.

## 3. Open design questions

1. What are the empirically justified weight deltas per mode?  The
   current defaults are editorial; mode-specific defaults would need
   corpus evidence showing that, e.g., `EssenceContemplative` sessions
   benefit from higher `cwIdentity`.  Without data, any choice is
   arbitrary.
2. Should the weights be static per mode (defined at compile time), or
   should they be tunable per deployment via `ConatusPriorModulation`
   or a new `EssenceConatusModulation` record?
3. Does `EssenceIntegrative` (agreement-dominated) get the current
   global defaults, or does it need its own tuned set?  If it uses the
   globals, then the `defaultConatusWeights` constant becomes the
   "integrative default," which may bias the system toward integrative
   commitment.
4. How does the conatus gradient (`computeConatusGradient`) change
   under mode-specific weights?  The gradient direction determines
   recovery priority; a contemplative system recovering along the
   identity axis rather than the morphology axis is a significant
   behavioural change.
5. Should mode-specific weights affect only the *scalar* `ceScalar`,
   or also the *gradient* magnitude and direction used by recovery
   planning?  The two are mathematically linked (same weights), but the
   recovery planner might need to know which axis the current mode
   prioritises.
6. What is the interaction with the conatus-aware effect scheduler
   (ADR-0007 §4.3 / `docs/effects-conatus-prior-implementation-spec.md`)?
   If `ceScalar` computation becomes mode-dependent, the scheduler's
   thresholds (`cpmHealthyThreshold`, etc.) may also need mode-aware
   tuning.
7. Can mode-specific weights be calibrated automatically from
   production traces (inverse problem: given a committed mode and a
   history of violations, what weights maximise conatus stability)?
   Or is hand-tuning the only practical path?

## 4. Estimated complexity

**M** — the code change is mechanical (turn a constant into a
mode-indexed map, thread `EssenceMode` through three call sites).  The
hard work is empirical calibration: running the long-session corpus
(or production traces) under candidate weight sets, measuring
`EssenceRupture` rates and commitment stability, and selecting defaults.
Without calibration data, the feature is trivial to implement but
impossible to justify.  Estimated 1–2 weeks for implementation, plus
an open-ended calibration period.

## 5. Why this is not in scope yet

Phase 10 must produce production observational data first.  The current
`defaultConatusWeights` are a conservative, mode-agnostic baseline that
passes all regression locks (`Test.Suite.SelfConatus`).  Introducing
mode-specific weights before we have stable endogenous commitment
statistics would add a tuning dimension that confounds all calibration
experiments.  The feature is deferred until:

1. The endogenous commitment path (angst threshold and conatus erosion)
   is validated in production under the current global weights.
2. A corpus of committed-mode traces exists (at least 100 sessions per
   mode) showing that the current weights produce suboptimal recovery
   behaviour for specific modes.
3. A calibration protocol (possibly inverse optimisation) is designed
   and peer-reviewed.

Until then, the mode-agnostic weights remain the conservative default.

— end of proposed ADR-0016 —
