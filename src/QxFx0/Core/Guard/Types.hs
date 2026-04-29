{-# LANGUAGE DerivingStrategies #-}

{-| Core guard surface model and post-render safety verdict types. -}
module QxFx0.Core.Guard.Types
  ( SafetyStatus(..)
  , RenderSegmentKind(..)
  , RenderSegment(..)
  , GuardSurface(..)
  ) where

import Data.Text (Text)

data SafetyStatus
  = InvariantOK
  | InvariantWarn !Text
  | InvariantBlock !Text
  deriving stock (Eq, Show)

data RenderSegmentKind
  = SegmentTemplate
  | SegmentIdentityClaim
  | SegmentNarrative
  | SegmentSurfacing
  | SegmentLocalRecovery
  | SegmentIntrospection
  deriving stock (Eq, Show)

data RenderSegment = RenderSegment
  { rsKind :: !RenderSegmentKind
  , rsText :: !Text
  } deriving stock (Eq, Show)

data GuardSurface = GuardSurface
  { gsRenderedText :: !Text
  , gsSegments :: ![RenderSegment]
  , gsQuestionLike :: !Bool
  } deriving stock (Eq, Show)
