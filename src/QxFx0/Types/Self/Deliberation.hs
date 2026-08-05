{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Types.Self.Deliberation
  ( NarrativeTone(..)
  , Plan(..)
  , Agreement(..)
  , ReconcileRule(..)
  , DeliberationTrace(..)
  , Deliberation(..)
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import GHC.Generics (Generic)

import QxFx0.Types.Decision.Enums.Render (RenderStyle)
import QxFx0.Types.Domain.R5 (CanonicalMoveFamily)
import QxFx0.Types.Recovery (LocalRecoveryCause)
import QxFx0.Types.Self.Salience (SalienceDriver)

data NarrativeTone
  = NarrativeNeutral
  | NarrativeWarm
  | NarrativeFormal
  | NarrativeTerse
  | NarrativeRecovery
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data Plan = Plan
  { planFamily        :: !CanonicalMoveFamily
  , planRenderStyle   :: !RenderStyle
  , planRecoveryCause :: !(Maybe LocalRecoveryCause)
  , planNarrativeTone :: !NarrativeTone
  , planConfidence    :: !Double
  } deriving stock (Eq, Show)

data Agreement
  = Agree
  | DivergeOnFamily
  | DivergeOnStyle
  | DivergeOnRecovery
  | DivergeOnTone
  | DivergeMultiple
  deriving stock (Eq, Show, Bounded, Enum, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data ReconcileRule
  = RuleAgreement
  | RuleConatusOverride
  | RuleSalienceLead
  | RuleHolisticAdvantage
  | RuleFormalAdvantage
  | RuleTiedFallback
  deriving stock (Eq, Show, Bounded, Enum, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data DeliberationTrace = DeliberationTrace
  { dtAgreement      :: !Agreement
  , dtDivergence     :: !Double
  , dtRule           :: !ReconcileRule
  , dtSalienceDriver :: !SalienceDriver
  } deriving stock (Eq, Show)

data Deliberation = Deliberation
  { delibHolistic   :: !Plan
  , delibFormal     :: !Plan
  , delibReconciled :: !Plan
  , delibTrace      :: !DeliberationTrace
  } deriving stock (Eq, Show)
