{-# LANGUAGE DerivingStrategies, DeriveAnyClass, DeriveGeneric, OverloadedStrings #-}
{-| Pure dream-cycle dynamics used to decay drift, apply evidence gates,
and re-center reflection bias over time.
-}
module QxFx0.Core.TopicDrift
  ( module QxFx0.Types.Vec
  , module QxFx0.Types.Dream
  , runDreamCycle
  , runDreamCatchup
  , computeBiasAttractor
  , buildTransitionMatrix
  ) where

import QxFx0.Types.Dream
import QxFx0.Types.Vec (CoreVec(..), zeroVec, vecAdd, vecSub, vecScale, vecNorm, clampVecNorm)
import QxFx0.Types.Thresholds (clamp01, dreamMinCycleDurationHours)
import Data.List (foldl')
import Data.Time (NominalDiffTime, UTCTime, addUTCTime, diffUTCTime)
import qualified Data.Map.Strict as M
import QxFx0.Types.Observability (MeaningGraph(..), MeaningEdge(..), MeaningStateId)

-- | Run one dream update step for a bounded time delta.
-- Applies drift decay, evidence quality gates, and bias relaxation.
runDreamCycle :: DreamConfig -> [DreamThemeEvidence] -> UTCTime -> NominalDiffTime -> DreamState -> (DreamState, DreamCycleLog)
runDreamCycle cfg evidence now delta dreamState =
  let hours = max 0.0 (realToFrac delta / 3600.0)
      r5 = dsR5State dreamState
      driftBefore = r5KernelDrift r5
      driftAfter = decayKernelDrift cfg hours driftBefore
      attractor = computeBiasAttractor cfg evidence
      biasBefore = r5ReflectionBias r5
      biasAfter = relaxReflectionBias cfg hours attractor biasBefore
      r5After = r5 { r5KernelDrift = driftAfter, r5ReflectionBias = biasAfter }
      nextState = dreamState
        { dsR5State = r5After
        , dsBiasAttractor = attractor
        , dsLastDreamTime = now
        , dsDreamCycleCount = dsDreamCycleCount dreamState + 1
        }
      (acceptedCount, rejectedCount) = evidenceGateCounts cfg evidence
      events =
        [ DriftDecayApplied hours (vecNorm driftBefore) (vecNorm driftAfter)
        , QualityGateApplied acceptedCount rejectedCount
        , AttractorComputed (vecNorm attractor)
        , BiasRelaxationApplied (vecNorm biasBefore) (vecNorm biasAfter) (vecNorm (vecSub biasAfter biasBefore))
        ]
      cycleLog = DreamCycleLog now hours r5 r5After attractor events
  in (nextState, cycleLog)

-- | Catch up missed dream cycles by splitting elapsed time into fixed-size steps.
runDreamCatchup :: DreamConfig -> [DreamThemeEvidence] -> UTCTime -> DreamState -> (DreamState, [DreamCycleLog])
runDreamCatchup cfg evidence now dreamState
  | hoursSinceLastDream < dcDreamThresholdHours cfg = (dreamState, [])
  | otherwise = (finalState, reverse reverseLogs)
  where
    cappedHours = min (dcMaxCatchupHours cfg) hoursSinceLastDream
    cycleHours = max dreamMinCycleDurationHours (dcCycleDurationHours cfg)
    fullSteps = floor (cappedHours / cycleHours)
    remainder = cappedHours - fromIntegral fullSteps * cycleHours
    stepHours = replicate fullSteps cycleHours ++ [remainder | remainder > 1e-9]
    startTime = dsLastDreamTime dreamState
    hoursSinceLastDream = max 0.0 (realToFrac (diffUTCTime now startTime) / 3600.0)
    step (stateAcc, logsAcc) hours =
      let stepNow = addUTCTime (realToFrac (hours * 3600.0) :: NominalDiffTime) (dsLastDreamTime stateAcc)
          delta = realToFrac (hours * 3600.0) :: NominalDiffTime
          (state', log') = runDreamCycle cfg evidence stepNow delta stateAcc
      in (state', log' : logsAcc)

    (finalState, reverseLogs) = foldl' step (dreamState, []) stepHours

decayKernelDrift :: DreamConfig -> Double -> CoreVec -> CoreVec
decayKernelDrift cfg hours drift = vecScale (exp (negate (dcDriftLambdaPerHour cfg) * hours)) drift

relaxReflectionBias :: DreamConfig -> Double -> CoreVec -> CoreVec -> CoreVec
relaxReflectionBias cfg hours attractor currentBias =
  clampVecNorm (dcMaxReflectionBiasNorm cfg) (vecAdd currentBias cappedDelta)
  where
    alpha = dcBiasRelaxAlphaPerHour cfg * max 0.0 hours
    targetDelta = vecScale alpha (vecSub attractor currentBias)
    cappedDelta = clampVecNorm (dcBiasDeltaCapPerCycle cfg) targetDelta

-- | Compute a bounded weighted attractor from accepted evidence only.
computeBiasAttractor :: DreamConfig -> [DreamThemeEvidence] -> CoreVec
computeBiasAttractor cfg evidence =
  clampVecNorm (dcMaxAttractorNorm cfg) weightedMean
  where
    accepted = [ (deaAcceptedWeight audit, dteBias item)
               | (item, audit) <- zip evidence (auditDreamEvidence cfg evidence)
               , deaAcceptedWeight audit > 0.0
               ]
    totalWeight = sum [ weight | (weight, _) <- accepted ]
    weightedMean
      | totalWeight < 1e-9 = zeroVec
      | otherwise = vecScale (1.0 / totalWeight) (foldl' vecAdd zeroVec [ vecScale weight bias | (weight, bias) <- accepted ])

evidenceGateCounts :: DreamConfig -> [DreamThemeEvidence] -> (Int, Int)
evidenceGateCounts cfg evidence = foldl' step (0, 0) (auditDreamEvidence cfg evidence)
  where
    step (accepted, rejected) audit
      | deaAcceptedWeight audit > 0.0 = (accepted + 1, rejected)
      | otherwise = (accepted, rejected + 1)

auditDreamEvidence :: DreamConfig -> [DreamThemeEvidence] -> [DreamEvidenceAudit]
auditDreamEvidence cfg = map auditOne
  where
    auditOne item =
      let quality = clamp01 (dteQualityWeight item)
          experience = clamp01 (dteExperienceWeight item)
          decision
            | not (dteBiographyPermission item) = Left RejectedByBiographyPermission
            | quality < dcMinQualityWeight cfg = Left (RejectedByLowQuality quality)
            | experience <= 0.0 = Left (RejectedByZeroExperienceWeight experience)
            | otherwise = Right (experience * quality)
      in DreamEvidenceAudit
           (dteTheme item)
           (either (const 0.0) id decision)
           quality
           experience
            (either Just (const Nothing) decision)

buildTransitionMatrix :: MeaningGraph -> M.Map MeaningStateId (M.Map MeaningStateId Double)
buildTransitionMatrix mg =
  let outgoing = foldl' addEdge M.empty (mgEdges mg)
      normalize m = M.mapWithKey (\_ neighbors ->
        let total = sum (M.elems neighbors)
        in if total > 1e-9 then M.map (/ total) neighbors else neighbors) m
      -- COMPAT GLUE: Source v2 used 3-field MeaningEdge; target has 9 fields.
      -- We only need the IDs and dream bias (weight) for the transition matrix.
      addEdge acc (MeaningEdge { meFromId = from, meToId = to, meDreamBias = w }) =
        M.insertWith (M.unionWith (+)) from (M.singleton to w) acc
  in normalize outgoing
