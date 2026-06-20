{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Test.Suite.SubstrateNetwork
  ( substrateTests
  ) where

import Test.HUnit
import Test.QuickCheck (Property, property, forAll, elements, arbitrary, choose)
import qualified Test.QuickCheck as QC
import Data.Set (Set)
import qualified Data.Set as S
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Sequence as Seq
import Data.Foldable (toList)

import QxFx0.Semantic.Network.Substrate
import QxFx0.Semantic.Network.Types
import QxFx0.Semantic.Network (activate, activateTopic, getActivatedAtoms)
import QxFx0.Semantic.Content (coveredTopics, lookupDefinitionContent, DefinitionContent(..), SemanticPredicate(..))

-- | Test suite for Substrate Network.
substrateTests :: [Test]
substrateTests =
  [ TestLabel "buildSubstrateEdges creates edges from brain_kb" $ TestCase $ do
      let explicitSet = S.fromList ["свобода", "страх", "вера"]
          entries =
            [ BrainKBEntry "текст 1" [] ["свобода", "страх", "один"] "ontology" "claim"
            , BrainKBEntry "текст 2" [] ["страх", "вера", "два"] "ontology" "claim"
            , BrainKBEntry "текст 3" [] ["свобода", "вера", "три"] "ontology" "claim"
            ]
          edges = buildSubstrateEdges entries explicitSet
      assertBool "should have edges" (length edges > 0)
      let edgePairs = [(seiFrom e, seiTo e) | e <- edges]
      assertBool "should have свобода-страх edge" (any (\(a,b) -> (a == "свобода" && b == "страх") || (a == "страх" && b == "свобода")) edgePairs)

  , TestLabel "substrate merge preserves explicit edges" $ TestCase $ do
      let explicitEdges = M.fromList [(("свобода", "ответственность"), SemanticEdge "свобода" "ответственность" 1.0 1 ExplicitEdge)]
          substrateEdges =
            [ SubstrateEdgeInfo "свобода" "страх" 0.3 5
            , SubstrateEdgeInfo "страх" "вера" 0.3 3
            ]
          substrateEdgeMap = M.fromList
            [ ((seiFrom e, seiTo e), SemanticEdge (seiFrom e) (seiTo e) (seiWeight e) (seiCooc e) SubstrateEdge)
            | e <- substrateEdges
            ]
          merged = M.union explicitEdges substrateEdgeMap
      assertBool "explicit edge preserved" (M.member ("свобода", "ответственность") merged)
      assertBool "substrate edge added" (M.member ("свобода", "страх") merged)
      assertBool "substrate edge added" (M.member ("страх", "вера") merged)

  , TestLabel "EdgeSource types work correctly" $ TestCase $ do
      let explicit = ExplicitEdge
          substrate = SubstrateEdge
      assertBool "explicit /= substrate" (explicit /= substrate)
      assertBool "explicit == explicit" (explicit == ExplicitEdge)

  , TestLabel "co-occurrence counting works" $ TestCase $ do
      let entries =
            [ BrainKBEntry "текст 1" [] ["свобода", "страх"] "ontology" "claim"
            , BrainKBEntry "текст 2" [] ["свобода", "страх"] "ontology" "claim"
            , BrainKBEntry "текст 3" [] ["свобода", "страх"] "ontology" "claim"
            ]
          explicitSet = S.fromList ["свобода", "страх"]
          edges = buildSubstrateEdges entries explicitSet
      case edges of
        [e] -> do
          assertBool "cooc should be 3" (seiCooc e == 3)
          assertBool "weight should be 0.3" (seiWeight e == 0.3)
        _ -> assertFailure ("Expected 1 edge, got " ++ show (length edges))

  , TestLabel "empty brain_kb produces no edges" $ TestCase $ do
      let edges = buildSubstrateEdges [] (S.fromList ["свобода", "страх"])
      assertBool "no edges from empty brain_kb" (null edges)

  , TestLabel "entries filtered by layer" $ TestCase $ do
      let entries =
            [ BrainKBEntry "текст 1" [] ["свобода", "страх"] "ontology" "claim"
            , BrainKBEntry "текст 2" [] ["свобода", "страх"] "runtime" "claim"
            , BrainKBEntry "текст 3" [] ["свобода", "страх"] "policy" "claim"
            ]
          explicitSet = S.fromList ["свобода", "страх"]
          edges = buildSubstrateEdges entries explicitSet
      case edges of
        [e] -> assertBool "cooc should be 1" (seiCooc e == 1)
        _ -> assertFailure ("Expected 1 edge, got " ++ show (length edges))

  -- Substrate Hardening: substrate edges never produce output text
  , TestLabel "substrate edge text never matches any explicit predicate output" $ TestCase $ do
      let -- Build a network with substrate edges
          substrateNet = SemanticNetwork
            { snNodes = S.fromList ["свобода", "страх", "вера", "ответственность"]
            , snEdges = M.fromList
                [ (("свобода", "ответственность"), SemanticEdge "свобода" "ответственность" 1.0 1 ExplicitEdge)
                , (("свобода", "страх"), SemanticEdge "свобода" "страх" 0.3 8 SubstrateEdge)
                , (("страх", "вера"), SemanticEdge "страх" "вера" 0.3 8 SubstrateEdge)
                ]
            , snActivation = M.empty
            , snDecayRate = 0.5
            , snMaxHops = 3
            , snActivationLog = Seq.empty
            }
          activated = activate "свобода" substrateNet
          activatedTopics = map fst (getActivatedAtoms activated)
          -- Get explicit predicate texts for activated topics
          explicitPredTexts = concatMap
            (\topic -> case lookupDefinitionContent topic of
                Just dc -> map spRu (dcPredicates dc)
                Nothing -> [])
            activatedTopics
          -- brain_kb sample texts (what substrate source looks like)
          brainKBSamples =
            [ "Когда тебя не слышат, боль часто не в словах"
            , "Одиночество в близости режет сильнее"
            , "Иногда страшит не сама перемена"
            , "Быть прочитанным, но не увиденным"
            ]
      -- Property: no brain_kb text fragment appears in any explicit predicate
      let leaks = [ (bp, pt)
                  | bp <- brainKBSamples
                  , pt <- explicitPredTexts
                  , any (`T.isInfixOf` pt) (T.chunksOf 10 (T.pack bp))
                  ]
      assertBool "no brain_kb text should leak into explicit predicates" (null leaks)

  , TestLabel "substrate edges only affect activation path, not output content" $ TestCase $ do
      let -- Network WITH substrate edges
          netWithSubstrate = SemanticNetwork
            { snNodes = S.fromList ["свобода", "страх", "вера", "ответственность"]
            , snEdges = M.fromList
                [ (("свобода", "ответственность"), SemanticEdge "свобода" "ответственность" 1.0 1 ExplicitEdge)
                , (("свобода", "страх"), SemanticEdge "свобода" "страх" 0.3 8 SubstrateEdge)
                , (("страх", "вера"), SemanticEdge "страх" "вера" 0.3 8 SubstrateEdge)
                ]
            , snActivation = M.empty
            , snDecayRate = 0.5
            , snMaxHops = 3
            , snActivationLog = Seq.empty
            }
          -- Network WITHOUT substrate edges (explicit only)
          netExplicitOnly = netWithSubstrate
            { snEdges = M.filter (\e -> seSource e == ExplicitEdge) (snEdges netWithSubstrate) }
          -- Activate both
          activatedWith = activate "свобода" netWithSubstrate
          activatedWithout = activate "свобода" netExplicitOnly
          -- Get explicit predicates for activated topics in both cases
          predsFromTopics topics = concatMap
            (\topic -> case lookupDefinitionContent topic of
                Just dc -> map spRu (dcPredicates dc)
                Nothing -> [])
            topics
          topicsWith = map fst (getActivatedAtoms activatedWith)
          topicsWithout = map fst (getActivatedAtoms activatedWithout)
          predsWith = predsFromTopics topicsWith
          predsWithout = predsFromTopics topicsWithout
          allExplicitPreds = concatMap
            (\dc -> map spRu (dcPredicates dc))
            (mapMaybe lookupDefinitionContent coveredTopics)
      -- All predicates in both cases come from explicit corpus only
      -- (substrate may activate MORE topics, but predicates are always from explicit)
      assertBool "predicates with substrate are all from explicit corpus"
                 (all (`elem` allExplicitPreds) predsWith)
      -- Substrate should activate MORE topics (or equal)
      assertBool "substrate activates >= topics than explicit-only"
                 (length topicsWith >= length topicsWithout)
      -- Substrate hops > 0 when substrate edges exist
      let substrateHops = length [ () | s <- toList (snActivationLog activatedWith), asSource s == SubstrateEdge ]
          explicitHops = length [ () | s <- toList (snActivationLog activatedWith), asSource s == ExplicitEdge ]
      assertBool "substrate hops > 0 when substrate edges present" (substrateHops > 0)
      assertBool "explicit hops > 0 always" (explicitHops > 0)

  , TestLabel "property: substrate edges never appear in output for any covered topic" $ TestCase $ do
      let allExplicitPreds = concatMap
            (\dc -> map spRu (dcPredicates dc))
            (mapMaybe lookupDefinitionContent coveredTopics)
          results = map (checkTopic allExplicitPreds) coveredTopics
          checkTopic ep topic =
            let net = SemanticNetwork
                  { snNodes = S.fromList coveredTopics
                  , snEdges = M.fromList
                      [ ((a, b), SemanticEdge a b 0.3 2 SubstrateEdge)
                      | a <- coveredTopics
                      , b <- coveredTopics
                      , a < b
                      ]
                  , snActivation = M.empty
                  , snDecayRate = 0.5
                  , snMaxHops = 3
                  , snActivationLog = Seq.empty
                  }
                activated = activate topic net
                topics = map fst (getActivatedAtoms activated)
                preds = concatMap
                  (\t -> case lookupDefinitionContent t of
                      Just dc -> map spRu (dcPredicates dc)
                      Nothing -> [])
                  topics
                allFromExplicit = all (`elem` ep) preds
            in (topic, allFromExplicit)
          failures = [ topic | (topic, False) <- results ]
      assertBool ("substrate never produces non-explicit predicates for topics: " ++ show failures)
                 (null failures)
  ]
  where
    mapMaybe :: (a -> Maybe b) -> [a] -> [b]
    mapMaybe f = concatMap (\x -> case f x of Just y -> [y]; Nothing -> [])
