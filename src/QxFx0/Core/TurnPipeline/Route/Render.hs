{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE StrictData #-}
{-# LANGUAGE DerivingStrategies #-}

{-| Route-stage rendering plan, effect resolution, and artifact assembly. -}
module QxFx0.Core.TurnPipeline.Route.Render
  ( RenderStatic(..)
  , LocalRecoveryPlan(..)
  , RenderEffectPlan(..)
  , RenderEffectResults(..)
  , planRenderEffects
  , planRenderEffectsForRuntime
  , resolveRenderEffects
  , buildTurnArtifacts
  ) where

import QxFx0.Types
import QxFx0.Core.TurnPipeline.Types
import QxFx0.Core.TurnPipeline.Effects
  ( TurnEffectRequest(..)
  , TurnEffectResult(..)
  )
import QxFx0.Core.Intuition (IntuitiveFlash(..))
import QxFx0.Core.PipelineIO
  ( PipelineIO
  , PipelineRuntimeMode(..)
  , resolveTurnEffect
  )
import QxFx0.Core.ConsciousnessLoop (ConsciousnessLoop(..))
import QxFx0.Core.Consciousness (ConsciousnessNarrative(..))
import qualified QxFx0.Core.Guard as Guard
import QxFx0.Core.BackgroundProcess (surfacingToFragment)
import QxFx0.Core.Observability
import QxFx0.Core.TurnLegitimacy (finalizeOutput)
import QxFx0.Core.TurnPlanning (integrateIdentityClaims)
import QxFx0.Core.TurnRender
  ( renderAnchorPrefix
  , renderPrincipledPrefix
  , renderStylePrefix
  , snapshotIdentitySignal
  )
import QxFx0.Core.TopicTransition (geodesicRouter)
import QxFx0.Semantic.Morphology (hasKnownMorphologyForm)
import QxFx0.Render.Dialogue
  ( DialogueRenderArtifact(..)
  , hasStructuredDialogueSurface
  , renderArtifactViaAssembly
  , renderDialogueArtifact
  )
import QxFx0.Semantic.Lexicon.RuntimeParadigms (RuntimeParadigms, emptyRuntimeParadigms)
import QxFx0.Semantic.Input.Parse (emptyParsedInput)
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
import QxFx0.ExceptionPolicy
  ( QxFx0Exception(PersistenceError)
  , throwQxFx0
  )

import Data.Char (isAlpha, isSpace)
import qualified Data.Foldable as F
import qualified Data.List as L
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock (UTCTime)

data RenderStatic = RenderStatic
  { rsRenderWithBg :: !Text
  , rsTemplateArtifact :: !DialogueRenderArtifact
  , rsPreferredGfLang :: !Text
  , rsModePrefixText :: !Text
  , rsAnchorPrefixText :: !Text
  , rsNarrativeFragmentText :: !Text
  , rsSurfacingFragmentText :: !Text
  } deriving stock (Eq, Show)

data LocalRecoveryPlan = LocalRecoveryPlan
  { lrpCause :: !LocalRecoveryCause
  , lrpStrategy :: !LocalRecoveryStrategy
  , lrpEvidence :: ![Text]
  , lrpSurface :: !Text
  } deriving stock (Eq, Show)

data RenderEffectPlan = RenderEffectPlan
  { repRenderStatic :: !RenderStatic
  , repLocalRecoveryPlan :: !(Maybe LocalRecoveryPlan)
  , repRenderMorphologyWarning :: !(Maybe Text)
  , repKnowledgeTopic :: !Text
  } deriving stock (Eq, Show)

data RenderTimeline = RenderTimeline
  { rtlRenderStart :: !UTCTime
  , rtlRenderEnd :: !UTCTime
  } deriving stock (Eq, Show)

data RenderEffectResults = RenderEffectResults
  { rerRenderTimeline :: !RenderTimeline
  , rerResolvedRenderStatic :: !(Maybe RenderStatic)
  , rerKnowledgeFact :: !(Maybe Text)
  , rerKnowledgeFactSource :: !(Maybe Text)
  } deriving stock (Eq, Show)

planRenderEffects :: RuntimeParadigms -> LocalRecoveryPolicy -> SystemState -> TurnInput -> TurnSignals -> TurnPlan -> RenderEffectPlan
planRenderEffects rp = planRenderEffectsForRuntimeImpl rp RuntimeStrict

-- COMPAT GLUE: old target callers expect 6-arg interface (no RuntimeParadigms).
planRenderEffectsForRuntime :: PipelineRuntimeMode -> LocalRecoveryPolicy -> SystemState -> TurnInput -> TurnSignals -> TurnPlan -> RenderEffectPlan
planRenderEffectsForRuntime = planRenderEffectsForRuntimeImpl emptyRuntimeParadigms

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
        case tpPrincipledMode tp of
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
      viaAssembly = renderArtifactViaAssembly rp ss (tiFrame ti) rmpAfterLegit rcpFinal
                        bestTopic identityClaims (ssMorphology ss) (rcpStyle rcpFinal) (emptyParsedInput input) mNarrative mGeodesicPlan
      assemblyFallbackReason = fromMaybe "assembly_empty_fallback" (draFallbackReason viaAssembly)
      dialogueArtifact
        | not (T.null (draRenderedText viaAssembly)) = viaAssembly
        | otherwise =
            (renderDialogueArtifact (tiFrame ti) rmpAfterLegit rcpFinal bestTopic identityClaims (ssMorphology ss))
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
      narrativeFragment = maybe "" id (tsNarrativeFragment ts)
      narrativeEnriched =
        if structuredSurface || T.null narrativeFragment
          then renderWithContext
          else renderWithContext <> "\n" <> T.take 40 narrativeFragment
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
          && ipfPropositionType (tiFrame ti) /= "PlainAssert"
      morphologyWarning =
        if T.any isSpace input
             && not structuredQuestion
             && not (T.null bestTopic)
             && not (hasKnownMorphologyForm (ssMorphology ss) bestTopic)
          then Just bestTopic
          else Nothing
      localRecoveryPlan =
        buildLocalRecoveryPlan runtimeMode localRecoveryPolicy ss ti tp morphologyWarning
  in RenderEffectPlan
      { repRenderStatic = RenderStatic
          { rsRenderWithBg = renderWithBg
          , rsTemplateArtifact = dialogueArtifact
          , rsPreferredGfLang = detectInputGfLang input
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
          , rsNarrativeFragmentText =
              if structuredSurface
                then ""
                else narrativeFragment
          , rsSurfacingFragmentText = surfacingFragment
          }
      , repLocalRecoveryPlan = localRecoveryPlan
      , repRenderMorphologyWarning = morphologyWarning
      , repKnowledgeTopic = bestTopic
       }

resolveRenderEffects :: PipelineIO -> RenderEffectPlan -> IO RenderEffectResults
resolveRenderEffects pio effectPlan = do
  tRender0 <- resolveRenderCurrentTime pio
  warnMorphologyFallback <- shouldWarnMorphologyFallback pio
  case repRenderMorphologyWarning effectPlan of
    Just bestTopic | warnMorphologyFallback ->
      hPutStrLnWarning ("Morphology fallback: unknown topic lexeme: " <> T.unpack bestTopic)
    _ ->
      pure ()

  resolvedRenderStatic <- resolveRuntimeGfLinearization pio (repRenderStatic effectPlan)
  -- WP3: Minimal legal DB adapter. Try legal lookup on the knowledge topic.
  -- For non-legal topics retrieveLegalFact returns Nothing; behavior is unchanged.
  mLegalFact <- retrieveLegalFact (repKnowledgeTopic effectPlan)
  let mKnowledgeFact = legalFactToKnowledgeFragment <$> mLegalFact
      mKnowledgeSource = lfSourceId <$> mLegalFact
  tRender1 <- resolveRenderCurrentTime pio
  pure RenderEffectResults
    { rerRenderTimeline = RenderTimeline
        { rtlRenderStart = tRender0
        , rtlRenderEnd = tRender1
        }
    , rerResolvedRenderStatic = resolvedRenderStatic
    , rerKnowledgeFact = mKnowledgeFact
    , rerKnowledgeFactSource = mKnowledgeSource
    }

buildTurnArtifacts :: SystemState -> TurnInput -> TurnSignals -> TurnPlan -> RenderEffectPlan -> RenderEffectResults -> TurnArtifacts
buildTurnArtifacts ss ti _ts tp effectPlan effectResults =
  let renderStatic = fromMaybe (repRenderStatic effectPlan) (rerResolvedRenderStatic effectResults)
      renderWithBg = rsRenderWithBg renderStatic
      localRecoveryPlan = repLocalRecoveryPlan effectPlan
      localRecoveryText = lrpSurface <$> localRecoveryPlan
      knowledgeFragment = maybe "" ("\n[знание] " <>) (rerKnowledgeFact effectResults)
      preSafetyRendered =
        case localRecoveryText of
          Just fb -> renderWithBg <> "\n" <> fb <> knowledgeFragment
          Nothing -> renderWithBg <> knowledgeFragment
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
      (renderedSurface, surfaceProv) = finalizeOutput preSafetySurface (F.toList (ssHistory ss))
      rendered = Guard.gsRenderedText renderedSurface
      finalRendered = rendered
      (recoveryCause, recoveryStrategy, recoveryEvidence) =
        case surfaceProv of
          FromRecovery ->
            (Just RecoveryRenderBlocked, Just StrategySafeRecovery, ["render_guard=blocked"])
          _ ->
            case localRecoveryPlan of
              Just plan -> (Just (lrpCause plan), Just (lrpStrategy plan), lrpEvidence plan)
              Nothing -> (Nothing, Nothing, [])
      decision = TurnDecision
        { tdFamily = case surfaceProv of FromRecovery -> CMRepair; _ -> tpFinalFamily tp
        , tdForce = case surfaceProv of FromRecovery -> IFOffer; _ -> tpFinalForce tp
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
  in TurnArtifacts
      { taPreSafetyRendered = preSafetyRendered
      , taGuardSurface = renderedSurface
      , taRendered = rendered
      , taSurfaceProv = surfaceProv
      , taFinalRendered = finalRendered
      , taClaimAst = draClaimAst (rsTemplateArtifact renderStatic)
      , taLinearizationLang = draLinearizationLang (rsTemplateArtifact renderStatic)
      , taLinearizationOk = draLinearizationOk (rsTemplateArtifact renderStatic)
      , taLinearizationFallbackReason = draFallbackReason (rsTemplateArtifact renderStatic)
      , taDecision = decision
      , taLocalRecoveryCause = recoveryCause
      , taLocalRecoveryStrategy = recoveryStrategy
      , taLocalRecoveryEvidence = recoveryEvidence
      , taMetrics = metrics4
      , taKnowledgeSource = rerKnowledgeFactSource effectResults
      }

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
      candidate =
        case () of
          _
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
            , lrpSurface = renderLocalRecoverySurface preferredLang cause strategy (tiBestTopic ti)
            })
        candidate

renderLocalRecoverySurface :: Text -> LocalRecoveryCause -> LocalRecoveryStrategy -> Text -> Text
renderLocalRecoverySurface gfLang _cause strategy topic =
  if gfLangTelemetryTag gfLang == "en"
    then renderLocalRecoverySurfaceEn strategy topic
    else renderLocalRecoverySurfaceRu strategy topic

renderLocalRecoverySurfaceRu :: LocalRecoveryStrategy -> Text -> Text
renderLocalRecoverySurfaceRu strategy topic =
  let topicText = if T.null topic then "этот вопрос" else topic
      header = "Локальный режим восстановления."
   in case strategy of
        StrategyAskClarification ->
          header <> " Уточни, тебе нужно определение, различение или пример по теме: " <> topicText <> "?"
        StrategyNarrowScope ->
          header <> " Я сужаю ответ до устойчивой части и не буду достраивать непроверенные выводы."
        StrategyDefineKnownTerms ->
          header <> " Я могу опереться только на известные локальные термины; для нового термина нужна рамка употребления: " <> topicText <> "."
        StrategyDistinguishCandidates ->
          header <> " Я различу возможные чтения и отмечу, где локальных данных недостаточно."
        StrategyExposeUncertainty ->
          header <> " Уверенность снижена; продолжу с явной пометкой неопределенности вместо внешней догадки."
        StrategySafeRecovery ->
          header <> " Ответ переведен в безопасную форму восстановления хода."

renderLocalRecoverySurfaceEn :: LocalRecoveryStrategy -> Text -> Text
renderLocalRecoverySurfaceEn strategy topic =
  let topicText = if T.null topic then "this question" else topic
      header = "Local recovery mode."
   in case strategy of
        StrategyAskClarification ->
          header <> " Clarify whether you need a definition, a distinction, or an example for: " <> topicText <> "."
        StrategyNarrowScope ->
          header <> " I will keep the answer within stable local evidence and avoid speculative completion."
        StrategyDefineKnownTerms ->
          header <> " I can rely only on known local terms; for a new term, provide usage context: " <> topicText <> "."
        StrategyDistinguishCandidates ->
          header <> " I will separate candidate readings and mark where local evidence is insufficient."
        StrategyExposeUncertainty ->
          header <> " Confidence is reduced; I will proceed with explicit uncertainty instead of external guessing."
        StrategySafeRecovery ->
          header <> " The response was switched to a safe recovery form."

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

resolveRenderCurrentTime :: PipelineIO -> IO UTCTime
resolveRenderCurrentTime pio = do
  result <- resolveTurnEffect pio TurnReqCurrentTime
  case result of
    TurnResCurrentTime currentTime -> pure currentTime
    _ -> throwQxFx0 (PersistenceError "render timeline current time effect returned unexpected result")

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
        TurnResLinearizeDialogAtoms (Right txt) | not (T.null (T.strip txt)) ->
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

applyRuntimeGfResult :: Text -> RenderStatic -> TurnEffectResult -> RenderStatic
applyRuntimeGfResult gfLang renderStatic result =
  let langTag = gfLangTelemetryTag gfLang
  in
  case result of
    TurnResLinearizeDialogAtoms (Right gfText)
      | not (T.null (T.strip gfText)) ->
          let baseArtifact = rsTemplateArtifact renderStatic
              updatedArtifact =
                baseArtifact
                  { draRenderedText = gfText
                  , draTemplateBodyText = gfText
                  , draLinearizationLang = Just (langTag <> "_GF_ATOMS")
                  , draLinearizationOk = True
                  , draFallbackReason = Nothing
                  }
          in renderStatic
               { rsTemplateArtifact = updatedArtifact
               , rsRenderWithBg = gfText
               }
    TurnResLinearizeClaimAst (Right gfText)
      | not (T.null (T.strip gfText)) ->
          let baseArtifact = rsTemplateArtifact renderStatic
              updatedArtifact =
                baseArtifact
                  { draRenderedText = gfText
                  , draTemplateBodyText = gfText
                  , draLinearizationLang = Just (langTag <> "_GF_PGF")
                  , draLinearizationOk = True
                  , draFallbackReason = Nothing
                  }
          in renderStatic
               { rsTemplateArtifact = updatedArtifact
               , rsRenderWithBg = rebuildRenderWithBg renderStatic gfText
               }
    TurnResLinearizeClaimAst (Left err) ->
      let baseArtifact = rsTemplateArtifact renderStatic
      in renderStatic
           { rsTemplateArtifact =
               baseArtifact
                 { draLinearizationLang = Just (langTag <> "_GF_PGF")
                 , draLinearizationOk = False
                 , draFallbackReason = Just ("gf_runtime:" <> err)
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
