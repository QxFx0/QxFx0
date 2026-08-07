{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Semantic.Ontology.Dynamic
  ( LearningObservation(..)
  , OntologyLearningConfig(..)
  , defaultLearningConfig
  , DynamicOntologyState(..)
  , emptyDynamicOntologyState
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import Data.Text (Text)
import GHC.Generics (Generic)

import QxFx0.Types.Semantic.AtomGraph (RelationType)

-- | Represents an observation that could lead to ontology learning
data LearningObservation = LearningObservation
  { loSourceTopic :: !Text
  , loTargetTopic :: !Text
  , loRelationType :: !RelationType
  , loConfidence :: !Double
  , loEvidence :: ![Text]
  , loContext :: !(Maybe Text)
  , loTimestamp :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- | Configuration for dynamic ontology learning
data OntologyLearningConfig = OntologyLearningConfig
  { olcMinConfidence :: !Double
  , olcMaxObservations :: !Int
  , olcLearningRate :: !Double
  , olcDecayFactor :: !Double
  , olcMaxSuggestions :: !Int
  , olcValidationThreshold :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- | Default learning configuration
defaultLearningConfig :: OntologyLearningConfig
defaultLearningConfig = OntologyLearningConfig
  { olcMinConfidence = 0.6
  , olcMaxObservations = 1000
  , olcLearningRate = 0.7
  , olcDecayFactor = 0.99
  , olcMaxSuggestions = 10
  , olcValidationThreshold = 0.8
  }

-- | State for dynamic ontology learning
data DynamicOntologyState = DynamicOntologyState
  { dosObservations :: ![LearningObservation]
  , dosLearnedEdges :: ![(Text, Text, RelationType)]
  , dosRejectedEdges :: ![(Text, Text, RelationType, Text)]
  , dosObservationCount :: !Int
  , dosLearningIterations :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- | Empty dynamic ontology state
emptyDynamicOntologyState :: DynamicOntologyState
emptyDynamicOntologyState = DynamicOntologyState
  { dosObservations = []
  , dosLearnedEdges = []
  , dosRejectedEdges = []
  , dosObservationCount = 0
  , dosLearningIterations = 0
  }