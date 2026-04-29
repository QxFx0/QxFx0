{-# LANGUAGE StrictData #-}

{-| Routing-phase and cascade aggregate records shared across routing modules. -}
module QxFx0.Core.TurnRouting.Types
  ( RoutingPhase(..)
  , FamilyCascade(..)
  ) where

import QxFx0.Core.IdentityGuard (IdentityGuardReport)
import QxFx0.Core.IdentitySignal (IdentitySignal)
import QxFx0.Core.PrincipledCore (PrincipledMode, PressureSignal)
import QxFx0.Core.R5Dynamics
  ( CoreDirective
  , EncounterMode
  , OrbitalMemory
  , OrbitalPhase
  )
import QxFx0.Types

data RoutingPhase = RoutingPhase
  { rpFamilyMerged :: !CanonicalMoveFamily
  , rpMPressure :: !(Maybe PressureSignal)
  , rpPrincipledModeResult :: !(Maybe PrincipledMode)
  , rpPressureBand :: !PressureBand
  , rpFromMs :: !MeaningState
  , rpToMs :: !MeaningState
  , rpChosenStrategy :: !ResponseStrategy
  , rpStrategyFamily :: !(Maybe CanonicalMoveFamily)
  , rpFamilyAfterStrategy :: !CanonicalMoveFamily
  , rpPreEgo :: !EgoState
  , rpPrevDirective :: !CoreDirective
  , rpOrbitalPhase :: !OrbitalPhase
  , rpEncounterMode :: !EncounterMode
  , rpUpdatedOrbital :: !OrbitalMemory
  , rpIdentitySignal0 :: !IdentitySignal
  }

data FamilyCascade = FamilyCascade
  { fcFamilyAfterIdentity :: !CanonicalMoveFamily
  , fcFamilyAfterNarrative :: !CanonicalMoveFamily
  , fcFamilyAfterIntuition :: !CanonicalMoveFamily
  , fcFamilyAfterPrincipled :: !CanonicalMoveFamily
  , fcGuardReportPre :: !IdentityGuardReport
  , fcFamilyAfterGuard :: !CanonicalMoveFamily
  , fcFamilyCascade :: !CanonicalMoveFamily
  , fcFinalFamily :: !CanonicalMoveFamily
  }
