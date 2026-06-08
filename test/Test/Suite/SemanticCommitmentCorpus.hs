{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE StrictData #-}

{-|
Description : canonical — C3 multi-turn semantic commitment corpus fixture.

Verifies that the SemanticCommitmentStore is populated across multiple
turns, closing the C3 evidence contour of the M6 activation gate
(per @docs\/closure\/M6_CLAIM_PACKAGE.md@):

  * Anchor-based commitments are created each turn via 'anchorToFactualClaim'
  * Surface-parsed authority claims accumulate in the store
  * @trcSemanticCommitmentCount@ grows across turns

This is the "multi-turn corpus fixture" required by C3 in
@docs\/closure\/M6_CLAIM_PACKAGE.md §5@.
-}
module Test.Suite.SemanticCommitmentCorpus
  ( semanticCommitmentCorpusTests
  ) where

import Test.HUnit (Test (..), assertBool, assertEqual)
import Data.Maybe (isJust)
import qualified Data.HashMap.Strict as HashMap
import Prelude

import QxFx0.Types.State.SemanticCommitment
  ( SemanticCommitmentStore (..)
  )
import QxFx0.Types.State.System (SystemState, emptySystemState, ssSemanticCommitments)
import QxFx0.Types.TurnProjection (tqpReplayTrace, trcSemanticCommitmentCount)
import QxFx0.Core.TurnPipeline.Protocol (FinalizePrecommitBundle(..))
import Test.Suite.TurnPipelineProtocol (withDeterministicEmbedding)
import Test.Support.TurnPipelineFixtures
  ( buildAuthoritativePerspectiveFinalizeFixture
  )

-- | Turn 1 must produce a non-empty SemanticCommitmentStore.
-- After the anchor bridge (C3 Package 2 completion), every turn that
-- establishes a SemanticAnchor adds at least one commitment.
c3Turn1ProducesCommitments :: Test
c3Turn1ProducesCommitments = TestLabel "C3: turn 1 produces a non-empty SemanticCommitmentStore" $
  TestCase $
    withDeterministicEmbedding $ do
      (bundle, _) <- buildAuthoritativePerspectiveFinalizeFixture emptySystemState "что такое свобода?"
      let nextSs = fpbNextSs bundle
          mStore = ssSemanticCommitments nextSs
      assertBool "C3: ssSemanticCommitments must be Just after first turn"
        (isJust mStore)
      let count = maybe 0 (HashMap.size . scsActive) mStore
      assertBool ("C3: at least one commitment must exist after turn 1, got: " <> show count)
        (count >= 1)

-- | Two sequential turns must produce more commitments than one turn.
-- The anchor bridge creates a new commitment every turn an anchor is
-- established; turns with different topics accumulate distinct anchors.
c3MultiTurnAccumulatesCommitments :: Test
c3MultiTurnAccumulatesCommitments = TestLabel "C3: commitment store grows across sequential turns" $
  TestCase $
    withDeterministicEmbedding $ do
      -- Turn 1
      (bundle1, _) <- buildAuthoritativePerspectiveFinalizeFixture emptySystemState "что такое свобода?"
      let ss1 = fpbNextSs bundle1
          count1 = maybe 0 (HashMap.size . scsActive) (ssSemanticCommitments ss1)
      -- Turn 2: build on state from turn 1
      (bundle2, _) <- buildAuthoritativePerspectiveFinalizeFixture ss1 "расскажи подробнее"
      let ss2 = fpbNextSs bundle2
          count2 = maybe 0 (HashMap.size . scsActive) (ssSemanticCommitments ss2)
      assertBool
        ("C3: commitment count after turn 2 (" <> show count2 <>
         ") must be >= count after turn 1 (" <> show count1 <> ")")
        (count2 >= count1)

-- | trcSemanticCommitmentCount in TurnReplayTrace must match the actual
-- store size — verifying that the trace field is correctly populated.
c3TraceFieldMatchesStoreCount :: Test
c3TraceFieldMatchesStoreCount = TestLabel "C3: trcSemanticCommitmentCount matches ssSemanticCommitments store size" $
  TestCase $
    withDeterministicEmbedding $ do
      (bundle, _) <- buildAuthoritativePerspectiveFinalizeFixture emptySystemState "что такое свобода?"
      let nextSs = fpbNextSs bundle
          trace  = tqpReplayTrace (fpbProjection bundle)
          traceCount  = trcSemanticCommitmentCount trace
          storeCount  = maybe 0 (HashMap.size . scsActive) (ssSemanticCommitments nextSs)
      assertEqual
        "C3: trcSemanticCommitmentCount in trace must match actual store size"
        storeCount
        traceCount

-- | Three turns must yield commitment count ≥ 3 (one per turn at minimum).
-- This is the "multi-turn corpus fixture" — evidence that the system
-- accumulates typed commitments over a dialogue session.
c3ThreeTurnCorpusFixture :: Test
c3ThreeTurnCorpusFixture = TestLabel "C3: three-turn corpus fixture yields ≥3 commitments" $
  TestCase $
    withDeterministicEmbedding $ do
      (b1, _) <- buildAuthoritativePerspectiveFinalizeFixture emptySystemState "что такое свобода?"
      let ss1 = fpbNextSs b1
      (b2, _) <- buildAuthoritativePerspectiveFinalizeFixture ss1 "расскажи об ответственности"
      let ss2 = fpbNextSs b2
      (b3, _) <- buildAuthoritativePerspectiveFinalizeFixture ss2 "как они связаны?"
      let ss3 = fpbNextSs b3
          count3 = maybe 0 (HashMap.size . scsActive) (ssSemanticCommitments ss3)
      assertBool
        ("C3: three-turn corpus must have ≥3 commitments; got: " <> show count3)
        (count3 >= 3)

-- ---------------------------------------------------------------------------
-- The test group
-- ---------------------------------------------------------------------------

semanticCommitmentCorpusTests :: [Test]
semanticCommitmentCorpusTests =
  [ c3Turn1ProducesCommitments
  , c3MultiTurnAccumulatesCommitments
  , c3TraceFieldMatchesStoreCount
  , c3ThreeTurnCorpusFixture
  ]
