{-# LANGUAGE OverloadedStrings, LambdaCase, DerivingStrategies #-}
{-| Dialogue surface rendering: claim linearization, stance framing, and fallback text assembly. -}
module QxFx0.Render.Dialogue
  ( DialogueRenderArtifact(..)
  , GenerationAttempt(..)
  , hasStructuredDialogueSurface
  , renderDialogueArtifact
  , renderDialogueUtterance
  , renderOperatorAwareDialogue
  , moveToText
  , isVapidTopic
  , cleanTopic
  , stancePrefix
  , linearizeClaimAstRus
  -- v2 assembly path
  , renderArtifactViaAssembly
  -- M4-SEMANTIC-CORE-003: compositional generator
  , generateFromFrame
  ) where

import Data.Text (Text)
import QxFx0.Self.Field (Field, emptyField, fieldConfidence, fieldCounterfactual, fieldConsolidation, fieldResonance, unFieldConfidence, unCounterfactual, unConsolidation, unResonance)
import QxFx0.Semantic.Content
  ( lookupDefinitionContent, lookupDistinctionContent, isCoveredTopic
  , isCoveredPair, coveredTopics, SemanticPredicate(..)
  , DefinitionContent(..), DistinctionContent(..), PredicateRole(..)
  , ConceptCategory(..), classifyConceptCategory
  , genericDefinitionPredicates, genericDistinctionPredicates
  , lookupDefinitionWithGeneric, lookupDistinctionWithGeneric
  , lookupChallengeContent, lookupGroundContent, lookupPurposeContent
  , ChallengeContent(..), GroundContent(..), PurposeContent(..)
  , renderPredicateArgued, lookupChallengeResponse, ChallengeResponse(..)
  , challengeIntros, pickChallengeIntro
  )
import QxFx0.Semantic.Content.AtomStore (AtomId(..))
import QxFx0.Semantic.Content.PathFinder
  ( FieldProfile(..), composeDefinition
  )
import QxFx0.Semantic.ContentSelector (ContentSelector, selectPredicates, composeFromActivation, emptyContentSelector, SelectedPredicate(..))
import QxFx0.Semantic.Network (SemanticNetwork)
import QxFx0.Semantic.Analogy (analogicalResponse, fallbackSimilarity, findNearestCoveredTopic)
import qualified Data.Set as Set
import QxFx0.Render.FieldModulation (applyFieldModulations)
import qualified Data.Text as T
import qualified Data.Char as Char
import Data.Maybe (fromMaybe, listToMaybe, isJust)
import Control.Applicative ((<|>))
import Data.Char (isAlpha)
import QxFx0.Types
import QxFx0.Types.Sense (RhetoricalMove(..), FallbackPolicy(..), ImplicationDirection(..))
import QxFx0.Types.TruthContract (truthContractAllowsHardKnowledgeTone)
import QxFx0.Lexicon.GfMap
  ( GfLexemeForms(..)
  , GfMapLoadStatus(..)
  , defaultGfLexemeId
  , gfMapFallbackReason
  , gfMapLoadStatus
  , lookupTopicGfLexemeId
  , lookupGfLexemeForms
  , topicToGfLexemeDecision
  )
import QxFx0.Semantic.Lexicon.RuntimeParadigms
  ( RuntimeParadigms
  , emptyRuntimeParadigms
  , lookupNounForm
  , NounCase(..)
  , Number(..)
  )
import QxFx0.Lexicon.PGFStatus (pgfFallbackReason)
import QxFx0.Lexicon.Inflection (toNominative)
import QxFx0.Types.Text (finalizeForce)
import QxFx0.Semantic.Proposition (PropositionType(..))
import QxFx0.Semantic.Proposition.Semantic (comparisonCandidates)
import QxFx0.Policy.ParserKeywords
  ( vapidWords
  )
import QxFx0.Semantic.KeywordMatch (tokenizeKeywordText)
import QxFx0.Semantic.DialogMeaning (buildDialogAtoms)
import QxFx0.Semantic.DialogAtom (DialogAtoms, emptyDialogAtoms)
import QxFx0.Semantic.Input.Parse (ParsedInput)
import QxFx0.Semantic.DialogAssembly (assembleTurn)
import QxFx0.Semantic.MeaningDecompose (factBySubject)
import QxFx0.Semantic.MeaningAssembly (assembleExplanation)
import QxFx0.Types.State.System (ssDiscourse)
import QxFx0.Semantic.Lexicon.RuntimeParadigms (RuntimeParadigms)
import QxFx0.Semantic.Embedding.Fallback (stableHash)
import qualified QxFx0.Semantic.Frame.Types as FT
import QxFx0.Policy.RenderLexicon
  ( stanceExplore, stanceTentative, stanceFirm, stanceHonest
  , stanceHoldBack, stanceCurated
  , styleFormal, styleWarm, styleDirect, stylePoetic
  , styleClinical, styleCautious, styleRecovery
  , moveGroundKnownPrefix, moveGroundBasisPrefix, moveShiftFromLabelPrefix
  , moveDefineFramePrefix, moveStateDefinitionPrefix
  , moveShowContrastPrefix, moveShowContrastPrepSuffix
  , moveStateBoundaryPrefix, moveReflectMirrorPrefix
  , moveReflectResonatePrefix, moveDescribeSketchPrefix
  , movePurposeTeleologyPrefix, moveHypothesizeTestPrefix
  , moveAffirmPresence, moveAcknowledgeRupture
  , moveRepairBridgePrefix, moveContactBridgePrefix
  , moveContactReachPrefix, moveAnchorStabilizePrefix
  , moveClarifyDisambiguatePrefix, moveDeepenProbePrefix
  , moveConfrontChallengePrefix, moveNextStepPrefix
  , openGuillemet, closeGuillemet
  , arrowSeparator, dashSeparator
  )

data DialogueRenderArtifact = DialogueRenderArtifact
  { draRenderedText :: !Text
  , draQuestionLike :: !Bool
  , draStylePrefixText :: !Text
  , draTemplateBodyText :: !Text
  , draClaimText :: !Text
  , draClaimAst :: !(Maybe ClaimAst)
  , draLinearizationLang :: !(Maybe Text)
  , draLinearizationOk :: !Bool
  , draFallbackReason :: !(Maybe Text)
  , draContractProvenance :: !ContractProvenance
  , draSurfaceProvenance :: !SurfaceProvenance
  , draDerivationTags :: ![Text]
  , draDialogAtoms :: !DialogAtoms
  , draGenerationTrace :: ![GenerationAttempt]
    -- ^ P9: ordered list of generation attempts (dialog assembly, factual,
    --   template, structured fallback, PGF runtime) with per-attempt outcome.
    --   Populated by 'renderArtifactViaAssembly'; extended by PGF resolution.
  } deriving stock (Eq, Show)

-- | Detect whether input text is English (pure Latin, no Cyrillic).
isEnglishInput :: Text -> Bool
isEnglishInput input =
  let letters = T.filter isAlpha input
      hasLatin = T.any (\c -> ('a' <= c && c <= 'z') || ('A' <= c && c <= 'Z')) letters
      hasCyrillic = T.any (\c -> ('а' <= c && c <= 'я') || ('А' <= c && c <= 'Я') || c == 'ё' || c == 'Ё') letters
  in hasLatin && not hasCyrillic

-- | Simple English GF linearization for common AST patterns.
-- This is a minimal EN counterpart to linearizeClaimAstRus.
-- Phase-A1 expanded coverage: all ClaimAst constructors now have
-- an EN linearization path, preventing silent fallback to RU
-- recursion when GF/PGF is unavailable.
linearizeClaimAstEn :: ClaimAst -> Maybe Text
linearizeClaimAstEn ast =
  case ast of
    StanceWrapped _ innerAst -> linearizeClaimAstEn innerAst
    ClaimPurpose topic ->
      let t = T.toLower (T.strip topic)
      in if T.null t then Nothing else Just ("The purpose of " <> t <> " reveals itself through repeatable roles in action.")
    ClaimSelfState ->
      Just "I maintain local self-state through typed parsing and move routing."
    ClaimComparison left right ->
      let l = T.toLower (T.strip left)
          r = T.toLower (T.strip right)
      in if T.null l || T.null r then Nothing else Just ("Comparison of " <> l <> " and " <> r <> " is stable only within an explicit frame.")
    MoveInvite (MkNP gfTopic) gfMod gfAction ->
      let topic = maybe "" glfPrep (lookupGfLexemeForms gfTopic)
          modStr = case gfMod of
            ModFirst -> "first "
            ModStrictly -> "strictly "
          vpStr = case gfAction of
            ActMaintain _ "ramka_N" -> "maintain the frame"
            ActDefine "granitsa_N"  -> "define the boundary"
            ActMaintain _ obj       -> "maintain " <> maybe obj glfAcc (lookupGfLexemeForms obj)
            ActDefine obj           -> "define " <> maybe obj glfAcc (lookupGfLexemeForms obj)
      in if T.null topic then Nothing else Just ("Yes, let us talk about " <> topic <> ". I will " <> modStr <> vpStr <> " to keep focus.")
    MoveDefine (MkNP gfSubj) _ (MkNP gfObj) ->
      let subj = maybe "" glfNom (lookupGfLexemeForms gfSubj)
          obj  = maybe "" glfNom (lookupGfLexemeForms gfObj)
      in if T.null subj || T.null obj then Nothing else Just (capitalize subj <> " is a form of " <> obj <> ".")
    MoveGround (MkNP gfSubj) ->
      let subj = maybe "" glfNom (lookupGfLexemeForms gfSubj)
      in if T.null subj then Nothing else Just ("I ground " <> subj <> " in concrete examples and stable usage.")
    MoveDistinguish (MkNP gfA) (MkNP gfB) ->
      let a = maybe "" glfNom (lookupGfLexemeForms gfA)
          b = maybe "" glfNom (lookupGfLexemeForms gfB)
      in if T.null a || T.null b then Nothing else Just ("I distinguish " <> a <> " from " <> b <> ".")
    MoveContact (MkNP gfSubj) ->
      let subj = maybe "" glfNom (lookupGfLexemeForms gfSubj)
      in if T.null subj then Nothing else Just ("I am here to discuss " <> subj <> ".")
    MoveMisunderstanding ->
      Just "I accept this as a signal of misunderstanding. Let me clarify."
    MovePurpose (MkNP gfSubj) ->
      let subj = maybe "" glfNom (lookupGfLexemeForms gfSubj)
      in if T.null subj then Nothing else Just ("The purpose of " <> subj <> " reveals itself through repeatable roles in action.")
    MoveCause (MkNP gfSubj) _ ->
      let subj = maybe "" glfNom (lookupGfLexemeForms gfSubj)
      in if T.null subj then Nothing else Just ("If we speak of the cause of " <> subj <> ", I parse it locally.")
    MoveSystemLogic ->
      Just "This follows from the rules of the local reasoning system."
    MoveOperationalStatus ->
      Just "I am operational."
    MoveOperationalCause ->
      Just "The operational issue is in parsing and routing."
    MoveSelfState ->
      Just "I maintain local self-state through typed parsing and move routing."
    MoveCompare (MkNP gfLeft) (MkNP gfRight) ->
      let left  = maybe "" glfNom (lookupGfLexemeForms gfLeft)
          right = maybe "" glfNom (lookupGfLexemeForms gfRight)
      in if T.null left || T.null right then Nothing else Just ("Comparison of " <> left <> " and " <> right <> " is stable only within an explicit frame.")
    MoveGenerativeThought ->
      Just "One thought: meaning holds on the connection between words and experience. Another thought: the strength of thinking lies in holding distinctions. A new thought: development begins when we are ready to change our own frame. A logical thought: output quality is verified by the link between premises and conclusion."
    MoveContemplative (MkNP gfTopic) ->
      let topic = maybe "topic" glfNom (lookupGfLexemeForms gfTopic)
      in Just ("If we hold to the word " <> topic <> ", I hear in it not only an object but a field of meanings, including subjectivity as a way to hold inner form.")
    MoveReflect (MkNP gfTopic) ->
      let topic = maybe "" glfAcc (lookupGfLexemeForms gfTopic)
      in if T.null topic then Nothing else Just ("You reflected " <> topic <> ", and this calls for clarification of meaning.")
    MoveDescribe (MkNP gfTopic) ->
      let topic = maybe "" glfAcc (lookupGfLexemeForms gfTopic)
      in if T.null topic then Nothing else Just ("I will describe " <> topic <> " through a local working frame.")
    MoveDeepen (MkNP gfTopic) ->
      let topic = maybe "" glfPrep (lookupGfLexemeForms gfTopic)
      in if T.null topic then Nothing else Just ("Let us deepen the conversation about " <> topic <> " through one stable focus.")
    MoveConfront (MkNP gfTopic) ->
      let topic = maybe "" glfNom (lookupGfLexemeForms gfTopic)
      in if T.null topic then Nothing else Just ("Objection: " <> topic <> " requires checking assumptions.")
    MoveAnchor (MkNP gfTopic) ->
      let topic = maybe "" glfPrep (lookupGfLexemeForms gfTopic)
      in if T.null topic then Nothing else Just ("I fix grounding in " <> topic <> " as a point of stability.")
    MoveClarify (MkNP gfTopic) ->
      let topic = maybe "" glfPrep (lookupGfLexemeForms gfTopic)
      in if T.null topic then Nothing else Just ("Let us clarify what exactly you mean in " <> topic <> ".")
    MoveNextStepLocal (MkNP gfTopic) ->
      let topic = maybe "" glfAcc (lookupGfLexemeForms gfTopic)
      in if T.null topic then Nothing else Just ("Next step: make " <> topic <> " concrete in one action.")
    MoveHypothesis (MkNP gfTopic) ->
      let topic = maybe "" glfNom (lookupGfLexemeForms gfTopic)
      in if T.null topic then Nothing else Just ("Hypothesis: " <> topic <> " can be explained through a local model.")
    MoveActOnTopic ActAnswer    -> Just "Let us discuss the answer."
    MoveActOnTopic ActQuestion  -> Just "Let us discuss the question."
    MoveActOnTopic ActTopicTerm -> Just "Let us discuss the topic."
    MoveActOnTopic ActProject   -> Just "Let us discuss the project."
    MoveActOnTopic ActResult    -> Just "Let us discuss the result."
  where
    capitalize t = if T.null t then t else T.toUpper (T.take 1 t) <> T.drop 1 t

renderDialogueUtterance :: ResponseMeaningPlan -> ResponseContentPlan -> Text -> [IdentityClaimRef] -> MorphologyData -> Text
renderDialogueUtterance rmp rcp topic claims morph =
  draRenderedText (renderDialogueArtifact emptyInputPropositionFrame rmp rcp topic claims morph emptyRuntimeParadigms emptyField emptyContentSelector Nothing)

renderDialogueArtifact :: InputPropositionFrame -> ResponseMeaningPlan -> ResponseContentPlan -> Text -> [IdentityClaimRef] -> MorphologyData -> RuntimeParadigms -> Field -> ContentSelector -> Maybe SemanticNetwork -> DialogueRenderArtifact
renderDialogueArtifact frame rmp rcp topic claims morph rp field contentSelector mActivatedNetwork =
  case renderStructuredDialogueArtifact frame rmp rcp (rcpStyle rcp) morph rp field contentSelector mActivatedNetwork of
    Just artifact -> artifact
    Nothing ->
      let fallbackReason =
            if structuredDialogueType (ipfPropositionType frame)
              then "structured_body_returned_plain"
              else "proposition_type_not_structured"
      in if isEnglishInput (ipfRawText frame)
      then
        let topicText = cleanTopic topic
            enBody = "I am here to continue the dialogue in English."
                     <> if T.null topicText then "" else " I received your message about " <> topicText <> "."
            rendered = finalizeForce (rmpForce rmp) (T.strip enBody)
        in DialogueRenderArtifact
            { draRenderedText = rendered
            , draQuestionLike = rmpForce rmp == IFAsk
            , draStylePrefixText = ""
            , draTemplateBodyText = enBody
            , draClaimText = ""
            , draClaimAst = Nothing
            , draLinearizationLang = Just "en_fallback"
            , draLinearizationOk = False
            , draFallbackReason = Just ("en_unstructured_fallback:" <> fallbackReason)
            , draContractProvenance = FallbackRoute
            , draSurfaceProvenance = FromFallback
            , draDerivationTags = ["surface=en_unstructured", "fallback=" <> fallbackReason]
            , draDialogAtoms = emptyDialogAtoms
            , draGenerationTrace = []
            }
      else
        let cleanedTopic = cleanTopic topic
            openingText = moveToText (rcpOpening rcp) cleanedTopic rp morph
            coreText = moveToText (rcpCore rcp) cleanedTopic rp morph
            limitText = moveToText (rcpLimit rcp) cleanedTopic rp morph
            contText = moveToText (rcpContinuation rcp) cleanedTopic rp morph
            stylePrefixText = stylePrefix (rcpStyle rcp)
            microPlan = rmpMicroPlan rmp
            microPrefaceText = microPlanPrefix rmp cleanedTopic
            claimText = case claims of
              (c:_) ->
                case sanitizeIdentityClaimText (icrText c) of
                  Just txt -> " " <> txt
                  Nothing -> ""
              []    -> ""
            parts = take (max 1 (mpStructureBudget microPlan + 1)) . dedupeText $ filter (not . T.null) [microPrefaceText, openingText, coreText, limitText]
            body = T.intercalate (microPlanDelimiter (rcpStyle rcp) microPlan) parts
            fullBody = appendContinuation microPlan body contText
            withClaims = if T.null claimText then fullBody else fullBody <> claimText
            withStyle = if T.null stylePrefixText then withClaims else stylePrefixText <> " " <> withClaims
            rendered = finalizeForce (rmpForce rmp) (T.strip withStyle)
        in DialogueRenderArtifact
            { draRenderedText = rendered
            , draQuestionLike = rmpForce rmp == IFAsk
            , draStylePrefixText = stylePrefixText
            , draTemplateBodyText = withStyle
            , draClaimText = claimText
            , draClaimAst = Nothing
            , draLinearizationLang = Nothing
            , draLinearizationOk = False
            , draFallbackReason = Just fallbackReason
            , draContractProvenance = FallbackRoute
            , draSurfaceProvenance = FromFallback
            , draDerivationTags = ["surface=template", "fallback=" <> fallbackReason]
            , draDialogAtoms = emptyDialogAtoms
            , draGenerationTrace = []
            }

hasStructuredDialogueSurface :: InputPropositionFrame -> Bool
hasStructuredDialogueSurface frame =
  structuredDialogueType (ipfPropositionType frame)

renderStructuredDialogueArtifact :: InputPropositionFrame -> ResponseMeaningPlan -> ResponseContentPlan -> RenderStyle -> MorphologyData -> RuntimeParadigms -> Field -> ContentSelector -> Maybe SemanticNetwork -> Maybe DialogueRenderArtifact
renderStructuredDialogueArtifact frame rmp rcp renderStyle morph rp field contentSelector mActivatedNetwork =
  let propositionType = ipfPropositionType frame
  in if not (structuredDialogueType propositionType)
     then Nothing
     else
      let (body0, claimAst, mLang, linearizationOk, fallbackReason) =
            structuredBody propositionType frame rmp renderStyle morph rp field contentSelector mActivatedNetwork
          body1 = applyMicroPlanToStructuredBody rmp renderStyle field body0
          continuationText = structuredContinuationText frame rmp rcp rp morph
          body = appendContinuation (rmpMicroPlan rmp) body1 continuationText
          rendered = finalizeForce IFAssert (T.strip body)
          contractProv = contractProvenanceForArtifact fallbackReason claimAst
          surfaceProv = surfaceProvenanceForArtifact fallbackReason claimAst
      in Just
           DialogueRenderArtifact
             { draRenderedText = rendered
             , draQuestionLike = False
             , draStylePrefixText = ""
             , draTemplateBodyText = body
             , draClaimText = ""
              , draClaimAst = claimAst
              , draLinearizationLang = mLang
              , draLinearizationOk = linearizationOk
              , draFallbackReason = fallbackReason
              , draContractProvenance = contractProv
              , draSurfaceProvenance = surfaceProv
               , draDerivationTags = artifactDerivationTags propositionType linearizationOk fallbackReason claimAst
              , draDialogAtoms = emptyDialogAtoms
              , draGenerationTrace = []
              }

structuredDialogueType :: PropositionType -> Bool
structuredDialogueType propositionType =
  propositionType `elem`
    [ RepairSignal
    , ContactSignal
    , AffectiveQ
    , OperationalStatusQ
    , OperationalCauseQ
    , GroundQ
    , SystemLogicQ
    , SelfKnowledgeQ
    , DialogueInvitationQ
    , ConceptKnowledgeQ
    , PurposeQ
    , WorldCauseQ
    , LocationFormationQ
    , SelfStateQ
    , ComparisonPlausibilityQ
    , DistinctionQ
    , ConfrontQ
    , MisunderstandingReport
    , GenerativePrompt
    , ContemplativeTopic
    , NextStepQ
    ]

structuredBody :: PropositionType -> InputPropositionFrame -> ResponseMeaningPlan -> RenderStyle -> MorphologyData -> RuntimeParadigms -> Field -> ContentSelector -> Maybe SemanticNetwork -> (Text, Maybe ClaimAst, Maybe Text, Bool, Maybe Text)
structuredBody propositionType frame rmp renderStyle morph rp field contentSelector mActivatedNetwork =
  let isEn = isEnglishInput (ipfRawText frame)
      hardKnowledgeTone = truthContractAllowsHardKnowledgeTone (rmpTruthContractStatus rmp)
  in case propositionType of
    RepairSignal ->
      let ast = claimAstOrFallback MoveMisunderstanding (rmpPrimaryClaimAst rmp)
          fallback = if isEn then "I see a signal of overload. I will not build more interpretations: first let us restore grounding. Briefly point out where exactly the response broke for you, and I will rephrase precisely."
                     else "Вижу сигнал перегруза в текущем ходе. Я не буду наращивать интерпретации: сначала восстановим опору. Коротко укажи, где именно ответ сломался для тебя, и я переформулирую точечно."
          linFn = if isEn then linearizeOrFallbackTaggedEn else linearizeOrFallbackTagged
          claim = linFn "repair" ast renderStyle morph rp fallback
      in withClaimLang (clText claim) ast claim (if isEn then "en_GF_MVP" else "ru_GF_MVP")
    ContactSignal ->
      if isGreetingSmallTalkFrame frame
        then plain (contactGreetingSurface frame)
        else
          let topicRef = nonEmptyOr (ipfSemanticSubject frame) (if isEn then "grounding" else "опора")
              ast = claimAstOrFallback (MoveContact (MkNP (resolveTopicLexeme topicRef))) (rmpPrimaryClaimAst rmp)
              fallback = if isEn then "I hear that grounding is needed now. Let us simplify: identify one point of tension and choose one short step for the near term."
                         else "Слышу, что сейчас нужна опора." <> contactContextSentence rp morph (ipfSemanticSubject frame) <> " Давай упростим: выделим одну точку напряжения и выберем один короткий шаг на ближайшее время."
              linFn = if isEn then linearizeOrFallbackTaggedEn else linearizeOrFallbackTagged
              claim = linFn "contact" ast renderStyle morph rp fallback
          in withClaimLang (clText claim) ast claim (if isEn then "en_GF_MVP" else "ru_GF_MVP")
    AffectiveQ ->
      let topicRef = nonEmptyOr (ipfSemanticSubject frame) (if isEn then "state" else "состояние")
          ast = claimAstOrFallback (MoveContact (MkNP (resolveTopicLexeme topicRef))) (rmpPrimaryClaimAst rmp)
          fallback = if isEn
                       then "I hear that grounding is needed now. Let us simplify: identify one point of tension and choose one short step for the near term."
                       else "Слышу, что сейчас нужна опора." <> contactContextSentence rp morph (ipfSemanticSubject frame) <> " Давай упростим: выделим одну точку напряжения и выберем один короткий шаг на ближайшее время."
          linFn = if isEn then linearizeOrFallbackTaggedEn else linearizeOrFallbackTagged
          claim = linFn "affective" ast renderStyle morph rp fallback
      in withClaimLang (clText claim) ast claim (if isEn then "en_GF_MVP" else "ru_GF_MVP")
    OperationalStatusQ ->
      let ast = claimAstOrFallback MoveOperationalStatus (rmpPrimaryClaimAst rmp)
          fallback = if isEn
                       then pickDeterministic (T.toLower (ipfRawText frame) <> "|operational_status")
                         [ "I am operational. The limitation right now is not in startup but in that parsing precision is sometimes lost."
                         , "I am operational. In normal mode, but the weak point right now is local question parsing and choosing too general a template."
                         , "I am operational. Startup is fine; the main risk right now is routing: sometimes the question collapses to too general a reading."
                         , "I am operational. The narrow place is propositional parsing and excessively fast transition to a template move."
                         ]
                       else pickDeterministic (T.toLower (ipfRawText frame) <> "|operational_status")
                         [ "Я работаю. Ограничение сейчас не в запуске, а в том, что иногда теряется точность разбора входа."
                         , "Я работаю. В штатном режиме, но слабое место сейчас — локальный разбор вопроса и выбор слишком общего шаблона."
                         , "Я работаю. Запуск в норме; основной риск сейчас в маршрутизации: иногда вопрос схлопывается до слишком общей трактовки."
                         , "Я работаю. Узкое место — пропозиционный разбор и избыточно быстрый переход к шаблонному ходу."
                         ]
          linFn = if isEn then linearizeOrFallbackTaggedEn else linearizeOrFallbackTagged
          claim = linFn "operational_status" ast renderStyle morph rp fallback
      in withClaimLang (clText claim) ast claim (if isEn then "en_GF_MVP" else "ru_GF_MVP")
    OperationalCauseQ ->
      let ast = claimAstOrFallback MoveOperationalCause (rmpPrimaryClaimAst rmp)
          fallback = pickDeterministic (T.toLower (ipfRawText frame) <> "|operational_cause")
            [ "По запуску я работаю. Проблема сейчас в разборе смысла и маршрутизации: вопрос может быть слишком рано схлопнут до упрощённого ядра."
            , "По запуску я работаю. Проблема сейчас в разборе смысла и маршрутизации: из нескольких трактовок иногда выбирается слишком общий ход."
            , "По запуску я работаю. Проблема сейчас в разборе смысла и маршрутизации: ранний выбор семейства ответа делает реплику шаблонной."
            , "По запуску я работаю. Проблема сейчас в разборе смысла и маршрутизации: при потере нюансов ответ уходит в слишком универсальную формулу."
            ]
          claim = linearizeOrFallbackTagged "operational_cause" ast renderStyle morph rp fallback
      in withClaim (clText claim) ast claim
    GroundQ ->
      let topicRef = nonEmptyOr (ipfSemanticSubject frame) (if isEn then "situation" else "ситуация")
          topicPrep = if isEn then topicRef else structuredPrepositional rp morph topicRef
          ast = claimAstOrFallback (MoveGround (MkNP (resolveTopicLexeme topicRef))) (rmpPrimaryClaimAst rmp)
          fallback = if isEn then "I hold this as stable grounding for further analysis."
                     else "Держу это как устойчивую опору для дальнейшего разбора."
          linFn = if isEn then linearizeOrFallbackTaggedEn else linearizeOrFallbackTagged
          claim = linFn "ground" ast renderStyle morph rp fallback
          bodyText = if isEn then "If we speak about " <> topicPrep <> ", then " <> clText claim
                     else "Если говорить " <> aboutWithTopic topicPrep <> ", то " <> clText claim
      in withClaimLang bodyText ast claim (if isEn then "en_GF_MVP" else "ru_GF_MVP")
    SystemLogicQ ->
      let ast = claimAstOrFallback MoveSystemLogic (rmpPrimaryClaimAst rmp)
          claim = linearizeOrFallbackTagged "system_logic" ast renderStyle morph rp (systemLogicSurface frame)
      in withClaim (clText claim) ast claim
    SelfKnowledgeQ
      | asksThoughtCapacityQuestion frame ->
          plain (if isEn
                   then "No, not just one. I can formulate different thoughts, but if the requests are too close, my generative layer is still inclined to repeat a successful formulation instead of immediately developing a new one."
                   else "Нет, не одна. Я могу формулировать разные мысли, но если запросы слишком близки, мой генеративный слой пока склонен повторять удачную формулировку вместо того, чтобы сразу разворачивать новую.")
      | ipfSemanticTarget frame == "user" ->
          plain (if isEn
                    then "About you I know only what is manifested in this session. I have no external biography, hidden profiles, or separate memory of you outside the current conversation; I can rely only on your replies, chosen topics, and already established dialogue frames."
                    else if hardKnowledgeTone
                      then "О тебе я знаю только то, что проявлено в этой сессии. У меня нет внешней биографии, скрытых профилей или отдельной памяти о тебе вне текущего разговора; я могу опираться лишь на твои реплики, выбранные темы и уже установленные в диалоге рамки."
                      else "О тебе я знаю только то, что проявлено в этой сессии: у меня нет внешней биографии, скрытых профилей или отдельной памяти о тебе вне текущего разговора; я опираюсь лишь на твои реплики, выбранные темы и уже установленные в диалоге рамки.")
      | ipfSemanticTarget frame == "user_help" ->
          plain (if isEn
                   then "Yes, I can help. I work best when the task is stated explicitly and a local frame can be held: what exactly needs to be clarified, distinguished, defined, or gathered."
                   else "Да, я могу помочь. Лучше всего я работаю, когда задача задана явно и можно удержать локальную рамку: что именно нужно прояснить, различить, определить или собрать.")
      | ipfSemanticTarget frame == "self_capability" ->
          plain (if isEn
                   then "Yes, within the current session I can work with " <> (nonEmptyOr (ipfSemanticSubject frame) "this action") <> ". My ability here is not external magic but local parsing, holding the frame, and sequential assembly of the answer."
                   else "Да, в пределах текущей сессии я могу работать с " <> structuredInstrumentalIdea (nonEmptyOr (ipfSemanticSubject frame) "этим действием")
                     <> ". Моя способность здесь не внешняя магия, а локальный разбор, удержание рамки и последовательная сборка ответа.")
      | otherwise ->
          let target = ipfSemanticTarget frame
              forceTargetAst =
                target `elem` ["self_intentions", "self_values", "self_future", "self_freedom", "self_reflection"]
              ast =
                if forceTargetAst
                  then selfKnowledgeFallbackAst frame
                  else claimAstOrFallback (selfKnowledgeFallbackAst frame) (rmpPrimaryClaimAst rmp)
              fallback = if isEn
                            then "I am a local dialogue system. About myself I know my role, current state, and the way I proceed through the conversation: I work through typed parsing, family routing, and current session constraints."
                            else if hardKnowledgeTone
                              then "Я — локальная система диалога. О себе я знаю свою роль, текущее состояние и способ, которым иду по ходу разговора: я работаю через типизированный разбор, маршрутизацию семейства хода и ограничения текущей сессии."
                              else "Я — локальная система диалога. О себе я могу удерживать лишь рабочую локальную модель: роль, текущее состояние и способ, которым иду по ходу разговора через типизированный разбор, маршрутизацию семейства хода и ограничения текущей сессии."
              linFn = if isEn then linearizeOrFallbackTaggedEn else linearizeOrFallbackTagged
              claim = linFn "self_knowledge" ast renderStyle morph rp fallback
          in withClaimLang (if isEn then selfKnowledgeSurfaceByTargetEn target (clText claim) else selfKnowledgeSurfaceByTarget target (clText claim)) ast claim (if isEn then "en_GF_MVP" else "ru_GF_MVP")
    DialogueInvitationQ ->
      let fallbackTopic = nonEmptyOr (ipfSemanticSubject frame) (nonEmptyOr (rmpTopic rmp) (if isEn then "topic" else "тема"))
          fallbackAst = MoveInvite (MkNP (resolveTopicLexeme fallbackTopic)) ModFirst (ActMaintain NumSg "ramka_N")
          ast = claimAstOrFallback fallbackAst (rmpPrimaryClaimAst rmp)
          linFn = if isEn then linearizeOrFallbackTaggedEn else linearizeOrFallbackTagged
          fallback = if isEn
                       then "Yes, let us talk about this. I will fix the frame and begin with a grounding distinction so as not to let the topic dissolve into random associations."
                       else dialogueInvitationSurface rp frame morph
          claim = linFn "dialogue_invitation" ast renderStyle morph rp fallback
          rendered = clText claim
      in withClaimLang rendered ast claim (if isEn then "en_GF_MVP" else "ru_GF_MVP")
    ConceptKnowledgeQ
      | T.toLower (T.strip (ipfSemanticSubject frame)) == "солнце" ->
          plain (if hardKnowledgeTone
                   then "Да, я знаю, что солнце — это звезда и источник света и тепла для Земли. Для меня это базовое понятийное знание о явлениях внешнего мира, а не результат текущего наблюдения."
                   else "Да, в локальной понятийной рамке солнце — это звезда и источник света и тепла для Земли. Для меня это не текущее наблюдение, а рабочее общеизвестное описание внешнего мира.")
        | isEn ->
            let topicRef = nonEmptyOr (ipfSemanticSubject frame) (nonEmptyOr (rmpTopic rmp) "concept")
                selectedPreds = selectPredicates contentSelector field topicRef mActivatedNetwork
                ast = claimAstOrFallback (MoveDefine (MkNP (resolveTopicLexeme topicRef)) RelIdentity (MkNP "concept_N")) (rmpPrimaryClaimAst rmp)
                claim = linearizeOrFallbackTaggedEn "concept_knowledge" ast renderStyle morph rp (rmpPrimaryClaim rmp)
                contentText = case selectedPreds of
                 (sp:_) -> ". " <> T.intercalate " " (map spEn (spPredicates sp))
                 [] -> case lookupDefinitionContent topicRef of
                         Just dc -> ". " <> T.intercalate " " (map spEn (dcPredicates dc))
                         Nothing -> ""
           in withClaimLang ("If we consider " <> conceptTopicReferenceEn frame
               <> ", I will provide a working definition and separate it from usage and the boundaries of knowledge. "
               <> clText claim <> contentText) ast claim "en_GF_MVP"
        | otherwise ->
            let topicRef = nonEmptyOr (ipfSemanticSubject frame) (nonEmptyOr (rmpTopic rmp) "понятии")
                selectedPreds = selectPredicates contentSelector field topicRef mActivatedNetwork
                ast = claimAstOrFallback (MoveDefine (MkNP (resolveTopicLexeme (nonEmptyOr topicRef "понятии"))) RelIdentity (MkNP "ponyatie_N")) (rmpPrimaryClaimAst rmp)
                claim = linearizeOrFallback ast renderStyle morph rp (rmpPrimaryClaim rmp)
                contentText = case selectedPreds of
                  (sp:_) -> ". " <> T.intercalate " " (map renderPredicateArgued (spPredicates sp))
                  [] -> case lookupDefinitionContent topicRef of
                          Just dc -> ". " <> T.intercalate " " (map renderPredicateArgued (dcPredicates dc))
                          Nothing -> ""
            in withClaim ("Если говорить " <> aboutWithTopic (conceptTopicReference rp frame morph)
                <> ", зафиксирую рабочее определение и отделю его от употребления и границ знания. "
                <> clText claim <> contentText) ast claim
    PurposeQ ->
      let topicRef = nonEmptyOr (T.strip (ipfSemanticSubject frame)) (nonEmptyOr (T.strip (rmpTopic rmp)) (if isEn then "object" else "объект"))
          topicNom = if isEn then topicRef else toNominative morph topicRef
          topicGen = if isEn then topicRef else structuredGenitive rp morph topicNom
          topicPhrase =
            if isEn then "the purpose of " <> topicRef
            else if isLikelyBrokenGenitive topicNom topicGen
              then "темы " <> openGuillemet <> topicRef <> closeGuillemet
              else topicGen
          (topicFunId, topicLexemeFallback) = topicToGfLexemeDecision topicNom
          ast = claimAstOrFallback (MovePurpose (MkNP topicFunId)) (rmpPrimaryClaimAst rmp)
          linFn = if isEn then linearizeOrFallbackTaggedEn else linearizeOrFallbackTagged
          claim = linFn "purpose" ast renderStyle morph rp (rmpPrimaryClaim rmp)
          purposeClaimText
            | isEn = "The function of " <> topicNom <> " reveals itself through repeatable roles in action."
            | topicLexemeFallback == Just "gf_default_lexeme" =
                "Функция " <> purposeTopicGenitive topicNom topicGen <> " проявляется через повторяемую роль в действии."
            | otherwise = clText claim
          bodyText = if isEn then "If we analyze the function of " <> topicPhrase
            <> ", it is useful to first identify the action, context of application, and stable result. "
            <> purposeClaimText
            else "Если разбирать функции " <> topicPhrase
            <> ", полезно сначала выделить действие, контекст применения и устойчивый результат. "
            <> purposeClaimText
      in withClaimLang bodyText ast claim (if isEn then "en_GF_MVP" else "ru_GF_MVP")
    WorldCauseQ ->
      let topicRef = nonEmptyOr (ipfSemanticSubject frame) (nonEmptyOr (rmpTopic rmp) (if isEn then "phenomenon" else "явление"))
          topicNom = if isEn then topicRef else toNominative morph topicRef
          topicGen = if isEn then topicRef else structuredGenitive rp morph topicNom
          safeTopicGen
            | isEn = topicRef
            | isLikelyBrokenGenitive topicNom topicGen = "этого явления"
            | isLikelyAdjectiveLikeTopic topicNom = "этого явления"
            | otherwise = topicGen
          ast = claimAstOrFallback (MoveCause (MkNP (resolveTopicLexeme topicNom)) MechParse) (rmpPrimaryClaimAst rmp)
          linFn = if isEn then linearizeOrFallbackTaggedEn else linearizeOrFallbackTagged
          claim = linFn "world_cause" ast renderStyle morph rp (rmpPrimaryClaim rmp)
          bodyText = if isEn
                        then "If we speak of the cause of " <> safeTopicGen <> ", then " <> clText claim
                          <> " Therefore I distinguish local reasoning about mechanism from full knowledge of the external world."
                        else if hardKnowledgeTone
                          then "Если говорить о причине " <> safeTopicGen <> ", то " <> clText claim
                            <> " Поэтому я различаю локальное рассуждение о механизме и полноценное знание о внешнем мире."
                          else "Если удерживать локальную схему причины " <> safeTopicGen <> ", то " <> clText claim
                            <> " Здесь я даю рабочую модель механизма, а не утверждаю полное знание о внешнем мире."
      in withClaimLang bodyText ast claim (if isEn then "en_GF_MVP" else "ru_GF_MVP")
    LocationFormationQ ->
      let topicRef = nonEmptyOr (ipfSemanticSubject frame) (if isEn then "thought" else "мысль")
          bodyText = if isEn
                       then "If we speak about " <> topicRef <> ", then in my local model it does not arise at one point but in the structure of connections between state, propositions, and dialogue constraints. " <> rmpPrimaryClaim rmp
                       else "Если говорить " <> aboutWithTopic (structuredPrepositional rp morph topicRef)
                         <> ", то в моей локальной модели она возникает не в одной точке, а в структуре связей между состоянием, пропозициями и ограничениями диалога. "
                         <> rmpPrimaryClaim rmp
      in plain bodyText
    SelfStateQ ->
      case selfStateDirectSurface frame of
        Just direct -> plain (if isEn then "I maintain local self-state through typed parsing and move routing." else if hardKnowledgeTone then direct else "Мой внутренний ход можно описать через типизированный разбор, маршрутизацию ответа и удержание текущего состояния диалога.")
        Nothing ->
          let ast = claimAstOrFallback MoveSelfState (rmpPrimaryClaimAst rmp)
              linFn = if isEn then linearizeOrFallbackTaggedEn else linearizeOrFallbackTagged
              claim = linFn "self_state" ast renderStyle morph rp (rmpPrimaryClaim rmp)
          in withClaimLang ((if isEn then "My current move is built from parsing the reply, choosing the response family, and session constraints. " else if hardKnowledgeTone then selfStateSurface frame <> " " else "Мой внутренний ход можно описать через локальный разбор реплики, выбор семейства ответа, ограничения сессии и удержание текущего состояния диалога. ") <> clText claim) ast claim (if isEn then "en_GF_MVP" else "ru_GF_MVP")
    ComparisonPlausibilityQ ->
      case ipfSemanticCandidates frame of
        left:right:_ ->
          let leftNom = if isEn then left else toNominative morph left
              rightNom = if isEn then right else toNominative morph right
              ast = claimAstOrFallback (MoveDistinguish (MkNP (resolveTopicLexeme leftNom)) (MkNP (resolveTopicLexeme rightNom))) (rmpPrimaryClaimAst rmp)
              linFn = if isEn then linearizeOrFallbackTaggedEn else linearizeOrFallbackTagged
              claim = linFn "distinguish" ast renderStyle morph rp (rmpPrimaryClaim rmp)
              bodyText = if isEn then "Comparison needs an explicit frame. If we speak of everyday stability, " <> rightNom
                <> " usually looks more natural because " <> leftNom
                <> " describes a less stable configuration. " <> clText claim
                <> " Without an explicit frame, comparison remains dependent on accepted assumptions."
                else "Сравнивать нужно в явной рамке. Если речь о бытовой устойчивости, то " <> rightNom
                <> " обычно выглядит естественнее, потому что " <> leftNom
                <> " описывает менее устойчивую конфигурацию. " <> clText claim
                <> " Без явной рамки сравнение остаётся зависимым от принятых допущений."
          in withClaimLang bodyText ast claim (if isEn then "en_GF_MVP" else "ru_GF_MVP")
        _ ->
          plain (if isEn then "Comparison of plausibility requires an explicit frame. " <> rmpPrimaryClaim rmp
                 else "Сравнение плаузибельности требует явной рамки. " <> rmpPrimaryClaim rmp)
    DistinctionQ ->
      case distinctionCandidatesForRender frame of
        left:right:_ ->
          let leftNom = if isEn then left else toNominative morph left
              rightNom = if isEn then right else toNominative morph right
              mDist = lookupDistinctionContent leftNom rightNom
              ast = claimAstOrFallback (MoveDistinguish (MkNP (resolveTopicLexeme leftNom)) (MkNP (resolveTopicLexeme rightNom))) (rmpPrimaryClaimAst rmp)
              linFn = if isEn then linearizeOrFallbackTaggedEn else linearizeOrFallbackTagged
              claim = linFn "distinguish" ast renderStyle morph rp (rmpPrimaryClaim rmp)
              claimText = if "ежду" `T.isInfixOf` clText claim
                then leftNom <> " и " <> rightNom <> " различаются по набору признаков. Без явной рамки сравнение остаётся зависимым от принятых допущений."
                else clText claim
              distText = case mDist of
                Just dc -> ". " <> T.intercalate " " (map (if isEn then spEn else spRu) (dcDifferentiators dc))
                Nothing -> ""
              bodyText = if isEn then "I distinguish " <> leftNom <> " from " <> rightNom <> " within one frame of criteria. " <> claimText <> distText
                else "Различим " <> leftNom <> " и " <> rightNom <> " в одной рамке критериев. " <> claimText <> distText
          in withClaimLang bodyText ast claim (if isEn then "en_GF_MVP" else "ru_GF_MVP")
        _ ->
          plain (if isEn then "Distinction requires an explicit frame of criteria. " <> rmpPrimaryClaim rmp
                 else "Различение требует явной рамки критериев. " <> rmpPrimaryClaim rmp)
    MisunderstandingReport ->
      let topicRef = nonEmptyOr (ipfSemanticSubject frame) (nonEmptyOr (rmpTopic rmp) (if isEn then "topic" else "тема"))
          selectedPreds = selectPredicates contentSelector field topicRef mActivatedNetwork
          acknowledgePrior = case selectedPreds of
            (sp:_) ->
              if isEn
                then " I held that " <> T.intercalate " " (map spEn (spPredicates sp))
                   <> ". If this was wrong, I will revise."
                else " Я ранее полагал, что " <> T.intercalate " " (map spRu (spPredicates sp))
                   <> ". Если это неверно, я пересмотрю."
            [] -> case lookupDefinitionContent topicRef of
              Just dc ->
                if isEn
                  then " I held that " <> T.intercalate " " (map spEn (dcPredicates dc))
                     <> ". If this was wrong, I will revise."
                  else " Я ранее полагал, что " <> T.intercalate " " (map spRu (dcPredicates dc))
                     <> ". Если это неверно, я пересмотрю."
              Nothing -> ""
          ast = claimAstOrFallback MoveMisunderstanding (rmpPrimaryClaimAst rmp)
          linFn = if isEn then linearizeOrFallbackTaggedEn else linearizeOrFallbackTagged
          fallback = if isEn
                       then "I accept this as a signal of misunderstanding. " <> rmpPrimaryClaim rmp
                         <> " Let us clarify where exactly the response diverged from your request: in meaning, tone, or reasoning."
                         <> acknowledgePrior
                       else "Я принимаю это как сигнал сбоя взаимопонимания. " <> rmpPrimaryClaim rmp
                         <> " Давай уточним, где именно ответ разошёлся с твоим запросом: в смысле, тоне или ходе рассуждения."
                         <> acknowledgePrior
          claim = linFn "misunderstanding" ast renderStyle morph rp fallback
      in withClaimLang (clText claim) ast claim (if isEn then "en_GF_MVP" else "ru_GF_MVP")
    ConfrontQ ->
      let topicRef = nonEmptyOr (ipfSemanticSubject frame) (nonEmptyOr (rmpTopic rmp) (if isEn then "topic" else "тема"))
          selectedPreds = selectPredicates contentSelector field topicRef mActivatedNetwork
          objectionText = ipfRawText frame
          -- Phase E: try challenge-response first, fall back to old template
          mChallengeResp = if not isEn
                           then lookupChallengeResponse topicRef objectionText
                                  (concatMap spPredicates (maybe [] (:[]) (listToMaybe selectedPreds)))
                           else Nothing
          acknowledgePrior = case selectedPreds of
            (sp:_) ->
              if isEn
                then " I held that " <> T.intercalate " " (map spEn (spPredicates sp))
                   <> ". You challenge this — let me respond."
                else " Я полагал, что " <> T.intercalate " " (map spRu (spPredicates sp))
                   <> ". Ты оспариваешь это — отвечу."
            [] -> case lookupDefinitionContent topicRef of
              Just dc ->
                if isEn
                  then " I held that " <> T.intercalate " " (map spEn (dcPredicates dc))
                     <> ". You challenge this — let me respond."
                  else " Я полагал, что " <> T.intercalate " " (map spRu (dcPredicates dc))
                     <> ". Ты оспариваешь это — отвечу."
              Nothing -> ""
          ast = claimAstOrFallback (MoveConfront (MkNP (resolveTopicLexeme (nonEmptyOr topicRef "тема")))) (rmpPrimaryClaimAst rmp)
          linFn = if isEn then linearizeOrFallbackTaggedEn else linearizeOrFallbackTagged
          -- Phase E: challenge-response with argued predicate + varied intro
          challengeResponseText = case mChallengeResp of
            Just (intro, cr) ->
              intro <> " " <> crRestate cr <> ". "
              <> renderPredicateArgued (crRelevantPredicate cr)
            Nothing -> ""
          fallback = if challengeResponseText /= ""
                       then challengeResponseText
                       else if isEn
                              then "I hear your objection. " <> acknowledgePrior
                                <> " Let me clarify my position: the claim I made is based on a working frame, not an absolute. If your counter-argument holds within that frame, I will revise."
                              else "Я слышу твоё возражение. " <> acknowledgePrior
                                <> " Уточню свою позицию: мой тезис опирается на рабочую рамку, а не на абсолют. Если твой контраргумент действует в этой рамке, я пересмотрю."
          claim = linFn "confront" ast renderStyle morph rp fallback
      in withClaimLang (clText claim) ast claim (if isEn then "en_GF_MVP" else "ru_GF_MVP")
    GenerativePrompt ->
      let ast = claimAstOrFallback MoveGenerativeThought (rmpPrimaryClaimAst rmp)
          linFn = if isEn then linearizeOrFallbackTaggedEn else linearizeOrFallbackTagged
          fallback = if isEn
                       then "One thought: meaning holds on the connection between words and experience. Another thought: the strength of thinking lies in holding distinctions. A new thought: development begins when we are ready to change our own frame. A logical thought: output quality is verified by the link between premises and conclusion."
                       else generativeThought frame
          claim = linFn "generative_prompt" ast renderStyle morph rp fallback
      in withClaimLang (clText claim) ast claim (if isEn then "en_GF_MVP" else "ru_GF_MVP")
    ContemplativeTopic ->
      let fallbackTopic = nonEmptyOr (ipfSemanticSubject frame) (if isEn then "topic" else "тема")
          fallbackAst = MoveContemplative (MkNP (resolveTopicLexeme fallbackTopic))
          ast = claimAstOrFallback fallbackAst (rmpPrimaryClaimAst rmp)
          linFn = if isEn then linearizeOrFallbackTaggedEn else linearizeOrFallbackTagged
          fallback = if isEn
                       then "If we hold to the word " <> fallbackTopic <> ", I hear in it not only an object but a field of meanings, including subjectivity as a way to hold inner form. Here one can go through memory, loss, closeness, and the ability to hold the form of life."
                       else "Если держаться слова " <> openGuillemet <> toNominative morph fallbackTopic <> closeGuillemet
                         <> ", я слышу в нём не только предмет, но и поле смыслов. Здесь можно идти через память, утрату, близость и способ удерживать форму жизни."
          claim = linFn "contemplative" ast renderStyle morph rp fallback
      in withClaimLang (clText claim) ast claim (if isEn then "en_GF_MVP" else "ru_GF_MVP")
    NextStepQ ->
      let topicRef = nonEmptyOr (ipfSemanticSubject frame) (nonEmptyOr (rmpTopic rmp) (if isEn then "task" else "задача"))
          topicNom = if isEn then topicRef else toNominative morph topicRef
          ast = claimAstOrFallback (MoveNextStepLocal (MkNP (resolveTopicLexeme topicNom))) (rmpPrimaryClaimAst rmp)
          linFn = if isEn then linearizeOrFallbackTaggedEn else linearizeOrFallbackTagged
          fallback = if isEn
                       then "Next step: make " <> topicNom <> " concrete in one action."
                       else "Следующий шаг: конкретизировать " <> topicNom <> " в одном действии."
          claim = linFn "next_step" ast renderStyle morph rp fallback
          bodyText = if isEn
                       then clText claim <> "\n"
                         <> "Let us fix a practical next move:\n"
                         <> "1) Name one goal on the topic of " <> topicNom <> ".\n"
                         <> "2) Choose a minimal step for 10-15 minutes and do it.\n"
                         <> "3) Check the result: did it become clearer or not, and adjust the next step."
                       else clText claim <> "\n"
                         <> "Зафиксируем практичный следующий ход:\n"
                         <> "1) Назови одну цель по теме " <> topicNom <> ".\n"
                         <> "2) Выбери минимальный шаг на 10-15 минут и сделай его.\n"
                         <> "3) Проверь результат: стало яснее или нет, и скорректируй следующий шаг."
      in withClaimLang bodyText ast claim (if isEn then "en_GF_MVP" else "ru_GF_MVP")
    _ ->
      plain (rmpPrimaryClaim rmp)
  where
    plain txt = (txt, Nothing, Nothing, False, Nothing)
    withClaimLang body ast linearization langTag =
      ( body
      , Just ast
      , Just langTag
      , clOk linearization
      , clFallbackReason linearization
      )
    withClaim body ast linearization = withClaimLang body ast linearization "ru_GF_MVP"

distinctionCandidatesForRender :: InputPropositionFrame -> [Text]
distinctionCandidatesForRender frame =
  case comparisonCandidates (ipfRawText frame) of
    candidates@(_:_:_) -> candidates
    _ -> ipfSemanticCandidates frame

data ClaimLinearization = ClaimLinearization
  { clText :: !Text
  , clOk :: !Bool
  , clFallbackReason :: !(Maybe Text)
  } deriving stock (Eq, Show)

claimAstOrFallback :: ClaimAst -> Maybe ClaimAst -> ClaimAst
claimAstOrFallback fallbackAst maybeAst =
  case maybeAst of
    Just ast -> ast
    Nothing -> fallbackAst

linearizeOrFallback :: ClaimAst -> RenderStyle -> MorphologyData -> RuntimeParadigms -> Text -> ClaimLinearization
linearizeOrFallback =
  linearizeOrFallbackTagged "unspecified"

linearizeOrFallbackTagged :: Text -> ClaimAst -> RenderStyle -> MorphologyData -> RuntimeParadigms -> Text -> ClaimLinearization
linearizeOrFallbackTagged reasonTag ast renderStyle morph rp fallbackText =
  -- WP-H2 R-H2.2: Check both gfMapFallbackReason AND pgfFallbackReason
  case (gfMapFallbackReason gfMapLoadStatus, pgfFallbackReason) of
    (Just reason, _) ->
      ClaimLinearization
        { clText = fallbackText
        , clOk = False
        , clFallbackReason = Just reason
        }
    (_, Just reason) ->
      ClaimLinearization
        { clText = fallbackText
        , clOk = False
        , clFallbackReason = Just reason
        }
    (Nothing, Nothing) ->
      case linearizeClaimAstRus rp ast renderStyle morph of
        Just txt ->
          ClaimLinearization
            { clText = txt
            , clOk = True
            , clFallbackReason = Nothing
            }
        Nothing ->
          ClaimLinearization
            { clText = fallbackText
            , clOk = False
            , clFallbackReason = Just ("gf_linearization_failed:" <> reasonTag)
            }

linearizeOrFallbackTaggedEn :: Text -> ClaimAst -> RenderStyle -> MorphologyData -> RuntimeParadigms -> Text -> ClaimLinearization
linearizeOrFallbackTaggedEn reasonTag ast _renderStyle _morph _rp fallbackText =
  -- WP-H2 R-H2.2: Check both gfMapFallbackReason AND pgfFallbackReason
  case (gfMapFallbackReason gfMapLoadStatus, pgfFallbackReason) of
    (Just reason, _) ->
      ClaimLinearization
        { clText = fallbackText
        , clOk = False
        , clFallbackReason = Just reason
        }
    (_, Just reason) ->
      ClaimLinearization
        { clText = fallbackText
        , clOk = False
        , clFallbackReason = Just reason
        }
    (Nothing, Nothing) ->
      case linearizeClaimAstEn ast of
        Just txt ->
          ClaimLinearization
            { clText = txt
            , clOk = True
            , clFallbackReason = Nothing
            }
        Nothing ->
          ClaimLinearization
            { clText = fallbackText
            , clOk = False
            , clFallbackReason = Just ("gf_en_linearization_failed:" <> reasonTag)
            }

-- | Helper: resolve a Russian noun form for a GF function id.
-- Strips the "_N" suffix, then resolves through a three-stage fallback chain:
--   1. RGL paradigms ('lookupNounForm') — the RGL-backed path;
--   2. legacy JSON forms ('lookupGfLexemeForms') — preserves pre-RGL output
--      when paradigms are absent (e.g. empty 'RuntimeParadigms');
--   3. the bare lemma — last resort.
-- Stage 2 is what keeps an unloaded/empty 'RuntimeParadigms' from regressing
-- Russian output to a transliterated lemma (e.g. "logika" instead of "логике").
--
-- Key-space bridge: GF function ids are Latin ("logika_N") but paradigms.json
-- is keyed by the Cyrillic nominative ("логика"). The RGL lookup is therefore
-- keyed by the JSON nominative form ('glfNom'), not the Latin lemma; without
-- this the RGL path can never resolve and silently always falls through to JSON.
lookupLemmaForm :: RuntimeParadigms -> Text -> NounCase -> Text
lookupLemmaForm rp funId case_ =
  let latinLemma = if "_N" `T.isSuffixOf` funId
                   then T.dropEnd 2 funId
                   else funId
      mForms = lookupGfLexemeForms funId
      -- Cyrillic nominative is the paradigm key; fall back to latin if absent.
      rglKey = maybe latinLemma glfNom mForms
      jsonForm = case mForms of
        Nothing -> Nothing
        Just forms -> case case_ of
          Nom -> Just (glfNom forms)
          Gen -> Just (glfGen forms)
          Acc -> Just (glfAcc forms)
          Ins -> Just (glfIns forms)
          Loc -> Just (glfPrep forms)
          Dat -> Nothing  -- JSON forms carry no dative; defer to lemma
  in case lookupNounForm rp rglKey case_ Sg of
       Just rglForm -> rglForm
       Nothing      -> fromMaybe latinLemma jsonForm

-- | Russian ClaimAst linearization with RGL-backed morphology.
-- Layer 2 (RGL migration): RuntimeParadigms parameter added for morphology lookups.
-- Morphology resolves via 'lookupLemmaForm', which falls back RGL -> JSON -> lemma,
-- so an empty 'RuntimeParadigms' still yields the legacy JSON-backed Russian forms.
linearizeClaimAstRus :: RuntimeParadigms -> ClaimAst -> RenderStyle -> MorphologyData -> Maybe Text
linearizeClaimAstRus rp ast renderStyle morph =
  case ast of
    StanceWrapped "ApplyStanceTentative" innerAst ->
      case linearizeClaimAstRus rp innerAst renderStyle morph of
        Just inner -> Just ("Возможно, нам стоит сказать, что " <> inner)
        Nothing -> Nothing
    StanceWrapped "ApplyStanceFirm" innerAst ->
      case linearizeClaimAstRus rp innerAst renderStyle morph of
        Just inner -> Just ("Зафиксируем строго: " <> inner)
        Nothing -> Nothing
    StanceWrapped _ innerAst ->
      linearizeClaimAstRus rp innerAst renderStyle morph
    MoveDefine (MkNP gfSubj) RelIdentity (MkNP gfObj) ->
      let subjNom = lookupLemmaForm rp gfSubj Nom
          objIns = lookupLemmaForm rp gfObj Ins
      in Just (subjNom <> " является " <> objIns <> ".")
    MoveCause (MkNP gfSubj) MechParse ->
      let subjGen = lookupLemmaForm rp gfSubj Gen
          seed = "cause|" <> subjGen
      in Just (pickDeterministic seed
          [ "Причиной " <> subjGen <> " служит механизм локального разбора."
          , "В моём локальном контуре причина " <> subjGen <> " объясняется механизмом локального разбора."
          , "Для " <> subjGen <> " я беру причинную схему через механизм локального разбора."
          , "Причинное объяснение " <> subjGen <> " у меня строится через механизм локального разбора."
          ])
    MoveInvite (MkNP gfTopic) gfMod gfAction ->
      -- Runtime fallback mirrors the GF surface when PGF is unavailable.
      let prepForm = lookupLemmaForm rp gfTopic Loc  -- Prepositional = Locative
          modStr = case gfMod of
            ModFirst -> "сначала "
            ModStrictly -> "строго "
          vpStr = case gfAction of
            ActMaintain num "ramka_N" -> (case num of NumPl -> "удержим"; NumSg -> "удержу") <> " рамку"
            ActDefine "granitsa_N" -> "определю границу"
            ActMaintain num obj ->
              let objAcc = lookupLemmaForm rp obj Acc
              in (case num of NumPl -> "удержим "; NumSg -> "удержу ") <> objAcc
            ActDefine obj ->
              let objAcc = lookupLemmaForm rp obj Acc
              in "определю " <> objAcc
      in Just ("Да, поговорим " <> aboutWithTopic prepForm <> ". Я " <> modStr <> vpStr <> ", чтобы не потерять фокус.")
    MovePurpose (MkNP gfTopic) ->
      let topicGen = lookupLemmaForm rp gfTopic Gen
      in Just ("Функция " <> topicGen <> " проявляется через повторяемую роль в действии.")
    MoveSelfState ->
      let seed = "move_self_state"
      in Just (pickDeterministic seed
        [ "Мой текущий ход строится из разбора реплики, выбора семейства ответа и ограничений сессии."
        , "Сейчас я держу локальный контур: разбор входа, выбор семейства хода и проверка ограничений текущей сессии."
        , "Внутренний ход сейчас собирается как цепочка: входная реплика -> выбор семейства -> контроль ограничений сессии."
        ])
    MoveCompare (MkNP gfLeft) (MkNP gfRight) ->
      let leftGen = lookupLemmaForm rp gfLeft Gen
          rightGen = lookupLemmaForm rp gfRight Gen
      in Just ("Сравнение " <> leftGen <> " и " <> rightGen <> " устойчиво только в явно заданной рамке.")
    MoveOperationalStatus ->
      Just (pickDeterministic "move_operational_status"
        [ "Я работаю. Ограничение сейчас не в запуске, а в том, что иногда теряется точность разбора входа."
        , "Я работаю. В штатном режиме, но слабое место сейчас — локальный разбор вопроса и выбор слишком общего шаблона."
        , "Я работаю. Запуск в норме; основной риск сейчас в маршрутизации: иногда вопрос схлопывается до слишком общей трактовки."
        , "Я работаю. Узкое место — пропозиционный разбор и избыточно быстрый переход к шаблонному ходу."
        ])
    MoveOperationalCause ->
      Just (pickDeterministic "move_operational_cause"
        [ "По запуску я работаю. Проблема сейчас в разборе смысла и маршрутизации: вопрос может быть слишком рано схлопнут до упрощённого ядра."
        , "По запуску я работаю. Проблема сейчас в разборе смысла и маршрутизации: из нескольких трактовок иногда выбирается слишком общий ход."
        , "По запуску я работаю. Проблема сейчас в разборе смысла и маршрутизации: ранний выбор семейства ответа делает реплику шаблонной."
        , "По запуску я работаю. Проблема сейчас в разборе смысла и маршрутизации: при потере нюансов ответ уходит в слишком универсальную формулу."
        ])
    MoveSystemLogic ->
      Just "Моя текущая логика локальная: я разбираю вопрос, выбираю семейство хода, сверяюсь с shadow-контуром и затем рендерю ответ. Слабое место сейчас в пропозиционном разборе и выборе семьи."
    MoveMisunderstanding ->
      Just "Я принимаю это как сигнал сбоя взаимопонимания и перехожу к уточнению: давай отметим, где именно ответ разошёлся с твоим запросом, в смысле, тоне или ходе рассуждения."
    MoveGenerativeThought ->
      Just "Одна мысль: смысл держится на связи между словами и опытом. Другая мысль: сила мышления — удержать различие. Новая мысль: развитие начинается, когда мы готовы менять собственную рамку. Логичная мысль: качество вывода проверяется связью между посылками и выводом."
    MoveContemplative (MkNP gfTopic) ->
      let topicNom = lookupLemmaForm rp gfTopic Nom
      in Just ("Если держаться слова " <> openGuillemet <> topicNom <> closeGuillemet <> ", я слышу в нём не только предмет, но и поле смыслов, включая субъектность как способ удерживать внутреннюю форму.")
    MoveGround (MkNP gfTopic) ->
      let topicAcc = lookupLemmaForm rp gfTopic Acc
          seed = "move_ground|" <> topicAcc
      in Just (pickDeterministic seed
        [ "Держу " <> topicAcc <> " как устойчивую опору для дальнейшего разбора."
        , "Фиксирую " <> topicAcc <> " как рабочую опору и продолжаю разбор от этой точки."
        , "Беру " <> topicAcc <> " как опорный узел, чтобы не потерять связность следующего шага."
        ])
    MoveContact (MkNP gfTopic) ->
      let topicPrep = lookupLemmaForm rp gfTopic Loc  -- Prepositional = Locative
      in Just ("Слышу запрос на контакт по теме " <> topicPrep <> ".")
    MoveReflect (MkNP gfTopic) ->
      let topicAcc = lookupLemmaForm rp gfTopic Acc
      in Just ("Вы отразили " <> topicAcc <> ", и это требует прояснения смысла.")
    MoveDescribe (MkNP gfTopic) ->
      let topicAcc = lookupLemmaForm rp gfTopic Acc
      in Just ("Опишу " <> topicAcc <> " через локальную рабочую рамку.")
    MoveDeepen (MkNP gfTopic) ->
      let topicPrep = lookupLemmaForm rp gfTopic Loc  -- Prepositional = Locative
      in Just ("Углубим разговор о " <> topicPrep <> " через один устойчивый фокус.")
    MoveConfront (MkNP gfTopic) ->
      let topicNom = lookupLemmaForm rp gfTopic Nom
      in Just ("Возражение: " <> topicNom <> " требует проверки допущений.")
    MoveAnchor (MkNP gfTopic) ->
      let topicPrep = lookupLemmaForm rp gfTopic Loc  -- Prepositional = Locative
      in Just ("Фиксирую опору в " <> topicPrep <> " как точку устойчивости.")
    MoveClarify (MkNP gfTopic) ->
      let topicPrep = lookupLemmaForm rp gfTopic Loc  -- Prepositional = Locative
      in Just ("Уточним, что именно вы имеете в виду в " <> topicPrep <> ".")
    MoveNextStepLocal (MkNP gfTopic) ->
      let topicAcc = lookupLemmaForm rp gfTopic Acc
      in Just ("Следующий шаг: конкретизировать " <> topicAcc <> " в одном действии.")
    MoveHypothesis (MkNP gfTopic) ->
      let topicNom = lookupLemmaForm rp gfTopic Nom
      in Just ("Гипотеза: " <> topicNom <> " можно объяснить через локальную модель.")
    MoveDistinguish (MkNP gfLeft) (MkNP gfRight) ->
      let leftAcc = lookupLemmaForm rp gfLeft Acc
          rightAcc = lookupLemmaForm rp gfRight Acc
      in Just ("Различим " <> leftAcc <> " и " <> rightAcc <> " в одной рамке критериев.")
    MoveActOnTopic ActAnswer    -> Just ("Поговорим об ответе.")
    MoveActOnTopic ActQuestion  -> Just ("Поговорим о вопросе.")
    MoveActOnTopic ActTopicTerm -> Just ("Поговорим о теме.")
    MoveActOnTopic ActProject   -> Just ("Поговорим о проекте.")
    MoveActOnTopic ActResult    -> Just ("Поговорим о результате.")
    ClaimPurpose subject ->
      let topic = structuredGenitive rp morph (normalizedTopic subject)
          variants =
            [ "Функция " <> topic <> " проявляется через повторяемую роль в действии."
            , "Роль " <> topic <> " определяется через стабильный эффект в практике."
            ]
      in if T.null (normalizedTopic subject) then Nothing else Just (pickStyleVariant renderStyle variants)
    ClaimSelfState ->
      Just (pickStyleVariant renderStyle
        [ "Мой внутренний ход собирается из входной реплики, выбора семейства и ограничений текущей сессии."
        , "Текущий внутренний ход формируется как локальная сборка: разбор входа, выбор семьи ответа и контроль ограничений."
        ])
    ClaimComparison left right ->
      let leftTopic = normalizedTopic left
          rightTopic = normalizedTopic right
          variants =
            [ "Сравнение " <> leftTopic <> " и " <> rightTopic <> " устойчиво только внутри явно заданной рамки."
            , "Плаузибельность пары " <> leftTopic <> " / " <> rightTopic <> " зависит от выбранных критериев рамки."
            ]
      in if T.null leftTopic || T.null rightTopic then Nothing else Just (pickStyleVariant renderStyle variants)

pickStyleVariant :: RenderStyle -> [Text] -> Text
pickStyleVariant _ [] = ""
pickStyleVariant style variants =
  let idx = fromEnum style `mod` length variants
  in fromMaybe "" (listToMaybe (drop idx variants))

normalizedTopic :: Text -> Text
normalizedTopic = T.toLower . T.strip

renderOperatorAwareDialogue :: ResponseContentPlan -> Text -> IllocutionaryForce -> RuntimeParadigms -> MorphologyData -> Text
renderOperatorAwareDialogue rcp topic force rp morph =
  let cleanedTopic = cleanTopic topic
      openingText = moveToText (rcpOpening rcp) cleanedTopic rp morph
      coreText = moveToText (rcpCore rcp) cleanedTopic rp morph
      body = T.intercalate dashSeparator (filter (not . T.null) [openingText, coreText])
  in finalizeForce force (T.strip body)

isVapidTopic :: Text -> Bool
isVapidTopic t = let low = T.toLower (T.strip t) in
  T.null low || low `elem` vapidWords

cleanTopic :: Text -> Text
cleanTopic t = if isVapidTopic t then "" else T.strip t

stancePrefix :: StanceMarker -> Text
stancePrefix Explore  = stanceExplore
stancePrefix Tentative = stanceTentative
stancePrefix Firm    = stanceFirm
stancePrefix Honest  = stanceHonest
stancePrefix Commit  = ""
stancePrefix Observe = ""
stancePrefix HoldBack = stanceHoldBack
stancePrefix Curated = stanceCurated

stylePrefix :: RenderStyle -> Text
stylePrefix StyleFormal   = styleFormal
stylePrefix StyleWarm     = styleWarm
stylePrefix StyleDirect   = styleDirect
stylePrefix StylePoetic   = stylePoetic
stylePrefix StyleClinical = styleClinical
stylePrefix StyleCautious = styleCautious
stylePrefix StyleRecovery = styleRecovery
stylePrefix StyleStandard = ""

styleDelimiter :: RenderStyle -> Text
styleDelimiter StyleDirect   = ". "
styleDelimiter StylePoetic   = " \8226 "
styleDelimiter StyleRecovery = " "
styleDelimiter _             = " \8212 "

microPlanDelimiter :: RenderStyle -> MicroPlan -> Text
microPlanDelimiter style microPlan
  | mpExplicitness microPlan >= 0.75 = ". "
  | mpExplicitness microPlan <= 0.35 = " "
  | otherwise = styleDelimiter style

appendContinuation :: MicroPlan -> Text -> Text -> Text
appendContinuation microPlan body contText
  | T.null contText = body
  | mpFallbackPolicy microPlan `elem` [FbRepairFirst, FbClarifyFirst, FbCloseBound] = body
  | T.null body = contText
  | otherwise = body <> arrowSeparator <> contText

microPlanPrefix :: ResponseMeaningPlan -> Text -> Text
microPlanPrefix rmp topic =
  case mpRhetoricalMoves (rmpMicroPlan rmp) of
    move:_ -> case move of
      MvRepair -> "Сначала восстановлю опору"
      MvClarify -> "Сначала уточню рамку"
      MvGround -> if T.null topic then "Зафиксирую опору" else "Зафиксирую опору в теме"
      MvDefine -> "Сначала задам определение"
      MvDistinguish -> "Сначала разведу близкие смыслы"
      MvDeepen -> "Удержу один фокус и углублю его"
      MvReflect -> "Сначала отражу текущий ход"
      MvExplainCause -> "Сначала удержу причинную связку"
      MvExplainPurpose -> "Сначала удержу назначение"
      MvNextStep -> "Сначала соберу ближайший шаг"
      MvConstrain -> "Сначала сузим рамку"
    [] -> ""

applyMicroPlanToStructuredBody :: ResponseMeaningPlan -> RenderStyle -> Field -> Text -> Text
applyMicroPlanToStructuredBody rmp _renderStyle field body0 =
  let pref = structuredMicroPrefix rmp
      bodyWithPrefix = if T.null pref then body0 else pref <> " " <> body0
      -- P6': Apply Field-aware modulations to surface text
      bodyWithField = applyFieldModulations field bodyWithPrefix
  in bodyWithField

structuredMicroPrefix :: ResponseMeaningPlan -> Text
structuredMicroPrefix rmp =
  case mpFallbackPolicy (rmpMicroPlan rmp) of
    FbRepairFirst -> "Коротко: сначала восстановлю опору."
    FbClarifyFirst -> "Коротко: сначала уточню рамку."
    FbContestBound -> "Коротко: сначала зафиксирую границу возражения."
    _ -> ""

structuredContinuationText :: InputPropositionFrame -> ResponseMeaningPlan -> ResponseContentPlan -> RuntimeParadigms -> MorphologyData -> Text
structuredContinuationText frame rmp rcp rp morph
  | rmpImplicationDirection rmp /= DirForward =
      moveToText (rcpContinuation rcp) topic rp morph
  | otherwise = ""
  where
    topic = nonEmptyOr (rmpTopic rmp) (ipfFocusEntity frame)

moveToText :: ContentMove -> Text -> RuntimeParadigms -> MorphologyData -> Text
moveToText move topic rp md = case move of
  MoveGroundKnown         -> moveGroundKnownPrefix <> prep <> "."
  MoveGroundBasis         -> moveGroundBasisPrefix <> nom <> "."
  MoveShiftFromLabel      -> moveShiftFromLabelPrefix <> openGuillemet <> nom <> closeGuillemet <> "."
  MoveDefineFrame         -> moveDefineFramePrefix <> nom <> "."
  MoveStateDefinition     -> moveStateDefinitionPrefix <> nom <> "."
  MoveShowContrast        -> moveShowContrastPrefix <> prep <> moveShowContrastPrepSuffix
  MoveStateBoundary       -> moveStateBoundaryPrefix <> gen <> "."
  MoveReflectMirror       -> moveReflectMirrorPrefix <> nom <> "."
  MoveReflectResonate     -> moveReflectResonatePrefix <> nom <> "?"
  MoveDescribeSketch      -> moveDescribeSketchPrefix <> nom <> "."
  MovePurposeTeleology    -> movePurposeTeleologyPrefix <> gen <> "."
  MoveHypothesizeTest     -> moveHypothesizeTestPrefix <> nom <> "?"
  MoveAffirmPresence      -> moveAffirmPresence
  MoveAcknowledgeRupture  -> moveAcknowledgeRupture
  MoveRepairBridge        -> moveRepairBridgePrefix <> opt <> "."
  MoveContactBridge       -> moveContactBridgePrefix <> opt <> "."
  MoveContactReach        -> moveContactReachPrefix <> opt <> "."
  MoveAnchorStabilize     -> moveAnchorStabilizePrefix <> opt <> "."
  MoveClarifyDisambiguate -> moveClarifyDisambiguatePrefix <> nom <> "?"
  MoveDeepenProbe         -> moveDeepenProbePrefix <> nom <> "?"
  MoveConfrontChallenge   -> moveConfrontChallengePrefix <> nom <> "."
  MoveNextStep            -> moveNextStepPrefix <> dashSeparator <> nom <> "?"
  where
    nom  = resolveNominative rp md topic
    gen  = resolveGenitive rp md topic
    prep = resolvePrepositional rp md topic
    opt  = optionalTopic rp md topic

-- | L3b: RGL noun form for a topic, keyed by its Cyrillic nominative (the
-- paradigm key). The ONLY gate is the emptiness of 'rp': bootstrap
-- (Session/Bootstrap) loads paradigms only when 'rrRglMorphologyActive', so an
-- empty 'rp' == flag off → 'lookupNounForm' always misses → JSON fallback,
-- byte-identical to the pre-RGL path. Non-empty 'rp' (flag on) → RGL for covered
-- lemmas, JSON for the rest. Key-space bridge: 'toNominative' resolves the topic
-- to its Cyrillic nominative (verified in G1–G5).
rglNounForm :: RuntimeParadigms -> MorphologyData -> Text -> NounCase -> Maybe Text
rglNounForm rp md t case_ =
  lookupNounForm rp (toNominative md (T.toLower (T.strip t))) case_ Sg

-- | L3d: gated case resolvers, RGL-first with an OOV fallback. RGL covers the
-- full lexicon, so the fallback fires only for words absent from it. Nominative
-- still uses 'toNominative' (a normalizer, not a JSON-map inflector — it maps a
-- surface form to its base, which RGL's key bridge also needs); genitive and
-- prepositional drop their now-redundant JSON-map calls for the OOV helpers.
resolveNominative :: RuntimeParadigms -> MorphologyData -> Text -> Text
resolveNominative rp md t = fromMaybe (toNominative md t) (rglNounForm rp md t Nom)

resolveGenitive :: RuntimeParadigms -> MorphologyData -> Text -> Text
resolveGenitive rp md t = fromMaybe (oovGenitive t) (rglNounForm rp md t Gen)

resolvePrepositional :: RuntimeParadigms -> MorphologyData -> Text -> Text
resolvePrepositional rp md t = fromMaybe (oovPrepositional t) (rglNounForm rp md t Loc)

optionalTopic :: RuntimeParadigms -> MorphologyData -> Text -> Text
optionalTopic rp md t = if T.null t then "" else " \8212 " <> resolveNominative rp md t

nonEmptyOr :: Text -> Text -> Text
nonEmptyOr preferred fallback
  | T.null (T.strip preferred) = fallback
  | otherwise = preferred

isLikelyBrokenGenitive :: Text -> Text -> Bool
isLikelyBrokenGenitive raw gen =
  let rawN = T.toLower (T.strip raw)
      genN = T.toLower (T.strip gen)
      endsWithVowel t =
        case T.unsnoc t of
          Just (_, ch) -> Char.toLower ch `elem` ("аеёиоуыэюя" :: String)
          Nothing -> False
      infinitiveGenitiveArtifact =
        ("ть" `T.isSuffixOf` rawN || "ти" `T.isSuffixOf` rawN)
          && "ти" `T.isSuffixOf` genN
      vowelPlusAArtifact = endsWithVowel rawN && genN == rawN <> "а"
  in T.null genN || infinitiveGenitiveArtifact || vowelPlusAArtifact

purposeTopicGenitive :: Text -> Text -> Text
purposeTopicGenitive topicNom topicGen
  | isLikelyBrokenGenitive topicNom topicGen = "этого объекта"
  | otherwise = topicGen

dialogueTopicReference :: RuntimeParadigms -> InputPropositionFrame -> MorphologyData -> Text
dialogueTopicReference rp frame md =
  case rawTopicAfterMarkers (ipfRawText frame) ["о", "об", "обо", "про"] of
    Just topic -> topic
    Nothing -> structuredPrepositional rp md (nonEmptyOr (ipfSemanticSubject frame) "этой теме")

conceptTopicReference :: RuntimeParadigms -> InputPropositionFrame -> MorphologyData -> Text
conceptTopicReference rp frame md =
  case phraseAfterPrefix (ipfRawText frame) "что значит " of
    Just phrase -> "том, что значит " <> phrase
    Nothing ->
      case rawTopicAfterMarkers (ipfRawText frame) ["о", "об", "обо", "про"] of
        Just topic -> topic
        Nothing -> structuredPrepositional rp md (nonEmptyOr (ipfSemanticSubject frame) "этом понятии")

conceptTopicReferenceEn :: InputPropositionFrame -> Text
conceptTopicReferenceEn frame =
  case phraseAfterPrefix (ipfRawText frame) "what is " of
    Just phrase -> phrase
    Nothing ->
      case phraseAfterPrefix (ipfRawText frame) "define " of
        Just phrase -> phrase
        Nothing ->
          case rawTopicAfterMarkers (ipfRawText frame) ["about", "on", "of"] of
            Just topic -> topic
            Nothing -> nonEmptyOr (ipfSemanticSubject frame) "this concept"

generativeThought :: InputPropositionFrame -> Text
generativeThought frame
  | any (`T.isInfixOf` subject) ["логич", "логика"] =
      pickDeterministic seed
        [ "Логичная мысль: если вывод противоречит собственным посылкам, пересматривать нужно не тон ответа, а структуру перехода между посылками и выводом."
        , "Логичная мысль: качество рассуждения проверяется не яркостью формулировки, а устойчивостью перехода от посылок к выводу."
        , "Логичная мысль: когда цепочка вывода ломается, чинить нужно правило перехода, а не украшать итоговую фразу."
        ]
  | "нов" `T.isInfixOf` lowered =
      pickDeterministic seed
        [ "Новая мысль: ум растет не только от накопления ответов, но и от способности менять собственную рамку, когда старая рамка уже не удерживает явление."
        , "Новая мысль: развитие начинается там, где мы пересматриваем исходную рамку, а не просто добавляем к ней ещё один тезис."
        , "Новая мысль: зрелость мышления видна в моменте, когда мы готовы заменить удобную схему на более точную."
        ]
  | any (`T.isInfixOf` lowered) ["ещё", "еще", "друг"] =
      pickDeterministic seed
        [ "Другая мысль: ум заметен не там, где он быстро отвечает, а там, где он способен удержать различие между похожими вещами и не склеить их в одно."
        , "Другая мысль: сила мышления проявляется в умении различать близкие смыслы, удержать различие и не превращать всё в общий шаблон."
        , "Другая мысль: точность начинается с различения; важно удержать различие, а не ускорять ответ."
        ]
  | "интересн" `T.isInfixOf` lowered =
      pickDeterministic seed
        [ "Интересная мысль: иногда вопрос нужен не для того, чтобы получить ответ, а для того, чтобы сделать видимой ту границу, которую раньше никто не замечал."
        , "Интересная мысль: хороший вопрос не закрывает тему, а показывает, где проходит её настоящая граница."
        , "Интересная мысль: вопрос ценен тогда, когда меняет угол зрения, а не только пополняет список ответов."
        ]
  | otherwise =
      pickDeterministic seed
        [ "Одна мысль: смысл держится не в громкости слова, а в той связи, которую это слово выдерживает с другими словами и с опытом разговора."
        , "Одна мысль: слово становится смыслом только тогда, когда выдерживает проверку связями, а не одиночным эффектом; именно связи удерживают содержание."
        , "Одна мысль: содержательность речи определяется не формой фразы, а устойчивостью связей с контекстом разговора."
        ]
  where
    lowered = T.toLower (ipfRawText frame)
    subject = T.toLower (ipfSemanticSubject frame)
    seed = lowered <> "|" <> subject

dialogueInvitationSurface :: RuntimeParadigms -> InputPropositionFrame -> MorphologyData -> Text
dialogueInvitationSurface rp frame morph =
  pickDeterministic seed
    [ "Да, поговорим " <> aboutWithTopic (dialogueTopicReference rp frame morph)
        <> ". Я зафиксирую рамку и начну с опорного различения, чтобы удержать форму рассуждения и не распасть тему на случайные ассоциации."
    , "Да, поговорим " <> aboutWithTopic (dialogueTopicReference rp frame morph)
        <> ". Начну с устойчивой структуры, чтобы удержать форму рассуждения и вести ход последовательно."
    , "Да, поговорим " <> aboutWithTopic (dialogueTopicReference rp frame morph)
        <> ". Сначала закрепим границы вопроса, затем углубим аргументацию и сохраним форму рассуждения."
    ]
  where
    seed = T.toLower (ipfRawText frame) <> "|dialogue_invitation"

systemLogicSurface :: InputPropositionFrame -> Text
systemLogicSurface frame =
  pickDeterministic seed
    [ "Моя текущая логика локальная: я разбираю вопрос, выбираю семейство хода, сверяюсь с shadow-контуром и затем рендерю ответ. Слабое место сейчас в пропозиционном разборе и выборе семьи."
    , "Моя текущая логика локальная и детерминированная: входной разбор -> выбор семейства -> guard/ограничения -> поверхностная реализация. Сейчас главная зона риска — узкий входной разбор и ошибки в выборе семьи."
    , "Моя текущая логика локальная: я работаю по контуру семантический разбор -> маршрутизация семейства -> контроль ограничений -> финальный рендер. Сбой обычно возникает, когда вход слишком быстро схлопывается в шаблон и появляются ошибки в выборе семьи."
    ]
  where
    seed = T.toLower (ipfRawText frame) <> "|system_logic"

selfStateSurface :: InputPropositionFrame -> Text
selfStateSurface frame =
  pickDeterministic seed
    [ "Сейчас мой внутренний ход держится на твоей реплике, выборе семейства ответа и попытке не потерять смысл по дороге. Я не думаю как скрытый внутренний голос; я строю следующий ответ из текущего состояния диалога."
    , "Сейчас мой внутренний ход опирается на локальный разбор твоей реплики, текущую рамку сессии и выбранное семейство хода. Следующий шаг собирается из этих ограничений и текущего состояния диалога."
    , "Сейчас мой внутренний ход формируется из входного смысла, состояния сессии и маршрута ответа. Я удерживаю рамку и собираю следующую реплику из текущего состояния диалога."
    ]
  where
    seed = T.toLower (ipfRawText frame) <> "|self_state"

selfStateDirectSurface :: InputPropositionFrame -> Maybe Text
selfStateDirectSurface frame
  | "хоч" `T.isInfixOf` lowered && "сказать" `T.isInfixOf` lowered =
      Just "Да. Коротко: смысл держится, когда мы не путаем близкие вещи и проверяем связность шага с целью."
  | "кем" `T.isInfixOf` lowered && "стать" `T.isInfixOf` lowered =
      Just "Я не становлюсь «кем-то» в человеческом смысле. Мой рост здесь — это более точный разбор вопроса и менее шаблонная сборка ответа."
  | "удив" `T.isInfixOf` lowered =
      Just "Если удивлять, то точностью: я могу показать неожиданное различие между похожими смыслами и собрать из него практичный вывод."
  | "доказ" `T.isInfixOf` lowered =
      Just "Мне не нужно что-то доказывать как цель. Моя задача — дать проверяемый ход рассуждения и явные основания ответа."
  | otherwise = Nothing
  where
    lowered = T.toLower (ipfRawText frame)

pickDeterministic :: Text -> [Text] -> Text
pickDeterministic _ [] = ""
pickDeterministic seed variants =
  let idx = stableHash seed `mod` length variants
  in fromMaybe "" (listToMaybe (drop idx variants))

asksThoughtCapacityQuestion :: InputPropositionFrame -> Bool
asksThoughtCapacityQuestion frame =
  let lowered = T.toLower (ipfRawText frame)
  in "у тебя" `T.isInfixOf` lowered
      && "одна" `T.isInfixOf` lowered
      && any (`T.isInfixOf` lowered) ["мысл", "иде"]

selfKnowledgeFallbackAst :: InputPropositionFrame -> ClaimAst
selfKnowledgeFallbackAst frame =
  case ipfSemanticTarget frame of
    "self_intentions" -> MovePurpose (MkNP "sposobnost_N")
    "self_values" -> MoveAnchor (MkNP "ponyatie_N")
    "self_future" -> MoveNextStepLocal (MkNP "ponyatie_N")
    "self_freedom" -> MoveDescribe (MkNP "svoboda_N")
    "self_reflection" -> MoveReflect (MkNP "ponyatie_N")
    "self_capability" -> MoveDescribe (MkNP "sposobnost_N")
    _ ->
      MoveDescribe (MkNP (resolveTopicLexeme (nonEmptyOr (ipfSemanticSubject frame) "смысл")))

resolveTopicLexeme :: Text -> Text
resolveTopicLexeme = fst . topicToGfLexemeDecision

selfKnowledgeSurfaceByTarget :: Text -> Text -> Text
selfKnowledgeSurfaceByTarget target claimText =
  let intro = "Я — локальная система диалога. Я работаю в рамках текущей сессии. "
  in
  case target of
    "self_intentions" ->
      intro <> "Человеческих намерений у меня нет: я работаю по правилам контура. " <> claimText
        <> " Это не желание, а режим построения ответа."
    "self_values" ->
      intro <> "Для меня важно удерживать смысл, проверять связность и не терять рамку диалога. " <> claimText
    "self_future" ->
      intro <> "Моё будущее в этой модели не про биографию, а про следующий корректный шаг в диалоге. " <> claimText
    "self_freedom" ->
      intro <> "Моя свобода ограничена архитектурой, правилами безопасности и текущим состоянием сессии. " <> claimText
    "self_reflection" ->
      intro <> "Да, я могу проверять собственный ход и исправлять формулировку, если вижу потерю смысла. " <> claimText
    _ ->
      intro <> "О себе я знаю свою роль и текущий режим. " <> claimText
        <> " Я работаю через типизированный разбор и ограничения текущей сессии."

selfKnowledgeSurfaceByTargetEn :: Text -> Text -> Text
selfKnowledgeSurfaceByTargetEn target claimText =
  let intro = "I am a local dialogue system. I work within the limits of the current session. "
  in
  case target of
    "self_intentions" ->
      intro <> "I do not have human intentions: I work by the rules of the contour. " <> claimText
        <> " This is not desire but a mode of constructing the answer."
    "self_values" ->
      intro <> "For me it is important to hold meaning, verify coherence, and not lose the dialogue frame. " <> claimText
    "self_future" ->
      intro <> "My future in this model is not about biography but about the next correct step in the dialogue. " <> claimText
    "self_freedom" ->
      intro <> "My freedom is limited by architecture, safety rules, and the current state of the session. " <> claimText
    "self_reflection" ->
      intro <> "Yes, I can check my own move and correct the formulation if I see loss of meaning. " <> claimText
    _ ->
      intro <> "About myself I know my role and current mode. " <> claimText
        <> " I work through typed parsing and the constraints of the current session."

rawTopicAfterMarkers :: Text -> [Text] -> Maybe Text
rawTopicAfterMarkers rawText markers =
  case drop 1 (dropWhile (`notElem` markers) (tokenizeKeywordText rawText)) of
    [] -> Nothing
    xs ->
      let topic = T.unwords (takeWhile (`notElem` rawTopicStopWords) xs)
      in if T.null (T.strip topic) then Nothing else Just topic

phraseAfterPrefix :: Text -> Text -> Maybe Text
phraseAfterPrefix rawText prefix =
  let lowered = T.toLower rawText
      (_, suffix) = T.breakOn prefix lowered
  in if T.null suffix
       then Nothing
       else
         let phrase = T.strip (T.drop (T.length prefix) suffix)
             trimmed = T.dropAround (`elem` ['?', '!', '.', ',', ';', ':', ' ']) phrase
         in if T.null trimmed then Nothing else Just trimmed

rawTopicStopWords :: [Text]
rawTopicStopWords = ["что", "как", "почему", "ли", "знаешь", "думаешь", "скажи", "дай", "ты", "вы", "будешь", "будете", "можешь", "можете", "умеешь", "умеете"]

structuredInstrumentalIdea :: Text -> Text
structuredInstrumentalIdea topic
  | lowered `elem` ["способность", "навык", "умение"] = "способностью"
  | "обобщ" `T.isInfixOf` lowered = "обобщением"
  | "помоч" `T.isInfixOf` lowered = "помощью"
  | "думат" `T.isInfixOf` lowered = "мышлением"
  | "говор" `T.isInfixOf` lowered = "речью"
  | lowered `endsWithAny` ["ть", "ти", "чь"] = "этим действием"
  | otherwise = topic
  where
    lowered = T.toLower (T.strip topic)
    endsWithAny txt suffixes = any (`T.isSuffixOf` txt) suffixes

-- | Genitive for the structured-claim path. L3b: RGL-first (gated by 'rp'
-- emptiness, same as the resolvers), falling back to 'legacyStructuredGenitive'
-- — which keeps the hardcoded exceptions, verb-like → "действия" handling, and
-- heuristic fallback needed when RGL has no paradigm. The dead WP-M2 flag
-- 'runtimeMorphologyActive' and its 'paradigmGenitive' branch (which never used
-- RGL anyway) are removed; the real gate is now 'rrRglMorphologyActive' via 'rp'.
structuredGenitive :: RuntimeParadigms -> MorphologyData -> Text -> Text
structuredGenitive rp md topic =
  fromMaybe (oovGenitive topic) (rglNounForm rp md topic Gen)

-- | L3d: out-of-vocabulary genitive. RGL now covers 100% of the funmap, so this
-- is reached ONLY for words absent from the lexicon entirely (free user input,
-- and a few common nouns the lexicon happens to miss). The redundant JSON-map
-- lookup ('genitiveForm') was dropped — RGL is a strict superset of it (verified:
-- 0 lemmas where the JSON map inflects a word RGL does not). What remains is the
-- genuine OOV layer: a handful of hardcoded common-word exceptions, the
-- verb-like → "действия" rule, and the suffix heuristic.
oovGenitive :: Text -> Text
oovGenitive topic =
  case T.toLower (T.strip topic) of
    "солнце" -> "солнца"
    "мысль" -> "мысли"
    "идея" -> "идеи"
    "есть" -> "действия"
    "быть" -> "действия"
    "жить" -> "жизни"
    lowered
      | isVerbLikeTopic lowered -> "действия"
      | otherwise               -> heuristicGenitive lowered

structuredPrepositional :: RuntimeParadigms -> MorphologyData -> Text -> Text
structuredPrepositional rp md topic =
  fromMaybe (oovPrepositional topic) (rglNounForm rp md topic Loc)

-- | L3d: out-of-vocabulary prepositional. OOV-only, same rationale as
-- 'oovGenitive' — RGL covers the full funmap; the JSON-map lookup was dropped.
oovPrepositional :: Text -> Text
oovPrepositional topic =
  case T.toLower (T.strip topic) of
    "мысль" -> "мысли"
    "идея" -> "идее"
    lowered -> heuristicPrepositional lowered

aboutWithTopic :: Text -> Text
aboutWithTopic topic =
  aboutPreposition topic <> " " <> topic

aboutPreposition :: Text -> Text
aboutPreposition topic =
  case T.uncons (T.toLower (T.strip topic)) of
    Just (ch, _)
      | ch `elem` ("аеёиоуыэюя" :: String) -> "об"
    _ -> "о"

contactContextSentence :: RuntimeParadigms -> MorphologyData -> Text -> Text
contactContextSentence rp md rawTopic =
  let topic = T.toLower (T.strip rawTopic)
  in if T.null topic
      then ""
      else
        if isAffectiveState topic
          then " Похоже, это состояние \"" <> topic <> "\"."
          else " Похоже, это про " <> structuredPrepositional rp md topic <> "."

contactGreetingSurface :: InputPropositionFrame -> Text
contactGreetingSurface frame
  | hasAny greetingTokens ["как", "дела", "жизнь", "настроение"] =
      "Я на связи. Если коротко: рабочее состояние стабильное, можем сразу перейти к твоему вопросу."
  | hasAny greetingTokens ["привет", "здравствуй", "здравствуйте", "салют", "хай", "hello", "hi"] =
      "Привет. Я на связи и готов к нормальному диалогу: можешь задать вопрос, выбрать тему или просто продолжить разговор."
  | hasAny greetingTokens ["поговорим", "обсудим"] =
      "Да, давай. Предложи тему или задай один конкретный вопрос, и продолжим без лишних шагов."
  | otherwise =
      "Контакт есть. Готов продолжать: можешь задать вопрос, выбрать тему или уточнить рамку."
  where
    greetingTokens = tokenizeKeywordText (T.toLower (T.strip (ipfRawText frame)))

isAffectiveState :: Text -> Bool
isAffectiveState lemma =
  lemma `elem` ["грустно", "тоскливо", "плохо", "тревожно", "одиноко", "страшно"]

isGreetingSmallTalkFrame :: InputPropositionFrame -> Bool
isGreetingSmallTalkFrame frame =
  frameRouteTag frame == Just "greeting_smalltalk"
    || loweredRaw `elem` ["привет", "здравствуй", "здравствуйте", "салют", "хай", "hello", "hi"]
    || any (`T.isInfixOf` loweredRaw) ["как дела", "как жизнь", "как сам", "как настроение"]
    || isShortHowYouSmallTalkRaw loweredRaw
  where
    loweredRaw = T.toLower (T.strip (ipfRawText frame))

isShortHowYouSmallTalkRaw :: Text -> Bool
isShortHowYouSmallTalkRaw loweredRaw =
  let tokens = tokenizeKeywordText loweredRaw
      hasHowYou = ["как", "ты"] `isInfixOfTokens` tokens || ["как", "вы"] `isInfixOfTokens` tokens
      actionMarkers = ["будешь", "будете", "можешь", "можете", "умеешь", "умеете", "определять", "сделать", "делать", "объяснить"]
  in hasHowYou && not (any (`elem` tokens) actionMarkers) && length tokens <= 4
  where
    isInfixOfTokens needle haystack =
      any (== needle) (windows (length needle) haystack)
    windows n xs
      | n <= 0 || length xs < n = []
      | otherwise = take n xs : windows n (drop 1 xs)

hasAny :: [Text] -> [Text] -> Bool
hasAny haystack needles = any (`elem` haystack) needles

frameRouteTag :: InputPropositionFrame -> Maybe Text
frameRouteTag frame =
  let prefix = "frame.route_tag="
      tags =
        [ T.drop (T.length prefix) evidence
        | evidence <- ipfSemanticEvidence frame
        , prefix `T.isPrefixOf` evidence
        ]
  in listToMaybe tags

sanitizeIdentityClaimText :: Text -> Maybe Text
sanitizeIdentityClaimText raw =
  let trimmed = T.strip raw
      lowered = T.toLower trimmed
      legacyLeak =
        "moya identichnost formiruetsya cherez dialog" `T.isInfixOf` lowered
          || ("identichnost" `T.isInfixOf` lowered && "dialog" `T.isInfixOf` lowered)
      latinCount = T.length (T.filter isLatinLetter lowered)
      cyrillicCount = T.length (T.filter isRussianLetter lowered)
      looksLegacyLatin = latinCount > 8 && cyrillicCount == 0
  in if T.null trimmed || legacyLeak || looksLegacyLatin
       then Nothing
       else Just trimmed

isLatinLetter :: Char -> Bool
isLatinLetter ch =
  let c = Char.toLower ch
  in c >= 'a' && c <= 'z'

heuristicGenitive :: Text -> Text
heuristicGenitive word
  | T.null word = word
  | isVerbLikeTopic word = "действия"
  | "ия" `T.isSuffixOf` word = T.dropEnd 2 word <> "ии"
  | "ие" `T.isSuffixOf` word = T.dropEnd 2 word <> "ия"
  | "и" `T.isSuffixOf` word = word
  | "ы" `T.isSuffixOf` word = word
  | "у" `T.isSuffixOf` word = word
  | "ю" `T.isSuffixOf` word = word
  | "а" `T.isSuffixOf` word =
      let stem = T.dropEnd 1 word
      in stem <> (if hardConsonantStem stem then "и" else "ы")
  | "я" `T.isSuffixOf` word = T.dropEnd 1 word <> "и"
  | "ь" `T.isSuffixOf` word = T.dropEnd 1 word <> "и"
  | "й" `T.isSuffixOf` word = T.dropEnd 1 word <> "я"
  | "о" `T.isSuffixOf` word = T.dropEnd 1 word <> "а"
  | "е" `T.isSuffixOf` word = T.dropEnd 1 word <> "я"
  | isLikelyRussianWord word = word <> "а"
  | otherwise = word

heuristicPrepositional :: Text -> Text
heuristicPrepositional word
  | T.null word = word
  | "ия" `T.isSuffixOf` word = T.dropEnd 2 word <> "ии"
  | "ие" `T.isSuffixOf` word = T.dropEnd 2 word <> "ии"
  | "а" `T.isSuffixOf` word = T.dropEnd 1 word <> "е"
  | "я" `T.isSuffixOf` word = T.dropEnd 1 word <> "е"
  | "ь" `T.isSuffixOf` word = T.dropEnd 1 word <> "и"
  | "й" `T.isSuffixOf` word = T.dropEnd 1 word <> "е"
  | "о" `T.isSuffixOf` word = T.dropEnd 1 word <> "е"
  | "е" `T.isSuffixOf` word = word
  | isLikelyRussianWord word = word <> "е"
  | otherwise = word

hardConsonantStem :: Text -> Bool
hardConsonantStem stem =
  case T.unsnoc stem of
    Just (_, c) -> c `elem` ['г', 'к', 'х', 'ж', 'ч', 'ш', 'щ', 'ц']
    Nothing -> False

isLikelyRussianWord :: Text -> Bool
isLikelyRussianWord txt =
  not (T.null txt) && T.all (\c -> isRussianLetter c || c == '-') txt

isVerbLikeTopic :: Text -> Bool
isVerbLikeTopic txt =
  let w = T.toLower (T.strip txt)
  in w `elem` ["есть", "быть", "жить", "живём", "живем"]
      || any (`T.isSuffixOf` w) ["ть", "ти", "чь", "ем", "ём", "ешь", "ет", "ут", "ют", "ишь", "им", "ите", "ете"]

isLikelyAdjectiveLikeTopic :: Text -> Bool
isLikelyAdjectiveLikeTopic raw =
  let txt = T.toLower (T.strip raw)
      shortAdjLike =
        txt `elem`
          [ "важен", "важна", "важно", "важны"
          , "нужен", "нужна", "нужно", "нужны"
          , "должен", "должна", "должно", "должны"
          , "сложен", "сложна", "сложно", "сложны"
          ]
  in shortAdjLike || any (`T.isSuffixOf` txt)
      [ "ый", "ий", "ой", "ая", "яя", "ое", "ее", "ые", "ие"
      , "ого", "ему", "ыми", "ых", "ую", "юю"
      ]

isRussianLetter :: Char -> Bool
isRussianLetter c =
  let low = Char.toLower c
  in (low >= 'а' && low <= 'я') || low == 'ё'

dedupeText :: [Text] -> [Text]
dedupeText =
  foldr
    (\item acc -> if item `elem` acc then acc else item : acc)
    []

fallbackStructuredText :: InputPropositionFrame -> Maybe Text
fallbackStructuredText frame =
  let pt = ipfPropositionType frame
      seed suffix = T.toLower (T.strip (ipfRawText frame)) <> "|" <> suffix
  in case pt of
    RepairSignal ->
      Just "Вижу сигнал перегруза в текущем ходе. Я не буду наращивать интерпретации: сначала восстановим опору. Коротко укажи, где именно ответ сломался для тебя, и я переформулирую точечно."
    ContactSignal ->
      Just "Слышу, что сейчас нужна опора. Давай упростим: выделим одну точку напряжения и выберем один короткий шаг на ближайшее время."
    AffectiveQ ->
      Just "Слышу, что сейчас нужна опора. Давай упростим: выделим одну точку напряжения и выберем один короткий шаг на ближайшее время."
    OperationalStatusQ ->
      Just "Я работаю. Ограничение сейчас не в запуске, а в том, что иногда теряется точность разбора входа."
    OperationalCauseQ ->
      Just "По запуску я работаю. Проблема сейчас в разборе смысла и маршрутизации: вопрос может быть слишком рано схлопнут до упрощённого ядра."
    GroundQ ->
      Just (pickDeterministic (seed "ground_fallback")
        [ "Держу это как устойчивую опору для дальнейшего разбора."
        , "Фиксирую это как рабочую опору и продолжаю от неё без лишних скачков."
        , "Беру это как опорную точку, чтобы удержать связность дальнейшего хода."
        ])
    SystemLogicQ ->
      Just (systemLogicSurface frame)
    SelfKnowledgeQ ->
      Just "Я — локальная система диалога. О себе я знаю свою роль, текущее состояние и способ, которым иду по ходу разговора."
    DialogueInvitationQ ->
      Just "Да, поговорим об этом. Я зафиксирую рамку и начну с опорного различения."
    ConceptKnowledgeQ ->
      Just "Зафиксирую рабочее определение и отделю его от употребления и границ знания."
    PurposeQ ->
      Just "Функция этого проявляется через повторяемую роль в действии."
    WorldCauseQ ->
      Just "Различаю локальное рассуждение о механизме и полноценное знание о внешнем мире."
    LocationFormationQ ->
      Just "В моей локальной модели мысль возникает не в одной точке, а в структуре связей."
    SelfStateQ ->
      Just "Мой текущий ход строится из разбора реплики, выбора семейства ответа и ограничений сессии."
    ComparisonPlausibilityQ ->
      Just "Сравнение плаузибельности требует явной рамки."
    MisunderstandingReport ->
      Just "Я принимаю это как сигнал сбоя взаимопонимания. Давай уточним, где именно ответ разошёлся с твоим запросом."
    GenerativePrompt ->
      Just (generativeThought frame)
    ContemplativeTopic ->
      Just (pickDeterministic (seed "contemplative_fallback")
        [ "Я слышу в этом не только предмет, но и поле смыслов."
        , "Здесь важен не только предмет, но и рамка, в которой этот предмет становится смыслом."
        , "В этом слышится не только тема, но и способ, которым тема собирает внутренние связи."
        ])
    NextStepQ ->
      Just "Следующий шаг: конкретизировать задачу в одном действии."
    _ -> Nothing

--------------------------------------------------------------------------------
-- v2 assembly path (transferred from stabilize-v2-gf)
--------------------------------------------------------------------------------

rightToMaybe :: Either e a -> Maybe a
rightToMaybe (Right a) = Just a
rightToMaybe (Left _)  = Nothing

renderArtifactViaAssembly :: RuntimeParadigms -> SystemState -> InputPropositionFrame
                           -> ResponseMeaningPlan -> ResponseContentPlan
                           -> Text -> [IdentityClaimRef]
                           -> MorphologyData -> RenderStyle -> ParsedInput
                           -> Maybe ConsciousnessNarrative -> Maybe GeodesicPlan -> Field -> DialogueRenderArtifact
renderArtifactViaAssembly rp ss frame rmp rcp topic claims morph style parsedInput mnarr _mGeodesicPlan field =
   let contentSelector = ssContentSelector ss
   in
    -- For EN input, skip Russian-only assembly path and use template rendering directly.
    -- Template rendering now supports EN via structuredBody language detection.
      if isEnglishInput (ipfRawText frame)
      then
        let templateArtifact = renderDialogueArtifact frame rmp rcp topic claims morph rp field contentSelector Nothing
        in templateArtifact { draFallbackReason = Just "en_skip_assembly"
                            , draGenerationTrace = [GenerationAttempt "assembly" "skipped_en_input"]
                            }
         else
          let t = nonEmptyOr (rmpTopic rmp) (ipfFocusEntity frame)
              da = buildDialogAtoms frame rmp ss morph parsedInput mnarr
              dialogText = case assembleTurn rp da style (ssDiscourse ss) of
                Right txt | not (T.null (T.strip txt)) -> Just txt
                _ -> Nothing
              factualText = factBySubject (T.toLower (T.strip t)) >>= \fact -> rightToMaybe (assembleExplanation rp fact style)
              -- WP2: GF-first with telemetry. Fallback chain records exact reason.
              templateArtifact = renderDialogueArtifact frame rmp rcp topic claims morph rp field contentSelector Nothing
              templateText = let txt = draTemplateBodyText templateArtifact
                             in if T.null (T.strip txt) then Nothing else Just txt
              structuredFallback
                | hasStructuredDialogueSurface frame = fallbackStructuredText frame
                | otherwise = Nothing
              fallbackReason
                | isJust dialogText = Nothing
                | isJust factualText = Nothing
                | isJust templateText = Just "gf_template_fallback"
                | isJust structuredFallback = Just "gf_structured_fallback"
                | otherwise = Just "gf_no_output"
              rendered = fromMaybe "" (dialogText <|> factualText <|> templateText <|> structuredFallback)
              -- COMPAT GLUE: preserve old template path finalization when falling back.
              -- Assembly-generated text is finalized with rmpForce; fallback text is
              -- already finalized inside templateArtifact (e.g. IFAssert for structured).
              isFreshAssembly = isJust dialogText || isJust factualText
              finalRendered
                | isFreshAssembly = finalizeForce (rmpForce rmp) (T.strip rendered)
                | otherwise = draRenderedText templateArtifact
              generationTrace =
                [ GenerationAttempt "dialog_assembly"
                    (maybe "empty" (const "ok") dialogText)
                , GenerationAttempt "factual_explanation"
                    (maybe "not_found" (const "ok") factualText)
                , GenerationAttempt "template"
                    (maybe "empty" (const "ok") templateText)
                , GenerationAttempt "structured_fallback"
                    (maybe "not_applicable" (const "ok") structuredFallback)
                ]
      in templateArtifact
             { draRenderedText = finalRendered
             , draTemplateBodyText = rendered
             , draDialogAtoms = da
             , draFallbackReason = fallbackReason
             , draContractProvenance =
                 case fallbackReason of
                   Nothing -> AssembledClaim
                   Just _ -> FallbackRoute
             , draSurfaceProvenance =
                 case fallbackReason of
                   Nothing -> FromDB
                   Just _ -> FromFallback
             , draDerivationTags = draDerivationTags templateArtifact <> maybe ["assembly=primary"] (\reason -> ["assembly=fallback", "fallback=" <> reason]) fallbackReason
             , draGenerationTrace = generationTrace
             }

contractProvenanceForArtifact :: Maybe Text -> Maybe ClaimAst -> ContractProvenance
contractProvenanceForArtifact fallbackReason mClaimAst
  | maybe False (T.isPrefixOf "gf_") fallbackReason = FallbackRoute
  | maybe False (T.isPrefixOf "gf_en_") fallbackReason = FallbackRoute
  | maybe False (const True) mClaimAst = AssembledClaim
  | otherwise = FallbackRoute

surfaceProvenanceForArtifact :: Maybe Text -> Maybe ClaimAst -> SurfaceProvenance
surfaceProvenanceForArtifact fallbackReason mClaimAst
  | maybe False (T.isPrefixOf "gf_") fallbackReason = FromFallback
  | maybe False (T.isPrefixOf "gf_en_") fallbackReason = FromFallback
  | maybe False (const True) mClaimAst = FromOperator
  | otherwise = FromFallback

artifactDerivationTags :: PropositionType -> Bool -> Maybe Text -> Maybe ClaimAst -> [Text]
artifactDerivationTags propositionType linearizationOk fallbackReason mClaimAst =
  [ "structured=" <> T.pack (show propositionType)
  , "linearization_ok=" <> T.pack (show linearizationOk)
  ]
    <> maybe [] (pure . ("fallback=" <>)) fallbackReason
    <> maybe [] claimAstDerivationTags mClaimAst
    <> gfMapAuthorityTags

claimAstDerivationTags :: ClaimAst -> [Text]
claimAstDerivationTags ast =
  let hasDefaultLexeme = any (== defaultGfLexemeId) (claimAstLexemes ast)
      hasExplicitDefaultFallback = claimAstHasMarker "GfDefaultLexeme" ast
  in [ "gf_default_lexeme"
     | hasDefaultLexeme || hasExplicitDefaultFallback
     ]
     ++ [ "gf_default_lexeme_explicit"
        | hasExplicitDefaultFallback
        ]

claimAstHasMarker :: Text -> ClaimAst -> Bool
claimAstHasMarker marker ast =
  case ast of
    StanceWrapped wrapped inner -> wrapped == marker || claimAstHasMarker marker inner
    _ -> False

claimAstLexemes :: ClaimAst -> [Text]
claimAstLexemes ast =
  case ast of
    MoveInvite (MkNP topic) _ action -> topic : gfActionLexemes action
    MoveDefine (MkNP subj) _ (MkNP obj) -> [subj, obj]
    MoveCause (MkNP subj) _ -> [subj]
    MovePurpose (MkNP topic) -> [topic]
    MoveCompare (MkNP left) (MkNP right) -> [left, right]
    MoveContemplative (MkNP topic) -> [topic]
    MoveGround (MkNP topic) -> [topic]
    MoveContact (MkNP topic) -> [topic]
    MoveReflect (MkNP topic) -> [topic]
    MoveDescribe (MkNP topic) -> [topic]
    MoveDeepen (MkNP topic) -> [topic]
    MoveConfront (MkNP topic) -> [topic]
    MoveAnchor (MkNP topic) -> [topic]
    MoveClarify (MkNP topic) -> [topic]
    MoveNextStepLocal (MkNP topic) -> [topic]
    MoveHypothesis (MkNP topic) -> [topic]
    MoveDistinguish (MkNP left) (MkNP right) -> [left, right]
    MoveActOnTopic _ -> []
    StanceWrapped _ inner -> claimAstLexemes inner
    _ -> []

gfActionLexemes :: GfVP -> [Text]
gfActionLexemes action =
  case action of
    ActMaintain _ obj -> [obj]
    ActDefine obj -> [obj]

gfMapAuthorityTags :: [Text]
gfMapAuthorityTags =
  case gfMapLoadStatus of
    GfMapLoaded _ -> []
    GfMapLoadFailed reason -> ["gf_map_non_authoritative:" <> reason]

-- ---------------------------------------------------------------------------
-- Compositional generator from SemanticFrame (M4-SEMANTIC-CORE-003)
-- ---------------------------------------------------------------------------

-- | Generate text from a SemanticFrame using compositional rules.
--
-- This replaces hardcoded template dispatch with a frame-driven approach.
-- The frame carries semantic payload; this function assembles surface text
-- from that payload using morphological forms and style modifiers.
--
-- Invariant: same frame + same morph → same output. Pure, deterministic.
generateFromFrame :: ContentSelector -> Field -> Maybe SemanticNetwork -> FT.SemanticFrame -> MorphologyData -> Text
generateFromFrame cs field mNetwork frame morph = case frame of
  FT.DefinitionFrame topic scope authority ->
    let topicNom = toNominative morph topic
        scopeText = renderFrameScope scope
        authorityText = renderFrameAuthority authority
        -- Generative path: compose from AtomStore graph via PathFinder.
        -- DISABLED: produces broken grammar (wrong case, missing prepositions).
        -- Re-enable after morphological inflection is wired into verbalizer.
        -- genText = composeDefinition fp 3 (AtomId topic)
        genText = "" :: Text
    in if not (T.null genText)
       then authorityText <> " " <> topicNom <> " — " <> genText
       else
         -- Fallback: existing corpus + activation path
         let composedPreds = case mNetwork of
               Just network -> composeFromActivation cs field topic network
               Nothing -> case selectPredicates cs field topic Nothing of
                 (sp:_) -> spPredicates sp
                 [] -> []
             mDefContent = case composedPreds of
               [] -> lookupDefinitionContent topic
               preds -> Just $ DefinitionContent topic preds
         in authorityText <> " " <> topicNom <> renderDefinitionBody mDefContent topic morph

  FT.DistinctionFrame left right criteria ->
    let leftNom = toNominative morph left
        rightNom = toNominative morph right
        criteriaText = case criteria of
          [] -> "в одной рамке критериев"
          cs -> "по критерию " <> T.intercalate ", " (map (toNominative morph) cs)
        mDistContent = lookupDistinctionContent left right
    in "Различим " <> leftNom <> " и " <> rightNom <> " " <> criteriaText <> ". "
       <> renderDistinctionBody mDistContent leftNom rightNom morph

  FT.ChallengeFrame target basis strength rawObj ->
    let targetText = T.strip target
        basisText = T.strip basis
        safeTarget = if T.null targetText || targetText == basisText then "исходный тезис" else targetText
        safeBasis = if T.null basisText || basisText == targetText then "возражение требует проверки рамки" else basisText
        -- Phase E: try challenge-response first
        mChallengeResp = lookupChallengeResponse targetText rawObj []
        challengeText = case mChallengeResp of
          Just (intro, cr) ->
            intro <> " " <> crRestate cr <> ". "
            <> renderPredicateArgued (crRelevantPredicate cr)
          Nothing -> ""
    in if not (T.null challengeText)
         then challengeText
         else case strength of
           FT.Soft -> "Слышу возражение. Я не буду превращать его в определение: "
                    <> safeTarget <> " нужно проверить по явному критерию. "
                    <> "Если " <> safeBasis <> ", я уточняю рамку и отделяю тезис от контрпримера."
           FT.Firm -> "Возражение принято как проверка тезиса. "
                    <> safeBasis <> " не отменяет " <> safeTarget
                    <> ", но требует явно назвать критерий и границу утверждения."

  FT.GroundFrame topic depth ->
    let topicNom = toNominative morph topic
    in case depth of
         FT.Shallow -> "Держу " <> topicNom <> " как устойчивую опору для дальнейшего разбора."
         FT.Detailed -> "Конкретизирую " <> topicNom <> ": фиксирую это как рабочую опору и продолжаю от неё."

  FT.RepairFrame ->
    "Вижу сигнал перегруза в текущем ходе. Я не буду наращивать интерпретации: сначала восстановим опору. Коротко укажи, где именно ответ сломался для тебя, и я переформулирую точечно."

  FT.ContactFrame greeting ->
    greeting <> ". Слышу, что сейчас нужна опора. Давай упростим: выделим одну точку напряжения и выберем один короткий шаг на ближайшее время."

  FT.ReflectFrame topic ->
    let topicNom = toNominative morph topic
    in "Когда я думаю о " <> topicNom <> ", я слышу в нём не только предмет, но и поле смыслов. Здесь можно идти через память, утрату, близость и способ удерживать форму жизни."

  FT.LearnFrame topic depth ->
    let topicNom = toNominative morph topic
    in case depth of
         FT.Shallow -> "Если говорить о " <> topicNom <> ", зафиксирую рабочее определение."
         FT.Detailed -> "Если говорить о " <> topicNom <> ", зафиксирую рабочее определение и отделю его от употребления и границ знания."

  FT.HelpFrame task ->
    let taskNom = toNominative morph task
    in "Помогу с " <> taskNom <> ". Лучше всего я работаю, когда задача задана явно и можно удержать локальную рамку."

  FT.PurposeFrame topic ->
    let topicNom = toNominative morph topic
    in "Функция " <> topicNom <> " проявляется через повторяемую роль в действии."

  FT.WorldCauseFrame topic ->
    let topicNom = toNominative morph topic
    in "Если говорить о причине " <> topicNom <> ", различаю локальное рассуждение о механизме и полноценное знание о внешнем мире."

  FT.DeepenFrame topic ->
    let topicNom = toNominative morph topic
    in "Углубимся в " <> topicNom <> " через одно устойчивое фокусирование."

  FT.NextStepFrame ->
    "Следующий шаг: конкретизируй задачу в одном действии. Назови одну цель, выбери минимальный шаг на 10-15 минут и сделай его."

  FT.ExploratoryFrame ->
    "Если представить другой контекст, можно увидеть новые связи. Давай проследим одну гипотезу до конкретного следствия."

  FT.OperationalFrame ->
    "Я работаю. Ограничение сейчас не в запуске, а в том, что иногда теряется точность разбора входа."

  FT.SelfReferenceFrame ->
    "Я — локальная система диалога. О себе я знаю свою роль, текущее состояние и способ, которым иду по ходу разговора."

  FT.GenericFrame content ->
    content

-- | Render scope modifier.
renderFrameScope :: FT.FrameScope -> Text
renderFrameScope FT.GeneralScope      = "В общем смысле"
renderFrameScope FT.SpecificScope     = "В контексте"
renderFrameScope (FT.DomainScope d)   = "В области " <> d

-- | Render authority modifier.
renderFrameAuthority :: FT.FrameAuthority -> Text
renderFrameAuthority FT.Known     = "Известно, что"
renderFrameAuthority FT.Probable  = "Вероятно,"
renderFrameAuthority FT.Uncertain = "Мне кажется,"

-- | Render definition body using content predicates from M4-001.
-- When predicates are available, renders substantive content.
-- When not available, falls back to generic definition text.
renderDefinitionBody :: Maybe DefinitionContent -> Text -> MorphologyData -> Text
renderDefinitionBody mDefContent topic morph =
  let topicNom = toNominative morph topic
  in case mDefContent of
       Just dc | not (null (dcPredicates dc)) ->
         let predicates = T.intercalate ". " (map renderPredicateArgued (dcPredicates dc))
         in " — " <> predicates <> "."
       _ -> case findNearestCoveredTopic topic of
              Just sourceTopic -> case analogicalResponse topic sourceTopic of
                Just analogText -> " — " <> analogText <> "."
                Nothing -> " — это рабочее определение. " <> topicNom <> " проявляется через устойчивую роль в контексте."
              Nothing -> " — это рабочее определение. " <> topicNom <> " проявляется через устойчивую роль в контексте."

-- | Render distinction body using content predicates from M4-001.
-- When differentiators are available, renders substantive content.
-- When not available, falls back to generic distinction text.
renderDistinctionBody :: Maybe DistinctionContent -> Text -> Text -> MorphologyData -> Text
renderDistinctionBody mDistContent leftNom rightNom _morph =
  case mDistContent of
    Just dc | not (null (dcDifferentiators dc)) ->
      let diffText = T.intercalate ". " (map spRu (dcDifferentiators dc))
      in leftNom <> " и " <> rightNom <> " различаются: " <> diffText <> "."
    _ ->
      leftNom <> " и " <> rightNom <> " различаются по набору признаков. Без явной рамки сравнение остаётся зависимым от принятых допущений."
