{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Types.ExternalQuery
Description : Types for external tool query transport (Phase 8).

Typed error taxonomy and response envelope for LLM / mentor / script
queries.  Kept pure and serialisable so the sandbox gate can replay
responses deterministically.
-}
module QxFx0.Types.ExternalQuery
  ( ExternalQueryError(..)
  , ExternalQueryResponse(..)
  , ExternalQueryConfig(..)
  , TransportFallbackReason(..)
  , renderExternalQueryError
  , renderFallbackReason
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

-- | Typed error taxonomy for external query failures.
--
-- Network and transport errors are distinguished from content-level
-- errors so the learning loop can decide whether to retry, fallback,
-- or reject.
data ExternalQueryError
  = EqeNetworkUnavailable !Text
    -- ^ DNS timeout, TLS failure, or no route to host.
  | EqeAuthFailure !Text
    -- ^ 401 / 403 or missing API key.
  | EqeRateLimited !Text
    -- ^ 429 or quota exceeded; back-off recommended.
  | EqeServerError !Text
    -- ^ 5xx from upstream.
  | EqeTimeout !Text
    -- ^ In-application deadline exceeded.
  | EqeInvalidResponse !Text
    -- ^ Response body is not valid JSON / schema.
  | EqeFallback !TransportFallbackReason
    -- ^ The runtime intentionally fell back instead of attempting an
    --   authoritative upstream query. This is non-authoritative and
    --   must not be treated as learning success.
  | EqeEmptyResponse
    -- ^ Response body is empty after trimming.
  deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- | Normalised response from an external tool.
--
-- The raw body is kept for telemetry / debugging, but the
-- 'eqrStructured' field is what the validator and parser consume.
data ExternalQueryResponse = ExternalQueryResponse
  { eqrRawBody      :: !Text
    -- ^ Original response body (truncated at 4 KiB by transport).
  , eqrStructured   :: !Text
    -- ^ Extracted structured payload (JSON schema or constrained text).
  , eqrToolName     :: !Text
    -- ^ Canonical tool identifier for reliability tracking.
  , eqrLatencyMs    :: !Int
    -- ^ Round-trip latency in milliseconds (for telemetry).
  }
  deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- | Explicit configuration contract for external query transport.
-- All fields are optional with safe defaults; the builder in
-- 'Bridge.ExternalLLM' fills them from env vars.
data ExternalQueryConfig = ExternalQueryConfig
  { eqcTransportMode   :: !Text
    -- ^ "mock" | "mistral"
  , eqcApiKey          :: !(Maybe Text)
    -- ^ Redacted in 'Show' / logs.
  , eqcModel           :: !Text
  , eqcEndpoint        :: !Text
  , eqcTimeoutMs       :: !Int
  , eqcFallbackReason  :: !(Maybe TransportFallbackReason)
    -- ^ If transport fell back to mock, why.
  }
  deriving stock (Eq, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

instance Show ExternalQueryConfig where
  show cfg =
    "ExternalQueryConfig { transportMode=" ++ show (eqcTransportMode cfg)
    ++ ", apiKey=<REDACTED>"
    ++ ", model=" ++ show (eqcModel cfg)
    ++ ", endpoint=" ++ show (eqcEndpoint cfg)
    ++ ", timeoutMs=" ++ show (eqcTimeoutMs cfg)
    ++ ", fallbackReason=" ++ show (eqcFallbackReason cfg)
    ++ " }"

-- | Why the transport fell back to mock instead of using the real
-- Mistral API.  Used for telemetry and operator diagnosis.
data TransportFallbackReason
  = TfrEnvNotSet
    -- ^ QXFX0_LLM_TRANSPORT is not "mistral".
  | TfrKeyMissing
    -- ^ QXFX0_MISTRAL_API_KEY is absent or empty.
  | TfrExplicitMock
    -- ^ User explicitly requested mock mode.
  | TfrUnsafeEndpoint
    -- ^ Endpoint does not use HTTPS.
  | TfrBlockedHost
    -- ^ Endpoint host is not in the official allowlist and untrusted-host
    -- override is not enabled.
  | TfrUntrustedOverrideRejected
    -- ^ Untrusted-host override was requested but the runtime was not in an
    -- explicit dev/test or double-confirmed mode.
  deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

renderFallbackReason :: TransportFallbackReason -> Text
renderFallbackReason TfrEnvNotSet    = "env_not_set"
renderFallbackReason TfrKeyMissing = "key_missing"
renderFallbackReason TfrExplicitMock = "explicit_mock"
renderFallbackReason TfrUnsafeEndpoint = "unsafe_endpoint"
renderFallbackReason TfrBlockedHost = "blocked_host"
renderFallbackReason TfrUntrustedOverrideRejected = "untrusted_override_rejected"

renderExternalQueryError :: ExternalQueryError -> Text
renderExternalQueryError err =
  case err of
    EqeNetworkUnavailable t -> T.concat ["network_unavailable:", t]
    EqeAuthFailure t        -> T.concat ["auth_failure:", t]
    EqeRateLimited t        -> T.concat ["rate_limited:", t]
    EqeServerError t        -> T.concat ["server_error:", t]
    EqeTimeout t            -> T.concat ["timeout:", t]
    EqeInvalidResponse t      -> T.concat ["invalid_response:", t]
    EqeFallback reason      -> T.concat ["fallback:", renderFallbackReason reason]
    EqeEmptyResponse        -> "empty_response"
