{-# LANGUAGE StrictData #-}

{-| Ego/trace modulation transforms for stance and epistemic planning hints. -}
module QxFx0.Core.TurnPlanning.Modulation
  ( egoModulateStance
  , egoModulateEpistemic
  , traceModulateStance
  , threeStageModulation
  , feralDegradation
  , antiStuck
  ) where

import QxFx0.Types
import QxFx0.Types.Thresholds
  ( criticalTensionThreshold
  , elevatedTensionThreshold
  , highAgencyThreshold
  , highTraceLoadThreshold
  , lowAgencyThreshold
  , veryLowAgencyThreshold
  )

egoModulateStance :: EgoState -> StanceMarker -> StanceMarker
egoModulateStance ego base =
  let tension = egoTension ego
      agency = egoAgency ego
   in if tension > criticalTensionThreshold && agency < lowAgencyThreshold
        then HoldBack
        else
          if tension > elevatedTensionThreshold
            then
              case base of
                Commit -> Honest
                Firm -> Observe
                stance -> stance
            else
              if agency > highAgencyThreshold
                then
                  case base of
                    Tentative -> Explore
                    HoldBack -> Observe
                    stance -> stance
                else base

egoModulateEpistemic :: EgoState -> EpistemicStatus -> EpistemicStatus
egoModulateEpistemic ego base =
  let tension = egoTension ego
      agency = egoAgency ego
   in if tension > elevatedTensionThreshold
        then degradeEpistemic base
        else if agency > highAgencyThreshold
          then strengthenEpistemic base
          else base

traceModulateStance :: AtomTrace -> StanceMarker -> StanceMarker
traceModulateStance trace base =
  let load = atCurrentLoad trace
   in if load > highTraceLoadThreshold
        then
          case base of
            Commit -> Honest
            Firm -> Explore
            stance -> stance
        else base

threeStageModulation :: EgoState -> AtomTrace -> StanceMarker -> EpistemicStatus -> (StanceMarker, EpistemicStatus)
threeStageModulation ego trace baseStance baseEpistemic =
  let stage2Stance = egoModulateStance ego baseStance
      stage2Epistemic = egoModulateEpistemic ego baseEpistemic
   in (traceModulateStance trace stage2Stance, stage2Epistemic)

feralDegradation :: Bool -> StanceMarker -> EpistemicStatus -> (StanceMarker, EpistemicStatus)
feralDegradation nixAvailable baseStance baseEpistemic =
  if nixAvailable
    then (baseStance, baseEpistemic)
    else (escalateStance baseStance, degradeEpistemic baseEpistemic)

antiStuck :: Int -> EgoState -> CanonicalMoveFamily -> Maybe CanonicalMoveFamily
antiStuck consecutiveReflect ego currentFamily =
  if consecutiveReflect >= 3 && currentFamily == CMReflect
    then Just CMDeepen
    else
      if egoAgency ego < veryLowAgencyThreshold && egoTension ego > elevatedTensionThreshold
        then Just CMRepair
        else Nothing

degradeEpistemic :: EpistemicStatus -> EpistemicStatus
degradeEpistemic (Known confidence) = Probable confidence
degradeEpistemic (Probable confidence) = Uncertain confidence
degradeEpistemic (Uncertain confidence) = Speculative confidence
degradeEpistemic status = status

strengthenEpistemic :: EpistemicStatus -> EpistemicStatus
strengthenEpistemic (Speculative confidence) = Uncertain confidence
strengthenEpistemic (Uncertain confidence) = Probable confidence
strengthenEpistemic (Probable confidence) = Known confidence
strengthenEpistemic status = status

escalateStance :: StanceMarker -> StanceMarker
escalateStance Commit = Firm
escalateStance Firm = Honest
escalateStance Honest = Observe
escalateStance Explore = Tentative
escalateStance Tentative = HoldBack
escalateStance stance = stance
