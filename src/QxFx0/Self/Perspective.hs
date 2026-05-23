{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

{-| P4 OpinionCore / PerspectiveOperator pure layer. -}
module QxFx0.Self.Perspective
  ( PerspectiveOperationResult(..)
  , assemblePerspectiveInput
  , opinionCore
  , evaluatePerspectiveAdmissibility
  , decidePerspectivePromotion
  , applyPerspectiveDecision
  , buildPerspectiveProjection
  , buildActivePerspectiveProjections
  , applyPerspectiveOperator
  ) where

import Data.List (sortOn)
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe, listToMaybe, mapMaybe)
import Data.Ord (Down(..))
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Learning.KnowledgeTree
  ( Branch(..)
  , KnowledgeFruit(..)
  , KnowledgeTree(..)
  )
import QxFx0.Learning.DialogueDevelopment
  ( isWeakAcknowledgementText
  , normalizeDialogueText
  )
import QxFx0.Self.Conatus (ConatusEnergy, ceScalar)
import QxFx0.Self.Field (Field, FieldConfidence(..), fieldConfidence)
import QxFx0.Self.Perspective.Reduce
  ( applyPerspectiveDecision
  , buildActivePerspectiveProjections
  , buildPerspectiveProjection
  )
import QxFx0.Types.Domain
  ( IdentityClaimRef
  )
import QxFx0.Types.State.Identity (idsIdentityClaims)
import QxFx0.Types.State.AdaptiveMutation
  ( AdaptiveDecision(..)
  , AdaptiveMutationKind(..)
  , AdaptiveMutationRecord(..)
  , EvidenceStrength(..)
  )
import QxFx0.Types.State.Governance
  ( GovernanceActor(..)
  , GovernanceRuntimeFault(..)
  , buildPerspectiveGovernanceEvent
  )
import QxFx0.Governance.Replay
  ( verifyPerspectiveRegistryRebuild
  )
import QxFx0.Types.State.DialogueDevelopment
  ( BeliefPolarity(..)
  , BeliefRecord(..)
  , BeliefStore(..)
  , DialoguePhase(..)
  , DialogueOutcomeKind(..)
  , DialogueOutcomeLearningState(..)
  , DialogueOutcomeSample(..)
  , DialogueThread(..)
  )
import QxFx0.Types.State.Perspective
import QxFx0.Types.State.System
  ( SystemState
  , commitGovernedPerspectiveProjection
  , appendGovernanceEventRecord
  , ssBeliefStore
  , ssDialoguePhase
  , ssDialogueThread
  , ssDialogueOutcomeLearning
  , ssIdentity
  , ssKnowledgeTree
  , ssGovernanceHistory
  , ssGovernanceRuntimeFault
  , ssPerspectiveRegistry
  , ssSessionId
  , ssTurnCount
  )

data PerspectiveOperationResult = PerspectiveOperationResult
  { porInput :: !PerspectiveInputBundle
  , porCandidate :: !PerspectiveCandidate
  , porAdmissibility :: !PerspectiveAdmissibility
  , porPromotionDecision :: !PerspectivePromotionDecision
  , porRegistry :: !PerspectiveRegistry
  , porProjection :: !(Maybe PerspectiveProjection)
  , porMutationRecord :: !AdaptiveMutationRecord
  }
  deriving stock (Eq, Show)

assemblePerspectiveInput :: SystemState -> ConatusEnergy -> Bool -> Field -> PerspectiveInputBundle
assemblePerspectiveInput ss conatusEnergy conatusGateFired field =
  let scope = selectPerspectiveScope ss
      registry = ssPerspectiveRegistry ss
      normativeProfile = activeNormativeProfile scope registry
      lineage = lineageForScope scope registry
      beliefStore = ssBeliefStore ss
      counterarguments = counterargumentsForScope scope beliefStore (ssDialogueOutcomeLearning ss) lineage
  in PerspectiveInputBundle
      { pibScope = scope
      , pibEvidence = evidenceForScope scope (ssKnowledgeTree ss) (ssDialogueOutcomeLearning ss)
      , pibStanceSlice = stanceSliceForScope scope beliefStore
      , pibIdentitySlice = identitySlice ss
      , pibConatusSlice = conatusSlice conatusEnergy conatusGateFired field
      , pibNormativeProfile = normativeProfile
      , pibCounterarguments = counterarguments
      , pibRevisionLineage = lineage
      }

