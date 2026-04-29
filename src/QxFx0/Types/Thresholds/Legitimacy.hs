module QxFx0.Types.Thresholds.Legitimacy
  ( criticalTensionThreshold
  , elevatedTensionThreshold
  , lowAgencyThreshold
  , veryLowAgencyThreshold
  , highAgencyThreshold
  , highTraceLoadThreshold
  , minIdentityClaimConfidence
  , parserLowConfidenceThreshold
  , parserHighConfidenceThreshold
  , scenePressureLowThreshold
  , scenePressureMediumThreshold
  , legitimacyConfidencePenaltyWeight
  , legitimacyHighLoadThreshold
  , legitimacyHighLoadPenalty
  , legitimacyApiPenalty
  , legitimacyPassThreshold
  , legitimacyCautionThreshold
  , legitimacyRecoveryThreshold
  , embSimilarityBonusThreshold
  , embSimilarityLegitimacyBonus
  , intuitConfidenceBonusThreshold
  , intuitConfidenceLegitimacyBonus
  , legitimacyShadowAgreementBonus
  , legitimacyStableRouteBonus
  , agdaVerificationPenalty
  , claimConceptMatchWeight
  , claimTopicMatchWeight
  , claimTextMatchWeight
  , claimConfidenceWeight
  , shadowPenaltyFamilyMismatch
  , shadowPenaltyForceMismatch
  , shadowPenaltyClauseMismatch
  , shadowPenaltyLayerMismatch
  , shadowPenaltyWarrantedMismatch
  ) where

criticalTensionThreshold :: Double
criticalTensionThreshold = 0.8

elevatedTensionThreshold :: Double
elevatedTensionThreshold = 0.7

lowAgencyThreshold :: Double
lowAgencyThreshold = 0.3

veryLowAgencyThreshold :: Double
veryLowAgencyThreshold = 0.2

highAgencyThreshold :: Double
highAgencyThreshold = 0.8

highTraceLoadThreshold :: Double
highTraceLoadThreshold = 0.8

minIdentityClaimConfidence :: Double
minIdentityClaimConfidence = 0.3

parserLowConfidenceThreshold :: Double
parserLowConfidenceThreshold = 0.5

parserHighConfidenceThreshold :: Double
parserHighConfidenceThreshold = 0.72

scenePressureLowThreshold :: Double
scenePressureLowThreshold = 0.33

scenePressureMediumThreshold :: Double
scenePressureMediumThreshold = 0.66

legitimacyConfidencePenaltyWeight :: Double
legitimacyConfidencePenaltyWeight = 0.3

legitimacyHighLoadThreshold :: Double
legitimacyHighLoadThreshold = 0.8

legitimacyHighLoadPenalty :: Double
legitimacyHighLoadPenalty = 0.1

legitimacyApiPenalty :: Double
legitimacyApiPenalty = 0.1

legitimacyPassThreshold :: Double
legitimacyPassThreshold = 0.8

legitimacyCautionThreshold :: Double
legitimacyCautionThreshold = 0.65

legitimacyRecoveryThreshold :: Double
legitimacyRecoveryThreshold = 0.5

embSimilarityBonusThreshold :: Double
embSimilarityBonusThreshold = 0.8

embSimilarityLegitimacyBonus :: Double
embSimilarityLegitimacyBonus = 0.05

intuitConfidenceBonusThreshold :: Double
intuitConfidenceBonusThreshold = 0.5

intuitConfidenceLegitimacyBonus :: Double
intuitConfidenceLegitimacyBonus = 0.03

legitimacyShadowAgreementBonus :: Double
legitimacyShadowAgreementBonus = 0.04

legitimacyStableRouteBonus :: Double
legitimacyStableRouteBonus = 0.03

agdaVerificationPenalty :: Double
agdaVerificationPenalty = 0.10

claimConceptMatchWeight :: Double
claimConceptMatchWeight = 0.4

claimTopicMatchWeight :: Double
claimTopicMatchWeight = 0.3

claimTextMatchWeight :: Double
claimTextMatchWeight = 0.2

claimConfidenceWeight :: Double
claimConfidenceWeight = 0.1

shadowPenaltyFamilyMismatch :: Double
shadowPenaltyFamilyMismatch = 0.3

shadowPenaltyForceMismatch :: Double
shadowPenaltyForceMismatch = 0.15

shadowPenaltyClauseMismatch :: Double
shadowPenaltyClauseMismatch = 0.1

shadowPenaltyLayerMismatch :: Double
shadowPenaltyLayerMismatch = 0.1

shadowPenaltyWarrantedMismatch :: Double
shadowPenaltyWarrantedMismatch = 0.1
