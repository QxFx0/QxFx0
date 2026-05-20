{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Learning.Validator
Description : WP3 — Strict response validator for external learning loop.

Validates a parsed 'KnowledgeFruitPayload' before it is allowed to
enter the knowledge tree.  Fail-closed: any ambiguity or conflict
results in 'ValidationError' and the fruit is marked
'kfValidated=False'.

Checks:
1. Target word is present and non-empty.
2. Definition is non-empty and >= 'minDefinitionWords'.
3. Optional morphology payload parses without conflict.
4. No collision with existing 'MorphologyData' / lexicon entries.
-}
module QxFx0.Learning.Validator
  ( ValidationError(..)
  , KnowledgeFruitPayload(..)
  , MorphologyPayload(..)
  , validateFruitPayload
  , renderValidationError
  , minDefinitionWords
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import qualified Data.Map.Strict as M
import Control.Monad (when)
import Data.Foldable (forM_)
import Data.Maybe (isJust)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

import QxFx0.Learning.KnowledgeTree (KnowledgeSource(..))
import QxFx0.Types.Domain.Atoms (MorphologyData(..))

-- | Parsed payload from an external tool before validation.
data KnowledgeFruitPayload = KnowledgeFruitPayload
  { kfpProposition    :: !Text
  , kfpWord           :: !Text
  , kfpDefinition     :: !Text
  , kfpMorphology     :: !(Maybe MorphologyPayload)
  , kfpSource         :: !KnowledgeSource
  , kfpConatusDelta   :: !Double
  , kfpPredictiveDelta:: !Double
  }
  deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- | Simplified morphology description from an LLM.
-- We do NOT require full 'LexemeForm' fidelity at ingest; the
-- sandbox gate (WP5) will exercise the real paradigm later.
data MorphologyPayload = MorphologyPayload
  { mpGender     :: !(Maybe Text)
  , mpDeclension :: !(Maybe Text)
  , mpCases      :: !(Maybe (M.Map Text Text))
    -- ^ e.g. {"nom":"книга","gen":"книги",...}
  }
  deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- | Typed validation-failure taxonomy.
data ValidationError
  = VeEmptyWord
  | VeEmptyDefinition
  | VeDefinitionTooShort !Int !Int   -- ^ actual word count, required minimum
  | VeMorphologyParseFailure !Text
  | VeLexiconConflict !Text         -- ^ conflicting surface form
  | VeInvalidField !Text !Text      -- ^ field name, reason
  deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- | Minimum word count for a definition to be considered substantive.
minDefinitionWords :: Int
minDefinitionWords = 3

-- | Validate a payload against the current morphology/lexicon baseline.
validateFruitPayload
  :: KnowledgeFruitPayload
  -> MorphologyData          -- ^ current runtime morphology (for conflict detection)
  -> Either ValidationError KnowledgeFruitPayload
validateFruitPayload payload morphData = do
  -- 1. Word presence
  when (T.null (T.strip (kfpWord payload))) (Left VeEmptyWord)

  -- 2. Definition substance
  let defStripped = T.strip (kfpDefinition payload)
  when (T.null defStripped) (Left VeEmptyDefinition)
  let wordCount = length (T.words defStripped)
  when (wordCount < minDefinitionWords)
    (Left (VeDefinitionTooShort wordCount minDefinitionWords))

  -- 3. Morphology structural sanity (not deep paradigm fidelity)
  case kfpMorphology payload of
    Nothing -> pure ()
    Just mp -> do
      -- If cases are provided, every value must be non-empty.
      case mpCases mp of
        Nothing -> pure ()
        Just cMap ->
          forM_ (M.toList cMap) (\(k,v) ->
            when (T.null (T.strip v))
              (Left (VeInvalidField (T.concat ["morphology.case.", k]) "empty surface form")))

  -- 4. Lexicon/Morphology conflict check
  let word = T.toLower (T.strip (kfpWord payload))
  when (M.member word (mdNominative morphData))
    (Left (VeLexiconConflict (T.concat ["nominative collision: ", word])))
  when (M.member word (mdFormsBySurface morphData))
    (Left (VeLexiconConflict (T.concat ["surface collision: ", word])))

  pure payload

renderValidationError :: ValidationError -> Text
renderValidationError err =
  case err of
    VeEmptyWord -> "empty_word"
    VeEmptyDefinition -> "empty_definition"
    VeDefinitionTooShort actual req ->
      T.concat ["definition_too_short: got ", T.pack (show actual), " words, need ", T.pack (show req)]
    VeMorphologyParseFailure t -> T.concat ["morphology_parse: ", t]
    VeLexiconConflict t -> T.concat ["lexicon_conflict: ", t]
    VeInvalidField f r -> T.concat ["invalid_field: ", f, " -> ", r]
