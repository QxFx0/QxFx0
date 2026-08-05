{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : QxFx0.Semantic.ResponsePlan
Description : Deterministic construction and local realization of grounded plans.

The plan builder is intentionally local-first.  It may select only predicates
already admitted by 'ContentSelector'; it never invents a factual predicate.
-}
module QxFx0.Semantic.ResponsePlan
  ( buildGenerativeResponsePlan
  , buildGenerativeResponsePlanWithActiveQuestion
  , buildResponseSemanticPlan
  , buildResponseSemanticPlanWithActiveQuestion
  , renderResponseSemanticPlan
  , responsePlanQualityIssues
  , responsePlanTopic
  , isGenerativeRequestText
  ) where

import Data.List (find, sortOn)
import Data.Maybe (listToMaybe, mapMaybe, maybeToList)
import qualified Data.Map.Strict as M
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Semantic.Content
  ( normalizeTopic
  , CanonicalPredicateRelation(..)
  , SemanticPredicate(..)
  )
import QxFx0.Semantic.ContentSelector
  ( ContentSelector(..)
  , SelectedPredicate(..)
  , selectPredicates
  )
import QxFx0.Lexicon.Generated.SemanticSlots (lookupArguedLeafConstructor)
import QxFx0.Semantic.Network (ActivationArtifact, activationArtifactNetwork)
import QxFx0.Semantic.Frame.Types (SemanticFrame(..))
import QxFx0.Semantic.Intent.Classifier (SemanticIntent(..))
import QxFx0.Self.Field (Field)
import QxFx0.Types.Semantic.ResponsePlan

-- | Legacy entry point for a generative request.
buildGenerativeResponsePlan
  :: ContentSelector
  -> Field
  -> Text
  -> Maybe ActivationArtifact
  -> ResponseSemanticPlan
buildGenerativeResponsePlan selector field rawInput mActivation =
  buildGenerativeResponsePlanWithActiveQuestion selector field rawInput mActivation Nothing

-- | Legacy generative entry point with dialogue context.
buildGenerativeResponsePlanWithActiveQuestion
  :: ContentSelector
  -> Field
  -> Text
  -> Maybe ActivationArtifact
  -> Maybe Text
  -> ResponseSemanticPlan
buildGenerativeResponsePlanWithActiveQuestion selector field rawInput mActivation mActiveQuestion =
  case responsePlanTopic selector rawInput of
    Nothing -> fallbackPlan GoalClarify NoTopicProvided Nothing
    Just topic -> buildGroundedPlan GoalGenerateThesis [topic] mActiveQuestion selector field mActivation

-- | Plan all supported semantic dialogue acts through the same bounded,
-- grounded composer. Unsupported intents deliberately retain their existing
-- semantic renderer rather than receiving an invented claim.
buildResponseSemanticPlan
  :: ContentSelector
  -> Field
  -> Text
  -> Maybe ActivationArtifact
  -> SemanticFrame
  -> SemanticIntent
  -> Maybe ResponseSemanticPlan
buildResponseSemanticPlan selector field rawInput mActivation semanticFrame semanticIntent =
  buildResponseSemanticPlanWithActiveQuestion selector field rawInput mActivation Nothing semanticFrame semanticIntent

buildResponseSemanticPlanWithActiveQuestion
  :: ContentSelector
  -> Field
  -> Text
  -> Maybe ActivationArtifact
  -> Maybe Text
  -> SemanticFrame
  -> SemanticIntent
  -> Maybe ResponseSemanticPlan
buildResponseSemanticPlanWithActiveQuestion selector field rawInput mActivation mActiveQuestion semanticFrame semanticIntent
  | isGenerativeRequestText rawInput = Just (buildGenerativeResponsePlanWithActiveQuestion selector field rawInput mActivation mActiveQuestion)
  | otherwise = case planRequest semanticFrame semanticIntent <|> clarifyRequest of
      Nothing -> Nothing
      Just (goal, topics) -> Just (buildGroundedPlan goal topics mActiveQuestion selector field mActivation)
  where
    clarifyRequest
      | isClarifyRequestText rawInput = Just (GoalClarify, maybeToList (responsePlanTopic selector rawInput))
      | otherwise = Nothing

