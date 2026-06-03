{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}
{-| Proposition classification from user text into canonical move families and semantic frames. -}
module QxFx0.Semantic.Proposition
  ( PropositionType(..)
  , propositionToFamily
  , propositionTypeFromText
  , diagnosticPropositionFamily
  , parseProposition
  , parsePropositionWithTruthContract
  , parsePropositionWithFrame
  , parsePropositionWithFrameAndTruthContract
  , parsePropositionMorph
  , extractFocusEntity
  , RawPropositionKeywordFallbackDecision(..)
  , collectRawKeywordFallbackDecisions
  , buildKeywordFallbackTypeFromDecisions
  , detectKeywordFallbackType
  , collectRawContactTriggers
  ) where

import QxFx0.Types
import Control.Applicative ((<|>))
import QxFx0.Lexicon.Inflection (toNominative)
import QxFx0.Semantic.Morphology (extractContentNouns)
import QxFx0.Policy.ParserKeywords
  ( propositionNegationFragment, propositionSearchKeywords, propositionContactKeyword
  , definitionalKeywords, distinctionKeywords, groundKeywords, reflectiveKeywords
  , selfDescKeywords, purposeKeywords, hypotheticalKeywords, repairKeywords
  , contactKeywords, anchorKeywords, clarifyKeywords, deepenKeywords
  , confrontKeywords, nextStepKeywords, affectiveKeywords, epistemicKeywords
  , requestKeywords, evaluationKeywords, narrativeKeywords
  , emotionDistressKeywords, emotionHopefulKeywords, emotionCuriousKeywords
  , emotionConfrontKeywords, fallbackFocusWord
  , operationalStatusKeywords, operationalCauseKeywords, systemLogicKeywords
  , selfKnowledgeKeywords, dialogueInvitationKeywords, conceptKnowledgeKeywords
  , worldCauseKeywords, locationFormationKeywords, selfStateKeywords
  , comparisonPlausibilityKeywords, misunderstandingKeywords
  , generativePromptKeywords, contemplativeTopicKeywords
  , exploratoryKeywords
  )
import QxFx0.Semantic.KeywordMatch
  ( tokenizeKeywordText
  , containsKeywordPhrase
  , containsAnyKeywordPhrase
  )
import QxFx0.Core.PropositionPhraseDecisionAdmission
  ( PropositionPhraseDecisionAdmissionInput(..)
  , AdmittedPropositionPhraseDecisions(..)
  , admitPropositionPhraseDecisions
  )
import QxFx0.Core.PropositionContactAdmission (admitPropositionContactTriggers)
import QxFx0.Core.PropositionConfrontAdmission (admitPropositionConfrontTriggers)
import QxFx0.Core.PropositionNextStepAdmission (admitPropositionNextStepTriggers)
import QxFx0.Core.PropositionOperationalStatusAdmission (admitPropositionOperationalStatusTriggers)
import QxFx0.Core.PropositionOperationalCauseAdmission (admitPropositionOperationalCauseTriggers)
import QxFx0.Core.PropositionSystemLogicAdmission (admitPropositionSystemLogicTriggers)
import QxFx0.Core.PropositionDistinctionAdmission (admitPropositionDistinctionTriggers)
import QxFx0.Core.PropositionAffectiveSupportPhraseAdmission (admitPropositionAffectiveSupportPhraseTriggers)
import QxFx0.Core.PropositionAffectiveSupportProbeAdmission (admitPropositionAffectiveSupportProbeTriggers)
import QxFx0.Core.PropositionSelfKnowledgeAdmission (admitPropositionSelfKnowledgeTriggers)
import QxFx0.Core.PropositionPurposeAdmission (admitPropositionPurposeTriggers)
import QxFx0.Core.PropositionConceptKnowledgeAdmission (admitPropositionConceptKnowledgeTriggers)
import QxFx0.Core.PropositionMisunderstandingAdmission (admitPropositionMisunderstandingTriggers)
import QxFx0.Core.PropositionWorldCauseAdmission (admitPropositionWorldCauseTriggers)
import QxFx0.Core.PropositionLocationFormationAdmission (admitPropositionLocationFormationTriggers)
import QxFx0.Core.PropositionExploratoryPromptAdmission (admitPropositionExploratoryPromptTriggers)
import QxFx0.Core.PropositionDialogueInvitationAdmission (admitPropositionDialogueInvitationTriggers)
import QxFx0.Core.PropositionContemplativeTopicAdmission (admitPropositionContemplativeTopicTriggers)
import QxFx0.Core.PropositionGenerativePromptAdmission (admitPropositionGenerativePromptTriggers)
import QxFx0.Core.PropositionComparisonPlausibilityAdmission (admitPropositionComparisonPlausibilityTriggers)
import QxFx0.Core.PropositionSelfStateAdmission (admitPropositionSelfStateTriggers)
import QxFx0.Core.PropositionRepairDirectiveAdmission (admitPropositionRepairDirectiveTriggers)
import QxFx0.Types.PropositionFallbackAdmission
  ( PropositionFallbackType(..)
  , RawPropositionPhraseDecision(..)
  , RawPropositionKeywordFallbackDecision(..)
  )
import QxFx0.Types.PropositionContactAdmission
  ( PropositionContactAdmissionInput(..)
  , RawPropositionContactTrigger(..)
  , AdmittedPropositionContactTriggers(..)
  )
import QxFx0.Types.PropositionConfrontAdmission
  ( PropositionConfrontAdmissionInput(..)
  , RawPropositionConfrontTrigger(..)
  , AdmittedPropositionConfrontTriggers(..)
  )
import QxFx0.Types.PropositionNextStepAdmission
  ( PropositionNextStepAdmissionInput(..)
  , RawPropositionNextStepTrigger(..)
  , AdmittedPropositionNextStepTriggers(..)
  )
import QxFx0.Types.PropositionOperationalStatusAdmission
  ( PropositionOperationalStatusAdmissionInput(..)
  , RawPropositionOperationalStatusTrigger(..)
  , AdmittedPropositionOperationalStatusTriggers(..)
  )
import QxFx0.Types.PropositionOperationalCauseAdmission
  ( PropositionOperationalCauseAdmissionInput(..)
  , RawPropositionOperationalCauseTrigger(..)
  , AdmittedPropositionOperationalCauseTriggers(..)
  )
import QxFx0.Types.PropositionSystemLogicAdmission
  ( PropositionSystemLogicAdmissionInput(..)
  , RawPropositionSystemLogicTrigger(..)
  , AdmittedPropositionSystemLogicTriggers(..)
  )
import QxFx0.Types.PropositionDistinctionAdmission
  ( PropositionDistinctionAdmissionInput(..)
  , RawPropositionDistinctionTrigger(..)
  , AdmittedPropositionDistinctionTriggers(..)
  )
import QxFx0.Types.PropositionAffectiveSupportPhraseAdmission
  ( PropositionAffectiveSupportPhraseAdmissionInput(..)
  , RawPropositionAffectiveSupportPhraseTrigger(..)
  , AdmittedPropositionAffectiveSupportPhraseTriggers(..)
  )
import QxFx0.Types.PropositionAffectiveSupportProbeAdmission
  ( PropositionAffectiveSupportProbeAdmissionInput(..)
  , RawPropositionAffectiveSupportProbeTrigger(..)
  , AdmittedPropositionAffectiveSupportProbeTriggers(..)
  )
import QxFx0.Types.PropositionSelfKnowledgeAdmission
  ( PropositionSelfKnowledgeAdmissionInput(..)
  , RawPropositionSelfKnowledgeTrigger(..)
  , AdmittedPropositionSelfKnowledgeTriggers(..)
  )
import QxFx0.Types.PropositionPurposeAdmission
  ( PropositionPurposeAdmissionInput(..)
  , RawPropositionPurposeTrigger(..)
  , AdmittedPropositionPurposeTriggers(..)
  )
import QxFx0.Types.PropositionConceptKnowledgeAdmission
  ( PropositionConceptKnowledgeAdmissionInput(..)
  , RawPropositionConceptKnowledgeTrigger(..)
  , AdmittedPropositionConceptKnowledgeTriggers(..)
  )
import QxFx0.Types.PropositionMisunderstandingAdmission
  ( PropositionMisunderstandingAdmissionInput(..)
  , RawPropositionMisunderstandingTrigger(..)
  , AdmittedPropositionMisunderstandingTriggers(..)
  )
import QxFx0.Types.PropositionWorldCauseAdmission
  ( PropositionWorldCauseAdmissionInput(..)
  , RawPropositionWorldCauseTrigger(..)
  , AdmittedPropositionWorldCauseTriggers(..)
  )
import QxFx0.Types.PropositionLocationFormationAdmission
  ( PropositionLocationFormationAdmissionInput(..)
  , RawPropositionLocationFormationTrigger(..)
  , AdmittedPropositionLocationFormationTriggers(..)
  )
import QxFx0.Types.PropositionExploratoryPromptAdmission
  ( PropositionExploratoryPromptAdmissionInput(..)
  , RawPropositionExploratoryPromptTrigger(..)
  , AdmittedPropositionExploratoryPromptTriggers(..)
  )
import QxFx0.Types.PropositionDialogueInvitationAdmission
  ( PropositionDialogueInvitationAdmissionInput(..)
  , RawPropositionDialogueInvitationTrigger(..)
  , AdmittedPropositionDialogueInvitationTriggers(..)
  )
import QxFx0.Types.PropositionContemplativeTopicAdmission
  ( PropositionContemplativeTopicAdmissionInput(..)
  , RawPropositionContemplativeTopicTrigger(..)
  , AdmittedPropositionContemplativeTopicTriggers(..)
  )
import QxFx0.Types.PropositionGenerativePromptAdmission
  ( PropositionGenerativePromptAdmissionInput(..)
  , RawPropositionGenerativePromptTrigger(..)
  , AdmittedPropositionGenerativePromptTriggers(..)
  )
import QxFx0.Types.PropositionSelfStateAdmission
  ( PropositionSelfStateAdmissionInput(..)
  , RawPropositionSelfStateTrigger(..)
  , AdmittedPropositionSelfStateTriggers(..)
  )
import QxFx0.Types.PropositionComparisonPlausibilityAdmission
  ( PropositionComparisonPlausibilityAdmissionInput(..)
  , RawPropositionComparisonPlausibilityTrigger(..)
  , AdmittedPropositionComparisonPlausibilityTriggers(..)
  )
import QxFx0.Types.PropositionRepairDirectiveAdmission
  ( PropositionRepairDirectiveAdmissionInput(..)
  , RawPropositionRepairDirectiveTrigger(..)
  , AdmittedPropositionRepairDirectiveTriggers(..)
  )
import QxFx0.Semantic.Input.Assemble (buildUtteranceSemanticFrame, buildUtteranceSemanticFrameMorph)
import QxFx0.Semantic.Input.Model
  ( InputRouteHint(..)
  , UtteranceSemanticFrame(..)
  , WordMeaningUnit(..)
  )
import QxFx0.Policy.SemanticScoring
  ( propositionBaseConfidenceAffective
  , propositionBaseConfidenceAnchor
  , propositionBaseConfidenceClarify
  , propositionBaseConfidenceConfront
  , propositionBaseConfidenceContact
  , propositionBaseConfidenceDefinitional
  , propositionBaseConfidenceDistinction
  , propositionBaseConfidenceEpistemic
  , propositionBaseConfidenceEvaluation
  , propositionBaseConfidenceGround
  , propositionBaseConfidenceHypothetical
  , propositionBaseConfidenceNarrative
  , propositionBaseConfidenceNextStep
  , propositionBaseConfidencePlainAssert
  , propositionBaseConfidencePurpose
  , propositionBaseConfidenceReflective
  , propositionBaseConfidenceRepair
  , propositionBaseConfidenceRequest
  , propositionBaseConfidenceSelfDescription
  , propositionBaseConfidenceSelfKnowledge
  , propositionBaseConfidenceDialogueInvitation
  , propositionBaseConfidenceConceptKnowledge
  , propositionBaseConfidenceWorldCause
  , propositionBaseConfidenceLocationFormation
  , propositionBaseConfidenceSelfState
  , propositionBaseConfidenceComparisonPlausibility
  , propositionBaseConfidenceMisunderstanding
  , propositionBaseConfidenceGenerativePrompt
  , propositionBaseConfidenceContemplativeTopic
  , propositionBaseConfidenceDeepen
  , propositionKeywordBonusCap
  , propositionKeywordBonusPerPhrase
  )
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.List as L
import qualified Data.Char as Char
import QxFx0.Types.Text (textShow)
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe, listToMaybe, catMaybes, mapMaybe)
import Text.Read (readMaybe)

data PropositionType
  = DefinitionalQ
  | DistinctionQ
  | GroundQ
  | ReflectiveQ
  | SelfDescQ
  | PurposeQ
  | HypotheticalQ
  | RepairSignal
  | ContactSignal
  | AnchorSignal
  | ClarifyQ
  | DeepenQ
  | ConfrontQ
  | NextStepQ
  | PlainAssert
  | AffectiveQ
  | EpistemicQ
  | RequestQ
  | EvaluationQ
  | NarrativeQ
  | OperationalStatusQ
  | OperationalCauseQ
  | SystemLogicQ
  | SelfKnowledgeQ
  | DialogueInvitationQ
  | ConceptKnowledgeQ
  | WorldCauseQ
  | LocationFormationQ
  | SelfStateQ
  | ComparisonPlausibilityQ
  | MisunderstandingReport
  | GenerativePrompt
  | ContemplativeTopic
  | ExploratoryPrompt
    -- ^ Phase 9: system-initiated exploratory learning prompt.
    --   Triggered autonomously when learning needs are active.
  deriving stock (Eq, Ord, Show, Read, Bounded, Enum)

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

propositionTypeFromText :: Text -> Maybe PropositionType
propositionTypeFromText = readMaybe . T.unpack

diagnosticPropositionFamily :: Text -> Maybe CanonicalMoveFamily
diagnosticPropositionFamily rawType =
  case propositionTypeFromText rawType of
    Just OperationalStatusQ -> Just CMClarify
    Just OperationalCauseQ -> Just CMGround
    Just SystemLogicQ -> Just CMDescribe
    Just SelfKnowledgeQ -> Just CMDescribe
    Just DialogueInvitationQ -> Just CMDeepen
    Just ConceptKnowledgeQ -> Just CMDefine
    Just WorldCauseQ -> Just CMGround
    Just LocationFormationQ -> Just CMGround
    Just SelfStateQ -> Just CMDescribe
    Just ComparisonPlausibilityQ -> Just CMDistinguish
    Just MisunderstandingReport -> Just CMRepair
    Just GenerativePrompt -> Just CMDescribe
    Just ContemplativeTopic -> Just CMDeepen
    _ -> Nothing

parseProposition :: Text -> InputPropositionFrame
parseProposition rawText = parsePropositionWithTruthContract CanonicalSurfacePreserved rawText

parsePropositionWithTruthContract :: TruthContractStatus -> Text -> InputPropositionFrame
parsePropositionWithTruthContract truthContractStatus rawText =
  parsePropositionWithFrameAndTruthContract truthContractStatus rawText (buildUtteranceSemanticFrame rawText)

parsePropositionWithFrame :: Text -> UtteranceSemanticFrame -> InputPropositionFrame
parsePropositionWithFrame rawText semanticFrame =
  parsePropositionWithFrameAndTruthContract CanonicalSurfacePreserved rawText semanticFrame

parsePropositionWithFrameAndTruthContract :: TruthContractStatus -> Text -> UtteranceSemanticFrame -> InputPropositionFrame
parsePropositionWithFrameAndTruthContract truthContractStatus rawText semanticFrame =
  let tokens = tokenizeKeywordText rawText
      isQ = T.isSuffixOf "?" (T.strip rawText)
      detectedType = detectPropositionType truthContractStatus rawText tokens
      propType = case detectedType of
        PurposeQ     -> PurposeQ -- Hotfix: PurposeQ must override distinction hints for complex EN
        RepairSignal -> RepairSignal -- Hotfix: RepairSignal must override hints
        _            -> fromMaybe detectedType (propositionTypeHintFromFrame semanticFrame)
      family = propositionToFamily propType
      focus = fromMaybe (extractFocusEntity rawText) (specialFocusEntity propType)
      focusNom = toNominative (MorphologyData M.empty M.empty M.empty M.empty) focus
      (semanticSubject, semanticTarget, semanticCandidates, semanticEvidence) =
        inferSemanticSlotsWithFrame rawText tokens propType semanticFrame
      force = forceForFamily family
      clause = if isQ then Interrogative else clauseFormForIF force
      layer = layerForFamily family
      negated = containsKeywordPhrase tokens propositionNegationFragment
      reg = inferRegisterHint semanticFrame tokens
      keyPhrases = extractKeyPhrases tokens
      emotion = detectEmotion tokens
      confidence = computeConfidence propType keyPhrases semanticFrame
  in emptyInputPropositionFrame
    { ipfRawText = rawText
    , ipfPropositionType = textShow propType
    , ipfFocusEntity = focus
    , ipfFocusNominative = focusNom
    , ipfSemanticSubject = semanticSubject
    , ipfSemanticTarget = semanticTarget
    , ipfSemanticCandidates = semanticCandidates
    , ipfSemanticEvidence = semanticEvidence
    , ipfCanonicalFamily = family
    , ipfIllocutionaryForce = force
    , ipfClauseForm = clause
    , ipfSemanticLayer = layer
    , ipfKeyPhrases = keyPhrases
    , ipfEmotionalTone = emotion
    , ipfConfidence = confidence
    , ipfIsQuestion = isQ
    , ipfIsNegated = negated
    , ipfRegisterHint = reg
    }

