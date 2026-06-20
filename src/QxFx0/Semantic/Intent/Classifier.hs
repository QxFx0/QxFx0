{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Semantic.Intent.Classifier
Description : Deterministic compositional intent classifier.

Classifies raw utterances into 'SemanticIntent' values using compositional
rules over 'SemanticFeatures'. This replaces the 23-detector keyword chain
in 'QxFx0.Semantic.Proposition.Detection' with a feature-based approach:

* Features describe /what properties/ the utterance has (question, negation,
  comparison, etc.)
* Rules combine features /compositionally/ to determine intent
* Single keywords do NOT decide classification — feature combinations do

Invariant: same input → same intent, always. Pure, total, deterministic.
No live second semantic ruler. No statistical model. No embedding lookup.
-}
module QxFx0.Semantic.Intent.Classifier
  ( SemanticIntent(..)
  , classifyIntent
  , intentToPropositionType
  , intentToFamily
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)
import Control.DeepSeq (NFData)
import Data.Aeson (ToJSON, FromJSON)

import QxFx0.Semantic.Intent.Features (SemanticFeatures(..), extractFeatures)
import QxFx0.Semantic.Morphology (extractContentNouns)
import QxFx0.Types (MorphologyData, CanonicalMoveFamily(..))
import QxFx0.Semantic.Proposition.Types (PropositionType(..))
import QxFx0.Types.PropositionType (PropositionType(..))
import QxFx0.Semantic.Proposition.Semantic (comparisonCandidates)

-- | Semantic intent: what the user wants, not how they said it.
--
-- This is the output of deterministic compositional classification.
-- Each constructor represents a distinct user intent that can be
-- satisfied by a specific response strategy.
--
-- 'IntentUnknown' is the honest fallback: the classifier could not
-- determine intent from available features. This is NOT an error —
-- it is an honest signal that the utterance doesn't match any
-- compositional rule. The caller decides what to do with it.
data SemanticIntent
  = IntentDefine Text
    -- ^ User wants a definition: "что такое X?", "означает ли X?"
    -- Topic extracted from content nouns.
  | IntentDistinguish Text Text
    -- ^ User wants to compare/contrast two concepts:
    -- "разница между A и B", "сравни A и B"
  | IntentChallenge
    -- ^ User challenges a prior claim: "неверно", "спорю", "а если"
  | IntentGround Text
    -- ^ User wants grounding/concretization: "подробнее", "объясни"
  | IntentRepair
    -- ^ User signals something is broken: "сломал", "не работает"
  | IntentContact
    -- ^ Greeting/relationship: "привет", "как дела"
  | IntentReflect
    -- ^ User asks for reflection: "что думаешь?", "какая мысль?"
  | IntentLearn Text
    -- ^ User wants to learn: "расскажи о X", "хочу узнать"
  | IntentHelp Text
    -- ^ User asks for help: "помоги с X", "поддержи"
  | IntentPurpose Text
    -- ^ User asks about purpose/function: "для чего X?", "зачем X?"
  | IntentWorldCause Text
    -- ^ User asks about world causation: "почему X?", "отчего X?"
  | IntentDeepen Text
    -- ^ User wants to go deeper: "углубимся", "продолжай"
  | IntentNextStep
    -- ^ User wants actionable next step: "что дальше?", "план?"
  | IntentExploratory
    -- ^ User explores hypotheticals: "а если", "представь"
  | IntentOperational
    -- ^ User asks about system status: "ты работаешь?"
  | IntentSelfReference
    -- ^ User asks about the system itself: "что ты можешь?"
  | IntentUnknown Text
    -- ^ Honest fallback: no compositional rule matched.
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Deterministic compositional classifier. Same input → same intent.
--
-- Priority chain: structural > semantic > discourse > lexical.
-- Each level tries more specific rules before falling through.
--
-- This is NOT keyword matching — it combines multiple features
-- via compositional rules. The lexical items in feature extraction
-- are /indicators/, not /triggers/.
classifyIntent :: Text -> [Text] -> MorphologyData -> SemanticIntent
classifyIntent rawText tokens morph =
  let features = extractFeatures rawText tokens morph
  in classifyFromFeatures rawText features

