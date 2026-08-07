{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Self.Conatus
  ( ConatusWeights(..)
  , ConatusComponents(..)
  , ConatusEnergy(..)
  , ConatusGradient(..)
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON(..), ToJSON(..), object, withObject, (.=), (.:?), (.!=))
import GHC.Generics (Generic)

data ConatusWeights = ConatusWeights
  { cwMorphology :: !Double
  , cwIdentity   :: !Double
  , cwTurns      :: !Double
  , cwViolation  :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

data ConatusComponents = ConatusComponents
  { ccMorphology     :: !Double
  , ccIdentity       :: !Double
  , ccTurns          :: !Double
  , ccPenalty        :: !Double
    -- ^ Violation penalty only ('BlanketViolation's). Semantically
    --   locked: self-divergence adjustments never land here.
  , ccSelfDivergence :: !Double
    -- ^ A-slice: self-consistency penalty share (<= 0), set by the
    --   prepare-stage application of the previous turn's divergence.
    --   Kept as a dedicated component so the violation channel stays
    --   semantically pure.  Invariant: @ceScalar == sum of all five@.
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON ConatusComponents where
  toJSON comps = object
    [ "ccMorphology" .= ccMorphology comps
    , "ccIdentity" .= ccIdentity comps
    , "ccTurns" .= ccTurns comps
    , "ccPenalty" .= ccPenalty comps
    , "ccSelfDivergence" .= ccSelfDivergence comps
    ]

-- | Backward-compatible parse: persisted pre-A2 traces lacked the
-- @ccSelfDivergence@ key, so it defaults to 0.0 when absent.
instance FromJSON ConatusComponents where
  parseJSON = withObject "ConatusComponents" $ \o ->
    ConatusComponents
      <$> o .:? "ccMorphology" .!= 0.0
      <*> o .:? "ccIdentity" .!= 0.0
      <*> o .:? "ccTurns" .!= 0.0
      <*> o .:? "ccPenalty" .!= 0.0
      <*> o .:? "ccSelfDivergence" .!= 0.0

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