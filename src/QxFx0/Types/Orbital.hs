{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE StrictData #-}
module QxFx0.Types.Orbital
  ( OrbitalPhase(..)
  , EncounterMode(..)
  , OrbitalMemory(..)
  , emptyOrbitalMemory
  , DirectiveMoveBias(..)
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import GHC.Generics (Generic)
import QxFx0.Types.Config.Orbital
  ( orbitalMemoryAvgAttractionDefault
  , orbitalMemoryAvgDistanceDefault
  , orbitalMemoryAvgRepulsionDefault
  , orbitalMemoryLastBoundaryBiasDefault
  , orbitalMemoryLastContactBiasDefault
  )

data OrbitalPhase
  = OrbitStable
  | OrbitCollapseRisk
  | OrbitFreezeRisk
  | OrbitCounterpressure
  | OrbitRecovery
  deriving stock (Show, Read, Eq, Ord, Generic, Bounded, Enum)
  deriving anyclass (NFData, ToJSON, FromJSON)

data EncounterMode
  = EncounterHolding
  | EncounterPressure
  | EncounterMirroring
  | EncounterCounterweight
  | EncounterRecovery
  | EncounterExploration
  deriving stock (Show, Read, Eq, Ord, Generic, Bounded, Enum)
  deriving anyclass (NFData, ToJSON, FromJSON)

data OrbitalMemory = OrbitalMemory
  { omCurrentPhase          :: !OrbitalPhase
  , omPhaseHistory          :: ![OrbitalPhase]
  , omEncounterHistory      :: ![EncounterMode]
  , omStableStreak          :: !Int
  , omCollapseStreak        :: !Int
  , omFreezeStreak          :: !Int
  , omCounterpressureStreak :: !Int
  , omRecoveryStreak        :: !Int
  , omAvgDistance           :: !Double
  , omAvgAttraction         :: !Double
  , omAvgRepulsion          :: !Double
  , omLastContactBias       :: !Double
  , omLastBoundaryBias      :: !Double
  } deriving stock (Show, Read, Eq, Generic)
  deriving anyclass (FromJSON, NFData, ToJSON)

emptyOrbitalMemory :: OrbitalMemory
emptyOrbitalMemory = OrbitalMemory
  { omCurrentPhase          = OrbitStable
  , omPhaseHistory          = []
  , omEncounterHistory      = []
  , omStableStreak          = 0
  , omCollapseStreak        = 0
  , omFreezeStreak          = 0
  , omCounterpressureStreak = 0
  , omRecoveryStreak        = 0
  , omAvgDistance           = orbitalMemoryAvgDistanceDefault
  , omAvgAttraction         = orbitalMemoryAvgAttractionDefault
  , omAvgRepulsion          = orbitalMemoryAvgRepulsionDefault
  , omLastContactBias       = orbitalMemoryLastContactBiasDefault
  , omLastBoundaryBias      = orbitalMemoryLastBoundaryBiasDefault
  }

data DirectiveMoveBias
  = BiasDirect
  | BiasLateral
  | BiasReframe
  | BiasContrast
  | BiasReflect
  deriving stock (Show, Read, Eq, Ord, Generic, Bounded, Enum)
  deriving anyclass (NFData, ToJSON, FromJSON)
