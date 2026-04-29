module QxFx0.Types.Thresholds.Common
  ( atomTraceAlphaDefault
  , kernelPulseCoherenceDefault
  , kernelPulseAgencySignalDefault
  , constitutionalAgencyMinDefault
  , constitutionalTensionMaxDefault
  , constitutionalAmbiguityPenaltyDefault
  , constitutionalShadowDivergencePenaltyDefault
  , constitutionalLocalRecoveryThresholdDefault
  , historyRetentionLimit
  , recentFamiliesLimit
  , rawInputHistoryLimit
  , blockedConceptsRetentionLimit
  , nixCacheMaxSize
  , maxInputLength
  , agdaTypecheckTimeoutMsDefault
  , egoAgencyDeltaGround
  , egoAgencyDeltaDefine
  , egoAgencyDeltaDistinguish
  , egoAgencyDeltaReflect
  , egoAgencyDeltaDescribe
  , egoAgencyDeltaPurpose
  , egoAgencyDeltaHypothesis
  , egoAgencyDeltaRepair
  , egoAgencyDeltaContact
  , egoAgencyDeltaAnchor
  , egoAgencyDeltaClarify
  , egoAgencyDeltaDeepen
  , egoAgencyDeltaConfront
  , egoAgencyDeltaNextStep
  ) where

atomTraceAlphaDefault :: Double
atomTraceAlphaDefault = 0.2

kernelPulseCoherenceDefault :: Double
kernelPulseCoherenceDefault = 0.5

kernelPulseAgencySignalDefault :: Double
kernelPulseAgencySignalDefault = 0.7

constitutionalAgencyMinDefault :: Double
constitutionalAgencyMinDefault = 0.3

constitutionalTensionMaxDefault :: Double
constitutionalTensionMaxDefault = 0.8

constitutionalAmbiguityPenaltyDefault :: Double
constitutionalAmbiguityPenaltyDefault = 0.15

constitutionalShadowDivergencePenaltyDefault :: Double
constitutionalShadowDivergencePenaltyDefault = 0.2

constitutionalLocalRecoveryThresholdDefault :: Double
constitutionalLocalRecoveryThresholdDefault = 0.3

historyRetentionLimit :: Int
historyRetentionLimit = 50

recentFamiliesLimit :: Int
recentFamiliesLimit = 10

rawInputHistoryLimit :: Int
rawInputHistoryLimit = 50

blockedConceptsRetentionLimit :: Int
blockedConceptsRetentionLimit = 64

nixCacheMaxSize :: Int
nixCacheMaxSize = 64

maxInputLength :: Int
maxInputLength = 10000

agdaTypecheckTimeoutMsDefault :: Int
agdaTypecheckTimeoutMsDefault = 30000

egoAgencyDeltaGround :: Double
egoAgencyDeltaGround = 0.05

egoAgencyDeltaDefine :: Double
egoAgencyDeltaDefine = 0.03

egoAgencyDeltaDistinguish :: Double
egoAgencyDeltaDistinguish = 0.02

egoAgencyDeltaReflect :: Double
egoAgencyDeltaReflect = 0.0

egoAgencyDeltaDescribe :: Double
egoAgencyDeltaDescribe = 0.01

egoAgencyDeltaPurpose :: Double
egoAgencyDeltaPurpose = 0.02

egoAgencyDeltaHypothesis :: Double
egoAgencyDeltaHypothesis = -0.01

egoAgencyDeltaRepair :: Double
egoAgencyDeltaRepair = 0.03

egoAgencyDeltaContact :: Double
egoAgencyDeltaContact = 0.04

egoAgencyDeltaAnchor :: Double
egoAgencyDeltaAnchor = 0.05

egoAgencyDeltaClarify :: Double
egoAgencyDeltaClarify = 0.0

egoAgencyDeltaDeepen :: Double
egoAgencyDeltaDeepen = -0.02

egoAgencyDeltaConfront :: Double
egoAgencyDeltaConfront = -0.05

egoAgencyDeltaNextStep :: Double
egoAgencyDeltaNextStep = 0.02
