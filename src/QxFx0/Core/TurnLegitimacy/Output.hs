{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-| Final output assembly with legitimacy-aware safety fallback handling. -}
module QxFx0.Core.TurnLegitimacy.Output
  ( finalizeOutput
  , safeOutputText
  ) where

import Data.Text (Text)

import QxFx0.Core.Guard
  ( GuardSurface(..)
  , SafetyStatus(..)
  , fallbackSurfaceOnBlock
  , postRenderSafetyCheckSurface
  , recoverySurface
  )
import QxFx0.Types

finalizeOutput :: GuardSurface -> [Text] -> (GuardSurface, SurfaceProvenance)
finalizeOutput preSafetySurface history =
  let safetyStatus = postRenderSafetyCheckSurface preSafetySurface history
      renderedSurface = fallbackSurfaceOnBlock preSafetySurface recoverySurface safetyStatus
      surfaceProvenance =
        case safetyStatus of
          InvariantBlock _ -> FromRecovery
          _ -> FromDB
   in (renderedSurface, surfaceProvenance)

safeOutputText :: GuardSurface -> GuardSurface -> SafetyStatus -> Text
safeOutputText okSurface blockedSurface safetyStatus =
  gsRenderedText (fallbackSurfaceOnBlock okSurface blockedSurface safetyStatus)
