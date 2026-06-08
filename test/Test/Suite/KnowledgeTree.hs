{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.KnowledgeTree
  ( knowledgeTreeTests
  ) where

import Data.Aeson (decode, encode)
import qualified Data.ByteString.Lazy.Char8 as BL
import Data.List (foldl')
import qualified Data.Map.Strict as M
import Data.Text (Text)
import qualified Data.Text as T
import Test.HUnit

import QxFx0.Learning.KnowledgeTree

knowledgeTreeTests :: [Test]
knowledgeTreeTests =
  [ TestLabel "KnowledgeTree graft creates branch and count" testGraftFruitCreatesBranchAndCount
  , TestLabel "KnowledgeTree quarantine tracks anti-dogmatism" testQuarantineFruitTracksAntiDogmatism
  , TestLabel "KnowledgeTree promotes only ripe authoritative non-negative fruit" testPromoteFromQuarantinePromotesOnlyNonNegativeFruit
  , TestLabel "KnowledgeTree prunes invalid fruit and authoritative-negative quarantine junk" testPruneFruitsDropsInvalidAndNegative
  , TestLabel "KnowledgeTree prunes persistently unhealthy branches" testPruneBranchesDropsPersistentlyUnhealthy
  , TestLabel "KnowledgeTree root stress reflects quarantine and decay" testRootStressSignalReflectsQuarantineAndDecay
  , TestLabel "KnowledgeTree known-term check uses word and proposition fallback" testKnownTermChecksWordAndFallbackProposition
  , TestLabel "KnowledgeTree round-trips through JSON" testKnowledgeTreeRoundTripsJson
  , TestLabel "KnowledgeTree prune drains unvalidated bulk quarantine" testPruneFruitsCleansUnvalidatedQuarantineUnderBulkInsertion
  , TestLabel "KnowledgeTree root stress signal is NaN-safe" testRootStressSignalIsNaNSafe
  , TestLabel "KnowledgeTree clamps inflated stored deltas on deserialize" testStoredDeltasClampedOnDeserialize
  ]

-- | Trust boundary at the READ edge: a fruit persisted (or hand-edited /
-- corrupted) with an out-of-range predictiveDelta must NOT deserialize at its
-- raw value, or it would bypass authoritativeNetDelta promotion gating. The
-- write path clamps at creation (Loop.hs/Sandbox.hs); this locks the read path.
testStoredDeltasClampedOnDeserialize :: Test
testStoredDeltasClampedOnDeserialize = TestCase $ do
  let inflated = BL.pack
        "{\"proposition\":\"p\",\"word\":\"w\",\"source\":\"SourceLLM\",\"validated\":true,\"conatusDelta\":999.0,\"predictiveDelta\":999.0,\"graftedTurn\":null,\"observedTurn\":1}"
  case decode inflated :: Maybe KnowledgeFruit of
    Nothing -> assertFailure "inflated fruit JSON must still decode (clamped, not rejected)"
    Just fruit -> do
      assertBool "predictiveDelta must be clamped to <= 0.50 on deserialize"
        (kfPredictiveDelta fruit <= 0.50)
      assertBool "conatusDelta must be clamped to <= 0.40 on deserialize"
        (kfConatusDelta fruit <= 0.40)
      assertBool "authoritativeNetDelta must not reflect the inflated 999.0 claim"
        (authoritativeNetDelta fruit <= 0.90)

testGraftFruitCreatesBranchAndCount :: Test
testGraftFruitCreatesBranchAndCount = TestCase $ do
  let fruit = mkFruit "freedom requires responsibility" "свобода" SourceInternal True 0.5 0.3
      tree = graftFruit "agreement" fruit emptyKnowledgeTree
  assertEqual "graft must increment grafted count"
    1 (ktGraftedCount tree)
  assertBool "agreement branch must exist after graft"
    (M.member "agreement" (ktBranches tree))

testQuarantineFruitTracksAntiDogmatism :: Test
testQuarantineFruitTracksAntiDogmatism = TestCase $ do
  let fruit = mkFruit "marginal claim" "свобода" SourceLLM True 0.05 (-0.1)
      tree = quarantineFruit fruit emptyKnowledgeTree
  assertEqual "quarantine must hold one fruit"
    1 (length (ktQuarantine tree))
  assertEqual "quarantined count must increment"
    1 (ktQuarantinedCount tree)

testPromoteFromQuarantinePromotesOnlyNonNegativeFruit :: Test
testPromoteFromQuarantinePromotesOnlyNonNegativeFruit = TestCase $ do
  let rejectedFruit = mkFruit "negative net delta" "риск" SourceLLM True (-0.4) 0.1
      promotedFruit = mkFruit "bounded agency" "свобода" SourceHuman True 0.4 0.3
      tree0 = emptyKnowledgeTree
        { ktQuarantine = [rejectedFruit, promotedFruit]
        , ktQuarantinedCount = 2
        }
      (tree1, promoted, rejected) = promoteFromQuarantine 10 2 "agreement" tree0
  assertEqual "exactly one ripe fruit should be promoted"
    1 promoted
  assertEqual "one non-negative failure should remain quarantined"
    1 rejected
  assertEqual "grafted counter must reflect promoted fruit"
    1 (ktGraftedCount tree1)
  assertEqual "rejected fruit should remain quarantined"
    [rejectedFruit] (ktQuarantine tree1)

testPruneFruitsDropsInvalidAndNegative :: Test
testPruneFruitsDropsInvalidAndNegative = TestCase $ do
  let validFruit = mkFruit "valid" "свобода" SourceInternal True 0.5 0.3
      invalidFruit = mkFruit "invalid" "ошибка" SourceLLM False 0.0 0.0
      negativeFruit = mkFruit "negative" "риск" SourceLLM True (-0.5) 0.0
      tree0 = emptyKnowledgeTree
        { ktBranches = M.singleton "agreement"
            [ Branch
                { brRule = "agreement"
                , brFruits = [validFruit, invalidFruit, negativeFruit]
                , brHealth = 0.0
                , brCreatedTurn = 1
                }
            ]
        , ktQuarantine = [invalidFruit]
        }
      (tree1, dropped) = pruneFruits 1 tree0
      remaining = concatMap brFruits (concat (M.elems (ktBranches tree1)))
  assertEqual "invalid branch fruit and invalid quarantine fruit must be pruned"
    3 dropped
  assertEqual "only validated non-degrading fruit should remain grafted"
    [validFruit] remaining
  assertEqual "invalid quarantine entries must be removed"
    [] (ktQuarantine tree1)

testPruneBranchesDropsPersistentlyUnhealthy :: Test
testPruneBranchesDropsPersistentlyUnhealthy = TestCase $ do
  let tree0 = emptyKnowledgeTree
        { ktBranches = M.singleton "agreement"
            [ Branch
                { brRule = "agreement"
                , brFruits = [mkFruit "x" "свобода" SourceInternal True 0.0 0.0]
                , brHealth = -0.8
                , brCreatedTurn = 1
                }
            ]
        }
      (tree1, prunedBranches) = pruneBranches 5 (-0.5) 3 tree0
  assertEqual "strongly unhealthy branch must be pruned"
    1 prunedBranches
  assertEqual "pruned branch must be removed from the tree"
    M.empty (ktBranches tree1)

testRootStressSignalReflectsQuarantineAndDecay :: Test
testRootStressSignalReflectsQuarantineAndDecay = TestCase $ do
  let stressedTree = emptyKnowledgeTree
        { ktBranches = M.singleton "agreement"
            [ Branch
                { brRule = "agreement"
                , brFruits = []
                , brHealth = -0.6
                , brCreatedTurn = 1
                }
            ]
        , ktQuarantinedCount = 2
        }
      stress = rootStressSignal stressedTree
  assertEqual "empty tree should have zero stress"
    0.0 (rootStressSignal emptyKnowledgeTree)
  assertBool "stress must stay bounded to unit interval"
    (stress >= 0.0 && stress <= 1.0)
  assertBool "quarantine plus negative branch health must raise strong root stress"
    (stress > defaultRootStressThreshold)

testKnownTermChecksWordAndFallbackProposition :: Test
testKnownTermChecksWordAndFallbackProposition = TestCase $ do
  let byWord = mkFruit "bounded agency" "свобода" SourceInternal True 0.4 0.3
      byProp = mkFruit "ответственность ограничивает свободу" "" SourceHuman True 0.3 0.2
      tree = emptyKnowledgeTree
        { ktBranches = M.fromList
            [ ("agreement", [Branch "agreement" [byWord] 0.0 1])
            , ("repair", [Branch "repair" [byProp] 0.0 1])
            ]
        }
  assertBool "term should be found by explicit kfWord"
    (isTermKnownInKnowledgeTree "свобода" tree)
  assertBool "term should be found by proposition fallback when word is absent"
    (isTermKnownInKnowledgeTree "ответственность" tree)
  assertBool "unknown term should not be reported as known"
    (not (isTermKnownInKnowledgeTree "дружба" tree))

testKnowledgeTreeRoundTripsJson :: Test
testKnowledgeTreeRoundTripsJson = TestCase $ do
  let fruit = mkFruit "prop" "свобода" SourceHuman True 0.3 0.2
      tree = graftFruit "agreement" fruit emptyKnowledgeTree
      decoded = decode (encode tree) :: Maybe KnowledgeTree
  assertEqual "knowledge tree must round-trip through JSON"
    (Just tree) decoded

-- | Regression lock for audit-round3 P0 #3: the 'pruneFruits' pass must
-- drain unvalidated quarantine entries even when the quarantine has accreted
-- in bulk.  'quarantineFruit' enforces a hard cap of 'maxKnowledgeQuarantineSize'
-- (200), so bulk insertion beyond the cap is silently capped at insertion time.
-- The prune pass must then drop all remaining unvalidated entries.
testPruneFruitsCleansUnvalidatedQuarantineUnderBulkInsertion :: Test
testPruneFruitsCleansUnvalidatedQuarantineUnderBulkInsertion = TestCase $ do
  let bulkUnvalidated =
        [ mkFruit ("u" <> T.pack (show i)) "x" SourceLLM False 0.0 0.0
        | i <- [1 .. 500 :: Int]
        ]
      tree0 = foldl' (flip quarantineFruit) emptyKnowledgeTree bulkUnvalidated
  -- quarantineFruit caps at maxKnowledgeQuarantineSize (200); bulk beyond cap is dropped at insertion
  assertEqual "bulk insertion is capped at maxKnowledgeQuarantineSize"
    maxKnowledgeQuarantineSize (length (ktQuarantine tree0))
  let (tree1, dropped) = pruneFruits 100 tree0
  assertEqual "all capped unvalidated quarantine entries must be dropped on prune"
    maxKnowledgeQuarantineSize dropped
  assertEqual "no unvalidated quarantine entries must remain after prune"
    [] (ktQuarantine tree1)

-- | Regression lock G1: 'rootStressSignal' must remain in [0, 1] and
-- never propagate NaN/Infinity even when fed a tree whose components
-- could otherwise produce non-finite arithmetic (e.g. degenerate
-- branch health values).  The NaN-safe 'clampUnit' in
-- "QxFx0.Learning.KnowledgeTree" guarantees a finite signal at the
-- calibration boundary.
testRootStressSignalIsNaNSafe :: Test
testRootStressSignalIsNaNSafe = TestCase $ do
  let nanBranch = Branch
        { brRule = "agreement"
        , brFruits = [mkFruit "p" "" SourceInternal True 0.0 0.0]
        , brHealth = 0/0
        , brCreatedTurn = 1
        }
      infBranch = Branch
        { brRule = "repair"
        , brFruits = [mkFruit "q" "" SourceInternal True 0.0 0.0]
        , brHealth = (-1)/0
        , brCreatedTurn = 1
        }
      tree = emptyKnowledgeTree
        { ktBranches = M.fromList [("agreement", [nanBranch]), ("repair", [infBranch])]
        , ktQuarantinedCount = 1
        , ktGraftedCount = 1
        }
      stress = rootStressSignal tree
  assertBool "root stress must not be NaN under non-finite branch health"
    (not (isNaN stress))
  assertBool "root stress must not be Infinity under non-finite branch health"
    (not (isInfinite stress))
  assertBool "root stress must stay bounded to the unit interval"
    (stress >= 0.0 && stress <= 1.0)

mkFruit :: Text -> Text -> KnowledgeSource -> Bool -> Double -> Double -> KnowledgeFruit
mkFruit prop word src valid cDelta pDelta =
  KnowledgeFruit
    { kfProposition = prop
    , kfWord = word
    , kfSource = src
    , kfValidated = valid
    , kfConatusDelta = cDelta
    , kfPredictiveDelta = pDelta
    , kfGraftedTurn = Nothing
    , kfObservedTurn = 1
    }
