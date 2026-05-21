{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-|
Experimental zero-sum routing game (payoff matrix, Nash / LP mixed strategy).

Not wired into the production turn pipeline. Runtime family selection uses
'Semantic.Logic' and the turn-routing cascade. Kept for extended scientific
contour experiments only.
-}
module QxFx0.Core.GameTheory
  ( GameState(..)
  , utility
  , payoffMatrix
  , nashEquilibrium
  , mixedStrategyNash
  , gameRouteFamily
  , gameRouteFamilyWithMixed
  , solveMixedStrategy
  ) where

import qualified Data.Map.Strict as M

import GHC.Generics (Generic)
import Control.DeepSeq (NFData)

import Data.Maybe (listToMaybe)

import QxFx0.Types.Domain (CanonicalMoveFamily(..))
import QxFx0.Types.State.Discourse (EngagementLevel(..), DialogPhase(..))
import QxFx0.Policy.SemanticScoring
  ( semanticLogicDefineWeight
  , semanticLogicClarifyWeight
  , semanticLogicDeepenWeight
  , semanticLogicConfrontWeight
  , semanticLogicReflectWeight
  , semanticLogicAnchorWeight
  , semanticLogicContactWeight
  , semanticLogicDistinguishWeight
  , semanticLogicHypothesisWeight
  , semanticSpecialPurposeWeight
  , semanticFallbackGroundWeight
  , semanticLogicRepairWeight
  , semanticFallbackNextStepWeight
  , semanticSpecialDescribeWeight
  )
import QxFx0.Types.Thresholds.GameTheory ( depthCostDeepen, depthCostHypothesis, depthCostDefine
                         , depthCostDistinguish, depthCostDefault
                         , engagementPenaltyMedium, engagementPenaltyLow
                         , phaseMultiplierOpening, phaseMultiplierExploring, phaseMultiplierDeep, phaseMultiplierClosing
                         , tensionHighThreshold
                         , tensionBonusContact, tensionBonusRepair, tensionBonusReflect, tensionBonusGround, tensionBonusDefault
                         , insightShiftDefine, insightShiftDeepen, insightShiftClarify, insightShiftDefault
                         , contradictionShiftConfront, contradictionShiftDistinguish, contradictionShiftClarify, contradictionShiftDefault
                         , userBonusDefine, userBonusClarify, userBonusAnchor, userBonusDeepenDefine, userBonusConfrontContact
                         , userBonusReflectRepair, userBonusContactContact, userBonusRepairConfront
                         , tensionCoefficient
                         )
import QxFx0.Core.GameTheory.LP (solveMixedStrategy)

