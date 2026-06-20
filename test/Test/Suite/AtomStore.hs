{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.AtomStore (atomStoreTests) where

import Test.HUnit
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Map.Strict as M
import QxFx0.Semantic.Content.AtomStore

atomStoreTests :: [Test]
atomStoreTests =
  [ TestLabel "AtomStore round-trip parity (stored)" roundTripTests
  , TestLabel "AtomStore morph round-trip (display)" morphRoundTripTests
  , TestLabel "AtomStore structure" structureTests
  ]

roundTripTests :: Test
roundTripTests = TestList
  [ TestCase $ do
      let mismatches = [ (orig, verb) | (orig, verb, False) <- allRoundTripResults ]
          total = length allRoundTripResults
          matchCount = total - length mismatches
      assertEqual ("stored round-trip: " <> show matchCount <> "/" <> show total
                   <> " matched, mismatches: " <> show (take 5 mismatches))
                  0 (length mismatches)
  ]

morphRoundTripTests :: Test
morphRoundTripTests = TestList
  [ TestCase $ do
      let mismatches = [ (orig, verb) | (orig, verb, False) <- allRoundTripMorphResults ]
          total = length allRoundTripMorphResults
          matchCount = total - length mismatches
      assertBool ("morph round-trip: " <> show matchCount <> "/" <> show total
                   <> " matched (< 70%), mismatches: " <> show (take 3 mismatches))
                 (matchCount * 10 >= total * 7)
  ]

structureTests :: Test
structureTests = TestList
  [ TestCase $ do
      let missingFrom = [ show (relFrom r) | r <- relationStore
                            , M.notMember (relFrom r) atomStore ]
      assertEqual ("all relFrom atoms exist in store, missing: " <> show missingFrom)
                  [] missingFrom

  , TestCase $ do
      let missingTo = [ show (relTo r) | r <- relationStore
                           , M.notMember (relTo r) atomStore ]
      assertEqual ("all relTo atoms exist in store, missing: " <> show missingTo)
                  [] missingTo

  , TestCase $ do
      assertEqual "30 topics in store" 30 (length allTopics)

  , TestCase $ do
      let relCount = length relationStore
      assertBool ("relation count >= 60, got " <> show relCount)
                 (relCount >= 60)

  , TestCase $ do
      let freedomRels = relationsFromAtom (AtomId "свобода")
      assertBool ("свобода has >= 2 relations, got " <> show (length freedomRels))
                 (length freedomRels >= 2)

  , TestCase $ do
      let allHaveTopic = all (\r -> relTopic r /= "") relationStore
      assertEqual "all relations have topic" True allHaveTopic

  , TestCase $ do
      let allSeed = all (\r -> relSource r == SeedFromPredicate) relationStore
      assertEqual "all relations are SeedFromPredicate" True allSeed
  ]