opinionCore :: PerspectiveInputBundle -> PerspectiveCandidate
opinionCore bundle =
  let evidenceCount = length (pibEvidence bundle)
      stanceCount = length (pibStanceSlice bundle)
      counterCount = length (pibCounterarguments bundle)
      lineage = pibRevisionLineage bundle
      np = pibNormativeProfile bundle
      counterPressure = clampUnit (fromIntegral counterCount / 4.0)
      normativeAlignment = computeNormativeAlignment np counterPressure (pibConatusSlice bundle)
      internalTension = clampUnit (0.55 * counterPressure + 0.45 * (1.0 - normativeAlignment))
      supportScore = clampUnit ((fromIntegral evidenceCount * 0.28) + (fromIntegral stanceCount * 0.14))
      confidence = clampUnit (0.18 + supportScore + (0.25 * normativeAlignment) - (0.35 * counterPressure) - (0.20 * internalTension))
      orientation = orientationFromScores confidence counterPressure normativeAlignment internalTension
      supportingClaims = take 8 (map renderEvidenceRef (pibEvidence bundle) <> map renderClaimStanceRef (pibStanceSlice bundle))
      baseVersion = case lineage of
        recent:_ -> Just (prrToVersion recent)
        [] -> Nothing
  in PerspectiveCandidate
      { pcScope = pibScope bundle
      , pcThesis = thesisForScope (pibScope bundle) orientation supportingClaims
      , pcOrientation = orientation
      , pcConfidence = confidence
      , pcSupportingClaims = supportingClaims
      , pcCounterargumentPressure = counterPressure
      , pcNormativeAlignment = normativeAlignment
      , pcInternalTension = internalTension
      , pcBaseVersion = baseVersion
      , pcNormativeProfileVersion = npVersionId np
      }

evaluatePerspectiveAdmissibility :: PerspectiveInputBundle -> PerspectiveCandidate -> PerspectiveAdmissibility
evaluatePerspectiveAdmissibility bundle candidate
  | null (pibEvidence bundle) && null (pibStanceSlice bundle) =
      PerspectiveInadmissible "insufficient_evidence"
  | T.null (isSessionId (pibIdentitySlice bundle)) =
      PerspectiveInadmissible "identity_violation:empty_session"
  | csGateFired (pibConatusSlice bundle) || csEnergy (pibConatusSlice bundle) < 0.0 =
      PerspectiveInadmissible "conatus_violation"
  | pcCounterargumentPressure candidate > 0.74 =
      PerspectiveInadmissible "excessive_counterargument_pressure"
  | npConflictPolicy (pibNormativeProfile bundle) == "invalid" =
      PerspectiveInadmissible "invalid_normative_conflict"
  | pcNormativeAlignment candidate < 0.25 =
      PerspectiveInadmissible "invalid_normative_conflict"
  | pcConfidence candidate < 0.30 =
      PerspectiveInadmissible "invalid_confidence_geometry"
  | length (pcSupportingClaims candidate) > 8 =
      PerspectiveInadmissible "boundedness_violation:supporting_claims"
  | invalidRevisionStep bundle candidate =
      PerspectiveInadmissible "invalid_revision_step"
  | pcCounterargumentPressure candidate > 0.45 =
      PerspectiveAdmissibleQuarantined
  | pcConfidence candidate >= 0.62 && pcNormativeAlignment candidate >= 0.55 =
      PerspectiveAdmissibleAccepted
  | otherwise =
      PerspectiveAdmissibleObserved

decidePerspectivePromotion :: PerspectiveRegistry -> PerspectiveInputBundle -> PerspectiveCandidate -> PerspectiveAdmissibility -> PerspectivePromotionDecision
decidePerspectivePromotion registry bundle candidate admissibility =
  case admissibility of
    PerspectiveInadmissible _ -> PpdObserveOnly
    PerspectiveAdmissibleObserved -> PpdObserveOnly
    PerspectiveAdmissibleQuarantined
      | rollbackPressure registry candidate -> PpdRollbackPrior
      | contestedActivePressure registry candidate -> PpdSuspendActive
      | otherwise -> PpdQuarantine
    PerspectiveAdmissibleAccepted
      | weakEvidenceOnly bundle -> PpdObserveOnly
      | rollbackPressure registry candidate -> PpdRollbackPrior
      | contestedActivePressure registry candidate -> PpdSuspendActive
      | hasActivePerspective (pcScope candidate) registry
          && stableCorroboration bundle candidate -> PpdReviseActive
      | stableCorroboration bundle candidate -> PpdPromoteEndorsed
      | otherwise -> PpdAcceptBounded