-- | At most eight selector-derived candidates enter composition. The first
-- admissible candidate is the thesis; its curated counter/synthesis fields may
-- add a contrast or conditional proposition, never a free-form fact.
buildGroundedPlan
  :: ResponseGoal
  -> [Text]
  -> Maybe Text
  -> ContentSelector
  -> Field
  -> Maybe ActivationArtifact
  -> ResponseSemanticPlan
buildGroundedPlan goal rawTopics mActiveQuestion selector field mActivation =
  case topics of
    [] -> fallbackPlan GoalClarify NoTopicProvided Nothing
    topic:_
      | any (`M.notMember` csTopicPredicates selector) topics -> fallbackPlan goal TopicNotCovered (Just topic)
      | otherwise ->
          case candidates of
            [] -> fallbackPlan goal NoAdmissiblePredicate (Just topic)
            primary:alternatives ->
               let
                 confidence = clamp01 (candidateConfidence primary)
                 primaryProposition = predicateProposition (candidatePredicate primary)
                 secondary = comparisonCounter goal primary alternatives
                 counterpoint = buildCounterpoint confidence (candidatePredicate primary) (map candidatePredicate alternatives)
                 counterProposition = derivedProposition <$> (pcText <$> counterpoint)
                 synthesisProposition = spSynthesis (candidatePredicate primary) >>= nonEmptyProposition
                 obligation = deriveObligation mActiveQuestion goal primaryProposition counterProposition
                 propositions = take 8 . concat $
                   [ [primaryProposition]
                   , maybe [] (pure . PropositionContrast primaryProposition) (secondary <|> counterProposition)
                   , maybe [] (pure . PropositionConditional primaryProposition) synthesisProposition
                   , maybe [] (pure . obligationProposition primaryProposition) obligation
                   ]
                 claim = PlannedClaim
                   { pcId = "claim-1"
                   , pcMode = claimModeFor goal
                   , pcText = renderSemanticProposition (head propositions)
                   , pcPredicateRefs = take 2 (map (cleanSentence . spRu . candidatePredicate) (primary:alternatives))
                   , pcEvidence = EvidenceSelectedPredicate
                   , pcConfidence = confidence
                   }
                 derivation = take 8 $
                   [ PlanDerivation "claim-1" (pcPredicateRefs claim) DeriveSelectedPredicate
                       "selected highest-ranked admitted predicate" (take 7 (map (cleanSentence . spRu . candidatePredicate) alternatives))
                   ]
                   <> [ PlanDerivation "counterpoint-1" [pcText point] DeriveContrast
                          "used curated counterpredicate or distinct admitted predicate" []
                      | Just point <- [counterpoint]
                      ]
                   <> [ PlanDerivation "next-move" [] (obligationRule obligation)
                          "continues the highest-priority unresolved dialogue obligation" []
                      | Just _ <- [obligation]
                      ]
              in ResponseSemanticPlan
                  { rspVersion = responsePlanVersion
                  , rspGoal = goal
                  , rspTopic = Just topic
                  , rspClaims = [claim]
                  , rspPropositions = propositions
                  , rspCounterpoint = counterpoint
                  , rspObligation = obligation
                  , rspNextMove = obligationSurface <$> obligation
                  , rspDerivation = derivation
                  , rspFallbackReason = Nothing
                  , rspDiscourse = DiscoursePlan
                      { dpRelation = if counterpoint == Nothing then DiscourseQualification else DiscourseCounterpoint
                      , dpMarker = Just (if counterpoint == Nothing then "Ограничение" else "Контрпроверка")
                      , dpMaxSentences = 3
                      }
                  }
  where
    topics = take 2 . uniqueNonEmpty $ map cleanTopic rawTopics
    candidates = take 8 $ concatMap candidatesForTopic topics
    candidatesForTopic topic =
      let selected = selectPredicates selector field topic (activationArtifactNetwork <$> mActivation)
      in [ PlanCandidate predicate (maybe 0 spScore (listToMaybe selected))
         | selectedPredicate <- selected
         , predicate <- spPredicates selectedPredicate
         ]

data PlanCandidate = PlanCandidate
  { candidatePredicate :: !SemanticPredicate
  , candidateConfidence :: !Double
  }

