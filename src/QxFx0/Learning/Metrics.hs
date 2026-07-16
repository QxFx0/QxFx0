{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Learning.Metrics
  ( LearningMetrics(..)
  , emptyLearningMetrics
  , newLearningMetrics
  ) where

import Data.IORef (IORef, newIORef)

-- | Metrics for autonomous learning cycle.
data LearningMetrics = LearningMetrics
  { lmUpdatesApplied :: !Int
  , lmUpdatesDeferred :: !Int
  , lmEventsProcessed :: !Int
  , lmErrorsEncountered :: !Int
  , lmEdgesAccepted :: !Int
  , lmEdgesRejected :: !Int
  , lmEdgesQuarantined :: !Int
  } deriving stock (Eq, Show)

emptyLearningMetrics :: LearningMetrics
emptyLearningMetrics = LearningMetrics
  { lmUpdatesApplied = 0
  , lmUpdatesDeferred = 0
  , lmEventsProcessed = 0
  , lmErrorsEncountered = 0
  , lmEdgesAccepted = 0
  , lmEdgesRejected = 0
  , lmEdgesQuarantined = 0
  }

newLearningMetrics :: IO (IORef LearningMetrics)
newLearningMetrics = newIORef emptyLearningMetrics
