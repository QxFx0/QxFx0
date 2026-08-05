{-# LANGUAGE OverloadedStrings #-}

-- | P2.3 regression tests for ontology-driven predicate borrowing
-- and depth weighting in the content selector.
module Test.Suite.OntologyContentSelector
  ( ontologyContentSelectorTests
  ) where

import qualified Data.Map.Strict as M
import qualified Data.Set as S
import Data.Text (Text)
import Test.HUnit

import QxFx0.Semantic.Content (SemanticPredicate(..), PredicateRole(..))
import QxFx0.Semantic.ContentSelector
  ( ContentSelector
  , buildContentSelector
  , composeFromActivation
  , ontologyRelatedTopics
  , ontologyDepthBoost
  , csTopicAtoms
  , csOntology
  )
import QxFx0.Semantic.Network (SemanticNetwork(..), emptySemanticNetwork)
import QxFx0.Semantic.Network.Types (SemanticEdge(..), EdgeSource(..), EdgeProvenance(..))
import QxFx0.Semantic.Ontology
  ( Ontology(..)
  , OntologyNode(..)
  , ConceptCategory(..)
  , emptyOntology
  )
import QxFx0.Semantic.Space (SemanticSpace(..), emptySemanticSpace)
import QxFx0.Self.Field (Field(..), emptyField, FieldHeuristics(..), builtinFieldHeuristics)

mkOnto :: Text -> ConceptCategory -> Maybe Text -> Int -> OntologyNode
mkOnto name category parent depth =
  OntologyNode name category parent S.empty depth

parentChildOntology :: Ontology
parentChildOntology = Ontology
  { otNodes = M.fromList
      [ ("parent", mkOnto "parent" CategoryGeneral Nothing 0)
      , ("child",  mkOnto "child"  CategoryGeneral (Just "parent") 1)
      , ("sibling", mkOnto "sibling" CategoryGeneral (Just "parent") 1)
      ]
  , otRoots = S.singleton "parent"
  }

semanticEdge :: Text -> Text -> Double -> Int -> EdgeSource -> SemanticEdge
semanticEdge f t w cooc source =
  SemanticEdge f t w cooc source Nothing Nothing Nothing Nothing Nothing 1.0 ProvenanceCurated Nothing Nothing Nothing Nothing

childOnlySelector :: Ontology -> SemanticSpace -> ContentSelector
childOnlySelector ont space =
  let topicAtoms = M.fromList
        [ ("child",  S.fromList ["child_atom"])
        , ("sibling", S.fromList ["sibling_atom"])
        ]
      siblingPred = SemanticPredicate RoleProperty "sibling predicate" "sibling predicate" "sibling" Nothing Nothing Nothing Nothing
      topicPredicates = M.fromList
        [ ("sibling", [siblingPred])
        ]
  in buildContentSelector space topicAtoms topicPredicates M.empty (Just ont)

testOntologyRelatedTopics :: Test
testOntologyRelatedTopics = TestLabel "ontologyRelatedTopics returns siblings" $ TestCase $
  let cs = childOnlySelector parentChildOntology emptySemanticSpace
      related = ontologyRelatedTopics cs "child"
  in assertBool "child should see sibling as related"
       ("sibling" `elem` related)

testContentSelectorCarriesOntology :: Test
testContentSelectorCarriesOntology = TestLabel "ContentSelector created with ontology carries Just ontology" $ TestCase $
  let cs = childOnlySelector parentChildOntology emptySemanticSpace
  in assertBool "csOntology should be present" (case csOntology cs of Just _ -> True; Nothing -> False)

testDepthBoostDisabledByDefault :: Test
testDepthBoostDisabledByDefault = TestLabel "default ontology depth boost is zero" $ TestCase $
  let cs = childOnlySelector parentChildOntology emptySemanticSpace
      boost = ontologyDepthBoost cs builtinFieldHeuristics "sibling"
  in assertEqual "default fhOntologyDepthBoost must be 0.0" 0.0 boost

testDepthBoostEnabled :: Test
testDepthBoostEnabled = TestLabel "depth boost increases with node depth" $ TestCase $
  let cs = childOnlySelector parentChildOntology emptySemanticSpace
      heuristics = builtinFieldHeuristics { fhOntologyDepthBoost = 0.5 }
      boost = ontologyDepthBoost cs heuristics "sibling"
  in assertBool "depth boost should be positive for depth=1" (boost > 0.0)

ontologyContentSelectorTests :: [Test]
ontologyContentSelectorTests =
  [ testOntologyRelatedTopics
  , testContentSelectorCarriesOntology
  , testDepthBoostDisabledByDefault
  , testDepthBoostEnabled
  ]
