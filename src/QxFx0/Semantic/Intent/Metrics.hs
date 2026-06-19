{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Semantic.Intent.Metrics
  ( IntentClassifierMetrics(..)
  , emptyIntentClassifierMetrics
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import GHC.Generics (Generic)

data IntentClassifierMetrics = IntentClassifierMetrics
  { icmTotalClassifications :: !Int
  , icmClassifiedCount      :: !Int
  , icmUnclassifiedCount    :: !Int
  , icmAgreementCount       :: !Int
  , icmDisagreementCount    :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

emptyIntentClassifierMetrics :: IntentClassifierMetrics
emptyIntentClassifierMetrics = IntentClassifierMetrics
  { icmTotalClassifications = 0
  , icmClassifiedCount = 0
  , icmUnclassifiedCount = 0
  , icmAgreementCount = 0
  , icmDisagreementCount = 0
  }
