{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Admission.PropositionDialogueInvitationAdmission
  ( admitPropositionDialogueInvitationTriggers
  ) where

import QxFx0.Types.TruthContract (truthContractIsAuthoritative)
import QxFx0.Types.PropositionAdmissionTypes

admitPropositionDialogueInvitationTriggers
  :: PropositionAdmissionInput
  -> [RawPropositionTrigger]
  -> AdmittedPropositionTriggers
admitPropositionDialogueInvitationTriggers input rawTriggers
  | truthContractIsAuthoritative (paiTruthContractStatus input) =
      AdmittedPropositionTriggers rawTriggers rawTriggers PadAdmitRaw
  | otherwise =
      AdmittedPropositionTriggers
        rawTriggers
        (map softenTrigger rawTriggers)
        PadSuppressStrongTriggers

softenTrigger :: RawPropositionTrigger -> RawPropositionTrigger
softenTrigger rawTrigger
  | rptMatched rawTrigger = rawTrigger { rptMatched = False }
  | otherwise = rawTrigger
