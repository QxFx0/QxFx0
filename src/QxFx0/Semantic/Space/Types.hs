{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Semantic.Space.Types
  ( PredicateVector(..)
  , AtomVector(..)
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

import QxFx0.Types.State.SemanticCommitment (CommitmentId)

data PredicateVector = PredicateVector
  { pvPredicateId :: !Text
  , pvAtoms       :: !(Set Text)
  , pvVector      :: !(Vector Double)
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

newtype AtomVector = AtomVector { unAtomVector :: Vector Double }
  deriving stock (Eq, Show, Generic)
  deriving newtype (NFData, ToJSON, FromJSON)

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
  , ssFactVectors      :: !(Map CommitmentId AtomVector)
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

emptySemanticSpace :: SemanticSpace
emptySemanticSpace = SemanticSpace
  { ssDimensionCount = 0
  , ssAtomIndex = M.empty
  , ssPrototypes = M.empty
  , ssPredicateVectors = M.empty
  , ssFactVectors = M.empty
  }

fieldDimensionPrototypes :: Map FieldDimension [Text]
fieldDimensionPrototypes = M.fromList
  [ (FdResonance, ["связана", "связан", "зависит", "контекст"])
  , (FdAtmosphere, ["выражает", "обозначает", "сигнализирует", "вызывает"])
  , (FdConfidence, ["претендует", "требует", "доказательства", "факт"])
  , (FdConsolidation, ["субъекта", "действие", "ответственность", "последствий"])
  , (FdCounterfactual, ["возможность", "независимо", "границу", "условиях"])
  ]
