{-# LANGUAGE DerivingStrategies, OverloadedStrings, StrictData, DeriveGeneric, DeriveAnyClass, GeneralizedNewtypeDeriving #-}
module QxFx0.Lexicon.Types
  ( LanguageCode(..)
  , LexemeId
  , TemplateId
  , SlotKind(..)
  , LexicalRuntimeData(..)
  , emptyLexicalRuntimeData
  ) where

import Data.Text (Text)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import GHC.Generics (Generic)
import Control.DeepSeq (NFData)
import Data.Aeson (ToJSON, FromJSON)

newtype LanguageCode = LanguageCode { unLanguageCode :: Text }
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (NFData, ToJSON, FromJSON)

newtype LexemeId = LexemeId { unLexemeId :: Text }
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (ToJSON, FromJSON)

newtype TemplateId = TemplateId { unTemplateId :: Text }
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (ToJSON, FromJSON)

data SlotKind
  = SlotTopic
  | SlotForce
  | SlotFamily
  | SlotStance
  | SlotStyle
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (ToJSON, FromJSON)

data LexicalRuntimeData = LexicalRuntimeData
  { lrdLanguage      :: !LanguageCode
  , lrdNominative    :: !(Map Text Text)
  , lrdGenitive      :: !(Map Text Text)
  , lrdPrepositional :: !(Map Text Text)
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

emptyLexicalRuntimeData :: LanguageCode -> LexicalRuntimeData
emptyLexicalRuntimeData lang = LexicalRuntimeData
  { lrdLanguage      = lang
  , lrdNominative    = Map.empty
  , lrdGenitive      = Map.empty
  , lrdPrepositional = Map.empty
  }
