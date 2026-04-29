{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

{-| Public embedding types and user-facing codecs. -}
module QxFx0.Semantic.Embedding.Types
  ( Embedding
  , APIHealthCache
  , EmbeddingBackend(..)
  , EmbeddingQuality(..)
  , EmbeddingHealth(..)
  , EmbeddingSource(..)
  , EmbeddingResult(..)
  , embeddingBackendText
  , embeddingQualityText
  , embeddingSourceText
  , embeddingSourceQuality
  ) where

import Control.Concurrent.MVar (MVar)
import Data.Text (Text)
import Data.Time.Clock (UTCTime)
import qualified Data.Vector as V

type Embedding = V.Vector Float
type APIHealthCache = MVar (Maybe (UTCTime, Bool))

data EmbeddingBackend
  = EmbeddingBackendLocalDeterministic
  | EmbeddingBackendRemoteHTTP
  deriving stock (Eq, Show)

data EmbeddingQuality
  = EmbeddingQualityHeuristic
  | EmbeddingQualityModeled
  deriving stock (Eq, Show)

data EmbeddingHealth = EmbeddingHealth
  { ehBackend :: !EmbeddingBackend
  , ehQuality :: !EmbeddingQuality
  , ehExplicit :: !Bool
  , ehOperational :: !Bool
  , ehStrictReady :: !Bool
  }
  deriving stock (Eq, Show)

data EmbeddingSource
  = EmbeddingRemote
  | EmbeddingLocalDeterministic
  | EmbeddingLocalImplicit
  | EmbeddingRemoteFailureLocalFallback
  deriving stock (Eq, Show)

data EmbeddingResult = EmbeddingResult
  { erEmbedding :: !Embedding
  , erSource :: !EmbeddingSource
  }
  deriving stock (Eq, Show)

embeddingBackendText :: EmbeddingBackend -> Text
embeddingBackendText EmbeddingBackendLocalDeterministic = "local_deterministic"
embeddingBackendText EmbeddingBackendRemoteHTTP = "remote_http"

embeddingQualityText :: EmbeddingQuality -> Text
embeddingQualityText EmbeddingQualityHeuristic = "heuristic"
embeddingQualityText EmbeddingQualityModeled = "modeled"

embeddingSourceText :: EmbeddingSource -> Text
embeddingSourceText EmbeddingRemote = "remote_http"
embeddingSourceText EmbeddingLocalDeterministic = "local_deterministic"
embeddingSourceText EmbeddingLocalImplicit = "local_implicit"
embeddingSourceText EmbeddingRemoteFailureLocalFallback = "remote_failure_local_fallback"

embeddingSourceQuality :: EmbeddingSource -> EmbeddingQuality
embeddingSourceQuality source = case source of
  EmbeddingRemote -> EmbeddingQualityModeled
  EmbeddingLocalDeterministic -> EmbeddingQualityHeuristic
  EmbeddingLocalImplicit -> EmbeddingQualityHeuristic
  EmbeddingRemoteFailureLocalFallback -> EmbeddingQualityHeuristic
