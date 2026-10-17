{-| Conatus energy weights and gates.

Central registry for the component weights consumed by
'QxFx0.Self.Conatus' ('builtinConatusWeights') and the
low-energy routing gate. Values verbatim: no behavior change,
single address for tuning (calibration-grade changes only).
-}
module QxFx0.Types.Thresholds.Conatus
  ( conatusWeightMorphology
  , conatusWeightIdentity
  , conatusWeightTurns
  , conatusWeightViolation
  , conatusLowEnergy
  ) where

-- | Morphology component weight.
conatusWeightMorphology :: Double
conatusWeightMorphology = 1.0

-- | Identity component weight.
conatusWeightIdentity :: Double
conatusWeightIdentity = 0.5

-- | Turn-count component weight.
conatusWeightTurns :: Double
conatusWeightTurns = 0.25

-- | Violation component weight.
conatusWeightViolation :: Double
conatusWeightViolation = 10.0

-- | Energy below which routing treats the turn as low-energy (ADR-0045).
conatusLowEnergy :: Double
conatusLowEnergy = 3.0
