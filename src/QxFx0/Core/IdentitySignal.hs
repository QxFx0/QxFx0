{-# LANGUAGE DerivingStrategies, OverloadedStrings, StrictData, DeriveGeneric, DeriveAnyClass #-}
{-| Identity-signal model and default signal extraction from system state. -}
module QxFx0.Core.IdentitySignal
  ( IdentitySignal(..)
  , defaultIdentitySignal
  , buildIdentitySignalSimple
  ) where

import GHC.Generics (Generic)
import Control.DeepSeq (NFData)
import Data.Aeson (ToJSON, FromJSON)

import QxFx0.Core.R5Dynamics (OrbitalPhase(..), EncounterMode(..), CoreDirective(..), DirectiveMoveBias(..))
import QxFx0.Types (CanonicalMoveFamily(..), IllocutionaryForce(..), SemanticLayer(..), Register(..))
import QxFx0.Types.Thresholds
  ( directiveDefaultBoundaryBias
  , directiveDefaultContactBias
  )

data IdentitySignal = IdentitySignal
  { isOrbitalPhase      :: !OrbitalPhase
  , isEncounterMode     :: !EncounterMode
  , isContactStrength   :: !Double
  , isBoundaryStrength  :: !Double
  , isAbstractionBudget :: !Int
  , isMoveBias          :: !DirectiveMoveBias
  , isRegister          :: !Register
  , isNeedLayer         :: !SemanticLayer
  , isFamily            :: !CanonicalMoveFamily
  , isForce             :: !IllocutionaryForce
  } deriving stock (Show, Read, Eq, Generic)
  deriving anyclass (FromJSON, NFData, ToJSON)

defaultIdentitySignal :: IdentitySignal
defaultIdentitySignal = IdentitySignal
  { isOrbitalPhase      = OrbitRecovery
  , isEncounterMode     = EncounterRecovery
  , isContactStrength   = directiveDefaultContactBias
  , isBoundaryStrength  = directiveDefaultBoundaryBias
  , isAbstractionBudget = 1
  , isMoveBias          = BiasLateral
  , isRegister          = Neutral
  , isNeedLayer         = ContentLayer
  , isFamily            = CMGround
  , isForce             = IFAssert
  }

buildIdentitySignalSimple
  :: OrbitalPhase -> EncounterMode -> CoreDirective
  -> Register -> SemanticLayer -> CanonicalMoveFamily -> IllocutionaryForce
  -> IdentitySignal
buildIdentitySignalSimple phase encounter directive reg needLayer fam force =
  IdentitySignal
    { isOrbitalPhase      = phase
    , isEncounterMode     = encounter
    , isContactStrength   = cdContactBias directive
    , isBoundaryStrength  = cdBoundaryBias directive
    , isAbstractionBudget = cdAbstractionBudget directive
    , isMoveBias          = cdMoveBias directive
    , isRegister          = reg
    , isNeedLayer         = needLayer
    , isFamily            = fam
    , isForce             = force
    }
