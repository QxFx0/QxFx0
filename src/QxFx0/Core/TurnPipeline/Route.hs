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
  , routeTurnPlan
  , detectAnomaly
  , planRenderEffects
  , planRenderEffectsForRuntime
  , resolveRenderEffects
  , buildTurnArtifacts
  , readFmarModeIO
  ) where

import QxFx0.Core.TurnPipeline.Route.Build
  ( buildRouteTurnPlan
  , routeTurnPlan
  , readFmarModeIO
  )
import QxFx0.Core.TurnPipeline.Route.Anomaly
  ( detectAnomaly
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
