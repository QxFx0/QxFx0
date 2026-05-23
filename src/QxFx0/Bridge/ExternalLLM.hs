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
  , buildTransportFromEnvWithManager
  , buildTransportFromConfig
  , buildTransportFromConfigWithManager
  , queryExternalTool
  , queryExternalToolWithConfig
  , defaultExternalQueryConfig
  , llmEndpointAllowlist
  , llmUntrustedHostOverrideWarningTag
  , validateEndpointUrl
  , validateEndpointUrlWithContext
  , extractStructured
  , decodeLlmBodyLimited
  , redactUpstreamError
  , classifyHttpException
  , classifyBodyReadFailure
  ) where

import Control.Applicative ((<|>))
import Control.Exception (try)
import Data.Aeson (FromJSON(..), ToJSON, decodeStrict, encode, object, (.=))
import Data.Aeson.Types (withObject, (.:), (.:?))
import qualified Data.ByteString as BS
import Data.Char (isSpace)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Text.Encoding.Error (lenientDecode)
import Data.Time.Clock (UTCTime, diffUTCTime, getCurrentTime)
import GHC.Generics (Generic)
import Network.HTTP.Client
  ( BodyReader
  , HttpException(..)
  , HttpExceptionContent(..)
  , Manager
  , Request
  , RequestBody(..)
  , brRead
  , checkResponse
  , method
  , parseRequest
  , requestBody
  , requestHeaders
  , responseTimeout
  , responseTimeoutMicro
  , responseBody
  , responseStatus
  , withResponse
  )
import Network.HTTP.Client.TLS (newTlsManager)
import Network.HTTP.Types.Status (Status, statusCode)
import Network.URI (URI(..), URIAuth(..), parseURI)
import System.Environment (lookupEnv)
import System.IO (hPutStrLn, stderr)

import QxFx0.Learning.Need (LearningNeed(..))
import QxFx0.Learning.Tool (ExternalTool(..), etName)
import QxFx0.Types.ExternalQuery
  ( ExternalQueryError(..)
  , ExternalQueryResponse(..)
  , ExternalQueryConfig(..)
  , TransportFallbackReason(..)
  )

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

-- | Official LLM API endpoint allowlist.
-- Any endpoint not on this list is rejected unless the operator sets
-- @QXFX0_LLM_ALLOW_UNTRUSTED_HOST=1@ and either enters an explicit
-- dev/test mode or supplies the second confirmation flag documented in
-- 'validateEndpointUrlWithContext'.
llmEndpointAllowlist :: [Text]
llmEndpointAllowlist =
  [ "api.mistral.ai"
  , "api.fireworks.ai"
  ]

llmUntrustedHostOverrideWarningTag :: Text
llmUntrustedHostOverrideWarningTag = "llm_untrusted_host_override_allowed"

llmMaxResponseBytes :: Int
llmMaxResponseBytes = 65536

llmRawBodyTelemetryChars :: Int
llmRawBodyTelemetryChars = 4096

-- | Validate an endpoint URL using the strict default policy.
--
-- Rules (fail-closed):
--   1. Scheme must be @https://@.
--   2. Host must be in 'llmEndpointAllowlist'.
--   3. A single untrusted-host override is not sufficient by itself.
--      Use 'validateEndpointUrlWithContext' with dev/test or double opt-in
--      context when this is intentional.
--   3. Empty or malformed URI is rejected.
--
-- Returns 'Right ()' when allowed, 'Left reason' when blocked.
validateEndpointUrl :: Text -> Maybe Text -> Either TransportFallbackReason ()
validateEndpointUrl endpoint mAllowOverride =
  () <$ validateEndpointUrlWithContext endpoint mAllowOverride Nothing Nothing

-- | Validate an endpoint URL with explicit override context.
--
-- Parameters after the endpoint are:
--
-- * @QXFX0_LLM_ALLOW_UNTRUSTED_HOST@ value.
-- * dev/test mode marker, for example @QXFX0_TEST_MODE=1@ or
--   @QXFX0_LLM_DEV_MODE=1@.
-- * double-confirmation marker, currently
--   @QXFX0_LLM_ALLOW_UNTRUSTED_HOST_CONFIRM=1@.
--
-- A successful untrusted-host override returns the warning tag that must be
-- emitted to logs/trace before a bearer token is sent to that host.
validateEndpointUrlWithContext
  :: Text
  -> Maybe Text
  -> Maybe Text
  -> Maybe Text
  -> Either TransportFallbackReason (Maybe Text)
