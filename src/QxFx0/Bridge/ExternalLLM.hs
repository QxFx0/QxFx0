{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Bridge.ExternalLLM
Description : WP2 — External LLM transport (Mock + Mistral).

Two transports:

1. 'MockTransport' — deterministic, pure, always succeeds or fails based
   on a static table.  Used for unit tests and offline replay.
2. 'MistralTransport' — real HTTP to the Mistral API, guarded by env
   vars and feature-flagged.  Never selected when 'QXFX0_LLM_TRANSPORT'
   is not set to @"mistral"@.

Fail-closed: any network/auth/rate-limit error returns a typed
'ExternalQueryError' and does NOT throw.  The learning loop decides
whether to retry, fallback, or reject.
-}
module QxFx0.Bridge.ExternalLLM
  ( LLMTransport(..)
  , MockTable
  , buildTransportFromEnv
  , buildTransportFromConfig
  , queryExternalTool
  , queryExternalToolWithConfig
  , defaultExternalQueryConfig
  ) where

import Control.Applicative ((<|>))
import Control.Exception (try)
import Control.Monad (when)
import Data.Aeson (FromJSON, ToJSON, Value(..), decodeStrict, object, (.=))
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as LBS
import Data.Char (isSpace)
import qualified Data.List as L
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import GHC.Generics (Generic)
import Network.HTTP.Client
  ( Manager
  , Request
  , RequestBody(..)
  , Response
  , httpLbs
  , method
  , parseRequest
  , requestBody
  , requestHeaders
  , responseBody
  , responseStatus
  , throwErrorStatusCodes
  )
import Network.HTTP.Client.TLS (newTlsManager)
import Network.HTTP.Types.Status (statusCode, statusMessage)
import System.Environment (lookupEnv)

import QxFx0.Learning.Need (LearningNeed(..))
import QxFx0.Learning.Tool (ExternalTool(..), etName)
import QxFx0.Types.ExternalQuery
  ( ExternalQueryError(..)
  , ExternalQueryResponse(..)
  , ExternalQueryConfig(..)
  , TransportFallbackReason(..)
  , renderFallbackReason
  )
import QxFx0.ExceptionPolicy (catchIO)

-- | Transport abstraction: carries a 'Manager' for real HTTP and a
-- static map for mock.
data LLMTransport
  = MockTransport !MockTable !(Maybe ExternalQueryConfig)
    -- ^ Mock table plus optional config that led to fallback.
  | MistralTransport !Manager !MistralConfig
  | FireworksTransport !Manager !FireworksConfig

instance Show LLMTransport where
  show (MockTransport _ mcfg) =
    "MockTransport(" ++ maybe "no_config" show mcfg ++ ")"
  show (MistralTransport _ cfg) =
    "MistralTransport(apiKey=<REDACTED>,model=" ++ show (mcModel cfg) ++ ")"
  show (FireworksTransport _ cfg) =
    "FireworksTransport(apiKey=<REDACTED>,model=" ++ show (fcModel cfg) ++ ")"

-- | Static lookup table for mock responses.
-- Key: (toolName, needTag, queryPrefix) -> response body.
type MockTable = [(Text, Text, Text, Either ExternalQueryError Text)]

-- | Mistral API configuration from env vars.
data MistralConfig = MistralConfig
  { mcApiKey    :: !Text
  , mcModel     :: !Text
  , mcEndpoint  :: !Text
  , mcTimeoutMs :: !Int
  }
  deriving stock (Eq, Show, Generic)
    deriving anyclass (FromJSON, ToJSON)

-- | Fireworks API configuration from env vars.
-- Fireworks uses an OpenAI-compatible schema, so the HTTP body and
-- response shape are identical to Mistral.  Only the endpoint and
-- env-var prefix differ.
data FireworksConfig = FireworksConfig
  { fcApiKey    :: !Text
  , fcModel     :: !Text
  , fcEndpoint  :: !Text
  , fcTimeoutMs :: !Int
  }
  deriving stock (Eq, Show, Generic)
    deriving anyclass (FromJSON, ToJSON)