comparisonCounter :: ResponseGoal -> PlanCandidate -> [PlanCandidate] -> Maybe SemanticProposition
comparisonCounter GoalCompare primary alternatives =
  predicateProposition . candidatePredicate <$> find (differentTopic primary) alternatives
comparisonCounter _ _ _ = Nothing

differentTopic :: PlanCandidate -> PlanCandidate -> Bool
differentTopic left right = spTopicForm (candidatePredicate left) /= spTopicForm (candidatePredicate right)

predicateProposition :: SemanticPredicate -> SemanticProposition
predicateProposition predicate =
  case spCanonicalRelation predicate of
    Just relation -> PropositionPredicate (cprSubject relation) (cprRelation relation) (cprObject relation)
    Nothing -> PropositionPredicate "" (cleanSentence (spRu predicate)) ""

nonEmptyProposition :: Text -> Maybe SemanticProposition
nonEmptyProposition text
  | T.null cleaned = Nothing
  | otherwise = Just (PropositionPredicate "" cleaned "")
  where
    cleaned = cleanSentence text

-- | Counterpoints and syntheses are admitted source material, but their
-- discourse markers belong to the surrounding proposition constructors.
-- Keeping the leaves marker-free gives GF a typed contrast/conditional rather
-- than duplicating Russian connective text inside a raw predicate leaf.
derivedProposition :: Text -> SemanticProposition
derivedProposition text =
  PropositionPredicate "" (catalogedLeafText text) ""

claimModeFor :: ResponseGoal -> ClaimMode
claimModeFor goal = case goal of
  GoalDefine -> ClaimKnown
  GoalCompare -> ClaimInterpretive
  GoalChallenge -> ClaimInterpretive
  GoalClarify -> ClaimQuestion
  GoalGenerateThesis -> ClaimHypothetical
  GoalHypothesize -> ClaimHypothetical
  _ -> ClaimInterpretive

deriveObligation :: Maybe Text -> ResponseGoal -> SemanticProposition -> Maybe SemanticProposition -> Maybe DialogueObligation
deriveObligation mActiveQuestion goal proposition mCounter =
  case normalizeActiveQuestion =<< mActiveQuestion of
    Just question -> Just (ObligationContinue question)
    Nothing -> case mCounter of
      Just counter -> Just (ObligationCheck counter)
      Nothing -> case goal of
        GoalCompare -> Just (ObligationContrast proposition)
        GoalChallenge -> Just (ObligationClarify "уточнить основание возражения")
        GoalClarify -> Just (ObligationClarify "уточнить рамку вопроса")
        _ -> Just (ObligationContinue "проверить тезис на контрпример")

obligationRule :: Maybe DialogueObligation -> DerivationRule
obligationRule obligation = case obligation of
  Just ObligationCheck{} -> DeriveQualification
  Just ObligationContrast{} -> DeriveContrast
  Just ObligationClarify{} -> DeriveQuestion
  Just ObligationContinue{} -> DeriveQuestion
  Just ObligationClose{} -> DeriveQuestion
  Nothing -> DeriveSelectedPredicate

obligationSurface :: DialogueObligation -> Text
obligationSurface obligation = case obligation of
  ObligationClarify text -> "уточнить: " <> text
  ObligationCheck proposition -> "проверить тезис через условие: " <> renderSemanticProposition proposition
  ObligationContrast proposition -> "сопоставить с: " <> renderSemanticProposition proposition
  ObligationContinue text -> "вернуться к открытому вопросу: «" <> text <> "»"
  ObligationClose text -> "закрыть вопрос: " <> text

obligationProposition :: SemanticProposition -> DialogueObligation -> SemanticProposition
obligationProposition primary obligation = case obligation of
  ObligationClarify text -> PropositionQuestion (PropositionPredicate "" text "")
  ObligationCheck proposition -> PropositionQuestion proposition
  ObligationContrast proposition -> PropositionQuestion proposition
  -- The user wording is retained in the obligation itself. The GF discourse
  -- leaf must be the approved predicate rather than raw user text.
  ObligationContinue _ -> PropositionQuestion primary
  ObligationClose text -> PropositionQuestion (PropositionPredicate "" text "")

