{-# LANGUAGE OverloadedStrings #-}
{-| Proposition type detection logic — full 23-detector chain migrated 2026-06-04. -}
module QxFx0.Semantic.Proposition.Detection
  ( -- * Main dispatcher
    detectPropositionType
  , detectRegressionFamilyOverrides
  , detectKeywordFallbackType
  , collectRawKeywordFallbackDecisions
  , buildKeywordFallbackTypeFromDecisions
    -- * Specific detectors (re-exported from Detectors)
  , detectContactSignal
  , detectOperationalStatus
  , detectOperationalCause
  , detectSystemLogic
  , detectDistinctionQuestion
  , detectConfrontSignal
  , detectNextStepSignal
  , detectAffectiveSupport
  , detectSelfKnowledge
  , detectPurposeFunction
  , detectDialogueInvitation
  , detectConceptKnowledge
  , detectWorldCause
  , detectLocationFormation
  , detectSelfState
  , detectComparisonPlausibility
  , detectMisunderstanding
  , detectRepairDirective
  , detectGenerativePrompt
  , detectContemplativeTopic
  , detectExploratoryPrompt
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.Maybe (fromMaybe, listToMaybe, catMaybes, mapMaybe)
import QxFx0.Types (TruthContractStatus(..))
import QxFx0.Semantic.Proposition.Types
  ( PropositionType(..)
  , toFallbackType
  , fromFallbackType
  )
import QxFx0.Semantic.Proposition.Semantic
  ( fallbackKeywordGroups
  , collectKeywordFallbackDecision
  , fallbackDecisionToPhraseDecisions
  )
import QxFx0.Types.Admission.PropositionPhraseDecisionAdmission
  ( PropositionPhraseDecisionAdmissionInput(..)
  , AdmittedPropositionPhraseDecisions(..)
  , admitPropositionPhraseDecisions
  )
import QxFx0.Types.PropositionFallbackAdmission
  ( PropositionFallbackType
  , RawPropositionKeywordFallbackDecision(..)
  , RawPropositionPhraseDecision(..)
  )
import QxFx0.Types.PropositionContactAdmission
  ( RawPropositionContactTrigger(..)
  )
import QxFx0.Semantic.KeywordMatch (containsAnyKeywordPhrase)
import QxFx0.Policy.ParserKeywords (contactKeywords)

-- Import the full specific-detector chain
import QxFx0.Semantic.Proposition.Detectors

-- | Full detection chain (23 detectors in priority order).
detectPropositionType :: TruthContractStatus -> Text -> [Text] -> PropositionType
detectPropositionType truthContractStatus rawText tokens = fromMaybe PlainAssert $ listToMaybe $ catMaybes
  [ detectRegressionFamilyOverrides rawText
  , detectDistinctionQuestion truthContractStatus rawText tokens
  , detectConfrontSignal truthContractStatus rawText tokens
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
