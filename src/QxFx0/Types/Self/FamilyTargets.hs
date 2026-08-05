{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Types.Self.FamilyTargets (FamilyTarget(..)) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import GHC.Generics (Generic)

import QxFx0.Types.Domain.R5 (CanonicalMoveFamily)
import QxFx0.Types.Self.Field (Field)

data FamilyTarget = FamilyTarget
  { ftFamily            :: !CanonicalMoveFamily
  , ftTargetField       :: !Field
  , ftMinConatus        :: !Double
  , ftMaxCounterfactual :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)
