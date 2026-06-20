{-# LANGUAGE StrictData #-}
{-|
Description : observer — Shared turn-pipeline phase types for input/signals/plans/artifacts/results. -}
module QxFx0.Core.TurnPipeline.Types
  ( TurnInput(..)
  , TurnSignals(..)
  , TurnPlan(..)
  , TurnArtifacts(..)
  , TurnResult(..)
  , RenderedTurn(..)
  , RoutingDecision(..)
  , turnResultOutput
  , tpNewEgo
  , tpIdentitySignal
  , tpGuardReport
  , tpSemanticAnchor
  , tpRenderStrategy
  , tpUpdatedOrbital
  , tpFromMs
  , tpToMs
  , tpStrategyFamily
  , tpPreShadowFamily
  , tpPrincipledModePair
  ) where

import QxFx0.Types
import QxFx0.Types.Observability (ArtifactManifest, AssemblyPath, AuthorityClass, ContractProvenance, ExecutedTurnOutcome, SurfaceProvenance, TruthContractStatus)
import QxFx0.Types.Orbital (OrbitalMemory)
import QxFx0.Core.PrincipledCore (PrincipledMode, PressureSignal)
import QxFx0.Core.IdentitySignal (IdentitySignal)
import QxFx0.Types.IdentityGuard (IdentityGuardReport)
import QxFx0.Core.StanceClassifier (ConsciousnessNarrative)
import QxFx0.Core.ConsciousnessLoop (ConsciousnessLoop)
import QxFx0.Types.Intuition (IntuitiveFlash)
import QxFx0.Core.Observability (TurnMetrics)
import qualified QxFx0.Core.Guard as Guard
import QxFx0.Self.Conatus (ConatusEnergy)
import QxFx0.Self.Deliberation (Deliberation)
import QxFx0.Self.Field (Field, FieldHeuristics)
import QxFx0.Self.Salience (SelfVerdict)
import QxFx0.Self.Essence (Essence)
import QxFx0.Semantic.Embedding (EmbeddingSource, EmbeddingQuality)
import QxFx0.Semantic.SemanticInput (SemanticInput)
import QxFx0.Semantic.Sense (SenseVector)
import QxFx0.Types.State.DialogueDevelopment (DialogueCommitmentLedger, DialoguePhase, DialogueThread)
import QxFx0.Types.ShadowDivergence (ShadowDivergenceKind, ShadowDivergenceSeverity, ShadowSnapshotId, ShadowVetoState)
import QxFx0.Core.ResponseContentAdmission (ResponseContentAdmissionDecision)
import QxFx0.Types.ExternalQuery (ExternalQueryError(..), ExternalQueryResponse(..))
import QxFx0.Learning.Guardrails (ExternalActionDecisionTrace)
import QxFx0.Memory.Episodic (EpisodicEvent)
import QxFx0.Types.State.SemanticCommitment (CommitmentEngagement)
import QxFx0.Semantic.Network.Types (SemanticNetwork)
import QxFx0.Semantic.Intent.GeometricClassifier (ClassificationResult)
import QxFx0.Types.Anomaly (AnomalySurface, AnomalyTrace)

import Data.Text (Text)
import Data.Time.Clock (UTCTime)

data RoutingDecision = RoutingDecision
  { rdFamily         :: !CanonicalMoveFamily
  , rdNewEgo         :: !EgoState
  , rdIdentitySignal :: !IdentitySignal
  , rdGuardReport    :: !IdentityGuardReport
  , rdSemanticInput  :: !SemanticInput
  , rdSemanticAnchor :: !(Maybe SemanticAnchor)
  , rdRenderStrategy :: !ResponseStrategy
  , rdRenderStyle    :: !RenderStyle
  , rdPrincipledMode :: !(Maybe PrincipledMode)
  , rdPressure       :: !(Maybe PressureSignal)
  , rdUpdatedOrbital :: !OrbitalMemory
  , rdFromMs         :: !MeaningState
  , rdToMs           :: !MeaningState
  , rdStrategyFamily :: !(Maybe CanonicalMoveFamily)
  , rdDeliberation   :: !(Maybe Deliberation)
  }

data TurnInput = TurnInput
  { tiStartTime :: !UTCTime
  , tiEmbedding :: !Embedding
  , tiEmbeddingSource :: !EmbeddingSource
  , tiEmbeddingQuality :: !EmbeddingQuality
  , tiEmbSimilarity :: !Double
  , tiAtomSet :: !AtomSet
  , tiNewTrace :: !AtomTrace
  , tiNextUserState :: !UserState
  , tiRecommendedFamily :: !CanonicalMoveFamily
  , tiFrame :: !InputPropositionFrame
  , tiNixStatus :: !NixGuardStatus
  , tiNixAvailable :: !Bool
  , tiIsNixBlocked :: !Bool
  , tiConceptToCheck :: !Text
  , tiBestTopic :: !Text
  , tiMetrics :: !TurnMetrics
  , tiConatusEnergy :: !ConatusEnergy
    -- ^ Phase 6 (M6): runtime Conatus energy carried from
    --   'QxFx0.Core.TurnPipeline.Effects.psConatusEnergy'.
    --   Single source of truth across the turn: route-stage
    --   ('buildLocalRecoveryPlan') and finalize-stage trace
    --   ('buildTurnProjection') previously each recomputed
    --   'computeConatusEnergy' independently; now both reads
    --   funnel through this field for the pre-turn state.
  , tiBlanketViolationCount :: !Int
    -- ^ Phase 6 (M6): violation count from
    --   'QxFx0.Core.TurnPipeline.Effects.psBlanketViolationCount',
    --   used by 'buildLocalRecoveryPlan' to construct the
    --   @"blanket_violations=N"@ evidence line.
  , tiConatusGateFired :: !Bool
    -- ^ Phase 6 addendum (M6.1): precomputed Conatus gate flag
    --   from 'psConatusGateFired'.  Single source of truth for
    --   both recovery and salience decisions.
  , tiField :: !Field
    -- ^ Per-turn 'QxFx0.Self.Field.Field' carried from
    --   'QxFx0.Core.TurnPipeline.Effects.psField'.  All five
    --   components are populated from runtime signals
    --   (Resonance from atom-trace, Atmosphere from Ego +
    --   legitimacy, Consolidation from narrative-success window,
    --   Counterfactual from candidate-family entropy, Confidence
    --   derived from the other four).  Single source of truth
    --   across the turn so routing ('routeFamily'), salience
    --   computation, and finalize-stage trace share the same
    --   Field instead of each constructing 'emptyField'
    --   independently.
  , tiFieldHeuristics :: !FieldHeuristics
    -- ^ Phase 6.7: the heuristic parameters used to build
    --   'tiField'.  Mirrors 'psFieldHeuristics' from
    --   'PrepareStatic' so downstream stages can read the
    --   same record without reconstructing defaults.
  , tiSelfVerdict :: !SelfVerdict
    -- ^ Canonical aggregated self-layer verdict, computed once in the
    --   prepare stage from 'tiConatusEnergy' and 'tiField'. Downstream
    --   route/finalize stages should consume this instead of rebuilding
    --   salience and its discrete verdict ad hoc.
  , tiSenseVector :: !SenseVector
    -- ^ Canonical sense-layer bridge extracted from the same semantic
    --   interpretation that produced 'tiFrame'. Used to constrain
    --   response planning toward bounded adjacent meaning-continuation.
  , tiDialogueThread :: !DialogueThread
  , tiDialogueCommitmentLedger :: !DialogueCommitmentLedger
  , tiDialoguePhase :: !DialoguePhase
  , tiTruthContractStatus :: !TruthContractStatus
  , tiEssence :: !Essence
    -- ^ Phase 9: the pre-turn essence carrier, populated by
    --   'buildPrepareEffectPlan' from 'ssEssence'.  Single source
    --   of truth for the turn's essence-layer reads.
  , tiDoubtScore :: !Double
    -- ^ WP-D: doubt score in @[0,1]@ derived from 'tiSelfVerdict'
    --   via 'QxFx0.Core.ConsciousnessLoop.computeDoubt'.  High doubt
    --   (≥ 'doubtSuppressionThreshold') signals uncertainty and can
    --   drive routing toward clarifying moves (CMClarify) or reduce
    --   explicitness.  Single source of truth for doubt-driven
    --   routing decisions.
  , tiRetrievedEpisodes :: ![EpisodicEvent]
    -- ^ WP-B R-B1: episodes retrieved from 'ssEpisodic' via frame-driven
    --   query on Prepare stage.  Enables routing/planning to avoid
    --   re-asking established facts or repeating recent decisions.
    --   Empty list when 'episodicRecallActive' is False or no relevant
    --   episodes exist.  Living consumer of 'QxFx0.Memory.Episodic.retrieve'.
  , tiActivatedNetwork :: !(Maybe SemanticNetwork)
    -- ^ Phase 1: semantic network after spreading activation, populated
    --   when 'contentDensityGate' passes.  Enables content selection
    --   to use activated atoms for predicate filtering.  Nothing when
    --   gate fails or network is empty.
  , tiGeoResult :: !(Maybe ClassificationResult)
    -- ^ Phase 2: geometric classifier result for A/B validation.
    --   Populated in Prepare stage, consumed in Finalize for metrics.
  }

data TurnSignals = TurnSignals
  { tsConsciousLoop' :: !ConsciousnessLoop
  , tsCurrentNarrative :: !(Maybe ConsciousnessNarrative)
  , tsNarrativeFragment :: !(Maybe Text)
  , tsFlash :: !(Maybe IntuitiveFlash)
  , tsIntuitPosterior :: !Double
  , tsIntuitionState :: !IntuitiveState
  , tsApiHealthy :: !Bool
  }

{-| Route-phase plan: cascade snapshot plus shadow/legitimacy/render derivations. -}
data TurnPlan = TurnPlan
  { tpRouting :: !RoutingDecision
  , tpFamily :: !CanonicalMoveFamily
  , tpRenderStyle :: !Text
  , tpRmpAfterLegit :: !ResponseMeaningPlan
  , tpRcpFinal :: !ResponseContentPlan
  , tpFinalFamily :: !CanonicalMoveFamily
  , tpFinalForce :: !IllocutionaryForce
  , tpLegitScore :: !Double
  , tpActiveScene :: !SemanticScene
  , tpShadowStatus :: !ShadowStatus
  , tpShadowDivergence :: !Bool
  , tpShadowDivergenceKind :: !ShadowDivergenceKind
  , tpShadowDivergenceSeverity :: !ShadowDivergenceSeverity
  , tpShadowGateTriggered :: !Bool
  , tpShadowSnapshotId :: !ShadowSnapshotId
  , tpShadowFamily :: !(Maybe CanonicalMoveFamily)
  , tpShadowForce :: !(Maybe IllocutionaryForce)
  , tpShadowMessage :: !Text
  , tpShadowVetoState :: !ShadowVetoState
    -- ^ WP2 (GAP2): bounded shadow-veto counter and window anchor
    --   carried through the turn so that 'buildNextSystemState' can
    --   persist it without recomputing the shadow policy.
  , tpMetrics :: !TurnMetrics
  , tpDeliberation :: !(Maybe Deliberation)
  , tpFmarDirective :: !(Maybe MeaningDirective)
    -- ^ FMAR Phase-7: the meaning-shaped directive computed in
    --   'routeTurnPlan' when @QXFX0_FMAR@ is shadow or live. 'Nothing'
    --   on the static path. In shadow mode this is carried for tracing
    --   only; in live mode the family override has already been applied.
  , tpFamilyDerivationChain :: ![TurnFamilyDerivationStep]
    -- ^ P9: provenance chain of family values through the route pipeline.
    --   Populated by 'buildRouteTurnPlan' so that trace projection can
    --   replay every intermediate family without rebuilding the chain.
  , tpResponseAdmission :: !ResponseContentAdmissionDecision
    -- ^ CTS-41: constitution-aware filtering decision applied to RMP/RCP
    --   between planning and render. Determines whether plans are admitted
    --   as-is, softened, weakened, or rerouted to clarify.
  , tpCommitmentEngagement :: !CommitmentEngagement
    -- ^ SUBJECT-SEAM-1: whether the turn engages or contradicts held
    --   commitments. Populated in 'buildRouteTurnPlan' from the active
    --   store and current atom set.
  , tpAnomalySurface :: !(Maybe AnomalySurface)
    -- ^ Anomaly detection: typed render payload when an anomaly is detected.
    --   Populated by 'buildAnomalyTurnPlan' in Route phase. Nothing on normal path.
  , tpAnomalyTrace :: !(Maybe AnomalyTrace)
    -- ^ Anomaly detection: trace information for observability when anomaly detected.
    --   Populated alongside tpAnomalySurface. Nothing on normal path.
  , tpSemanticFirstDisabled :: !Bool
    -- ^ B2 Control-A ablation: when True, render pipeline skips semantic-first
    --   path and uses assembly/template fallback only. Set from env var
    --   QXFX0_CONTROL_A_DISABLE_SEMANTIC_FIRST in routeTurnPlan.
  }

tpNewEgo :: TurnPlan -> EgoState
tpNewEgo tp = rdNewEgo (tpRouting tp)

tpIdentitySignal :: TurnPlan -> IdentitySignal
tpIdentitySignal tp = rdIdentitySignal (tpRouting tp)

tpGuardReport :: TurnPlan -> IdentityGuardReport
tpGuardReport tp = rdGuardReport (tpRouting tp)

tpSemanticAnchor :: TurnPlan -> Maybe SemanticAnchor
tpSemanticAnchor tp = rdSemanticAnchor (tpRouting tp)

tpRenderStrategy :: TurnPlan -> ResponseStrategy
tpRenderStrategy tp = rdRenderStrategy (tpRouting tp)

tpUpdatedOrbital :: TurnPlan -> OrbitalMemory
tpUpdatedOrbital tp = rdUpdatedOrbital (tpRouting tp)

tpFromMs :: TurnPlan -> MeaningState
tpFromMs tp = rdFromMs (tpRouting tp)

tpToMs :: TurnPlan -> MeaningState
tpToMs tp = rdToMs (tpRouting tp)

tpStrategyFamily :: TurnPlan -> Maybe CanonicalMoveFamily
tpStrategyFamily tp = rdStrategyFamily (tpRouting tp)

tpPreShadowFamily :: TurnPlan -> CanonicalMoveFamily
tpPreShadowFamily tp = rdFamily (tpRouting tp)

tpPrincipledModePair :: TurnPlan -> Maybe (PressureSignal, PrincipledMode)
tpPrincipledModePair tp =
  case (rdPressure (tpRouting tp), rdPrincipledMode (tpRouting tp)) of
    (Just p, Just pm) -> Just (p, pm)
    _ -> Nothing

data TurnArtifacts = TurnArtifacts
  { taPreSafetyRendered :: !Text
  , taGuardSurface :: !Guard.GuardSurface
  , taRendered :: !Text
  , taSurfaceProv :: !SurfaceProvenance
  , taContractProv :: !ContractProvenance
  , taAuthorityClass :: !AuthorityClass
  , taTruthContractStatus :: !TruthContractStatus
  , taAssemblyPath :: !AssemblyPath
  , taArtifactManifest :: !ArtifactManifest
  , taExecutedOutcome :: !ExecutedTurnOutcome
  , taDerivationTags :: ![Text]
  , taFinalRendered :: !Text
  , taClaimAst :: !(Maybe ClaimAst)
  , taLinearizationLang :: !(Maybe Text)
  , taLinearizationOk :: !Bool
  , taLinearizationFallbackReason :: !(Maybe Text)
  , taDecision :: !TurnDecision
  , taLocalRecoveryCause :: !(Maybe LocalRecoveryCause)
  , taLocalRecoveryStrategy :: !(Maybe LocalRecoveryStrategy)
  , taLocalRecoveryEvidence :: ![Text]
  , taMetrics :: !TurnMetrics
  , taKnowledgeSource :: !(Maybe Text)
  , taExternalQueryResult :: !(Maybe (Either ExternalQueryError ExternalQueryResponse))
    -- ^ Phase 8 gap closure: result of the external query effect when a
    --   request strategy was chosen.  Populated by the render phase and
    --   consumed by 'applyExternalLearning' in finalize.
  , taExploratoryQueryResult :: !(Maybe (Either ExternalQueryError ExternalQueryResponse))
    -- ^ Phase 9: result of the autonomous exploratory external query.
    --   Populated by the render phase and consumed by 'applyExternalLearning'
    --   in finalize alongside 'taExternalQueryResult'.
  , taExternalQuerySkipReason :: !(Maybe Text)
    -- ^ WP3 dedup telemetry: populated when an external query was
    --   suppressed because the term was already known in morphology
    --   or knowledge tree.
  , taExternalActionDecisionTrace :: !(Maybe ExternalActionDecisionTrace)
    -- ^ AS1-03: typed rationale for allow/deny/no-action on outbound actions.
  , taGenerationTrace :: ![GenerationAttempt]
    -- ^ P9: text-generation attempt trace from the dialogue renderer.
    --   Populated by 'buildTurnArtifacts' from the DialogueRenderArtifact.
  }

data RenderedTurn = RenderedTurn !TurnInput !TurnSignals !TurnPlan !TurnArtifacts

data TurnResult = TurnResult
  { trRendered :: !RenderedTurn
  , trNextSs :: !SystemState
  , trOutput :: !Text
  , trMetrics :: !TurnMetrics
  }

turnResultOutput :: TurnResult -> Text
turnResultOutput = trOutput
