{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

{-| Session bootstrap, readiness gating, and runtime lifecycle wiring. -}
module QxFx0.Runtime.Session.Bootstrap
  ( bootstrapSession
  , withBootstrappedSession
  , closeSession
  , checkSessionReadiness
  ) where

import Control.Exception (bracket, try)
import Control.Monad (unless)
import Data.Text (Text)
import qualified Data.Text as T
import QxFx0.Bridge.SQLite
  ( ensureSchemaMigrations
  , loadClusters
  , loadScenes
  , queryIdentityClaimsByFocus
  , withDB
  )
import qualified QxFx0.Bridge.NativeSQLite as NSQL
import QxFx0.Types.Persistence (LoadStateResult(..), renderPersistenceDiagnostics)
import QxFx0.Bridge.StatePersistence (loadState)
import QxFx0.ExceptionPolicy (QxFx0Exception(..), throwQxFx0, tryIO, tryQxFx0)
import QxFx0.Resources
  ( ReadinessMode(..)
  , assessResourceReadiness
  , computeReadinessMode
  , loadMorphologyData
  )
import QxFx0.Runtime.Context
  ( hydrateRuntimeTurnState
  , initRuntimeContext
  , releaseRuntimeContext
  , withRuntimeDb
  )
import QxFx0.Runtime.Gate
  ( evaluateBootstrapReadiness
  , evaluateStrictHealth
  , renderBootstrapGateFailure
  )
import QxFx0.Runtime.Health (checkHealth)
import QxFx0.Runtime.Mode (resolveRuntimeMode)
import QxFx0.Runtime.Paths (resolveDbPath)
import QxFx0.Runtime.Session.Types
import QxFx0.Semantic.SemanticScene (defaultScenes)
import QxFx0.Types.State
  ( SystemState(..)
  , dsActiveScene
  , emptySystemState
  , idsIdentityClaims
  , semClusters
  , ssActiveScene
  , ssClusters
  , ssHistory
  , ssIdentityClaims
  , ssTurnCount
  )
import System.Directory (createDirectoryIfMissing)
import System.FilePath (takeDirectory)
import System.IO (hPutStrLn, stderr)

bootstrapSession :: Bool -> Text -> IO Session
bootstrapSession quiet sessionId = do
  dbPath <- resolveDbPath
  runtimeMode <- resolveRuntimeMode
  createDirectoryIfMissing True (takeDirectory dbPath)
  readiness <- assessResourceReadiness dbPath
  let readinessMode = computeReadinessMode readiness
  case evaluateBootstrapReadiness runtimeMode readinessMode of
    Left failure ->
      throwQxFx0 (RuntimeInitError (renderBootstrapGateFailure failure))
    Right _ ->
      case readinessMode of
        Degraded failed ->
          unless quiet $ hPutStrLn stderr $ "[degraded] optional components unavailable: " ++ show failed
        _ ->
          pure ()
  schemaInitResult <- try (withDB dbPath $ \db -> do
    ensureSchemaMigrations db
    mStmt <- NSQL.prepare db "INSERT OR IGNORE INTO runtime_sessions(id, agency, tension, status) VALUES(?, 0.5, 0.3, 'active')"
    case mStmt of
      Left err -> throwQxFx0 (SQLiteError err)
      Right stmt -> do
        _ <- NSQL.bindText stmt 1 sessionId
        _ <- NSQL.step stmt
        NSQL.finalize stmt
        pure ()
    ) :: IO (Either QxFx0Exception (Either Text ()))
  case schemaInitResult of
    Left err -> throwQxFx0 (RuntimeInitError $ "Cannot initialize schema: " <> T.pack (show err))
    Right (Left err) -> throwQxFx0 (RuntimeInitError $ "Cannot initialize schema: " <> err)
    Right (Right _) -> pure ()

  morphologyResult <- tryQxFx0 loadMorphologyData
  morphology <- case morphologyResult of
    Left err -> throwQxFx0 (RuntimeInitError $ "Cannot load morphology data: " <> T.pack (show err))
    Right md -> pure md
  runtime <- initRuntimeContext dbPath
  health <- checkHealth runtime
  case evaluateStrictHealth runtimeMode health of
    Left failure ->
      throwQxFx0 (RuntimeInitError (renderBootstrapGateFailure failure))
    Right _ ->
      pure ()

  idClaims <- withRuntimeDb runtime $ \db ->
    queryIdentityClaimsByFocus db ["identity", "agency", "meaning", "consciousness", "truth"]

  clusters <- withRuntimeDb runtime loadClusters
  scenes <- withRuntimeDb runtime loadScenes

  let firstScene = case (scenes ++ defaultScenes) of
        s : _ -> s
        [] -> ssActiveScene emptySystemState
      freshState = emptySystemState
        { ssDialogue = (ssDialogue emptySystemState) {dsActiveScene = firstScene}
        , ssMorphology = morphology
        , ssIdentity = (ssIdentity emptySystemState) {idsIdentityClaims = idClaims}
        , ssSemantic = (ssSemantic emptySystemState) {semClusters = clusters}
        , ssSessionId = sessionId
        }
  (stateOrigin, restored) <- do
    mSs <- tryIO (loadState (withRuntimeDb runtime) sessionId)
    case mSs of
      Left err -> do
        unless quiet $ hPutStrLn stderr $ "[warn] cannot restore state, starting fresh: " ++ show err
        pure (FreshOrigin, freshState)
      Right LoadStateMissing ->
        pure (FreshOrigin, freshState)
      Right (LoadStateCorrupt diagnostics) -> do
        unless quiet $
          hPutStrLn stderr $
            "[warn] persisted state is corrupt, entering recovery bootstrap: " <> T.unpack (renderPersistenceDiagnostics diagnostics)
        pure (RecoveredCorruptOrigin, freshState)
      Right (LoadStateRestored ss) ->
        if ssTurnCount ss == 0 && null (ssHistory ss)
          then pure (FreshOrigin, freshState)
          else pure (RestoredOrigin, ss
            { ssDialogue = (ssDialogue ss) {dsActiveScene = firstScene}
            , ssMorphology = morphology
            , ssIdentity = (ssIdentity ss)
              { idsIdentityClaims = if null (ssIdentityClaims ss) then idClaims else ssIdentityClaims ss
              }
            , ssSemantic = (ssSemantic ss)
              { semClusters = if null (ssClusters ss) then clusters else ssClusters ss
              }
            , ssSessionId = sessionId
            })
  hydrateRuntimeTurnState runtime restored
  pure Session
    { sessSystemState = restored
    , sessOutputMode = DialogueMode
    , sessSessionId = sessionId
    , sessDbPath = dbPath
    , sessStateOrigin = stateOrigin
    , sessReadinessMode = readinessMode
    , sessRuntime = runtime
    }

withBootstrappedSession :: Bool -> Text -> (Session -> IO a) -> IO a
withBootstrappedSession quiet sessionId =
  bracket (bootstrapSession quiet sessionId) closeSession

closeSession :: Session -> IO ()
closeSession = releaseRuntimeContext . sessRuntime

checkSessionReadiness :: Session -> IO ReadinessMode
checkSessionReadiness session = do
  readiness <- assessResourceReadiness (sessDbPath session)
  pure (computeReadinessMode readiness)
