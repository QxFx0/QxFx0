{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

{-| Canonical top-level persisted system state plus compatibility accessors. -}
module QxFx0.Types.State.System
  ( SystemState(..)
  , CuratedOverlayRuntime(..)
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
  ) where

import Control.DeepSeq (NFData)
import qualified Data.Map.Strict as M
import Data.Sequence (Seq)
import qualified Data.Sequence as Seq
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

import QxFx0.Types.Decision (DialogueOutputMode, SemanticAnchor, TurnDecision)
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
import QxFx0.Types.Lexicon.RuntimeParadigms (RuntimeParadigms)
import QxFx0.Types.Bayesian (BeliefState)
import QxFx0.Types.Dream (DreamState(..))
import QxFx0.Types.IdentityGuard (IdentityGuardReport)
import QxFx0.Types.Intuition (IntuitiveState)
import QxFx0.Types.Observability
  ( KernelPulse
  , MeaningGraph
  , ObservabilityState
  , TruthContractStatus
  )
import QxFx0.Types.Orbital (OrbitalMemory)
import QxFx0.Types.State.Dialogue (DialogueState(..))
import QxFx0.Types.State.AdaptiveMutation
  ( AdaptiveMutationRecord
  )
import QxFx0.Types.State.DialogueDevelopment
  ( BeliefStore
  , DialogueCommitmentLedger
  , DialoguePhase
  , DialogueThread
  , DialogueOutcomeLearningState
  , SpeechPolicyState
  )
import QxFx0.Types.State.Governance
  ( GovernanceEvent
  , GovernanceProjection(..)
  , GovernanceRuntimeFault
  , appendGovernanceEventToHistory
  )
import QxFx0.Types.State.Discourse
  ( DiscourseState(..)
  , emptyDiscourseState
  , TurnMemory(..)
  , recomputeDiscourse
  )
import QxFx0.Types.SemanticConfig
  ( SemanticConfig )
import QxFx0.Types.State.Identity
  ( EgoState
  , IdentityState(..)
  )
import QxFx0.Types.State.Semantic
  ( SemanticState(..)
  )
import QxFx0.Types.Domain.Atoms (ProvisionalAtom)
import QxFx0.Types.State.SelfState
  ( SelfState(..)
  )
import QxFx0.Types.Learning.Need (LearningNeedState)
import QxFx0.Types.Learning.Guardrails (GuardrailState)
import QxFx0.Types.Learning.Calibration (CalibrationLog)
import QxFx0.Types.Learning.KnowledgeTree (KnowledgeTree)
import QxFx0.Types.Learning.Signal (CalibrationSnapshot)
import QxFx0.Types.ShadowDivergence (ShadowVetoState)
import QxFx0.Types.State.SemanticCommitment (SemanticCommitmentStore)
import QxFx0.Types.Policy.Metacognition (MetacognitionContour)
import QxFx0.Types.Memory.Episodic (EpisodicStore)
import Data.Set (Set)
import QxFx0.Types.RuntimeRegime (RuntimeRegime)
import QxFx0.Types.Semantic.Network (ActivationArtifact, SemanticNetwork)
import QxFx0.Types.Semantic.Space (SemanticSpace)
import QxFx0.Types.Semantic.IntentMetrics (IntentClassifierMetrics)
import QxFx0.Types.Semantic.Content (ConceptCategory, DefinitionContent)
import QxFx0.Types.Semantic.ContentSelector (ContentSelector)
import QxFx0.Types.Semantic.AtomGraph (AtomGraph)
import QxFx0.Semantic.ContentSelector.Integration (ContentSelectorState)
import QxFx0.Types.Semantic.Ontology (Ontology)
import QxFx0.Types.State.Stance
  ( StanceState
  , StanceDefense
  , UserStanceTracker
  , StanceLineage
  )

-- | Bootstrap-derived provenance for the explicitly active promotion overlay.
-- This is intentionally runtime-only: the overlay is reconstructed from the
-- promotion store at every bootstrap and must not inflate persisted sessions.
data CuratedOverlayRuntime = CuratedOverlayRuntime
  { corVersion :: !Text
  , corPredicateIdsBySurface :: !(M.Map Text Text)
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

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
    --   Runtime initialization is owned by 'QxFx0.Runtime.StateDefaults'.
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
    --   machine-visible. Selected at bootstrap and updated when a promotion
    --   ADR is executed.
  , ssSemanticNetwork :: !SemanticNetwork
    -- ^ Phase 1: semantic network built from MeaningGraph edges.
    --   Used for spreading activation and content density gating.
    --   Initialised to 'emptySemanticNetwork'.
  , ssLastActivationArtifact :: !(Maybe ActivationArtifact)
    -- ^ Exact activation used by the preceding rendered turn. Kept separate
    --   from graph ownership so the next user feedback consumes that artifact.
  , ssOntology :: !Ontology
    -- ^ ADR-0052 Phase IV: loaded once at bootstrap and passed to the
    --   ontology-driven category classifier.
  , ssSemanticSpace :: !SemanticSpace
    -- ^ Phase 1: vector space for predicate affinity computation.
    --   Built from semantic network nodes. Used by ContentSelector.
    --   Initialised to 'emptySemanticSpace'.
  , ssContentSelector :: !ContentSelector
    -- ^ Phase 1: selects predicates based on Field state and topic.
    --   Replaces direct definitionCorpus lookup in rendering.
    --   Initialised to 'emptyContentSelector'.
  , ssContentSelectorState :: !(Maybe ContentSelectorState)
    -- ^ ContentSelector optimization state with caching and dynamic learning.
    --   Contains predicate indexes, score cache, and ontology learning state.
    --   Initialised to Nothing, populated in Bootstrap when optimizations enabled.
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
    --   Runtime construction and promoted-substrate updates occur in Bootstrap.
  , ssDefinitionCorpus :: !(M.Map Text DefinitionContent)
    -- ^ P1.2: extended definition corpus = hardcoded seed corpus merged with
    --   curated predicates loaded from @resources/knowledge/curated_predicates.jsonl@.
    --   Used by projection to report missing predicates and by rendering paths.
  , ssCuratedOverlay :: !(Maybe CuratedOverlayRuntime)
    -- ^ Active promotion overlay provenance, rebuilt from the local promotion
    -- store on bootstrap. It is never persisted as session authority.
  , ssEmittedPredicates :: !(Set Text)
    -- ^ P2.2: cross-turn coherence buffer. Tracks predicate surface forms
    --   (spRu) emitted in recent turns on the same topic, so the renderer
    --   can avoid repeating them. Cleared on topic change.
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

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
