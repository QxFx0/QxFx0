{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Learning.Need
  ( LearningNeed(..)
  , NeedTrend(..)
  , LearningNeedState(..)
  , LearningPressureConfig(..)
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON(..), ToJSON(..), object, withObject, (.:?), (.!=), (.=))
import GHC.Generics (Generic)

data LearningNeed
  = NeedSalienceCalibration
  | NeedKeywordEnrichment
  | NeedLexiconExtension
  | NeedNone
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data NeedTrend = TrendRising | TrendStable | TrendFalling
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data LearningNeedState = LearningNeedState
  { lnsCurrentNeed        :: !LearningNeed
  , lnsCandidateNeed      :: !LearningNeed
  , lnsLevel              :: !Double
  , lnsTrend              :: !NeedTrend
  , lnsPersistence        :: !Int
  , lnsLastSeenTurn       :: !Int
  , lnsHistory            :: ![(Int, Double)]
  , lnsUnknownWindowCount :: !Int
  , lnsWindowStartTurn    :: !Int
  , lnsWindowGraftBaseline :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON LearningNeedState where
  toJSON s = object
    [ "currentNeed" .= lnsCurrentNeed s
    , "candidateNeed" .= lnsCandidateNeed s
    , "level" .= lnsLevel s
    , "trend" .= lnsTrend s
    , "persistence" .= lnsPersistence s
    , "lastSeenTurn" .= lnsLastSeenTurn s
    , "history" .= lnsHistory s
    , "unknownWindowCount" .= lnsUnknownWindowCount s
    , "windowStartTurn" .= lnsWindowStartTurn s
    , "windowGraftBaseline" .= lnsWindowGraftBaseline s
    ]

instance FromJSON LearningNeedState where
  parseJSON = withObject "LearningNeedState" $ \o -> LearningNeedState
    <$> o .:? "currentNeed" .!= NeedNone
    <*> o .:? "candidateNeed" .!= NeedNone
    <*> o .:? "level" .!= 0.0
    <*> o .:? "trend" .!= TrendStable
    <*> o .:? "persistence" .!= 0
    <*> o .:? "lastSeenTurn" .!= 0
    <*> o .:? "history" .!= []
    <*> o .:? "unknownWindowCount" .!= 0
    <*> o .:? "windowStartTurn" .!= 0
    <*> o .:? "windowGraftBaseline" .!= 0

data LearningPressureConfig = LearningPressureConfig
  { lpcWindowSize      :: !Int
  , lpcMinUnknownCount :: !Int
  , lpcStagnationTurns :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)
