{-|
Description : observer — Public protocol surface for turn-pipeline phase data and effect contracts. -}
module QxFx0.Core.TurnPipeline.Protocol
  ( RoutingDecision(..)
  , TurnInput(..)
  , TurnSignals(..)
  , TurnPlan(..)
  , TurnArtifacts(..)
  , TurnResult(..)
  , TurnEffectRequest(..)
  , TurnEffectResult(..)
  , PrepareStatic(..)
  , PrepareEffectRequest(..)
  , PrepareEffectPlan(..)
  , InterpretationAdmissionInput(..)
  , InterpretationAdmissionDecision(..)
  , AdmittedInterpretation(..)
  , admitInterpretationCandidate
  , PrepareEffectResults(..)
  , RouteStatic(..)
  , RouteEffectRequest(..)
  , RouteEffectPlan(..)
  , RouteEffectResults(..)
  , RenderStatic(..)
  , LocalRecoveryPlan(..)
  , RenderEffectPlan(..)
  , RenderEffectResults(..)
  , FinalizeStatic(..)
  , FinalizePrecommitRequest(..)
  , FinalizePrecommitPlan(..)
  , FinalizePrecommitResults(..)
  , FinalizePrecommitBundle(..)
  , FinalizeCommitPlan(..)
  , FinalizeCommitResults(..)
  , PreparedTurn(..)
  , PlannedTurn(..)
  , RenderedTurn(..)
  , planPrepareEffects
  , resolvePrepareEffects
  , buildTurnInput
  , buildTurnSignals
  , planRouteEffects
  , resolveRouteEffects
  , buildRouteTurnPlan
  , planRenderEffects
  , planRenderEffectsForRuntime
  , resolveRenderEffects
  , buildTurnArtifacts
  , planFinalizePrecommit
  , resolveFinalizePrecommit
  , buildFinalizePrecommit
  , planFinalizeCommit
  , resolveFinalizeCommit
  , buildFinalizeTurnResult
  , resolveFinalizePostCommit
  , finalizeMetrics
  , prepareTurn
  , planTurn
  , renderTurn
  , finalizeTurn
  ) where

import QxFx0.Types
import QxFx0.Render.Authority (AuthoritySurface(..))
import QxFx0.Types.State.SemanticCommitment (FactualClaimPayload(..))
import QxFx0.Core.PipelineIO
  ( PipelineIO
  , PipelineRuntimeMode
  , ShadowPolicy
  , resolveTurnEffect
  , pipelineRuntimeMode
  , pipelineShadowPolicy
  , pipelineLocalRecoveryPolicy
  , pipelineUpdateHistory
  , pipelineParseAuthoritySurface
  )
import QxFx0.Core.TurnPipeline.Effects
  ( TurnEffectRequest(..)
  , TurnEffectResult(..)
  , PrepareStatic(..)
  , PrepareEffectRequest(..)
  , PrepareEffectPlan(..)
  , buildPrepareEffectPlan
  )
import QxFx0.Core.InterpretationAdmission
  ( InterpretationAdmissionInput(..)
  , InterpretationAdmissionDecision(..)
  , AdmittedInterpretation(..)
  , admitInterpretationCandidate
  )
import QxFx0.Core.TurnPipeline.Types
  ( RoutingDecision(..)
  , RenderedTurn(..)
  , TurnArtifacts(..)
  , TurnInput(..)
  , TurnPlan(..)
  , TurnResult(..)
  , TurnSignals(..)
  , turnResultOutput
  )
import QxFx0.Core.Observability (TurnMetrics)
import qualified Data.Map.Strict as Map
import QxFx0.ExceptionPolicy
  ( QxFx0Exception(PersistenceError)
  , mkPersistenceError
  , throwQxFx0
  )
import QxFx0.Types.Persistence (PersistenceStage(StageUnknown))
import QxFx0.Semantic.Lexicon.RuntimeParadigms (emptyRuntimeParadigms)
import Data.Time.Clock (UTCTime)
import QxFx0.Core.TurnPipeline.Prepare (PrepareEffectResults(..))
import qualified QxFx0.Core.TurnPipeline.Prepare as Prepare
import QxFx0.Core.FMAR (FmarMode(..))
import QxFx0.Core.TurnPipeline.Route
  ( RouteStatic(..)
  , RouteEffectRequest(..)
  , RouteEffectPlan(..)
  , RouteEffectResults(..)
  , RenderStatic(..)
  , LocalRecoveryPlan(..)
  , RenderEffectPlan(..)
  , RenderEffectResults(..)
  )
