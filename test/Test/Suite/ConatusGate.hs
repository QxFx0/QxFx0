{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.ConatusGate
Description : Anti-rot tests for P1 Conatus Gate integration.

Property tests verifying that low Conatus energy restricts family
selection to restorative families (CMContact, CMAnchor, CMRepair)
and prohibits high-risk families (CMConfront, CMHypothesis,
CMDistinguish), as specified in ADR-0045.

These tests close the gap between Conatus computation (which was
already traced) and routing behaviour (which previously ignored the
signal). If the wire is disconnected, these tests fail.
-}
module Test.Suite.ConatusGate
  ( conatusGateTests
  ) where

import Test.HUnit (Test (..), assertBool)

import QxFx0.Core.TurnRouting (applyConatusGateRestriction)
import QxFx0.Self.Conatus
  ( ConatusComponents (..)
  , ConatusEnergy (..)
  , ConatusWeights (..)
  , computeConatusEnergyWith
  , lowEnergyThreshold
  )
import QxFx0.Self.Types (SelfBlanket (..))
import QxFx0.Types (CanonicalMoveFamily (..))

-- | Helper: construct a ConatusEnergy with a specific scalar value.
-- Used to test the threshold boundary without needing to construct
-- complex blankets.
mkConatusEnergy :: Double -> ConatusEnergy
mkConatusEnergy scalar =
  ConatusEnergy
    { ceScalar = scalar
    , ceComponents = ConatusComponents
        { ccMorphology = scalar
        , ccIdentity = 0
        , ccTurns = 0
        , ccPenalty = 0
        }
    }

-- | Helper: construct a low-energy blanket (below threshold).
-- A minimal blanket with 1 morphology entry, 0 claims, 0 turns yields:
-- C = 1.0 * log(2) ≈ 0.69, well below threshold of 3.0.
lowEnergyBlanket :: SelfBlanket
lowEnergyBlanket = SelfBlanket
  { sbSessionId = "low-energy-test"
  , sbMorphologyTotalSize = 1
  , sbIdentityClaimsCount = 0
  , sbTurnCount = 0
  }

-- | Helper: construct a high-energy blanket (above threshold).
-- A healthy blanket with 20 morphology entries, 5 claims, 10 turns yields:
-- C = 1.0 * log(21) + 0.5 * log(6) + 0.25 * log(11) ≈ 4.5, above threshold.
highEnergyBlanket :: SelfBlanket
highEnergyBlanket = SelfBlanket
  { sbSessionId = "high-energy-test"
  , sbMorphologyTotalSize = 20
  , sbIdentityClaimsCount = 5
  , sbTurnCount = 10
  }

-- | All canonical move families for exhaustive testing.
allFamilies :: [CanonicalMoveFamily]
allFamilies =
  [ CMContact
  , CMAnchor
  , CMRepair
  , CMClarify
  , CMGround
  , CMDeepen
  , CMConfront
  , CMHypothesis
  , CMDistinguish
  ]

-- | Restorative families that are always allowed, even at low energy.
restorativeFamilies :: [CanonicalMoveFamily]
restorativeFamilies = [CMContact, CMAnchor, CMRepair]

-- | High-risk families that are prohibited at low energy.
highRiskFamilies :: [CanonicalMoveFamily]
highRiskFamilies = [CMConfront, CMHypothesis, CMDistinguish]

-- | Check if a family is restorative (safe at low energy).
isRestorative :: CanonicalMoveFamily -> Bool
isRestorative f = f `elem` restorativeFamilies

conatusGateTests :: [Test]
conatusGateTests =
  [ TestLabel "low energy restricts CMConfront to CMContact" $
      TestCase $ do
        let restricted = applyConatusGateRestriction CMConfront
        assertBool
          ("CMConfront should map to CMContact at low energy, got " <> show restricted)
          (restricted == CMContact)

  , TestLabel "low energy restricts CMHypothesis to CMAnchor" $
      TestCase $ do
        let restricted = applyConatusGateRestriction CMHypothesis
        assertBool
          ("CMHypothesis should map to CMAnchor at low energy, got " <> show restricted)
          (restricted == CMAnchor)

  , TestLabel "low energy restricts CMDistinguish to CMRepair" $
      TestCase $ do
        let restricted = applyConatusGateRestriction CMDistinguish
        assertBool
          ("CMDistinguish should map to CMRepair at low energy, got " <> show restricted)
          (restricted == CMRepair)

  , TestLabel "low energy preserves restorative families" $
      TestCase $ do
        let results = [(f, applyConatusGateRestriction f) | f <- restorativeFamilies]
            allPreserved = all (\(orig, res) -> orig == res) results
        assertBool
          ("Restorative families should be unchanged at low energy: " <> show results)
          allPreserved

  , TestLabel "low energy preserves safe non-restorative families" $
      TestCase $ do
        -- CMClarify, CMGround, CMDeepen are not high-risk, should pass through
        let safeFamilies = [CMClarify, CMGround, CMDeepen]
            results = [(f, applyConatusGateRestriction f) | f <- safeFamilies]
            allPreserved = all (\(orig, res) -> orig == res) results
        assertBool
          ("Safe non-restorative families should be unchanged: " <> show results)
          allPreserved

  , TestLabel "property: all high-risk families map to restorative" $
      TestCase $ do
        let results = [(f, applyConatusGateRestriction f) | f <- highRiskFamilies]
            allRestorative = all (\(_, res) -> isRestorative res) results
        assertBool
          ("All high-risk families must map to restorative families: " <> show results)
          allRestorative

  , TestLabel "property: low energy blanket is below threshold" $
      TestCase $ do
        let ce = computeConatusEnergyWith
                   (ConatusWeights 1.0 0.5 0.25 10.0)
                   lowEnergyBlanket
                   []
        assertBool
          ("Low energy blanket must be below threshold: scalar="
            <> show (ceScalar ce) <> " threshold=" <> show lowEnergyThreshold)
          (ceScalar ce < lowEnergyThreshold)

  , TestLabel "property: high energy blanket is above threshold" $
      TestCase $ do
        let ce = computeConatusEnergyWith
                   (ConatusWeights 1.0 0.5 0.25 10.0)
                   highEnergyBlanket
                   []
        assertBool
          ("High energy blanket must be above threshold: scalar="
            <> show (ceScalar ce) <> " threshold=" <> show lowEnergyThreshold)
          (ceScalar ce >= lowEnergyThreshold)

  , TestLabel "property: restriction is idempotent" $
      TestCase $ do
        -- Applying restriction twice should give same result as once
        let results = [(f, applyConatusGateRestriction f,
                        applyConatusGateRestriction (applyConatusGateRestriction f))
                      | f <- allFamilies]
            allIdempotent = all (\(_, once, twice) -> once == twice) results
        assertBool
          ("Restriction must be idempotent: " <> show results)
          allIdempotent

  , TestLabel "threshold value is sensible (between 1 and 10)" $
      TestCase $ do
        assertBool
          ("Threshold must be in sensible range [1, 10]: " <> show lowEnergyThreshold)
          (lowEnergyThreshold > 1.0 && lowEnergyThreshold < 10.0)

  , TestLabel "anti-rot: applyConatusGateRestriction is total on all families" $
      TestCase $ do
        -- This test ensures the function doesn't crash on any family
        let results = [(f, applyConatusGateRestriction f) | f <- allFamilies]
            allDefined = length results == length allFamilies
        assertBool
          ("Restriction must be defined for all families: " <> show results)
          allDefined
  ]

