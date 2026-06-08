# ADR-0044: Promote User Model (Bayesian Theory-of-Mind)

- **Status**: Proposed (2026-06-04)
- **Date**: 2026-06-04
- **Related**:
  - `src/QxFx0/Core/Bayesian.hs` (`updateUserModel`, `userModelActive`, `dominantIntent`, `bayesianUpdateFromText`)
  - `src/QxFx0/Types/State/System.hs` (`ssUserModel :: BeliefState`)
  - `src/QxFx0/Core/TurnPipeline/Finalize/State.hs` (per-turn update + `dtIntentHypothesis` reader)
  - `docs/specs/cognitive-and-substrate-roadmap-v3.1.md` (WP-A)
  - `docs/adr/0042-anti-rot-standard.md`

## 1. Context

`QxFx0.Core.Bayesian` implemented a correct discrete posterior update over hidden
user intents (`UserWantsDefine | … | UserIsDistressed`) but was tagged "Not wired
into the production turn pipeline." The dialogue-thread slots `dtIntentHypothesis`
and `dtUserGoal` were write-only (a speech-act label string, never read to alter a
decision). The audit flagged this as the single largest cognitive gap: a dialogue
runtime with no model of its interlocutor's mind.

WP-A persists a posterior in `ssUserModel`, updates it each turn from raw text via
`bayesianUpdateFromText`, and adds a living reader (`dominantIntent`) that overrides
`dtIntentHypothesis` with the inferred intent. All gated by the default-off flag
`userModelActive` so production behaviour is unchanged until promotion.

## 2. Decision

### 2.1 State

`ssUserModel :: BeliefState` is added to `SystemState`, initialised to
`initialBeliefs` (uniform prior). ToJSON writes `"userModel"`; FromJSON reads it
with `.!= initialBeliefs` (backward-compatible: legacy states decode to the prior).

### 2.2 Flag

`userModelActive :: Bool = False` is registered in the flag-off discipline
(`scripts/check_architecture.sh` rule [20]). `updateUserModel` is identity when
off, so `ssUserModel` stays uniform and `dominantIntent` returns `Nothing`,
preserving the baseline `dtIntentHypothesis`.

### 2.3 Promotion gate

The flag flips to `True` only when **all** hold:

- **G1 — determinism**: fixed-fixture replay under `userModelActive = True`
  produces a deterministic posterior trajectory (same input + prior → same
  posterior).
- **G2 — replay parity (flag-off)**: with the flag `False`, trace + behaviour are
  byte-identical to the pre-WP-A baseline.
- **G3 — calibration (Phase II)**: the likelihood constants in `textLikelihood`
  (`0.1 + 0.15·count`, …) are extracted to a named `UserModelWeights` record with
  provenance and calibrated against the production-trace corpus (F-09/F-10). Until
  then the posterior is advisory (drives only `dtIntentHypothesis`, no routing).

### 2.4 Anti-rot

Guarded by `docs/anti_rot_registry.tsv` (kind `consumer`); `Test.Suite.UserModel`
fails if `updateUserModel` stops calling `bayesianUpdateFromText`.

## 3. Consequences

- **+** `bayesianUpdate*` is no longer dead code; the system carries a persistent,
  serialized model of the interlocutor's likely intent.
- **+** `dtIntentHypothesis` gains a real reader (inferred intent), closing a
  write-only slot.
- **+** Baseline unchanged while flag-off — no replay churn.
- **−** Increment-1 only feeds `dtIntentHypothesis`; routing/planning consumption
  of the posterior (and `dtUserGoal`) is a later, output-churning increment.
- **−** Likelihoods remain uncalibrated magic constants until Phase II (G3).
