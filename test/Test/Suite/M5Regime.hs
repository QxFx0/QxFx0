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
- regime stamps read the LIVE session regime (@ssCurrentRegime@), not
  the static @defaultRuntimeRegime@ (restored sessions may carry a
  different persisted regime)

This test closes the H3 gate of M6 activation
(per @docs\/closure\/REGIME_GOVERNANCE.md §8@).
-}
module Test.Suite.M5Regime
  ( m5RegimeTests
  ) where

import Test.HUnit (Test (..), assertBool, assertEqual)
import Prelude

import QxFx0.Core.TurnPipeline.Protocol (FinalizePrecommitBundle(..))
import QxFx0.Types.State.System (ssCurrentRegime)
import QxFx0.Types.TurnProjection (tqpReplayTrace, trcRegimeVersion, trcFamilyDivergenceActive)
import QxFx0.Types.RuntimeRegime (RuntimeRegime(..), currentMathVersion, defaultRuntimeRegime, rrFamilyDivergenceActive)
import QxFx0.Runtime.StateDefaults (emptySystemState)
import Test.Suite.TurnPipelineProtocol (buildFinalizeFixture, buildFinalizeFixtureWithState, withDeterministicEmbedding)

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

-- | Regression pin (2026-08-23): the regime stamps must read the LIVE
-- session regime (@ssCurrentRegime@), not the static default. A restored
-- session carrying a foreign persisted regime must surface it verbatim —
-- previously trcRegimeVersion/trcFamilyDivergenceActive silently stamped
-- the binary default and lied about restored sessions.
m5RegimeStampsLiveSessionRegime :: Test
m5RegimeStampsLiveSessionRegime = TestLabel "M5: regime stamps read the live ssCurrentRegime, not the static default" $
  TestCase $
    withDeterministicEmbedding $ do
      let foreignRegime = defaultRuntimeRegime
            { rrMathVersion = currentMathVersion + 99
            , rrFamilyDivergenceActive = not (rrFamilyDivergenceActive defaultRuntimeRegime)
            }
          startSs = emptySystemState { ssCurrentRegime = foreignRegime }
      (_, _, _, _, _, bundle) <- buildFinalizeFixtureWithState startSs "что такое свобода?"
      let trace = tqpReplayTrace (fpbProjection bundle)
      assertEqual
        "M5: trcRegimeVersion must come from the live session regime"
        (currentMathVersion + 99)
        (trcRegimeVersion trace)
      assertEqual
        "M5: trcFamilyDivergenceActive must come from the live session regime"
        (not (rrFamilyDivergenceActive defaultRuntimeRegime))
        (trcFamilyDivergenceActive trace)

-- ---------------------------------------------------------------------------
-- The test group
-- ---------------------------------------------------------------------------

m5RegimeTests :: [Test]
m5RegimeTests =
  [ m5RegimeVersionIsStamped
  , m5RegimeVersionMatchesCurrent
  , m5FamilyDivergenceActiveIsStamped
  , m5RegimeStampsLiveSessionRegime
  ]
