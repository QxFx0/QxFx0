{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Admission.PropositionGenerativePromptAdmission
  ( admitPropositionGenerativePromptTriggers
  ) where

import QxFx0.Types.TruthContract (truthContractIsAuthoritative)
import QxFx0.Types.PropositionAdmissionTypes

admitPropositionGenerativePromptTriggers
  :: PropositionAdmissionInput
  -> [RawPropositionTrigger]
  -> AdmittedPropositionTriggers
admitPropositionGenerativePromptTriggers input rawTriggers
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
