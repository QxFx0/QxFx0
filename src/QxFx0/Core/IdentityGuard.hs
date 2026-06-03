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
  let nonFinite = any isNaN [prevAgency, curAgency, prevTension, curTension]
      agencyDelta = curAgency - prevAgency
      tensionDelta = curTension - prevTension
      absTensionDelta = abs tensionDelta
      warnings
        | nonFinite =
            [ GuardTransitionOutsideManifold
            , GuardHighTensionDrift
            , GuardAgencyCollapse
            ]
        | otherwise =
            [ GuardTransitionOutsideManifold | absTensionDelta > igcTensionDriftThreshold calib ]
            ++ [ GuardHighTensionDrift | curTension > igcTensionCeiling calib ]
            ++ [ GuardAgencyCollapse | curAgency < igcAgencyFloor calib ]
  in IdentityGuardReport
       { igrAgencyDelta = if nonFinite then 0 else agencyDelta
       , igrTensionDelta = if nonFinite then 0 else tensionDelta
       , igrWithinBounds = null warnings
       , igrWarnings = warnings
       }
