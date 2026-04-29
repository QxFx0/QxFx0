{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Types.ClaimAst
  ( ClaimAst(..)
  , GfModifier(..)
  , GfVP(..)
  , GfNP(..)
  , GfRelation(..)
  , GfMechanism(..)
  , GfNumber(..)
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson
  ( FromJSON(..)
  , ToJSON(..)
  , defaultOptions
  , genericParseJSON
  , genericToJSON
  )
import Data.Text (Text)
import GHC.Generics (Generic)

data GfModifier = ModFirst | ModStrictly deriving stock (Eq, Show, Generic) deriving anyclass (NFData)
data GfVP = ActMaintain !GfNumber !Text | ActDefine !Text deriving stock (Eq, Show, Generic) deriving anyclass (NFData)
data GfNP = MkNP !Text deriving stock (Eq, Show, Generic) deriving anyclass (NFData)
data GfRelation = RelIdentity deriving stock (Eq, Show, Generic) deriving anyclass (NFData)
data GfMechanism = MechParse deriving stock (Eq, Show, Generic) deriving anyclass (NFData)
data GfNumber = NumSg | NumPl deriving stock (Eq, Show, Generic) deriving anyclass (NFData)

data ClaimAst
  = ClaimPurpose !Text
  | ClaimSelfState
  | ClaimComparison !Text !Text
  | MoveInvite GfNP GfModifier GfVP
  | MoveDefine GfNP GfRelation GfNP
  | MoveCause GfNP GfMechanism
  | MovePurpose GfNP
  | MoveSelfState
  | MoveCompare GfNP GfNP
  | MoveOperationalStatus
  | MoveOperationalCause
  | MoveSystemLogic
  | MoveMisunderstanding
  | MoveGenerativeThought
  | MoveContemplative GfNP
  | MoveGround GfNP
  | MoveContact GfNP
  | MoveReflect GfNP
  | MoveDescribe GfNP
  | MoveDeepen GfNP
  | MoveConfront GfNP
  | MoveAnchor GfNP
  | MoveClarify GfNP
  | MoveNextStepLocal GfNP
  | MoveHypothesis GfNP
  | MoveDistinguish GfNP GfNP
  | StanceWrapped !Text ClaimAst
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

instance ToJSON GfModifier where toJSON = genericToJSON defaultOptions
instance FromJSON GfModifier where parseJSON = genericParseJSON defaultOptions
instance ToJSON GfVP where toJSON = genericToJSON defaultOptions
instance FromJSON GfVP where parseJSON = genericParseJSON defaultOptions
instance ToJSON GfNP where toJSON = genericToJSON defaultOptions
instance FromJSON GfNP where parseJSON = genericParseJSON defaultOptions
instance ToJSON GfRelation where toJSON = genericToJSON defaultOptions
instance FromJSON GfRelation where parseJSON = genericParseJSON defaultOptions
instance ToJSON GfMechanism where toJSON = genericToJSON defaultOptions
instance FromJSON GfMechanism where parseJSON = genericParseJSON defaultOptions
instance ToJSON GfNumber where toJSON = genericToJSON defaultOptions
instance FromJSON GfNumber where parseJSON = genericParseJSON defaultOptions

instance ToJSON ClaimAst where toJSON = genericToJSON defaultOptions
instance FromJSON ClaimAst where parseJSON = genericParseJSON defaultOptions