import qualified QxFx0.Core.TurnPipeline.Route as Route
import QxFx0.Core.TurnPipeline.Finalize
  ( FinalizeStatic(..)
  , FinalizePrecommitRequest(..)
  , FinalizePrecommitPlan(..)
  , FinalizePrecommitResults(..)
  , FinalizePrecommitBundle(..)
  , FinalizeCommitPlan(..)
  , FinalizeCommitResults(..)
  , finalizeMetrics
  )
import qualified QxFx0.Core.TurnPipeline.Finalize as Finalize

import Data.Text (Text)
import qualified Data.Text as T
import Data.Sequence (Seq)

data PreparedTurn = PreparedTurn !TurnInput !TurnSignals
data PlannedTurn = PlannedTurn !TurnInput !TurnSignals !TurnPlan

planPrepareEffects :: SystemState -> Text -> UTCTime -> PrepareEffectPlan
planPrepareEffects = buildPrepareEffectPlan

resolvePrepareEffects :: PipelineIO -> PrepareEffectPlan -> IO PrepareEffectResults
resolvePrepareEffects = Prepare.resolvePrepareEffects

buildTurnInput :: SystemState -> Text -> Text -> PrepareEffectPlan -> PrepareEffectResults -> TurnInput
buildTurnInput = Prepare.buildTurnInput

buildTurnSignals :: PrepareEffectResults -> TurnSignals
buildTurnSignals = Prepare.buildTurnSignals

planRouteEffects :: SystemState -> TurnInput -> TurnSignals -> RouteEffectPlan
planRouteEffects = Route.planRouteEffects

resolveRouteEffects :: PipelineIO -> RouteEffectPlan -> IO RouteEffectResults
resolveRouteEffects = Route.resolveRouteEffects

buildRouteTurnPlan :: FmarMode -> ShadowPolicy -> SystemState -> TurnInput -> TurnSignals -> RouteEffectPlan -> RouteEffectResults -> TurnPlan
buildRouteTurnPlan = Route.buildRouteTurnPlan

planRenderEffects :: LocalRecoveryPolicy -> SystemState -> TurnInput -> TurnSignals -> TurnPlan -> RenderEffectPlan
planRenderEffects = Route.planRenderEffects emptyRuntimeParadigms

planRenderEffectsForRuntime :: PipelineRuntimeMode -> LocalRecoveryPolicy -> SystemState -> TurnInput -> TurnSignals -> TurnPlan -> RenderEffectPlan
planRenderEffectsForRuntime = Route.planRenderEffectsForRuntime

resolveRenderEffects :: PipelineIO -> RenderEffectPlan -> IO RenderEffectResults
resolveRenderEffects = Route.resolveRenderEffects

buildTurnArtifacts :: SystemState -> TurnInput -> TurnSignals -> TurnPlan -> RenderEffectPlan -> RenderEffectResults -> TurnArtifacts
buildTurnArtifacts = Route.buildTurnArtifacts

planFinalizePrecommit :: SystemState -> TurnInput -> TurnSignals -> TurnPlan -> TurnArtifacts -> FinalizePrecommitPlan
planFinalizePrecommit = Finalize.planFinalizePrecommit

resolveFinalizePrecommit :: PipelineIO -> FinalizePrecommitPlan -> IO FinalizePrecommitResults
resolveFinalizePrecommit = Finalize.resolveFinalizePrecommit

buildFinalizePrecommit :: (Text -> Seq Text -> Seq Text) -> (AuthoritySurface -> Maybe FactualClaimPayload) -> SystemState -> TurnInput -> TurnSignals -> TurnPlan -> TurnArtifacts -> FinalizePrecommitPlan -> FinalizePrecommitResults -> IO FinalizePrecommitBundle
buildFinalizePrecommit = Finalize.buildFinalizePrecommit

