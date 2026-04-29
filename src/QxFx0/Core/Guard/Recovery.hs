{-# LANGUAGE OverloadedStrings #-}

{-| Guard recovery helpers for blocked outputs and safe fallback surface generation. -}
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
    , gsSegments = [RenderSegment SegmentTemplate recoveryRenderedText]
    , gsQuestionLike = True
    }

recoveryRenderedText :: Text
recoveryRenderedText = "Извини, я сейчас перенастраиваю ход мысли. Можем продолжить через секунду?"
