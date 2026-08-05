{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Semantic.Intent.Metrics
  ( IntentClassifierMetrics(..)
  , emptyIntentClassifierMetrics
  ) where

import QxFx0.Types.Semantic.IntentMetrics (IntentClassifierMetrics(..))

emptyIntentClassifierMetrics :: IntentClassifierMetrics
emptyIntentClassifierMetrics = IntentClassifierMetrics
  { icmTotalClassifications = 0
  , icmClassifiedCount = 0
  , icmUnclassifiedCount = 0
  , icmAgreementCount = 0
  , icmDisagreementCount = 0
  }
