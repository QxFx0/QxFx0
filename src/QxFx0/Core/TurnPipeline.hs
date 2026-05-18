{-| High-level turn-pipeline facade over prepare/plan/render/finalize phases. -}
module QxFx0.Core.TurnPipeline
  ( RoutingDecision(..)
  , TurnInput(..)
  , TurnSignals(..)
  , TurnPlan
  , TurnArtifacts
  , TurnResult(..)
  , PreparedTurn
  , PlannedTurn
  , RenderedTurn
  , prepareTurn
  , planTurn
  , renderTurn
  , finalizeTurn
  , PrepareStatic(..)
  , PrepareEffectPlan(..)
  , PrepareEffectRequest(..)
  , buildPrepareEffectPlan
  ) where

import QxFx0.Core.TurnPipeline.Protocol
  ( RoutingDecision(..)
  , TurnInput(..)
  , TurnSignals(..)
  , TurnPlan
  , TurnArtifacts
  , TurnResult(..)
  , PreparedTurn
  , PlannedTurn
  , RenderedTurn
  , prepareTurn
  , planTurn
  , renderTurn
  , finalizeTurn
  )
import QxFx0.Core.TurnPipeline.Effects
  ( PrepareStatic(..)
  , PrepareEffectPlan(..)
  , PrepareEffectRequest(..)
  , buildPrepareEffectPlan
  )
