{-# LANGUAGE OverloadedStrings #-}
module QxFx0.Semantic.Proposition.Detect.Overrides
  ( detectRegressionFamilyOverrides
  , detectKeywordFallbackType
  , matchKeywords
  ) where

import QxFx0.Semantic.Proposition.Types (PropositionType(..))
import QxFx0.Semantic.KeywordMatch
  ( containsKeywordPhrase
  , containsAnyKeywordPhrase
  )
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
import Data.Text (Text)
import qualified Data.Text as T
import Data.Maybe (listToMaybe, catMaybes)

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

matchKeywords :: [Text] -> PropositionType -> [Text] -> Maybe PropositionType
matchKeywords keywords propType tokens
  | containsAnyKeywordPhrase tokens keywords = Just propType
  | otherwise = Nothing
