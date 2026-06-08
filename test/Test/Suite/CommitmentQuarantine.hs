{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.CommitmentQuarantine
Description : CTS-43 — unit and integration tests for commitment quarantine.

Unit tests: quarantineObservation writes to scsQuarantine, shared scsNextId,
retrieve isolation, quarantinedClaims accessor.
Migration tests: round-trip + back-compat (JSON without scsQuarantine decodes).
Integration tests: verify suppressed claims go to quarantine, not active.
-}
module Test.Suite.CommitmentQuarantine
  ( commitmentQuarantineTests
  ) where

import Test.HUnit (Test (..), assertEqual, assertBool)
import Data.Maybe (isJust, isNothing)
import qualified Data.HashMap.Strict as HashMap

import QxFx0.Core.CommitmentStoreAdmission
  ( CommitmentStoreAdmissionDecision (..)
  )
import QxFx0.Types.Observability (TruthContractStatus (..))
import QxFx0.Types.State.SemanticCommitment
  ( SemanticCommitmentStore (..)
  , emptySemanticCommitmentStore
  , FactualClaimPayload (..)
  , CommitmentId (..)
  , CommitmentOrigin (..)
  , TurnSeq (..)
  , quarantinedClaims
  )
import QxFx0.Semantic.Commitment (commitObservation, quarantineObservation)
import QxFx0.Semantic.Retrieve (retrieve)
import QxFx0.Types.State.System (ssSemanticCommitments, ssTruthContractStatus)
import QxFx0.Types.TurnProjection (tqpReplayTrace, trcSemanticCommitmentCount, trcQuarantinedCommitmentCount, trcCommitmentStoreDecision)
import QxFx0.Core.TurnPipeline.Protocol
  ( FinalizePrecommitBundle(..)
  , planFinalizePrecommit
  , resolveFinalizePrecommit
  , buildFinalizePrecommit
  )
import QxFx0.Core.PipelineIO (pipelineUpdateHistory)
import Test.Suite.TurnPipelineProtocol (withDeterministicEmbedding)
import Test.Support.TurnPipelineFixtures
  ( buildRenderedFixture
  , buildFinalizeFixtureWithState
  , forceAuthoritativeTurnArtifacts
  , testProtocolPipelineIO
  )

import Data.Aeson (encode, decode, ToJSON, FromJSON)
import Data.ByteString.Lazy (ByteString)

-- ---------------------------------------------------------------------------
-- Unit tests
-- ---------------------------------------------------------------------------

samplePayload :: FactualClaimPayload
samplePayload = FactualClaimPayload
  { fcpStatement  = "test statement"
  , fcpConfidence = 0.9
  , fcpOrigin     = OriginParser "test"
  , fcpTurnSeq    = TurnSeq 1
  , fcpDeps       = []
  }

unitQuarantineWritesToQuarantine :: Test
unitQuarantineWritesToQuarantine = TestLabel "quarantineObservation writes to scsQuarantine, not scsActive" $
  TestCase $ do
    let store0 = emptySemanticCommitmentStore
        store1 = quarantineObservation samplePayload store0
    assertEqual "active must be empty"
      HashMap.empty (scsActive store1)
    assertBool "quarantine must be non-empty"
      (not (HashMap.null (scsQuarantine store1)))

unitQuarantineSharedNextId :: Test
unitQuarantineSharedNextId = TestLabel "active and quarantine share scsNextId (no collision)" $
  TestCase $ do
    let store0 = emptySemanticCommitmentStore
        store1 = commitObservation samplePayload store0
        store2 = quarantineObservation (samplePayload { fcpStatement = "quarantined" }) store1
    assertEqual "active must have 1 entry"
      1 (HashMap.size (scsActive store2))
    assertEqual "quarantine must have 1 entry"
      1 (HashMap.size (scsQuarantine store2))
    assertEqual "nextId must have advanced by 2"
      3 (scsNextId store2)
    let activeId = head (HashMap.keys (scsActive store2))
        quarantineId = head (HashMap.keys (scsQuarantine store2))
    assertBool "active and quarantine ids must differ"
      (activeId /= quarantineId)

unitRetrieveDoesNotSeeQuarantine :: Test
unitRetrieveDoesNotSeeQuarantine = TestLabel "retrieve does not return quarantined claims" $
  TestCase $ do
    let store0 = emptySemanticCommitmentStore
        store1 = quarantineObservation (samplePayload { fcpStatement = "quarantined test" }) store0
        results = retrieve "test" store1
    assertEqual "retrieve must return empty list"
      [] results

unitQuarantinedClaimsAccessor :: Test
unitQuarantinedClaimsAccessor = TestLabel "quarantinedClaims returns quarantined payloads" $
  TestCase $ do
    let store0 = emptySemanticCommitmentStore
        store1 = quarantineObservation samplePayload store0
    assertEqual "quarantinedClaims must return 1 payload"
      [samplePayload] (quarantinedClaims store1)

-- ---------------------------------------------------------------------------
-- Migration tests (serialization round-trip + back-compat)
-- ---------------------------------------------------------------------------

