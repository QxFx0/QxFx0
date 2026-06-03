{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Types.PropositionFallbackAdmission
  ( PropositionPhraseDecisionAdmissionInput(..)
  , PropositionPhraseDecisionAdmissionDecision(..)
  , PropositionFallbackType(..)
  , RawPropositionPhraseDecision(..)
  , AdmittedPropositionPhraseDecisions(..)
  , RawPropositionKeywordFallbackDecision(..)
  ) where

import Data.Text (Text)
import QxFx0.Types (TruthContractStatus)

data PropositionPhraseDecisionAdmissionInput = PropositionPhraseDecisionAdmissionInput
  { ppdaiTruthContractStatus :: !TruthContractStatus
  } deriving stock (Eq, Show)

data PropositionPhraseDecisionAdmissionDecision
  = PpddAdmitRaw
  | PpddPreserveAmbiguous
  | PpddSuppressStrongDecisions
  deriving stock (Eq, Show)

data PropositionFallbackType
  = PfDefinitionalQ
  | PfDistinctionQ
  | PfGroundQ
  | PfReflectiveQ
  | PfSelfDescQ
  | PfPurposeQ
  | PfHypotheticalQ
  | PfRepairSignal
  | PfContactSignal
  | PfAnchorSignal
  | PfClarifyQ
  | PfDeepenQ
  | PfConfrontQ
  | PfNextStepQ
  | PfAffectiveQ
  | PfEpistemicQ
  | PfRequestQ
  | PfEvaluationQ
  | PfNarrativeQ
  | PfOperationalStatusQ
  | PfOperationalCauseQ
  | PfSystemLogicQ
  | PfSelfKnowledgeQ
  | PfDialogueInvitationQ
  | PfConceptKnowledgeQ
  | PfWorldCauseQ
  | PfLocationFormationQ
  | PfSelfStateQ
  | PfComparisonPlausibilityQ
  | PfMisunderstandingReport
  | PfGenerativePrompt
  | PfContemplativeTopic
  | PfExploratoryPrompt
  deriving stock (Eq, Ord, Show, Read, Bounded, Enum)

data RawPropositionPhraseDecision = RawPropositionPhraseDecision
  { rppdPropositionType :: !PropositionFallbackType
  , rppdPhrase :: !Text
  , rppdMatched :: !Bool
  } deriving stock (Eq, Show)

data AdmittedPropositionPhraseDecisions = AdmittedPropositionPhraseDecisions
  { appdRawDecisions :: ![RawPropositionPhraseDecision]
  , appdDecisions :: ![RawPropositionPhraseDecision]
  , appdDecision :: !PropositionPhraseDecisionAdmissionDecision
  } deriving stock (Eq, Show)

data RawPropositionKeywordFallbackDecision = RawPropositionKeywordFallbackDecision
  { rpkfdPropositionType :: !PropositionFallbackType
  , rpkfdMatchedPhrases :: ![Text]
  } deriving stock (Eq, Show)
