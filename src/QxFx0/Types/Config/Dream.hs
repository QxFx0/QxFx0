{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Types.Config.Dream
  ( DreamPressureRegime(..)
  , defaultDreamPressureRegime
  , dreamFamilyBiasProfile
  , dreamDriftHalfLifeHours
  , dreamBiasRelaxAlphaPerHourDefault
  , dreamBiasDeltaCapPerCycleDefault
  , dreamMinQualityWeightDefault
  , dreamMaxAttractorNormDefault
  , dreamMaxReflectionBiasNormDefault
  , dreamThresholdHoursDefault
  , dreamCycleDurationHoursDefault
  , dreamMaxCatchupHoursDefault
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import GHC.Generics (Generic)
import QxFx0.Types.Domain (CanonicalMoveFamily(..))
import QxFx0.Types.Vec (CoreVec(..))

data DreamPressureRegime = DreamPressureRegime
  { dprDatalogWeight :: !Double
  , dprIntuitionWeight :: !Double
  , dprAgreementBonus :: !Double
  , dprConflictPenalty :: !Double
  , dprMaxStrength :: !Double
  , dprMaxBiasNorm :: !Double
  , dprCandidateThreshold :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

defaultDreamPressureRegime :: DreamPressureRegime
defaultDreamPressureRegime = DreamPressureRegime
  { dprDatalogWeight = 0.55
  , dprIntuitionWeight = 0.45
  , dprAgreementBonus = 0.10
  , dprConflictPenalty = 0.15
  , dprMaxStrength = 1.0
  , dprMaxBiasNorm = 0.08
  , dprCandidateThreshold = 0.35
  }

dreamDriftHalfLifeHours :: Double
dreamDriftHalfLifeHours = 7.0

dreamBiasRelaxAlphaPerHourDefault :: Double
dreamBiasRelaxAlphaPerHourDefault = 0.0025

dreamBiasDeltaCapPerCycleDefault :: Double
dreamBiasDeltaCapPerCycleDefault = 0.003

dreamMinQualityWeightDefault :: Double
dreamMinQualityWeightDefault = 0.35

dreamMaxAttractorNormDefault :: Double
dreamMaxAttractorNormDefault = 0.08

dreamMaxReflectionBiasNormDefault :: Double
dreamMaxReflectionBiasNormDefault = 0.15

dreamThresholdHoursDefault :: Double
dreamThresholdHoursDefault = 6.0

dreamCycleDurationHoursDefault :: Double
dreamCycleDurationHoursDefault = 1.0

dreamMaxCatchupHoursDefault :: Double
dreamMaxCatchupHoursDefault = 168.0

dreamFamilyBiasProfile :: CanonicalMoveFamily -> CoreVec
dreamFamilyBiasProfile family = case family of
  CMContact -> CoreVec 0.08 0.02 0.07 0.03 0.04
  CMRepair -> CoreVec 0.07 0.01 0.08 0.02 0.03
  CMAnchor -> CoreVec 0.05 0.01 0.08 0.04 0.05
  CMDeepen -> CoreVec 0.03 0.02 0.05 0.08 0.05
  CMClarify -> CoreVec 0.04 0.03 0.06 0.06 0.05
  CMReflect -> CoreVec 0.05 0.02 0.06 0.07 0.06
  CMConfront -> CoreVec 0.02 0.08 0.03 0.05 0.07
  CMNextStep -> CoreVec 0.03 0.07 0.05 0.03 0.08
  CMPurpose -> CoreVec 0.04 0.03 0.05 0.07 0.07
  CMHypothesis -> CoreVec 0.02 0.05 0.04 0.08 0.06
  CMDefine -> CoreVec 0.03 0.03 0.05 0.06 0.05
  CMDistinguish -> CoreVec 0.03 0.04 0.05 0.06 0.05
  CMDescribe -> CoreVec 0.04 0.02 0.05 0.05 0.04
  CMGround -> CoreVec 0.04 0.02 0.06 0.04 0.05
