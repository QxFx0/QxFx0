{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module QxFx0.Types.Semantic.Space
  ( PredicateVector(..)
  , AtomVector(..)
  , FieldDimension(..)
  , DimensionPrototype(..)
  , SemanticSpace(..)
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, FromJSONKey, ToJSON, ToJSONKey)
import Data.Map.Strict (Map)
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

data FieldDimension = FdResonance | FdAtmosphere | FdConfidence | FdConsolidation | FdCounterfactual
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
