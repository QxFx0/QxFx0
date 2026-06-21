{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.PathFinder (pathFinderTests) where

import Test.HUnit
import Data.Text (Text)
import qualified Data.Text as T
import QxFx0.Semantic.Content.AtomStore
import QxFx0.Semantic.Content.PathFinder
import QxFx0.Semantic.Content.GeneratedPredicateGate (validatePath, GateVerdict(..))
import QxFx0.Types (MorphologyData(..))
import qualified Data.Map.Strict as M

testMorph :: MorphologyData
testMorph = MorphologyData M.empty M.empty M.empty M.empty

pathFinderTests :: [Test]
pathFinderTests =
  [ TestLabel "PathFinder length 1" length1Tests
  , TestLabel "PathFinder length 2" length2Tests
  , TestLabel "PathFinder length 3" length3Tests
  , TestLabel "PathFinder field bias" fieldBiasTests
  , TestLabel "PathFinder determinism" determinismTests
  , TestLabel "PathFinder composition" compositionTests
  , TestLabel "PathFinder gate enforcement" gateEnforcementTests
  ]

length1Tests :: Test
length1Tests = TestList
  [ TestCase $ do
      let paths = findPathsLength1 seedGraph (AtomId "свобода")
      assertBool ("свобода length-1 has >= 2 paths, got " <> show (length paths))
                 (length paths >= 2)

  , TestCase $ do
      let paths = findPathsLength1 seedGraph (AtomId "свобода")
          allLen1 = all (\rp -> length (ppEdges (rpProof rp)) == 1) paths
      assertEqual "all length-1 paths have exactly 1 edge" True allLen1

  , TestCase $ do
      let paths = findPathsLength1 seedGraph (AtomId "несуществующий_топик")
      assertEqual "nonexistent topic has 0 paths" 0 (length paths)

  , TestCase $ do
      let paths = findPathsLength1 seedGraph (AtomId "истина")
      assertBool ("истина has >= 2 paths, got " <> show (length paths))
                 (length paths >= 2)
  ]

length2Tests :: Test
length2Tests = TestList
  [ TestCase $ do
      let paths = findPathsLength2 seedGraph (AtomId "свобода")
      assertBool ("свобода length-2 has >= 1 path, got " <> show (length paths))
                 (length paths >= 1)

  , TestCase $ do
      let paths = findPathsLength2 seedGraph (AtomId "свобода")
          allLen2 = all (\rp -> length (ppEdges (rpProof rp)) == 2) paths
      assertEqual "all length-2 paths have exactly 2 edges" True allLen2

  , TestCase $ do
      let paths = findPathsLength2 seedGraph (AtomId "несуществующий_топик")
      assertEqual "nonexistent topic has 0 length-2 paths" 0 (length paths)
  ]

length3Tests :: Test
length3Tests = TestList
  [ TestCase $ do
      let paths = findPathsLength3 seedGraph (AtomId "свобода")
      assertBool ("свобода length-3 has >= 1 path, got " <> show (length paths))
                 (length paths >= 1)

  , TestCase $ do
      let paths = findPathsLength3 seedGraph (AtomId "свобода")
          allLen3 = all (\rp -> length (ppEdges (rpProof rp)) == 3) paths
      assertEqual "all length-3 paths have exactly 3 edges" True allLen3
  ]

fieldBiasTests :: Test
fieldBiasTests = TestList
  [ TestCase $ do
      let highConf = FieldProfile 1.0 0.0 0.0 0.0
          highCF   = FieldProfile 0.0 1.0 0.0 0.0
          confScore = relationTypeBias highConf RelClaims
          cfScore   = relationTypeBias highCF RelClaims
      assertBool "confidence profile scores RelClaims higher than counterfactual"
                 (confScore > cfScore)

  , TestCase $ do
      let highCF = FieldProfile 0.0 1.0 0.0 0.0
          cfScore = relationTypeBias highCF RelDiffersFrom
          confScore = relationTypeBias (FieldProfile 1.0 0.0 0.0 0.0) RelDiffersFrom
      assertBool "counterfactual profile scores RelDiffersFrom higher than confidence"
                 (cfScore > confScore)

  , TestCase $ do
      let highConf = FieldProfile 1.0 0.0 0.0 0.0
          paths = selectTopPaths 3 highConf seedGraph (AtomId "истина") 1
          allPaths = findPathsLength1 seedGraph (AtomId "истина")
      assertBool ("selectTopPaths returns <= 3, got " <> show (length paths))
                 (length paths <= 3 && length paths >= 1)
      assertBool ("selectTopPaths returns subset of all paths")
                 (length paths <= length allPaths)

  , TestCase $ do
      let highConf = FieldProfile 1.0 0.0 0.0 0.0
          highConsolid = FieldProfile 0.0 0.0 1.0 0.0
          confPaths = selectTopPaths 1 highConf seedGraph (AtomId "истина") 1
          consolPaths = selectTopPaths 1 highConsolid seedGraph (AtomId "истина") 1
      let confScore = case confPaths of (rp:_) -> psTotal (rpScore rp); [] -> 0
          consolScore = case consolPaths of (rp:_) -> psTotal (rpScore rp); [] -> 0
      assertBool ("different profiles yield different scores: " <> show (confScore, consolScore))
                 (confScore /= consolScore)
  ]

determinismTests :: Test
determinismTests = TestList
  [ TestCase $ do
      let p1 = findPathsFrom seedGraph 2 (AtomId "свобода")
          p2 = findPathsFrom seedGraph 2 (AtomId "свобода")
      assertEqual "same input -> same output (findPathsFrom)" p1 p2

  , TestCase $ do
      let p1 = selectTopPaths 3 defaultFieldProfile seedGraph (AtomId "истина") 2
          p2 = selectTopPaths 3 defaultFieldProfile seedGraph (AtomId "истина") 2
      assertEqual "same input -> same output (selectTopPaths)" p1 p2

  , TestCase $ do
      let p1 = rankPaths (findPathsLength1 seedGraph (AtomId "свобода"))
          p2 = rankPaths (findPathsLength1 seedGraph (AtomId "свобода"))
      assertEqual "same input -> same output (rankPaths)" p1 p2
  ]

compositionTests :: Test
compositionTests = TestList
  [ TestCase $ do
      let surface = composeDefinition testMorph defaultFieldProfile 3 seedGraph (AtomId "свобода")
      assertBool ("composeDefinition produces non-empty text: " <> show (T.length (gsText surface)))
                 (T.length (gsText surface) > 0)

  , TestCase $ do
      let surface = composeDefinition testMorph defaultFieldProfile 3 seedGraph (AtomId "свобода")
      assertBool ("composed text contains 'свобода': " <> show (gsText surface))
                 ("свобода" `T.isInfixOf` gsText surface)

  , TestCase $ do
      let surface = composeDefinition testMorph defaultFieldProfile 3 seedGraph (AtomId "истина")
      assertBool ("composed text contains 'истина': " <> show (gsText surface))
                 ("истина" `T.isInfixOf` gsText surface)

  , TestCase $ do
      let surface = composeDefinition testMorph defaultFieldProfile 10 seedGraph (AtomId "несуществующий")
      assertEqual "nonexistent topic produces empty text" "" (gsText surface)
  ]

-- ============================================================
-- Gate enforcement integration tests
-- ============================================================
-- These tests verify that composeDefinition actually REJECTS invalid proofs.
-- Previously the gate verdict was computed but discarded (_gateVerdict),
-- making the gate system decorative -- present in tests but not enforced
-- in the production path. These integration tests guard against regression.

-- | A relation with SubstrateExtractedRaw source -- fails G4 (Source whitelist).
substrateEdge :: Relation
substrateEdge = Relation
  { relFrom = AtomId "тест_топик"
  , relTo = AtomId "тест_объект"
  , relType = RelPresupposes
  , relObjectCase = CaseAccusative
  , relObjectText = "тестовый объект"
  , relVerbText = Nothing
  , relRuOriginal = "тест_топик предполагает тестовый объект"
  , relEnOriginal = "test_topic presupposes test_object"
  , relSource = SubstrateExtractedRaw
  , relTopic = "тест_топик"
  }

-- | A self-referential relation -- fails G2 (Non-tautology).
tautologicalEdge :: Relation
tautologicalEdge = Relation
  { relFrom = AtomId "тест_топик"
  , relTo = AtomId "тест_топик"
  , relType = RelPresupposes
  , relObjectCase = CaseAccusative
  , relObjectText = "тестовый объект"
  , relVerbText = Nothing
  , relRuOriginal = "тест_топик предполагает тестовый объект"
  , relEnOriginal = "test_topic presupposes test_object"
  , relSource = SeedFromPredicate
  , relTopic = "тест_топик"
  }

-- | Build a graph containing only invalid edges.
invalidGraph :: [Relation] -> AtomGraph
invalidGraph rels =
  let idx = M.fromList [(AtomId "тест_топик", rels)]
  in AtomGraph rels idx "test-invalid"

gateEnforcementTests :: Test
gateEnforcementTests = TestList
  [ TestCase $ do
      -- G4 violation: SubstrateExtractedRaw source should be rejected
      let graph = invalidGraph [substrateEdge]
          surface = composeDefinition testMorph defaultFieldProfile 3 graph (AtomId "тест_топик")
      assertEqual "composeDefinition rejects SubstrateExtractedRaw (G4)" "" (gsText surface)
      assertEqual "rejected surface has no proofs" [] (gsPaths surface)
      assertEqual "rejected surface has no provenance" [] (gsProvenance surface)

  , TestCase $ do
      -- G2 violation: self-referential edge should be rejected
      let graph = invalidGraph [tautologicalEdge]
          surface = composeDefinition testMorph defaultFieldProfile 3 graph (AtomId "тест_топик")
      assertEqual "composeDefinition rejects tautological edge (G2)" "" (gsText surface)
      assertEqual "rejected surface has no proofs" [] (gsPaths surface)

  , TestCase $ do
      -- Direct gate verification: SubstrateExtractedRaw fails G4
      let proof = PathProof [substrateEdge] "тест_топик"
          verdict = validatePath proof
      assertBool "G4 gate fails for SubstrateExtractedRaw" (not (gvOverall verdict))

  , TestCase $ do
      -- Direct gate verification: tautological edge fails G2
      let proof = PathProof [tautologicalEdge] "тест_топик"
          verdict = validatePath proof
      assertBool "G2 gate fails for tautological edge" (not (gvOverall verdict))

  , TestCase $ do
      -- Regression: valid seedGraph edges still pass gates and produce output
      let surface = composeDefinition testMorph defaultFieldProfile 3 seedGraph (AtomId "свобода")
      assertBool ("valid seedGraph still produces non-empty text after gate enforcement: " <> show (gsText surface))
                 (T.length (gsText surface) > 0)
  ]
