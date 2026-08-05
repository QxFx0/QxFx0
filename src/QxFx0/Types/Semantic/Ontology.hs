{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

-- | Leaf ontology graph contracts. Loading and lookup policy live in Semantic.
module QxFx0.Types.Semantic.Ontology
  ( OntologyNode(..)
  , Ontology(..)
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import Data.Map.Strict (Map)
import Data.Set (Set)
import Data.Text (Text)
import GHC.Generics (Generic)

import QxFx0.Types.Semantic.Content (ConceptCategory)

data OntologyNode = OntologyNode
  { onName :: !Text
  , onCategory :: !ConceptCategory
  , onParent :: !(Maybe Text)
  , onChildren :: !(Set Text)
  , onDepth :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

data Ontology = Ontology
  { otNodes :: !(Map Text OntologyNode)
  , otRoots :: !(Set Text)
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)
