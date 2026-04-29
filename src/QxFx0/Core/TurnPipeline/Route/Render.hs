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
import QxFx0.Core.Semantic.Morphology (hasKnownMorphologyForm)
import QxFx0.Core.Render.Dialogue
  ( DialogueRenderArtifact(..)
  , hasStructuredDialogueSurface
  , renderDialogueArtifact
  )
import QxFx0.Types.Text (finalizeForce)
import QxFx0.Types.Thresholds (parserLowConfidenceThreshold)
import QxFx0.Types.ShadowDivergence (ShadowDivergenceSeverity(..), shadowDivergenceSeverityText)
import QxFx0.ExceptionPolicy
  ( QxFx0Exception(PersistenceError)
  , throwQxFx0
  )

import Data.Char (isSpace)
import qualified Data.Foldable as F
import qualified Data.List as L
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock (UTCTime)

data RenderStatic = RenderStatic
  { rsRenderWithBg :: !Text
  , rsTemplateArtifact :: !DialogueRenderArtifact
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
  } deriving stock (Eq, Show)

data RenderTimeline = RenderTimeline
  { rtlRenderStart :: !UTCTime
  , rtlRenderEnd :: !UTCTime
  } deriving stock (Eq, Show)

data RenderEffectResults = RenderEffectResults
  { rerRenderTimeline :: !RenderTimeline
  , rerResolvedRenderStatic :: !(Maybe RenderStatic)
  } deriving stock (Eq, Show)

planRenderEffects :: LocalRecoveryPolicy -> SystemState -> TurnInput -> TurnSignals -> TurnPlan -> RenderEffectPlan
planRenderEffects = planRenderEffectsForRuntime RuntimeStrict

planRenderEffectsForRuntime :: PipelineRuntimeMode -> LocalRecoveryPolicy -> SystemState -> TurnInput -> TurnSignals -> TurnPlan -> RenderEffectPlan
planRenderEffectsForRuntime runtimeMode localRecoveryPolicy ss ti ts tp =
  let bestTopic = tiBestTopic ti
      mFlash = tsFlash ts
      consciousLoop' = tsConsciousLoop' ts
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
      dialogueArtifact =
        renderDialogueArtifact (tiFrame ti) rmpAfterLegit rcpFinal bestTopic identityClaims (ssMorphology ss)
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
      renderWithContext =
        let modePrefix =
              if structuredSurface
                then ""
                else maybe "" (renderPrincipledPrefix mPressure) principledModeResult
            stylePrefix =
              if structuredSurface
                then ""
                else renderStylePrefix (rcpStyle rcpFinal)
            anchorPrefixAllowed =
              not structuredSurface && tpFinalFamily tp == CMAnchor
            anchorPrefix =
              if not anchorPrefixAllowed
                then ""
                else maybe "" renderAnchorPrefix semanticAnchor
        in T.intercalate "\n" (filter (not . T.null) [stylePrefix, modePrefix, anchorPrefix, finalRender])
      narrativeFragment = maybe "" id (tsNarrativeFragment ts)
      narrativeEnriched =
        if structuredSurface || T.null narrativeFragment
          then renderWithContext
          else renderWithContext <> "\n" <> T.take 80 narrativeFragment
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
  tRender1 <- resolveRenderCurrentTime pio
  pure RenderEffectResults
    { rerRenderTimeline = RenderTimeline
        { rtlRenderStart = tRender0
        , rtlRenderEnd = tRender1
        }
    , rerResolvedRenderStatic = resolvedRenderStatic
    }

buildTurnArtifacts :: SystemState -> TurnInput -> TurnSignals -> TurnPlan -> RenderEffectPlan -> RenderEffectResults -> TurnArtifacts
buildTurnArtifacts ss ti _ts tp effectPlan effectResults =
  let renderStatic = fromMaybe (repRenderStatic effectPlan) (rerResolvedRenderStatic effectResults)
      renderWithBg = rsRenderWithBg renderStatic
      localRecoveryPlan = repLocalRecoveryPlan effectPlan
      localRecoveryText = lrpSurface <$> localRecoveryPlan
      preSafetyRendered =
        case localRecoveryText of
          Just fb -> renderWithBg <> "\n" <> fb
          Nothing -> renderWithBg
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
          LocalRecoveryPlan
            { lrpCause = cause
            , lrpStrategy = strategy
            , lrpEvidence = evidence
            , lrpSurface = renderLocalRecoverySurface cause strategy (tiBestTopic ti)
            })
        candidate

renderLocalRecoverySurface :: LocalRecoveryCause -> LocalRecoveryStrategy -> Text -> Text
renderLocalRecoverySurface _cause strategy topic =
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
    else
      case draClaimAst (rsTemplateArtifact renderStatic) of
        Nothing -> pure Nothing
        Just claimAst -> do
          mPgfPath <- resolveGfPgfPath pio
          result <- resolveTurnEffect pio (TurnReqLinearizeClaimAst mPgfPath claimAst)
          pure (Just (applyRuntimeGfResult renderStatic result))

shouldUseGfRuntime :: PipelineIO -> IO Bool
shouldUseGfRuntime pio = do
  result <- resolveTurnEffect pio (TurnReqReadEnv "QXFX0_GF_RUNTIME")
  case result of
    TurnResReadEnv (Just rawValue) ->
      pure (normalizeBool rawValue)
    _ ->
      pure False

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

applyRuntimeGfResult :: RenderStatic -> TurnEffectResult -> RenderStatic
applyRuntimeGfResult renderStatic result =
  case result of
    TurnResLinearizeClaimAst (Right gfText)
      | not (T.null (T.strip gfText)) ->
          let baseArtifact = rsTemplateArtifact renderStatic
              updatedArtifact =
                baseArtifact
                  { draRenderedText = gfText
                  , draTemplateBodyText = gfText
                  , draLinearizationLang = Just "ru_GF_PGF"
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
                 { draLinearizationLang = Just "ru_GF_PGF"
                 , draLinearizationOk = False
                 , draFallbackReason = Just ("gf_runtime:" <> err)
                 }
           }
    _ ->
      let baseArtifact = rsTemplateArtifact renderStatic
      in renderStatic
           { rsTemplateArtifact =
               baseArtifact
                 { draLinearizationLang = Just "ru_GF_PGF"
                 , draLinearizationOk = False
                 , draFallbackReason = Just "gf_runtime:unexpected_effect_result"
                 }
           }

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