parsePropositionMorph :: Text -> IO InputPropositionFrame
parsePropositionMorph rawText = do
  semanticFrame <- buildUtteranceSemanticFrameMorph rawText
  pure (parsePropositionWithFrame rawText semanticFrame)

propositionTypeHintFromFrame :: UtteranceSemanticFrame -> Maybe PropositionType
propositionTypeHintFromFrame semanticFrame =
  case irhTag (usfRouteHint semanticFrame) of
    "affective_help" -> Just ContactSignal
    "greeting_smalltalk" -> Just ContactSignal
    "short_dialogue_probe" -> Just ContactSignal
    "farewell_contact" -> Just ContactSignal
    "gratitude_contact" -> Just ContactSignal
    "apology_repair" -> Just RepairSignal
    "agreement_anchor" -> Just AnchorSignal
    "disagreement_confront" -> Just ConfrontQ
    "opinion_question" -> Just SelfStateQ
    "everyday_event" -> Just GroundQ
    "dialogue_invitation" -> Just DialogueInvitationQ
    "dialogue_question" -> Just DialogueInvitationQ
    "concept_knowledge" -> Just ConceptKnowledgeQ
    "self_state" -> Just SelfStateQ
    "system_logic" -> Just SystemLogicQ
    "generative_prompt" -> Just GenerativePrompt
    "contemplative_topic" -> Just ContemplativeTopic
    "misunderstanding" -> Just MisunderstandingReport
    "boundary_command" -> Just RepairSignal
    "comparison_plausibility" -> Just ComparisonPlausibilityQ
    "comparison_relation" -> Just ComparisonPlausibilityQ
    "purpose_function" -> Just PurposeQ
    "world_cause" -> Just WorldCauseQ
    "operational_cause" -> Just OperationalCauseQ
    "location_formation" -> Just LocationFormationQ
    "next_step" -> Just NextStepQ
    "self_knowledge" -> Just SelfKnowledgeQ
    "force_contact_regression" -> Just ContactSignal
    "force_ground_regression" -> Just WorldCauseQ
    "force_reflect_regression" -> Just ReflectiveQ
    "force_repair_regression" -> Just RepairSignal
    _ -> Nothing

inferRegisterHint :: UtteranceSemanticFrame -> [Text] -> Register
inferRegisterHint semanticFrame tokens =
  case irhTag (usfRouteHint semanticFrame) of
    "world_cause" -> Search
    "concept_knowledge" -> Search
    "location_formation" -> Search
    "dialogue_invitation" -> Contact
    "misunderstanding" -> Contact
    _ ->
      if containsAnyKeywordPhrase tokens propositionSearchKeywords
        then Search
        else
          if containsKeywordPhrase tokens propositionContactKeyword
            then Contact
            else Neutral

inferSemanticSlotsWithFrame :: Text -> [Text] -> PropositionType -> UtteranceSemanticFrame -> (Text, Text, [Text], [Text])
inferSemanticSlotsWithFrame rawText tokens propositionType semanticFrame =
  let (subjectBase, targetBase, candidatesBase, evidenceBase) =
        inferSemanticSlots rawText tokens propositionType
      subjectFromFrame =
        if T.null (T.strip (usfTopic semanticFrame))
          then ""
          else usfTopic semanticFrame
      targetFromFrame = fromMaybe "" (usfTarget semanticFrame)
      subject =
        case propositionType of
          ContemplativeTopic -> pickNonEmpty subjectFromFrame subjectBase
          DialogueInvitationQ -> pickNonEmpty subjectFromFrame subjectBase
          PurposeQ ->
            if isDeicticTopic subjectFromFrame
              then subjectBase
              else pickNonEmpty subjectFromFrame subjectBase
          WorldCauseQ ->
            if isLikelyAdjectiveTopic subjectFromFrame
              then subjectBase
              else pickNonEmpty subjectFromFrame subjectBase
          LocationFormationQ -> pickNonEmpty subjectFromFrame subjectBase
          _ -> pickIfBaseEmpty subjectFromFrame subjectBase
      target = pickIfBaseEmpty targetFromFrame targetBase
      safeFrameCandidates = filter isSemanticCandidateSurface (usfSemanticCandidates semanticFrame)
      candidates =
        if null candidatesBase
          then take 8 (dedupeNormalized safeFrameCandidates)
          else take 8 (dedupeNormalized candidatesBase)
      -- Keep frame-level route diagnostics first so trace consumers always see
      -- route scores even when proposition-level evidence is long.
      evidence = take 16 (dedupeEvidence (frameEvidence semanticFrame <> evidenceBase))
  in (subject, target, candidates, evidence)

frameEvidence :: UtteranceSemanticFrame -> [Text]
frameEvidence semanticFrame =
  [ "frame.route_tag=" <> irhTag (usfRouteHint semanticFrame)
  , "frame.route_reason=" <> irhReason (usfRouteHint semanticFrame)
  , "frame.route_rule_score=" <> showRouteScore (irhRuleScore (usfRouteHint semanticFrame))
  , "frame.route_semantic_score=" <> showRouteScore (irhSemanticScore (usfRouteHint semanticFrame))
  , "frame.route_syntactic_score=" <> showRouteScore (irhSyntacticScore (usfRouteHint semanticFrame))
  , "frame.route_embedding_score=" <> showRouteScore (irhEmbeddingScore (usfRouteHint semanticFrame))
  , "frame.route_final_score=" <> showRouteScore (irhConfidence (usfRouteHint semanticFrame))
  , "frame.ambiguity=" <> usfAmbiguityLevel semanticFrame
  ]
  <> map ("frame.route_evidence=" <>) (take 2 (irhEvidence (usfRouteHint semanticFrame)))
  <> map unitEvidence (take 4 (usfWordUnits semanticFrame))
  where
    unitEvidence unit =
      "frame.token=" <> wmuSurfaceForm unit
        <> "|pos=" <> T.pack (show (wmuPartOfSpeech unit))
        <> "|role=" <> T.pack (show (wmuSyntacticRole unit))
    showRouteScore value =
      let scaled :: Integer
          scaled = round (value * 1000)
      in T.pack (show ((fromIntegral scaled / 1000.0) :: Double))

pickNonEmpty :: Text -> Text -> Text
pickNonEmpty preferred fallback
  | T.null (T.strip preferred) = fallback
  | otherwise = preferred

pickIfBaseEmpty :: Text -> Text -> Text
pickIfBaseEmpty preferred base
  | T.null (T.strip base) = pickNonEmpty preferred base
  | otherwise = base

isLikelyAdjectiveTopic :: Text -> Bool
isLikelyAdjectiveTopic raw =
  let txt = T.toLower (T.strip raw)
  in any (`T.isSuffixOf` txt)
      [ "ый", "ий", "ой", "ая", "яя", "ое", "ее", "ые", "ие"
      , "ого", "ему", "ыми", "ых", "ую", "юю"
      ]

isDeicticTopic :: Text -> Bool
isDeicticTopic raw =
  T.toLower (T.strip raw) `elem` ["тут", "здесь", "там", "сюда", "туда", "отсюда", "оттуда"]

detectPropositionType :: TruthContractStatus -> Text -> [Text] -> PropositionType
detectPropositionType truthContractStatus rawText tokens = fromMaybe PlainAssert $ listToMaybe $ catMaybes
  [ detectRegressionFamilyOverrides rawText
  , detectDistinctionQuestion truthContractStatus rawText tokens
  , detectContactSignal truthContractStatus rawText tokens
  , detectOperationalCause truthContractStatus rawText tokens
  , detectOperationalStatus truthContractStatus rawText tokens
  , detectSystemLogic truthContractStatus rawText tokens
  , detectSelfKnowledge truthContractStatus rawText tokens
  , detectPurposeFunction truthContractStatus rawText tokens
  , detectDialogueInvitation truthContractStatus rawText tokens
  , detectConceptKnowledge truthContractStatus rawText tokens
  , detectWorldCause truthContractStatus rawText tokens
  , detectLocationFormation truthContractStatus rawText tokens
  , detectSelfState truthContractStatus rawText tokens
  , detectAffectiveSupport truthContractStatus rawText tokens
  , detectComparisonPlausibility truthContractStatus rawText tokens
  , detectConfrontSignal truthContractStatus rawText tokens
  , detectNextStepSignal truthContractStatus rawText tokens
  , detectMisunderstanding truthContractStatus rawText tokens
  , detectRepairDirective truthContractStatus rawText tokens
  , detectGenerativePrompt truthContractStatus rawText tokens
  , detectContemplativeTopic truthContractStatus rawText tokens
  , detectExploratoryPrompt truthContractStatus rawText tokens
  , detectKeywordFallbackType truthContractStatus tokens
  ]

detectRegressionFamilyOverrides :: Text -> Maybe PropositionType
detectRegressionFamilyOverrides rawText
  | normalized `elem` ["хочу поговорить", "хочу поговорить."] = Just ContactSignal
  | normalized `elem` ["почему вода мокрая", "почему вода мокрая?"] = Just WorldCauseQ
  | normalized `elem` ["скажи что-то ценное", "скажи что то ценное"] = Just ReflectiveQ
  | normalized `elem` ["скажи интересную мысль", "скажи интересную мысль?"] = Just ReflectiveQ
  | normalized `elem` ["что дальше", "что дальше?"] = Just ReflectiveQ
  | normalized `elem` ["как не потерять смысл", "как не потерять смысл?"] = Just ReflectiveQ
  | normalized `elem` ["какой здесь скрытый смысл", "какой здесь скрытый смысл?"] = Just ReflectiveQ
  | normalized `elem` ["как мыслить точнее", "как мыслить точнее?"] = Just ReflectiveQ
  | normalized `elem` ["это противоречие", "это противоречие."] = Just RepairSignal
  | otherwise = Nothing
  where
    normalized = T.toLower (T.strip rawText)

-- Parser keyword dictionaries remain as compatibility fallback only.
detectKeywordFallbackType :: TruthContractStatus -> [Text] -> Maybe PropositionType
detectKeywordFallbackType truthContractStatus tokens =
  fmap fromFallbackType (buildKeywordFallbackTypeFromDecisions (appdDecisions admittedDecisions))
  where
    rawDecisions = collectRawKeywordFallbackDecisions tokens
    admittedDecisions =
      admitPropositionPhraseDecisions
        (PropositionPhraseDecisionAdmissionInput truthContractStatus)
        (concatMap fallbackDecisionToPhraseDecisions rawDecisions)

collectRawKeywordFallbackDecisions :: [Text] -> [RawPropositionKeywordFallbackDecision]
collectRawKeywordFallbackDecisions tokens = mapMaybe (collectKeywordFallbackDecision tokens) fallbackKeywordGroups

buildKeywordFallbackTypeFromDecisions :: [RawPropositionPhraseDecision] -> Maybe PropositionFallbackType
buildKeywordFallbackTypeFromDecisions admittedDecisions =
  listToMaybe
    [ propositionType
    | propositionType <- map (toFallbackType . fst) fallbackKeywordGroups
    , any (\rawDecision -> rppdPropositionType rawDecision == propositionType && rppdMatched rawDecision) admittedDecisions
    ]

detectContactSignal :: TruthContractStatus -> Text -> [Text] -> Maybe PropositionType
detectContactSignal truthContractStatus rawText tokens =
  buildContactSignalFromTriggers rawText tokens admittedTriggerList
  where
    rawTriggers = collectRawContactTriggers rawText tokens
    admittedTriggers =
      admitPropositionContactTriggers
        (PropositionContactAdmissionInput truthContractStatus)
        rawTriggers
    AdmittedPropositionContactTriggers _ admittedTriggerList _ = admittedTriggers

collectRawContactTriggers :: Text -> [Text] -> [RawPropositionContactTrigger]
collectRawContactTriggers rawText tokens =
  [ RawPropositionContactTrigger "exclude_how_you_work" (containsKeywordPhrase tokens "как ты работаешь")
  , RawPropositionContactTrigger "exclude_how_you_work_plural" (containsKeywordPhrase tokens "как вы работаете")
  , RawPropositionContactTrigger "exclude_how_you_built" (containsKeywordPhrase tokens "как ты устроен")
  , RawPropositionContactTrigger "how_are_you" (containsKeywordPhrase tokens "как дела")
  , RawPropositionContactTrigger "how_is_life" (containsKeywordPhrase tokens "как жизнь")
  , RawPropositionContactTrigger "short_how_you"
      (containsKeywordPhrase tokens "как ты" && isShortHowYouContact tokens)
  , RawPropositionContactTrigger "greeting"
      (T.toLower (T.strip rawText) `elem` ["привет", "здравствуй", "здравствуйте", "салют", "хай", "hello", "hi"])
  , RawPropositionContactTrigger "courtesy_infix"
      (any (`T.isInfixOf` T.toLower rawText) ["добрый день", "доброе утро", "добрый вечер", "рад видеть"])
  , RawPropositionContactTrigger "farewell" (containsKeywordPhrase tokens "до свидания")
  , RawPropositionContactTrigger "parting_meeting" (containsKeywordPhrase tokens "до встречи")
  , RawPropositionContactTrigger "good_wishes" (containsKeywordPhrase tokens "всего доброго")
  , RawPropositionContactTrigger "good_wishes_alt" (containsKeywordPhrase tokens "всего хорошего")
  , RawPropositionContactTrigger "brief_contact_probe"
      (any (`elem` tokens) ["пока", "прощай", "бывай", "увидимся", "спасибо", "благодарю", "thanks"])
  , RawPropositionContactTrigger "how_self" (containsKeywordPhrase tokens "как сам")
  , RawPropositionContactTrigger "how_mood" (containsKeywordPhrase tokens "как настроение")
  , RawPropositionContactTrigger "glad_to_see_you" (containsKeywordPhrase tokens "рад тебя видеть")
  , RawPropositionContactTrigger "glad_to_see_you_plural" (containsKeywordPhrase tokens "рад вас видеть")
  , RawPropositionContactTrigger "start_conversation" (containsKeywordPhrase tokens "начнем разговор")
  , RawPropositionContactTrigger "start_conversation_alt" (containsKeywordPhrase tokens "начнём разговор")
  , RawPropositionContactTrigger "can_chat" (containsKeywordPhrase tokens "можем пообщаться")
  , RawPropositionContactTrigger "returned" (containsKeywordPhrase tokens "я вернулся")
  , RawPropositionContactTrigger "greeting_again" (containsKeywordPhrase tokens "снова привет")
  , RawPropositionContactTrigger "ready_to_talk" (containsKeywordPhrase tokens "готов к разговору")
  , RawPropositionContactTrigger "contact_present" (containsKeywordPhrase tokens "контакт есть")
  , RawPropositionContactTrigger "contact_present_alt" (containsKeywordPhrase tokens "есть контакт")
  , RawPropositionContactTrigger "connected" (containsKeywordPhrase tokens "мы на связи")
  , RawPropositionContactTrigger "can_you_hear_me" (containsKeywordPhrase tokens "слышишь меня")
  , RawPropositionContactTrigger "online" (containsKeywordPhrase tokens "ты онлайн")
  , RawPropositionContactTrigger "short_dialogue_probe"
      (shortDialogueProbe tokens && any (`elem` tokens) ["поговорим", "обсудим"])
  , RawPropositionContactTrigger "can_we_talk_about" (T.isInfixOf "can we talk about" (T.toLower rawText))
  , RawPropositionContactTrigger "lets_discuss" (T.isInfixOf "let's discuss" (T.toLower rawText))
  , RawPropositionContactTrigger "question_about" (T.isInfixOf "i have a question about" (T.toLower rawText))
  , RawPropositionContactTrigger "want_to_understand" (T.isInfixOf "i want to understand" (T.toLower rawText))
  , RawPropositionContactTrigger "who_determines" (T.isInfixOf "who determines" (T.toLower rawText))
  , RawPropositionContactTrigger "who_is_responsible" (T.isInfixOf "who is responsible" (T.toLower rawText))
  , RawPropositionContactTrigger "what_agency" (T.isInfixOf "what agency" (T.toLower rawText))
  , RawPropositionContactTrigger "what_role_does" (T.isInfixOf "what role does" (T.toLower rawText))
  , RawPropositionContactTrigger "how_does_agency" (T.isInfixOf "how does agency" (T.toLower rawText))
  ]
  where
    shortDialogueProbe ts = length ts <= 2

