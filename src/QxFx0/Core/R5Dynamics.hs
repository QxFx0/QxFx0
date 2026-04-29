{-# LANGUAGE DerivingStrategies, OverloadedStrings, StrictData, DeriveGeneric, DeriveAnyClass #-}
{-| Orbital/encounter dynamics and directive steering for turn routing. -}
module QxFx0.Core.R5Dynamics
  ( OrbitalPhase(..)
  , EncounterMode(..)
  , OrbitalMemory(..)
  , emptyOrbitalMemory
  , DirectiveMoveBias(..)
  , CoreDirective(..)
  , defaultCoreDirective
  , updateOrbitalMemorySimple
  , classifyOrbitalPhaseSimple
  , classifyEncounterModeSimple
  , steerDirectiveWithOrbitalSimple
  ) where

import GHC.Generics (Generic)
import Control.DeepSeq (NFData)
import Data.Aeson (ToJSON, FromJSON)
import QxFx0.Types.Orbital
  ( OrbitalPhase(..)
  , EncounterMode(..)
  , OrbitalMemory(..)
  , emptyOrbitalMemory
  , DirectiveMoveBias(..)
  )
import QxFx0.Types.Thresholds
  ( clamp01
  , encounterMirroringTensionThreshold
  , orbitalCounterpressureThreshold
  , orbitalHighRiskThreshold
  , orbitalHistoryLimit
  , orbitalDistEstCollapseRisk
  , orbitalDistEstFreezeRisk
  , orbitalDistEstCounterpressure
  , orbitalDistEstRecovery
  , orbitalDistEstStable
  , orbitalEmaAlpha
  , orbitalContactBoostRecovery
  , orbitalContactBoostFreezeRisk
  , orbitalContactPenaltyCounterpressure
  , orbitalBoundaryBoostCollapseRisk
  , orbitalBoundaryBoostCounterpressure
  , orbitalBoundaryPenaltyRecovery
  , directiveDefaultAssertionForce
  , directiveDefaultBoundaryBias
  , directiveDefaultContactBias
  , directiveDefaultCounterpressureStrength
  , directiveDefaultStabilityUnderTension
  )

data CoreDirective = CoreDirective
  { cdContactBias             :: !Double
  , cdBoundaryBias            :: !Double
  , cdAbstractionBudget       :: !Int
  , cdAssertionForce          :: !Double
  , cdCounterpressureStrength :: !Double
  , cdStabilityUnderTension   :: !Double
  , cdMoveBias                :: !DirectiveMoveBias
  , cdMaxWordsHint            :: !Int
  , cdAllowCounterweight      :: !Bool
  , cdAllowMeaningLift        :: !Bool
  } deriving stock (Show, Read, Eq, Generic)
  deriving anyclass (FromJSON, NFData, ToJSON)

defaultCoreDirective :: CoreDirective
defaultCoreDirective = CoreDirective
  { cdContactBias             = directiveDefaultContactBias
  , cdBoundaryBias            = directiveDefaultBoundaryBias
  , cdAbstractionBudget       = 1
  , cdAssertionForce          = directiveDefaultAssertionForce
  , cdCounterpressureStrength = directiveDefaultCounterpressureStrength
  , cdStabilityUnderTension   = directiveDefaultStabilityUnderTension
  , cdMoveBias                = BiasLateral
  , cdMaxWordsHint            = 48
  , cdAllowCounterweight      = True
  , cdAllowMeaningLift        = True
  }

-- | Classify orbital phase from collapse/freeze risk signals.
classifyOrbitalPhaseSimple :: Double -> Double -> OrbitalPhase
classifyOrbitalPhaseSimple collapseRisk freezeRisk
  | collapseRisk > orbitalHighRiskThreshold = OrbitCollapseRisk
  | freezeRisk   > orbitalHighRiskThreshold = OrbitFreezeRisk
  | collapseRisk > orbitalCounterpressureThreshold = OrbitCounterpressure
  | freezeRisk   > orbitalCounterpressureThreshold = OrbitRecovery
  | otherwise           = OrbitStable

-- | Classify encounter mode from orbital phase and current tension.
classifyEncounterModeSimple :: OrbitalPhase -> Double -> EncounterMode
classifyEncounterModeSimple OrbitCollapseRisk _    = EncounterPressure
classifyEncounterModeSimple OrbitFreezeRisk _       = EncounterHolding
classifyEncounterModeSimple OrbitCounterpressure _  = EncounterCounterweight
classifyEncounterModeSimple OrbitRecovery _         = EncounterRecovery
classifyEncounterModeSimple OrbitStable tension
  | tension > encounterMirroringTensionThreshold = EncounterMirroring
  | otherwise        = EncounterExploration

-- | Update rolling orbital memory with the latest phase/encounter outcome.
updateOrbitalMemorySimple :: OrbitalMemory -> OrbitalPhase -> EncounterMode -> CoreDirective -> OrbitalMemory
updateOrbitalMemorySimple om phase encounter directive =
  let addPhase p hist = take orbitalHistoryLimit (p : hist)
      addEnc e hist = take orbitalHistoryLimit (e : hist)
      streakFor = case phase of
        OrbitStable          -> omStableStreak om + 1
        OrbitCollapseRisk    -> omCollapseStreak om + 1
        OrbitFreezeRisk      -> omFreezeStreak om + 1
        OrbitCounterpressure -> omCounterpressureStreak om + 1
        OrbitRecovery        -> omRecoveryStreak om + 1
      resetOther = case phase of
        OrbitStable          -> om { omCollapseStreak = 0, omFreezeStreak = 0, omCounterpressureStreak = 0, omRecoveryStreak = 0 }
        OrbitCollapseRisk    -> om { omStableStreak = 0, omFreezeStreak = 0, omCounterpressureStreak = 0, omRecoveryStreak = 0 }
        OrbitFreezeRisk      -> om { omStableStreak = 0, omCollapseStreak = 0, omCounterpressureStreak = 0, omRecoveryStreak = 0 }
        OrbitCounterpressure -> om { omStableStreak = 0, omCollapseStreak = 0, omFreezeStreak = 0, omRecoveryStreak = 0 }
        OrbitRecovery        -> om { omStableStreak = 0, omCollapseStreak = 0, omFreezeStreak = 0, omCounterpressureStreak = 0 }
      om' = resetOther
      distEst = case phase of
        OrbitCollapseRisk    -> orbitalDistEstCollapseRisk
        OrbitFreezeRisk      -> orbitalDistEstFreezeRisk
        OrbitCounterpressure -> orbitalDistEstCounterpressure
        OrbitRecovery        -> orbitalDistEstRecovery
        OrbitStable          -> orbitalDistEstStable
      alpha = orbitalEmaAlpha
      newDist = alpha * distEst + (1.0 - alpha) * omAvgDistance om
      newAttr = alpha * cdContactBias directive + (1.0 - alpha) * omAvgAttraction om
      newRepl = alpha * cdBoundaryBias directive + (1.0 - alpha) * omAvgRepulsion om
      setPhaseStreak = case phase of
        OrbitStable          -> om' { omStableStreak = streakFor }
        OrbitCollapseRisk    -> om' { omCollapseStreak = streakFor }
        OrbitFreezeRisk      -> om' { omFreezeStreak = streakFor }
        OrbitCounterpressure -> om' { omCounterpressureStreak = streakFor }
        OrbitRecovery        -> om' { omRecoveryStreak = streakFor }
  in setPhaseStreak
     { omCurrentPhase     = phase
     , omPhaseHistory     = addPhase phase (omPhaseHistory om)
     , omEncounterHistory = addEnc encounter (omEncounterHistory om)
     , omAvgDistance       = newDist
     , omAvgAttraction     = newAttr
     , omAvgRepulsion      = newRepl
     , omLastContactBias   = cdContactBias directive
     , omLastBoundaryBias  = cdBoundaryBias directive
     }

-- | Steer directive contact/boundary biases from current orbital phase.
steerDirectiveWithOrbitalSimple :: OrbitalMemory -> CoreDirective -> CoreDirective
steerDirectiveWithOrbitalSimple om d =
  let contactBoost = case omCurrentPhase om of
        OrbitRecovery        -> orbitalContactBoostRecovery
        OrbitFreezeRisk      -> orbitalContactBoostFreezeRisk
        OrbitCounterpressure -> orbitalContactPenaltyCounterpressure
        _                    -> 0.0
      boundaryBoost = case omCurrentPhase om of
        OrbitCollapseRisk    -> orbitalBoundaryBoostCollapseRisk
        OrbitCounterpressure -> orbitalBoundaryBoostCounterpressure
        OrbitRecovery        -> orbitalBoundaryPenaltyRecovery
        _                    -> 0.0
  in d { cdContactBias = clamp01 (cdContactBias d + contactBoost)
        , cdBoundaryBias = clamp01 (cdBoundaryBias d + boundaryBoost)
        }