-- | Default safe configuration when no env vars are present.
defaultExternalQueryConfig :: ExternalQueryConfig
defaultExternalQueryConfig = ExternalQueryConfig
  { eqcTransportMode  = "mock"
  , eqcApiKey         = Nothing
  , eqcModel          = "mistral-small-latest"
  , eqcEndpoint       = "https://api.mistral.ai/v1/chat/completions"
  , eqcTimeoutMs      = 30000
  , eqcFallbackReason = Just TfrExplicitMock
  }

-- | Build transport from environment.
--
-- Env vars:
--   QXFX0_LLM_TRANSPORT=mock|mistral|fireworks  (default: mock)
--   QXFX0_MISTRAL_API_KEY                       (required for mistral)
--   QXFX0_MISTRAL_MODEL                         (default: "mistral-small-latest")
--   QXFX0_MISTRAL_ENDPOINT                      (default: "https://api.mistral.ai/v1/chat/completions")
--   QXFX0_FIREWORKS_API_KEY                     (required for fireworks)
--   QXFX0_FIREWORKS_MODEL                       (default: "accounts/fireworks/models/glm-5p1")
--   QXFX0_FIREWORKS_ENDPOINT                    (default: "https://api.fireworks.ai/inference/v1/chat/completions")
--
-- Fail-closed: any missing required config falls back to mock with an
-- explicit 'TransportFallbackReason' in the returned 'ExternalQueryConfig'.
buildTransportFromEnv :: IO LLMTransport
buildTransportFromEnv = do
  mTransport <- lookupEnv "QXFX0_LLM_TRANSPORT"
  let mode = fromMaybe "mock" mTransport
  cfg0 <- case mode of
    "mistral" -> do
      mKey <- lookupEnv "QXFX0_MISTRAL_API_KEY"
      case mKey of
        Nothing -> pure $ defaultExternalQueryConfig
          { eqcTransportMode = "mistral"
          , eqcFallbackReason = Just TfrKeyMissing
          }
        Just key -> do
          model    <- fmap (T.pack . fromMaybe "mistral-small-latest") (lookupEnv "QXFX0_MISTRAL_MODEL")
          endpoint <- fmap (T.pack . fromMaybe "https://api.mistral.ai/v1/chat/completions") (lookupEnv "QXFX0_MISTRAL_ENDPOINT")
          let isHttps = T.isPrefixOf "https://" endpoint
          if not isHttps
            then pure $ defaultExternalQueryConfig
              { eqcTransportMode = "mistral"
              , eqcApiKey = Just (T.pack key)
              , eqcModel = model
              , eqcEndpoint = endpoint
              , eqcFallbackReason = Just TfrUnsafeEndpoint
              }
            else pure $ ExternalQueryConfig
              { eqcTransportMode = "mistral"
              , eqcApiKey = Just (T.pack key)
              , eqcModel = model
              , eqcEndpoint = endpoint
              , eqcTimeoutMs = 30000
              , eqcFallbackReason = Nothing
              }
    "fireworks" -> do
      mKey <- lookupEnv "QXFX0_FIREWORKS_API_KEY"
      case mKey of
        Nothing -> pure $ defaultExternalQueryConfig
          { eqcTransportMode = "fireworks"
          , eqcFallbackReason = Just TfrKeyMissing
          }
        Just key -> do
          model    <- fmap (T.pack . fromMaybe "accounts/fireworks/models/glm-5p1") (lookupEnv "QXFX0_FIREWORKS_MODEL")
          endpoint <- fmap (T.pack . fromMaybe "https://api.fireworks.ai/inference/v1/chat/completions") (lookupEnv "QXFX0_FIREWORKS_ENDPOINT")
          let isHttps = T.isPrefixOf "https://" endpoint
          if not isHttps
            then pure $ defaultExternalQueryConfig
              { eqcTransportMode = "fireworks"
              , eqcApiKey = Just (T.pack key)
              , eqcModel = model
              , eqcEndpoint = endpoint
              , eqcFallbackReason = Just TfrUnsafeEndpoint
              }
            else pure $ ExternalQueryConfig
              { eqcTransportMode = "fireworks"
              , eqcApiKey = Just (T.pack key)
              , eqcModel = model
              , eqcEndpoint = endpoint
              , eqcTimeoutMs = 30000
              , eqcFallbackReason = Nothing
              }
    _ -> pure $ defaultExternalQueryConfig
           { eqcTransportMode = T.pack mode
           , eqcFallbackReason = if mode == "mock" then Just TfrExplicitMock else Just TfrEnvNotSet
           }
  buildTransportFromConfig cfg0

