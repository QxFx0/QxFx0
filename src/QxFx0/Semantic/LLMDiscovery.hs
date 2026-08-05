{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}
{-# OPTIONS_GHC -Wno-deprecations #-}

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
  , parseStructuredLLMRelations
  , buildDiscoveryPrompt
  , buildDiscoveryPromptWithCandidates
  , buildGapAwareDiscoveryPrompt
  , buildCorroborationPrompt
  , responseViolatesTopicLanguage
  ) where

import Control.DeepSeq (NFData)
import Control.Exception (bracket)
import Data.Aeson
import qualified Data.Aeson as A
import Data.Aeson.KeyMap (KeyMap)
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import Data.List (intercalate, isInfixOf, find)
import Data.Char (isAlpha, isAscii)
import Data.Maybe (fromMaybe, mapMaybe, listToMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Vector as V
import GHC.Generics (Generic)
import Network.HTTP.Client
import Network.HTTP.Client.TLS (tlsManagerSettings)
import qualified Data.ByteString.Lazy as LBS
import qualified Data.ByteString.Char8 as BS8
import System.IO (hPutStrLn, stderr)

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
  , llmUrl = "https://api.cerebras.ai/v1/chat/completions"
  , llmModel = "gemma-4-31b"
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
  response <- bracket (newManager tlsManagerSettings) closeManager (httpLbs request)
  let body = responseBody response
  case A.eitherDecode body of
    Right (LLMResponse { lrChoices = choices }) ->
      case choices of
        (choice:_) -> return $ parseLLMRelations concept (mContent (cMessage choice))
        [] -> return []
    Left _ -> do
      -- Try to parse as generic JSON and extract content from choices[0].message.content
      case A.decode body of
        Just val -> 
          case val of
            A.Object obj -> do
              let choices = KeyMap.lookup "choices" obj
              case choices of
                Just (A.Array arr) -> do
                  let firstChoice = arr V.!? 0
                  case firstChoice of
                    Just (A.Object choiceObj) -> do
                      let msg = KeyMap.lookup "message" choiceObj
                      case msg of
                        Just (A.Object msgObj) -> do
                          let content = KeyMap.lookup "content" msgObj
                          case content of
                            Just (A.String txt) -> return $ parseLLMRelations concept txt
                            _ -> do
                              hPutStrLn stderr $ "[llm_discovery] Could not extract content from message for concept '" <> T.unpack concept <> "'"
                              return []
                        Just (A.String txt) -> return $ parseLLMRelations concept txt
                        _ -> do
                          hPutStrLn stderr $ "[llm_discovery] Unexpected choice format for concept '" <> T.unpack concept <> "'"
                          return []
                    _ -> do
                      hPutStrLn stderr $ "[llm_discovery] Unexpected choice type for concept '" <> T.unpack concept <> "'"
                      return []
                _ -> do
                  hPutStrLn stderr $ "[llm_discovery] JSON decode error for concept '" <> T.unpack concept <> "': choices field missing"
                  return []
            _ -> do
              hPutStrLn stderr $ "[llm_discovery] JSON decode error for concept '" <> T.unpack concept <> "': not an object"
              return []
        Nothing -> do
          hPutStrLn stderr $ "[llm_discovery] JSON decode error for concept '" <> T.unpack concept <> "'"
          return []

-- | Build a structured prompt for the LLM to extract relations.
buildDiscoveryPrompt :: Text -> Text
buildDiscoveryPrompt concept = buildDiscoveryPromptWithCandidates concept []

-- | Add a compact local endpoint whitelist without exposing the complete
-- corpus to the external provider.  The caller derives candidates locally;
-- normal admission remains the authoritative enforcement point.
buildDiscoveryPromptWithCandidates :: Text -> [Text] -> Text
buildDiscoveryPromptWithCandidates concept candidates =
  "Ты аналитик семантических связей. Для темы \"" <> concept <> "\" предложи 3-7 "
  <> "кратких, проверяемых отношений с общеупотребимыми понятиями из той же предметной области.\n"
  <> "Верни только JSON без markdown и текста вне JSON: "
  <> "{\"schema_version\":1,\"relations\":[{\"from\":\"...\",\"verb\":\"...\",\"to\":\"...\",\"type\":\"...\"}]}.\n"
  <> "В каждом отношении один конец должен быть \"" <> concept <> "\". Не создавай новые термины, "
  <> "не выдумывай факты, не давай советов и не пиши объяснений.\n"
  <> "Для кириллической темы from, to и verb должны быть кириллическими; type оставь латинским идентификатором схемы.\n"
  <> "Допустимые type: presupposes, limitedBy, requires, claims, "
  <> "verifiedBy, signals, expresses, differsFrom, relatedTo, "
  <> "preserves, orientsToward, prescribes, denotes, structures, "
  <> "determines, transforms, gives, reveals, recognizes, "
  <> "unifies, connects, precedes, dependsOn, includes, "
  <> "evokes, means, says, negates, directedAt, pointsTo, "
  <> "makes, supports, sets, destroys, contrastsWith, notReducibleTo.\n"
  <> candidateConstraint
  <> "Пример: {\"schema_version\":1,\"relations\":[{\"from\":\"ремонт\",\"verb\":\"требует\",\"to\":\"инструмент\",\"type\":\"requires\"}]}.\n"
  where
    candidateConstraint
      | null candidates = ""
      | otherwise = "Второй конец каждого отношения выбери строго из локально известных тем: "
          <> T.intercalate ", " (take 24 candidates) <> ".\n"

-- | Ask only for missing, locally admissible relation slots. The prompt is a
-- bounded hint; local preflight and admission remain authoritative.
buildGapAwareDiscoveryPrompt :: Text -> [Text] -> [Text] -> [Text] -> Text
buildGapAwareDiscoveryPrompt concept candidates basePredicates missingSlots =
  "Ты аналитик семантических связей. Тема: \"" <> concept <> "\".\n"
  <> "Найди только недостающие содержательные связи; не перефразируй и не повторяй существующие predicates.\n"
  <> "Текущий base predicate темы (запрещено повторять или перефразировать): "
  <> if null basePredicates then "нет данных" else T.intercalate " | " (take 1 basePredicates)
  <> ".\n"
  <> "Приоритетные недостающие relation slots: "
  <> if null missingSlots then "causes, presupposes, requires, dependsOn, limitedBy, partOf, contrastsWith"
       else T.intercalate ", " (take 6 missingSlots)
  <> ".\n"
  <> "Предложи максимум 3 связи только из этих slots и только с локально известными endpoints."
  <> " Каждая связь должна добавлять новый object, constraint, cause, condition, consequence, part или contrast.\n"
  <> "Новая связь должна дополнять текущий base predicate, а не заменять его.\n"
  <> "Верни только JSON без markdown: {\"schema_version\":1,\"relations\":[{\"from\":\"...\",\"verb\":\"...\",\"to\":\"...\",\"type\":\"...\"}]}\n"
  <> "Один конец должен быть \"" <> concept <> "\". Не создавай новые термины и не пиши объяснений.\n"
  <> "Если тема написана кириллицей, значения from, to и verb также пиши кириллицей; латинские relation type оставь как в схеме.\n"
  <> "Допустимые type: causes, presupposes, requires, dependsOn, limitedBy, partOf, contrastsWith.\n"
  <> "Локальные endpoints: " <> T.intercalate ", " (take 24 candidates)

-- | One-shape confirmation prompt. A response may confirm the exact shape or
-- explicitly report a conflict; it may not introduce arbitrary graph edges.
buildCorroborationPrompt :: Text -> Text -> Text -> Text -> Text
buildCorroborationPrompt topic edgeFrom relationType edgeTo =
  "Проверь только одну семантическую связь для темы \"" <> topic <> "\": "
  <> edgeFrom <> " | " <> relationType <> " | " <> edgeTo <> ".\n"
  <> "Не предлагай других связей, объектов или тем. Независимо подтверди связь либо сообщи конфликт.\n"
  <> "Сохрани язык endpoints: для кириллической темы from, to и verb должны быть кириллическими.\n"
  <> "Верни только JSON: {\"schema_version\":1,\"relations\":[{\"from\":\""
  <> edgeFrom <> "\",\"verb\":\"...\",\"to\":\"" <> edgeTo
  <> "\",\"type\":\"" <> relationType <> "\"}]} либо {\"schema_version\":1,\"relations\":[]}."

-- | Parse a versioned JSON response, retaining the legacy line format as a
-- compatibility fallback during provider/prompt migration.
parseStructuredLLMRelations :: Text -> Text -> [Relation]
parseStructuredLLMRelations topic responseText =
  if T.length responseText > 65536
    then []
    else case A.decodeStrict' (TE.encodeUtf8 responseText) of
      Just (Object obj) | schemaVersionOne obj ->
        case KeyMap.lookup "relations" obj of
          Just (Array values) -> filter (relationLanguageCompatible topic) (mapMaybe relationFromValue (take 32 (V.toList values)))
          _ -> []
      Just (Object _) -> []
      _ | T.isPrefixOf "{" (T.strip responseText) -> []
        | otherwise -> filter (relationLanguageCompatible topic) (parseLLMRelations topic responseText)
  where
    relationFromValue (Object obj) = do
      from <- textField "from" obj
      verb <- textField "verb" obj
      to <- textField "to" obj
      type_ <- textField "type" obj
      let rationale = optionalTextField "rationale" obj
      case parseLLMRelations topic (T.intercalate " | " [from, verb, to, type_]) of
        relation : _ -> Just (relation { relRationale = rationale })
        [] -> Nothing
    relationFromValue _ = Nothing

    textField key obj =
      case KeyMap.lookup (Key.fromText key) obj of
        Just (String value)
          | not (T.null (T.strip value)) && T.length value <= 256 -> Just (T.strip value)
        _ -> Nothing

    optionalTextField key obj =
      case KeyMap.lookup (Key.fromText key) obj of
        Just (String value) | T.length value <= 2048 -> Just (T.strip value)
        _ -> Nothing

    schemaVersionOne obj =
      case KeyMap.lookup "schema_version" obj of
        Just (Number n) -> n == 1
        _ -> False

relationLanguageCompatible :: Text -> Relation -> Bool
relationLanguageCompatible topic relation
  | not (hasCyrillic topic) = True
  | otherwise = endpointOk from && endpointOk to && maybe True endpointOk (relVerbText relation)
  where
    AtomId from = relFrom relation
    AtomId to = relTo relation
    endpointOk value = hasCyrillic value && not (latinOnly value)
    latinOnly value = T.any (\c -> isAscii c && isAlpha c) value && not (hasCyrillic value)

hasCyrillic :: Text -> Bool
hasCyrillic = T.any (\c -> c >= '\x0400' && c <= '\x04ff')

-- | Detect a provider contract violation before endpoint admission. This is
-- intentionally stricter than endpoint registry admission and is paired with
-- the parser filter above so malformed language can never reach graph gates.
responseViolatesTopicLanguage :: Text -> Text -> Bool
responseViolatesTopicLanguage topic responseBody
  | not (hasCyrillic topic) = False
  | otherwise = any latinOnlyEndpoint (jsonEndpoints responseBody)
  where
    latinOnlyEndpoint value =
      T.any (\c -> isAscii c && isAlpha c) value && not (hasCyrillic value)
    jsonEndpoints body = case A.eitherDecodeStrict (TE.encodeUtf8 body) of
      Right (Object obj) -> case KeyMap.lookup "relations" obj of
        Just (Array values) -> concatMap endpoints (V.toList values)
        _ -> []
      _ -> []
    endpoints (Object obj) = mapMaybe textValue
      [KeyMap.lookup "from" obj, KeyMap.lookup "to" obj, KeyMap.lookup "verb" obj]
    endpoints _ = []
    textValue (Just (String value)) = Just value
    textValue _ = Nothing

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

    makeRelation subject verb object_ typeStr = do
      relType <- parseRelType typeStr
      let fromId = subject
          toId = if T.toLower object_ `elem` map T.toLower allTopics
                   then object_  -- L1 topic: use directly
                   else T.toLower object_  -- concept: lowercase
          ruOriginal = subject <> " " <> verb <> " " <> object_
      pure $ Relation
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
           , relRationale = Nothing
           , relCounter = Nothing
           , relSynthesis = Nothing
           }

    parseRelType :: Text -> Maybe RelationType
    parseRelType t = case T.toLower (T.strip t) of
      "presupposes" -> Just RelPresupposes
      "causes" -> Just RelCauses
      "limitedby" -> Just RelLimitedBy
      "requires" -> Just RelRequires
      "partof" -> Just RelPartOf
      "claims" -> Just RelClaims
      "verifiedby" -> Just RelVerifiedBy
      "signals" -> Just RelSignals
      "expresses" -> Just RelExpresses
      "differsfrom" -> Just RelDiffersFrom
      "relatedto" -> Just RelRelatedTo
      "preserves" -> Just RelPreserves
      "orientstoward" -> Just RelOrientsToward
      "prescribes" -> Just RelPrescribes
      "denotes" -> Just RelDenotes
      "structures" -> Just RelStructures
      "determines" -> Just RelDetermines
      "transforms" -> Just RelTransforms
      "gives" -> Just RelGives
      "reveals" -> Just RelReveals
      "recognizes" -> Just RelRecognizes
      "unifies" -> Just RelUnifies
      "connects" -> Just RelConnects
      "precedes" -> Just RelPrecedes
      "dependson" -> Just RelDependsOn
      "includes" -> Just RelIncludes
      "evokes" -> Just RelEvokes
      "means" -> Just RelMeans
      "says" -> Just RelSays
      "negates" -> Just RelNegates
      "directedat" -> Just RelDirectedAt
      "pointsto" -> Just RelPointsTo
      "makes" -> Just RelMakes
      "supports" -> Just RelSupports
      "sets" -> Just RelSets
      "destroys" -> Just RelDestroys
      "contrastswith" -> Just RelContrastsWith
      "notreducibleto" -> Just RelNotReducibleTo
      _ -> Nothing

-- | LLM API response types (compatible with OpenAI/Cerebras format).
data LLMResponse = LLMResponse
  { lrChoices :: ![LLMChoice]
  } deriving stock (Eq, Show, Generic)

instance FromJSON LLMResponse where
  parseJSON = A.withObject "LLMResponse" $ \v ->
    LLMResponse <$> v A..: "choices"

data LLMChoice = LLMChoice
  { cMessage :: !LLMMessage
  } deriving stock (Eq, Show, Generic)

instance FromJSON LLMChoice where
  parseJSON = A.withObject "LLMChoice" $ \v ->
    LLMChoice <$> v A..: "message"

data LLMMessage = LLMMessage
  { mContent :: !Text
  } deriving stock (Eq, Show, Generic)

instance FromJSON LLMMessage where
  parseJSON = A.withObject "LLMMessage" $ \v ->
    LLMMessage <$> v A..: "content"
