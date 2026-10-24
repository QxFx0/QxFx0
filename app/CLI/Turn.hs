{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module CLI.Turn
  ( TurnJsonResponse(..)
  , runTurnJson
  , runTurnJsonInSession
  , crisisPreflightResponse
  , attachRuntimeDiagnostics
  ) where

import CLI.Protocol (RuntimeOutputMode(..))
import Control.Exception (IOException, bracket, displayException, throwIO)
import Data.Aeson (ToJSON(..), object, (.=), Value, Key)
import Data.Text (Text)
import qualified Data.Text as T
import QxFx0.Render.Text (textShow)
import GHC.Generics (Generic)
import System.Environment (lookupEnv)
import System.IO (hPutStrLn, stderr)

import qualified QxFx0.Runtime as Runtime
import QxFx0.Core.IdentityGuard (IdentityGuardReport(..))
import QxFx0.ExceptionPolicy (QxFx0Exception(..), tryIO, tryQxFx0)
import QxFx0.Safety.CrisisGuard (crisisPreflightSurface)
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
  -- Catch only the bootstrap acquisition.  A turn that fails after the
  -- session exists must follow the normal engine/exception policy; the
  -- fallback exists solely for the pre-session window where the crisis
  -- preflight inside Engine is unreachable.  The two boot-boundary
  -- classes are caught explicitly: domain errors via 'tryQxFx0' and I/O
  -- failures via 'tryIO'.  Cancellation and programming errors still
  -- propagate, matching `ExceptionPolicy.tryBootResource` semantics
  -- without naming 'SomeException' in app code (architecture rule [5]).
  bootstrapResult <- tryIO (tryQxFx0 (Runtime.bootstrapSession True sessionId))
  case bootstrapResult of
    Left ioErr -> bootstrapIOFailureResponse sessionId inputText ioErr
    Right (Left err) -> bootstrapFailureResponse sessionId inputText err
    Right (Right session0) ->
      bracket (pure session0) Runtime.closeSession $ \session -> do
        (_, response) <- runTurnJsonInSession session mode inputText
        pure response

bootstrapFailureResponse :: Text -> Text -> QxFx0Exception -> IO TurnJsonResponse
bootstrapFailureResponse sessionId inputText err =
  bootstrapFailureWith sessionId inputText (rawQxFx0Exception err) (throwIO err)

bootstrapIOFailureResponse :: Text -> Text -> IOException -> IO TurnJsonResponse
bootstrapIOFailureResponse sessionId inputText err =
  bootstrapFailureWith sessionId inputText (displayException err) (throwIO err)

bootstrapFailureWith :: Text -> Text -> String -> IO TurnJsonResponse -> IO TurnJsonResponse
bootstrapFailureWith sessionId inputText detail rethrow =
  case crisisPreflightSurface inputText of
    Just surface -> pure (crisisPreflightResponse sessionId inputText surface)
    Nothing -> do
      emitCliDebug detail
      rethrow

-- | Emergency Protocol B response for a runtime that could not be
-- bootstrapped at all.  This is deliberately not a synthetic turn: no
-- session, no trace, no persistence.  It exists so an acute crisis
-- utterance never gets a bootstrap error instead of real resources.
crisisPreflightResponse :: Text -> Text -> Text -> TurnJsonResponse
crisisPreflightResponse sessionId inputText surface =
  TurnJsonResponse
    { tjrStatus = "ok"
    , tjrSessionId = sessionId
    , tjrInput = inputText
    , tjrOutput = surface
    , tjrFamily = "CrisisProtocolB"
    , tjrForce = "IFAssert"
    , tjrRenderStrategy = Nothing
    , tjrRenderStyle = Nothing
    , tjrLegitimacy = Nothing
    , tjrGuardStatus = Nothing
    , tjrGuardReportWarnings = Nothing
    , tjrIdentitySignal = Nothing
    , tjrSemanticAnchor = Nothing
    , tjrTurns = 0
    , tjrEgoAgency = 0
    , tjrEgoTension = 0
    , tjrDecision = Nothing
    , tjrRuntimeEpoch = Nothing
    , tjrRuntimeTurnIndex = Nothing
    , tjrWorkerMode = Nothing
    }

emitCliDebug :: String -> IO ()
emitCliDebug detail = do
  mFlag <- lookupEnv "QXFX0_DEBUG_RAW_ERRORS"
  case fmap (T.toLower . T.strip . T.pack) mFlag of
    Just "1" -> hPutStrLn stderr ("[cli_debug] " <> detail)
    Just "true" -> hPutStrLn stderr ("[cli_debug] " <> detail)
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
    PersistenceConflict _ _ _ -> "PersistenceConflict"
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
