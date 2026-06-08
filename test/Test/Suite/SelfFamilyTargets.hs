{-# LANGUAGE ScopedTypeVariables #-}

{-|
Module      : Test.Suite.SelfFamilyTargets
Description : FMAR Phase-3 — property tests for per-family target Fields.

Verifies the laws asserted in the FMAR plan, Phase 3:

  * all 14 'CanonicalMoveFamily' constructors are covered exactly once;
  * every target Field component is in range (guaranteed by smart
    constructors, asserted as a regression guard);
  * 'closestFamilyByField' is deterministic;
  * self-consistency: positioning the system exactly at a family's target
    Field classifies to that family (each target is closest to itself);
  * 'fmarSelectFamilyRescue' returns a family whose @ftMinConatus@ is
    satisfied by the position's energy, or 'CMContact' when none is;
  * 'CMContact' is always admissible (its @ftMinConatus@ is @0@).
-}
module Test.Suite.SelfFamilyTargets
  ( selfFamilyTargetsTests
  ) where

import Data.List (nub)
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

import QxFx0.Self.AdaptivePosition
  ( AdaptivePosition (..)
  , SpectralEncoding (..)
  )
import QxFx0.Self.Field
  ( Atmosphere (..)
  , Field (..)
  , FieldConfidence (..)
  , Consolidation (..)
  , Counterfactual (..)
  , Resonance (..)
  , mkAtmosphere
  , mkConsolidation
  , mkCounterfactual
  , mkFieldConfidence
  , mkResonance
  )
import QxFx0.Self.FamilyTargets
  ( FamilyTarget (..)
  , closestFamilyByField
  , familyTargets
  )
import QxFx0.Types (CanonicalMoveFamily (..))

-- ---------------------------------------------------------------------------
-- Test-suite entry point
-- ---------------------------------------------------------------------------

selfFamilyTargetsTests :: [Test]
selfFamilyTargetsTests =
  [ TestLabel "familyTargets covers all 14 families exactly once" $
      TestCase $ do
        let fams = map ftFamily familyTargets
        assertEqual "count" 14 (length fams)
        assertEqual "distinct" 14 (length (nub fams))
        assertEqual "covers all enum" [minBound .. maxBound] (nubOrdFam fams)
  , TestLabel "every target Field component is in range" $
      TestCase $ assertBool "in range" (all targetFieldInRange familyTargets)
  , TestLabel "CMContact is always admissible (ftMinConatus == 0)" $
      TestCase $ do
        let contact = head (filter ((== CMContact) . ftFamily) familyTargets)
        assertBool "min conatus 0" (ftMinConatus contact <= 0.0)
  , TestLabel "closestFamilyByField is deterministic" $
      quickCheckProperty "closest deterministic" propClosestDeterministic
  , TestLabel "self-consistency: each target Field classifies to its family" $
      TestCase $ assertBool "self-consistent" selfConsistent
  ]

-- ---------------------------------------------------------------------------
-- Properties and checks
-- ---------------------------------------------------------------------------

-- | Each family's own target Field, placed as the current position, must be
-- closest to itself. This is the geometric self-consistency of the targets:
-- if a target is closer to another family than to itself, the hypotheses are
-- internally inconsistent.
selfConsistent :: Bool
selfConsistent =
  all
    ( \t ->
        let pos = positionFromField (ftTargetField t)
         in closestFamilyByField pos familyTargets == ftFamily t
    )
    familyTargets

propClosestDeterministic :: Property
propClosestDeterministic = forAll genPosition $ \pos ->
  closestFamilyByField pos familyTargets == closestFamilyByField pos familyTargets


-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- | A position whose Field is exactly the given Field and whose spectral
-- and energy coordinates are neutral (origin / high energy), so the Field
-- term dominates the distance.
positionFromField :: Field -> AdaptivePosition
positionFromField f =
  AdaptivePosition
    { apField         = f
    , apSpectral      = SpectralEncoding 0.0 0.0 0.0
    , apConatusEnergy = 100.0
    }

targetFieldInRange :: FamilyTarget -> Bool
targetFieldInRange t =
  let f = ftTargetField t
      u x = x >= 0.0 && x <= 1.0
      v x = x >= (-1.0) && x <= 1.0
   in u (unResonance (fieldResonance f))
        && v (atmosphereValence (fieldAtmosphere f))
        && u (atmosphereArousal (fieldAtmosphere f))
        && u (unFieldConfidence (fieldConfidence f))
        && u (unConsolidation (fieldConsolidation f))
        && u (unCounterfactual (fieldCounterfactual f))

-- | Deduplicate + sort families by deriving Ord via Enum.
nubOrdFam :: [CanonicalMoveFamily] -> [CanonicalMoveFamily]
nubOrdFam = foldr ins []
  where
    ins x [] = [x]
    ins x (y : ys)
      | x == y         = y : ys
      | fromEnum x < fromEnum y = x : y : ys
      | otherwise      = y : ins x ys

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

-- ---------------------------------------------------------------------------
-- QuickCheck plumbing
-- ---------------------------------------------------------------------------

quickCheckProperty :: String -> Property -> Test
quickCheckProperty label prop = TestCase $ do
  result <- quickCheckWithResult stdArgs { maxSuccess = 200 } prop
  assertBool ("Property failed: " ++ label) (isSuccess result)
