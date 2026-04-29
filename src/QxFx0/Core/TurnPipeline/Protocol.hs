{-| Public protocol surface for turn-pipeline phase data and effect contracts. -}
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
  , prepareTurn
  , planTurn
  , renderTurn
  , finalizeTurn
  ) where

import QxFx0.Types
import QxFx0.Core.PipelineIO
  ( PipelineIO
  , PipelineRuntimeMode
  , ShadowPolicy
  , pipelineRuntimeMode
  , pipelineShadowPolicy
  , pipelineLocalRecoveryPolicy
  , pipelineUpdateHistory
  )
import QxFx0.Core.TurnPipeline.Effects
  ( TurnEffectRequest(..)
  , TurnEffectResult(..)
  , PrepareStatic(..)
  , PrepareEffectRequest(..)
  , PrepareEffectPlan(..)
  , buildPrepareEffectPlan
  )
import QxFx0.Core.TurnPipeline.Types
  ( RoutingDecision(..)
  , TurnArtifacts(..)
  , TurnInput(..)
  , TurnPlan(..)
  , TurnResult(..)
  , TurnSignals(..)
  )
import QxFx0.Core.Observability (TurnMetrics)
import QxFx0.Core.TurnPipeline.Prepare (PrepareEffectResults(..))
import qualified QxFx0.Core.TurnPipeline.Prepare as Prepare
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
  )
import qualified QxFx0.Core.TurnPipeline.Finalize as Finalize

import Data.Text (Text)
import Data.Sequence (Seq)

data PreparedTurn = PreparedTurn !TurnInput !TurnSignals
data PlannedTurn = PlannedTurn !TurnInput !TurnSignals !TurnPlan
data RenderedTurn = RenderedTurn !TurnInput !TurnSignals !TurnPlan !TurnArtifacts

planPrepareEffects :: SystemState -> Text -> PrepareEffectPlan
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

buildRouteTurnPlan :: ShadowPolicy -> SystemState -> TurnInput -> TurnSignals -> RouteEffectPlan -> RouteEffectResults -> TurnPlan
buildRouteTurnPlan = Route.buildRouteTurnPlan

planRenderEffects :: LocalRecoveryPolicy -> SystemState -> TurnInput -> TurnSignals -> TurnPlan -> RenderEffectPlan
planRenderEffects = Route.planRenderEffects

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

buildFinalizePrecommit :: (Text -> Seq Text -> Seq Text) -> SystemState -> TurnInput -> TurnSignals -> TurnPlan -> TurnArtifacts -> FinalizePrecommitPlan -> FinalizePrecommitResults -> FinalizePrecommitBundle
buildFinalizePrecommit = Finalize.buildFinalizePrecommit

planFinalizeCommit :: Text -> SystemState -> TurnSignals -> TurnArtifacts -> FinalizePrecommitBundle -> FinalizeCommitPlan
planFinalizeCommit = Finalize.planFinalizeCommit

resolveFinalizeCommit :: PipelineIO -> FinalizeCommitPlan -> IO FinalizeCommitResults
resolveFinalizeCommit = Finalize.resolveFinalizeCommit

buildFinalizeTurnResult :: TurnInput -> TurnSignals -> TurnArtifacts -> FinalizePrecommitBundle -> FinalizeCommitResults -> TurnResult
buildFinalizeTurnResult = Finalize.buildFinalizeTurnResult

resolveFinalizePostCommit :: TurnMetrics -> IO ()
resolveFinalizePostCommit = Finalize.resolveFinalizePostCommit

prepareTurn :: PipelineIO -> SystemState -> Text -> Text -> Text -> IO PreparedTurn
prepareTurn pio ss input sessionId requestId = do
  let prepareEffects = buildPrepareEffectPlan ss input
  prepareResults <- Prepare.resolvePrepareEffects pio prepareEffects
  let ti' = Prepare.buildTurnInput ss requestId sessionId prepareEffects prepareResults
      ts = Prepare.buildTurnSignals prepareResults
  pure (PreparedTurn ti' ts)

planTurn :: PipelineIO -> SystemState -> PreparedTurn -> IO PlannedTurn
planTurn pio ss (PreparedTurn ti ts) = do
  let routeEffects = Route.planRouteEffects ss ti ts
  routeResults <- Route.resolveRouteEffects pio routeEffects
  let tp = Route.buildRouteTurnPlan (pipelineShadowPolicy pio) ss ti ts routeEffects routeResults
  pure (PlannedTurn ti ts tp)

renderTurn :: PipelineIO -> SystemState -> PlannedTurn -> IO RenderedTurn
renderTurn pio ss (PlannedTurn ti ts tp) = do
  let renderEffects = Route.planRenderEffectsForRuntime (pipelineRuntimeMode pio) (pipelineLocalRecoveryPolicy pio) ss ti ts tp
  renderResults <- Route.resolveRenderEffects pio renderEffects
  let ta = Route.buildTurnArtifacts ss ti ts tp renderEffects renderResults
  pure (RenderedTurn ti ts tp ta)

finalizeTurn :: PipelineIO -> SystemState -> Text -> Text -> RenderedTurn -> IO TurnResult
finalizeTurn pio ss sessionId _requestId (RenderedTurn ti ts tp ta) = do
  let precommitPlan = Finalize.planFinalizePrecommit ss ti ts tp ta
  precommitResults <- Finalize.resolveFinalizePrecommit pio precommitPlan
  let precommitBundle = Finalize.buildFinalizePrecommit (pipelineUpdateHistory pio) ss ti ts tp ta precommitPlan precommitResults
      commitPlan = Finalize.planFinalizeCommit sessionId ss ts ta precommitBundle
  commitResults <- Finalize.resolveFinalizeCommit pio commitPlan
  let turnResult = Finalize.buildFinalizeTurnResult ti ts ta precommitBundle commitResults
  Finalize.resolveFinalizePostCommit (trMetrics turnResult)
  pure turnResult
