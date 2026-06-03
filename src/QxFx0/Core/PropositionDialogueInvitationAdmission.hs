{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Core.PropositionDialogueInvitationAdmission
  ( admitPropositionDialogueInvitationTriggers
  ) where

import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Types.PropositionDialogueInvitationAdmission

admitPropositionDialogueInvitationTriggers
  :: PropositionDialogueInvitationAdmissionInput
  -> [RawPropositionDialogueInvitationTrigger]
  -> AdmittedPropositionDialogueInvitationTriggers
admitPropositionDialogueInvitationTriggers input rawTriggers
  | truthContractIsAuthoritative (pdiaiTruthContractStatus input) =
      AdmittedPropositionDialogueInvitationTriggers rawTriggers rawTriggers PpdiadAdmitRaw
  | otherwise =
      AdmittedPropositionDialogueInvitationTriggers
        rawTriggers
        (map softenTrigger rawTriggers)
        PpdiadSuppressStrongTriggers

softenTrigger :: RawPropositionDialogueInvitationTrigger -> RawPropositionDialogueInvitationTrigger
softenTrigger rawTrigger
  | rpdiMatched rawTrigger = rawTrigger { rpdiMatched = False }
  | otherwise = rawTrigger
