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
import QxFx0.Runtime.Wiring (RuntimeContext, withRuntimeSession, toPipelineIO)
import QxFx0.Types.Persistence (StateVersion(..), corruptStateRepairVersion)
import QxFx0.Runtime.Session
  ( Session(..)
  , RuntimeOutputMode(..)
  , StateOrigin(..)
  , checkSessionReadiness
  , printHelp
  , printStateSummary
  , runtimeToDialogueMode
  )
import QxFx0.Runtime.Session.Autonomous
  ( beginSemanticNetworkTurn
  , commitSemanticNetworkTurn
  , enqueueAutonomousLearningForTopic
  )
import QxFx0.ExceptionPolicy (QxFx0Exception(..), mkRuntimeInitError, throwQxFx0)
import qualified QxFx0.Observability.Logging as Log
import qualified QxFx0.Observability.Metrics as Metrics

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as T
import Control.Exception (AsyncException, IOException, SomeException, fromException, throwIO, try)
import Control.Monad (when)
import System.IO (hPutStrLn, stderr, hIsEOF, stdin)
import System.Exit (exitSuccess)
import Data.Time.Clock (getCurrentTime, diffUTCTime)
import Data.IORef (newIORef)

runTurn :: RuntimeContext -> SystemState -> StateVersion -> Text -> Text -> IO (SystemState, Text)
runTurn ctx ss expectedVersion input sessionId = do
  Log.logDebug "Starting turn execution"
    (Log.addContext "session_id" sessionId $
     Log.addContext "input_length" (T.pack $ show $ T.length input) Log.emptyContext)
  runTurnWithVersion ctx ss input sessionId expectedVersion

runTurnWithVersion :: RuntimeContext -> SystemState -> Text -> Text -> StateVersion -> IO (SystemState, Text)
runTurnWithVersion ctx ss input sessionId expectedVersion
  | T.length input > maxInputLength = do
      Log.logWarn "Input exceeds maximum length"
        (Log.addContext "input_length" (T.pack $ show $ T.length input) $
         Log.addContext "max_length" (T.pack $ show maxInputLength) Log.emptyContext)
      return (ss, "\1054\1096\1080\1073\1082\1072: \1090\1077\1082\1089\1090 \1089\1083\1080\1096\1082\1086\1084 \1076\1083\1080\1085\1085\1099\1081.")
  | otherwise = withRuntimeSession ctx sessionId $ do
      startTime <- getCurrentTime
      turnResult <- try (runTurnBody ctx ss input sessionId expectedVersion) :: IO (Either QxFx0Exception (SystemState, Text))
      endTime <- getCurrentTime
      let duration = diffUTCTime endTime startTime
      
      -- Create metrics registry for this turn
      metricsRegistry <- newIORef []
      
      case turnResult of
        Left (EssenceRupture detail) -> do
          Log.logError "Turn blocked by essence rupture"
            (Log.addContext "detail" detail Log.emptyContext)
          Metrics.recordCounter metricsRegistry "turn.error" 1.0
            (M.singleton "error_type" "essence_rupture")
          Metrics.recordTiming metricsRegistry "turn.duration" duration M.empty
          pure (ss, "Turn blocked: essence rupture [" <> detail <> "]")
        Left (EmbeddingError detail) -> do
          Log.logError "Turn blocked by embedding error"
            (Log.addContext "detail" detail Log.emptyContext)
          Metrics.recordCounter metricsRegistry "turn.error" 1.0
            (M.singleton "error_type" "embedding_error")
          Metrics.recordTiming metricsRegistry "turn.duration" duration M.empty
          pure (ss, "Turn blocked: embedding backend [" <> detail <> "]")
        Left err -> do
          Log.logException err
            (Log.addContext "session_id" sessionId Log.emptyContext)
          Metrics.recordCounter metricsRegistry "turn.error" 1.0
            (M.singleton "error_type" "other")
          throwQxFx0 err
        Right result -> do
          Log.logInfo "Turn completed successfully"
            (Log.addContext "session_id" sessionId $
             Log.addContext "duration_ms" (T.pack $ show $ round (realToFrac duration * 1000 :: Double)) Log.emptyContext)
          Metrics.recordCounter metricsRegistry "turn.success" 1.0 M.empty
          Metrics.recordTiming metricsRegistry "turn.duration" duration M.empty
          pure result

