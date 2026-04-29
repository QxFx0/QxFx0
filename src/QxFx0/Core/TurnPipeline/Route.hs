{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-| Facade for route planning, route effects, and render-phase handoff. -}
module QxFx0.Core.TurnPipeline.Route
  ( RouteStatic(..)
  , RouteEffectRequest(..)
  , RouteEffectPlan(..)
  , RouteEffectResults(..)
  , RenderStatic(..)
  , LocalRecoveryPlan(..)
  , RenderEffectPlan(..)
  , RenderEffectResults(..)
  , planRouteEffects
  , resolveRouteEffects
  , buildRouteTurnPlan
  , planRenderEffects
  , planRenderEffectsForRuntime
  , resolveRenderEffects
  , buildTurnArtifacts
  , routeTurnPlan
  , renderTurnOutput
  ) where

import QxFx0.Core.TurnPipeline.Route.Build
  ( buildRouteTurnPlan
  , renderTurnOutput
  , routeTurnPlan
  )
import QxFx0.Core.TurnPipeline.Route.Effects
  ( planRouteEffects
  , resolveRouteEffects
  )
import QxFx0.Core.TurnPipeline.Route.Render
  ( RenderStatic(..)
  , LocalRecoveryPlan(..)
  , RenderEffectPlan(..)
  , RenderEffectResults(..)
  , buildTurnArtifacts
  , planRenderEffects
  , planRenderEffectsForRuntime
  , resolveRenderEffects
  )
import QxFx0.Core.TurnPipeline.Route.Types
  ( RouteStatic(..)
  , RouteEffectRequest(..)
  , RouteEffectPlan(..)
  , RouteEffectResults(..)
  )