planRequest :: SemanticFrame -> SemanticIntent -> Maybe (ResponseGoal, [Text])
planRequest frame intent = case intent of
  IntentDefine topic -> Just (GoalDefine, [topic])
  IntentDistinguish left right -> Just (GoalCompare, [left, right])
  IntentChallenge -> Just (GoalChallenge, frameTopics frame)
  IntentGround topic -> Just (GoalExplain, [topic])
  IntentLearn topic -> Just (GoalExplain, [topic])
  IntentPurpose topic -> Just (GoalExplain, [topic])
  IntentWorldCause topic -> Just (GoalExplain, [topic])
  IntentDeepen topic -> Just (GoalExplain, [topic])
  IntentExploratory -> Just (GoalHypothesize, frameTopics frame)
  _ -> Nothing

frameTopics :: SemanticFrame -> [Text]
frameTopics frame = case frame of
  DefinitionFrame topic _ _ -> [topic]
  DistinctionFrame left right _ -> [left, right]
  ChallengeFrame target _ _ _ -> [target]
  GroundFrame topic _ -> [topic]
  ReflectFrame topic -> [topic]
  LearnFrame topic _ -> [topic]
  HelpFrame topic -> [topic]
  PurposeFrame topic -> [topic]
  WorldCauseFrame topic -> [topic]
  DeepenFrame topic -> [topic]
  _ -> []

fallbackPlan :: ResponseGoal -> SemanticFallbackReason -> Maybe Text -> ResponseSemanticPlan
fallbackPlan goal reason topic = ResponseSemanticPlan
  { rspVersion = responsePlanVersion
  , rspGoal = goal
  , rspTopic = topic
  , rspClaims = []
  , rspPropositions = []
  , rspCounterpoint = Nothing
  , rspObligation = Nothing
  , rspNextMove = Nothing
  , rspDerivation = []
  , rspFallbackReason = Just reason
  , rspDiscourse = DiscoursePlan DiscourseNone Nothing 2
  }

buildCounterpoint :: Double -> SemanticPredicate -> [SemanticPredicate] -> Maybe PlannedClaim
buildCounterpoint confidence primary predicates =
  let primaryText = cleanSentence (spRu primary)
      secondary = find ((/= primaryText) . cleanSentence . spRu) predicates
      counterText = spCounter primary <|> (spRu <$> secondary)
   in catalogedLeafText <$> counterText >>= \text ->
       if T.null text || text == primaryText
         then Nothing
         else Just PlannedClaim
           { pcId = "counterpoint-1"
           , pcMode = ClaimQuestion
           , pcText = text
           , pcPredicateRefs = [text]
            , pcEvidence = EvidenceSelectedPredicate
             , pcConfidence = confidence
             }

normalizeActiveQuestion :: Text -> Maybe Text
normalizeActiveQuestion question =
  let normalized = T.take 240 (T.unwords (T.words question))
  in if T.null normalized then Nothing else Just normalized

-- | Extract the longest known topic first, then preserve an uncovered topic
-- after a topic marker so the admission reason remains observable.
responsePlanTopic :: ContentSelector -> Text -> Maybe Text
responsePlanTopic selector rawInput =
  let lowered = normalizeTopic rawInput
      knownTopics = sortOn (negate . T.length) (M.keys (csTopicPredicates selector))
      uncovered = firstAfterMarker lowered [" о ", " об ", " обо ", " про ", " на тему "]
      explicitKnown = uncovered >>= \candidate ->
        find (topicMatchesExplicit candidate) (sortOn explicitRank knownTopics)
      known = find (topicMatches lowered) knownTopics
  in explicitKnown <|> uncovered <|> known
  where
    topicMatches input topic =
      topicMatchesText input topic
        || any (\candidate -> inflectedWordMatch candidate (cleanTopic topic)) (T.words (T.map normalizeWordChar input))
    topicMatchesExplicit input topic =
      let candidate = cleanTopic input
          normalizedTopic = cleanTopic topic
          topicWords = T.words normalizedTopic
      in candidate == normalizedTopic
           || (length topicWords == 1 && length (T.words candidate) == 1
               && inflectedWordMatch candidate normalizedTopic)
    explicitRank topic = (if length (T.words topic) == 1 then 0 :: Int else 1, T.length topic)
    normalizeWordChar c
      | c `elem` ("?!.,;:\"'()[]{}" :: String) = ' '
      | otherwise = c

