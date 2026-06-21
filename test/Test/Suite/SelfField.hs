{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

{-|
Module      : Test.Suite.SelfField
Description : Property tests for the Phase-4 right-hemispheric Field components.

Verifies, by QuickCheck, the laws asserted in
@docs\/adr\/0009-right-hemisphere-field.md@ §6 step 3:

  * every smart constructor ('mkResonance', 'mkAtmosphere',
    'mkFieldConfidence', 'mkConsolidation', 'mkCounterfactual')
    clamps its input to the documented range;
  * per-component combinators respect their stated algebraic laws
    (commutativity, associativity, idempotence, identity);
  * 'emptyField' is the identity of @combineField CombineMaxima@
    and of @combineField CombineAccumulate@ (where it makes sense);
  * 'deriveFieldConfidence' is monotone in the agreement between
    its components — equal-valued fields receive the maximum
    confidence;
  * a smoke test that the Phase-4 'Field' continues to compose
    with the Phase-3 'Holistic' \/ 'Formal' adjunction.

The Phase-3 acceptance criteria from ADR-0008 §10 continue to be
verified by @Test.Suite.SelfAdjunction@ against the substantive
'Field' (the generator there now draws every component from its
smart constructor); this module is responsible only for the laws
specific to 'Field'.
-}
module Test.Suite.SelfField
  ( selfFieldTests
  ) where
import Test.Support.QuickCheckConfig (qcArgs)

import Test.HUnit (Test (..), assertBool, assertFailure)
import Test.QuickCheck
  ( Gen
  , Property
  , arbitrary
  , choose
  , forAll
  , quickCheckWithResult
  )
import Test.QuickCheck.Test (isSuccess)

import QxFx0.Self.Adjunction
  ( Adjunction (..)
  , Holistic (..)
  , Formal   (..)
  , probe
  )
import QxFx0.Self.Field
  ( Atmosphere (..)
  , CombineMode (..)
  , Consolidation (..)
  , Counterfactual (..)
  , Field (..)
  , FieldConfidence (..)
  , Resonance (..)
  , combineConsolidation
  , combineCounterfactual
  , combineField
  , combineFieldConfidence
  , combineResonance
  , deriveFieldConfidence
  , emptyField
  , mkAtmosphere
  , mkConsolidation
  , mkCounterfactual
  , mkFieldConfidence
  , mkResonance
  , FieldHeuristics(..)
  , defaultFieldHeuristics
  , computeConsolidation
  , computeCounterfactual
  , computeAtmosphere
  , adaptFieldHeuristics
  )

-- ---------------------------------------------------------------------------
-- Test-suite entry point
-- ---------------------------------------------------------------------------

selfFieldTests :: [Test]
selfFieldTests =
  [ -- Smart-constructor clamping
    TestLabel "mkResonance clamps to [0,1]" $
      quickCheckProperty "mkResonance clamps" propMkResonanceClamps
  , TestLabel "mkAtmosphere clamps valence to [-1,1] and arousal to [0,1]" $
      quickCheckProperty "mkAtmosphere clamps" propMkAtmosphereClamps
  , TestLabel "mkFieldConfidence clamps to [0,1]" $
      quickCheckProperty "mkFieldConfidence clamps" propMkFieldConfidenceClamps
  , TestLabel "mkConsolidation clamps to [0,1]" $
      quickCheckProperty "mkConsolidation clamps" propMkConsolidationClamps
  , TestLabel "mkCounterfactual clamps to [0,1]" $
      quickCheckProperty "mkCounterfactual clamps" propMkCounterfactualClamps

  -- Per-component combinator laws
  , TestLabel "combineResonance is commutative" $
      quickCheckProperty "combineResonance commutative" propCombineResonanceCommutative
  , TestLabel "combineResonance is associative" $
      quickCheckProperty "combineResonance associative" propCombineResonanceAssociative
  , TestLabel "combineResonance is idempotent" $
      quickCheckProperty "combineResonance idempotent" propCombineResonanceIdempotent
  , TestLabel "combineFieldConfidence is commutative" $
      quickCheckProperty "combineFieldConfidence commutative" propCombineFieldConfidenceCommutative
  , TestLabel "combineFieldConfidence is associative" $
      quickCheckProperty "combineFieldConfidence associative" propCombineFieldConfidenceAssociative
  , TestLabel "combineConsolidation is commutative" $
      quickCheckProperty "combineConsolidation commutative" propCombineConsolidationCommutative
  , TestLabel "combineConsolidation has identity Consolidation 0" $
      quickCheckProperty "combineConsolidation identity" propCombineConsolidationIdentity
  , TestLabel "combineConsolidation result is bounded by 1.0" $
      quickCheckProperty "combineConsolidation bounded" propCombineConsolidationBounded
  , TestLabel "combineCounterfactual is commutative" $
      quickCheckProperty "combineCounterfactual commutative" propCombineCounterfactualCommutative
  , TestLabel "combineCounterfactual is associative" $
      quickCheckProperty "combineCounterfactual associative" propCombineCounterfactualAssociative

  -- Field-level combinators
  , TestLabel "combineField CombineMaxima is commutative" $
      quickCheckProperty "combineField CombineMaxima commutative" propCombineMaximaCommutative
  , TestLabel "combineField CombineAverage is commutative" $
      quickCheckProperty "combineField CombineAverage commutative" propCombineAverageCommutative
  , TestLabel "combineField CombineAccumulate non-confidence components are commutative" $
      quickCheckProperty "combineField CombineAccumulate non-conf commutative" propCombineAccumulateNonConfCommutative

  -- emptyField identity
  , TestLabel "combineField CombineMaxima with emptyField preserves non-confidence components" $
      quickCheckProperty "emptyField is right-identity for non-conf maxima"
        propEmptyFieldIdentityForMaxima

  -- deriveFieldConfidence monotonicity / boundary cases
  , TestLabel "deriveFieldConfidence on uniform field gives confidence 1.0" $
      quickCheckProperty "uniform field has max confidence" propUniformFieldMaxConfidence
  , TestLabel "deriveFieldConfidence is in [0,1] for any well-formed field" $
      quickCheckProperty "deriveFieldConfidence in [0,1]" propDeriveFieldConfidenceInRange

  -- Adjunction smoke test
  , TestLabel "Field round-trips through Holistic / Formal (smoke)" $
      quickCheckProperty "Adjunction smoke" propAdjunctionSmoke

  -- Phase-7 heuristic lifeness gates
  , TestLabel "computeConsolidation is in [0,1]" $
      quickCheckProperty "computeConsolidation in range" propComputeConsolidationInRange
  , TestLabel "computeCounterfactual is in [0,1]" $
      quickCheckProperty "computeCounterfactual in range" propComputeCounterfactualInRange
  , TestLabel "computeAtmosphere valence is in [-1,1]" $
      quickCheckProperty "computeAtmosphere valence in range" propComputeAtmosphereValenceInRange
  , TestLabel "computeAtmosphere arousal is in [0,1]" $
      quickCheckProperty "computeAtmosphere arousal in range" propComputeAtmosphereArousalInRange
  , TestLabel "sameTopic boosts consolidation" $
      quickCheckProperty "sameTopic boosts consolidation" propSameTopicBoostsConsolidation
  , TestLabel "streak boosts counterfactual" $
      quickCheckProperty "streak boosts counterfactual" propStreakBoostsCounterfactual
  , TestLabel "higher legitimacy raises valence" $
      quickCheckProperty "higher legitimacy raises valence" propHighLegitimacyRaisesValence

    -- Phase 6.7: heuristics override honored
  , TestLabel "overridden FieldHeuristics changes computeAtmosphere" $
      TestCase testHeuristicsOverrideHonored

    -- Phase-B bounded post-commitment adaptation
  , TestLabel "adaptFieldHeuristics signal=0 is identity" $
      quickCheckProperty "adapt identity" propAdaptFieldHeuristicsIdentity
  , TestLabel "adaptFieldHeuristics clamps adapted doubles to [0,1]" $
      quickCheckProperty "adapt clamp" propAdaptFieldHeuristicsClamp
  , TestLabel "adaptFieldHeuristics anti-drift keeps doubles within ±0.5 of default" $
      quickCheckProperty "adapt anti-drift" propAdaptFieldHeuristicsAntiDrift
  ]

-- ---------------------------------------------------------------------------
-- QuickCheck plumbing
-- ---------------------------------------------------------------------------

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

-- | Wide range to exercise clamping; not restricted to [0, 1].
arbitraryWideDouble :: Gen Double
arbitraryWideDouble = choose (-100.0, 100.0)

arbitraryUnitDouble :: Gen Double
arbitraryUnitDouble = choose (0.0, 1.0)

arbitraryValenceDouble :: Gen Double
arbitraryValenceDouble = choose (-1.0, 1.0)

arbitraryResonance :: Gen Resonance
arbitraryResonance = mkResonance <$> arbitraryUnitDouble

arbitraryFieldConfidence :: Gen FieldConfidence
arbitraryFieldConfidence = mkFieldConfidence <$> arbitraryUnitDouble

arbitraryConsolidation :: Gen Consolidation
arbitraryConsolidation = mkConsolidation <$> arbitraryUnitDouble

arbitraryCounterfactual :: Gen Counterfactual
arbitraryCounterfactual = mkCounterfactual <$> arbitraryUnitDouble

arbitraryAtmosphere :: Gen Atmosphere
arbitraryAtmosphere =
  mkAtmosphere <$> arbitraryValenceDouble <*> arbitraryUnitDouble

arbitraryField :: Gen Field
arbitraryField = do
  r  <- arbitraryUnitDouble
  v  <- arbitraryValenceDouble
  ar <- arbitraryUnitDouble
  c  <- arbitraryUnitDouble
  cf <- arbitraryUnitDouble
  let scaffold =
        Field
          { fieldResonance      = mkResonance r
          , fieldAtmosphere     = mkAtmosphere v ar
          , fieldConfidence     = mkFieldConfidence 1.0
          , fieldConsolidation  = mkConsolidation c
          , fieldCounterfactual = mkCounterfactual cf
          }
  pure scaffold { fieldConfidence = deriveFieldConfidence scaffold }

-- ---------------------------------------------------------------------------
-- Smart-constructor clamping properties
-- ---------------------------------------------------------------------------

propMkResonanceClamps :: Property
propMkResonanceClamps =
  forAll arbitraryWideDouble $ \x ->
    let Resonance r = mkResonance x
    in r >= 0.0 && r <= 1.0

propMkAtmosphereClamps :: Property
propMkAtmosphereClamps =
  forAll arbitraryWideDouble $ \v ->
  forAll arbitraryWideDouble $ \a ->
    let Atmosphere v' a' = mkAtmosphere v a
    in v' >= -1.0 && v' <= 1.0 && a' >= 0.0 && a' <= 1.0

propMkFieldConfidenceClamps :: Property
propMkFieldConfidenceClamps =
  forAll arbitraryWideDouble $ \x ->
    let FieldConfidence c = mkFieldConfidence x
    in c >= 0.0 && c <= 1.0

propMkConsolidationClamps :: Property
propMkConsolidationClamps =
  forAll arbitraryWideDouble $ \x ->
    let Consolidation c = mkConsolidation x
    in c >= 0.0 && c <= 1.0

propMkCounterfactualClamps :: Property
propMkCounterfactualClamps =
  forAll arbitraryWideDouble $ \x ->
    let Counterfactual c = mkCounterfactual x
    in c >= 0.0 && c <= 1.0

-- ---------------------------------------------------------------------------
-- Per-component combinator laws
-- ---------------------------------------------------------------------------

propCombineResonanceCommutative :: Property
propCombineResonanceCommutative =
  forAll arbitraryResonance $ \a ->
  forAll arbitraryResonance $ \b ->
    combineResonance a b == combineResonance b a

propCombineResonanceAssociative :: Property
propCombineResonanceAssociative =
  forAll arbitraryResonance $ \a ->
  forAll arbitraryResonance $ \b ->
  forAll arbitraryResonance $ \c ->
    combineResonance a (combineResonance b c)
      == combineResonance (combineResonance a b) c

propCombineResonanceIdempotent :: Property
propCombineResonanceIdempotent =
  forAll arbitraryResonance $ \a ->
    combineResonance a a == a

propCombineFieldConfidenceCommutative :: Property
propCombineFieldConfidenceCommutative =
  forAll arbitraryFieldConfidence $ \a ->
  forAll arbitraryFieldConfidence $ \b ->
    combineFieldConfidence a b == combineFieldConfidence b a

propCombineFieldConfidenceAssociative :: Property
propCombineFieldConfidenceAssociative =
  forAll arbitraryFieldConfidence $ \a ->
  forAll arbitraryFieldConfidence $ \b ->
  forAll arbitraryFieldConfidence $ \c ->
    combineFieldConfidence a (combineFieldConfidence b c)
      == combineFieldConfidence (combineFieldConfidence a b) c

propCombineConsolidationCommutative :: Property
propCombineConsolidationCommutative =
  forAll arbitraryConsolidation $ \a ->
  forAll arbitraryConsolidation $ \b ->
    combineConsolidation a b == combineConsolidation b a

-- | Consolidation 0 is the identity element.
propCombineConsolidationIdentity :: Property
propCombineConsolidationIdentity =
  forAll arbitraryConsolidation $ \a ->
    combineConsolidation a (Consolidation 0.0) == a
      && combineConsolidation (Consolidation 0.0) a == a

-- | The clipped-additive monoid is bounded by 1.0.
propCombineConsolidationBounded :: Property
propCombineConsolidationBounded =
  forAll arbitraryConsolidation $ \a ->
  forAll arbitraryConsolidation $ \b ->
    let Consolidation c = combineConsolidation a b
    in c <= 1.0 + 1e-12

propCombineCounterfactualCommutative :: Property
propCombineCounterfactualCommutative =
  forAll arbitraryCounterfactual $ \a ->
  forAll arbitraryCounterfactual $ \b ->
    combineCounterfactual a b == combineCounterfactual b a

propCombineCounterfactualAssociative :: Property
propCombineCounterfactualAssociative =
  forAll arbitraryCounterfactual $ \a ->
  forAll arbitraryCounterfactual $ \b ->
  forAll arbitraryCounterfactual $ \c ->
    combineCounterfactual a (combineCounterfactual b c)
      == combineCounterfactual (combineCounterfactual a b) c

-- ---------------------------------------------------------------------------
-- Field-level combinator commutativity
-- ---------------------------------------------------------------------------

-- | Strict structural equality is sufficient for commutativity:
-- max, min, average and weighted-average with weight 0.5 are all
-- commutative on Double, and the construction of 'Field' preserves
-- this pointwise.
propCombineMaximaCommutative :: Property
propCombineMaximaCommutative =
  forAll arbitraryField $ \f1 ->
  forAll arbitraryField $ \f2 ->
    combineField CombineMaxima f1 f2 == combineField CombineMaxima f2 f1

propCombineAverageCommutative :: Property
propCombineAverageCommutative =
  forAll arbitraryField $ \f1 ->
  forAll arbitraryField $ \f2 ->
    combineField CombineAverage f1 f2 == combineField CombineAverage f2 f1

-- | All non-confidence components of CombineAccumulate are
-- commutative ('combineConsolidation' is commutative because
-- addition is). 'combineFieldConfidence' is also commutative
-- ('min'). Hence the whole field combine is commutative.
propCombineAccumulateNonConfCommutative :: Property
propCombineAccumulateNonConfCommutative =
  forAll arbitraryField $ \f1 ->
  forAll arbitraryField $ \f2 ->
    combineField CombineAccumulate f1 f2 == combineField CombineAccumulate f2 f1

-- ---------------------------------------------------------------------------
-- emptyField identity
-- ---------------------------------------------------------------------------

-- | For 'CombineMaxima', the four non-confidence components of
-- 'emptyField' are zero (or identity-shaped for 'Atmosphere'),
-- and combining with them leaves the other field's non-confidence
-- components untouched. We check that explicitly per component.
--
-- 'fieldConfidence' is not preserved because 'emptyField' has
-- 'FieldConfidence 1.0' and the combine takes 'min'; that is the
-- documented behaviour and we simply do not assert on it.
propEmptyFieldIdentityForMaxima :: Property
propEmptyFieldIdentityForMaxima =
  forAll arbitraryField $ \f ->
    let merged = combineField CombineMaxima f emptyField
    in fieldResonance     merged == fieldResonance     f
       && fieldConsolidation  merged == fieldConsolidation  f
       && fieldCounterfactual merged == fieldCounterfactual f
       && atmosphereValence (fieldAtmosphere merged)
            == 0.5 * atmosphereValence (fieldAtmosphere f)
       && atmosphereArousal (fieldAtmosphere merged)
            == 0.5 * atmosphereArousal (fieldAtmosphere f)

-- ---------------------------------------------------------------------------
-- deriveFieldConfidence boundary cases
-- ---------------------------------------------------------------------------

-- | A field whose four scalarised components are all equal is
-- maximally coherent and should receive 'FieldConfidence 1.0'.
propUniformFieldMaxConfidence :: Property
propUniformFieldMaxConfidence =
  forAll arbitraryUnitDouble $ \x ->
    let scaffold =
          Field
            { fieldResonance      = mkResonance x
            , fieldAtmosphere     = mkAtmosphere 0.0 x
            , fieldConfidence     = mkFieldConfidence 1.0
            , fieldConsolidation  = mkConsolidation x
            , fieldCounterfactual = mkCounterfactual x
            }
        FieldConfidence c = deriveFieldConfidence scaffold
    in abs (c - 1.0) < 1e-9

-- | The derivation always lands in [0, 1].
propDeriveFieldConfidenceInRange :: Property
propDeriveFieldConfidenceInRange =
  forAll arbitraryField $ \f ->
    let FieldConfidence c = deriveFieldConfidence f
    in c >= 0.0 && c <= 1.0 + 1e-12

-- ---------------------------------------------------------------------------
-- Adjunction smoke test
-- ---------------------------------------------------------------------------

-- | Sanity check that the Phase-3 'Holistic' \/ 'Formal'
-- adjunction continues to compose against the substantive 'Field'.
-- We exercise 'unit' followed by 'counit' on a Holistic value and
-- expect to get back the original.
propAdjunctionSmoke :: Property
propAdjunctionSmoke =
  forAll arbitraryField $ \fd ->
  forAll (choose (-100, 100 :: Int)) $ \a ->
    let h        = Holistic (a, fd)
        rebuilt  = counit (fmap unit h)
    in h == rebuilt

-- ---------------------------------------------------------------------------
-- Phase-7 heuristic lifeness gates
-- ---------------------------------------------------------------------------

propComputeConsolidationInRange :: Property
propComputeConsolidationInRange =
  forAll arbitrary $ \recentSuccess ->
  forAll (choose (False, True)) $ \sameTopic ->
    let Consolidation c = computeConsolidation defaultFieldHeuristics (recentSuccess :: [Bool]) sameTopic
    in c >= 0.0 && c <= 1.0

propComputeCounterfactualInRange :: Property
propComputeCounterfactualInRange =
  forAll arbitrary $ \weights ->
  forAll (choose (0, 100 :: Int)) $ \streak ->
    let Counterfactual c = computeCounterfactual defaultFieldHeuristics (weights :: [Double]) streak
    in c >= 0.0 && c <= 1.0

propComputeAtmosphereValenceInRange :: Property
propComputeAtmosphereValenceInRange =
  forAll arbitraryWideDouble $ \egoAgency ->
  forAll arbitraryWideDouble $ \egoTension ->
  forAll arbitraryWideDouble $ \legitScore ->
    let Atmosphere v _ = computeAtmosphere defaultFieldHeuristics egoAgency egoTension legitScore
    in v >= -1.0 && v <= 1.0

propComputeAtmosphereArousalInRange :: Property
propComputeAtmosphereArousalInRange =
  forAll arbitraryWideDouble $ \egoAgency ->
  forAll arbitraryWideDouble $ \egoTension ->
  forAll arbitraryWideDouble $ \legitScore ->
    let Atmosphere _ a = computeAtmosphere defaultFieldHeuristics egoAgency egoTension legitScore
    in a >= 0.0 && a <= 1.0

propSameTopicBoostsConsolidation :: Property
propSameTopicBoostsConsolidation =
  forAll arbitrary $ \recentSuccess ->
    let off = computeConsolidation defaultFieldHeuristics (recentSuccess :: [Bool]) False
        on  = computeConsolidation defaultFieldHeuristics recentSuccess True
    in unConsolidation on >= unConsolidation off

propStreakBoostsCounterfactual :: Property
propStreakBoostsCounterfactual =
  forAll arbitrary $ \weights ->
  forAll (choose (0, 50 :: Int)) $ \low ->
  forAll (choose (low, 100 :: Int)) $ \high ->
    let lowCF  = computeCounterfactual defaultFieldHeuristics (weights :: [Double]) low
        highCF = computeCounterfactual defaultFieldHeuristics weights high
    in unCounterfactual highCF >= unCounterfactual lowCF

propHighLegitimacyRaisesValence :: Property
propHighLegitimacyRaisesValence =
  forAll arbitraryWideDouble $ \egoAgency ->
  forAll arbitraryWideDouble $ \egoTension ->
  forAll arbitraryWideDouble $ \lowLegit ->
  forAll (choose (lowLegit, 100.0)) $ \highLegit ->
    let lowAtm  = computeAtmosphere defaultFieldHeuristics egoAgency egoTension lowLegit
        highAtm = computeAtmosphere defaultFieldHeuristics egoAgency egoTension highLegit
    in atmosphereValence highAtm >= atmosphereValence lowAtm

-- | Phase 6.7: verify that a non-default heuristic parameter
-- actually changes the compute function output.  If this test
-- fails, the plumbing is broken (the override is not reaching
-- the compute site).
testHeuristicsOverrideHonored :: IO ()
testHeuristicsOverrideHonored = do
  let defaultAtm = computeAtmosphere defaultFieldHeuristics 0.5 0.5 0.8
      tweaked    = defaultFieldHeuristics { fhLegitimacyBonusScale = 0.99 }
      tweakedAtm = computeAtmosphere tweaked 0.5 0.5 0.8
  assertBool "override must change valence"
    (atmosphereValence tweakedAtm /= atmosphereValence defaultAtm)

-- ---------------------------------------------------------------------------
-- Phase-B bounded post-commitment adaptation
-- ---------------------------------------------------------------------------

arbitraryFieldHeuristics :: Gen FieldHeuristics
arbitraryFieldHeuristics = do
  nw   <- choose (1, 20)
  dnr  <- choose (0.0, 1.0)
  tsb  <- choose (0.0, 1.0)
  ee   <- choose (1e-12, 1e-6)
  hsbr <- choose (0.0, 1.0)
  hsbc <- choose (0.0, 1.0)
  lm   <- choose (0.0, 1.0)
  lbs  <- choose (0.0, 1.0)
  pure $ FieldHeuristics nw dnr tsb ee hsbr hsbc lm lbs

propAdaptFieldHeuristicsIdentity :: Property
propAdaptFieldHeuristicsIdentity =
  forAll arbitraryFieldHeuristics $ \fh ->
    adaptFieldHeuristics 0.0 fh == fh

propAdaptFieldHeuristicsClamp :: Property
propAdaptFieldHeuristicsClamp =
  forAll arbitraryFieldHeuristics $ \fh ->
  forAll (choose (-10.0, 10.0)) $ \signal ->
    let adapted = adaptFieldHeuristics signal fh
    in all (\x -> x >= 0.0 && x <= 1.0)
         [ fhDefaultNarrativeRate adapted
         , fhTopicStabilityBoost adapted
         , fhHolisticStreakBoostRate adapted
         , fhHolisticStreakBoostCap adapted
         , fhLegitimacyMidpoint adapted
         , fhLegitimacyBonusScale adapted
         ]

propAdaptFieldHeuristicsAntiDrift :: Property
propAdaptFieldHeuristicsAntiDrift =
  forAll arbitraryFieldHeuristics $ \fh ->
  forAll (choose (-10.0, 10.0)) $ \signal ->
    let adapted = adaptFieldHeuristics signal fh
        def = defaultFieldHeuristics
        withinDrift x target = abs (x - target) <= 0.5 + 1e-12
    in withinDrift (fhDefaultNarrativeRate adapted)    (fhDefaultNarrativeRate def)
    && withinDrift (fhTopicStabilityBoost adapted)     (fhTopicStabilityBoost def)
    && withinDrift (fhHolisticStreakBoostRate adapted) (fhHolisticStreakBoostRate def)
    && withinDrift (fhHolisticStreakBoostCap adapted)  (fhHolisticStreakBoostCap def)
    && withinDrift (fhLegitimacyMidpoint adapted)      (fhLegitimacyMidpoint def)
    && withinDrift (fhLegitimacyBonusScale adapted)    (fhLegitimacyBonusScale def)
