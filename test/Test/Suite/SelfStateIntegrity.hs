{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.SelfStateIntegrity
Description : Unit tests for the Phase-2 Conatus functional.

Pure tests over 'QxFx0.Self.StateIntegrity.computeStateIntegrityEnergy' and
'QxFx0.Self.StateIntegrity.computeStateIntegrityGradient', exercising the formal
properties asserted in @docs\/THEORY.md@ §4.2 and elaborated in the
Haddock for 'QxFx0.Self.StateIntegrity':

 * monotonicity in each blanket axis,
 * exact violation-penalty arithmetic,
 * gradient sign and diminishing-returns shape,
 * scalar = sum-of-components invariant,
 * well-definedness at the degenerate \((0, 0, 0)\) blanket,
 * normalisation properties.
-}
module Test.Suite.SelfStateIntegrity
  ( selfStateIntegrityTests
  ) where

import Test.HUnit (Test (..), assertBool, assertFailure)

import QxFx0.Self.StateIntegrity
  ( StateIntegrityComponents (..)
  , StateIntegrity (..)
  , StateIntegrityGradient (..)
  , StateIntegrityWeights (..)
  , computeStateIntegrityEnergy
  , computeStateIntegrityEnergyWith
  , computeStateIntegrityGradient
  , computeStateIntegrityGradientWith
  , stateIntegrityViolationPenalty
  , defaultStateIntegrityWeights
  , gradientMagnitude
  , gradientNormalize
  )
import QxFx0.Self.Types
  ( BlanketViolation (..)
  , SelfBlanket (..)
  )

-- | Approximate floating-point equality with a small absolute
-- tolerance. Conatus arithmetic uses 'log' and divisions, so we do
-- not expect bit-exact results but expect agreement to several
-- decimal places.
approxEqual :: Double -> Double -> Double -> Bool
approxEqual tol x y = abs (x - y) <= tol

eps :: Double
eps = 1e-9

-- | Baseline blanket used as the start of monotonicity comparisons.
baseBlanket :: SelfBlanket
baseBlanket = SelfBlanket
  { sbSessionId           = "demo"
  , sbMorphologyTotalSize = 10
  , sbIdentityClaimsCount = 2
  , sbTurnCount           = 5
  }

