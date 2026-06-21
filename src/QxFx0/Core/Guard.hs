{-| Guard façade: post-render safety checks, content quality gate, and recovery surface primitives. -}
module QxFx0.Core.Guard
  ( postRenderSafetyCheck
  , postRenderSafetyCheckSurface
  , recoverySurface
  , fallbackSurfaceOnBlock
  , RenderSegmentKind(..)
  , RenderSegment(..)
  , GuardSurface(..)
  , SafetyStatus(..)
  , QualityVerdict(..)
  , evaluateContentQuality
  , evaluateContentQualityWithTopic
  ) where

import QxFx0.Core.Guard.Checks
  ( postRenderSafetyCheck
  , postRenderSafetyCheckSurface
  )
import QxFx0.Core.Guard.Recovery
  ( fallbackSurfaceOnBlock
  , recoverySurface
  )
import QxFx0.Core.Guard.Types
  ( GuardSurface(..)
  , RenderSegment(..)
  , RenderSegmentKind(..)
  , SafetyStatus(..)
  )
import QxFx0.Core.Guard.ContentQuality
  ( QualityVerdict(..)
  , evaluateContentQuality
  , evaluateContentQualityWithTopic
  )
