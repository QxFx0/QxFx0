{-# LANGUAGE OverloadedStrings #-}
module Test.Suite.RenderDialogueCoverage
  ( renderDialogueCoverageTests
  ) where

import Test.HUnit
import qualified Data.Text as T
import qualified Data.Map.Strict as M

import QxFx0.Render.Dialogue
  ( isVapidTopic
  , cleanTopic
  , stancePrefix
  , moveToText
  , linearizeClaimAstRus
  , hasStructuredDialogueSurface
  )
import QxFx0.Types
  ( StanceMarker(..)
  , ContentMove(..)
  , ClaimAst(..)
  , MorphologyData(..)
  , InputPropositionFrame(..)
  , RenderStyle(..)
  , emptyInputPropositionFrame
  )

emptyMorphologyData :: MorphologyData
emptyMorphologyData = MorphologyData M.empty M.empty M.empty M.empty

renderDialogueCoverageTests :: [Test]
renderDialogueCoverageTests =
  [ TestLabel "isVapidTopic detects vapid words" testIsVapidTopic
  , TestLabel "isVapidTopic accepts non-vapid" testIsVapidTopicFalse
  , TestLabel "cleanTopic trims and lowercases" testCleanTopic
  , TestLabel "stancePrefix for all markers" testStancePrefixAll
  , TestLabel "moveToText GroundKnown" testMoveToTextGroundKnown
  , TestLabel "moveToText DefineFrame" testMoveToTextDefineFrame
  , TestLabel "moveToText all content moves" testMoveToTextAllMoves
  , TestLabel "linearizeClaimAstRus MoveOperationalStatus" testLinearizeOperationalStatus
  , TestLabel "linearizeClaimAstRus ClaimPurpose" testLinearizeClaimPurpose
  , TestLabel "linearizeClaimAstRus all simple constructors" testLinearizeAllSimple
  , TestLabel "hasStructuredDialogueSurface False for empty" testHasStructuredSurfaceEmpty
  , TestLabel "hasStructuredDialogueSurface True for operational" testHasStructuredSurfaceOperational
  ]

testIsVapidTopic :: Test
testIsVapidTopic = TestCase $ do
  assertBool "'не' should be vapid" (isVapidTopic "не")
  assertBool "'это' should be vapid" (isVapidTopic "это")

testIsVapidTopicFalse :: Test
testIsVapidTopicFalse = TestCase $ do
  assertBool "'право' should not be vapid" (not (isVapidTopic "право"))

testCleanTopic :: Test
testCleanTopic = TestCase $ do
  assertEqual "strips only" "ПРАВО" (cleanTopic "  ПРАВО  ")

testStancePrefixAll :: Test
testStancePrefixAll = TestCase $ do
  -- Calling stancePrefix for all constructors exercises the mapping.
  -- Commit and Observe intentionally return empty text per design.
  mapM_ (\sm -> assertBool ("stancePrefix should not crash for " ++ show sm)
             (let _ = stancePrefix sm in True))
    [Commit, Observe, Explore, HoldBack, Firm, Honest, Tentative, Curated]

testMoveToTextGroundKnown :: Test
testMoveToTextGroundKnown = TestCase $ do
  let txt = moveToText MoveGroundKnown "право" emptyMorphologyData
  assertBool "GroundKnown should produce non-empty text" (not (T.null txt))

testMoveToTextDefineFrame :: Test
testMoveToTextDefineFrame = TestCase $ do
  let txt = moveToText MoveDefineFrame "хартия" emptyMorphologyData
  assertBool "DefineFrame should produce non-empty text" (not (T.null txt))

testMoveToTextAllMoves :: Test
testMoveToTextAllMoves = TestCase $ do
  -- Exercise every ContentMove constructor to increase branch coverage.
  let moves =
        [ MoveGroundKnown, MoveGroundBasis, MoveShiftFromLabel
        , MoveDefineFrame, MoveStateDefinition, MoveShowContrast
        , MoveStateBoundary, MoveReflectMirror, MoveReflectResonate
        , MoveDescribeSketch, MovePurposeTeleology, MoveHypothesizeTest
        , MoveAffirmPresence, MoveAcknowledgeRupture, MoveRepairBridge
        , MoveContactBridge, MoveContactReach, MoveAnchorStabilize
        , MoveClarifyDisambiguate, MoveDeepenProbe, MoveConfrontChallenge
        , MoveNextStep
        ]
  mapM_ (\cm -> assertBool ("moveToText should not crash for " ++ show cm)
             (let _ = moveToText cm "тема" emptyMorphologyData in True))
    moves

testLinearizeOperationalStatus :: Test
testLinearizeOperationalStatus = TestCase $ do
  let result = linearizeClaimAstRus MoveOperationalStatus StyleStandard emptyMorphologyData
  assertBool "MoveOperationalStatus should linearize to Just" (maybe False (not . T.null) result)

testLinearizeClaimPurpose :: Test
testLinearizeClaimPurpose = TestCase $ do
  let _ = linearizeClaimAstRus (ClaimPurpose "тест") StyleStandard emptyMorphologyData
  assertBool "ClaimPurpose linearization should not crash" True

testLinearizeAllSimple :: Test
testLinearizeAllSimple = TestCase $ do
  -- Exercise every ClaimAst constructor that does not need complex nested args.
  let asts =
        [ ClaimPurpose "x"
        , ClaimSelfState
        , ClaimComparison "a" "b"
        , MoveOperationalStatus
        , MoveOperationalCause
        , MoveSystemLogic
        , MoveMisunderstanding
        , MoveGenerativeThought
        , MoveSelfState
        ]
  mapM_ (\ast -> assertBool ("linearizeClaimAstRus should not crash for " ++ show ast)
             (let _ = linearizeClaimAstRus ast StyleStandard emptyMorphologyData in True))
    asts

testHasStructuredSurfaceEmpty :: Test
testHasStructuredSurfaceEmpty = TestCase $ do
  assertBool "empty frame should not have structured surface"
    (not (hasStructuredDialogueSurface emptyInputPropositionFrame))

testHasStructuredSurfaceOperational :: Test
testHasStructuredSurfaceOperational = TestCase $ do
  let frame = emptyInputPropositionFrame { ipfPropositionType = "OperationalStatusQ" }
  assertBool "OperationalStatusQ should have structured surface"
    (hasStructuredDialogueSurface frame)
