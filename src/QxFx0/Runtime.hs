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
  , stateSummaryLines
  , resolveDbPath
  , resolveSessionId
  , resolveRuntimeMode
  , renderRuntimeOutputMode
  , runtimeToDialogueMode
  , dialogueToRuntimeMode
  , StateOrigin(..)
  , StateVersion(..)
  , ensureSchemaMigrations
  , RuntimeContext
  , withRuntimeDb
  , checkHealth
  , probeRuntimeReadiness
  , SystemHealth(..)
  , HealthStatus(..)
  , healthStatusText
  , AgdaWitnessReport(..)
  , readAgdaWitnessReport
  , writeAgdaWitness
  , runTurn
  , runTurnInSession
  , loop
  ) where

import QxFx0.Bridge.SQLite (ensureSchemaMigrations)
import QxFx0.Types.Persistence (StateVersion(..))
import QxFx0.Bridge.AgdaWitness (AgdaWitnessReport(..), readAgdaWitnessReport, writeAgdaWitness)
import QxFx0.Runtime.Wiring
  ( RuntimeContext
  , withRuntimeDb
  )
import QxFx0.Runtime.Paths
  ( resolveDbPath
  , resolveSessionId
  )
import QxFx0.Runtime.Health
  ( HealthStatus(..)
  , healthStatusText
  , SystemHealth(..)
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
  , stateSummaryLines
  )
