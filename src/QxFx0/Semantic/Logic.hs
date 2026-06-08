{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
module QxFx0.Semantic.Logic
  ( RankedFamily
  , runSemanticLogic
  , deriveAtoms
  , derivedInferenceActive
  ) where

import Data.Maybe (catMaybes)
import Data.Text (Text)
import qualified Data.Text as T
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
import qualified Data.Vector as V

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
  let rawAtoms = if derivedInferenceActive
                   then asAtoms atoms ++ deriveAtoms (asAtoms atoms)
                   else asAtoms atoms
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

-- | WP-G: default-on promotion flag gating derived-atom inference. Promoted
-- to default-on (2026-06-04); registered in the flag-off discipline.
derivedInferenceActive :: Bool
derivedInferenceActive = True

-- | WP-G: derive additional atoms from simple multi-step patterns over the
-- existing atom set. These feed into the same 'ruleTable' as raw atoms,
-- allowing a combination (A ∧ B) to fire rules that neither fires alone.
-- This is the living consumer of the derived-inference path.
deriveAtoms :: [MeaningAtom] -> [MeaningAtom]
deriveAtoms input =
  let tags = map maTag input
      hasNeedContact = any (\case NeedContact _ -> True; _ -> False) tags
      hasExhaustion  = any (\case Exhaustion _  -> True; _ -> False) tags
      hasContradiction = any (\case Contradiction _ _ -> True; _ -> False) tags
      hasDoubt       = any (\case Doubt _        -> True; _ -> False) tags
      hasAgencyLost  = any (\case AgencyLost _   -> True; _ -> False) tags
      hasSearching   = any (\case Searching _    -> True; _ -> False) tags

      mk t = MeaningAtom { maText = "derived", maTag = t, maEmbedding = V.empty }

      -- Rule 1: Contact under stress (NeedContact + Exhaustion)
      contactStress
        | hasNeedContact && hasExhaustion = [mk (NeedContact "stressed")]
        | otherwise = []

      -- Rule 2: Contradiction under doubt
      contradictionDoubt
        | hasContradiction && hasDoubt = [mk (Contradiction "amplified" "amplified")]
        | otherwise = []

      -- Rule 3: Agency lost while searching
      agencySearch
        | hasAgencyLost && hasSearching = [mk (Exhaustion "search_exhausted")]
        | otherwise = []

  in concat [contactStress, contradictionDoubt, agencySearch]
