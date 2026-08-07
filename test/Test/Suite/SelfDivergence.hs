{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

{-|
Module      : Test.Suite.SelfDivergence
Description : Deterministic self-divergence contour tests (A-slice).

Pins the pure morphisms of @QxFx0.Self.SelfDivergence@:

  * 'predictSelf' is total and deterministic on every
    (modulation, Field, angst) triple;
  * a steady in-envelope Field at zero angst measures exactly zero
    divergence (mean-reverting prediction stays inside the envelope);
  * the total divergence is clamped into [0, 1];
  * 'selfConsistencyPenalty' fires only above 'sdtThreshold' and then
    as a negative /fraction/ of the energy (log-scale aware, WP-F
    unit-mismatch guard);
  * the fired penalty preserves the five-component invariant
    @ceScalar == sum of components@;
  * 'windowMeanDivergence' is the exact arithmetic mean and is 0 on
    empty windows.
  * 'sustainedDivergenceExceeds' (C-slice CD trigger) is False on
    empty windows, False below the threshold, and True exactly when a
    non-empty window mean strictly exceeds 'sdtThreshold'.
-}
module Test.Suite.SelfDivergence
  ( selfDivergenceTests
  ) where

import Test.HUnit (Test (..), assertBool, assertEqual, assertFailure)
import Test.QuickCheck
  ( Gen
  , Property
  , choose
  , forAll
  , property
  , quickCheckWithResult
  )
import Test.QuickCheck.Test (isSuccess)
import Test.Support.QuickCheckConfig (qcArgs)

import QxFx0.Self.Conatus
  ( ConatusEnergy (..)
  , ConatusComponents (..)
  )
import QxFx0.Self.Essence (defaultEssenceModulation)
import QxFx0.Self.Field
  ( Field (..)
  , emptyField
  , mkAtmosphere
  , mkConsolidation
  , mkCounterfactual
  , mkFieldConfidence
  , mkResonance
  )
import QxFx0.Self.SelfDivergence
  ( measureDivergence
  , predictSelf
  , selfConsistencyPenalty
  , sustainedDivergenceExceeds
  , windowMeanDivergence
  )
import QxFx0.Types.Self.SelfDivergence
  ( SelfDivergenceE (..)
  , SelfDivergenceTuning (..)
  , defaultSelfDivergenceTuning
  , emptySelfDivergenceE
  )

-- ---------------------------------------------------------------------------
-- Test-suite entry point
-- ---------------------------------------------------------------------------

selfDivergenceTests :: [Test]
selfDivergenceTests =
  [ TestLabel "predictSelf is deterministic on the same (em, Field, angst)" $
      quickCheckProperty "predictSelf deterministic"
        propPredictDeterministic
  , TestLabel "steady in-envelope Field at zero angst measures zero divergence" $
      quickCheckProperty "in-envelope fields diverge zero"
        propInEnvelopeZeroDivergence
  , TestLabel "total divergence is clamped into [0, 1]" $
      quickCheckProperty "total divergence clamped"
        propDivergenceInUnit
  , TestLabel "penalty fires only above threshold and as a fraction of energy" $
      quickCheckProperty "penalty gated by threshold"
        propPenaltyGatedByThreshold
  , TestLabel "penalty preserves the five-component invariant ceScalar == sum" $
      quickCheckProperty "penalty preserves component invariant"
        propPenaltyPreservesInvariant
  , TestLabel "windowMeanDivergence is the exact arithmetic mean" $
      TestCase $ do
        assertEqual "simple mean" 0.5 (windowMeanDivergence [0.0, 1.0])
        assertEqual "weighted mean" 0.25 (windowMeanDivergence [0.0, 0.5])
  , TestLabel "windowMeanDivergence is 0 on an empty window" $
      TestCase $ assertEqual "empty window mean" 0.0 (windowMeanDivergence [])
    -- C-slice (CD): sustainedDivergenceExceeds recovery trigger
  , TestLabel "sustained divergence is False on an empty window" $
      TestCase $ assertBool "empty window never sustained-diverged"
        (not (sustainedDivergenceExceeds tuning []))
  , TestLabel "sustained divergence is False below or at threshold" $
      TestCase $
        let thr = sdtThreshold tuning
            atThreshold = [thr]
            belowThreshold = [thr / 2.0, thr / 2.0]
        in do
          assertBool "at-threshold window must not fire"
            (not (sustainedDivergenceExceeds tuning atThreshold))
          assertBool "below-threshold window must not fire"
            (not (sustainedDivergenceExceeds tuning belowThreshold))
  , TestLabel "sustained divergence is True when window mean exceeds threshold" $
      TestCase $
        assertBool "above-threshold window must fire"
          (sustainedDivergenceExceeds tuning [1.0, 1.0])
  ]

quickCheckProperty :: String -> Property -> Test
quickCheckProperty label prop = TestCase $ do
  args <- qcArgs
  result <- quickCheckWithResult args prop
  if isSuccess result
    then pure ()
    else assertFailure ("Property failed: " ++ label)

-- ---------------------------------------------------------------------------
-- Generators
-- ---------------------------------------------------------------------------

-- | Arbitrary unit-domain Field with all five components in [0, 1].
arbitraryField :: Gen Field
arbitraryField = do
  res <- choose (0.0, 1.0)
  val <- choose (0.0, 1.0)
  aro <- choose (0.0, 1.0)
  con <- choose (0.0, 1.0)
  cons <- choose (0.0, 1.0)
  cf <- choose (0.0, 1.0)
  pure (mkField res val aro con cons cf)

-- ---------------------------------------------------------------------------
-- Properties
-- ---------------------------------------------------------------------------

propPredictDeterministic :: Property
propPredictDeterministic =
  forAll arbitraryField $ \f ->
    forAll (choose (0.0, 1.0)) $ \angst ->
      property
        (predictSelf defaultEssenceModulation f angst
           == predictSelf defaultEssenceModulation f angst)

-- The prediction mean-reverts toward the band center at the angst
-- decay rate; for any observed value inside [0,1] the drift
-- @|observed - center| * decay@ stays below the envelope half-width
-- (0.17), so a steady Field produces exactly zero axis divergence.
-- The angst axis also expects the observed angst to have decayed; at
-- zero observed angst the prediction is zero and the delta is zero.
propInEnvelopeZeroDivergence :: Property
propInEnvelopeZeroDivergence =
  forAll arbitraryField $ \f ->
    property $
      let pred = predictSelf defaultEssenceModulation f 0.0
          divE = measureDivergence pred f 0.0
      in sdeTotalDivergence divE == 0.0

propDivergenceInUnit :: Property
propDivergenceInUnit =
  forAll arbitraryField $ \f ->
    forAll arbitraryField $ \other ->
      forAll (choose (0.0, 1.0)) $ \angst ->
        property $
          let pred = predictSelf defaultEssenceModulation f angst
              divE = measureDivergence pred other angst
              t = sdeTotalDivergence divE
          in 0.0 <= t && t <= 1.0

propPenaltyGatedByThreshold :: Property
propPenaltyGatedByThreshold =
  forAll (choose (0.0, 1.0)) $ \total ->
    property $
      let divE = emptySelfDivergenceE { sdeTotalDivergence = total }
          (ce', pShare) = selfConsistencyPenalty tuning divE baseEnergy
      in (pShare == 0.0 && ceScalar ce' == ceScalar baseEnergy)
           == (total <= sdtThreshold tuning)

propPenaltyPreservesInvariant :: Property
propPenaltyPreservesInvariant =
  forAll (choose (0.0, 1.0)) $ \total ->
    property $
      let divE = emptySelfDivergenceE { sdeTotalDivergence = total }
          (ce', pShare) = selfConsistencyPenalty tuning divE baseEnergy
          comps = ceComponents ce'
          sumC = ccMorphology comps + ccIdentity comps + ccTurns comps
                   + ccPenalty comps + ccSelfDivergence comps
      in pShare <= 0.0
           && approxEqual (ceScalar ce') sumC
           && approxEqual (ceScalar ce') (ceScalar baseEnergy + pShare)
           && (pShare < 0.0) == (total > sdtThreshold tuning)

-- ---------------------------------------------------------------------------
-- Shared fixtures
-- ---------------------------------------------------------------------------

tuning :: SelfDivergenceTuning
tuning = defaultSelfDivergenceTuning

-- Production log-scale band: ceScalar ~ 10 like the live runtime
-- (WP-F guard: penalty is a fraction of this, not a unit flat value).
baseEnergy :: ConatusEnergy
baseEnergy = ConatusEnergy
  { ceScalar = 10.0
  , ceComponents = ConatusComponents 2.5 2.5 2.5 2.5 0.0
  }

mkField
  :: Double -> Double -> Double -> Double -> Double -> Double -> Field
mkField r v a c co cf = emptyField
  { fieldResonance = mkResonance r
  , fieldAtmosphere = mkAtmosphere v a
  , fieldConfidence = mkFieldConfidence c
  , fieldConsolidation = mkConsolidation co
  , fieldCounterfactual = mkCounterfactual cf
  }

approxEqual :: Double -> Double -> Bool
approxEqual a b = abs (a - b) < 1e-9
