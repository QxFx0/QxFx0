{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

module QxFx0.Bridge.Morphology
  ( MorphRemoteToken(..)
  , MorphBackend(..)
  , resolveMorphBackend
  , analyzeMorphRemote
  , checkMorphHealth
  ) where

import Control.Exception (try)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as Aeson
import qualified Data.ByteString.Char8 as B8
import qualified Data.Char as Char
import Network.HTTP.Client (HttpException)
import qualified Network.HTTP.Client as HTTPClient
import qualified Network.HTTP.Simple as HTTP
import System.Environment (lookupEnv)

data MorphRemoteToken = MorphRemoteToken
  { mrtWord   :: !Text
  , mrtLemma  :: !Text
  , mrtPos    :: !(Maybe Text)
  , mrtCase   :: !(Maybe Text)
  , mrtNumber :: !(Maybe Text)
  , mrtGender :: !(Maybe Text)
  , mrtTense  :: !(Maybe Text)
  , mrtMood   :: !(Maybe Text)
  , mrtPerson :: !(Maybe Text)
  } deriving stock (Eq, Show)

instance Aeson.FromJSON MorphRemoteToken where
  parseJSON = Aeson.withObject "MorphRemoteToken" $ \o ->
    MorphRemoteToken
      <$> o Aeson..:  "word"
      <*> o Aeson..:  "lemma"
      <*> o Aeson..:! "pos"
      <*> o Aeson..:! "case"
      <*> o Aeson..:! "number"
      <*> o Aeson..:! "gender"
      <*> o Aeson..:! "tense"
      <*> o Aeson..:! "mood"
      <*> o Aeson..:! "person"

data MorphBackend
  = MorphBackendLocal
  | MorphBackendRemote
  deriving stock (Eq, Show)

resolveMorphBackend :: IO MorphBackend
resolveMorphBackend = do
  mBackend <- fmap (fmap (T.toLower . T.pack)) (lookupEnv "QXFX0_MORPH_BACKEND")
  pure $ case mBackend of
    Just "remote" -> MorphBackendRemote
    _ -> MorphBackendLocal

morphApiUrl :: IO (Maybe String)
morphApiUrl = lookupEnv "MORPH_API_URL"

analyzeMorphRemote :: Text -> IO (Either Text [MorphRemoteToken])
analyzeMorphRemote text = do
  mUrl <- morphApiUrl
  case mUrl of
    Nothing -> pure (Left "MORPH_API_URL not set")
    Just url -> fetchRemoteMorph url text

fetchRemoteMorph :: String -> Text -> IO (Either Text [MorphRemoteToken])
fetchRemoteMorph url txt = do
  requestResult <- try @HttpException (HTTP.parseRequest url)
  case requestResult of
    Left err -> pure (Left ("invalid morph url: " <> showText err))
    Right baseRequest -> do
      let request =
            HTTP.setRequestIgnoreStatus $
              HTTP.setRequestResponseTimeout (HTTPClient.responseTimeoutMicro 5000000) $
                HTTP.setRequestBodyJSON (Aeson.object ["text" Aeson..= txt]) $
                  HTTP.setRequestMethod "POST" baseRequest
      responseResult <- try @HttpException (HTTP.httpBS request)
      case responseResult of
        Left err -> pure (Left ("morph request failed: " <> showText err))
        Right response
          | not (successfulStatus response) ->
              pure (Left ("unexpected morph status: " <> showText (HTTP.getResponseStatusCode response)))
          | not (jsonContentType response) ->
              pure (Left ("unexpected morph content-type: " <> renderContentTypes response))
          | otherwise ->
              pure (parseMorphResponse (HTTP.getResponseBody response))

checkMorphHealth :: IO Bool
checkMorphHealth = do
  mUrl <- morphApiUrl
  case mUrl of
    Nothing -> pure False
    Just url -> do
      requestResult <- try @HttpException (HTTP.parseRequest (url <> "/health"))
      case requestResult of
        Left _ -> pure False
        Right baseRequest -> do
          let request = HTTP.setRequestResponseTimeout (HTTPClient.responseTimeoutMicro 2000000) $
                        HTTP.setRequestMethod "GET" baseRequest
          responseResult <- try @HttpException (HTTP.httpBS request)
          pure $ case responseResult of
            Right response -> successfulStatus response
            Left _ -> False

successfulStatus :: HTTP.Response a -> Bool
successfulStatus response =
  let code = HTTP.getResponseStatusCode response
   in code >= 200 && code < 300

jsonContentType :: HTTP.Response a -> Bool
jsonContentType response =
  any isJsonHeader (HTTP.getResponseHeader "Content-Type" response)
  where
    isJsonHeader raw =
      let lowered = B8.map Char.toLower raw
       in "application/json" `B8.isPrefixOf` B8.dropWhile (== ' ') lowered

renderContentTypes :: HTTP.Response a -> Text
renderContentTypes response =
  case HTTP.getResponseHeader "Content-Type" response of
    [] -> "<missing>"
    headers -> T.intercalate ", " (map (T.pack . B8.unpack) headers)

parseMorphResponse :: B8.ByteString -> Either Text [MorphRemoteToken]
parseMorphResponse body = do
  value <- case Aeson.eitherDecodeStrict' body of
    Left err -> Left ("invalid morph json: " <> showText err)
    Right parsed -> Right parsed
  case Aeson.parseMaybe (Aeson.withObject "resp" (Aeson..: "tokens")) value of
    Just tokens -> Right tokens
    Nothing -> Left "invalid morph response format: missing 'tokens' field"

showText :: Show a => a -> Text
showText = T.pack . show
