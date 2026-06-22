{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Admission.PropositionExploratoryPromptAdmission
  ( admitPropositionExploratoryPromptTriggers
  ) where

import QxFx0.Types.TruthContract (truthContractIsAuthoritative)
import QxFx0.Types.PropositionAdmissionTypes

-- | Constitution-aware admission for proposition exploratory-prompt raw
-- trigger decisions.
--
-- Under an authoritative truth-contract contour, raw triggers pass through
-- unchanged and the decision is @PadAdmitRaw@.
--
-- Under a non-authoritative (weakened) contour every matched raw trigger is
-- softened to @rptMatched = False@ before reaching
-- @buildExploratoryPromptFromTriggers@; the decision is
-- @PadSuppressStrongTriggers@.  Exploratory-prompt has no "guard"-class
-- trigger to preserve (unlike location-formation's @mental_noun_guard@):
-- every raw trigger here is a strong direct keyword-infix match, so the
-- non-authoritative contour suppresses all of them uniformly.
admitPropositionExploratoryPromptTriggers
  :: PropositionAdmissionInput
  -> [RawPropositionTrigger]
  -> AdmittedPropositionTriggers
admitPropositionExploratoryPromptTriggers input rawTriggers
  | truthContractIsAuthoritative (paiTruthContractStatus input) =
      AdmittedPropositionTriggers rawTriggers rawTriggers PadAdmitRaw
  | otherwise =
      AdmittedPropositionTriggers
        rawTriggers
        (map softenTrigger rawTriggers)
        PadSuppressStrongTriggers

softenTrigger :: RawPropositionTrigger -> RawPropositionTrigger
softenTrigger rawTrigger
  | not (rptMatched rawTrigger) = rawTrigger
  | otherwise = rawTrigger { rptMatched = False }
