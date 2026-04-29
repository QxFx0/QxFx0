{-# LANGUAGE StrictData #-}
{-| Shared turn-pipeline phase types for input/signals/plans/artifacts/results. -}
module QxFx0.Core.TurnPipeline.Types
  ( TurnInput(..)
  , TurnSignals(..)
  , TurnPlan(..)
  , TurnArtifacts(..)
  , TurnResult(..)
  , RoutingDecision(..)
  ) where

import QxFx0.Types
import QxFx0.Types.Orbital (OrbitalMemory)
import QxFx0.Core.PrincipledCore (PrincipledMode, PressureSignal)
import QxFx0.Core.IdentitySignal (IdentitySignal)
import QxFx0.Types.IdentityGuard (IdentityGuardReport)
import QxFx0.Core.Consciousness (ConsciousnessNarrative)
import QxFx0.Core.ConsciousnessLoop (ConsciousnessLoop)
import QxFx0.Core.Intuition (IntuitiveFlash)
import QxFx0.Core.Observability (TurnMetrics)
import qualified QxFx0.Core.Guard as Guard
import QxFx0.Core.Semantic.Embedding (EmbeddingSource, EmbeddingQuality)
import QxFx0.Core.Semantic.SemanticInput (SemanticInput)
import QxFx0.Types.ShadowDivergence (ShadowDivergenceKind, ShadowDivergenceSeverity, ShadowSnapshotId)

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

data TurnPlan = TurnPlan
  { tpFamily :: !CanonicalMoveFamily
  , tpNewEgo :: !EgoState
  , tpIdentitySignal :: !IdentitySignal
  , tpGuardReport :: !IdentityGuardReport
  , tpSemanticAnchor :: !(Maybe SemanticAnchor)
  , tpRenderStrategy :: !ResponseStrategy
  , tpRenderStyle :: !Text
  , tpPrincipledMode :: !(Maybe (PressureSignal, PrincipledMode))
  , tpUpdatedOrbital :: !OrbitalMemory
  , tpFromMs :: !MeaningState
  , tpToMs :: !MeaningState
  , tpStrategyFamily :: !(Maybe CanonicalMoveFamily)
  , tpPreShadowFamily :: !CanonicalMoveFamily
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
  , tpMetrics :: !TurnMetrics
  }

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
  }

data TurnResult = TurnResult
  { trNextSs :: !SystemState
  , trOutput :: !Text
  , trMetrics :: !TurnMetrics
  }
