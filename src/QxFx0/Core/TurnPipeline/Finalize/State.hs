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
import QxFx0.Types.ExternalQuery (renderExternalQueryError)
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
import QxFx0.Self.Field (adaptFieldHeuristics, Field(..), fieldCounterfactual, Counterfactual(..))
import QxFx0.Learning.Need (detectLearningNeed)
import QxFx0.Learning.Signal (CalibrationSignal(..), computeCalibrationSignal, emptySignalComponents)
import QxFx0.Learning.KnowledgeTree
  ( KnowledgeTree(..)
  , emptyKnowledgeTree
  , graftFruit
  , quarantineFruit
  , promoteFromQuarantine
  , pruneBranches
  , pruneFruits
  , rootStressSignal
  )
import QxFx0.Self.Essence
  ( EssenceCommitment(..)
  , EssenceMode(..)
  , renderEssenceMode
  , renderCommitmentTrigger
  )
import QxFx0.Semantic.AtomAccretion
  ( observeNovelAtom
  , promoteProvisionalAtoms
  , decayProvisionalAtoms
  , resolveCollisions
  )
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
      -- Phase 7: bounded calibration signal + rooted tree maintenance.
      -- Compute signal from conatus trend, uncertainty, loop risk,
      -- and branch health.  Only adapt when committed.
      (adaptedWeights, adaptedHeuristics, nextTree, _signalComponents) =
        case nextEssence of
          EssenceCommitted _ commitment ->
            let -- Extract counterfactual from the pre-turn Field
                counterfactual =
                  case tiField ti of
                    field -> unCounterfactual (fieldCounterfactual field)
                -- Proxy loop risk: blocked-concept count / 10 (window)
                loopCount = length (ssBlockedConcepts ss)
                windowSize = 10
                (calSignal, sigComps) =
                  computeCalibrationSignal
                    (ssLearningNeedState ss)
                    counterfactual
                    loopCount
                    windowSize
                    (ssKnowledgeTree ss)
                signal = unCalibrationSignal calSignal
                -- Update knowledge tree root from commitment
                treeWithRoot =
                  (ssKnowledgeTree ss)
                    { ktRootMode = renderEssenceMode (ecMode commitment)
                    , ktRootTrigger = renderCommitmentTrigger (ecTrigger commitment)
                    }
                -- Structural maintenance: prune stale fruits and branches
                currentTurn = ssTurnCount ss + 1
                (treePruned, _prunedBranches) =
                  pruneBranches currentTurn (-0.5) 3 treeWithRoot
                (treeClean, _prunedFruits) =
                  pruneFruits currentTurn treePruned
            in ( adaptSalienceWeights signal (ssSalienceWeights ss)
               , adaptFieldHeuristics signal (ssFieldHeuristics ss)
               , treeClean
               , sigComps
               )
          _ -> (ssSalienceWeights ss, ssFieldHeuristics ss, ssKnowledgeTree ss, emptySignalComponents)
      -- WP1: endogenous learning diagnostic drive.
      newLearningNeedState =
         detectLearningNeed
           (tiConatusEnergy ti)
           (tiField ti)
           0 -- repairCount: historical recovery tracking deferred to Phase 7
           (length (ssBlockedConcepts ss)) -- proxy: blocked concepts indicate substrate gaps
           (ssTurnCount ss + 1)
           (ssLearningNeedState ss)
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
      , ssShadowVetoState = tpShadowVetoState tp
      , ssProvisionalAtoms =
          let currentTurn = ssTurnCount ss
              canonicalSet = tiAtomSet ti
              observed = foldr
                (\atom acc -> observeNovelAtom (maTag atom) currentTurn acc)
                (ssProvisionalAtoms ss)
                (asAtoms canonicalSet)
              decayed = decayProvisionalAtoms currentTurn observed
              (remaining, _promoted) = promoteProvisionalAtoms currentTurn decayed
          in resolveCollisions canonicalSet remaining
      , ssLearningNeedState = newLearningNeedState
      , ssGuardrailState = ssGuardrailState ss
        -- ^ WP5: guardrails currently pass through unchanged;
        --   proposal-submission tracking will be wired when the
        --   external-tool bridge is integrated.
      , ssCalibrationLog = ssCalibrationLog ss
        -- ^ WP4: calibration ledger currently pass through unchanged;
        --   accept/rollback mutations will be wired when the
        --   verify/simulate/accept loop is integrated end-to-end.
      , ssKnowledgeTree = nextTree
        -- ^ Phase 7: rooted knowledge tree.  Root updated from
        --   committed essence; structural pruning applied each turn.
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
            , trcLearningQueryType =
                case (taExternalQueryResult ta, taExploratoryQueryResult ta) of
                  (Nothing, Nothing)       -> Nothing
                  (Just _, Nothing)        -> Just "request_concept"
                  (Nothing, Just _)        -> Just "exploratory"
                  (Just _, Just _)         -> Just "both"
            , trcExternalTool =
                case taExternalQueryResult ta of
                  Just (Right resp) -> Just (eqrToolName resp)
                  _ -> case taExploratoryQueryResult ta of
                         Just (Right resp) -> Just (eqrToolName resp)
                         _ -> Nothing
            , trcLearningValidationStatus =
                case (taExternalQueryResult ta, taExploratoryQueryResult ta) of
                  (Nothing, Nothing)       -> Just "not_attempted"
                  (Just (Left _), _)       -> Just "transport_error"
                  (Just (Right _), _)      -> Just "pending_validation"
                  (Nothing, Just (Left _)) -> Just "exploratory_transport_error"
                  (Nothing, Just (Right _)) -> Just "exploratory_pending_validation"
            , trcLearningSandboxResult = Nothing
            , trcLearningGraftTurn = Nothing
            , trcLearningRejectReason =
                case taExternalQueryResult ta of
                  Just (Left err) -> Just (renderExternalQueryError err)
                  _ -> case taExploratoryQueryResult ta of
                         Just (Left err) -> Just (T.concat ["exploratory:", renderExternalQueryError err])
                         _ -> Nothing
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
