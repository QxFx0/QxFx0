{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE StrictData #-}

{-| Finalize-stage construction of persisted state, projection, output, and final metrics. -}
module QxFx0.Core.TurnPipeline.Finalize.State
  ( buildNextSystemState
  , buildTurnProjection
  , buildFinalOutput
  , finalizeMetrics
  , computeEssenceValidation
  ) where

import QxFx0.Types
import QxFx0.Types.Thresholds
  ( legitimacyPassThreshold
  , legitimacyRecoveryThreshold
  , parserLowConfidenceThreshold
  , scenePressureLowThreshold
  , scenePressureMediumThreshold
  , ScenePressure(..)
  , LegitimacyStatus(..)
  , blockedConceptsRetentionLimit
  , recentFamiliesLimit
  , rawInputHistoryLimit
  )
import QxFx0.Core.TurnPipeline.Types
import QxFx0.Core.TurnRender (updateStateNixCache)
import qualified QxFx0.Core.Guard as Guard
import QxFx0.Core.TurnLegitimacy (safeOutputText)
import QxFx0.Core.Observability
import QxFx0.Core.Intuition (IntuitiveFlash(..))
import QxFx0.Render.Semantic (renderSemanticIntrospection)
import QxFx0.Semantic.Embedding (embeddingQualityText)
import QxFx0.Self.Salience
  ( Salience (..)
  , renderSalienceDriver
  , salienceFromConatusEnergy
  , isHolisticFamily
  )
import QxFx0.Self.Deliberation
  ( renderAgreement
  , renderReconcileRule
  , renderNarrativeTone
  , Deliberation(..)
  , DeliberationTrace(..)
  , Plan(..)
  , defaultDeliberation
  )
import QxFx0.Self.Essence
  ( Essence(..)
  , EssenceMode (..)
  , EssenceTrajectory (..)
  , EssenceCommitment (..)
  , CommitmentTrigger (..)
  , EssenceViolation(..)
  , defaultEssenceModulation
  , renderEssenceMode
  , renderCommitmentTrigger
  , shouldCommit
  , commit
  , validatePlan
  , witness
  )
import QxFx0.Self.Salience (adaptSalienceWeights)
import QxFx0.Self.Field (adaptFieldHeuristics)
import QxFx0.Types.Text (textShow)

import Data.Maybe (fromMaybe)
import Data.Sequence (Seq)
import qualified Data.Foldable as F
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock (UTCTime)

-- | Local helper: derive the canonical pre-turn Salience verdict
-- from a 'TurnInput'.  Used by both 'buildNextSystemState' (for
-- 'dsLastSalienceBias' on the persisted state) and
-- 'buildTurnProjection' (for the @trcSalience*@ trace fields).
-- Computed identically in both call sites; centralised here so
-- they cannot drift.
turnInputSalience :: TurnInput -> Salience
turnInputSalience ti = salienceFromConatusEnergy (tiConatusEnergy ti) (tiField ti)

-- | WP1 (contour closure): validate the reconciled 'Plan' against a
-- pre-turn committed essence.  Only runs when the pre-turn state
-- is already 'EssenceCommitted' — the commitment itself is law-driven
-- in 'buildNextSystemState' and does not depend on a feature flag.
computeEssenceValidation
  :: TurnInput
  -> TurnPlan
  -> Essence          -- ^ post-'buildNextSystemState' essence
  -> Maybe CommitmentTrigger
  -> Either EssenceViolation ()
computeEssenceValidation ti tp nextEssence mTrigger =
  case (mTrigger, nextEssence) of
    (Just trigger, EssenceUncommitted _) ->
      Left (ViolationRefusedCommitment trigger)
    (_, EssenceCommitted _ commitment)
      | Just delib <- tpDeliberation tp
      -> case validatePlan commitment (delibReconciled delib) of
           Right _ -> Right ()
           Left v  -> Left v
    _ -> Right ()

buildNextSystemState :: (Text -> Seq Text -> Seq Text) -> SystemState -> TurnInput -> TurnSignals -> TurnPlan -> TurnArtifacts -> DreamState -> MeaningGraph -> CanonicalMoveFamily -> R5Verdict -> Int -> (SystemState, Maybe CommitmentTrigger)
buildNextSystemState updateHistory ss ti ts tp ta newDreamState newMeaningGraph outcomeFamily outcomeVerdict consecReflect =
  let !newHumanHistory = updateHistory (ipfRawText (tiFrame ti)) (ssHistory ss)
      updatedNixCache = updateStateNixCache (tiConceptToCheck ti) (tiNixStatus ti) (obsNixCache (ssObservability ss))
      turnSalience = turnInputSalience ti
      newHolisticStreak = if isHolisticFamily outcomeFamily then ssHolisticStreak ss + 1 else 0
      narrativeSuccess = maybe False (not . T.null) (tsNarrativeFragment ts)
      newNarrativeSuccess = take 5 (narrativeSuccess : ssRecentNarrativeSuccess ss)
      -- WP1 (contour closure): law-driven commitment.
      -- 'shouldCommit' is always evaluated; no feature flag.
      -- The trigger (if any) is exposed for downstream validation.
      (nextEssence, commitmentTrigger) =
        case tiEssence ti of
          EssenceUncommitted trajectory ->
            let trajectory' =
                  witness
                    defaultEssenceModulation
                    (ssTurnCount ss + 1)
                    (tiConatusEnergy ti)
                    (tiField ti)
                    (fromMaybe defaultDeliberation (tpDeliberation tp))
                    trajectory
            in case shouldCommit defaultEssenceModulation trajectory' of
                 Nothing      -> (EssenceUncommitted trajectory', Nothing)
                 Just trigger ->
                   ( EssenceCommitted
                       trajectory'
                       (commit (ssTurnCount ss + 1) trigger trajectory')
                   , Just trigger
                   )
          EssenceCommitted trajectory commitment ->
             -- Sticky: committed essences are never reverted. We still
             -- ingest a witness so etAngstLevel/etConatusFloor track
             -- post-commit deliberation for diagnostics.
             let trajectory' =
                   witness
                     defaultEssenceModulation
                     (ssTurnCount ss + 1)
                     (tiConatusEnergy ti)
                     (tiField ti)
                     (fromMaybe defaultDeliberation (tpDeliberation tp))
                     trajectory
             in (EssenceCommitted trajectory' commitment, Nothing)
      -- Phase-B: post-commitment bounded self-tuning.
      -- Empirical signal generation is deferred to Phase 7;
      -- signal=0.0 means no drift until calibration is available.
      (adaptedWeights, adaptedHeuristics) =
        case nextEssence of
          EssenceCommitted _ _ ->
            let signal = 0.0
            in ( adaptSalienceWeights signal (ssSalienceWeights ss)
               , adaptFieldHeuristics signal (ssFieldHeuristics ss)
               )
          _ -> (ssSalienceWeights ss, ssFieldHeuristics ss)
    in ( ss
       { ssDialogue = (ssDialogue ss)
          { dsHistory = newHumanHistory
          , dsActiveScene = tpActiveScene tp
          , dsLastFamily = outcomeFamily
          , dsLastTopic = tiBestTopic ti
          , dsUserState = tiNextUserState ti
          , dsLastForce = r5Force outcomeVerdict
          , dsLastLayer = r5Layer outcomeVerdict
          , dsRecentFamilies = take recentFamiliesLimit (outcomeFamily : ssRecentFamilies ss)
          , dsRawInputHistory = appendHistoryBounded rawInputHistoryLimit (ssRawInputHistory ss) (ipfRawText (tiFrame ti))
          , dsTurnCount = ssTurnCount ss + 1
          , dsConsecutiveReflect = consecReflect
          , dsLastEmbedding = Just (tiEmbedding ti)
          , dsLastSalienceBias = salienceHolisticBias turnSalience
          , dsHolisticStreak = newHolisticStreak
          , dsRecentNarrativeSuccess = newNarrativeSuccess
          }
      , ssIdentity = (ssIdentity ss)
          { idsEgo = tpNewEgo tp
          , idsOrbitalMemory = tpUpdatedOrbital tp
          , idsLastGuardReport = Just (tpGuardReport tp)
          }
      , ssSemantic = (ssSemantic ss)
          { semTrace = tiNewTrace ti
          , semMeaningGraph = newMeaningGraph
          , semDreamState = newDreamState
          , semIntuitionState = Just (tsIntuitionState ts)
          , semKernelPulse = (ssKernelPulse ss) { kpActive = True, kpLastUpdate = ssTurnCount ss + 1 }
          , semBlockedConcepts =
              case tiNixStatus ti of
                Blocked reason -> retainBlockedConcepts reason (ssBlockedConcepts ss)
                _ -> ssBlockedConcepts ss
          , semIntuitConfidence = tsIntuitPosterior ts
          , semSemanticAnchor = tpSemanticAnchor tp
          , semLastTurnDecision = Just (taDecision ta)
          }
      , ssObservability = (ssObservability ss)
          { obsNixCache = updatedNixCache
          , obsTelemetry = (obsTelemetry (ssObservability ss))
              { lrtFamily = outcomeFamily
              , lrtTopic = tiBestTopic ti
              , lrtApiHealthy = tsApiHealthy ts
              , lrtGuardStatus = tdGuardStatus (taDecision ta)
              , lrtSurfaceRoute = taSurfaceProv ta
              }
          , obsEmbeddingApiHealthy = tsApiHealthy ts
          , obsLastLegitimacyScore = tpLegitScore tp
          }
      , ssEssence = nextEssence
      , ssSalienceWeights = adaptedWeights
      , ssFieldHeuristics = adaptedHeuristics
      }
    , commitmentTrigger
    )

buildTurnProjection
  :: Text
  -> Text
  -> Text
  -> Bool
  -> Bool
  -> SystemState
  -> TurnInput
  -> TurnSignals
  -> TurnPlan
  -> TurnArtifacts
  -> TurnProjection
buildTurnProjection runtimeMode shadowPolicy localRecoveryPolicy semanticIntrospectionEnabled warnMorphologyFallbackEnabled nextSs ti ts tp ta =
  let decision = taDecision ta
      parserConfidence = ipfConfidence (tiFrame ti)
      parserErrors = if parserConfidence < parserLowConfidenceThreshold then ["low_confidence"] else []
      scenePressure
        | asLoad (tiAtomSet ti) <= scenePressureLowThreshold = PressureLow
        | asLoad (tiAtomSet ti) <= scenePressureMediumThreshold = PressureMedium
        | otherwise = PressureHigh
      legitScore = tpLegitScore tp
      legitimacyStatus
        | legitScore >= legitimacyPassThreshold = LegitimacyPass
        | legitScore >= legitimacyRecoveryThreshold = LegitimacyDegraded
        | otherwise = LegitimacyRecovery
      legitimacyReason
        | tpShadowGateTriggered tp = ReasonShadowDivergence
        | tpShadowStatus tp == ShadowUnavailable = ReasonShadowUnavailable
        | parserConfidence < parserLowConfidenceThreshold = ReasonLowParserConfidence
        | otherwise = ReasonOk
      ownerFamily = tdFamily decision
      ownerForce = tdForce decision
      warrantedMode = warrantedForFamily ownerFamily
      legitimacyOutcome = classifyLegitimacyOutcome legitimacyStatus legitimacyReason warrantedMode (tpShadowStatus tp) (tpShadowDivergenceSeverity tp)
      requestId = tmRequestId (tiMetrics ti)
      sessionId = tmSessionId (tiMetrics ti)
      intuitionHint = ifDirective <$> tsFlash ts
      (recoveryCause, recoveryStrategy, recoveryEvidence) =
        case taLocalRecoveryCause ta of
          Just cause ->
            (Just cause, taLocalRecoveryStrategy ta, taLocalRecoveryEvidence ta)
          Nothing
            | runtimeMode == "degraded" ->
                (Just RecoveryRuntimeDegraded, Just StrategyNarrowScope, ["runtime_mode=degraded"])
          Nothing ->
            (Nothing, Nothing, [])
      -- Canonical trace Salience.  The Conatus and Field values
      -- are the pre-turn snapshot (single source of truth from
      -- 'PrepareStatic') so the trace reflects the actual signals
      -- that drove the routing decision.
      traceSalience   = turnInputSalience ti
      postEssence = ssEssence nextSs
      (modeTag, committedFlag, angst, triggerTag) = case postEssence of
        EssenceUncommitted t ->
          ( Just (renderEssenceMode EssenceWitnessing)
          , Just False
          , Just (etAngstLevel t)
          , Nothing
          )
        EssenceCommitted t c ->
          ( Just (renderEssenceMode (ecMode c))
          , Just True
          , Just (etAngstLevel t)
          , Just (renderCommitmentTrigger (ecTrigger c))
          )
      replayTrace =
        TurnReplayTrace
          { trcRequestId = requestId
          , trcSessionId = sessionId
          , trcRuntimeMode = runtimeMode
          , trcShadowPolicy = shadowPolicy
          , trcLocalRecoveryPolicy = localRecoveryPolicy
          , trcRecoveryCause = recoveryCause
          , trcRecoveryStrategy = recoveryStrategy
          , trcRecoveryEvidence = recoveryEvidence
          , trcSemanticIntrospectionEnabled = semanticIntrospectionEnabled
          , trcWarnMorphologyFallbackEnabled = warnMorphologyFallbackEnabled
          , trcRequestedFamily = tiRecommendedFamily ti
          , trcStrategyFamily = tpStrategyFamily tp
          , trcNarrativeHint = tsNarrativeFragment ts
          , trcIntuitionHint = intuitionHint
          , trcPreShadowFamily = tpPreShadowFamily tp
          , trcShadowSnapshotId = tpShadowSnapshotId tp
          , trcShadowStatus = tpShadowStatus tp
          , trcShadowDivergenceKind = tpShadowDivergenceKind tp
          , trcShadowDivergenceSeverity = tpShadowDivergenceSeverity tp
          , trcShadowResolvedFamily = tpFamily tp
          , trcFinalFamily = tdFamily decision
          , trcFinalForce = tdForce decision
          , trcDecisionDisposition = loDisposition legitimacyOutcome
          , trcLegitimacyReason = legitimacyReason
          , trcParserConfidence = parserConfidence
          , trcEmbeddingQuality = embeddingQualityText (tiEmbeddingQuality ti)
          , trcClaimAst = taClaimAst ta
          , trcLinearizationLang = taLinearizationLang ta
          , trcLinearizationOk = taLinearizationOk ta
          , trcFallbackReason = taLinearizationFallbackReason ta
           , trcSalienceDriver = renderSalienceDriver (salienceDriver traceSalience)
           , trcSalienceHolisticBias = salienceHolisticBias traceSalience
           , trcSalienceConfidence = salienceConfidence traceSalience
           , trcDeliberationRule =
               tpDeliberation tp >>= \d ->
                 Just (renderReconcileRule (dtRule (delibTrace d)))
           , trcDeliberationAgreement =
               tpDeliberation tp >>= \d ->
                 Just (renderAgreement (dtAgreement (delibTrace d)))
           , trcDeliberationDivergence =
               tpDeliberation tp >>= \d ->
                 Just (dtDivergence (delibTrace d))
            , trcDeliberationNarrativeTone =
                tpDeliberation tp >>= \d ->
                  Just (renderNarrativeTone (planNarrativeTone (delibReconciled d)))
            , trcEssenceMode = modeTag
            , trcEssenceCommitted = committedFlag
            , trcEssenceAngstLevel = angst
            , trcEssenceTrigger = triggerTag
            }
  in TurnProjection
      { tqpTurn = ssTurnCount nextSs
      , tqpParserMode = ParserFrameV1
      , tqpParserConfidence = parserConfidence
      , tqpParserErrors = parserErrors
      , tqpPlannerMode = case tpPrincipledModePair tp of Just _ -> PrincipledPlanner; Nothing -> DefaultPlanner
      , tqpPlannerDecision = tpFamily tp
      , tqpAtomRegister = asRegister (tiAtomSet ti)
      , tqpAtomLoad = asLoad (tiAtomSet ti)
      , tqpScenePressure = scenePressure
      , tqpSceneRequest = tiBestTopic ti
      , tqpSceneStance = usNeedLayer (tiNextUserState ti)
      , tqpRenderLane = rsMove (tpRenderStrategy tp)
      , tqpRenderStyle = tdRenderStyle decision
      , tqpLegitimacyStatus = legitimacyStatus
      , tqpLegitimacyReason = legitimacyReason
      , tqpWarrantedMode = warrantedMode
      , tqpDecisionDisposition = loDisposition legitimacyOutcome
      , tqpOwnerFamily = ownerFamily
      , tqpOwnerForce = ownerForce
      , tqpShadowStatus = tpShadowStatus tp
      , tqpShadowSnapshotId = tpShadowSnapshotId tp
      , tqpShadowDivergenceKind = tpShadowDivergenceKind tp
      , tqpShadowFamily = tpShadowFamily tp
      , tqpShadowForce = tpShadowForce tp
      , tqpShadowMessage = tpShadowMessage tp
      , tqpReplayTrace = replayTrace
      , tqpDivergence = tpShadowDivergence tp
      }

buildFinalOutput :: Bool -> SystemState -> Guard.GuardSurface -> SystemState -> (Text, Guard.SafetyStatus)
buildFinalOutput wantIntrospection ss baseSurface nextSs =
  let preIntrospectionSurface =
        if wantIntrospection
          then
            let introspectionText = renderSemanticIntrospection nextSs
            in baseSurface
                { Guard.gsRenderedText = Guard.gsRenderedText baseSurface <> "\n" <> introspectionText
                , Guard.gsSegments = Guard.gsSegments baseSurface <> [Guard.RenderSegment Guard.SegmentIntrospection introspectionText]
                }
          else baseSurface
      finalSafetyStatus = Guard.postRenderSafetyCheckSurface preIntrospectionSurface (F.toList (ssHistory ss))
      outputText = safeOutputText preIntrospectionSurface baseSurface finalSafetyStatus
  in (outputText, finalSafetyStatus)

finalizeMetrics :: TurnInput -> TurnArtifacts -> CanonicalMoveFamily -> TurnDecision -> SystemState -> Bool -> Guard.SafetyStatus -> UTCTime -> UTCTime -> TurnMetrics
finalizeMetrics ti ta outcomeFamily decision savedSs apiHealthy finalSafetyStatus tSave0 tSave1 =
  let !metrics5 =
        addPhase (recordPhase "save_state" tSave0 tSave1)
          $ (taMetrics ta)
              { tmTurnCount = ssTurnCount savedSs
              , tmFamily = textShow outcomeFamily
              , tmNixStatus = textShow (tdGuardStatus decision)
              , tmSafetyStatus = textShow finalSafetyStatus
              , tmApiHealthy = apiHealthy
              }
      !metricsFinal = addPhase (recordPhase "total" (tiStartTime ti) tSave1) metrics5
  in metricsFinal

retainBlockedConcepts :: Text -> [Text] -> [Text]
retainBlockedConcepts latestReason existing =
  take blockedConceptsRetentionLimit (dedupePreservingOrder (latestReason : existing))

dedupePreservingOrder :: [Text] -> [Text]
dedupePreservingOrder = go Set.empty
  where
    go _ [] = []
    go seen (value : rest)
      | value `Set.member` seen = go seen rest
      | otherwise = value : go (Set.insert value seen) rest
