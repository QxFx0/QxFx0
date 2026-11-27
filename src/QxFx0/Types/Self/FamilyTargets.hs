{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Types.Self.FamilyTargets (FamilyTarget(..)) where

import Control.DeepSeq (NFData)
import Data.Aeson
  ( FromJSON(..)
  , Options(..)
  , ToJSON(..)
  , defaultOptions
  , genericParseJSON
  , genericToJSON
  )
import GHC.Generics (Generic)

import QxFx0.Internal.WireCompat (legacyConatusLabel)
import QxFx0.Types.Domain.R5 (CanonicalMoveFamily)
import QxFx0.Types.Self.Field (Field)

data FamilyTarget = FamilyTarget
  { ftFamily            :: !CanonicalMoveFamily
  , ftTargetField       :: !Field
  , ftMinStateIntegrity        :: !Double
  , ftMaxCounterfactual :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

-- | P4 (2026-11-23): persisted as @selfFamilyTargets@; the floor key
-- keeps its historical @ftMinConatus@ spelling.
instance ToJSON FamilyTarget where
  toJSON = genericToJSON defaultOptions
    { fieldLabelModifier = legacyConatusLabel }

instance FromJSON FamilyTarget where
  parseJSON = genericParseJSON defaultOptions
    { fieldLabelModifier = legacyConatusLabel }
