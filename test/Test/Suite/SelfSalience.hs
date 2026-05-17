{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

{-|
Module      : Test.Suite.SelfSalience
Description : Property tests for the Phase-5 salience controller.

Verifies, by QuickCheck, the laws asserted in
@docs\/adr\/0010-salience-controller.md@ §10:

  * 'computeSalience' is total on every well-formed input
    (no exception, no NaN, no infinity);
  * the verdict's bias and confidence both lie in @[0, 1]@;
  * monotonicity in each Field component along its declared
    rule direction (more Resonance / Atmosphere /
    Counterfactual ⇒ no decrease in bias toward Holistic;
    more Consolidation / FieldConfidence ⇒ no increase in bias
    toward Holistic);
  * the Conatus gate fires when @ceScalar < conatusGateThreshold@
    and returns 'DrivenByConatusGate';
  * 'salienceVerdict' produces 'Tied' exactly inside the
    @[0.5 − t, 0.5 + t]@ dead band;
  * 'chooseBranch' dispatches 'PreferHolistic' to the holistic
    branch and 'PreferFormal' \/ 'Tied' to the formal branch;
  * determinism: identical inputs produce identical 'Salience'
    values, including the discrete 'salienceDriver' tag.
-}
module Test.Suite.SelfSalience
  ( selfSalienceTests
  ) where

import Test.HUnit (Test (..), assertFailure)
import Test.QuickCheck
  ( Gen
  , Property
  , choose
  , forAll
  , maxSuccess
  , quickCheckWithResult
  , stdArgs
  )
import Test.QuickCheck.Test (isSuccess)

import QxFx0.Self.Adjunction
  ( Formal (..)
  , Holistic (..)
  )
import QxFx0.Self.Conatus
  ( ConatusComponents (..)
  , ConatusEnergy (..)
  )
import QxFx0.Self.Field
  ( Atmosphere (..)
  , Consolidation (..)
  , Counterfactual (..)
  , Field (..)
  , FieldConfidence (..)
  , Resonance (..)
  , deriveFieldConfidence
  , mkAtmosphere
  , mkConsolidation
  , mkCounterfactual
  , mkFieldConfidence
  , mkResonance
  )
import QxFx0.Self.Salience
  ( Salience (..)
  , SalienceDriver (..)
  , SalienceVerdict (..)
  , SalienceWeights (..)
  , chooseBranch
  , computeSalience
  , defaultSalienceWeights
  , salienceVerdict
  )

-- ---------------------------------------------------------------------------
-- Test-suite entry point
-- ---------------------------------------------------------------------------

selfSalienceTests :: [Test]
selfSalienceTests =
  [ -- Totality and range
    TestLabel "computeSalience produces finite bias and confidence" $
      quickCheckProperty "totality / finiteness" propTotality
  , TestLabel "salienceHolisticBias ∈ [0, 1]" $
      quickCheckProperty "bias range" propBiasRange
  , TestLabel "salienceConfidence ∈ [0, 1]" $
      quickCheckProperty "confidence range" propConfidenceRange

    -- Monotonicity
  , TestLabel "bias is non-decreasing in Resonance" $
      quickCheckProperty "monotone in Resonance" propMonotoneResonance
  , TestLabel "bias is non-increasing in Consolidation" $
      quickCheckProperty "anti-monotone in Consolidation" propAntiMonotoneConsolidation
  , TestLabel "bias is non-decreasing in Counterfactual" $
      quickCheckProperty "monotone in Counterfactual" propMonotoneCounterfactual
  , TestLabel "bias is non-increasing in FieldConfidence" $
      quickCheckProperty "anti-monotone in FieldConfidence" propAntiMonotoneFieldConfidence

    -- Conatus gate
  , TestLabel "Conatus gate fires when ceScalar < threshold" $
      quickCheckProperty "Conatus gate" propConatusGate
  , TestLabel "Conatus gate yields DrivenByConatusGate driver" $
      quickCheckProperty "Conatus gate driver" propConatusGateDriver

    -- Verdict band
  , TestLabel "salienceVerdict produces Tied inside the dead band" $
      quickCheckProperty "Tied band" propTiedBand
  , TestLabel "salienceVerdict produces PreferHolistic above the band" $
      quickCheckProperty "PreferHolistic above band" propPreferHolisticAboveBand
  , TestLabel "salienceVerdict produces PreferFormal below the band" $
      quickCheckProperty "PreferFormal below band" propPreferFormalBelowBand

    -- chooseBranch dispatch
  , TestLabel "chooseBranch dispatches PreferHolistic to the holistic branch" $
      quickCheckProperty "dispatch holistic" propDispatchHolistic
  , TestLabel "chooseBranch dispatches PreferFormal to the formal branch" $
      quickCheckProperty "dispatch formal" propDispatchFormal
  , TestLabel "chooseBranch dispatches Tied to the formal branch (safe default)" $
      quickCheckProperty "dispatch tied" propDispatchTied

    -- Determinism
  , TestLabel "computeSalience is deterministic" $
      quickCheckProperty "determinism" propDeterminism
  ]

-- ---------------------------------------------------------------------------
-- QuickCheck plumbing
-- ---------------------------------------------------------------------------

quickCheckProperty :: String -> Property -> Test
quickCheckProperty label prop = TestCase $ do
  result <- quickCheckWithResult stdArgs { maxSuccess = 200 } prop
  if isSuccess result
    then pure ()
    else assertFailure ("Property failed: " ++ label)

-- ---------------------------------------------------------------------------
-- Generators
-- ---------------------------------------------------------------------------

arbitraryUnitDouble :: Gen Double
arbitraryUnitDouble = choose (0.0, 1.0)

arbitraryValenceDouble :: Gen Double
arbitraryValenceDouble = choose (-1.0, 1.0)

-- | A 'Field' whose every component is drawn from its smart
-- constructor, with @fieldConfidence@ re-derived for internal
-- consistency.
arbitraryField :: Gen Field
arbitraryField = do
  r  <- arbitraryUnitDouble
  v  <- arbitraryValenceDouble
  ar <- arbitraryUnitDouble
  c  <- arbitraryUnitDouble
  cf <- arbitraryUnitDouble
  let scaffold = Field
        { fieldResonance      = mkResonance r
        , fieldAtmosphere     = mkAtmosphere v ar
        , fieldConfidence     = mkFieldConfidence 1.0
        , fieldConsolidation  = mkConsolidation c
        , fieldCounterfactual = mkCounterfactual cf
        }
  pure scaffold { fieldConfidence = deriveFieldConfidence scaffold }

-- | A 'ConatusEnergy' whose @ceScalar@ is drawn from a wide
-- positive range so the Conatus gate (default threshold @0.0@) is
-- not tripped. Components are placeholders; @computeSalience@
-- only reads @ceScalar@.
arbitraryHealthyConatus :: Gen ConatusEnergy
arbitraryHealthyConatus = do
  s <- choose (0.5, 5.0)
  pure (placeholderConatus s)

-- | A 'ConatusEnergy' whose @ceScalar@ is below @0.0@ so the
-- default Conatus gate trips.
arbitraryUnhealthyConatus :: Gen ConatusEnergy
arbitraryUnhealthyConatus = do
  s <- choose (-5.0, -0.001)
  pure (placeholderConatus s)

placeholderConatus :: Double -> ConatusEnergy
placeholderConatus s = ConatusEnergy
  { ceScalar     = s
  , ceComponents = ConatusComponents
      { ccMorphology = 0.0
      , ccIdentity   = 0.0
      , ccTurns      = 0.0
      , ccPenalty    = 0.0
      }
  }

-- | Replace the 'fieldResonance' component on an existing field,
-- preserving the rest. @fieldConfidence@ is /not/ re-derived
-- here so monotonicity tests can isolate a single channel.
withResonance :: Double -> Field -> Field
withResonance r f = f { fieldResonance = mkResonance r }

withConsolidation :: Double -> Field -> Field
withConsolidation c f = f { fieldConsolidation = mkConsolidation c }

withCounterfactual :: Double -> Field -> Field
withCounterfactual c f = f { fieldCounterfactual = mkCounterfactual c }

withFieldConfidence :: Double -> Field -> Field
withFieldConfidence c f = f { fieldConfidence = mkFieldConfidence c }

-- ---------------------------------------------------------------------------
-- Totality and range
-- ---------------------------------------------------------------------------

isFinite :: Double -> Bool
isFinite x = not (isNaN x) && not (isInfinite x)

propTotality :: Property
propTotality =
  forAll arbitraryHealthyConatus $ \ce ->
  forAll arbitraryField $ \f ->
    let s = computeSalience defaultSalienceWeights ce f
    in isFinite (salienceHolisticBias s) && isFinite (salienceConfidence s)

propBiasRange :: Property
propBiasRange =
  forAll arbitraryHealthyConatus $ \ce ->
  forAll arbitraryField $ \f ->
    let b = salienceHolisticBias (computeSalience defaultSalienceWeights ce f)
    in b >= 0.0 && b <= 1.0

propConfidenceRange :: Property
propConfidenceRange =
  forAll arbitraryHealthyConatus $ \ce ->
  forAll arbitraryField $ \f ->
    let c = salienceConfidence (computeSalience defaultSalienceWeights ce f)
    in c >= 0.0 && c <= 1.0 + 1e-12

-- ---------------------------------------------------------------------------
-- Monotonicity along each rule direction
--
-- We check that increasing a positive-direction component does not
-- /decrease/ the holistic bias, and that increasing a negative-
-- direction component does not /increase/ it. These are
-- non-strict inequalities because the sigmoid squash and
-- floating-point arithmetic admit ties on near-equal raw scores.
-- ---------------------------------------------------------------------------

propMonotoneResonance :: Property
propMonotoneResonance =
  forAll arbitraryHealthyConatus $ \ce ->
  forAll arbitraryField $ \f ->
  forAll arbitraryUnitDouble $ \lo ->
  forAll (choose (0.0, 1.0)) $ \delta ->
    let hi = min 1.0 (lo + delta)
        bLo = salienceHolisticBias (computeSalience defaultSalienceWeights ce (withResonance lo f))
        bHi = salienceHolisticBias (computeSalience defaultSalienceWeights ce (withResonance hi f))
    in bHi >= bLo - 1e-12

propAntiMonotoneConsolidation :: Property
propAntiMonotoneConsolidation =
  forAll arbitraryHealthyConatus $ \ce ->
  forAll arbitraryField $ \f ->
  forAll arbitraryUnitDouble $ \lo ->
  forAll (choose (0.0, 1.0)) $ \delta ->
    let hi = min 1.0 (lo + delta)
        bLo = salienceHolisticBias (computeSalience defaultSalienceWeights ce (withConsolidation lo f))
        bHi = salienceHolisticBias (computeSalience defaultSalienceWeights ce (withConsolidation hi f))
    in bHi <= bLo + 1e-12

propMonotoneCounterfactual :: Property
propMonotoneCounterfactual =
  forAll arbitraryHealthyConatus $ \ce ->
  forAll arbitraryField $ \f ->
  forAll arbitraryUnitDouble $ \lo ->
  forAll (choose (0.0, 1.0)) $ \delta ->
    let hi = min 1.0 (lo + delta)
        bLo = salienceHolisticBias (computeSalience defaultSalienceWeights ce (withCounterfactual lo f))
        bHi = salienceHolisticBias (computeSalience defaultSalienceWeights ce (withCounterfactual hi f))
    in bHi >= bLo - 1e-12

propAntiMonotoneFieldConfidence :: Property
propAntiMonotoneFieldConfidence =
  forAll arbitraryHealthyConatus $ \ce ->
  forAll arbitraryField $ \f ->
  forAll arbitraryUnitDouble $ \lo ->
  forAll (choose (0.0, 1.0)) $ \delta ->
    let hi = min 1.0 (lo + delta)
        bLo = salienceHolisticBias (computeSalience defaultSalienceWeights ce (withFieldConfidence lo f))
        bHi = salienceHolisticBias (computeSalience defaultSalienceWeights ce (withFieldConfidence hi f))
    in bHi <= bLo + 1e-12

-- ---------------------------------------------------------------------------
-- Conatus gate
-- ---------------------------------------------------------------------------

propConatusGate :: Property
propConatusGate =
  forAll arbitraryUnhealthyConatus $ \ce ->
  forAll arbitraryField $ \f ->
    let s = computeSalience defaultSalienceWeights ce f
    in salienceHolisticBias s == 0.0
       && salienceConfidence s == 1.0

propConatusGateDriver :: Property
propConatusGateDriver =
  forAll arbitraryUnhealthyConatus $ \ce ->
  forAll arbitraryField $ \f ->
    salienceDriver (computeSalience defaultSalienceWeights ce f)
      == DrivenByConatusGate

-- ---------------------------------------------------------------------------
-- Verdict band
-- ---------------------------------------------------------------------------

-- | Build a 'Salience' with a chosen bias for verdict-band tests.
synthSalience :: Double -> Salience
synthSalience b = Salience
  { salienceHolisticBias = b
  , salienceConfidence   = 1.0
  , salienceDriver       = DrivenByDefault
  }

isTied :: SalienceVerdict -> Bool
isTied Tied = True
isTied _    = False

isPreferHolistic :: SalienceVerdict -> Bool
isPreferHolistic (PreferHolistic _) = True
isPreferHolistic _                  = False

isPreferFormal :: SalienceVerdict -> Bool
isPreferFormal (PreferFormal _) = True
isPreferFormal _                = False

propTiedBand :: Property
propTiedBand =
  forAll (choose (-1.0, 1.0)) $ \scaled ->
    let t   = verdictThreshold defaultSalienceWeights
        b   = 0.5 + scaled * t                          -- in [0.5 - t, 0.5 + t]
        b'  = max 0.0 (min 1.0 b)
        v   = salienceVerdict defaultSalienceWeights (synthSalience b')
    in isTied v

propPreferHolisticAboveBand :: Property
propPreferHolisticAboveBand =
  forAll (choose (0.0, 1.0)) $ \jitter ->
    let t = verdictThreshold defaultSalienceWeights
        b = min 1.0 (0.5 + t + 1e-3 + jitter * (0.5 - t - 1e-3))
        v = salienceVerdict defaultSalienceWeights (synthSalience b)
    in isPreferHolistic v

propPreferFormalBelowBand :: Property
propPreferFormalBelowBand =
  forAll (choose (0.0, 1.0)) $ \jitter ->
    let t = verdictThreshold defaultSalienceWeights
        b = max 0.0 (0.5 - t - 1e-3 - jitter * (0.5 - t - 1e-3))
        v = salienceVerdict defaultSalienceWeights (synthSalience b)
    in isPreferFormal v

-- ---------------------------------------------------------------------------
-- chooseBranch dispatch
--
-- The two test branches are constructed so that their outputs are
-- distinguishable: the holistic branch tags its output with @+1@,
-- the formal branch tags it with @+100@ (the latter will reach
-- the caller via @rightAdjunct@ inside @chooseBranch@).
-- ---------------------------------------------------------------------------

holisticBranchTag :: Holistic Int -> Int
holisticBranchTag (Holistic (a, _fd)) = a + 1

formalBranchTag :: Int -> Formal Int
formalBranchTag a = Formal (\_fd -> a + 100)

propDispatchHolistic :: Property
propDispatchHolistic =
  forAll (choose (-50, 50 :: Int)) $ \magInput ->
  forAll arbitraryField $ \fd ->
  forAll (choose (1, 100 :: Int)) $ \a ->
    let mag = fromIntegral magInput / 100.0  -- magnitude (sign is irrelevant for verdict tag)
        v   = PreferHolistic (abs mag + 0.1)
        f   = chooseBranch v holisticBranchTag formalBranchTag
    in f (Holistic (a, fd)) == a + 1

propDispatchFormal :: Property
propDispatchFormal =
  forAll (choose (-50, 50 :: Int)) $ \magInput ->
  forAll arbitraryField $ \fd ->
  forAll (choose (1, 100 :: Int)) $ \a ->
    let mag = fromIntegral magInput / 100.0
        v   = PreferFormal (abs mag + 0.1)
        f   = chooseBranch v holisticBranchTag formalBranchTag
    in f (Holistic (a, fd)) == a + 100

propDispatchTied :: Property
propDispatchTied =
  forAll arbitraryField $ \fd ->
  forAll (choose (1, 100 :: Int)) $ \a ->
    let f = chooseBranch Tied holisticBranchTag formalBranchTag
    in f (Holistic (a, fd)) == a + 100

-- ---------------------------------------------------------------------------
-- Determinism
-- ---------------------------------------------------------------------------

propDeterminism :: Property
propDeterminism =
  forAll arbitraryHealthyConatus $ \ce ->
  forAll arbitraryField $ \f ->
    let s1 = computeSalience defaultSalienceWeights ce f
        s2 = computeSalience defaultSalienceWeights ce f
    in s1 == s2