validateEndpointUrlWithContext endpoint mAllowOverride mDevOrTestMode mDoubleConfirm =
  let stripped = T.strip endpoint
  in if T.null stripped
       then Left TfrUnsafeEndpoint
       else case parseEndpointHost stripped of
              Nothing -> Left TfrUnsafeEndpoint
              Just host ->
                if host `elem` llmEndpointAllowlist
                  then Right Nothing
                  else if mAllowOverride == Just "1"
                         then if isTruthy mDevOrTestMode || isTruthy mDoubleConfirm
                                then Right (Just llmUntrustedHostOverrideWarningTag)
                                else Left TfrUntrustedOverrideRejected
                         else Left TfrBlockedHost

parseEndpointHost :: Text -> Maybe Text
parseEndpointHost endpoint = do
  uri <- parseURI (T.unpack endpoint)
  auth <- uriAuthority uri
  let scheme = T.toLower (T.pack (uriScheme uri))
      rawHost = uriRegName auth
  if scheme == "https:" && null (uriUserInfo auth) && not (null rawHost)
    then Just (T.toLower (T.pack rawHost))
    else Nothing

endpointHost :: Text -> Text
endpointHost rawEndpoint =
  fromMaybe "invalid_endpoint" (parseEndpointHost (T.strip rawEndpoint))

isTruthy :: Maybe Text -> Bool
isTruthy raw =
  case T.toLower . T.strip <$> raw of
    Just "1" -> True
    Just "true" -> True
    Just "yes" -> True
    Just "on" -> True
    Just "dev" -> True
    Just "test" -> True
    _ -> False

-- | Default safe configuration when no env vars are present.
defaultExternalQueryConfig :: ExternalQueryConfig
defaultExternalQueryConfig = ExternalQueryConfig
  { eqcTransportMode  = "disabled"
  , eqcApiKey         = Nothing
  , eqcModel          = "mistral-small-latest"
  , eqcEndpoint       = "https://api.mistral.ai/v1/chat/completions"
  , eqcTimeoutMs      = 30000
  , eqcFallbackReason = Just TfrEnvNotSet
  }

-- | Build transport from environment.
--
-- Env vars:
--   QXFX0_LLM_TRANSPORT=mock|mistral|fireworks  (default: disabled/non-authoritative)
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
  cfg <- resolveTransportConfigFromEnv
  buildTransportFromValidatedConfig cfg

buildTransportFromEnvWithManager :: Manager -> IO LLMTransport
buildTransportFromEnvWithManager mgr = do
  cfg <- resolveTransportConfigFromEnv
  buildTransportFromValidatedConfigWithManager mgr cfg

