{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Semantic.LLMDiscovery
Description : L3 — Live atom/relation discovery via LLM API.

When a user asks about a concept not in the AtomStore, this module
calls an LLM API (Fireworks AI / deepseek-v4-pro) to extract
philosophical relations between the concept and L1 topics.

The LLM is a discovery engine only — it never generates dialogue output.
Extracted relations go through the same admission pipeline and gates
as substrate-extracted relations. Once admitted, they are cached in
the graph and subsequent requests for the same concept are served
from the graph (deterministic, no LLM call).

API key is read from QXFX0_LLM_API_KEY env var. Never hardcoded.
-}
module QxFx0.Semantic.LLMDiscovery
  ( LLMConfig(..)
  , defaultLLMConfig
  , discoverFromLLM
  , parseLLMRelations
  , buildDiscoveryPrompt
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson
import qualified Data.Aeson as A
import Data.List (intercalate, isInfixOf, find)
import Data.Maybe (fromMaybe, mapMaybe, listToMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)
import Network.HTTP.Client
import Network.HTTP.Client.TLS (tlsManagerSettings)
import qualified Data.ByteString.Lazy as LBS
import qualified Data.ByteString.Char8 as BS8

import QxFx0.Semantic.Content.AtomStore

-- | LLM API configuration.
data LLMConfig = LLMConfig
  { llmApiKey :: !Text
  , llmUrl   :: !Text
  , llmModel :: !Text
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Default config for Fireworks AI / deepseek-v4-pro.
defaultLLMConfig :: Text -> LLMConfig
defaultLLMConfig apiKey = LLMConfig
  { llmApiKey = apiKey
  , llmUrl = "https://api.fireworks.ai/inference/v1/chat/completions"
  , llmModel = "accounts/fireworks/models/deepseek-v4-pro"
  }

-- | Discover relations for a concept via LLM.
-- Returns candidate relations (not yet admitted — caller runs admission).
discoverFromLLM :: LLMConfig -> Text -> IO [Relation]
discoverFromLLM config concept = do
  let prompt = buildDiscoveryPrompt concept
  let requestBody = A.encode $ A.object
        [ "model" A..= llmModel config
        , "max_tokens" A..= (4096 :: Int)
        , "messages" A..= [ A.object
            [ "role" A..= ("user" :: Text)
            , "content" A..= prompt
            ]
          ]
        ]
  let request = (parseRequest_ (T.unpack (llmUrl config)))
        { method = "POST"
        , requestBody = RequestBodyLBS requestBody
        , requestHeaders =
            [ ("Accept", "application/json")
            , ("Content-Type", "application/json")
            , ("Authorization", "Bearer " <> BS8.pack (T.unpack (llmApiKey config)))
            ]
        }
  manager <- newManager tlsManagerSettings
  response <- httpLbs request manager
  let body = responseBody response
  case A.eitherDecode body of
    Right (LLMResponse { lrChoices = choices }) ->
      case choices of
        (choice:_) -> return $ parseLLMRelations concept (mContent (cMessage choice))
        [] -> return []
    Left _ -> return []

-- | Build a structured prompt for the LLM to extract relations.
buildDiscoveryPrompt :: Text -> Text
buildDiscoveryPrompt concept =
  "Ты философский анализатор. Извлеки отношения концепта \"" <> concept <> "\" к философским темам.\n"
  <> "Темы L1: свобода, истина, сознание, ответственность, страх, вера, память, "
  <> "смерть, время, разум, бытие, язык, воля, любовь, труд, долг, доверие, "
  <> "надежда, справедливость, власть, красота, одиночество, покой, правда, молчание.\n\n"
  <> "Для каждого отношения выведи строку в формате:\n"
  <> "SUBJECT | VERB | OBJECT | TYPE\n\n"
  <> "Где:\n"
  <> "- SUBJECT: \"" <> concept <> "\" или связанная L1 тема\n"
  <> "- VERB: один из: предполагает, ограничена, требует, претендует, "
  <> "проверяется, сигнализирует, выражает, отличается, связана, "
  <> "сохраняет, ориентирует, предписывает, обозначает, структурирует, "
  <> "определяет, преобразует, придаёт, обнаруживает, признаёт, "
  <> "объединяет, связывает, предшествует, зависит, включает, "
  <> "вызывает, означает, говорит, отрицает, направляет, указывает, "
  <> "делает, поддерживает, задаёт, разрушает\n"
  <> "- OBJECT: L1 тема или конкретный концепт\n"
  <> "- TYPE: один из: presupposes, limitedBy, requires, claims, "
  <> "verifiedBy, signals, expresses, differsFrom, relatedTo, "
  <> "preserves, orientsToward, prescribes, denotes, structures, "
  <> "determines, transforms, gives, reveals, recognizes, "
  <> "unifies, connects, precedes, dependsOn, includes, "
  <> "evokes, means, says, negates, directedAt, pointsTo, "
  <> "makes, supports, sets, destroys, contrastsWith, notReducibleTo\n\n"
  <> "Выведи 3-7 отношений. Только факты, никаких рассуждений.\n"
  <> "Пример:\n"
  <> "свобода | предполагает | возможность выбора | presupposes\n"
  <> "свобода | ограничена | ответственностью | limitedBy\n"

-- | Parse LLM response text into Relation candidates.
-- Expected format: "SUBJECT | VERB | OBJECT | TYPE" per line.
parseLLMRelations :: Text -> Text -> [Relation]
parseLLMRelations topic responseText =
  let lines = T.lines responseText
      parsed = mapMaybe parseLine lines
  in parsed
  where
    parseLine line =
      let parts = map T.strip (T.splitOn "|" line)
      in case parts of
           [subject, verb, object_, typeStr] ->
             makeRelation subject verb object_ typeStr
           _ -> Nothing

    makeRelation subject verb object_ typeStr =
      let relType = parseRelType typeStr
          fromId = subject
          toId = if T.toLower object_ `elem` map T.toLower allTopics
                   then object_  -- L1 topic: use directly
                   else T.toLower object_  -- concept: lowercase
          ruOriginal = subject <> " " <> verb <> " " <> object_
      in Just $ Relation
           { relFrom = AtomId (T.toLower fromId)
           , relTo = AtomId toId
           , relType = relType
           , relObjectCase = CaseAccusative
           , relObjectText = object_
           , relVerbText = Just verb
           , relRuOriginal = ruOriginal
           , relEnOriginal = ""
           , relSource = SeedFromPredicate  -- will be overridden to LLMDiscovered by caller
           , relTopic = T.toLower topic
           }

    parseRelType :: Text -> RelationType
    parseRelType t = case T.toLower (T.strip t) of
      "presupposes" -> RelPresupposes
      "limitedby" -> RelLimitedBy
      "requires" -> RelRequires
      "claims" -> RelClaims
      "verifiedby" -> RelVerifiedBy
      "signals" -> RelSignals
      "expresses" -> RelExpresses
      "differsfrom" -> RelDiffersFrom
      "relatedto" -> RelRelatedTo
      "preserves" -> RelPreserves
      "orientstoward" -> RelOrientsToward
      "prescribes" -> RelPrescribes
      "denotes" -> RelDenotes
      "structures" -> RelStructures
      "determines" -> RelDetermines
      "transforms" -> RelTransforms
      "gives" -> RelGives
      "reveals" -> RelReveals
      "recognizes" -> RelRecognizes
      "unifies" -> RelUnifies
      "connects" -> RelConnects
      "precedes" -> RelPrecedes
      "dependson" -> RelDependsOn
      "includes" -> RelIncludes
      "evokes" -> RelEvokes
      "means" -> RelMeans
      "says" -> RelSays
      "negates" -> RelNegates
      "directedat" -> RelDirectedAt
      "pointsto" -> RelPointsTo
      "makes" -> RelMakes
      "supports" -> RelSupports
      "sets" -> RelSets
      "destroys" -> RelDestroys
      "contrastswith" -> RelContrastsWith
      "notreducibleto" -> RelNotReducibleTo
      _ -> RelRelatedTo  -- safe default

-- | LLM API response types.
data LLMResponse = LLMResponse
  { lrChoices :: ![LLMChoice]
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON)

data LLMChoice = LLMChoice
  { cMessage :: !LLMMessage
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON)

data LLMMessage = LLMMessage
  { mContent :: !Text
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (FromJSON)
