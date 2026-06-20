{-# LANGUAGE OverloadedStrings #-}
{-| Semantic analysis functions for proposition classification.

This module provides semantic slot inference, evidence generation,
confidence computation, and emotion detection for propositions.
-}
module QxFx0.Semantic.Proposition.Semantic
  ( -- * Semantic slot inference
    inferSemanticSlots
  , specialFocusEntity
  , semanticEvidenceFor
    -- * Confidence and emotion
  , computeConfidence
  , detectEmotion
  , clamp01
    -- * Topic extraction
  , invitationTopic
  , conceptSubject
  , contemplativeTopic
  , extractTopicAfterMarkers
  , asksAboutUser
  , comparisonCandidates
    -- * Noun detection
  , hasConcreteWorldNoun
  , hasMentalNoun
  , hasConceptLikeNoun
  , firstConcreteWorldNoun
  , firstMentalNoun
  , firstNonVapid
  , lastNonVapid
  , capabilitySubject
    -- * Keyword fallback
  , fallbackKeywordGroups
  , collectKeywordFallbackDecision
  , fallbackDecisionToPhraseDecisions
  , matchKeywords
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Char as Char
import Data.Maybe (fromMaybe, listToMaybe)
import Control.Applicative ((<|>))
import QxFx0.Types (EmotionalTone(..))
import QxFx0.Semantic.Input.Model
  ( UtteranceSemanticFrame(..)
  , InputRouteHint(..)
  )
import QxFx0.Semantic.Proposition.Types
  ( PropositionType(..)
  , toFallbackType
  , fromFallbackType
  )
import QxFx0.Semantic.Proposition.Focus
  ( extractFocusEntity
  , extractKeyPhrases
  , isFocusCandidate
  )
import QxFx0.Semantic.Morphology (extractContentNouns)
import QxFx0.Semantic.KeywordMatch
  ( tokenizeKeywordText
  , containsKeywordPhrase
  , containsAnyKeywordPhrase
  )
import QxFx0.Policy.ParserKeywords
  ( emotionDistressKeywords, emotionHopefulKeywords
  , emotionCuriousKeywords, emotionConfrontKeywords
  , operationalCauseKeywords, operationalStatusKeywords
  , systemLogicKeywords, selfKnowledgeKeywords
  , dialogueInvitationKeywords, conceptKnowledgeKeywords
  , worldCauseKeywords, locationFormationKeywords
  , selfStateKeywords, comparisonPlausibilityKeywords
  , misunderstandingKeywords, generativePromptKeywords
  , definitionalKeywords, distinctionKeywords, groundKeywords
  , reflectiveKeywords, selfDescKeywords, purposeKeywords
  , hypotheticalKeywords, repairKeywords, contactKeywords
  , anchorKeywords, clarifyKeywords, deepenKeywords
  , confrontKeywords, nextStepKeywords, affectiveKeywords
  , epistemicKeywords, requestKeywords, evaluationKeywords
  , narrativeKeywords, contemplativeTopicKeywords
  , exploratoryKeywords
  )
import QxFx0.Types.Text (textShow)
import QxFx0.Types.PropositionFallbackAdmission
  ( RawPropositionKeywordFallbackDecision(..)
  , RawPropositionPhraseDecision(..)
  )

-- Confidence constants (inline definitions to avoid missing module)
propositionBaseConfidenceDefinitional :: Double
propositionBaseConfidenceDefinitional = 0.85

propositionBaseConfidenceDistinction :: Double
propositionBaseConfidenceDistinction = 0.80

propositionBaseConfidenceGround :: Double
propositionBaseConfidenceGround = 0.75

propositionBaseConfidenceReflective :: Double
propositionBaseConfidenceReflective = 0.70

propositionBaseConfidenceSelfDescription :: Double
propositionBaseConfidenceSelfDescription = 0.75

propositionBaseConfidencePurpose :: Double
propositionBaseConfidencePurpose = 0.70

propositionBaseConfidenceHypothetical :: Double
propositionBaseConfidenceHypothetical = 0.65

propositionBaseConfidenceRepair :: Double
propositionBaseConfidenceRepair = 0.80

propositionBaseConfidenceContact :: Double
propositionBaseConfidenceContact = 0.90

propositionBaseConfidenceAnchor :: Double
propositionBaseConfidenceAnchor = 0.75

propositionBaseConfidenceClarify :: Double
propositionBaseConfidenceClarify = 0.70

propositionBaseConfidenceDeepen :: Double
propositionBaseConfidenceDeepen = 0.75

propositionBaseConfidenceConfront :: Double
propositionBaseConfidenceConfront = 0.70

propositionBaseConfidenceNextStep :: Double
propositionBaseConfidenceNextStep = 0.75

propositionBaseConfidencePlainAssert :: Double
propositionBaseConfidencePlainAssert = 0.60

propositionBaseConfidenceAffective :: Double
propositionBaseConfidenceAffective = 0.70

propositionBaseConfidenceEpistemic :: Double
propositionBaseConfidenceEpistemic = 0.75

propositionBaseConfidenceRequest :: Double
propositionBaseConfidenceRequest = 0.80

propositionBaseConfidenceEvaluation :: Double
propositionBaseConfidenceEvaluation = 0.70

propositionBaseConfidenceNarrative :: Double
propositionBaseConfidenceNarrative = 0.65

propositionBaseConfidenceSelfKnowledge :: Double
propositionBaseConfidenceSelfKnowledge = 0.75

propositionBaseConfidenceDialogueInvitation :: Double
propositionBaseConfidenceDialogueInvitation = 0.80

propositionBaseConfidenceConceptKnowledge :: Double
propositionBaseConfidenceConceptKnowledge = 0.75

propositionBaseConfidenceWorldCause :: Double
propositionBaseConfidenceWorldCause = 0.70

propositionBaseConfidenceLocationFormation :: Double
propositionBaseConfidenceLocationFormation = 0.70

propositionBaseConfidenceSelfState :: Double
propositionBaseConfidenceSelfState = 0.75

propositionBaseConfidenceComparisonPlausibility :: Double
propositionBaseConfidenceComparisonPlausibility = 0.70

propositionBaseConfidenceMisunderstanding :: Double
propositionBaseConfidenceMisunderstanding = 0.75

propositionBaseConfidenceGenerativePrompt :: Double
propositionBaseConfidenceGenerativePrompt = 0.70

propositionBaseConfidenceContemplativeTopic :: Double
propositionBaseConfidenceContemplativeTopic = 0.70

propositionKeywordBonusCap :: Double
propositionKeywordBonusCap = 0.15

propositionKeywordBonusPerPhrase :: Double
propositionKeywordBonusPerPhrase = 0.05

-- | Get special focus entity for specific proposition types.
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

-- | Infer semantic slots (subject, target, candidates, evidence) for a proposition.
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

-- | Generate semantic evidence for a proposition type.
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

-- | Compute confidence score for a proposition classification.
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

-- | Clamp a value to [0.0, 1.0] range.
clamp01 :: Double -> Double
clamp01 value
  | value < 0.0 = 0.0
  | value > 1.0 = 1.0
  | otherwise = value

-- | Detect emotional tone from tokens.
detectEmotion :: [Text] -> EmotionalTone
detectEmotion tokens
  | containsAnyKeywordPhrase tokens emotionDistressKeywords = ToneDistress
  | containsAnyKeywordPhrase tokens emotionHopefulKeywords = ToneHopeful
  | containsAnyKeywordPhrase tokens emotionCuriousKeywords = ToneCurious
  | containsAnyKeywordPhrase tokens emotionConfrontKeywords = ToneConfrontational
  | otherwise = ToneNeutral

-- | Check if text contains concrete world nouns.
hasConcreteWorldNoun :: [Text] -> Bool
hasConcreteWorldNoun tokens =
  any (`elem` tokens)
    [ "солнце", "дождь", "небо", "мир", "земля", "вода", "огонь"
    , "время", "пространство", "природа", "вселенная", "жизнь"
    , "дом", "город", "лес", "море", "река", "камень", "ветер", "звезда", "осень"
    ]

-- | Check if text contains mental/cognitive nouns.
hasMentalNoun :: [Text] -> Bool
hasMentalNoun tokens =
  any (`elem` tokens)
    [ "мысль", "мысли", "идея", "идеи", "знание", "знания"
    , "сознание", "память", "воспоминание", "воображение"
    , "фокус", "внимание", "смысл", "образ", "мышление"
    ]

-- | Check if text contains concept-like nouns.
hasConceptLikeNoun :: [Text] -> Bool
hasConceptLikeNoun tokens = hasConcreteWorldNoun tokens || hasMentalNoun tokens || any (`elem` tokens)
  [ "логика", "свобода", "смысл", "тишина", "любовь", "страх", "истина", "дом", "душа", "бог" ]

-- | Find first concrete world noun in tokens.
firstConcreteWorldNoun :: [Text] -> Maybe Text
firstConcreteWorldNoun =
  listToMaybe . filter (`elem`
    [ "солнце", "дождь", "небо", "мир", "земля", "вода", "огонь"
    , "время", "пространство", "природа", "вселенная", "жизнь"
    , "дом", "город", "лес", "море", "река", "камень", "ветер", "звезда", "осень"
    ])

-- | Find first mental noun in tokens.
firstMentalNoun :: [Text] -> Maybe Text
firstMentalNoun =
  listToMaybe . filter (`elem`
    [ "мысль", "мысли", "идея", "идеи", "знание", "знания"
    , "сознание", "память", "воспоминание", "воображение"
    , "фокус", "внимание", "смысл", "образ", "мышление"
    ])

-- | Extract topic for dialogue invitation.
invitationTopic :: Text -> Text
invitationTopic rawText =
  fromMaybe
    "диалог"
    (extractTopicAfterMarkers rawText ["о", "об", "обо", "про", "насчет", "насчёт", "к"])

-- | Extract subject for concept knowledge question.
conceptSubject :: Text -> [Text] -> Text
conceptSubject rawText tokens =
  fromMaybe
    (extractFocusEntity rawText)
    ( firstConcreteWorldNoun tokens
   <|> firstMentalNoun tokens
   <|> extractTopicAfterMarkers rawText ["значит", "такое", "такой", "такая", "есть", "о", "об", "обо", "про"]
    )

-- | Extract topic for contemplative statement.
contemplativeTopic :: Text -> Text
contemplativeTopic rawText =
  fromMaybe
    (extractFocusEntity rawText)
    (firstNonVapid (extractContentNouns rawText) <|> lastNonVapid (extractContentNouns rawText))

-- | Find first non-vapid (valid focus) candidate.
firstNonVapid :: [Text] -> Maybe Text
firstNonVapid =
  listToMaybe . filter isFocusCandidate

-- | Find last non-vapid (valid focus) candidate.
lastNonVapid :: [Text] -> Maybe Text
lastNonVapid =
  listToMaybe . reverse . filter isFocusCandidate

-- | Extract topic after specific marker words.
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

-- | Check if text asks about the user.
asksAboutUser :: Text -> Bool
asksAboutUser rawText =
  let lowered = T.toLower rawText
  in any (`T.isInfixOf` lowered)
      [ "обо мне", "о мне", "обо мне?", "о мне?"
      , "кто я", "кто я такой", "что я такое"
      ]

-- | Extract comparison candidates from text.
comparisonCandidates :: Text -> [Text]
comparisonCandidates rawText =
  case splitByBetween normalized of
    pair@(_:_:_) -> take 2 pair
    _ -> case splitByFrom normalized of
      pair@(_:_:_) -> take 2 pair
      _ -> splitByEither normalized
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
    -- Handle "между X и Y" — the most common Russian distinction pattern.
    -- Also handles "разница между X и Y" and "различие между X и Y".
    splitByBetween txt =
      case T.breakOn "между " txt of
        (_, afterMezhdu)
          | T.null afterMezhdu -> []
          | otherwise ->
              let rest = fromMaybe afterMezhdu (T.stripPrefix "между " afterMezhdu)
              in case T.breakOn " и " rest of
                   (left, rightRaw)
                     | T.null rightRaw -> []
                     | otherwise ->
                         let right = T.drop 3 rightRaw  -- drop " и "
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

-- | Extract capability subject from tokens.
capabilitySubject :: [Text] -> Maybe Text
capabilitySubject =
  listToMaybe . filter (`notElem`
    [ "ты", "тебе", "тебя", "мне", "меня", "я", "кто", "что", "такой"
    , "умеешь", "умею", "умеет", "можешь", "могу", "может"
    , "помочь", "помоги", "помощь", "быть", "есть", "являешься"
    ])

-- | Keyword groups for fallback detection.
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

-- | Collect keyword fallback decision for a proposition type.
collectKeywordFallbackDecision :: [Text] -> (PropositionType, [Text]) -> Maybe RawPropositionKeywordFallbackDecision
collectKeywordFallbackDecision tokens (propType, keywords) =
  let matchedPhrases = filter (containsKeywordPhrase tokens) keywords
  in if null matchedPhrases
        then Nothing
        else Just (RawPropositionKeywordFallbackDecision (toFallbackType propType) matchedPhrases)

-- | Convert fallback decision to phrase decisions.
fallbackDecisionToPhraseDecisions :: RawPropositionKeywordFallbackDecision -> [RawPropositionPhraseDecision]
fallbackDecisionToPhraseDecisions rawDecision =
  map
    (\phrase -> RawPropositionPhraseDecision (rpkfdPropositionType rawDecision) phrase True)
    (rpkfdMatchedPhrases rawDecision)

-- | Match keywords against tokens for a proposition type.
matchKeywords :: [Text] -> PropositionType -> [Text] -> Maybe PropositionType
matchKeywords keywords propType tokens =
  fmap fromFallbackType (buildKeywordFallbackTypeFromDecisions
    [ RawPropositionPhraseDecision (toFallbackType propType) phrase True
    | phrase <- keywords
    , containsKeywordPhrase tokens phrase
    ])
  where
    -- Placeholder - actual implementation in Detection module
    buildKeywordFallbackTypeFromDecisions _ = Nothing