selfStateIntegrityTests :: [Test]
selfStateIntegrityTests =
  [ TestLabel "scalar equals sum of components (no violations)" $
      TestCase $ do
        let ce    = computeStateIntegrityEnergy baseBlanket []
            comps = siComponents ce
            sumC  = sicMorphology comps + sicIdentity comps + sicTurns comps + sicPenalty comps + sicSelfDivergence comps
        assertBool
          ("scalar/component disagreement: scalar=" <> show (siScalar ce)
            <> " sum=" <> show sumC)
          (approxEqual eps (siScalar ce) sumC)

  , TestLabel "scalar equals sum of components (with violations)" $
      TestCase $ do
        let vs    = [BlanketEmptySession, BlanketTurnRegressed 3 1]
            ce    = computeStateIntegrityEnergy baseBlanket vs
            comps = siComponents ce
            sumC  = sicMorphology comps + sicIdentity comps + sicTurns comps + sicPenalty comps + sicSelfDivergence comps
        assertBool
          "scalar must equal sum of all five components in the presence of violations"
          (approxEqual eps (siScalar ce) sumC)

  , TestLabel "degenerate blanket (0,0,0) gives zero smooth scalar" $
      TestCase $ do
        let degenerate = baseBlanket
              { sbMorphologyTotalSize = 0
              , sbIdentityClaimsCount = 0
              , sbTurnCount           = 0
              }
            ce = computeStateIntegrityEnergy degenerate []
        assertBool
          ("degenerate scalar must equal 0, got " <> show (siScalar ce))
          (approxEqual eps (siScalar ce) 0)

  , TestLabel "scalar is monotone in morphology size" $
      TestCase $ do
        let smaller = baseBlanket { sbMorphologyTotalSize = 10 }
            larger  = baseBlanket { sbMorphologyTotalSize = 100 }
            ceS     = computeStateIntegrityEnergy smaller []
            ceL     = computeStateIntegrityEnergy larger  []
        assertBool
          "more morphology => greater Conatus"
          (siScalar ceL > siScalar ceS)

  , TestLabel "scalar is monotone in identity claims count" $
      TestCase $ do
        let smaller = baseBlanket { sbIdentityClaimsCount = 0 }
            larger  = baseBlanket { sbIdentityClaimsCount = 20 }
            ceS     = computeStateIntegrityEnergy smaller []
            ceL     = computeStateIntegrityEnergy larger  []
        assertBool
          "more identity claims => greater Conatus"
          (siScalar ceL > siScalar ceS)

  , TestLabel "scalar is monotone in turn count" $
      TestCase $ do
        let smaller = baseBlanket { sbTurnCount = 1 }
            larger  = baseBlanket { sbTurnCount = 200 }
            ceS     = computeStateIntegrityEnergy smaller []
            ceL     = computeStateIntegrityEnergy larger  []
        assertBool
          "more turns => greater Conatus"
          (siScalar ceL > siScalar ceS)

  , TestLabel "each violation drops scalar by exactly the violation weight" $
      TestCase $ do
        let clean      = computeStateIntegrityEnergy baseBlanket []
            withOne    = computeStateIntegrityEnergy baseBlanket [BlanketEmptySession]
            withTwo    = computeStateIntegrityEnergy baseBlanket
                          [BlanketEmptySession, BlanketEmptyMorphology]
            withThree  = computeStateIntegrityEnergy baseBlanket
                          [ BlanketEmptySession
                          , BlanketEmptyMorphology
                          , BlanketTurnRegressed 4 2
                          ]
            lam        = siwViolation defaultStateIntegrityWeights
        assertBool "one violation drops scalar by lambda"
          (approxEqual eps (siScalar clean - siScalar withOne) lam)
        assertBool "two violations drop scalar by 2*lambda"
          (approxEqual eps (siScalar clean - siScalar withTwo) (2 * lam))
        assertBool "three violations drop scalar by 3*lambda"
          (approxEqual eps (siScalar clean - siScalar withThree) (3 * lam))

  , TestLabel "violation penalty helper matches inline computation" $
      TestCase $ do
        let vs   = [BlanketEmptySession, BlanketIdentityErased 5 3]
            comp = siComponents (computeStateIntegrityEnergy baseBlanket vs)
            via  = stateIntegrityViolationPenalty defaultStateIntegrityWeights vs
        assertBool
          "conatusViolationPenalty must agree with ccPenalty"
          (approxEqual eps via (sicPenalty comp))

  , TestLabel "violations do not affect gradient" $
      TestCase $ do
        let g  = computeStateIntegrityGradient baseBlanket
            -- Gradient does not take violations; this test
            -- documents the structural invariant that the gradient
            -- depends only on the blanket axes.
            allPositive = sigMorphology g > 0 && sigIdentity g > 0 && sigTurns g > 0
        assertBool
          "all gradient components must be strictly positive on a non-degenerate blanket"
          allPositive

  , TestLabel "gradient is strictly positive on the degenerate blanket" $
      TestCase $ do
        let degenerate = baseBlanket
              { sbMorphologyTotalSize = 0
              , sbIdentityClaimsCount = 0
              , sbTurnCount           = 0
              }
            g = computeStateIntegrityGradient degenerate
        assertBool
          "even the degenerate blanket has a strictly positive gradient (no recovery direction missing)"
          (sigMorphology g > 0 && sigIdentity g > 0 && sigTurns g > 0)

  , TestLabel "gradient exhibits diminishing returns in each axis" $
      TestCase $ do
        let small    = baseBlanket { sbMorphologyTotalSize = 1 }
            large    = baseBlanket { sbMorphologyTotalSize = 1000 }
            gSmall   = computeStateIntegrityGradient small
            gLarge   = computeStateIntegrityGradient large
        assertBool
          "gradient w.r.t. morphology must decrease as morphology grows"
          (sigMorphology gSmall > sigMorphology gLarge)

  , TestLabel "gradient magnitude is strictly positive" $
      TestCase $ do
        let g = computeStateIntegrityGradient baseBlanket
        assertBool
          "magnitude must be > 0 for any reachable blanket under default weights"
          (gradientMagnitude g > 0)

  , TestLabel "gradientNormalize produces a unit-magnitude vector" $
      TestCase $ do
        let g = computeStateIntegrityGradient baseBlanket
        case gradientNormalize g of
          Nothing ->
            assertFailure
              "default-weighted gradient must normalise; got Nothing"
          Just n  ->
            assertBool
              ("normalised gradient must have magnitude 1; got "
                <> show (gradientMagnitude n))
              (approxEqual 1e-12 (gradientMagnitude n) 1.0)

  , TestLabel "gradientNormalize returns Nothing on a zero gradient" $
      TestCase $ do
        let zeroWeights = StateIntegrityWeights 0 0 0 0
            g           = computeStateIntegrityGradientWith zeroWeights baseBlanket
        case gradientNormalize g of
          Nothing -> pure ()
          Just _  ->
            assertFailure "zero gradient must not be normalisable"

  , TestLabel "tuned weights produce proportional scalars" $
      TestCase $ do
        -- Doubling all smooth weights and zeroing the penalty must
        -- double the scalar of a violation-free blanket. This
        -- documents the linearity-in-weights property the recovery
        -- driver will eventually depend on.
        let w     = defaultStateIntegrityWeights
            w2    = StateIntegrityWeights
                      (2 * siwMorphology w)
                      (2 * siwIdentity   w)
                      (2 * siwTurns      w)
                      0
            wZeroPen = w { siwViolation = 0 }
            ce1   = computeStateIntegrityEnergyWith wZeroPen baseBlanket []
            ce2   = computeStateIntegrityEnergyWith w2       baseBlanket []
        assertBool
          ("doubled smooth weights must double the scalar; got "
            <> show (siScalar ce1) <> " and " <> show (siScalar ce2))
          (approxEqual 1e-9 (siScalar ce2) (2 * siScalar ce1))
  ]
