{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

-- | Leaf contracts for semantic content carried by persisted state.
module QxFx0.Types.Semantic.Content
  ( PredicateRole(..)
  , CanonicalPredicateRelation(..)
  , SemanticPredicate(..)
  , ChallengeResponse(..)
  , DefinitionContent(..)
  , DistinctionContent(..)
  , ConceptCategory(..)
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import Data.Text (Text)
import GHC.Generics (Generic)

data PredicateRole
  = RoleProperty
  | RoleRelation
  | RoleStructure
  | RoleDifferentiator
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data CanonicalPredicateRelation = CanonicalPredicateRelation
  { cprSubject :: !Text
  , cprRelation :: !Text
  , cprObject :: !Text
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

data SemanticPredicate = SemanticPredicate
  { spRole :: !PredicateRole
  , spRu :: !Text
  , spEn :: !Text
  , spTopicForm :: !Text
  , spCanonicalRelation :: !(Maybe CanonicalPredicateRelation)
  , spRationale :: !(Maybe Text)
  , spCounter :: !(Maybe Text)
  , spSynthesis :: !(Maybe Text)
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

data ChallengeResponse = ChallengeResponse
  { crTopic :: !Text
  , crObjectionKeywords :: ![Text]
  , crRelevantPredicate :: !SemanticPredicate
  , crRestate :: !Text
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

data DefinitionContent = DefinitionContent
  { dcTopic :: !Text
  , dcPredicates :: ![SemanticPredicate]
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

data DistinctionContent = DistinctionContent
  { dcLeft :: !Text
  , dcRight :: !Text
  , dcDifferentiators :: ![SemanticPredicate]
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

data ConceptCategory
  = CategoryPhilosophical
  | CategorySocial
  | CategoryPsychological
  | CategoryPhysical
  | CategoryGeneral
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)