applyPerspectiveOperator :: SystemState -> ConatusEnergy -> Bool -> Field -> SystemState
applyPerspectiveOperator ss conatusEnergy conatusGateFired field =
  let bundle = assemblePerspectiveInput ss conatusEnergy conatusGateFired field
      candidate = opinionCore bundle
      admissibility = evaluatePerspectiveAdmissibility bundle candidate
      registry0 = ssPerspectiveRegistry ss
      decision = decidePerspectivePromotion registry0 bundle candidate admissibility
      prospectiveRegistry = applyPerspectiveDecision (ssTurnCount ss) registry0 bundle candidate decision
      prospectiveAdaptiveRecord = perspectiveMutationRecord (ssTurnCount ss) prospectiveRegistry bundle candidate admissibility decision
      previousEvent = listToMaybe (reverse (ssGovernanceHistory ss))
      sequenceNo = length (ssGovernanceHistory ss) + 1
      prospectiveEvent = buildPerspectiveGovernanceEvent
        ActorRuntime
        sequenceNo
        (ssSessionId ss)
        previousEvent
        registry0
        prospectiveRegistry
        bundle
        candidate
        admissibility
        (Just decision)
        decision
        (buildPerspectiveProjection prospectiveRegistry (pcScope candidate))
   in case appendGovernanceEventRecord prospectiveEvent ss of
        Left err -> ss { ssGovernanceRuntimeFault = Just (GrfAppendRejected err) }
        Right ssWithGovernance ->
           case verifyPerspectiveRegistryRebuild (ssGovernanceHistory ssWithGovernance) prospectiveRegistry of
             Right rebuiltRegistry ->
               (commitGovernedPerspectiveProjection rebuiltRegistry prospectiveAdaptiveRecord ssWithGovernance)
                 { ssGovernanceRuntimeFault = Nothing }
             Left "governance perspective registry rebuild mismatch" ->
               ss { ssGovernanceRuntimeFault = Just GrfRebuildMismatch }
             Left err ->
               ss { ssGovernanceRuntimeFault = Just (GrfRebuildUnavailable err) }

selectPerspectiveScope :: SystemState -> PerspectiveScope
selectPerspectiveScope ss =
  let topic = firstNonEmpty
        [ lastOutcomeTopic (ssDialogueOutcomeLearning ss)
        , strongestClaimTopic (ssBeliefStore ss)
        , strongestKnowledgeTopic (ssKnowledgeTree ss)
        ]
      scopedTopic = clampPerspectiveScopeTopic (ssDialoguePhase ss) (ssDialogueThread ss) (fromMaybe "general" topic)
  in ScopeTopic scopedTopic

clampPerspectiveScopeTopic :: DialoguePhase -> DialogueThread -> Text -> Text
clampPerspectiveScopeTopic phase thread proposedTopic =
  let proposed = normalizeDialogueText proposedTopic
      currentFocus = normalizeDialogueText (dtCurrentFocus thread)
      phaseScope = normalizeDialogueText (dtPhaseScope thread)
      activeScope = firstNonEmpty [nonEmptyMaybe phaseScope, nonEmptyMaybe currentFocus]
      lockedPhase = phase `elem` [Clarifying, Grounding, Repairing, Contesting, Closing]
  in case activeScope of
       Nothing -> if T.null proposed then "general" else proposed
       Just scope
         | T.null proposed -> scope
         | lockedPhase && scope /= proposed && not (scope `T.isInfixOf` proposed) && not (proposed `T.isInfixOf` scope) -> scope
         | otherwise -> proposed

nonEmptyMaybe :: Text -> Maybe Text
nonEmptyMaybe txt
  | T.null txt = Nothing
  | otherwise = Just txt

activeNormativeProfile :: PerspectiveScope -> PerspectiveRegistry -> NormativeProfile
activeNormativeProfile scope registry =
  case M.lookup (prActiveNormativeProfileId registry) (prNormativeProfiles registry) of
    Just profile | normativeProfileApplies scope profile -> profile
    _ -> case filter (normativeProfileApplies scope) (M.elems (prNormativeProfiles registry)) of
      profile:_ -> profile
      [] -> defaultNormativeProfile

lineageForScope :: PerspectiveScope -> PerspectiveRegistry -> [PerspectiveRevisionRecord]
lineageForScope scope registry =
  case M.lookup scope (prThreads registry) of
    Nothing -> []
    Just thread -> take (prMaxLineageSlice registry) (ptRevisionHistory thread)

evidenceForScope :: PerspectiveScope -> KnowledgeTree -> DialogueOutcomeLearningState -> [EvidenceRef]
evidenceForScope scope tree outcomes =
  take 12 (knowledgeEvidence scope tree <> dialogueEvidence scope outcomes)

knowledgeEvidence :: PerspectiveScope -> KnowledgeTree -> [EvidenceRef]
knowledgeEvidence scope tree =
  let topic = scopeText scope
      fruits = concatMap brFruits (concat (M.elems (ktBranches tree)))
      relevant fruit =
        kfValidated fruit
          && (T.null topic || topic `T.isInfixOf` normalizeDialogueText (kfWord fruit <> " " <> kfProposition fruit))
  in map (EvidenceRef . ("knowledge:" <>) . T.take 120 . kfProposition) (filter relevant fruits)

dialogueEvidence :: PerspectiveScope -> DialogueOutcomeLearningState -> [EvidenceRef]
dialogueEvidence scope outcomes =
  let topic = scopeText scope
      relevant sample =
          dosStrongUpdate sample
            && dosKind sample `elem` [DialogueOutcomeSuccess, DialogueOutcomeConflict, DialogueOutcomeRepeatedQuestion]
            && (T.null topic || normalizeDialogueText (dosTopic sample) == topic)
  in map (EvidenceRef . dialogueEvidenceText) (take 6 (filter relevant (dolRecentOutcomes outcomes)))

