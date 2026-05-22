{-# LANGUAGE OverloadedStrings #-}

{-| Human-facing session help and compact state summaries. -}
module QxFx0.Runtime.Session.UI
  ( printHelp
  , printStateSummary
  ) where

import Control.Exception (SomeException, finally, try)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as K
import qualified Data.Aeson.KeyMap as KM
import qualified Data.ByteString.Lazy as BL
import qualified Data.Vector as V
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Text.IO as T
import qualified QxFx0.Bridge.NativeSQLite as NSQL
import QxFx0.Core.MeaningGraph (graphStats)
import QxFx0.Runtime.Session.Types
  ( Session(..)
  , renderRuntimeOutputMode
  )
import QxFx0.Runtime.Wiring (withRuntimeDb)
import QxFx0.Self.Essence (Essence(..), EssenceCommitment(..), renderEssenceMode)
import QxFx0.Types.Domain (atCurrentLoad)
import QxFx0.Types.Observability (KernelPulse(..))
import QxFx0.Types.State
  ( EgoState(..)
  , ssEgo
  , ssEssence
  , ssKernelPulse
  , ssLastFamily
  , ssLastTopic
  , ssMeaningGraph
  , ssTrace
  , ssTurnCount
  )

data ReplayTraceSummary = ReplayTraceSummary
  { rtsRecoveryCause :: !(Maybe Text)
  , rtsRecoveryStrategy :: !(Maybe Text)
  , rtsRecoveryEvidence :: ![Text]
  , rtsShadowSeverity :: !(Maybe Text)
  }

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
printStateSummary session = stateSummaryLines session >>= mapM_ T.putStrLn

stateSummaryLines :: Session -> IO [Text]
stateSummaryLines session = do
  latestTrace <- loadLatestReplayTrace session
  let ss = sessSystemState session
      renderValue :: Show a => a -> Text
      renderValue = T.pack . show
      essenceModeTag =
        case ssEssence ss of
          EssenceUncommitted _ -> "uncommitted"
          EssenceCommitted _ c -> "committed:" <> renderEssenceMode (ecMode c)
      recoveryCauseTag = maybe "n/a" id (rtsRecoveryCause =<< latestTrace)
      recoveryStrategyTag = maybe "n/a" id (rtsRecoveryStrategy =<< latestTrace)
      shadowSeverityTag =
        case rtsShadowSeverity =<< latestTrace of
          Just raw -> raw
          Nothing -> "n/a"
      gradientTag = maybe "n/a" renderGradientTag (latestTrace >>= (parseGradientFromEvidence . rtsRecoveryEvidence))
  pure
    [ "STATE_BEGIN"
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
    , "essence_mode: " <> essenceModeTag
    , "recovery_cause: " <> recoveryCauseTag
    , "shadow_severity: " <> shadowSeverityTag
    , "gradient(m,c,t): " <> gradientTag
    , "strategy: " <> recoveryStrategyTag
    , "STATE_END"
    ]

loadLatestReplayTrace :: Session -> IO (Maybe ReplayTraceSummary)
loadLatestReplayTrace session = do
  result <- try $ withRuntimeDb (sessRuntime session) $ \db -> do
    let sql = "SELECT replay_trace_json FROM turn_quality WHERE session_id = ? ORDER BY turn DESC LIMIT 1"
    mStmt <- NSQL.prepare db sql
    case mStmt of
      Left _ -> pure Nothing
      Right stmt -> do
        result' <- (
          do
            _ <- NSQL.bindText stmt 1 (sessSessionId session)
            hasRow <- NSQL.stepRow stmt
            if not hasRow
              then pure Nothing
              else do
                payload <- NSQL.columnText stmt 0
                pure (decodeReplayTraceSummary payload)
          ) `finally` finalizeQuietly stmt
        pure result'
  pure (either (const Nothing) id (result :: Either SomeException (Maybe ReplayTraceSummary)))
  where
    decodeReplayTraceSummary :: Text -> Maybe ReplayTraceSummary
    decodeReplayTraceSummary payload =
      case Aeson.decode (BL.fromStrict (TE.encodeUtf8 payload)) :: Maybe Aeson.Value of
        Just (Aeson.Object obj) ->
          let recoveryCause = decodeScalarField "trcRecoveryCause" obj
              recoveryStrategy = decodeScalarField "trcRecoveryStrategy" obj
              shadowSeverity = decodeScalarField "trcShadowDivergenceSeverity" obj
              evidence = decodeStringArrayField "trcRecoveryEvidence" obj
           in Just ReplayTraceSummary
                { rtsRecoveryCause = recoveryCause
                , rtsRecoveryStrategy = recoveryStrategy
                , rtsRecoveryEvidence = evidence
                , rtsShadowSeverity = shadowSeverity
                }
        _ -> Nothing

    decodeScalarField :: Text -> Aeson.Object -> Maybe Text
    decodeScalarField key obj =
      case KM.lookup (K.fromText key) obj of
        Just (Aeson.String t) -> Just t
        Just (Aeson.Number n) -> Just (T.pack (show n))
        Just (Aeson.Bool True) -> Just "true"
        Just (Aeson.Bool False) -> Just "false"
        _ -> Nothing

    decodeStringArrayField :: Text -> Aeson.Object -> [Text]
    decodeStringArrayField key obj =
      case KM.lookup (K.fromText key) obj of
        Just (Aeson.Array arr) ->
          [ t | Aeson.String t <- V.toList arr ]
        _ -> []

finalizeQuietly :: NSQL.Statement -> IO ()
finalizeQuietly stmt = do
  _ <- try (NSQL.finalize stmt) :: IO (Either SomeException ())
  pure ()

parseGradientFromEvidence :: [Text] -> Maybe (Double, Double, Double)
parseGradientFromEvidence evidence =
  let findMarker prefix =
        case [ rest | entry <- evidence, Just rest <- [T.stripPrefix prefix entry] ] of
          rest : _ -> case reads (T.unpack (T.takeWhile (/= ' ') rest)) of
            [(n, _)] -> Just n
            _ -> Nothing
          [] -> Nothing
      m = findMarker "conatus_gradient_m="
      c = findMarker "conatus_gradient_c="
      t = findMarker "conatus_gradient_t="
  in case (m, c, t) of
       (Just m', Just c', Just t') -> Just (m', c', t')
       _ -> Nothing

renderGradientTag :: (Double, Double, Double) -> Text
renderGradientTag (m, c, t) =
  T.concat [ "m=", T.pack (show m), ",c=", T.pack (show c), ",t=", T.pack (show t) ]
