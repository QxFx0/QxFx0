{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Semantic.Space
  ( module QxFx0.Semantic.Space.Types
  , buildPredicateVector
  , computeFieldAffinity
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Set (Set)
import qualified Data.Set as S
import Data.Text (Text)
import Data.Vector (Vector)
import qualified Data.Vector as V

import QxFx0.Semantic.Network (SemanticNetwork(..))
import QxFx0.Semantic.Space.Types

buildPredicateVector :: SemanticNetwork -> Text -> Set Text -> PredicateVector
buildPredicateVector sn predicateId atoms =
  let dimCount = S.size (snNodes sn)
      vec = V.replicate dimCount 0.0
      vec' = foldl (\v atom ->
        case M.lookup atom (M.fromList $ zip (S.toList (snNodes sn)) [0..]) of
          Nothing -> v
          Just idx -> v V.// [(idx, 1.0)]
        ) vec (S.toList atoms)
  in PredicateVector predicateId atoms vec'

computeFieldAffinity :: SemanticSpace -> FieldDimension -> PredicateVector -> Double
computeFieldAffinity space dim pv =
  case M.lookup dim (ssPrototypes space) of
    Nothing -> 0.5
    Just prototype ->
      let dotProduct = V.sum $ V.zipWith (*) (pvVector pv) (dpVector prototype)
          normPV = sqrt $ V.sum $ V.map (^2) (pvVector pv)
          normProto = sqrt $ V.sum $ V.map (^2) (dpVector prototype)
      in if normPV == 0 || normProto == 0
         then 0.5
         else dotProduct / (normPV * normProto)

