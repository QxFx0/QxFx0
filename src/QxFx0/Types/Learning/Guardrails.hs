{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : QxFx0.Types.Learning.Guardrails
Description : Persisted guardrail state and trace types for the superseded external-learning contour.

'GuardrailState' stays in @SystemState@ for JSON compatibility; the
live turn pipeline does not update it (`legacyExternalLearningEnabled
= False` in `QxFx0.Learning.Loop`).  The JSON field names below are
part of the persisted-state contract and must not be renamed without a
state migration.
-}
module QxFx0.Types.Learning.Guardrails
  ( GuardrailState(..)
  , ExternalActionKind(..)
  , ExternalActionDecisionReason(..)
  , ExternalActionDecisionTrace(..)
  , ExternalActionDecision(..)
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON(..), ToJSON(..), object, withObject, (.:?), (.!=), (.=))
import Data.Text (Text)
import GHC.Generics (Generic)

import QxFx0.Types.Learning.Calibration (CalibrationId)

data ExternalActionKind = RequestDrivenExternalAction | ExploratoryExternalAction
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

data ExternalActionDecisionReason
  = AllowedRequestDriven
  | AllowedExploratory
  | DeniedGuardrailRateLimit
  | DeniedGuardrailCircuitBreaker
  | DeniedNoEligibleNeed
  | DeniedNoExecutableTool
  | DeniedNoActionSelected
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

data ExternalActionDecisionTrace = ExternalActionDecisionTrace
  { eadtKind    :: !ExternalActionKind
  , eadtReason  :: !ExternalActionDecisionReason
  , eadtNeedTag :: !(Maybe Text)
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

data ExternalActionDecision
  = ExternalActionAllowed
  | ExternalActionDenied !ExternalActionDecisionReason
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

data GuardrailState = GuardrailState
  { gsLastProposalTurn      :: !Int
  , gsProposalsThisWindow   :: !Int
  , gsWindowStart           :: !Int
  , gsConsecutiveRejections :: !Int
  , gsCooldownExpiry        :: !Int
  , gsQuarantine            :: ![(Int, CalibrationId)]
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON GuardrailState where
  toJSON s = object
    [ "lastProposalTurn" .= gsLastProposalTurn s
    , "proposalsThisWindow" .= gsProposalsThisWindow s
    , "windowStart" .= gsWindowStart s
    , "consecutiveRejections" .= gsConsecutiveRejections s
    , "cooldownExpiry" .= gsCooldownExpiry s
    , "quarantine" .= gsQuarantine s
    ]

instance FromJSON GuardrailState where
  parseJSON = withObject "GuardrailState" $ \o -> GuardrailState
    <$> o .:? "lastProposalTurn" .!= 0
    <*> o .:? "proposalsThisWindow" .!= 0
    <*> o .:? "windowStart" .!= 0
    <*> o .:? "consecutiveRejections" .!= 0
    <*> o .:? "cooldownExpiry" .!= 0
    <*> o .:? "quarantine" .!= []
