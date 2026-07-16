{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

module QxFx0.Lexicon.Expanded.Types where

import GHC.Generics (Generic)
import Control.DeepSeq (NFData)
import Data.Text (Text)
import Data.Aeson (ToJSON, FromJSON)
import qualified Data.Map.Strict as M
import QxFx0.Types (LexemeCase, LexemeNumber)

-- | Supported languages in the expanded lexicon.
data LanguageCode = RU | EN
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Abstract grammatical features to replace language-specific cases.
-- This allow the system to handle English (Possessive) and Russian (Cases) uniformly.
data GrammaticalFeature
  = FeatureCase LexemeCase
  | FeatureNumber LexemeNumber
  | FeaturePossessive
  | FeaturePlural
  | FeatureDefault
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | The source tier of the lexical data.
data LexicalTier
  = TierCurated     -- ^ Manually verified, highest priority
  | TierCore        -- ^ Verified dictionary
  | TierAlgorithmic -- ^ Rule-based generation
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | A request for a specific word form.
-- Features are now a set/map for flexibility across languages.
data MorphologyRequest = MorphologyRequest
  { mrLang     :: !LanguageCode
  , mrLemma    :: !Text
  , mrFeatures :: ![GrammaticalFeature]
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- | The result of a morphology lookup.
data MorphologyResponse = MorphologyResponse
  { resSurface    :: !Text
  , resTier       :: !LexicalTier
  , resConfidence :: !Double
  , resSource     :: !Text -- ^ Name of the provider that resolved this
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Error types for lexicon operations to avoid 'error' calls.
data LexiconError
  = ResourceMissing FilePath
  | ParseError String
  | ProviderFailure Text
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Metadata for a lexeme.
data LexemeMetadata = LexemeMetadata
  { lmPos        :: !Text
  , lmQuality    :: !Double
  , lmSource     :: !Text
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)
