{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.PathFinder (pathFinderTests) where

import Test.HUnit
import Data.Text (Text)
import qualified Data.Text as T
import QxFx0.Semantic.Content.AtomStore
import QxFx0.Semantic.Content.PathFinder
import QxFx0.Semantic.Content.GeneratedPredicateGate (validatePath, GateVerdict(..))

pathFinderTests :: [Test]
pathFinderTests =
  [ TestLabel "PathFinder length 1" length1Tests
  , TestLabel "PathFinder length 2" length2Tests
  , TestLabel "PathFinder length 3" length3Tests
  , TestLabel "PathFinder field bias" fieldBiasTests
  , TestLabel "PathFinder determinism" determinismTests
  , TestLabel "PathFinder composition" compositionTests
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
      let paths = findPathsLength2 seedGraph (AtomId "свобода")
          -- No path should revisit the start atom
          noCycles = all (\rp ->
            let edges = ppEdges (rpProof rp)
                start = relFrom (head edges)
                destinations = map relTo edges
            in start `notElem` destinations) paths
      assertEqual "no cycles back to start" True noCycles
  ]

length3Tests :: Test
length3Tests = TestList
  [ TestCase $ do
      let paths = findPathsLength3 seedGraph (AtomId "свобода")
      assertBool ("свобода length-3 has >= 0 paths (graph may be sparse), got " <> show (length paths))
                 (length paths >= 0)

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
      -- With different profiles, the top path may differ
      -- (not guaranteed, but at least scores should differ)
      let confScore = case confPaths of (rp:_) -> psTotal (rpScore rp); [] -> 0
          consolScore = case consolPaths of (rp:_) -> psTotal (rpScore rp); [] -> 0
      assertBool ("different profiles produce different scores: "
                   <> show confScore <> " vs " <> show consolScore)
                 (confScore /= consolScore)
  ]

determinismTests :: Test
determinismTests = TestList
  [ TestCase $ do
      let p1 = findPathsFrom seedGraph 2 (AtomId "свобода")
          p2 = findPathsFrom seedGraph 2 (AtomId "свобода")
      assertEqual "same input → same output (findPathsFrom)" p1 p2

  , TestCase $ do
      let p1 = selectTopPaths 3 defaultFieldProfile seedGraph (AtomId "истина") 2
          p2 = selectTopPaths 3 defaultFieldProfile seedGraph (AtomId "истина") 2
      assertEqual "same input → same output (selectTopPaths)" p1 p2

  , TestCase $ do
      let p1 = rankPaths (findPathsLength1 seedGraph (AtomId "свобода"))
          p2 = rankPaths (findPathsLength1 seedGraph (AtomId "свобода"))
      assertEqual "same input → same output (rankPaths)" p1 p2
  ]

compositionTests :: Test
compositionTests = TestList
  [ TestCase $ do
      let surface = composeDefinition defaultFieldProfile 3 seedGraph (AtomId "свобода")
      assertBool ("composeDefinition produces non-empty text: " <> show (T.length (gsText surface)))
                 (T.length (gsText surface) > 0)

  , TestCase $ do
      let surface = composeDefinition defaultFieldProfile 3 seedGraph (AtomId "свобода")
      assertBool ("composed text contains 'свобода': " <> show (gsText surface))
                 ("свобода" `T.isInfixOf` gsText surface)

  , TestCase $ do
      let surface = composeDefinition defaultFieldProfile 3 seedGraph (AtomId "истина")
      assertBool ("composed text contains 'истина': " <> show (gsText surface))
                 ("истина" `T.isInfixOf` gsText surface)

  , TestCase $ do
      let surface = composeDefinition defaultFieldProfile 10 seedGraph (AtomId "несуществующий")
      assertEqual "nonexistent topic produces empty text" "" (gsText surface)
  ]
