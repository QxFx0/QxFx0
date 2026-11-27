{-| State-integrity weights and gates.

Central registry for the component weights consumed by
'QxFx0.Self.StateIntegrity' ('builtinStateIntegrityWeights') and the
low-energy routing gate. Values verbatim: no behavior change,
single address for tuning (calibration-grade changes only).
-}
module QxFx0.Types.Thresholds.StateIntegrity
  ( stateIntegrityWeightMorphology
  , stateIntegrityWeightIdentity
  , stateIntegrityWeightTurns
  , stateIntegrityWeightViolation
  , stateIntegrityLowEnergy
  ) where

-- | Morphology component weight.
stateIntegrityWeightMorphology :: Double
stateIntegrityWeightMorphology = 1.0

-- | Identity component weight.
stateIntegrityWeightIdentity :: Double
stateIntegrityWeightIdentity = 0.5

-- | Turn-count component weight.
stateIntegrityWeightTurns :: Double
stateIntegrityWeightTurns = 0.25

-- | Violation component weight.
stateIntegrityWeightViolation :: Double
stateIntegrityWeightViolation = 10.0

-- | Energy below which routing treats the turn as low-energy (ADR-0045).
stateIntegrityLowEnergy :: Double
stateIntegrityLowEnergy = 3.0