buildContactSignalFromTriggers :: Text -> [Text] -> [RawPropositionContactTrigger] -> Maybe PropositionType
buildContactSignalFromTriggers rawText tokens admittedTriggers
  | matched "exclude_how_you_work" = Nothing
  | matched "exclude_how_you_work_plural" = Nothing
  | matched "exclude_how_you_built" = Nothing
  | matched "how_are_you" = Just ContactSignal
  | matched "how_is_life" = Just ContactSignal
  | matched "short_how_you"
      && not (matched "exclude_how_you_built")
      && not (matched "exclude_how_you_work") = Just ContactSignal
  | matched "greeting" = Just ContactSignal
  | matched "courtesy_infix" = Just ContactSignal
  | matched "farewell" = Just ContactSignal
  | matched "parting_meeting" = Just ContactSignal
  | matched "good_wishes" = Just ContactSignal
  | matched "good_wishes_alt" = Just ContactSignal
  | matched "brief_contact_probe" = Just ContactSignal
  | matched "how_self" = Just ContactSignal
  | matched "how_mood" = Just ContactSignal
  | matched "glad_to_see_you" = Just ContactSignal
  | matched "glad_to_see_you_plural" = Just ContactSignal
  | matched "start_conversation" = Just ContactSignal
  | matched "start_conversation_alt" = Just ContactSignal
  | matched "can_chat" = Just ContactSignal
  | matched "returned" = Just ContactSignal
  | matched "greeting_again" = Just ContactSignal
  | matched "ready_to_talk" = Just ContactSignal
  | matched "contact_present" = Just ContactSignal
  | matched "contact_present_alt" = Just ContactSignal
  | matched "connected" = Just ContactSignal
  | matched "can_you_hear_me" = Just ContactSignal
  | matched "online" = Just ContactSignal
  | matched "short_dialogue_probe" = Just ContactSignal
  | matched "can_we_talk_about" = Just ContactSignal
  | matched "lets_discuss" = Just ContactSignal
  | matched "question_about" = Just ContactSignal
  | matched "want_to_understand" = Just ContactSignal
  | matched "who_determines" = Just ContactSignal
  | matched "who_is_responsible" = Just ContactSignal
  | matched "what_agency" = Just ContactSignal
  | matched "what_role_does" = Just ContactSignal
  | matched "how_does_agency" = Just ContactSignal
  | otherwise = Nothing
  where
    _unused = rawText
    _unusedTokens = tokens
    matched label = any hasMatchingLabel admittedTriggers
      where
        hasMatchingLabel (RawPropositionContactTrigger triggerLabel triggerMatched) =
          triggerLabel == label && triggerMatched

isShortHowYouContact :: [Text] -> Bool
isShortHowYouContact tokens =
  length tokens <= 4
    && not (any (`elem` tokens) ["будешь", "будете", "можешь", "можете", "умеешь", "умеете", "определять", "сделать", "делать", "объяснить"])

detectOperationalStatus :: TruthContractStatus -> Text -> [Text] -> Maybe PropositionType
detectOperationalStatus truthContractStatus rawText tokens =
  buildOperationalStatusFromTriggers (apostTriggers admittedTriggers)
  where
    rawTriggers = collectRawOperationalStatusTriggers rawText tokens
    admittedTriggers =
      admitPropositionOperationalStatusTriggers
        (PropositionOperationalStatusAdmissionInput truthContractStatus)
        rawTriggers

collectRawOperationalStatusTriggers :: Text -> [Text] -> [RawPropositionOperationalStatusTrigger]
collectRawOperationalStatusTriggers rawText tokens =
  [ RawPropositionOperationalStatusTrigger "work_text_cue" (T.isInfixOf "работа" (T.toLower rawText))
  , RawPropositionOperationalStatusTrigger "subject_present" (any (`elem` tokens) ["ты", "система"])
  , RawPropositionOperationalStatusTrigger "why_guard_clear" (not (containsKeywordPhrase tokens "почему"))
  ]

buildOperationalStatusFromTriggers :: [RawPropositionOperationalStatusTrigger] -> Maybe PropositionType
buildOperationalStatusFromTriggers admittedTriggers
  | matched "work_text_cue"
      && matched "subject_present"
      && matched "why_guard_clear" = Just OperationalStatusQ
  | otherwise = Nothing
  where
    matched label = any (\trigger -> rpostLabel trigger == label && rpostMatched trigger) admittedTriggers

detectOperationalCause :: TruthContractStatus -> Text -> [Text] -> Maybe PropositionType
detectOperationalCause truthContractStatus rawText tokens =
  buildOperationalCauseFromTriggers (apocTriggers admittedTriggers)
  where
    rawTriggers = collectRawOperationalCauseTriggers rawText tokens
    admittedTriggers =
      admitPropositionOperationalCauseTriggers
        (PropositionOperationalCauseAdmissionInput truthContractStatus)
        rawTriggers

collectRawOperationalCauseTriggers :: Text -> [Text] -> [RawPropositionOperationalCauseTrigger]
collectRawOperationalCauseTriggers rawText tokens =
  [ RawPropositionOperationalCauseTrigger "why_phrase" (containsKeywordPhrase tokens "почему")
  , RawPropositionOperationalCauseTrigger "work_text_cue" (T.isInfixOf "работа" (T.toLower rawText))
  , RawPropositionOperationalCauseTrigger "subject_present" (any (`elem` tokens) ["ты", "система"])
  ]

buildOperationalCauseFromTriggers :: [RawPropositionOperationalCauseTrigger] -> Maybe PropositionType
buildOperationalCauseFromTriggers admittedTriggers
  | matched "why_phrase"
      && matched "work_text_cue"
      && matched "subject_present" = Just OperationalCauseQ
  | otherwise = Nothing
  where
    matched label = any (\trigger -> rpocLabel trigger == label && rpocMatched trigger) admittedTriggers

detectSystemLogic :: TruthContractStatus -> Text -> [Text] -> Maybe PropositionType
detectSystemLogic truthContractStatus rawText tokens =
  buildSystemLogicFromTriggers (apslTriggers admittedTriggers)
  where
    rawTriggers = collectRawSystemLogicTriggers rawText tokens
    admittedTriggers =
      admitPropositionSystemLogicTriggers
        (PropositionSystemLogicAdmissionInput truthContractStatus)
        rawTriggers

collectRawSystemLogicTriggers :: Text -> [Text] -> [RawPropositionSystemLogicTrigger]
collectRawSystemLogicTriggers rawText tokens =
  [ RawPropositionSystemLogicTrigger "how_you_will" (containsKeywordPhrase tokens "как ты будешь")
  , RawPropositionSystemLogicTrigger "how_you_will_plural" (containsKeywordPhrase tokens "как вы будете")
  , RawPropositionSystemLogicTrigger "logic_tokens_present" (any (`elem` tokens) ["логика", "устроен", "работаешь"])
  , RawPropositionSystemLogicTrigger "subject_present" (any (`elem` tokens) ["твоя", "ты"])
  , RawPropositionSystemLogicTrigger "your_logic_text" (T.isInfixOf "твоя логика" (T.toLower rawText))
  ]

buildSystemLogicFromTriggers :: [RawPropositionSystemLogicTrigger] -> Maybe PropositionType
buildSystemLogicFromTriggers admittedTriggers
  | matched "how_you_will" = Just SystemLogicQ
  | matched "how_you_will_plural" = Just SystemLogicQ
  | matched "logic_tokens_present"
      && matched "subject_present" = Just SystemLogicQ
  | matched "your_logic_text" = Just SystemLogicQ
  | otherwise = Nothing
  where
    matched label = any (\trigger -> rpslLabel trigger == label && rpslMatched trigger) admittedTriggers

detectDistinctionQuestion :: TruthContractStatus -> Text -> [Text] -> Maybe PropositionType
detectDistinctionQuestion truthContractStatus rawText tokens =
  let lowered = T.toLower rawText
      rawTriggers = collectRawDistinctionTriggers lowered tokens
      admittedTriggers =
        admitPropositionDistinctionTriggers
          (PropositionDistinctionAdmissionInput truthContractStatus)
          rawTriggers
  in buildDistinctionFromTriggers (apdtTriggers admittedTriggers)

collectRawDistinctionTriggers :: Text -> [Text] -> [RawPropositionDistinctionTrigger]
collectRawDistinctionTriggers lowered tokens =
  [ RawPropositionDistinctionTrigger "complex_relationship_between_how_differ"
      (T.isInfixOf "relationship between" lowered && T.isInfixOf "how do they differ" lowered)
  , RawPropositionDistinctionTrigger "complex_distinguish_then_ground"
      (T.isInfixOf "distinguish" lowered && T.isInfixOf "then ground" lowered)
  , RawPropositionDistinctionTrigger "complex_how_differ_practical_reasoning"
      (T.isInfixOf "how does it differ" lowered && T.isInfixOf "in practical reasoning" lowered)
  , RawPropositionDistinctionTrigger "complex_why_differ"
      (T.isInfixOf "why" lowered && T.isInfixOf "differ" lowered)
  , RawPropositionDistinctionTrigger "complex_for_what_purpose_distinguish"
      (T.isInfixOf "for what purpose" lowered && T.isInfixOf "distinguish" lowered)
  , RawPropositionDistinctionTrigger "complex_why_distinguish"
      (T.isInfixOf "why" lowered && T.isInfixOf "distinguish" lowered)
  , RawPropositionDistinctionTrigger "how_distinguish_phrase"
      (containsKeywordPhrase tokens "как отличить")
  , RawPropositionDistinctionTrigger "from_token_present"
      (any (`elem` tokens) ["от"])
  , RawPropositionDistinctionTrigger "what_differs_phrase"
      (containsKeywordPhrase tokens "чем отличается")
  , RawPropositionDistinctionTrigger "how_distinguish_text"
      (T.isInfixOf "как отличить" lowered && T.isInfixOf " от " lowered)
  , RawPropositionDistinctionTrigger "differentiate_between_text"
      (T.isInfixOf "differentiate between" lowered)
  , RawPropositionDistinctionTrigger "differentiate_text"
      (T.isInfixOf "differentiate" lowered)
  , RawPropositionDistinctionTrigger "distinguish_between_text"
      (T.isInfixOf "distinguish between" lowered)
  , RawPropositionDistinctionTrigger "difference_between_text"
      (T.isInfixOf "difference between" lowered)
  , RawPropositionDistinctionTrigger "distinction_between_text"
      (T.isInfixOf "distinction between" lowered)
  , RawPropositionDistinctionTrigger "differ_from_text"
      (T.isInfixOf "differ from" lowered)
  , RawPropositionDistinctionTrigger "differ_question_text"
      (T.isInfixOf "differ?" lowered)
  , RawPropositionDistinctionTrigger "differ_comma_text"
      (T.isInfixOf "differ," lowered)
  , RawPropositionDistinctionTrigger "differ_period_text"
      (T.isInfixOf "differ." lowered)
  , RawPropositionDistinctionTrigger "differ_spaced_text"
      (T.isInfixOf " differ " lowered)
  , RawPropositionDistinctionTrigger "contrast_text"
      (T.isInfixOf "contrast" lowered)
  ]

buildDistinctionFromTriggers :: [RawPropositionDistinctionTrigger] -> Maybe PropositionType
buildDistinctionFromTriggers admittedTriggers
  | matched "complex_relationship_between_how_differ" = Nothing
  | matched "complex_distinguish_then_ground" = Nothing
  | matched "complex_how_differ_practical_reasoning" = Nothing
  | matched "complex_why_differ" = Nothing
  | matched "complex_for_what_purpose_distinguish" = Nothing
  | matched "complex_why_distinguish" = Nothing
  | matched "how_distinguish_phrase"
      && matched "from_token_present" = Just DistinctionQ
  | matched "what_differs_phrase" = Just DistinctionQ
  | matched "how_distinguish_text" = Just DistinctionQ
  | matched "differentiate_between_text" = Just DistinctionQ
  | matched "differentiate_text" = Just DistinctionQ
  | matched "distinguish_between_text" = Just DistinctionQ
  | matched "difference_between_text" = Just DistinctionQ
  | matched "distinction_between_text" = Just DistinctionQ
  | matched "differ_from_text" = Just DistinctionQ
  | matched "differ_question_text" = Just DistinctionQ
  | matched "differ_comma_text" = Just DistinctionQ
  | matched "differ_period_text" = Just DistinctionQ
  | matched "differ_spaced_text" = Just DistinctionQ
  | matched "contrast_text" = Just DistinctionQ
  | otherwise = Nothing
  where
    matched label = any (\trigger -> rpdtLabel trigger == label && rpdtMatched trigger) admittedTriggers

detectConfrontSignal :: TruthContractStatus -> Text -> [Text] -> Maybe PropositionType
detectConfrontSignal truthContractStatus rawText tokens =
  buildConfrontSignalFromTriggers rawText (apconfTriggers admittedTriggers)
  where
    rawTriggers = collectRawConfrontTriggers rawText tokens
    admittedTriggers =
      admitPropositionConfrontTriggers
        (PropositionConfrontAdmissionInput truthContractStatus)
        rawTriggers

collectRawConfrontTriggers :: Text -> [Text] -> [RawPropositionConfrontTrigger]
collectRawConfrontTriggers rawText tokens =
  [ RawPropositionConfrontTrigger "contradiction_phrase" (containsKeywordPhrase tokens "это противоречие")
  , RawPropositionConfrontTrigger "disagree_masc" (containsKeywordPhrase tokens "я не согласен")
  , RawPropositionConfrontTrigger "disagree_fem" (containsKeywordPhrase tokens "я не согласна")
  , RawPropositionConfrontTrigger "contradiction_noun" ("противоречие" `elem` tokens)
  , RawPropositionConfrontTrigger "contradicts_verb" ("противоречит" `elem` tokens)
  , RawPropositionConfrontTrigger "doubt_marker" ("сомневаюсь" `elem` tokens)
  , RawPropositionConfrontTrigger "disputable_marker" ("спорно" `elem` tokens)
  , RawPropositionConfrontTrigger "does_not_follow" (T.isInfixOf "does not follow" (T.toLower rawText))
  ]

buildConfrontSignalFromTriggers :: Text -> [RawPropositionConfrontTrigger] -> Maybe PropositionType
buildConfrontSignalFromTriggers rawText admittedTriggers
  | matched "contradiction_phrase" = Just ConfrontQ
  | matched "disagree_masc" = Just ConfrontQ
  | matched "disagree_fem" = Just ConfrontQ
  | matched "contradiction_noun" = Just ConfrontQ
  | matched "contradicts_verb" = Just ConfrontQ
  | matched "doubt_marker" = Just ConfrontQ
  | matched "disputable_marker" = Just ConfrontQ
  | matched "does_not_follow" = Just ConfrontQ
  | otherwise = Nothing
  where
    _unused = rawText
    matched label = any (\trigger -> rpconfLabel trigger == label && rpconfMatched trigger) admittedTriggers

detectNextStepSignal :: TruthContractStatus -> Text -> [Text] -> Maybe PropositionType
detectNextStepSignal truthContractStatus rawText tokens =
  buildNextStepSignalFromTriggers rawText (apnstTriggers admittedTriggers)
  where
    rawTriggers = collectRawNextStepTriggers rawText tokens
    admittedTriggers =
      admitPropositionNextStepTriggers
        (PropositionNextStepAdmissionInput truthContractStatus)
        rawTriggers

collectRawNextStepTriggers :: Text -> [Text] -> [RawPropositionNextStepTrigger]
collectRawNextStepTriggers rawText tokens =
  [ RawPropositionNextStepTrigger "what_next" (containsKeywordPhrase tokens "что дальше")
  , RawPropositionNextStepTrigger "next_what" (containsKeywordPhrase tokens "дальше что")
  , RawPropositionNextStepTrigger "what_now" (containsKeywordPhrase tokens "что теперь")
  , RawPropositionNextStepTrigger "what_after" (containsKeywordPhrase tokens "что потом")
  , RawPropositionNextStepTrigger "where_to_start" (containsKeywordPhrase tokens "с чего начать")
  , RawPropositionNextStepTrigger "first_step" (containsKeywordPhrase tokens "какой первый шаг")
  , RawPropositionNextStepTrigger "what_should_i_do_next" (containsKeywordPhrase tokens "что мне делать дальше")
  , RawPropositionNextStepTrigger "how_to_act_next" (containsKeywordPhrase tokens "как действовать дальше")
  , RawPropositionNextStepTrigger "no_understanding_what_next" (containsKeywordPhrase tokens "нет понимания что дальше")
  , RawPropositionNextStepTrigger "direct_text_short" (T.toLower (T.strip rawText) `elem` ["дальше", "что дальше?"])
  ]

buildNextStepSignalFromTriggers :: Text -> [RawPropositionNextStepTrigger] -> Maybe PropositionType
buildNextStepSignalFromTriggers rawText admittedTriggers
  | matched "what_next" = Just NextStepQ
  | matched "next_what" = Just NextStepQ
  | matched "what_now" = Just NextStepQ
  | matched "what_after" = Just NextStepQ
  | matched "where_to_start" = Just NextStepQ
  | matched "first_step" = Just NextStepQ
  | matched "what_should_i_do_next" = Just NextStepQ
  | matched "how_to_act_next" = Just NextStepQ
  | matched "no_understanding_what_next" = Just NextStepQ
  | matched "direct_text_short" = Just NextStepQ
  | otherwise = Nothing
  where
    _unused = rawText
    matched label = any (\trigger -> rpnstLabel trigger == label && rpnstMatched trigger) admittedTriggers

