{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Offline quality/evaluation gates for autonomous learning.  This module
-- is deliberately pure: CI and replay tooling can evaluate a corpus of
-- durable learning events without starting the runtime or calling an LLM.
module QxFx0.Learning.Quality
  ( LearningQualityMetrics(..)
  , QualityGateConfig(..)
  , QualityGateResult(..)
  , emptyLearningQualityMetrics
  , summarizeLearningEvents
  , evaluateQualityGate
  ) where

import Data.Text (Text)
import GHC.Generics (Generic)

import QxFx0.Learning.Events
  ( LearningEvent(..)
  , LearningEventKind(..)
  )

data LearningQualityMetrics = LearningQualityMetrics
  { lqmAccepted       :: !Int
  , lqmQuarantined    :: !Int
  , lqmRejected       :: !Int
  , lqmRetries        :: !Int
  , lqmFailures       :: !Int
  , lqmRollbacks      :: !Int
  , lqmContradictions :: !Int
  , lqmDensityBefore  :: !Double
  , lqmDensityAfter   :: !Double
  } deriving stock (Eq, Show, Generic)

data QualityGateConfig = QualityGateConfig
  { qgcMinAccepted          :: !Int
  , qgcMaxQuarantineRate   :: !Double
  , qgcMaxContradictionRate :: !Double
  , qgcMinDensityDelta     :: !Double
  } deriving stock (Eq, Show, Generic)

data QualityGateResult
  = QualityGatePass
  | QualityGateFail [Text]
  deriving stock (Eq, Show, Generic)

emptyLearningQualityMetrics :: LearningQualityMetrics
emptyLearningQualityMetrics = LearningQualityMetrics 0 0 0 0 0 0 0 0 0

summarizeLearningEvents :: [LearningEvent] -> LearningQualityMetrics
summarizeLearningEvents = foldr step emptyLearningQualityMetrics
  where
    step event m = case leKind event of
      EdgeAdmitted -> m { lqmAccepted = lqmAccepted m + 1 }
      EdgeCorroborated -> m { lqmAccepted = lqmAccepted m + 1 }
      EdgeQuarantined -> m { lqmQuarantined = lqmQuarantined m + 1 }
      EdgeRejected -> m { lqmRejected = lqmRejected m + 1 }
      EdgeRetired -> m { lqmRollbacks = lqmRollbacks m + 1 }
      RuntimeFeedbackConflict -> m { lqmContradictions = lqmContradictions m + 1 }
      _ -> m

evaluateQualityGate :: QualityGateConfig -> LearningQualityMetrics -> QualityGateResult
evaluateQualityGate cfg m =
  let total = max 1 (lqmAccepted m + lqmQuarantined m + lqmRejected m)
      quarantineRate = fromIntegral (lqmQuarantined m) / fromIntegral total
      contradictionRate = fromIntegral (lqmContradictions m) / fromIntegral total
      failures = concat
        [ ["minimum accepted candidates not reached" | lqmAccepted m < qgcMinAccepted cfg]
        , ["quarantine rate exceeds gate" | quarantineRate > qgcMaxQuarantineRate cfg]
        , ["contradiction rate exceeds gate" | contradictionRate > qgcMaxContradictionRate cfg]
        , ["density delta below gate" | lqmDensityAfter m - lqmDensityBefore m < qgcMinDensityDelta cfg]
        ]
  in if null failures then QualityGatePass else QualityGateFail failures
