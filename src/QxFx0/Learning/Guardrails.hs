{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Learning.Guardrails
Description : WP5 — persisted guardrail projection for the superseded external-learning contour.

This module is **diagnostic state, not a runtime enforcement point**.
The Phase 8/9 external-learning loop is permanently disabled
(`legacyExternalLearningEnabled = False` in `QxFx0.Learning.Loop`), so
no production path submits a proposal or issues an external action and
these counters are never updated by the turn pipeline.  They stay in
`SystemState` for state/JSON compatibility and are exercised only by
the disabled loop body and tests.

The functions below project the counters (rate limit, circuit breaker,
quarantine) into the legacy trace.  `externalActionGuardrailDecision`
is kind-agnostic by construction.  Governed autonomous learning
(`QxFx0.Learning.Autonomous`) is a separate contour and does not
consult this state.
-}
module QxFx0.Learning.Guardrails
  ( GuardrailState(..)
  , emptyGuardrailState
  , ExternalActionKind(..)
  , ExternalActionDecisionReason(..)
  , ExternalActionDecisionTrace(..)
  , ExternalActionDecision(..)
  , externalActionGuardrailDecision
  , proposalSubmissionGuardrailDecision
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

-- | Legacy-contour thresholds (hard-coded for determinism).  Diagnostic
-- only: no production path consults them while the legacy flag is off.
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

-- | Persisted counters for the superseded contour.  They are not
-- updated by the live turn pipeline (the legacy flag is off); the
-- initial value is what a production session actually carries.
emptyGuardrailState :: GuardrailState
emptyGuardrailState = GuardrailState
  { gsLastProposalTurn      = 0
  , gsProposalsThisWindow   = 0
  , gsWindowStart           = 0
  , gsConsecutiveRejections = 0
  , gsCooldownExpiry        = 0
  , gsQuarantine            = []
  }

-- | Diagnostic projection: would the legacy counters admit a proposal
-- at the given turn?  No production caller consults this as a gate;
-- the external-learning path is disabled.
proposalSubmissionGuardrailDecision :: GuardrailState -> Int -> Bool
proposalSubmissionGuardrailDecision gs turn =
  not (circuitBreakerOpen gs turn) && not (rateLimitExceeded gs turn)

-- | Diagnostic projection of the legacy guardrail state for an
-- external action.  The decision is kind-agnostic by design: the rate
-- limit and circuit breaker apply to every external action, and the
-- action kind is recorded only in the trace.  This function never
-- authorizes an external action by itself.
externalActionGuardrailDecision :: GuardrailState -> Int -> ExternalActionDecision
externalActionGuardrailDecision gs turn
  | circuitBreakerOpen gs turn = ExternalActionDenied DeniedGuardrailCircuitBreaker
  | rateLimitExceeded gs turn = ExternalActionDenied DeniedGuardrailRateLimit
  | otherwise = ExternalActionAllowed

-- | Record a new proposal submission, updating counters and window.
-- Only the disabled legacy body and tests call this; the live turn
-- pipeline leaves the state untouched.
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
-- and potentially opening the circuit breaker.  Legacy/test-only, as
-- 'recordProposalSubmission'.
recordRejection :: GuardrailState -> Int -> GuardrailState
recordRejection gs turn =
  let newRejections = gsConsecutiveRejections gs + 1
      newCooldown =
        if newRejections >= maxConsecutiveRejections
           then turn + cooldownTurns
           else gsCooldownExpiry gs
  in gs { gsConsecutiveRejections = newRejections, gsCooldownExpiry = newCooldown }

-- | Record an acceptance, resetting the rejection streak.
-- Legacy/test-only, as 'recordProposalSubmission'.
recordAcceptance :: GuardrailState -> GuardrailState
recordAcceptance gs = gs { gsConsecutiveRejections = 0 }

-- | Add a proposal to quarantine (done automatically by
-- 'recordProposalSubmission').  This function is exposed for
-- re-hydration from persisted state if needed; legacy/test-only.
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
-- Also prunes expired entries from the quarantine list; legacy/test-only.
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
