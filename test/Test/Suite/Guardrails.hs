{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.Guardrails
  ( guardrailsTests
  ) where

import Data.Aeson (decode, encode)
import Test.HUnit

import QxFx0.Learning.Calibration (CalibrationId(..))
import QxFx0.Learning.Guardrails

guardrailsTests :: [Test]
guardrailsTests =
  [ TestLabel "Guardrails record proposal submission" testRecordProposalSubmissionTracksQuarantine
  , TestLabel "Guardrails reset expired proposal window" testRecordProposalSubmissionResetsExpiredWindow
  , TestLabel "Guardrails rate limit blocks after max" testGuardrailRateLimitBlocksAfterMax
  , TestLabel "Guardrails circuit breaker opens after rejections" testGuardrailCircuitBreakerOpensAfterRejections
  , TestLabel "Guardrails acceptance resets rejection streak only" testGuardrailAcceptanceResetsRejectionStreak
  , TestLabel "Guardrails quarantine expires after minimum turns" testGuardrailQuarantineExpiresAfterMinTurns
  , TestLabel "Guardrails quarantine prunes stale entries" testGuardrailQuarantinePrunesStaleEntries
  , TestLabel "Guardrails state round-trips through JSON" testGuardrailStateRoundTripsThroughJson
  , TestLabel "Guardrails fresh state allows submission on turn 0" testCanSubmitOnTurnZeroWithEmptyState
  ]

testRecordProposalSubmissionTracksQuarantine :: Test
testRecordProposalSubmissionTracksQuarantine = TestCase $ do
  let proposalId = CalibrationId 7
      gs = recordProposalSubmission emptyGuardrailState 5 proposalId
  assertEqual "submission must record last proposal turn"
    5 (gsLastProposalTurn gs)
  assertEqual "submission must increment proposals in current window"
    1 (gsProposalsThisWindow gs)
  assertEqual "submission must quarantine the proposal id"
    [(5, proposalId)] (gsQuarantine gs)

testRecordProposalSubmissionResetsExpiredWindow :: Test
testRecordProposalSubmissionResetsExpiredWindow = TestCase $ do
  let proposalId = CalibrationId 3
      gs0 = emptyGuardrailState
        { gsWindowStart = 1
        , gsProposalsThisWindow = 2
        }
      gs1 = recordProposalSubmission gs0 12 proposalId
  assertEqual "expired window must restart at the new turn"
    12 (gsWindowStart gs1)
  assertEqual "expired window must restart proposal count at one"
    1 (gsProposalsThisWindow gs1)

testGuardrailRateLimitBlocksAfterMax :: Test
testGuardrailRateLimitBlocksAfterMax = TestCase $ do
  let gs = emptyGuardrailState
        { gsWindowStart = 1
        , gsProposalsThisWindow = 2
        }
  assertBool "must block when window is full"
    (not (canSubmitProposal gs 5))

testGuardrailCircuitBreakerOpensAfterRejections :: Test
testGuardrailCircuitBreakerOpensAfterRejections = TestCase $ do
  let gs0 = emptyGuardrailState { gsConsecutiveRejections = 2 }
      gs1 = recordRejection gs0 10
  assertEqual "rejection must increment consecutive rejection counter"
    3 (gsConsecutiveRejections gs1)
  assertEqual "threshold rejection must open cooldown window"
    15 (gsCooldownExpiry gs1)
  assertBool "circuit breaker must be open during cooldown"
    (not (canSubmitProposal gs1 11))

testGuardrailAcceptanceResetsRejectionStreak :: Test
testGuardrailAcceptanceResetsRejectionStreak = TestCase $ do
  let gs0 = emptyGuardrailState
        { gsConsecutiveRejections = 2
        , gsCooldownExpiry = 15
        }
      gs1 = recordAcceptance gs0
  assertEqual "acceptance must reset rejection streak"
    0 (gsConsecutiveRejections gs1)
  assertEqual "acceptance must not silently clear active cooldown"
    15 (gsCooldownExpiry gs1)

testGuardrailQuarantineExpiresAfterMinTurns :: Test
testGuardrailQuarantineExpiresAfterMinTurns = TestCase $ do
  let gs = emptyGuardrailState { gsQuarantine = [(5, CalibrationId 1)] }
  assertBool "quarantine must block before min turns"
    (not (isQuarantineExpired gs 6 (CalibrationId 1)))
  assertBool "quarantine must expire after min turns"
    (isQuarantineExpired gs 7 (CalibrationId 1))

testGuardrailQuarantinePrunesStaleEntries :: Test
testGuardrailQuarantinePrunesStaleEntries = TestCase $ do
  let gs0 = emptyGuardrailState
        { gsQuarantine = [(7, CalibrationId 1), (9, CalibrationId 2)] }
      gs1 = quarantineProposal gs0 10 (CalibrationId 3)
  assertEqual "stale quarantine entries must be pruned on insert"
    [(10, CalibrationId 3), (9, CalibrationId 2)]
    (gsQuarantine gs1)

testGuardrailStateRoundTripsThroughJson :: Test
testGuardrailStateRoundTripsThroughJson = TestCase $ do
  let gs = GuardrailState
        { gsLastProposalTurn = 7
        , gsProposalsThisWindow = 2
        , gsWindowStart = 3
        , gsConsecutiveRejections = 1
        , gsCooldownExpiry = 15
        , gsQuarantine = [(5, CalibrationId 1), (6, CalibrationId 2)]
        }
      decoded = decode (encode gs) :: Maybe GuardrailState
  assertEqual "guardrail state must round-trip through JSON"
    (Just gs) decoded

-- | Regression lock for ADR-0030 §5.2.  A previously shipped bug treated
-- @gsCooldownExpiry = 0@ (the empty-state sentinel meaning "no active
-- cooldown") as an open circuit on turn 0, blocking the first
-- 'canSubmitProposal' call of every fresh session.  This test pins the
-- contract that a fresh 'emptyGuardrailState' permits submissions on
-- turn 0 and on any later turn while no cooldown has been recorded.
testCanSubmitOnTurnZeroWithEmptyState :: Test
testCanSubmitOnTurnZeroWithEmptyState = TestCase $ do
  assertBool "fresh guardrail state must allow submission on turn 0"
    (canSubmitProposal emptyGuardrailState 0)
  assertBool "fresh guardrail state must allow submission on a later turn"
    (canSubmitProposal emptyGuardrailState 100)
  assertBool "fresh guardrail state must allow submission far ahead in time"
    (canSubmitProposal emptyGuardrailState 1000000)
