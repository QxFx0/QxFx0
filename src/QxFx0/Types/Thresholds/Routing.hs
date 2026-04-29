module QxFx0.Types.Thresholds.Routing
  ( narrativeDeepCharsThreshold
  , strategyDeepKnownConfidenceCap
  , strategyDeepKnownConfidenceBoost
  , strategyDeepProbableToKnownCap
  , strategyDeepProbableToKnownBoost
  , strategyDeepUncertainToProbableCap
  , strategyDeepUncertainToProbableBoost
  , strategyDeepUnknownToUncertainCap
  , strategyDeepSpeculativeToUncertainCap
  , strategyShallowKnownToProbableFloor
  , strategyShallowKnownPenalty
  , strategyShallowProbableToUncertainFloor
  , strategyShallowProbablePenalty
  , anchorNoTopicLowLoadThreshold
  , anchorCarryStabilityBaseline
  , anchorCarryStabilityStep
  , anchorResetStabilityDefault
  , anchorTopicPreviewChars
  , anchorStabilityThreshold
  , principledRepetitionOverlapThreshold
  , principledAuthorityPressureStrength
  , principledCorrectionPressureWithNewInfo
  , principledCorrectionPressureWithoutNewInfo
  , principledEmotionalPressureStrength
  , principledInsistencePressureStrength
  , identityGuardDefaultAgencyBaseline
  , identityGuardDefaultTensionBaseline
  , narrativeIntuitionFamilyHintThreshold
  , tensionNegativeDelta
  , tensionDistressDelta
  , tensionEgoCarryFactor
  ) where

narrativeDeepCharsThreshold :: Int
narrativeDeepCharsThreshold = 60

strategyDeepKnownConfidenceCap :: Double
strategyDeepKnownConfidenceCap = 0.95

strategyDeepKnownConfidenceBoost :: Double
strategyDeepKnownConfidenceBoost = 0.05

strategyDeepProbableToKnownCap :: Double
strategyDeepProbableToKnownCap = 0.9

strategyDeepProbableToKnownBoost :: Double
strategyDeepProbableToKnownBoost = 0.1

strategyDeepUncertainToProbableCap :: Double
strategyDeepUncertainToProbableCap = 0.8

strategyDeepUncertainToProbableBoost :: Double
strategyDeepUncertainToProbableBoost = 0.1

strategyDeepUnknownToUncertainCap :: Double
strategyDeepUnknownToUncertainCap = 0.6

strategyDeepSpeculativeToUncertainCap :: Double
strategyDeepSpeculativeToUncertainCap = 0.6

strategyShallowKnownToProbableFloor :: Double
strategyShallowKnownToProbableFloor = 0.5

strategyShallowKnownPenalty :: Double
strategyShallowKnownPenalty = 0.1

strategyShallowProbableToUncertainFloor :: Double
strategyShallowProbableToUncertainFloor = 0.4

strategyShallowProbablePenalty :: Double
strategyShallowProbablePenalty = 0.1

anchorNoTopicLowLoadThreshold :: Double
anchorNoTopicLowLoadThreshold = 0.2

anchorCarryStabilityBaseline :: Double
anchorCarryStabilityBaseline = 0.45

anchorCarryStabilityStep :: Double
anchorCarryStabilityStep = 0.1

anchorResetStabilityDefault :: Double
anchorResetStabilityDefault = 0.35

anchorTopicPreviewChars :: Int
anchorTopicPreviewChars = 24

anchorStabilityThreshold :: Double
anchorStabilityThreshold = 0.6

principledRepetitionOverlapThreshold :: Double
principledRepetitionOverlapThreshold = 0.65

principledAuthorityPressureStrength :: Double
principledAuthorityPressureStrength = 0.90

principledCorrectionPressureWithNewInfo :: Double
principledCorrectionPressureWithNewInfo = 0.35

principledCorrectionPressureWithoutNewInfo :: Double
principledCorrectionPressureWithoutNewInfo = 0.80

principledEmotionalPressureStrength :: Double
principledEmotionalPressureStrength = 0.70

principledInsistencePressureStrength :: Double
principledInsistencePressureStrength = 0.55

identityGuardDefaultAgencyBaseline :: Double
identityGuardDefaultAgencyBaseline = 0.5

identityGuardDefaultTensionBaseline :: Double
identityGuardDefaultTensionBaseline = 0.5

narrativeIntuitionFamilyHintThreshold :: Double
narrativeIntuitionFamilyHintThreshold = 0.50

tensionNegativeDelta :: Double
tensionNegativeDelta = 0.10

tensionDistressDelta :: Double
tensionDistressDelta = 0.15

tensionEgoCarryFactor :: Double
tensionEgoCarryFactor = 0.05
