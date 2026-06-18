{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Semantic.Space.Types
  ( PredicateVector(..)
  , FieldDimension(..)
  , DimensionPrototype(..)
  , SemanticSpace(..)
  , emptySemanticSpace
  , fieldDimensionPrototypes
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON, FromJSONKey, ToJSONKey)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Set (Set)
import Data.Text (Text)
import Data.Vector (Vector)
import GHC.Generics (Generic)

data PredicateVector = PredicateVector
  { pvPredicateId :: !Text
  , pvAtoms       :: !(Set Text)
  , pvVector      :: !(Vector Double)
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

data FieldDimension
  = FdResonance
  | FdAtmosphere
  | FdConfidence
  | FdConsolidation
  | FdCounterfactual
  deriving stock (Eq, Ord, Show, Generic, Enum, Bounded)
    deriving anyclass (NFData, ToJSON, FromJSON, ToJSONKey, FromJSONKey)

data DimensionPrototype = DimensionPrototype
  { dpDimension :: !FieldDimension
  , dpAtoms     :: !(Set Text)
  , dpVector    :: !(Vector Double)
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

data SemanticSpace = SemanticSpace
  { ssDimensionCount   :: !Int
  , ssAtomIndex        :: !(Map Text Int)
  , ssPrototypes       :: !(Map FieldDimension DimensionPrototype)
  , ssPredicateVectors :: !(Map Text PredicateVector)
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

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
