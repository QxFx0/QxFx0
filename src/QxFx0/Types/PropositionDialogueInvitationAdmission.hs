{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Types.PropositionDialogueInvitationAdmission
  ( PropositionDialogueInvitationAdmissionInput(..)
  , PropositionDialogueInvitationAdmissionDecision(..)
  , RawPropositionDialogueInvitationTrigger(..)
  , AdmittedPropositionDialogueInvitationTriggers(..)
  ) where

import Data.Text (Text)
import QxFx0.Types (TruthContractStatus)

data PropositionDialogueInvitationAdmissionInput = PropositionDialogueInvitationAdmissionInput
  { pdiaiTruthContractStatus :: !TruthContractStatus
  } deriving stock (Eq, Show)

data PropositionDialogueInvitationAdmissionDecision
  = PpdiadAdmitRaw
  | PpdiadSuppressStrongTriggers
  deriving stock (Eq, Show)

data RawPropositionDialogueInvitationTrigger = RawPropositionDialogueInvitationTrigger
  { rpdiLabel :: !Text
  , rpdiMatched :: !Bool
  } deriving stock (Eq, Show)

data AdmittedPropositionDialogueInvitationTriggers = AdmittedPropositionDialogueInvitationTriggers
  { apdiRawTriggers :: ![RawPropositionDialogueInvitationTrigger]
  , apdiTriggers :: ![RawPropositionDialogueInvitationTrigger]
  , apdiDecision :: !PropositionDialogueInvitationAdmissionDecision
  } deriving stock (Eq, Show)
