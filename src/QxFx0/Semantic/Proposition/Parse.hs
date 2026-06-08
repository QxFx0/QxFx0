{-# LANGUAGE OverloadedStrings #-}
{-| Proposition parsing functions.

This module provides the main parsing interface for converting raw text
into structured InputPropositionFrame records with semantic analysis.
-}
module QxFx0.Semantic.Proposition.Parse
  ( -- * Main parsing functions
    parseProposition
  , parsePropositionWithTruthContract
  , parsePropositionWithFrame
  , parsePropositionWithFrameAndTruthContract
  , parsePropositionMorph
    -- * Helper functions
  , propositionTypeHintFromFrame
  , inferRegisterHint
  , inferSemanticSlotsWithFrame
  , frameEvidence
  , pickNonEmpty
  , pickIfBaseEmpty
  , isLikelyAdjectiveTopic
  , isDeicticTopic
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe)
import QxFx0.Types
  ( InputPropositionFrame(..)
  , emptyInputPropositionFrame
  , TruthContractStatus(..)
  , Register(..)
  , ClauseForm(..)
  , IllocutionaryForce(..)
  , SemanticLayer(..)
  , MorphologyData(..)
  , forceForFamily
  , clauseFormForIF
  , layerForFamily
  )
import QxFx0.Semantic.Input.Model
  ( UtteranceSemanticFrame(..)
  , InputRouteHint(..)
  , SemanticTag(..)
  , semanticTagText
  , wmuSurfaceForm
  , wmuPartOfSpeech
  , wmuSyntacticRole
  )
import QxFx0.Semantic.Input.Assemble
  ( buildUtteranceSemanticFrame
  , buildUtteranceSemanticFrameMorph
  )
import QxFx0.Semantic.Proposition.Types
  ( PropositionType(..)
  , propositionToFamily
  )
import QxFx0.Semantic.Proposition.Focus
  ( extractFocusEntity
  , extractKeyPhrases
  , dedupeNormalized
  , dedupeEvidence
  , isSemanticCandidateSurface
  )
import QxFx0.Semantic.Proposition.Semantic
  ( specialFocusEntity
  , inferSemanticSlots
  , computeConfidence
  , detectEmotion
  )
import QxFx0.Semantic.Proposition.Detection
  ( detectPropositionType
  )
import QxFx0.Semantic.KeywordMatch
  ( tokenizeKeywordText
  , containsKeywordPhrase
  , containsAnyKeywordPhrase
  )
import QxFx0.Policy.ParserKeywords
  ( propositionNegationFragment
  , propositionSearchKeywords
  , propositionContactKeyword
  )
import QxFx0.Lexicon.Inflection (toNominative)
import QxFx0.Types.Text (textShow)

-- | Parse proposition with default truth contract (CanonicalSurfacePreserved).
parseProposition :: Text -> InputPropositionFrame
parseProposition rawText = parsePropositionWithTruthContract CanonicalSurfacePreserved rawText

-- | Parse proposition with specified truth contract status.
parsePropositionWithTruthContract :: TruthContractStatus -> Text -> InputPropositionFrame
parsePropositionWithTruthContract truthContractStatus rawText =
  parsePropositionWithFrameAndTruthContract truthContractStatus rawText (buildUtteranceSemanticFrame rawText)

-- | Parse proposition with pre-built semantic frame.
parsePropositionWithFrame :: Text -> UtteranceSemanticFrame -> InputPropositionFrame
parsePropositionWithFrame rawText semanticFrame =
  parsePropositionWithFrameAndTruthContract CanonicalSurfacePreserved rawText semanticFrame

-- | Parse proposition with truth contract and semantic frame.
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
    , ipfPropositionType = propType
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

-- | Parse proposition with morphological analysis (IO version).
parsePropositionMorph :: Text -> IO InputPropositionFrame
parsePropositionMorph rawText = do
  semanticFrame <- buildUtteranceSemanticFrameMorph rawText
  pure (parsePropositionWithFrame rawText semanticFrame)

-- | Extract proposition type hint from semantic frame route tag.
propositionTypeHintFromFrame :: UtteranceSemanticFrame -> Maybe PropositionType
propositionTypeHintFromFrame semanticFrame =
  case irhTag (usfRouteHint semanticFrame) of
    TagAffectiveHelp -> Just ContactSignal
    TagGreetingSmalltalk -> Just ContactSignal
    TagShortDialogueProbe -> Just ContactSignal
    TagFarewellContact -> Just ContactSignal
    TagGratitudeContact -> Just ContactSignal
    TagApologyRepair -> Just RepairSignal
    TagAgreementAnchor -> Just AnchorSignal
    TagDisagreementConfront -> Just ConfrontQ
    TagOpinionQuestion -> Just SelfStateQ
    TagEverydayEvent -> Just GroundQ
    TagDialogueInvitation -> Just DialogueInvitationQ
    TagConceptKnowledge -> Just ConceptKnowledgeQ
    TagSelfState -> Just SelfStateQ
    TagSystemLogic -> Just SystemLogicQ
    TagGenerativePrompt -> Just GenerativePrompt
    TagContemplativeTopic -> Just ContemplativeTopic
    TagMisunderstanding -> Just MisunderstandingReport
    TagBoundaryCommand -> Just RepairSignal
    TagPurposeFunction -> Just PurposeQ
    TagWorldCause -> Just WorldCauseQ
    TagOperationalCause -> Just OperationalCauseQ
    TagLocationFormation -> Just LocationFormationQ
    TagNextStep -> Just NextStepQ
    TagSelfKnowledge -> Just SelfKnowledgeQ
    TagCustom "force_contact_regression" -> Just ContactSignal
    TagCustom "force_ground_regression" -> Just WorldCauseQ
    TagCustom "force_reflect_regression" -> Just ReflectiveQ
    TagCustom "force_repair_regression" -> Just RepairSignal
    _ -> Nothing

-- | Infer register hint from semantic frame and tokens.
inferRegisterHint :: UtteranceSemanticFrame -> [Text] -> Register
inferRegisterHint semanticFrame tokens =
  case irhTag (usfRouteHint semanticFrame) of
    TagWorldCause -> Search
    TagConceptKnowledge -> Search
    TagLocationFormation -> Search
    TagDialogueInvitation -> Contact
    TagMisunderstanding -> Contact
    _ ->
      if containsAnyKeywordPhrase tokens propositionSearchKeywords
        then Search
        else
          if containsKeywordPhrase tokens propositionContactKeyword
            then Contact
            else Neutral

-- | Infer semantic slots with frame integration.
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

-- | Extract evidence from semantic frame for tracing.
frameEvidence :: UtteranceSemanticFrame -> [Text]
frameEvidence semanticFrame =
  [ "frame.route_tag=" <> semanticTagText (irhTag (usfRouteHint semanticFrame))
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

-- | Pick non-empty text, preferring the first argument.
pickNonEmpty :: Text -> Text -> Text
pickNonEmpty preferred fallback
  | T.null (T.strip preferred) = fallback
  | otherwise = preferred

-- | Pick preferred if base is empty, otherwise use base.
pickIfBaseEmpty :: Text -> Text -> Text
pickIfBaseEmpty preferred base
  | T.null (T.strip base) = pickNonEmpty preferred base
  | otherwise = base

-- | Check if text looks like an adjective (Russian morphology heuristic).
isLikelyAdjectiveTopic :: Text -> Bool
isLikelyAdjectiveTopic raw =
  let txt = T.toLower (T.strip raw)
  in any (`T.isSuffixOf` txt)
      [ "ый", "ий", "ой", "ая", "яя", "ое", "ее", "ые", "ие"
      , "ого", "ему", "ыми", "ых", "ую", "юю"
      ]

-- | Check if text is a deictic expression (here, there, etc.).
isDeicticTopic :: Text -> Bool
isDeicticTopic raw =
  T.toLower (T.strip raw) `elem` ["тут", "здесь", "там", "сюда", "туда", "отсюда", "оттуда"]

