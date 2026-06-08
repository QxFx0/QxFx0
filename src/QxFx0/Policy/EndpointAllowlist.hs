{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : QxFx0.Policy.EndpointAllowlist
Description : Pure host-allowlist + endpoint-URL validation, shared across layers.

Extracted from @QxFx0.Bridge.ExternalLLM@ so that BOTH the Bridge LLM path and
the Semantic embedding path validate remote endpoints against ONE allowlist,
without Semantic importing Bridge (architecture invariant [2]). Pure: no IO, no
network. 'TransportFallbackReason' lives in 'QxFx0.Types.ExternalQuery'.
-}
module QxFx0.Policy.EndpointAllowlist
  ( endpointAllowlist
  , untrustedHostOverrideWarningTag
  , validateEndpointUrl
  , validateEndpointUrlWithContext
  , parseEndpointHost
  , endpointHost
  , isTruthy
  ) where

import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import Network.URI (URI(..), URIAuth(..), parseURI)

import QxFx0.Types.ExternalQuery (TransportFallbackReason(..))

-- | Official remote-endpoint host allowlist. The single source of truth for
-- both LLM and embedding remote calls.
endpointAllowlist :: [Text]
endpointAllowlist =
  [ "api.mistral.ai"
  , "api.fireworks.ai"
  ]

untrustedHostOverrideWarningTag :: Text
untrustedHostOverrideWarningTag = "llm_untrusted_host_override_allowed"

-- | Validate an endpoint URL using the strict default policy
-- (HTTPS + host in 'endpointAllowlist', fail-closed). 'Right ()' = allowed.
validateEndpointUrl :: Text -> Maybe Text -> Either TransportFallbackReason ()
validateEndpointUrl endpoint mAllowOverride =
  () <$ validateEndpointUrlWithContext endpoint mAllowOverride Nothing Nothing

-- | Validate with explicit override context. Parameters after the endpoint:
-- the @QXFX0_LLM_ALLOW_UNTRUSTED_HOST@ value, a dev/test marker, and a
-- double-confirmation marker. A successful untrusted-host override returns the
-- warning tag that must be logged before a bearer token is sent.
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
                if host `elem` endpointAllowlist
                  then Right Nothing
                  else if mAllowOverride == Just "1"
                         -- Two-factor on top of the override flag: an untrusted
                         -- host requires BOTH an explicit dev/test context AND
                         -- the double-confirmation marker. (Was '||', which let a
                         -- single factor suffice — too permissive for a
                         -- fail-closed gate; tests 18/19 pin the stricter AND.)
                         then if isTruthy mDevOrTestMode && isTruthy mDoubleConfirm
                                then Right (Just untrustedHostOverrideWarningTag)
                                else Left TfrUntrustedOverrideRejected
                         else Left TfrBlockedHost

-- | Parse the lowercased host from an endpoint, enforcing https, no userinfo,
-- and port 443 (or default). 'Nothing' on any violation.
parseEndpointHost :: Text -> Maybe Text
parseEndpointHost endpoint = do
  uri <- parseURI (T.unpack endpoint)
  auth <- uriAuthority uri
  let scheme = T.toLower (T.pack (uriScheme uri))
      rawHost = uriRegName auth
      rawPort = uriPort auth
      portAllowed = null rawPort || rawPort == ":443"
  if scheme == "https:" && null (uriUserInfo auth) && not (null rawHost) && portAllowed
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
