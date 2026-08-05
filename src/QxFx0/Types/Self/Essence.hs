{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Types.Self.Essence
  ( Essence(..)
  , EssenceTrajectory(..)
  , EssenceWitness(..)
  , FieldSignature(..)
  , FieldBand(..)
  , ValenceBand(..)
  , TrajectoryHash(..)
  , EssenceMode(..)
  , CommitmentTrigger(..)
  , EssenceCommitment(..)
  , EssenceResetEvent(..)
  , EssenceViolation(..)
  , EssenceModulation(..)
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON(..), ToJSON(..), Value(..))
import Data.Aeson.Types (typeMismatch)
import Data.Sequence (Seq)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

import QxFx0.Types.Decision.Enums.Render (RenderStyle)
import QxFx0.Types.Domain.R5 (CanonicalMoveFamily)
import QxFx0.Types.Self.Deliberation (Agreement, NarrativeTone, ReconcileRule)
import QxFx0.Types.Self.Salience (SalienceDriver)

data Essence
  = EssenceUncommitted !EssenceTrajectory
  | EssenceCommitted !EssenceTrajectory !EssenceCommitment
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data EssenceTrajectory = EssenceTrajectory
  { etWitnesses    :: !(Seq EssenceWitness)
  , etAngstLevel   :: !Double
  , etConatusFloor :: !Double
  , etCapacity     :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

data EssenceWitness = EssenceWitness
  { ewTurnOrdinal    :: !Int
  , ewSalienceDriver :: !SalienceDriver
  , ewReconcileRule  :: !ReconcileRule
  , ewAgreement      :: !Agreement
  , ewDivergence     :: !Double
  , ewConatusScalar  :: !Double
  , ewFieldSignature :: !FieldSignature
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

data FieldSignature = FieldSignature
  { fsResonance      :: !FieldBand
  , fsArousal        :: !FieldBand
  , fsValence        :: !ValenceBand
  , fsConsolidation  :: !FieldBand
  , fsCounterfactual :: !FieldBand
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

data FieldBand = BandLow | BandMid | BandHigh
  deriving stock (Eq, Show, Bounded, Enum, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data ValenceBand = ValenceNegative | ValenceNeutral | ValencePositive
  deriving stock (Eq, Show, Bounded, Enum, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data EssenceMode
  = EssenceWitnessing
  | EssenceContemplative
  | EssenceDialogical
  | EssenceIntegrative
  deriving stock (Eq, Show, Bounded, Enum, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data CommitmentTrigger = TriggerAngstThreshold | TriggerConatusErosion
  deriving stock (Eq, Show, Bounded, Enum, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

newtype TrajectoryHash = TrajectoryHash { unTrajectoryHash :: Text }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

instance ToJSON TrajectoryHash where
  toJSON = toJSON . unTrajectoryHash

instance FromJSON TrajectoryHash where
  parseJSON value = case value of
    String txt -> pure (TrajectoryHash txt)
    Number n ->
      let rounded = round n :: Integer
      in if fromInteger rounded == n
           then pure (TrajectoryHash (T.pack (show rounded)))
           else pure (TrajectoryHash (T.pack (show (realToFrac n :: Double))))
    _ -> typeMismatch "TrajectoryHash" value

data EssenceCommitment = EssenceCommitment
  { ecMode        :: !EssenceMode
  , ecTrigger     :: !CommitmentTrigger
  , ecCommittedAt :: !Int
  , ecWitnessHash :: !TrajectoryHash
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

data EssenceResetEvent = EssenceResetEvent
  { ereTurn                 :: !Int
  , erePreviousAngst        :: !Double
  , erePreviousWitnessCount :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

data EssenceViolation
  = ViolationFamilyMismatch !EssenceMode !CanonicalMoveFamily
  | ViolationToneMismatch !EssenceMode !NarrativeTone
  | ViolationStyleMismatch !EssenceMode !RenderStyle
  | ViolationMissingDeliberation !EssenceMode
  | ViolationRefusedCommitment !CommitmentTrigger
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data EssenceModulation = EssenceModulation
  { emAngstCommitmentThreshold    :: !Double
  , emAngstAccrualRate            :: !Double
  , emAngstDecayRate              :: !Double
  , emAngstAccrualDivergenceFloor :: !Double
  , emConatusFloorWindow          :: !Int
  , emConatusStructuralFloor      :: !Double
  , emTrajectoryCapacity          :: !Int
  , emBandLowEdge                 :: !Double
  , emBandHighEdge                :: !Double
  , emValenceLowEdge              :: !Double
  , emValenceHighEdge             :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)