stanceSliceForScope :: PerspectiveScope -> BeliefStore -> [ClaimStanceRef]
stanceSliceForScope scope store =
  let topic = scopeText scope
      relevant record =
          brConfidence record >= 0.45
            && brPolarity record `elem` [BeliefAffirmed, BeliefTentative, BeliefContested]
            && (T.null topic || topic `T.isInfixOf` normalizeDialogueText (brClaim record))
      scored record = (brConfidence record, record)
  in map (ClaimStanceRef . stanceRefText) . take 8 . map snd . sortOn (Down . fst) . map scored . filter relevant . M.elems $ bsClaims store

counterargumentsForScope :: PerspectiveScope -> BeliefStore -> DialogueOutcomeLearningState -> [PerspectiveRevisionRecord] -> [CounterargumentRef]
counterargumentsForScope scope store outcomes lineage =
  take 8 (stanceCounterarguments scope store <> dialogueCounterarguments scope outcomes <> lineageCounterarguments lineage)

stanceCounterarguments :: PerspectiveScope -> BeliefStore -> [CounterargumentRef]
stanceCounterarguments scope store =
  let topic = scopeText scope
      relevant record =
        brPolarity record `elem` [BeliefContested, BeliefRejected, BeliefAmbivalent]
          && (T.null topic || topic `T.isInfixOf` normalizeDialogueText (brClaim record))
  in map (CounterargumentRef . ("stance_counter:" <>) . brClaim) (filter relevant (M.elems (bsClaims store)))

dialogueCounterarguments :: PerspectiveScope -> DialogueOutcomeLearningState -> [CounterargumentRef]
dialogueCounterarguments scope outcomes =
  let topic = scopeText scope
      relevant sample =
        dosKind sample == DialogueOutcomeConflict
          && (T.null topic || normalizeDialogueText (dosTopic sample) == topic)
  in map (CounterargumentRef . ("dialogue_conflict:" <>) . dosTopic) (take 4 (filter relevant (dolRecentOutcomes outcomes)))

lineageCounterarguments :: [PerspectiveRevisionRecord] -> [CounterargumentRef]
lineageCounterarguments = mapMaybe lineageCounterargument
  where
    lineageCounterargument record
      | prrCounterargumentDelta record > 0.25 = Just (CounterargumentRef ("revision_pressure:" <> prrTrigger record))
      | otherwise = Nothing

identitySlice :: SystemState -> IdentitySlice
identitySlice ss =
  let claims = idsIdentityClaims (ssIdentity ss)
  in IdentitySlice
      { isSessionId = ssSessionId ss
      , isIdentityClaims = map renderIdentityClaim claims
      , isIdentityClaimCount = length claims
      , isTurnCount = ssTurnCount ss
      }

conatusSlice :: ConatusEnergy -> Bool -> Field -> ConatusSlice
conatusSlice energy gateFired field =
  let fieldConf = unFieldConfidence (fieldConfidence field)
  in ConatusSlice
      { csEnergy = ceScalar energy
      , csGateFired = gateFired
      , csFieldConfidence = fieldConf
      , csStability = clampUnit (fieldConf + min 0.25 (max 0.0 (ceScalar energy / 80.0)))
      }

invalidRevisionStep :: PerspectiveInputBundle -> PerspectiveCandidate -> Bool
invalidRevisionStep bundle candidate =
  case (pibRevisionLineage bundle, pcBaseVersion candidate) of
    ([], Nothing) -> False
    ([], Just _) -> True
    (recent:_, Just baseVersion) -> prrToVersion recent /= baseVersion
    (_:_, Nothing) -> True

weakEvidenceOnly :: PerspectiveInputBundle -> Bool
weakEvidenceOnly bundle =
  null (pibEvidence bundle) || all weakRef (pibEvidence bundle)
  where
    weakRef = isWeakAcknowledgementText . renderEvidenceRef

contestedActivePressure :: PerspectiveRegistry -> PerspectiveCandidate -> Bool
contestedActivePressure registry candidate =
  hasActivePerspective (pcScope candidate) registry
    && pcCounterargumentPressure candidate >= 0.65

rollbackPressure :: PerspectiveRegistry -> PerspectiveCandidate -> Bool
rollbackPressure registry candidate =
  hasActivePerspective (pcScope candidate) registry
    && hasRollbackCandidate (pcScope candidate) registry
    && pcCounterargumentPressure candidate >= 0.50

hasRollbackCandidate :: PerspectiveScope -> PerspectiveRegistry -> Bool
hasRollbackCandidate scope registry =
  case M.lookup scope (prThreads registry) of
    Nothing -> False
    Just thread -> any (isRollbackCandidate (ptActiveVersion thread)) (ptVersions thread)
  where
    isRollbackCandidate activeVersion ep =
      Just (epVersion ep) /= activeVersion
        && epStatus ep `elem` [PerspectiveRevised, PerspectiveContested, PerspectiveActive]