resolveTransportConfigFromEnv :: IO ExternalQueryConfig
resolveTransportConfigFromEnv = do
  mTransport <- lookupEnv "QXFX0_LLM_TRANSPORT"
  let mode = fromMaybe "disabled" mTransport
  case mode of
    "mock" -> pure $ defaultExternalQueryConfig
      { eqcTransportMode = "mock"
      , eqcFallbackReason = Just TfrExplicitMock
      }
    "mistral" -> do
      mKey <- lookupEnv "QXFX0_MISTRAL_API_KEY"
      overrideContext <- readOverrideContext
      case fmap (T.strip . T.pack) mKey of
        Nothing -> pure $ defaultExternalQueryConfig
          { eqcTransportMode = "mistral"
          , eqcFallbackReason = Just TfrKeyMissing
          }
        Just key | T.null key -> pure $ defaultExternalQueryConfig
          { eqcTransportMode = "mistral"
          , eqcFallbackReason = Just TfrKeyMissing
          }
        Just key -> do
          model    <- fmap (T.pack . fromMaybe "mistral-small-latest") (lookupEnv "QXFX0_MISTRAL_MODEL")
          endpoint <- fmap (T.pack . fromMaybe "https://api.mistral.ai/v1/chat/completions") (lookupEnv "QXFX0_MISTRAL_ENDPOINT")
          case validateEndpointWithOverrideContext endpoint overrideContext of
            Left reason -> pure $ defaultExternalQueryConfig
              { eqcTransportMode = "mistral"
              , eqcApiKey = Nothing
              , eqcModel = model
              , eqcEndpoint = endpoint
              , eqcFallbackReason = Just reason
              }
            Right mWarningTag -> do
              emitOverrideWarning endpoint mWarningTag
              pure $ ExternalQueryConfig
                { eqcTransportMode = "mistral"
                , eqcApiKey = Just key
                , eqcModel = model
                , eqcEndpoint = endpoint
                , eqcTimeoutMs = 30000
                , eqcFallbackReason = Nothing
                }
    "fireworks" -> do
      mKey <- lookupEnv "QXFX0_FIREWORKS_API_KEY"
      overrideContext <- readOverrideContext
      case fmap (T.strip . T.pack) mKey of
        Nothing -> pure $ defaultExternalQueryConfig
          { eqcTransportMode = "fireworks"
          , eqcFallbackReason = Just TfrKeyMissing
          }
        Just key | T.null key -> pure $ defaultExternalQueryConfig
          { eqcTransportMode = "fireworks"
          , eqcFallbackReason = Just TfrKeyMissing
          }
        Just key -> do
          model    <- fmap (T.pack . fromMaybe "accounts/fireworks/models/glm-5p1") (lookupEnv "QXFX0_FIREWORKS_MODEL")
          endpoint <- fmap (T.pack . fromMaybe "https://api.fireworks.ai/inference/v1/chat/completions") (lookupEnv "QXFX0_FIREWORKS_ENDPOINT")
          case validateEndpointWithOverrideContext endpoint overrideContext of
            Left reason -> pure $ defaultExternalQueryConfig
              { eqcTransportMode = "fireworks"
              , eqcApiKey = Nothing
              , eqcModel = model
              , eqcEndpoint = endpoint
              , eqcFallbackReason = Just reason
              }
            Right mWarningTag -> do
              emitOverrideWarning endpoint mWarningTag
              pure $ ExternalQueryConfig
                { eqcTransportMode = "fireworks"
                , eqcApiKey = Just key
                , eqcModel = model
                , eqcEndpoint = endpoint
                , eqcTimeoutMs = 30000
                , eqcFallbackReason = Nothing
                }
    _ -> pure $ defaultExternalQueryConfig
           { eqcTransportMode = T.pack mode
           , eqcFallbackReason = Just TfrEnvNotSet
           }

data OverrideContext = OverrideContext
  { ocAllowUntrusted :: !(Maybe Text)
  , ocDevOrTestMode :: !(Maybe Text)
  , ocDoubleConfirm :: !(Maybe Text)
  }

readOverrideContext :: IO OverrideContext
readOverrideContext = do
  mAllowUntrusted <- fmap (fmap T.pack) (lookupEnv "QXFX0_LLM_ALLOW_UNTRUSTED_HOST")
  mTestMode <- fmap (fmap T.pack) (lookupEnv "QXFX0_TEST_MODE")
  mDevMode <- fmap (fmap T.pack) (lookupEnv "QXFX0_LLM_DEV_MODE")
  mDoubleConfirm <- fmap (fmap T.pack) (lookupEnv "QXFX0_LLM_ALLOW_UNTRUSTED_HOST_CONFIRM")
  let mDevOrTest = firstTruthy [mTestMode, mDevMode]
  pure OverrideContext
    { ocAllowUntrusted = mAllowUntrusted
    , ocDevOrTestMode = mDevOrTest
    , ocDoubleConfirm = mDoubleConfirm
    }

validateEndpointWithOverrideContext :: Text -> OverrideContext -> Either TransportFallbackReason (Maybe Text)
validateEndpointWithOverrideContext endpoint ctx =
  validateEndpointUrlWithContext endpoint (ocAllowUntrusted ctx) (ocDevOrTestMode ctx) (ocDoubleConfirm ctx)

firstTruthy :: [Maybe Text] -> Maybe Text
firstTruthy [] = Nothing
firstTruthy (x:xs)
  | isTruthy x = x
  | otherwise = firstTruthy xs

emitOverrideWarning :: Text -> Maybe Text -> IO ()
emitOverrideWarning _ Nothing = pure ()
emitOverrideWarning endpoint (Just tag) =
  hPutStrLn stderr $ T.unpack $ T.concat
    [ "[security_warning] tag="
    , tag
    , " endpoint_host="
    , endpointHost (T.strip endpoint)
    ]

