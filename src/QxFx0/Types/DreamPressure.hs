{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

module QxFx0.Types.DreamPressure
  ( DatalogPressureClass(..)
  , DatalogPressure(..)
  , IntuitionPressureClass(..)
  , IntuitionPressure(..)
  , DreamPressureAgreement(..)
  , DreamPressure(..)
  , DreamCandidateKind(..)
  , DreamCorrectionCandidate(..)
  , DreamCandidateDecisionReason(..)
  , DreamCandidateDecision(..)
  , DreamCandidateEnvelope(..)
  , AcceptedDreamCandidate(..)
  , RejectedDreamCandidate(..)
  , QuarantinedDreamCandidate(..)
  , DreamOutcome(..)
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson
  ( FromJSON(parseJSON)
  , ToJSON(toJSON)
  , Value(Object, String)
  , object
  , (.:)
  , (.=)
  )
import Data.Text (Text)
import GHC.Generics (Generic)
import Data.Aeson.Types (Parser)

import QxFx0.Types.Decision (ShadowStatus)
import QxFx0.Types.Domain (CanonicalMoveFamily)
import QxFx0.Types.Intuition (FlashTrigger)
import QxFx0.Types.ShadowDivergence (ShadowDivergenceKind, ShadowDivergenceSeverity, ShadowSnapshotId)
import QxFx0.Types.Vec (CoreVec)

data DatalogPressureClass
  = DPNoPressure
  | DPUnavailableOnly
  | DPAdvisoryMismatch
  | DPAlternativeFamilyPressure
  | DPSafetyPressure
  | DPContractPressure
  | DPGateEscalation
  deriving stock (Eq, Show, Read, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data DatalogPressure = DatalogPressure
  { dpClass :: !DatalogPressureClass
  , dpRequestedFamily :: !CanonicalMoveFamily
  , dpShadowFamily :: !(Maybe CanonicalMoveFamily)
  , dpSnapshotId :: !(Maybe ShadowSnapshotId)
  , dpStrength :: !Double
  , dpDiagnostics :: ![Text]
  , dpDivergenceKind :: !ShadowDivergenceKind
  , dpSeverity :: !ShadowDivergenceSeverity
  , dpGateTriggered :: !Bool
  , dpLegitimacyDeficit :: !Double
  , dpShadowStatus :: !ShadowStatus
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

data IntuitionPressureClass
  = IntuitionPressureNone
  | IntuitionPressurePosterior
  | IntuitionPressureFlash
  | IntuitionPressureFlashOverride
  deriving stock (Eq, Show, Read, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data IntuitionPressure = IntuitionPressure
  { inpClass :: !IntuitionPressureClass
  , inpStrength :: !Double
  , inpPosterior :: !Double
  , inpDirective :: !(Maybe Text)
  , inpTrigger :: !(Maybe FlashTrigger)
  , inpOverridesAll :: !Bool
  , inpReasonTags :: ![Text]
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

data DreamPressureAgreement
  = DreamPressureNone
  | DreamPressureConvergent
  | DreamPressureDatalogDominant
  | DreamPressureIntuitionDominant
  | DreamPressureConflict
  deriving stock (Eq, Show, Read, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data DreamPressure = DreamPressure
  { drpAgreement :: !DreamPressureAgreement
  , drpStrength :: !Double
  , drpBias :: !CoreVec
  , drpSuggestedFamily :: !(Maybe CanonicalMoveFamily)
  , drpReasonTags :: ![Text]
  , drpCandidateThreshold :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

data DreamCandidateKind
  = DckGraphBias
  | DckSymbolic
  | DckAffective
  | DckConflict
  | DckNone
  deriving stock (Eq, Ord, Show, Read, Generic)

instance NFData DreamCandidateKind

instance FromJSON DreamCandidateKind where
  parseJSON (String t) =
    case t of
      "graph_bias" -> pure DckGraphBias
      "symbolic" -> pure DckSymbolic
      "affective" -> pure DckAffective
      "conflict" -> pure DckConflict
      "none" -> pure DckNone
      other -> parserFailure ("unknown DreamCandidateKind string: " <> show other)
  parseJSON (Object o) = do
    tag <- o .: "tag"
    case tag of
      "DckGraphBias" -> pure DckGraphBias
      "DckSymbolic" -> pure DckSymbolic
      "DckAffective" -> pure DckAffective
      "DckConflict" -> pure DckConflict
      "DckNone" -> pure DckNone
      other -> parserFailure ("unknown DreamCandidateKind tag: " <> show (other :: Text))
  parseJSON _ = parserFailure "DreamCandidateKind expects a string or an object with a 'tag' field"

instance ToJSON DreamCandidateKind where
  toJSON k = object ["tag" .= show k]

parserFailure :: String -> Parser a
parserFailure = fail

data DreamCorrectionCandidate = DreamCorrectionCandidate
  { dccLabel :: !Text
  , dccKind :: !DreamCandidateKind
  , dccStrength :: !Double
  , dccSuggestedFamily :: !(Maybe CanonicalMoveFamily)
  , dccReasonTags :: ![Text]
  , dccAdvisoryOnly :: !Bool
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

data DreamCandidateDecisionReason
  = DCDRNoPressure
  | DCDRUnavailableOnly
  | DCDRAdvisoryMismatchOnly
  | DCDRAlternativeFamilyPressure
  | DCDRConflictAgreement
  | DCDRSymbolicOnlyAgreement
  | DCDRAffectiveOnlyAgreement
  | DCDRNoneCandidateObservedOnly
  | DCDRSymbolicCandidateObservedOnly
  | DCDRAffectiveCandidateObservedOnly
  | DCDRConflictCandidateObservedOnly
  | DCDRUnsupportedCandidateKind
  | DCDRAcceptedSafetyGraphBias
  | DCDRAcceptedContractGraphBias
  | DCDRAcceptedGateEscalationGraphBias
  | DCDRThresholdNotReached
  deriving stock (Eq, Show, Read, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data DreamCandidateEnvelope = DreamCandidateEnvelope
  { dceCandidate :: !DreamCorrectionCandidate
  , dceDatalogClass :: !DatalogPressureClass
  , dceIntuitionClass :: !IntuitionPressureClass
  , dceAgreement :: !DreamPressureAgreement
  , dceUnifiedStrength :: !Double
  , dceThresholdFired :: !Bool
  , dceBias :: !CoreVec
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

data AcceptedDreamCandidate = AcceptedDreamCandidate
  { adcEnvelope :: !DreamCandidateEnvelope
  , adcReason :: !DreamCandidateDecisionReason
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

data RejectedDreamCandidate = RejectedDreamCandidate
  { rdcEnvelope :: !DreamCandidateEnvelope
  , rdcReason :: !DreamCandidateDecisionReason
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

data QuarantinedDreamCandidate = QuarantinedDreamCandidate
  { qdcEnvelope :: !DreamCandidateEnvelope
  , qdcReason :: !DreamCandidateDecisionReason
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)

data DreamCandidateDecision
  = DreamCandidateAccepted !AcceptedDreamCandidate
  | DreamCandidateRejected !RejectedDreamCandidate
  | DreamCandidateQuarantined !QuarantinedDreamCandidate
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data DreamOutcome = DreamOutcome
  { doDatalogPressure :: !DatalogPressure
  , doIntuitionPressure :: !IntuitionPressure
  , doDreamPressure :: !DreamPressure
  , doBias :: !CoreVec
  , doCorrectionCandidates :: ![DreamCorrectionCandidate]
  , doCandidateDecisions :: ![DreamCandidateDecision]
  , doAppliedBias :: !CoreVec
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, FromJSON, ToJSON)
