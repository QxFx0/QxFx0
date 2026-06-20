{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.GeneratedPredicateGate (generatedPredicateGateTests) where

import Test.HUnit
import Data.Text (Text)
import qualified Data.Text as T
import QxFx0.Semantic.Content.AtomStore
import QxFx0.Semantic.Content.GeneratedPredicateGate
import QxFx0.Semantic.Content.PathFinder

generatedPredicateGateTests :: [Test]
generatedPredicateGateTests =
  [ TestLabel "Gate G1 specificity" g1Tests
  , TestLabel "Gate G2 non-tautology" g2Tests
  , TestLabel "Gate G3 path provenance" g3Tests
  , TestLabel "Gate G4 source whitelist" g4Tests
  , TestLabel "Gate G5 non-substrate output" g5Tests
  , TestLabel "Combined verdict" combinedTests
  , TestLabel "composeDefinitionWithGates" composeWithGatesTests
  ]

-- Helper: get a valid path proof for свобода
sampleProof :: PathProof
sampleProof = case findPathsLength1 (AtomId "свобода") of
  (rp:_) -> rpProof rp
  [] -> PathProof [] "свобода"

-- Helper: tautological proof (from == to)
tautologicalProof :: PathProof
tautologicalProof = PathProof
  [ Relation
      { relFrom = AtomId "свобода"
      , relTo = AtomId "свобода"
      , relType = RelIsA
      , relObjectCase = CaseNominative
      , relObjectText = "свобода"
      , relVerbText = Nothing
      , relRuOriginal = "свобода есть свобода"
      , relEnOriginal = "freedom is freedom"
      , relSource = SeedFromPredicate
      , relTopic = "свобода"
      }
  ] "свобода"

-- Helper: raw substrate proof
rawSubstrateProof :: PathProof
rawSubstrateProof = PathProof
  [ Relation
      { relFrom = AtomId "свобода"
      , relTo = AtomId "выбор"
      , relType = RelPresupposes
      , relObjectCase = CaseAccusative
      , relObjectText = "выбор"
      , relVerbText = Nothing
      , relRuOriginal = "свобода предполагает выбор"
      , relEnOriginal = "freedom presupposes choice"
      , relSource = SubstrateExtractedRaw
      , relTopic = "свобода"
      }
  ] "свобода"

g1Tests :: Test
g1Tests = TestList
  [ TestCase $ do
      let result = gateSpecificity sampleProof
      assertEqual "valid path passes G1" GatePass result

  , TestCase $ do
      let badProof = PathProof [] "другой_топик"
          result = gateSpecificity badProof
      case result of
        GateFail _ -> assertBool "empty path fails G1" True
        GatePass  -> assertFailure "empty path should fail G1"
  ]

g2Tests :: Test
g2Tests = TestList
  [ TestCase $ do
      let result = gateNonTautology sampleProof
      assertEqual "valid path passes G2" GatePass result

  , TestCase $ do
      let result = gateNonTautology tautologicalProof
      case result of
        GateFail _ -> assertBool "tautological path fails G2" True
        GatePass  -> assertFailure "tautological path should fail G2"
  ]

g3Tests :: Test
g3Tests = TestList
  [ TestCase $ do
      let result = gatePathProvenance sampleProof
      assertEqual "valid path passes G3" GatePass result

  , TestCase $ do
      let emptyProof = PathProof [] "свобода"
          result = gatePathProvenance emptyProof
      case result of
        GateFail _ -> assertBool "empty path fails G3" True
        GatePass  -> assertFailure "empty path should fail G3"
  ]

g4Tests :: Test
g4Tests = TestList
  [ TestCase $ do
      let result = gateSourceWhitelist sampleProof
      assertEqual "seed source passes G4" GatePass result

  , TestCase $ do
      let result = gateSourceWhitelist rawSubstrateProof
      case result of
        GateFail _ -> assertBool "raw substrate fails G4" True
        GatePass  -> assertFailure "raw substrate should fail G4"
  ]

g5Tests :: Test
g5Tests = TestList
  [ TestCase $ do
      let result = gateNonSubstrateOutput sampleProof
      assertEqual "no raw substrate passes G5" GatePass result

  , TestCase $ do
      let result = gateNonSubstrateOutput rawSubstrateProof
      case result of
        GateFail _ -> assertBool "raw substrate fails G5" True
        GatePass  -> assertFailure "raw substrate should fail G5"
  ]

combinedTests :: Test
combinedTests = TestList
  [ TestCase $ do
      let verdict = validatePath sampleProof
      assertEqual "valid path passes all gates" True (gvOverall verdict)

  , TestCase $ do
      let verdict = validatePath tautologicalProof
      assertEqual "tautological path fails overall" False (gvOverall verdict)

  , TestCase $ do
      let verdict = validatePath rawSubstrateProof
      assertEqual "raw substrate path fails overall" False (gvOverall verdict)

  , TestCase $ do
      let (passed, rejected) = validatePaths [sampleProof, tautologicalProof, rawSubstrateProof]
      assertEqual "1 passed" 1 (length passed)
      assertEqual "2 rejected" 2 (length rejected)
  ]

composeWithGatesTests :: Test
composeWithGatesTests = TestList
  [ TestCase $ do
      let (text, passed, rejected) = composeDefinitionWithGates defaultFieldProfile 3 (AtomId "свобода")
      assertBool ("text non-empty: " <> show text) (T.length text > 0)
      assertBool ("passed >= 1: " <> show passed) (passed >= 1)
      assertEqual "rejected = 0 for seed-only graph" 0 rejected

  , TestCase $ do
      let (text, _, _) = composeDefinitionWithGates defaultFieldProfile 3 (AtomId "несуществующий")
      assertEqual "nonexistent topic → empty text" "" text
  ]