-- | Build transport from an explicit configuration record.
-- Useful for tests and for deterministic fallback paths.
buildTransportFromConfig :: ExternalQueryConfig -> IO LLMTransport
buildTransportFromConfig cfg =
  case eqcFallbackReason cfg of
    Just reason -> pure (MockTransport defaultMockTable (Just cfg { eqcApiKey = Nothing, eqcFallbackReason = Just reason }))
    Nothing -> do
      mgr <- newTlsManager
      case eqcApiKey cfg of
        Nothing -> pure (MockTransport defaultMockTable (Just cfg { eqcFallbackReason = Just TfrKeyMissing }))
        Just key ->
          if eqcTransportMode cfg == "fireworks"
            then pure $ FireworksTransport mgr FireworksConfig
              { fcApiKey = key
              , fcModel = eqcModel cfg
              , fcEndpoint = eqcEndpoint cfg
              , fcTimeoutMs = eqcTimeoutMs cfg
              }
            else pure $ MistralTransport mgr MistralConfig
              { mcApiKey = key
              , mcModel = eqcModel cfg
              , mcEndpoint = eqcEndpoint cfg
              , mcTimeoutMs = eqcTimeoutMs cfg
              }

-- | Default mock table with a handful of deterministic responses.
-- Extend this in tests by passing a custom table to 'MockTransport'.
defaultMockTable :: MockTable
defaultMockTable =
  [ ( "llm-augment"
    , "NeedLexiconExtension"
    , "что"
    , Right mockDefinitionPositive
    )
  , ( "llm-augment"
    , "NeedLexiconExtension"
    , "тема"
    , Right mockDefinitionPositive
    )
  , ( "llm-augment"
    , "NeedLexiconExtension"
    , "как"
    , Right mockDeclensionPositive
    )
  , ( "llm-augment"
    , "NeedLexiconExtension"
    , "Explore"
    , Right mockDefinitionPositive
    )
  , ( "llm-augment"
    , "NeedLexiconExtension"
    , "fail"
    , Left (EqeServerError "mock_injected_failure")
    )
  ]
  where
    mockDefinitionPositive =
      "{\"proposition\":\"свобода — способность действовать по своей воле\",\"source\":\"llm\",\"validated\":true,\"conatusDelta\":0.3,\"predictiveDelta\":0.2,\"word\":\"свобода\",\"definition\":\"способность действовать по своей воле\",\"morphology\":{\"gender\":\"feminine\",\"declension\":\"first\"}}"
    mockDeclensionPositive =
      "{\"proposition\":\"склонение слова 'книга'\",\"source\":\"llm\",\"validated\":true,\"conatusDelta\":0.2,\"predictiveDelta\":0.1,\"word\":\"книга\",\"definition\":\"печатное издание\",\"morphology\":{\"gender\":\"feminine\",\"declension\":\"first\",\"cases\":{\"nom\":\"книга\",\"gen\":\"книги\",\"dat\":\"книге\",\"acc\":\"книгу\",\"ins\":\"книгой\",\"pre\":\"книге\"}}}"

-- | Execute a query against the chosen transport.
--
-- Returns 'Either ExternalQueryError ExternalQueryResponse' so the
-- caller (learning loop) can decide what to do next.
queryExternalTool
  :: LLMTransport
  -> ExternalTool
  -> LearningNeed
  -> Text        -- ^ user query / prompt
  -> IO (Either ExternalQueryError ExternalQueryResponse)
queryExternalTool transport tool need query =
  case transport of
    MockTransport table _     -> mockQuery table tool need query
    MistralTransport mgr cfg  -> mistralQuery mgr cfg tool need query
    FireworksTransport mgr cfg -> fireworksQuery mgr cfg tool need query

