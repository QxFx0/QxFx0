{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Intuition
  ( IntuitiveState(..)
  , basePrior
  , defaultIntuitiveState
  , effectivePosterior
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson
  ( FromJSON(..)
  , ToJSON(..)
  , object
  , withObject
  , (.:?)
  , (.!=)
  , (.=)
  )
import GHC.Generics (Generic)

import QxFx0.Types.Thresholds
  ( clamp01
  , intuitionBasePriorDefault
  , intuitionEffectivePosteriorShortWeight
  , intuitionEffectivePosteriorLongWeight
  )

data IntuitiveState = IntuitiveState
  { isCooldown :: !Int
  , isFlashCount :: !Int
  , isLastTurn :: !Int
  , isPosterior :: !Double
  , isLongPosterior :: !Double
  } deriving stock (Show, Read, Eq, Generic)
    deriving anyclass (NFData)

instance ToJSON IntuitiveState where
  toJSON state = object
    [ "cooldown" .= isCooldown state
    , "flashCount" .= isFlashCount state
    , "lastTurn" .= isLastTurn state
    , "posterior" .= isPosterior state
    , "longPosterior" .= isLongPosterior state
    ]

instance FromJSON IntuitiveState where
  parseJSON = withObject "IntuitiveState" $ \o -> do
    posterior <- o .:? "posterior" .!= basePrior
    longPosterior <- o .:? "longPosterior" .!= posterior
    IntuitiveState
      <$> o .:? "cooldown" .!= 0
      <*> o .:? "flashCount" .!= 0
      <*> o .:? "lastTurn" .!= 0
      <*> pure posterior
      <*> pure longPosterior

basePrior :: Double
basePrior = intuitionBasePriorDefault

defaultIntuitiveState :: IntuitiveState
defaultIntuitiveState = IntuitiveState 0 0 0 basePrior basePrior

effectivePosterior :: IntuitiveState -> Double
effectivePosterior state =
  let blended =
        intuitionEffectivePosteriorShortWeight * isPosterior state
          + intuitionEffectivePosteriorLongWeight * isLongPosterior state
  in clamp01 (max (isPosterior state) blended)