buildTransportFromValidatedConfig :: ExternalQueryConfig -> IO LLMTransport
buildTransportFromValidatedConfig cfg =
  case eqcFallbackReason cfg of
    Just reason -> pure (MockTransport defaultMockTable (Just cfg { eqcApiKey = Nothing, eqcFallbackReason = Just reason }))
    Nothing ->
      case eqcApiKey cfg of
        Nothing -> pure (MockTransport defaultMockTable (Just cfg { eqcFallbackReason = Just TfrKeyMissing }))
        Just _ -> do
          mgr <- newTlsManager
          buildTransportFromValidatedConfigWithManager mgr cfg

buildTransportFromValidatedConfigWithManager :: Manager -> ExternalQueryConfig -> IO LLMTransport
buildTransportFromValidatedConfigWithManager mgr cfg =
  case eqcFallbackReason cfg of
    Just reason -> pure (MockTransport defaultMockTable (Just cfg { eqcApiKey = Nothing, eqcFallbackReason = Just reason }))
    Nothing ->
      case eqcApiKey cfg of
        Nothing -> pure (MockTransport defaultMockTable (Just cfg { eqcFallbackReason = Just TfrKeyMissing }))
        Just key -> pure (realTransportForKey mgr cfg key)

realTransportForKey :: Manager -> ExternalQueryConfig -> Text -> LLMTransport
realTransportForKey mgr cfg key =
  if eqcTransportMode cfg == "fireworks"
    then FireworksTransport mgr FireworksConfig
      { fcApiKey = key
      , fcModel = eqcModel cfg
      , fcEndpoint = eqcEndpoint cfg
      , fcTimeoutMs = eqcTimeoutMs cfg
      }
    else MistralTransport mgr MistralConfig
      { mcApiKey = key
      , mcModel = eqcModel cfg
      , mcEndpoint = eqcEndpoint cfg
      , mcTimeoutMs = eqcTimeoutMs cfg
      }

-- | Build transport from an explicit configuration record.
-- Useful for tests and for deterministic fallback paths.
buildTransportFromConfig :: ExternalQueryConfig -> IO LLMTransport
buildTransportFromConfig cfg =
  case eqcFallbackReason cfg of
    Just reason -> pure (MockTransport defaultMockTable (Just cfg { eqcApiKey = Nothing, eqcFallbackReason = Just reason }))
    Nothing ->
      case eqcApiKey cfg of
        Nothing -> pure (MockTransport defaultMockTable (Just cfg { eqcFallbackReason = Just TfrKeyMissing }))
        Just _ ->
          case validateEndpointUrl (eqcEndpoint cfg) Nothing of
            Left reason ->
              pure (MockTransport defaultMockTable (Just cfg { eqcApiKey = Nothing, eqcFallbackReason = Just reason }))
            Right () -> do
              mgr <- newTlsManager
              buildTransportFromValidatedConfigWithManager mgr cfg

buildTransportFromConfigWithManager :: Manager -> ExternalQueryConfig -> IO LLMTransport
buildTransportFromConfigWithManager mgr cfg =
  case eqcFallbackReason cfg of
    Just reason -> pure (MockTransport defaultMockTable (Just cfg { eqcApiKey = Nothing, eqcFallbackReason = Just reason }))
    Nothing ->
      case eqcApiKey cfg of
        Nothing -> pure (MockTransport defaultMockTable (Just cfg { eqcFallbackReason = Just TfrKeyMissing }))
        Just key ->
          case validateEndpointUrl (eqcEndpoint cfg) Nothing of
            Left reason ->
              pure (MockTransport defaultMockTable (Just cfg { eqcApiKey = Nothing, eqcFallbackReason = Just reason }))
            Right () -> pure (realTransportForKey mgr cfg key)

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
    MockTransport table mCfg  ->
      case mCfg >>= eqcFallbackReason of
        Just reason | reason /= TfrExplicitMock -> pure (Left (EqeFallback reason))
        _ -> mockQuery table tool need query
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
  chatCompletionQuery mgr "mistral" (mcEndpoint cfg) (mcModel cfg) (mcApiKey cfg) (mcTimeoutMs cfg) tool query

-- | Real Fireworks HTTP query.
-- Fireworks uses the same OpenAI-compatible chat-completion schema as
-- Mistral, so the request body and response unwrapping are identical.
-- Only the endpoint and auth header differ.
fireworksQuery :: Manager -> FireworksConfig -> ExternalTool -> LearningNeed -> Text -> IO (Either ExternalQueryError ExternalQueryResponse)
fireworksQuery mgr cfg tool _need query =
  chatCompletionQuery mgr "fireworks" (fcEndpoint cfg) (fcModel cfg) (fcApiKey cfg) (fcTimeoutMs cfg) tool query