-- | Execute a query with explicit config (for tests and telemetry).
queryExternalToolWithConfig
  :: ExternalQueryConfig
  -> ExternalTool
  -> LearningNeed
  -> Text
  -> IO (Either ExternalQueryError ExternalQueryResponse)
queryExternalToolWithConfig cfg tool need query = do
  transport <- buildTransportFromConfig cfg
  queryExternalTool transport tool need query

-- | Deterministic mock query.
mockQuery :: MockTable -> ExternalTool -> LearningNeed -> Text -> IO (Either ExternalQueryError ExternalQueryResponse)
mockQuery table tool need query = do
  let needTag = renderNeedTag need
      qPrefix = T.takeWhile (not . isSpace) (T.strip query)
      match = mockTableLookup (etName tool, needTag, qPrefix) table
            <|> mockTableLookup (etName tool, needTag, "") table
            <|> mockTableLookup (etName tool, "", qPrefix) table
  pure $ case match of
    Just (Right body) ->
      Right ExternalQueryResponse
        { eqrRawBody    = body
        , eqrStructured = body
        , eqrToolName   = etName tool
        , eqrLatencyMs  = 0
        }
    Just (Left err) ->
      Left err
    Nothing ->
      Left (EqeNetworkUnavailable "mock_no_matching_response")

renderNeedTag :: LearningNeed -> Text
renderNeedTag NeedSalienceCalibration = "NeedSalienceCalibration"
renderNeedTag NeedKeywordEnrichment   = "NeedKeywordEnrichment"
renderNeedTag NeedLexiconExtension      = "NeedLexiconExtension"
renderNeedTag NeedNone                  = "NeedNone"

-- | Real Mistral HTTP query.
-- Fail-closed: any exception or non-2xx status is mapped to a typed
-- 'ExternalQueryError'.  Never returns a silent accept.
mistralQuery :: Manager -> MistralConfig -> ExternalTool -> LearningNeed -> Text -> IO (Either ExternalQueryError ExternalQueryResponse)
mistralQuery mgr cfg tool _need query =
  catchIO (do
    req0 <- parseRequest (T.unpack (mcEndpoint cfg))
    let req = req0
          { method = "POST"
          , requestHeaders =
              [ ("Authorization", TE.encodeUtf8 (T.concat ["Bearer ", mcApiKey cfg]))
              , ("Content-Type", "application/json")
              ]
          , requestBody = RequestBodyLBS $ LBS.fromStrict $ TE.encodeUtf8 $
              T.concat ["{\"model\":\"", mcModel cfg, "\",\"messages\":[{\"role\":\"user\",\"content\":\"", escapeJson query, "\"}]}"]
          }
    resp <- httpLbs req mgr
    let code = statusCode (responseStatus resp)
        body = TE.decodeUtf8 (LBS.toStrict (responseBody resp))
        statusMsg = T.pack (show (statusMessage (responseStatus resp)))
    if code >= 200 && code < 300
      then if T.null (T.strip body)
             then pure $ Left EqeEmptyResponse
             else pure $ Right ExternalQueryResponse
                    { eqrRawBody    = body
                    , eqrStructured = extractStructured body
                    , eqrToolName   = etName tool
                    , eqrLatencyMs  = 0 -- TODO: measure via diffUTCTime
                    }
      else case code of
        401 -> pure $ Left (EqeAuthFailure (T.concat ["401 ", statusMsg, ": ", body]))
        403 -> pure $ Left (EqeAuthFailure (T.concat ["403 ", statusMsg, ": ", body]))
        429 -> pure $ Left (EqeRateLimited (T.concat ["429 ", statusMsg, ": ", body]))
        _ | code >= 500 && code < 600 -> pure $ Left (EqeServerError (T.concat ["5xx ", T.pack (show code), " ", statusMsg, ": ", body]))
        _ | code >= 400 && code < 500 -> pure $ Left (EqeInvalidResponse (T.concat ["4xx ", T.pack (show code), " ", statusMsg, ": ", body]))
        _ -> pure $ Left (EqeInvalidResponse (T.concat ["unexpected ", T.pack (show code), ": ", body]))
  ) (\e -> pure $ Left (EqeNetworkUnavailable (T.pack (show e))))

