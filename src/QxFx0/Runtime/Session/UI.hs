{-# LANGUAGE OverloadedStrings #-}

{-| Human-facing session help and compact state summaries. -}
module QxFx0.Runtime.Session.UI
  ( printHelp
  , printStateSummary
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import QxFx0.Core.MeaningGraph (graphStats)
import QxFx0.Runtime.Session.Types
  ( Session(..)
  , renderRuntimeOutputMode
  )
import QxFx0.Types.Domain (atCurrentLoad)
import QxFx0.Types.Observability (KernelPulse(..))
import QxFx0.Types.State
  ( EgoState(..)
  , ssEgo
  , ssKernelPulse
  , ssLastFamily
  , ssLastTopic
  , ssMeaningGraph
  , ssTrace
  , ssTurnCount
  )

printHelp :: IO ()
printHelp = do
  T.putStrLn "Interactive commands:"
  T.putStrLn "  :help      show commands"
  T.putStrLn "  :state     show compact runtime state"
  T.putStrLn "  :dialogue  natural dialogue output"
  T.putStrLn "  :semantic  semantic introspection output"
  T.putStrLn "  :quit      save state and exit"
  T.putStrLn ""
  T.putStrLn "Environment:"
  T.putStrLn "  QXFX0_SESSION_ID    session identifier"
  T.putStrLn "  QXFX0_DB            database path"
  T.putStrLn "  QXFX0_ROOT          project root"
  T.putStrLn "  QXFX0_RUNTIME_MODE  strict(default)|degraded(test harness only)"
  T.putStrLn "  QXFX0_EMBEDDING_BACKEND  local-deterministic|remote-http"
  T.putStrLn "  QXFX0_SESSION_LOCK  enable session locking"

printStateSummary :: Session -> IO ()
printStateSummary session = mapM_ T.putStrLn (stateSummaryLines session)

stateSummaryLines :: Session -> [Text]
stateSummaryLines session =
  let ss = sessSystemState session
      renderValue :: Show a => a -> Text
      renderValue = T.pack . show
   in [ "STATE_BEGIN"
      , "session_id: " <> sessSessionId session
      , "turns: " <> renderValue (ssTurnCount ss)
      , "output_mode: " <> renderRuntimeOutputMode (sessOutputMode session)
      , "atom_trace_ema: " <> renderValue (atCurrentLoad (ssTrace ss))
      , "last_family: " <> renderValue (ssLastFamily ss)
      , "last_topic: " <> ssLastTopic ss
      , "ego_agency: " <> renderValue (egoAgency (ssEgo ss))
      , "ego_tension: " <> renderValue (egoTension (ssEgo ss))
      , "meaning_graph: " <> graphStats (ssMeaningGraph ss)
      , "kernel_pulse: " <> renderValue (kpActive (ssKernelPulse ss))
      , "STATE_END"
      ]
