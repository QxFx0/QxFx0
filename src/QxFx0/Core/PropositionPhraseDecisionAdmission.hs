{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Core.PropositionPhraseDecisionAdmission
  ( PropositionPhraseDecisionAdmissionInput(..)
  , PropositionPhraseDecisionAdmissionDecision(..)
  , RawPropositionPhraseDecision(..)
  , AdmittedPropositionPhraseDecisions(..)
  , admitPropositionPhraseDecisions
  ) where

import Data.Text (Text)
import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Types
import QxFx0.Types.PropositionFallbackAdmission
  ( PropositionPhraseDecisionAdmissionInput(..)
  , PropositionPhraseDecisionAdmissionDecision(..)
  , PropositionFallbackType(..)
  , RawPropositionPhraseDecision(..)
  , AdmittedPropositionPhraseDecisions(..)
  )

admitPropositionPhraseDecisions
  :: PropositionPhraseDecisionAdmissionInput
  -> [RawPropositionPhraseDecision]
  -> AdmittedPropositionPhraseDecisions
admitPropositionPhraseDecisions input rawDecisions
  | truthContractIsAuthoritative (ppdaiTruthContractStatus input) =
      AdmittedPropositionPhraseDecisions rawDecisions rawDecisions PpddAdmitRaw
  | all propositionDecisionAlreadySafe rawDecisions =
      AdmittedPropositionPhraseDecisions rawDecisions rawDecisions PpddPreserveAmbiguous
  | otherwise =
      AdmittedPropositionPhraseDecisions
        rawDecisions
        (map softenDecision rawDecisions)
        PpddSuppressStrongDecisions

propositionDecisionAlreadySafe :: RawPropositionPhraseDecision -> Bool
propositionDecisionAlreadySafe rawDecision =
  not (rppdMatched rawDecision) || propositionTypeAlreadySafe (rppdPropositionType rawDecision)

softenDecision :: RawPropositionPhraseDecision -> RawPropositionPhraseDecision
softenDecision rawDecision
  | propositionDecisionAlreadySafe rawDecision = rawDecision
  | otherwise = rawDecision { rppdMatched = False }

propositionTypeAlreadySafe :: PropositionFallbackType -> Bool
propositionTypeAlreadySafe propositionType =
  propositionType `elem`
    [ PfContactSignal
    , PfAnchorSignal
    , PfClarifyQ
    , PfDeepenQ
    ]
