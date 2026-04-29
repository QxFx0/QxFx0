{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE StrictData #-}
module QxFx0.Types.IdentityGuard
  ( identityManifoldRadius
  , IdentityGuardWarning(..)
  , IdentityGuardCalibration(..)
  , defaultIdentityGuardCalibration
  , IdentityGuardReport(..)
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import GHC.Generics (Generic)
import QxFx0.Types.Config.Identity
  ( identityGuardAgencyFloorDefault
  , identityGuardManifoldRadiusDefault
  , identityGuardTensionCeilingDefault
  )

identityManifoldRadius :: Double
identityManifoldRadius = identityGuardManifoldRadiusDefault

data IdentityGuardWarning
  = GuardTransitionOutsideManifold
  | GuardHighTensionDrift
  | GuardAgencyCollapse
  deriving stock (Show, Read, Eq, Ord, Generic, Bounded, Enum)
  deriving anyclass (NFData, ToJSON, FromJSON)

data IdentityGuardCalibration = IdentityGuardCalibration
  { igcTensionDriftThreshold :: !Double
  , igcAgencyFloor           :: !Double
  , igcTensionCeiling        :: !Double
  } deriving stock (Show, Read, Eq, Generic)
  deriving anyclass (FromJSON, NFData, ToJSON)

defaultIdentityGuardCalibration :: IdentityGuardCalibration
defaultIdentityGuardCalibration = IdentityGuardCalibration
  { igcTensionDriftThreshold = identityManifoldRadius
  , igcAgencyFloor           = identityGuardAgencyFloorDefault
  , igcTensionCeiling        = identityGuardTensionCeilingDefault
  }

data IdentityGuardReport = IdentityGuardReport
  { igrAgencyDelta  :: !Double
  , igrTensionDelta :: !Double
  , igrWithinBounds :: !Bool
  , igrWarnings     :: ![IdentityGuardWarning]
  } deriving stock (Show, Read, Eq, Generic)
  deriving anyclass (FromJSON, NFData, ToJSON)
