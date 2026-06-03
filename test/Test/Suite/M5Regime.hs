{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE StrictData #-}

{-|
Description : canonical — M5 regime governance integration test.

Verifies that a real turn produces a TurnReplayTrace with:
- @trcRegimeVersion > 0@ — math version is machine-visible
- @trcFamilyDivergenceActive@ matches the promoted ADR-0019 state
- @trcRegimeVersion == currentMathVersion@ — regime is consistent

This test closes the H3 gate of M6 activation
(per @docs\/closure\/REGIME_GOVERNANCE.md §8@).
-}
module Test.Suite.M5Regime
  ( m5RegimeTests
  ) where

import Test.HUnit (Test (..), assertBool, assertEqual)
import Prelude

import QxFx0.Core.TurnPipeline.Protocol (FinalizePrecommitBundle(..))
import QxFx0.Types.TurnProjection (tqpReplayTrace, trcRegimeVersion, trcFamilyDivergenceActive)
import QxFx0.Types.RuntimeRegime (currentMathVersion, defaultRuntimeRegime, rrFamilyDivergenceActive)
import Test.Suite.TurnPipelineProtocol (buildFinalizeFixture, withDeterministicEmbedding)

-- | Run a real finalize turn in-memory and verify that the regime markers
-- are correctly stamped into the produced TurnReplayTrace.
m5RegimeVersionIsStamped :: Test
m5RegimeVersionIsStamped = TestLabel "M5: trcRegimeVersion is stamped in produced TurnReplayTrace" $
  TestCase $
    withDeterministicEmbedding $ do
      (_, _, _, _, _, bundle) <- buildFinalizeFixture "что такое свобода?"
      let trace = tqpReplayTrace (fpbProjection bundle)
      assertBool
        ("M5: trcRegimeVersion must be > 0, got: " <> show (trcRegimeVersion trace))
        (trcRegimeVersion trace > 0)

-- | trcRegimeVersion must equal currentMathVersion — no stale stamping.
m5RegimeVersionMatchesCurrent :: Test
m5RegimeVersionMatchesCurrent = TestLabel "M5: trcRegimeVersion matches currentMathVersion" $
  TestCase $
    withDeterministicEmbedding $ do
      (_, _, _, _, _, bundle) <- buildFinalizeFixture "что такое свобода?"
      let trace = tqpReplayTrace (fpbProjection bundle)
      assertEqual
        "M5: trcRegimeVersion in trace must equal currentMathVersion"
        currentMathVersion
        (trcRegimeVersion trace)

-- | trcFamilyDivergenceActive must match the defaultRuntimeRegime flag.
-- After ADR-0019 (2026-06-02), this is True.
m5FamilyDivergenceActiveIsStamped :: Test
m5FamilyDivergenceActiveIsStamped = TestLabel "M5: trcFamilyDivergenceActive matches defaultRuntimeRegime (ADR-0019)" $
  TestCase $
    withDeterministicEmbedding $ do
      (_, _, _, _, _, bundle) <- buildFinalizeFixture "что такое свобода?"
      let trace = tqpReplayTrace (fpbProjection bundle)
      assertEqual
        "M5: trcFamilyDivergenceActive in trace must match rrFamilyDivergenceActive defaultRuntimeRegime"
        (rrFamilyDivergenceActive defaultRuntimeRegime)
        (trcFamilyDivergenceActive trace)

-- ---------------------------------------------------------------------------
-- The test group
-- ---------------------------------------------------------------------------

m5RegimeTests :: [Test]
m5RegimeTests =
  [ m5RegimeVersionIsStamped
  , m5RegimeVersionMatchesCurrent
  , m5FamilyDivergenceActiveIsStamped
  ]