unitRoundTripWithQuarantine :: Test
unitRoundTripWithQuarantine = TestLabel "round-trip: encode/decode store with quarantine" $
  TestCase $ do
    let store0 = emptySemanticCommitmentStore
        store1 = quarantineObservation samplePayload store0
        json = encode store1
        decoded = decode json
    assertEqual "decode . encode == id"
      (Just store1) decoded

unitBackCompatNoQuarantineKey :: Test
unitBackCompatNoQuarantineKey = TestLabel "back-compat: JSON without scsQuarantine decodes to empty" $
  TestCase $ do
    let oldJson :: ByteString
        oldJson = encode emptySemanticCommitmentStore
        -- Strip scsQuarantine key manually to simulate old JSON
        stripped = "{\"scsActive\":[],\"scsLineage\":[],\"scsContradictions\":[],\"scsNextId\":1}"
        decoded = decode stripped
    assertBool "decoded must be Just"
      (isJust decoded)
    let store = maybe emptySemanticCommitmentStore id decoded
    assertEqual "quarantine must be empty"
      HashMap.empty (scsQuarantine store)

-- ---------------------------------------------------------------------------
-- Integration tests
-- ---------------------------------------------------------------------------

integrationCanonicalActiveEmptyQuarantine :: Test
integrationCanonicalActiveEmptyQuarantine = TestLabel "CTS-43: canonical surface → active, quarantine empty" $
  TestCase $
    withDeterministicEmbedding $ do
      (ss, ti, ts, tp, ta) <- buildRenderedFixture "что такое свобода?"
      let taAuth = forceAuthoritativeTurnArtifacts ta
          precommitPlan = planFinalizePrecommit ss ti ts tp taAuth
      precommitResults <- resolveFinalizePrecommit testProtocolPipelineIO precommitPlan
      bundle <- buildFinalizePrecommit
                    (pipelineUpdateHistory testProtocolPipelineIO)
                    ss ti ts tp taAuth precommitPlan precommitResults
      let nextSs = fpbNextSs bundle
          trace = tqpReplayTrace (fpbProjection bundle)
          mStore = ssSemanticCommitments nextSs
      assertBool "store must be Just"
        (isJust mStore)
      let store = maybe emptySemanticCommitmentStore id mStore
      assertBool "active must be non-empty"
        (not (HashMap.null (scsActive store)))
      assertEqual "quarantine must be empty"
        HashMap.empty (scsQuarantine store)
      assertEqual "trace active count must be >0"
        True (trcSemanticCommitmentCount trace > 0)
      assertEqual "trace quarantine count must be 0"
        0 (trcQuarantinedCommitmentCount trace)

integrationDegradedQuarantineNotActive :: Test
integrationDegradedQuarantineNotActive = TestLabel "CTS-43: degraded surface → quarantine, not active" $
  TestCase $
    withDeterministicEmbedding $ do
      -- First turn: canonical (force authoritative artifacts)
      (ss, ti, ts, tp, ta) <- buildRenderedFixture "что такое свобода?"
      let taAuth = forceAuthoritativeTurnArtifacts ta
          precommitPlan = planFinalizePrecommit ss ti ts tp taAuth
      precommitResults <- resolveFinalizePrecommit testProtocolPipelineIO precommitPlan
      bundle1 <- buildFinalizePrecommit
                    (pipelineUpdateHistory testProtocolPipelineIO)
                    ss ti ts tp taAuth precommitPlan precommitResults
      let ss1 = fpbNextSs bundle1
          count1 = maybe 0 (HashMap.size . scsActive) (ssSemanticCommitments ss1)
      -- Second turn: degraded (normal fallback artifacts from the fixture)
      (_, _, _, _, _, bundle2) <- buildFinalizeFixtureWithState ss1 "расскажи подробнее"
      let nextSs = fpbNextSs bundle2
          trace = tqpReplayTrace (fpbProjection bundle2)
          mStore = ssSemanticCommitments nextSs
      assertBool "store must be Just"
        (isJust mStore)
      let store = maybe emptySemanticCommitmentStore id mStore
      assertEqual "trace decision must be CsaSuppress"
        CsaSuppress (trcCommitmentStoreDecision trace)
      -- Active count must not have grown from the degraded turn
      let count2 = HashMap.size (scsActive store)
      assertBool ("active count after degraded turn (" <> show count2 <> ") must not exceed count after first turn (" <> show count1 <> ")")
        (count2 <= count1)
      -- Quarantine must have grown
      assertBool "quarantine must be non-empty after degraded turn"
        (not (HashMap.null (scsQuarantine store)))
      assertEqual "trace quarantine count must be >0"
        True (trcQuarantinedCommitmentCount trace > 0)
      -- Retrieve must not see the quarantined claim (unit test covers
      -- pure isolation; here we just verify the quarantined set is non-empty)
      let quarantined = quarantinedClaims store
      assertBool "at least one quarantined claim must exist"
        (not (null quarantined))

commitmentQuarantineTests :: [Test]
commitmentQuarantineTests =
  [ unitQuarantineWritesToQuarantine
  , unitQuarantineSharedNextId
  , unitRetrieveDoesNotSeeQuarantine
  , unitQuarantinedClaimsAccessor
  , unitRoundTripWithQuarantine
  , unitBackCompatNoQuarantineKey
  , integrationCanonicalActiveEmptyQuarantine
  , integrationDegradedQuarantineNotActive
  ]
