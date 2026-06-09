{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-| Lexical paradigm types — pure data layer.

    Moved from Semantic.Lexicon.RuntimeParadigms to avoid
    Types/State/System importing Semantic (layer violation).
    Logic (load, lookup, inference) remains in Semantic.
-}
module QxFx0.Types.Lexicon.RuntimeParadigms
  ( PartOfSpeech(..)
  , partOfSpeechText
  , parsePartOfSpeechText
  , ParadigmEntry(..)
  , RuntimeParadigms(..)
  , emptyRuntimeParadigms
  ) where

import Data.Aeson (FromJSON(..), ToJSON(..), genericParseJSON, genericToJSON, defaultOptions, fieldLabelModifier, withText, Value(String))
import Data.Char (toLower)
import Data.Map.Strict (Map)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)
import Control.DeepSeq (NFData)

--------------------------------------------------------------------------------
-- PartOfSpeech
--------------------------------------------------------------------------------

data PartOfSpeech
  = PosNoun
  | PosVerb
  | PosAdjective
  | PosAdverb
  | PosExpression
  | PosMetaphor
  deriving stock (Eq, Ord, Show, Read, Bounded, Enum, Generic)
  deriving anyclass (NFData)

instance FromJSON PartOfSpeech where
  parseJSON = withText "PartOfSpeech" $ \t ->
    case parsePartOfSpeechText t of
      Just pos -> pure pos
      Nothing  -> fail ("Unknown PartOfSpeech: " ++ T.unpack t)

instance ToJSON PartOfSpeech where
  toJSON pos = String (partOfSpeechText pos)

partOfSpeechText :: PartOfSpeech -> Text
partOfSpeechText PosNoun       = "Noun"
partOfSpeechText PosVerb       = "Verb"
partOfSpeechText PosAdjective  = "Adjective"
partOfSpeechText PosAdverb     = "Adverb"
partOfSpeechText PosExpression = "Expression"
partOfSpeechText PosMetaphor   = "Metaphor"

parsePartOfSpeechText :: Text -> Maybe PartOfSpeech
parsePartOfSpeechText t = case t of
  "Noun"       -> Just PosNoun
  "Verb"       -> Just PosVerb
  "Adjective"  -> Just PosAdjective
  "Adverb"     -> Just PosAdverb
  "Expression" -> Just PosExpression
  "Metaphor"   -> Just PosMetaphor
  _            -> Nothing

--------------------------------------------------------------------------------
-- ParadigmEntry
--------------------------------------------------------------------------------

data ParadigmEntry = ParadigmEntry
  { pePos     :: !PartOfSpeech
  , peGender  :: !(Maybe Text)
  , peAnimacy :: !(Maybe Text)
  , peAspect  :: !(Maybe Text)
  , peTransitivity :: !(Maybe Text)
  , peForms   :: !(Map Text Text)
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance FromJSON ParadigmEntry where
  parseJSON = genericParseJSON defaultOptions
    { fieldLabelModifier = \lbl -> case lbl of
        ('p':'e':rest) -> map toLower rest
        _              -> map toLower lbl
    }

instance ToJSON ParadigmEntry where
  toJSON = genericToJSON defaultOptions
    { fieldLabelModifier = \lbl -> case lbl of
        ('p':'e':rest) -> map toLower rest
        _              -> map toLower lbl
    }

--------------------------------------------------------------------------------
-- RuntimeParadigms
--------------------------------------------------------------------------------

data RuntimeParadigms = RuntimeParadigms
  { rpMap        :: !(Map Text ParadigmEntry)
  , rpExceptions :: !(Map Text ParadigmEntry)
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance FromJSON RuntimeParadigms where
  parseJSON = genericParseJSON defaultOptions
    { fieldLabelModifier = \lbl -> case lbl of
        ('r':'p':rest) -> map toLower rest
        _              -> map toLower lbl
    }

instance ToJSON RuntimeParadigms where
  toJSON = genericToJSON defaultOptions
    { fieldLabelModifier = \lbl -> case lbl of
        ('r':'p':rest) -> map toLower rest
        _              -> map toLower lbl
    }

emptyRuntimeParadigms :: RuntimeParadigms
emptyRuntimeParadigms = RuntimeParadigms mempty mempty
