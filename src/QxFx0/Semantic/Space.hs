{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Semantic.Space
  ( PredicateVector(..)
  , FieldDimension(..)
  , DimensionPrototype(..)
  , SemanticSpace(..)
  , emptySemanticSpace
  , buildPredicateVector
  , computeFieldAffinity
  , fieldDimensionPrototypes
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Set (Set)
import qualified Data.Set as S
import Data.Text (Text)
import Data.Vector (Vector)
import qualified Data.Vector as V
import GHC.Generics (Generic)

import QxFx0.Semantic.Network (SemanticNetwork(..))

data PredicateVector = PredicateVector
  { pvPredicateId :: !Text
  , pvAtoms       :: !(Set Text)
  , pvVector      :: !(Vector Double)
  } deriving (Eq, Show, Generic)

data FieldDimension
  = FdResonance
  | FdAtmosphere
  | FdConfidence
  | FdConsolidation
  | FdCounterfactual
  deriving (Eq, Ord, Show, Generic, Enum, Bounded)

data DimensionPrototype = DimensionPrototype
  { dpDimension :: !FieldDimension
  , dpAtoms     :: !(Set Text)
  , dpVector    :: !(Vector Double)
  } deriving (Eq, Show, Generic)

data SemanticSpace = SemanticSpace
  { ssDimensionCount   :: !Int
  , ssAtomIndex        :: !(Map Text Int)
  , ssPrototypes       :: !(Map FieldDimension DimensionPrototype)
  , ssPredicateVectors :: !(Map Text PredicateVector)
  } deriving (Eq, Show, Generic)

emptySemanticSpace :: SemanticSpace
emptySemanticSpace = SemanticSpace
  { ssDimensionCount = 0
  , ssAtomIndex = M.empty
  , ssPrototypes = M.empty
  , ssPredicateVectors = M.empty
  }

fieldDimensionPrototypes :: Map FieldDimension [Text]
fieldDimensionPrototypes = M.fromList
  [ (FdResonance, ["связь", "отношение", "контекст", "система"])
  , (FdAtmosphere, ["эффект", "свойство", "аналогия", "выражение"])
  , (FdConfidence, ["количество", "единица", "открыватель", "факт"])
  , (FdConsolidation, ["субъект", "предикат", "причина", "нарратив"])
  , (FdCounterfactual, ["условие", "масштаб", "аналогия", "альтернатива"])
  ]

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
