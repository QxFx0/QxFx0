module QxFx0.Types.Thresholds.Consciousness
  ( backgroundSurfacingThreshold
  , backgroundConflictStrongThreshold
  , backgroundConflictMediumThreshold
  , backgroundPressureDecayFactor
  , backgroundDesireConflictDelta
  , backgroundProductModeResistanceDelta
  , backgroundExplicitConflictDelta
  , consciousnessSilenceOntologyBonus
  , consciousnessListenOntologyBonus
  , consciousnessNameOntologyBonus
  , consciousnessSilenceContextBonus
  , consciousnessListenContextBonus
  , consciousnessResistContextBonus
  , consciousnessDeepSearchThreshold
  , consciousnessShallowSearchThreshold
  , consciousnessAbstractionEpsilon
  , consciousnessDesirePresenceThreshold
  , consciousnessDesirePreserveThreshold
  , consciousnessFragmentLengthThreshold
  , consciousnessLowResonanceThreshold
  , consciousnessHighResonanceReturnThreshold
  , consciousnessLowResonanceReturnThreshold
  , consciousnessTrajectoryLimit
  , consciousnessSkillAffinityPatternThreshold
  , consciousnessDefaultSkillAffinity
  , consciousnessInitialSearchDepth
  , consciousnessInitialPatternWeight
  , consciousnessInitialTemporalBias
  , consciousnessInitialAbstractionLevel
  , consciousnessInitialSilenceTolerance
  , consciousnessLowConfidenceThreshold
  ) where

backgroundSurfacingThreshold :: Double
backgroundSurfacingThreshold = 0.65

backgroundConflictStrongThreshold :: Double
backgroundConflictStrongThreshold = 0.85

backgroundConflictMediumThreshold :: Double
backgroundConflictMediumThreshold = 0.70

backgroundPressureDecayFactor :: Double
backgroundPressureDecayFactor = 0.92

backgroundDesireConflictDelta :: Double
backgroundDesireConflictDelta = 0.20

backgroundProductModeResistanceDelta :: Double
backgroundProductModeResistanceDelta = 0.15

backgroundExplicitConflictDelta :: Double
backgroundExplicitConflictDelta = 0.30

consciousnessSilenceOntologyBonus :: Double
consciousnessSilenceOntologyBonus = 0.30

consciousnessListenOntologyBonus :: Double
consciousnessListenOntologyBonus = 0.25

consciousnessNameOntologyBonus :: Double
consciousnessNameOntologyBonus = 0.20

consciousnessSilenceContextBonus :: Double
consciousnessSilenceContextBonus = 0.25

consciousnessListenContextBonus :: Double
consciousnessListenContextBonus = 0.20

consciousnessResistContextBonus :: Double
consciousnessResistContextBonus = 0.30

consciousnessDeepSearchThreshold :: Double
consciousnessDeepSearchThreshold = 0.80

consciousnessShallowSearchThreshold :: Double
consciousnessShallowSearchThreshold = 0.50

consciousnessAbstractionEpsilon :: Double
consciousnessAbstractionEpsilon = 0.01

consciousnessDesirePresenceThreshold :: Double
consciousnessDesirePresenceThreshold = 0.30

consciousnessDesirePreserveThreshold :: Double
consciousnessDesirePreserveThreshold = 0.70

consciousnessFragmentLengthThreshold :: Int
consciousnessFragmentLengthThreshold = 15

consciousnessLowResonanceThreshold :: Double
consciousnessLowResonanceThreshold = 0.30

consciousnessHighResonanceReturnThreshold :: Double
consciousnessHighResonanceReturnThreshold = 0.65

consciousnessLowResonanceReturnThreshold :: Double
consciousnessLowResonanceReturnThreshold = 0.25

consciousnessTrajectoryLimit :: Int
consciousnessTrajectoryLimit = 30

consciousnessSkillAffinityPatternThreshold :: Double
consciousnessSkillAffinityPatternThreshold = 0.80

consciousnessDefaultSkillAffinity :: Double
consciousnessDefaultSkillAffinity = 0.50

consciousnessInitialSearchDepth :: Double
consciousnessInitialSearchDepth = 0.90

consciousnessInitialPatternWeight :: Double
consciousnessInitialPatternWeight = 0.65

consciousnessInitialTemporalBias :: Double
consciousnessInitialTemporalBias = 0.05

consciousnessInitialAbstractionLevel :: Double
consciousnessInitialAbstractionLevel = 0.60

consciousnessInitialSilenceTolerance :: Double
consciousnessInitialSilenceTolerance = 0.85

consciousnessLowConfidenceThreshold :: Double
consciousnessLowConfidenceThreshold = 0.60
