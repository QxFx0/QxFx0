module QxFx0.Types.Thresholds.Intuition
  ( intuitionFlashThreshold
  , intuitionHighResonanceThreshold
  , intuitionElevatedResonanceThreshold
  , intuitionDeepResonanceThreshold
  , intuitionHighTensionThreshold
  , intuitionElevatedTensionThreshold
  , intuitionCrisisTensionThreshold
  , intuitionNoFlashBaselineLikelihood
  , intuitionBasePriorDefault
  , intuitionEffectivePosteriorShortWeight
  , intuitionEffectivePosteriorLongWeight
  , intuitionFlashLikelihoodConvergent
  , intuitionFlashLikelihoodElevated
  , intuitionFlashLikelihoodDeep
  , intuitionFlashLikelihoodBaseline
  , intuitionNoFlashLikelihoodConvergent
  , intuitionNoFlashLikelihoodElevated
  , intuitionNoFlashLikelihoodDeep
  , intuitionPosteriorAfterFlashDecayFactor
  , intuitionLongPosteriorAfterFlashDecayFactor
  , intuitionLongPosteriorPriorWeight
  , intuitionLongPosteriorCurrentWeight
  , intuitionFlashOverrideStrengthThreshold
  , intuitionCoreVecPresence
  , intuitionCoreVecDepth
  , intuitionCoreVecAutonomy
  , intuitionCoreVecDirectiveness
  , intuitionCoreVecSteadiness
  , intuitionSteadinessBaseline
  , intuitionSignalSteadyBonusScale
  ) where

intuitionFlashThreshold :: Double
intuitionFlashThreshold = 0.65

intuitionHighResonanceThreshold :: Double
intuitionHighResonanceThreshold = 0.80

intuitionElevatedResonanceThreshold :: Double
intuitionElevatedResonanceThreshold = 0.70

intuitionDeepResonanceThreshold :: Double
intuitionDeepResonanceThreshold = 0.55

intuitionHighTensionThreshold :: Double
intuitionHighTensionThreshold = 0.60

intuitionElevatedTensionThreshold :: Double
intuitionElevatedTensionThreshold = 0.65

intuitionCrisisTensionThreshold :: Double
intuitionCrisisTensionThreshold = 0.75

intuitionNoFlashBaselineLikelihood :: Double
intuitionNoFlashBaselineLikelihood = 0.72

intuitionBasePriorDefault :: Double
intuitionBasePriorDefault = 0.06

intuitionEffectivePosteriorShortWeight :: Double
intuitionEffectivePosteriorShortWeight = 0.35

intuitionEffectivePosteriorLongWeight :: Double
intuitionEffectivePosteriorLongWeight = 0.65

intuitionFlashLikelihoodConvergent :: Double
intuitionFlashLikelihoodConvergent = 0.82

intuitionFlashLikelihoodElevated :: Double
intuitionFlashLikelihoodElevated = 0.65

intuitionFlashLikelihoodDeep :: Double
intuitionFlashLikelihoodDeep = 0.45

intuitionFlashLikelihoodBaseline :: Double
intuitionFlashLikelihoodBaseline = 0.18

intuitionNoFlashLikelihoodConvergent :: Double
intuitionNoFlashLikelihoodConvergent = 0.25

intuitionNoFlashLikelihoodElevated :: Double
intuitionNoFlashLikelihoodElevated = 0.38

intuitionNoFlashLikelihoodDeep :: Double
intuitionNoFlashLikelihoodDeep = 0.48

intuitionPosteriorAfterFlashDecayFactor :: Double
intuitionPosteriorAfterFlashDecayFactor = 0.55

intuitionLongPosteriorAfterFlashDecayFactor :: Double
intuitionLongPosteriorAfterFlashDecayFactor = 0.92

intuitionLongPosteriorPriorWeight :: Double
intuitionLongPosteriorPriorWeight = 0.85

intuitionLongPosteriorCurrentWeight :: Double
intuitionLongPosteriorCurrentWeight = 0.15

intuitionFlashOverrideStrengthThreshold :: Double
intuitionFlashOverrideStrengthThreshold = 0.55

intuitionCoreVecPresence :: Double
intuitionCoreVecPresence = 0.85

intuitionCoreVecDepth :: Double
intuitionCoreVecDepth = 0.10

intuitionCoreVecAutonomy :: Double
intuitionCoreVecAutonomy = 0.75

intuitionCoreVecDirectiveness :: Double
intuitionCoreVecDirectiveness = 0.70

intuitionCoreVecSteadiness :: Double
intuitionCoreVecSteadiness = 0.80

intuitionSteadinessBaseline :: Double
intuitionSteadinessBaseline = 0.50

intuitionSignalSteadyBonusScale :: Double
intuitionSignalSteadyBonusScale = 0.20
