{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Bayesian
  ( HiddenBelief(..)
  , BeliefState
  , initialBeliefs
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson
  ( FromJSON(..)
  , FromJSONKey(..)
  , FromJSONKeyFunction(..)
  , ToJSON(..)
  , ToJSONKey(..)
  , ToJSONKeyFunction(..)
  , genericParseJSON
  , genericToJSON
  , defaultOptions
  , toEncoding
  )
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import GHC.Generics (Generic)

data HiddenBelief
  = UserWantsDefine
  | UserWantsCompare
  | UserWantsConfront
  | UserSeeksSupport
  | UserIsConfused
  | UserIsDistressed
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData, ToJSON, FromJSON)

instance ToJSONKey HiddenBelief where
  toJSONKey = ToJSONKeyValue toJSON toEncoding
instance FromJSONKey HiddenBelief where
  fromJSONKey = FromJSONKeyValue parseJSON

type BeliefState = Map HiddenBelief Double

initialBeliefs :: BeliefState
initialBeliefs = M.fromList [(b, 1.0 / fromIntegral (length [minBound..maxBound :: HiddenBelief])) | b <- [minBound..maxBound]]
