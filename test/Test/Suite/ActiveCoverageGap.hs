{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.ActiveCoverageGap
Description : Tests for dynamic active-learning coverage-gap detection.
-}
module Test.Suite.ActiveCoverageGap
  ( activeCoverageGapTests
  ) where

import Test.HUnit (Test (..), assertBool, assertEqual, assertFailure)

import Data.Text (Text)

import QxFx0.Learning.ActiveCoverageGap
  ( CoverageGap(..)
  , GapConfig(..)
  , defaultGapConfig
  , findCoverageGapsWithConfig
  )
import QxFx0.Semantic.Content.AtomStore (RelationType(..))
import QxFx0.Semantic.Network.Types
  ( EdgeNamespace(..)
  , EdgeProvenance(..)
  , EdgeSource(..)
  , SemanticEdge(..)
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

activeCoverageGapTests :: [Test]
activeCoverageGapTests =
  [ TestLabel "findCoverageGaps detects shared-out-neighbour gap" $
      TestCase $ do
        let edges =
              [ mkEdge "A" "C" RelRequires 0.8
              , mkEdge "B" "C" RelRequires 0.7
              , mkEdge "C" "D" RelRequires 0.9
              ]
            cfg = defaultGapConfig { gcMinCommonNeighbors = 1, gcMaxResults = 5 }
            gaps = findCoverageGapsWithConfig cfg edges
        case gaps of
          [g] -> do
            assertEqual "gap from A" "A" (cgFrom g)
            assertEqual "gap to B" "B" (cgTo g)
            assertBool "positive score" (cgScore g > 0)
          _ -> assertFailure $ "expected exactly one gap, got " <> show (length gaps)

  , TestLabel "findCoverageGaps ignores existing direct edges" $
      TestCase $ do
        let edges =
              [ mkEdge "A" "B" RelRequires 0.8
              , mkEdge "A" "C" RelRequires 0.8
              , mkEdge "B" "C" RelRequires 0.7
              ]
            cfg = defaultGapConfig { gcMaxResults = 5 }
            gaps = findCoverageGapsWithConfig cfg edges
        assertEqual "no gaps when A->B already exists" 0 (length gaps)

  , TestLabel "findCoverageGaps detects shared-in-neighbour gap" $
      TestCase $ do
        let edges =
              [ mkEdge "C" "A" RelRequires 0.8
              , mkEdge "C" "B" RelRequires 0.7
              , mkEdge "D" "C" RelRequires 0.9
              ]
            cfg = defaultGapConfig { gcMinCommonNeighbors = 1, gcMaxResults = 5 }
            gaps = findCoverageGapsWithConfig cfg edges
        assertEqual "one gap from shared in-neighbour C" 1 (length gaps)

  , TestLabel "findCoverageGaps respects maxResults" $
      TestCase $ do
        let edges =
              [ mkEdge "A" "C" RelRequires 0.8
              , mkEdge "B" "C" RelRequires 0.7
              , mkEdge "A" "D" RelRequires 0.8
              , mkEdge "B" "D" RelRequires 0.7
              ]
            cfg = defaultGapConfig { gcMaxResults = 1 }
            gaps = findCoverageGapsWithConfig cfg edges
        assertEqual "returns at most maxResults" 1 (length gaps)

  , TestLabel "findCoverageGaps returns empty for disconnected graph" $
      TestCase $ do
        let edges =
              [ mkEdge "A" "B" RelRequires 0.8
              , mkEdge "C" "D" RelRequires 0.7
              ]
            cfg = defaultGapConfig { gcMaxResults = 5 }
            gaps = findCoverageGapsWithConfig cfg edges
        assertEqual "no shared neighbours" 0 (length gaps)
  ]