planFinalizeCommit :: Text -> SystemState -> TurnInput -> TurnSignals -> TurnArtifacts -> FinalizePrecommitBundle -> FinalizeCommitPlan
planFinalizeCommit = Finalize.planFinalizeCommit

resolveFinalizeCommit :: PipelineIO -> Int -> FinalizeCommitPlan -> IO FinalizeCommitResults
resolveFinalizeCommit = Finalize.resolveFinalizeCommit

buildFinalizeTurnResult :: RenderedTurn -> FinalizePrecommitBundle -> FinalizeCommitResults -> TurnResult
buildFinalizeTurnResult = Finalize.buildFinalizeTurnResult

resolveFinalizePostCommit :: TurnMetrics -> IO ()
resolveFinalizePostCommit = Finalize.resolveFinalizePostCommit

prepareTurn :: PipelineIO -> SystemState -> Text -> Text -> Text -> IO PreparedTurn
prepareTurn pio ss input sessionId requestId = do
  -- Phase C: resolve time up-front so buildPrepareEffectPlan is deterministic
  currentTime <- resolvePrepareCurrentTime pio
  let prepareEffects = buildPrepareEffectPlan ss input currentTime
  prepareResults <- Prepare.resolvePrepareEffects pio prepareEffects
  let ti' = Prepare.buildTurnInput ss requestId sessionId prepareEffects prepareResults
      ts = Prepare.buildTurnSignals prepareResults
  pure (PreparedTurn ti' ts)

-- | Resolve current time through the runtime effect boundary.
-- Phase C abstraction: uses the same 'TimeSource' that backs
-- 'TurnReqCurrentTime' so tests can override it via env var.
resolvePrepareCurrentTime :: PipelineIO -> IO UTCTime
resolvePrepareCurrentTime pio = do
  result <- resolveTurnEffect pio TurnReqCurrentTime
  case result of
    TurnResCurrentTime t -> pure t
    _ -> throwQxFx0 (mkPersistenceError
          StageUnknown
          (T.pack "resolvePrepareCurrentTime")
          (T.pack "PERSISTENCE_UNEXPECTED_EFFECT")
          Map.empty)

planTurn :: PipelineIO -> SystemState -> PreparedTurn -> IO PlannedTurn
planTurn pio ss (PreparedTurn ti ts) = do
  let routeEffects = Route.planRouteEffects ss ti ts
  routeResults <- Route.resolveRouteEffects pio routeEffects
  fmarMode <- Route.readFmarModeIO pio
  let tp = Route.buildRouteTurnPlan fmarMode (pipelineShadowPolicy pio) ss ti ts routeEffects routeResults
  pure (PlannedTurn ti ts tp)

renderTurn :: PipelineIO -> SystemState -> PlannedTurn -> IO RenderedTurn
renderTurn pio ss (PlannedTurn ti ts tp) = do
  let renderEffects = Route.planRenderEffectsForRuntime (pipelineRuntimeMode pio) (pipelineLocalRecoveryPolicy pio) ss ti ts tp
  renderResults <- Route.resolveRenderEffects pio renderEffects
  let ta = Route.buildTurnArtifacts ss ti ts tp renderEffects renderResults
  pure (RenderedTurn ti ts tp ta)

finalizeTurn :: PipelineIO -> SystemState -> Text -> Int -> Text -> RenderedTurn -> IO TurnResult
finalizeTurn pio ss sessionId expectedRevision _requestId (RenderedTurn ti ts tp ta) = do
  let precommitPlan = Finalize.planFinalizePrecommit ss ti ts tp ta
  precommitResults <- Finalize.resolveFinalizePrecommit pio precommitPlan
  precommitBundle <- Finalize.buildFinalizePrecommit (pipelineUpdateHistory pio) (pipelineParseAuthoritySurface pio) ss ti ts tp ta precommitPlan precommitResults
  let commitPlan = Finalize.planFinalizeCommit sessionId ss ti ts ta precommitBundle
  commitResults <- Finalize.resolveFinalizeCommit pio expectedRevision commitPlan
  let turnResult = Finalize.buildFinalizeTurnResult (RenderedTurn ti ts tp ta) precommitBundle commitResults
  Finalize.resolveFinalizePostCommit (trMetrics turnResult)
  pure turnResult
