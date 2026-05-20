{-# LANGUAGE StrictData #-}
{-| Shared turn-pipeline phase types for input/signals/plans/artifacts/results. -}
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
import QxFx0.Types.Orbital (OrbitalMemory)
import QxFx0.Core.PrincipledCore (PrincipledMode, PressureSignal)
import QxFx0.Core.IdentitySignal (IdentitySignal)
import QxFx0.Types.IdentityGuard (IdentityGuardReport)
import QxFx0.Core.Consciousness (ConsciousnessNarrative)
import QxFx0.Core.ConsciousnessLoop (ConsciousnessLoop)
import QxFx0.Types.Intuition (IntuitiveFlash)
import QxFx0.Core.Observability (TurnMetrics)
import qualified QxFx0.Core.Guard as Guard
import QxFx0.Self.Conatus (ConatusEnergy)
import QxFx0.Self.Deliberation (Deliberation)
import QxFx0.Self.Field (Field, FieldHeuristics)
import QxFx0.Self.Essence (Essence)
import QxFx0.Semantic.Embedding (EmbeddingSource, EmbeddingQuality)
import QxFx0.Semantic.SemanticInput (SemanticInput)
import QxFx0.Types.ShadowDivergence (ShadowDivergenceKind, ShadowDivergenceSeverity, ShadowSnapshotId, ShadowVetoState)
import QxFx0.Types.ExternalQuery (ExternalQueryError(..), ExternalQueryResponse(..))

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
  , tiEssence :: !Essence
    -- ^ Phase 9: the pre-turn essence carrier, populated by
    --   'buildPrepareEffectPlan' from 'ssEssence'.  Single source
    --   of truth for the turn's essence-layer reads.
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
