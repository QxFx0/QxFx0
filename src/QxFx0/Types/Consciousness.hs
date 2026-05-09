{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

{-| Consciousness narrative type: promoted to Types layer so Semantic and Render
    modules can reference it without importing Core (architecture compliance).
-}
module QxFx0.Types.Consciousness
  ( ConsciousnessNarrative(..)
  ) where

import Data.Text (Text)
import GHC.Generics (Generic)

data ConsciousnessNarrative = ConsciousnessNarrative
  { cnKernelState :: Text
  , cnActiveDesires :: Text
  , cnSkillInPlay :: Text
  , cnSelfView :: Text
  , cnConflict :: Text
  , cnLimitation :: Text
  } deriving stock (Show, Read, Generic)
