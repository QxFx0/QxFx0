{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Learning.Parser
Description : WP4 — Parse external tool response into KnowledgeFruitPayload.

Supports strict JSON schema first; falls back to constrained text
parsing only when the response body is not valid JSON.

The JSON schema expected from an LLM (or script) is:

```json
{
  "proposition": "string",
  "word": "string",
  "definition": "string",
  "morphology": {
    "gender": "masculine|feminine|neuter",
    "declension": "first|second|...",
    "cases": {
      "nom": "...", "gen": "...", "dat": "...",
      "acc": "...", "ins": "...", "pre": "..."
    }
  },
  "source": "llm|human|script|internal",
  "conatusDelta": 0.0,
  "predictiveDelta": 0.0
}
```

All fields except @morphology@ are required.  Missing optional fields
yield 'Nothing' / 'False' / '0.0' defaults.
-}
module QxFx0.Learning.Parser
  ( parseLLMResponseToFruit
  , parseStructuredTextToFruit
  ) where

import Control.Applicative ((<|>))
import Data.Aeson (FromJSON, ToJSON, Value(..), decodeStrict, withObject, (.:), (.:?), (.!=))
import Data.Aeson.Types (Parser, parseEither)
import Data.ByteString (ByteString)
import qualified Data.ByteString.Lazy as LBS
import Data.Char (isSpace)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import GHC.Generics (Generic)
import qualified Data.Map.Strict as M

import QxFx0.Learning.KnowledgeTree (KnowledgeSource(..))
import QxFx0.Learning.Validator
  ( KnowledgeFruitPayload(..)
  , MorphologyPayload(..)
  )
import QxFx0.Types.ExternalQuery (ExternalQueryResponse(..))

-- | Top-level entry point: parse an 'ExternalQueryResponse' into a
-- 'KnowledgeFruitPayload'.
--
-- 1. Try the structured field (already extracted JSON from Mistral
--    chat-completion envelope).
-- 2. Try the raw body as JSON.
-- 3. Fallback to constrained text parsing.
parseLLMResponseToFruit :: ExternalQueryResponse -> Maybe KnowledgeFruitPayload
parseLLMResponseToFruit resp =
  -- First: try structured field (JSON inside the LLM content field)
  parseJsonPayload (eqrStructured resp)
  -- Second: try raw body (in case structured extraction failed)
  <|> parseJsonPayload (eqrRawBody resp)
  -- Third: fallback text parser
  <|> parseStructuredTextToFruit (eqrRawBody resp)

-- | Parse a strict JSON payload.
parseJsonPayload :: Text -> Maybe KnowledgeFruitPayload
parseJsonPayload txt =
  case decodeStrict (TE.encodeUtf8 txt) of
    Nothing -> Nothing
    Just val ->
      case parseEither parseFruitPayload val of
        Left _  -> Nothing
        Right p -> Just p

parseFruitPayload :: Value -> Parser KnowledgeFruitPayload
parseFruitPayload = withObject "KnowledgeFruitPayload" $ \o -> do
  prop      <- o .:  "proposition"
  word      <- o .:  "word"
  def       <- o .:  "definition"
  morphObj  <- o .:? "morphology"
  srcTag    <- o .:? "source" .!= "llm"
  cDelta    <- o .:? "conatusDelta" .!= 0.0
  pDelta    <- o .:? "predictiveDelta" .!= 0.0
  morph <- case morphObj of
    Nothing -> pure Nothing
    Just m  -> Just <$> parseMorphologyPayload m
  pure KnowledgeFruitPayload
    { kfpProposition     = prop
    , kfpWord            = word
    , kfpDefinition      = def
    , kfpMorphology      = morph
    , kfpSource          = parseSourceTag srcTag
    , kfpConatusDelta    = cDelta
    , kfpPredictiveDelta = pDelta
    }

parseMorphologyPayload :: Value -> Parser MorphologyPayload
parseMorphologyPayload = withObject "MorphologyPayload" $ \o ->
  MorphologyPayload
    <$> o .:? "gender"
    <*> o .:? "declension"
    <*> o .:? "cases"

parseSourceTag :: Text -> KnowledgeSource
parseSourceTag "llm"      = SourceLLM
parseSourceTag "human"    = SourceHuman
parseSourceTag "script"   = SourceScript
parseSourceTag "internal" = SourceInternal
parseSourceTag _          = SourceLLM

-- | Fallback constrained text parser.
--
-- Expects a very rigid format (one per line):
--   Word: <word>
--   Definition: <definition>
--   Proposition: <proposition>
--   ConatusDelta: <float>
--   PredictiveDelta: <float>
--
-- If any required line is missing or malformed, returns 'Nothing'.
parseStructuredTextToFruit :: Text -> Maybe KnowledgeFruitPayload
parseStructuredTextToFruit txt = do
  let lines' = map T.strip (T.lines txt)
      dict   = M.fromList
                 [ (T.toLower (T.takeWhile (/= ':') line), T.strip (T.drop 1 (T.dropWhile (/= ':') line)))
                 | line <- lines'
                 , T.isInfixOf ":" line
                 ]
  word        <- M.lookup (T.pack "word") dict
  definition  <- M.lookup (T.pack "definition") dict
  proposition <- Just (fromMaybe word (M.lookup (T.pack "proposition") dict))
  let cDelta  = readDouble (fromMaybe "0.0" (M.lookup (T.pack "conatusdelta") dict))
      pDelta  = readDouble (fromMaybe "0.0" (M.lookup (T.pack "predictivedelta") dict))
  pure KnowledgeFruitPayload
    { kfpProposition     = proposition
    , kfpWord            = word
    , kfpDefinition      = definition
    , kfpMorphology      = Nothing
    , kfpSource          = SourceLLM
    , kfpConatusDelta    = cDelta
    , kfpPredictiveDelta = pDelta
    }

readDouble :: Text -> Double
readDouble t =
  case reads (T.unpack (T.strip t)) of
    [(d, "")] -> d
    _         -> 0.0
