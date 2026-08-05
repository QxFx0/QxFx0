{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Types.Learning.Signal
  ( CalibrationSignal(..)
  , SignalComponents(..)
  , CalibrationSnapshot(..)
  , CalibrationDecision(..)
  , SignalPipelineConfig(..)
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import Data.Text (Text)
import Data.Time.Clock (UTCTime)
import GHC.Generics (Generic)

newtype CalibrationSignal = CalibrationSignal { unCalibrationSignal :: Double }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data SignalComponents = SignalComponents
  { scConatusTrend      :: !Double
  , scUncertaintyTrend  :: !Double
  , scLoopRisk          :: !Double
  , scBranchHealthTrend :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

data CalibrationSnapshot = CalibrationSnapshot
  { csTimestamp  :: !UTCTime
  , csRunId      :: !Text
  , csComponents :: !SignalComponents
  , csSignal     :: !Double
  , csDecision   :: !CalibrationDecision
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

data CalibrationDecision
  = CdApplySignal
  | CdHoldLowConfidence
  | CdHoldGuardrails
  | CdHoldNoNeed
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data SignalPipelineConfig = SignalPipelineConfig
  { spcMinConfidence      :: !Double
  , spcApplyRateLimit     :: !Int
  , spcApplyWindow        :: !Int
  , spcConatusWeight      :: !Double
  , spcUncertaintyWeight  :: !Double
  , spcLoopRiskWeight     :: !Double
  , spcBranchHealthWeight :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)