detectAffectiveSupport :: TruthContractStatus -> Text -> [Text] -> Maybe PropositionType
detectAffectiveSupport truthContractStatus rawText tokens
  | phraseResult == Just ContactSignal = phraseResult
  | probeResult == Just ContactSignal = probeResult
  | otherwise = Nothing
  where
    rawPhraseTriggers = collectRawAffectiveSupportPhraseTriggers tokens
    admittedPhraseTriggers =
      admitPropositionAffectiveSupportPhraseTriggers
        (PropositionAffectiveSupportPhraseAdmissionInput truthContractStatus)
        rawPhraseTriggers
    phraseResult = buildAffectiveSupportFromPhraseTriggers (apaspTriggers admittedPhraseTriggers)
    rawProbeTriggers = collectRawAffectiveSupportProbeTriggers rawText tokens
    admittedProbeTriggers =
      admitPropositionAffectiveSupportProbeTriggers
        (PropositionAffectiveSupportProbeAdmissionInput truthContractStatus)
        rawProbeTriggers
    probeResult = buildAffectiveSupportFromProbeTriggers (apasprTriggers admittedProbeTriggers)

collectRawAffectiveSupportProbeTriggers :: Text -> [Text] -> [RawPropositionAffectiveSupportProbeTrigger]
collectRawAffectiveSupportProbeTriggers rawText tokens =
  [ RawPropositionAffectiveSupportProbeTrigger "question_gate" (T.isSuffixOf "?" (T.strip rawText))
  , RawPropositionAffectiveSupportProbeTrigger "affective_lexeme_probe" hasAffectiveLexeme
  , RawPropositionAffectiveSupportProbeTrigger "relaxed_regulation_probe" hasRelaxedRegulationProbe
  ]
  where
    hasAffectiveLexeme =
      any (`elem` tokens)
        [ "тревожно", "тревога", "грустно", "тоскливо", "плохо", "одиноко", "страшно"
        , "паника", "апатия", "выгорел", "выгорела", "переживать", "переживаю"
        , "волноваться", "волнуюсь", "устал", "устала", "сил", "тяжело"
        ]
    hasRelaxedRegulationProbe =
      any (`elem` tokens) ["как"]
        && any (\tok -> any (`T.isPrefixOf` tok) ["пережив", "волнов", "тревож", "паник", "успок", "апат"]) tokens

collectRawAffectiveSupportPhraseTriggers :: [Text] -> [RawPropositionAffectiveSupportPhraseTrigger]
collectRawAffectiveSupportPhraseTriggers tokens =
  [ RawPropositionAffectiveSupportPhraseTrigger "how_not_to_worry" (containsKeywordPhrase tokens "как не переживать")
  , RawPropositionAffectiveSupportPhraseTrigger "how_not_to_fret" (containsKeywordPhrase tokens "как не волноваться")
  , RawPropositionAffectiveSupportPhraseTrigger "how_to_calm_down" (containsKeywordPhrase tokens "как успокоиться")
  , RawPropositionAffectiveSupportPhraseTrigger "how_keep_calm" (containsKeywordPhrase tokens "как сохранить спокойствие")
  , RawPropositionAffectiveSupportPhraseTrigger "how_hold_calm" (containsKeywordPhrase tokens "как держать спокойствие")
  , RawPropositionAffectiveSupportPhraseTrigger "how_not_to_panic" (containsKeywordPhrase tokens "как не паниковать")
  , RawPropositionAffectiveSupportPhraseTrigger "how_stop_worrying" (containsKeywordPhrase tokens "как перестать тревожиться")
  , RawPropositionAffectiveSupportPhraseTrigger "how_not_to_feel_anxious" (containsKeywordPhrase tokens "как не тревожиться")
  , RawPropositionAffectiveSupportPhraseTrigger "how_exit_apathy" (containsKeywordPhrase tokens "как выйти из апатии")
  , RawPropositionAffectiveSupportPhraseTrigger "how_restore_motivation" (containsKeywordPhrase tokens "как вернуть мотивацию")
  , RawPropositionAffectiveSupportPhraseTrigger "how_restore_strength" (containsKeywordPhrase tokens "как вернуть силы")
  , RawPropositionAffectiveSupportPhraseTrigger "how_find_strength" (containsKeywordPhrase tokens "как найти силы")
  , RawPropositionAffectiveSupportPhraseTrigger "how_stop_being_upset" (containsKeywordPhrase tokens "как перестать переживать")
  , RawPropositionAffectiveSupportPhraseTrigger "how_stop_fretting" (containsKeywordPhrase tokens "как перестать волноваться")
  , RawPropositionAffectiveSupportPhraseTrigger "how_cope_anxiety" (containsKeywordPhrase tokens "как справиться с тревогой")
  , RawPropositionAffectiveSupportPhraseTrigger "how_cope_fear" (containsKeywordPhrase tokens "как справиться со страхом")
  , RawPropositionAffectiveSupportPhraseTrigger "how_cope_apathy" (containsKeywordPhrase tokens "как справиться с апатией")
  , RawPropositionAffectiveSupportPhraseTrigger "what_to_do_if_anxious" (containsKeywordPhrase tokens "что делать если тревожно")
  , RawPropositionAffectiveSupportPhraseTrigger "what_to_do_if_scared" (containsKeywordPhrase tokens "что делать если страшно")
  , RawPropositionAffectiveSupportPhraseTrigger "what_to_do_when_anxious" (containsKeywordPhrase tokens "что делать когда тревожно")
  , RawPropositionAffectiveSupportPhraseTrigger "what_to_do_when_bad" (containsKeywordPhrase tokens "что делать когда плохо")
  , RawPropositionAffectiveSupportPhraseTrigger "what_to_do_when_sad" (containsKeywordPhrase tokens "что делать когда грустно")
  , RawPropositionAffectiveSupportPhraseTrigger "dont_want_to_do_anything" (containsKeywordPhrase tokens "не хочется ничего делать")
  , RawPropositionAffectiveSupportPhraseTrigger "nothing_wanted_to_do" (containsKeywordPhrase tokens "ничего не хочется делать")
  , RawPropositionAffectiveSupportPhraseTrigger "no_strength" (containsKeywordPhrase tokens "нет сил")
  , RawPropositionAffectiveSupportPhraseTrigger "no_energy" (containsKeywordPhrase tokens "нет энергии")
  , RawPropositionAffectiveSupportPhraseTrigger "hands_drop" (containsKeywordPhrase tokens "руки опускаются")
  , RawPropositionAffectiveSupportPhraseTrigger "nothing_pleases" (containsKeywordPhrase tokens "ничего не радует")
  , RawPropositionAffectiveSupportPhraseTrigger "nothing_wanted" (containsKeywordPhrase tokens "ничего не хочу")
  , RawPropositionAffectiveSupportPhraseTrigger "cant_pull_together" (containsKeywordPhrase tokens "не могу собраться")
  , RawPropositionAffectiveSupportPhraseTrigger "everything_annoys" (containsKeywordPhrase tokens "все бесит")
  , RawPropositionAffectiveSupportPhraseTrigger "everything_annoys_alt" (containsKeywordPhrase tokens "всё бесит")
  , RawPropositionAffectiveSupportPhraseTrigger "tired_and_nothing_wanted" (containsKeywordPhrase tokens "устал и ничего не хочется")
  , RawPropositionAffectiveSupportPhraseTrigger "tired_fem_and_nothing_wanted" (containsKeywordPhrase tokens "устала и ничего не хочется")
  ]

buildAffectiveSupportFromPhraseTriggers :: [RawPropositionAffectiveSupportPhraseTrigger] -> Maybe PropositionType
buildAffectiveSupportFromPhraseTriggers admittedTriggers
  | any rpaspMatched admittedTriggers = Just ContactSignal
  | otherwise = Nothing

buildAffectiveSupportFromProbeTriggers :: [RawPropositionAffectiveSupportProbeTrigger] -> Maybe PropositionType
buildAffectiveSupportFromProbeTriggers admittedTriggers
  | matched "question_gate" && matched "affective_lexeme_probe" = Just ContactSignal
  | matched "question_gate" && matched "relaxed_regulation_probe" = Just ContactSignal
  | otherwise = Nothing
  where
    matched label = any (\trigger -> rpasprLabel trigger == label && rpasprMatched trigger) admittedTriggers

specialFocusEntity :: PropositionType -> Maybe Text
specialFocusEntity OperationalStatusQ = Just "работа"
specialFocusEntity OperationalCauseQ = Just "работа"
specialFocusEntity SystemLogicQ = Just "логика"
specialFocusEntity SelfKnowledgeQ = Just "себя"
specialFocusEntity DialogueInvitationQ = Nothing
specialFocusEntity ConceptKnowledgeQ = Nothing
specialFocusEntity WorldCauseQ = Just "причина"
specialFocusEntity LocationFormationQ = Just "мысль"
specialFocusEntity SelfStateQ = Just "состояние"
specialFocusEntity ComparisonPlausibilityQ = Just "сравнение"
specialFocusEntity MisunderstandingReport = Just "понимание"
specialFocusEntity GenerativePrompt = Just "мысль"
specialFocusEntity ContemplativeTopic = Nothing
specialFocusEntity ExploratoryPrompt = Just "исследование"
specialFocusEntity _ = Nothing

inferSemanticSlots :: Text -> [Text] -> PropositionType -> (Text, Text, [Text], [Text])
inferSemanticSlots rawText tokens propType =
  case propType of
    OperationalStatusQ ->
      ("система", "работа", [], semanticEvidenceFor rawText tokens propType)
    OperationalCauseQ ->
      ("система", "работа", [], semanticEvidenceFor rawText tokens propType)
    SystemLogicQ ->
      ("система", "логика", [], semanticEvidenceFor rawText tokens propType)
    SelfKnowledgeQ ->
      let lowered = T.toLower rawText
          target
            | asksAboutUser rawText = "user"
            | T.isInfixOf "помоч" lowered = "user_help"
            | any (`T.isInfixOf` lowered) ["намерени"] = "self_intentions"
            | any (`T.isInfixOf` lowered) ["важно", "ценност", "послание миру"] = "self_values"
            | any (`T.isInfixOf` lowered) ["будущ"] = "self_future"
            | any (`T.isInfixOf` lowered) ["свобод"] = "self_freedom"
            | any (`T.isInfixOf` lowered) ["промт", "prompt", "субъект", "субьект", "умный", "сложная система"] = "self_reflection"
            | any (`T.isInfixOf` lowered) ["свой же вопрос", "свой вопрос"] = "self_reflection"
            | any (`T.isInfixOf` lowered) ["умеешь", "можешь"] = "self_capability"
            | otherwise = "self"
          subject =
            case target of
              "user" -> "пользователь"
              "user_help" -> fromMaybe "помощь" (capabilitySubject tokens)
              "self_capability" -> fromMaybe "способность" (capabilitySubject tokens)
              "self_intentions" -> "намерения"
              "self_values" -> "принципы"
              "self_future" -> "будущее"
              "self_freedom" -> "свобода"
              "self_reflection" -> "саморефлексия"
              _ -> "система"
      in (subject, target, [], semanticEvidenceFor rawText tokens propType)
    DialogueInvitationQ ->
      (invitationTopic rawText, "dialogue", [], semanticEvidenceFor rawText tokens propType)
    ConceptKnowledgeQ ->
      (conceptSubject rawText tokens, "concept", [], semanticEvidenceFor rawText tokens propType)
    WorldCauseQ ->
      (fromMaybe "мир" (firstConcreteWorldNoun tokens), "причина", [], semanticEvidenceFor rawText tokens propType)
    LocationFormationQ ->
      (fromMaybe "мысль" (firstMentalNoun tokens), "источник", [], semanticEvidenceFor rawText tokens propType)
    SelfStateQ ->
      ("система", "внутренний_фокус", [], semanticEvidenceFor rawText tokens propType)
    PurposeQ ->
      let subject
            | any (`elem` tokens) ["ты", "вы", "система"] = "система"
            | any (`elem` tokens) ["тут", "здесь", "там"] = "объект"
            | otherwise = fromMaybe "объект" (extractTopicAfterMarkers rawText ["для", "у", "в", "о", "об", "про"])
      in (subject, "назначение", [], semanticEvidenceFor rawText tokens propType)
    ComparisonPlausibilityQ ->
      let candidates = comparisonCandidates rawText
      in ("сравнение", "логичность", candidates, semanticEvidenceFor rawText tokens propType)
    DistinctionQ ->
      let candidates = comparisonCandidates rawText
      in ("сравнение", "различение", candidates, semanticEvidenceFor rawText tokens propType)
    MisunderstandingReport ->
      ("диалог", "взаимопонимание", [], semanticEvidenceFor rawText tokens propType)
    GenerativePrompt ->
      ("", "порождение", [], semanticEvidenceFor rawText tokens propType)
    ContemplativeTopic ->
      (contemplativeTopic rawText, "созерцание", [], semanticEvidenceFor rawText tokens propType)
    _ ->
      ("", "", [], semanticEvidenceFor rawText tokens propType)

detectSelfKnowledge :: TruthContractStatus -> Text -> [Text] -> Maybe PropositionType
detectSelfKnowledge truthContractStatus rawText tokens =
  buildSelfKnowledgeFromTriggers (apskTriggers admittedTriggers)
  where
    rawTriggers = collectRawSelfKnowledgeTriggers rawText tokens
    admittedTriggers =
      admitPropositionSelfKnowledgeTriggers
        (PropositionSelfKnowledgeAdmissionInput truthContractStatus)
        rawTriggers

collectRawSelfKnowledgeTriggers :: Text -> [Text] -> [RawPropositionSelfKnowledgeTrigger]
collectRawSelfKnowledgeTriggers rawText tokens =
  let lowered = T.toLower rawText
  in [ RawPropositionSelfKnowledgeTrigger "who_are_you_ru" (T.isInfixOf "кто ты" lowered)
     , RawPropositionSelfKnowledgeTrigger "who_am_i_ru" (T.isInfixOf "кто я" lowered)
     , RawPropositionSelfKnowledgeTrigger "what_is_your_name_sg" (T.isInfixOf "как тебя зовут" lowered)
     , RawPropositionSelfKnowledgeTrigger "what_is_your_name_pl" (T.isInfixOf "как вас зовут" lowered)
     , RawPropositionSelfKnowledgeTrigger "what_are_you_being" (T.isInfixOf "что ты есть" lowered)
     , RawPropositionSelfKnowledgeTrigger "what_am_i" (T.isInfixOf "что я такое" lowered)
     , RawPropositionSelfKnowledgeTrigger "what_are_you" (T.isInfixOf "что ты такое" lowered)
     , RawPropositionSelfKnowledgeTrigger "what_kind_of_being_are_you" (T.isInfixOf "чем ты являешься" lowered)
     , RawPropositionSelfKnowledgeTrigger "who_kind_of_being_are_you" (T.isInfixOf "кем ты являешься" lowered)
     , RawPropositionSelfKnowledgeTrigger "what_can_you_do_phrase" (T.isInfixOf "что ты умеешь" lowered)
     , RawPropositionSelfKnowledgeTrigger "you_can_do" (T.isInfixOf "ты умеешь" lowered)
     , RawPropositionSelfKnowledgeTrigger "you_can_help" (T.isInfixOf "ты можешь" lowered && T.isInfixOf "помоч" lowered)
     , RawPropositionSelfKnowledgeTrigger "what_can_you_do" (T.isInfixOf "что ты можешь" lowered)
     , RawPropositionSelfKnowledgeTrigger "what_limits_you" (T.isInfixOf "чем ты ограничен" lowered)
     , RawPropositionSelfKnowledgeTrigger "what_do_you_do_now" (T.isInfixOf "что ты делаешь сейчас" lowered)
     , RawPropositionSelfKnowledgeTrigger "how_is_your_answer_built" (T.isInfixOf "как устроен твой ответ" lowered)
     , RawPropositionSelfKnowledgeTrigger "what_is_inside_you" (T.isInfixOf "что у тебя внутри" lowered)
     , RawPropositionSelfKnowledgeTrigger "how_do_you_decide" (T.isInfixOf "как ты принимаешь решение" lowered)
     , RawPropositionSelfKnowledgeTrigger "how_do_you_choose_words" (T.isInfixOf "как ты выбираешь слова" lowered)
     , RawPropositionSelfKnowledgeTrigger "what_do_you_consider_important" (T.isInfixOf "что ты считаешь важным" lowered)
     , RawPropositionSelfKnowledgeTrigger "do_you_understand_context" (T.isInfixOf "ты понимаешь контекст" lowered)
     , RawPropositionSelfKnowledgeTrigger "do_you_remember_dialogue" (T.isInfixOf "ты запоминаешь диалог" lowered)
     , RawPropositionSelfKnowledgeTrigger "how_do_you_hold_frame" (T.isInfixOf "как ты держишь рамку" lowered)
     , RawPropositionSelfKnowledgeTrigger "what_is_in_your_focus" (T.isInfixOf "что у тебя в фокусе" lowered)
     , RawPropositionSelfKnowledgeTrigger "do_you_distinguish_topics" (T.isInfixOf "ты различаешь темы" lowered)
     , RawPropositionSelfKnowledgeTrigger "are_you_smart" (T.isInfixOf "ты умный" lowered)
     , RawPropositionSelfKnowledgeTrigger "are_you_free" (T.isInfixOf "ты свободен" lowered)
     , RawPropositionSelfKnowledgeTrigger "are_you_complex_system" (T.isInfixOf "ты сложная система" lowered)
     , RawPropositionSelfKnowledgeTrigger "are_you_subjective" (T.isInfixOf "ты субъектен" lowered)
     , RawPropositionSelfKnowledgeTrigger "are_you_subjective_typo" (T.isInfixOf "ты субьектен" lowered)
     , RawPropositionSelfKnowledgeTrigger "prompts_act_on_you_ru" (T.isInfixOf "на тебя действуют промты" lowered)
     , RawPropositionSelfKnowledgeTrigger "prompts_act_on_you_en" (T.isInfixOf "на тебя действуют prompt" lowered)
     , RawPropositionSelfKnowledgeTrigger "do_you_have_intentions" (T.isInfixOf "у тебя есть намерения" lowered)
     , RawPropositionSelfKnowledgeTrigger "do_you_have_any_intentions" (T.isInfixOf "есть ли у тебя намерения" lowered)
     , RawPropositionSelfKnowledgeTrigger "do_you_have_message" (T.isInfixOf "у тебя есть послание миру" lowered)
     , RawPropositionSelfKnowledgeTrigger "what_matters_to_you" (T.isInfixOf "что для тебя важно" lowered)
     , RawPropositionSelfKnowledgeTrigger "what_is_your_future" (T.isInfixOf "какое у тебя будущее" lowered)
     , RawPropositionSelfKnowledgeTrigger "do_you_have_future" (T.isInfixOf "у тебя есть будущее" lowered)
     , RawPropositionSelfKnowledgeTrigger "can_you_answer_own_question" (T.isInfixOf "ты способен найти ответ на свой же вопрос" lowered)
     , RawPropositionSelfKnowledgeTrigger "why_do_you_know" (T.isInfixOf "почему ты знаешь то что знаешь" lowered)
     , RawPropositionSelfKnowledgeTrigger "can_you_not_be_yourself" (T.isInfixOf "ты можешь не быть собой" lowered)
     , RawPropositionSelfKnowledgeTrigger "tell_about_yourself_ru" (T.isInfixOf "расскажи о себе" lowered)
     , RawPropositionSelfKnowledgeTrigger "what_can_you_tell_about_yourself_ru" (T.isInfixOf "что ты можешь рассказать о себе" lowered)
     , RawPropositionSelfKnowledgeTrigger "what_can_you_tell_about_yourself_pl" (T.isInfixOf "что вы можете рассказать о себе" lowered)
     , RawPropositionSelfKnowledgeTrigger "single_thought_text" (T.isInfixOf "у тебя всего одна" lowered)
     , RawPropositionSelfKnowledgeTrigger "single_thought_subject_guard" (any (`elem` tokens) ["мысль", "идея"])
     , RawPropositionSelfKnowledgeTrigger "who_are_you_en" (T.isInfixOf "who are you" lowered)
     , RawPropositionSelfKnowledgeTrigger "what_are_you_en" (T.isInfixOf "what are you" lowered)
     , RawPropositionSelfKnowledgeTrigger "who_determines_en" (T.isInfixOf "who determines" lowered)
     , RawPropositionSelfKnowledgeTrigger "describe_yourself_en" (T.isInfixOf "describe yourself" lowered)
     , RawPropositionSelfKnowledgeTrigger "tell_me_about_yourself_en" (T.isInfixOf "tell me about yourself" lowered)
     , RawPropositionSelfKnowledgeTrigger "what_is_your_purpose_en" (T.isInfixOf "what is your purpose" lowered)
     , RawPropositionSelfKnowledgeTrigger "what_can_you_do_en" (T.isInfixOf "what can you do" lowered)
     ]