runTurnBody :: RuntimeContext -> SystemState -> Text -> Text -> StateVersion -> IO (SystemState, Text)
runTurnBody ctx ss input sessionId expectedVersion = do
  let pio = toPipelineIO ctx
  
  Log.logDebug "Turn pipeline: resolving request ID" Log.emptyContext
  reqId <- resolveRequestId pio
  
  Log.logDebug "Turn pipeline: preparing turn" Log.emptyContext
  prepareStart <- getCurrentTime
  prepared <- prepareTurn pio ss input sessionId reqId
  prepareEnd <- getCurrentTime
  
  Log.logDebug "Turn pipeline: planning turn" Log.emptyContext
  planStart <- getCurrentTime
  planned <- planTurn pio ss prepared
  planEnd <- getCurrentTime
  
  Log.logDebug "Turn pipeline: rendering turn" Log.emptyContext
  renderStart <- getCurrentTime
  rendered <- renderTurn pio ss planned
  renderEnd <- getCurrentTime
  
  Log.logDebug "Turn pipeline: finalizing turn" Log.emptyContext
  finalizeStart <- getCurrentTime
  tr <- finalizeTurn pio ss sessionId expectedVersion reqId rendered
  finalizeEnd <- getCurrentTime
  
  -- Log phase timings
  let prepareDuration = diffUTCTime prepareEnd prepareStart
      planDuration = diffUTCTime planEnd planStart
      renderDuration = diffUTCTime renderEnd renderStart
      finalizeDuration = diffUTCTime finalizeEnd finalizeStart
  
  Log.logDebug "Turn pipeline phases completed"
    (Log.addContext "session_id" sessionId $
     Log.addContext "total_ms" (T.pack $ show $ round (realToFrac (diffUTCTime finalizeEnd prepareStart) * 1000 :: Double)) $
     Log.addContext "prepare_ms" (T.pack $ show $ round (realToFrac prepareDuration * 1000 :: Double)) $
     Log.addContext "plan_ms" (T.pack $ show $ round (realToFrac planDuration * 1000 :: Double)) $
     Log.addContext "render_ms" (T.pack $ show $ round (realToFrac renderDuration * 1000 :: Double)) $
     Log.addContext "finalize_ms" (T.pack $ show $ round (realToFrac finalizeDuration * 1000 :: Double)) Log.emptyContext)
  
  pure (trNextSs tr, trOutput tr)

resolveRequestId :: PipelineIO -> IO Text
resolveRequestId pio = do
  requestIdResult <- resolveTurnEffect pio TurnReqRequestId
  case requestIdResult of
    TurnResRequestId rid -> pure rid
    _ -> throwQxFx0 $ mkRuntimeInitError "Engine" "resolve_request_id" "UNEXPECTED_EFFECT_RESULT"
      (M.singleton "expected" "TurnResRequestId")

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
          expectedVersion = case sessStateOrigin s of
            RecoveredCorruptOrigin -> corruptStateRepairVersion (sessStateRevision s)
            _ -> StateVersion (sessStateRevision s) (ssTurnCount ss)
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
              continueTurn s readiness ss runtime sid expectedVersion
        else continueTurn s readiness ss runtime sid expectedVersion

    continueTurn s readiness ss runtime sid expectedVersion = do
      (networkTurn, turnSs) <- beginSemanticNetworkTurn (sessAutonomousHandles s) ss
      turnResult <- try (runTurnWithVersion runtime turnSs text sid expectedVersion) :: IO (Either QxFx0Exception (SystemState, Text))
      case turnResult of
        Left (AgdaGateError detail) ->
          pure
            ( s { sessReadinessMode = readiness }
            , "Turn blocked: strict runtime requires Agda verification [" <> detail <> "]"
            )
        Left (EmbeddingError detail) ->
          pure
            ( s { sessReadinessMode = readiness }
            , "Turn blocked: embedding backend [" <> detail <> "]"
            )
        Left (EssenceRupture detail) ->
          pure
            ( s { sessReadinessMode = readiness }
            , "Turn blocked: essence rupture [" <> detail <> "]"
            )
        Left err ->
          throwQxFx0 err
        Right (nextSs, response) -> do
          -- Finalize has already durably committed this turn. Autonomous
          -- follow-up is post-commit work, so a failure must not turn a
          -- committed response into an apparently safe-to-retry failure.
          followUp <- try (do
              hPutStrLn stderr "[engine] Applying pending autonomous updates..."
              nextSsWithUpdates <- commitSemanticNetworkTurn
                (sessAutonomousHandles s) networkTurn nextSs
              hPutStrLn stderr "[engine] Pending updates applied."
              learningEnqueued <- enqueueAutonomousLearningForTopic
                (sessAutonomousHandles s)
                (ssLastTopic nextSsWithUpdates)
                nextSsWithUpdates
              when learningEnqueued $
                hPutStrLn stderr $ "[engine] Autonomous learning queued for topic '"
                  <> T.unpack (ssLastTopic nextSsWithUpdates) <> "'."
              pure nextSsWithUpdates) :: IO (Either SomeException SystemState)
          nextSsWithUpdates <- case followUp of
            Right updated -> pure updated
            Left err
              | Just async <- (fromException err :: Maybe AsyncException) -> throwIO async
              | otherwise -> do
                  hPutStrLn stderr $ "[engine] Post-commit autonomous follow-up failed; turn remains committed: " <> show err
                  pure nextSs
          let !session' = s
                { sessSystemState = nextSsWithUpdates
                , sessStateRevision = stateRevision expectedVersion + 1
                , sessStateOrigin = case sessStateOrigin s of
                    RecoveredCorruptOrigin -> RestoredOrigin
                    origin -> origin
                , sessReadinessMode = readiness
                }
          pure (session', response)

loop :: Session -> IO ()
loop session = do
  T.putStr $ "\n[" <> promptMode (sessOutputMode session) <> "] [QxFx0] > "
  eof <- hIsEOF stdin
  if eof
    then pure ()
    else do
      inputResult <- try T.getLine :: IO (Either IOException Text)
      case inputResult of
        Left e -> hPutStrLn stderr ("[engine] stdin read error: " <> show e)
        Right input ->
          let boundedInput = T.take maxInputLength input
          in case T.strip boundedInput of
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