-- | Core classification logic. Separated from extraction for testability.
classifyFromFeatures :: Text -> SemanticFeatures -> SemanticIntent
classifyFromFeatures rawText features =
  -- Level 1: structural rules (question form + specific markers)
  case classifyStructural rawText features of
    Just intent -> intent
    Nothing ->
      -- Level 2: semantic role rules (two concepts + comparison)
      case classifySemanticRoles rawText features of
        Just intent -> intent
        Nothing ->
          -- Level 3: discourse marker rules (challenge, repair, contact)
          case classifyDiscourse rawText features of
            Just intent -> intent
            Nothing ->
              -- Level 4: topic-specific rules (purpose, cause, self)
              case classifyTopicSpecific features of
                Just intent -> intent
                Nothing ->
                  -- Level 5: honest fallback
                  IntentUnknown rawText

-- ---------------------------------------------------------------------------
-- Compositional rules (NOT single-keyword triggers)
-- ---------------------------------------------------------------------------

-- | Level 1: structural rules — syntactic form + semantic markers.
--
-- "что такое X?" → IntentDefine (question + definition mark)
-- "разница между A и B?" → IntentDistinguish (question + two concepts + comparison)
-- "что дальше?" → IntentNextStep (question + next step mark)
classifyStructural :: Text -> SemanticFeatures -> Maybe SemanticIntent
classifyStructural rawText f
  -- Challenge markers outrank broad definitional phrases like "это".
  | sfHasChallengeMark f = Just IntentChallenge
  -- Question + definition marker → define
  | sfIsQuestion f && sfHasDefinitionMark f = Just (IntentDefine (extractTopicAfter rawText "что такое"))
  -- Question + two concepts + comparison → distinguish
  | sfIsQuestion f && sfHasTwoConcepts f && sfHasComparisonMark f = Just (IntentDistinguish (extractComparisonLeft rawText) (extractComparisonRight rawText))
  -- Question + next step marker → next step
  | sfIsQuestion f && sfHasNextStepMark f = Just IntentNextStep
  -- Question + purpose marker → purpose
  | sfIsQuestion f && sfHasPurposeMark f = Just (IntentPurpose (extractTopicAfter rawText "для чего"))
  -- Question + world cause marker → world cause
  | sfIsQuestion f && sfHasWorldCauseMark f = Just (IntentWorldCause (extractTopicAfter rawText "почему"))
  -- Question + deepen marker → deepen
  | sfIsQuestion f && sfHasDeepenMark f = Just (IntentDeepen (extractTopicAfter rawText "расскажи"))
  -- Question + generative marker → reflect
  | sfIsQuestion f && sfHasGenerativeMark f = Just IntentReflect
  -- Question + operational marker → operational
  | sfIsQuestion f && sfHasOperationalMark f = Just IntentOperational
  | otherwise = Nothing

-- | Level 2: semantic role rules — concept structure.
--
-- Two concepts + comparison → distinguish
-- Challenge mark → challenge
-- Repair mark → repair
classifySemanticRoles :: Text -> SemanticFeatures -> Maybe SemanticIntent
classifySemanticRoles rawText f
  -- Two concepts + comparison mark → distinguish
  | sfHasTwoConcepts f && sfHasComparisonMark f = Just (IntentDistinguish (extractComparisonLeft rawText) (extractComparisonRight rawText))
  -- Challenge mark → challenge
  | sfHasChallengeMark f = Just IntentChallenge
  -- Repair mark → repair
  | sfHasRepairMark f = Just IntentRepair
  | otherwise = Nothing

-- | Level 3: discourse marker rules — interaction patterns.
--
-- Contact mark → contact
-- Deepen mark (non-question) → deepen
-- Generative mark (non-question) → reflect
-- Exploratory mark → exploratory
-- Self reference → self reference
classifyDiscourse :: Text -> SemanticFeatures -> Maybe SemanticIntent
classifyDiscourse rawText f
  -- Contact → contact
  | sfHasContactMark f = Just IntentContact
  -- Operational (with or without question mark) → operational
  | sfHasOperationalMark f = Just IntentOperational
  -- Generative (non-question) → reflect
  | sfHasGenerativeMark f = Just IntentReflect
  -- Exploratory → exploratory
  | sfHasExploratoryMark f = Just IntentExploratory
  | otherwise = Nothing

