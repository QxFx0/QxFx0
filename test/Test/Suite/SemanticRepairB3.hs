{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.SemanticRepairB3
  ( semanticRepairB3Tests
  ) where

import Test.HUnit (Test(..), assertBool, assertEqual, assertFailure)

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.HashMap.Strict as HashMap

import QxFx0.Semantic.Content
import QxFx0.Semantic.Commitment (commitObservation)
import QxFx0.Semantic.Retrieve (detectCommitmentEngagement)
import QxFx0.Types.State.SemanticCommitment
import QxFx0.Types.Domain.Atoms (AtomSet(..), Register(..))

-- ============================================================================
-- Gate 3: Challenge → engagement → revision
-- ============================================================================

-- | Gate 3: a domain-bearing commitment for 'свобода' is detectable by
-- 'detectCommitmentEngagement' when a later turn mentions the same topic.
testGate3CommitmentEngagementForCoveredTopic :: Test
testGate3CommitmentEngagementForCoveredTopic =
  TestLabel "B3 Gate 3: domain-bearing commitment for 'свобода' is engaged" $
    TestCase $ do
      let topic = "свобода"
          Just dc = lookupDefinitionContent topic
          preds = map spRu (dcPredicates dc)
          -- Create a commitment with domain-bearing predicates (as
          -- anchorToFactualClaim now does for covered topics)
          stmt = "Dialogue channel: define. Topic: " <> topic <> ". "
                 <> T.intercalate " " preds
                 <> " (established at turn 1)"
          payload = FactualClaimPayload
            { fcpStatement = stmt
            , fcpConfidence = 0.5
            , fcpOrigin = OriginParser "anchor:define"
            , fcpTurnSeq = TurnSeq 1
            , fcpDeps = []
            }
          store0 = emptySemanticCommitmentStore
          (store1, _cid) = commitObservation payload store0
          -- Simulate a later turn mentioning 'свобода' (challenge)
          engagement = detectCommitmentEngagement store1 "свобода" emptyAtomSet
      assertBool "should engage ≥1 commitment"
                 (length (ceEngaged engagement) >= 1)
      assertBool "engagement should find the свобода commitment"
                 (not (null (ceEngaged engagement)))

-- | Gate 3: a domain-bearing commitment for 'сознание' is engaged when
-- a later turn challenges it.
testGate3CommitmentEngagementForConsciousness :: Test
testGate3CommitmentEngagementForConsciousness =
  TestLabel "B3 Gate 3: commitment for 'сознание' is engaged on challenge" $
    TestCase $ do
      let topic = "сознание"
          Just dc = lookupDefinitionContent topic
          preds = map spRu (dcPredicates dc)
          stmt = "Dialogue channel: define. Topic: " <> topic <> ". "
                 <> T.intercalate " " preds
                 <> " (established at turn 1)"
          payload = FactualClaimPayload
            { fcpStatement = stmt
            , fcpConfidence = 0.5
            , fcpOrigin = OriginParser "anchor:define"
            , fcpTurnSeq = TurnSeq 1
            , fcpDeps = []
            }
          store0 = emptySemanticCommitmentStore
          (store1, _cid) = commitObservation payload store0
          engagement = detectCommitmentEngagement store1 "сознание" emptyAtomSet
      assertBool "should engage ≥1 commitment"
                 (length (ceEngaged engagement) >= 1)

-- | Gate 3: prior definition claim content is findable by topic words.
-- This is the precondition for repair — if the engagement can't find
-- the prior claim, repair can't reference it.
testGate3PriorClaimFindableByTopicWords :: Test
testGate3PriorClaimFindableByTopicWords =
  TestLabel "B3 Gate 3: prior claim findable by topic words (all covered topics)" $
    TestCase $ do
      let failures = [ topic
                     | topic <- coveredTopics
                     , let Just dc = lookupDefinitionContent topic
                           preds = map spRu (dcPredicates dc)
                           stmt = "Dialogue channel: define. Topic: " <> topic <> ". "
                                  <> T.intercalate " " preds
                                  <> " (established at turn 1)"
                           payload = FactualClaimPayload
                             { fcpStatement = stmt
                             , fcpConfidence = 0.5
                             , fcpOrigin = OriginParser "anchor:define"
                             , fcpTurnSeq = TurnSeq 1
                             , fcpDeps = []
                             }
                           store0 = emptySemanticCommitmentStore
                           (store1, _) = commitObservation payload store0
                           engagement = detectCommitmentEngagement store1 topic emptyAtomSet
                     , null (ceEngaged engagement)
                     ]
      assertBool ("Topics where prior claim is not found: " <> show failures)
                 (null failures)

-- | Gate 3: the old-style anchor (without domain content) does NOT engage
-- for philosophical topics — proving the M4-002 change is load-bearing.
testGate3OldAnchorDoesNotEngage :: Test
testGate3OldAnchorDoesNotEngage =
  TestLabel "B3 Gate 3: old-style anchor (channel-only) does not engage for 'свобода'" $
    TestCase $ do
      let -- This is what anchorToFactualClaim used to produce before M4-002
          stmt = "Dialogue channel: define (established at turn 1)"
          payload = FactualClaimPayload
            { fcpStatement = stmt
            , fcpConfidence = 0.5
            , fcpOrigin = OriginParser "anchor:define"
            , fcpTurnSeq = TurnSeq 1
            , fcpDeps = []
            }
          store0 = emptySemanticCommitmentStore
          (store1, _) = commitObservation payload store0
          engagement = detectCommitmentEngagement store1 "свобода" emptyAtomSet
      assertBool "old-style anchor should NOT engage for 'свобода'"
                 (null (ceEngaged engagement))

-- ============================================================================
-- Gate 4: Multi-turn session, commitment persistence
-- ============================================================================

-- | Gate 4: commitments accumulate across multiple definition turns for
-- different covered topics. No silent loss.
testGate4MultiTurnCommitmentAccumulation :: Test
testGate4MultiTurnCommitmentAccumulation =
  TestLabel "B3 Gate 4: commitments accumulate across 3 covered-topic turns" $
    TestCase $ do
      let topics = ["свобода", "истина", "сознание"]
          payloads = map (\(topic, turn) ->
            let Just dc = lookupDefinitionContent topic
                preds = map spRu (dcPredicates dc)
                stmt = "Dialogue channel: define. Topic: " <> topic <> ". "
                       <> T.intercalate " " preds
                       <> " (established at turn " <> T.pack (show turn) <> ")"
            in FactualClaimPayload
              { fcpStatement = stmt
              , fcpConfidence = 0.5
              , fcpOrigin = OriginParser "anchor:define"
              , fcpTurnSeq = TurnSeq turn
              , fcpDeps = []
              }
            ) (zip topics [1..])
          store0 = emptySemanticCommitmentStore
          store1 = foldr (\payload s -> fst (commitObservation payload s)) store0 payloads
          activeCount = HashMap.size (scsActive store1)
      assertEqual "should have 3 active commitments" 3 activeCount

-- | Gate 4: a 10-turn session accumulates commitments and they persist.
testGate4TenTurnSessionPersistence :: Test
testGate4TenTurnSessionPersistence =
  TestLabel "B3 Gate 4: 10-turn session — commitments persist, no silent loss" $
    TestCase $ do
      let topics = ["свобода", "произвол", "ответственность", "истина", "мнение"
                   ,"память","воспоминание","сознание","самосознание","свобода"]
          -- 10 turns, each creating a commitment for a covered topic
          payloads = map (\(topic, turn) ->
            let Just dc = lookupDefinitionContent topic
                preds = map spRu (dcPredicates dc)
                stmt = "Dialogue channel: define. Topic: " <> topic <> ". "
                       <> T.intercalate " " preds
                       <> " (established at turn " <> T.pack (show turn) <> ")"
            in FactualClaimPayload
              { fcpStatement = stmt
              , fcpConfidence = 0.5
              , fcpOrigin = OriginParser "anchor:define"
              , fcpTurnSeq = TurnSeq turn
              , fcpDeps = []
              }
            ) (zip topics [1..])
          store0 = emptySemanticCommitmentStore
          store1 = foldr (\payload s -> fst (commitObservation payload s)) store0 payloads
          activeCount = HashMap.size (scsActive store1)
      assertBool "should have ≥1 active commitment after 10 turns"
                 (activeCount >= 1)
      assertBool "should have ≥9 active commitments (some topics repeat)"
                 (activeCount >= 9)
      -- Verify that a challenge on 'свобода' still finds the prior commitment
      let engagement = detectCommitmentEngagement store1 "свобода" emptyAtomSet
      assertBool "challenge on 'свобода' should engage prior commitment after 10 turns"
                 (not (null (ceEngaged engagement)))

-- | Gate 4: commitments are domain-bearing (not just "channel: define").
testGate4CommitmentsAreDomainBearing :: Test
testGate4CommitmentsAreDomainBearing =
  TestLabel "B3 Gate 4: commitments carry domain content (not just channel)" $
    TestCase $ do
      let topic = "свобода"
          Just dc = lookupDefinitionContent topic
          preds = map spRu (dcPredicates dc)
          stmt = "Dialogue channel: define. Topic: " <> topic <> ". "
                 <> T.intercalate " " preds
                 <> " (established at turn 1)"
          payload = FactualClaimPayload
            { fcpStatement = stmt
            , fcpConfidence = 0.5
            , fcpOrigin = OriginParser "anchor:define"
            , fcpTurnSeq = TurnSeq 1
            , fcpDeps = []
            }
      -- The statement must contain domain-bearing words from predicates
      assertBool "statement should contain 'выбор' (from predicates)"
                 ("выбор" `T.isInfixOf` fcpStatement payload)
      assertBool "statement should contain 'ответственность' (from predicates)"
                 ("ответственность" `T.isInfixOf` fcpStatement payload)
      assertBool "statement should contain topic 'свобода'"
                 ("свобода" `T.isInfixOf` fcpStatement payload)

-- ============================================================================
-- Helpers
-- ============================================================================

emptyAtomSet :: AtomSet
emptyAtomSet = AtomSet [] 0.0 Neutral

-- ============================================================================
-- Test group
-- ============================================================================

semanticRepairB3Tests :: [Test]
semanticRepairB3Tests =
  [ testGate3CommitmentEngagementForCoveredTopic
  , testGate3CommitmentEngagementForConsciousness
  , testGate3PriorClaimFindableByTopicWords
  , testGate3OldAnchorDoesNotEngage
  , testGate4MultiTurnCommitmentAccumulation
  , testGate4TenTurnSessionPersistence
  , testGate4CommitmentsAreDomainBearing
  ]
