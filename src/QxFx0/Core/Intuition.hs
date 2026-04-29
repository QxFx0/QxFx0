{-# LANGUAGE DerivingStrategies, OverloadedStrings, DeriveGeneric, DeriveAnyClass #-}
{-| Intuition heuristics for flash detection, posterior updates, and directive shaping. -}
module QxFx0.Core.Intuition
  ( IntuitiveState(..)
  , defaultIntuitiveState
  , basePrior
  , likelihoodGivenFlash
  , updatePosterior
  , likelihoodGivenNoFlash
  , posteriorAfterFlash
  , longPosteriorAfterFlash
  , updateLongPosterior
  , flashThreshold
  , FlashTrigger(..)
  , IntuitiveFlash(..)
  , checkIntuition
  , triggerToGapDomains
  , intuitionSignalStrength
  , effectivePosterior
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Aeson
  ( FromJSON(..)
  , ToJSON(..)
  )
import GHC.Generics (Generic)
import QxFx0.Types.Thresholds
  ( clamp01
  , intuitionCrisisTensionThreshold
  , intuitionDeepResonanceThreshold
  , intuitionElevatedResonanceThreshold
  , intuitionElevatedTensionThreshold
  , intuitionFlashThreshold
  , intuitionHighResonanceThreshold
  , intuitionHighTensionThreshold
  , intuitionNoFlashBaselineLikelihood
  , intuitionFlashLikelihoodConvergent
  , intuitionFlashLikelihoodElevated
  , intuitionFlashLikelihoodDeep
  , intuitionFlashLikelihoodBaseline
  , intuitionNoFlashLikelihoodConvergent
  , intuitionNoFlashLikelihoodElevated
  , intuitionNoFlashLikelihoodDeep
  , intuitionPosteriorAfterFlashDecayFactor
  , intuitionLongPosteriorAfterFlashDecayFactor
  , intuitionLongPosteriorPriorWeight
  , intuitionLongPosteriorCurrentWeight
  , intuitionFlashOverrideStrengthThreshold
  , intuitionCoreVecPresence
  , intuitionCoreVecDepth
  , intuitionCoreVecAutonomy
  , intuitionCoreVecDirectiveness
  , intuitionCoreVecSteadiness
  , intuitionSteadinessBaseline
  , intuitionSignalSteadyBonusScale
  )
import QxFx0.Core.Policy.Consciousness
  ( triggerDeepResonance, triggerCrisisMoment, triggerPureKernel, triggerConvergence
  , kernelSignalPresence, kernelSignalDepth
  , triggerContextDeepResonance, triggerContextCrisisMoment
  , triggerContextPureKernel, triggerContextConvergence
  , intuitionHeaderPrefix, intuitionTriggerLabel
  , intuitionOverrideDirective, intuitionSupplementaryDirective
  , intuitionFormDirective
  )
import QxFx0.Types.Intuition
  ( IntuitiveState(..)
  , basePrior
  , defaultIntuitiveState
  , effectivePosterior
  )
import QxFx0.Types.Vec (CoreVec(..))
import Text.Printf (printf)

flashThreshold :: Double
flashThreshold = intuitionFlashThreshold

likelihoodGivenFlash :: Double -> Double -> Double
likelihoodGivenFlash resonance tension
  | resonance > intuitionHighResonanceThreshold && tension > intuitionHighTensionThreshold = intuitionFlashLikelihoodConvergent
  | resonance > intuitionElevatedResonanceThreshold || tension > intuitionElevatedTensionThreshold = intuitionFlashLikelihoodElevated
  | resonance > intuitionDeepResonanceThreshold = intuitionFlashLikelihoodDeep
  | otherwise                          = intuitionFlashLikelihoodBaseline

likelihoodGivenNoFlash :: Double -> Double -> Double
likelihoodGivenNoFlash resonance tension
  | resonance > intuitionHighResonanceThreshold && tension > intuitionHighTensionThreshold = intuitionNoFlashLikelihoodConvergent
  | resonance > intuitionElevatedResonanceThreshold || tension > intuitionElevatedTensionThreshold = intuitionNoFlashLikelihoodElevated
  | resonance > intuitionDeepResonanceThreshold = intuitionNoFlashLikelihoodDeep
  | otherwise                          = intuitionNoFlashBaselineLikelihood

updatePosterior :: Double -> Double -> Double -> Double
updatePosterior resonance tension prior =
  let pEH  = likelihoodGivenFlash  resonance tension
      pEnH = likelihoodGivenNoFlash resonance tension
      pE   = pEH * prior + pEnH * (1.0 - prior)
  in clamp01 ((pEH * prior) / max 1e-9 pE)

data FlashTrigger
  = DeepResonanceTrigger | CrisisMomentTrigger | PureKernelTrigger | ConvergenceTrigger
  deriving stock (Show, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

renderTrigger :: FlashTrigger -> Text
renderTrigger DeepResonanceTrigger = triggerDeepResonance
renderTrigger CrisisMomentTrigger  = triggerCrisisMoment
renderTrigger PureKernelTrigger    = triggerPureKernel
renderTrigger ConvergenceTrigger   = triggerConvergence

triggerToGapDomains :: FlashTrigger -> [Text]
triggerToGapDomains ConvergenceTrigger   = ["HumanPsychology", "CausalChains"]
triggerToGapDomains CrisisMomentTrigger  = ["HumanPsychology"]
triggerToGapDomains DeepResonanceTrigger = ["HumanPsychology", "CulturalAnthropology"]
triggerToGapDomains PureKernelTrigger    = ["CausalChains", "RhetoricalAnalysis"]

data IntuitiveFlash = IntuitiveFlash
  { ifStrength     :: !Double
  , ifTrigger      :: !FlashTrigger
  , ifKernelSignal :: !Text
  , ifDirective    :: !Text
  , ifOverridesAll :: !Bool
  } deriving stock (Show, Generic)
  deriving anyclass (FromJSON, ToJSON)

qxfx0CoreVec :: CoreVec
qxfx0CoreVec =
  CoreVec
    intuitionCoreVecPresence
    intuitionCoreVecDepth
    intuitionCoreVecAutonomy
    intuitionCoreVecDirectiveness
    intuitionCoreVecSteadiness

checkIntuition :: Double -> Double -> Int -> IntuitiveState -> (Maybe IntuitiveFlash, IntuitiveState)
checkIntuition resonance tension turnNumber state =
  let newPost = updatePosterior resonance tension (isPosterior state)
      newLongPost = updateLongPosterior resonance tension (isLongPosterior state)
      newCooldown = max 0 (isCooldown state - 1)
      state' = state
        { isPosterior = newPost
        , isLongPosterior = newLongPost
        , isCooldown = newCooldown
        }
      currentPosterior = effectivePosterior state'
  in if newCooldown > 0
     then (Nothing, state')
     else if currentPosterior >= flashThreshold
          then let flash = buildFlash resonance tension currentPosterior
                   state'' = state'
                     { isPosterior  = posteriorAfterFlash newPost
                     , isLongPosterior = longPosteriorAfterFlash newLongPost
                     , isCooldown   = 2
                     , isFlashCount = isFlashCount state + 1
                     , isLastTurn   = turnNumber
                     }
               in (Just flash, state'')
          else (Nothing, state')

posteriorAfterFlash :: Double -> Double
posteriorAfterFlash posterior =
  max basePrior (posterior * intuitionPosteriorAfterFlashDecayFactor)

longPosteriorAfterFlash :: Double -> Double
longPosteriorAfterFlash posterior =
  max basePrior (posterior * intuitionLongPosteriorAfterFlashDecayFactor)

updateLongPosterior :: Double -> Double -> Double -> Double
updateLongPosterior resonance tension prior =
  clamp01
    ( prior * intuitionLongPosteriorPriorWeight
      + updatePosterior resonance tension prior * intuitionLongPosteriorCurrentWeight
    )

buildFlash :: Double -> Double -> Double -> IntuitiveFlash
buildFlash resonance tension posterior =
  let trigger = selectTrigger resonance tension
      strength = clamp01 ((posterior - flashThreshold) / (1.0 - flashThreshold))
      kernelSig = buildKernelSignal trigger
      directive = buildDirective trigger strength
  in IntuitiveFlash strength trigger kernelSig directive (strength > intuitionFlashOverrideStrengthThreshold)

selectTrigger :: Double -> Double -> FlashTrigger
selectTrigger resonance tension
  | resonance > intuitionHighResonanceThreshold && tension > intuitionHighTensionThreshold = ConvergenceTrigger
  | tension > intuitionCrisisTensionThreshold = CrisisMomentTrigger
  | resonance > intuitionHighResonanceThreshold = DeepResonanceTrigger
  | otherwise                         = PureKernelTrigger

buildKernelSignal :: FlashTrigger -> Text
buildKernelSignal trigger = T.intercalate ". "
  [ kernelSignalPresence
  , kernelSignalDepth
  , triggerContext trigger
  ]

triggerContext :: FlashTrigger -> Text
triggerContext DeepResonanceTrigger = triggerContextDeepResonance
triggerContext CrisisMomentTrigger  = triggerContextCrisisMoment
triggerContext PureKernelTrigger    = triggerContextPureKernel
triggerContext ConvergenceTrigger   = triggerContextConvergence

buildDirective :: FlashTrigger -> Double -> Text
buildDirective trigger strength =
  let header = intuitionHeaderPrefix <> fmtPctText strength <> "]"
      trig   = intuitionTriggerLabel <> renderTrigger trigger
      ovrd   = if strength > intuitionFlashOverrideStrengthThreshold
               then intuitionOverrideDirective
               else intuitionSupplementaryDirective
  in T.unlines [header, trig, ovrd, intuitionFormDirective]

fmtPctText :: Double -> Text
fmtPctText value = T.pack (printf "%.0f%%" (value * 100.0) :: String)

intuitionSignalStrength :: Double
intuitionSignalStrength =
  let v = qxfx0CoreVec
      base = cvPresence v * cvDepth v * (1.0 - cvDirectiveness v) * cvAutonomy v
      steadyBonus = 1.0 + (cvSteadiness v - intuitionSteadinessBaseline) * intuitionSignalSteadyBonusScale
  in base * steadyBonus
