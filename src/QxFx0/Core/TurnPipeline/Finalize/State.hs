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
import QxFx0.Types.State.System (appendAdaptiveMutationRecords)
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
import QxFx0.Semantic.Sense (rspChosenOperator, rspInputVector, rspPreservedAxes, svAnchor, unSemanticNodeId)
import QxFx0.Self.Salience
  ( Salience (..)
  , SalienceWeights(..)
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
import QxFx0.Self.Perspective (buildActivePerspectiveProjections)
import QxFx0.Self.Field (adaptFieldHeuristics, Field(..), FieldHeuristics(..), fieldCounterfactual, Counterfactual(..))
import QxFx0.Learning.Need
  ( detectLearningNeedWithPressure
  , defaultLearningPressureConfig
  , LearningNeed(..)
  , LearningNeedState(..)
  , renderLearningNeed
  )
import QxFx0.Learning.Calibration
  ( CalibrationId(..)
  , CalibrationEntry(..)
  , CalibrationLog(..)
  , CalibrationProposal(..)
  , acceptProposal
  , currentCalibrationVersion
  )
import QxFx0.Learning.Signal
  ( CalibrationDecision(..)
  , CalibrationSignal(..)
  , CalibrationSnapshot(..)
  , SignalComponents(..)
  , applyCalibrationGated
  , computeCalibrationSignal
  , defaultSignalPipelineConfig
  , emptySignalComponents
  )
import QxFx0.Learning.KnowledgeTree
  ( KnowledgeTree(..)
  , emptyKnowledgeTree
  , graftFruit
  , quarantineFruit
  , promoteFromQuarantine
  , pruneBranches
  , pruneFruits
  , rootStressSignal
  , isTermKnownInKnowledgeTree
  , ktGraftedCount
  )
import QxFx0.Semantic.Morphology (hasKnownMorphologyForm)
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
import QxFx0.Types.State.DialogueDevelopment
  ( CommitmentStatus(..)
  , DialogueCommitment(..)
  , DialogueCommitmentLedger(..)
  , DialoguePhase(..)
  , DialogueThread(..)
  )

import Data.Maybe (fromMaybe)
import Control.Applicative ((<|>))
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

selfTuningMutationRecords
  :: Int
  -> Double
  -> SignalComponents
  -> SalienceWeights
  -> FieldHeuristics
  -> SalienceWeights
  -> FieldHeuristics
  -> [AdaptiveMutationRecord]
selfTuningMutationRecords turn signal comps newWeights newHeuristics oldWeights oldHeuristics =
  salienceRecord <> fieldRecord
  where
    signalEvidence =
      [ "signal=" <> textShow signal
      , "conatus=" <> textShow (scConatusTrend comps)
      , "uncertainty=" <> textShow (scUncertaintyTrend comps)
      , "loop=" <> textShow (scLoopRisk comps)
      , "branch=" <> textShow (scBranchHealthTrend comps)
      ]
    strength = if abs signal >= 0.15 then EvidenceStrong else EvidenceWeak
    decision = if abs signal >= 0.15 then AdaptiveAccepted else AdaptiveObserved
    salienceDelta = salienceWeightsMaxDelta oldWeights newWeights
    fieldDelta = fieldHeuristicsMaxDelta oldHeuristics newHeuristics
    salienceRecord =
      if oldWeights == newWeights
        then []
        else
          [ AdaptiveMutationRecord
              { amrTurnId = turn
              , amrKind = MutSalienceWeights
              , amrCause = "finalize:bounded_salience_adaptation"
              , amrEvidence = signalEvidence
              , amrEvidenceStrength = strength
              , amrConfidence = min 1.0 (abs signal)
              , amrBoundedDelta = Just salienceDelta
              , amrDecision = decision
              }
          ]
    fieldRecord =
      if oldHeuristics == newHeuristics
        then []
        else
          [ AdaptiveMutationRecord
              { amrTurnId = turn
              , amrKind = MutFieldHeuristics
              , amrCause = "finalize:bounded_field_heuristics_adaptation"
              , amrEvidence = signalEvidence
              , amrEvidenceStrength = strength
              , amrConfidence = min 1.0 (abs signal)
              , amrBoundedDelta = Just fieldDelta
              , amrDecision = decision
              }
          ]

knowledgeMaintenanceMutationRecords :: Int -> Int -> Int -> [AdaptiveMutationRecord]
knowledgeMaintenanceMutationRecords turn prunedBranches prunedFruits =
  if prunedBranches <= 0 && prunedFruits <= 0
    then []
    else
      [ AdaptiveMutationRecord
          { amrTurnId = turn
          , amrKind = MutKnowledgeTree
          , amrCause = "finalize:knowledge_tree_maintenance"
          , amrEvidence =
              [ "pruned_branches=" <> textShow prunedBranches
              , "pruned_fruits=" <> textShow prunedFruits
              ]
          , amrEvidenceStrength = EvidenceStrong
          , amrConfidence = 1.0
          , amrBoundedDelta = Just (fromIntegral (prunedBranches + prunedFruits))
          , amrDecision = AdaptiveRejected
          }
      ]

quarantinePromotionMutationRecords :: Int -> Int -> [AdaptiveMutationRecord]
quarantinePromotionMutationRecords turn promotedCount
  | promotedCount <= 0 = []
  | otherwise =
      [ AdaptiveMutationRecord
          { amrTurnId = turn
          , amrKind = MutKnowledgeTree
          , amrCause = "finalize:knowledge_tree_quarantine_promotion"
          , amrEvidence = ["promoted_from_quarantine=" <> textShow promotedCount]
          , amrEvidenceStrength = EvidenceModerate
          , amrConfidence = 0.75
          , amrBoundedDelta = Just (fromIntegral promotedCount)
          , amrDecision = AdaptivePromoted
          }
      ]

appendCalibrationEntries :: Int -> CalibrationLog -> [Maybe CalibrationProposal] -> CalibrationLog
appendCalibrationEntries turn (CalibrationLog existing) proposals =
  let concrete = [ proposal | Just proposal <- proposals ]
      nextBase = maybe 1 ((+ 1) . unCalibrationId . ceId) (safeLast existing)
      prevId = currentCalibrationVersion (CalibrationLog existing)
      step (entries, nextId, previous) proposal =
        let (entry, CalibrationId nextRaw) = acceptProposal (CalibrationId nextId) proposal turn previous
        in (entries ++ [entry], nextRaw, Just (ceId entry))
      (newEntries, _, _) = foldl step ([], nextBase, prevId) concrete
  in CalibrationLog (existing ++ newEntries)
  where
    safeLast [] = Nothing
    safeLast xs = Just (last xs)

calibrationMutationRecord :: Int -> CalibrationDecision -> Double -> SignalComponents -> AdaptiveMutationRecord
calibrationMutationRecord turn decision signal comps = AdaptiveMutationRecord
  { amrTurnId = turn
  , amrKind = MutCalibration
  , amrCause = "finalize:calibration_signal"
  , amrEvidence =
      [ "decision=" <> renderCalibrationDecision decision
      , "signal=" <> textShow signal
      , "conatus=" <> textShow (scConatusTrend comps)
      , "uncertainty=" <> textShow (scUncertaintyTrend comps)
      , "loop=" <> textShow (scLoopRisk comps)
      , "branch=" <> textShow (scBranchHealthTrend comps)
      ]
  , amrEvidenceStrength = if abs signal >= 0.15 then EvidenceStrong else EvidenceWeak
  , amrConfidence = min 1.0 (abs signal)
  , amrBoundedDelta = Just 1.0
  , amrDecision = adaptiveDecisionForCalibration decision
  }

adaptiveDecisionForCalibration :: CalibrationDecision -> AdaptiveDecision
adaptiveDecisionForCalibration decision =
  case decision of
    CdApplySignal -> AdaptiveAccepted
    CdHoldLowConfidence -> AdaptiveObserved
    CdHoldGuardrails -> AdaptiveRejected
    CdHoldNoNeed -> AdaptiveObserved

renderCalibrationDecision :: CalibrationDecision -> Text
renderCalibrationDecision decision =
  case decision of
    CdApplySignal -> "apply_signal"
    CdHoldLowConfidence -> "hold_low_confidence"
    CdHoldGuardrails -> "hold_guardrails"
    CdHoldNoNeed -> "hold_no_need"

salienceWeightsMaxDelta :: SalienceWeights -> SalienceWeights -> Double
salienceWeightsMaxDelta old new = maximumOrZero
  [ abs (weightResonance new - weightResonance old)
  , abs (weightAtmosphere new - weightAtmosphere old)
  , abs (weightConsolidation new - weightConsolidation old)
  , abs (weightCounterfactual new - weightCounterfactual old)
  , abs (weightFieldConfidence new - weightFieldConfidence old)
  ]

fieldHeuristicsMaxDelta :: FieldHeuristics -> FieldHeuristics -> Double
fieldHeuristicsMaxDelta old new = maximumOrZero
  [ abs (fhDefaultNarrativeRate new - fhDefaultNarrativeRate old)
  , abs (fhTopicStabilityBoost new - fhTopicStabilityBoost old)
  , abs (fhHolisticStreakBoostRate new - fhHolisticStreakBoostRate old)
  , abs (fhHolisticStreakBoostCap new - fhHolisticStreakBoostCap old)
  , abs (fhLegitimacyMidpoint new - fhLegitimacyMidpoint old)
  , abs (fhLegitimacyBonusScale new - fhLegitimacyBonusScale old)
  ]

maximumOrZero :: [Double] -> Double
maximumOrZero = foldr max 0.0

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
      (adaptedWeights, adaptedHeuristics, nextTree, calibrationSnapshots, nextCalibrationLog, adaptiveRecords) =
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
                (shouldApplySignal, calibrationDecision) =
                  applyCalibrationGated defaultSignalPipelineConfig calSignal (ssCalibrationSnapshots ss)
                calibrationSnapshot = CalibrationSnapshot
                  { csTimestamp = tiStartTime ti
                  , csRunId = tmSessionId (tiMetrics ti) <> ":" <> tmRequestId (tiMetrics ti)
                  , csComponents = sigComps
                  , csSignal = signal
                  , csDecision = calibrationDecision
                  }
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
                promotionRule = textShow outcomeFamily
                (treePromoted, promotedFromQuarantine, _rejectedFromQuarantine) =
                  promoteFromQuarantine currentTurn 2 promotionRule treeClean
                weights1 = if shouldApplySignal then adaptSalienceWeights signal (ssSalienceWeights ss) else ssSalienceWeights ss
                heuristics1 = if shouldApplySignal then adaptFieldHeuristics signal (ssFieldHeuristics ss) else ssFieldHeuristics ss
                calibrationLog1 =
                  if shouldApplySignal
                    then appendCalibrationEntries currentTurn (ssCalibrationLog ss)
                      [ if weights1 /= ssSalienceWeights ss then Just (ProposalSalienceWeights weights1) else Nothing
                      , if heuristics1 /= ssFieldHeuristics ss then Just (ProposalFieldHeuristics heuristics1) else Nothing
                      ]
                    else ssCalibrationLog ss
                tuningRecords = calibrationMutationRecord currentTurn calibrationDecision signal sigComps :
                  selfTuningMutationRecords currentTurn signal sigComps weights1 heuristics1 (ssSalienceWeights ss) (ssFieldHeuristics ss)
                treeRecords = knowledgeMaintenanceMutationRecords currentTurn _prunedBranches _prunedFruits
                  <> quarantinePromotionMutationRecords currentTurn promotedFromQuarantine
            in ( weights1
               , heuristics1
               , treePromoted
               , take 100 (calibrationSnapshot : ssCalibrationSnapshots ss)
               , calibrationLog1
               , tuningRecords <> treeRecords
               )
          _ -> (ssSalienceWeights ss, ssFieldHeuristics ss, ssKnowledgeTree ss, ssCalibrationSnapshots ss, ssCalibrationLog ss, [])
      -- WP6.1: endogenous learning diagnostic drive with separate learning pressure.
      bestTopic = tiBestTopic ti
      isTopicUnknown = not (T.null bestTopic)
                         && not (hasKnownMorphologyForm (ssMorphology ss) bestTopic)
                         && not (isTermKnownInKnowledgeTree bestTopic nextTree)
      currentGraftedCount = ktGraftedCount nextTree
      newLearningNeedState =
          detectLearningNeedWithPressure
           defaultLearningPressureConfig
           (tiConatusEnergy ti)
           (tiField ti)
           0 -- repairCount: historical recovery tracking deferred to Phase 7
           (length (ssBlockedConcepts ss)) -- proxy: blocked concepts indicate substrate gaps
           (ssTurnCount ss + 1)
            (ssLearningNeedState ss)
            isTopicUnknown
            currentGraftedCount
      baseNext = ss
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
      , ssDialogueThread = advanceDialogueThreadAfterTurn (tiDialogueThread ti) tp ta
      , ssDialogueCommitmentLedger = advanceDialogueLedgerAfterTurn (tiDialogueCommitmentLedger ti) tp
      , ssDialoguePhase = advanceDialoguePhaseAfterTurn (tiDialoguePhase ti) tp
      , ssGuardrailState = ssGuardrailState ss
        -- ^ WP5: guardrails currently pass through unchanged;
        --   proposal-submission tracking will be wired when the
        --   external-tool bridge is integrated.
      , ssCalibrationLog = nextCalibrationLog
      , ssKnowledgeTree = nextTree
        -- ^ Phase 7: rooted knowledge tree.  Root updated from
        --   committed essence; structural pruning applied each turn.
      , ssCalibrationSnapshots = calibrationSnapshots
      }
      nextWithLog = appendAdaptiveMutationRecords adaptiveRecords baseNext
      in ( nextWithLog
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
                (Nothing, Nothing, ["runtime_mode=degraded"])
          Nothing ->
            (Nothing, Nothing, [])
      -- Canonical trace Salience.  The Conatus and Field values
      -- are the pre-turn snapshot (single source of truth from
      -- 'PrepareStatic') so the trace reflects the actual signals
      -- that drove the routing decision.
      traceSalience   = turnInputSalience ti
      postEssence = ssEssence nextSs
      perspectiveProjections = buildActivePerspectiveProjections (ssPerspectiveRegistry nextSs)
      learningVerdict = deriveLearningReplayVerdict nextSs ta
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
            , trcLearningValidationStatus = Just (lrvStatus learningVerdict)
            , trcLearningSandboxResult = lrvSandboxResult learningVerdict
            , trcLearningGraftTurn = lrvGraftTurn learningVerdict
            , trcLearningRejectReason = lrvRejectReason learningVerdict
            , trcSenseAnchor = unSemanticNodeId (svAnchor (rspInputVector (rmpSensePlan (tpRmpAfterLegit tp))))
            , trcSenseOperator = Just (rspChosenOperator (rmpSensePlan (tpRmpAfterLegit tp)))
            , trcSensePreservedAxes = rspPreservedAxes (rmpSensePlan (tpRmpAfterLegit tp))
            , trcDialogueFocus = dtCurrentFocus (tiDialogueThread ti)
            , trcDialoguePhase = tiDialoguePhase ti
            , trcDialogueCommitmentCount = length (dclItems (tiDialogueCommitmentLedger ti))
            , trcMicroPlanMoves = mpRhetoricalMoves (rmpMicroPlan (tpRmpAfterLegit tp))
            , trcMicroPlanExplicitness = mpExplicitness (rmpMicroPlan (tpRmpAfterLegit tp))
            , trcPerspectiveProjection =
                case perspectiveProjections of
                  projection:_ -> Just projection
                  [] -> Nothing
            , trcPerspectiveProjections = perspectiveProjections
            }
  in TurnProjection
      { tqpTurn = ssTurnCount nextSs
      , tqpParserMode = ParserFrameV1
      , tqpParserConfidence = parserConfidence
      , tqpParserErrors = parserErrors
      , tqpPlannerMode = case tpPrincipledModePair tp of Just _ -> PrincipledPlanner; Nothing -> DefaultPlanner
      , tqpPlannerDecision = tdFamily decision
      , tqpAtomRegister = asRegister (tiAtomSet ti)
      , tqpAtomLoad = asLoad (tiAtomSet ti)
      , tqpScenePressure = scenePressure
      , tqpSceneRequest = tiBestTopic ti
      , tqpSceneStance = usNeedLayer (tiNextUserState ti)
      , tqpRenderLane = rsMove (tdRenderStrategy decision)
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
  let lns = ssLearningNeedState savedSs
      tree = ssKnowledgeTree savedSs
      graftsWindow = max 0 (ktGraftedCount tree - lnsWindowGraftBaseline lns)
      needReason =
        if lnsCurrentNeed lns == NeedLexiconExtension
          then "lexicon_pressure:unknown=" <> textShow (lnsUnknownWindowCount lns)
               <> ":grafts=" <> textShow graftsWindow
          else renderLearningNeed (lnsCurrentNeed lns)
      !metrics5 =
        addPhase (recordPhase "save_state" tSave0 tSave1)
          $ (taMetrics ta)
              { tmTurnCount = ssTurnCount savedSs
              , tmFamily = textShow outcomeFamily
              , tmNixStatus = textShow (tdGuardStatus decision)
              , tmSafetyStatus = textShow finalSafetyStatus
              , tmApiHealthy = apiHealthy
              , tmLearningPressureScore = lnsLevel lns
              , tmUnknownCountWindow = lnsUnknownWindowCount lns
              , tmGraftsWindow = graftsWindow
              , tmLexiconNeedTriggerReason = needReason
              , tmDedupSkipReason = taExternalQuerySkipReason ta
              }
      !metricsFinal = addPhase (recordPhase "total" (tiStartTime ti) tSave1) metrics5
  in metricsFinal

advanceDialogueThreadAfterTurn :: DialogueThread -> TurnPlan -> TurnArtifacts -> DialogueThread
advanceDialogueThreadAfterTurn thread tp ta =
  let family = tdFamily (taDecision ta)
      clarified = case family of
        CMClarify -> dtCurrentFocus thread : dtClarifiedItems thread
        CMGround -> dtCurrentFocus thread : dtClarifiedItems thread
        _ -> dtClarifiedItems thread
      unresolved = case family of
        CMRepair -> dtOpenLoops thread
        CMClarify -> dtOpenLoops thread
        _ -> filter (/= dtCurrentFocus thread) (dtOpenLoops thread)
  in thread
      { dtClarifiedItems = take 8 clarified
      , dtOpenLoops = take 8 unresolved
      , dtResistance = case family of
          CMRepair -> min 1.0 (dtResistance thread + 0.15)
          CMGround -> max 0.0 (dtResistance thread - 0.10)
          _ -> dtResistance thread
      }

advanceDialogueLedgerAfterTurn :: DialogueCommitmentLedger -> TurnPlan -> DialogueCommitmentLedger
advanceDialogueLedgerAfterTurn (DialogueCommitmentLedger items) tp =
  let family = tpFinalFamily tp
      rewrite item =
        if T.null (dcClaim item)
          then item
          else case family of
            CMClarify -> item { dcStatus = CsUnresolved }
            CMRepair -> item { dcStatus = CsSuspended }
            CMGround -> item { dcStatus = CsAccepted }
            CMConfront -> item { dcStatus = CsContested }
            _ -> item
  in DialogueCommitmentLedger (map rewrite items)

advanceDialoguePhaseAfterTurn :: DialoguePhase -> TurnPlan -> DialoguePhase
advanceDialoguePhaseAfterTurn prior tp =
  case tpFinalFamily tp of
    CMRepair -> Repairing
    CMClarify -> Clarifying
    CMGround -> Grounding
    CMNextStep -> Advancing
    CMConfront -> Contesting
    _ -> prior

data LearningReplayVerdict = LearningReplayVerdict
  { lrvStatus :: !Text
  , lrvSandboxResult :: !(Maybe Text)
  , lrvGraftTurn :: !(Maybe Int)
  , lrvRejectReason :: !(Maybe Text)
  }

deriveLearningReplayVerdict :: SystemState -> TurnArtifacts -> LearningReplayVerdict
deriveLearningReplayVerdict nextSs ta =
  case firstAttempt of
    Nothing -> LearningReplayVerdict "not_attempted" Nothing Nothing Nothing
    Just (Left err) ->
      LearningReplayVerdict
        { lrvStatus = case err of
            EqeFallback _ -> "fallback_non_authoritative"
            _ -> "transport_error"
        , lrvSandboxResult = Nothing
        , lrvGraftTurn = Nothing
        , lrvRejectReason = Just (renderExternalQueryError err)
        }
    Just (Right _) ->
      case () of
        _ | any isGraft currentTurnRecords -> LearningReplayVerdict "accept" (firstCauseEvidence "sandbox_accept") (Just currentTurn) Nothing
          | any isSandboxReject currentTurnRecords -> LearningReplayVerdict "sandbox_reject" (firstMutationEvidence "external_learning:sandbox_reject") Nothing (firstMutationEvidence "external_learning:sandbox_reject")
          | any isValidationReject currentTurnRecords -> LearningReplayVerdict "validation_reject" Nothing Nothing (firstMutationEvidence "external_learning:validation_reject")
          | any isParserReject currentTurnRecords -> LearningReplayVerdict "invalid_response" Nothing Nothing (Just "parser_rejected_schema_or_text")
          | otherwise -> LearningReplayVerdict "observed_non_authoritative" Nothing Nothing (Just "learning_outcome_unresolved")
  where
    currentTurn = ssTurnCount nextSs
    currentTurnRecords = filter ((== currentTurn) . amrTurnId) (ssAdaptiveMutationLog nextSs)
    firstAttempt = taExternalQueryResult ta <|> taExploratoryQueryResult ta
    isGraft record = amrCause record == "external_learning:graft" && amrDecision record == AdaptiveAccepted
    isSandboxReject record = amrCause record == "external_learning:sandbox_reject"
    isValidationReject record = amrCause record == "external_learning:validation_reject"
    isParserReject record = amrCause record == "tool_reliability:rejected" && any (== "reason=parser_rejected_schema_or_text") (amrEvidence record)
    firstMutationEvidence cause =
      case [ evidence | record <- currentTurnRecords, amrCause record == cause, evidence:_ <- [amrEvidence record] ] of
        value:_ -> Just value
        [] -> Nothing
    firstCauseEvidence reason =
      case [ evidence | record <- currentTurnRecords, any (== ("reason=" <> reason)) (amrEvidence record), evidence:_ <- [amrEvidence record] ] of
        value:_ -> Just value
        [] -> Nothing

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
