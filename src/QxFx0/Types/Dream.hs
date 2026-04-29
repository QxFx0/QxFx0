{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Dream
  ( DreamConfig(..)
  , DreamThemeEvidence(..)
  , DreamState(..)
  , DreamCycleLog(..)
  , DreamRejectionReason(..)
  , DreamEvidenceAudit(..)
  , DreamEvent(..)
  , R5State(..)
  , defaultDreamConfig
  , emptyDreamState
  , initialDreamState
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import Data.Text (Text)
import Data.Time (UTCTime(..))
import Data.Time.Calendar (fromGregorian)
import GHC.Generics (Generic)

import QxFx0.Types.Config.Dream
  ( dreamBiasDeltaCapPerCycleDefault
  , dreamBiasRelaxAlphaPerHourDefault
  , dreamCycleDurationHoursDefault
  , dreamDriftHalfLifeHours
  , dreamMaxAttractorNormDefault
  , dreamMaxCatchupHoursDefault
  , dreamMaxReflectionBiasNormDefault
  , dreamMinQualityWeightDefault
  , dreamThresholdHoursDefault
  )
import QxFx0.Types.Vec (CoreVec, zeroVec)

data DreamConfig = DreamConfig
  { dcDriftLambdaPerHour :: !Double
  , dcBiasRelaxAlphaPerHour :: !Double
  , dcBiasDeltaCapPerCycle :: !Double
  , dcMinQualityWeight :: !Double
  , dcMaxAttractorNorm :: !Double
  , dcMaxReflectionBiasNorm :: !Double
  , dcDreamThresholdHours :: !Double
  , dcCycleDurationHours :: !Double
  , dcMaxCatchupHours :: !Double
  } deriving stock (Show, Read, Eq, Generic)
    deriving anyclass (FromJSON, ToJSON)

data DreamThemeEvidence = DreamThemeEvidence
  { dteTheme :: !Text
  , dteBias :: !CoreVec
  , dteExperienceWeight :: !Double
  , dteQualityWeight :: !Double
  , dteBiographyPermission :: !Bool
  } deriving stock (Show, Read, Eq, Generic)
    deriving anyclass (FromJSON, ToJSON, NFData)

data DreamRejectionReason
  = RejectedByBiographyPermission
  | RejectedByLowQuality !Double
  | RejectedByZeroExperienceWeight !Double
  deriving stock (Show, Read, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

data DreamEvidenceAudit = DreamEvidenceAudit
  { deaTheme :: !Text
  , deaAcceptedWeight :: !Double
  , deaQualityWeight :: !Double
  , deaExperienceWeight :: !Double
  , deaRejectionReason :: !(Maybe DreamRejectionReason)
  } deriving stock (Show, Read, Eq, Generic)
    deriving anyclass (FromJSON, ToJSON)

data R5State = R5State
  { r5BaseVec :: !CoreVec
  , r5KernelDrift :: !CoreVec
  , r5ReflectionBias :: !CoreVec
  } deriving stock (Show, Read, Eq, Generic)
    deriving anyclass (FromJSON, ToJSON, NFData)

data DreamState = DreamState
  { dsR5State :: !R5State
  , dsBiasAttractor :: !CoreVec
  , dsLastWakeTime :: !UTCTime
  , dsLastDreamTime :: !UTCTime
  , dsDreamCycleCount :: !Int
  } deriving stock (Show, Read, Eq, Generic)
    deriving anyclass (FromJSON, ToJSON, NFData)

data DreamEvent
  = DriftDecayApplied !Double !Double !Double
  | QualityGateApplied !Int !Int
  | AttractorComputed !Double
  | BiasRelaxationApplied !Double !Double !Double
  deriving stock (Show, Read, Eq, Generic)
  deriving anyclass (FromJSON, ToJSON)

data DreamCycleLog = DreamCycleLog
  { dclTimestamp :: !UTCTime
  , dclHours :: !Double
  , dclR5Before :: !R5State
  , dclR5After :: !R5State
  , dclAttractor :: !CoreVec
  , dclEvents :: ![DreamEvent]
  } deriving stock (Show, Read, Eq, Generic)
    deriving anyclass (FromJSON, ToJSON)

defaultDreamConfig :: DreamConfig
defaultDreamConfig = DreamConfig
  { dcDriftLambdaPerHour = log 2 / dreamDriftHalfLifeHours
  , dcBiasRelaxAlphaPerHour = dreamBiasRelaxAlphaPerHourDefault
  , dcBiasDeltaCapPerCycle = dreamBiasDeltaCapPerCycleDefault
  , dcMinQualityWeight = dreamMinQualityWeightDefault
  , dcMaxAttractorNorm = dreamMaxAttractorNormDefault
  , dcMaxReflectionBiasNorm = dreamMaxReflectionBiasNormDefault
  , dcDreamThresholdHours = dreamThresholdHoursDefault
  , dcCycleDurationHours = dreamCycleDurationHoursDefault
  , dcMaxCatchupHours = dreamMaxCatchupHoursDefault
  }

dreamEpoch :: UTCTime
dreamEpoch = UTCTime (fromGregorian 1970 1 1) 0

emptyDreamState :: CoreVec -> DreamState
emptyDreamState kv = initialDreamState dreamEpoch kv

initialDreamState :: UTCTime -> CoreVec -> DreamState
initialDreamState now kv = DreamState
  { dsR5State = R5State kv zeroVec zeroVec
  , dsBiasAttractor = zeroVec
  , dsLastWakeTime = now
  , dsLastDreamTime = now
  , dsDreamCycleCount = 0
  }
