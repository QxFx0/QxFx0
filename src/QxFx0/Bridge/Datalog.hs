{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-| Facade for Souffle/Datalog shadow execution, verdict comparison, and executable resolution. -}
module QxFx0.Bridge.Datalog
  ( compileAndRunDatalog
  , compileAndRunDatalogWithExecutable
  , ShadowDivergence(..)
  , ShadowResult(..)
  , compareShadowOutput
  , computeShadowLegitimacyPenalty
  , runDatalogShadow
  , runDatalogShadowWithExecutable
  , resolveSouffleExecutable
  ) where

import QxFx0.Bridge.Datalog.Compare (compareShadowOutput)
import QxFx0.Bridge.Datalog.Runtime
  ( compileAndRunDatalog
  , compileAndRunDatalogWithExecutable
  , resolveSouffleExecutable
  , runDatalogShadow
  , runDatalogShadowWithExecutable
  )
import QxFx0.Bridge.Datalog.Types (ShadowResult(..))
import QxFx0.Types.ShadowDivergence
  ( ShadowDivergence(..)
  , computeShadowLegitimacyPenalty
  )