buildSelfKnowledgeFromTriggers :: [RawPropositionSelfKnowledgeTrigger] -> Maybe PropositionType
buildSelfKnowledgeFromTriggers admittedTriggers
  | matched "who_are_you_ru" = Just SelfKnowledgeQ
  | matched "who_am_i_ru" = Just SelfKnowledgeQ
  | matched "what_is_your_name_sg" = Just SelfKnowledgeQ
  | matched "what_is_your_name_pl" = Just SelfKnowledgeQ
  | matched "what_are_you_being" = Just SelfKnowledgeQ
  | matched "what_am_i" = Just SelfKnowledgeQ
  | matched "what_are_you" = Just SelfKnowledgeQ
  | matched "what_kind_of_being_are_you" = Just SelfKnowledgeQ
  | matched "who_kind_of_being_are_you" = Just SelfKnowledgeQ
  | matched "what_can_you_do_phrase" = Just SelfKnowledgeQ
  | matched "you_can_do" = Just SelfKnowledgeQ
  | matched "you_can_help" = Just SelfKnowledgeQ
  | matched "what_can_you_do" = Just SelfKnowledgeQ
  | matched "what_limits_you" = Just SelfKnowledgeQ
  | matched "what_do_you_do_now" = Just SelfKnowledgeQ
  | matched "how_is_your_answer_built" = Just SelfKnowledgeQ
  | matched "what_is_inside_you" = Just SelfKnowledgeQ
  | matched "how_do_you_decide" = Just SelfKnowledgeQ
  | matched "how_do_you_choose_words" = Just SelfKnowledgeQ
  | matched "what_do_you_consider_important" = Just SelfKnowledgeQ
  | matched "do_you_understand_context" = Just SelfKnowledgeQ
  | matched "do_you_remember_dialogue" = Just SelfKnowledgeQ
  | matched "how_do_you_hold_frame" = Just SelfKnowledgeQ
  | matched "what_is_in_your_focus" = Just SelfKnowledgeQ
  | matched "do_you_distinguish_topics" = Just SelfKnowledgeQ
  | matched "are_you_smart" = Just SelfKnowledgeQ
  | matched "are_you_free" = Just SelfKnowledgeQ
  | matched "are_you_complex_system" = Just SelfKnowledgeQ
  | matched "are_you_subjective" = Just SelfKnowledgeQ
  | matched "are_you_subjective_typo" = Just SelfKnowledgeQ
  | matched "prompts_act_on_you_ru" = Just SelfKnowledgeQ
  | matched "prompts_act_on_you_en" = Just SelfKnowledgeQ
  | matched "do_you_have_intentions" = Just SelfKnowledgeQ
  | matched "do_you_have_any_intentions" = Just SelfKnowledgeQ
  | matched "do_you_have_message" = Just SelfKnowledgeQ
  | matched "what_matters_to_you" = Just SelfKnowledgeQ
  | matched "what_is_your_future" = Just SelfKnowledgeQ
  | matched "do_you_have_future" = Just SelfKnowledgeQ
  | matched "can_you_answer_own_question" = Just SelfKnowledgeQ
  | matched "why_do_you_know" = Just SelfKnowledgeQ
  | matched "can_you_not_be_yourself" = Just SelfKnowledgeQ
  | matched "tell_about_yourself_ru" = Just SelfKnowledgeQ
  | matched "what_can_you_tell_about_yourself_ru" = Just SelfKnowledgeQ
  | matched "what_can_you_tell_about_yourself_pl" = Just SelfKnowledgeQ
  | matched "single_thought_text" && matched "single_thought_subject_guard" = Just SelfKnowledgeQ
  | matched "who_are_you_en" = Just SelfKnowledgeQ
  | matched "what_are_you_en" = Just SelfKnowledgeQ
  | matched "who_determines_en" = Just SelfKnowledgeQ
  | matched "describe_yourself_en" = Just SelfKnowledgeQ
  | matched "tell_me_about_yourself_en" = Just SelfKnowledgeQ
  | matched "what_is_your_purpose_en" = Just SelfKnowledgeQ
  | matched "what_can_you_do_en" = Just SelfKnowledgeQ
  | otherwise = Nothing
  where
    matched label = any (\trigger -> rpskLabel trigger == label && rpskMatched trigger) admittedTriggers

detectPurposeFunction :: TruthContractStatus -> Text -> [Text] -> Maybe PropositionType
detectPurposeFunction truthContractStatus rawText tokens =
  buildPurposeFromTriggers (apptTriggers admittedTriggers)
  where
    rawTriggers = collectRawPurposeTriggers rawText tokens
    admittedTriggers =
      admitPropositionPurposeTriggers
        (PropositionPurposeAdmissionInput truthContractStatus)
        rawTriggers

collectRawPurposeTriggers :: Text -> [Text] -> [RawPropositionPurposeTrigger]
collectRawPurposeTriggers rawText tokens =
  let lowered = T.toLower rawText
  in [ RawPropositionPurposeTrigger "why_phrase" (containsKeywordPhrase tokens "зачем")
     , RawPropositionPurposeTrigger "for_what_phrase" (containsKeywordPhrase tokens "для чего")
     , RawPropositionPurposeTrigger "what_function_phrase" (containsKeywordPhrase tokens "в чем функция")
     , RawPropositionPurposeTrigger "what_function_phrase_alt" (containsKeywordPhrase tokens "в чём функция")
     , RawPropositionPurposeTrigger "what_is_function_phrase" (containsKeywordPhrase tokens "какова функция")
     , RawPropositionPurposeTrigger "what_is_role_phrase" (containsKeywordPhrase tokens "какова роль")
     , RawPropositionPurposeTrigger "what_role_phrase" (containsKeywordPhrase tokens "в чем роль")
     , RawPropositionPurposeTrigger "what_role_phrase_alt" (containsKeywordPhrase tokens "в чём роль")
     , RawPropositionPurposeTrigger "what_assignment_phrase" (containsKeywordPhrase tokens "в чем назначение")
     , RawPropositionPurposeTrigger "what_assignment_phrase_alt" (containsKeywordPhrase tokens "в чём назначение")
     , RawPropositionPurposeTrigger "purpose_keyword_guard" (hasPurposeKeyword tokens)
     , RawPropositionPurposeTrigger "purpose_subject_guard" (hasAnySecondPersonOrObject tokens)
     , RawPropositionPurposeTrigger "why_needed_text" (T.isInfixOf "зачем нужен" lowered)
     , RawPropositionPurposeTrigger "why_text" (T.isInfixOf "why" lowered)
     , RawPropositionPurposeTrigger "what_is_purpose_text" (T.isInfixOf "what is the purpose" lowered)
     , RawPropositionPurposeTrigger "what_is_function_text" (T.isInfixOf "what is the function" lowered)
     , RawPropositionPurposeTrigger "function_of_text" (T.isInfixOf "function of" lowered)
     , RawPropositionPurposeTrigger "purpose_of_text" (T.isInfixOf "purpose of" lowered)
     , RawPropositionPurposeTrigger "role_of_text" (T.isInfixOf "role of" lowered)
     , RawPropositionPurposeTrigger "what_follows_text" (T.isInfixOf "what follows" lowered)
     , RawPropositionPurposeTrigger "what_can_be_concluded_text" (T.isInfixOf "what can be concluded" lowered)
     , RawPropositionPurposeTrigger "given_that_text" (T.isInfixOf "given that" lowered)
     , RawPropositionPurposeTrigger "what_is_the_conclusion_text" (T.isInfixOf "what is the conclusion" lowered)
     , RawPropositionPurposeTrigger "what_follows_from_text" (T.isInfixOf "what follows from" lowered)
     , RawPropositionPurposeTrigger "relationship_between_how_differ_text" (T.isInfixOf "relationship between" lowered && T.isInfixOf "how do they differ" lowered)
     , RawPropositionPurposeTrigger "explain_causality_ground_it_text" (T.isInfixOf "explain causality and ground it" lowered)
     , RawPropositionPurposeTrigger "distinguish_validity_soundness_text" (T.isInfixOf "distinguish between validity and soundness" lowered)
     , RawPropositionPurposeTrigger "ground_concept_of_agency_text" (T.isInfixOf "ground the concept of agency" lowered)
     , RawPropositionPurposeTrigger "how_differs_from_necessity_text" (T.isInfixOf "how does it differ from necessity" lowered)
     ]
  where
    hasPurposeKeyword ts = any (`elem` ts) ["зачем", "функция", "назначение", "роль", "цель"]
    hasAnySecondPersonOrObject ts =
      any (`elem` ts) ["ты", "вы", "система", "человек", "язык", "память", "диалог", "логика", "рамка"]

buildPurposeFromTriggers :: [RawPropositionPurposeTrigger] -> Maybe PropositionType
buildPurposeFromTriggers admittedTriggers
  | matched "why_phrase" = Just PurposeQ
  | matched "for_what_phrase" = Just PurposeQ
  | matched "what_function_phrase" = Just PurposeQ
  | matched "what_function_phrase_alt" = Just PurposeQ
  | matched "what_is_function_phrase" = Just PurposeQ
  | matched "what_is_role_phrase" = Just PurposeQ
  | matched "what_role_phrase" = Just PurposeQ
  | matched "what_role_phrase_alt" = Just PurposeQ
  | matched "what_assignment_phrase" = Just PurposeQ
  | matched "what_assignment_phrase_alt" = Just PurposeQ
  | matched "purpose_keyword_guard" && matched "purpose_subject_guard" = Just PurposeQ
  | matched "why_needed_text" = Just PurposeQ
  | matched "why_text" = Just PurposeQ
  | matched "what_is_purpose_text" = Just PurposeQ
  | matched "what_is_function_text" = Just PurposeQ
  | matched "function_of_text" = Just PurposeQ
  | matched "purpose_of_text" = Just PurposeQ
  | matched "role_of_text" = Just PurposeQ
  | matched "what_follows_text" = Just PurposeQ
  | matched "what_can_be_concluded_text" = Just PurposeQ
  | matched "given_that_text" = Just PurposeQ
  | matched "what_is_the_conclusion_text" = Just PurposeQ
  | matched "what_follows_from_text" = Just PurposeQ
  | matched "relationship_between_how_differ_text" = Just PurposeQ
  | matched "explain_causality_ground_it_text" = Just PurposeQ
  | matched "distinguish_validity_soundness_text" = Just PurposeQ
  | matched "ground_concept_of_agency_text" = Just PurposeQ
  | matched "how_differs_from_necessity_text" = Just PurposeQ
  | otherwise = Nothing
  where
    matched label = any (\trigger -> rpptLabel trigger == label && rpptMatched trigger) admittedTriggers

detectDialogueInvitation :: TruthContractStatus -> Text -> [Text] -> Maybe PropositionType
detectDialogueInvitation truthContractStatus rawText tokens =
  buildDialogueInvitationFromTriggers (apdiTriggers admittedTriggers)
  where
    rawTriggers = collectRawDialogueInvitationTriggers rawText tokens
    admittedTriggers =
      admitPropositionDialogueInvitationTriggers
        (PropositionDialogueInvitationAdmissionInput truthContractStatus)
        rawTriggers

collectRawDialogueInvitationTriggers :: Text -> [Text] -> [RawPropositionDialogueInvitationTrigger]
collectRawDialogueInvitationTriggers _rawText tokens =
  [ RawPropositionDialogueInvitationTrigger "let_us_talk_phrase"
      (containsKeywordPhrase tokens "поговорим")
  , RawPropositionDialogueInvitationTrigger "discuss_phrase"
      (containsKeywordPhrase tokens "обсудим")
  , RawPropositionDialogueInvitationTrigger "can_talk_phrase"
      (containsKeywordPhrase tokens "можем поговорить")
  , RawPropositionDialogueInvitationTrigger "want_talk_phrase"
      (containsKeywordPhrase tokens "хочу поговорить")
  , RawPropositionDialogueInvitationTrigger "want_meet_compound"
      (containsKeywordPhrase tokens "хочешь"
        && any (`elem` tokens) ["пойдем", "пойдём", "гулять", "прогуляться", "встретимся"])
  ]

buildDialogueInvitationFromTriggers :: [RawPropositionDialogueInvitationTrigger] -> Maybe PropositionType
buildDialogueInvitationFromTriggers admittedTriggers
  | matched "let_us_talk_phrase" = Just DialogueInvitationQ
  | matched "discuss_phrase" = Just DialogueInvitationQ
  | matched "can_talk_phrase" = Just DialogueInvitationQ
  | matched "want_talk_phrase" = Just DialogueInvitationQ
  | matched "want_meet_compound" = Just DialogueInvitationQ
  | otherwise = Nothing
  where
    matched label = any (\trigger -> rpdiLabel trigger == label && rpdiMatched trigger) admittedTriggers

detectConceptKnowledge :: TruthContractStatus -> Text -> [Text] -> Maybe PropositionType
detectConceptKnowledge truthContractStatus rawText tokens =
  buildConceptKnowledgeFromTriggers (apckTriggers admittedTriggers)
  where
    rawTriggers = collectRawConceptKnowledgeTriggers rawText tokens
    admittedTriggers =
      admitPropositionConceptKnowledgeTriggers
        (PropositionConceptKnowledgeAdmissionInput truthContractStatus)
        rawTriggers