-- | Level 4: topic-specific rules — need content noun extraction.
--
-- These rules extract topics from the utterance and construct
-- intent values with topic parameters.
classifyTopicSpecific :: SemanticFeatures -> Maybe SemanticIntent
classifyTopicSpecific f
  -- Self reference → self reference (handled by features, no topic needed)
  | sfHasSelfReference f = Just IntentSelfReference
  | otherwise = Nothing

-- ---------------------------------------------------------------------------
-- Topic extraction (deterministic, not keyword-based)
-- ---------------------------------------------------------------------------

-- | Extract topic after a marker phrase.
-- E.g., extractTopicAfter "что такое свобода" "что такое" → "свобода"
extractTopicAfter :: Text -> Text -> Text
extractTopicAfter rawText marker =
  let lower = T.toLower (T.strip rawText)
      markerLower = T.toLower marker
      raw = if markerLower `T.isPrefixOf` lower
            then T.strip (T.drop (T.length marker + 1) (T.strip rawText))
            else T.strip rawText
  in T.dropWhileEnd (`elem` ("?!.,;:" :: String)) raw

-- | Extract left concept from comparison utterance.
-- "разница между свободой и волей" → "свободой"
-- "отличие несвободы от подчинения" → "несвободы"
-- "сравни A и B" → "A"
extractComparisonLeft :: Text -> Text
extractComparisonLeft rawText =
  case comparisonCandidates rawText of
    (left:_) -> left
    _ -> ""

extractComparisonRight :: Text -> Text
extractComparisonRight rawText =
  case comparisonCandidates rawText of
    (_:right:_) -> right
    _ -> ""

-- ---------------------------------------------------------------------------
-- Intent → existing type conversions
-- ---------------------------------------------------------------------------

-- | Convert SemanticIntent to the legacy PropositionType.
-- Used during migration (Phase A) to bridge old and new paths.
intentToPropositionType :: SemanticIntent -> PropositionType
intentToPropositionType (IntentDefine _)        = ConceptKnowledgeQ
intentToPropositionType (IntentDistinguish _ _) = DistinctionQ
intentToPropositionType IntentChallenge         = ConfrontQ
intentToPropositionType (IntentGround _)        = GroundQ
intentToPropositionType IntentRepair            = RepairSignal
intentToPropositionType IntentContact           = ContactSignal
intentToPropositionType IntentReflect           = GenerativePrompt
intentToPropositionType (IntentLearn _)         = ConceptKnowledgeQ
intentToPropositionType (IntentHelp _)          = AffectiveQ
intentToPropositionType (IntentPurpose _)       = PurposeQ
intentToPropositionType (IntentWorldCause _)    = WorldCauseQ
intentToPropositionType (IntentDeepen _)        = DeepenQ
intentToPropositionType IntentNextStep          = NextStepQ
intentToPropositionType IntentExploratory       = GenerativePrompt
intentToPropositionType IntentOperational       = OperationalStatusQ
intentToPropositionType IntentSelfReference     = SelfKnowledgeQ
intentToPropositionType (IntentUnknown _)       = PlainAssert

-- | Convert SemanticIntent to CanonicalMoveFamily.
-- Direct mapping, no intermediate PropositionType needed.
intentToFamily :: SemanticIntent -> CanonicalMoveFamily
intentToFamily (IntentDefine _)        = CMDefine
intentToFamily (IntentDistinguish _ _) = CMDistinguish
intentToFamily IntentChallenge         = CMConfront
intentToFamily (IntentGround _)        = CMGround
intentToFamily IntentRepair            = CMRepair
intentToFamily IntentContact           = CMContact
intentToFamily IntentReflect           = CMReflect
intentToFamily (IntentLearn _)         = CMDefine
intentToFamily (IntentHelp _)          = CMContact
intentToFamily (IntentPurpose _)       = CMPurpose
intentToFamily (IntentWorldCause _)    = CMGround
intentToFamily (IntentDeepen _)        = CMDeepen
intentToFamily IntentNextStep          = CMNextStep
intentToFamily IntentExploratory       = CMHypothesis
intentToFamily IntentOperational       = CMClarify
intentToFamily IntentSelfReference     = CMDescribe
intentToFamily (IntentUnknown _)       = CMGround
