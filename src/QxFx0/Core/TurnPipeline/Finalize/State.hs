{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE StrictData #-}

{-|
Description : observer — Finalize-stage construction of persisted state, projection, output, and final metrics. -}
module QxFx0.Core.TurnPipeline.Finalize.State
  ( buildNextSystemState
  , buildFinalOutput
  , finalizeMetrics
  , computeEssenceValidation
  ) where

import Control.Exception (throw)
import QxFx0.ExceptionPolicy (QxFx0Exception(..))
import QxFx0.Types
import QxFx0.Types.State.System (appendAdaptiveMutationRecords)
import QxFx0.Types.State.SelfState (SelfState(..))
import QxFx0.Types.Decision.Enums.Render (dominantChannelText)
import QxFx0.Semantic.Commitment (commitObservation, quarantineObservation, promoteMatchingQuarantine, contradict)
import qualified QxFx0.Semantic.Content as Content
import QxFx0.Types.State.SemanticCommitment (FactualClaimPayload(..), CommitmentOrigin(..), TurnSeq(..), emptySemanticCommitmentStore, CommitmentEngagement(..), CommitmentId(..), ContradictionKind(..))
import QxFx0.Semantic.Revision (RevisedCommitment(..), revisePosition, applyRevisionDecision)
import QxFx0.Render.Authority (AuthoritySurface(..))
import QxFx0.Core.CommitmentStoreAdmission (admitCommitmentToStore, CommitmentStoreAdmissionDecision(..))
import QxFx0.Policy.Metacognition (MetacognitionContour(..), emptyMetacognitionContour, runMetacognitionLoop)
import QxFx0.Memory.Episodic
  ( EpisodicStore(..)
  , EpisodicKind(..)
  , EpisodicContent(..)
  , EpisodicId(..)
  , emptyIndex
  , encode
  , enforceCapacity
  , enforceAgeWindow
  )
import QxFx0.Self.Deliberation (Agreement(..))
import QxFx0.Types.Thresholds
  ( legitimacyPassThreshold
  , legitimacyRecoveryThreshold
  , blockedConceptsRetentionLimit
  , recentFamiliesLimit
  , rawInputHistoryLimit
  )
import QxFx0.Core.TurnPipeline.Types
import QxFx0.Core.TurnPipeline.Finalize.Projection (buildTurnProjection, turnInputSalience)
import QxFx0.Core.TurnRender (updateStateNixCache)
import qualified QxFx0.Core.Guard as Guard
import QxFx0.Core.TurnLegitimacy (safeOutputText)
import QxFx0.Core.Bayesian (updateUserModel, dominantIntent)
import QxFx0.Core.Observability
import QxFx0.Observability.TraceAnalysis
  ( analyzeTrace
  , logTraceAnomalies
  )
import QxFx0.Render.Semantic (renderSemanticIntrospection)
import QxFx0.Self.Salience
  ( SelfVerdict(..)
  , SalienceWeights(..)
  , salienceHolisticBias
  , isHolisticFamily
  )
import QxFx0.Self.Deliberation
  ( Deliberation(..)
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
import QxFx0.Self.Field (adaptFieldHeuristics, Field(..), FieldHeuristics(..), fieldCounterfactual, Counterfactual(..), Atmosphere(..), updateMood)
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
import QxFx0.Semantic.Network (buildSemanticNetwork, mergeSemanticNetworks, contentDensityGate)
import QxFx0.Semantic.Space (buildSemanticSpace, buildFactVectors)
import QxFx0.Semantic.Space.Types (emptySemanticSpace, ssFactVectors)
import QxFx0.Semantic.ContentSelector (buildContentSelector, buildTopicAtoms, tokenizePredicate)
import QxFx0.Semantic.ContentSelector.Types (emptyContentSelector)
import QxFx0.Semantic.Intent.Metrics (IntentClassifierMetrics)
import QxFx0.Semantic.Intent.GeometricClassifier (recordABValidation)
import QxFx0.Types.Text (textShow)
import QxFx0.Types.State.DialogueDevelopment
  ( CommitmentStatus(..)
  , DialogueCommitment(..)
  , DialogueCommitmentLedger(..)
  , DialoguePhase(..)
  , DialogueThread(..)
  )

import Data.Maybe (fromMaybe)
import Control.Applicative ((<$>), (<*>), (<|>))
import Data.Sequence (Seq, empty)
import qualified Data.Foldable as F
import qualified Data.Map.Strict as M
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock (UTCTime)
import qualified Data.HashSet as HS

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
    maxFieldHeuristicsDelta = fieldHeuristicsMaxDelta oldHeuristics newHeuristics
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
              , amrBoundedDelta = Just maxFieldHeuristicsDelta
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
      nextBase = maybe 1 ((+ 1) . unCalibrationId . ceId) (safeLastEntry existing)
      prevId = currentCalibrationVersion (CalibrationLog existing)
      step (entries, nextId, previous) proposal =
        let (entry, CalibrationId nextRaw) = acceptProposal (CalibrationId nextId) proposal turn previous
        in (entries ++ [entry], nextRaw, Just (ceId entry))
      (newEntries, _, _) = foldl step ([], nextBase, prevId) concrete
  in CalibrationLog (existing ++ newEntries)
  where
    safeLastEntry [] = Nothing
    safeLastEntry xs = foldl (\_ entry -> Just entry) Nothing xs

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

buildNextSystemState :: (Text -> Seq Text -> Seq Text) -> (AuthoritySurface -> Maybe FactualClaimPayload) -> SystemState -> TurnInput -> TurnSignals -> TurnPlan -> TurnArtifacts -> DreamState -> MeaningGraph -> CanonicalMoveFamily -> R5Verdict -> Int -> (SystemState, Maybe CommitmentTrigger, CommitmentStoreAdmissionDecision, Int)
buildNextSystemState updateHistory parseAuthSurface ss ti ts tp ta newDreamState newMeaningGraph outcomeFamily outcomeVerdict consecReflect =
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
                weights1 = if shouldApplySignal then adaptSalienceWeights signal (selfSalienceWeights (ssSelfState ss)) else selfSalienceWeights (ssSelfState ss)
                heuristics1 = if shouldApplySignal then adaptFieldHeuristics signal (selfFieldHeuristics (ssSelfState ss)) else selfFieldHeuristics (ssSelfState ss)
                calibrationLog1 =
                  if shouldApplySignal
                    then appendCalibrationEntries currentTurn (ssCalibrationLog ss)
                      [ if weights1 /= selfSalienceWeights (ssSelfState ss) then Just (ProposalSalienceWeights weights1) else Nothing
                      , if heuristics1 /= selfFieldHeuristics (ssSelfState ss) then Just (ProposalFieldHeuristics heuristics1) else Nothing
                      ]
                    else ssCalibrationLog ss
                tuningRecords = calibrationMutationRecord currentTurn calibrationDecision signal sigComps :
                  selfTuningMutationRecords currentTurn signal sigComps weights1 heuristics1 (selfSalienceWeights (ssSelfState ss)) (selfFieldHeuristics (ssSelfState ss))
                treeRecords = knowledgeMaintenanceMutationRecords currentTurn _prunedBranches _prunedFruits
                  <> quarantinePromotionMutationRecords currentTurn promotedFromQuarantine
            in ( weights1
               , heuristics1
               , treePromoted
               , take 100 (calibrationSnapshot : ssCalibrationSnapshots ss)
               , calibrationLog1
               , tuningRecords <> treeRecords
               )
          _ -> (selfSalienceWeights (ssSelfState ss), selfFieldHeuristics (ssSelfState ss), ssKnowledgeTree ss, ssCalibrationSnapshots ss, ssCalibrationLog ss, [])
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
      executedOutcome = taExecutedOutcome ta
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
      -- Phase 4.1.3: Update grouped Self-layer state
      , ssSelfState = (ssSelfState ss)
          { selfEssence = nextEssence
          , selfSalienceWeights = adaptedWeights
          , selfFieldHeuristics = adaptedHeuristics
          }
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
          in take maxProvisionalAtoms (resolveCollisions canonicalSet remaining)
      , ssLearningNeedState = newLearningNeedState
       , ssDialogueThread = advanceDialogueThreadAfterTurn (tiDialogueThread ti) (tpRmpAfterLegit tp) executedOutcome
      , ssDialogueCommitmentLedger = advanceDialogueLedgerAfterTurn (tiDialogueCommitmentLedger ti) executedOutcome
      , ssDialoguePhase = advanceDialoguePhaseAfterTurn (tiDialoguePhase ti) executedOutcome
      , ssTruthContractStatus = etoTruthContractStatus executedOutcome
      , ssGuardrailState = ssGuardrailState ss
        -- ^ WP5: guardrails currently pass through unchanged;
        --   proposal-submission tracking will be wired when the
        --   external-tool bridge is integrated.
      , ssCalibrationLog = nextCalibrationLog
      , ssKnowledgeTree = nextTree
        -- ^ Phase 7: rooted knowledge tree.  Root updated from
        --   committed essence; structural pruning applied each turn.
      , ssCalibrationSnapshots = calibrationSnapshots
      , ssSemanticNetwork = semanticNetwork
      , ssSemanticSpace = semanticSpace
      , ssContentSelector = contentSelector
      }
      semanticNetwork = mergeSemanticNetworks (ssSemanticNetwork ss) (buildSemanticNetwork newMeaningGraph)
      topicAtomsMap = M.fromList
        [ (topic, Set.toList $ Set.unions [tokenizePredicate (Content.spRu pred) | pred <- Content.dcPredicates dc])
        | topic <- Content.coveredTopics
        , Just dc <- [Content.lookupDefinitionContent topic]
        ]
      topicAtomsSetMap = M.fromList
        [ (topic, Set.unions [tokenizePredicate (Content.spRu pred) | pred <- Content.dcPredicates dc])
        | topic <- Content.coveredTopics
        , Just dc <- [Content.lookupDefinitionContent topic]
        ]
      semanticSpace = if contentDensityGate semanticNetwork
                      then buildSemanticSpace semanticNetwork topicAtomsSetMap
                      else emptySemanticSpace
      contentSelector = if contentDensityGate semanticNetwork
                        then buildContentSelector semanticSpace (buildTopicAtoms topicAtomsMap) topicPredicatesMap
                        else emptyContentSelector
      topicPredicatesMap = M.fromList
        [ (topic, Content.dcPredicates dc)
        | topic <- Content.coveredTopics
        , Just dc <- [Content.lookupDefinitionContent topic]
        ]
      nextWithLog = appendAdaptiveMutationRecords adaptiveRecords baseNext
      -- P4: parse the rendered authority surface; commit if recognised.
      -- Nothing parse is silently skipped (non-authority surface).
      turnSeq = TurnSeq (ssTurnCount ss + 1)
      renderedSurface = AuthoritySurface (taFinalRendered ta)
      mClaimPayload = parseAuthSurface renderedSurface
      store0 = fromMaybe emptySemanticCommitmentStore (ssSemanticCommitments nextWithLog)
      -- C3: additionally commit a typed anchor observation when SemanticAnchor
      -- is established this turn. This makes the anchor machine-visible in the
      -- SemanticCommitmentStore alongside the surface-parsed claim.
      -- CTS-42: gate both commits with the same admission decision.
      (store1, mAnchorCid) = case (commitDecision, tpSemanticAnchor tp) of
        (CsaAdmitCanonical, Just anchor) ->
          let anchorPayload = anchorToFactualClaim anchor turnSeq
              (s, cid) = commitObservation anchorPayload store0
          in (s, Just cid)
        (CsaSuppress, Just anchor) ->
          let anchorPayload = anchorToFactualClaim anchor turnSeq
          in (quarantineObservation anchorPayload store0, Nothing)
        _ -> (store0, Nothing)
      (store2, promotedCount, mSurfaceCid) = case (commitDecision, mClaimPayload) of
        (CsaAdmitCanonical, Just claimPayload) ->
          let payload = claimPayload { fcpTurnSeq = turnSeq }
              (committed, newCid) = commitObservation payload store1
              (promoted, count) = promoteMatchingQuarantine newCid (fcpStatement payload) committed
          in (promoted, count, Just newCid)
        (CsaSuppress, Just claimPayload) ->
          ( quarantineObservation claimPayload { fcpTurnSeq = turnSeq } store1
          , 0
          , Nothing
          )
        _ -> (store1, 0, Nothing)
      -- SUBJECT-SEAM-1: if the turn contradicted held commitments, record each
      -- contradiction pair (new claim ↔ engaged commitment) in the ledger.
      -- Phase E: apply revision decisions based on angst/conatus thresholds.
      store3 =
        let ce = tpCommitmentEngagement tp
        in if ceContradicted ce
             then
               let newCid = case mSurfaceCid of Just c -> c; Nothing -> fromMaybe (CommitmentId 0) mAnchorCid
                   engaged = ceEngaged ce
               in foldr (\engagedCid s ->
                    if engagedCid == newCid
                      then s
                      else contradict engagedCid newCid ContradictionStatement turnSeq s
                  ) store2 engaged
              else store2
      -- Phase E: revision decisions for contradicted commitments
      revisionDecisions =
        let ce = tpCommitmentEngagement tp
            angst = case tiEssence ti of
                      EssenceUncommitted traj -> etAngstLevel traj
                      EssenceCommitted traj _ -> etAngstLevel traj
            conatus = tiConatusEnergy ti
        in if ceContradicted ce
             then
               let newCid = case mSurfaceCid of Just c -> c; Nothing -> fromMaybe (CommitmentId 0) mAnchorCid
                   engaged = ceEngaged ce
               in map (\engagedCid -> revisePosition engagedCid ContradictionStatement angst conatus)
                      (filter (/= newCid) engaged)
               else []
      store4 = F.foldl' (\s dec -> applyRevisionDecision turnSeq s mClaimPayload dec) store3 revisionDecisions
      nextWithCommitments = nextWithLog
        { ssSemanticCommitments = Just store4
        , ssSemanticSpace = semanticSpace { ssFactVectors = buildFactVectors semanticSpace store4 }
        }
      -- P9: metacognitive correction loop (post-hoc, pure)
      mContour = case ssMetacognition nextWithCommitments of
        Just c  -> Just c
        Nothing -> Just emptyMetacognitionContour
      rawText = ipfRawText (tiFrame ti)
      agreement = case tpDeliberation tp of
        Just d  -> agreementToDouble (dtAgreement (delibTrace d))
        Nothing -> 0.5
      inRecovery = maybe False (const True)
        (tpDeliberation tp >>= \d ->
           planRecoveryCause (delibReconciled d))
      nextWithMeta = nextWithCommitments
        { ssMetacognition = runMetacognitionLoop
            <$> mContour
            <*> pure turnSeq
            <*> pure rawText
            <*> pure agreement
            <*> pure inRecovery
        }
      -- P7: episodic memory encoding (WP-B R-B4: store is always Just after explicit init)
      -- unreachable invariant (R-B4 guarantees ssEpisodic Just);
      -- typed bottom forced here for deterministic, categorisable failure
      !episodic0 = case ssEpisodic nextWithMeta of
        Just store' -> store'
        Nothing     -> throw (StateInvariantViolation "WP-B invariant violation: ssEpisodic should never be Nothing after R-B4")
      userInputEncoded = encode turnSeq EpisodicUserInput (EpisodicUserText rawText) [] episodic0
      decisionKind = EpisodicSystemDecision
      decisionContent = EpisodicFamilyDecision outcomeFamily
      episodic1 = encode turnSeq decisionKind decisionContent [] userInputEncoded
      episodic2 = enforceCapacity episodic1
      episodic3 = enforceAgeWindow turnSeq episodic2
      nextWithEpisodic = nextWithMeta
        { ssEpisodic = Just episodic3
        }
      -- WP-A: Bayesian user-model update (default-off, flag-gated in updateUserModel)
      updatedUserModel = updateUserModel
        (ssSemanticConfig nextWithEpisodic)
        (ssUserModel nextWithEpisodic)
        rawText
      -- WP-A reader: a peaked posterior overrides the write-only intent
      -- hypothesis with the inferred intent (uniform posterior -> unchanged).
      threadWithIntent = case dominantIntent updatedUserModel of
        Just intent ->
          (ssDialogueThread nextWithEpisodic)
            { dtIntentHypothesis = Just (T.pack (show intent)) }
        Nothing -> ssDialogueThread nextWithEpisodic
      nextWithUserModel = nextWithEpisodic
        { ssUserModel = updatedUserModel
        , ssDialogueThread = threadWithIntent
        }
      -- WP-E: update the slow mood baseline from this turn's atmosphere valence
      -- (EMA over ~moodWindowTurns). Living consumer of updateMood.
      turnValence = atmosphereValence (fieldAtmosphere (tiField ti))
      nextWithMood = nextWithUserModel
        { ssMood = updateMood (ssMood nextWithUserModel) turnValence
        }
      -- Phase 2: record A/B validation metrics for geometric classifier
      nextWithMetrics = case tiGeoResult ti of
        Just geoResult -> nextWithMood
          { ssGeometricMetrics = recordABValidation (ssGeometricMetrics ss) geoResult outcomeFamily
          }
        Nothing -> nextWithMood
      -- CTS-42: compute the admission decision once, apply to both
      -- anchor and surface-parsed claims.
      commitDecision = admitCommitmentToStore (etoTruthContractStatus executedOutcome)
      in ( nextWithMetrics
    , commitmentTrigger
    , commitDecision
    , promotedCount
    )

maxProvisionalAtoms :: Int
maxProvisionalAtoms = 1000

buildFinalOutput :: Bool -> TurnReplayTrace -> SystemState -> Guard.GuardSurface -> SystemState -> (Text, Guard.SafetyStatus)
buildFinalOutput wantIntrospection replayTrace ss baseSurface nextSs =
  let -- Phase 3D: Analyze trace for anomalies (lightweight, < 1ms)
      -- Note: Trace analysis and logging moved to IO boundary in caller (buildFinalizePrecommit)
      -- to maintain referential transparency. The analysis itself is pure.
      _traceAnalysis = analyzeTrace replayTrace
      
      preIntrospectionSurface =
        if wantIntrospection
          then
            let introspectionText = renderSemanticIntrospection nextSs (Just replayTrace)
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

advanceDialogueThreadAfterTurn :: DialogueThread -> ResponseMeaningPlan -> ExecutedTurnOutcome -> DialogueThread
advanceDialogueThreadAfterTurn thread meaningPlan outcome =
  let family = etoFamily outcome
      currentFocus = dtCurrentFocus thread
      chooseNonEmpty primary fallback = if T.null primary then fallback else primary
      clarified = case family of
        CMClarify -> currentFocus : dtClarifiedItems thread
        CMGround -> currentFocus : dtClarifiedItems thread
        _ -> dtClarifiedItems thread
      unresolved = case family of
        CMRepair -> dtOpenLoops thread
        CMClarify -> dtOpenLoops thread
        _ -> filter (/= currentFocus) (dtOpenLoops thread)
      nextFocus =
        case family of
          CMClarify -> currentFocus
          CMGround -> currentFocus
          CMRepair -> currentFocus
          _ -> if T.null currentFocus then dtPhaseScope thread else currentFocus
      nextScope =
        case family of
          CMClarify -> nextFocus
          CMGround -> nextFocus
          CMRepair -> chooseNonEmpty (dtPhaseScope thread) nextFocus
          CMConfront -> chooseNonEmpty (dtPhaseScope thread) nextFocus
          _ -> chooseNonEmpty nextFocus (dtPhaseScope thread)
      nextStructuralScope =
        case etoAuthorityClass outcome of
          AuthorityCanonical -> rmpScope meaningPlan <|> dtStructuralScope thread
          AuthorityAssembled -> rmpScope meaningPlan <|> dtStructuralScope thread
          _ -> dtStructuralScope thread
  in thread
      { dtCurrentFocus = nextFocus
      , dtPhaseScope = nextScope
      , dtClarifiedItems = take 8 clarified
      , dtOpenLoops = take 8 unresolved
      , dtResistance = case family of
          CMRepair -> min 1.0 (dtResistance thread + 0.15)
          CMGround -> max 0.0 (dtResistance thread - 0.10)
          _ -> dtResistance thread
      , dtStructuralScope = nextStructuralScope
      }

advanceDialogueLedgerAfterTurn :: DialogueCommitmentLedger -> ExecutedTurnOutcome -> DialogueCommitmentLedger
advanceDialogueLedgerAfterTurn (DialogueCommitmentLedger items) outcome =
  let family = etoFamily outcome
      nonAuthoritative = etoAuthorityClass outcome `notElem` [AuthorityCanonical, AuthorityAssembled]
      rewrite item =
        if T.null (dcClaim item)
          then item
          else if nonAuthoritative
            then case family of
              CMRepair -> item { dcStatus = CsSuspended }
              _ -> item { dcStatus = downgradeCommitmentStatus (dcStatus item) }
            else case family of
              CMClarify -> item { dcStatus = CsUnresolved }
              CMRepair -> item { dcStatus = CsSuspended }
              CMGround -> item { dcStatus = CsAccepted }
              CMConfront -> item { dcStatus = CsContested }
              _ -> item
  in DialogueCommitmentLedger (map rewrite items)

advanceDialoguePhaseAfterTurn :: DialoguePhase -> ExecutedTurnOutcome -> DialoguePhase
advanceDialoguePhaseAfterTurn prior outcome
  | etoAuthorityClass outcome `notElem` [AuthorityCanonical, AuthorityAssembled] =
      case etoFamily outcome of
        CMRepair -> Repairing
        _ -> prior
  | otherwise =
      case etoFamily outcome of
        CMRepair -> Repairing
        CMClarify -> Clarifying
        CMGround -> Grounding
        CMNextStep -> Advancing
        CMConfront -> Contesting
        _ -> prior

downgradeCommitmentStatus :: CommitmentStatus -> CommitmentStatus
downgradeCommitmentStatus status =
  case status of
    CsAccepted -> CsUnresolved
    CsContested -> CsSuspended
    other -> other

agreementToDouble :: Agreement -> Double
agreementToDouble a = case a of
  Agree             -> 1.0
  DivergeOnFamily   -> 0.3
  DivergeOnStyle    -> 0.4
  DivergeOnRecovery -> 0.2
  DivergeOnTone     -> 0.5
  DivergeMultiple   -> 0.1

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

-- | Convert a 'SemanticAnchor' to a 'FactualClaimPayload' for commitment.
-- The anchor captures which dialogue channel is dominant at a turn; the
-- payload records this as a factual observation about the dialogue state
-- so that the 'SemanticCommitmentStore' reflects anchor continuity.
--
-- M4-002: for covered topics (per 'QxFx0.Semantic.Content'), the payload
-- statement includes the topic name and its substantive predicates. This
-- makes the commitment domain-bearing — 'detectCommitmentEngagement' can
-- find it when a later turn challenges the same topic, enabling Gate 3
-- (repair under challenge) and Gate 4 (commitment accountability).
anchorToFactualClaim :: SemanticAnchor -> TurnSeq -> FactualClaimPayload
anchorToFactualClaim anchor tseq =
  let channel = dominantChannelText (saDominantChannel anchor)
      topic = fromMaybe "" (saSecondaryChannel anchor)
      mContent = Content.lookupDefinitionContent topic
      contentStmt = case mContent of
        Just dc ->
          let preds = map Content.spRu (Content.dcPredicates dc)
          in " Topic: " <> topic <> ". " <> T.intercalate " " preds
        Nothing -> ""
      stmt = "Dialogue channel: " <> channel
             <> contentStmt
             <> " (established at turn " <> T.pack (show (saEstablishedAtTurn anchor)) <> ")"
      conf = min 1.0 (saStrength anchor * saStability anchor)
  in FactualClaimPayload
       { fcpStatement  = stmt
       , fcpConfidence = conf
       , fcpOrigin     = OriginParser ("anchor:" <> channel)
       , fcpTurnSeq    = tseq
       , fcpDeps       = []
       , fcpTopic      = topic
       }
