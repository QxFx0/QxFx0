{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

{-| Typed adaptive mutation records shared by all self-change contours. -}
module QxFx0.Types.State.AdaptiveMutation
  ( EvidenceStrength(..)
  , AdaptiveDecision(..)
  , AdaptiveMutationKind(..)
  , AdaptiveMutationRecord(..)
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON(..), ToJSON(..), Value(String), withText)
import Data.Aeson.Types (Parser)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

data EvidenceStrength
  = EvidenceObservational
  | EvidenceWeak
  | EvidenceModerate
  | EvidenceStrong
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData)

instance ToJSON EvidenceStrength where
  toJSON = String . renderEvidenceStrength

instance FromJSON EvidenceStrength where
  parseJSON = withText "EvidenceStrength" parseEvidenceStrengthText

data AdaptiveDecision
  = AdaptiveObserved
  | AdaptiveRejected
  | AdaptiveQuarantined
  | AdaptiveAccepted
  | AdaptivePromoted
  | AdaptiveRolledBack
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData)

instance ToJSON AdaptiveDecision where
  toJSON = String . renderAdaptiveDecision

instance FromJSON AdaptiveDecision where
  parseJSON = withText "AdaptiveDecision" parseAdaptiveDecisionText

data AdaptiveMutationKind
  = MutDialogueOutcome
  | MutSpeechPolicy
  | MutClaimStance
  | MutKnowledgeTree
  | MutToolReliability
  | MutCalibration
  | MutSalienceWeights
  | MutFieldHeuristics
  | MutPerspective
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData)

instance ToJSON AdaptiveMutationKind where
  toJSON = String . renderAdaptiveMutationKind

instance FromJSON AdaptiveMutationKind where
  parseJSON = withText "AdaptiveMutationKind" parseAdaptiveMutationKindText

data AdaptiveMutationRecord = AdaptiveMutationRecord
  { amrTurnId :: !Int
  , amrKind :: !AdaptiveMutationKind
  , amrCause :: !Text
  , amrEvidence :: ![Text]
  , amrEvidenceStrength :: !EvidenceStrength
  , amrConfidence :: !Double
  , amrBoundedDelta :: !(Maybe Double)
  , amrDecision :: !AdaptiveDecision
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

renderEvidenceStrength :: EvidenceStrength -> Text
renderEvidenceStrength strength =
  case strength of
    EvidenceObservational -> "EvidenceObservational"
    EvidenceWeak -> "EvidenceWeak"
    EvidenceModerate -> "EvidenceModerate"
    EvidenceStrong -> "EvidenceStrong"

parseEvidenceStrengthText :: Text -> Parser EvidenceStrength
parseEvidenceStrengthText text =
  case text of
    "EvidenceObservational" -> pure EvidenceObservational
    "EvidenceWeak" -> pure EvidenceWeak
    "EvidenceModerate" -> pure EvidenceModerate
    "EvidenceStrong" -> pure EvidenceStrong
    "AdaptiveEvidenceWeak" -> pure EvidenceWeak
    "AdaptiveEvidenceModerate" -> pure EvidenceModerate
    "AdaptiveEvidenceStrong" -> pure EvidenceStrong
    _ -> failUnknown "EvidenceStrength" text

renderAdaptiveDecision :: AdaptiveDecision -> Text
renderAdaptiveDecision decision =
  case decision of
    AdaptiveObserved -> "AdaptiveObserved"
    AdaptiveRejected -> "AdaptiveRejected"
    AdaptiveQuarantined -> "AdaptiveQuarantined"
    AdaptiveAccepted -> "AdaptiveAccepted"
    AdaptivePromoted -> "AdaptivePromoted"
    AdaptiveRolledBack -> "AdaptiveRolledBack"

parseAdaptiveDecisionText :: Text -> Parser AdaptiveDecision
parseAdaptiveDecisionText text =
  case text of
    "AdaptiveObserved" -> pure AdaptiveObserved
    "AdaptiveRejected" -> pure AdaptiveRejected
    "AdaptiveQuarantined" -> pure AdaptiveQuarantined
    "AdaptiveAccepted" -> pure AdaptiveAccepted
    "AdaptivePromoted" -> pure AdaptivePromoted
    "AdaptiveRolledBack" -> pure AdaptiveRolledBack
    "AdaptiveRecordOnly" -> pure AdaptiveObserved
    "AdaptiveApplyBoundedMutation" -> pure AdaptiveAccepted
    "AdaptiveQuarantineMutation" -> pure AdaptiveQuarantined
    _ -> failUnknown "AdaptiveDecision" text

renderAdaptiveMutationKind :: AdaptiveMutationKind -> Text
renderAdaptiveMutationKind kind =
  case kind of
    MutDialogueOutcome -> "MutDialogueOutcome"
    MutSpeechPolicy -> "MutSpeechPolicy"
    MutClaimStance -> "MutClaimStance"
    MutKnowledgeTree -> "MutKnowledgeTree"
    MutToolReliability -> "MutToolReliability"
    MutCalibration -> "MutCalibration"
    MutSalienceWeights -> "MutSalienceWeights"
    MutFieldHeuristics -> "MutFieldHeuristics"
    MutPerspective -> "MutPerspective"

parseAdaptiveMutationKindText :: Text -> Parser AdaptiveMutationKind
parseAdaptiveMutationKindText text =
  case text of
    "MutDialogueOutcome" -> pure MutDialogueOutcome
    "MutSpeechPolicy" -> pure MutSpeechPolicy
    "MutClaimStance" -> pure MutClaimStance
    "MutKnowledgeTree" -> pure MutKnowledgeTree
    "MutToolReliability" -> pure MutToolReliability
    "MutCalibration" -> pure MutCalibration
    "MutSalienceWeights" -> pure MutSalienceWeights
    "MutFieldHeuristics" -> pure MutFieldHeuristics
    "MutPerspective" -> pure MutPerspective
    "AdaptiveTargetDialogueOutcome" -> pure MutDialogueOutcome
    "AdaptiveTargetSpeechPolicy" -> pure MutSpeechPolicy
    "AdaptiveTargetClaimStance" -> pure MutClaimStance
    _ -> failUnknown "AdaptiveMutationKind" text

failUnknown :: Text -> Text -> Parser a
failUnknown label text =
  fail (T.unpack ("unknown " <> label <> ": " <> text))
