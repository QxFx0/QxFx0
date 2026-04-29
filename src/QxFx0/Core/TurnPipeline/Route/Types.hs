{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE StrictData #-}

{-| Route-phase public types shared by planning, effect resolution, and build steps. -}
module QxFx0.Core.TurnPipeline.Route.Types
  ( RouteStatic(..)
  , RouteEffectRequest(..)
  , RouteEffectPlan(..)
  , RouteEffectResults(..)
  ) where

import QxFx0.Core.PipelineIO (ShadowResult)
import QxFx0.Core.TurnPipeline.Types (RoutingDecision)
import QxFx0.Types
  ( AgdaVerificationStatus
  , AtomTag
  , CanonicalMoveFamily
  , IllocutionaryForce
  )

data RouteStatic = RouteStatic
  { rsRoutingDecision :: !RoutingDecision
  }

data RouteEffectRequest
  = RouteReqShadow !CanonicalMoveFamily !IllocutionaryForce ![AtomTag]
  | RouteReqAgdaVerify
  deriving stock (Eq, Show)

data RouteEffectPlan = RouteEffectPlan
  { repStatic :: !RouteStatic
  , repShadowRequest :: !RouteEffectRequest
  , repAgdaRequest :: !RouteEffectRequest
  }

data RouteEffectResults = RouteEffectResults
  { rerShadowResult :: !ShadowResult
  , rerAgdaStatus :: !AgdaVerificationStatus
  }
  deriving stock (Eq, Show)
