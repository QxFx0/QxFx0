{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Admission.PropositionExploratoryPromptAdmission
  ( admitPropositionExploratoryPromptTriggers
  ) where

import QxFx0.Types.TruthContract (truthContractIsAuthoritative)
import QxFx0.Types.PropositionExploratoryPromptAdmission

-- | Constitution-aware admission for proposition exploratory-prompt raw
-- trigger decisions.
--
-- Under an authoritative truth-contract contour, raw triggers pass through
-- unchanged and the decision is @PpeptdAdmitRaw@.
--
-- Under a non-authoritative (weakened) contour every matched raw trigger is
-- softened to @rpeptMatched = False@ before reaching
-- @buildExploratoryPromptFromTriggers@; the decision is
-- @PpeptdSuppressStrongTriggers@.  Exploratory-prompt has no "guard"-class
-- trigger to preserve (unlike location-formation's @mental_noun_guard@):
-- every raw trigger here is a strong direct keyword-infix match, so the
-- non-authoritative contour suppresses all of them uniformly.
admitPropositionExploratoryPromptTriggers
  :: PropositionExploratoryPromptAdmissionInput
  -> [RawPropositionExploratoryPromptTrigger]
  -> AdmittedPropositionExploratoryPromptTriggers
admitPropositionExploratoryPromptTriggers input rawTriggers
  | truthContractIsAuthoritative (peptaiTruthContractStatus input) =
      AdmittedPropositionExploratoryPromptTriggers rawTriggers rawTriggers PpeptdAdmitRaw
  | otherwise =
      AdmittedPropositionExploratoryPromptTriggers
        rawTriggers
        (map softenTrigger rawTriggers)
        PpeptdSuppressStrongTriggers

softenTrigger :: RawPropositionExploratoryPromptTrigger -> RawPropositionExploratoryPromptTrigger
softenTrigger rawTrigger
  | not (rpeptMatched rawTrigger) = rawTrigger
  | otherwise = rawTrigger { rpeptMatched = False }
