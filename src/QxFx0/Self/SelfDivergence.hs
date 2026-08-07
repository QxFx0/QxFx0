{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE OverloadedStrings #-}

{-|
Description : canonical - deterministic self-divergence contour (A-slice).

Implements the A0 concept: "awareness, in the deterministic sense, is
the ability to predict one's own next state and notice the mismatch."

    predict -> witness -> diff -> allergen -> Conatus

One turn, one measurement 'SelfDivergenceE'.  All morphisms are pure,
total, and deterministic; identical inputs yield identical outputs
(the A4 anti-rot suite pins this).

The prediction is anchored on the /previous/ observed 'Field' plus the
modulation band prices: the system expects itself to remain inside
its calibrated envelope, with a mean-reverting pull toward the band
center driven by the angst decay rate.  Divergence is the excess
distance beyond the envelope, not the raw delta:

* deviations inside the envelope contribute zero per axis;
* only out-of-envelope excess counts (max 0 (|delta| - envelope));
* axes are combined with an L2 norm clamped to [0,1].

The optional Conatus penalty applies only when the total divergence
exceeds 'sdtThreshold' and is a /fraction/ of the current energy
(energy-scale aware, avoiding the WP-F absolute-value unit mismatch).
-}
module QxFx0.Self.SelfDivergence
  ( predictSelf
  , measureDivergence
  , selfConsistencyPenalty
  , windowMeanDivergence
  , sustainedDivergenceExceeds
  , clampUnit
  ) where

import QxFx0.Types.Self.Conatus (ConatusComponents(..), ConatusEnergy(..))
import QxFx0.Types.Self.Essence (EssenceModulation(..))
import QxFx0.Types.Self.Field
  ( Atmosphere(..)
  , Counterfactual(..)
  , Field(..)
  , FieldConfidence(..)
  , Resonance(..)
  , Consolidation(..)
  )
import QxFx0.Types.Self.SelfDivergence
  ( SelfDivergenceE(..)
  , SelfDivergenceTuning(..)
  , SelfPrediction(..)
  )

-- | Clamp a real number into [0, 1].
clampUnit :: Double -> Double
clampUnit = max 0.0 . min 1.0

-- | Half-width of the unit-domain envelope from the modulation band
-- prices.  Non-negative by construction.
envelopeHalfWidth :: EssenceModulation -> Double
envelopeHalfWidth em =
  max 0.0 ((emBandHighEdge em - emBandLowEdge em) / 2.0)

-- | Continuous center of a band from the modulation edges.
bandCenter :: EssenceModulation -> Double
bandCenter em = (emBandLowEdge em + emBandHighEdge em) / 2.0

-- | The valence envelope is centered at 0 (signed domain [-1, 1]);
-- its half-width is derived from the valence edges.
valenceEnvelopeHalfWidth :: EssenceModulation -> Double
valenceEnvelopeHalfWidth em =
  max 0.0 ((emValenceHighEdge em - emValenceLowEdge em) / 2.0)

-- | Expected next angst under pure deterministic decay (no accrual).
--  The system expects itself to relax toward zero angst at the
--  configured decay rate.
predictAngst :: EssenceModulation -> Double -> Double
predictAngst em angst = max 0.0 (angst - emAngstDecayRate em)

-- | Mean-reverting prediction of a single unit-domain axis:
-- the system expects to drift back toward its calibrated band center
-- at the angst-decay rate.  This keeps the prediction continuous and
-- deterministic while making steady-state Fields predictable with
-- zero divergence.
predictAxis
  :: EssenceModulation -> Double -> Double -> Double
predictAxis em center observed =
  center + (observed - center) * (1.0 - emAngstDecayRate em)

-- | Build the deterministic prediction for the next turn from the
-- previous observed 'Field' and the current angst level.
--
-- Total and deterministic: same (em, field, angst) triple always
-- produces the same 'SelfPrediction'.
predictSelf :: EssenceModulation -> Field -> Double -> SelfPrediction
predictSelf em f angst =
  let cRes  = bandCenter em
      cVal  = 0.0
      cAro  = bandCenter em
      cCon  = bandCenter em
      cCons = bandCenter em
      cCf   = bandCenter em
  in SelfPrediction
       { spResonance      = predictAxis em cRes  (unResonance (fieldResonance f))
       , spValence        = predictAxis em cVal  (atmosphereValence (fieldAtmosphere f))
       , spArousal        = predictAxis em cAro  (atmosphereArousal (fieldAtmosphere f))
       , spConfidence     = predictAxis em cCon  (unFieldConfidence (fieldConfidence f))
       , spConsolidation  = predictAxis em cCons (unConsolidation (fieldConsolidation f))
       , spCounterfactual = predictAxis em cCf   (unCounterfactual (fieldCounterfactual f))
       , spAngst          = predictAngst em angst
       , spEnvelope       = envelopeHalfWidth em
       }

-- | Excess distance beyond an envelope: @max 0 (|actual - predicted| - env)@.
excess :: Double -> Double -> Double -> Double
excess predicted envelope actual =
  max 0.0 (abs (actual - predicted) - envelope)

-- | Measure the divergence of the observed 'Field' against the
-- prediction.  Per-axis deltas are the out-of-envelope excess; the
-- total is the L2 norm of the axis deltas clamped to [0, 1].
--
-- 'sdeAtmosphereDelta' combines valence and arousal via L2; the
-- valence axis uses the valence envelope, arousal the unit envelope.
measureDivergence :: SelfPrediction -> Field -> Double -> SelfDivergenceE
measureDivergence sp f actualAngst =
  let valEnv = spEnvelope sp
      valDelta = clampUnit (excess (spValence sp) valEnv (atmosphereValence (fieldAtmosphere f)))
      aroDelta = clampUnit (excess (spArousal sp) (spEnvelope sp) (atmosphereArousal (fieldAtmosphere f)))
      atmDelta = clampUnit (l2 [valDelta, aroDelta])
      resDelta = clampUnit (excess (spResonance sp) (spEnvelope sp) (unResonance (fieldResonance f)))
      conDelta = clampUnit (excess (spConfidence sp) (spEnvelope sp) (unFieldConfidence (fieldConfidence f)))
      consDelta = clampUnit (excess (spConsolidation sp) (spEnvelope sp) (unConsolidation (fieldConsolidation f)))
      cfDelta = clampUnit (excess (spCounterfactual sp) (spEnvelope sp) (unCounterfactual (fieldCounterfactual f)))
      angDelta = clampUnit (max 0.0 (abs (actualAngst - spAngst sp)))
      total = clampUnit (l2 [resDelta, atmDelta, conDelta, consDelta, cfDelta, angDelta])
  in SelfDivergenceE
       { sdeResonanceDelta     = resDelta
       , sdeAtmosphereDelta    = atmDelta
       , sdeConfidenceDelta    = conDelta
       , sdeConsolidationDelta = consDelta
       , sdeCounterfactualDelta = cfDelta
       , sdeAngstDelta         = angDelta
       , sdeTotalDivergence    = total
       }

-- | L2 norm of a list of non-negative axis deltas.
l2 :: [Double] -> Double
l2 xs = sqrt (sum (map (\x -> x * x) xs))

-- | Apply the self-consistency penalty to a 'ConatusEnergy':
-- only when the total divergence exceeds 'sdtThreshold', and as a
-- /fraction/ of the current scalar (energy-scale aware).  The pure
-- penalty share (negative) is returned alongside for trace/observer
-- alignment; the caller decides how to surface it (A2 wires it into
-- the 'ConatusComponents' divergence channel).
--
-- The penalty lands in the @ccSelfDivergence@ component and the
-- scalar is kept equal to the component sum (invariant: @ceScalar ==
-- sum of all five components@).
--
-- Deterministic: same inputs, same penalty.
selfConsistencyPenalty
  :: SelfDivergenceTuning
  -> SelfDivergenceE
  -> ConatusEnergy
  -> (ConatusEnergy, Double)
selfConsistencyPenalty tuning divE ce
  | sdeTotalDivergence divE <= sdtThreshold tuning = (ce, 0.0)
  | otherwise =
      let share = sdtScaling tuning * sdeTotalDivergence divE
          baseScalar = ceScalar ce
          penalty = negate (share * baseScalar)
          comps' = (ceComponents ce)
            { ccSelfDivergence = penalty }
          adjusted = ce
            { ceScalar = baseScalar + penalty
            , ceComponents = comps'
            }
      in (adjusted, penalty)

-- | Sliding-window mean of divergence samples.  Pure; the caller
-- maintains the bounded window.  Empty windows yield 0.0.
windowMeanDivergence :: [Double] -> Double
windowMeanDivergence [] = 0.0
windowMeanDivergence xs =
  sum xs / fromIntegral (length xs)

-- | C-slice (CD): the recovery trigger for 'RecoverySelfDivergence'.
-- True exactly when a /non-empty/ bounded window of recent total
-- divergence samples has a mean strictly above 'sdtThreshold' — i.e.
-- the system has been out of its predicted envelope on average, not
-- just on one noisy turn.  Empty windows (no self-history yet) are
-- never sustained-diverged.
--
-- Deterministic and total: same tuning and window always yield the
-- same verdict.
sustainedDivergenceExceeds :: SelfDivergenceTuning -> [Double] -> Bool
sustainedDivergenceExceeds tuning window =
  not (null window) && windowMeanDivergence window > sdtThreshold tuning