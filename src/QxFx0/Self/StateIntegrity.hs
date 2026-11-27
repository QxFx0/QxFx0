{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Self.StateIntegrity
Description : canonical — structural integrity functional over the SelfBlanket.

A typed, pure scalar functional over the structural self-identity
snapshot.  The historical name "Conatus" was retired from this module on
2026-11-23 (P4): the functional does not measure a drive, an endeavour
or a vitality.  It measures the structural integrity of the blanket —
how much morphology, identity and history the system currently carries,
minus a discrete penalty for each violated invariant.  The name
"Conatus" now belongs only to 'QxFx0.Self.ConatusContour', a typed
record of four self-maintenance facts that is measured, not claimed.
See @docs\/closure\/P4_STATE_INTEGRITY_PREREG_2026-11-23.md@.

== Definition

We project a 'QxFx0.Self.Types.SelfBlanket' \(b = (m, c, t)\)
together with a list of 'QxFx0.Self.Types.BlanketViolation's \(v\) to:

\[
C(b, v) = w_m \cdot \log(1 + m) + w_c \cdot \log(1 + c) + w_t \cdot \log(1 + t) - \lambda \cdot |v|
\]

where \(m, c, t\) are the morphology size, identity-claim count, and
turn count from the blanket, and \(w_m, w_c, w_t, \lambda\) are
tunable coefficients ('StateIntegrityWeights'). The logarithmic shape
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
current value is smallest, because the marginal gain in integrity is
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
module QxFx0.Self.StateIntegrity
  ( -- * Weights
    StateIntegrityWeights (..)
  , defaultStateIntegrityWeights
    -- * Scalar energy
  , StateIntegrityComponents (..)
  , StateIntegrity (..)
  , computeStateIntegrityEnergy
  , computeStateIntegrityEnergyWith
    -- * Gradient
  , StateIntegrityGradient (..)
  , computeStateIntegrityGradient
  , computeStateIntegrityGradientWith
    -- * Derived quantities
  , gradientMagnitude
  , gradientNormalize
  , stateIntegrityViolationPenalty
    -- * Thresholds
  , lowEnergyThreshold
  ) where

import QxFx0.Self.Types (BlanketViolation, SelfBlanket (..))
import QxFx0.Types.Self.StateIntegrity
import QxFx0.Types.Thresholds.StateIntegrity

-- | The reference builtin weights used throughout the system unless an
-- experiment overrides them via 'computeStateIntegrityEnergyWith' or
-- 'computeStateIntegrityGradientWith'. The defaults in 'defaultStateIntegrityWeights'
-- encode the editorial judgement that morphological substance is the
-- primary carrier of identity (largest weight), accumulated identity
-- claims are secondary, and raw turn count is a weaker indicator (a
-- long-running session of empty turns says less than a short session
-- with rich growth). The violation penalty is intentionally large
-- relative to any single-axis logarithmic contribution: a structural
-- rupture must not be wallpapered over by mere accumulation.
builtinStateIntegrityWeights :: StateIntegrityWeights
builtinStateIntegrityWeights = StateIntegrityWeights
  { siwMorphology = stateIntegrityWeightMorphology
  , siwIdentity   = stateIntegrityWeightIdentity
  , siwTurns      = stateIntegrityWeightTurns
  , siwViolation  = stateIntegrityWeightViolation
  }

-- | Pure reference weights. Runtime configuration is loaded explicitly by
-- session bootstrap and injected into 'SelfState'.
defaultStateIntegrityWeights :: StateIntegrityWeights
defaultStateIntegrityWeights = builtinStateIntegrityWeights

-- | Compute the state-integrity scalar of a blanket under the supplied
-- violation list, using 'defaultStateIntegrityWeights'. Pure, total, and
-- well-defined on every legitimately constructed blanket including
-- the degenerate \((0, 0, 0)\) case.
computeStateIntegrityEnergy :: SelfBlanket -> [BlanketViolation] -> StateIntegrity
computeStateIntegrityEnergy = computeStateIntegrityEnergyWith defaultStateIntegrityWeights

-- | Compute the state-integrity scalar under explicit weights. Used by
-- tests and experiments that perturb the coefficients; production
-- code should call 'computeStateIntegrityEnergy'.
computeStateIntegrityEnergyWith :: StateIntegrityWeights -> SelfBlanket -> [BlanketViolation] -> StateIntegrity
computeStateIntegrityEnergyWith w b violations =
  let m         = fromIntegral (sbMorphologyTotalSize b) :: Double
      c         = fromIntegral (sbIdentityClaimsCount b) :: Double
      t         = fromIntegral (sbTurnCount           b) :: Double
      mComp     = siwMorphology w * log1p m
      cComp     = siwIdentity   w * log1p c
      tComp     = siwTurns      w * log1p t
      penalty   = negate (siwViolation w * fromIntegral (length violations))
      comps     = StateIntegrityComponents
        { sicMorphology     = mComp
        , sicIdentity       = cComp
        , sicTurns          = tComp
        , sicPenalty        = penalty
        , sicSelfDivergence = 0.0
        }
   in StateIntegrity
        { siScalar     = mComp + cComp + tComp + penalty
        , siComponents = comps
        }

-- | Compute the gradient of the smooth part of state integrity at a blanket,
-- using 'defaultStateIntegrityWeights'. Independent of the violation set.
computeStateIntegrityGradient :: SelfBlanket -> StateIntegrityGradient
computeStateIntegrityGradient = computeStateIntegrityGradientWith defaultStateIntegrityWeights

-- | Compute the gradient under explicit weights.
computeStateIntegrityGradientWith :: StateIntegrityWeights -> SelfBlanket -> StateIntegrityGradient
computeStateIntegrityGradientWith w b =
  let m = fromIntegral (sbMorphologyTotalSize b) :: Double
      c = fromIntegral (sbIdentityClaimsCount b) :: Double
      t = fromIntegral (sbTurnCount           b) :: Double
   in StateIntegrityGradient
        { sigMorphology = siwMorphology w / (1 + m)
        , sigIdentity   = siwIdentity   w / (1 + c)
        , sigTurns      = siwTurns      w / (1 + t)
        }

-- | Euclidean magnitude of a state-integrity gradient. Useful as an
-- /urgency/ scalar: a recovery system can compare magnitudes to
-- decide whether the current state warrants intervention at all.
gradientMagnitude :: StateIntegrityGradient -> Double
gradientMagnitude g =
  sqrt (sigMorphology g ^ (2 :: Int) + sigIdentity g ^ (2 :: Int) + sigTurns g ^ (2 :: Int))

-- | Normalise a gradient to unit Euclidean magnitude. Returns
-- @Nothing@ when the gradient is the zero vector (which can only
-- happen if all weights are zero, since blanket fields contribute
-- @1 / (1 + x) > 0@ for any finite \(x \geq 0\)).
gradientNormalize :: StateIntegrityGradient -> Maybe StateIntegrityGradient
gradientNormalize g =
  let mag = gradientMagnitude g
   in if mag == 0
        then Nothing
        else Just StateIntegrityGradient
          { sigMorphology = sigMorphology g / mag
          , sigIdentity   = sigIdentity   g / mag
          , sigTurns      = sigTurns      g / mag
          }

-- | The signed scalar drop in state integrity attributable to a list of
-- violations under given weights. Exposed for diagnostics; the same
-- value already appears as 'sicPenalty' in any 'StateIntegrity'
-- record computed under matching weights.
stateIntegrityViolationPenalty :: StateIntegrityWeights -> [BlanketViolation] -> Double
stateIntegrityViolationPenalty w vs = negate (siwViolation w * fromIntegral (length vs))

-- | Threshold below which the state-integrity scalar is considered "low" and
-- triggers self-preservation routing restrictions. When
-- @siScalar < lowEnergyThreshold@, the system prohibits high-risk
-- families (CMConfront, CMHypothesis, CMDistinguish) and allows
-- only restorative families (CMContact, CMAnchor, CMRepair).
--
-- The default value of @3.0@ is calibrated against the log-scale
-- codomain of 'siScalar': a healthy blanket with moderate
-- morphology (e.g., 20 entries), some identity claims (e.g., 5),
-- and a few turns (e.g., 10) yields:
--
-- @
-- C = 1.0 * log(21) + 0.5 * log(6) + 0.25 * log(11) ≈ 3.0 + 0.9 + 0.6 = 4.5
-- @
--
-- A blanket below this threshold has either suffered violations
-- (penalty term) or has minimal structural substance, warranting
-- conservative routing.
--
-- See ADR-0045 for the integration rationale.
lowEnergyThreshold :: Double
lowEnergyThreshold = stateIntegrityLowEnergy

-- | Numerically robust \(\log(1 + x)\) for \(x \geq 0\). Avoids
-- catastrophic cancellation for small \(x\), and is well-defined
-- and equal to @0@ at \(x = 0\). The standard Haskell 'log'
-- composed with @(+ 1)@ would also give the correct value on
-- the inputs we feed it (non-negative integers cast to 'Double'),
-- but expressing the operation explicitly documents the intent.
log1p :: Double -> Double
log1p x = log (1 + x)
