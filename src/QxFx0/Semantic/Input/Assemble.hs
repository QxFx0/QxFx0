{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

module QxFx0.Semantic.Input.Assemble
  ( buildUtteranceSemanticFrame
  , buildUtteranceSemanticFrameMorph
  , classifyWordUnitsMorph
  ) where

import Data.List (findIndex, isPrefixOf, maximumBy)
import Data.Maybe (fromMaybe, listToMaybe)
import Data.Ord (comparing)
import Data.Text (Text)
import qualified Data.Text as T
import Control.Applicative ((<|>))

import QxFx0.Semantic.Embedding.Fallback (cosineSimilarity, fallbackEmbedding)
import QxFx0.Semantic.Input.Classify (classifyWordUnits)
import QxFx0.Semantic.Input.Lexicon
  ( discourseFunctionsForToken
  , guessMorphFeatures
  , isAssistanceLemma
  , isCapabilityLemma
  , isFunctionWord
  , isGenerativeRequestLemma
  , isIdentityLemma
  , isMentalNoun
  , semanticClassesForToken
  , isWorldNoun
  )
import QxFx0.Semantic.Input.Model
import QxFx0.Semantic.Input.Normalize (NormalizedInput(..), normalizeInput)
import QxFx0.Semantic.Morphology
  ( Case(..)
  , Mood(..)
  , MorphBackend(..)
  , MorphToken(..)
  , Number(..)
  , POS(..)
  , Person(..)
  , Tense(..)
  , analyzeMorphWithBackend
  , resolveMorphBackend
  )

buildUtteranceSemanticFrame :: Text -> UtteranceSemanticFrame
buildUtteranceSemanticFrame rawText =
  let normalized = normalizeInput rawText
      units = classifyWordUnits normalized
      routeHint = inferRouteHint normalized units
      clauseType = inferClauseType normalized
      speechAct = inferSpeechAct clauseType routeHint
      polarity = inferPolarity units
      topic = inferTopic normalized units routeHint
      focus = inferFocus units
      (agent, target) = inferParticipants normalized
      semanticCandidates = inferSemanticCandidates normalized units routeHint
      ambiguityLevel = inferAmbiguityLevel units
      confidence = inferFrameConfidence units routeHint
  in UtteranceSemanticFrame
      { usfRawText = rawText
      , usfNormalizedText = niNormalizedText normalized
      , usfWordUnits = units
      , usfClauseType = clauseType
      , usfSpeechAct = speechAct
      , usfPolarity = polarity
      , usfTopic = topic
      , usfFocus = focus
      , usfAgent = agent
      , usfTarget = target
      , usfSemanticCandidates = semanticCandidates
      , usfAmbiguityLevel = ambiguityLevel
      , usfRouteHint = routeHint
      , usfConfidence = confidence
      }

buildUtteranceSemanticFrameMorph :: Text -> IO UtteranceSemanticFrame
buildUtteranceSemanticFrameMorph rawText = do
  backend <- resolveMorphBackend
  let normalized = normalizeInput rawText
  units <- classifyWordUnitsMorph backend normalized
  let routeHint = inferRouteHint normalized units
      clauseType = inferClauseType normalized
      speechAct = inferSpeechAct clauseType routeHint
      polarity = inferPolarity units
      topic = inferTopic normalized units routeHint
      focus = inferFocus units
      (agent, target) = inferParticipants normalized
      semanticCandidates = inferSemanticCandidates normalized units routeHint
      ambiguityLevel = inferAmbiguityLevel units
      confidence = inferFrameConfidence units routeHint
  pure UtteranceSemanticFrame
      { usfRawText = rawText
      , usfNormalizedText = niNormalizedText normalized
      , usfWordUnits = units
      , usfClauseType = clauseType
      , usfSpeechAct = speechAct
      , usfPolarity = polarity
      , usfTopic = topic
      , usfFocus = focus
      , usfAgent = agent
      , usfTarget = target
      , usfSemanticCandidates = semanticCandidates
      , usfAmbiguityLevel = ambiguityLevel
      , usfRouteHint = routeHint
      , usfConfidence = confidence
      }

classifyWordUnitsMorph :: MorphBackend -> NormalizedInput -> IO [WordMeaningUnit]
classifyWordUnitsMorph backend normalizedInput =
  fmap assignSyntacticRoles (mapM (classifyTokenMorph backend) (niTokens normalizedInput))

classifyTokenMorph :: MorphBackend -> Text -> IO WordMeaningUnit
classifyTokenMorph backend token = do
  morphToken <- analyzeMorphWithBackend backend token
  let lemma = mtLemma morphToken
      pos = mapInputPos (mtPOS morphToken)
      morphFeatures = guessMorphFeatures token <> morphFeaturesFromToken morphToken
      semanticClasses = semanticClassesForToken token
      discourseFunctions = discourseFunctionsForToken token
      confidence
        | pos == PosUnknown = 0.35
        | isFunctionWord token = 0.7
        | otherwise = 0.82
      ambiguityCandidates =
        case pos of
          PosUnknown -> [token]
          PosAdverb -> [token, lemma]
          PosAdjective -> [token, lemma]
          _ -> [lemma]
  pure WordMeaningUnit
      { wmuSurfaceForm = token
      , wmuLemma = lemma
      , wmuPartOfSpeech = pos
      , wmuMorphFeatures = morphFeatures
      , wmuSyntacticRole = SynUnknown
      , wmuSemanticClasses = semanticClasses
      , wmuDiscourseFunctions = discourseFunctions
      , wmuAmbiguityCandidates = ambiguityCandidates
      , wmuConfidence = confidence
      }

morphFeaturesFromToken :: MorphToken -> [InputMorphFeature]
morphFeaturesFromToken morphToken =
  caseFeatures <> numberFeatures <> personFeatures <> tenseFeatures <> moodFeatures
  where
    caseFeatures = case mtCase morphToken of
      Just Nominative -> [FeatCaseNom]
      Just Genitive -> [FeatCaseGen]
      Just Dative -> [FeatCaseDat]
      Just Accusative -> [FeatCaseAcc]
      Just Instrumental -> [FeatCaseIns]
      Just Prepositional -> [FeatCaseLoc]
      Nothing -> []
    numberFeatures = case mtNumber morphToken of
      Just Singular -> [FeatNumberSing]
      Just Plural -> [FeatNumberPlur]
      _ -> []
    personFeatures = case mtPerson morphToken of
      Just First -> [FeatPerson1]
      Just Second -> [FeatPerson2]
      Just Third -> [FeatPerson3]
      _ -> []
    tenseFeatures = case mtTense morphToken of
      Just Past -> [FeatTensePast]
      Just Present -> [FeatTensePres]
      Just Future -> [FeatTenseFut]
      _ -> []
    moodFeatures = case mtMood morphToken of
      Just Indicative -> [FeatMoodInd]
      Just ImperativeMood -> [FeatMoodImp]
      _ -> []

assignSyntacticRoles :: [WordMeaningUnit] -> [WordMeaningUnit]
assignSyntacticRoles units =
  zipWith assign [0 ..] units
  where
    rootIndex = findRootIndex units
    assign idx unit =
      unit {wmuSyntacticRole = inferRole rootIndex idx unit}

inferRole :: Int -> Int -> WordMeaningUnit -> InputSyntacticRole
inferRole rootIndex idx unit
  | idx == rootIndex = SynRoot
  | wmuPartOfSpeech unit == PosVerb = SynPredicate
  | idx < rootIndex && wmuPartOfSpeech unit `elem` [PosNoun, PosPronoun, PosNumeral] = SynSubject
  | idx > rootIndex && wmuPartOfSpeech unit `elem` [PosNoun, PosPronoun, PosNumeral] = SynObject
  | wmuPartOfSpeech unit == PosAdjective = SynAttribute
  | wmuPartOfSpeech unit `elem` [PosAdverb, PosPreposition] = SynCircumstance
  | wmuPartOfSpeech unit `elem` [PosConjunction, PosParticle, PosInterjection] = SynMarker
  | otherwise = SynUnknown

findRootIndex :: [WordMeaningUnit] -> Int
findRootIndex units =
  case findIndex ((== PosVerb) . wmuPartOfSpeech) units of
    Just idx -> idx
    Nothing ->
      case findIndex (\u -> wmuPartOfSpeech u `elem` [PosNoun, PosPronoun]) units of
        Just idx -> idx
        Nothing -> 0

mapInputPos :: POS -> InputPartOfSpeech
mapInputPos Noun = PosNoun
mapInputPos Verb = PosVerb
mapInputPos Adj = PosAdjective
mapInputPos Adv = PosAdverb
mapInputPos Pron = PosPronoun
mapInputPos Prep = PosPreposition
mapInputPos Conj = PosConjunction
mapInputPos Part = PosParticle
mapInputPos Num = PosNumeral
mapInputPos UnknownPOS = PosUnknown

inferRouteHint :: NormalizedInput -> [WordMeaningUnit] -> InputRouteHint
inferRouteHint normalized units =
  scoreRouteHint normalized units (inferRuleRouteHint normalized units)

inferRuleRouteHint :: NormalizedInput -> [WordMeaningUnit] -> InputRouteHint
inferRuleRouteHint normalized units
  | hasPhrase tokens ["не", "понимаю"] && hasAny tokens ["тебя", "диалог", "контакт"] =
      mkHint RouteTypeRepair "misunderstanding" "misunderstanding_report" 0.9
  | isBoundarySilenceCommand normalized units =
      mkHint RouteTypeRepair "boundary_command" "boundary_silence_command" 0.91
  | isInsultSignal normalized units =
      mkHint RouteTypeRepair "boundary_command" "insult_boundary_signal" 0.9
  | isNextStepQuestion normalized units =
      mkHint RouteTypeClarify "next_step" "next_step_question" 0.89
  | isConfrontSignal normalized units =
      mkHint RouteTypeDistinguish "disagreement_confront" "confront_signal" 0.89
  | isRepairDirective normalized units =
      mkHint RouteTypeRepair "misunderstanding" "repair_directive" 0.9
  | isApologySignal normalized units =
      mkHint RouteTypeRepair "apology_repair" "apology_signal" 0.88
  | isFarewellSignal normalized units =
      mkHint RouteTypeContact "farewell_contact" "farewell_signal" 0.88
  | isGratitudeSignal normalized units =
      mkHint RouteTypeContact "gratitude_contact" "gratitude_signal" 0.87
  | isAffectiveHelpQuestion normalized units =
      mkHint RouteTypeContact "affective_help" "affective_help_question" 0.9
  | isDisagreementSignal normalized units =
      mkHint RouteTypeDistinguish "disagreement_confront" "disagreement_signal" 0.88
  | isAgreementSignal normalized units =
      mkHint RouteTypeGround "agreement_anchor" "agreement_signal" 0.86
  | isSelfFutureQuestion normalized units =
      mkHint RouteTypeDescribe "self_knowledge" "self_future_question" 0.9
  | isOpinionQuestion normalized units =
      mkHint RouteTypeDescribe "opinion_question" "opinion_question" 0.88
  | isNameQuestion normalized units =
      mkHint RouteTypeDescribe "self_knowledge" "self_name_question" 0.9
  | isSelfDescriptionRequest normalized units =
      mkHint RouteTypeDescribe "self_knowledge" "self_knowledge_profile_request" 0.9
  | isSelfIntentQuestion normalized units =
      mkHint RouteTypeDescribe "self_state" "self_intent_question" 0.9
  | isSelfMetaQuestion normalized units =
      mkHint RouteTypeDescribe "self_knowledge" "self_meta_question_direct" 0.9
  | isSelfThoughtQuestion normalized units =
      mkHint RouteTypeDescribe "self_state" "self_state_question_direct" 0.89
  | isGenericHowYouProcessQuestion normalized units =
      mkHint RouteTypeDescribe "system_logic" "self_process_how_question_generic" 0.89
  | hasPhrase tokens ["как", "ты", "думаешь"] || hasPhrase tokens ["как", "вы", "думаете"] =
      mkHint RouteTypeDescribe "self_state" "self_state_how_question" 0.9
  | hasPhrase tokens ["как", "ты", "формируешь", "ответ"] =
      mkHint RouteTypeDescribe "self_knowledge" "self_response_formation_question" 0.9
  | hasPhrase tokens ["как", "ты", "выбираешь", "слова"] =
      mkHint RouteTypeDescribe "self_knowledge" "self_word_choice_question" 0.9
  | hasPhrase tokens ["как", "ты", "принимаешь", "решение"] =
      mkHint RouteTypeDescribe "self_knowledge" "self_decision_question" 0.9
  | hasPhrase tokens ["как", "ты", "держишь", "рамку"] =
      mkHint RouteTypeDescribe "self_knowledge" "self_frame_holding_question" 0.9
  | asksSelfRoleQuestion normalized units =
      mkHint RouteTypeDescribe "self_knowledge" "self_role_question" 0.88
  | asksSystemLogicQuestion normalized units =
      mkHint RouteTypeDescribe "system_logic" "system_logic_question" 0.88
  | asksCapabilityQuestion normalized units =
      mkHint RouteTypeDescribe "self_knowledge" "system_capability_question" 0.88
  | asksAssistanceQuestion normalized units =
      mkHint RouteTypeDescribe "self_knowledge" "directed_help_question" 0.9
  | asksUserIdentityQuestion normalized units =
      mkHint RouteTypeDescribe "self_knowledge" "user_identity_question" 0.88
  | isSystemIdentityQuestion normalized units =
      mkHint RouteTypeDescribe "self_knowledge" "system_identity_probe" 0.86
  | isDirectSelfProbeQuestion normalized units =
      mkHint RouteTypeDescribe "self_knowledge" "direct_self_probe_question" 0.88
  | isGreetingOrSmallTalk normalized units =
      mkHint RouteTypeContact "greeting_smalltalk" "greeting_or_smalltalk" 0.85
  | shortDialogueProbe tokens && not (niIsQuestion normalized) && hasAny tokens ["поговорим", "обсудим"] =
      mkHint RouteTypeContact "short_dialogue_probe" "short_dialogue_probe" 0.88
  | isDialogueQuestion normalized units =
      mkHint RouteTypeDeepen "dialogue_invitation" "dialogue_question" 0.86
  | hasAny tokens ["поговорим", "обсудим"] || hasPhrase tokens ["давай", "поговорим"] =
      mkHint RouteTypeDeepen "dialogue_invitation" "dialogue_invitation" 0.88
  | asksThoughtAboutTopicQuestion normalized units =
      mkHint RouteTypeDeepen "contemplative_topic" "thought_about_topic_question" 0.88
  | isDefinitionalQuestion normalized units =
      mkHint RouteTypeDefine "concept_knowledge" "concept_question_form" 0.87
  | isRelationComparisonQuestion normalized units =
      mkHint RouteTypeDistinguish "comparison_relation" "relation_comparison_signal" 0.85
  | isPurposeFunctionQuestion normalized units =
      mkHint RouteTypeGround "purpose_function" "purpose_function_question" 0.86
  | hasAny tokens ["знаешь", "известно"] && hasPhrase tokens ["что", "такое"] =
      mkHint RouteTypeDefine "concept_knowledge" "knowledge_plus_definition" 0.89
  | hasPhrase tokens ["о", "чем", "ты", "думаешь"] || hasPhrase tokens ["что", "у", "тебя", "на", "уме"] =
      mkHint RouteTypeDescribe "self_state" "self_state_question" 0.86
  | (hasLemmaAny units ["в", "что"] && hasLemmaAny units ["твой", "твоя", "твое", "ваш"] && hasLemmaAny units ["логика", "смысл", "суть"]) =
      mkHint RouteTypeDescribe "system_logic" "system_logic_question" 0.86
  | isGenerativeQualityPrompt normalized units =
      mkHint RouteTypeDescribe "generative_prompt" "quality_modulated_generation" 0.86
  | (hasAny tokens ["скажи", "дай"] || hasAny tokens ["еще", "ещё", "новую", "другую"])
      && hasAny tokens ["мысль", "идею", "идея", "слово", "фразу"] =
      mkHint RouteTypeDescribe "generative_prompt" "generative_request" 0.84
  | hasAny tokens ["почему"] && (hasLemmaAny units ["система", "сбой", "ошибка", "ты", "вы"]) =
      mkHint RouteTypeGround "operational_cause" "why_plus_system_noun" 0.84
  | hasAny tokens ["почему"] && any (isWorldNoun . wmuLemma) units =
      mkHint RouteTypeGround "world_cause" "why_plus_world_noun" 0.84
  | hasAny tokens ["почему"] && not (isAffectiveHelpQuestion normalized units) =
      mkHint RouteTypeGround "world_cause" "why_generic_ground" 0.82
  | isLocationFormationQuestion normalized units =
      mkHint RouteTypeGround "location_formation" "where_plus_mental_noun" 0.84
  | isConcealmentLocationQuestion normalized units =
      mkHint RouteTypeDeepen "contemplative_topic" "where_plus_concealment_question" 0.84
  | hasPhrase tokens ["кто", "ты"]
      || hasPhrase tokens ["кто", "я"]
      || hasPhrase tokens ["что", "ты", "есть"]
      || hasPhrase tokens ["что", "я", "такое"]
      || hasPhrase tokens ["что", "ты", "такое"]
      || hasPhrase tokens ["чем", "ты", "являешься"]
      || hasPhrase tokens ["кем", "ты", "являешься"]
      || hasPhrase tokens ["что", "ты", "знаешь", "о", "себе"]
      || (hasPhrase tokens ["у", "тебя"] && hasAny tokens ["мысль", "идея"] && hasAny tokens ["одна", "всего"]) =
      mkHint RouteTypeDescribe "self_knowledge" "self_knowledge_question" 0.86
  | isContemplativeQuestion normalized units =
      mkHint RouteTypeDeepen "contemplative_topic" "contemplative_question" 0.85
  | isReflectiveAssertion normalized units =
      mkHint RouteTypeDeepen "contemplative_topic" "reflective_assertion" 0.83
  | isEverydayEventAssertion normalized units =
      mkHint RouteTypeGround "everyday_event" "declarative_action_world_object" 0.84
  | contemplativeInput units =
      mkHint RouteTypeDeepen "contemplative_topic" "single_or_short_contemplative_input" 0.8
  | otherwise =
      mkHint RouteTypeUnknown "unknown" "no_high_confidence_semantic_route" 0.55
  where
    tokens = niTokens normalized

scoreRouteHint :: NormalizedInput -> [WordMeaningUnit] -> InputRouteHint -> InputRouteHint
scoreRouteHint normalized units ruleHint =
  let clauseType = inferClauseType normalized
      normalizedText = niNormalizedText normalized
      scoredCandidates = map (buildRouteCandidate normalized units clauseType normalizedText ruleHint) routeCatalog
      bestCandidate =
        if null scoredCandidates
          then defaultCandidate ruleHint
          else maximumBy (comparing rcFinalScore) scoredCandidates
      ruleCandidate = fallbackRuleCandidate ruleHint scoredCandidates
      preserveRuleHint =
        irhTag ruleHint `elem`
          [ "misunderstanding"
          , "boundary_command"
          , "apology_repair"
          , "farewell_contact"
          , "gratitude_contact"
          , "affective_help"
          , "greeting_smalltalk"
          , "purpose_function"
          , "comparison_relation"
          , "disagreement_confront"
          , "next_step"
          , "short_dialogue_probe"
          , "concept_knowledge"
          , "self_knowledge"
          , "self_state"
          , "system_logic"
          , "operational_cause"
          , "world_cause"
          , "location_formation"
          , "generative_prompt"
          ]
      useBest =
        (not preserveRuleHint)
          && ( irhTag ruleHint == "unknown"
                || rcFinalScore bestCandidate > rcFinalScore ruleCandidate + 0.05
             )
      chosen = if useBest then bestCandidate else ruleCandidate
  in InputRouteHint
      { irhType = rcRouteType chosen
      , irhTag = rcTag chosen
      , irhReason = rcReason chosen
      , irhRuleScore = rcRuleScore chosen
      , irhSemanticScore = rcSemanticScore chosen
      , irhSyntacticScore = rcSyntacticScore chosen
      , irhEmbeddingScore = rcEmbeddingScore chosen
      , irhEvidence = rcEvidence chosen
      , irhConfidence = rcFinalScore chosen
      }

data RouteCandidate = RouteCandidate
  { rcRouteType :: !InputRouteType
  , rcTag :: !Text
  , rcReason :: !Text
  , rcRuleScore :: !Double
  , rcSemanticScore :: !Double
  , rcSyntacticScore :: !Double
  , rcEmbeddingScore :: !Double
  , rcFinalScore :: !Double
  , rcEvidence :: ![Text]
  }

buildRouteCandidate
  :: NormalizedInput
  -> [WordMeaningUnit]
  -> InputClauseType
  -> Text
  -> InputRouteHint
  -> (InputRouteType, Text, Text, [Text])
  -> RouteCandidate
buildRouteCandidate normalized units clauseType normalizedText ruleHint (routeType, tag, reason, prototypes) =
  let ruleScore = ruleAlignmentScore ruleHint routeType tag
      semanticScore = semanticScoreForTag normalized units tag
      syntacticScore = syntacticScoreForRoute clauseType routeType
      embeddingScore = embeddingScoreForTag normalizedText prototypes
      finalScore = clamp01 ((ruleScore * 0.42) + (semanticScore * 0.23) + (syntacticScore * 0.15) + (embeddingScore * 0.20))
      evidence =
        [ "rule=" <> showScore ruleScore
        , "semantic=" <> showScore semanticScore
        , "syntax=" <> showScore syntacticScore
        , "embedding=" <> showScore embeddingScore
        , "final=" <> showScore finalScore
        ]
  in RouteCandidate
      { rcRouteType = routeType
      , rcTag = tag
      , rcReason = reason
      , rcRuleScore = ruleScore
      , rcSemanticScore = semanticScore
      , rcSyntacticScore = syntacticScore
      , rcEmbeddingScore = embeddingScore
      , rcFinalScore = finalScore
      , rcEvidence = evidence
      }

defaultCandidate :: InputRouteHint -> RouteCandidate
defaultCandidate hint =
  RouteCandidate
    { rcRouteType = irhType hint
    , rcTag = irhTag hint
    , rcReason = irhReason hint
    , rcRuleScore = irhConfidence hint
    , rcSemanticScore = 0.5
    , rcSyntacticScore = 0.5
    , rcEmbeddingScore = 0.5
    , rcFinalScore = irhConfidence hint
    , rcEvidence = ["fallback_rule_hint"]
    }

fallbackRuleCandidate :: InputRouteHint -> [RouteCandidate] -> RouteCandidate
fallbackRuleCandidate ruleHint candidates =
  case findByTag (irhTag ruleHint) candidates of
    Just candidate -> candidate
    Nothing ->
      case findByType (irhType ruleHint) candidates of
        Just candidate -> candidate
        Nothing -> defaultCandidate ruleHint
  where
    findByTag wanted = listToMaybe . filter (\candidate -> rcTag candidate == wanted)
    findByType wanted = listToMaybe . filter (\candidate -> rcRouteType candidate == wanted)

ruleAlignmentScore :: InputRouteHint -> InputRouteType -> Text -> Double
ruleAlignmentScore ruleHint routeType tag
  | irhTag ruleHint == tag = irhConfidence ruleHint
  | irhType ruleHint == routeType = clamp01 (irhConfidence ruleHint * 0.72)
  | irhTag ruleHint == "unknown" = 0.18
  | otherwise = 0.08

semanticScoreForTag :: NormalizedInput -> [WordMeaningUnit] -> Text -> Double
semanticScoreForTag normalized units tag
  | tag == "misunderstanding" =
      if hasPhrase tokens ["не", "понимаю"] then 0.95 else 0.2
  | tag == "boundary_command" =
      if isBoundarySilenceCommand normalized units || isInsultSignal normalized units then 0.95 else 0.2
  | tag == "apology_repair" =
      if isApologySignal normalized units then 0.94 else 0.22
  | tag == "farewell_contact" =
      if isFarewellSignal normalized units then 0.93 else 0.22
  | tag == "gratitude_contact" =
      if isGratitudeSignal normalized units then 0.93 else 0.22
  | tag == "affective_help" =
      if isAffectiveHelpQuestion normalized units then 0.95 else 0.2
  | tag == "disagreement_confront" =
      if isDisagreementSignal normalized units then 0.93 else 0.24
  | tag == "agreement_anchor" =
      if isAgreementSignal normalized units then 0.92 else 0.24
  | tag == "opinion_question" =
      if isOpinionQuestion normalized units then 0.93 else 0.25
  | tag == "system_logic" =
      if asksSystemLogicQuestion normalized units then 0.93 else 0.25
  | tag == "self_knowledge" =
      if asksCapabilityQuestion normalized units || asksAssistanceQuestion normalized units
           || isNameQuestion normalized units || isSelfDescriptionRequest normalized units
           || asksUserIdentityQuestion normalized units || isSystemIdentityQuestion normalized units
         then 0.92
         else 0.28
  | tag == "greeting_smalltalk" =
      if isGreetingOrSmallTalk normalized units then 0.93 else 0.2
  | tag == "dialogue_invitation" =
      if isDialogueQuestion normalized units
           || ((hasAny tokens ["поговорим", "обсудим"]) && not (shortDialogueProbe tokens && not (niIsQuestion normalized)))
        then 0.92
        else 0.24
  | tag == "short_dialogue_probe" =
      if shortDialogueProbe tokens && not (niIsQuestion normalized) && hasAny tokens ["поговорим", "обсудим"] then 0.92 else 0.2
  | tag == "concept_knowledge" =
      if isDefinitionalQuestion normalized units || (hasAny tokens ["знаешь", "известно"] && hasPhrase tokens ["что", "такое"])
         then 0.92
         else 0.26
  | tag == "purpose_function" =
      if isPurposeFunctionQuestion normalized units then 0.92 else 0.25
  | tag == "comparison_relation" =
      if isRelationComparisonQuestion normalized units then 0.92 else 0.24
  | tag == "self_state" =
      if isSelfThoughtQuestion normalized units
          || hasPhrase tokens ["о", "чем", "ты", "думаешь"] || hasPhrase tokens ["что", "у", "тебя", "на", "уме"]
        then 0.92
        else 0.25
  | tag == "generative_prompt" =
      if isGenerativeQualityPrompt normalized units
           || ((hasAny tokens ["скажи", "дай"] || hasAny tokens ["еще", "ещё", "новую", "другую"])
                && hasAny tokens ["мысль", "идею", "идея", "слово", "фразу"])
        then 0.92
        else 0.24
  | tag == "operational_cause" =
      if hasAny tokens ["почему"] && hasLemmaAny units ["система", "сбой", "ошибка", "ты", "вы"] then 0.9 else 0.24
  | tag == "world_cause" =
      if hasAny tokens ["почему"] && any (isWorldNoun . wmuLemma) units then 0.9 else 0.24
  | tag == "location_formation" =
      if isLocationFormationQuestion normalized units then 0.91 else 0.24
  | tag == "next_step" =
      if isNextStepQuestion normalized units then 0.93 else 0.22
  | tag == "everyday_event" =
      if isEverydayEventAssertion normalized units then 0.9 else 0.24
  | tag == "contemplative_topic" =
      if isContemplativeQuestion normalized units || isReflectiveAssertion normalized units || contemplativeInput units then 0.88 else 0.25
  | otherwise = 0.22
  where
    tokens = niTokens normalized

syntacticScoreForRoute :: InputClauseType -> InputRouteType -> Double
syntacticScoreForRoute clauseType routeType =
  case clauseType of
    ClauseInterrogativeInput ->
      if routeType `elem` [RouteTypeUnknown]
        then 0.35
        else 0.84
    ClauseDeclarativeInput ->
      if routeType `elem` [RouteTypeGround, RouteTypeDeepen, RouteTypeDescribe, RouteTypeRepair]
        then 0.76
        else 0.58
    ClauseImperativeInput ->
      if routeType `elem` [RouteTypeDescribe, RouteTypeClarify, RouteTypeContact]
        then 0.78
        else 0.55
    ClauseFragmentInput ->
      if routeType `elem` [RouteTypeDeepen, RouteTypeContact, RouteTypeDescribe]
        then 0.72
        else 0.5

embeddingScoreForTag :: Text -> [Text] -> Double
embeddingScoreForTag normalizedText prototypes =
  let inputVec = fallbackEmbedding (T.unpack normalizedText)
      similarities =
        [ (realToFrac (cosineSimilarity inputVec (fallbackEmbedding (T.unpack prototype))) + 1.0) / 2.0
        | prototype <- prototypes
        ]
  in case similarities of
      [] -> 0.0
      _ -> maximum similarities

routeCatalog :: [(InputRouteType, Text, Text, [Text])]
routeCatalog =
  [ (RouteTypeRepair, "misunderstanding", "semantic_misunderstanding", ["я не понимаю тебя", "контакт потерян", "диалог распался"])
  , (RouteTypeRepair, "boundary_command", "semantic_boundary_command", ["молчи", "замолчи", "заткнись", "ты тупой"])
  , (RouteTypeRepair, "apology_repair", "semantic_apology_repair", ["извини", "прости", "прошу прощения"])
  , (RouteTypeContact, "farewell_contact", "semantic_farewell_contact", ["пока", "до свидания", "увидимся"])
  , (RouteTypeContact, "gratitude_contact", "semantic_gratitude_contact", ["спасибо", "благодарю", "thank you"])
  , (RouteTypeContact, "affective_help", "semantic_affective_help"
      , [ "что делать если грустно"
        , "как не переживать"
        , "как не волноваться"
        , "как успокоиться"
        , "как сохранить спокойствие"
        , "как не паниковать"
        , "как выйти из апатии"
        , "как вернуть мотивацию"
        , "как вернуть силы"
        , "как собраться с силами"
        , "не хочется ничего делать"
        , "нет энергии"
        , "руки опускаются"
        , "ничего не радует"
        , "все бесит"
        , "что мне делать дальше"
        , "нет сил"
        , "мне тревожно"
        , "мне плохо"
        ]
    )
  , (RouteTypeGround, "agreement_anchor", "semantic_agreement_anchor", ["я согласен", "верно", "логично"])
  , (RouteTypeDistinguish, "disagreement_confront", "semantic_disagreement_confront", ["я не согласен", "сомневаюсь", "это спорно"])
  , (RouteTypeDescribe, "opinion_question", "semantic_opinion_question", ["какое твое мнение", "как считаешь", "что думаешь об этом"])
  , (RouteTypeDescribe, "system_logic", "semantic_system_logic", ["в чем твоя логика", "как ты устроен", "как ты работаешь"])
  , (RouteTypeDescribe, "self_knowledge", "semantic_self_knowledge", ["кто ты", "что ты такое", "что ты знаешь о себе", "ты можешь мне помочь", "как тебя зовут", "расскажи о себе", "что ты можешь рассказать о себе"])
  , (RouteTypeContact, "greeting_smalltalk", "semantic_greeting_smalltalk", ["привет", "как дела", "как жизнь"])
  , (RouteTypeContact, "short_dialogue_probe", "semantic_short_dialogue_probe", ["поговорим", "обсудим"])
  , (RouteTypeDeepen, "dialogue_invitation", "semantic_dialogue_invitation", ["поговорим", "давай поговорим", "обсудим"])
  , (RouteTypeDefine, "concept_knowledge", "semantic_concept_knowledge", ["что такое", "что значит", "знаешь что такое"])
  , (RouteTypeGround, "purpose_function", "semantic_purpose_function", ["в чем функция", "зачем нужен", "для чего"])
  , (RouteTypeDistinguish, "comparison_relation", "semantic_comparison_relation", ["что логичнее", "в чем разница", "или это"])
  , (RouteTypeDescribe, "self_state", "semantic_self_state", ["о чем ты думаешь", "что у тебя на уме"])
  , (RouteTypeDescribe, "generative_prompt", "semantic_generative_prompt", ["скажи мысль", "дай идею", "скажи что-нибудь"])
  , (RouteTypeGround, "operational_cause", "semantic_operational_cause", ["почему система не работает", "почему ты не отвечаешь"])
  , (RouteTypeGround, "world_cause", "semantic_world_cause", ["почему небо голубое", "почему солнце светит"])
  , (RouteTypeGround, "location_formation", "semantic_location_formation", ["где формируется мысль", "откуда берется идея"])
  , (RouteTypeClarify, "next_step", "semantic_next_step"
      , [ "что дальше"
        , "что теперь"
        , "что потом"
        , "с чего начать"
        , "какой первый шаг"
        , "как действовать дальше"
        ]
    )
  , (RouteTypeGround, "everyday_event", "semantic_everyday_event", ["я купил дом", "я живу дома"])
  , (RouteTypeDeepen, "contemplative_topic", "semantic_contemplative_topic", ["тишина", "смысл", "истина", "я думаю"])
  , (RouteTypeUnknown, "unknown", "semantic_unknown", ["что", "непонятно"])
  ]

showScore :: Double -> Text
showScore value =
  let scaled :: Integer
      scaled = round (value * 1000)
  in T.pack (show ((fromIntegral scaled / 1000.0) :: Double))

isGreetingOrSmallTalk :: NormalizedInput -> [WordMeaningUnit] -> Bool
isGreetingOrSmallTalk normalized _units =
  let tokens = niTokens normalized
  in hasAny tokens ["привет", "здравствуй", "здравствуйте", "салют", "хай"]
  || hasPhrase tokens ["здравия", "желаю"]
  || hasPhrase tokens ["доброго", "времени", "суток"]
  || hasPhrase tokens ["как", "дела"]
  || hasPhrase tokens ["как", "жизнь"]
  || hasShortHowYouSmallTalk tokens
  || hasPhrase tokens ["как", "сам"]
  || hasPhrase tokens ["как", "настроение"]
  || hasPhrase tokens ["рад", "видеть"]
  || hasPhrase tokens ["рад", "тебя", "видеть"]
  || hasPhrase tokens ["рад", "вас", "видеть"]
  || hasPhrase tokens ["добрый", "день"]
  || hasPhrase tokens ["доброе", "утро"]
  || hasPhrase tokens ["добрый", "вечер"]
  || hasPhrase tokens ["контакт", "есть"]
  || hasPhrase tokens ["есть", "контакт"]
  || hasPhrase tokens ["мы", "на", "связи"]
  || hasPhrase tokens ["начнем", "разговор"]
  || hasPhrase tokens ["начнем", "диалог"]
  || hasPhrase tokens ["начнем", "беседу"]
  || hasPhrase tokens ["начнем", "общение"]
  || hasPhrase tokens ["начнём", "разговор"]
  || hasPhrase tokens ["начнём", "диалог"]
  || hasPhrase tokens ["я", "вернулся"]
  || hasPhrase tokens ["снова", "привет"]
  || hasPhrase tokens ["слышишь", "меня"]
  || hasPhrase tokens ["ты", "онлайн"]
  || hasPhrase tokens ["продолжим", "диалог"]
  || hasPhrase tokens ["продолжим", "разговор"]
  || hasPhrase tokens ["продолжим", "общение"]
  || hasPhrase tokens ["можем", "поговорить"]
  || hasPhrase tokens ["можем", "начать"]
  || hasPhrase tokens ["можем", "продолжить"]
  || hasPhrase tokens ["я", "снова", "здесь"]
  || hasPhrase tokens ["я", "вернулся", "к", "диалогу"]
  || hasPhrase tokens ["подключился", "снова"]
  || hasPhrase tokens ["я", "здесь", "и", "слушаю"]
  || hasPhrase tokens ["тут", "кто-нибудь", "есть"]
  || hasPhrase tokens ["на", "связи"]
  || hasPhrase tokens ["можем", "держать", "контакт"]
  || hasPhrase tokens ["контакт", "подтверждаю"]
  || hasPhrase tokens ["давай", "начнем"]
  || hasPhrase tokens ["давай", "начнём"]

hasShortHowYouSmallTalk :: [Text] -> Bool
hasShortHowYouSmallTalk tokens =
  (hasPhrase tokens ["как", "ты"] || hasPhrase tokens ["как", "вы"])
    && not (hasAny tokens
      [ "будешь", "будете", "можешь", "можете", "умеешь", "умеете"
      , "определять", "сделать", "делать", "объяснить", "думаешь"
      , "думаете", "работаешь", "работаете", "формируешь", "формируете"
      , "выбираешь", "выбираете", "принимаешь", "принимаете"
      , "держишь", "держите", "устроен", "устроена", "устроено"
      ]
    )
    && length tokens <= 4

isFarewellSignal :: NormalizedInput -> [WordMeaningUnit] -> Bool
isFarewellSignal normalized _units =
  let tokens = niTokens normalized
  in hasAny tokens ["пока", "прощай", "бывай", "увидимся", "goodbye", "bye"]
    || hasPhrase tokens ["до", "свидания"]
    || hasPhrase tokens ["до", "встречи"]
    || hasPhrase tokens ["всего", "доброго"]
    || hasPhrase tokens ["всего", "хорошего"]

isGratitudeSignal :: NormalizedInput -> [WordMeaningUnit] -> Bool
isGratitudeSignal normalized _units =
  let tokens = niTokens normalized
  in hasAny tokens ["спасибо", "благодарю", "благодарен", "благодарна", "признателен", "thanks"]
    || hasPhrase tokens ["большое", "спасибо"]
    || hasPhrase tokens ["thank", "you"]

isApologySignal :: NormalizedInput -> [WordMeaningUnit] -> Bool
isApologySignal normalized _units =
  let tokens = niTokens normalized
  in hasAny tokens ["извини", "извините", "прости", "простите", "сорри", "виноват", "виновата"]
    || hasPhrase tokens ["прошу", "прощения"]

isAgreementSignal :: NormalizedInput -> [WordMeaningUnit] -> Bool
isAgreementSignal normalized _units =
  let tokens = niTokens normalized
  in hasPhrase tokens ["я", "согласен"]
    || hasPhrase tokens ["я", "согласна"]
    || hasPhrase tokens ["мы", "согласны"]
    || hasPhrase tokens ["полностью", "согласен"]
    || hasAny tokens ["согласен", "согласна", "согласны", "верно", "точно", "логично", "именно"]

isDisagreementSignal :: NormalizedInput -> [WordMeaningUnit] -> Bool
isDisagreementSignal normalized _units =
  let tokens = niTokens normalized
  in hasPhrase tokens ["не", "согласен"]
    || hasPhrase tokens ["не", "согласна"]
    || hasPhrase tokens ["не", "согласны"]
    || hasPhrase tokens ["я", "не", "согласен"]
    || hasPhrase tokens ["я", "не", "согласна"]
    || hasAny tokens ["сомневаюсь", "оспариваю", "спорно", "возражаю", "противоречие", "противоречиво", "противоречит"]
    || hasAnyPrefix tokens ["противореч"]

isConfrontSignal :: NormalizedInput -> [WordMeaningUnit] -> Bool
isConfrontSignal normalized units =
  isDisagreementSignal normalized units
    || hasPhrase tokens ["это", "противоречие"]
    || hasPhrase tokens ["это", "противоречиво"]
    || T.isInfixOf "противореч" (niNormalizedText normalized)
  where
    tokens = niTokens normalized

isBoundarySilenceCommand :: NormalizedInput -> [WordMeaningUnit] -> Bool
isBoundarySilenceCommand normalized _units =
  let tokens = niTokens normalized
  in hasPhrase tokens ["можешь", "замолчать"]
      || hasPhrase tokens ["можете", "замолчать"]
      || hasAny tokens ["молчи", "замолчи", "заткнись"]

isInsultSignal :: NormalizedInput -> [WordMeaningUnit] -> Bool
isInsultSignal normalized _units =
  let tokens = niTokens normalized
      lowered = niNormalizedText normalized
  in hasAny tokens ["тупой", "тупая", "тупое", "идиот", "идиотка", "дурной", "глупый", "бесполезный"]
      || (hasAny tokens ["ты", "вы"] && hasAny tokens ["программа", "програма"] && hasAny tokens ["тупой", "тупая", "глупый", "плохой"])
      || T.isInfixOf "ты туп" lowered

isNextStepQuestion :: NormalizedInput -> [WordMeaningUnit] -> Bool
isNextStepQuestion normalized units =
  let planningPattern =
        hasPhrase tokens ["с", "чего", "начать"]
          || hasPhrase tokens ["какой", "первый", "шаг"]
          || hasPhrase tokens ["что", "мне", "делать", "дальше"]
          || hasPhrase tokens ["что", "сейчас", "делать"]
          || hasPhrase tokens ["как", "действовать", "дальше"]
          || hasPhrase tokens ["нет", "понимания", "что", "дальше"]
      distressPlusAction =
        hasAny tokens ["что", "как"]
          && hasAny tokens ["делать", "дальше", "шаг", "начать"]
          && hasAny tokens ["тревожно", "тревога", "плохо", "грустно", "страшно", "апатия", "переживать", "волноваться", "сил", "устал", "устала"]
  in niIsQuestion normalized
    && ( hasPhrase tokens ["что", "дальше"]
      || hasPhrase tokens ["дальше", "что"]
      || hasPhrase tokens ["что", "теперь"]
      || hasPhrase tokens ["что", "потом"]
      || planningPattern
      || distressPlusAction
      || isAffectiveHelpQuestion normalized units
      )
  where
    tokens = niTokens normalized

isOpinionQuestion :: NormalizedInput -> [WordMeaningUnit] -> Bool
isOpinionQuestion normalized _units =
  let tokens = niTokens normalized
  in niIsQuestion normalized
    && not (hasPhrase tokens ["какое", "у", "тебя", "будущее"])
    && not (hasPhrase tokens ["какое", "у", "вас", "будущее"])
    && not (hasPhrase tokens ["у", "тебя", "есть", "будущее"])
    && not (hasPhrase tokens ["у", "вас", "есть", "будущее"])
    && ( hasPhrase tokens ["какое", "твое", "мнение"]
      || hasPhrase tokens ["какое", "ваше", "мнение"]
      || hasPhrase tokens ["каково", "твое", "мнение"]
      || hasPhrase tokens ["как", "считаешь"]
      || hasPhrase tokens ["как", "считаете"]
      || hasPhrase tokens ["как", "думаешь"]
      || hasPhrase tokens ["что", "думаешь"]
      || hasPhrase tokens ["по", "твоему"]
      || hasPhrase tokens ["по", "вашему"]
      )

isDialogueQuestion :: NormalizedInput -> [WordMeaningUnit] -> Bool
isDialogueQuestion normalized _units =
  let tokens = niTokens normalized
  in hasAny tokens ["говорим", "говоришь", "разговариваем"]
  || hasPhrase tokens ["мы", "с", "тобой"]
  || hasPhrase tokens ["мы", "с", "вами"]
  || hasPhrase tokens ["мы", "разговариваем"]

shortDialogueProbe :: [Text] -> Bool
shortDialogueProbe tokens =
  (tokens == ["поговорим"] || tokens == ["обсудим"] || hasPhrase tokens ["давай", "поговорим"])
    && length tokens <= 2

isDefinitionalQuestion :: NormalizedInput -> [WordMeaningUnit] -> Bool
isDefinitionalQuestion normalized units =
  let tokens = niTokens normalized
      isWhatIsPattern =
        hasPhrase tokens ["что", "есть"] && length tokens >= 3
  in not (hasLemmaAny units ["твой", "твоя", "твое", "ваш"]) &&
    ( hasPhrase tokens ["что", "такое"]
    || hasPhrase tokens ["что", "значит"]
    || hasPhrase tokens ["кто", "такой"]
    || hasPhrase tokens ["кто", "такая"]
    || hasPhrase tokens ["кто", "такое"]
    || (hasPhrase tokens ["что", "есть"] && any (\u -> wmuPartOfSpeech u == PosNoun) units)
    || isWhatIsPattern
    || hasPhrase tokens ["как", "определить"]
    )

isPurposeFunctionQuestion :: NormalizedInput -> [WordMeaningUnit] -> Bool
isPurposeFunctionQuestion normalized units =
  let tokens = niTokens normalized
      hasPurposeLexeme = hasLemmaAny units ["зачем", "цель", "назначение", "функция", "роль", "задача", "польза"]
      hasPurposePattern =
        hasPhrase tokens ["для", "чего"]
          || hasPhrase tokens ["почему", "нужный"]
          || hasPhrase tokens ["в", "чем", "функция"]
          || hasPhrase tokens ["в", "чем", "роль"]
          || hasPhrase tokens ["в", "чем", "назначение"]
          || hasPhrase tokens ["какова", "функция"]
          || hasPhrase tokens ["какова", "роль"]
          || hasPhrase tokens ["какова", "задача"]
          || hasPhrase tokens ["в", "чем", "польза"]
          || hasPhrase tokens ["какая", "функция"]
          || hasPhrase tokens ["какая", "роль"]
          || ((hasAny tokens ["каков", "какова", "каковы", "какой", "какая", "какое"] || hasPhrase tokens ["в", "чем"] || hasPhrase tokens ["в", "чём"])
                && hasAny tokens ["функция", "роль", "назначение", "цель", "задача"])
  in ( hasLemmaAny units ["зачем", "цель", "назначение"]
  || hasPhrase (niTokens normalized) ["для", "чего"]
  || hasPhrase (niTokens normalized) ["почему", "нужный"]
  || hasPhrase (niTokens normalized) ["в", "чем", "функция"]
  || hasPhrase (niTokens normalized) ["какова", "функция"]
  || hasPhrase (niTokens normalized) ["какова", "роль"]
  || hasPhrase (niTokens normalized) ["в", "чем", "роль"]
  || hasPurposePattern
  || (hasPurposeLexeme && any isObjectLikeUnit units)
  )

isRelationComparisonQuestion :: NormalizedInput -> [WordMeaningUnit] -> Bool
isRelationComparisonQuestion normalized units =
  let tokens = niTokens normalized
      hasDistinctByFrom =
        hasPhrase tokens ["как", "отличить"] && hasAny tokens ["от"]
  in (hasLemmaAny units ["разница", "отличие", "между"]
   || hasPhrase (niTokens normalized) ["как", "отличить"]
   || hasPhrase (niTokens normalized) ["чем", "отличается"]
   || hasDistinctByFrom
   || (hasAny (niTokens normalized) ["или"] && hasAny (niTokens normalized) ["логичнее", "вероятнее", "естественнее", "правильнее"]))

isContemplativeQuestion :: NormalizedInput -> [WordMeaningUnit] -> Bool
isContemplativeQuestion normalized units =
  niIsQuestion normalized &&
  any (\u -> SemContemplative `elem` wmuSemanticClasses u) units
    && not (hasSecondPersonReference units)
    && not (isAffectiveHelpQuestion normalized units)
    && not (isNextStepQuestion normalized units)
    && not (isDefinitionalQuestion normalized units)
    && not (isPurposeFunctionQuestion normalized units)
    && not (isRelationComparisonQuestion normalized units)
    && not (isOpinionQuestion normalized units)
    && not (asksSystemLogicQuestion normalized units)

isLocationFormationQuestion :: NormalizedInput -> [WordMeaningUnit] -> Bool
isLocationFormationQuestion normalized units =
  niIsQuestion normalized
    && hasLemmaAny units ["где", "откуда"]
    && any (\u -> wmuLemma u `elem` formationVerbs) units
    && (any (isMentalNoun . wmuLemma) units || any (\u -> SemAbstractConcept `elem` wmuSemanticClasses u) units)

isConcealmentLocationQuestion :: NormalizedInput -> [WordMeaningUnit] -> Bool
isConcealmentLocationQuestion normalized units =
  niIsQuestion normalized
    && hasLemmaAny units ["где", "откуда"]
    && any (\u -> wmuLemma u `elem` concealmentVerbs) units
    && any (\u -> SemAbstractConcept `elem` wmuSemanticClasses u || SemContemplative `elem` wmuSemanticClasses u) units

asksThoughtAboutTopicQuestion :: NormalizedInput -> [WordMeaningUnit] -> Bool
asksThoughtAboutTopicQuestion normalized units =
  niIsQuestion normalized
    && hasPhrase (niTokens normalized) ["что", "ты", "думаешь", "о"]
    && any (\u -> SemAbstractConcept `elem` wmuSemanticClasses u || SemMentalObject `elem` wmuSemanticClasses u || SemContemplative `elem` wmuSemanticClasses u) units

isReflectiveAssertion :: NormalizedInput -> [WordMeaningUnit] -> Bool
isReflectiveAssertion normalized units =
  not (niIsQuestion normalized)
    && hasSelfReference units
    && hasLemmaAny units ["думать", "считать", "полагать"]
    && any (\u -> SemAbstractConcept `elem` wmuSemanticClasses u || SemContemplative `elem` wmuSemanticClasses u) units

asksSystemLogicQuestion :: NormalizedInput -> [WordMeaningUnit] -> Bool
asksSystemLogicQuestion normalized units =
  let tokens = niTokens normalized
      hasLogicLexeme =
        hasLemmaAny units ["логика"]
          || hasAny tokens ["логика", "логике", "логики", "логичен", "логична", "логично"]
      hasStructureProbe =
        hasAny tokens ["как"] && hasLemmaAny units ["устроен", "устроить", "работать"]
      hasSecondPerson =
        hasSecondPersonReference units
          || hasAny tokens ["ты", "тебя", "тебе", "тобой", "твой", "твоя", "твое", "твои", "вы", "вас", "вам", "вами", "ваш", "ваша", "ваше"]
  in niIsQuestion normalized
      && not (hasAny tokens ["почему"])
      && hasSecondPerson
      && (hasLogicLexeme || hasStructureProbe)

isSystemIdentityQuestion :: NormalizedInput -> [WordMeaningUnit] -> Bool
isSystemIdentityQuestion normalized units =
  let tokens = niTokens normalized
      tokenCount = length tokens
      hasShortIdentityProbe =
        tokenCount <= 4
          && ( hasPhrase tokens ["ты", "кто"]
            || hasPhrase tokens ["кто", "ты"]
            || hasPhrase tokens ["ты", "что"]
            || hasPhrase tokens ["что", "ты"]
            || hasPhrase tokens ["ты", "такой"]
            || hasPhrase tokens ["ты", "какой"]
            )
  in niIsQuestion normalized
      && hasSecondPersonOrToken units tokens
      && ( hasAny tokens ["машина", "бот", "промт", "prompt", "llm", "модель", "механизм"]
         || hasShortIdentityProbe
         )

isDirectSelfProbeQuestion :: NormalizedInput -> [WordMeaningUnit] -> Bool
isDirectSelfProbeQuestion normalized units =
  let tokens = niTokens normalized
  in
  niIsQuestion normalized
    && startsWithSecondPerson tokens
    && hasSecondPersonOrToken units tokens
    && not (isDefinitionalQuestion normalized units)
    && not (hasPhrase tokens ["что", "такое"])
    && not (isNameQuestion normalized units)
    && not (asksSelfRoleQuestion normalized units)
    && not (asksCapabilityQuestion normalized units)
    && not (asksAssistanceQuestion normalized units)
    && not (asksSystemLogicQuestion normalized units)
    && not (hasLemmaAny units ["работать"])
    && not (hasAnyPrefix tokens ["работ"])
    && not (hasAny tokens ["будешь", "будете"])
    && not (hasAny tokens ["как"])
    && not (isSelfThoughtQuestion normalized units)
    && not (isGenericHowYouProcessQuestion normalized units)
    && any
      (\unit ->
        topicalUnit unit
          && ( wmuPartOfSpeech unit `elem` [PosNoun, PosAdjective, PosVerb]
                || (wmuPartOfSpeech unit == PosUnknown && length tokens <= 4)
             )
      )
      units

startsWithSecondPerson :: [Text] -> Bool
startsWithSecondPerson [] = False
startsWithSecondPerson (tok:_) =
  tok `elem` ["ты", "вы"]

isNameQuestion :: NormalizedInput -> [WordMeaningUnit] -> Bool
isNameQuestion normalized _units =
  niIsQuestion normalized
    && (hasPhrase tokens ["как", "тебя", "зовут"] || hasPhrase tokens ["как", "вас", "зовут"])
  where
    tokens = niTokens normalized

isSelfDescriptionRequest :: NormalizedInput -> [WordMeaningUnit] -> Bool
isSelfDescriptionRequest normalized _units =
  hasPhrase tokens ["расскажи", "о", "себе"]
    || hasPhrase tokens ["что", "ты", "можешь", "рассказать", "о", "себе"]
    || hasPhrase tokens ["что", "вы", "можете", "рассказать", "о", "себе"]
  where
    tokens = niTokens normalized

isSelfFutureQuestion :: NormalizedInput -> [WordMeaningUnit] -> Bool
isSelfFutureQuestion normalized units =
  let tokens = niTokens normalized
  in niIsQuestion normalized
      && hasSecondPersonOrToken units tokens
      && ( hasPhrase tokens ["какое", "у", "тебя", "будущее"]
        || hasPhrase tokens ["какое", "у", "вас", "будущее"]
        || hasPhrase tokens ["у", "тебя", "есть", "будущее"]
        || hasPhrase tokens ["у", "вас", "есть", "будущее"]
        || hasPhrase tokens ["как", "думаешь", "какое", "у", "тебя", "будущее"]
        || hasPhrase tokens ["как", "считаешь", "какое", "у", "тебя", "будущее"]
        )

isSelfIntentQuestion :: NormalizedInput -> [WordMeaningUnit] -> Bool
isSelfIntentQuestion normalized units =
  let tokens = niTokens normalized
      bareIntentPattern =
        hasPhrase tokens ["хочешь", "что-то", "сказать"]
          || hasPhrase tokens ["хочешь", "что", "то", "сказать"]
          || hasPhrase tokens ["хочешь", "сказать"]
  in niIsQuestion normalized
      && (hasSecondPersonOrToken units tokens || bareIntentPattern)
      && ( hasPhrase tokens ["что", "ты", "хочешь"]
        || hasPhrase tokens ["что", "вы", "хотите"]
        || hasPhrase tokens ["ты", "хочешь"]
        || hasPhrase tokens ["вы", "хотите"]
        || hasPhrase tokens ["кем", "ты", "хочешь", "стать"]
        || hasPhrase tokens ["кем", "вы", "хотите", "стать"]
        || hasPhrase tokens ["хочешь", "ли", "ты"]
        || hasPhrase tokens ["хотите", "ли", "вы"]
        || bareIntentPattern
        )

isSelfMetaQuestion :: NormalizedInput -> [WordMeaningUnit] -> Bool
isSelfMetaQuestion normalized units =
  let tokens = niTokens normalized
      low = niNormalizedText normalized
  in niIsQuestion normalized
      && hasSecondPersonOrToken units tokens
      && ( hasPhrase tokens ["у", "тебя", "есть", "послание", "миру"]
        || hasPhrase tokens ["у", "вас", "есть", "послание", "миру"]
        || hasPhrase tokens ["у", "тебя", "есть", "намерения"]
        || hasPhrase tokens ["есть", "ли", "у", "тебя", "намерения"]
        || hasPhrase tokens ["какое", "у", "тебя", "будущее"]
        || hasPhrase tokens ["у", "тебя", "есть", "будущее"]
        || hasPhrase tokens ["ты", "способен", "найти", "ответ", "на", "свой", "же", "вопрос"]
        || hasPhrase tokens ["на", "тебя", "действуют", "промты"]
        || hasPhrase tokens ["на", "вас", "действуют", "промты"]
        || hasPhrase tokens ["что", "для", "тебя", "важно"]
        || hasPhrase tokens ["что", "для", "вас", "важно"]
        || hasPhrase tokens ["ты", "субъектен"]
        || hasPhrase tokens ["ты", "субьектен"]
        || hasPhrase tokens ["ты", "умный"]
        || hasPhrase tokens ["ты", "свободен"]
        || hasPhrase tokens ["ты", "сложная", "система"]
        || T.isInfixOf "почему ты знаешь то что знаешь" low
        )

isSelfThoughtQuestion :: NormalizedInput -> [WordMeaningUnit] -> Bool
isSelfThoughtQuestion normalized _units =
  niIsQuestion normalized
    && (hasPhrase tokens ["что", "ты", "думаешь"] || hasPhrase tokens ["что", "вы", "думаете"])
  where
    tokens = niTokens normalized

isGenericHowYouProcessQuestion :: NormalizedInput -> [WordMeaningUnit] -> Bool
isGenericHowYouProcessQuestion normalized units =
  niIsQuestion normalized
    && hasAny tokens ["как"]
    && hasAny tokens ["ты", "вы"]
    && hasAny
      (map wmuLemma units)
      [ "определять", "держать", "выбирать", "понимать", "проверять", "работать"
      , "действовать", "обрабатывать", "интерпретировать", "адаптироваться"
      , "оценивать", "различать", "решать", "сохранять"
      ]
  where
    tokens = niTokens normalized

asksSelfRoleQuestion :: NormalizedInput -> [WordMeaningUnit] -> Bool
asksSelfRoleQuestion normalized _units =
  niIsQuestion normalized
    && hasAny tokens ["ты", "вы", "твой", "твоя", "твое", "ваш", "ваша", "ваше"]
    && hasAny tokens ["роль", "задача"]
  where
    tokens = niTokens normalized

isRepairDirective :: NormalizedInput -> [WordMeaningUnit] -> Bool
isRepairDirective normalized _units =
  hasAny tokens
    [ "непонятно", "неясно", "запутался", "запуталась"
    , "разберись", "уточни", "исправь", "переформулируй"
    , "повтори", "проще", "короче", "иначе"
    , "шаблон", "шаблона", "конкретику", "абстрактно"
    , "расплывчато", "общо", "вода", "бесполезно"
    ]
    || hasPhrase tokens ["не", "по", "вопросу"]
    || hasPhrase tokens ["вернись", "к", "вопросу"]
    || hasPhrase tokens ["давай", "сначала"]
    || hasPhrase tokens ["дай", "пример"]
    || hasPhrase tokens ["дай", "более", "практичный", "ответ"]
    || hasPhrase tokens ["разложи", "по", "пунктам"]
    || hasPhrase tokens ["объясни", "как", "для", "новичка"]
    || hasPhrase tokens ["сначала", "ответ", "потом", "пояснение"]
    || hasPhrase tokens ["сделай", "ответ", "конкретнее"]
    || hasPhrase tokens ["сделай", "ответ", "структурным"]
    || hasPhrase tokens ["пересобери", "ответ", "без", "воды"]
    || hasPhrase tokens ["дай", "четкий", "тезис"]
    || hasPhrase tokens ["дай", "чёткий", "тезис"]
    || hasPhrase tokens ["сформулируй", "один", "главный", "вывод"]
    || hasPhrase tokens ["по", "человечески"]
    || hasPhrase tokens ["по", "человечески", "объясни"]
    || hasPhrase tokens ["слишком", "общо"]
    || hasPhrase tokens ["не", "уловил", "суть"]
    || hasPhrase tokens ["не", "вижу", "связи"]
    || hasPhrase tokens ["ты", "меня", "не", "услышал"]
    || hasPhrase tokens ["это", "не", "помогает"]
    || hasPhrase tokens ["проверь", "логику", "ответа"]
    || hasPhrase tokens ["без", "лишнего"]
  where
    tokens = niTokens normalized

inferClauseType :: NormalizedInput -> InputClauseType
inferClauseType normalized
  | niIsQuestion normalized = ClauseInterrogativeInput
  | startsImperative (niTokens normalized) = ClauseImperativeInput
  | length (niTokens normalized) <= 2 = ClauseFragmentInput
  | otherwise = ClauseDeclarativeInput

inferSpeechAct :: InputClauseType -> InputRouteHint -> InputSpeechAct
inferSpeechAct clauseType routeHint =
  case irhTag routeHint of
    "dialogue_invitation" -> ActInvite
    "misunderstanding" -> ActReport
    "generative_prompt" -> ActRequest
    _ ->
      case clauseType of
        ClauseInterrogativeInput -> ActAsk
        ClauseImperativeInput -> ActRequest
        ClauseFragmentInput -> ActReport
        ClauseDeclarativeInput -> ActAssert

inferPolarity :: [WordMeaningUnit] -> InputPolarity
inferPolarity units
  | any hasNegation units = PolarityNegative
  | otherwise = PolarityPositive
  where
    hasNegation unit = DiscNegation `elem` wmuDiscourseFunctions unit

inferTopic :: NormalizedInput -> [WordMeaningUnit] -> InputRouteHint -> Text
inferTopic normalized units routeHint =
  case irhTag routeHint of
    "greeting_smalltalk" -> "контакт"
    "dialogue_invitation" ->
      fromMaybe "диалог" (topicAfterMarkers (niTokens normalized) ["о", "об", "обо", "про"])
    "concept_knowledge" -> fromMaybe defaultTopic (topicAfterMarkers (niTokens normalized) ["о", "об", "обо", "про", "такое", "значит"])
    "affective_help" ->
      fromMaybe defaultTopic (affectiveStateTopic units)
    "purpose_function" ->
      fromMaybe purposeFallback (purposeObjectLemma units)
    "world_cause" ->
      fromMaybe defaultTopic (worldCauseTopic units)
    "self_knowledge"
      | asksCapabilityQuestion normalized units || asksAssistanceQuestion normalized units ->
          fromMaybe defaultTopic (abilityComplement units)
    "contemplative_topic" -> fromMaybe defaultTopic (topicBySemantics units)
    "generative_prompt" ->
      fromMaybe defaultTopic (requestedQualityTopic (niTokens normalized) <|> qualityDescriptorLemma units <|> preferredTopicLemma units)
    _ -> defaultTopic
  where
    defaultTopic = fromMaybe "тема" (preferredTopicLemma units)
    purposeFallback
      | hasAny (niTokens normalized) ["ты", "тебя", "тебе", "тобой", "вы", "вас", "вам", "вами"] = "система"
      | otherwise = "объект"

inferFocus :: [WordMeaningUnit] -> Text
inferFocus units =
  fromMaybe "тема" $
    listToMaybe (reverse (preferredTopicLemmas units))

inferParticipants :: NormalizedInput -> (Maybe Text, Maybe Text)
inferParticipants normalized =
  let tokens = niTokens normalized
      hasSelf = hasAny tokens ["я", "мне", "меня", "мы", "мой", "моя", "моё"]
      hasUser = hasAny tokens ["ты", "тебе", "тебя", "вы", "вас", "твой", "твоя", "твое"]
      agent
        | hasSelf = Just "user"
        | hasUser = Just "system"
        | otherwise = Nothing
      target
        | hasUser = Just "system"
        | hasSelf = Just "user"
        | otherwise = Nothing
  in (agent, target)

inferSemanticCandidates :: NormalizedInput -> [WordMeaningUnit] -> InputRouteHint -> [Text]
inferSemanticCandidates normalized units routeHint =
  take 8 . filter (not . T.null) $
    [ "route_tag=" <> irhTag routeHint
    , "route_reason=" <> irhReason routeHint
    , "route_rule_score=" <> showScore (irhRuleScore routeHint)
    , "route_semantic_score=" <> showScore (irhSemanticScore routeHint)
    , "route_syntactic_score=" <> showScore (irhSyntacticScore routeHint)
    , "route_embedding_score=" <> showScore (irhEmbeddingScore routeHint)
    , "route_final_score=" <> showScore (irhConfidence routeHint)
    , "clause=" <> T.pack (show (inferClauseType normalized))
    ]
    <> map ("route_evidence=" <>) (take 2 (irhEvidence routeHint))
    <> map (\u -> "token=" <> wmuSurfaceForm u <> "|pos=" <> T.pack (show (wmuPartOfSpeech u))) (take 5 units)

inferAmbiguityLevel :: [WordMeaningUnit] -> Text
inferAmbiguityLevel units
  | any (\u -> wmuPartOfSpeech u == PosUnknown) units = "high"
  | any (\u -> length (wmuAmbiguityCandidates u) > 1) units = "medium"
  | otherwise = "low"

inferFrameConfidence :: [WordMeaningUnit] -> InputRouteHint -> Double
inferFrameConfidence units routeHint =
  let tokenConfidence =
        if null units
          then 0.45
          else sum (map wmuConfidence units) / fromIntegral (length units)
  in clamp01 ((tokenConfidence * 0.55) + (irhConfidence routeHint * 0.45))

mkHint :: InputRouteType -> Text -> Text -> Double -> InputRouteHint
mkHint routeType tag reason confidence =
  InputRouteHint
    { irhType = routeType
    , irhTag = tag
    , irhReason = reason
    , irhRuleScore = confidence
    , irhSemanticScore = 0.0
    , irhSyntacticScore = 0.0
    , irhEmbeddingScore = 0.0
    , irhEvidence = ["rule_only_seed"]
    , irhConfidence = confidence
    }

hasAny :: [Text] -> [Text] -> Bool
hasAny haystack needles = any (`elem` haystack) needles

hasAnyPrefix :: [Text] -> [Text] -> Bool
hasAnyPrefix haystack prefixes =
  any (\token -> any (`T.isPrefixOf` token) prefixes) haystack

hasPhrase :: [Text] -> [Text] -> Bool
hasPhrase haystack phrase = go haystack
  where
    go [] = null phrase
    go xs
      | phrase `isPrefixOf` xs = True
      | otherwise = go (drop 1 xs)

startsImperative :: [Text] -> Bool
startsImperative [] = False
startsImperative (firstToken:_) =
  firstToken `elem`
    [ "скажи", "дай", "объясни", "поясни", "уточни", "поговорим", "обсудим", "расскажи", "сформулируй"
    , "молчи", "замолчи", "заткнись", "перестань", "хватит"
    ]

cont
  :: WordMeaningUnit
  -> Bool
cont unit = not (isFunctionWord (wmuSurfaceForm unit))

contentLemmas :: [WordMeaningUnit] -> [Text]
contentLemmas = map wmuLemma . filter cont

preferredTopicLemma :: [WordMeaningUnit] -> Maybe Text
preferredTopicLemma = listToMaybe . preferredTopicLemmas

qualityDescriptorLemma :: [WordMeaningUnit] -> Maybe Text
qualityDescriptorLemma units =
  listToMaybe
    [ wmuLemma unit
    | unit <- units
    , topicalUnit unit
    , wmuPartOfSpeech unit `elem` [PosAdjective, PosAdverb]
    ]

requestedQualityTopic :: [Text] -> Maybe Text
requestedQualityTopic tokens =
  listToMaybe
    [ normalizeQualityAdjective token
    | token <- reverse tokens
    , isQualityToken token
    ]

isQualityToken :: Text -> Bool
isQualityToken token =
  let low = T.toLower (T.strip token)
      blocked =
        [ "скажи", "дай", "что", "что-то", "чтонибудь", "что-нибудь"
        , "один", "одну", "одна", "еще", "ещё", "просто"
        , "мысль", "идею", "идея", "фразу", "тезис"
        ]
      qualitySuffixes = ["ое", "ее", "ая", "яя", "ые", "ие", "ый", "ий"]
  in low `notElem` blocked && any (`T.isSuffixOf` low) qualitySuffixes

normalizeQualityAdjective :: Text -> Text
normalizeQualityAdjective raw =
  let low = T.toLower (T.strip raw)
  in if "ое" `T.isSuffixOf` low
      then T.dropEnd 2 low <> "ый"
      else if "ее" `T.isSuffixOf` low
        then T.dropEnd 2 low <> "ий"
        else if "ая" `T.isSuffixOf` low
          then T.dropEnd 2 low <> "ый"
          else if "яя" `T.isSuffixOf` low
            then T.dropEnd 2 low <> "ий"
            else if "ые" `T.isSuffixOf` low
              then T.dropEnd 2 low <> "ый"
              else if "ие" `T.isSuffixOf` low
                then T.dropEnd 2 low <> "ий"
                else low

preferredTopicLemmas :: [WordMeaningUnit] -> [Text]
preferredTopicLemmas units =
  prefer PosNoun
    <> complementVerbs
    <> fallback
  where
    filtered = filter topicalUnit units
    prefer pos = [wmuLemma unit | unit <- filtered, wmuPartOfSpeech unit == pos]
    complementVerbs =
      [ wmuLemma unit
      | unit <- filtered
      , wmuPartOfSpeech unit == PosVerb
      , not (wmuLemma unit `elem` topicalMetaVerbLemmas)
      ]
    fallback = [wmuLemma unit | unit <- filtered]

topicalUnit :: WordMeaningUnit -> Bool
topicalUnit unit =
  let lemma = wmuLemma unit
  in not (isFunctionWord (wmuSurfaceForm unit))
      && lemma `notElem` topicalStopLemmas
      && lemma `notElem` dialogueMetaLemmas
      && not (isGenerativeRequestLemma lemma)
      && not (T.null (T.strip lemma))

topicalStopLemmas :: [Text]
topicalStopLemmas =
  [ "я", "ты", "мы", "вы", "кто", "что", "такой", "это", "этот", "эта"
  , "мне", "тебе", "меня", "тебя", "себя"
  , "очень", "слишком", "просто", "вообще", "только"
  , "свой", "своя", "своё", "свое", "свои", "свою"
  , "мой", "моя", "моё", "мое", "мои", "мою"
  , "твой", "твоя", "твоё", "твое", "твои", "твою"
  ]

topicalMetaVerbLemmas :: [Text]
topicalMetaVerbLemmas =
  [ "сказать", "скажи", "дать", "дай", "уметь", "мочь", "быть", "являться", "помочь"
  , "поговорить", "обсудить", "думать", "сохранять", "скрываться", "размышлять"
  ]

dialogueMetaLemmas :: [Text]
dialogueMetaLemmas =
  [ "поговорим", "поговорить", "говорить", "разговаривать", "обсудить", "беседовать", "диалог"
  ]

hasSelfReference :: [WordMeaningUnit] -> Bool
hasSelfReference =
  any (\unit -> FeatPerson1 `elem` wmuMorphFeatures unit || SemSelfReference `elem` wmuSemanticClasses unit)

hasSecondPersonReference :: [WordMeaningUnit] -> Bool
hasSecondPersonReference =
  any (\unit -> FeatPerson2 `elem` wmuMorphFeatures unit || SemUserReference `elem` wmuSemanticClasses unit)

hasSecondPersonToken :: [Text] -> Bool
hasSecondPersonToken tokens =
  hasAny tokens ["ты", "тебя", "тебе", "тобой", "твой", "твоя", "твое", "твоё", "твои", "вы", "вас", "вам", "вами", "ваш", "ваша", "ваше", "ваши"]

hasSecondPersonOrToken :: [WordMeaningUnit] -> [Text] -> Bool
hasSecondPersonOrToken units tokens =
  hasSecondPersonReference units || hasSecondPersonToken tokens

hasLemmaAny :: [WordMeaningUnit] -> [Text] -> Bool
hasLemmaAny units lemmas = any (\unit -> wmuLemma unit `elem` lemmas) units

asksCapabilityQuestion :: NormalizedInput -> [WordMeaningUnit] -> Bool
asksCapabilityQuestion normalized units =
  let tokens = niTokens normalized
  in
  niIsQuestion normalized
    && hasSecondPersonOrToken units tokens
    && hasLemmaAny units ["уметь", "мочь"]
    && isJustText (abilityComplement units)
    && not (asksAssistanceQuestion normalized units)

asksAssistanceQuestion :: NormalizedInput -> [WordMeaningUnit] -> Bool
asksAssistanceQuestion normalized units =
  let tokens = niTokens normalized
  in
  hasSecondPersonOrToken units tokens
    && hasLemmaAny units ["мочь", "помочь", "помощь"]
    && hasLemmaAny units ["помочь", "помощь"]
    && (niIsQuestion normalized || any ((== PosVerb) . wmuPartOfSpeech) units)

asksUserIdentityQuestion :: NormalizedInput -> [WordMeaningUnit] -> Bool
asksUserIdentityQuestion normalized units =
  let tokens = niTokens normalized
  in niIsQuestion normalized
      && hasSelfReference units
      && ( hasPhrase tokens ["кто", "я"]
        || hasPhrase tokens ["кто", "я", "такой"]
        || hasPhrase tokens ["что", "я", "такое"]
        || hasPhrase tokens ["какой", "я"]
        )

isAffectiveHelpQuestion :: NormalizedInput -> [WordMeaningUnit] -> Bool
isAffectiveHelpQuestion normalized units =
  let tokens = niTokens normalized
      hasAffectiveSignal =
        any (\u -> wmuLemma u `elem` affectiveStateLemmas) units
          || hasAny tokens
              [ "тревожно", "тревога", "грустно", "тоскливо", "плохо", "одиноко", "страшно"
              , "паника", "апатия", "выгорел", "выгорела", "переживать", "переживаю"
              , "волноваться", "волнуюсь", "устал", "устала", "сил", "тяжело"
              ]
      classicHelpPattern =
        hasPhrase tokens ["что", "делать"]
          && (hasAffectiveSignal || hasAny tokens ["если", "когда"])
      regulationPattern =
        hasPhrase tokens ["как", "не", "переживать"]
          || hasPhrase tokens ["как", "не", "волноваться"]
          || hasPhrase tokens ["как", "успокоиться"]
          || hasPhrase tokens ["как", "сохранить", "спокойствие"]
          || hasPhrase tokens ["как", "держать", "спокойствие"]
          || hasPhrase tokens ["как", "не", "паниковать"]
          || hasPhrase tokens ["как", "перестать", "тревожиться"]
          || hasPhrase tokens ["как", "не", "тревожиться"]
          || hasPhrase tokens ["как", "выйти", "из", "апатии"]
          || hasPhrase tokens ["как", "собраться", "с", "силами"]
          || hasPhrase tokens ["как", "вернуть", "силы"]
          || hasPhrase tokens ["как", "вернуть", "мотивацию"]
          || hasPhrase tokens ["как", "найти", "силы"]
          || hasPhrase tokens ["как", "перестать", "переживать"]
          || hasPhrase tokens ["как", "перестать", "волноваться"]
          || hasPhrase tokens ["как", "справиться", "с", "тревогой"]
          || hasPhrase tokens ["как", "справиться", "со", "страхом"]
          || hasPhrase tokens ["как", "справиться", "с", "апатией"]
      lowEnergyPattern =
        hasPhrase tokens ["не", "хочется", "ничего", "делать"]
          || hasPhrase tokens ["ничего", "не", "хочется", "делать"]
          || hasPhrase tokens ["нет", "сил"]
          || hasPhrase tokens ["нет", "энергии"]
          || hasPhrase tokens ["руки", "опускаются"]
          || hasPhrase tokens ["все", "бесит"]
          || hasPhrase tokens ["всё", "бесит"]
          || hasPhrase tokens ["ничего", "не", "радует"]
          || hasPhrase tokens ["ничего", "не", "хочу"]
          || hasPhrase tokens ["не", "могу", "собраться"]
          || hasPhrase tokens ["не", "хочу", "ничего"]
          || hasPhrase tokens ["не", "знаю", "что", "делать"]
          || hasPhrase tokens ["устал", "и", "ничего", "не", "хочется"]
          || hasPhrase tokens ["устала", "и", "ничего", "не", "хочется"]
      shortSupportProbe =
        (hasAny tokens ["как", "что"] && hasAffectiveSignal)
          || hasPhrase tokens ["что", "мне", "делать"]
          || hasPhrase tokens ["помоги", "собраться"]
          || hasPhrase tokens ["дай", "мне", "шаг"]
          || hasPhrase tokens ["с", "чего", "начать", "когда", "тревожно"]
      relaxedRegulationProbe =
        hasAny tokens ["как"]
          && ( hasAnyPrefix tokens ["пережив", "волнов", "тревож", "паник", "успок", "апат"]
            || hasAffectiveSignal
             )
  in niIsQuestion normalized
      && (classicHelpPattern || regulationPattern || lowEnergyPattern || shortSupportProbe || relaxedRegulationProbe)

isEverydayEventAssertion :: NormalizedInput -> [WordMeaningUnit] -> Bool
isEverydayEventAssertion normalized units =
  not (niIsQuestion normalized)
    && hasSelfReference units
    && any ((== PosVerb) . wmuPartOfSpeech) units
    && any isObjectLikeUnit units

isGenerativeQualityPrompt :: NormalizedInput -> [WordMeaningUnit] -> Bool
isGenerativeQualityPrompt normalized units =
  let tokens = niTokens normalized
      hasPromptVerb =
        hasAny tokens ["скажи", "дай", "сформулируй"]
          || hasLemmaAny units ["скажи", "дай", "сформулируй", "сказать", "дать", "сформулировать"]
      hasQualityToken =
        any (`elem` tokens) ["логичное", "логично", "интересное", "новое", "другое", "короткое", "четкое", "чёткое", "ясное"]
      hasQualityByPos = any ((== PosAdjective) . wmuPartOfSpeech) units
  in hasPromptVerb
      && (hasAny tokens ["что-то", "что-нибудь", "чтонибудь"] || hasPhrase tokens ["что", "то"])
      && (hasQualityToken || hasQualityByPos)

abilityComplement :: [WordMeaningUnit] -> Maybe Text
abilityComplement units =
  listToMaybe
    [ wmuLemma unit
    | unit <- units
    , let lemma = wmuLemma unit
    , wmuPartOfSpeech unit `elem` [PosVerb, PosNoun, PosAdjective]
    , not (isCapabilityLemma lemma)
    , not (isAssistanceLemma lemma)
    , not (isIdentityLemma lemma)
    , not (isGenerativeRequestLemma lemma)
    , topicalUnit unit
    ]

isJustText :: Maybe Text -> Bool
isJustText (Just txt) = not (T.null (T.strip txt))
isJustText Nothing = False

topicAfterMarkers :: [Text] -> [Text] -> Maybe Text
topicAfterMarkers tokens markers =
  let afterMarker = drop 1 (dropWhile (`notElem` markers) tokens)
      candidate = T.unwords (takeWhile (`notElem` stopTokens) afterMarker)
  in if T.null candidate then Nothing else Just candidate

stopTokens :: [Text]
stopTokens = ["что", "как", "почему", "ли", "знаешь", "думаешь", "скажи", "дай"]

contemplativeInput :: [WordMeaningUnit] -> Bool
contemplativeInput units =
  let content = contentLemmas units
      allContemplative = all (`elem` contemplativeSeed) content
  in not (null content) && length content <= 2 && allContemplative

contemplativeSeed :: [Text]
contemplativeSeed =
  [ "я", "дом", "тишина", "смысл", "любовь", "смерть", "время", "страх", "память", "свобода" ]

formationVerbs :: [Text]
formationVerbs =
  [ "формироваться", "возникать", "создаваться", "браться", "рождаться", "появляться"
  ]

concealmentVerbs :: [Text]
concealmentVerbs =
  [ "скрываться", "прятаться", "утаиваться"
  ]

affectiveStateLemmas :: [Text]
affectiveStateLemmas =
  [ "грустно", "тоскливо", "плохо", "тревожно", "одиноко", "страшно"
  ]

isObjectLikeUnit :: WordMeaningUnit -> Bool
isObjectLikeUnit unit =
  wmuPartOfSpeech unit == PosNoun
    && any (`elem` wmuSemanticClasses unit) [SemPhysicalObject, SemWorldObject, SemAbstractConcept, SemMentalObject]

objectHeadLemma :: [WordMeaningUnit] -> Maybe Text
objectHeadLemma units =
  listToMaybe
    [ wmuLemma unit
    | unit <- units
    , isObjectLikeUnit unit
    , topicalUnit unit
    ]

purposeObjectLemma :: [WordMeaningUnit] -> Maybe Text
purposeObjectLemma units =
  listToMaybe
    [ wmuLemma unit
    | unit <- reverse units
    , isObjectLikeUnit unit
    , topicalUnit unit
    , wmuLemma unit `notElem` purposeMetaLemmas
    ]
  <|> objectHeadLemma units

worldCauseTopic :: [WordMeaningUnit] -> Maybe Text
worldCauseTopic units =
  listToMaybe
    [ wmuLemma unit
    | unit <- units
    , topicalUnit unit
    , wmuPartOfSpeech unit == PosNoun
    , isWorldNoun (wmuLemma unit)
        || any (`elem` wmuSemanticClasses unit) [SemWorldObject, SemPhysicalObject]
    ]
  <|> objectHeadLemma units

affectiveStateTopic :: [WordMeaningUnit] -> Maybe Text
affectiveStateTopic units =
  listToMaybe
    [ wmuLemma unit
    | unit <- units
    , wmuLemma unit `elem` affectiveStateLemmas
    ]

purposeMetaLemmas :: [Text]
purposeMetaLemmas =
  [ "функция", "назначение", "цель", "смысл", "роль", "задача" ]

topicBySemantics :: [WordMeaningUnit] -> Maybe Text
topicBySemantics units =
  listToMaybe
    [ wmuLemma unit
    | unit <- units
    , topicalUnit unit
    , wmuPartOfSpeech unit == PosNoun
    , any (`elem` wmuSemanticClasses unit) [SemAbstractConcept, SemMentalObject, SemContemplative, SemWorldObject, SemPhysicalObject]
    ]

clamp01 :: Double -> Double
clamp01 value
  | value < 0.0 = 0.0
  | value > 1.0 = 1.0
  | otherwise = value
