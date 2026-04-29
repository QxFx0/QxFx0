{-# LANGUAGE OverloadedStrings, DeriveGeneric, BangPatterns, StrictData, LambdaCase, ScopedTypeVariables #-}
module QxFx0.Runtime.Engine
  ( runTurn
  , runTurnInSession
  , loop
  ) where

import QxFx0.Types
import QxFx0.Core.TurnPipeline
import QxFx0.Resources (ReadinessMode(..))
import QxFx0.Core.PipelineIO (PipelineIO, resolveTurnEffect)
import QxFx0.Core.TurnPipeline.Effects (TurnEffectRequest(..), TurnEffectResult(..))
import QxFx0.Runtime.Health (checkHealth)
import QxFx0.Runtime.Gate
  ( evaluateBootstrapReadiness
  , evaluateStrictHealth
  , renderTurnGateFailure
  )
import QxFx0.Runtime.Mode (resolveRuntimeMode, isStrictRuntimeMode)
import QxFx0.Types.Thresholds (maxInputLength)
import QxFx0.Runtime.Context (RuntimeContext, withRuntimeSession, toPipelineIO)
import QxFx0.Runtime.Session
  ( Session(..)
  , RuntimeOutputMode(..)
  , checkSessionReadiness
  , printHelp
  , printStateSummary
  , runtimeToDialogueMode
  )
import QxFx0.ExceptionPolicy (QxFx0Exception(..), throwQxFx0)

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import Control.Exception (try)
import System.IO (hPutStrLn, stderr)
import System.Exit (exitSuccess)

runTurn :: RuntimeContext -> SystemState -> Text -> Text -> IO (SystemState, Text)
runTurn ctx ss input sessionId
  | T.length input > maxInputLength = return (ss, "\1054\1096\1080\1073\1082\1072: \1090\1077\1082\1089\1090 \1089\1083\1080\1096\1082\1086\1084 \1076\1083\1080\1085\1085\1099\1081.")
  | otherwise = withRuntimeSession ctx sessionId (runTurnBody ctx ss input sessionId)

runTurnBody :: RuntimeContext -> SystemState -> Text -> Text -> IO (SystemState, Text)
runTurnBody ctx ss input sessionId = do
  let pio = toPipelineIO ctx
  reqId <- resolveRequestId pio
  prepared <- prepareTurn pio ss input sessionId reqId
  planned <- planTurn pio ss prepared
  rendered <- renderTurn pio ss planned
  tr <- finalizeTurn pio ss sessionId reqId rendered
  pure (trNextSs tr, trOutput tr)

resolveRequestId :: PipelineIO -> IO Text
resolveRequestId pio = do
  requestIdResult <- resolveTurnEffect pio TurnReqRequestId
  case requestIdResult of
    TurnResRequestId rid -> pure rid
    _ -> throwQxFx0 (RuntimeInitError "request id effect returned unexpected result")

runTurnInSession :: Session -> Text -> IO (Session, Text)
runTurnInSession session text = do
  readiness <- checkSessionReadiness session
  runtimeMode <- resolveRuntimeMode
  let strictMode = isStrictRuntimeMode runtimeMode
  case evaluateBootstrapReadiness runtimeMode readiness of
    Left failure ->
      pure
        ( session { sessReadinessMode = readiness }
        , renderTurnGateFailure failure
        )
    Right _ ->
      case readiness of
        Degraded failed -> do
          hPutStrLn stderr $ "[degraded] optional components unavailable: " ++ show failed
          continueWithHealthCheck runtimeMode strictMode session readiness
        _ ->
          continueWithHealthCheck runtimeMode strictMode session readiness
  where
    continueWithHealthCheck runtimeMode strictMode s readiness = do
      let ss = sessSystemState s
          runtime = sessRuntime s
          sid = sessSessionId s
      if strictMode
        then do
          health <- checkHealth runtime
          case evaluateStrictHealth runtimeMode health of
            Left failure ->
              pure
                ( s { sessReadinessMode = readiness }
                , renderTurnGateFailure failure
                )
            Right _ ->
              continueTurn s readiness ss runtime sid
        else continueTurn s readiness ss runtime sid

    continueTurn s readiness ss runtime sid = do
      turnResult <- try (runTurn runtime ss text sid) :: IO (Either QxFx0Exception (SystemState, Text))
      case turnResult of
        Left (AgdaGateError detail) ->
          pure
            ( s { sessReadinessMode = readiness }
            , "Turn blocked: strict runtime requires Agda verification [" <> detail <> "]"
            )
        Left err ->
          throwQxFx0 err
        Right (nextSs, response) -> do
          let !session' = s { sessSystemState = nextSs, sessReadinessMode = readiness }
          pure (session', response)

loop :: Session -> IO ()
loop session = do
  T.putStr $ "\n[" <> promptMode (sessOutputMode session) <> "] [QxFx0] > "
  input <- T.getLine
  case T.strip input of
    ":quit" -> do
      T.putStrLn "State saved. Bye."
      exitSuccess
    ":help" -> printHelp >> loop session
    ":dialogue" ->
      T.putStrLn "Output mode: DIALOGUE" >> loop (setOutputMode DialogueMode session)
    ":semantic" ->
      T.putStrLn "Output mode: SEMANTIC" >> loop (setOutputMode SemanticIntrospectionMode session)
    ":state" -> printStateSummary session >> loop session
    text
      | not (T.null text) -> do
          (session', safeResponse) <- runTurnInSession session text
          T.putStrLn safeResponse
          loop session'
    _ -> loop session
  where
    promptMode DialogueMode = "DIALOGUE"
    promptMode SemanticIntrospectionMode = "SEMANTIC"
    setOutputMode mode s = s
      { sessOutputMode = mode
      , sessSystemState = (sessSystemState s) { ssOutputMode = runtimeToDialogueMode mode }
      }