chatCompletionQuery
  :: Manager
  -> Text
  -> Text
  -> Text
  -> Text
  -> Int
  -> ExternalTool
  -> Text
  -> IO (Either ExternalQueryError ExternalQueryResponse)
chatCompletionQuery mgr _provider endpoint model apiKey timeoutMs tool query = do
  requestResult <- buildChatRequest endpoint model apiKey timeoutMs query
  case requestResult of
    Left err -> pure (Left err)
    Right req -> do
      start <- getCurrentTime
      httpResult <- runChatHttp mgr req
      end <- getCurrentTime
      let latencyMs = elapsedMs start end
      pure (handleChatHttpResult tool latencyMs httpResult)

buildChatRequest :: Text -> Text -> Text -> Int -> Text -> IO (Either ExternalQueryError Request)
buildChatRequest endpoint model apiKey timeoutMs query = do
  parsed <- try (parseRequest (T.unpack endpoint)) :: IO (Either HttpException Request)
  pure $ case parsed of
    Left err -> Left (classifyHttpException err)
    Right req0 -> Right req0
      { method = "POST"
      , requestHeaders =
          [ ("Authorization", TE.encodeUtf8 (T.concat ["Bearer ", apiKey]))
          , ("Content-Type", "application/json")
          ]
      , requestBody = RequestBodyLBS $ encode $ object
          [ "model" .= model
          , "messages" .= [object ["role" .= ("user" :: Text), "content" .= query]]
          ]
      , responseTimeout = responseTimeoutMicro (timeoutMicroseconds timeoutMs)
      , checkResponse = \_ _ -> pure ()
      }

runChatHttp :: Manager -> Request -> IO (Either HttpException (Status, Either ExternalQueryError BS.ByteString))
runChatHttp mgr req =
  try (withResponse req mgr $ \resp -> do
    bodyResult <- readResponseBodyLimited llmMaxResponseBytes (responseBody resp)
    pure (responseStatus resp, bodyResult))

handleChatHttpResult
  :: ExternalTool
  -> Int
  -> Either HttpException (Status, Either ExternalQueryError BS.ByteString)
  -> Either ExternalQueryError ExternalQueryResponse
handleChatHttpResult tool latencyMs httpResult =
  case httpResult of
    Left err -> Left (classifyHttpException err)
    Right (status, bodyResult) ->
      case bodyResult of
        Left err -> Left (classifyBodyReadFailure (statusCode status) err)
        Right rawBody ->
          case decodeLlmBodyLimited llmMaxResponseBytes rawBody of
            Left err -> Left err
            Right body -> responseFromStatus status body
  where
    responseFromStatus status body =
      let code = statusCode status
          diag = redactUpstreamError code body
      in if code >= 200 && code < 300
           then if T.null (T.strip body)
                  then Left EqeEmptyResponse
                  else Right ExternalQueryResponse
                         { eqrRawBody = T.take llmRawBodyTelemetryChars body
                         , eqrStructured = extractStructured body
                         , eqrToolName = etName tool
                         , eqrLatencyMs = latencyMs
                         }
           else case code of
             _ -> Left (classifyHttpStatusError code diag)

classifyBodyReadFailure :: Int -> ExternalQueryError -> ExternalQueryError
classifyBodyReadFailure code err =
  classifyHttpStatusError code $ T.concat
    [ "upstream_status="
    , T.pack (show code)
    , ":body_redacted:"
    , bodyReadFailureTag err
    ]

classifyHttpStatusError :: Int -> Text -> ExternalQueryError
classifyHttpStatusError code diag =
  case code of
    401 -> EqeAuthFailure diag
    403 -> EqeAuthFailure diag
    429 -> EqeRateLimited diag
    _ | code >= 500 && code < 600 -> EqeServerError diag
    _ | code >= 400 && code < 500 -> EqeInvalidResponse diag
    _ -> EqeInvalidResponse diag

bodyReadFailureTag :: ExternalQueryError -> Text
bodyReadFailureTag (EqeInvalidResponse msg) = msg
bodyReadFailureTag EqeEmptyResponse = "empty_response"
bodyReadFailureTag other = T.pack (show other)

