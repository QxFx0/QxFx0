{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.LearningLoop
  ( learningLoopTests
  ) where

import Data.Aeson (encode, decode)
import qualified Data.Map.Strict as M
import qualified Data.Text as T
import Test.HUnit

import QxFx0.Learning.KnowledgeTree
  ( KnowledgeSource(..)
  , KnowledgeFruit(..)
  , Branch(..)
  , KnowledgeTree(..)
  , emptyKnowledgeTree
  , graftFruit
  , quarantineFruit
  , promoteFromQuarantine
  , pruneBranches
  , pruneFruits
  , rootStressSignal
  , treeCounters
  )
import QxFx0.Learning.Signal
  ( CalibrationSignal(..)
  , SignalComponents(..)
  , computeCalibrationSignal
  , emptySignalComponents
  )
import QxFx0.Learning.Tool
  ( ExternalTool(..)
  , ToolDomain(..)
  , selectToolWithReliability
  , updateToolReliability
  , defaultAvailableTools
  )
import QxFx0.Learning.Need
  ( LearningNeed(..)
  , LearningNeedState(..)
  , emptyLearningNeedState
  , NeedTrend(..)
  )

learningLoopTests :: [Test]
learningLoopTests =
  [ testGraftValidPositiveFruit
  , testQuarantineMarginalFruit
  , testPromoteFromQuarantineAfterWindow
  , testPruneUnhealthyBranches
  , testPruneInvalidFruits
  , testCalibrationSignalBoundedAndNonZero
  , testCalibrationSignalClampWorks
  , testToolReliabilityRisesOnAccept
  , testToolReliabilityFallsOnReject
  , testToolReliabilityAffectsSelection
  , testKnowledgeTreeRoundTripsJson
  , testOldJsonLoadsWithDefaults
  ]

-- | Phase 7: valid + positive-delta fruit grafts into branch.
testGraftValidPositiveFruit :: Test
testGraftValidPositiveFruit = TestCase $ do
  let fruit = mkFruit "test-proposition" SourceInternal True 0.5 0.3
      tree = graftFruit "agreement" fruit emptyKnowledgeTree
  assertEqual "graft must increment grafted count"
    1 (ktGraftedCount tree)
  assertBool "agreement branch must exist"
    (M.member "agreement" (ktBranches tree))

-- | Phase 7: marginal fruit (weak deltas) goes to quarantine.
testQuarantineMarginalFruit :: Test
testQuarantineMarginalFruit = TestCase $ do
  let fruit = mkFruit "marginal" SourceLLM True 0.05 (-0.1)
      tree = quarantineFruit fruit emptyKnowledgeTree
  assertEqual "quarantine must hold 1 fruit"
    1 (length (ktQuarantine tree))
  assertEqual "quarantined count must be 1"
    1 (ktQuarantinedCount tree)

-- | Phase 7: after min quarantine window + positive net delta,
-- fruit promotes to branch.
testPromoteFromQuarantineAfterWindow :: Test
testPromoteFromQuarantineAfterWindow = TestCase $ do
  let fruit = mkFruit "ripe" SourceHuman True 0.4 0.3
      tree0 = quarantineFruit fruit emptyKnowledgeTree
      (tree, promoted, rejected) =
        promoteFromQuarantine 10 2 "agreement" tree0
  assertEqual "promoted count must be 1"
    1 promoted
  assertEqual "rejected count must be 0"
    0 rejected
  assertEqual "grafted count must be 1"
    1 (ktGraftedCount tree)

-- | Phase 7: branch with sustained negative health pruned after K turns.
testPruneUnhealthyBranches :: Test
testPruneUnhealthyBranches = TestCase $ do
  let fruit = mkFruit "a" SourceInternal True 0.5 0.3
      tree0 = graftFruit "agreement" fruit emptyKnowledgeTree
      -- Force branch health negative by pruning its only fruit
      (tree1, _dropped) = pruneFruits 1 tree0
      -- health after pruning one fruit: 0.0 - 0.05 = -0.05
      -- Use threshold below actual health so it doesn't prune yet
      (tree2a, pruned0) = pruneBranches 5 (-0.10) 3 tree1
  assertEqual "slightly negative branch must NOT prune at -0.10 threshold"
    0 pruned0
  -- Now manually set branch health very negative to test pruneBranches
  let treeForced = tree0 { ktBranches = M.singleton "agreement"
        [ Branch { brRule = "agreement"
                 , brFruits = [mkFruit "x" SourceInternal True 0.0 0.0]
                 , brHealth = -0.8
                 , brCreatedTurn = 1
                 } ] }
      (tree3, prunedBranches) = pruneBranches 5 (-0.5) 3 treeForced
  assertEqual "strongly unhealthy branch must be pruned"
    1 prunedBranches
  assertBool "pruned count must reflect dropped fruits"
    (ktPrunedCount tree3 > 0)

-- | Phase 7: unvalidated or persistently negative fruits are pruned.
testPruneInvalidFruits :: Test
testPruneInvalidFruits = TestCase $ do
  let validFruit   = mkFruit "valid"   SourceInternal True  0.5 0.3
      invalidFruit = mkFruit "invalid" SourceLLM    False 0.0 0.0
      tree0 = graftFruit "agreement" validFruit
              (graftFruit "agreement" invalidFruit emptyKnowledgeTree)
      (tree, dropped) = pruneFruits 1 tree0
  assertEqual "invalid fruit must be pruned"
    1 dropped
  assertEqual "remaining fruit count in branch must be 1"
    1 (sum (map (length . brFruits) (concat (M.elems (ktBranches tree)))))

-- | Phase 7: calibration signal is non-zero in a diagnostic scenario
-- and bounded within [-1, 1].
testCalibrationSignalBoundedAndNonZero :: Test
testCalibrationSignalBoundedAndNonZero = TestCase $ do
  let needState = emptyLearningNeedState
        { lnsHistory = [(1, 0.8), (2, 0.85), (3, 0.9)]
        , lnsCurrentNeed = NeedLexiconExtension
        }
      (calSignal, _comps) =
        computeCalibrationSignal needState 0.8 5 10 emptyKnowledgeTree
      signal = unCalibrationSignal calSignal
  assertBool "signal must be non-zero in diagnostic scenario"
    (abs signal > 0.01)
  assertBool "signal must be <= 1.0"
    (signal <= 1.0)
  assertBool "signal must be >= -1.0"
    (signal >= -1.0)

-- | Phase 7: extreme inputs are clamped.
testCalibrationSignalClampWorks :: Test
testCalibrationSignalClampWorks = TestCase $ do
  let needState = emptyLearningNeedState
        { lnsHistory = [(1, 0.0), (2, 10.0), (3, 20.0)]
        , lnsCurrentNeed = NeedLexiconExtension
        }
      (calSignal, _comps) =
        computeCalibrationSignal needState 1.0 50 10 emptyKnowledgeTree
      signal = unCalibrationSignal calSignal
  assertBool "extreme positive inputs must clamp to <= 1.0"
    (signal <= 1.0)

-- | WP5: tool reliability rises on accepted outcome.
testToolReliabilityRisesOnAccept :: Test
testToolReliabilityRisesOnAccept = TestCase $ do
  let rel0 = M.empty
      rel1 = updateToolReliability "llm-augment" True rel0
  assertEqual "first accept must set reliability to 0.55"
    (Just 0.55) (M.lookup "llm-augment" rel1)

-- | WP5: tool reliability falls on rejected outcome.
testToolReliabilityFallsOnReject :: Test
testToolReliabilityFallsOnReject = TestCase $ do
  let rel0 = M.fromList [("llm-augment", 0.80)]
      rel1 = updateToolReliability "llm-augment" False rel0
  let actual = M.lookup "llm-augment" rel1
  assertBool "reject must drop reliability to ~0.70 (within 1e-9)"
    (case actual of
       Just v  -> abs (v - 0.70) < 1e-9
       Nothing -> False)

-- | WP5: low-reliability tool is no longer selected.
testToolReliabilityAffectsSelection :: Test
testToolReliabilityAffectsSelection = TestCase $ do
  let tools =
        [ ExternalTool "high-domain" DomainSalience 0.60 True
        , ExternalTool "low-domain" DomainSalience 0.90 True
        ]
      -- Override high-domain to be better than low-domain
      relMap = M.fromList [("high-domain", 0.95), ("low-domain", 0.30)]
      result = selectToolWithReliability NeedSalienceCalibration relMap tools
  assertEqual "selection must use dynamic reliability and pick high-domain"
    (Just "high-domain")
    (etName <$> result)

-- | Phase 7: knowledge tree round-trips through JSON.
testKnowledgeTreeRoundTripsJson :: Test
testKnowledgeTreeRoundTripsJson = TestCase $ do
  let fruit = mkFruit "prop" SourceHuman True 0.3 0.2
      tree = graftFruit "agreement" fruit emptyKnowledgeTree
      decoded = decode (encode tree) :: Maybe KnowledgeTree
  assertEqual "knowledge tree must round-trip through JSON"
    (Just tree) decoded

-- | Backward compatibility: old JSON without knowledgeTree loads
-- with default empty tree.
testOldJsonLoadsWithDefaults :: Test
testOldJsonLoadsWithDefaults = TestCase $ do
  let minimalJson = "{\"rootMode\": \"witnessing\", \"rootTrigger\": \"conatus_floor\"}"
      decoded = decode minimalJson :: Maybe KnowledgeTree
  assertBool "minimal JSON must decode"
    (decoded /= Nothing)
  let tree = maybe emptyKnowledgeTree id decoded
  assertEqual "default branches must be empty"
    M.empty (ktBranches tree)
  assertEqual "default quarantine must be empty"
    [] (ktQuarantine tree)

-- Helpers

mkFruit :: T.Text -> KnowledgeSource -> Bool -> Double -> Double -> KnowledgeFruit
mkFruit prop src valid cDelta pDelta =
  KnowledgeFruit
    { kfProposition = prop
    , kfSource = src
    , kfValidated = valid
    , kfConatusDelta = cDelta
    , kfPredictiveDelta = pDelta
    , kfGraftedTurn = Nothing
    , kfObservedTurn = 1
    }
