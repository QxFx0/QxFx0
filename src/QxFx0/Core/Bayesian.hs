{-# LANGUAGE OverloadedStrings #-}
{-|
Experimental discrete belief update over hidden user intents (lemma likelihoods).

Not wired into the production turn pipeline. Runtime routing uses
'Semantic.Logic' for family selection and 'QxFx0.Core.Intuition' for
threshold-based flash hints. See spec/BayesianCoverage.agda in the extended
scientific contour.
-}
module QxFx0.Core.Bayesian
  ( bayesianUpdate
  , bayesianUpdateFromText
  , detectInsight
  , likelihood
  , maxBelief
  ) where

import qualified Data.Map.Strict as M
import Data.Maybe (listToMaybe)
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Types.SemanticConfig (SemanticConfig(..))
import QxFx0.Semantic.Input.Parse (ParsedInput(..), ParsedToken(..))
import QxFx0.Types.Bayesian
  ( HiddenBelief(..)
  , BeliefState
  )

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
