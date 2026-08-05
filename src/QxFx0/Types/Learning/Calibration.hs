{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Learning.Calibration
  ( CalibrationId(..)
  , CalibrationProposal(..)
  , CalibrationStatus(..)
  , CalibrationEntry(..)
  , CalibrationLog(..)
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON(..), ToJSON(..), object, withObject, (.:), (.:?), (.!=), (.=))
import Data.Text (Text)
import GHC.Generics (Generic)

import QxFx0.Types.Self.Field (FieldHeuristics)
import QxFx0.Types.Self.Salience (SalienceWeights)

newtype CalibrationId = CalibrationId { unCalibrationId :: Int }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data CalibrationProposal
  = ProposalSalienceWeights !SalienceWeights
  | ProposalFieldHeuristics !FieldHeuristics
  | ProposalRule !Text
  | ProposalConcept !Text
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data CalibrationStatus = Pending | Verified | Simulated | Accepted | Rejected | RolledBack
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data CalibrationEntry = CalibrationEntry
  { ceId          :: !CalibrationId
  , ceProposal    :: !CalibrationProposal
  , ceStatus      :: !CalibrationStatus
  , ceCreatedTurn :: !Int
  , ceDecidedTurn :: !(Maybe Int)
  , cePrevId      :: !(Maybe CalibrationId)
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON CalibrationEntry where
  toJSON e = object
    [ "id" .= unCalibrationId (ceId e)
    , "proposal" .= ceProposal e
    , "status" .= ceStatus e
    , "createdTurn" .= ceCreatedTurn e
    , "decidedTurn" .= ceDecidedTurn e
    , "prevId" .= fmap unCalibrationId (cePrevId e)
    ]

instance FromJSON CalibrationEntry where
  parseJSON = withObject "CalibrationEntry" $ \o -> CalibrationEntry
    <$> (CalibrationId <$> o .: "id")
    <*> o .: "proposal"
    <*> o .:? "status" .!= Pending
    <*> o .:? "createdTurn" .!= 0
    <*> o .:? "decidedTurn" .!= Nothing
    <*> (fmap CalibrationId <$> o .:? "prevId" .!= Nothing)

newtype CalibrationLog = CalibrationLog { unCalibrationLog :: [CalibrationEntry] }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)
