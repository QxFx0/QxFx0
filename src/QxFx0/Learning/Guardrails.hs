{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Learning.Guardrails
Description : WP5 — Rate limit, circuit breaker, and quarantine.

Prevents runaway learning loops by enforcing:

1. Rate limit — max proposals per sliding window.
2. Circuit breaker — cooldown after consecutive rejections.
3. Quarantine — proposals must sit for a minimum number of turns
   before they are eligible for verify / simulate.
-}
module QxFx0.Learning.Guardrails
  ( GuardrailState(..)
  , emptyGuardrailState
  , canSubmitProposal
  , recordProposalSubmission
  , recordRejection
  , recordAcceptance
  , quarantineProposal
  , isQuarantineExpired
  , maxProposalsPerWindow
  , proposalWindowTurns
  , maxConsecutiveRejections
  , cooldownTurns
  , minQuarantineTurns
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON(..), ToJSON(..), object, withObject, (.:), (.:?), (.!=), (.=))
import Data.Maybe (isJust)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

import QxFx0.Learning.Calibration (CalibrationId(..), CalibrationProposal(..))

-- | Guardrail configuration (hard-coded for determinism).
maxProposalsPerWindow :: Int
maxProposalsPerWindow = 2

proposalWindowTurns :: Int
proposalWindowTurns = 10

maxConsecutiveRejections :: Int
maxConsecutiveRejections = 3

cooldownTurns :: Int
cooldownTurns = 5

minQuarantineTurns :: Int
minQuarantineTurns = 2

-- | Mutable guardrail counters kept in 'SystemState'.
data GuardrailState = GuardrailState
  { gsLastProposalTurn      :: !Int
    -- ^ Turn of the most recent proposal submission.
  , gsProposalsThisWindow   :: !Int
    -- ^ Count of submissions within the current window.
  , gsWindowStart           :: !Int
    -- ^ Turn when the current window began.
  , gsConsecutiveRejections :: !Int
    -- ^ How many consecutive proposals were rejected.
  , gsCooldownExpiry        :: !Int
    -- ^ Turn after which the circuit breaker re-closes.
    --   0 = no active cooldown.
  , gsQuarantine            :: ![(Int, CalibrationId)]
    -- ^ (submittedTurn, proposalId) pairs still in quarantine.
  }
  deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON GuardrailState where
  toJSON s = object
    [ "lastProposalTurn"      .= gsLastProposalTurn s
    , "proposalsThisWindow"   .= gsProposalsThisWindow s
    , "windowStart"           .= gsWindowStart s
    , "consecutiveRejections" .= gsConsecutiveRejections s
    , "cooldownExpiry"        .= gsCooldownExpiry s
    , "quarantine"            .= gsQuarantine s
    ]

instance FromJSON GuardrailState where
  parseJSON = withObject "GuardrailState" $ \o ->
    GuardrailState
      <$> o .:? "lastProposalTurn"      .!= 0
      <*> o .:? "proposalsThisWindow"   .!= 0
      <*> o .:? "windowStart"           .!= 0
      <*> o .:? "consecutiveRejections" .!= 0
      <*> o .:? "cooldownExpiry"        .!= 0
      <*> o .:? "quarantine"            .!= []

emptyGuardrailState :: GuardrailState
emptyGuardrailState = GuardrailState
  { gsLastProposalTurn      = 0
  , gsProposalsThisWindow   = 0
  , gsWindowStart           = 0
  , gsConsecutiveRejections = 0
  , gsCooldownExpiry        = 0
  , gsQuarantine            = []
  }

-- | Predicate: can a new proposal be submitted at the given turn?
canSubmitProposal :: GuardrailState -> Int -> Bool
canSubmitProposal gs turn =
  not (circuitBreakerOpen gs turn) && not (rateLimitExceeded gs turn)

-- | Record a new proposal submission, updating counters and window.
recordProposalSubmission :: GuardrailState -> Int -> CalibrationId -> GuardrailState
recordProposalSubmission gs turn proposalId =
  let (newWindowStart, newWindowCount) =
        if turn - gsWindowStart gs > proposalWindowTurns
           then (turn, 1)
           else (gsWindowStart gs, gsProposalsThisWindow gs + 1)
  in gs
       { gsLastProposalTurn    = turn
       , gsProposalsThisWindow = newWindowCount
       , gsWindowStart         = newWindowStart
       , gsQuarantine          = (turn, proposalId) : gsQuarantine gs
       }

-- | Record a rejection, bumping the consecutive-rejection counter
-- and potentially opening the circuit breaker.
recordRejection :: GuardrailState -> Int -> GuardrailState
recordRejection gs turn =
  let newRejections = gsConsecutiveRejections gs + 1
      newCooldown =
        if newRejections >= maxConsecutiveRejections
           then turn + cooldownTurns
           else gsCooldownExpiry gs
  in gs { gsConsecutiveRejections = newRejections, gsCooldownExpiry = newCooldown }

-- | Record an acceptance, resetting the rejection streak.
recordAcceptance :: GuardrailState -> GuardrailState
recordAcceptance gs = gs { gsConsecutiveRejections = 0 }

-- | Add a proposal to quarantine (done automatically by
-- 'recordProposalSubmission').  This function is exposed for
-- re-hydration from persisted state if needed.
quarantineProposal :: GuardrailState -> Int -> CalibrationId -> GuardrailState
quarantineProposal gs turn proposalId =
  gs { gsQuarantine = (turn, proposalId) : gsQuarantine gs }

-- | Check whether a specific proposal has completed its quarantine.
isQuarantineExpired :: GuardrailState -> Int -> CalibrationId -> Bool
isQuarantineExpired gs turn proposalId =
  case lookup proposalId (map swap (gsQuarantine gs)) of
    Nothing    -> False
    Just subTurn -> turn - subTurn >= minQuarantineTurns
  where
    swap (a, b) = (b, a)

-- Internal helpers

circuitBreakerOpen :: GuardrailState -> Int -> Bool
circuitBreakerOpen gs turn = turn <= gsCooldownExpiry gs

rateLimitExceeded :: GuardrailState -> Int -> Bool
rateLimitExceeded gs turn =
  let inCurrentWindow = turn - gsWindowStart gs <= proposalWindowTurns
  in inCurrentWindow && gsProposalsThisWindow gs >= maxProposalsPerWindow
