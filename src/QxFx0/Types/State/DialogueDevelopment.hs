{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

{-| Persistent state for the dialogue-development phase.

The three records below are intentionally separate: knowledge acquisition,
speech adaptation, and belief/stance revision are not interchangeable signals.
-}
module QxFx0.Types.State.DialogueDevelopment
  ( AdaptiveDecisionRecord(..)
  , DialogueOutcomeKind(..)
  , DialogueOutcomeSample(..)
  , DialogueOutcomeLearningState(..)
  , emptyDialogueOutcomeLearningState
  , SpeechPolicyState(..)
  , emptySpeechPolicyState
  , BeliefPolarity(..)
  , BeliefRecord(..)
  , BeliefStore(..)
  , emptyBeliefStore
  , ClaimStanceStore
  , emptyClaimStanceStore
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson
  ( FromJSON(..)
  , ToJSON(..)
  , object
  , withObject
  , (.:)
  , (.:?)
  , (.!=)
  , (.=)
  )
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

import QxFx0.Types.State.AdaptiveMutation
  ( AdaptiveDecision(..)
  , AdaptiveMutationKind(..)
  , AdaptiveMutationRecord(..)
  , EvidenceStrength(..)
  )

data AdaptiveDecisionRecord = AdaptiveDecisionRecord
  { adrTurn :: !Int
  , adrCause :: !Text
  , adrEvidence :: ![Text]
  , adrConfidence :: !Double
  , adrBoundedDelta :: ![Text]
  , adrDecision :: !AdaptiveDecision
  , adrTargets :: ![AdaptiveMutationKind]
  , adrMutationRecords :: ![AdaptiveMutationRecord]
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON AdaptiveDecisionRecord where
  toJSON record = object
    [ "adrTurn" .= adrTurn record
    , "adrCause" .= adrCause record
    , "adrEvidence" .= adrEvidence record
    , "adrConfidence" .= adrConfidence record
    , "adrBoundedDelta" .= adrBoundedDelta record
    , "adrDecision" .= adrDecision record
    , "adrTargets" .= adrTargets record
    , "adrMutationRecords" .= adrMutationRecords record
    ]

instance FromJSON AdaptiveDecisionRecord where
  parseJSON = withObject "AdaptiveDecisionRecord" $ \o -> do
    turn <- o .: "adrTurn"
    cause <- o .: "adrCause"
    evidence <- o .: "adrEvidence"
    confidence <- o .: "adrConfidence"
    boundedDelta <- o .:? "adrBoundedDelta" .!= []
    decision <- o .: "adrDecision"
    targets <- o .: "adrTargets"
    mutationRecords <- o .:? "adrMutationRecords" .!= legacyMutationRecords turn cause evidence confidence boundedDelta decision targets
    pure AdaptiveDecisionRecord
      { adrTurn = turn
      , adrCause = cause
      , adrEvidence = evidence
      , adrConfidence = confidence
      , adrBoundedDelta = boundedDelta
      , adrDecision = decision
      , adrTargets = targets
      , adrMutationRecords = mutationRecords
      }

data DialogueOutcomeKind
  = DialogueOutcomeSuccess
  | DialogueOutcomePartialSuccess
  | DialogueOutcomeRepairRequested
  | DialogueOutcomeRepeatedQuestion
  | DialogueOutcomeConflict
  | DialogueOutcomeDegraded
  | DialogueOutcomeUncertain
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData, FromJSON, ToJSON)

data DialogueOutcomeSample = DialogueOutcomeSample
  { dosTurn :: !Int
  , dosKind :: !DialogueOutcomeKind
  , dosTopic :: !Text
  , dosSignals :: ![Text]
  , dosEvidenceStrength :: !EvidenceStrength
  , dosStrongUpdate :: !Bool
  , dosDecisionRecord :: !AdaptiveDecisionRecord
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON DialogueOutcomeSample where
  toJSON sample = object
    [ "dosTurn" .= dosTurn sample
    , "dosKind" .= dosKind sample
    , "dosTopic" .= dosTopic sample
    , "dosSignals" .= dosSignals sample
    , "dosEvidenceStrength" .= dosEvidenceStrength sample
    , "dosStrongUpdate" .= dosStrongUpdate sample
    , "dosDecisionRecord" .= dosDecisionRecord sample
    ]

instance FromJSON DialogueOutcomeSample where
  parseJSON = withObject "DialogueOutcomeSample" $ \o -> do
    turn <- o .: "dosTurn"
    kind <- o .: "dosKind"
    topic <- o .: "dosTopic"
    signals <- o .: "dosSignals"
    strong <- o .: "dosStrongUpdate"
    strength <- o .:? "dosEvidenceStrength" .!= legacyEvidenceStrength strong
    decision <- o .:? "dosDecisionRecord" .!= legacyAdaptiveDecisionRecord turn kind signals strong strength
    pure DialogueOutcomeSample
      { dosTurn = turn
      , dosKind = kind
      , dosTopic = topic
      , dosSignals = signals
      , dosEvidenceStrength = strength
      , dosStrongUpdate = strong
      , dosDecisionRecord = decision
      }

data DialogueOutcomeLearningState = DialogueOutcomeLearningState
  { dolRecentOutcomes :: ![DialogueOutcomeSample]
  , dolSuccessCount :: !Int
  , dolPartialSuccessCount :: !Int
  , dolRepairRequestCount :: !Int
  , dolRepeatedQuestionCount :: !Int
  , dolConflictCount :: !Int
  , dolDegradedCount :: !Int
  , dolUncertainCount :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

emptyDialogueOutcomeLearningState :: DialogueOutcomeLearningState
emptyDialogueOutcomeLearningState = DialogueOutcomeLearningState
  { dolRecentOutcomes = []
  , dolSuccessCount = 0
  , dolPartialSuccessCount = 0
  , dolRepairRequestCount = 0
  , dolRepeatedQuestionCount = 0
  , dolConflictCount = 0
  , dolDegradedCount = 0
  , dolUncertainCount = 0
  }

data SpeechPolicyState = SpeechPolicyState
  { spsDirectness :: !Double
  , spsCompression :: !Double
  , spsAmbiguityTolerance :: !Double
  , spsRepairBias :: !Double
  , spsSuccessfulPatterns :: !(Map Text Int)
  , spsFailedPatterns :: !(Map Text Int)
  , spsLastUpdatedTurn :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

emptySpeechPolicyState :: SpeechPolicyState
emptySpeechPolicyState = SpeechPolicyState
  { spsDirectness = 0.5
  , spsCompression = 0.5
  , spsAmbiguityTolerance = 0.5
  , spsRepairBias = 0.0
  , spsSuccessfulPatterns = M.empty
  , spsFailedPatterns = M.empty
  , spsLastUpdatedTurn = 0
  }

data BeliefPolarity
  = BeliefAffirmed
  | BeliefTentative
  | BeliefContested
  | BeliefRejected
  | BeliefAmbivalent
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData, FromJSON, ToJSON)

data BeliefRecord = BeliefRecord
  { brClaim :: !Text
  , brPolarity :: !BeliefPolarity
  , brConfidence :: !Double
  , brEvidence :: ![Text]
  , brCounterEvidence :: ![Text]
  , brLastUpdatedTurn :: !Int
  , brRevisionCount :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

-- | Low-level claim stance memory. The legacy 'BeliefStore' name is retained
-- for JSON/API compatibility; prefer the 'ClaimStanceStore' alias in new code.
data BeliefStore = BeliefStore
  { bsClaims :: !(Map Text BeliefRecord)
  , bsRecentRevisions :: ![Text]
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

type ClaimStanceStore = BeliefStore

emptyBeliefStore :: BeliefStore
emptyBeliefStore = BeliefStore
  { bsClaims = M.empty
  , bsRecentRevisions = []
  }

emptyClaimStanceStore :: ClaimStanceStore
emptyClaimStanceStore = emptyBeliefStore

legacyEvidenceStrength :: Bool -> EvidenceStrength
legacyEvidenceStrength strong =
  if strong then EvidenceStrong else EvidenceWeak

legacyAdaptiveDecisionRecord
  :: Int
  -> DialogueOutcomeKind
  -> [Text]
  -> Bool
  -> EvidenceStrength
  -> AdaptiveDecisionRecord
legacyAdaptiveDecisionRecord turn kind signals strong strength = AdaptiveDecisionRecord
  { adrTurn = turn
  , adrCause = "legacy_dialogue_outcome:" <> T.pack (show kind)
  , adrEvidence = signals
  , adrConfidence = legacyConfidence strength
  , adrBoundedDelta = ["recent_outcomes<=12"]
  , adrDecision = if strong then AdaptiveAccepted else AdaptiveObserved
  , adrTargets = legacyTargets kind strong
  , adrMutationRecords = legacyMutationRecords
      turn
      ("legacy_dialogue_outcome:" <> T.pack (show kind))
      signals
      (legacyConfidence strength)
      ["recent_outcomes<=12"]
      (if strong then AdaptiveAccepted else AdaptiveObserved)
      (legacyTargets kind strong)
  }

legacyConfidence :: EvidenceStrength -> Double
legacyConfidence strength =
  case strength of
    EvidenceObservational -> 0.10
    EvidenceWeak -> 0.25
    EvidenceModerate -> 0.50
    EvidenceStrong -> 0.75

legacyTargets :: DialogueOutcomeKind -> Bool -> [AdaptiveMutationKind]
legacyTargets kind strong =
  MutDialogueOutcome :
    if not strong
      then []
      else case kind of
        DialogueOutcomeSuccess -> [MutSpeechPolicy, MutClaimStance]
        DialogueOutcomeConflict -> [MutSpeechPolicy, MutClaimStance]
        DialogueOutcomeRepairRequested -> [MutSpeechPolicy]
        DialogueOutcomeRepeatedQuestion -> [MutSpeechPolicy]
        DialogueOutcomeDegraded -> [MutSpeechPolicy]
        DialogueOutcomePartialSuccess -> []
        DialogueOutcomeUncertain -> []

legacyMutationRecords
  :: Int
  -> Text
  -> [Text]
  -> Double
  -> [Text]
  -> AdaptiveDecision
  -> [AdaptiveMutationKind]
  -> [AdaptiveMutationRecord]
legacyMutationRecords turn cause evidence confidence boundedDelta decision targets =
  map targetRecord targets
  where
    targetRecord target = AdaptiveMutationRecord
      { amrTurnId = turn
      , amrKind = target
      , amrCause = cause
      , amrEvidence = evidence
      , amrEvidenceStrength = evidenceStrengthForDecision decision
      , amrConfidence = confidence
      , amrBoundedDelta = parseBoundedDelta boundedDelta
      , amrDecision = decision
      }

evidenceStrengthForDecision :: AdaptiveDecision -> EvidenceStrength
evidenceStrengthForDecision decision =
  case decision of
    AdaptiveAccepted -> EvidenceStrong
    AdaptivePromoted -> EvidenceStrong
    AdaptiveRolledBack -> EvidenceStrong
    AdaptiveObserved -> EvidenceWeak
    AdaptiveRejected -> EvidenceWeak
    AdaptiveQuarantined -> EvidenceWeak

parseBoundedDelta :: [Text] -> Maybe Double
parseBoundedDelta deltas =
  case deltas of
    [] -> Nothing
    _ -> Just 1.0
