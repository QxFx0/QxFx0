{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.LogicInference
Description : Tests for semantic edge logical inference (transitivity, symmetry, lineage).
-}
module Test.Suite.LogicInference
  ( logicInferenceTests
  ) where

import Test.HUnit (Test (..), assertBool, assertEqual, assertFailure)

import qualified Data.Map.Strict as M
import qualified Data.Set as S
import qualified Data.Sequence as Seq
import Data.Maybe (fromMaybe)
import Data.Text (Text)

import QxFx0.Semantic.Content.AtomStore (RelationType(..))
import QxFx0.Semantic.Logic.Inference
  ( inferEdges
  , inferTransitiveEdges
  , inferSymmetricEdges
  , applyInference
  , applyInferenceUntilFixpoint
  , explainPath
  )
import QxFx0.Semantic.Network.Types
  ( EdgeProvenance(..)
  , EdgeNamespace(..)
  , EdgeSource(..)
  , SemanticEdge(..)
  , SemanticNetwork(..)
  )

mkEdge :: Text -> Text -> RelationType -> Double -> SemanticEdge
mkEdge from to rt conf = SemanticEdge
  { seFrom          = from
  , seTo            = to
  , seWeight        = conf
  , seCoOccurrence  = 1
  , seSource        = ExplicitEdge
  , seRelationType  = Just rt
  , seDomain        = Nothing
  , seTemporalScope = Nothing
  , seVerb          = Nothing
  , seRationale     = Nothing
  , seCounter       = Nothing
  , seSynthesis     = Nothing
  , seConfidence    = conf
  , seProvenance    = ProvenanceIngested
  , seNamespace     = NamespaceSessionLocal
  , seLineage       = Nothing
  }

mkNetwork :: [SemanticEdge] -> SemanticNetwork
mkNetwork edges = SemanticNetwork
  { snNodes = S.fromList (concatMap (\e -> [seFrom e, seTo e]) edges)
  , snEdges = M.fromList [((seFrom e, seTo e), e) | e <- edges]
  , snActivation = M.empty
  , snDecayRate = 0.5
  , snMaxHops = 3
  , snActivationLog = Seq.empty
  }

logicInferenceTests :: [Test]
logicInferenceTests =
  [ TestLabel "transitivity derives A -> C from A -> B and B -> C" $
      TestCase $ do
        let e1 = mkEdge "A" "B" RelRequires 0.8
            e2 = mkEdge "B" "C" RelRequires 0.8
            derived = inferTransitiveEdges [e1, e2]
        assertEqual "one derived edge" 1 (length derived)
        let d = head derived
        assertEqual "derived from" "A" (seFrom d)
        assertEqual "derived to" "C" (seTo d)
        assertEqual "derived provenance" ProvenanceDerived (seProvenance d)

  , TestLabel "transitivity does not derive when middle nodes mismatch" $
      TestCase $ do
        let e1 = mkEdge "A" "B" RelRequires 0.8
            e2 = mkEdge "X" "C" RelRequires 0.8
        assertEqual "no derived edge" [] (inferTransitiveEdges [e1, e2])

  , TestLabel "symmetry derives B -> A from A contrastsWith B" $
      TestCase $ do
        let e1 = mkEdge "A" "B" RelContrastsWith 0.8
            derived = inferSymmetricEdges [e1]
        assertEqual "one symmetric edge" 1 (length derived)
        let d = head derived
        assertEqual "derived from" "B" (seFrom d)
        assertEqual "derived to" "A" (seTo d)
        assertEqual "derived relation" (Just RelContrastsWith) (seRelationType d)
        assertEqual "derived provenance" ProvenanceDerived (seProvenance d)

  , TestLabel "derived edge carries lineage pointing to parents" $
      TestCase $ do
        let e1 = mkEdge "A" "B" RelRequires 0.8
            e2 = mkEdge "B" "C" RelRequires 0.8
            derived = inferTransitiveEdges [e1, e2]
        assertBool "derived edges exist" (not (null derived))
        let d = head derived
        case seLineage d of
          Nothing -> assertFailure "derived edge missing lineage"
          Just refs -> assertBool "lineage contains parents"
            (("A", "B") `elem` refs && ("B", "C") `elem` refs)

  , TestLabel "applyInference inserts derived edges without overwriting" $
      TestCase $ do
        let e1 = mkEdge "A" "B" RelRequires 0.8
            e2 = mkEdge "B" "C" RelRequires 0.8
            net0 = mkNetwork [e1, e2]
            net1 = applyInference net0
        assertEqual "two original edges" 2 (M.size (snEdges net0))
        assertEqual "three edges after inference" 3 (M.size (snEdges net1))
        case M.lookup ("A", "C") (snEdges net1) of
          Nothing -> assertFailure "derived A->C missing"
          Just d  -> assertEqual "derived provenance" ProvenanceDerived (seProvenance d)

  , TestLabel "applyInference does not duplicate existing derived edges" $
      TestCase $ do
        let e1 = mkEdge "A" "B" RelRequires 0.8
            e2 = mkEdge "B" "C" RelRequires 0.8
            net0 = mkNetwork [e1, e2]
            net1 = applyInference net0
            net2 = applyInference net1
        assertEqual "still three edges after second inference" 3 (M.size (snEdges net2))

  , TestLabel "fixpoint inference derives multi-hop A -> D" $
      TestCase $ do
        let e1 = mkEdge "A" "B" RelRequires 0.8
            e2 = mkEdge "B" "C" RelRequires 0.8
            e3 = mkEdge "C" "D" RelRequires 0.8
            net0 = mkNetwork [e1, e2, e3]
            net1 = applyInferenceUntilFixpoint net0
        case M.lookup ("A", "D") (snEdges net1) of
          Nothing -> assertFailure "multi-hop A->D missing"
          Just d  -> do
            assertEqual "multi-hop provenance" ProvenanceDerived (seProvenance d)
            assertBool "multi-hop confidence bounded" (seConfidence d <= 0.8)

  , TestLabel "explainPath finds shortest multi-hop path" $
      TestCase $ do
        let e1 = mkEdge "A" "B" RelRequires 0.8
            e2 = mkEdge "B" "C" RelRequires 0.8
            e3 = mkEdge "C" "D" RelRequires 0.8
            net = mkNetwork [e1, e2, e3]
        case explainPath net "A" "D" of
          Nothing -> assertFailure "expected path A->D"
          Just path -> assertEqual "path length 3" 3 (length path)

  , TestLabel "explainPath uses derived shortcut when available" $
      TestCase $ do
        let e1 = mkEdge "A" "B" RelRequires 0.8
            e2 = mkEdge "B" "C" RelRequires 0.8
            e3 = mkEdge "C" "D" RelRequires 0.8
            net = applyInferenceUntilFixpoint (mkNetwork [e1, e2, e3])
        case explainPath net "A" "D" of
          Nothing -> assertFailure "expected path A->D"
          Just path -> do
            assertEqual "shortcut path length 1" 1 (length path)
            assertEqual "shortcut is derived" ProvenanceDerived (seProvenance (head path))

  , TestLabel "explainPath returns Nothing for disconnected nodes" $
      TestCase $ do
        let e1 = mkEdge "A" "B" RelRequires 0.8
            net = mkNetwork [e1]
        assertEqual "no path A->Z" Nothing (explainPath net "A" "Z")
  ]
