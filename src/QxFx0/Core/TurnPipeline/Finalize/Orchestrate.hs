{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-| End-to-end orchestration for finalize precommit/commit phases. -}
module QxFx0.Core.TurnPipeline.Finalize.Orchestrate
  ( finalizeTurnState
  ) where

import Data.Text (Text)

import QxFx0.Core.PipelineIO
  ( PipelineIO
  , pipelineUpdateHistory
  )
import QxFx0.Core.TurnPipeline.Finalize.Commit
  ( buildFinalizeTurnResult
  , planFinalizeCommit
  , resolveFinalizeCommit
  , resolveFinalizePostCommit
  )
import QxFx0.Core.TurnPipeline.Finalize.Precommit
  ( buildFinalizePrecommit
  , planFinalizePrecommit
  , resolveFinalizePrecommit
  )
import QxFx0.Core.TurnPipeline.Types
import QxFx0.Types

finalizeTurnState :: PipelineIO -> SystemState -> Text -> Text -> TurnInput -> TurnSignals -> TurnPlan -> TurnArtifacts -> IO TurnResult
finalizeTurnState pipelineIO systemState sessionId _requestId turnInput turnSignals turnPlan turnArtifacts = do
  let precommitPlan = planFinalizePrecommit systemState turnInput turnSignals turnPlan turnArtifacts
  precommitResults <- resolveFinalizePrecommit pipelineIO precommitPlan
  let precommitBundle =
        buildFinalizePrecommit
          (pipelineUpdateHistory pipelineIO)
          systemState
          turnInput
          turnSignals
          turnPlan
          turnArtifacts
          precommitPlan
          precommitResults
      commitPlan = planFinalizeCommit sessionId systemState turnSignals turnArtifacts precommitBundle
  commitResults <- resolveFinalizeCommit pipelineIO commitPlan
  let turnResult = buildFinalizeTurnResult turnInput turnSignals turnArtifacts precommitBundle commitResults
  resolveFinalizePostCommit (trMetrics turnResult)
  pure turnResult
