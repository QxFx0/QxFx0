{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-| Core types for proposition classification.

This module contains the PropositionType data type and conversion functions
between PropositionType and other type representations.
-}
module QxFx0.Semantic.Proposition.Types
  ( PropositionType(..)
  , propositionTypeText
  , propositionTypeFromText
  , propositionToFamily
  , diagnosticPropositionFamily
  , diagnosticPropositionFamilyTyped
  , toFallbackType
  , fromFallbackType
  ) where

import QxFx0.Types.PropositionType
  ( PropositionType(..)
  , propositionTypeText
  , propositionTypeFromText
  )
import QxFx0.Types
  ( CanonicalMoveFamily(..)
  )
import QxFx0.Types.PropositionFallbackAdmission
  ( PropositionFallbackType(..)
  )
import Data.Text (Text)

-- | Convert a PropositionType to its corresponding CanonicalMoveFamily.
propositionToFamily :: PropositionType -> CanonicalMoveFamily
propositionToFamily DefinitionalQ  = CMDefine
propositionToFamily DistinctionQ   = CMDistinguish
propositionToFamily GroundQ        = CMGround
propositionToFamily ReflectiveQ    = CMReflect
propositionToFamily SelfDescQ      = CMDescribe
propositionToFamily PurposeQ       = CMPurpose
propositionToFamily HypotheticalQ  = CMHypothesis
propositionToFamily RepairSignal   = CMRepair
propositionToFamily ContactSignal  = CMContact
propositionToFamily AnchorSignal   = CMAnchor
propositionToFamily ClarifyQ       = CMClarify
propositionToFamily DeepenQ        = CMDeepen
propositionToFamily ConfrontQ      = CMConfront
propositionToFamily NextStepQ      = CMNextStep
propositionToFamily PlainAssert    = CMGround
propositionToFamily AffectiveQ     = CMContact
propositionToFamily EpistemicQ     = CMClarify
propositionToFamily RequestQ       = CMClarify
propositionToFamily EvaluationQ    = CMDistinguish
propositionToFamily NarrativeQ     = CMDescribe
propositionToFamily OperationalStatusQ = CMClarify
propositionToFamily OperationalCauseQ = CMGround
propositionToFamily SystemLogicQ   = CMDescribe
propositionToFamily SelfKnowledgeQ = CMDescribe
propositionToFamily DialogueInvitationQ = CMDeepen
propositionToFamily ConceptKnowledgeQ = CMDefine
propositionToFamily WorldCauseQ    = CMGround
propositionToFamily LocationFormationQ = CMGround
propositionToFamily SelfStateQ = CMDescribe
propositionToFamily ComparisonPlausibilityQ = CMDistinguish
propositionToFamily MisunderstandingReport = CMRepair
propositionToFamily GenerativePrompt = CMDescribe
propositionToFamily ContemplativeTopic = CMDeepen
propositionToFamily ExploratoryPrompt = CMDescribe

-- | Get the canonical move family for diagnostic proposition types.
-- Returns Nothing for non-diagnostic types.
diagnosticPropositionFamily :: Text -> Maybe CanonicalMoveFamily
diagnosticPropositionFamily rawType =
  case propositionTypeFromText rawType of
    Just pt -> diagnosticPropositionFamilyTyped pt
    Nothing -> Nothing

-- | Typed version: works directly on PropositionType.
diagnosticPropositionFamilyTyped :: PropositionType -> Maybe CanonicalMoveFamily
diagnosticPropositionFamilyTyped OperationalStatusQ = Just CMClarify
diagnosticPropositionFamilyTyped OperationalCauseQ = Just CMGround
diagnosticPropositionFamilyTyped SystemLogicQ = Just CMDescribe
diagnosticPropositionFamilyTyped SelfKnowledgeQ = Just CMDescribe
diagnosticPropositionFamilyTyped DialogueInvitationQ = Just CMDeepen
diagnosticPropositionFamilyTyped ConceptKnowledgeQ = Just CMDefine
diagnosticPropositionFamilyTyped WorldCauseQ = Just CMGround
diagnosticPropositionFamilyTyped LocationFormationQ = Just CMGround
diagnosticPropositionFamilyTyped SelfStateQ = Just CMDescribe
diagnosticPropositionFamilyTyped ComparisonPlausibilityQ = Just CMDistinguish
diagnosticPropositionFamilyTyped DistinctionQ = Just CMDistinguish
diagnosticPropositionFamilyTyped MisunderstandingReport = Just CMRepair
diagnosticPropositionFamilyTyped GenerativePrompt = Just CMDescribe
diagnosticPropositionFamilyTyped ContemplativeTopic = Just CMDeepen
diagnosticPropositionFamilyTyped _ = Nothing

