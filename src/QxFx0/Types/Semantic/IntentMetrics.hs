{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

-- | Leaf observability carrier for semantic intent classification.
module QxFx0.Types.Semantic.IntentMetrics
  ( IntentClassifierMetrics(..)
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import GHC.Generics (Generic)

data IntentClassifierMetrics = IntentClassifierMetrics
  { icmTotalClassifications :: !Int
  , icmClassifiedCount :: !Int
  , icmUnclassifiedCount :: !Int
  , icmAgreementCount :: !Int
  , icmDisagreementCount :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)
