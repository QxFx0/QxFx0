{-# LANGUAGE OverloadedStrings #-}

{-| Guard recovery: safety fallback when all assembly output is blocked.

  The single static string here is the ULTIMATE catch-all — it fires only when
  the meaning assembly pipeline is completely blocked by the safety guard.
  This is NOT a template path; it's a circuit breaker.
-}
module QxFx0.Core.Guard.Recovery
  ( recoverySurface
  , fallbackSurfaceOnBlock
  ) where

import Data.Text (Text)

import QxFx0.Core.Guard.Types

fallbackSurfaceOnBlock :: GuardSurface -> GuardSurface -> SafetyStatus -> GuardSurface
fallbackSurfaceOnBlock okSurface blockedSurface safetyStatus =
  case safetyStatus of
    InvariantBlock _ -> blockedSurface
    _ -> okSurface

recoverySurface :: GuardSurface
recoverySurface =
  GuardSurface
    { gsRenderedText = recoveryRenderedText
    , gsSegments = [RenderSegment SegmentFallback recoveryRenderedText]
    , gsQuestionLike = True
    }

-- Single hardcoded safety string — circuit breaker, not template.
-- Honesty fix (pre-registered 2026-09-28): every trigger reaching
-- here is deterministic, so the text owns the failure and invites
-- reformulation instead of promising transient reconfiguration and
-- retry-after-a-second. Ends «?» consistent with gsQuestionLike.
recoveryRenderedText :: Text
recoveryRenderedText =
  "Извини, на эту реплику честного ответа у меня не собралось — попробуешь сформулировать иначе?"
