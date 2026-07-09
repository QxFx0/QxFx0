{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.CuratedPredicates
Description : P1.2 — curated predicate corpus loading and admission.
-}
module Test.Suite.CuratedPredicates
  ( curatedPredicatesTests
  ) where

import qualified Data.Map.Strict as M
import Data.Maybe (isJust)
import qualified Data.Text as T
import System.Directory (doesFileExist)
import Test.HUnit

import QxFx0.Semantic.Content
  ( DefinitionContent(..)
  , definitionCorpus
  , spRu
  )
import QxFx0.Semantic.Content.Curated
  ( curatedPredicatesPath
  , extendedDefinitionCorpus
  , loadCuratedPredicates
  , mergeCuratedIntoDefinitionCorpus
  )
import QxFx0.Semantic.Network.Ingest (admitRelationEndpoint, normalizeRelationText)

-- | The curated predicates file must exist and contain the first five gap
-- topics from @docs/GAPS.md@, each with at least two predicates.
testCuratedPredicatesLoad :: Test
testCuratedPredicatesLoad = TestLabel "curated predicates load with first 5 gaps" $ TestCase $ do
  exists <- doesFileExist curatedPredicatesPath
  assertBool "curated_predicates.jsonl must exist" exists
  curated <- loadCuratedPredicates curatedPredicatesPath
  let expectedTopics = ["смысл", "идентичность", "граница", "ремонт", "цифра"]
      missing = filter (\t -> not (M.member t curated)) expectedTopics
  assertEqual "first 5 gap topics must be present in curated predicates"
    [] missing
  mapM_ (\t ->
           case M.lookup t curated of
             Nothing -> assertFailure ("topic " ++ T.unpack t ++ " missing")
             Just dc -> assertBool ("topic " ++ T.unpack t ++ " must have >=2 predicates")
                                   (length (dcPredicates dc) >= 2))
        expectedTopics

-- | Merging curated predicates into the seed corpus extends coverage: a
-- hardcoded topic and a curated topic are both reachable.
testCuratedMergeExtendsDefinitionCorpus :: Test
testCuratedMergeExtendsDefinitionCorpus = TestLabel "extended corpus covers seed and curated topics" $ TestCase $ do
  curated <- loadCuratedPredicates curatedPredicatesPath
  let extended = mergeCuratedIntoDefinitionCorpus curated definitionCorpus
  assertBool "seed topic 'свобода' must still be present"
    (isJust (M.lookup "свобода" extended))
  assertBool "curated topic 'смысл' must be present"
    (isJust (M.lookup "смысл" extended))

-- | A curated topic contains the expected Russian predicate surface form.
testCuratedPredicatesAdmitted :: Test
testCuratedPredicatesAdmitted = TestLabel "curated topic contains expected Russian predicate" $ TestCase $ do
  extended <- extendedDefinitionCorpus
  case M.lookup "смысл" extended of
    Nothing -> assertFailure "смысл should be present in extended corpus"
    Just dc -> do
      let ruPreds = map spRu (dcPredicates dc)
      assertBool "смысл predicate should mention 'понимание'"
        (any ("понимание" `T.isInfixOf`) ruPreds)

-- | A relation-rationale endpoint that corresponds to a curated gap concept
-- must pass the admission gate after normalization.
testCuratedConceptAdmittedByRelationGate :: Test
testCuratedConceptAdmittedByRelationGate = TestLabel "curated gap concept admitted through relation gate" $ TestCase $ do
  let normalized = normalizeRelationText "смысл"
  assertEqual "смысл normalizes to itself" "смысл" normalized
  assertBool "смысл must be admitted as a relation endpoint"
    (isJust (admitRelationEndpoint "смысл"))

curatedPredicatesTests :: [Test]
curatedPredicatesTests =
  [ testCuratedPredicatesLoad
  , testCuratedMergeExtendsDefinitionCorpus
  , testCuratedPredicatesAdmitted
  , testCuratedConceptAdmittedByRelationGate
  ]
