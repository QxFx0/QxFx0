{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Semantic.ContentSelector.Types
  ( ContentSelector(..)
  , SelectedPredicate(..)
  , emptyContentSelector
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Set (Set)
import Data.Text (Text)
import GHC.Generics (Generic)

import QxFx0.Semantic.Space.Types (SemanticSpace, emptySemanticSpace)
import QxFx0.Semantic.Content (SemanticPredicate)
import QxFx0.Semantic.Ontology (Ontology, emptyOntology)

data ContentSelector = ContentSelector
  { csSpace           :: !SemanticSpace
  , csTopicAtoms      :: !(Map Text (Set Text))
  , csTopicPredicates :: !(Map Text [SemanticPredicate])
  , csLemmaMap        :: !(Map Text Text)
  , csOntology        :: !(Maybe Ontology)
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

data SelectedPredicate = SelectedPredicate
  { spPredicateId :: Text
  , spScore :: Double
  , spPredicates :: [SemanticPredicate]
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

emptyContentSelector :: ContentSelector
emptyContentSelector = ContentSelector
  { csSpace = emptySemanticSpace
  , csTopicAtoms = M.empty
  , csTopicPredicates = M.empty
  , csLemmaMap = M.empty
  , csOntology = Nothing
  }
