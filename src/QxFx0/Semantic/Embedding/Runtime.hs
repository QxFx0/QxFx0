{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

{-| Runtime embedding selection, health checks, and remote fetch logic. -}
module QxFx0.Semantic.Embedding.Runtime
  ( textToEmbedding
  , textToEmbeddingWithManager
  , textToEmbeddingResult
  , textToEmbeddingResultWithManager
  , checkApiHealth
  , checkApiHealthWithManager
  , checkEmbeddingHealth
  , checkEmbeddingHealthWithManager
  ) where

import Control.Concurrent.MVar (modifyMVar_, readMVar)
import Control.Exception (try)
import Data.Char (toLower)
import Data.Text (Text)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as Aeson
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as B8
import qualified Data.Text as T
import Data.Time.Clock (diffUTCTime, getCurrentTime)
import qualified Data.Vector as V
import qualified Data.CaseInsensitive as CI
import Network.HTTP.Client (BodyReader, HttpException, Manager, ResponseTimeout, brRead, withResponse, responseStatus, responseHeaders, responseBody)
import qualified Network.HTTP.Client as HTTPClient
import qualified Network.HTTP.Simple as HTTP
import Network.HTTP.Client.TLS (newTlsManager)
import Network.HTTP.Types.Status (statusCode)
import Network.URI (URI(..), URIAuth(..), parseURI)
import QxFx0.ExceptionPolicy (QxFx0Exception(EmbeddingError), throwQxFx0)
import QxFx0.Semantic.Embedding.Fallback (fallbackEmbedding)
import QxFx0.Semantic.Embedding.Support (embeddingDim)
import QxFx0.Semantic.Embedding.Types
import System.Environment (lookupEnv)

data EmbeddingSelection = EmbeddingSelection
  { esBackend :: !EmbeddingBackend
  , esExplicit :: !Bool
  , esRemoteUrl :: !(Maybe String)
  , esIssues :: ![Text]
  }

checkApiHealth :: APIHealthCache -> IO Bool
checkApiHealth cache = withFreshEmbeddingManager (`checkApiHealthWithManager` cache)

checkApiHealthWithManager :: Manager -> APIHealthCache -> IO Bool
checkApiHealthWithManager manager cache = ehOperational <$> checkEmbeddingHealthWithManager manager cache

checkEmbeddingHealth :: APIHealthCache -> IO EmbeddingHealth
checkEmbeddingHealth cache = withFreshEmbeddingManager (`checkEmbeddingHealthWithManager` cache)

checkEmbeddingHealthWithManager :: Manager -> APIHealthCache -> IO EmbeddingHealth
checkEmbeddingHealthWithManager manager cache = do
  selection <- resolveEmbeddingSelection
  case selection of
    EmbeddingSelection
      { esBackend = EmbeddingBackendLocalDeterministic
      , esExplicit = explicit
      , esIssues = issues
      } ->
      pure EmbeddingHealth
        { ehBackend = EmbeddingBackendLocalDeterministic
        , ehQuality = EmbeddingQualityHeuristic
        , ehExplicit = explicit
        , ehOperational = True
        , ehStrictReady = True
        , ehIssues = issues
        }
    EmbeddingSelection
      { esBackend = EmbeddingBackendRemoteHTTP
      , esExplicit = explicit
      , esRemoteUrl = mUrl
      , esIssues = selectionIssues
      } ->
        case mUrl of
          Nothing ->
            pure EmbeddingHealth
              { ehBackend = EmbeddingBackendRemoteHTTP
              , ehQuality = EmbeddingQualityModeled
              , ehExplicit = explicit
              , ehOperational = False
              , ehStrictReady = False
              , ehIssues = selectionIssues
              }
          Just url -> do
            operational <- cachedRemoteHealth manager cache url
            let healthIssues = if operational then selectionIssues else selectionIssues <> ["remote_embedding_unhealthy"]
            pure EmbeddingHealth
              { ehBackend = EmbeddingBackendRemoteHTTP
              , ehQuality = EmbeddingQualityModeled
              , ehExplicit = explicit
              , ehOperational = operational
              , ehStrictReady = explicit && operational
              , ehIssues = healthIssues
              }

textToEmbedding :: Text -> IO Embedding
textToEmbedding input = erEmbedding <$> textToEmbeddingResult input

textToEmbeddingWithManager :: Manager -> Text -> IO Embedding
textToEmbeddingWithManager manager input = erEmbedding <$> textToEmbeddingResultWithManager manager input

textToEmbeddingResult :: Text -> IO EmbeddingResult
textToEmbeddingResult input = withFreshEmbeddingManager (`textToEmbeddingResultWithManager` input)

textToEmbeddingResultWithManager :: Manager -> Text -> IO EmbeddingResult
textToEmbeddingResultWithManager manager input = do
  selection <- resolveEmbeddingSelection
  case selection of
    EmbeddingSelection
      { esBackend = EmbeddingBackendLocalDeterministic
      , esExplicit = explicit
      } ->
      pure EmbeddingResult
        { erEmbedding = fallbackEmbedding input
        , erSource = if explicit then EmbeddingLocalDeterministic else EmbeddingLocalImplicit
        }
    EmbeddingSelection
      { esBackend = EmbeddingBackendRemoteHTTP
      , esExplicit = explicit
      , esRemoteUrl = mUrl
      , esIssues = issues
      } ->
        case mUrl of
          Just url -> tryRemote explicit url issues input
          Nothing -> failRemote explicit (if null issues then ["remote_embedding_url_missing"] else issues) input
  where
    tryRemote explicit url issues txt = do
      res <- fetchRemoteEmbeddingWithManager manager url txt
      case res of
        Left _ -> failRemote explicit (issues <> ["remote_embedding_unhealthy"]) txt
        Right embedding ->
          pure EmbeddingResult
            { erEmbedding = embedding
            , erSource = EmbeddingRemote
            }

    failRemote explicit issues txt
      | explicit = throwQxFx0 (EmbeddingError (T.intercalate ";" issues))
      | otherwise =
          pure EmbeddingResult
            { erEmbedding = fallbackEmbedding txt
            , erSource = EmbeddingRemoteFailureLocalFallback
            }

resolveEmbeddingSelection :: IO EmbeddingSelection
resolveEmbeddingSelection = do
  mBackend <- fmap normalizeBackend <$> lookupEnv "QXFX0_EMBEDDING_BACKEND"
  mUrl <- lookupEnv "EMBEDDING_API_URL"
  pure $ case mBackend of
    Just "local" ->
      EmbeddingSelection
        { esBackend = EmbeddingBackendLocalDeterministic
        , esExplicit = True
        , esRemoteUrl = Nothing
        , esIssues = []
        }
    Just "local-deterministic" ->
      EmbeddingSelection
        { esBackend = EmbeddingBackendLocalDeterministic
        , esExplicit = True
        , esRemoteUrl = Nothing
        , esIssues = []
        }
    Just "remote" -> remoteSelection mUrl
    Just "remote-http" -> remoteSelection mUrl
    _ ->
      EmbeddingSelection
        { esBackend = EmbeddingBackendLocalDeterministic
        , esExplicit = False
        , esRemoteUrl = Nothing
        , esIssues = []
        }
  where
    normalizeBackend = map toLower
    remoteSelection mRemoteUrl =
      case mRemoteUrl of
        Nothing ->
          EmbeddingSelection
            { esBackend = EmbeddingBackendRemoteHTTP
            , esExplicit = True
            , esRemoteUrl = Nothing
            , esIssues = ["remote_embedding_url_missing"]
            }
        Just url ->
          case validateEmbeddingUrl url of
            Just validated ->
              EmbeddingSelection
                { esBackend = EmbeddingBackendRemoteHTTP
                , esExplicit = True
                , esRemoteUrl = Just validated
                , esIssues = []
                }
            Nothing ->
              EmbeddingSelection
                { esBackend = EmbeddingBackendRemoteHTTP
                , esExplicit = True
                , esRemoteUrl = Nothing
                , esIssues = ["invalid_remote_embedding_url"]
                }

validateEmbeddingUrl :: String -> Maybe String
validateEmbeddingUrl rawUrl
  | null rawUrl = Nothing
  | otherwise =
      case parseURI rawUrl of
        Nothing -> Nothing
        Just uri -> do
          auth <- uriAuthority uri
          let scheme = map toLower (uriScheme uri)
              host = map toLower (uriRegName auth)
              loopbackHosts = ["127.0.0.1", "localhost", "::1"]
          if null host || not (null (uriUserInfo auth))
            then Nothing
            else case scheme of
              "https:" -> Just rawUrl
              "http:" | host `elem` loopbackHosts && allowedLoopbackPort (uriPort auth) -> Just rawUrl
              _ -> Nothing

allowedLoopbackPort :: String -> Bool
allowedLoopbackPort port =
  case port of
    "" -> True
    ":8080" -> True
    ":11434" -> True
    _ -> False

cachedRemoteHealth :: Manager -> APIHealthCache -> String -> IO Bool
cachedRemoteHealth manager cache url = do
  now <- getCurrentTime
  mCache <- readMVar cache
  case mCache of
    Just (ts, status) | diffUTCTime now ts < 60 -> pure status
    _ -> do
      status <- performRealHealthCheck manager url
      modifyMVar_ cache $ \current ->
        case current of
          Just (ts, cachedStatus) | ts > now -> pure current
          _ -> pure (Just (now, status))
      pure status

performRealHealthCheck :: Manager -> String -> IO Bool
performRealHealthCheck manager url =
  either (const False) (const True)
    <$> fetchRemoteEmbeddingWithTimeout manager (HTTPClient.responseTimeoutMicro 2000000) url "healthcheck"

fetchRemoteEmbedding :: String -> Text -> IO (Either Text Embedding)
fetchRemoteEmbedding url txt = withFreshEmbeddingManager (\manager -> fetchRemoteEmbeddingWithManager manager url txt)

withFreshEmbeddingManager :: (Manager -> IO a) -> IO a
withFreshEmbeddingManager action = do
  manager <- newTlsManager
  action manager

fetchRemoteEmbeddingWithManager :: Manager -> String -> Text -> IO (Either Text Embedding)
fetchRemoteEmbeddingWithManager manager =
  fetchRemoteEmbeddingWithTimeout manager (HTTPClient.responseTimeoutMicro 5000000)

fetchRemoteEmbeddingWithTimeout :: Manager -> ResponseTimeout -> String -> Text -> IO (Either Text Embedding)
fetchRemoteEmbeddingWithTimeout manager timeout url txt = do
  requestResult <- try @HttpException (HTTP.parseRequest url)
  case requestResult of
    Left err -> pure (Left ("invalid embedding url: " <> showText err))
    Right baseRequest -> do
      let request =
            HTTP.setRequestIgnoreStatus $
              HTTP.setRequestResponseTimeout timeout $
                HTTP.setRequestBodyJSON (Aeson.object ["model" Aeson..= ("all-minilm" :: String), "prompt" Aeson..= txt]) $
                  HTTP.setRequestMethod "POST" baseRequest
      responseResult <- try @HttpException $ do
        withResponse request manager $ \response -> do
          if not (successfulStatusCode (statusCode (responseStatus response)))
            then pure (Left ("unexpected embedding status: " <> showText (statusCode (responseStatus response))))
            else if not (jsonContentTypeSimple (responseHeaders response))
              then pure (Left ("unexpected embedding type: " <> renderContentTypesSimple (responseHeaders response)))
              else do
                bodyResult <- readResponseBodyLimited embeddingMaxResponseBytes (responseBody response)
                pure (bodyResult >>= parseEmbeddingResponse)
      case responseResult of
        Left err -> pure (Left ("embedding request failed: " <> showText err))
        Right result -> pure result

embeddingMaxResponseBytes :: Int
embeddingMaxResponseBytes = 1048576

successfulStatusCode :: Int -> Bool
successfulStatusCode code = code >= 200 && code < 300

jsonContentTypeSimple :: HTTP.ResponseHeaders -> Bool
jsonContentTypeSimple headers =
  any isJsonHeader [ value | (name, value) <- headers, CI.foldedCase name == "content-type" ]
  where
    isJsonHeader raw =
      let lowered = B8.map toLower raw
      in "application/json" `B8.isPrefixOf` B8.dropWhile (== ' ') lowered

renderContentTypesSimple :: HTTP.ResponseHeaders -> Text
renderContentTypesSimple headers =
  let values = [ T.pack (B8.unpack value) | (name, value) <- headers, CI.foldedCase name == "content-type" ]
  in case values of
       [] -> "<missing>"
       xs -> T.intercalate ", " xs

parseEmbeddingResponse :: B8.ByteString -> Either Text Embedding
parseEmbeddingResponse body = do
  value <- case Aeson.eitherDecodeStrict' body of
    Left err -> Left ("invalid embedding json: " <> showText err)
    Right parsed -> Right parsed
  case Aeson.parseMaybe (Aeson.withObject "resp" (Aeson..: "embedding")) value of
    Just list ->
      let vec = V.fromList list
       in if V.length vec == embeddingDim
            then Right vec
            else Left ("unexpected embedding dimension: expected " <> showText embeddingDim <> ", got " <> showText (V.length vec))
    Nothing -> Left "invalid embedding format"

showText :: Show a => a -> Text
showText = T.pack . show

readResponseBodyLimited :: Int -> BodyReader -> IO (Either Text B8.ByteString)
readResponseBodyLimited maxBytes reader = go 0 []
  where
    go total chunks = do
      chunk <- brRead reader
      if BS.null chunk
        then pure (Right (B8.concat (reverse chunks)))
        else do
          let total' = total + BS.length chunk
          if total' > maxBytes
            then pure (Left ("embedding response too large: " <> showText total'))
            else go total' (chunk : chunks)
