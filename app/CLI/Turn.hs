{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module CLI.Turn
  ( TurnJsonResponse(..)
  , runTurnJson
  , runTurnJsonInSession
  , attachRuntimeDiagnostics
  ) where

import CLI.Protocol (RuntimeOutputMode(..))
import Control.Exception (throwIO)
import Data.Aeson (ToJSON(..), object, (.=), Value, Key)
import Data.Text (Text)
import qualified Data.Text as T
import QxFx0.Render.Text (textShow)
import GHC.Generics (Generic)
import System.Environment (lookupEnv)
import System.IO (hPutStrLn, stderr)

import qualified QxFx0.Runtime as Runtime
import QxFx0.Core.IdentityGuard (IdentityGuardReport(..))
import QxFx0.ExceptionPolicy (QxFx0Exception(..), tryQxFx0)
import QxFx0.Types.Decision (IdentitySignalSnapshot(..), SemanticAnchor(..), TurnDecision(..), renderStyleText, DialogueOutputMode(..), dominantChannelText)
import QxFx0.Types.State

data TurnJsonResponse = TurnJsonResponse
  { tjrStatus     :: Text
  , tjrSessionId  :: Text
  , tjrInput      :: Text
  , tjrOutput     :: Text
  , tjrFamily     :: Text
  , tjrForce      :: Text
  , tjrRenderStrategy :: Maybe Text
  , tjrRenderStyle :: Maybe Text
  , tjrLegitimacy :: Maybe Double
  , tjrGuardStatus :: Maybe Text
  , tjrGuardReportWarnings :: Maybe [Text]
  , tjrIdentitySignal :: Maybe Text
  , tjrSemanticAnchor :: Maybe Text
  , tjrTurns      :: Int
  , tjrEgoAgency  :: Double
  , tjrEgoTension :: Double
  , tjrDecision   :: Maybe TurnDecision
  , tjrRuntimeEpoch :: Maybe Text
  , tjrRuntimeTurnIndex :: Maybe Int
  , tjrWorkerMode :: Maybe Text
  } deriving stock (Generic)

instance ToJSON TurnJsonResponse where
  toJSON r = object $
    [ "status"     .= tjrStatus r
    , "session_id" .= tjrSessionId r
    , "input"      .= tjrInput r
    ] ++ backwardCompatAliases r ++
    [ "render_strategy" .= tjrRenderStrategy r
    , "render_style" .= tjrRenderStyle r
    , "legitimacy" .= tjrLegitimacy r
    , "guard_status" .= tjrGuardStatus r
    , "guard_warnings" .= tjrGuardReportWarnings r
    , "identity_signal" .= tjrIdentitySignal r
    , "semantic_anchor" .= tjrSemanticAnchor r
    , "turns"      .= tjrTurns r
    , "ego_agency" .= tjrEgoAgency r
    , "ego_tension" .= tjrEgoTension r
    , "decision" .= tjrDecision r
    , "runtime_epoch" .= tjrRuntimeEpoch r
    , "runtime_turn_index" .= tjrRuntimeTurnIndex r
    , "worker_mode" .= tjrWorkerMode r
    ]

backwardCompatAliases :: TurnJsonResponse -> [(Data.Aeson.Key, Data.Aeson.Value)]
backwardCompatAliases r =
  [ "surface"    .= tjrOutput r
  , "text"       .= tjrOutput r
  , "response"   .= tjrOutput r
  , "family"     .= tjrFamily r
  , "move_family" .= tjrFamily r
  , "force"      .= tjrForce r
  , "illocutionary_force" .= tjrForce r
  ]

runTurnJson :: Text -> RuntimeOutputMode -> Text -> IO TurnJsonResponse
runTurnJson sessionId mode inputText = do
  result <- tryQxFx0 $
    Runtime.withBootstrappedSession True sessionId $ \session0 -> do
      (_, response) <- runTurnJsonInSession session0 mode inputText
      pure response
  case result of
    Right response -> pure response
    Left err -> do
      emitCliDebug err
      throwIO err

emitCliDebug :: QxFx0Exception -> IO ()
emitCliDebug err = do
  mFlag <- lookupEnv "QXFX0_DEBUG_RAW_ERRORS"
  case fmap (T.toLower . T.strip . T.pack) mFlag of
    Just "1" -> hPutStrLn stderr ("[cli_debug] " <> rawQxFx0Exception err)
    Just "true" -> hPutStrLn stderr ("[cli_debug] " <> rawQxFx0Exception err)
    _ -> pure ()

rawQxFx0Exception :: QxFx0Exception -> String
rawQxFx0Exception err =
  case err of
    PersistenceError msg -> "PersistenceError: " <> T.unpack msg
    PersistenceTxError stage msg -> "PersistenceTxError(stage=" <> show stage <> "): " <> T.unpack msg
    SQLiteError msg -> "SQLiteError: " <> T.unpack msg
    RuntimeInitError msg -> "RuntimeInitError: " <> T.unpack msg
    EmbeddingError msg -> "EmbeddingError: " <> T.unpack msg
    ThresholdParseError msg -> "ThresholdParseError: " <> T.unpack msg
    AgdaGateError msg -> "AgdaGateError: " <> T.unpack msg
    IdentityRupture msg -> "IdentityRupture: " <> T.unpack msg
    EssenceRupture msg -> "EssenceRupture: " <> T.unpack msg
    EvidenceInadmissibleFailure msg -> "EvidenceInadmissibleFailure: " <> T.unpack msg
    StateInvariantViolation msg -> "StateInvariantViolation: " <> T.unpack msg
    EmbeddingErrorStructured _ -> "EmbeddingErrorStructured"
    RuntimeInitErrorStructured _ -> "RuntimeInitErrorStructured"
    SQLiteErrorStructured _ -> "SQLiteErrorStructured"
    PersistenceConflict _ _ _ _ -> "PersistenceConflict"
    PersistenceErrorStructured _ -> "PersistenceErrorStructured"

runTurnJsonInSession :: Runtime.Session -> RuntimeOutputMode -> Text -> IO (Runtime.Session, TurnJsonResponse)
runTurnJsonInSession session0 mode inputText = do
  let session1 = setOutputMode mode session0
  (session2, response) <- Runtime.runTurnInSession session1 inputText
  let ss = Runtime.sessSystemState session2
      mDecision = ssLastTurnDecision ss
  pure
    ( session2
    , TurnJsonResponse
    { tjrStatus = "ok"
    , tjrSessionId = Runtime.sessSessionId session2
    , tjrInput = inputText
    , tjrOutput = response
     , tjrFamily = maybe (textShow (ssLastFamily ss)) (textShow . tdFamily) mDecision
     , tjrForce = maybe (textShow (ssLastForce ss)) (textShow . tdForce) mDecision
     , tjrRenderStrategy = textShow . tdRenderStrategy <$> mDecision
    , tjrRenderStyle = renderStyleText . tdRenderStyle <$> mDecision
    , tjrLegitimacy = tdLegitimacy <$> mDecision
     , tjrGuardStatus = textShow . tdGuardStatus <$> mDecision
     , tjrGuardReportWarnings = (fmap textShow . igrWarnings . tdGuardReport) <$> mDecision
    , tjrIdentitySignal = renderIdentitySignal <$> mDecision
    , tjrSemanticAnchor = renderSemanticAnchor <$> mDecision
    , tjrTurns = ssTurnCount ss
    , tjrEgoAgency = egoAgency (ssEgo ss)
    , tjrEgoTension = egoTension (ssEgo ss)
    , tjrDecision = mDecision
    , tjrRuntimeEpoch = Nothing
    , tjrRuntimeTurnIndex = Nothing
    , tjrWorkerMode = Nothing
    }
    )

attachRuntimeDiagnostics :: Text -> Int -> Text -> TurnJsonResponse -> TurnJsonResponse
attachRuntimeDiagnostics epoch turnIndex workerMode response =
  response
    { tjrRuntimeEpoch = Just epoch
    , tjrRuntimeTurnIndex = Just turnIndex
    , tjrWorkerMode = Just workerMode
    }

setOutputMode :: RuntimeOutputMode -> Runtime.Session -> Runtime.Session
setOutputMode mode session = session
  { Runtime.sessOutputMode = toRuntimeMode mode
  , Runtime.sessSystemState = (Runtime.sessSystemState session)
      { ssOutputMode = toDialogueMode mode }
  }
  where
    toRuntimeMode DialogueMode = Runtime.DialogueMode
    toRuntimeMode SemanticIntrospectionMode = Runtime.SemanticIntrospectionMode
    toDialogueMode DialogueMode = DialogueOutput
    toDialogueMode SemanticIntrospectionMode = SemanticIntrospectionOutput

renderIdentitySignal :: TurnDecision -> Text
renderIdentitySignal decision =
  let sig = tdIdentity decision
  in textShow (issOrbitalPhase sig)
     <> "/"
     <> textShow (issEncounterMode sig)
     <> "/"
     <> textShow (issMoveBias sig)

renderSemanticAnchor :: TurnDecision -> Text
renderSemanticAnchor decision =
  case tdSemanticAnchor decision of
    Nothing -> ""
    Just anchor -> dominantChannelText (saDominantChannel anchor)