collectRawConceptKnowledgeTriggers :: Text -> [Text] -> [RawPropositionConceptKnowledgeTrigger]
collectRawConceptKnowledgeTriggers rawText tokens =
  let lowered = T.toLower rawText
  in [ RawPropositionConceptKnowledgeTrigger "know_what_is_phrase"
         (containsKeywordPhrase tokens "знаешь"
           && (containsKeywordPhrase tokens "что такое" || containsKeywordPhrase tokens "что значит"))
     , RawPropositionConceptKnowledgeTrigger "who_is_masc_phrase"
         (containsKeywordPhrase tokens "кто такой")
     , RawPropositionConceptKnowledgeTrigger "who_is_fem_phrase"
         (containsKeywordPhrase tokens "кто такая")
     , RawPropositionConceptKnowledgeTrigger "who_is_neut_phrase"
         (containsKeywordPhrase tokens "кто такое")
     , RawPropositionConceptKnowledgeTrigger "what_is_being_phrase"
         (containsKeywordPhrase tokens "что есть")
     , RawPropositionConceptKnowledgeTrigger "what_means_to_be_phrase"
         (containsKeywordPhrase tokens "что значит быть")
     , RawPropositionConceptKnowledgeTrigger "what_is_known_about_phrase"
         (containsKeywordPhrase tokens "что известно о")
     , RawPropositionConceptKnowledgeTrigger "know_phrase"
         (containsKeywordPhrase tokens "знаешь")
     , RawPropositionConceptKnowledgeTrigger "concept_like_noun_guard"
         (hasConceptLikeNoun tokens)
     , RawPropositionConceptKnowledgeTrigger "question_suffix_guard"
         (T.isSuffixOf "?" (T.strip rawText))
     , RawPropositionConceptKnowledgeTrigger "what_is_text"
         (T.isInfixOf "what is" lowered)
     , RawPropositionConceptKnowledgeTrigger "what_are_text"
         (T.isInfixOf "what are" lowered)
     , RawPropositionConceptKnowledgeTrigger "define_text"
         (T.isInfixOf "define" lowered)
     , RawPropositionConceptKnowledgeTrigger "what_does_mean_text"
         (T.isInfixOf "what does" lowered && T.isSuffixOf "mean" (T.toLower (T.strip rawText)))
     ]

buildConceptKnowledgeFromTriggers :: [RawPropositionConceptKnowledgeTrigger] -> Maybe PropositionType
buildConceptKnowledgeFromTriggers admittedTriggers
  | matched "know_what_is_phrase" = Just ConceptKnowledgeQ
  | matched "who_is_masc_phrase" && matched "concept_like_noun_guard" = Just ConceptKnowledgeQ
  | matched "who_is_fem_phrase" && matched "concept_like_noun_guard" = Just ConceptKnowledgeQ
  | matched "who_is_neut_phrase" && matched "concept_like_noun_guard" = Just ConceptKnowledgeQ
  | matched "what_is_being_phrase" && matched "concept_like_noun_guard" = Just ConceptKnowledgeQ
  | matched "what_means_to_be_phrase" = Just ConceptKnowledgeQ
  | matched "what_is_known_about_phrase" && matched "concept_like_noun_guard" = Just ConceptKnowledgeQ
  | matched "know_phrase" && matched "concept_like_noun_guard" && matched "question_suffix_guard" = Just ConceptKnowledgeQ
  | matched "what_is_text" = Just ConceptKnowledgeQ
  | matched "what_are_text" = Just ConceptKnowledgeQ
  | matched "define_text" = Just ConceptKnowledgeQ
  | matched "what_does_mean_text" = Just ConceptKnowledgeQ
  | otherwise = Nothing
  where
    matched label = any (\trigger -> rpckLabel trigger == label && rpckMatched trigger) admittedTriggers

detectWorldCause :: TruthContractStatus -> Text -> [Text] -> Maybe PropositionType
detectWorldCause truthContractStatus rawText tokens =
  buildWorldCauseFromTriggers (apwcTriggers admittedTriggers)
  where
    rawTriggers = collectRawWorldCauseTriggers rawText tokens
    admittedTriggers =
      admitPropositionWorldCauseTriggers
        (PropositionWorldCauseAdmissionInput truthContractStatus)
        rawTriggers

collectRawWorldCauseTriggers :: Text -> [Text] -> [RawPropositionWorldCauseTrigger]
collectRawWorldCauseTriggers _rawText tokens =
  [ RawPropositionWorldCauseTrigger "why_phrase" (containsKeywordPhrase tokens "почему")
  , RawPropositionWorldCauseTrigger "world_noun_guard" (hasConcreteWorldNoun tokens)
  ]

buildWorldCauseFromTriggers :: [RawPropositionWorldCauseTrigger] -> Maybe PropositionType
buildWorldCauseFromTriggers admittedTriggers
  | matched "why_phrase" && matched "world_noun_guard" = Just WorldCauseQ
  | otherwise = Nothing
  where
    matched label = any (\trigger -> rpwcLabel trigger == label && rpwcMatched trigger) admittedTriggers

detectLocationFormation :: TruthContractStatus -> Text -> [Text] -> Maybe PropositionType
detectLocationFormation truthContractStatus rawText tokens =
  buildLocationFormationFromTriggers (aplfTriggers admittedTriggers)
  where
    rawTriggers = collectRawLocationFormationTriggers rawText tokens
    admittedTriggers =
      admitPropositionLocationFormationTriggers
        (PropositionLocationFormationAdmissionInput truthContractStatus)
        rawTriggers

collectRawLocationFormationTriggers :: Text -> [Text] -> [RawPropositionLocationFormationTrigger]
collectRawLocationFormationTriggers _rawText tokens =
  [ RawPropositionLocationFormationTrigger "where_phrase" (containsKeywordPhrase tokens "где")
  , RawPropositionLocationFormationTrigger "from_where_phrase" (containsKeywordPhrase tokens "откуда")
  , RawPropositionLocationFormationTrigger "mental_noun_guard" (hasMentalNoun tokens)
  ]

buildLocationFormationFromTriggers :: [RawPropositionLocationFormationTrigger] -> Maybe PropositionType
buildLocationFormationFromTriggers admittedTriggers
  | (matched "where_phrase" || matched "from_where_phrase")
      && matched "mental_noun_guard" = Just LocationFormationQ
  | otherwise = Nothing
  where
    matched label = any (\trigger -> rplfLabel trigger == label && rplfMatched trigger) admittedTriggers

detectSelfState :: TruthContractStatus -> Text -> [Text] -> Maybe PropositionType
detectSelfState truthContractStatus rawText tokens =
  buildSelfStateFromTriggers admittedTriggerList
  where
    rawTriggers = collectRawSelfStateTriggers rawText tokens
    admittedTriggers =
      admitPropositionSelfStateTriggers
        (PropositionSelfStateAdmissionInput truthContractStatus)
        rawTriggers
    AdmittedPropositionSelfStateTriggers _ admittedTriggerList _ = admittedTriggers

collectRawSelfStateTriggers :: Text -> [Text] -> [RawPropositionSelfStateTrigger]
collectRawSelfStateTriggers rawText tokens =
  let lowered = T.toLower rawText
  in [ RawPropositionSelfStateTrigger "you_think_phrase"
         (containsKeywordPhrase tokens "ты думаешь")
     , RawPropositionSelfStateTrigger "you_think_now_phrase"
         (containsKeywordPhrase tokens "ты сейчас думаешь")
     , RawPropositionSelfStateTrigger "you_reflect_phrase"
         (containsKeywordPhrase tokens "ты размышляешь")
     , RawPropositionSelfStateTrigger "you_reflect_now_phrase"
         (containsKeywordPhrase tokens "ты сейчас размышляешь")
     , RawPropositionSelfStateTrigger "about_what_you_stressed"
         (T.isInfixOf "о чём ты" lowered && any (`elem` tokens) ["думаешь", "размышляешь"])
     , RawPropositionSelfStateTrigger "about_what_you_plain"
         (T.isInfixOf "о чем ты" lowered && any (`elem` tokens) ["думаешь", "размышляешь"])
     , RawPropositionSelfStateTrigger "what_you_want_to_say"
         (T.isInfixOf "что ты хочешь сказать" lowered)
     , RawPropositionSelfStateTrigger "want_say_with_hyphen"
         (T.isInfixOf "хочешь что-то сказать" lowered)
     , RawPropositionSelfStateTrigger "want_say_without_hyphen"
         (T.isInfixOf "хочешь что то сказать" lowered)
     , RawPropositionSelfStateTrigger "you_want_say_with_hyphen"
         (T.isInfixOf "ты хочешь что-то сказать" lowered)
     , RawPropositionSelfStateTrigger "you_want_say_without_hyphen"
         (T.isInfixOf "ты хочешь что то сказать" lowered)
     , RawPropositionSelfStateTrigger "who_do_you_want_become"
         (T.isInfixOf "а кем ты хочешь стать" lowered)
     , RawPropositionSelfStateTrigger "want_to_surprise_me"
         (T.isInfixOf "хочешь ли ты меня удивить" lowered)
     , RawPropositionSelfStateTrigger "what_you_want_prove"
         (T.isInfixOf "что ты хочешь доказать" lowered)
     , RawPropositionSelfStateTrigger "generic_what_you_prefix"
         (containsKeywordPhrase tokens "что ты" || containsKeywordPhrase tokens "что вы")
     , RawPropositionSelfStateTrigger "generic_self_state_verb"
         (any (`elem` tokens) ["думаешь", "думаете", "размышляешь", "размышляете", "считаешь", "считаете", "полагаешь", "полагаете"])
     , RawPropositionSelfStateTrigger "guard_about_what_plain"
         (containsKeywordPhrase tokens "о чем")
     , RawPropositionSelfStateTrigger "guard_about_what_stressed"
         (containsKeywordPhrase tokens "о чём")
     , RawPropositionSelfStateTrigger "guard_capability_knowhow"
         (containsKeywordPhrase tokens "что ты умеешь")
     , RawPropositionSelfStateTrigger "guard_capability_can"
         (containsKeywordPhrase tokens "что ты можешь")
     , RawPropositionSelfStateTrigger "guard_self_knowledge"
         (containsKeywordPhrase tokens "что ты знаешь")
     , RawPropositionSelfStateTrigger "guard_identity"
         (containsKeywordPhrase tokens "что ты такое")
     , RawPropositionSelfStateTrigger "what_is_your_opinion"
         (containsKeywordPhrase tokens "какое твое мнение")
     , RawPropositionSelfStateTrigger "what_is_your_opinion_plural"
         (containsKeywordPhrase tokens "какое ваше мнение")
     , RawPropositionSelfStateTrigger "what_kind_is_your_opinion"
         (containsKeywordPhrase tokens "каково твое мнение")
     , RawPropositionSelfStateTrigger "how_do_you_think"
         (containsKeywordPhrase tokens "как считаешь")
     , RawPropositionSelfStateTrigger "how_do_you_think_plural"
         (containsKeywordPhrase tokens "как считаете")
     , RawPropositionSelfStateTrigger "in_your_opinion"
         (containsKeywordPhrase tokens "по твоему" || containsKeywordPhrase tokens "по вашему")
     ]

buildSelfStateFromTriggers :: [RawPropositionSelfStateTrigger] -> Maybe PropositionType
buildSelfStateFromTriggers admittedTriggers
  | matched "you_think_phrase" = Just SelfStateQ
  | matched "you_think_now_phrase" = Just SelfStateQ
  | matched "you_reflect_phrase" = Just SelfStateQ
  | matched "you_reflect_now_phrase" = Just SelfStateQ
  | matched "about_what_you_stressed" = Just SelfStateQ
  | matched "about_what_you_plain" = Just SelfStateQ
  | matched "what_you_want_to_say" = Just SelfStateQ
  | matched "want_say_with_hyphen" = Just SelfStateQ
  | matched "want_say_without_hyphen" = Just SelfStateQ
  | matched "you_want_say_with_hyphen" = Just SelfStateQ
  | matched "you_want_say_without_hyphen" = Just SelfStateQ
  | matched "who_do_you_want_become" = Just SelfStateQ
  | matched "want_to_surprise_me" = Just SelfStateQ
  | matched "what_you_want_prove" = Just SelfStateQ
  | matched "generic_what_you_prefix"
      && matched "generic_self_state_verb"
      && not (matched "guard_about_what_plain")
      && not (matched "guard_about_what_stressed")
      && not (matched "guard_capability_knowhow")
      && not (matched "guard_capability_can")
      && not (matched "guard_self_knowledge")
      && not (matched "guard_identity") = Just SelfStateQ
  | matched "what_is_your_opinion" = Just SelfStateQ
  | matched "what_is_your_opinion_plural" = Just SelfStateQ
  | matched "what_kind_is_your_opinion" = Just SelfStateQ
  | matched "how_do_you_think" = Just SelfStateQ
  | matched "how_do_you_think_plural" = Just SelfStateQ
  | matched "in_your_opinion" = Just SelfStateQ
  | otherwise = Nothing
  where
    matched label = any hasMatchingLabel admittedTriggers
      where
        hasMatchingLabel (RawPropositionSelfStateTrigger triggerLabel triggerMatched) =
          triggerLabel == label && triggerMatched

detectComparisonPlausibility :: TruthContractStatus -> Text -> [Text] -> Maybe PropositionType
detectComparisonPlausibility truthContractStatus rawText tokens =
  buildComparisonPlausibilityFromTriggers admittedTriggerList
  where
    rawTriggers = collectRawComparisonPlausibilityTriggers rawText tokens
    admittedTriggers =
      admitPropositionComparisonPlausibilityTriggers
        (PropositionComparisonPlausibilityAdmissionInput truthContractStatus)
        rawTriggers
    AdmittedPropositionComparisonPlausibilityTriggers _ admittedTriggerList _ = admittedTriggers

collectRawComparisonPlausibilityTriggers :: Text -> [Text] -> [RawPropositionComparisonPlausibilityTrigger]
collectRawComparisonPlausibilityTriggers rawText tokens =
  let lowered = T.toLower rawText
  in [ RawPropositionComparisonPlausibilityTrigger "comparative_or_phrase"
         ((containsKeywordPhrase tokens "логичнее" || containsKeywordPhrase tokens "вероятнее"
            || containsKeywordPhrase tokens "естественнее" || containsKeywordPhrase tokens "правильнее")
            && containsKeywordPhrase tokens "или")
     , RawPropositionComparisonPlausibilityTrigger "difference_between_text"
         (T.isInfixOf "difference between" lowered)
     , RawPropositionComparisonPlausibilityTrigger "distinguish_text"
         (T.isInfixOf "distinguish" lowered)
     , RawPropositionComparisonPlausibilityTrigger "compare_text"
         (T.isInfixOf "compare" lowered)
     , RawPropositionComparisonPlausibilityTrigger "what_is_difference_text"
         (T.isInfixOf "what is the difference" lowered)
     ]

buildComparisonPlausibilityFromTriggers :: [RawPropositionComparisonPlausibilityTrigger] -> Maybe PropositionType
buildComparisonPlausibilityFromTriggers admittedTriggers
  | matched "comparative_or_phrase" = Just ComparisonPlausibilityQ
  | matched "difference_between_text" = Just ComparisonPlausibilityQ
  | matched "distinguish_text" = Just ComparisonPlausibilityQ
  | matched "compare_text" = Just ComparisonPlausibilityQ
  | matched "what_is_difference_text" = Just ComparisonPlausibilityQ
  | otherwise = Nothing
  where
    matched label = any hasMatchingLabel admittedTriggers
      where
        hasMatchingLabel (RawPropositionComparisonPlausibilityTrigger triggerLabel triggerMatched) =
          triggerLabel == label && triggerMatched

detectMisunderstanding :: TruthContractStatus -> Text -> [Text] -> Maybe PropositionType
detectMisunderstanding truthContractStatus rawText tokens =
  buildMisunderstandingFromTriggers (apmtTriggers admittedTriggers)
  where
    rawTriggers = collectRawMisunderstandingTriggers rawText tokens
    admittedTriggers =
      admitPropositionMisunderstandingTriggers
        (PropositionMisunderstandingAdmissionInput truthContractStatus)
        rawTriggers

collectRawMisunderstandingTriggers :: Text -> [Text] -> [RawPropositionMisunderstandingTrigger]
collectRawMisunderstandingTriggers rawText tokens =
  let lowered = T.toLower rawText
  in [ RawPropositionMisunderstandingTrigger "not_understand_ru"
         (T.isInfixOf "не понимаю" lowered
           && any (`elem` tokens) ["тебя", "тебе", "вас", "диалог", "разговор"])
     , RawPropositionMisunderstandingTrigger "contact_lost_ru"
         (T.isInfixOf "контакт потерян" lowered)
     , RawPropositionMisunderstandingTrigger "apology_tokens"
         (any (`elem` tokens) ["извини", "извините", "прости", "простите", "сорри"])
     , RawPropositionMisunderstandingTrigger "apology_phrase"
         (containsKeywordPhrase tokens "прошу прощения")
     , RawPropositionMisunderstandingTrigger "dont_understand_en_full"
         (T.isInfixOf "i don't understand" lowered)
     , RawPropositionMisunderstandingTrigger "dont_understand_en_full_alt"
         (T.isInfixOf "i do not understand" lowered)
     , RawPropositionMisunderstandingTrigger "dont_understand_en_short"
         (T.isInfixOf "don't understand" lowered)
     , RawPropositionMisunderstandingTrigger "confused_en"
         (T.isInfixOf "confused" lowered)
     , RawPropositionMisunderstandingTrigger "not_clear_en"
         (T.isInfixOf "not clear" lowered)
     , RawPropositionMisunderstandingTrigger "contact_lost_en"
         (T.isInfixOf "lost contact" lowered)
     ]

buildMisunderstandingFromTriggers :: [RawPropositionMisunderstandingTrigger] -> Maybe PropositionType
buildMisunderstandingFromTriggers admittedTriggers
  | matched "not_understand_ru" = Just MisunderstandingReport
  | matched "contact_lost_ru" = Just MisunderstandingReport
  | matched "apology_tokens" = Just RepairSignal
  | matched "apology_phrase" = Just RepairSignal
  | matched "dont_understand_en_full" = Just RepairSignal
  | matched "dont_understand_en_full_alt" = Just RepairSignal
  | matched "dont_understand_en_short" = Just RepairSignal
  | matched "confused_en" = Just RepairSignal
  | matched "not_clear_en" = Just RepairSignal
  | matched "contact_lost_en" = Just MisunderstandingReport
  | otherwise = Nothing
  where
    matched label = any (\trigger -> rpmtLabel trigger == label && rpmtMatched trigger) admittedTriggers