hasActivePerspective :: PerspectiveScope -> PerspectiveRegistry -> Bool
hasActivePerspective scope registry =
  case M.lookup scope (prThreads registry) of
    Nothing -> False
    Just thread -> case activeEndorsedPerspective thread of
      Just ep -> epStatus ep == PerspectiveActive
      Nothing -> False

stableCorroboration :: PerspectiveInputBundle -> PerspectiveCandidate -> Bool
stableCorroboration bundle candidate =
  length (pibEvidence bundle) >= 2
    && pcConfidence candidate >= 0.66
    && pcNormativeAlignment candidate >= 0.55
    && pcInternalTension candidate <= 0.50

upsertThread :: Int -> PerspectiveRegistry -> PerspectiveInputBundle -> PerspectiveCandidate -> PerspectivePromotionDecision -> PerspectiveStatus -> Maybe Int -> PerspectiveRegistry
upsertThread turn registry bundle candidate decision status endorsedTurn =
  let scope = pcScope candidate
      oldThread = M.lookup scope (prThreads registry)
      perspectiveId = maybe (PerspectiveId ("perspective-" <> T.pack (show (prNextPerspectiveOrdinal registry)))) ptPerspectiveId oldThread
      version = PerspectiveVersionId (prNextVersionOrdinal registry)
      priorActive = oldThread >>= ptActiveVersion
      oldConfidence = maybe 0.0 epConfidence (oldThread >>= activeEndorsedPerspective)
      oldNormative = maybe (npVersionId (pibNormativeProfile bundle)) epNormativeProfileVersion (oldThread >>= activeEndorsedPerspective)
      endorsed = EndorsedPerspective
        { epId = perspectiveId
        , epVersion = version
        , epScope = scope
        , epThesis = pcThesis candidate
        , epOrientation = pcOrientation candidate
        , epConfidence = pcConfidence candidate
        , epNormativeProfileId = npId (pibNormativeProfile bundle)
        , epNormativeProfileVersion = npVersionId (pibNormativeProfile bundle)
        , epStatus = status
        , epCreatedTurn = turn
        , epEndorsedTurn = endorsedTurn
        , epSupportingClaims = take 8 (pcSupportingClaims candidate)
        , epCounterarguments = take 8 (map renderCounterargumentRef (pibCounterarguments bundle))
        }
      revision = PerspectiveRevisionRecord
        { prrFromVersion = priorActive
        , prrToVersion = version
        , prrTrigger = promotionTrigger decision candidate
        , prrEvidenceDelta = fromIntegral (length (pibEvidence bundle))
        , prrCounterargumentDelta = pcCounterargumentPressure candidate
        , prrConfidenceDelta = pcConfidence candidate - oldConfidence
        , prrNormativeDelta = fromIntegral (npVersionId (pibNormativeProfile bundle) - oldNormative)
        , prrNormativeProfileVersion = npVersionId (pibNormativeProfile bundle)
        , prrDecision = decision
        , prrRollbackOf = Nothing
        }
      oldVersions = maybe [] ptVersions oldThread
      oldRevisions = maybe [] ptRevisionHistory oldThread
      activeVersion = if status == PerspectiveActive then Just version else priorActive
      thread = PerspectiveThread
        { ptPerspectiveId = perspectiveId
        , ptScope = scope
        , ptActiveVersion = activeVersion
        , ptVersions = boundVersions registry (endorsed : markPriorRevised status oldVersions)
        , ptRevisionHistory = take (prMaxRevisionsPerScope registry) (revision : oldRevisions)
        , ptStatus = status
        , ptLastUpdatedTurn = turn
       }
      threads = enforceRegistryBounds registry (M.insert scope thread (prThreads registry))
      nextPerspectiveOrdinal = case oldThread of
        Nothing -> prNextPerspectiveOrdinal registry + 1
        Just _ -> prNextPerspectiveOrdinal registry
  in registry
      { prThreads = threads
      , prNextPerspectiveOrdinal = nextPerspectiveOrdinal
      , prNextVersionOrdinal = prNextVersionOrdinal registry + 1
      , prLastUpdatedTurn = turn
      }

