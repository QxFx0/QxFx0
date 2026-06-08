{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.AffectModel
Description : WP-E anti-rot guard for the decoupled affect model + mood EMA.

Per ADR-0042, the consumers must stay connected. WP-E:
- 'computeAtmosphereDecoupled' makes arousal independent of valence (the legacy
  'computeAtmosphere' sets arousal = egoTension);
- 'updateMood' is the living consumer maintaining a slow valence baseline that a
  single spike cannot dominate.
Gated by the default-off 'affectDecoupledActive' flag (ADR-0046).
-}
module Test.Suite.AffectModel
  ( affectModelTests
  ) where

import Test.HUnit (Test (..), assertBool, assertEqual)

import QxFx0.Self.Field
  ( Atmosphere(..)
  , computeAtmosphere
  , computeAtmosphereDecoupled
  , updateMood
  , moodWindowTurns
  , affectDecoupledActive
  , defaultFieldHeuristics
  )

affectModelTests :: [Test]
affectModelTests =
  [ -- WP-E: in the legacy model arousal IS tension; the decoupled model lets
    -- arousal track input intensity independently. Two inputs with the same
    -- ego state but different intensity must yield different arousal under the
    -- decoupled model (and identical arousal under the legacy one).
    TestLabel "WP-E: decoupled arousal tracks input intensity, not tension" $
      TestCase $ do
        let fh = defaultFieldHeuristics
            -- same agency/tension/legit, different input intensity
            legacyLo = atmosphereArousal (computeAtmosphere fh 0.5 0.4 0.5)
            legacyHi = atmosphereArousal (computeAtmosphere fh 0.5 0.4 0.5)
            decLo = atmosphereArousal (computeAtmosphereDecoupled fh 0.5 0.4 0.5 0.1)
            decHi = atmosphereArousal (computeAtmosphereDecoupled fh 0.5 0.4 0.5 0.9)
        assertEqual "legacy arousal ignores intensity (== tension)" legacyLo legacyHi
        assertBool "decoupled arousal rises with input intensity" (decHi > decLo)

    -- WP-E: calm-positive vs agitated-positive become distinguishable —
    -- positive valence can co-occur with low OR high arousal.
  , TestLabel "WP-E: valence and arousal are independently expressible" $
      TestCase $ do
        let fh = defaultFieldHeuristics
            calmPos = computeAtmosphereDecoupled fh 0.8 0.1 0.5 0.05
            agitPos = computeAtmosphereDecoupled fh 0.8 0.1 0.5 0.95
        assertBool "both positive valence" (atmosphereValence calmPos > 0 && atmosphereValence agitPos > 0)
        assertBool "but different arousal"
          (atmosphereArousal agitPos > atmosphereArousal calmPos)

    -- WP-E: mood is a bounded EMA — one extreme spike cannot dominate it.
    -- After a single +1.0 spike from neutral, mood moves by at most the EMA
    -- factor 2/(window+1), i.e. well under half the window's worth.
  , TestLabel "WP-E: mood EMA resists a single spike" $
      TestCase $ do
        let afterSpike = updateMood 0.0 1.0
            alpha      = 2.0 / (fromIntegral moodWindowTurns + 1.0)
        assertBool "spike moves mood only by ~alpha" (afterSpike <= alpha + 1.0e-9)
        assertBool "mood stays in [-1,1]" (afterSpike >= -1.0 && afterSpike <= 1.0)
        -- and a sustained signal converges toward it
        let sustained = iterate (`updateMood` 1.0) 0.0 !! (moodWindowTurns * 4)
        assertBool "sustained signal converges toward the bound" (sustained > 0.9)

    -- flag promoted to default-on
  , TestLabel "WP-E: decoupled affect is promoted to default-on" $
      TestCase $ assertEqual "promoted to default-on (2026-06-04)" True affectDecoupledActive
  ]
