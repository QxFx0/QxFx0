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
import Data.Aeson (FromJSON, ToJSON)
import GHC.Generics (Generic)

data SalienceDriver
  = DrivenByResonance
  | DrivenByAtmosphere
  | DrivenByConsolidation
  | DrivenByCounterfactual
  | DrivenByFieldConfidence
  | DrivenByConatusGate
  | DrivenByContentSaliency
  | DrivenByDefault
  deriving stock (Eq, Show, Bounded, Enum, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

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
  , conatusGateThreshold  :: !Double
  , verdictThreshold      :: !Double
  , sigmoidTemperature    :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

data SalienceModulation = SalienceModulation
  { smModulationHolisticBiasFloor :: !Double
  , smEscalationConfidenceFloor   :: !Double
  } deriving stock (Eq, Show)