readResponseBodyLimited :: Int -> BodyReader -> IO (Either ExternalQueryError BS.ByteString)
readResponseBodyLimited maxBytes reader = go 0 []
  where
    go total chunks = do
      chunk <- brRead reader
      if BS.null chunk
        then pure (Right (BS.concat (reverse chunks)))
        else do
          let total' = total + BS.length chunk
          if total' > maxBytes
            then pure (Left (responseTooLarge total' maxBytes))
            else go total' (chunk : chunks)

decodeLlmBodyLimited :: Int -> BS.ByteString -> Either ExternalQueryError Text
decodeLlmBodyLimited maxBytes raw
  | BS.length raw > maxBytes = Left (responseTooLarge (BS.length raw) maxBytes)
  | otherwise = Right (TE.decodeUtf8With lenientDecode raw)

responseTooLarge :: Int -> Int -> ExternalQueryError
responseTooLarge actual maxBytes =
  EqeInvalidResponse $ T.concat
    [ "response_too_large:max_bytes="
    , T.pack (show maxBytes)
    , ":actual_bytes="
    , T.pack (show actual)
    ]

redactUpstreamError :: Int -> Text -> Text
redactUpstreamError code body =
  T.concat
    [ "upstream_status="
    , T.pack (show code)
    , ":body_redacted:body_chars="
    , T.pack (show (T.length body))
    ]

classifyHttpException :: HttpException -> ExternalQueryError
classifyHttpException err =
  case err of
    InvalidUrlException _ _ -> EqeInvalidResponse "invalid_url"
    HttpExceptionRequest _ ResponseTimeout -> EqeTimeout "response_timeout"
    HttpExceptionRequest _ ConnectionTimeout -> EqeTimeout "connection_timeout"
    HttpExceptionRequest _ content -> EqeNetworkUnavailable (httpExceptionContentTag content)

httpExceptionContentTag :: HttpExceptionContent -> Text
httpExceptionContentTag content =
  "http_exception:" <> T.take 80 (T.takeWhile (\c -> c /= ' ' && c /= '\n') (T.pack (show content)))

timeoutMicroseconds :: Int -> Int
timeoutMicroseconds timeoutMs = max 1 timeoutMs * 1000

elapsedMs :: UTCTime -> UTCTime -> Int
elapsedMs start end = floor ((realToFrac (diffUTCTime end start) :: Double) * 1000.0)

-- | OpenAI-compatible chat-completion response envelope.
-- Used to unwrap the assistant message content.
data ChatCompletionResponse = ChatCompletionResponse
  { ccrChoices :: ![ChatCompletionChoice]
  }
  deriving stock (Generic)

instance FromJSON ChatCompletionResponse where
  parseJSON = withObject "ChatCompletionResponse" $ \o ->
    ChatCompletionResponse <$> o .: "choices"

data ChatCompletionChoice = ChatCompletionChoice
  { cccMessage :: !ChatCompletionMessage
  }
  deriving stock (Generic)

instance FromJSON ChatCompletionChoice where
  parseJSON = withObject "ChatCompletionChoice" $ \o ->
    ChatCompletionChoice <$> o .: "message"

data ChatCompletionMessage = ChatCompletionMessage
  { ccmContent :: !(Maybe Text)
  }
  deriving stock (Generic)

instance FromJSON ChatCompletionMessage where
  parseJSON = withObject "ChatCompletionMessage" $ \o ->
    ChatCompletionMessage <$> o .:? "content"

-- | Extract structured payload from a Mistral / Fireworks chat-completion
-- response using a typed JSON decoder.
--
-- 1. Decode the body as an OpenAI-compatible 'ChatCompletionResponse'.
-- 2. If successful, return the first choice's message content.
-- 3. If decoding fails OR the content is empty/Null, return the raw
--    body so downstream parsers can attempt direct JSON or legacy text.
extractStructured :: Text -> Text
extractStructured body =
  case decodeStrict (TE.encodeUtf8 body) :: Maybe ChatCompletionResponse of
    Nothing -> body
    Just ccr ->
      case ccrChoices ccr of
        [] -> body
        (choice : _) ->
          case ccmContent (cccMessage choice) of
            Nothing  -> body
            Just ""  -> body
            Just txt -> txt

-- Helpers

mockTableLookup :: (Text, Text, Text) -> MockTable -> Maybe (Either ExternalQueryError Text)
mockTableLookup _ [] = Nothing
mockTableLookup key ((a,b,c,d):rest)
  | key == (a,b,c)  = Just d
  | otherwise = mockTableLookup key rest
