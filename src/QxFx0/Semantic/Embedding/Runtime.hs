{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

{-| Runtime embedding selection, health checks, and remote fetch logic. -}
module QxFx0.Semantic.Embedding.Runtime
  ( textToEmbedding
  , textToEmbeddingResult
  , checkApiHealth
  , checkEmbeddingHealth
  ) where

import Control.Concurrent.MVar (modifyMVar)
import Control.Exception (try)
import Data.Char (toLower)
import Data.Text (Text)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as Aeson
import qualified Data.ByteString.Char8 as B8
import qualified Data.Text as T
import Data.Time.Clock (diffUTCTime, getCurrentTime)
import qualified Data.Vector as V
import Network.HTTP.Client (HttpException, ResponseTimeout)
import qualified Network.HTTP.Client as HTTPClient
import qualified Network.HTTP.Simple as HTTP
import QxFx0.Semantic.Embedding.Fallback (fallbackEmbedding)
import QxFx0.Semantic.Embedding.Support (embeddingDim)
import QxFx0.Semantic.Embedding.Types
import System.Environment (lookupEnv)

data EmbeddingSelection = EmbeddingSelection !EmbeddingBackend !Bool !(Maybe String)

checkApiHealth :: APIHealthCache -> IO Bool
checkApiHealth cache = ehOperational <$> checkEmbeddingHealth cache

checkEmbeddingHealth :: APIHealthCache -> IO EmbeddingHealth
checkEmbeddingHealth cache = do
  selection <- resolveEmbeddingSelection
  case selection of
    EmbeddingSelection EmbeddingBackendLocalDeterministic explicit _ ->
      pure EmbeddingHealth
        { ehBackend = EmbeddingBackendLocalDeterministic
        , ehQuality = EmbeddingQualityHeuristic
        , ehExplicit = explicit
        , ehOperational = True
        , ehStrictReady = True
        }
    EmbeddingSelection EmbeddingBackendRemoteHTTP explicit mUrl ->
      case mUrl of
        Nothing ->
          pure EmbeddingHealth
            { ehBackend = EmbeddingBackendRemoteHTTP
            , ehQuality = EmbeddingQualityModeled
            , ehExplicit = explicit
            , ehOperational = False
            , ehStrictReady = False
            }
        Just url -> do
          operational <- cachedRemoteHealth cache url
          pure EmbeddingHealth
            { ehBackend = EmbeddingBackendRemoteHTTP
            , ehQuality = EmbeddingQualityModeled
            , ehExplicit = explicit
            , ehOperational = operational
            , ehStrictReady = explicit && operational
            }

textToEmbedding :: String -> IO Embedding
textToEmbedding input = erEmbedding <$> textToEmbeddingResult input

textToEmbeddingResult :: String -> IO EmbeddingResult
textToEmbeddingResult input = do
  selection <- resolveEmbeddingSelection
  case selection of
    EmbeddingSelection EmbeddingBackendLocalDeterministic explicit _ ->
      pure EmbeddingResult
        { erEmbedding = fallbackEmbedding input
        , erSource = if explicit then EmbeddingLocalDeterministic else EmbeddingLocalImplicit
        }
    EmbeddingSelection EmbeddingBackendRemoteHTTP _ (Just url) ->
      tryRemote url input
    EmbeddingSelection EmbeddingBackendRemoteHTTP _ Nothing ->
      pure EmbeddingResult
        { erEmbedding = fallbackEmbedding input
        , erSource = EmbeddingRemoteFailureLocalFallback
        }
  where
    tryRemote url txt = do
      res <- fetchRemoteEmbedding url txt
      case res of
        Left _ ->
          pure EmbeddingResult
            { erEmbedding = fallbackEmbedding txt
            , erSource = EmbeddingRemoteFailureLocalFallback
            }
        Right embedding ->
          pure EmbeddingResult
            { erEmbedding = embedding
            , erSource = EmbeddingRemote
            }

resolveEmbeddingSelection :: IO EmbeddingSelection
resolveEmbeddingSelection = do
  mBackend <- fmap normalizeBackend <$> lookupEnv "QXFX0_EMBEDDING_BACKEND"
  mUrl <- lookupEnv "EMBEDDING_API_URL"
  pure $
    case mBackend of
      Just "local" -> EmbeddingSelection EmbeddingBackendLocalDeterministic True Nothing
      Just "local-deterministic" -> EmbeddingSelection EmbeddingBackendLocalDeterministic True Nothing
      Just "remote" -> EmbeddingSelection EmbeddingBackendRemoteHTTP True mUrl
      Just "remote-http" -> EmbeddingSelection EmbeddingBackendRemoteHTTP True mUrl
      _ -> EmbeddingSelection EmbeddingBackendLocalDeterministic False Nothing
  where
    normalizeBackend = map toLower

cachedRemoteHealth :: APIHealthCache -> String -> IO Bool
cachedRemoteHealth cache url = do
  now <- getCurrentTime
  modifyMVar cache $ \mCache ->
    case mCache of
      Just (ts, status) | diffUTCTime now ts < 60 -> pure (mCache, status)
      _ -> do
        status <- performRealHealthCheck url
        pure (Just (now, status), status)

performRealHealthCheck :: String -> IO Bool
performRealHealthCheck url =
  either (const False) (const True)
    <$> fetchRemoteEmbeddingWithTimeout (HTTPClient.responseTimeoutMicro 2000000) url "healthcheck"

fetchRemoteEmbedding :: String -> String -> IO (Either Text Embedding)
fetchRemoteEmbedding =
  fetchRemoteEmbeddingWithTimeout (HTTPClient.responseTimeoutMicro 5000000)

fetchRemoteEmbeddingWithTimeout :: ResponseTimeout -> String -> String -> IO (Either Text Embedding)
fetchRemoteEmbeddingWithTimeout timeout url txt = do
  requestResult <- try @HttpException (HTTP.parseRequest url)
  case requestResult of
    Left err -> pure (Left ("invalid embedding url: " <> showText err))
    Right baseRequest -> do
      let request =
            HTTP.setRequestIgnoreStatus $
              HTTP.setRequestResponseTimeout timeout $
                HTTP.setRequestBodyJSON (Aeson.object ["model" Aeson..= ("all-minilm" :: String), "prompt" Aeson..= txt]) $
                  HTTP.setRequestMethod "POST" baseRequest
      responseResult <- try @HttpException (HTTP.httpBS request)
      case responseResult of
        Left err -> pure (Left ("embedding request failed: " <> showText err))
        Right response
          | not (successfulStatus response) ->
              pure (Left ("unexpected embedding status: " <> showText (HTTP.getResponseStatusCode response)))
          | not (jsonContentType response) ->
              pure (Left ("unexpected embedding content-type: " <> renderContentTypes response))
          | otherwise ->
              pure (parseEmbeddingResponse (HTTP.getResponseBody response))

successfulStatus :: HTTP.Response a -> Bool
successfulStatus response =
  let code = HTTP.getResponseStatusCode response
   in code >= 200 && code < 300

jsonContentType :: HTTP.Response a -> Bool
jsonContentType response =
  any isJsonHeader (HTTP.getResponseHeader "Content-Type" response)
  where
    isJsonHeader raw =
      let lowered = B8.map toLower raw
       in "application/json" `B8.isPrefixOf` B8.dropWhile (== ' ') lowered

renderContentTypes :: HTTP.Response a -> Text
renderContentTypes response =
  case HTTP.getResponseHeader "Content-Type" response of
    [] -> "<missing>"
    headers -> T.intercalate ", " (map (T.pack . B8.unpack) headers)

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
