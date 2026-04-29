{-# LANGUAGE DerivingStrategies, OverloadedStrings, BangPatterns, StrictData #-}
module QxFx0.Runtime
  ( RuntimeOutputMode(..)
  , RuntimeMode(..)
  , Session(..)
  , bootstrapSession
  , withBootstrappedSession
  , closeSession
  , checkSessionReadiness
  , printHelp
  , printStateSummary
  , resolveDbPath
  , resolveSessionId
  , resolveRuntimeMode
  , renderRuntimeOutputMode
  , runtimeToDialogueMode
  , dialogueToRuntimeMode
  , StateOrigin(..)
  , ensureSchemaMigrations
  , RuntimeContext
  , withRuntimeDb
  , checkHealth
  , probeRuntimeReadiness
  , SystemHealth(..)
  , AgdaWitnessReport(..)
  , readAgdaWitnessReport
  , writeAgdaWitness
  , runTurn
  , runTurnInSession
  , loop
  ) where

import QxFx0.Bridge.SQLite (ensureSchemaMigrations)
import QxFx0.Bridge.AgdaWitness (AgdaWitnessReport(..), readAgdaWitnessReport, writeAgdaWitness)
import QxFx0.Runtime.Context
  ( RuntimeContext
  , withRuntimeDb
  )
import QxFx0.Runtime.Paths
  ( resolveDbPath
  , resolveSessionId
  )
import QxFx0.Runtime.Health
  ( SystemHealth(..)
  , checkHealth
  , probeRuntimeReadiness
  )
import QxFx0.Runtime.Engine
  ( runTurn
  , runTurnInSession
  , loop
  )
import QxFx0.Runtime.Session
  ( RuntimeOutputMode(..)
  , RuntimeMode(..)
  , Session(..)
  , resolveRuntimeMode
  , bootstrapSession
  , withBootstrappedSession
  , closeSession
  , checkSessionReadiness
  , renderRuntimeOutputMode
  , runtimeToDialogueMode
  , dialogueToRuntimeMode
  , StateOrigin(..)
  , printHelp
  , printStateSummary
  )
