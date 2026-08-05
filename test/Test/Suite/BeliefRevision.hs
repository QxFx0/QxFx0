{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.BeliefRevision
Description : Tests for contradiction-driven belief revision and lineage propagation.
-}
module Test.Suite.BeliefRevision
  ( beliefRevisionTests
  ) where

import Test.HUnit (Test (..), assertBool, assertEqual, assertFailure)

import qualified Data.Map.Strict as M
import Data.Text (Text)

import QxFx0.Semantic.Content.AtomStore (RelationType(..))
import QxFx0.Semantic.Logic.BeliefRevision
  ( Contradiction(..)
  , Resolution(..)
  , ResolutionAction(..)
  , detectContradictions
  , resolveContradictions
  , resolveContradictionsWithConfig
  , defaultRevisionConfig
  )
import QxFx0.Semantic.Network.Types
  ( EdgeProvenance(..)
  , EdgeNamespace(..)
  , EdgeSource(..)
  , SemanticEdge(..)
  )

mkEdge :: Text -> Text -> RelationType -> EdgeProvenance -> Double -> SemanticEdge
mkEdge from to rt prov conf = SemanticEdge
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
  , seProvenance    = prov
  , seNamespace     = Just NamespaceSessionLocal
  , seLineage       = Nothing
  }

-- | Find the unique edge in the list matching the given (from, to).
findEdge :: Text -> Text -> [SemanticEdge] -> Maybe SemanticEdge
findEdge f t edges =
  case [ e | e <- edges, seFrom e == f, seTo e == t ] of
    (e:_) -> Just e
    []    -> Nothing

beliefRevisionTests :: [Test]
beliefRevisionTests =
  [ TestLabel "detectContradictions finds positive vs negative on same pair" $
      TestCase $ do
        let e1 = mkEdge "A" "B" RelRequires ProvenanceIngested 0.8
            e2 = mkEdge "A" "B" RelContrastsWith ProvenanceIngested 0.6
            edges = [e1, e2]
        case detectContradictions edges of
          [c] -> do
            assertEqual "stronger is positive" (Just RelRequires) (seRelationType (cStronger c))
            assertEqual "weaker is negative" (Just RelContrastsWith) (seRelationType (cWeaker c))
          _ -> assertFailure "expected exactly one contradiction"

  , TestLabel "resolveContradictions weakens lower-confidence edge" $
      TestCase $ do
        let e1 = mkEdge "A" "B" RelRequires ProvenanceIngested 0.8
            e2 = mkEdge "A" "B" RelContrastsWith ProvenanceIngested 0.6
            edges = [e1, e2]
            (resolved, resols) = resolveContradictions edges
        assertEqual "one resolution" 1 (length resols)
        case findEdge "A" "B" resolved of
          Nothing -> assertFailure "A -> B should remain"
          Just e  -> assertEqual "positive edge unchanged" 0.8 (seConfidence e)
        case rAction (head resols) of
          Weakened conf -> assertBool "weakened confidence below original" (conf < 0.6)
          Quarantined   -> assertFailure "should have weakened, not quarantined"

  , TestLabel "resolveContradictions quarantines edge below threshold" $
      TestCase $ do
        let e1 = mkEdge "A" "B" RelRequires ProvenanceIngested 0.8
            e2 = mkEdge "A" "B" RelContrastsWith ProvenanceIngested 0.3
            edges = [e1, e2]
            (resolved, resols) = resolveContradictions edges
        assertEqual "one resolution" 1 (length resols)
        assertEqual "negative edge removed" Nothing
          (findEdge "A" "B" resolved >>= \e ->
             if seRelationType e == Just RelContrastsWith then Just e else Nothing)
        case rAction (head resols) of
          Quarantined -> pure ()
          _           -> assertFailure "should have quarantined"

  , TestLabel "weakening propagates to derived edges via lineage" $
      TestCase $ do
        let e1 = mkEdge "A" "B" RelRequires ProvenanceIngested 0.9
            e2 = mkEdge "A" "B" RelContrastsWith ProvenanceIngested 0.6
            derived = (mkEdge "B" "C" RelRequires ProvenanceDerived 0.8)
                        { seLineage = Just [("A", "B", RelContrastsWith, NamespaceSessionLocal)] }
            edges = [e1, e2, derived]
            (resolved, _resols) = resolveContradictions edges
        case findEdge "B" "C" resolved of
          Nothing -> assertFailure "B -> C derived edge should remain"
          Just e  ->
            if seProvenance e == ProvenanceDerived
              then assertBool "derived edge weakened by propagation" (seConfidence e < 0.8)
              else assertFailure "expected derived edge at B -> C"
  ]