-- | Convert PropositionType to PropositionFallbackType for keyword-based fallback detection.
toFallbackType :: PropositionType -> PropositionFallbackType
toFallbackType propositionType =
  case propositionType of
    DefinitionalQ -> PfDefinitionalQ
    DistinctionQ -> PfDistinctionQ
    GroundQ -> PfGroundQ
    ReflectiveQ -> PfReflectiveQ
    SelfDescQ -> PfSelfDescQ
    PurposeQ -> PfPurposeQ
    HypotheticalQ -> PfHypotheticalQ
    RepairSignal -> PfRepairSignal
    ContactSignal -> PfContactSignal
    AnchorSignal -> PfAnchorSignal
    ClarifyQ -> PfClarifyQ
    DeepenQ -> PfDeepenQ
    ConfrontQ -> PfConfrontQ
    NextStepQ -> PfNextStepQ
    AffectiveQ -> PfAffectiveQ
    EpistemicQ -> PfEpistemicQ
    RequestQ -> PfRequestQ
    EvaluationQ -> PfEvaluationQ
    NarrativeQ -> PfNarrativeQ
    OperationalStatusQ -> PfOperationalStatusQ
    OperationalCauseQ -> PfOperationalCauseQ
    SystemLogicQ -> PfSystemLogicQ
    SelfKnowledgeQ -> PfSelfKnowledgeQ
    DialogueInvitationQ -> PfDialogueInvitationQ
    ConceptKnowledgeQ -> PfConceptKnowledgeQ
    WorldCauseQ -> PfWorldCauseQ
    LocationFormationQ -> PfLocationFormationQ
    SelfStateQ -> PfSelfStateQ
    ComparisonPlausibilityQ -> PfComparisonPlausibilityQ
    MisunderstandingReport -> PfMisunderstandingReport
    GenerativePrompt -> PfGenerativePrompt
    ContemplativeTopic -> PfContemplativeTopic
    ExploratoryPrompt -> PfExploratoryPrompt
    PlainAssert -> PfGroundQ

-- | Convert PropositionFallbackType back to PropositionType.
fromFallbackType :: PropositionFallbackType -> PropositionType
fromFallbackType fallbackType =
  case fallbackType of
    PfDefinitionalQ -> DefinitionalQ
    PfDistinctionQ -> DistinctionQ
    PfGroundQ -> GroundQ
    PfReflectiveQ -> ReflectiveQ
    PfSelfDescQ -> SelfDescQ
    PfPurposeQ -> PurposeQ
    PfHypotheticalQ -> HypotheticalQ
    PfRepairSignal -> RepairSignal
    PfContactSignal -> ContactSignal
    PfAnchorSignal -> AnchorSignal
    PfClarifyQ -> ClarifyQ
    PfDeepenQ -> DeepenQ
    PfConfrontQ -> ConfrontQ
    PfNextStepQ -> NextStepQ
    PfAffectiveQ -> AffectiveQ
    PfEpistemicQ -> EpistemicQ
    PfRequestQ -> RequestQ
    PfEvaluationQ -> EvaluationQ
    PfNarrativeQ -> NarrativeQ
    PfOperationalStatusQ -> OperationalStatusQ
    PfOperationalCauseQ -> OperationalCauseQ
    PfSystemLogicQ -> SystemLogicQ
    PfSelfKnowledgeQ -> SelfKnowledgeQ
    PfDialogueInvitationQ -> DialogueInvitationQ
    PfConceptKnowledgeQ -> ConceptKnowledgeQ
    PfWorldCauseQ -> WorldCauseQ
    PfLocationFormationQ -> LocationFormationQ
    PfSelfStateQ -> SelfStateQ
    PfComparisonPlausibilityQ -> ComparisonPlausibilityQ
    PfMisunderstandingReport -> MisunderstandingReport
    PfGenerativePrompt -> GenerativePrompt
    PfContemplativeTopic -> ContemplativeTopic
    PfExploratoryPrompt -> ExploratoryPrompt

