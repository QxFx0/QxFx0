{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}
{-# LANGUAGE RecordWildCards #-}
{-| Ego-state update rules and trend estimation across dialogue turns. -}
module QxFx0.Core.Ego
  ( updateEgoFromTurn
  ) where

import QxFx0.Types
import QxFx0.Types.Thresholds
  ( egoTensionDecayFactor
  , egoTensionInputFactor
  , egoAgencyDecayFactor
  , egoAgencyInputFactor
  , egoTrendWindow
  , egoTrendRisingThreshold
  , egoTrendFallingThreshold
  , egoHistoryRetention
  , egoHistoryLimit
  , egoAgencyDeltaGround
  , egoAgencyDeltaDefine
  , egoAgencyDeltaDistinguish
  , egoAgencyDeltaReflect
  , egoAgencyDeltaDescribe
  , egoAgencyDeltaPurpose
  , egoAgencyDeltaHypothesis
  , egoAgencyDeltaRepair
  , egoAgencyDeltaContact
  , egoAgencyDeltaAnchor
  , egoAgencyDeltaClarify
  , egoAgencyDeltaDeepen
  , egoAgencyDeltaConfront
  , egoAgencyDeltaNextStep
  )
import QxFx0.Core.Policy.Contracts (missionTexts)
import Data.Text (Text)
import qualified Data.Text as T
import QxFx0.Types.Text (textShow)

updateEgoFromTurn :: EgoState -> CanonicalMoveFamily -> Double -> EgoState
updateEgoFromTurn ego fam tensionDelta =
  let newTension = egoTension ego * egoTensionDecayFactor + tensionDelta * egoTensionInputFactor
      agencyDelta = case fam of
        CMGround      -> egoAgencyDeltaGround
        CMDefine      -> egoAgencyDeltaDefine
        CMDistinguish -> egoAgencyDeltaDistinguish
        CMReflect     -> egoAgencyDeltaReflect
        CMDescribe    -> egoAgencyDeltaDescribe
        CMPurpose     -> egoAgencyDeltaPurpose
        CMHypothesis  -> egoAgencyDeltaHypothesis
        CMRepair      -> egoAgencyDeltaRepair
        CMContact     -> egoAgencyDeltaContact
        CMAnchor      -> egoAgencyDeltaAnchor
        CMClarify     -> egoAgencyDeltaClarify
        CMDeepen      -> egoAgencyDeltaDeepen
        CMConfront    -> egoAgencyDeltaConfront
        CMNextStep    -> egoAgencyDeltaNextStep
      newAgency = min 1.0 $ max 0.0 $ egoAgency ego * egoAgencyDecayFactor + (egoAgency ego + agencyDelta) * egoAgencyInputFactor
      mission = inferMission fam
      newDynamics = updateSubjectDynamics (egoSubjectDynamics ego) newAgency
      newUserState = (egoUserState ego) { usReadiness = newAgency }
  in ego
      { egoTension = min 1.0 $ max 0.0 newTension
      , egoAgency = newAgency
      , egoMission = mission
      , egoUserState = newUserState
      , egoSubjectDynamics = newDynamics
      }

inferMission :: CanonicalMoveFamily -> Text
inferMission fam = case lookup (textShow fam) missionTexts of
  Just t  -> t
  Nothing -> textShow fam

detectTrend :: [Double] -> Trend
detectTrend [] = Plateau
detectTrend [_] = Plateau
detectTrend vals =
  let recent = take egoTrendWindow vals
      len = length recent
      diffs = if len >= 2
                then zipWith (-) (drop 1 recent) (take (len - 1) recent)
                else []
      avgDiff = if null diffs then 0.0 else sum diffs / fromIntegral (length diffs)
  in if avgDiff > egoTrendRisingThreshold then Rising
     else if avgDiff < egoTrendFallingThreshold then Falling
     else Plateau

updateSubjectDynamics :: SubjectDynamics -> Double -> SubjectDynamics
updateSubjectDynamics sd agency =
  let histTexts = sdSemanticHistory sd
      histDoubles = map safeRead histTexts
      newHistDoubles = agency : take egoHistoryRetention histDoubles
      newHistTexts = take egoHistoryLimit $ map (T.pack . show) newHistDoubles
      trend = detectTrend newHistDoubles
      shiftTurn = if trend /= sdTrend sd then 0 else sdLastShiftTurn sd + 1
  in sd
      { sdTrend = trend
      , sdSemanticHistory = newHistTexts
      , sdLastShiftTurn = shiftTurn
      }
  where
    safeRead t = case reads (T.unpack t) of
      [(d, "")] -> d
      _ -> 0.0
