{-# LANGUAGE DerivingStrategies, OverloadedStrings, StrictData #-}
module QxFx0.Bridge.TxStatement
  ( TxStmt
  , prepareTx
  , bindTextOrFail
  , bindIntOrFail
  , bindDoubleOrFail
  , stepOrFail
  , rollbackAndFail
  ) where

import qualified QxFx0.Bridge.NativeSQLite as NSQL
import QxFx0.ExceptionPolicy (throwQxFx0, QxFx0Exception(PersistenceTxError))
import QxFx0.Types.Persistence (PersistenceStage(..))
import Data.Text (Text)
import qualified Data.Text as T
import Foreign.C.Types (CInt)

data TxStmt = TxStmt
  { txsStmt :: !NSQL.Statement
  , txsDb   :: !NSQL.Database
  , txsCtx  :: !Text
  }

prepareTx :: NSQL.Database -> Text -> Text -> IO TxStmt
prepareTx db ctx sql = do
  mStmt <- NSQL.prepare db sql
  case mStmt of
    Left err -> do
      _ <- NSQL.execSql db "ROLLBACK;"
      throwQxFx0 (PersistenceTxError (stageFromContext ctx) err)
    Right s -> pure TxStmt { txsStmt = s, txsDb = db, txsCtx = ctx }

rollbackAndFail :: TxStmt -> Text -> IO a
rollbackAndFail ts msg = do
  NSQL.finalize (txsStmt ts)
  _ <- NSQL.execSql (txsDb ts) "ROLLBACK;"
  throwQxFx0 (PersistenceTxError (stageFromContext (txsCtx ts)) msg)

bindTextOrFail :: TxStmt -> CInt -> Text -> IO ()
bindTextOrFail ts ix v =
  NSQL.bindText (txsStmt ts) ix v >>= either
    (\err -> rollbackAndFail ts ("bindText[" <> T.pack (show ix) <> "] failed: " <> err))
    (const (pure ()))

bindIntOrFail :: TxStmt -> CInt -> Int -> IO ()
bindIntOrFail ts ix v =
  NSQL.bindInt (txsStmt ts) ix v >>= either
    (\err -> rollbackAndFail ts ("bindInt[" <> T.pack (show ix) <> "] failed: " <> err))
    (const (pure ()))

bindDoubleOrFail :: TxStmt -> CInt -> Double -> IO ()
bindDoubleOrFail ts ix v =
  NSQL.bindDouble (txsStmt ts) ix v >>= either
    (\err -> rollbackAndFail ts ("bindDouble[" <> T.pack (show ix) <> "] failed: " <> err))
    (const (pure ()))

stepOrFail :: TxStmt -> IO ()
stepOrFail ts = do
  stepResult <- NSQL.step (txsStmt ts)
  NSQL.finalize (txsStmt ts)
  case stepResult of
    Left err -> do
      _ <- NSQL.execSql (txsDb ts) "ROLLBACK;"
      throwQxFx0 (PersistenceTxError (stageFromContext (txsCtx ts)) err)
    Right _ -> pure ()

stageFromContext :: Text -> PersistenceStage
stageFromContext ctx
  | "turn_quality" `T.isPrefixOf` ctx = StageTurnQualityUpsert
  | "shadow_divergence_log" `T.isPrefixOf` ctx = StageShadowDivergenceInsert
  | "saveKV:" `T.isPrefixOf` ctx = StageStateBlobUpsert
  | "touchRuntimeSessionActivity" `T.isPrefixOf` ctx = StageSessionTouch
  | "delete_turn_quality_above" `T.isPrefixOf` ctx = StageRollbackTurnQuality
  | "delete_shadow_divergence_above" `T.isPrefixOf` ctx = StageRollbackShadowDivergence
  | otherwise = StageUnknown
