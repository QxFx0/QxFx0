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
import Data.Aeson
  ( FromJSON(..)
  , Options(..)
  , ToJSON(..)
  , defaultOptions
  , genericParseJSON
  , genericToJSON
  )
import Data.Text (Text)
import Data.Time.Clock (UTCTime)
import GHC.Generics (Generic)

import QxFx0.Internal.WireCompat (legacyConatusLabel)

newtype CalibrationSignal = CalibrationSignal { unCalibrationSignal :: Double }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data SignalComponents = SignalComponents
  { scStateIntegrityTrend      :: !Double
  , scUncertaintyTrend  :: !Double
  , scLoopRisk          :: !Double
  , scBranchHealthTrend :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

-- | P4 (2026-11-23): persisted inside @calibrationSnapshots@; the trend
-- key keeps its historical @scConatusTrend@ spelling.
instance ToJSON SignalComponents where
  toJSON = genericToJSON defaultOptions
    { fieldLabelModifier = legacyConatusLabel }

instance FromJSON SignalComponents where
  parseJSON = genericParseJSON defaultOptions
    { fieldLabelModifier = legacyConatusLabel }

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
  , spcStateIntegrityWeight      :: !Double
  , spcUncertaintyWeight  :: !Double
  , spcLoopRiskWeight     :: !Double
  , spcBranchHealthWeight :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)
