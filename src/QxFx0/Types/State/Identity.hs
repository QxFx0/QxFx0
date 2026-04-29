{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

{-| Identity-facing persisted state slices: ego dynamics, orbital memory, and guard reports. -}
module QxFx0.Types.State.Identity
  ( Trend(..)
  , SubjectDynamics(..)
  , EgoState(..)
  , emptyEgoState
  , IdentityState(..)
  , emptyIdentityState
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson
  ( FromJSON(..)
  , ToJSON(..)
  , defaultOptions
  , genericParseJSON
  , genericToJSON
  , object
  , withObject
  , (.:)
  , (.:?)
  , (.!=)
  , (.=)
  )
import Data.Text (Text)
import GHC.Generics (Generic)

import QxFx0.Types.Config.State
  ( defaultEgoAgency
  , defaultEgoMission
  , defaultEgoTension
  , defaultNeutralUserState
  )
import QxFx0.Types.Domain
  ( IdentityClaimRef
  , UserState
  )
import QxFx0.Types.IdentityGuard (IdentityGuardReport)
import QxFx0.Types.Orbital (OrbitalMemory, emptyOrbitalMemory)

data Trend = Rising | Falling | Plateau
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData)

instance ToJSON Trend where
  toJSON = genericToJSON defaultOptions

instance FromJSON Trend where
  parseJSON = genericParseJSON defaultOptions

data SubjectDynamics = SubjectDynamics
  { sdTrend :: !Trend
  , sdSemanticHistory :: ![Text]
  , sdLastShiftTurn :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON SubjectDynamics where
  toJSON = genericToJSON defaultOptions

instance FromJSON SubjectDynamics where
  parseJSON = genericParseJSON defaultOptions

data EgoState = EgoState
  { egoTension :: !Double
  , egoAgency :: !Double
  , egoMission :: !Text
  , egoUserState :: !UserState
  , egoSubjectDynamics :: !SubjectDynamics
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON EgoState where
  toJSON = genericToJSON defaultOptions

instance FromJSON EgoState where
  parseJSON = genericParseJSON defaultOptions

emptyEgoState :: EgoState
emptyEgoState = EgoState
  { egoTension = defaultEgoTension
  , egoAgency = defaultEgoAgency
  , egoMission = defaultEgoMission
  , egoUserState = defaultNeutralUserState
  , egoSubjectDynamics = SubjectDynamics Plateau [] 0
  }

data IdentityState = IdentityState
  { idsEgo :: !EgoState
  , idsIdentityClaims :: ![IdentityClaimRef]
  , idsOrbitalMemory :: !OrbitalMemory
  , idsLastGuardReport :: !(Maybe IdentityGuardReport)
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON IdentityState where
  toJSON ids = object
    [ "ego" .= idsEgo ids
    , "identityClaims" .= idsIdentityClaims ids
    , "orbitalMemory" .= idsOrbitalMemory ids
    , "lastGuardReport" .= idsLastGuardReport ids
    ]

instance FromJSON IdentityState where
  parseJSON = withObject "IdentityState" $ \o -> IdentityState
    <$> o .: "ego"
    <*> o .: "identityClaims"
    <*> o .: "orbitalMemory"
    <*> o .:? "lastGuardReport" .!= Nothing

emptyIdentityState :: IdentityState
emptyIdentityState = IdentityState
  { idsEgo = emptyEgoState
  , idsIdentityClaims = []
  , idsOrbitalMemory = emptyOrbitalMemory
  , idsLastGuardReport = Nothing
  }
