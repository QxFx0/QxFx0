{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Types.Self.Salience
  ( SalienceDriver(..)
  , Salience(..)
  , SalienceVerdict(..)
  , SelfVerdict(..)
  , SalienceWeights(..)
  , SalienceModulation(..)
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
import GHC.Generics (Generic)

import QxFx0.Internal.WireCompat (legacyConatusLabel)

data SalienceDriver
  = DrivenByResonance
  | DrivenByAtmosphere
  | DrivenByConsolidation
  | DrivenByCounterfactual
  | DrivenByFieldConfidence
  | DrivenByStateIntegrityGate
  | DrivenByContentSaliency
  | DrivenByDefault
  deriving stock (Eq, Show, Bounded, Enum, Generic)
  deriving anyclass (NFData)

-- | P4 (2026-11-23): the constructor tag is a persisted wire value
-- (inside @selfEssence@ witnesses), so it keeps the historical
-- @DrivenByConatusGate@ spelling.
instance ToJSON SalienceDriver where
  toJSON = genericToJSON defaultOptions
    { constructorTagModifier = legacyConatusLabel }

instance FromJSON SalienceDriver where
  parseJSON = genericParseJSON defaultOptions
    { constructorTagModifier = legacyConatusLabel }

data Salience = Salience
  { salienceHolisticBias :: !Double
  , salienceConfidence   :: !Double
  , salienceDriver       :: !SalienceDriver
  } deriving stock (Eq, Show)

data SalienceVerdict
  = PreferHolistic !Double
  | PreferFormal !Double
  | Tied
  deriving stock (Eq, Show)

data SelfVerdict = SelfVerdict
  { svSalience :: !Salience
  , svVerdict  :: !SalienceVerdict
  } deriving stock (Eq, Show)

data SalienceWeights = SalienceWeights
  { weightResonance       :: !Double
  , weightAtmosphere      :: !Double
  , weightConsolidation   :: !Double
  , weightCounterfactual  :: !Double
  , weightFieldConfidence :: !Double
  , weightContentSaliency :: !Double
  , stateIntegrityGateThreshold  :: !Double
  , verdictThreshold      :: !Double
  , sigmoidTemperature    :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

-- | P4 (2026-11-23): persisted as @selfSalienceWeights@; the threshold
-- key keeps its historical @conatusGateThreshold@ spelling.
instance ToJSON SalienceWeights where
  toJSON = genericToJSON defaultOptions
    { fieldLabelModifier = legacyConatusLabel }

instance FromJSON SalienceWeights where
  parseJSON = genericParseJSON defaultOptions
    { fieldLabelModifier = legacyConatusLabel }

data SalienceModulation = SalienceModulation
  { smModulationHolisticBiasFloor :: !Double
  , smEscalationConfidenceFloor   :: !Double
  } deriving stock (Eq, Show)
