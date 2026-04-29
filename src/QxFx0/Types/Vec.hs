{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Types.Vec
  ( CoreVec(..)
  , zeroVec
  , vecAdd
  , vecSub
  , vecScale
  , vecNorm
  , clampVecNorm
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON(..), ToJSON(..), object, withObject, (.:), (.=))
import GHC.Generics (Generic)

data CoreVec = CoreVec
  { cvPresence      :: !Double
  , cvDirectiveness :: !Double
  , cvSteadiness    :: !Double
  , cvDepth         :: !Double
  , cvAutonomy      :: !Double
  } deriving stock (Show, Read, Eq, Generic)
    deriving anyclass (NFData)

instance ToJSON CoreVec where
  toJSON v = object
    [ "presence"      .= cvPresence v
    , "directiveness" .= cvDirectiveness v
    , "steadiness"    .= cvSteadiness v
    , "depth"         .= cvDepth v
    , "autonomy"      .= cvAutonomy v
    ]

instance FromJSON CoreVec where
  parseJSON = withObject "CoreVec" $ \v ->
    CoreVec <$> v .: "presence"
            <*> v .: "directiveness"
            <*> v .: "steadiness"
            <*> v .: "depth"
            <*> v .: "autonomy"

zeroVec :: CoreVec
zeroVec = CoreVec 0 0 0 0 0

vecAdd :: CoreVec -> CoreVec -> CoreVec
vecAdd a b = CoreVec
  { cvPresence = cvPresence a + cvPresence b
  , cvDirectiveness = cvDirectiveness a + cvDirectiveness b
  , cvSteadiness = cvSteadiness a + cvSteadiness b
  , cvDepth = cvDepth a + cvDepth b
  , cvAutonomy = cvAutonomy a + cvAutonomy b
  }

vecSub :: CoreVec -> CoreVec -> CoreVec
vecSub a b = CoreVec
  { cvPresence = cvPresence a - cvPresence b
  , cvDirectiveness = cvDirectiveness a - cvDirectiveness b
  , cvSteadiness = cvSteadiness a - cvSteadiness b
  , cvDepth = cvDepth a - cvDepth b
  , cvAutonomy = cvAutonomy a - cvAutonomy b
  }

vecScale :: Double -> CoreVec -> CoreVec
vecScale s v = CoreVec
  { cvPresence = s * cvPresence v
  , cvDirectiveness = s * cvDirectiveness v
  , cvSteadiness = s * cvSteadiness v
  , cvDepth = s * cvDepth v
  , cvAutonomy = s * cvAutonomy v
  }

vecNorm :: CoreVec -> Double
vecNorm v = sqrt
  ( cvPresence v * cvPresence v
  + cvDirectiveness v * cvDirectiveness v
  + cvSteadiness v * cvSteadiness v
  + cvDepth v * cvDepth v
  + cvAutonomy v * cvAutonomy v
  )

clampVecNorm :: Double -> CoreVec -> CoreVec
clampVecNorm maxNorm v
  | normV < 1e-9 = zeroVec
  | normV <= maxNorm = v
  | otherwise = vecScale (maxNorm / normV) v
  where
    normV = vecNorm v
{-# LANGUAGE OverloadedStrings #-}
