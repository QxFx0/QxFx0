#!/usr/bin/env python3
"""CF-2 patch: Extract computeNextEssence from buildNextSystemState god function."""
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "/home/liskil/my-haskell-project/QxFx0/src/QxFx0/Core/TurnPipeline/Finalize/State.hs"
with open(path, "r") as f:
    content = f.read()

# 1. Add computeNextEssence to export list
old_exports = """  ( buildNextSystemState
  , buildFinalOutput
  , finalizeMetrics
  , computeEssenceValidation
  ) where"""
new_exports = """  ( buildNextSystemState
  , buildFinalOutput
  , finalizeMetrics
  , computeEssenceValidation
  , computeNextEssence
  ) where

-- | CF-2 Decomposition: Extracted essence computation phase.
-- This function is independently testable without constructing the full
-- SystemState turn pipeline. Future decomposition phases:
--   * computeCalibrationPhase — Phase 7 calibration + tree maintenance
--   * computeCommitmentPhase — Phase E/F revision + collapse decisions
--   * computeSelfStatePhase — Phase 4.1.3 grouped Self-layer state
-- Each extraction reduces the god function's scope and enables isolated testing."""
content = content.replace(old_exports, new_exports)

# 2. Add computeNextEssence function before buildNextSystemState
old_build_sig = """buildNextSystemState :: (Text -> Seq Text -> Seq Text) -> (AuthoritySurface -> Maybe FactualClaimPayload) -> SystemState -> TurnInput -> TurnSignals -> TurnPlan -> TurnArtifacts -> DreamState -> MeaningGraph -> CanonicalMoveFamily -> R5Verdict -> Int -> (SystemState, Maybe CommitmentTrigger, CommitmentStoreAdmissionDecision, Int)"""

new_func_and_sig = """-- | Extracted Phase: Essence commitment computation (CF-2).
-- Evaluates witness + shouldCommit for the current turn, returning
-- the next Essence state and any commitment trigger.
computeNextEssence :: SystemState -> TurnInput -> TurnPlan -> (Essence, Maybe CommitmentTrigger)
computeNextEssence ss ti tp =
  case tiEssence ti of
    EssenceUncommitted trajectory ->
      let trajectory' =
            witness
              defaultEssenceModulation
              (ssTurnCount ss + 1)
              (tiConatusEnergy ti)
              (tiField ti)
              (fromMaybe defaultDeliberation (tpDeliberation tp))
              trajectory
      in case shouldCommit defaultEssenceModulation trajectory' of
           Nothing      -> (EssenceUncommitted trajectory', Nothing)
           Just trigger ->
             ( EssenceCommitted
                 trajectory'
                 (commit (ssTurnCount ss + 1) trigger trajectory')
             , Just trigger
             )
    EssenceCommitted trajectory commitment ->
      let trajectory' =
            witness
              defaultEssenceModulation
              (ssTurnCount ss + 1)
              (tiConatusEnergy ti)
              (tiField ti)
              (fromMaybe defaultDeliberation (tpDeliberation tp))
              trajectory
      in (EssenceCommitted trajectory' commitment, Nothing)

""" + old_build_sig

content = content.replace(old_build_sig, new_func_and_sig)

# 3. Replace inline essence computation with call to computeNextEssence
old_essence_block = """      -- WP1 (contour closure): law-driven commitment.
      -- 'shouldCommit' is always evaluated; no feature flag.
      -- The trigger (if any) is exposed for downstream validation.
      (nextEssence, commitmentTrigger) =
        case tiEssence ti of
          EssenceUncommitted trajectory ->
            let trajectory' =
                  witness
                    defaultEssenceModulation
                    (ssTurnCount ss + 1)
                    (tiConatusEnergy ti)
                    (tiField ti)
                    (fromMaybe defaultDeliberation (tpDeliberation tp))
                    trajectory
            in case shouldCommit defaultEssenceModulation trajectory' of
                 Nothing      -> (EssenceUncommitted trajectory', Nothing)
                 Just trigger ->
                   ( EssenceCommitted
                       trajectory'
                       (commit (ssTurnCount ss + 1) trigger trajectory')
                   , Just trigger
                   )
          EssenceCommitted trajectory commitment ->
             -- Sticky: committed essences are never reverted. We still
             -- ingest a witness so etAngstLevel/etConatusFloor track
             -- post-commit deliberation for diagnostics.
             let trajectory' =
                   witness
                     defaultEssenceModulation
                     (ssTurnCount ss + 1)
                     (tiConatusEnergy ti)
                     (tiField ti)
                     (fromMaybe defaultDeliberation (tpDeliberation tp))
                     trajectory
              in (EssenceCommitted trajectory' commitment, Nothing)"""

new_essence_block = """      -- WP1 (contour closure): law-driven commitment (CF-2: extracted to computeNextEssence).
      (nextEssence, commitmentTrigger) = computeNextEssence ss ti tp"""

content = content.replace(old_essence_block, new_essence_block)

with open(path, "w") as f:
    f.write(content)
print("CF-2: computeNextEssence extracted and exported")
