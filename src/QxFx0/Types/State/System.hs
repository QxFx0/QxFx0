{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

{-| Canonical top-level persisted system state plus compatibility accessors. -}
module QxFx0.Types.State.System
  ( SystemState(..)
  , ssHistory
  , ssRawInputHistory
  , ssTurnCount
  , ssLastFamily
  , ssLastTopic
  , ssLastForce
  , ssLastLayer
  , ssLastEmbedding
  , ssConsecutiveReflect
  , ssRecentFamilies
  , ssActiveScene
  , ssUserState
  , ssEgo
  , ssIdentityClaims
  , ssOrbitalMemory
  , ssLastGuardReport
  , ssTrace
  , ssMeaningGraph
  , ssDiscourse
  , ssSemanticConfig
  , ssKernelPulse
  , ssBlockedConcepts
  , ssClusters
  , ssSemanticAnchor
  , ssLastTurnDecision
  , ssIntuitConfidence
  , ssDreamState
  , ssDreamAxiom
  , ssIntuitionState
  , ssLastSalienceBias
  , ssHolisticStreak
  , ssRecentNarrativeSuccess
  , appendAdaptiveMutationRecord
  , appendAdaptiveMutationRecords
  , commitGovernedPerspectiveProjection
  , appendGovernanceEventRecord
  , emptySystemState
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson
  ( FromJSON(..)
  , ToJSON(..)
  , object
  , withObject
  , (.:)
  , (.:?)
  , (.!=)
  , (.=)
  )
import qualified Data.Aeson.Key as AK
import qualified Data.Aeson.KeyMap as KM
import qualified Data.Map.Strict as M
import Data.Sequence (Seq)
import qualified Data.Sequence as Seq
import Control.Monad (when)
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

import QxFx0.Types.Decision (DialogueOutputMode(..), dialogueOutputModeText, parseDialogueOutputMode, SemanticAnchor, TurnDecision)
import QxFx0.Types.Domain
  ( AtomTrace
  , CanonicalMoveFamily
  , ClusterDef
  , Embedding
  , IdentityClaimRef
  , IllocutionaryForce
  , MorphologyData(..)
  , SemanticLayer
  , SemanticScene
  , UserState
  )
import QxFx0.Types.Lexicon.RuntimeParadigms (RuntimeParadigms, emptyRuntimeParadigms)
import QxFx0.Types.Bayesian (BeliefState, initialBeliefs)
import QxFx0.Types.Dream (DreamState(..))
import QxFx0.Types.IdentityGuard (IdentityGuardReport)
import QxFx0.Types.Intuition (IntuitiveState, defaultIntuitiveState)
import QxFx0.Types.Observability
  ( KernelPulse
  , MeaningGraph
  , ObservabilityState
  , TruthContractStatus(..)
  , emptyObservabilityState
  )
import QxFx0.Types.Orbital (OrbitalMemory)
import QxFx0.Types.State.Dialogue
  ( DialogueState(..)
  , emptyDialogueState
  )
import QxFx0.Types.State.AdaptiveMutation
  ( AdaptiveMutationRecord
  )
import QxFx0.Types.State.DialogueDevelopment
  ( BeliefStore
  , DialogueCommitmentLedger
  , DialoguePhase(..)
  , DialogueThread
  , DialogueOutcomeLearningState
  , SpeechPolicyState
  , emptyDialogueCommitmentLedger
  , emptyDialogueThread
  , emptyBeliefStore
  , emptyDialogueOutcomeLearningState
  , emptySpeechPolicyState
  )
import QxFx0.Types.State.Perspective
  ( PerspectiveRegistry
  , emptyPerspectiveRegistry
  )
import QxFx0.Types.State.Governance
  ( GovernanceEvent
  , GovernanceProjection(..)
  , GovernanceRuntimeFault
  , ProjectionMeta(..)
  , appendGovernanceEventToHistory
  , currentProjectionVersion
  , currentReducerVersion
  )
import QxFx0.Types.State.Discourse
  ( DiscourseState(..)
  , emptyDiscourseState
  , TurnMemory(..)
  , recomputeDiscourse
  )
import QxFx0.Types.SemanticConfig
  ( SemanticConfig
  , defaultSemanticConfig
  )
import QxFx0.Types.State.Identity
  ( EgoState
  , IdentityState(..)
  , emptyIdentityState
  )
import QxFx0.Types.State.Semantic
  ( SemanticState(..)
  , emptySemanticState
  )
import QxFx0.Types.Vec (zeroVec)
import QxFx0.Types.Dream (emptyDreamState)
import QxFx0.Self.Essence (Essence, emptyEssence)
import QxFx0.Self.Salience (SalienceWeights, defaultSalienceWeights)
import QxFx0.Self.Field (FieldHeuristics, defaultFieldHeuristics)
import QxFx0.Types.Domain.Atoms (ProvisionalAtom)
import QxFx0.Types.State.SelfState
  ( SelfState(..)
  , defaultSelfState
  )
import QxFx0.Learning.Need (LearningNeedState, emptyLearningNeedState)
import QxFx0.Learning.Guardrails (GuardrailState, emptyGuardrailState)
import QxFx0.Learning.Calibration (CalibrationLog(..), emptyCalibrationLog)
import QxFx0.Learning.KnowledgeTree (KnowledgeTree, emptyKnowledgeTree)
import QxFx0.Learning.Signal (CalibrationSnapshot, emptySignalComponents)
import QxFx0.Types.ShadowDivergence (ShadowVetoState, defaultShadowVetoState)
import QxFx0.Types.State.SemanticCommitment (SemanticCommitmentStore)
import QxFx0.Policy.Metacognition (MetacognitionContour)
import QxFx0.Memory.Episodic (EpisodicStore(..), EpisodicIndex, emptyIndex)
import qualified Data.HashSet as HS
import qualified Data.Sequence as Seq
import QxFx0.Types.RuntimeRegime (RuntimeRegime(..), defaultRuntimeRegime)
import QxFx0.Semantic.Network.Types (SemanticNetwork, emptySemanticNetwork)
import QxFx0.Semantic.Network.Seed (seedFromCorpus)
import QxFx0.Semantic.Space.Types (SemanticSpace, emptySemanticSpace)
import QxFx0.Semantic.Intent.Metrics (IntentClassifierMetrics, emptyIntentClassifierMetrics)
import QxFx0.Semantic.ContentSelector.Types (ContentSelector, emptyContentSelector)
import QxFx0.Semantic.Content (ConceptCategory)
import QxFx0.Semantic.Content.AtomStore (AtomGraph, seedGraph)
import QxFx0.Types.State.Stance
  ( StanceState
  , StanceDefense
  , UserStanceTracker
  , StanceLineage
  , emptyStanceDefense
  , emptyUserStanceTracker
  , emptyStanceLineage
  )

data SystemState = SystemState
  { ssDialogue :: !DialogueState
  , ssIdentity :: !IdentityState
  , ssSemantic :: !SemanticState
  , ssSessionId :: !Text
  , ssOutputMode :: !DialogueOutputMode
  , ssMorphology :: !MorphologyData
  , ssRuntimeParadigms :: !RuntimeParadigms
    -- ^ P9 (RGL Russian): runtime morphology paradigms loaded from
    --   paradigms.json. Used by linearizeClaimAstRus when
    --   rrRglMorphologyActive is True. Initialised to emptyRuntimeParadigms.
  , ssObservability :: !ObservabilityState
  , ssSelfState :: !SelfState
    -- ^ Phase 4.1.3: Grouped Self-layer state containing essence,
    --   salience weights, field heuristics, and perspective registry.
    --   Initialised to 'defaultSelfState'.
  , ssShadowVetoState :: !ShadowVetoState
    -- ^ WP2 (GAP2): bounded shadow-veto counter and window anchor.
    --   Tracks gate-trigger count within a sliding window to prevent
    --   infinite shadow-verdict loops.  Initialised to
  , ssProvisionalAtoms :: ![ProvisionalAtom]
    -- ^ WP3 (GAP3): provisional-atom quarantine for ontology accretion.
    --   Atoms observed from user input that do not yet match canonical
    --   clusters are held here until they meet promotion criteria or
    --   decay.  Initialised to '[]'.
  , ssLearningNeedState :: !LearningNeedState
    -- ^ WP1: endogenous learning diagnostic drive state.
    --   Tracks persistent deficit patterns (salience calibration,
    --   keyword enrichment, lexicon extension) across turns.
    --   Initialised to 'emptyLearningNeedState'.
  , ssGuardrailState :: !GuardrailState
    -- ^ WP5: guardrail counters for rate limit, circuit breaker,
    --   and quarantine.  Initialised to 'emptyGuardrailState'.
  , ssCalibrationLog :: !CalibrationLog
    -- ^ WP4: versioned calibration ledger (accepted/rolled-back
    --   proposals).  Initialised to 'emptyCalibrationLog'.
  , ssKnowledgeTree :: !KnowledgeTree
    -- ^ Phase 7: rooted knowledge tree anchored in the current
    --   EssenceCommitment.  Branches keyed by reconcile rule;
    --   fruits validated through verify/simulate gates.
    --   Initialised to 'emptyKnowledgeTree'.
  , ssToolReliability :: !(M.Map Text Double)
    -- ^ WP5: dynamic reliability overrides per tool name.
    --   Updated by acceptance/rejection outcomes.  Names not present
    --   fall back to static profile defaults.  Initialised to 'M.empty'.
  , ssCalibrationSnapshots :: ![CalibrationSnapshot]
    -- ^ Phase 9: audit trail of calibration signal computations.
    --   Each turn that produces a signal appends a snapshot with
    --   timestamp, run-id, components, and decision.  Bounded to
    --   the most recent 100 entries to prevent unbounded growth.
    --   Initialised to '[]'.
  , ssAdaptiveMutationLog :: ![AdaptiveMutationRecord]
    -- ^ P0: unified bounded log of meaningful adaptive mutations across
    --   knowledge, calibration, tool reliability, speech policy, and
    --   claim-stance contours. Initialised to '[]'.
  , ssDialogueOutcomeLearning :: !DialogueOutcomeLearningState
  , ssDialogueThread :: !DialogueThread
    -- ^ Canonical shared-thinking thread derived from event history and
    --   updated per turn. Single authoritative carrier of current
    --   conversational focus and active unresolved object.
  , ssDialogueCommitmentLedger :: !DialogueCommitmentLedger
    -- ^ Canonical dialogue commitment state. Constrains future moves and
    --   prevents planning from ignoring accepted/contested/suspended claims.
  , ssDialoguePhase :: !DialoguePhase
    -- ^ Machine-enforced current phase of the dialogue.
    -- ^ Phase 11/ADR-0032: bounded outcome counters and recent
    --   dialogue-outcome samples. Initialised to
    --   'emptyDialogueOutcomeLearningState'.
  , ssTruthContractStatus :: !TruthContractStatus
    -- ^ Persisted post-turn truth contract used to cap downstream channels.
  , ssSpeechPolicyState :: !SpeechPolicyState
    -- ^ Phase 11/ADR-0032: bounded style-pressure state derived from
    --   strong dialogue outcomes. Initialised to 'emptySpeechPolicyState'.
  , ssBeliefStore :: !BeliefStore
    -- ^ Phase 11/ADR-0032: revisable dialogue claim-stance memory,
    --   separate from the validated 'KnowledgeTree'. The legacy field name
    --   is kept for persisted JSON compatibility; conceptually this is the
    --   ClaimStanceStore contour. Initialised to 'emptyBeliefStore'.
  , ssGovernanceProjection :: !GovernanceProjection
    -- ^ Rebuildable governance-wide runtime projection derived from
    --   canonical governance history.
  , ssGovernanceHistory :: ![GovernanceEvent]
    -- ^ P5: append-only canonical governance history for high-impact
    --   governed mutations. Initialised to '[]'.
  , ssGovernanceRuntimeFault :: !(Maybe GovernanceRuntimeFault)
  , ssSemanticCommitments :: !(Maybe SemanticCommitmentStore)
    -- ^ P2: typed commitment store for semantic authority.  @Nothing@
    --   means Package 2 has not yet initialised the store; @Just@ means
    --   commitments can be created, revised, retracted, and contradicted.
  , ssMetacognition :: !(Maybe MetacognitionContour)
    -- ^ P9: metacognitive correction loop state.  @Nothing@ until the
    --   first turn; @Just@ after the first runMetacognitionLoop call.
  , ssEpisodic :: !(Maybe EpisodicStore)
    -- ^ P7: episodic memory store.  @Nothing@ until the first turn's
    --   encode call; @Just@ after the first encode.
  , ssUserModel :: !BeliefState
    -- ^ WP-A: Bayesian posterior over hidden user intents
    --   (@UserWantsDefine|…|UserIsDistressed@).  Updated per turn by
    --   'QxFx0.Core.Bayesian.bayesianUpdateFromText'; initialised to
    --   'initialBeliefs' (uniform prior).
  , ssMood :: !Double
    -- ^ WP-E: slow affective baseline (valence EMA over ~'moodWindowTurns'
    --   turns), range @[-1,1]@.  Fast per-turn 'Atmosphere' rides on this;
    --   updated by 'QxFx0.Self.Field.updateMood'.  Initialised to @0.0@.
  , ssCurrentRegime :: !RuntimeRegime
    -- ^ M5: the runtime regime active for this session. Records which
    --   math version and feature flags are in effect, making governance
    --   machine-visible. Initialised to 'defaultRuntimeRegime' on
    --   bootstrap; updated when a promotion ADR is executed.
  , ssSemanticNetwork :: !SemanticNetwork
    -- ^ Phase 1: semantic network built from MeaningGraph edges.
    --   Used for spreading activation and content density gating.
    --   Initialised to 'emptySemanticNetwork'.
  , ssSemanticSpace :: !SemanticSpace
    -- ^ Phase 1: vector space for predicate affinity computation.
    --   Built from semantic network nodes. Used by ContentSelector.
    --   Initialised to 'emptySemanticSpace'.
  , ssContentSelector :: !ContentSelector
    -- ^ Phase 1: selects predicates based on Field state and topic.
    --   Replaces direct definitionCorpus lookup in rendering.
    --   Initialised to 'emptyContentSelector'.
  , ssGeometricMetrics :: !IntentClassifierMetrics
    -- ^ Phase 2: A/B validation metrics for geometric intent classifier.
    --   Tracks agreement/disagreement with runSemanticLogic.
    --   Initialised to 'emptyIntentClassifierMetrics'.
  , ssLemmaMap :: !(M.Map Text Text)
    -- ^ Morphological normalization: surface form → lemma mapping.
    --   Built from MorphologyData via buildLemmaMap.
    --   Used to normalize atoms before prototype matching.
    --   Initialised to 'M.empty', populated in Bootstrap.
  , ssCategoryMap :: !(M.Map Text ConceptCategory)
    -- ^ Anomaly detection: topic → concept category mapping.
    --   Built from definitionCorpus topics via classifyConceptCategory.
    --   Used to constrain predicate selection within same category.
    --   Initialised to 'M.empty', populated in Bootstrap.
  , ssStances :: !(M.Map Text StanceState)
    -- ^ Anomaly detection: topic → current stance state.
    --   Tracks system's stance on each topic for revision detection.
    --   Initialised to 'M.empty'.
  , ssStanceDefenses :: !(M.Map Text StanceDefense)
    -- ^ Anomaly detection: topic → stance defense state.
    --   Tracks attack count, evidence seen, recovery counter per topic.
    --   Initialised to 'M.empty'.
  , ssUserStanceTrackers :: !(M.Map Text UserStanceTracker)
    -- ^ Anomaly detection: topic → user stance tracker.
    --   Tracks user's stance history for consistency detection.
    --   Initialised to 'M.empty'.
  , ssStanceLineages :: !(M.Map Text StanceLineage)
    -- ^ Anomaly detection: topic → stance lineage.
    --   Tracks stance transitions for temporal anomaly detection.
    --   Initialised to 'M.empty'.
  , ssRuntimeGraph :: !AtomGraph
    -- ^ Runtime atom graph: seed relations + promoted substrate relations.
    --   Used by PathFinder for generative composition. Initialised to
    --   'seedGraph', updated in Bootstrap with promoted substrate.
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON SystemState where
  toJSON ss = object
    [ "schemaVersion" .= currentSystemStateSchemaVersion
    , "history" .= dsHistory (ssDialogue ss)
    , "rawInputHistory" .= dsRawInputHistory (ssDialogue ss)
    , "turnCount" .= dsTurnCount (ssDialogue ss)
    , "lastFamily" .= dsLastFamily (ssDialogue ss)
    , "lastTopic" .= dsLastTopic (ssDialogue ss)
    , "lastForce" .= dsLastForce (ssDialogue ss)
    , "lastLayer" .= dsLastLayer (ssDialogue ss)
    , "lastEmbedding" .= dsLastEmbedding (ssDialogue ss)
    , "consecutiveReflect" .= dsConsecutiveReflect (ssDialogue ss)
    , "recentFamilies" .= dsRecentFamilies (ssDialogue ss)
    , "activeScene" .= dsActiveScene (ssDialogue ss)
     , "userState" .= dsUserState (ssDialogue ss)
     , "lastSalienceBias" .= dsLastSalienceBias (ssDialogue ss)
     , "holisticStreak" .= dsHolisticStreak (ssDialogue ss)
     , "recentNarrativeSuccess" .= dsRecentNarrativeSuccess (ssDialogue ss)
     , "ego" .= idsEgo (ssIdentity ss)
    , "identityClaims" .= idsIdentityClaims (ssIdentity ss)
    , "orbitalMemory" .= idsOrbitalMemory (ssIdentity ss)
    , "lastGuardReport" .= idsLastGuardReport (ssIdentity ss)
    , "trace" .= semTrace (ssSemantic ss)
    , "meaningGraph" .= semMeaningGraph (ssSemantic ss)
    , "kernelPulse" .= semKernelPulse (ssSemantic ss)
    , "blockedConcepts" .= semBlockedConcepts (ssSemantic ss)
    , "clusters" .= semClusters (ssSemantic ss)
    , "dreamState" .= semDreamState (ssSemantic ss)
    , "intuitionState" .= semIntuitionState (ssSemantic ss)
    , "semanticAnchor" .= semSemanticAnchor (ssSemantic ss)
    , "lastTurnDecision" .= semLastTurnDecision (ssSemantic ss)
    , "intuitConfidence" .= semIntuitConfidence (ssSemantic ss)
    , "sessionId" .= ssSessionId ss
     , "outputMode" .= dialogueOutputModeText (ssOutputMode ss)
     , "morphology" .= ssMorphology ss
     , "observability" .= ssObservability ss
     -- Phase 4.1.3: Grouped Self-layer state (single source of truth)
     , "ssSelfState" .= ssSelfState ss
     , "shadowVetoState" .= ssShadowVetoState ss
     , "provisionalAtoms" .= ssProvisionalAtoms ss
     , "learningNeedState" .= ssLearningNeedState ss
     , "guardrailState" .= ssGuardrailState ss
     , "calibrationLog" .= ssCalibrationLog ss
      , "knowledgeTree" .= ssKnowledgeTree ss
      , "toolReliability" .= ssToolReliability ss
      , "calibrationSnapshots" .= ssCalibrationSnapshots ss
      , "adaptiveMutationLog" .= ssAdaptiveMutationLog ss
        , "dialogueOutcomeLearning" .= ssDialogueOutcomeLearning ss
        , "dialogueThread" .= ssDialogueThread ss
        , "dialogueCommitmentLedger" .= ssDialogueCommitmentLedger ss
        , "dialoguePhase" .= ssDialoguePhase ss
        , "truthContractStatus" .= ssTruthContractStatus ss
         , "speechPolicyState" .= ssSpeechPolicyState ss
         , "beliefStore" .= ssBeliefStore ss
         , "governanceHistory" .= ssGovernanceHistory ss
         , "governanceRuntimeFault" .= ssGovernanceRuntimeFault ss
          , "semanticCommitments" .= ssSemanticCommitments ss
           , "metacognition" .= ssMetacognition ss
           , "episodic" .= ssEpisodic ss
            , "userModel" .= ssUserModel ss
            , "mood" .= ssMood ss
            , "currentRegime" .= ssCurrentRegime ss
            , "runtimeParadigms" .= ssRuntimeParadigms ss
            , "semanticNetwork" .= ssSemanticNetwork ss
            , "semanticSpace" .= ssSemanticSpace ss
             , "contentSelector" .= ssContentSelector ss
              , "lemmaMap" .= ssLemmaMap ss
              , "categoryMap" .= ssCategoryMap ss
              , "stances" .= ssStances ss
              , "stanceDefenses" .= ssStanceDefenses ss
              , "userStanceTrackers" .= ssUserStanceTrackers ss
              , "stanceLineages" .= ssStanceLineages ss
              , "runtimeGraph" .= ssRuntimeGraph ss
              ]

instance FromJSON SystemState where
  parseJSON = withObject "SystemState" $ \o -> do
    schemaVersion <- o .:? "schemaVersion" .!= 1
    let requiredTopLevelFields
          | schemaVersion >= currentSystemStateSchemaVersion =
              [ "morphology"
              , "ssSelfState"
              , "learningNeedState"
              , "knowledgeTree"
              , "truthContractStatus"
              , "dialogueOutcomeLearning"
              , "dialogueThread"
              , "dialogueCommitmentLedger"
              , "dialoguePhase"
              , "speechPolicyState"
              , "beliefStore"
              , "governanceHistory"
              ]
          | otherwise =
              -- Legacy (pre-v2) required set. 'salienceWeights' and
              -- 'fieldHeuristics' are intentionally NOT here: in the legacy
              -- branch they parse via '.:? .!= default' (folded into ssSelfState
              -- in v2), so demanding them rejected genuinely-old state that
              -- never carried them top-level.
              [ "morphology"
              , "learningNeedState"
              , "knowledgeTree"
              , "truthContractStatus"
              ]
        missingTopLevel = filter (\k -> not (KM.member (AK.fromText k) o)) requiredTopLevelFields
    when (not (null missingTopLevel)) $
      fail ("missing required top-level fields: " <> show missingTopLevel)
    ds <- DialogueState
      <$> o .: "history"
      <*> o .: "rawInputHistory"
      <*> o .: "turnCount"
      <*> o .: "lastTopic"
      <*> o .: "lastFamily"
      <*> o .: "lastForce"
      <*> o .: "lastLayer"
      <*> o .: "lastEmbedding"
      <*> o .: "consecutiveReflect"
      <*> o .: "recentFamilies"
      <*> o .: "activeScene"
      <*> o .: "userState"
      <*> o .:? "lastSalienceBias" .!= 0.0
      <*> o .:? "holisticStreak" .!= 0
      <*> o .:? "recentNarrativeSuccess" .!= []
    ids <- IdentityState
      <$> o .: "ego"
      <*> o .: "identityClaims"
      <*> o .: "orbitalMemory"
      <*> o .:? "lastGuardReport" .!= Nothing
    sem <- SemanticState
      <$> o .: "trace"
      <*> o .: "meaningGraph"
      <*> o .: "kernelPulse"
      <*> o .: "blockedConcepts"
      <*> o .: "clusters"
      <*> o .:? "dreamState" .!= emptyDreamState zeroVec
      <*> o .:? "intuitionState" .!= Just defaultIntuitiveState
      <*> o .:? "semanticAnchor" .!= Nothing
      <*> o .:? "lastTurnDecision" .!= Nothing
      <*> o .: "intuitConfidence"
      <*> o .:? "semanticConfig" .!= defaultSemanticConfig
    -- Phase 4.1.3: Read SelfState with backward compatibility fallback
    selfState <- (o .:? "ssSelfState") >>= \case
      Just s -> pure s
      Nothing -> SelfState
        <$> (if schemaVersion >= currentSystemStateSchemaVersion
             then o .: "salienceWeights"
             else o .:? "salienceWeights" .!= defaultSalienceWeights)
        <*> (if schemaVersion >= currentSystemStateSchemaVersion
             then o .: "fieldHeuristics"
             else o .:? "fieldHeuristics" .!= defaultFieldHeuristics)
        <*> pure emptyPerspectiveRegistry
        <*> o .:? "essence" .!= emptyEssence
    
    SystemState ds ids sem
      <$> o .: "sessionId"
      <*> (parseDialogueOutputMode <$> o .: "outputMode")
      <*> (if schemaVersion >= currentSystemStateSchemaVersion then o .: "morphology" else o .:? "morphology" .!= MorphologyData M.empty M.empty M.empty M.empty)
      <*> o .:? "runtimeParadigms" .!= emptyRuntimeParadigms
      <*> o .: "observability"
      <*> pure selfState
       <*> o .:? "shadowVetoState" .!= defaultShadowVetoState
       <*> o .:? "provisionalAtoms" .!= []
       <*> (if schemaVersion >= currentSystemStateSchemaVersion then o .: "learningNeedState" else o .:? "learningNeedState" .!= emptyLearningNeedState)
       <*> o .:? "guardrailState" .!= emptyGuardrailState
       <*> o .:? "calibrationLog" .!= emptyCalibrationLog
          <*> (if schemaVersion >= currentSystemStateSchemaVersion then o .: "knowledgeTree" else o .:? "knowledgeTree" .!= emptyKnowledgeTree)
          <*> o .:? "toolReliability" .!= M.empty
          <*> o .:? "calibrationSnapshots" .!= []
          <*> o .:? "adaptiveMutationLog" .!= []
           <*> (if schemaVersion >= currentSystemStateSchemaVersion then o .: "dialogueOutcomeLearning" else o .:? "dialogueOutcomeLearning" .!= emptyDialogueOutcomeLearningState)
           <*> (if schemaVersion >= currentSystemStateSchemaVersion then o .: "dialogueThread" else o .:? "dialogueThread" .!= emptyDialogueThread)
           <*> (if schemaVersion >= currentSystemStateSchemaVersion then o .: "dialogueCommitmentLedger" else o .:? "dialogueCommitmentLedger" .!= emptyDialogueCommitmentLedger)
           <*> (if schemaVersion >= currentSystemStateSchemaVersion then o .: "dialoguePhase" else o .:? "dialoguePhase" .!= Exploring)
            <*> (if schemaVersion >= currentSystemStateSchemaVersion then o .: "truthContractStatus" else o .:? "truthContractStatus" .!= LegacyIncompleteSurface)
            <*> (if schemaVersion >= currentSystemStateSchemaVersion then o .: "speechPolicyState" else o .:? "speechPolicyState" .!= emptySpeechPolicyState)
            <*> (if schemaVersion >= currentSystemStateSchemaVersion then o .: "beliefStore" else o .:? "beliefStore" .!= emptyBeliefStore)
            <*> pure emptyGovernanceProjection
            <*> (if schemaVersion >= currentSystemStateSchemaVersion then o .: "governanceHistory" else o .:? "governanceHistory" .!= [])
            <*> o .:? "governanceRuntimeFault" .!= Nothing
            <*> o .:? "semanticCommitments" .!= Nothing
            <*> o .:? "metacognition" .!= Nothing
            <*> o .:? "episodic" .!= Nothing
            <*> o .:? "userModel" .!= initialBeliefs
            <*> o .:? "mood" .!= 0.0
            <*> o .:? "currentRegime" .!= defaultRuntimeRegime
            <*> o .:? "semanticNetwork" .!= emptySemanticNetwork
            <*> o .:? "semanticSpace" .!= emptySemanticSpace
             <*> o .:? "contentSelector" .!= emptyContentSelector
              <*> o .:? "geometricMetrics" .!= emptyIntentClassifierMetrics
              <*> o .:? "lemmaMap" .!= M.empty
              <*> o .:? "categoryMap" .!= M.empty
              <*> o .:? "stances" .!= M.empty
              <*> o .:? "stanceDefenses" .!= M.empty
              <*> o .:? "userStanceTrackers" .!= M.empty
              <*> o .:? "stanceLineages" .!= M.empty
              <*> o .:? "runtimeGraph" .!= seedGraph

ssHistory :: SystemState -> Seq Text
ssHistory = dsHistory . ssDialogue

ssRawInputHistory :: SystemState -> Seq Text
ssRawInputHistory = dsRawInputHistory . ssDialogue

ssTurnCount :: SystemState -> Int
ssTurnCount = dsTurnCount . ssDialogue

ssLastFamily :: SystemState -> CanonicalMoveFamily
ssLastFamily = dsLastFamily . ssDialogue

ssLastTopic :: SystemState -> Text
ssLastTopic = dsLastTopic . ssDialogue

ssLastForce :: SystemState -> IllocutionaryForce
ssLastForce = dsLastForce . ssDialogue

ssLastLayer :: SystemState -> SemanticLayer
ssLastLayer = dsLastLayer . ssDialogue

ssLastEmbedding :: SystemState -> Maybe Embedding
ssLastEmbedding = dsLastEmbedding . ssDialogue

ssConsecutiveReflect :: SystemState -> Int
ssConsecutiveReflect = dsConsecutiveReflect . ssDialogue

ssRecentFamilies :: SystemState -> [CanonicalMoveFamily]
ssRecentFamilies = dsRecentFamilies . ssDialogue

ssActiveScene :: SystemState -> SemanticScene
ssActiveScene = dsActiveScene . ssDialogue

ssUserState :: SystemState -> UserState
ssUserState = dsUserState . ssDialogue

ssEgo :: SystemState -> EgoState
ssEgo = idsEgo . ssIdentity

ssIdentityClaims :: SystemState -> [IdentityClaimRef]
ssIdentityClaims = idsIdentityClaims . ssIdentity

ssOrbitalMemory :: SystemState -> OrbitalMemory
ssOrbitalMemory = idsOrbitalMemory . ssIdentity

-- | Legacy persisted shapes may omit or null this field; both decode to
-- Nothing and runtime repopulates it opportunistically per turn.
ssLastGuardReport :: SystemState -> Maybe IdentityGuardReport
ssLastGuardReport = idsLastGuardReport . ssIdentity

ssTrace :: SystemState -> AtomTrace
ssTrace = semTrace . ssSemantic

ssMeaningGraph :: SystemState -> MeaningGraph
ssMeaningGraph = semMeaningGraph . ssSemantic

ssDiscourse :: SystemState -> DiscourseState
ssDiscourse ss =
  let history = dsHistory (ssDialogue ss)
      turnCount = dsTurnCount (ssDialogue ss)
      lastTopic = dsLastTopic (ssDialogue ss)
      turnMemory = if turnCount <= 0
        then Seq.empty
        else Seq.singleton TurnMemory
          { tmrTurnIndex = max 0 (turnCount - 1)
          , tmrTopic = lastTopic
          , tmrFamily = dsLastFamily (ssDialogue ss)
          , tmrRendered = maybe "" id (Seq.lookup (max 0 (Seq.length history - 1)) history)
          }
  in recomputeDiscourse emptyDiscourseState
       { dscTurnMemory = turnMemory
       , dscTopicChain = filter (not . T.null) [lastTopic]
       }

ssSemanticConfig :: SystemState -> SemanticConfig
ssSemanticConfig = semConfig . ssSemantic

ssKernelPulse :: SystemState -> KernelPulse
ssKernelPulse = semKernelPulse . ssSemantic

ssBlockedConcepts :: SystemState -> [Text]
ssBlockedConcepts = semBlockedConcepts . ssSemantic

ssClusters :: SystemState -> [ClusterDef]
ssClusters = semClusters . ssSemantic

ssSemanticAnchor :: SystemState -> Maybe SemanticAnchor
ssSemanticAnchor = semSemanticAnchor . ssSemantic

ssLastTurnDecision :: SystemState -> Maybe TurnDecision
ssLastTurnDecision = semLastTurnDecision . ssSemantic

ssIntuitConfidence :: SystemState -> Double
ssIntuitConfidence = semIntuitConfidence . ssSemantic

ssDreamAxiom :: SystemState -> Text
ssDreamAxiom ss =
  let dreamState = semDreamState (ssSemantic ss)
      cycles = dsDreamCycleCount dreamState
  in if cycles <= 0
       then ""
       else T.concat ["dream_cycle_count=", T.pack (show cycles)]

ssDreamState :: SystemState -> DreamState
ssDreamState = semDreamState . ssSemantic

ssIntuitionState :: SystemState -> Maybe IntuitiveState
ssIntuitionState = semIntuitionState . ssSemantic

ssLastSalienceBias :: SystemState -> Double
ssLastSalienceBias = dsLastSalienceBias . ssDialogue

ssHolisticStreak :: SystemState -> Int
ssHolisticStreak = dsHolisticStreak . ssDialogue

ssRecentNarrativeSuccess :: SystemState -> [Bool]
ssRecentNarrativeSuccess = dsRecentNarrativeSuccess . ssDialogue

adaptiveMutationLogLimit :: Int
adaptiveMutationLogLimit = 100

currentSystemStateSchemaVersion :: Int
currentSystemStateSchemaVersion = 2

appendAdaptiveMutationRecord :: AdaptiveMutationRecord -> SystemState -> SystemState
appendAdaptiveMutationRecord record ss =
  ss { ssAdaptiveMutationLog = take adaptiveMutationLogLimit (record : ssAdaptiveMutationLog ss) }

appendAdaptiveMutationRecords :: [AdaptiveMutationRecord] -> SystemState -> SystemState
appendAdaptiveMutationRecords records ss =
  ss { ssAdaptiveMutationLog = take adaptiveMutationLogLimit (records ++ ssAdaptiveMutationLog ss) }

commitGovernedPerspectiveProjection :: GovernanceProjection -> AdaptiveMutationRecord -> SystemState -> SystemState
commitGovernedPerspectiveProjection projection record ss =
  let selfState' = (ssSelfState ss) { selfPerspectiveRegistry = gpPerspectiveRegistry projection }
  in appendAdaptiveMutationRecord record ss
    { ssSelfState = selfState'
    , ssGovernanceProjection = projection
    }

appendGovernanceEventRecord :: GovernanceEvent -> SystemState -> Either Text SystemState
appendGovernanceEventRecord event ss = do
  history <- appendGovernanceEventToHistory event (ssGovernanceHistory ss)
  pure ss { ssGovernanceHistory = history }

emptySystemState :: SystemState
emptySystemState = SystemState
  { ssDialogue = emptyDialogueState
  , ssIdentity = emptyIdentityState
  , ssSemantic = emptySemanticState
  , ssSessionId = ""
  , ssOutputMode = DialogueOutput
  , ssMorphology = MorphologyData M.empty M.empty M.empty M.empty
  , ssRuntimeParadigms = emptyRuntimeParadigms
  , ssObservability = emptyObservabilityState
  , ssSelfState = defaultSelfState
  , ssShadowVetoState = defaultShadowVetoState
  , ssProvisionalAtoms = []
  , ssLearningNeedState = emptyLearningNeedState
  , ssGuardrailState = emptyGuardrailState
  , ssCalibrationLog = emptyCalibrationLog
  , ssKnowledgeTree = emptyKnowledgeTree
  , ssToolReliability = M.empty
  , ssCalibrationSnapshots = []
  , ssAdaptiveMutationLog = []
  , ssDialogueOutcomeLearning = emptyDialogueOutcomeLearningState
  , ssDialogueThread = emptyDialogueThread
  , ssDialogueCommitmentLedger = emptyDialogueCommitmentLedger
  , ssDialoguePhase = Exploring
  , ssTruthContractStatus = LegacyIncompleteSurface
  , ssSpeechPolicyState = emptySpeechPolicyState
  , ssBeliefStore = emptyBeliefStore
  , ssGovernanceProjection = emptyGovernanceProjection
  , ssGovernanceHistory = []
  , ssGovernanceRuntimeFault = Nothing
  , ssSemanticCommitments = Nothing
  , ssMetacognition = Nothing
  , ssEpisodic = Just (EpisodicStore Seq.empty emptyIndex HS.empty 0)
    -- ^ WP-B R-B4: explicit initialization instead of lazy Nothing.
    --   Empty store with session-id 0 (will be updated on first encode).
  , ssUserModel = initialBeliefs
  , ssMood = 0.0
  , ssCurrentRegime = defaultRuntimeRegime
  , ssSemanticNetwork = seedFromCorpus M.empty
  , ssSemanticSpace = emptySemanticSpace
  , ssContentSelector = emptyContentSelector
  , ssGeometricMetrics = emptyIntentClassifierMetrics
  , ssLemmaMap = M.empty
  , ssCategoryMap = M.empty
  , ssStances = M.empty
  , ssStanceDefenses = M.empty
  , ssUserStanceTrackers = M.empty
  , ssStanceLineages = M.empty
  , ssRuntimeGraph = seedGraph
  }

emptyGovernanceProjection :: GovernanceProjection
emptyGovernanceProjection = GovernanceProjection
  { gpMeta = ProjectionMeta
      { pmProjectionVersion = currentProjectionVersion
      , pmReducerVersion = currentReducerVersion
      , pmSnapshotTurn = Just 0
      }
  , gpPerspectiveRegistry = emptyPerspectiveRegistry
  , gpActivePerspectiveProjections = []
  , gpGovernedRefs = []
  , gpProjectionChecksum = "governance_projection_empty"
  }