-- | Real Fireworks HTTP query.
-- Fireworks uses the same OpenAI-compatible chat-completion schema as
-- Mistral, so the request body and response unwrapping are identical.
-- Only the endpoint and auth header differ.
fireworksQuery :: Manager -> FireworksConfig -> ExternalTool -> LearningNeed -> Text -> IO (Either ExternalQueryError ExternalQueryResponse)
fireworksQuery mgr cfg tool _need query =
  catchIO (do
    req0 <- parseRequest (T.unpack (fcEndpoint cfg))
    let req = req0
          { method = "POST"
          , requestHeaders =
              [ ("Authorization", TE.encodeUtf8 (T.concat ["Bearer ", fcApiKey cfg]))
              , ("Content-Type", "application/json")
              ]
          , requestBody = RequestBodyLBS $ LBS.fromStrict $ TE.encodeUtf8 $
              T.concat ["{\"model\":\"", fcModel cfg, "\",\"messages\":[{\"role\":\"user\",\"content\":\"", escapeJson query, "\"}]}"]
          }
    resp <- httpLbs req mgr
    let code = statusCode (responseStatus resp)
        body = TE.decodeUtf8 (LBS.toStrict (responseBody resp))
        statusMsg = T.pack (show (statusMessage (responseStatus resp)))
    if code >= 200 && code < 300
      then if T.null (T.strip body)
             then pure $ Left EqeEmptyResponse
             else pure $ Right ExternalQueryResponse
                    { eqrRawBody    = body
                    , eqrStructured = extractStructured body
                    , eqrToolName   = etName tool
                    , eqrLatencyMs  = 0
                    }
      else case code of
        401 -> pure $ Left (EqeAuthFailure (T.concat ["401 ", statusMsg, ": ", body]))
        403 -> pure $ Left (EqeAuthFailure (T.concat ["403 ", statusMsg, ": ", body]))
        429 -> pure $ Left (EqeRateLimited (T.concat ["429 ", statusMsg, ": ", body]))
        _ | code >= 500 && code < 600 -> pure $ Left (EqeServerError (T.concat ["5xx ", T.pack (show code), " ", statusMsg, ": ", body]))
        _ | code >= 400 && code < 500 -> pure $ Left (EqeInvalidResponse (T.concat ["4xx ", T.pack (show code), " ", statusMsg, ": ", body]))
        _ -> pure $ Left (EqeInvalidResponse (T.concat ["unexpected ", T.pack (show code), ": ", body]))
  ) (\e -> pure $ Left (EqeNetworkUnavailable (T.pack (show e))))

-- | Naïve JSON escape for the prompt body (sufficient for our
-- constrained prompts).
escapeJson :: Text -> Text
escapeJson = T.concatMap escapeChar
  where
    escapeChar '"' = "\\\""
    escapeChar '\\' = "\\\\"
    escapeChar '\n' = "\\n"
    escapeChar '\r' = "\\r"
    escapeChar c    = T.singleton c

-- | Extract structured payload from a Mistral chat-completion response.
-- If the response contains JSON in a @content@ field, unwrap it;
-- otherwise return the whole body for fallback parsing.
extractStructured :: Text -> Text
extractStructured body =
  fromMaybe body $ do
    -- Very lightweight unwrap: look for "content":"..."
    let prefix = "\"content\":\""
    case T.breakOn prefix body of
      (_, rest) | T.null rest -> Nothing
      (_, rest') -> do
        let contentStart = T.drop (T.length prefix) rest'
        case T.breakOn "\"" contentStart of
          (content, _) | T.null content -> Nothing
          (content, _) -> Just content

-- Helpers

mockTableLookup :: (Text, Text, Text) -> MockTable -> Maybe (Either ExternalQueryError Text)
mockTableLookup _ [] = Nothing
mockTableLookup key ((a,b,c,d):rest)
  | key == (a,b,c)  = Just d
  | otherwise = mockTableLookup key rest
