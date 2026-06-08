{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Admission.PropositionGenerativePromptAdmission
  ( admitPropositionGenerativePromptTriggers
  ) where

import QxFx0.Types.TruthContract (truthContractIsAuthoritative)
import QxFx0.Types.PropositionGenerativePromptAdmission

admitPropositionGenerativePromptTriggers
  :: PropositionGenerativePromptAdmissionInput
  -> [RawPropositionGenerativePromptTrigger]
  -> AdmittedPropositionGenerativePromptTriggers
admitPropositionGenerativePromptTriggers input rawTriggers
  | truthContractIsAuthoritative (pgpaiTruthContractStatus input) =
      AdmittedPropositionGenerativePromptTriggers rawTriggers rawTriggers PpgpdAdmitRaw
  | otherwise =
      AdmittedPropositionGenerativePromptTriggers
        rawTriggers
        (map softenTrigger rawTriggers)
        PpgpdSuppressStrongTriggers

softenTrigger :: RawPropositionGenerativePromptTrigger -> RawPropositionGenerativePromptTrigger
softenTrigger rawTrigger
  | rpgpMatched rawTrigger = rawTrigger { rpgpMatched = False }
  | otherwise = rawTrigger
