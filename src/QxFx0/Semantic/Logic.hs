{-# LANGUAGE OverloadedStrings #-}
module QxFx0.Semantic.Logic
  ( RankedFamily
  , runSemanticLogic
  ) where

import Data.Maybe (catMaybes)
import QxFx0.Policy.SemanticScoring
  ( semanticFallbackGroundWeight
  , semanticFallbackNextStepWeight
  , semanticLogicAnchorWeight
  , semanticLogicClarifyWeight
  , semanticLogicConfrontWeight
  , semanticLogicContactWeight
  , semanticLogicDeepenWeight
  , semanticLogicDefineWeight
  , semanticLogicDistinguishWeight
  , semanticLogicHypothesisWeight
  , semanticLogicReflectWeight
  , semanticLogicRepairWeight
  , semanticSpecialDescribeWeight
  , semanticSpecialPurposeWeight
  )
import QxFx0.Types (AtomSet(..), MeaningAtom(..), AtomTag(..), CanonicalMoveFamily(..))

type RankedFamily = (CanonicalMoveFamily, Double)

data LogicRule = LogicRule
  { lrFamily :: CanonicalMoveFamily
  , lrWeight :: Double
  , lrMatch :: MeaningAtom -> Bool
  }

ruleTable :: [LogicRule]
ruleTable =
  [ LogicRule CMRepair      semanticLogicRepairWeight      (\a -> case maTag a of Exhaustion _ -> True; _ -> False)
  , LogicRule CMContact     semanticLogicContactWeight     (\a -> case maTag a of NeedContact _ -> True; _ -> False)
  , LogicRule CMDefine      semanticLogicDefineWeight      (\a -> case maTag a of Searching _ -> True; _ -> False)
  , LogicRule CMReflect     semanticLogicReflectWeight     (\a -> case maTag a of NeedMeaning _ -> True; _ -> False)
  , LogicRule CMAnchor      semanticLogicAnchorWeight      (\a -> case maTag a of Anchoring _ -> True; _ -> False)
  , LogicRule CMClarify     semanticLogicClarifyWeight     (\a -> case maTag a of Verification _ -> True; _ -> False)
  , LogicRule CMDeepen      semanticLogicDeepenWeight      (\a -> case maTag a of AgencyFound _ -> True; _ -> False)
  , LogicRule CMConfront    semanticLogicConfrontWeight    (\a -> case maTag a of Contradiction _ _ -> True; _ -> False)
  , LogicRule CMDistinguish semanticLogicDistinguishWeight (\a -> case maTag a of Doubt _ -> True; _ -> False)
  , LogicRule CMHypothesis  semanticLogicHypothesisWeight  (\a -> case maTag a of Doubt _ -> True; _ -> False)
  ]

runRule :: LogicRule -> [MeaningAtom] -> Maybe RankedFamily
runRule rule atoms
  | any (lrMatch rule) atoms = Just (lrFamily rule, lrWeight rule)
  | otherwise = Nothing

runSpecialRule :: CanonicalMoveFamily -> Double -> (Int -> Bool) -> [MeaningAtom] -> Maybe RankedFamily
runSpecialRule family weight cond atoms
  | cond (length atoms) = Just (family, weight)
  | otherwise = Nothing

runSemanticLogic :: AtomSet -> [RankedFamily]
runSemanticLogic atoms =
  let rawAtoms = asAtoms atoms
      primaryResults = concatMap (\r -> maybe [] (:[]) (runRule r rawAtoms)) ruleTable
      specialResults = catMaybes
        [ runSpecialRule CMPurpose semanticSpecialPurposeWeight (> 3) rawAtoms
        , runSpecialRule CMDescribe semanticSpecialDescribeWeight (== 0) rawAtoms
        ]
      results = primaryResults ++ specialResults
      fallbacks = case results of
                    [] -> [(CMNextStep, semanticFallbackNextStepWeight), (CMGround, semanticFallbackGroundWeight)]
                    [(CMDescribe, _)] -> [(CMNextStep, semanticFallbackNextStepWeight), (CMGround, semanticFallbackGroundWeight)] ++ results
                    _ -> []
  in results ++ fallbacks
