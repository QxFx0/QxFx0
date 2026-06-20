{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.SubstrateNetwork
  ( substrateTests
  ) where

import Test.HUnit
import Data.Set (Set)
import qualified Data.Set as S
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Semantic.Network.Substrate
import QxFx0.Semantic.Network.Types

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
  ]
