{-# LANGUAGE DerivingStrategies, OverloadedStrings, DeriveGeneric, DeriveAnyClass #-}
{-| Intuition heuristics for flash detection, posterior updates, and directive shaping. -}
module QxFx0.Core.Intuition
  ( IntuitiveState(..)
  , defaultIntuitiveState
  , basePrior
  , IntuitiveFlash(..)
  , likelihoodGivenFlash
  , updatePosterior
  , likelihoodGivenNoFlash
  , posteriorAfterFlash
  , longPosteriorAfterFlash
  , updateLongPosterior
  , flashThreshold
  , checkIntuition
  , checkIntuitionWithInput
  , checkIntuitionWithSalience
  , checkIntuitionWithInputAndSalience
  , applySalienceToFlash
  , salienceFlashMultiplier
  , bayesianBeliefNudge
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
  , intuitionCooldownTurns
  )
import QxFx0.Policy.Consciousness
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
  , FlashTrigger(..)
  , IntuitiveFlash(..)
  )
import QxFx0.Types.Vec (CoreVec(..))
import QxFx0.Types.SemanticConfig (SemanticConfig(..), defaultSemanticConfig)
import QxFx0.Types.Bayesian (initialBeliefs)
import QxFx0.Core.Bayesian (bayesianUpdateFromText, maxBelief)
import QxFx0.Self.Salience (Salience, salienceHolisticBias)
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

qxfx0CoreVec :: CoreVec
qxfx0CoreVec =
  CoreVec
    intuitionCoreVecPresence
    intuitionCoreVecDepth
    intuitionCoreVecAutonomy
    intuitionCoreVecDirectiveness
    intuitionCoreVecSteadiness

bayesianBeliefNudge :: SemanticConfig -> Text -> Double
bayesianBeliefNudge cfg raw =
  clamp01 (maxBelief (bayesianUpdateFromText cfg initialBeliefs raw) * 0.08)

checkIntuitionWithInput :: Text -> Double -> Double -> Int -> IntuitiveState -> (Maybe IntuitiveFlash, IntuitiveState)
checkIntuitionWithInput raw resonance tension turnNumber state =
  let nudge = bayesianBeliefNudge defaultSemanticConfig raw
      adjustedResonance = clamp01 (resonance + nudge * 0.25)
      adjustedTension = clamp01 (tension + nudge * 0.15)
  in checkIntuition adjustedResonance adjustedTension turnNumber state

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
                      , isCooldown   = intuitionCooldownTurns
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

-- | Multiplier applied to flash strength under a 'Salience' verdict.
--
-- Capped at @1.0@ so neutral or holistic-leaning salience never
-- /boosts/ flashes above their base strength; only formal-leaning
-- salience attenuates. At @salienceHolisticBias = 0.5@ (the
-- neutral / dead-band point) the multiplier is exactly @1.0@,
-- so wiring the salience controller into a call site that does
-- not yet supply rich Field signals is a strict no-op.
salienceFlashMultiplier :: Salience -> Double
salienceFlashMultiplier salience = min 1.0 (2.0 * salienceHolisticBias salience)

-- | Re-shape an 'IntuitiveFlash' under a salience verdict. The
-- flash strength is scaled by 'salienceFlashMultiplier'; the
-- override flag and directive text are recomputed so the trace
-- stays internally consistent.
applySalienceToFlash :: Salience -> IntuitiveFlash -> IntuitiveFlash
applySalienceToFlash salience flash =
  let multiplier   = salienceFlashMultiplier salience
      newStrength  = clamp01 (ifStrength flash * multiplier)
      newOverride  = newStrength > intuitionFlashOverrideStrengthThreshold
      newDirective = buildDirective (ifTrigger flash) newStrength
  in flash
       { ifStrength     = newStrength
       , ifDirective    = newDirective
       , ifOverridesAll = newOverride
       }

-- | Salience-aware variant of 'checkIntuition'. The flash-detection
-- decision is unchanged; the produced flash, if any, is
-- post-processed via 'applySalienceToFlash'.
checkIntuitionWithSalience
  :: Salience
  -> Double -> Double -> Int -> IntuitiveState
  -> (Maybe IntuitiveFlash, IntuitiveState)
checkIntuitionWithSalience salience resonance tension turnNumber state =
  let (mFlash, state') = checkIntuition resonance tension turnNumber state
  in (fmap (applySalienceToFlash salience) mFlash, state')

-- | Salience-aware variant of 'checkIntuitionWithInput'.
checkIntuitionWithInputAndSalience
  :: Salience
  -> Text -> Double -> Double -> Int -> IntuitiveState
  -> (Maybe IntuitiveFlash, IntuitiveState)
checkIntuitionWithInputAndSalience salience raw resonance tension turnNumber state =
  let (mFlash, state') = checkIntuitionWithInput raw resonance tension turnNumber state
  in (fmap (applySalienceToFlash salience) mFlash, state')