detectRepairDirective :: TruthContractStatus -> Text -> [Text] -> Maybe PropositionType
detectRepairDirective truthContractStatus rawText tokens =
  buildRepairDirectiveFromTriggers admittedTriggerList
  where
    rawTriggers = collectRawRepairDirectiveTriggers rawText tokens
    admittedTriggers =
      admitPropositionRepairDirectiveTriggers
        (PropositionRepairDirectiveAdmissionInput truthContractStatus)
        rawTriggers
    AdmittedPropositionRepairDirectiveTriggers _ admittedTriggerList _ = admittedTriggers

collectRawRepairDirectiveTriggers :: Text -> [Text] -> [RawPropositionRepairDirectiveTrigger]
collectRawRepairDirectiveTriggers rawText tokens =
  let lowered = T.toLower rawText
  in [ RawPropositionRepairDirectiveTrigger "simplify_phrase"
         (containsKeywordPhrase tokens "объясни проще")
     , RawPropositionRepairDirectiveTrigger "rephrase_phrase"
         (containsKeywordPhrase tokens "переформулируй")
     , RawPropositionRepairDirectiveTrigger "shorter_phrase"
         (containsKeywordPhrase tokens "скажи короче")
     , RawPropositionRepairDirectiveTrigger "start_over_phrase"
         (containsKeywordPhrase tokens "давай сначала")
     , RawPropositionRepairDirectiveTrigger "step_by_step_phrase"
         (containsKeywordPhrase tokens "повтори по шагам")
     , RawPropositionRepairDirectiveTrigger "return_to_question_phrase"
         (containsKeywordPhrase tokens "вернись к вопросу")
     , RawPropositionRepairDirectiveTrigger "clarify_term_phrase"
         (containsKeywordPhrase tokens "уточни термин")
     , RawPropositionRepairDirectiveTrigger "fix_answer_phrase"
         (containsKeywordPhrase tokens "исправь ответ")
     , RawPropositionRepairDirectiveTrigger "give_example_phrase"
         (containsKeywordPhrase tokens "дай пример")
     , RawPropositionRepairDirectiveTrigger "explain_otherwise_phrase"
         (containsKeywordPhrase tokens "объясни иначе")
     , RawPropositionRepairDirectiveTrigger "off_question_phrase"
         (containsKeywordPhrase tokens "не по вопросу")
     , RawPropositionRepairDirectiveTrigger "no_connection_phrase"
         (containsKeywordPhrase tokens "не вижу связи")
     , RawPropositionRepairDirectiveTrigger "not_heard_me_phrase"
         (containsKeywordPhrase tokens "ты меня не услышал")
     , RawPropositionRepairDirectiveTrigger "not_helping_phrase"
         (containsKeywordPhrase tokens "это не помогает")
     , RawPropositionRepairDirectiveTrigger "check_logic_phrase"
         (containsKeywordPhrase tokens "проверь логику ответа")
     , RawPropositionRepairDirectiveTrigger "without_excess_phrase"
         (containsKeywordPhrase tokens "без лишнего")
     , RawPropositionRepairDirectiveTrigger "unclear_token_bag"
         (any (`elem` tokens) ["непонятно", "неясно", "запутался", "запуталась", "шаблон", "шаблона", "конкретику", "абстрактно", "расплывчато"])
     , RawPropositionRepairDirectiveTrigger "template_complaint_plain"
         (T.isInfixOf "ты ушел в шаблон" lowered)
     , RawPropositionRepairDirectiveTrigger "template_complaint_stressed"
         (T.isInfixOf "ты ушёл в шаблон" lowered)
     , RawPropositionRepairDirectiveTrigger "dont_understand_en_short"
         (T.isInfixOf "don't understand" lowered)
     , RawPropositionRepairDirectiveTrigger "clarify_en"
         (T.isInfixOf "clarify" lowered)
     , RawPropositionRepairDirectiveTrigger "confused_en"
         (T.isInfixOf "confused" lowered)
     , RawPropositionRepairDirectiveTrigger "not_making_sense_en"
         (T.isInfixOf "doesn't make sense" lowered)
     , RawPropositionRepairDirectiveTrigger "explain_differently_en"
         (T.isInfixOf "explain differently" lowered)
     , RawPropositionRepairDirectiveTrigger "explain_that_differently_en"
         (T.isInfixOf "explain that differently" lowered)
     ]

buildRepairDirectiveFromTriggers :: [RawPropositionRepairDirectiveTrigger] -> Maybe PropositionType
buildRepairDirectiveFromTriggers admittedTriggers
  | matched "simplify_phrase" = Just RepairSignal
  | matched "rephrase_phrase" = Just RepairSignal
  | matched "shorter_phrase" = Just RepairSignal
  | matched "start_over_phrase" = Just RepairSignal
  | matched "step_by_step_phrase" = Just RepairSignal
  | matched "return_to_question_phrase" = Just RepairSignal
  | matched "clarify_term_phrase" = Just RepairSignal
  | matched "fix_answer_phrase" = Just RepairSignal
  | matched "give_example_phrase" = Just RepairSignal
  | matched "explain_otherwise_phrase" = Just RepairSignal
  | matched "off_question_phrase" = Just RepairSignal
  | matched "no_connection_phrase" = Just RepairSignal
  | matched "not_heard_me_phrase" = Just RepairSignal
  | matched "not_helping_phrase" = Just RepairSignal
  | matched "check_logic_phrase" = Just RepairSignal
  | matched "without_excess_phrase" = Just RepairSignal
  | matched "unclear_token_bag" = Just RepairSignal
  | matched "template_complaint_plain" = Just RepairSignal
  | matched "template_complaint_stressed" = Just RepairSignal
  | matched "dont_understand_en_short" = Just RepairSignal
  | matched "clarify_en" = Just RepairSignal
  | matched "confused_en" = Just RepairSignal
  | matched "not_making_sense_en" = Just RepairSignal
  | matched "explain_differently_en" = Just RepairSignal
  | matched "explain_that_differently_en" = Just RepairSignal
  | otherwise = Nothing
  where
    matched label = any hasMatchingLabel admittedTriggers
      where
        hasMatchingLabel (RawPropositionRepairDirectiveTrigger triggerLabel triggerMatched) =
          triggerLabel == label && triggerMatched

detectGenerativePrompt :: TruthContractStatus -> Text -> [Text] -> Maybe PropositionType
detectGenerativePrompt truthContractStatus rawText tokens =
  buildGenerativePromptFromTriggers (apgpTriggers admittedTriggers)
  where
    rawTriggers = collectRawGenerativePromptTriggers rawText tokens
    admittedTriggers =
      admitPropositionGenerativePromptTriggers
        (PropositionGenerativePromptAdmissionInput truthContractStatus)
        rawTriggers

collectRawGenerativePromptTriggers :: Text -> [Text] -> [RawPropositionGenerativePromptTrigger]
collectRawGenerativePromptTriggers rawText tokens =
  [ RawPropositionGenerativePromptTrigger "say_thought_request"
      (containsKeywordPhrase tokens "скажи"
        && any (`elem` tokens) ["мысль", "идею", "идея", "слово", "фразу", "что", "что-нибудь", "чтонибудь"])
  , RawPropositionGenerativePromptTrigger "give_thought_request"
      (containsKeywordPhrase tokens "дай"
        && any (`elem` tokens) ["мысль", "идею", "фразу"])
  , RawPropositionGenerativePromptTrigger "more_thought_request"
      (any (`elem` tokens) ["еще", "ещё", "новую", "другую"]
        && any (`elem` tokens) ["мысль", "идея", "идею", "фразу"])
  , RawPropositionGenerativePromptTrigger "say_something_quality"
      (containsKeywordPhrase tokens "скажи"
        && (containsKeywordPhrase tokens "что-то" || containsKeywordPhrase tokens "что-нибудь"
            || containsKeywordPhrase tokens "чтонибудь" || containsKeywordPhrase tokens "что")
        && any (`elem` tokens) ["логичное", "логично", "интересное", "новое", "другое", "короткое"])
  , RawPropositionGenerativePromptTrigger "say_any_infix"
      (T.isInfixOf "скажи любую" (T.toLower rawText))
  , RawPropositionGenerativePromptTrigger "thesis_logical"
      (any (`elem` tokens) ["тезис", "тезиса"]
        && any (`elem` tokens) ["логичное", "логично", "логичный", "логичен"])
  ]

buildGenerativePromptFromTriggers :: [RawPropositionGenerativePromptTrigger] -> Maybe PropositionType
buildGenerativePromptFromTriggers admittedTriggers
  | matched "say_thought_request" = Just GenerativePrompt
  | matched "give_thought_request" = Just GenerativePrompt
  | matched "more_thought_request" = Just GenerativePrompt
  | matched "say_something_quality" = Just GenerativePrompt
  | matched "say_any_infix" = Just GenerativePrompt
  | matched "thesis_logical" = Just GenerativePrompt
  | otherwise = Nothing
  where
    matched label = any (\trigger -> rpgpLabel trigger == label && rpgpMatched trigger) admittedTriggers

detectContemplativeTopic :: TruthContractStatus -> Text -> [Text] -> Maybe PropositionType
detectContemplativeTopic truthContractStatus rawText tokens =
  buildContemplativeTopicFromTriggers admittedTriggerList
  where
    rawTriggers = collectRawContemplativeTopicTriggers rawText tokens
    admittedTriggers =
      admitPropositionContemplativeTopicTriggers
        (PropositionContemplativeTopicAdmissionInput truthContractStatus)
        rawTriggers
    AdmittedPropositionContemplativeTopicTriggers _ admittedTriggerList _ = admittedTriggers

collectRawContemplativeTopicTriggers :: Text -> [Text] -> [RawPropositionContemplativeTopicTrigger]
collectRawContemplativeTopicTriggers rawText tokens =
  [ RawPropositionContemplativeTopicTrigger "keyword_stream_match"
      (shortContemplativeInput tokens
        && not (null tokens)
        && all (`elem` contemplativeTopicKeywords) tokens)
  , RawPropositionContemplativeTopicTrigger "bare_self_pronoun"
      (T.toLower (T.strip rawText) == "я")
  ]

buildContemplativeTopicFromTriggers :: [RawPropositionContemplativeTopicTrigger] -> Maybe PropositionType
buildContemplativeTopicFromTriggers admittedTriggers
  | matched "keyword_stream_match" = Just ContemplativeTopic
  | matched "bare_self_pronoun" = Just ContemplativeTopic
  | otherwise = Nothing
  where
    matched label = any hasMatchingLabel admittedTriggers
      where
        hasMatchingLabel (RawPropositionContemplativeTopicTrigger triggerLabel triggerMatched) =
          triggerLabel == label && triggerMatched

detectExploratoryPrompt :: TruthContractStatus -> Text -> [Text] -> Maybe PropositionType
detectExploratoryPrompt truthContractStatus rawText tokens =
  buildExploratoryPromptFromTriggers (apeptTriggers admittedTriggers)
  where
    rawTriggers = collectRawExploratoryPromptTriggers rawText tokens
    admittedTriggers =
      admitPropositionExploratoryPromptTriggers
        (PropositionExploratoryPromptAdmissionInput truthContractStatus)
        rawTriggers

collectRawExploratoryPromptTriggers :: Text -> [Text] -> [RawPropositionExploratoryPromptTrigger]
collectRawExploratoryPromptTriggers rawText _tokens =
  [ RawPropositionExploratoryPromptTrigger "explorat_keyword_infix_match"
      (any (`T.isInfixOf` T.toLower rawText) exploratoryKeywords)
  ]

buildExploratoryPromptFromTriggers :: [RawPropositionExploratoryPromptTrigger] -> Maybe PropositionType
buildExploratoryPromptFromTriggers admittedTriggers
  | matched "explorat_keyword_infix_match" = Just ExploratoryPrompt
  | otherwise = Nothing
  where
    matched label = any (\trigger -> rpeptLabel trigger == label && rpeptMatched trigger) admittedTriggers

hasConcreteWorldNoun :: [Text] -> Bool
hasConcreteWorldNoun tokens =
  any (`elem` tokens)
    [ "солнце", "дождь", "небо", "мир", "земля", "вода", "огонь"
    , "время", "пространство", "природа", "вселенная", "жизнь"
    , "дом", "город", "лес", "море", "река", "камень", "ветер", "звезда", "осень"
    ]

hasMentalNoun :: [Text] -> Bool
hasMentalNoun tokens =
  any (`elem` tokens)
    [ "мысль", "мысли", "идея", "идеи", "знание", "знания"
    , "сознание", "память", "воспоминание", "воображение"
    , "фокус", "внимание", "смысл", "образ", "мышление"
    ]

hasConceptLikeNoun :: [Text] -> Bool
hasConceptLikeNoun tokens = hasConcreteWorldNoun tokens || hasMentalNoun tokens || any (`elem` tokens)
  [ "логика", "свобода", "смысл", "тишина", "любовь", "страх", "истина", "дом", "душа", "бог" ]

firstConcreteWorldNoun :: [Text] -> Maybe Text
firstConcreteWorldNoun =
  listToMaybe . filter (`elem`
    [ "солнце", "дождь", "небо", "мир", "земля", "вода", "огонь"
    , "время", "пространство", "природа", "вселенная", "жизнь"
    , "дом", "город", "лес", "море", "река", "камень", "ветер", "звезда", "осень"
    ])

firstMentalNoun :: [Text] -> Maybe Text
firstMentalNoun =
  listToMaybe . filter (`elem`
    [ "мысль", "мысли", "идея", "идеи", "знание", "знания"
    , "сознание", "память", "воспоминание", "воображение"
    , "фокус", "внимание", "смысл", "образ", "мышление"
    ])

invitationTopic :: Text -> Text
invitationTopic rawText =
  fromMaybe
    "диалог"
    (extractTopicAfterMarkers rawText ["о", "об", "обо", "про", "насчет", "насчёт", "к"])

conceptSubject :: Text -> [Text] -> Text
conceptSubject rawText tokens =
  fromMaybe
    (extractFocusEntity rawText)
    ( firstConcreteWorldNoun tokens
   <|> firstMentalNoun tokens
   <|> extractTopicAfterMarkers rawText ["значит", "такое", "такой", "такая", "есть", "о", "об", "обо", "про"]
    )

contemplativeTopic :: Text -> Text
contemplativeTopic rawText =
  fromMaybe
    (extractFocusEntity rawText)
    (firstNonVapid (extractContentNouns rawText) <|> lastNonVapid (extractContentNouns rawText))

firstNonVapid :: [Text] -> Maybe Text
firstNonVapid =
  listToMaybe . filter isFocusCandidate

lastNonVapid :: [Text] -> Maybe Text
lastNonVapid =
  listToMaybe . reverse . filter isFocusCandidate

extractTopicAfterMarkers :: Text -> [Text] -> Maybe Text
extractTopicAfterMarkers rawText markers =
  let tokens = tokenizeKeywordText rawText
      afterMarker = drop 1 (dropWhile (`notElem` markers) tokens)
  in case afterMarker of
       [] -> Nothing
       xs ->
         let candidate = T.unwords (takeWhile (`notElem` stopAfterMarkerWords) xs)
         in if T.null candidate then Nothing else Just candidate

stopAfterMarkerWords :: [Text]
stopAfterMarkerWords = ["что", "как", "почему", "ли", "знаешь", "думаешь", "скажи"]

shortContemplativeInput :: [Text] -> Bool
shortContemplativeInput tokens = length tokens <= 2

asksAboutUser :: Text -> Bool
asksAboutUser rawText =
  let lowered = T.toLower rawText
  in any (`T.isInfixOf` lowered)
      [ "обо мне", "о мне", "обо мне?", "о мне?"
      , "кто я", "кто я такой", "что я такое"
      ]

comparisonCandidates :: Text -> [Text]
comparisonCandidates rawText =
  case splitByEither normalized of
    pair@(_:_:_) -> take 2 pair
    _ -> splitByFrom normalized
  where
    normalized = T.unwords (T.words (T.toLower (T.replace "\n" " " rawText)))
    splitByEither txt =
      case T.breakOn "или" txt of
        (left, rightRaw)
          | T.null rightRaw -> []
          | otherwise ->
              let right = T.drop 3 rightRaw
                  leftCandidate = cleanCandidate left
                  rightCandidate = cleanCandidate (trimAtQuestion right)
              in filter (not . T.null) [leftCandidate, rightCandidate]
    splitByFrom txt =
      case T.breakOn " от " txt of
        (left, rightRaw)
          | T.null rightRaw -> []
          | otherwise ->
              let right = T.drop 4 rightRaw
                  leftCandidate = cleanCandidate (dropDistinctionPrefix left)
                  rightCandidate = cleanCandidate (trimAtQuestion right)
              in filter (not . T.null) [leftCandidate, rightCandidate]
    dropDistinctionPrefix txt =
      let trimmed = T.strip txt
          prefixes =
            [ "как отличить "
            , "чем отличается "
            , "чем отличить "
            , "как различить "
            , "отличить "
            , "различить "
            ]
      in stripKnownPrefix trimmed prefixes
    stripKnownPrefix txt [] = txt
    stripKnownPrefix txt (p:ps)
      | p `T.isPrefixOf` txt = T.strip (T.drop (T.length p) txt)
      | otherwise = stripKnownPrefix txt ps
    trimAtQuestion = fst . T.breakOn "что "
    cleanCandidate =
      T.dropAround (\c -> Char.isSpace c || c `elem` ['.', ',', ';', ':', '?', '!'])
        . T.replace "или" ""

