{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.OntologyCategoryClassification
  ( ontologyCategoryClassificationTests
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Set (Set)
import qualified Data.Set as S
import Data.Text (Text)
import Test.HUnit

import QxFx0.Semantic.Content
  ( ConceptCategory(..)
  , classifyConceptCategory
  , categoryFromOntology
  )
import QxFx0.Semantic.Ontology
  ( Ontology(..)
  , OntologyNode(..)
  , emptyOntology
  , loadOntology
  )

-- | Minimal ontology for unit tests.
testOntology :: Ontology
testOntology = Ontology
  { otNodes = M.fromList
      [ ("свобода", OntologyNode "свобода" CategoryPhilosophical (Just "философия") S.empty 2)
      , ("память", OntologyNode "память" CategoryPsychological (Just "психология") S.empty 2)
      , ("философия", OntologyNode "философия" CategoryPhilosophical Nothing (S.fromList ["свобода"]) 0)
      , ("психология", OntologyNode "психология" CategoryPsychological Nothing (S.fromList ["память"]) 0)
      ]
  , otRoots = S.fromList ["философия", "психология"]
  }

ontologyCategoryClassificationTests :: [Test]
ontologyCategoryClassificationTests =
  [ TestLabel "known philosophical concept returns CategoryPhilosophical" $ TestCase $ do
      assertEqual "свобода" CategoryPhilosophical (classifyConceptCategory testOntology "свобода")
      assertEqual "normalized whitespace" CategoryPhilosophical (classifyConceptCategory testOntology "  Свобода  ")

  , TestLabel "known psychological concept returns CategoryPsychological" $ TestCase $ do
      assertEqual "память" CategoryPsychological (classifyConceptCategory testOntology "память")

  , TestLabel "categoryFromOntology returns Nothing for unknown concept" $ TestCase $ do
      assertEqual "unknown" Nothing (categoryFromOntology testOntology "неизвестное")

  , TestLabel "unknown concept falls back to lexical classification" $ TestCase $ do
      assertEqual "physical marker телo" CategoryPhysical (classifyConceptCategory testOntology "тело")
      assertEqual "social marker обществo" CategorySocial (classifyConceptCategory testOntology "общество")

  , TestLabel "empty ontology recovers lexical classification" $ TestCase $ do
      assertEqual "empty ontology lexical fallback" CategoryPhilosophical (classifyConceptCategory emptyOntology "свобода")

  , TestLabel "real ontology loads and classifies sample topics" $ TestCase $ do
      ot <- loadOntology "resources/knowledge/ontology.jsonl"
      assertEqual "real ontology свобода" CategoryPhilosophical (classifyConceptCategory ot "свобода")
      assertEqual "real ontology память" CategoryPsychological (classifyConceptCategory ot "память")
      assertEqual "real ontology ответственность" CategorySocial (classifyConceptCategory ot "ответственность")
      assertBool "real ontology has nodes" (not (M.null (otNodes ot)))
  ]
