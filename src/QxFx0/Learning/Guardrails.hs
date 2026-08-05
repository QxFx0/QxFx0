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
  , ExternalActionKind(..)
  , ExternalActionDecisionReason(..)
  , ExternalActionDecisionTrace(..)
  , ExternalActionDecision(..)
  , canIssueExternalAction
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
  , maxQuarantineEntries
  ) where

import QxFx0.Learning.Calibration (CalibrationId(..))
import QxFx0.Types.Learning.Guardrails

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

-- | Maximum size of quarantine list (bounded rotation, newest first).
maxQuarantineEntries :: Int
maxQuarantineEntries = 500

-- | Mutable guardrail counters kept in 'SystemState'.
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

canIssueExternalAction :: GuardrailState -> ExternalActionKind -> Int -> ExternalActionDecision
canIssueExternalAction gs _kind turn
  | circuitBreakerOpen gs turn = ExternalActionDenied DeniedGuardrailCircuitBreaker
  | rateLimitExceeded gs turn = ExternalActionDenied DeniedGuardrailRateLimit
  | otherwise = ExternalActionAllowed

-- | Record a new proposal submission, updating counters and window.
recordProposalSubmission :: GuardrailState -> Int -> CalibrationId -> GuardrailState
recordProposalSubmission gs turn proposalId =
  let (newWindowStart, newWindowCount) =
        if turn - gsWindowStart gs > proposalWindowTurns
           then (turn, 1)
           else (gsWindowStart gs, gsProposalsThisWindow gs + 1)
      quarantine' = take maxQuarantineEntries ((turn, proposalId) : gsQuarantine gs)
   in gs
        { gsLastProposalTurn    = turn
        , gsProposalsThisWindow = newWindowCount
        , gsWindowStart         = newWindowStart
        , gsQuarantine          = quarantine'
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
  -- Prune entries that have already completed their quarantine window (stale,
  -- relative to the current insert turn) BEFORE size-capping. Without this,
  -- the list only ever truncated by size (maxQuarantineEntries) and expired
  -- entries lingered, so a re-quarantine could see a stale slot as still
  -- active. Size cap is retained as the OOM backstop.
  let fresh = filter (\(subTurn, _) -> turn - subTurn < minQuarantineTurns) (gsQuarantine gs)
  in gs { gsQuarantine = take maxQuarantineEntries ((turn, proposalId) : fresh) }

-- | Check whether a specific proposal has completed its quarantine.
-- Also prunes expired entries from the quarantine list.
isQuarantineExpired :: GuardrailState -> Int -> CalibrationId -> Bool
isQuarantineExpired gs turn proposalId =
  case lookup proposalId (map swap (gsQuarantine gs)) of
    Nothing    -> True
    Just subTurn -> turn - subTurn >= minQuarantineTurns
  where
    swap (a, b) = (b, a)

-- Internal helpers

circuitBreakerOpen :: GuardrailState -> Int -> Bool
circuitBreakerOpen gs turn = gsCooldownExpiry gs > 0 && turn <= gsCooldownExpiry gs

rateLimitExceeded :: GuardrailState -> Int -> Bool
rateLimitExceeded gs turn =
  let inCurrentWindow = turn - gsWindowStart gs <= proposalWindowTurns
  in inCurrentWindow && gsProposalsThisWindow gs >= maxProposalsPerWindow