-- | Recognize the narrow request shape needed to protect the generative path
-- when proposition classification loses the route hint for an uncovered topic.
-- This is deliberately not a general intent classifier: it only admits an
-- explicit generation verb together with a thought/thesis object.
isGenerativeRequestText :: Text -> Bool
isGenerativeRequestText rawInput =
  let input = T.toLower (T.strip rawInput)
      hasAny phrases = any (`T.isInfixOf` input) phrases
      hasGenerationVerb = hasAny ["придумай", "сформулируй", "предложи"]
        || (hasAny ["скажи", "дай"] && hasAny ["мысль", "идею", "идея", "тезис", "фразу"])
      hasGenerationObject = hasAny ["мысль", "идею", "идея", "тезис", "тезиса", "фразу", "эксперимент"]
  in hasGenerationVerb && hasGenerationObject

isClarifyRequestText :: Text -> Bool
isClarifyRequestText rawInput =
  let input = T.toLower (T.strip rawInput)
  in any (`T.isInfixOf` input) ["уточни", "уточните", "проясни", "поясни"]

firstAfterMarker :: Text -> [Text] -> Maybe Text
firstAfterMarker input markers =
  listToMaybe
    [ cleanTopic suffixAfter
    | marker <- markers
    , let (_, suffix) = T.breakOn marker input
    , not (T.null suffix)
    , let suffixAfter = T.drop (T.length marker) suffix
    , not (T.null (cleanTopic suffixAfter))
    ]

topicMatchesText :: Text -> Text -> Bool
topicMatchesText input topic =
  let wordsInInput = T.words (T.map normalizeChar input)
      normalizedTopic = cleanTopic topic
  in normalizedTopic `elem` wordsInInput
       || (" " <> normalizedTopic <> " ") `T.isInfixOf` (" " <> input <> " ")
  where
    normalizeChar c
      | c `elem` ("?!.,;:\"'()[]{}" :: String) = ' '
      | otherwise = c

cleanTopic :: Text -> Text
cleanTopic = T.dropWhileEnd (`elem` ("?!.,;:" :: String)) . T.strip

inflectedWordMatch :: Text -> Text -> Bool
inflectedWordMatch candidate topic =
  let endings = ["ами", "ями", "ого", "ему", "ому", "ыми", "ими", "ей", "ой", "ий", "ый", "ое", "ее", "ом", "ем", "ам", "ям", "ах", "ях", "ов", "ев", "ей", "а", "я", "ы", "и", "е", "у", "ю", "ь"]
      stems word = [T.dropEnd (T.length ending) word | ending <- endings, ending `T.isSuffixOf` word]
      commonStem left right = T.length left >= 5 && left == right
  in any (\candidateStem -> any (commonStem candidateStem) (stems topic)) (stems candidate)

cleanSentence :: Text -> Text
cleanSentence text =
  let cleaned = T.strip text
  in T.dropWhileEnd (`elem` (".!?" :: String)) cleaned

-- | Argued leaves are cataloged verbatim, including terminal punctuation.
-- Other predicate material retains legacy sentence cleanup before composition.
catalogedLeafText :: Text -> Text
catalogedLeafText text =
  let exact = T.strip text
  in case lookupArguedLeafConstructor exact of
       Just _ -> exact
       Nothing -> cleanSentence exact

