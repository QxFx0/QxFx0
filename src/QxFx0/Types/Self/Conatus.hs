{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Types.Self.Conatus
  ( ConatusWeights(..)
  , ConatusComponents(..)
  , ConatusEnergy(..)
  , ConatusGradient(..)
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import GHC.Generics (Generic)

data ConatusWeights = ConatusWeights
  { cwMorphology :: !Double
  , cwIdentity   :: !Double
  , cwTurns      :: !Double
  , cwViolation  :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

data ConatusComponents = ConatusComponents
  { ccMorphology :: !Double
  , ccIdentity   :: !Double
  , ccTurns      :: !Double
  , ccPenalty    :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

data ConatusEnergy = ConatusEnergy
  { ceScalar     :: !Double
  , ceComponents :: !ConatusComponents
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

data ConatusGradient = ConatusGradient
  { cgMorphology :: !Double
  , cgIdentity   :: !Double
  , cgTurns      :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)
