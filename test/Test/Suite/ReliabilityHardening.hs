{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.ReliabilityHardening
  ( reliabilityHardeningTests
  ) where

import Test.HUnit

import QxFx0.Learning.Tool
  ( ExternalTool(..)
  , ToolDomain(..)
  , selectTool
  , selectToolWithReliability
  )
import QxFx0.Learning.Need (LearningNeed(..))
import QxFx0.Learning.Calibration
  ( CalibrationId(..)
  , CalibrationEntry(..)
  , CalibrationStatus(..)
  , CalibrationProposal(..)
  , CalibrationLog(..)
  , currentCalibrationVersion
  )
import QxFx0.Learning.GameTheory (solveMixedStrategy)
import QxFx0.Lexicon.GfMap
  ( topicToGfLexemeId
  , lookupGfLexemeForms
  , defaultGfLexemeId
  , GfMapLoadStatus(..)
  , gfMapLoadStatus
  , loadGfMapFromContent
  )

-- | 1. Tool selection with empty candidate list -> total (no crash).
testSelectToolEmptyPool :: Test
testSelectToolEmptyPool = TestCase $ do
  let tools = []
      result = selectTool NeedLexiconExtension tools
  assertEqual "empty tool pool must yield Nothing" Nothing result

-- | 2. Tool selection with mismatched domain and no general fallback -> total.
testSelectToolNoMatchingDomain :: Test
testSelectToolNoMatchingDomain = TestCase $ do
  let tools =
        [ ExternalTool "script" DomainSalience 0.9 True
        ]
      result = selectTool NeedLexiconExtension tools
  assertEqual "no matching domain and no general fallback must yield Nothing"
    Nothing result

-- | 3. Calibration current version with empty accepted list -> total.
testCalibrationVersionEmptyLog :: Test
testCalibrationVersionEmptyLog = TestCase $ do
  let log = CalibrationLog []
      result = currentCalibrationVersion log
  assertEqual "empty calibration log must yield Nothing" Nothing result

-- | 4. Calibration current version with no accepted entries -> total.
testCalibrationVersionNoAccepted :: Test
testCalibrationVersionNoAccepted = TestCase $ do
  let log = CalibrationLog
        [ CalibrationEntry (CalibrationId 1) (ProposalRule "rule") Pending 0 Nothing Nothing
        , CalibrationEntry (CalibrationId 2) (ProposalRule "rule") Rejected 0 Nothing Nothing
        ]
      result = currentCalibrationVersion log
  assertEqual "log without accepted entries must yield Nothing" Nothing result

-- | 5. LP with valid uniform matrix -> Just probabilities.
testLPValidUniformMatrix :: Test
testLPValidUniformMatrix = TestCase $ do
  let a = replicate 3 (replicate 3 1.0)
      result = solveMixedStrategy a
  assertBool "uniform 3x3 matrix must return Just" (result /= Nothing)

-- | 6. LP with jagged rows -> safe reject (Nothing).
testLPJaggedRows :: Test
testLPJaggedRows = TestCase $ do
  let a =
        [ [1.0, 2.0]
        , [3.0]        -- jagged: second row shorter
        ]
      result = solveMixedStrategy a
  assertEqual "jagged matrix must yield Nothing (fail-closed)"
    Nothing result

-- | 7. LP with empty matrix -> safe reject.
testLPEmptyMatrix :: Test
testLPEmptyMatrix = TestCase $ do
  assertEqual "empty matrix must yield Nothing" Nothing (solveMixedStrategy [])

-- | 8. GfMap fallback deterministic (unknown topic -> default lexeme id).
testGfMapUnknownTopicFallback :: Test
testGfMapUnknownTopicFallback = TestCase $ do
  let result = topicToGfLexemeId "xyz_nonexistent_topic"
  assertEqual "unknown topic must fallback to defaultGfLexemeId"
    defaultGfLexemeId result

-- | 9. GfMap lookup unknown fun id -> Nothing (no crash).
testGfMapLookupUnknownFun :: Test
testGfMapLookupUnknownFun = TestCase $ do
  let result = lookupGfLexemeForms "nonexistent_fun"
  assertEqual "lookup of unknown fun must yield Nothing" Nothing result

-- | 10. GfMap missing resource -> explicit GfMapLoadFailed with structured reason.
testGfMapMissingResource :: Test
testGfMapMissingResource = TestCase $ do
  let (_data', status) = loadGfMapFromContent Nothing
  assertEqual "missing resource must yield explicit failed status"
    (GfMapLoadFailed "resource_missing_or_unreadable") status

-- | 11. GfMap empty/unparseable content -> explicit GfMapLoadFailed.
testGfMapEmptyContent :: Test
testGfMapEmptyContent = TestCase $ do
  let (_data', status) = loadGfMapFromContent (Just "")
  assertEqual "empty content must yield explicit failed status"
    (GfMapLoadFailed "resource_empty_or_unparseable") status

-- | 12. GfMap valid content -> GfMapLoaded with positive count.
testGfMapValidContent :: Test
testGfMapValidContent = TestCase $ do
  let tsv = "fun\tlemma\tpos\tnom\tgen\tprep\nfun1\tlemma1\tn\tлемма1\tлеммы\tлемме\n"
      (_data', status) = loadGfMapFromContent (Just tsv)
  case status of
    GfMapLoaded n -> assertBool "valid content must load >0 entries" (n > 0)
    other -> assertFailure ("expected GfMapLoaded, got: " ++ show other)

-- | 13. GfMap runtime load status must be healthy in test environment.
testGfMapRuntimeLoadHealthy :: Test
testGfMapRuntimeLoadHealthy = TestCase $ do
  case gfMapLoadStatus of
    GfMapLoaded n -> assertBool "runtime load must have >0 entries" (n > 0)
    GfMapLoadFailed reason -> assertFailure
      ("runtime GF map load failed in test env: " ++ show reason)

reliabilityHardeningTests :: [Test]
reliabilityHardeningTests =
  [ TestLabel "select-tool-empty-pool"             testSelectToolEmptyPool
  , TestLabel "select-tool-no-matching-domain"     testSelectToolNoMatchingDomain
  , TestLabel "calibration-version-empty-log"      testCalibrationVersionEmptyLog
  , TestLabel "calibration-version-no-accepted"   testCalibrationVersionNoAccepted
  , TestLabel "lp-valid-uniform-matrix"            testLPValidUniformMatrix
  , TestLabel "lp-jagged-rows"                    testLPJaggedRows
  , TestLabel "lp-empty-matrix"                   testLPEmptyMatrix
  , TestLabel "gfmap-unknown-topic-fallback"      testGfMapUnknownTopicFallback
  , TestLabel "gfmap-lookup-unknown-fun"           testGfMapLookupUnknownFun
  , TestLabel "gfmap-missing-resource"           testGfMapMissingResource
  , TestLabel "gfmap-empty-content"              testGfMapEmptyContent
  , TestLabel "gfmap-valid-content"              testGfMapValidContent
  , TestLabel "gfmap-runtime-load-healthy"       testGfMapRuntimeLoadHealthy
  ]