data GameState = GameState
  { gsTension       :: !Double
  , gsConfidence    :: !Double
  , gsEngagement    :: !EngagementLevel
  , gsPhase         :: !DialogPhase
  , gsTopicKnown    :: !Bool
  , gsHasInsight    :: !Bool
  , gsContradiction :: !Bool
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

families :: [CanonicalMoveFamily]
families = [minBound..maxBound]

infoGain :: CanonicalMoveFamily -> Double
infoGain CMDefine      = semanticLogicDefineWeight
infoGain CMClarify     = semanticLogicClarifyWeight
infoGain CMDeepen      = semanticLogicDeepenWeight
infoGain CMDistinguish = semanticLogicDistinguishWeight
infoGain CMHypothesis  = semanticLogicHypothesisWeight
infoGain CMReflect     = semanticLogicReflectWeight
infoGain CMPurpose     = semanticSpecialPurposeWeight
infoGain CMConfront    = semanticLogicConfrontWeight
infoGain CMGround      = semanticFallbackGroundWeight
infoGain CMContact     = semanticLogicContactWeight
infoGain CMRepair      = semanticLogicRepairWeight
infoGain CMAnchor      = semanticLogicAnchorWeight
infoGain CMNextStep    = semanticFallbackNextStepWeight
infoGain CMDescribe    = semanticSpecialDescribeWeight

depthCost :: CanonicalMoveFamily -> Double
depthCost CMDeepen      = depthCostDeepen
depthCost CMHypothesis  = depthCostHypothesis
depthCost CMDefine      = depthCostDefine
depthCost CMDistinguish = depthCostDistinguish
depthCost _             = depthCostDefault

engagementPenalty :: EngagementLevel -> Double
engagementPenalty HighEngagement   = 0.0
engagementPenalty MediumEngagement = engagementPenaltyMedium
engagementPenalty LowEngagement    = engagementPenaltyLow

phaseMultiplier :: DialogPhase -> Double
phaseMultiplier PhaseOpening   = phaseMultiplierOpening
phaseMultiplier PhaseExploring = phaseMultiplierExploring
phaseMultiplier PhaseDeep      = phaseMultiplierDeep
phaseMultiplier PhaseClosing   = phaseMultiplierClosing

distressShift :: Double -> CanonicalMoveFamily -> Double
distressShift tension fam
  | tension > tensionHighThreshold = case fam of
      CMContact  -> tensionBonusContact
      CMRepair   -> tensionBonusRepair
      CMReflect  -> tensionBonusReflect
      CMGround   -> tensionBonusGround
      _          -> tensionBonusDefault
  | otherwise = 0.0

insightShift :: Bool -> CanonicalMoveFamily -> Double
insightShift True CMDefine  = insightShiftDefine
insightShift True CMDeepen  = insightShiftDeepen
insightShift True CMClarify = insightShiftClarify
insightShift True _         = insightShiftDefault
insightShift False _        = insightShiftDefault

contradictionShift :: Bool -> CanonicalMoveFamily -> Double
contradictionShift True CMConfront    = contradictionShiftConfront
contradictionShift True CMDistinguish = contradictionShiftDistinguish
contradictionShift True CMClarify     = contradictionShiftClarify
contradictionShift True _             = contradictionShiftDefault
contradictionShift False _            = contradictionShiftDefault

userBonus :: CanonicalMoveFamily -> CanonicalMoveFamily -> Double
userBonus CMDefine    CMDefine    = userBonusDefine
userBonus CMClarify   CMClarify   = userBonusClarify
userBonus CMRepair    CMConfront  = userBonusRepairConfront
userBonus CMAnchor    CMAnchor    = userBonusAnchor
userBonus CMDeepen    CMDefine    = userBonusDeepenDefine
userBonus CMConfront  CMContact   = userBonusConfrontContact
userBonus CMReflect   CMRepair    = userBonusReflectRepair
userBonus CMContact   CMContact   = userBonusContactContact
userBonus _ _ = 0.0

utility :: CanonicalMoveFamily -> CanonicalMoveFamily -> GameState -> Double
utility sysMove userMove gs =
  let ig = infoGain sysMove
      ub = userBonus sysMove userMove
      tc = gsTension gs * tensionCoefficient
      dc = depthCost sysMove
      ep = engagementPenalty (gsEngagement gs)
      ib = if gsHasInsight gs then insightShiftDefine else 0.0
      ds = distressShift (gsTension gs) sysMove
      is' = insightShift (gsHasInsight gs) sysMove
      cs = contradictionShift (gsContradiction gs) sysMove
      pm = phaseMultiplier (gsPhase gs)
  in pm * (ig + ub - tc - dc + ep + ib + ds + is' + cs)

payoffMatrix :: GameState -> [[Double]]
payoffMatrix gs =
  [[utility sysMove userMove gs | userMove <- families]
   | sysMove <- families]

{-| Pure-strategy saddle-point (Nash equilibrium) for a zero-sum game.
  A saddle point exists when max_i min_j a_{ij} = min_j max_i a_{ij}. -}
matrixAt :: [[Double]] -> Int -> Int -> Double
matrixAt mat i j =
  case drop i mat of
    (row:_) ->
      case drop j row of
        (x:_) -> x
        _ -> 0.0
    _ -> 0.0

familyAt :: Int -> Maybe CanonicalMoveFamily
familyAt i = listToMaybe (drop i families)

nashEquilibrium :: [[Double]] -> Maybe CanonicalMoveFamily
nashEquilibrium matrix =
  let n = length families
      rowMins = map minimum matrix
      colMaxs = [maximum [matrixAt matrix i j | i <- [0..n-1]] | j <- [0..n-1]]
      maxMin = maximum rowMins
      minMax = minimum colMaxs
      eps = 1e-6
  in if abs (maxMin - minMax) < eps
     then case filter (\(i, rowMin) -> abs (rowMin - maxMin) < eps) (zip [0..] rowMins) of
          (i, _):_ -> familyAt i
          [] -> Nothing
     else Nothing

{-| Mixed-strategy Nash equilibrium via proper LP simplex solver. -}
mixedStrategyNash :: [[Double]] -> M.Map CanonicalMoveFamily Double
mixedStrategyNash matrix =
  case solveMixedStrategy matrix of
    Nothing   -> M.empty
    Just probs -> M.fromList (zip families probs)

gameRouteFamily :: GameState -> Maybe CanonicalMoveFamily
gameRouteFamily gs =
  let matrix = payoffMatrix gs
  in if validatePayoffMatrix matrix
     then nashEquilibrium matrix
     else Nothing

gameRouteFamilyWithMixed :: GameState -> M.Map CanonicalMoveFamily Double
gameRouteFamilyWithMixed gs =
  let matrix = payoffMatrix gs
  in if validatePayoffMatrix matrix
     then mixedStrategyNash matrix
     else M.empty

validatePayoffMatrix :: [[Double]] -> Bool
validatePayoffMatrix matrix =
  let n = length matrix
      rowLengths = map length matrix
  in n > 0 && all (== n) rowLengths
