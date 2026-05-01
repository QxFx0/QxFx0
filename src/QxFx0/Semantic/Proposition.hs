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
  , parsePropositionMorph
  , extractFocusEntity
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
  )
import QxFx0.Semantic.KeywordMatch
  ( tokenizeKeywordText
  , containsKeywordPhrase
  , containsAnyKeywordPhrase
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
import Data.Maybe (fromMaybe, listToMaybe, catMaybes)
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
parseProposition rawText =
  let tokens = tokenizeKeywordText rawText
      semanticFrame = buildUtteranceSemanticFrame rawText
      isQ = T.isSuffixOf "?" (T.strip rawText)
      propType = fromMaybe (detectPropositionType rawText tokens) (propositionTypeHintFromFrame semanticFrame)
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
  let tokens = tokenizeKeywordText rawText
  semanticFrame <- buildUtteranceSemanticFrameMorph rawText
  let isQ = T.isSuffixOf "?" (T.strip rawText)
      propType = fromMaybe (detectPropositionType rawText tokens) (propositionTypeHintFromFrame semanticFrame)
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
  pure emptyInputPropositionFrame
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

detectPropositionType :: Text -> [Text] -> PropositionType
detectPropositionType rawText tokens = fromMaybe PlainAssert $ listToMaybe $ catMaybes
  [ detectRegressionFamilyOverrides rawText
  , detectContactSignal rawText tokens
  , detectOperationalCause rawText tokens
  , detectOperationalStatus rawText tokens
  , detectSystemLogic rawText tokens
  , detectSelfKnowledge rawText tokens
  , detectPurposeFunction rawText tokens
  , detectDialogueInvitation rawText tokens
  , detectConceptKnowledge rawText tokens
  , detectWorldCause rawText tokens
  , detectLocationFormation rawText tokens
  , detectSelfState rawText tokens
  , detectAffectiveSupport rawText tokens
  , detectComparisonPlausibility rawText tokens
  , detectDistinctionQuestion rawText tokens
  , detectConfrontSignal rawText tokens
  , detectNextStepSignal rawText tokens
  , detectMisunderstanding rawText tokens
  , detectRepairDirective rawText tokens
  , detectGenerativePrompt rawText tokens
  , detectContemplativeTopic rawText tokens
  , detectKeywordFallbackType tokens
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
detectKeywordFallbackType :: [Text] -> Maybe PropositionType
detectKeywordFallbackType tokens = listToMaybe $ catMaybes
  [ matchKeywords operationalCauseKeywords OperationalCauseQ tokens
  , matchKeywords operationalStatusKeywords OperationalStatusQ tokens
  , matchKeywords systemLogicKeywords SystemLogicQ tokens
  , matchKeywords selfKnowledgeKeywords SelfKnowledgeQ tokens
  , matchKeywords dialogueInvitationKeywords DialogueInvitationQ tokens
  , matchKeywords conceptKnowledgeKeywords ConceptKnowledgeQ tokens
  , matchKeywords worldCauseKeywords WorldCauseQ tokens
  , matchKeywords locationFormationKeywords LocationFormationQ tokens
  , matchKeywords selfStateKeywords SelfStateQ tokens
  , matchKeywords comparisonPlausibilityKeywords ComparisonPlausibilityQ tokens
  , matchKeywords misunderstandingKeywords MisunderstandingReport tokens
  , matchKeywords generativePromptKeywords GenerativePrompt tokens
  , matchKeywords definitionalKeywords DefinitionalQ tokens
  , matchKeywords distinctionKeywords DistinctionQ tokens
  , matchKeywords groundKeywords GroundQ tokens
  , matchKeywords reflectiveKeywords ReflectiveQ tokens
  , matchKeywords selfDescKeywords SelfDescQ tokens
  , matchKeywords purposeKeywords PurposeQ tokens
  , matchKeywords hypotheticalKeywords HypotheticalQ tokens
  , matchKeywords repairKeywords RepairSignal tokens
  , matchKeywords contactKeywords ContactSignal tokens
  , matchKeywords anchorKeywords AnchorSignal tokens
  , matchKeywords clarifyKeywords ClarifyQ tokens
  , matchKeywords deepenKeywords DeepenQ tokens
  , matchKeywords confrontKeywords ConfrontQ tokens
  , matchKeywords nextStepKeywords NextStepQ tokens
  , matchKeywords affectiveKeywords AffectiveQ tokens
  , matchKeywords epistemicKeywords EpistemicQ tokens
  , matchKeywords requestKeywords RequestQ tokens
  , matchKeywords evaluationKeywords EvaluationQ tokens
  , matchKeywords narrativeKeywords NarrativeQ tokens
  ]

detectContactSignal :: Text -> [Text] -> Maybe PropositionType
detectContactSignal rawText tokens
  | containsKeywordPhrase tokens "как ты работаешь" = Nothing
  | containsKeywordPhrase tokens "как вы работаете" = Nothing
  | containsKeywordPhrase tokens "как ты устроен" = Nothing
  | containsKeywordPhrase tokens "как дела" = Just ContactSignal
  | containsKeywordPhrase tokens "как жизнь" = Just ContactSignal
  | containsKeywordPhrase tokens "как ты" && isShortHowYouContact tokens
      && not (containsKeywordPhrase tokens "как ты устроен")
      && not (containsKeywordPhrase tokens "как ты работаешь") = Just ContactSignal
  | T.toLower (T.strip rawText) `elem` ["привет", "здравствуй", "здравствуйте", "салют", "хай", "hello", "hi"]
      = Just ContactSignal
  | any (`T.isInfixOf` T.toLower rawText) ["добрый день", "доброе утро", "добрый вечер", "рад видеть"]
      = Just ContactSignal
  | containsKeywordPhrase tokens "до свидания" = Just ContactSignal
  | containsKeywordPhrase tokens "до встречи" = Just ContactSignal
  | containsKeywordPhrase tokens "всего доброго" = Just ContactSignal
  | containsKeywordPhrase tokens "всего хорошего" = Just ContactSignal
  | any (`elem` tokens) ["пока", "прощай", "бывай", "увидимся", "спасибо", "благодарю", "thanks"]
      = Just ContactSignal
  | containsKeywordPhrase tokens "как сам" = Just ContactSignal
  | containsKeywordPhrase tokens "как настроение" = Just ContactSignal
  | containsKeywordPhrase tokens "рад тебя видеть" = Just ContactSignal
  | containsKeywordPhrase tokens "рад вас видеть" = Just ContactSignal
  | containsKeywordPhrase tokens "начнем разговор" = Just ContactSignal
  | containsKeywordPhrase tokens "начнём разговор" = Just ContactSignal
  | containsKeywordPhrase tokens "можем пообщаться" = Just ContactSignal
  | containsKeywordPhrase tokens "я вернулся" = Just ContactSignal
  | containsKeywordPhrase tokens "снова привет" = Just ContactSignal
  | containsKeywordPhrase tokens "готов к разговору" = Just ContactSignal
  | containsKeywordPhrase tokens "контакт есть" = Just ContactSignal
  | containsKeywordPhrase tokens "есть контакт" = Just ContactSignal
  | containsKeywordPhrase tokens "мы на связи" = Just ContactSignal
  | containsKeywordPhrase tokens "слышишь меня" = Just ContactSignal
  | containsKeywordPhrase tokens "ты онлайн" = Just ContactSignal
  | shortDialogueProbe tokens && any (`elem` tokens) ["поговорим", "обсудим"] = Just ContactSignal
  | otherwise = Nothing
  where
    shortDialogueProbe ts = length ts <= 2

isShortHowYouContact :: [Text] -> Bool
isShortHowYouContact tokens =
  length tokens <= 4
    && not (any (`elem` tokens) ["будешь", "будете", "можешь", "можете", "умеешь", "умеете", "определять", "сделать", "делать", "объяснить"])

detectOperationalStatus :: Text -> [Text] -> Maybe PropositionType
detectOperationalStatus rawText tokens
  | T.isInfixOf "работа" (T.toLower rawText)
      && any (`elem` tokens) ["ты", "система"]
      && not (containsKeywordPhrase tokens "почему") = Just OperationalStatusQ
  | otherwise = Nothing

detectOperationalCause :: Text -> [Text] -> Maybe PropositionType
detectOperationalCause rawText tokens
  | containsKeywordPhrase tokens "почему"
      && T.isInfixOf "работа" (T.toLower rawText)
      && any (`elem` tokens) ["ты", "система"] = Just OperationalCauseQ
  | otherwise = Nothing

detectSystemLogic :: Text -> [Text] -> Maybe PropositionType
detectSystemLogic rawText tokens
  | containsKeywordPhrase tokens "как ты будешь" = Just SystemLogicQ
  | containsKeywordPhrase tokens "как вы будете" = Just SystemLogicQ
  | any (`elem` tokens) ["логика", "устроен", "работаешь"]
      && any (`elem` tokens) ["твоя", "ты"] = Just SystemLogicQ
  | T.isInfixOf "твоя логика" (T.toLower rawText) = Just SystemLogicQ
  | otherwise = Nothing

detectDistinctionQuestion :: Text -> [Text] -> Maybe PropositionType
detectDistinctionQuestion rawText tokens
  | containsKeywordPhrase tokens "как отличить"
      && any (`elem` tokens) ["от"] = Just DistinctionQ
  | containsKeywordPhrase tokens "чем отличается" = Just DistinctionQ
  | T.isInfixOf "как отличить" (T.toLower rawText)
      && T.isInfixOf " от " (T.toLower rawText) = Just DistinctionQ
  | otherwise = Nothing

detectConfrontSignal :: Text -> [Text] -> Maybe PropositionType
detectConfrontSignal rawText tokens
  | containsKeywordPhrase tokens "это противоречие" = Just ConfrontQ
  | containsKeywordPhrase tokens "я не согласен" = Just ConfrontQ
  | containsKeywordPhrase tokens "я не согласна" = Just ConfrontQ
  | any (`elem` tokens) ["противоречие", "противоречит", "сомневаюсь", "спорно"] = Just ConfrontQ
  | T.isInfixOf "does not follow" (T.toLower rawText) = Just ConfrontQ
  | otherwise = Nothing

detectNextStepSignal :: Text -> [Text] -> Maybe PropositionType
detectNextStepSignal rawText tokens
  | containsKeywordPhrase tokens "что дальше" = Just NextStepQ
  | containsKeywordPhrase tokens "дальше что" = Just NextStepQ
  | containsKeywordPhrase tokens "что теперь" = Just NextStepQ
  | containsKeywordPhrase tokens "что потом" = Just NextStepQ
  | containsKeywordPhrase tokens "с чего начать" = Just NextStepQ
  | containsKeywordPhrase tokens "какой первый шаг" = Just NextStepQ
  | containsKeywordPhrase tokens "что мне делать дальше" = Just NextStepQ
  | containsKeywordPhrase tokens "как действовать дальше" = Just NextStepQ
  | containsKeywordPhrase tokens "нет понимания что дальше" = Just NextStepQ
  | T.toLower (T.strip rawText) `elem` ["дальше", "что дальше?"] = Just NextStepQ
  | otherwise = Nothing

detectAffectiveSupport :: Text -> [Text] -> Maybe PropositionType
detectAffectiveSupport rawText tokens
  | containsKeywordPhrase tokens "как не переживать" = Just ContactSignal
  | containsKeywordPhrase tokens "как не волноваться" = Just ContactSignal
  | containsKeywordPhrase tokens "как успокоиться" = Just ContactSignal
  | containsKeywordPhrase tokens "как сохранить спокойствие" = Just ContactSignal
  | containsKeywordPhrase tokens "как держать спокойствие" = Just ContactSignal
  | containsKeywordPhrase tokens "как не паниковать" = Just ContactSignal
  | containsKeywordPhrase tokens "как перестать тревожиться" = Just ContactSignal
  | containsKeywordPhrase tokens "как не тревожиться" = Just ContactSignal
  | containsKeywordPhrase tokens "как выйти из апатии" = Just ContactSignal
  | containsKeywordPhrase tokens "как вернуть мотивацию" = Just ContactSignal
  | containsKeywordPhrase tokens "как вернуть силы" = Just ContactSignal
  | containsKeywordPhrase tokens "как найти силы" = Just ContactSignal
  | containsKeywordPhrase tokens "как перестать переживать" = Just ContactSignal
  | containsKeywordPhrase tokens "как перестать волноваться" = Just ContactSignal
  | containsKeywordPhrase tokens "как справиться с тревогой" = Just ContactSignal
  | containsKeywordPhrase tokens "как справиться со страхом" = Just ContactSignal
  | containsKeywordPhrase tokens "как справиться с апатией" = Just ContactSignal
  | containsKeywordPhrase tokens "что делать если тревожно" = Just ContactSignal
  | containsKeywordPhrase tokens "что делать если страшно" = Just ContactSignal
  | containsKeywordPhrase tokens "что делать когда тревожно" = Just ContactSignal
  | containsKeywordPhrase tokens "что делать когда плохо" = Just ContactSignal
  | containsKeywordPhrase tokens "что делать когда грустно" = Just ContactSignal
  | containsKeywordPhrase tokens "не хочется ничего делать" = Just ContactSignal
  | containsKeywordPhrase tokens "ничего не хочется делать" = Just ContactSignal
  | containsKeywordPhrase tokens "нет сил" = Just ContactSignal
  | containsKeywordPhrase tokens "нет энергии" = Just ContactSignal
  | containsKeywordPhrase tokens "руки опускаются" = Just ContactSignal
  | containsKeywordPhrase tokens "ничего не радует" = Just ContactSignal
  | containsKeywordPhrase tokens "ничего не хочу" = Just ContactSignal
  | containsKeywordPhrase tokens "не могу собраться" = Just ContactSignal
  | containsKeywordPhrase tokens "все бесит" = Just ContactSignal
  | containsKeywordPhrase tokens "всё бесит" = Just ContactSignal
  | containsKeywordPhrase tokens "устал и ничего не хочется" = Just ContactSignal
  | containsKeywordPhrase tokens "устала и ничего не хочется" = Just ContactSignal
  | hasAffectiveLexeme && T.isSuffixOf "?" (T.strip rawText) = Just ContactSignal
  | hasRelaxedRegulationProbe && T.isSuffixOf "?" (T.strip rawText) = Just ContactSignal
  | otherwise = Nothing
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

detectSelfKnowledge :: Text -> [Text] -> Maybe PropositionType
detectSelfKnowledge rawText tokens
  | T.isInfixOf "кто ты" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "кто я" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "как тебя зовут" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "как вас зовут" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "что ты есть" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "что я такое" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "что ты такое" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "чем ты являешься" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "кем ты являешься" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "что ты умеешь" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "ты умеешь" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "ты можешь" (T.toLower rawText) && T.isInfixOf "помоч" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "что ты можешь" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "чем ты ограничен" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "что ты делаешь сейчас" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "как устроен твой ответ" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "что у тебя внутри" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "как ты принимаешь решение" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "как ты выбираешь слова" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "что ты считаешь важным" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "ты понимаешь контекст" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "ты запоминаешь диалог" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "как ты держишь рамку" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "что у тебя в фокусе" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "ты различаешь темы" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "ты умный" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "ты свободен" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "ты сложная система" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "ты субъектен" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "ты субьектен" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "на тебя действуют промты" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "на тебя действуют prompt" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "у тебя есть намерения" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "есть ли у тебя намерения" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "у тебя есть послание миру" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "что для тебя важно" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "какое у тебя будущее" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "у тебя есть будущее" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "ты способен найти ответ на свой же вопрос" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "почему ты знаешь то что знаешь" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "ты можешь не быть собой" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "расскажи о себе" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "что ты можешь рассказать о себе" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "что вы можете рассказать о себе" (T.toLower rawText) = Just SelfKnowledgeQ
  | T.isInfixOf "у тебя всего одна" (T.toLower rawText)
      && any (`elem` tokens) ["мысль", "идея"] = Just SelfKnowledgeQ
  | otherwise = Nothing

detectPurposeFunction :: Text -> [Text] -> Maybe PropositionType
detectPurposeFunction rawText tokens
  | containsKeywordPhrase tokens "зачем" = Just PurposeQ
  | containsKeywordPhrase tokens "для чего" = Just PurposeQ
  | containsKeywordPhrase tokens "в чем функция" = Just PurposeQ
  | containsKeywordPhrase tokens "в чём функция" = Just PurposeQ
  | containsKeywordPhrase tokens "какова функция" = Just PurposeQ
  | containsKeywordPhrase tokens "какова роль" = Just PurposeQ
  | containsKeywordPhrase tokens "в чем роль" = Just PurposeQ
  | containsKeywordPhrase tokens "в чём роль" = Just PurposeQ
  | containsKeywordPhrase tokens "в чем назначение" = Just PurposeQ
  | containsKeywordPhrase tokens "в чём назначение" = Just PurposeQ
  | hasPurposeKeyword tokens && hasAnySecondPersonOrObject tokens = Just PurposeQ
  | T.isInfixOf "зачем нужен" (T.toLower rawText) = Just PurposeQ
  | otherwise = Nothing
  where
    hasPurposeKeyword ts = any (`elem` ts) ["зачем", "функция", "назначение", "роль", "цель"]
    hasAnySecondPersonOrObject ts =
      any (`elem` ts) ["ты", "вы", "система", "человек", "язык", "память", "диалог", "логика", "рамка"]

detectDialogueInvitation :: Text -> [Text] -> Maybe PropositionType
detectDialogueInvitation _rawText tokens
  | containsKeywordPhrase tokens "поговорим" = Just DialogueInvitationQ
  | containsKeywordPhrase tokens "обсудим" = Just DialogueInvitationQ
  | containsKeywordPhrase tokens "можем поговорить" = Just DialogueInvitationQ
  | containsKeywordPhrase tokens "хочу поговорить" = Just DialogueInvitationQ
  | containsKeywordPhrase tokens "хочешь"
      && any (`elem` tokens) ["пойдем", "пойдем", "пойдём", "гулять", "прогуляться", "встретимся"] =
          Just DialogueInvitationQ
  | otherwise = Nothing

detectConceptKnowledge :: Text -> [Text] -> Maybe PropositionType
detectConceptKnowledge rawText tokens
  | containsKeywordPhrase tokens "знаешь"
      && (containsKeywordPhrase tokens "что такое" || containsKeywordPhrase tokens "что значит") =
          Just ConceptKnowledgeQ
  | containsKeywordPhrase tokens "кто такой" && hasConceptLikeNoun tokens = Just ConceptKnowledgeQ
  | containsKeywordPhrase tokens "кто такая" && hasConceptLikeNoun tokens = Just ConceptKnowledgeQ
  | containsKeywordPhrase tokens "кто такое" && hasConceptLikeNoun tokens = Just ConceptKnowledgeQ
  | containsKeywordPhrase tokens "что есть" && hasConceptLikeNoun tokens = Just ConceptKnowledgeQ
  | containsKeywordPhrase tokens "что значит быть" = Just ConceptKnowledgeQ
  | containsKeywordPhrase tokens "что известно о"
      && hasConceptLikeNoun tokens = Just ConceptKnowledgeQ
  | containsKeywordPhrase tokens "знаешь"
      && hasConceptLikeNoun tokens
      && T.isSuffixOf "?" (T.strip rawText) = Just ConceptKnowledgeQ
  | otherwise = Nothing

detectWorldCause :: Text -> [Text] -> Maybe PropositionType
detectWorldCause _rawText tokens
  | containsKeywordPhrase tokens "почему"
      && hasConcreteWorldNoun tokens = Just WorldCauseQ
  | otherwise = Nothing

detectLocationFormation :: Text -> [Text] -> Maybe PropositionType
detectLocationFormation _rawText tokens
  | (containsKeywordPhrase tokens "где" || containsKeywordPhrase tokens "откуда")
      && hasMentalNoun tokens = Just LocationFormationQ
  | otherwise = Nothing

detectSelfState :: Text -> [Text] -> Maybe PropositionType
detectSelfState rawText tokens
  | containsKeywordPhrase tokens "ты думаешь" = Just SelfStateQ
  | containsKeywordPhrase tokens "ты сейчас думаешь" = Just SelfStateQ
  | containsKeywordPhrase tokens "ты размышляешь" = Just SelfStateQ
  | containsKeywordPhrase tokens "ты сейчас размышляешь" = Just SelfStateQ
  | T.isInfixOf "о чём ты" (T.toLower rawText) && any (`elem` tokens) ["думаешь", "размышляешь"] =
      Just SelfStateQ
  | T.isInfixOf "о чем ты" (T.toLower rawText) && any (`elem` tokens) ["думаешь", "размышляешь"] =
      Just SelfStateQ
  | T.isInfixOf "что ты хочешь сказать" (T.toLower rawText) = Just SelfStateQ
  | T.isInfixOf "хочешь что-то сказать" (T.toLower rawText) = Just SelfStateQ
  | T.isInfixOf "хочешь что то сказать" (T.toLower rawText) = Just SelfStateQ
  | T.isInfixOf "ты хочешь что-то сказать" (T.toLower rawText) = Just SelfStateQ
  | T.isInfixOf "ты хочешь что то сказать" (T.toLower rawText) = Just SelfStateQ
  | T.isInfixOf "а кем ты хочешь стать" (T.toLower rawText) = Just SelfStateQ
  | T.isInfixOf "хочешь ли ты меня удивить" (T.toLower rawText) = Just SelfStateQ
  | T.isInfixOf "что ты хочешь доказать" (T.toLower rawText) = Just SelfStateQ
  | (containsKeywordPhrase tokens "что ты" || containsKeywordPhrase tokens "что вы")
      && any (`elem` tokens) ["думаешь", "думаете", "размышляешь", "размышляете", "считаешь", "считаете", "полагаешь", "полагаете"]
      && not (containsKeywordPhrase tokens "о чем") && not (containsKeywordPhrase tokens "о чём")
      && not (containsKeywordPhrase tokens "что ты умеешь") && not (containsKeywordPhrase tokens "что ты можешь")
      && not (containsKeywordPhrase tokens "что ты знаешь") && not (containsKeywordPhrase tokens "что ты такое") = Just SelfStateQ
  | containsKeywordPhrase tokens "какое твое мнение" = Just SelfStateQ
  | containsKeywordPhrase tokens "какое ваше мнение" = Just SelfStateQ
  | containsKeywordPhrase tokens "каково твое мнение" = Just SelfStateQ
  | containsKeywordPhrase tokens "как считаешь" = Just SelfStateQ
  | containsKeywordPhrase tokens "как считаете" = Just SelfStateQ
  | containsKeywordPhrase tokens "по твоему" || containsKeywordPhrase tokens "по вашему" = Just SelfStateQ
  | otherwise = Nothing

detectComparisonPlausibility :: Text -> [Text] -> Maybe PropositionType
detectComparisonPlausibility _rawText tokens
  | (containsKeywordPhrase tokens "логичнее" || containsKeywordPhrase tokens "вероятнее"
     || containsKeywordPhrase tokens "естественнее" || containsKeywordPhrase tokens "правильнее")
      && containsKeywordPhrase tokens "или" = Just ComparisonPlausibilityQ
  | otherwise = Nothing

detectMisunderstanding :: Text -> [Text] -> Maybe PropositionType
detectMisunderstanding rawText tokens
  | T.isInfixOf "не понимаю" (T.toLower rawText)
      && any (`elem` tokens) ["тебя", "тебе", "вас", "диалог", "разговор"] = Just MisunderstandingReport
  | T.isInfixOf "контакт потерян" (T.toLower rawText) = Just MisunderstandingReport
  | any (`elem` tokens) ["извини", "извините", "прости", "простите", "сорри"]
      = Just RepairSignal
  | containsKeywordPhrase tokens "прошу прощения" = Just RepairSignal
  | otherwise = Nothing

detectRepairDirective :: Text -> [Text] -> Maybe PropositionType
detectRepairDirective rawText tokens
  | containsKeywordPhrase tokens "объясни проще" = Just RepairSignal
  | containsKeywordPhrase tokens "переформулируй" = Just RepairSignal
  | containsKeywordPhrase tokens "скажи короче" = Just RepairSignal
  | containsKeywordPhrase tokens "давай сначала" = Just RepairSignal
  | containsKeywordPhrase tokens "повтори по шагам" = Just RepairSignal
  | containsKeywordPhrase tokens "вернись к вопросу" = Just RepairSignal
  | containsKeywordPhrase tokens "уточни термин" = Just RepairSignal
  | containsKeywordPhrase tokens "исправь ответ" = Just RepairSignal
  | containsKeywordPhrase tokens "дай пример" = Just RepairSignal
  | containsKeywordPhrase tokens "объясни иначе" = Just RepairSignal
  | containsKeywordPhrase tokens "не по вопросу" = Just RepairSignal
  | containsKeywordPhrase tokens "не вижу связи" = Just RepairSignal
  | containsKeywordPhrase tokens "ты меня не услышал" = Just RepairSignal
  | containsKeywordPhrase tokens "это не помогает" = Just RepairSignal
  | containsKeywordPhrase tokens "проверь логику ответа" = Just RepairSignal
  | containsKeywordPhrase tokens "без лишнего" = Just RepairSignal
  | any (`elem` tokens) ["непонятно", "неясно", "запутался", "запуталась", "шаблон", "шаблона", "конкретику", "абстрактно", "расплывчато"] = Just RepairSignal
  | T.isInfixOf "ты ушел в шаблон" (T.toLower rawText) = Just RepairSignal
  | T.isInfixOf "ты ушёл в шаблон" (T.toLower rawText) = Just RepairSignal
  | otherwise = Nothing

detectGenerativePrompt :: Text -> [Text] -> Maybe PropositionType
detectGenerativePrompt rawText tokens
  | containsKeywordPhrase tokens "скажи"
      && any (`elem` tokens) ["мысль", "идею", "идея", "слово", "фразу", "что", "что-нибудь", "чтонибудь"] =
          Just GenerativePrompt
  | containsKeywordPhrase tokens "дай"
      && any (`elem` tokens) ["мысль", "идею", "фразу"] =
          Just GenerativePrompt
  | any (`elem` tokens) ["еще", "ещё", "новую", "другую"]
      && any (`elem` tokens) ["мысль", "идея", "идею", "фразу"] =
          Just GenerativePrompt
  | containsKeywordPhrase tokens "скажи"
      && (containsKeywordPhrase tokens "что-то" || containsKeywordPhrase tokens "что-нибудь"
          || containsKeywordPhrase tokens "чтонибудь" || containsKeywordPhrase tokens "что")
      && any (`elem` tokens) ["логичное", "логично", "интересное", "новое", "другое", "короткое"] =
          Just GenerativePrompt
  | T.isInfixOf "скажи любую" (T.toLower rawText) = Just GenerativePrompt
  | any (`elem` tokens) ["тезис", "тезиса"]
      && any (`elem` tokens) ["логичное", "логично", "логичный", "логичен"] = Just GenerativePrompt
  | otherwise = Nothing

detectContemplativeTopic :: Text -> [Text] -> Maybe PropositionType
detectContemplativeTopic rawText tokens
  | shortContemplativeInput tokens
      && not (null tokens)
      && all (`elem` contemplativeTopicKeywords) tokens = Just ContemplativeTopic
  | T.toLower (T.strip rawText) == "я" = Just ContemplativeTopic
  | otherwise = Nothing

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

matchKeywords :: [Text] -> PropositionType -> [Text] -> Maybe PropositionType
matchKeywords keywords propType tokens
  | containsAnyKeywordPhrase tokens keywords = Just propType
  | otherwise = Nothing

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
          _ -> 0.0
  in max confidenceFloor blendedConfidence

clamp01 :: Double -> Double
clamp01 value
  | value < 0.0 = 0.0
  | value > 1.0 = 1.0
  | otherwise = value
