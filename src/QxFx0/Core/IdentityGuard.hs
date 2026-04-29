{-# LANGUAGE DerivingStrategies, OverloadedStrings, StrictData, DeriveGeneric, DeriveAnyClass #-}
{-| Identity-guard facade and convenience constructors for guard reports. -}
module QxFx0.Core.IdentityGuard
  ( IdentityGuardWarning(..)
  , IdentityGuardCalibration(..)
  , defaultIdentityGuardCalibration
  , IdentityGuardReport(..)
  , buildIdentityGuardReportSimple
  , identityManifoldRadius
  ) where

import QxFx0.Types.IdentityGuard
  ( identityManifoldRadius
  , IdentityGuardWarning(..)
  , IdentityGuardCalibration(..)
  , defaultIdentityGuardCalibration
  , IdentityGuardReport(..)
  )

buildIdentityGuardReportSimple
  :: IdentityGuardCalibration
  -> Double -> Double -> Double -> Double
  -> IdentityGuardReport
buildIdentityGuardReportSimple calib prevAgency curAgency prevTension curTension =
  let agencyDelta = curAgency - prevAgency
      tensionDelta = curTension - prevTension
      absTensionDelta = abs tensionDelta
      warnings = []
               ++ [ GuardTransitionOutsideManifold | absTensionDelta > igcTensionDriftThreshold calib ]
               ++ [ GuardHighTensionDrift          | curTension > igcTensionCeiling calib ]
               ++ [ GuardAgencyCollapse             | curAgency < igcAgencyFloor calib ]
      withinBounds = null warnings
  in IdentityGuardReport
     { igrAgencyDelta  = agencyDelta
     , igrTensionDelta = tensionDelta
     , igrWithinBounds = withinBounds
     , igrWarnings     = warnings
     }
