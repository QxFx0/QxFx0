# Phase 10 Flag-Flip Operations Checklist

## Preconditions (all must hold before flip)

1. Calibration addendum (ADR-0012 §15) merged.
   - `emConatusStructuralFloor` corrected (0.5 → 7.0).
   - Angst-side parameters remain at Phase 9 defaults (deferred to
     production trace ingestion).

2. Long-session corpus replay executed with
   `QXFX0_ESSENCE_COMMITMENT_ENABLED=1` on at least 5 sessions
   each ≥ 15 turns, producing zero `EssenceRupture` events and at
   least one `EssenceCommitted` row in the trace.
   - **Status as of 2026-05-19**: zero ruptures confirmed on 70 turns
     (5 synthetic fixtures), but **no commitment fired** because
     angst-side calibration is deferred.  Operator must validate
     that the corrected Conatus floor (`7.0`) produces the expected
     `TriggerConatusErosion` under sustained low-energy conditions
     before considering this precondition satisfied.

3. `defaultEssenceModulation` calibrated against observed dynamics
   from the long corpus (not the conservative defaults from Phase 9).
   - **Partial**: Conatus floor calibrated against production
     `ceScalar` codomain. Angst-side remains Phase 9 default.

4. Operator has validated that the calibrated `EssenceModulation`
   defaults still pass `Test.Suite.SelfEssence` and
   `Test.Suite.SelfEssenceCommit`.
   - **Verified on 2026-05-19**: 589/589 PASS.

## Procedure

1. **Locate the feature-flag site** (currently hardcoded, no env-var
   parser exists in production):
   - `src/QxFx0/Core/TurnPipeline/Effects.hs:254`
     ```haskell
     , psEssenceCommitmentEnabled = False
     ```
   - This value is threaded through `PrepareStatic` → `TurnInput`:
     - `src/QxFx0/Core/TurnPipeline/Types.hs:119` — type field
       `tiEssenceCommitmentEnabled :: !Bool`
     - `src/QxFx0/Core/TurnPipeline/Prepare/Build.hs:95` —
       `tiEssenceCommitmentEnabled = psEssenceCommitmentEnabled prepareStatic`
   - In the test harness the flag is toggled via
     `withEnvVar "QXFX0_ESSENCE_COMMITMENT_ENABLED"` (see
     `test/Test/Support.hs:149`), but **no production env-var parser**
     for this key exists yet.  Before the flip, an operator must
     either:
     - Add `QXFX0_ESSENCE_COMMITMENT_ENABLED` to the env-var lookup
       in `src/QxFx0/Core/TurnPipeline/Effects.hs` (mirroring the
       pattern in `src/QxFx0/Runtime/Mode.hs:22` or
       `src/QxFx0/Runtime/Wiring/Handlers.hs:224-230`), **or**
     - Change the hardcoded `False` to `True` at the site above.

2. If using the hardcoded route: change `False` → `True` at
   `src/QxFx0/Core/TurnPipeline/Effects.hs:254`.

3. Bump version in `qxfx0.cabal`.
   - Current version: `0.1.0.0` (`qxfx0.cabal:3`).
   - Recommended bump: `0.2.0.0` (new behavioural default).

4. Update `CHANGELOG.md` with a release note.
   - **No `CHANGELOG.md` exists in the repository as of 2026-05-19**.
   - Create one at repository root or append to release notes in
     `docs/operations/`.

5. Run `scripts/verify.sh` and `scripts/release-smoke.sh`.
   - See `docs/operations/release-reproducibility.md` for the
     reproducibility audit and two-pass verification procedure.

6. Tag release.
   - Example: `git tag -a v0.2.0.0 -m "Phase 10: essence commitment enabled by default"`

7. Roll out.
   - Deploy the tagged artifact.  Monitor telemetry (see below)
     for the first 24 hours.

## Rollback procedure

If post-flip production traces show unexpected `EssenceRupture`
events, the operator can roll back by:

1. Reverting the hardcoded `True` → `False` at
   `src/QxFx0/Core/TurnPipeline/Effects.hs:254`, **or**
   (if an env-var parser was added) setting
   `QXFX0_ESSENCE_COMMITMENT_ENABLED=0` in the runtime env.
2. Re-deploying the previous tag (`v0.1.0.0` or the last known-good
   release).
3. Filing an incident report referencing the rupture trace and the
   committed `EssenceMode` that the plan violated.
   - `EssenceRupture` carries the committed mode and the violating
     `Plan` family/tone/style; see ADR-0012 §7.

## Telemetry to watch post-flip

- Count of `trcEssenceCommitted = true` per session.
  - Source: `TurnReplayTrace` fields populated in
    `src/QxFx0/Core/TurnPipeline/Finalize/State.hs`.
- Mode distribution (`trcEssenceMode`).
  - Values: `witnessing`, `contemplative`, `dialogical`, `integrative`.
- Trigger distribution (`trcEssenceTrigger`).
  - Values: `angst_threshold`, `conatus_erosion`.
- Any `EssenceRupture` events in the application log.
  - These are non-recoverable; each one means a committed essence
    produced a `Plan` that `validatePlan` rejected.
- `etAngstLevel` and `etConatusFloor` trajectory diagnostics
  (extracted from trace or debug logging) to validate that the
  calibrated modulation values are behaving as expected under
  production load.
