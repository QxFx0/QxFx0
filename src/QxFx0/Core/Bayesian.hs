{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Core.Bayesian
  ( bayesianUpdate
  , bayesianUpdateFromText
  , detectInsight
  , likelihood
  , maxBelief
  , likelihoodGivenFlash
  , likelihoodGivenNoFlash
  , updatePosterior
  , posteriorAfterFlash
  , longPosteriorAfterFlash
  , updateLongPosterior
  , checkIntuition
  , triggerToGapDomains
  , intuitionSignalStrength
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Maybe (listToMaybe)
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Types.SemanticConfig (SemanticConfig(..))
import QxFx0.Semantic.Input.Parse (ParsedInput(..), ParsedToken(..))
import QxFx0.Types.Bayesian
  ( HiddenBelief(..)
  , BeliefState
  , initialBeliefs
  )
import QxFx0.Types.Intuition
  ( IntuitiveState(..)
  , FlashTrigger(..)
  , IntuitiveFlash(..)
  , basePrior
  , defaultIntuitiveState
  , effectivePosterior
  )
import QxFx0.Types.Vec (CoreVec(..))
import QxFx0.Types.Thresholds
  ( clamp01
  , intuitionFlashThreshold
  , intuitionHighResonanceThreshold
  , intuitionElevatedResonanceThreshold
  , intuitionDeepResonanceThreshold
  , intuitionHighTensionThreshold
  , intuitionElevatedTensionThreshold
  , intuitionCrisisTensionThreshold
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
-- Distress lemmas now come from SemanticConfig, not a hardcoded list.
import Text.Printf (printf)

bayesianUpdate :: SemanticConfig -> BeliefState -> ParsedInput -> BeliefState
bayesianUpdate cfg prior obs =
  let unnorm = M.mapWithKey (\h p -> p * likelihood cfg h obs) prior
      total  = sum (M.elems unnorm)
  in if total > 1e-9 then M.map (/ total) unnorm else prior

bayesianUpdateFromText :: SemanticConfig -> BeliefState -> Text -> BeliefState
bayesianUpdateFromText cfg prior raw =
  let stress = simpleTextStress cfg raw
      unnorm = M.mapWithKey (\h p -> p * textLikelihood cfg h raw stress) prior
      total  = sum (M.elems unnorm)
  in if total > 1e-9 then M.map (/ total) unnorm else prior

simpleTextStress :: SemanticConfig -> Text -> Double
simpleTextStress cfg raw =
  let w = T.words (T.toLower raw)
      dCount = fromIntegral (length (filter (`elem` scTensionDistressLemmas cfg) w))
      nCount = fromIntegral (length (filter (== "не") w))
      defCount = fromIntegral (length (filter (`elem` scBayesianDefineLemmas cfg) w))
  in dCount + nCount * 0.5 + defCount * 0.3

textLikelihood :: SemanticConfig -> HiddenBelief -> Text -> Double -> Double
textLikelihood cfg UserWantsDefine raw _ =
  let w = T.words (T.toLower raw)
      defCount = fromIntegral (length (filter (`elem` scBayesianDefineLemmas cfg) w))
  in 0.1 + 0.15 * defCount
textLikelihood cfg UserWantsCompare raw _ =
  let w = T.words (T.toLower raw)
      cmpCount = fromIntegral (length (filter (`elem` scBayesianCompareLemmas cfg) w))
  in 0.1 + 0.15 * cmpCount
textLikelihood cfg UserWantsConfront raw _ =
  let w = T.words (T.toLower raw)
      cfmCount = fromIntegral (length (filter (`elem` scBayesianConfrontLemmas cfg) w))
  in 0.05 + 0.2 * cfmCount
textLikelihood cfg UserSeeksSupport raw _ =
  let w = T.words (T.toLower raw)
      supCount = fromIntegral (length (filter (`elem` scBayesianSupportLemmas cfg) w))
  in 0.05 + 0.15 * supCount
textLikelihood cfg UserIsConfused raw _ =
  let w = T.words (T.toLower raw)
      cnfCount = fromIntegral (length (filter (`elem` scBayesianConfusedLemmas cfg) w))
  in 0.05 + 0.2 * cnfCount
textLikelihood _cfg UserIsDistressed _ stress = 0.05 + 0.2 * stress

likelihood :: SemanticConfig -> HiddenBelief -> ParsedInput -> Double
likelihood cfg UserWantsDefine pi =
  let defCount = fromIntegral (length [t | t <- piTokens pi, ptLemma t `elem` scBayesianDefineLemmas cfg])
  in 0.1 + 0.15 * defCount
likelihood cfg UserWantsCompare pi =
  let cmpCount = fromIntegral (length [t | t <- piTokens pi, ptLemma t `elem` scBayesianCompareLemmas cfg])
  in 0.1 + 0.15 * cmpCount
likelihood cfg UserWantsConfront pi =
  let cfmCount = fromIntegral (length [t | t <- piTokens pi, ptLemma t `elem` scBayesianConfrontLemmas cfg])
  in 0.05 + 0.2 * cfmCount
likelihood cfg UserSeeksSupport pi =
  let supCount = fromIntegral (length [t | t <- piTokens pi, ptLemma t `elem` scBayesianSupportLemmas cfg])
  in 0.05 + 0.15 * supCount
likelihood cfg UserIsConfused pi =
  let cnfCount = fromIntegral (length [t | t <- piTokens pi, ptLemma t `elem` scBayesianConfusedLemmas cfg])
  in 0.05 + 0.2 * cnfCount
likelihood cfg UserIsDistressed pi =
  let dWords = fromIntegral (length [t | t <- piTokens pi, ptLemma t `elem` scTensionDistressLemmas cfg])
  in 0.05 + 0.2 * dWords

detectInsight :: BeliefState -> Maybe (HiddenBelief, Double)
detectInsight bs =
  let above = filter (\(_, p) -> p >= 0.95) (M.toList bs)
  in listToMaybe above

maxBelief :: BeliefState -> Double
maxBelief bs = if M.null bs then 0.0 else maximum (M.elems bs)

--------------------------------------------------------------------------------
-- Intuition: posterior updates, flash detection, signal strength
--------------------------------------------------------------------------------

likelihoodGivenFlash :: Double -> Double -> Double
likelihoodGivenFlash resonance tension
  | resonance > intuitionHighResonanceThreshold && tension > intuitionHighTensionThreshold = intuitionFlashLikelihoodConvergent
  | resonance > intuitionElevatedResonanceThreshold || tension > intuitionElevatedTensionThreshold = intuitionFlashLikelihoodElevated
  | resonance > intuitionDeepResonanceThreshold = intuitionFlashLikelihoodDeep
  | otherwise = intuitionFlashLikelihoodBaseline

likelihoodGivenNoFlash :: Double -> Double -> Double
likelihoodGivenNoFlash resonance tension
  | resonance > intuitionHighResonanceThreshold && tension > intuitionHighTensionThreshold = intuitionNoFlashLikelihoodConvergent
  | resonance > intuitionElevatedResonanceThreshold || tension > intuitionElevatedTensionThreshold = intuitionNoFlashLikelihoodElevated
  | resonance > intuitionDeepResonanceThreshold = intuitionNoFlashLikelihoodDeep
  | otherwise = intuitionNoFlashBaselineLikelihood

updatePosterior :: Double -> Double -> Double -> Double
updatePosterior resonance tension prior =
  let pEH  = likelihoodGivenFlash  resonance tension
      pEnH = likelihoodGivenNoFlash resonance tension
      pE   = pEH * prior + pEnH * (1.0 - prior)
  in clamp01 ((pEH * prior) / max 1e-9 pE)

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

triggerToGapDomains :: FlashTrigger -> [Text]
triggerToGapDomains ConvergenceTrigger   = ["HumanPsychology", "CausalChains"]
triggerToGapDomains CrisisMomentTrigger  = ["HumanPsychology"]
triggerToGapDomains DeepResonanceTrigger = ["HumanPsychology", "CulturalAnthropology"]
triggerToGapDomains PureKernelTrigger    = ["CausalChains", "RhetoricalAnalysis"]

intuitionSignalStrength :: Double
intuitionSignalStrength =
  let v = CoreVec
            intuitionCoreVecPresence
            intuitionCoreVecDepth
            intuitionCoreVecAutonomy
            intuitionCoreVecDirectiveness
            intuitionCoreVecSteadiness
      base = cvPresence v * cvDepth v * (1.0 - cvDirectiveness v) * cvAutonomy v
      steadyBonus = 1.0 + (cvSteadiness v - intuitionSteadinessBaseline) * intuitionSignalSteadyBonusScale
  in base * steadyBonus

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
     else if currentPosterior >= intuitionFlashThreshold
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

renderTrigger :: FlashTrigger -> Text
renderTrigger DeepResonanceTrigger = triggerDeepResonance
renderTrigger CrisisMomentTrigger  = triggerCrisisMoment
renderTrigger PureKernelTrigger    = triggerPureKernel
renderTrigger ConvergenceTrigger   = triggerConvergence

triggerContext :: FlashTrigger -> Text
triggerContext DeepResonanceTrigger = triggerContextDeepResonance
triggerContext CrisisMomentTrigger  = triggerContextCrisisMoment
triggerContext PureKernelTrigger    = triggerContextPureKernel
triggerContext ConvergenceTrigger   = triggerContextConvergence

selectTrigger :: Double -> Double -> FlashTrigger
selectTrigger resonance tension
  | resonance > intuitionHighResonanceThreshold && tension > intuitionHighTensionThreshold = ConvergenceTrigger
  | tension > intuitionCrisisTensionThreshold = CrisisMomentTrigger
  | resonance > intuitionHighResonanceThreshold = DeepResonanceTrigger
  | otherwise = PureKernelTrigger

buildFlash :: Double -> Double -> Double -> IntuitiveFlash
buildFlash resonance tension posterior =
  let trigger = selectTrigger resonance tension
      strength = clamp01 ((posterior - intuitionFlashThreshold) / (1.0 - intuitionFlashThreshold))
      kernelSig = buildKernelSignal trigger
      directive = buildDirective trigger strength
  in IntuitiveFlash strength trigger kernelSig directive (strength > intuitionFlashOverrideStrengthThreshold)

buildKernelSignal :: FlashTrigger -> Text
buildKernelSignal trigger = T.intercalate ". "
  [ kernelSignalPresence
  , kernelSignalDepth
  , triggerContext trigger
  ]

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
