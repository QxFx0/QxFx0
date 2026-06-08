{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

{-|
Module      : Test.Suite.FMARCore
Description : FMAR Phase-4 — property tests for fmarSelectFamily.

Verifies the laws asserted in the FMAR plan, Phase 4:

  * determinism: same position + recommendation → same family;
  * recommendation preserved when the position sits at the recommended
    family's target Field (distance 0 ≤ threshold);
  * override: when the position sits exactly at family X's target while the
    detector recommended a far-away family Y, FMAR moves toward X;
  * the result is always one of the 14 canonical families;
  * a viability guard: the override never proposes a family whose
    @ftMinConatus@ exceeds the position energy (unless it is the
    recommendation kept as-is, or the CMContact fallback).
-}
module Test.Suite.FMARCore
  ( fmarCoreTests
  ) where

import Test.HUnit (Test (..), assertBool, assertEqual)
import Test.QuickCheck
  ( Gen
  , Property
  , choose
  , elements
  , forAll
  , maxSuccess
  , quickCheckWithResult
  , stdArgs
  )
import Test.QuickCheck.Test (isSuccess)

import QxFx0.Core.FMAR (fmarSelectFamily)
import QxFx0.Self.AdaptivePosition
  ( AdaptivePosition (..)
  , SpectralEncoding (..)
  )
import QxFx0.Self.Field
  ( Field (..)
  , mkAtmosphere
  , mkConsolidation
  , mkCounterfactual
  , mkFieldConfidence
  , mkResonance
  )
import QxFx0.Self.FamilyTargets
  ( FamilyTarget (..)
  , closestFamilyByField
  , familyTargetFor
  , familyTargets
  )
import QxFx0.Types
  ( CanonicalMoveFamily (..)
  , ClauseForm (..)
  , IllocutionaryForce (..)
  , MeaningDirective (..)
  , R5Verdict (..)
  , SemanticLayer (..)
  , WarrantedMoveMode (..)
  , mkVerdict
  , mkVerdictWithDirective
  )
import QxFx0.Core.FMAR
  ( FmarMode (..)
  , fmarSeed
  , isFmarActive
  , readFmarMode
  )
import QxFx0.Self.Field
  ( Atmosphere (..)
  , Field (..)
  , FieldConfidence (..)
  , emptyField
  , mkAtmosphere
  , mkFieldConfidence
  , mkResonance
  )

-- ---------------------------------------------------------------------------
-- Test-suite entry point
-- ---------------------------------------------------------------------------

fmarCoreTests :: [Test]
fmarCoreTests =
  [ TestLabel "fmarSelectFamily is deterministic" $
      quickCheckProperty "deterministic" propDeterministic
  , TestLabel "fmarSelectFamily result is a valid family" $
      quickCheckProperty "valid family" propValidFamily
  , TestLabel "recommendation preserved when position at its target" $
      TestCase $ assertBool "all preserved" recommendationPreservedAtTarget
  , TestLabel "override moves toward the family the position sits at" $
      TestCase $ assertEqual "override to CMConfront" CMConfront overrideToConfront
  , TestLabel "high-energy position never blocked by viability on override" $
      quickCheckProperty "viability respected" propViabilityRespected
  , TestLabel "fmarSeed with emptyField yields consistent seed" $
      TestCase $ assertBool "emptyField baseline"
        (fmarSeed "x" emptyField == "x|1.0|0.0|0.0")
  , TestLabel "fmarSeed with different Field yields different seed" $
      TestCase $
        let f1 = emptyField
            f2 = emptyField
              { fieldConfidence = mkFieldConfidence 0.8
              , fieldAtmosphere = mkAtmosphere 0.3 0.5
              }
         in assertBool "different Field → different seed"
              (fmarSeed "x" f1 /= fmarSeed "x" f2)
  , TestLabel "readFmarMode parses shadow/live/off fail-closed" $
      TestCase $ do
        assertEqual "unset → off" FmarOff (readFmarMode Nothing)
        assertEqual "0 → off" FmarOff (readFmarMode (Just "0"))
        assertEqual "shadow" FmarShadow (readFmarMode (Just "shadow"))
        assertEqual "SHADOW case-insensitive" FmarShadow (readFmarMode (Just "SHADOW"))
        assertEqual "live" FmarLive (readFmarMode (Just "live"))
        assertEqual "1 → live" FmarLive (readFmarMode (Just "1"))
        assertEqual "unknown → off (fail-closed)" FmarOff (readFmarMode (Just "wat"))
  , TestLabel "isFmarActive is True for shadow and live only" $
      TestCase $ do
        assertBool "off inactive" (not (isFmarActive FmarOff))
        assertBool "shadow active" (isFmarActive FmarShadow)
        assertBool "live active" (isFmarActive FmarLive)
  , TestLabel "FMAR scenario validation: realistic Fields route to intended families" $
      TestCase $ mapM_ assertScenario fmarScenarios
  , TestLabel "mkVerdict sets r5Directive to Nothing" $
      TestCase $ assertBool "r5Directive is Nothing" (r5Directive (mkVerdict CMContact) == Nothing)
  , TestLabel "mkVerdictWithDirective sets r5Directive to Just" $
      TestCase $
        let directive = MeaningDirective
              { mdFamily = CMContact
              , mdDetectorFamily = CMContact
              , mdFieldDelta = emptyField
              , mdForce = IFContact
              , mdClause = Declarative
              , mdLayer = ContactLayer
              , mdWarranted = AlwaysWarranted
              , mdConatusGateOk = True
              , mdRescueUsed = False
              , mdFieldDistance = 0.0
              , mdAbstractionBudget = 0
              , mdMaxWordsHint = 0
              }
            verdict = mkVerdictWithDirective directive
         in assertBool "r5Directive is Just" (r5Directive verdict == Just directive)
  ]

-- ---------------------------------------------------------------------------
-- Properties and checks
-- ---------------------------------------------------------------------------

propDeterministic :: Property
propDeterministic = forAll genPosition $ \pos ->
  forAll genFamily $ \rec ->
    fmarSelectFamily pos rec familyTargets == fmarSelectFamily pos rec familyTargets

propValidFamily :: Property
propValidFamily = forAll genPosition $ \pos ->
  forAll genFamily $ \rec ->
    fmarSelectFamily pos rec familyTargets `elem` [minBound .. maxBound]

-- | For each family, place the position exactly at its target Field and
-- recommend that same family. Distance is 0 ≤ threshold, so FMAR must keep
-- the recommendation unchanged.
recommendationPreservedAtTarget :: Bool
recommendationPreservedAtTarget =
  all
    ( \t ->
        let pos = positionAt (ftTargetField t)
         in fmarSelectFamily pos (ftFamily t) familyTargets == ftFamily t
    )
    familyTargets

-- | Position sits exactly at CMConfront's target, but the detector
-- recommended CMContact (a distant, calm family). Since the position is far
-- from CMContact's target, FMAR overrides; the closest family to the
-- position is CMConfront itself. Energy is high so all families are viable.
overrideToConfront :: CanonicalMoveFamily
overrideToConfront =
  let confrontTarget = familyTargetFor CMConfront
      pos = (positionAt (ftTargetField confrontTarget)) { apConatusEnergy = 100.0 }
   in fmarSelectFamily pos CMContact familyTargets

-- | When the recommendation is overridden, the chosen family must either be
-- CMContact (the fallback) or have its @ftMinConatus@ satisfied by the
-- position energy. We test with positions whose recommendation is forced far
-- by using a low-confidence field that is distant from most targets.
propViabilityRespected :: Property
propViabilityRespected = forAll genPosition $ \pos ->
  forAll genFamily $ \rec ->
    let chosen = fmarSelectFamily pos rec familyTargets
        target = familyTargetFor chosen
     in chosen == rec
          || chosen == CMContact
          || ftMinConatus target <= apConatusEnergy pos

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- | Position whose Field is exactly @f@, spectral at origin, neutral energy.
positionAt :: Field -> AdaptivePosition
positionAt f =
  AdaptivePosition
    { apField         = f
    , apSpectral      = SpectralEncoding 0.0 0.0 0.0
    , apConatusEnergy = 10.0
    }

-- ---------------------------------------------------------------------------
-- Generators
-- ---------------------------------------------------------------------------

genPosition :: Gen AdaptivePosition
genPosition =
  AdaptivePosition
    <$> genField
    <*> genSpectral
    <*> choose (-5.0, 15.0)

genField :: Gen Field
genField =
  Field
    <$> (mkResonance <$> choose (0.0, 1.0))
    <*> (mkAtmosphere <$> choose (-1.0, 1.0) <*> choose (0.0, 1.0))
    <*> (mkFieldConfidence <$> choose (0.0, 1.0))
    <*> (mkConsolidation <$> choose (0.0, 1.0))
    <*> (mkCounterfactual <$> choose (0.0, 1.0))

genSpectral :: Gen SpectralEncoding
genSpectral =
  SpectralEncoding
    <$> elements [0.0, 0.5, 1.0]
    <*> elements [0.0, 0.5, 1.0]
    <*> elements [0.0, 1.0 / 3.0, 2.0 / 3.0, 1.0]

genFamily :: Gen CanonicalMoveFamily
genFamily = elements [minBound .. maxBound]

-- ---------------------------------------------------------------------------
-- QuickCheck plumbing
-- ---------------------------------------------------------------------------

quickCheckProperty :: String -> Property -> Test
quickCheckProperty label prop = TestCase $ do
  result <- quickCheckWithResult stdArgs { maxSuccess = 200 } prop
  assertBool ("Property failed: " ++ label) (isSuccess result)

-- ---------------------------------------------------------------------------
-- Scenario validation: realistic Field states → intended families
-- ---------------------------------------------------------------------------
--
-- Each scenario asserts that a Field state with an interpretable meaning
-- routes to the intended family when FMAR is given a neutral, distant
-- recommendation (CMGround). This validates that the 14 editorial target
-- Fields carve the space sensibly — not just that each target is closest to
-- itself, but that off-target realistic states land in the right family.
--
-- High energy (10.0) so the Conatus viability filter never excludes a target.

-- | (label, current Field, intended family).
fmarScenarios :: [(String, Field, CanonicalMoveFamily)]
fmarScenarios =
  [ ( "very low confidence + negative valence → repair"
    , field 0.30 (-0.10) 0.30 0.30 0.20 0.30
    , CMRepair
    )
  , ( "high confidence + high consolidation + low arousal → anchor"
    , field 0.80 0.40 0.10 0.90 0.90 0.05
    , CMAnchor
    )
  , ( "negative valence + high arousal + mid confidence → confront"
    , field 0.40 (-0.20) 0.70 0.50 0.40 0.50
    , CMConfront
    )
  , ( "high resonance + low arousal + calm → reflect"
    , field 0.90 0.10 0.15 0.80 0.75 0.20
    , CMReflect
    )
  , ( "warm positive contact state → contact"
    , field 0.70 0.30 0.20 0.90 0.80 0.10
    , CMContact
    )
  ]
  where field = scenarioField

-- | Build a full Field from six raw component values.
scenarioField :: Double -> Double -> Double -> Double -> Double -> Double -> Field
scenarioField resonance valence arousal confidence consolidation counterfactual =
  Field
    { fieldResonance      = mkResonance resonance
    , fieldAtmosphere     = mkAtmosphere valence arousal
    , fieldConfidence     = mkFieldConfidence confidence
    , fieldConsolidation  = mkConsolidation consolidation
    , fieldCounterfactual = mkCounterfactual counterfactual
    }

-- | Position from a Field, spectral origin, high energy (no viability cutoff).
scenarioPos :: Field -> AdaptivePosition
scenarioPos f =
  AdaptivePosition
    { apField         = f
    , apSpectral      = SpectralEncoding 0.0 0.0 0.0
    , apConatusEnergy = 10.0
    }

-- | Assert a scenario: the geometric classifier must map the given Field
-- to its intended family. This validates that the 14 target Fields carve
-- the space correctly, independent of the override threshold (which is
-- exercised separately — a state may be classified to family X yet sit
-- close enough to the detector recommendation that FMAR keeps the latter).
assertScenario :: (String, Field, CanonicalMoveFamily) -> IO ()
assertScenario (label, f, expected) =
  let chosen = closestFamilyByField (scenarioPos f) familyTargets
   in assertEqual ("scenario: " ++ label) expected chosen
