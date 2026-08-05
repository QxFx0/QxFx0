{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

-- | Leaf contracts for persisted multi-turn semantic context.
module QxFx0.Types.Semantic.DialogueContext
  ( DialogueContext(..)
  , ContextEntry(..)
  , ContextRole(..)
  , emptyDialogueContext
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import Data.Text (Text)
import GHC.Generics (Generic)

import QxFx0.Types.Semantic.AtomGraph (Relation)

data ContextEntry = ContextEntry
  { ceTurn :: !Int
  , ceRole :: !ContextRole
  , ceTopic :: !Text
  , ceSurface :: !Text
  , ceRelations :: ![Relation]
  , ceTTL :: !Int
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data ContextRole = RoleSystem | RoleUser
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data DialogueContext = DialogueContext
  { dcEntries :: ![ContextEntry]
  , dcTurnCount :: !Int
  , dcMaxEntries :: !Int
  , dcTTL :: !Int
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

emptyDialogueContext :: DialogueContext
emptyDialogueContext = DialogueContext
  { dcEntries = []
  , dcTurnCount = 0
  , dcMaxEntries = 10
  , dcTTL = 5
  }
