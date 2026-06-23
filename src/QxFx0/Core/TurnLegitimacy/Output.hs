{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-| Final output assembly with legitimacy-aware safety fallback handling.

  The content quality gate is applied AFTER structural safety checks.
  If structural safety passes but content quality fails, the output is
  replaced with the recovery surface (fail-closed).
-}
module QxFx0.Core.TurnLegitimacy.Output
  ( finalizeOutput
  , finalizeOutputWithTopic
  , safeOutputText
  ) where

import Data.Text (Text)

import QxFx0.Core.Guard
  ( GuardSurface(..)
  , SafetyStatus(..)
  , QualityVerdict(..)
  , evaluateContentQualityWithTopic
  , fallbackSurfaceOnBlock
  , postRenderSafetyCheckSurface
  , recoverySurface
  )
import QxFx0.Types

-- | Finalize output with topic-agnostic content quality check.
finalizeOutput :: GuardSurface -> [Text] -> (GuardSurface, SurfaceProvenance)
finalizeOutput preSafetySurface history =
  finalizeOutputWithTopic preSafetySurface history ""

-- | Finalize output with topic-aware content quality gate.
-- The gate is applied after structural safety checks.
-- If structural safety blocks, recovery surface is used (existing behavior).
-- Content quality gate is now BLOCKING (fail-closed): outputs that fail
-- semantic checks (empty, template placeholders, generic fillers, zero topic
-- relevance for 16+ tokens, low content density, high repetition) are replaced
-- with the recovery surface.
finalizeOutputWithTopic :: GuardSurface -> [Text] -> Text -> (GuardSurface, SurfaceProvenance)
finalizeOutputWithTopic preSafetySurface history topic =
  let safetyStatus = postRenderSafetyCheckSurface preSafetySurface history
      renderedText = gsRenderedText preSafetySurface
      qualityVerdict = evaluateContentQualityWithTopic topic renderedText
      structuralBlocked = case safetyStatus of
        InvariantBlock _ -> True
        _ -> False
      qualityBlocked = case qualityVerdict of
        QualityBlock _ -> True
        QualityPass -> False
      isBlocked = structuralBlocked || qualityBlocked
      renderedSurface = if isBlocked then recoverySurface else preSafetySurface
      surfaceProvenance = if isBlocked then FromRecovery else FromDB
   in (renderedSurface, surfaceProvenance)


safeOutputText :: GuardSurface -> GuardSurface -> SafetyStatus -> Text
safeOutputText okSurface blockedSurface safetyStatus =
  gsRenderedText (fallbackSurfaceOnBlock okSurface blockedSurface safetyStatus)
