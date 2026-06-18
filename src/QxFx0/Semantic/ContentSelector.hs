{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Semantic.ContentSelector
  ( ContentSelector(..)
  , SelectedPredicate(..)
  , emptyContentSelector
  , selectPredicates
  , buildContentSelector
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Set (Set)
import qualified Data.Set as S
import Data.Text (Text)
import Data.Vector (Vector)
import qualified Data.Vector as V
import GHC.Generics (Generic)

import QxFx0.Semantic.Space
import QxFx0.Self.Field (Field(..), Resonance(..), Atmosphere(..), FieldConfidence(..), Consolidation(..), Counterfactual(..))

data ContentSelector = ContentSelector
  { csSpace       :: !SemanticSpace
  , csTopicAtoms  :: !(Map Text (Set Text))
  } deriving (Eq, Show, Generic)

data SelectedPredicate = SelectedPredicate
  { spPredicateId :: !Text
  , spScore       :: !Double
  , spAtoms       :: !(Set Text)
  } deriving (Eq, Show, Generic)

emptyContentSelector :: ContentSelector
emptyContentSelector = ContentSelector
  { csSpace = emptySemanticSpace
  , csTopicAtoms = M.empty
  }

buildContentSelector :: SemanticSpace -> Map Text (Set Text) -> ContentSelector
buildContentSelector = ContentSelector

selectPredicates :: ContentSelector -> Field -> Text -> [SelectedPredicate]
selectPredicates cs field topic =
  case M.lookup topic (csTopicAtoms cs) of
    Nothing -> []
    Just atoms ->
      let pv = PredicateVector topic atoms (buildVector (csSpace cs) atoms)
          scores = [ (dim, computeFieldAffinity (csSpace cs) dim pv)
                   | dim <- [FdResonance .. FdCounterfactual]
                   ]
          totalScore = sum [ w * s | (dim, s) <- scores, let w = fieldWeight field dim ]
      in [SelectedPredicate topic totalScore atoms | totalScore > 0.1]

buildVector :: SemanticSpace -> Set Text -> Vector Double
buildVector space atoms =
  let dimCount = ssDimensionCount space
      vec = V.replicate dimCount 0.0
  in foldl (\v atom ->
    case M.lookup atom (ssAtomIndex space) of
      Nothing -> v
      Just idx -> v V.// [(idx, 1.0)]
    ) vec (S.toList atoms)

fieldWeight :: Field -> FieldDimension -> Double
fieldWeight f dim = case dim of
  FdResonance      -> unResonance (fieldResonance f)
  FdAtmosphere     -> atmosphereValence (fieldAtmosphere f)
  FdConfidence     -> unFieldConfidence (fieldConfidence f)
  FdConsolidation  -> unConsolidation (fieldConsolidation f)
  FdCounterfactual -> unCounterfactual (fieldCounterfactual f)
