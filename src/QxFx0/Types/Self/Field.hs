{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Self.Field
  ( Resonance(..)
  , Atmosphere(..)
  , FieldConfidence(..)
  , Consolidation(..)
  , Counterfactual(..)
  , Field(..)
  , FieldHeuristics(..)
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON(..), ToJSON(..), object, withObject, (.:), (.:?), (.!=), (.=))
import GHC.Generics (Generic)

newtype Resonance = Resonance { unResonance :: Double }
  deriving stock (Eq, Ord, Read, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data Atmosphere = Atmosphere
  { atmosphereValence :: !Double
  , atmosphereArousal :: !Double
  } deriving stock (Eq, Ord, Read, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

newtype FieldConfidence = FieldConfidence { unFieldConfidence :: Double }
  deriving stock (Eq, Ord, Read, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

newtype Consolidation = Consolidation { unConsolidation :: Double }
  deriving stock (Eq, Ord, Read, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

newtype Counterfactual = Counterfactual { unCounterfactual :: Double }
  deriving stock (Eq, Ord, Read, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data Field = Field
  { fieldResonance      :: !Resonance
  , fieldAtmosphere     :: !Atmosphere
  , fieldConfidence     :: !FieldConfidence
  , fieldConsolidation  :: !Consolidation
  , fieldCounterfactual :: !Counterfactual
  } deriving stock (Eq, Ord, Read, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

data FieldHeuristics = FieldHeuristics
  { fhNarrativeWindowSize     :: !Int
  , fhDefaultNarrativeRate    :: !Double
  , fhTopicStabilityBoost     :: !Double
  , fhEntropyEpsilon          :: !Double
  , fhHolisticStreakBoostRate :: !Double
  , fhHolisticStreakBoostCap  :: !Double
  , fhLegitimacyMidpoint      :: !Double
  , fhLegitimacyBonusScale    :: !Double
  , fhOntologyDepthBoost      :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON FieldHeuristics where
  toJSON fh = object
    [ "fhNarrativeWindowSize" .= fhNarrativeWindowSize fh
    , "fhDefaultNarrativeRate" .= fhDefaultNarrativeRate fh
    , "fhTopicStabilityBoost" .= fhTopicStabilityBoost fh
    , "fhEntropyEpsilon" .= fhEntropyEpsilon fh
    , "fhHolisticStreakBoostRate" .= fhHolisticStreakBoostRate fh
    , "fhHolisticStreakBoostCap" .= fhHolisticStreakBoostCap fh
    , "fhLegitimacyMidpoint" .= fhLegitimacyMidpoint fh
    , "fhLegitimacyBonusScale" .= fhLegitimacyBonusScale fh
    , "fhOntologyDepthBoost" .= fhOntologyDepthBoost fh
    ]

instance FromJSON FieldHeuristics where
  parseJSON = withObject "FieldHeuristics" $ \o -> FieldHeuristics
    <$> o .: "fhNarrativeWindowSize"
    <*> o .: "fhDefaultNarrativeRate"
    <*> o .: "fhTopicStabilityBoost"
    <*> o .: "fhEntropyEpsilon"
    <*> o .: "fhHolisticStreakBoostRate"
    <*> o .: "fhHolisticStreakBoostCap"
    <*> o .: "fhLegitimacyMidpoint"
    <*> o .: "fhLegitimacyBonusScale"
    <*> o .:? "fhOntologyDepthBoost" .!= 0.0
