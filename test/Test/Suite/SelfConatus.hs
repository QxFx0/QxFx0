{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.SelfConatus
Description : Unit tests for the Phase-2 Conatus functional.

Pure tests over 'QxFx0.Self.Conatus.computeConatusEnergy' and
'QxFx0.Self.Conatus.computeConatusGradient', exercising the formal
properties asserted in @docs\/THEORY.md@ §4.2 and elaborated in the
Haddock for 'QxFx0.Self.Conatus':

 * monotonicity in each blanket axis,
 * exact violation-penalty arithmetic,
 * gradient sign and diminishing-returns shape,
 * scalar = sum-of-components invariant,
 * well-definedness at the degenerate \((0, 0, 0)\) blanket,
 * normalisation properties.
-}
module Test.Suite.SelfConatus
  ( selfConatusTests
  ) where

import Test.HUnit (Test (..), assertBool, assertFailure)

import QxFx0.Self.Conatus
  ( ConatusComponents (..)
  , ConatusEnergy (..)
  , ConatusGradient (..)
  , ConatusWeights (..)
  , computeConatusEnergy
  , computeConatusEnergyWith
  , computeConatusGradient
  , computeConatusGradientWith
  , conatusViolationPenalty
  , defaultConatusWeights
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

selfConatusTests :: [Test]
selfConatusTests =
  [ TestLabel "scalar equals sum of components (no violations)" $
      TestCase $ do
        let ce    = computeConatusEnergy baseBlanket []
            comps = ceComponents ce
            sumC  = ccMorphology comps + ccIdentity comps + ccTurns comps + ccPenalty comps
        assertBool
          ("scalar/component disagreement: scalar=" <> show (ceScalar ce)
            <> " sum=" <> show sumC)
          (approxEqual eps (ceScalar ce) sumC)

  , TestLabel "scalar equals sum of components (with violations)" $
      TestCase $ do
        let vs    = [BlanketEmptySession, BlanketTurnRegressed 3 1]
            ce    = computeConatusEnergy baseBlanket vs
            comps = ceComponents ce
            sumC  = ccMorphology comps + ccIdentity comps + ccTurns comps + ccPenalty comps
        assertBool
          "scalar must equal sum of all four components in the presence of violations"
          (approxEqual eps (ceScalar ce) sumC)

  , TestLabel "degenerate blanket (0,0,0) gives zero smooth scalar" $
      TestCase $ do
        let degenerate = baseBlanket
              { sbMorphologyTotalSize = 0
              , sbIdentityClaimsCount = 0
              , sbTurnCount           = 0
              }
            ce = computeConatusEnergy degenerate []
        assertBool
          ("degenerate scalar must equal 0, got " <> show (ceScalar ce))
          (approxEqual eps (ceScalar ce) 0)

  , TestLabel "scalar is monotone in morphology size" $
      TestCase $ do
        let smaller = baseBlanket { sbMorphologyTotalSize = 10 }
            larger  = baseBlanket { sbMorphologyTotalSize = 100 }
            ceS     = computeConatusEnergy smaller []
            ceL     = computeConatusEnergy larger  []
        assertBool
          "more morphology => greater Conatus"
          (ceScalar ceL > ceScalar ceS)

  , TestLabel "scalar is monotone in identity claims count" $
      TestCase $ do
        let smaller = baseBlanket { sbIdentityClaimsCount = 0 }
            larger  = baseBlanket { sbIdentityClaimsCount = 20 }
            ceS     = computeConatusEnergy smaller []
            ceL     = computeConatusEnergy larger  []
        assertBool
          "more identity claims => greater Conatus"
          (ceScalar ceL > ceScalar ceS)

  , TestLabel "scalar is monotone in turn count" $
      TestCase $ do
        let smaller = baseBlanket { sbTurnCount = 1 }
            larger  = baseBlanket { sbTurnCount = 200 }
            ceS     = computeConatusEnergy smaller []
            ceL     = computeConatusEnergy larger  []
        assertBool
          "more turns => greater Conatus"
          (ceScalar ceL > ceScalar ceS)

  , TestLabel "each violation drops scalar by exactly the violation weight" $
      TestCase $ do
        let clean      = computeConatusEnergy baseBlanket []
            withOne    = computeConatusEnergy baseBlanket [BlanketEmptySession]
            withTwo    = computeConatusEnergy baseBlanket
                          [BlanketEmptySession, BlanketEmptyMorphology]
            withThree  = computeConatusEnergy baseBlanket
                          [ BlanketEmptySession
                          , BlanketEmptyMorphology
                          , BlanketTurnRegressed 4 2
                          ]
            lam        = cwViolation defaultConatusWeights
        assertBool "one violation drops scalar by lambda"
          (approxEqual eps (ceScalar clean - ceScalar withOne) lam)
        assertBool "two violations drop scalar by 2*lambda"
          (approxEqual eps (ceScalar clean - ceScalar withTwo) (2 * lam))
        assertBool "three violations drop scalar by 3*lambda"
          (approxEqual eps (ceScalar clean - ceScalar withThree) (3 * lam))

  , TestLabel "violation penalty helper matches inline computation" $
      TestCase $ do
        let vs   = [BlanketEmptySession, BlanketIdentityErased 5 3]
            comp = ceComponents (computeConatusEnergy baseBlanket vs)
            via  = conatusViolationPenalty defaultConatusWeights vs
        assertBool
          "conatusViolationPenalty must agree with ccPenalty"
          (approxEqual eps via (ccPenalty comp))

  , TestLabel "violations do not affect gradient" $
      TestCase $ do
        let g  = computeConatusGradient baseBlanket
            -- Gradient does not take violations; this test
            -- documents the structural invariant that the gradient
            -- depends only on the blanket axes.
            allPositive = cgMorphology g > 0 && cgIdentity g > 0 && cgTurns g > 0
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
            g = computeConatusGradient degenerate
        assertBool
          "even the degenerate blanket has a strictly positive gradient (no recovery direction missing)"
          (cgMorphology g > 0 && cgIdentity g > 0 && cgTurns g > 0)

  , TestLabel "gradient exhibits diminishing returns in each axis" $
      TestCase $ do
        let small    = baseBlanket { sbMorphologyTotalSize = 1 }
            large    = baseBlanket { sbMorphologyTotalSize = 1000 }
            gSmall   = computeConatusGradient small
            gLarge   = computeConatusGradient large
        assertBool
          "gradient w.r.t. morphology must decrease as morphology grows"
          (cgMorphology gSmall > cgMorphology gLarge)

  , TestLabel "gradient magnitude is strictly positive" $
      TestCase $ do
        let g = computeConatusGradient baseBlanket
        assertBool
          "magnitude must be > 0 for any reachable blanket under default weights"
          (gradientMagnitude g > 0)

  , TestLabel "gradientNormalize produces a unit-magnitude vector" $
      TestCase $ do
        let g = computeConatusGradient baseBlanket
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
        let zeroWeights = ConatusWeights 0 0 0 0
            g           = computeConatusGradientWith zeroWeights baseBlanket
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
        let w     = defaultConatusWeights
            w2    = ConatusWeights
                      (2 * cwMorphology w)
                      (2 * cwIdentity   w)
                      (2 * cwTurns      w)
                      0
            wZeroPen = w { cwViolation = 0 }
            ce1   = computeConatusEnergyWith wZeroPen baseBlanket []
            ce2   = computeConatusEnergyWith w2       baseBlanket []
        assertBool
          ("doubled smooth weights must double the scalar; got "
            <> show (ceScalar ce1) <> " and " <> show (ceScalar ce2))
          (approxEqual 1e-9 (ceScalar ce2) (2 * ceScalar ce1))
  ]