renderResponseSemanticPlan :: ResponseSemanticPlan -> Text
renderResponseSemanticPlan plan =
  case rspFallbackReason plan of
    Just NoTopicProvided ->
      "Укажи тему, и я сформулирую тезис из доступных смысловых оснований."
    Just TopicNotCovered ->
      "Я вижу тему, но в локальной модели нет достаточного основания для содержательного тезиса. Могу предложить только явно отмеченную гипотезу после уточнения рамки."
    Just NoAdmissiblePredicate ->
      "По этой теме не нашлось admissible-предиката. Я не буду заменять отсутствие основания универсальной фразой."
    Just ConflictingEvidence ->
      "По этой теме есть конфликтующие основания. Сначала нужно выбрать критерий, по которому их сопоставлять."
    Just PlanQualityRejected ->
      "План ответа не прошёл проверку качества, поэтому я не выдаю неподтверждённый тезис."
    Nothing ->
      case rspClaims plan of
        [] -> "Я не могу построить содержательный план ответа без основания."
        claim:_ ->
          let proposition = fromMaybeText (pcText claim) (listToMaybe (rspPropositions plan))
              basis = T.intercalate "; " (pcPredicateRefs claim)
              headline = responseLabel (rspGoal plan) <> ": "
                <> ensureSentence (renderSemanticProposition proposition <> basisSuffix basis)
              counterpointText = case rspCounterpoint plan of
                Nothing -> Nothing
                Just point -> Just ("Контрпроверка: " <> ensureSentence (pcText point))
              nextMoveText = ("Следующий ход: " <>) . ensureSentence <$> rspNextMove plan
              fragments = headline : mapMaybe id [counterpointText, nextMoveText]
          in T.intercalate " " (take (dpMaxSentences (rspDiscourse plan)) fragments)

renderSemanticProposition :: SemanticProposition -> Text
renderSemanticProposition proposition = case proposition of
  PropositionPredicate subject relation object ->
    T.unwords (filter (not . T.null) [subject, relation, object])
  PropositionConditional premise conclusion ->
    "если " <> renderSemanticProposition premise <> ", то " <> renderSemanticProposition conclusion
  PropositionConjunction left right ->
    renderSemanticProposition left <> ", и вместе с тем " <> renderSemanticProposition right
  PropositionContrast thesis counter ->
    renderSemanticProposition thesis <> ", но " <> renderSemanticProposition counter
  PropositionQuestion inner ->
    "нужно уточнить: " <> renderSemanticProposition inner
  PropositionQualification inner condition ->
    renderSemanticProposition inner <> " при условии: " <> renderSemanticProposition condition

responseLabel :: ResponseGoal -> Text
responseLabel goal = case goal of
  GoalGenerateThesis -> "Тезис"
  GoalDefine -> "Определение"
  GoalExplain -> "Объяснение"
  GoalCompare -> "Сопоставление"
  GoalClarify -> "Уточнение"
  GoalRepair -> "Восстановление"
  GoalChallenge -> "Ответ на возражение"
  GoalHypothesize -> "Гипотеза"

basisSuffix :: Text -> Text
basisSuffix basis
  | T.null basis = ""
  | otherwise = " (основание: " <> basis <> ")"

fromMaybeText :: Text -> Maybe SemanticProposition -> SemanticProposition
fromMaybeText fallback proposition = case proposition of
  Just value -> value
  Nothing -> PropositionPredicate "" fallback ""

responsePlanQualityIssues :: ResponseSemanticPlan -> [Text]
responsePlanQualityIssues plan =
  [ "plan_not_admissible" | not (responsePlanIsAdmissible plan) ]
    <> [ "missing_topic_for_claim" | not (null (rspClaims plan)) && rspTopic plan == Nothing ]
    <> [ "missing_proposition_for_claim" | rspVersion plan >= 2 && not (null (rspClaims plan)) && null (rspPropositions plan) ]
    <> [ "duplicate_predicate_refs" | any hasDuplicates (map pcPredicateRefs (rspClaims plan)) ]
  where
    hasDuplicates values = length values /= length (unique values)
    unique [] = []
    unique (x:xs) = x : unique (filter (/= x) xs)

ensureSentence :: Text -> Text
ensureSentence text =
  let cleaned = T.strip text
  in if T.null cleaned || T.takeEnd 1 cleaned `elem` [".", "!", "?"]
        then cleaned
        else cleaned <> "."

clamp01 :: Double -> Double
clamp01 value = max 0 (min 1 value)

uniqueNonEmpty :: [Text] -> [Text]
uniqueNonEmpty = foldr add [] . map T.strip
  where
    add text acc
      | T.null text || text `elem` acc = acc
      | otherwise = text : acc

infixl 3 <|>
(<|>) :: Maybe a -> Maybe a -> Maybe a
Just value <|> _ = Just value
Nothing <|> other = other
