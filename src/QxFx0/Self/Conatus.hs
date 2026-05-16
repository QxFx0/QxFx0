{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Self.Conatus
Description : Phase-2 Conatus functional over the SelfBlanket.

A typed, pure realisation of the scalar functional named in
@docs\/THEORY.md@ §4.2 and elaborated in @docs\/adr\/0007-dual-mode-conatus.md@.

== Theoretical Sketch

Following the Spinozan reading committed in @docs\/THEORY.md@, every
finite mode persists by an inner endeavour — a /conatus/. We do not
claim the present implementation possesses anything like the conatus
of a living substance; we claim only that the system's structural
self-identity can be summarised by a scalar functional whose
behaviour mirrors the formal /shape/ of conatus:

* It is positive when the system is intact as /this system/.
* It decreases — strictly, by a fixed step — for each
  structural invariant the system has violated.
* It admits a gradient pointing in the direction of fastest increase,
  which serves as a /direction of recovery/ in Phase 2.5.

Concretely, we project a 'QxFx0.Self.Types.SelfBlanket' \(b = (m, c, t)\)
together with a list of 'QxFx0.Self.Types.BlanketViolation's \(v\) to:

\[
C(b, v) = w_m \cdot \log(1 + m) + w_c \cdot \log(1 + c) + w_t \cdot \log(1 + t) - \lambda \cdot |v|
\]

where \(m, c, t\) are the morphology size, identity-claim count, and
turn count from the blanket, and \(w_m, w_c, w_t, \lambda\) are
tunable coefficients ('ConatusWeights'). The logarithmic shape
captures /diminishing returns/: a system gains a great deal of
identity by acquiring its first hundred morphological entries and
proportionally less by acquiring its next hundred. The penalty term
is discrete; violations contribute only to the scalar, not to the
gradient.

The gradient

\[
\nabla C(b) = \left( \frac{w_m}{1 + m}, \frac{w_c}{1 + c}, \frac{w_t}{1 + t} \right)
\]

is computed analytically (no automatic-differentiation dependency).
Each component is strictly positive on non-degenerate blankets and
/decreases/ as its axis grows — operationally: when several axes
have degraded, recovery should preferentially restore the one whose
current value is smallest, because the marginal gain in Conatus is
largest there.

== Scope and Honesty

This module is /not/ a model of subjective drive, motivation, or
phenomenal striving. It is a structural functional over a tiny
finite-dimensional summary of the system state, designed so that
later phases (recovery, salience control, dual-mode arbitration)
have a single principled scalar/gradient to consult instead of
hand-coded heuristics. See @docs\/THEORY.md@ §5 for the explicit
list of what we do /not/ claim.
-}
module QxFx0.Self.Conatus
  ( -- * Weights
    ConatusWeights (..)
  , defaultConatusWeights
    -- * Scalar energy
  , ConatusComponents (..)
  , ConatusEnergy (..)
  , computeConatusEnergy
  , computeConatusEnergyWith
    -- * Gradient
  , ConatusGradient (..)
  , computeConatusGradient
  , computeConatusGradientWith
    -- * Derived quantities
  , gradientMagnitude
  , gradientNormalize
  , conatusViolationPenalty
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import GHC.Generics (Generic)

import QxFx0.Self.Types (BlanketViolation, SelfBlanket (..))

-- | Tunable coefficients of the Conatus functional. The defaults
-- in 'defaultConatusWeights' encode the editorial judgement that
-- morphological substance is the primary carrier of identity
-- (largest weight), accumulated identity claims are secondary, and
-- raw turn count is a weaker indicator (a long-running session of
-- empty turns says less than a short session with rich growth).
-- The violation penalty is intentionally large relative to any
-- single-axis logarithmic contribution: a structural rupture must
-- not be wallpapered over by mere accumulation.
data ConatusWeights = ConatusWeights
  { cwMorphology :: !Double
    -- ^ Weight on \(\log(1 + m)\). Default: @1.0@.
  , cwIdentity   :: !Double
    -- ^ Weight on \(\log(1 + c)\). Default: @0.5@.
  , cwTurns      :: !Double
    -- ^ Weight on \(\log(1 + t)\). Default: @0.25@.
  , cwViolation  :: !Double
    -- ^ Penalty per 'BlanketViolation' (subtracted). Default: @10.0@.
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

-- | The reference weights used throughout the system unless an
-- experiment overrides them via 'computeConatusEnergyWith' or
-- 'computeConatusGradientWith'.
defaultConatusWeights :: ConatusWeights
defaultConatusWeights = ConatusWeights
  { cwMorphology = 1.0
  , cwIdentity   = 0.5
  , cwTurns      = 0.25
  , cwViolation  = 10.0
  }

-- | The decomposed scalar contribution of each axis. Kept separate
-- from 'ConatusEnergy' so that diagnostics and observability can
-- show which axis is carrying (or failing) the system, not only the
-- aggregate.
data ConatusComponents = ConatusComponents
  { ccMorphology :: !Double
    -- ^ \(w_m \cdot \log(1 + m)\).
  , ccIdentity   :: !Double
    -- ^ \(w_c \cdot \log(1 + c)\).
  , ccTurns      :: !Double
    -- ^ \(w_t \cdot \log(1 + t)\).
  , ccPenalty    :: !Double
    -- ^ \(-\lambda \cdot |v|\). Always @<= 0@.
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

-- | The scalar value of the Conatus functional together with its
-- per-axis decomposition. Invariant: @ceScalar == sum of all four
-- 'ConatusComponents' fields@.
data ConatusEnergy = ConatusEnergy
  { ceScalar     :: !Double
    -- ^ \(C(b, v)\), the aggregate.
  , ceComponents :: !ConatusComponents
    -- ^ The per-axis breakdown.
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

-- | The gradient of the smooth part of \(C\) at a blanket. Each
-- component is the partial derivative of \(C\) with respect to that
-- blanket axis, treating the blanket fields as real-valued for the
-- duration of the derivative. The violation penalty contributes
-- nothing because it is a step function in \(|v|\), not a smooth
-- function of \((m, c, t)\).
--
-- All components are strictly positive on any blanket whose
-- integer fields are non-negative (which is the universe of all
-- legitimately-constructed 'SelfBlanket' values), so the gradient
-- always points into the strictly-growing orthant.
data ConatusGradient = ConatusGradient
  { cgMorphology :: !Double
    -- ^ \(w_m / (1 + m)\).
  , cgIdentity   :: !Double
    -- ^ \(w_c / (1 + c)\).
  , cgTurns      :: !Double
    -- ^ \(w_t / (1 + t)\).
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

-- | Compute the Conatus energy of a blanket under the supplied
-- violation list, using 'defaultConatusWeights'. Pure, total, and
-- well-defined on every legitimately constructed blanket including
-- the degenerate \((0, 0, 0)\) case.
computeConatusEnergy :: SelfBlanket -> [BlanketViolation] -> ConatusEnergy
computeConatusEnergy = computeConatusEnergyWith defaultConatusWeights

-- | Compute the Conatus energy under explicit weights. Used by
-- tests and experiments that perturb the coefficients; production
-- code should call 'computeConatusEnergy'.
computeConatusEnergyWith :: ConatusWeights -> SelfBlanket -> [BlanketViolation] -> ConatusEnergy
computeConatusEnergyWith w b violations =
  let m         = fromIntegral (sbMorphologyTotalSize b) :: Double
      c         = fromIntegral (sbIdentityClaimsCount b) :: Double
      t         = fromIntegral (sbTurnCount           b) :: Double
      mComp     = cwMorphology w * log1p m
      cComp     = cwIdentity   w * log1p c
      tComp     = cwTurns      w * log1p t
      penalty   = negate (cwViolation w * fromIntegral (length violations))
      comps     = ConatusComponents
        { ccMorphology = mComp
        , ccIdentity   = cComp
        , ccTurns      = tComp
        , ccPenalty    = penalty
        }
   in ConatusEnergy
        { ceScalar     = mComp + cComp + tComp + penalty
        , ceComponents = comps
        }

-- | Compute the gradient of the smooth part of Conatus at a blanket,
-- using 'defaultConatusWeights'. Independent of the violation set.
computeConatusGradient :: SelfBlanket -> ConatusGradient
computeConatusGradient = computeConatusGradientWith defaultConatusWeights

-- | Compute the gradient under explicit weights.
computeConatusGradientWith :: ConatusWeights -> SelfBlanket -> ConatusGradient
computeConatusGradientWith w b =
  let m = fromIntegral (sbMorphologyTotalSize b) :: Double
      c = fromIntegral (sbIdentityClaimsCount b) :: Double
      t = fromIntegral (sbTurnCount           b) :: Double
   in ConatusGradient
        { cgMorphology = cwMorphology w / (1 + m)
        , cgIdentity   = cwIdentity   w / (1 + c)
        , cgTurns      = cwTurns      w / (1 + t)
        }

-- | Euclidean magnitude of a Conatus gradient. Useful as an
-- /urgency/ scalar: a recovery system can compare magnitudes to
-- decide whether the current state warrants intervention at all.
gradientMagnitude :: ConatusGradient -> Double
gradientMagnitude g =
  sqrt (cgMorphology g ^ (2 :: Int) + cgIdentity g ^ (2 :: Int) + cgTurns g ^ (2 :: Int))

-- | Normalise a gradient to unit Euclidean magnitude. Returns
-- @Nothing@ when the gradient is the zero vector (which can only
-- happen if all weights are zero, since blanket fields contribute
-- @1 / (1 + x) > 0@ for any finite \(x \geq 0\)).
gradientNormalize :: ConatusGradient -> Maybe ConatusGradient
gradientNormalize g =
  let mag = gradientMagnitude g
   in if mag == 0
        then Nothing
        else Just ConatusGradient
          { cgMorphology = cgMorphology g / mag
          , cgIdentity   = cgIdentity   g / mag
          , cgTurns      = cgTurns      g / mag
          }

-- | The signed scalar drop in Conatus attributable to a list of
-- violations under given weights. Exposed for diagnostics; the same
-- value already appears as 'ccPenalty' in any 'ConatusEnergy'
-- record computed under matching weights.
conatusViolationPenalty :: ConatusWeights -> [BlanketViolation] -> Double
conatusViolationPenalty w vs = negate (cwViolation w * fromIntegral (length vs))

-- | Numerically robust \(\log(1 + x)\) for \(x \geq 0\). Avoids
-- catastrophic cancellation for small \(x\), and is well-defined
-- and equal to @0@ at \(x = 0\). The standard Haskell 'log'
-- composed with @(+ 1)@ would also give the correct value on
-- the inputs we feed it (non-negative integers cast to 'Double'),
-- but expressing the operation explicitly documents the intent.
log1p :: Double -> Double
log1p x = log (1 + x)
