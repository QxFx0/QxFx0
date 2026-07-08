{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

{-| Typed labels for the turn-pipeline effect bus.

These replace the previous string-keyed @[(Text, TurnEffectRequest)]@ buses
with a sum type, eliminating implicit string equality and typo-prone lookups.
-}
module QxFx0.Core.TurnPipeline.EffectLabel
  ( PipelineEffectLabel(..)
  , pipelineEffectLabelText
  , parsePipelineEffectLabel
  ) where

import Data.Aeson (FromJSON(..), ToJSON(..), Value, withText)
import Data.Aeson.Types (Parser)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

data PipelineEffectLabel
  = PelEmbedding
  | PelNix
  | PelConsciousness
  | PelIntuition
  | PelApiHealth
  | PelShadow
  | PelAgda
  | PelRequest
  | PelExplore
  | PelSemanticIntrospection
  | PelWarnMorphology
  | PelFmarMode
  deriving stock (Eq, Ord, Show, Read, Generic)

-- | Render a label to the same snake_case string used historically for the
-- effect bus.  This keeps JSON serialization backward-compatible with the
-- previous @Text@-keyed representation.
pipelineEffectLabelText :: PipelineEffectLabel -> Text
pipelineEffectLabelText PelEmbedding            = "embedding"
pipelineEffectLabelText PelNix                  = "nix"
pipelineEffectLabelText PelConsciousness        = "consciousness"
pipelineEffectLabelText PelIntuition            = "intuition"
pipelineEffectLabelText PelApiHealth            = "api_health"
pipelineEffectLabelText PelShadow               = "shadow"
pipelineEffectLabelText PelAgda                 = "agda"
pipelineEffectLabelText PelRequest              = "request"
pipelineEffectLabelText PelExplore              = "explore"
pipelineEffectLabelText PelSemanticIntrospection = "semantic_introspection"
pipelineEffectLabelText PelWarnMorphology       = "warn_morphology"
pipelineEffectLabelText PelFmarMode             = "fmar_mode"

-- | Inverse of 'pipelineEffectLabelText'.
parsePipelineEffectLabel :: Text -> Maybe PipelineEffectLabel
parsePipelineEffectLabel t =
  case t of
    "embedding"              -> Just PelEmbedding
    "nix"                    -> Just PelNix
    "consciousness"          -> Just PelConsciousness
    "intuition"              -> Just PelIntuition
    "api_health"             -> Just PelApiHealth
    "shadow"                 -> Just PelShadow
    "agda"                   -> Just PelAgda
    "request"                -> Just PelRequest
    "explore"                -> Just PelExplore
    "semantic_introspection" -> Just PelSemanticIntrospection
    "warn_morphology"        -> Just PelWarnMorphology
    "fmar_mode"              -> Just PelFmarMode
    _                        -> Nothing

instance ToJSON PipelineEffectLabel where
  toJSON = toJSON . pipelineEffectLabelText

instance FromJSON PipelineEffectLabel where
  parseJSON = withText "PipelineEffectLabel" $ \t ->
    case parsePipelineEffectLabel t of
      Just label -> pure label
      Nothing    -> fail ("unknown PipelineEffectLabel: " <> T.unpack t)