suspendActivePerspective :: Int -> PerspectiveRegistry -> PerspectiveCandidate -> PerspectivePromotionDecision -> PerspectiveRegistry
suspendActivePerspective turn registry candidate decision =
  case M.lookup (pcScope candidate) (prThreads registry) of
    Nothing -> registry { prLastUpdatedTurn = turn }
    Just thread ->
      let revision = PerspectiveRevisionRecord
            { prrFromVersion = ptActiveVersion thread
            , prrToVersion = fromMaybe (PerspectiveVersionId (prNextVersionOrdinal registry)) (ptActiveVersion thread)
            , prrTrigger = "counterargument_pressure_suspend"
            , prrEvidenceDelta = 0.0
            , prrCounterargumentDelta = pcCounterargumentPressure candidate
            , prrConfidenceDelta = 0.0
            , prrNormativeDelta = 0.0
            , prrNormativeProfileVersion = pcNormativeProfileVersion candidate
            , prrDecision = decision
            , prrRollbackOf = Nothing
            }
          thread' = thread
            { ptActiveVersion = Nothing
            , ptVersions = map (setStatusForActive (ptActiveVersion thread) PerspectiveSuspended) (ptVersions thread)
            , ptRevisionHistory = take (prMaxRevisionsPerScope registry) (revision : ptRevisionHistory thread)
            , ptStatus = PerspectiveSuspended
            , ptLastUpdatedTurn = turn
            }
        in registry
            { prThreads = enforceRegistryBounds registry (M.insert (pcScope candidate) thread' (prThreads registry))
            , prLastUpdatedTurn = turn
            }

rollbackPriorPerspective :: Int -> PerspectiveRegistry -> PerspectiveCandidate -> PerspectivePromotionDecision -> PerspectiveRegistry
rollbackPriorPerspective turn registry candidate decision =
  case M.lookup (pcScope candidate) (prThreads registry) of
    Nothing -> registry { prLastUpdatedTurn = turn }
    Just thread ->
      let active = ptActiveVersion thread
          remaining = filter (isViableRollbackVersion active) (ptVersions thread)
          replacement = case remaining of
            x:_ -> Just (epVersion x)
            [] -> Nothing
          revision = PerspectiveRevisionRecord
            { prrFromVersion = active
            , prrToVersion = fromMaybe (PerspectiveVersionId (prNextVersionOrdinal registry)) replacement
            , prrTrigger = "rollback_prior_promotion"
            , prrEvidenceDelta = 0.0
            , prrCounterargumentDelta = pcCounterargumentPressure candidate
            , prrConfidenceDelta = 0.0
            , prrNormativeDelta = 0.0
            , prrNormativeProfileVersion = pcNormativeProfileVersion candidate
            , prrDecision = decision
            , prrRollbackOf = active
            }
          thread' = thread
            { ptActiveVersion = replacement
            , ptVersions = map (statusAfterRollback active replacement) (ptVersions thread)
            , ptRevisionHistory = take (prMaxRevisionsPerScope registry) (revision : ptRevisionHistory thread)
            , ptStatus = maybe PerspectiveWithdrawn (const PerspectiveActive) replacement
            , ptLastUpdatedTurn = turn
            }
      in registry
          { prThreads = enforceRegistryBounds registry (M.insert (pcScope candidate) thread' (prThreads registry))
          , prLastUpdatedTurn = turn
          }

perspectiveMutationRecord :: Int -> PerspectiveRegistry -> PerspectiveInputBundle -> PerspectiveCandidate -> PerspectiveAdmissibility -> PerspectivePromotionDecision -> AdaptiveMutationRecord
perspectiveMutationRecord turn registry bundle candidate admissibility decision = AdaptiveMutationRecord
  { amrTurnId = turn
  , amrKind = MutPerspective
  , amrCause = "perspective:" <> promotionDecisionText decision <> ":" <> admissibilityText admissibility
  , amrEvidence = take 8 (map renderEvidenceRef (pibEvidence bundle) <> map renderClaimStanceRef (pibStanceSlice bundle) <> map renderCounterargumentRef (pibCounterarguments bundle))
  , amrEvidenceStrength = evidenceStrengthForPerspective bundle decision
  , amrConfidence = pcConfidence candidate
  , amrBoundedDelta = Just (fromIntegral (prMaxRevisionsPerScope registry))
  , amrDecision = adaptiveDecisionForPromotion decision
  }

evidenceStrengthForPerspective :: PerspectiveInputBundle -> PerspectivePromotionDecision -> EvidenceStrength
evidenceStrengthForPerspective bundle decision
  | weakEvidenceOnly bundle = EvidenceWeak
  | decision `elem` [PpdPromoteEndorsed, PpdReviseActive, PpdRollbackPrior] = EvidenceStrong
  | decision `elem` [PpdAcceptBounded, PpdQuarantine, PpdSuspendActive] = EvidenceModerate
  | otherwise = EvidenceObservational

adaptiveDecisionForPromotion :: PerspectivePromotionDecision -> AdaptiveDecision
adaptiveDecisionForPromotion decision =
  case decision of
    PpdObserveOnly -> AdaptiveObserved
    PpdQuarantine -> AdaptiveQuarantined
    PpdAcceptBounded -> AdaptiveAccepted
    PpdPromoteEndorsed -> AdaptivePromoted
    PpdReviseActive -> AdaptivePromoted
    PpdSuspendActive -> AdaptiveQuarantined
    PpdRollbackPrior -> AdaptiveRolledBack

computeNormativeAlignment :: NormativeProfile -> Double -> ConatusSlice -> Double
computeNormativeAlignment np counterPressure cs =
  let safety = M.findWithDefault 1.0 "safety" (npPriorities np)
      stability = M.findWithDefault 0.9 "stability" (npPriorities np)
      counterWeight = M.findWithDefault 0.7 "counterargument" (npPriorities np)
      conflictPenalty = if npConflictPolicy np == "permissive" then 0.08 else 0.18
      base = (0.45 * safety) + (0.35 * stability) + (0.20 * csStability cs)
      penalty = (counterPressure * counterWeight * 0.30) + conflictPenalty
  in clampUnit (base - penalty)

orientationFromScores :: Double -> Double -> Double -> Double -> Text
orientationFromScores confidence counterPressure normativeAlignment internalTension
  | counterPressure >= 0.45 || internalTension >= 0.55 = "contested"
  | confidence >= 0.72 && normativeAlignment >= 0.60 = "endorsed"
  | confidence >= 0.55 = "provisional"
  | otherwise = "observational"

thesisForScope :: PerspectiveScope -> Text -> [Text] -> Text
thesisForScope scope orientation claims =
  let basis = case claims of
        [] -> "available governed evidence"
        first:_ -> first
  in "Perspective on " <> renderPerspectiveScope scope <> " is " <> orientation <> " from " <> basis

promotionTrigger :: PerspectivePromotionDecision -> PerspectiveCandidate -> Text
promotionTrigger decision candidate =
  promotionDecisionText decision <> ":confidence=" <> T.pack (show (pcConfidence candidate))

promotionDecisionText :: PerspectivePromotionDecision -> Text
promotionDecisionText decision =
  case decision of
    PpdObserveOnly -> "observe_only"
    PpdQuarantine -> "quarantine"
    PpdAcceptBounded -> "accept_bounded"
    PpdPromoteEndorsed -> "promote_endorsed"
    PpdReviseActive -> "revise_active"
    PpdSuspendActive -> "suspend_active"
    PpdRollbackPrior -> "rollback_prior"

admissibilityText :: PerspectiveAdmissibility -> Text
admissibilityText admissibility =
  case admissibility of
    PerspectiveInadmissible reason -> "inadmissible:" <> reason
    PerspectiveAdmissibleObserved -> "admissible_observed"
    PerspectiveAdmissibleQuarantined -> "admissible_quarantined"
    PerspectiveAdmissibleAccepted -> "admissible_accepted"

boundVersions :: PerspectiveRegistry -> [EndorsedPerspective] -> [EndorsedPerspective]
boundVersions registry versions =
  let active = filter ((== PerspectiveActive) . epStatus) versions
      inactive = filter ((/= PerspectiveActive) . epStatus) versions
  in take (prMaxActivePerScope registry) active <> take (prMaxInactiveVersions registry) inactive

enforceRegistryBounds :: PerspectiveRegistry -> M.Map PerspectiveScope PerspectiveThread -> M.Map PerspectiveScope PerspectiveThread
enforceRegistryBounds registry threads =
  let activeThreads = filter (hasActiveThread . snd) (M.toList threads)
      allowedActiveScopes = map fst . take (prMaxActivePerspectives registry) . sortOn (Down . ptLastUpdatedTurn . snd) $ activeThreads
  in M.mapWithKey (enforceActiveScope allowedActiveScopes) threads

hasActiveThread :: PerspectiveThread -> Bool
hasActiveThread thread = activeEndorsedPerspective thread /= Nothing

enforceActiveScope :: [PerspectiveScope] -> PerspectiveScope -> PerspectiveThread -> PerspectiveThread
enforceActiveScope allowedScopes scope thread
  | scope `elem` allowedScopes = thread
  | hasActiveThread thread = suspendThreadForActiveCap thread
  | otherwise = thread

suspendThreadForActiveCap :: PerspectiveThread -> PerspectiveThread
suspendThreadForActiveCap thread = thread
  { ptActiveVersion = Nothing
  , ptVersions = map (setStatusForActive (ptActiveVersion thread) PerspectiveSuspended) (ptVersions thread)
  , ptStatus = PerspectiveSuspended
  }

markPriorRevised :: PerspectiveStatus -> [EndorsedPerspective] -> [EndorsedPerspective]
markPriorRevised status versions
  | status == PerspectiveActive = map reviseActive versions
  | otherwise = versions
  where
    reviseActive ep
      | epStatus ep == PerspectiveActive = ep { epStatus = PerspectiveRevised }
      | otherwise = ep

setStatusForActive :: Maybe PerspectiveVersionId -> PerspectiveStatus -> EndorsedPerspective -> EndorsedPerspective
setStatusForActive activeVersion status ep
  | Just (epVersion ep) == activeVersion = ep { epStatus = status }
  | otherwise = ep

setStatusForVersion :: Maybe PerspectiveVersionId -> PerspectiveStatus -> EndorsedPerspective -> EndorsedPerspective
setStatusForVersion version status ep
  | Just (epVersion ep) == version = ep { epStatus = status }
  | otherwise = ep

statusAfterRollback :: Maybe PerspectiveVersionId -> Maybe PerspectiveVersionId -> EndorsedPerspective -> EndorsedPerspective
statusAfterRollback active replacement =
  setStatusForVersion replacement PerspectiveActive . setStatusForActive active PerspectiveWithdrawn

isViableRollbackVersion :: Maybe PerspectiveVersionId -> EndorsedPerspective -> Bool
isViableRollbackVersion active ep =
  Just (epVersion ep) /= active
    && epStatus ep `elem` [PerspectiveRevised, PerspectiveContested, PerspectiveActive]

confidenceBand :: Double -> Text
confidenceBand value
  | value >= 0.80 = "high"
  | value >= 0.60 = "medium"
  | value >= 0.40 = "low"
  | otherwise = "minimal"

cautionLevel :: EndorsedPerspective -> Text
cautionLevel ep
  | epStatus ep `elem` [PerspectiveContested, PerspectiveSuspended] = "high"
  | epConfidence ep < 0.60 = "medium"
  | null (epCounterarguments ep) = "low"
  | otherwise = "medium"

explanationHandle :: EndorsedPerspective -> Text
explanationHandle ep =
  renderPerspectiveId (epId ep)
    <> ":v"
    <> T.pack (show (unPerspectiveVersionId (epVersion ep)))
    <> ":np"
    <> T.pack (show (epNormativeProfileVersion ep))

lastOutcomeTopic :: DialogueOutcomeLearningState -> Maybe Text
lastOutcomeTopic outcomes =
  case filter (not . T.null . dosTopic) (dolRecentOutcomes outcomes) of
    sample:_ -> Just (normalizeDialogueText (dosTopic sample))
    [] -> Nothing

strongestClaimTopic :: BeliefStore -> Maybe Text
strongestClaimTopic store =
  case sortOn (Down . brConfidence) (M.elems (bsClaims store)) of
    record:_ -> firstToken (brClaim record)
    [] -> Nothing

strongestKnowledgeTopic :: KnowledgeTree -> Maybe Text
strongestKnowledgeTopic tree =
  case filter (not . T.null . kfWord) (concatMap brFruits (concat (M.elems (ktBranches tree)))) of
    fruit:_ -> Just (normalizeDialogueText (kfWord fruit))
    [] -> Nothing

firstNonEmpty :: [Maybe Text] -> Maybe Text
firstNonEmpty values =
  case [value | Just value <- values, not (T.null value)] of
    value:_ -> Just value
    [] -> Nothing

firstToken :: Text -> Maybe Text
firstToken text =
  case T.words (normalizeDialogueText text) of
    token:_ -> Just token
    [] -> Nothing

scopeText :: PerspectiveScope -> Text
scopeText scope =
  case scope of
    ScopeTopic topic -> normalizeDialogueText topic
    ScopeTheme theme -> normalizeDialogueText theme
    ScopeCluster cluster -> normalizeDialogueText cluster

normativeProfileApplies :: PerspectiveScope -> NormativeProfile -> Bool
normativeProfileApplies scope profile =
  case npActivationScope profile of
    Nothing -> True
    Just activationScope -> samePerspectiveScope scope activationScope

samePerspectiveScope :: PerspectiveScope -> PerspectiveScope -> Bool
samePerspectiveScope left right =
  case (left, right) of
    (ScopeTopic a, ScopeTopic b) -> normalizeDialogueText a == normalizeDialogueText b
    (ScopeTheme a, ScopeTheme b) -> normalizeDialogueText a == normalizeDialogueText b
    (ScopeCluster a, ScopeCluster b) -> normalizeDialogueText a == normalizeDialogueText b
    _ -> False

dialogueEvidenceText :: DialogueOutcomeSample -> Text
dialogueEvidenceText sample =
  "dialogue:" <> T.pack (show (dosKind sample)) <> ":" <> dosTopic sample

stanceRefText :: BeliefRecord -> Text
stanceRefText record =
  "stance:" <> T.pack (show (brPolarity record)) <> ":" <> brClaim record

renderEvidenceRef :: EvidenceRef -> Text
renderEvidenceRef (EvidenceRef value) = value

renderClaimStanceRef :: ClaimStanceRef -> Text
renderClaimStanceRef (ClaimStanceRef value) = value

renderCounterargumentRef :: CounterargumentRef -> Text
renderCounterargumentRef (CounterargumentRef value) = value

renderIdentityClaim :: IdentityClaimRef -> Text
renderIdentityClaim = T.pack . show

clampUnit :: Double -> Double
clampUnit = max 0.0 . min 1.0