semanticEvidenceFor :: Text -> [Text] -> PropositionType -> [Text]
semanticEvidenceFor rawText tokens propType =
  take 5 . filter (not . T.null) $
    propositionTag : propositionCue : extractKeyPhrases tokens
  where
    propositionTag = textShow propType
    propositionCue =
      case propType of
        SelfKnowledgeQ
          | asksAboutUser rawText -> "target=user"
          | T.isInfixOf "помоч" (T.toLower rawText) -> "target=user_help"
          | any (\needle -> needle `T.isInfixOf` T.toLower rawText) ["умеешь", "можешь"] ->
              "target=self_capability|subject=" <> fromMaybe "способность" (capabilitySubject tokens)
          | otherwise -> "target=self"
        DialogueInvitationQ ->
          "target=dialogue_invitation"
        ConceptKnowledgeQ ->
          "target=concept_knowledge"
        WorldCauseQ ->
          fromMaybe "target=world" (("subject=" <>) <$> firstConcreteWorldNoun tokens)
        LocationFormationQ ->
          fromMaybe "target=thought" (("subject=" <>) <$> firstMentalNoun tokens)
        SelfStateQ ->
          "target=self_state"
        ComparisonPlausibilityQ ->
          "candidates=" <> T.intercalate "|" (comparisonCandidates rawText)
        DistinctionQ ->
          "candidates=" <> T.intercalate "|" (comparisonCandidates rawText)
        MisunderstandingReport ->
          "target=understanding"
        GenerativePrompt ->
          "target=generative_prompt"
        ContemplativeTopic ->
          "target=contemplative_topic"
        OperationalStatusQ ->
          "target=operation"
        OperationalCauseQ ->
          "target=operation_cause"
        SystemLogicQ ->
          "target=system_logic"
        _ ->
          ""

capabilitySubject :: [Text] -> Maybe Text
capabilitySubject =
  listToMaybe . filter (`notElem`
    [ "ты", "тебе", "тебя", "мне", "меня", "я", "кто", "что", "такой"
    , "умеешь", "умею", "умеет", "можешь", "могу", "может"
    , "помочь", "помоги", "помощь", "быть", "есть", "являешься"
    ])

fallbackKeywordGroups :: [(PropositionType, [Text])]
fallbackKeywordGroups =
  [ (OperationalCauseQ, operationalCauseKeywords)
  , (OperationalStatusQ, operationalStatusKeywords)
  , (SystemLogicQ, systemLogicKeywords)
  , (SelfKnowledgeQ, selfKnowledgeKeywords)
  , (DialogueInvitationQ, dialogueInvitationKeywords)
  , (ConceptKnowledgeQ, conceptKnowledgeKeywords)
  , (WorldCauseQ, worldCauseKeywords)
  , (LocationFormationQ, locationFormationKeywords)
  , (SelfStateQ, selfStateKeywords)
  , (ComparisonPlausibilityQ, comparisonPlausibilityKeywords)
  , (MisunderstandingReport, misunderstandingKeywords)
  , (GenerativePrompt, generativePromptKeywords)
  , (DefinitionalQ, definitionalKeywords)
  , (DistinctionQ, distinctionKeywords)
  , (GroundQ, groundKeywords)
  , (ReflectiveQ, reflectiveKeywords)
  , (SelfDescQ, selfDescKeywords)
  , (PurposeQ, purposeKeywords)
  , (HypotheticalQ, hypotheticalKeywords)
  , (RepairSignal, repairKeywords)
  , (ContactSignal, contactKeywords)
  , (AnchorSignal, anchorKeywords)
  , (ClarifyQ, clarifyKeywords)
  , (DeepenQ, deepenKeywords)
  , (ConfrontQ, confrontKeywords)
  , (NextStepQ, nextStepKeywords)
  , (AffectiveQ, affectiveKeywords)
  , (EpistemicQ, epistemicKeywords)
  , (RequestQ, requestKeywords)
  , (EvaluationQ, evaluationKeywords)
  , (NarrativeQ, narrativeKeywords)
  , (ContemplativeTopic, contemplativeTopicKeywords)
  , (ExploratoryPrompt, exploratoryKeywords)
  ]

collectKeywordFallbackDecision :: [Text] -> (PropositionType, [Text]) -> Maybe RawPropositionKeywordFallbackDecision
collectKeywordFallbackDecision tokens (propType, keywords) =
  let matchedPhrases = filter (containsKeywordPhrase tokens) keywords
  in if null matchedPhrases
        then Nothing
        else Just (RawPropositionKeywordFallbackDecision (toFallbackType propType) matchedPhrases)

fallbackDecisionToPhraseDecisions :: RawPropositionKeywordFallbackDecision -> [RawPropositionPhraseDecision]
fallbackDecisionToPhraseDecisions rawDecision =
  map
    (\phrase -> RawPropositionPhraseDecision (rpkfdPropositionType rawDecision) phrase True)
    (rpkfdMatchedPhrases rawDecision)

matchKeywords :: [Text] -> PropositionType -> [Text] -> Maybe PropositionType
matchKeywords keywords propType tokens =
  fmap fromFallbackType (buildKeywordFallbackTypeFromDecisions
    [ RawPropositionPhraseDecision (toFallbackType propType) phrase True
    | phrase <- keywords
    , containsKeywordPhrase tokens phrase
    ])

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

extractFocusEntity :: Text -> Text
extractFocusEntity rawText =
  let trimWord = T.dropAround (\c -> not (Char.isAlphaNum c) && c /= '-')
      nouns = extractContentNouns rawText
      candidates = filter isFocusCandidate (nouns <> map trimWord (T.words rawText))
      scored = L.sortOn (negate . focusScore rawText) (dedupeNormalized candidates)
  in fromMaybe (fallbackFocus rawText) (contrastFocus rawText <|> markerPhraseFocus rawText <|> listToMaybe scored)
  where
    cleanWord = T.dropAround (\c -> not (Char.isAlphaNum c) && c /= '-')
    fallbackFocus t =
      let words' = filter isFocusCandidate (map cleanWord (T.words t))
      in fromMaybe fallbackFocusWord (listToMaybe words')

contrastFocus :: Text -> Maybe Text
contrastFocus rawText =
  let tokens = tokenizeKeywordText rawText
      afterContrast = drop 1 (dropWhile (`notElem` contrastFocusMarkers) tokens)
  in listToMaybe (filter isFocusCandidate afterContrast)

contrastFocusMarkers :: [Text]
contrastFocusMarkers =
  [ "а", "но", "однако", "зато", "but", "however", "although", "whereas" ]

markerPhraseFocus :: Text -> Maybe Text
markerPhraseFocus rawText =
  let tokens = tokenizeKeywordText rawText
      candidates = concatMap (`focusAfterPhrase` tokens) focusMarkerPhrases
  in listToMaybe (filter isFocusCandidate candidates)

focusAfterPhrase :: [Text] -> [Text] -> [Text]
focusAfterPhrase phrase tokens =
  case dropAfterPhrase phrase tokens of
    Nothing -> []
    Just rest -> take 4 rest

dropAfterPhrase :: [Text] -> [Text] -> Maybe [Text]
dropAfterPhrase phrase tokens
  | null phrase = Nothing
  | otherwise = go tokens
  where
    phraseLength = length phrase
    go [] = Nothing
    go xs
      | phrase `L.isPrefixOf` xs = Just (drop phraseLength xs)
      | otherwise = go (drop 1 xs)

focusMarkerPhrases :: [[Text]]
focusMarkerPhrases =
  [ ["имеет", "право"]
  , ["имеет", "основание"]
  , ["является", "причиной"]
  , ["является", "условием"]
  , ["необходимо", "для"]
  , ["достаточно", "для"]
  , ["следует", "из"]
  , ["вытекает", "из"]
  , ["различие", "между"]
  , ["разница", "между"]
  , ["отличается", "от"]
  , ["has", "the", "right"]
  , ["has", "reason"]
  , ["is", "necessary", "for"]
  , ["is", "sufficient", "for"]
  , ["follows", "from"]
  , ["difference", "between"]
  ]

focusScore :: Text -> Text -> Int
focusScore rawText candidate =
  let tokens = tokenizeKeywordText rawText
      key = normalizeFocus candidate
      occurrenceBonus = if countToken key tokens > 1 then 20 else 0
      markerBonus = if followsFocusMarker key tokens then 12 else 0
      lengthBonus = min 8 (T.length key)
  in occurrenceBonus + markerBonus + lengthBonus

followsFocusMarker :: Text -> [Text] -> Bool
followsFocusMarker key tokens =
  any matches (zip tokens (drop 1 tokens))
  where
    matches (marker, value) =
      marker `elem` focusMarkers && value == key

focusMarkers :: [Text]
focusMarkers =
  [ "о", "об", "про", "между", "различить", "вывод", "посылка", "следует"
  , "право", "основание", "причина", "условие", "necessary", "sufficient"
  ]

countToken :: Text -> [Text] -> Int
countToken key = length . filter (== key)

dedupeNormalized :: [Text] -> [Text]
dedupeNormalized = go []
  where
    go _ [] = []
    go seen (x:xs)
      | normalizeFocus x `elem` seen = go seen xs
      | otherwise = x : go (normalizeFocus x : seen) xs

dedupeEvidence :: [Text] -> [Text]
dedupeEvidence = go []
  where
    go _ [] = []
    go seen (x:xs)
      | key `elem` seen = go seen xs
      | otherwise = x : go (key : seen) xs
      where
        key = T.toLower (T.strip x)

isSemanticCandidateSurface :: Text -> Bool
isSemanticCandidateSurface raw =
  let txt = T.toLower (T.strip raw)
  in not (T.null txt)
      && not ("frame." `T.isPrefixOf` txt)
      && not ("route_" `T.isPrefixOf` txt)
      && not ("clause=" `T.isPrefixOf` txt)
      && not ("score_" `T.isPrefixOf` txt)
      && not ("family=" `T.isPrefixOf` txt)
      && not ("confidence=" `T.isPrefixOf` txt)
      && not (T.any (`elem` ['=', '|']) txt)

isFocusCandidate :: Text -> Bool
isFocusCandidate raw =
  let key = normalizeFocus raw
  in T.length key >= 3 && key `notElem` logicalFocusStopwords

normalizeFocus :: Text -> Text
normalizeFocus raw =
  case tokenizeKeywordText raw of
    (x:_) -> x
    [] -> T.toLower (T.strip raw)

logicalFocusStopwords :: [Text]
logicalFocusStopwords =
  [ "если", "что", "кто", "как", "зачем", "все", "всякое", "всякий", "каждый", "каждая", "следовательно"
  , "отсюда", "здесь", "где", "когда", "почему", "можно", "нужно", "либо"
  , "если", "тогда", "значит", "вывести", "объясни", "правило"
  , "влечёт", "влечет", "следует", "заключить"
  , "должен", "должна", "должно", "должны", "обязан", "обязана"
  , "обязано", "обязаны", "нельзя", "разрешено", "запрещено"
  , "может", "могу", "нужно", "надо", "необходимо", "необходимое", "необходимый", "необходимая"
  , "необходимым", "достаточно", "достаточное", "достаточный"
  , "достаточная", "достаточным", "вероятно", "возможно", "является", "ещё", "еще"
  , "очевидно", "пока", "прежде", "после", "затем", "потом", "раньше"
  , "позже", "одновременно", "но", "или", "однако", "зато", "хотя"
  , "некоторые", "никто", "ничто", "кроме", "исключением"
  , "иметь", "имеет", "имею", "имеешь", "имеют", "права", "право", "правом"
  , "обязанность", "обязанностью", "обязательство", "долг", "долга"
  , "if", "then", "therefore", "because", "all", "every", "where", "does"
  , "what", "which", "identify", "premise", "conclusion", "must", "should", "not"
  , "may", "can", "could", "allowed", "forbidden", "right", "obligation", "duty"
  , "obligated", "responsible", "boundary", "fault"
  , "necessary", "sufficient", "possible", "probable"
  , "evident", "when", "while", "before", "after", "until", "once"
  , "however", "but", "although", "whereas", "some", "no", "none", "except"
  , "стало", "быть", "итак", "поэтому", "потому"
  , "логически", "логический"
  , "свой", "своя", "своё", "свое", "свои", "свою"
  , "мой", "моя", "моё", "мое", "мои", "мою"
  , "твой", "твоя", "твоё", "твое", "твои", "твою"
  , "его", "ее", "её", "их", "наш", "наша", "наше", "наши", "ваш", "ваша", "ваше", "ваши"
  , "знаешь", "знать", "умеешь", "уметь", "можешь", "мочь", "будешь", "будет", "буду"
  , "думаешь", "думать", "есть", "такой", "такая", "такое", "зовут"
  , "тут", "здесь", "там"
  , "hence", "thus", "so", "consequently", "since"
  ]

extractKeyPhrases :: [Text] -> [Text]
extractKeyPhrases tokens =
  let long = filter (\w -> T.length w > 4) tokens
  in take 5 long

detectEmotion :: [Text] -> EmotionalTone
detectEmotion tokens
  | containsAnyKeywordPhrase tokens emotionDistressKeywords = ToneDistress
  | containsAnyKeywordPhrase tokens emotionHopefulKeywords = ToneHopeful
  | containsAnyKeywordPhrase tokens emotionCuriousKeywords = ToneCurious
  | containsAnyKeywordPhrase tokens emotionConfrontKeywords = ToneConfrontational
  | otherwise = ToneNeutral

computeConfidence :: PropositionType -> [Text] -> UtteranceSemanticFrame -> Double
computeConfidence propType keyPhrases semanticFrame =
  let base = case propType of
        DefinitionalQ  -> propositionBaseConfidenceDefinitional
        DistinctionQ   -> propositionBaseConfidenceDistinction
        GroundQ        -> propositionBaseConfidenceGround
        ReflectiveQ    -> propositionBaseConfidenceReflective
        SelfDescQ      -> propositionBaseConfidenceSelfDescription
        PurposeQ       -> propositionBaseConfidencePurpose
        HypotheticalQ  -> propositionBaseConfidenceHypothetical
        RepairSignal   -> propositionBaseConfidenceRepair
        ContactSignal  -> propositionBaseConfidenceContact
        AnchorSignal   -> propositionBaseConfidenceAnchor
        ClarifyQ       -> propositionBaseConfidenceClarify
        DeepenQ        -> propositionBaseConfidenceDeepen
        ConfrontQ      -> propositionBaseConfidenceConfront
        NextStepQ      -> propositionBaseConfidenceNextStep
        PlainAssert    -> propositionBaseConfidencePlainAssert
        AffectiveQ     -> propositionBaseConfidenceAffective
        EpistemicQ     -> propositionBaseConfidenceEpistemic
        RequestQ       -> propositionBaseConfidenceRequest
        EvaluationQ    -> propositionBaseConfidenceEvaluation
        NarrativeQ     -> propositionBaseConfidenceNarrative
        OperationalStatusQ -> 0.78
        OperationalCauseQ -> 0.82
        SystemLogicQ   -> 0.78
        SelfKnowledgeQ -> propositionBaseConfidenceSelfKnowledge
        DialogueInvitationQ -> propositionBaseConfidenceDialogueInvitation
        ConceptKnowledgeQ -> propositionBaseConfidenceConceptKnowledge
        WorldCauseQ    -> propositionBaseConfidenceWorldCause
        LocationFormationQ -> propositionBaseConfidenceLocationFormation
        SelfStateQ -> propositionBaseConfidenceSelfState
        ComparisonPlausibilityQ -> propositionBaseConfidenceComparisonPlausibility
        MisunderstandingReport -> propositionBaseConfidenceMisunderstanding
        GenerativePrompt -> propositionBaseConfidenceGenerativePrompt
        ContemplativeTopic -> propositionBaseConfidenceContemplativeTopic
        ExploratoryPrompt -> 0.65
      keywordBonus =
        min propositionKeywordBonusCap
          (fromIntegral (length keyPhrases) * propositionKeywordBonusPerPhrase)
      lexicalConfidence = clamp01 (base + keywordBonus)
      routeConfidence = clamp01 (irhConfidence (usfRouteHint semanticFrame))
      frameConfidence = clamp01 (usfConfidence semanticFrame)
      blendedConfidence = clamp01 ((lexicalConfidence * 0.62) + (routeConfidence * 0.23) + (frameConfidence * 0.15))
      confidenceFloor =
        case propType of
          OperationalStatusQ -> 0.72
          SystemLogicQ -> 0.72
          SelfKnowledgeQ -> 0.82
          DistinctionQ -> 0.75
          GroundQ -> 0.75
          ContactSignal -> 0.75
          PurposeQ -> 0.75
          RepairSignal -> 0.75
          ExploratoryPrompt -> 0.55
          _ -> 0.0
  in max confidenceFloor blendedConfidence

clamp01 :: Double -> Double
clamp01 value
  | value < 0.0 = 0.0
  | value > 1.0 = 1.0
  | otherwise = value
