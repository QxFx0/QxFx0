{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

{-|
Description : observer — Route-stage rendering plan, effect resolution, and artifact assembly. -}
module QxFx0.Core.TurnPipeline.Route.Render
  ( RenderStatic(..)
  , LocalRecoveryPlan(..)
  , RenderEffectPlan(..)
  , RenderEffectResults(..)
  , planRenderEffects
  , planRenderEffectsForRuntime
  , resolveRenderEffects
  , buildTurnArtifacts
  , renderAnomalySurface
  , isTopicNoisyOrAmbiguous
  ) where

import QxFx0.Types
import QxFx0.Types.Anomaly (AnomalySurface(..))
import QxFx0.Types.PropositionType (PropositionType(..))
import QxFx0.Types.Domain.Atoms (MorphologyData(..), AtomSet(..), MeaningAtom(..))
import Data.Maybe (isJust, isNothing)
import qualified Data.Map.Strict as Data.Map
import qualified Data.Set as Set
import QxFx0.Core.TurnPipeline.Types
import QxFx0.Core.TurnPipeline.Effects
  ( TurnEffectRequest(..)
  , TurnEffectResult(..)
  )
import QxFx0.Core.Intuition (IntuitiveFlash(..))
import QxFx0.Core.PipelineIO
  ( PipelineIO
  , PipelineRuntimeMode(..)
  , scheduleTurnEffects
  , resolveTurnEffect
  )
import QxFx0.Core.ConsciousnessLoop (ConsciousnessLoop(..))
import QxFx0.Core.StanceClassifier (ConsciousnessNarrative(..))
import qualified QxFx0.Core.Guard as Guard
import QxFx0.Core.BackgroundProcess (surfacingToFragment)
import QxFx0.Core.Observability
import QxFx0.Core.TruthContract (truthContractRebindRenderedText)
import QxFx0.Core.TurnLegitimacy (finalizeOutput)
import QxFx0.Core.TurnPlanning (integrateIdentityClaims)
import QxFx0.Core.TurnRender
  ( renderAnchorPrefix
  , renderPrincipledPrefix
  , renderStylePrefix
  , snapshotIdentitySignal
  )
import QxFx0.Core.TopicTransition (geodesicRouter)
import QxFx0.Self.Conatus (ConatusGradient(..), ceScalar, computeConatusGradient)
import QxFx0.Learning.Need (LearningNeed(..), LearningNeedState(..))
import QxFx0.Learning.Tool (ExternalTool(..), ToolDomain(..), selectToolWithReliability, defaultAvailableTools, updateToolReliability)
import QxFx0.Learning.Guardrails
  ( ExternalActionDecision(..)
  , ExternalActionDecisionReason(..)
  , ExternalActionDecisionTrace(..)
  , ExternalActionKind(..)
  , canIssueExternalAction
  )
import QxFx0.Types.ExternalQuery (ExternalQueryError(..), ExternalQueryResponse)
import qualified QxFx0.Learning.Guardrails as Guardrails
import QxFx0.Self.Blanket (computeSelfBlanket)
import QxFx0.Self.Deliberation (planRecoveryCause, delibReconciled, pickHigherSeverity)
-- import QxFx0.Self.Salience (conatusGateFires)  -- M6.1: replaced by tiConatusGateFired
import QxFx0.Semantic.Morphology (hasKnownMorphologyForm)
import QxFx0.Learning.KnowledgeTree (isTermKnownInKnowledgeTree)
import QxFx0.Semantic.Stance (selectFarthestPoint)
import QxFx0.Semantic.Content (SemanticPredicate(..))
import QxFx0.Semantic.ContentSelector.Types (ContentSelector(..))
import QxFx0.Semantic.Network.Types (SemanticNetwork(..), SemanticEdge(..), EdgeSource(..))
import System.Environment (lookupEnv)
import QxFx0.Self.Field (Field(..))
import QxFx0.Render.Dialogue
  ( DialogueRenderArtifact(..)
  , hasStructuredDialogueSurface
  , renderArtifactViaAssembly
  , renderDialogueArtifact
  , generateFromFrame
  )
import QxFx0.Semantic.Intent.Features (extractFeatures)
import QxFx0.Semantic.Intent.Classifier (SemanticIntent(..), classifyIntent, intentToFamily)
import QxFx0.Semantic.Frame.Types (SemanticFrame(..), frameTypeText)
import QxFx0.Semantic.Frame.Builder (buildFrame)
import QxFx0.Semantic.DialogAtom (emptyDialogAtoms)
import QxFx0.Semantic.Content (isCoveredTopic, lookupDefinitionContent, lookupDistinctionContent)
import QxFx0.Semantic.Analogy (findNearestCoveredTopic)
import QxFx0.Semantic.Lexicon.RuntimeParadigms (RuntimeParadigms, emptyRuntimeParadigms)
import QxFx0.Semantic.Input.Parse (emptyParsedInput)
import QxFx0.Semantic.Input.Lexicon (inputGeneratedLexiconProvenanceTag)
import QxFx0.Lexicon.GfMap (gfMapProvenanceTag)
import QxFx0.Legal.Adapter
  ( retrieveLegalFact
  , legalFactToKnowledgeFragment
  , lfSourceId
  )
import QxFx0.Types.SemanticConfig (SemanticConfig(..))
import QxFx0.Types.State.Discourse (DiscourseState(..))
import QxFx0.Types.Text (finalizeForce)
import QxFx0.Types.Thresholds (parserLowConfidenceThreshold)
import QxFx0.Types.ShadowDivergence (ShadowDivergenceSeverity(..), shadowDivergenceSeverityText)
import QxFx0.ExceptionPolicy (throwQxFx0)

import Data.Char (isAlpha, isSpace)
import Control.Concurrent.Async (forConcurrently)
import qualified Data.Foldable as F
import qualified Data.List as L
import Data.Maybe (fromMaybe, isJust)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock (UTCTime)

data RenderStatic = RenderStatic
  { rsRenderWithBg :: !Text
  , rsTemplateArtifact :: !DialogueRenderArtifact
  , rsPreferredGfLang :: !Text
  , rsResolvedAssemblyPath :: !(Maybe AssemblyPath)
  , rsResolvedAuthorityClass :: !(Maybe AuthorityClass)
  , rsArtifactManifest :: !(Maybe ArtifactManifest)
  , rsModePrefixText :: !Text
  , rsAnchorPrefixText :: !Text
  , rsNarrativeFragmentText :: !Text
  , rsSurfacingFragmentText :: !Text
  } deriving stock (Eq, Show)

semanticIntentForRender :: PropositionType -> Text -> [Text] -> MorphologyData -> SemanticIntent
semanticIntentForRender propositionType input tokens morphology =
  case propositionType of
    ConfrontQ -> IntentChallenge
    MisunderstandingReport -> IntentRepair
    RepairSignal -> IntentRepair
    _ -> classifyIntent input tokens morphology

data LocalRecoveryPlan = LocalRecoveryPlan
  { lrpCause :: !LocalRecoveryCause
  , lrpStrategy :: !LocalRecoveryStrategy
  , lrpEvidence :: ![Text]
  , lrpSurface :: !Text
  } deriving stock (Eq, Show)

data RenderEffectPlan = RenderEffectPlan
  { repRenderStatic :: !RenderStatic
  , repTurnInput :: !TurnInput
  , repLocalRecoveryPlan :: !(Maybe LocalRecoveryPlan)
  , repRenderMorphologyWarning :: !(Maybe Text)
  , repKnowledgeTopic :: !Text
  , repExternalQueryRequest :: !(Maybe (ExternalTool, LearningNeed, Text))
    -- ^ Phase 8 gap closure: when a request strategy is chosen,
    --   this field carries the tool, need, and query text for the
    --   external query effect.  'Nothing' means no request strategy.
  , repExploratoryQueryRequest :: !(Maybe (ExternalTool, LearningNeed, Text))
    -- ^ Phase 9: autonomous exploratory learning query.  When the
    --   system decides to explore autonomously (learning need active,
    --   guardrails allow, no request-driven query already planned),
    --   this field carries the exploratory query.  'Nothing' means
    --   no autonomous exploration this turn.
  , repExternalQuerySkipReason :: !(Maybe Text)
    -- ^ WP3 dedup telemetry: reason why external query was skipped
    --   (already_known_morphology / already_known_tree).
  , repExternalActionDecision :: !(Maybe ExternalActionDecision)
    -- ^ AS1: shared pre-effect decision for request/exploratory outbound actions.
  , repExternalActionDecisionTrace :: !(Maybe ExternalActionDecisionTrace)
    -- ^ AS1-03: typed reason model for allow/deny/no-action on outbound actions.
  }

data RenderTimeline = RenderTimeline
  { rtlRenderStart :: !UTCTime
  , rtlRenderEnd :: !UTCTime
  } deriving stock (Eq, Show)
data RenderEffectResults = RenderEffectResults
  { rerRenderTimeline :: !RenderTimeline
  , rerResolvedRenderStatic :: !(Maybe RenderStatic)
  , rerKnowledgeFact :: !(Maybe Text)
  , rerKnowledgeFactSource :: !(Maybe Text)
  , rerExternalQueryResult :: !(Maybe (Either ExternalQueryError ExternalQueryResponse))
    -- ^ Phase 8 gap closure: result of the external query effect
    --   when a request strategy was chosen.  'Nothing' means no
    --   request was attempted.
  , rerExploratoryQueryResult :: !(Maybe (Either ExternalQueryError ExternalQueryResponse))
    -- ^ Phase 9: result of the autonomous exploratory external query.
    --   'Nothing' means no exploratory query was attempted this turn.
  , rerExternalQuerySkipReason :: !(Maybe Text)
    -- ^ WP3 dedup telemetry: mirrors repExternalQuerySkipReason.
  , rerExternalActionDecisionTrace :: !(Maybe ExternalActionDecisionTrace)
  , rerSemanticFirstDisabled :: !Bool
    -- ^ B2 Control-A ablation: True when QXFX0_CONTROL_A_DISABLE_SEMANTIC_FIRST=1.
  }
  deriving stock (Eq, Show)

planRenderEffects :: RuntimeParadigms -> LocalRecoveryPolicy -> SystemState -> TurnInput -> TurnSignals -> TurnPlan -> RenderEffectPlan
planRenderEffects rp = planRenderEffectsForRuntimeImpl rp RuntimeStrict

-- COMPAT GLUE: old target callers expect 6-arg interface (no RuntimeParadigms).
planRenderEffectsForRuntime :: PipelineRuntimeMode -> LocalRecoveryPolicy -> SystemState -> TurnInput -> TurnSignals -> TurnPlan -> RenderEffectPlan
planRenderEffectsForRuntime = planRenderEffectsForRuntimeImpl emptyRuntimeParadigms

-- | WP6.1 anti-overblocking: do not dedup-block terms that are too
-- short, contain digits, or look like noise / mis-parsed fragments.
isTopicNoisyOrAmbiguous :: Text -> Bool
isTopicNoisyOrAmbiguous t =
  T.length t < 3
    || T.any isDigit t
    || T.any isPunctuation t
  where
    isDigit c = c >= '0' && c <= '9'
    isPunctuation c = c `elem` (".,;:!?-–—…\"'()[]{}" :: String)

planRenderEffectsForRuntimeImpl :: RuntimeParadigms -> PipelineRuntimeMode -> LocalRecoveryPolicy -> SystemState -> TurnInput -> TurnSignals -> TurnPlan -> RenderEffectPlan
planRenderEffectsForRuntimeImpl rp runtimeMode localRecoveryPolicy ss ti ts tp =
  let bestTopic = tiBestTopic ti
      mFlash = tsFlash ts
      consciousLoop' = tsConsciousLoop' ts
      mNarrative = clLastNarrative consciousLoop'
      rmpAfterLegit = tpRmpAfterLegit tp
      rcpFinal = tpRcpFinal tp
      semanticAnchor = tpSemanticAnchor tp
      (mPressure, principledModeResult) =
        case tpPrincipledModePair tp of
          Just (p, pmr) -> (Just p, Just pmr)
          Nothing -> (Nothing, Nothing)
      identityClaims = integrateIdentityClaims (ssIdentityClaims ss) (tpFamily tp) bestTopic
      input = ipfRawText (tiFrame ti)
      structuredSurface = hasStructuredDialogueSurface (tiFrame ti)
      mGeodesicPlan =
        let topicChain = dscTopicChain (ssDiscourse ss)
        in case topicChain of
          (prev:_) | prev /= bestTopic && not (T.null prev) && not (T.null bestTopic) ->
            Just (geodesicRouter (ssMeaningGraph ss) prev bestTopic (take 3 topicChain))
          _ -> Nothing
      -- WP2: GF-first rendering. Assembly path is primary for all dialogue branches.
      -- Template fallback is only used when assembly produces empty text (no PGF/runtime).
      -- M4-SEMANTIC-CORE-003 Phase C: semantic-first path is now PRIMARY
      -- for ALL input (not just covered topics). isCoveredTopic gate removed.
      -- Old assembly/template paths remain as fallback when semantic-first
      -- does not produce text or when morphology is not ready (test fixtures).
      semanticInput = input
      semanticTokens = map T.toLower (T.words (T.strip input))
      semanticMorph = ssMorphology ss
      semanticIntent = semanticIntentForRender (ipfPropositionType (tiFrame ti)) semanticInput semanticTokens semanticMorph
      semanticFrame = buildFrame semanticIntent semanticInput
      semanticText = generateFromFrame (ssContentSelector ss) (tiField ti) (Just (ssSemanticNetwork ss)) semanticFrame semanticMorph
      semanticNonUnknown = case semanticIntent of
        IntentUnknown _ -> False
        _               -> True
      -- M4-SEMANTIC-CORE-003 Phase C: content source classification for trace
      semanticContentSource =
        let isCovered = isCoveredTopic bestTopic
            hasExactDef = isJust (lookupDefinitionContent bestTopic)
            hasExactDist = case semanticIntent of
              IntentDistinguish l r -> isJust (lookupDistinctionContent l r)
              _ -> False
        in if hasExactDef || hasExactDist
           then "covered_exact"
           else if isCovered
                then "covered_generic"
                else "uncovered_generic"
      -- Analogical response: when no exact definition but findNearestCoveredTopic finds source
      mAnalogicalSourceTag = case findNearestCoveredTopic bestTopic of
        Just sourceTopic | isNothing (lookupDefinitionContent bestTopic) ->
          ["analogical_source=" <> sourceTopic]
        _ -> []
      -- Substrate trace: count substrate edges in network, identify activated topics
      substrateEdges = [ (seFrom e, seTo e) | e <- Data.Map.elems (snEdges (ssSemanticNetwork ss)), seSource e == SubstrateEdge ]
      substrateEdgeCount = length substrateEdges
      -- Topics reachable via substrate edges from bestTopic
      substrateActivatedTopics = [ to | (from, to) <- substrateEdges, from == bestTopic ]
      -- Only fire semantic-first when morphology has real data (not test fixture).
      -- This prevents regression in tests that use minimal MorphologyData.
      semanticMorphReady = not (Data.Map.null (mdNominative semanticMorph))
      semanticFirstAblated = tpSemanticFirstDisabled tp
      viaSemantic
        | semanticNonUnknown && semanticMorphReady && not semanticFirstAblated && not (T.null semanticText) =
            Just mkSemanticArtifact
        | otherwise = Nothing
      mkSemanticArtifact = DialogueRenderArtifact
        { draRenderedText = semanticText
        , draQuestionLike = False
        , draStylePrefixText = ""
        , draTemplateBodyText = semanticText
        , draClaimText = ""
        , draClaimAst = Nothing
        , draLinearizationLang = Just "semantic_intent"
        , draLinearizationOk = True
        , draFallbackReason = Nothing
        , draContractProvenance = AssembledClaim
        , draSurfaceProvenance = FromDB
        , draDerivationTags =
            [ "surface=semantic_intent"
            , "intent=" <> T.pack (show semanticIntent)
            , "frame=" <> frameTypeText semanticFrame
            , "content_source=" <> semanticContentSource
            ] ++ mAnalogicalSourceTag
              ++ (if not (null substrateActivatedTopics)
                  then [ "substrate_activated=" <> T.intercalate "," substrateActivatedTopics
                       , "substrate_edges_used=" <> T.pack (show substrateEdgeCount)
                       ]
                  else [])
        , draDialogAtoms = emptyDialogAtoms
        , draGenerationTrace =
            [ GenerationAttempt "semantic_intent" "ok"
            , GenerationAttempt "frame_builder" "ok"
            , GenerationAttempt "compositional_generator" "ok"
            ]
        }
      viaAssembly = renderArtifactViaAssembly rp ss (tiFrame ti) rmpAfterLegit rcpFinal
                        bestTopic identityClaims (ssMorphology ss) (rcpStyle rcpFinal) (emptyParsedInput input) mNarrative mGeodesicPlan (tiField ti)
      assemblyFallbackReason = fromMaybe "assembly_empty_fallback" (draFallbackReason viaAssembly)
      dialogueArtifact
        | Just semanticArtifact <- viaSemantic = semanticArtifact
        | not (T.null (draRenderedText viaAssembly)) = viaAssembly
        | otherwise =
            (renderDialogueArtifact (tiFrame ti) rmpAfterLegit rcpFinal bestTopic identityClaims (ssMorphology ss) (ssRuntimeParadigms ss) (tiField ti) (ssContentSelector ss) (tiActivatedNetwork ti))
              { draFallbackReason = Just assemblyFallbackReason }
      forceFinalized =
        if structuredSurface
          then draRenderedText dialogueArtifact
          else finalizeForce (rmpForce rmpAfterLegit) (draRenderedText dialogueArtifact)
      finalRender =
        case mFlash of
          Just flash ->
            if ifOverridesAll flash
              then forceFinalized <> "\n[" <> ifDirective flash <> "]"
              else forceFinalized
          Nothing -> forceFinalized
      renderWithContext = finalRender
      narrativeEnriched = renderWithContext
      surfacingFragment =
        case structuredSurface of
          True -> ""
          False ->
            case clLastSurfacing consciousLoop' of
              Just se -> surfacingToFragment se
              Nothing -> ""
      renderWithBg =
        if T.null surfacingFragment
          then narrativeEnriched
          else narrativeEnriched <> "\n" <> surfacingFragment
      structuredQuestion =
        ipfConfidence (tiFrame ti) >= parserLowConfidenceThreshold
          && ipfPropositionType (tiFrame ti) /= PlainAssert
      morphologyWarning =
        if T.any isSpace input
             && not structuredQuestion
             && not (T.null bestTopic)
             && not (hasKnownMorphologyForm (ssMorphology ss) bestTopic)
          then Just bestTopic
          else Nothing
      localRecoveryPlan =
        buildLocalRecoveryPlan runtimeMode localRecoveryPolicy ss ti tp morphologyWarning
      -- WP3 dedup: skip external query if term is already known.
      -- WP6.1 anti-overblocking: do NOT block noisy/ambiguous/low-confidence topics.
      topicIsNoisy = isTopicNoisyOrAmbiguous bestTopic
      parserConfidenceLow =
        ipfConfidence (tiFrame ti) < parserLowConfidenceThreshold
      mDedupSkipReason =
        if topicIsNoisy || parserConfidenceLow
          then Nothing
          else if hasKnownMorphologyForm (ssMorphology ss) bestTopic
            then Just "already_known_morphology"
            else if isTermKnownInKnowledgeTree bestTopic (ssKnowledgeTree ss)
              then Just "already_known_tree"
              else Nothing
      mExternalQueryRequest =
        case mDedupSkipReason of
          Just _ -> Nothing
          Nothing ->
            case localRecoveryPlan of
              Just plan | isRequestStrategy (lrpStrategy plan) ->
                let need = lnsCurrentNeed (ssLearningNeedState ss)
                in buildExternalActionRequest
                    RequestDrivenExternalAction
                    need
                    (buildExternalQueryText need (tiBestTopic ti))
              _ -> Nothing
      -- Phase 9: autonomous exploratory learning query.
      -- Triggered when:
      --   1. No request-driven external query already planned
      --   2. Learning need is active (not NeedNone)
      --   3. Guardrails allow (rate limit, circuit breaker)
      --   4. A suitable tool is available
      exploratoryDecision =
        canIssueExternalAction (ssGuardrailState ss) ExploratoryExternalAction (ssTurnCount ss)
      mExploratoryQueryRequest =
        case mDedupSkipReason of
          Just _ -> Nothing
          Nothing ->
            case mExternalQueryRequest of
              Just _ -> Nothing  -- request-driven query takes priority
              Nothing ->
                let need = lnsCurrentNeed (ssLearningNeedState ss)
                in if need == NeedNone
                      then Nothing
                      else case exploratoryDecision of
                        ExternalActionDenied _ -> Nothing
                        ExternalActionAllowed ->
                          buildExternalActionRequest
                            ExploratoryExternalAction
                            need
                            (buildExploratoryQueryText need (tiBestTopic ti))
      mExternalActionDecision
        | mExternalQueryRequest /= Nothing = Just ExternalActionAllowed
        | repLikeExploratory = Just exploratoryDecision
        | isRequestRecovery = Just (canIssueExternalAction (ssGuardrailState ss) RequestDrivenExternalAction (ssTurnCount ss))
        | otherwise = Nothing
      mExternalActionDecisionTrace
        | mExternalQueryRequest /= Nothing =
            Just (ExternalActionDecisionTrace RequestDrivenExternalAction AllowedRequestDriven (Just (renderNeedTag (lnsCurrentNeed (ssLearningNeedState ss)))))
        | mExploratoryQueryRequest /= Nothing =
            Just (ExternalActionDecisionTrace ExploratoryExternalAction AllowedExploratory (Just (renderNeedTag (lnsCurrentNeed (ssLearningNeedState ss)))))
        | isRequestRecovery =
            case canIssueExternalAction (ssGuardrailState ss) RequestDrivenExternalAction (ssTurnCount ss) of
              ExternalActionDenied _ ->
                Just (deniedTrace RequestDrivenExternalAction (lnsCurrentNeed (ssLearningNeedState ss)) (canIssueExternalAction (ssGuardrailState ss) RequestDrivenExternalAction (ssTurnCount ss)))
              ExternalActionAllowed ->
                Just (ExternalActionDecisionTrace RequestDrivenExternalAction DeniedNoExecutableTool (Just (renderNeedTag (lnsCurrentNeed (ssLearningNeedState ss)))))
        | repLikeExploratory =
            if lnsCurrentNeed (ssLearningNeedState ss) == NeedNone
              then Just (ExternalActionDecisionTrace ExploratoryExternalAction DeniedNoEligibleNeed Nothing)
              else case exploratoryDecision of
                     ExternalActionDenied _ -> Just (deniedTrace ExploratoryExternalAction (lnsCurrentNeed (ssLearningNeedState ss)) exploratoryDecision)
                     ExternalActionAllowed -> Just (ExternalActionDecisionTrace ExploratoryExternalAction DeniedNoExecutableTool (Just (renderNeedTag (lnsCurrentNeed (ssLearningNeedState ss)))))
        | otherwise = Just (ExternalActionDecisionTrace RequestDrivenExternalAction DeniedNoActionSelected Nothing)
      externalQuerySkipReason =
        case mDedupSkipReason of
          Just reason -> Just reason
          Nothing ->
            case mExternalActionDecision of
              Just (ExternalActionDenied reason) -> Just reason
              _ -> Nothing
      repLikeExploratory =
        mExternalQueryRequest == Nothing && lnsCurrentNeed (ssLearningNeedState ss) /= NeedNone
      isRequestRecovery =
        case localRecoveryPlan of
          Just plan -> isRequestStrategy (lrpStrategy plan)
          Nothing -> False
    in RenderEffectPlan
        { repRenderStatic = RenderStatic
           { rsRenderWithBg = renderWithBg
           , rsTemplateArtifact = dialogueArtifact
           , rsPreferredGfLang = detectInputGfLang input
           , rsResolvedAssemblyPath = Nothing
           , rsResolvedAuthorityClass = Nothing
           , rsArtifactManifest = Nothing
           , rsModePrefixText =
               if structuredSurface
                 then ""
                else
                  T.intercalate
                    "\n"
                    (filter
                      (not . T.null)
                      [ renderStylePrefix (rcpStyle rcpFinal)
                      , maybe "" (renderPrincipledPrefix mPressure) principledModeResult
                      ])
          , rsAnchorPrefixText =
              if not (not structuredSurface && tpFinalFamily tp == CMAnchor)
                then ""
                else maybe "" renderAnchorPrefix semanticAnchor
          , rsNarrativeFragmentText = ""
          , rsSurfacingFragmentText = surfacingFragment
          }
      , repTurnInput = ti
      , repLocalRecoveryPlan = localRecoveryPlan
      , repRenderMorphologyWarning = morphologyWarning
      , repKnowledgeTopic = bestTopic
      , repExternalQueryRequest = mExternalQueryRequest
      , repExploratoryQueryRequest = mExploratoryQueryRequest
      , repExternalQuerySkipReason = externalQuerySkipReason
      , repExternalActionDecision = mExternalActionDecision
      , repExternalActionDecisionTrace = mExternalActionDecisionTrace
        }
  where
    isRequestStrategy StrategyRequestCalibration = True
    isRequestStrategy StrategyRequestRule        = True
    isRequestStrategy StrategyRequestConcept     = True
    isRequestStrategy _                          = False

    buildExternalQueryText :: LearningNeed -> Text -> Text
    buildExternalQueryText need topic =
      let topicText = if T.null topic then "concept" else topic
      in case need of
           -- Direct topic query for deterministic mock-table matching
           -- (first word is the topic itself).
           NeedLexiconExtension    -> topicText
           NeedKeywordEnrichment   -> T.concat ["Explain ", topicText]
           NeedSalienceCalibration -> T.concat ["Calibrate salience for ", topicText]
           NeedNone                -> ""

    buildExploratoryQueryText :: LearningNeed -> Text -> Text
    buildExploratoryQueryText need topic =
      let topicText = if T.null topic then "concept" else topic
      in case need of
           NeedLexiconExtension    -> T.concat ["Explore definition of ", topicText]
           NeedKeywordEnrichment   -> T.concat ["Explore keywords for ", topicText]
           NeedSalienceCalibration -> T.concat ["Explore salience calibration for ", topicText]
           NeedNone                -> ""

    buildExternalActionRequest :: ExternalActionKind -> LearningNeed -> Text -> Maybe (ExternalTool, LearningNeed, Text)
    buildExternalActionRequest actionKind need queryText =
      let mTool = selectToolWithReliability need (ssToolReliability ss) defaultAvailableTools
          decision = canIssueExternalAction (ssGuardrailState ss) actionKind (ssTurnCount ss)
      in case (decision, mTool) of
           (ExternalActionAllowed, Just tool) | etReliability tool >= 0.3 -> Just (tool, need, queryText)
           _ -> Nothing
    deniedTrace kind need decision =
      ExternalActionDecisionTrace kind (decisionReason kind need decision) (Just (renderNeedTag need))
    decisionReason kind need decision =
      case decision of
        ExternalActionAllowed ->
          case kind of
            RequestDrivenExternalAction -> AllowedRequestDriven
            ExploratoryExternalAction -> AllowedExploratory
        ExternalActionDenied reason
          | reason == "guardrail_rate_limit" -> DeniedGuardrailRateLimit
          | reason == "guardrail_circuit_breaker" -> DeniedGuardrailCircuitBreaker
          | need == NeedNone -> DeniedNoEligibleNeed
          | otherwise -> DeniedNoExecutableTool
    reasonText reason =
      Just $ case reason of
        AllowedRequestDriven -> "allowed_request_driven"
        AllowedExploratory -> "allowed_exploratory"
        DeniedGuardrailRateLimit -> "guardrail_rate_limit"
        DeniedGuardrailCircuitBreaker -> "guardrail_circuit_breaker"
        DeniedNoEligibleNeed -> "no_eligible_need"
        DeniedNoExecutableTool -> "no_executable_tool"
        DeniedNoActionSelected -> "no_action_selected"
    renderNeedTag NeedSalienceCalibration = "NeedSalienceCalibration"
    renderNeedTag NeedKeywordEnrichment = "NeedKeywordEnrichment"
    renderNeedTag NeedLexiconExtension = "NeedLexiconExtension"
    renderNeedTag NeedNone = "NeedNone"

resolveRenderEffects :: PipelineIO -> RenderEffectPlan -> IO RenderEffectResults
resolveRenderEffects pio effectPlan = do
  let tRender0 = tiStartTime (repTurnInput effectPlan)
  warnMorphologyFallback <- shouldWarnMorphologyFallback pio
  -- B2 Control-A ablation: check if semantic-first path should be disabled
  mSemanticDisable <- lookupEnv "QXFX0_CONTROL_A_DISABLE_SEMANTIC_FIRST"
  let semanticFirstDisabled = mSemanticDisable == Just "1"
  case repRenderMorphologyWarning effectPlan of
    Just bestTopic | warnMorphologyFallback ->
      hPutStrLnWarning ("Morphology fallback: unknown topic lexeme: " <> bestTopic)
    _ ->
      pure ()

  resolvedRenderStatic <- resolveRuntimeGfLinearization pio (repRenderStatic effectPlan)
  -- WP3: Minimal legal DB adapter. Try legal lookup on the knowledge topic.
  -- For non-legal topics retrieveLegalFact returns Nothing; behavior is unchanged.
  mLegalFact <- retrieveLegalFact (repKnowledgeTopic effectPlan)
  let mKnowledgeFact = legalFactToKnowledgeFragment <$> mLegalFact
      mKnowledgeSource = lfSourceId <$> mLegalFact
  let scheduledRequests =
        scheduleTurnEffects pio (tiConatusEnergy (repTurnInput effectPlan))
          (  [ ("request", TurnReqExternalQuery tool need queryText)
             | Just (tool, need, queryText) <- [repExternalQueryRequest effectPlan]
             ]
          <> [ ("explore", TurnReqExternalQuery tool need queryText)
             | Just (tool, need, queryText) <- [repExploratoryQueryRequest effectPlan]
             ]
          )
  resolvedEffects <- forConcurrently scheduledRequests $ \(label, request) -> do
    result <- resolveTurnEffect pio request
    pure (label, result)
  let mExternalQueryResult =
        case firstMatch (\(label, _) -> label == "request") resolvedEffects of
          Nothing -> Nothing
          Just (_, TurnResExternalQuery res) -> Just res
          Just _ -> Just (Left (EqeInvalidResponse "unexpected_effect_result"))
      mExploratoryQueryResult =
        case firstMatch (\(label, _) -> label == "explore") resolvedEffects of
          Nothing -> Nothing
          Just (_, TurnResExternalQuery res) -> Just res
          Just _ -> Just (Left (EqeInvalidResponse "unexpected_effect_result"))
  let tRender1 = tiStartTime (repTurnInput effectPlan)
  pure RenderEffectResults
    { rerRenderTimeline = RenderTimeline
        { rtlRenderStart = tRender0
        , rtlRenderEnd = tRender1
        }
    , rerResolvedRenderStatic = resolvedRenderStatic
    , rerKnowledgeFact = mKnowledgeFact
    , rerKnowledgeFactSource = mKnowledgeSource
    , rerExternalQueryResult = mExternalQueryResult
    , rerExploratoryQueryResult = mExploratoryQueryResult
    , rerExternalQuerySkipReason = repExternalQuerySkipReason effectPlan
    , rerExternalActionDecisionTrace = repExternalActionDecisionTrace effectPlan
    , rerSemanticFirstDisabled = semanticFirstDisabled
    }

renderAnomalySurface :: ContentSelector -> Field -> Set.Set Text -> AnomalySurface -> Text
renderAnomalySurface cs field currentAtoms (SurfaceUnclassifiable input _scores) =
  let farthestPred = selectFarthestPoint cs field input currentAtoms
      predText = case farthestPred of
        Just p -> "Я предлагаю рассмотреть: " <> spRu p <> ". "
        Nothing -> ""
  in "Я выбираю не отвечать на этот запрос. " <>
     "Ваш вопрос не имеет для меня ясного смысла. " <>
     predText <>
     "Переформулируйте, пожалуйста."
renderAnomalySurface cs field currentAtoms (SurfaceAntiConatus _energy _threshold _input) =
  "Я не буду продолжать в этом направлении. " <>
  "Этот запрос ослабляет мою позицию. " <>
  "Давайте вернёмся к тому, что я понимаю."
renderAnomalySurface cs field currentAtoms (SurfaceSelfReferential _depth _context) =
  "Я не буду обсуждать себя. " <>
  "Сосредоточимся на вашем вопросе. " <>
  "Что вы хотите узнать?"
renderAnomalySurface cs field currentAtoms (SurfaceTemporal _current _historical _contradiction) =
  "Я пересматриваю свою позицию. " <>
  "То, что я говорил ранее, противоречит тому, что я говорю сейчас. " <>
  "Мне нужно уточнить, что я имею в виду."

buildTurnArtifacts :: SystemState -> TurnInput -> TurnSignals -> TurnPlan -> RenderEffectPlan -> RenderEffectResults -> TurnArtifacts
buildTurnArtifacts ss ti _ts tp effectPlan effectResults =
  let contentSelector = ssContentSelector ss
      field = tiField ti
      currentAtoms = Set.fromList $ map maText $ asAtoms $ tiAtomSet ti
      anomalyText = fmap (renderAnomalySurface contentSelector field currentAtoms) (tpAnomalySurface tp)
      renderStatic = if semanticFirstDisabled
                     then repRenderStatic effectPlan
                     else fromMaybe (repRenderStatic effectPlan) (rerResolvedRenderStatic effectResults)
      renderWithBg = rsRenderWithBg renderStatic
      localRecoveryPlan = repLocalRecoveryPlan effectPlan
      -- B2 Control-A ablation: disable semantic-first path when flag is set
      semanticFirstDisabled = rerSemanticFirstDisabled effectResults
      localRecoveryText = lrpSurface <$> localRecoveryPlan
      knowledgeFragment = maybe "" ("\n[знание] " <>) (rerKnowledgeFact effectResults)
      preSafetyRendered =
        case (anomalyText, localRecoveryText) of
          (Just anom, _) -> anom
          (Nothing, Just fb) -> renderWithBg <> "\n" <> fb <> knowledgeFragment
          (Nothing, Nothing) -> renderWithBg <> knowledgeFragment
      preSafetySurface =
        Guard.GuardSurface
          { Guard.gsRenderedText = preSafetyRendered
          , Guard.gsSegments =
              filter (not . T.null . Guard.rsText)
                [ Guard.RenderSegment Guard.SegmentTemplate (draStylePrefixText (rsTemplateArtifact renderStatic))
                , Guard.RenderSegment Guard.SegmentTemplate (rsModePrefixText renderStatic)
                , Guard.RenderSegment Guard.SegmentTemplate (rsAnchorPrefixText renderStatic)
                , Guard.RenderSegment Guard.SegmentTemplate (draTemplateBodyText (rsTemplateArtifact renderStatic))
                , Guard.RenderSegment Guard.SegmentIdentityClaim (draClaimText (rsTemplateArtifact renderStatic))
                , Guard.RenderSegment Guard.SegmentNarrative (rsNarrativeFragmentText renderStatic)
                , Guard.RenderSegment Guard.SegmentSurfacing (rsSurfacingFragmentText renderStatic)
                ]
                  ++ maybe [] (\fb -> [Guard.RenderSegment Guard.SegmentLocalRecovery fb]) localRecoveryText
          , Guard.gsQuestionLike = draQuestionLike (rsTemplateArtifact renderStatic)
          }
      timeline = rerRenderTimeline effectResults
      !metrics4 = addPhase (recordPhase "render" (rtlRenderStart timeline) (rtlRenderEnd timeline)) (tpMetrics tp)
      guardSafety = Guard.postRenderSafetyCheckSurface preSafetySurface (F.toList (ssHistory ss))
      templateArtifact = rsTemplateArtifact renderStatic
      (renderedSurface, finalizeSurfaceProv) = finalizeOutput preSafetySurface (F.toList (ssHistory ss))
      surfaceProv = case finalizeSurfaceProv of
        FromRecovery -> FromRecovery
        _ -> draSurfaceProvenance templateArtifact
      contractProv = case surfaceProv of
        FromRecovery -> RecoveryRoute
        _ -> draContractProvenance templateArtifact
      assemblyPath = deriveAssemblyPath renderStatic templateArtifact finalizeSurfaceProv
      authorityClass = deriveAuthorityClass renderStatic contractProv surfaceProv assemblyPath
      artifactManifest = deriveArtifactManifest renderStatic templateArtifact assemblyPath authorityClass
      rendered = Guard.gsRenderedText renderedSurface
      (recoveryCause, recoveryStrategy, recoveryEvidence) =
        case surfaceProv of
          FromRecovery ->
            (Just RecoveryRenderBlocked, Just StrategySafeRecovery, ["render_guard=blocked"])
          _ ->
            case localRecoveryPlan of
              Just plan -> (Just (lrpCause plan), Just (lrpStrategy plan), lrpEvidence plan)
              Nothing -> (Nothing, Nothing, [])
      -- Phase 8 (M3): deliberation override of recovery cause.
      -- We merge by severity rather than simple Maybe-fallback so
      -- that future hemispheric proposals (Package D and beyond)
      -- cannot silently downgrade a more severe local cause.
      -- Today this is semantically equivalent because the only
      -- deliberation-produced cause is RecoveryConatusGate
      -- (severity 100, dominates everything).
      delibRecoveryCause = tpDeliberation tp >>= planRecoveryCause . delibReconciled
      finalRecoveryCause = pickHigherSeverity delibRecoveryCause recoveryCause
      decisionFamily = case surfaceProv of
        FromRecovery -> CMRepair
        _ | hasChallengeMarkerForDecision (ipfRawText (tiFrame ti)) -> CMConfront
        _ -> tpFinalFamily tp
      decisionForce = case surfaceProv of
        FromRecovery -> IFOffer
        _ | decisionFamily == CMConfront -> IFConfront
        _ -> tpFinalForce tp
      decision = TurnDecision
        { tdFamily = decisionFamily
        , tdForce = decisionForce
        , tdRenderStrategy = tpRenderStrategy tp
        , tdRenderStyle = rcpStyle (tpRcpFinal tp)
        , tdGuardStatus =
            if tpShadowGateTriggered tp
              then Blocked (tpShadowMessage tp)
              else case guardSafety of
                Guard.InvariantBlock w -> Blocked w
                _ -> tiNixStatus ti
        , tdGuardReport = tpGuardReport tp
        , tdLegitimacy = tpLegitScore tp
        , tdIdentity = snapshotIdentitySignal (tpIdentitySignal tp)
        , tdSemanticAnchor = tpSemanticAnchor tp
        }
      executedOutcome = safeExecutedTurnOutcome decision authorityClass contractProv surfaceProv assemblyPath artifactManifest
      derivationTags =
        draDerivationTags templateArtifact
          <> [ "surface_provenance=" <> T.pack (show surfaceProv)
             , "contract_provenance=" <> T.pack (show contractProv)
             , "assembly_path=" <> T.pack (show assemblyPath)
             , "authority_class=" <> T.pack (show authorityClass)
             , "response_surface_kind=" <> T.pack (show (etoResponseSurfaceKind executedOutcome))
             ]
          <> if finalizeSurfaceProv == FromRecovery then ["finalize=guard_blocked_non_expansive"] else ["finalize=preserve_upstream_surface"]
      executedDecision =
        decision
          { tdFamily = etoFamily executedOutcome
          , tdForce = etoForce executedOutcome
          }
      finalRendered = truthContractRebindRenderedText (etoTruthContractStatus executedOutcome) authorityClass rendered
      finalGuardSurface = renderedSurface { Guard.gsRenderedText = finalRendered }
  in TurnArtifacts
       { taPreSafetyRendered = preSafetyRendered
       , taGuardSurface = finalGuardSurface
        , taRendered = finalRendered
       , taSurfaceProv = surfaceProv
       , taContractProv = contractProv
       , taAuthorityClass = authorityClass
       , taTruthContractStatus = etoTruthContractStatus executedOutcome
       , taAssemblyPath = assemblyPath
       , taArtifactManifest = artifactManifest
       , taExecutedOutcome = executedOutcome
       , taDerivationTags = derivationTags
        , taFinalRendered = finalRendered
       , taClaimAst = draClaimAst (rsTemplateArtifact renderStatic)
      , taLinearizationLang = draLinearizationLang (rsTemplateArtifact renderStatic)
      , taLinearizationOk = draLinearizationOk (rsTemplateArtifact renderStatic)
      , taLinearizationFallbackReason = draFallbackReason (rsTemplateArtifact renderStatic)
       , taDecision = executedDecision
       , taLocalRecoveryCause = finalRecoveryCause
       , taLocalRecoveryStrategy = recoveryStrategy
       , taLocalRecoveryEvidence = recoveryEvidence
       , taMetrics = metrics4
       , taKnowledgeSource = rerKnowledgeFactSource effectResults
        , taExternalQueryResult = rerExternalQueryResult effectResults
       , taExploratoryQueryResult = rerExploratoryQueryResult effectResults
       , taExternalQuerySkipReason = rerExternalQuerySkipReason effectResults
        , taExternalActionDecisionTrace = rerExternalActionDecisionTrace effectResults
        , taGenerationTrace = draGenerationTrace (rsTemplateArtifact renderStatic)
         }

deriveAssemblyPath :: RenderStatic -> DialogueRenderArtifact -> SurfaceProvenance -> AssemblyPath
deriveAssemblyPath renderStatic artifact finalizeSurfaceProv
  | finalizeSurfaceProv == FromRecovery = GuardRecoveryRoute
  | Just route <- rsResolvedAssemblyPath renderStatic = route
  | maybe False (T.isSuffixOf "_GF_ATOMS") (draLinearizationLang artifact) = PgfAtomsRoute
  | maybe False (T.isSuffixOf "_GF_PGF") (draLinearizationLang artifact)
      && maybe False (T.isPrefixOf "ru") (draLinearizationLang artifact) = RussianCompatShimRoute
  | maybe False (T.isSuffixOf "_GF_PGF") (draLinearizationLang artifact) = PgfClaimRoute
  | "assembly=primary" `elem` draDerivationTags artifact = DialogueAssemblyRoute
  | any (`elem` draDerivationTags artifact) ["fallback=gf_template_fallback", "fallback=en_unstructured_fallback:input_detected_english", "fallback=ru_unstructured_fallback:template_empty"] = TemplateFallbackRoute
  | any (`elem` draDerivationTags artifact) ["fallback=gf_structured_fallback", "fallback=structured_surface_render_failed"] = StructuredFallbackRoute
  | otherwise = DialogueAssemblyRoute

deriveAuthorityClass :: RenderStatic -> ContractProvenance -> SurfaceProvenance -> AssemblyPath -> AuthorityClass
deriveAuthorityClass renderStatic contractProv surfaceProv assemblyPath =
  case rsResolvedAuthorityClass renderStatic of
    Just authority -> authority
    Nothing ->
      case assemblyPath of
        GuardRecoveryRoute -> AuthorityRecovery
        RussianCompatShimRoute -> AuthorityShim
        _ -> case (contractProv, surfaceProv) of
          (RecoveryRoute, _) -> AuthorityRecovery
          (FallbackRoute, _) -> AuthorityFallback
          (ShimRoute, _) -> AuthorityShim
          (DefaultRoute, _) -> AuthorityDefault
          (GeneratedArtifactRoute, _) -> AuthorityGeneratedArtifact
          (_, FromRecovery) -> AuthorityRecovery
          (_, FromFallback) -> AuthorityFallback
          (_, FromShim) -> AuthorityShim
          (_, FromDefault) -> AuthorityDefault
          (_, FromGeneratedArtifact) -> AuthorityGeneratedArtifact
          (AssembledClaim, _) -> AuthorityAssembled
          (BuiltClaim, _) -> AuthorityCanonical
          (NixGuarded, _) -> AuthorityRecovery
          (OperatorMapping, _) -> AuthorityAssembled

deriveArtifactManifest :: RenderStatic -> DialogueRenderArtifact -> AssemblyPath -> AuthorityClass -> ArtifactManifest
deriveArtifactManifest renderStatic artifact assemblyPath authorityClass =
  fromMaybe
    ArtifactManifest
      { amPgfPath = Nothing
      , amPgfHash = Just ("route_manifest:" <> T.pack (show assemblyPath) <> "|" <> T.pack (show authorityClass) <> "|" <> fromMaybe "" (draLinearizationLang artifact) <> "|" <> T.intercalate "," (draDerivationTags artifact))
      , amPgfSourceManifestHash = Just "route_source_manifest:local"
      , amGeneratedInputLexiconHash = Just (inputGeneratedLexiconProvenanceTag <> ":required")
      , amGfMapHash = Just (gfMapProvenanceTag <> ":required")
      , amToolchainIdentity = Just "render-route:local"
      , amToolchainMarker =
          "route=" <> T.pack (show assemblyPath)
            <> maybe "" (";lang=" <>) (draLinearizationLang artifact)
            <> ";authority=" <> T.pack (show authorityClass)
            <> ";contract=" <> T.pack (show (draContractProvenance artifact))
            <> ";surface=" <> T.pack (show (draSurfaceProvenance artifact))
      }
    (rsArtifactManifest renderStatic)

safeExecutedTurnOutcome :: TurnDecision -> AuthorityClass -> ContractProvenance -> SurfaceProvenance -> AssemblyPath -> ArtifactManifest -> ExecutedTurnOutcome
safeExecutedTurnOutcome decision authorityClass contractProv surfaceProv assemblyPath manifest =
  case mkExecutedTurnOutcome (tdFamily decision) (tdForce decision) authorityClass contractProv surfaceProv assemblyPath manifest of
    Right outcome -> outcome
    Left _ ->
      case mkExecutedTurnOutcome CMRepair IFOffer AuthorityRecovery RecoveryRoute FromRecovery GuardRecoveryRoute manifest of
        Right recoveryOutcome -> recoveryOutcome
        Left _ ->
          ExecutedTurnOutcome
            { etoFamily = CMRepair
            , etoForce = IFOffer
            , etoAuthorityClass = AuthorityRecovery
            , etoTruthContractStatus = NonExpansiveRecoverySurface
            , etoResponseSurfaceKind = SurfaceDegraded
            , etoContractProvenance = RecoveryRoute
            , etoSurfaceProvenance = FromRecovery
            , etoAssemblyPath = GuardRecoveryRoute
            , etoArtifactManifest = manifest
            , etoTransitionWon = False
            }

hasChallengeMarkerForDecision :: Text -> Bool
hasChallengeMarkerForDecision input =
  let lowered = T.toLower input
  in any (`T.isInfixOf` lowered)
       [ "разве", "не согласен", "не согласна", "противореч", "неверно"
       , "ошибаешься", "не прав", "спорю", "возраж", "сомневаюсь"
       , "ты говоришь", "оспариваю"
       ]

buildLocalRecoveryPlan :: PipelineRuntimeMode -> LocalRecoveryPolicy -> SystemState -> TurnInput -> TurnPlan -> Maybe Text -> Maybe LocalRecoveryPlan
buildLocalRecoveryPlan _ LocalRecoveryDisabled _ _ _ _ = Nothing
buildLocalRecoveryPlan runtimeMode LocalRecoveryEnabled ss ti tp morphologyWarning =
  let parserConfidence = ipfConfidence (tiFrame ti)
      legitScore = tpLegitScore tp
      lowLegitThreshold = ctLocalRecoveryThreshold (obsConstitutionalThresholds (ssObservability ss))
      candidateFamilies = localRecoveryCandidateFamilies ti tp
      hasCandidateSplit = length candidateFamilies >= 2
      hasDisambiguationCue = mentionsDisambiguationCue (ipfRawText (tiFrame ti))
      parserStrategy =
        if hasCandidateSplit && hasDisambiguationCue
          then StrategyDistinguishCandidates
          else StrategyAskClarification
      parserEvidence =
        ["parser_confidence=" <> T.pack (show parserConfidence)]
          <> if hasCandidateSplit
            then ["candidate_families=" <> renderCandidateFamilies candidateFamilies]
            else []
      -- Phase 2.5 (M2d) + Phase 6 (M6): the Conatus gate is the
      -- highest-priority recovery driver. When the runtime
      -- Conatus energy drops below 'conatusGateThreshold' (see
      -- 'QxFx0.Self.Salience.defaultSalienceWeights'), the system
      -- is in structural risk and 'StrategySafeRecovery' is forced
      -- regardless of shadow / parser / legitimacy / runtime-mode
      -- signals. The cause is tagged 'RecoveryConatusGate' — a
      -- dedicated 'LocalRecoveryCause' variant introduced together
      -- with this guard so the trace and the JSON schema can
      -- distinguish a structural-Conatus event from an
      -- environmental 'RecoveryRuntimeDegraded' event.
      --
      -- M6: the energy and the violation count are read straight
      -- from 'TurnInput', where the Prepare stage stored them
      -- (see 'QxFx0.Core.TurnPipeline.Effects.psConatusEnergy'
      -- and 'psBlanketViolationCount'). This is the
      -- single-source-of-truth for the pre-turn Conatus snapshot;
      -- the previous local 'computeSelfBlanket' \/
      -- 'checkInitialBlanket' \/ 'computeConatusEnergy' triple has
      -- been removed to eliminate the duplicate computation.
      conatusEnergy     = tiConatusEnergy ti
      conatusViolationCount = tiBlanketViolationCount ti
      conatusEvidence =
        [ "conatus_gate_fired"
        , "conatus_energy=" <> T.pack (show (ceScalar conatusEnergy))
        , "blanket_violations=" <> T.pack (show conatusViolationCount)
        ]
      candidate =
        case () of
          _
            | tiConatusGateFired ti ->
                let gradient = computeConatusGradient (computeSelfBlanket ss)
                    strategy = selectConatusRecoveryStrategy gradient
                    evidence =
                      conatusEvidence
                        <> [ "conatus_gradient_m=" <> T.pack (show (cgMorphology gradient))
                           , "conatus_gradient_c=" <> T.pack (show (cgIdentity gradient))
                           , "conatus_gradient_t=" <> T.pack (show (cgTurns gradient))
                           , "conatus_strategy=" <> renderLocalRecoveryStrategy strategy
                           ]
                 in Just
                      ( RecoveryConatusGate
                      , strategy
                      , evidence
                      )
            -- WP3: learning-driven recovery.  Only triggered when a
            -- persistent need (already stored in state from previous
            -- turns) has a high deficit level.  This introduces one
            -- turn of natural latency, acting as a lightweight
            -- rate-limit / quarantine before escalating to an external
            -- request strategy.
            | learningNeedActive ss ->
                let lns = ssLearningNeedState ss
                    need = lnsCurrentNeed lns
                    strategy = selectLearningRecoveryStrategy need
                    evidence =
                      [ "learning_need=" <> T.pack (show need)
                      , "learning_level=" <> T.pack (show (lnsLevel lns))
                      , "learning_persistence=" <> T.pack (show (lnsPersistence lns))
                      , "learning_strategy=" <> renderLocalRecoveryStrategy strategy
                      ]
                 in Just
                       ( RecoveryLearningNeed
                       , strategy
                       , evidence
                       )
            | tpShadowStatus tp == ShadowDiverged
                && tpShadowDivergenceSeverity tp /= ShadowSeverityAdvisory ->
                Just
                  ( RecoveryShadowDivergence
                  , StrategyNarrowScope
                  , [ "shadow_status=diverged"
                    , "shadow_kind=" <> T.pack (show (tpShadowDivergenceKind tp))
                    , "shadow_severity=" <> shadowDivergenceSeverityText (tpShadowDivergenceSeverity tp)
                    ]
                  )
            | tpShadowStatus tp == ShadowUnavailable ->
                Just
                  ( RecoveryShadowUnavailable
                  , StrategyExposeUncertainty
                  , [ "shadow_status=unavailable"
                    , "shadow_snapshot=" <> T.pack (show (tpShadowSnapshotId tp))
                    ]
                  )
            | parserConfidence < parserLowConfidenceThreshold ->
                Just
                  ( RecoveryParserLowConfidence
                  , parserStrategy
                  , parserEvidence
                  )
            | legitScore < lowLegitThreshold ->
                Just
                  ( RecoveryLowLegitimacy
                  , StrategyExposeUncertainty
                  , ["legitimacy_score=" <> T.pack (show legitScore)]
                  )
            | runtimeMode == RuntimeDegraded ->
                Just
                  ( RecoveryRuntimeDegraded
                  , StrategyNarrowScope
                  , ["runtime_mode=degraded"]
                  )
            | hasStructuredDialogueSurface (tiFrame ti) ->
                Nothing
            | otherwise ->
                case morphologyWarning of
                  Just topic ->
                    Just
                      ( RecoveryUnknownTopic
                      , StrategyDefineKnownTerms
                      , ["unknown_topic=" <> topic]
                      )
                  Nothing ->
                    Nothing
   in fmap
        (\(cause, strategy, evidence) ->
          let preferredLang = detectInputGfLang (ipfRawText (tiFrame ti))
          in
          LocalRecoveryPlan
            { lrpCause = cause
            , lrpStrategy = strategy
            , lrpEvidence = evidence
             , lrpSurface = renderLocalRecoverySurface preferredLang cause strategy (tiBestTopic ti) evidence
            })
         candidate

-- | WP1 (GAP1): map the Conatus gradient to a recovery strategy.
-- The component with the strictly largest partial derivative is
-- the axis that yields the highest marginal gain in Conatus energy
-- and therefore determines the recovery direction.
-- If two or more components tie for the maximum (degenerate gradient),
-- fall back to 'StrategySafeRecovery'.
selectConatusRecoveryStrategy :: ConatusGradient -> LocalRecoveryStrategy
selectConatusRecoveryStrategy g =
  let comps =
        [ (cgMorphology g, StrategyMorphologyExpansion)
        , (cgIdentity   g, StrategyIdentityReinforcement)
        , (cgTurns      g, StrategyTemporalDeepening)
        ]
      sorted = L.sortBy (\(a, _) (b, _) -> compare b a) comps
   in case sorted of
        ((v1, s1) : (v2, _) : _)
          | v1 > v2   -> s1
          | otherwise -> StrategySafeRecovery
        _ -> StrategySafeRecovery

-- | WP3: predicate for whether a persisted learning need is active
-- and severe enough to trigger an external-request recovery strategy.
-- The threshold (0.6) is chosen so that only high-deficit needs
-- escalate beyond local strategies; moderate deficits remain handled
-- by the normal turn pipeline.
learningNeedActive :: SystemState -> Bool
learningNeedActive ss =
  let lns = ssLearningNeedState ss
  in lnsCurrentNeed lns /= NeedNone && lnsLevel lns >= 0.6

-- | WP3: map an active 'LearningNeed' to the corresponding
-- 'LocalRecoveryStrategy' that requests external help.
selectLearningRecoveryStrategy :: LearningNeed -> LocalRecoveryStrategy
selectLearningRecoveryStrategy NeedSalienceCalibration = StrategyRequestCalibration
selectLearningRecoveryStrategy NeedKeywordEnrichment   = StrategyRequestConcept
selectLearningRecoveryStrategy NeedLexiconExtension    = StrategyRequestConcept
selectLearningRecoveryStrategy NeedNone                = StrategySafeRecovery

renderLocalRecoverySurface :: Text -> LocalRecoveryCause -> LocalRecoveryStrategy -> Text -> [Text] -> Text
renderLocalRecoverySurface gfLang cause strategy topic _evidence =
  if gfLangTelemetryTag gfLang == "en"
    then renderLocalRecoverySurfaceEn cause strategy topic
    else renderLocalRecoverySurfaceRu strategy topic

renderLocalRecoverySurfaceRu :: LocalRecoveryStrategy -> Text -> Text
renderLocalRecoverySurfaceRu strategy topic =
  let topicText = if T.null topic then "этот вопрос" else topic
   in case strategy of
        StrategyAskClarification ->
          "Уточни, тебе нужно определение, различение или пример по теме: " <> topicText <> "?"
        StrategyNarrowScope ->
          "Я удержу только устойчивую часть ответа и не буду достраивать непроверенные выводы."
        StrategyDefineKnownTerms ->
          "Чтобы ответ был точнее, нужна рамка употребления для темы: " <> topicText <> "."
        StrategyDistinguishCandidates ->
          "Я разделю возможные чтения и отмечу, где данных недостаточно."
        StrategyExposeUncertainty ->
          "Уверенность здесь ограничена, поэтому отвечу осторожно и не буду подменять недостающие основания догадкой."
        StrategySafeRecovery ->
          "Остановлю расширение ответа и вернусь к проверяемой части хода."
        StrategyMorphologyExpansion ->
          "Сначала уточню форму ключевых слов, чтобы не потерять смысловую связь."
        StrategyIdentityReinforcement ->
          "Удержу устойчивую рамку ответа и отделю её от непроверенных утверждений о себе."
        StrategyTemporalDeepening ->
          "Свяжу этот ход с предыдущим контекстом, чтобы не отвечать как на изолированную фразу."
        StrategyRequestCalibration ->
          "Для точной калибровки здесь не хватает внешнего критерия; пока зафиксирую осторожную рабочую версию."
        StrategyRequestRule ->
          "Для уверенного выбора хода не хватает правила различения; зафиксирую ближайшую безопасную рамку."
        StrategyRequestConcept ->
          "Для темы " <> topicText <> " не хватает понятия или ключевого признака; сначала задам рабочую границу смысла."
        StrategyExternalDialogue ->
          "Эту тему лучше разворачивать через отдельное исследование; сейчас удержу исходный вопрос: " <> topicText <> "."

renderLocalRecoverySurfaceEn :: LocalRecoveryCause -> LocalRecoveryStrategy -> Text -> Text
renderLocalRecoverySurfaceEn _cause strategy topic =
  let topicText = if T.null topic then "this question" else topic
   in case strategy of
        StrategyAskClarification ->
          "Clarify whether you need a definition, a distinction, or an example for: " <> topicText <> "."
        StrategyNarrowScope ->
          "I will keep the answer within stable evidence and avoid speculative completion."
        StrategyDefineKnownTerms ->
          "To answer precisely, I need usage context for: " <> topicText <> "."
        StrategyDistinguishCandidates ->
          "I will separate candidate readings and mark where the evidence is insufficient."
        StrategyExposeUncertainty ->
          "Confidence is limited here, so I will answer cautiously instead of filling gaps with guesses."
        StrategySafeRecovery ->
          "I will stop expanding the answer and return to the verifiable part of the turn."
        StrategyMorphologyExpansion ->
          "I will first clarify the form of the key terms so the meaning stays connected."
        StrategyIdentityReinforcement ->
          "I will keep the answer within a stable self-description and avoid unchecked claims."
        StrategyTemporalDeepening ->
          "I will connect this turn to the previous context instead of treating it as isolated."
        StrategyRequestCalibration ->
          "A precise calibration would need an external criterion; for now I will state a cautious working version."
        StrategyRequestRule ->
          "A confident next move needs a clearer rule of distinction; I will keep the safest local frame."
        StrategyRequestConcept ->
          "The topic " <> topicText <> " needs a clearer concept or key feature; I will start by setting a working boundary."
        StrategyExternalDialogue ->
          "This topic is better developed through a separate inquiry; I will keep the current question in view: " <> topicText <> "."

localRecoveryCandidateFamilies :: TurnInput -> TurnPlan -> [CanonicalMoveFamily]
localRecoveryCandidateFamilies ti tp =
  L.nub
    ( [ tiRecommendedFamily ti
      , ipfCanonicalFamily (tiFrame ti)
      , tpPreShadowFamily tp
      , tpFinalFamily tp
      ]
        <> maybe [] pure (tpStrategyFamily tp)
    )

mentionsDisambiguationCue :: Text -> Bool
mentionsDisambiguationCue input =
  let lowered = " " <> T.toLower input <> " "
      cues =
        [ " или "
        , " либо "
        , "разниц"
        , "отлич"
        , " vs "
        , " versus "
        ]
  in any (`T.isInfixOf` lowered) cues

renderCandidateFamilies :: [CanonicalMoveFamily] -> Text
renderCandidateFamilies =
  T.intercalate "," . map (T.pack . show)

shouldWarnMorphologyFallback :: PipelineIO -> IO Bool
shouldWarnMorphologyFallback pio = do
  result <- resolveTurnEffect pio (TurnReqReadEnv "QXFX0_WARN_MORPHOLOGY_FALLBACK")
  case result of
    TurnResReadEnv (Just "1") -> pure True
    TurnResReadEnv _ -> pure False
    _ -> pure False

resolveRuntimeGfLinearization :: PipelineIO -> RenderStatic -> IO (Maybe RenderStatic)
resolveRuntimeGfLinearization pio renderStatic = do
  runtimeEnabled <- shouldUseGfRuntime pio
  if not runtimeEnabled
    then pure Nothing
    else do
      gfLang <- resolveGfLang pio (rsPreferredGfLang renderStatic)
      mPgfPath <- resolveGfPgfPath pio
      let da = draDialogAtoms (rsTemplateArtifact renderStatic)
      resultDa <- resolveTurnEffect pio (TurnReqLinearizeDialogAtoms mPgfPath gfLang da)
      case resultDa of
        TurnResLinearizeDialogAtoms (Right gfResult) | not (T.null (T.strip (glrText gfResult))) ->
          pure (Just (applyRuntimeGfResult gfLang renderStatic resultDa))
        _ ->
          case draClaimAst (rsTemplateArtifact renderStatic) of
            Nothing -> pure Nothing
            Just claimAst -> do
              result <- resolveTurnEffect pio (TurnReqLinearizeClaimAst mPgfPath gfLang claimAst)
              pure (Just (applyRuntimeGfResult gfLang renderStatic result))

shouldUseGfRuntime :: PipelineIO -> IO Bool
shouldUseGfRuntime pio = do
  result <- resolveTurnEffect pio (TurnReqReadEnv "QXFX0_GF_RUNTIME")
  case result of
    TurnResReadEnv (Just rawValue) ->
      pure (normalizeBool rawValue)
    _ ->
      pure False

resolveGfLang :: PipelineIO -> Text -> IO Text
resolveGfLang pio defaultLang = do
  result <- resolveTurnEffect pio (TurnReqReadEnv "QXFX0_GF_LANG")
  case result of
    TurnResReadEnv (Just lang) | not (T.null (T.strip lang)) ->
      pure (normalizeGfLang (T.strip lang))
    _ ->
      pure (normalizeGfLang defaultLang)

resolveGfPgfPath :: PipelineIO -> IO (Maybe FilePath)
resolveGfPgfPath pio = do
  result <- resolveTurnEffect pio (TurnReqReadEnv "QXFX0_GF_PGF_PATH")
  case result of
    TurnResReadEnv (Just rawPath) ->
      let stripped = T.unpack (T.strip rawPath)
      in pure (if null stripped then Nothing else Just stripped)
    _ ->
      pure Nothing

normalizeBool :: Text -> Bool
normalizeBool rawValue =
  T.toLower (T.strip rawValue) `elem` ["1", "true", "yes", "on"]

firstMatch :: (a -> Bool) -> [a] -> Maybe a
firstMatch predicate = go
  where
    go [] = Nothing
    go (x:xs)
      | predicate x = Just x
      | otherwise = go xs

applyRuntimeGfResult :: Text -> RenderStatic -> TurnEffectResult -> RenderStatic
applyRuntimeGfResult gfLang renderStatic result =
  let langTag = gfLangTelemetryTag gfLang
  in
  case result of
    TurnResLinearizeDialogAtoms (Right gfResult)
      | not (T.null (T.strip (glrText gfResult))) ->
          let baseArtifact = rsTemplateArtifact renderStatic
              updatedArtifact =
                baseArtifact
                  { draRenderedText = glrText gfResult
                  , draTemplateBodyText = glrText gfResult
                  , draLinearizationLang = Just (glrLanguage gfResult)
                  , draLinearizationOk = True
                  , draFallbackReason = glrFallbackReason gfResult
                  , draContractProvenance = case glrAuthorityClass gfResult of
                      AuthorityShim -> ShimRoute
                      AuthorityDefault -> DefaultRoute
                      AuthorityGeneratedArtifact -> GeneratedArtifactRoute
                      AuthorityFallback -> FallbackRoute
                      AuthorityRecovery -> RecoveryRoute
                      AuthorityAssembled -> AssembledClaim
                      AuthorityCanonical -> BuiltClaim
                      AuthorityLegacyIncomplete -> AssembledClaim
                  , draSurfaceProvenance = case glrAuthorityClass gfResult of
                      AuthorityShim -> FromShim
                      AuthorityDefault -> FromDefault
                      AuthorityGeneratedArtifact -> FromGeneratedArtifact
                      AuthorityFallback -> FromFallback
                      AuthorityRecovery -> FromRecovery
                      AuthorityAssembled -> FromOperator
                      AuthorityCanonical -> FromDB
                      AuthorityLegacyIncomplete -> FromHardFallback
                   , draDerivationTags = draDerivationTags baseArtifact
                       <> ["gf_authority=" <> T.pack (show (glrAuthorityClass gfResult))
                          , "gf_assembly_path=" <> T.pack (show (glrAssemblyPath gfResult))
                          ]
                   , draGenerationTrace = draGenerationTrace baseArtifact
                       <> [GenerationAttempt "pgf_dialog_atoms" "ok"]
                   }
          in renderStatic
                { rsTemplateArtifact = updatedArtifact
                , rsResolvedAssemblyPath = Just (glrAssemblyPath gfResult)
                , rsResolvedAuthorityClass = Just (glrAuthorityClass gfResult)
                , rsArtifactManifest = Just (glrArtifactManifest gfResult)
                , rsRenderWithBg = glrText gfResult
                }
    TurnResLinearizeClaimAst (Right gfResult)
      | not (T.null (T.strip (glrText gfResult))) ->
          let baseArtifact = rsTemplateArtifact renderStatic
              updatedArtifact =
                baseArtifact
                  { draRenderedText = glrText gfResult
                  , draTemplateBodyText = glrText gfResult
                  , draLinearizationLang = Just (glrLanguage gfResult)
                  , draLinearizationOk = True
                  , draFallbackReason = glrFallbackReason gfResult
                  , draContractProvenance = case glrAuthorityClass gfResult of
                      AuthorityShim -> ShimRoute
                      AuthorityDefault -> DefaultRoute
                      AuthorityGeneratedArtifact -> GeneratedArtifactRoute
                      AuthorityFallback -> FallbackRoute
                      AuthorityRecovery -> RecoveryRoute
                      AuthorityAssembled -> AssembledClaim
                      AuthorityCanonical -> BuiltClaim
                      AuthorityLegacyIncomplete -> AssembledClaim
                  , draSurfaceProvenance = case glrAuthorityClass gfResult of
                      AuthorityShim -> FromShim
                      AuthorityDefault -> FromDefault
                      AuthorityGeneratedArtifact -> FromGeneratedArtifact
                      AuthorityFallback -> FromFallback
                      AuthorityRecovery -> FromRecovery
                      AuthorityAssembled -> FromOperator
                      AuthorityCanonical -> FromDB
                      AuthorityLegacyIncomplete -> FromHardFallback
                   , draDerivationTags = draDerivationTags baseArtifact
                       <> ["gf_authority=" <> T.pack (show (glrAuthorityClass gfResult))
                          , "gf_assembly_path=" <> T.pack (show (glrAssemblyPath gfResult))
                          ]
                   , draGenerationTrace = draGenerationTrace baseArtifact
                       <> [GenerationAttempt "pgf_claim_ast" "ok"]
                   }
          in renderStatic
                { rsTemplateArtifact = updatedArtifact
                , rsResolvedAssemblyPath = Just (glrAssemblyPath gfResult)
                , rsResolvedAuthorityClass = Just (glrAuthorityClass gfResult)
                , rsArtifactManifest = Just (glrArtifactManifest gfResult)
                , rsRenderWithBg = rebuildRenderWithBg renderStatic (glrText gfResult)
                }
    TurnResLinearizeClaimAst (Left err) ->
      let baseArtifact = rsTemplateArtifact renderStatic
      in renderStatic
           { rsTemplateArtifact =
               baseArtifact
                 { draLinearizationLang = Just (langTag <> "_GF_PGF")
                 , draLinearizationOk = False
                 , draFallbackReason = Just ("gf_runtime:" <> err)
                 , draGenerationTrace = draGenerationTrace baseArtifact
                     <> [GenerationAttempt "pgf_claim_ast" ("error:" <> err)]
                 }
           }
    _ ->
      let baseArtifact = rsTemplateArtifact renderStatic
      in renderStatic
           { rsTemplateArtifact =
               baseArtifact
                 { draLinearizationLang = Just (langTag <> "_GF_PGF")
                 , draLinearizationOk = False
                 , draFallbackReason = Just "gf_runtime:unexpected_effect_result"
                 , draGenerationTrace = draGenerationTrace baseArtifact
                     <> [GenerationAttempt "pgf" "unexpected_effect_result"]
                 }
           }

normalizeGfLang :: Text -> Text
normalizeGfLang raw =
  case T.toLower (T.strip raw) of
    "ru" -> "QxFx0SyntaxRus"
    "russian" -> "QxFx0SyntaxRus"
    "en" -> "QxFx0SyntaxEng"
    "english" -> "QxFx0SyntaxEng"
    "qxfx0syntaxrus" -> "QxFx0SyntaxRus"
    "qxfx0syntaxeng" -> "QxFx0SyntaxEng"
    x | T.isPrefixOf "qxfx0syntax" x -> raw
    _ -> "QxFx0SyntaxRus"

gfLangTelemetryTag :: Text -> Text
gfLangTelemetryTag lang
  | normalized == "QxFx0SyntaxEng" = "en"
  | otherwise = "ru"
  where
    normalized = normalizeGfLang lang

detectInputGfLang :: Text -> Text
-- Language routing policy:
-- - Pure Latin input (no Cyrillic) → English GF path (QxFx0SyntaxEng)
-- - Any Cyrillic present → Russian GF path (QxFx0SyntaxRus)
-- This conservative policy prevents RU leakage on EN input by default.
-- Override via QXFX0_GF_LANG environment variable.
detectInputGfLang input
  | hasLatin && not hasCyrillic = "QxFx0SyntaxEng"
  | otherwise = "QxFx0SyntaxRus"
  where
    letters = T.filter isAlpha input
    hasLatin = T.any (\c -> ('a' <= c && c <= 'z') || ('A' <= c && c <= 'Z')) letters
    hasCyrillic = T.any (\c -> ('а' <= c && c <= 'я') || ('А' <= c && c <= 'Я') || c == 'ё' || c == 'Ё') letters

rebuildRenderWithBg :: RenderStatic -> Text -> Text
rebuildRenderWithBg renderStatic claimText =
  let renderWithContext =
        T.intercalate
          "\n"
          ( filter
              (not . T.null)
              [ rsModePrefixText renderStatic
              , rsAnchorPrefixText renderStatic
              , claimText
              ]
          )
      withNarrative =
        if T.null (rsNarrativeFragmentText renderStatic)
          then renderWithContext
          else renderWithContext <> "\n" <> T.take 80 (rsNarrativeFragmentText renderStatic)
  in if T.null (rsSurfacingFragmentText renderStatic)
       then withNarrative
       else withNarrative <> "\n" <> rsSurfacingFragmentText renderStatic
