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
import qualified Data.Map.Strict as M
import QxFx0.Bridge.SQLite
  ( ensureSchemaMigrations
  , loadClusters
  , loadScenes
  , queryIdentityClaimsByFocus
  , withDB
  )
import qualified QxFx0.Bridge.NativeSQLite as NSQL
import QxFx0.Bridge.TxStatement (prepareTx, bindTextOrFail, stepOrFail)
import QxFx0.Types.Persistence (LoadStateResult(..), renderPersistenceDiagnostics)
import QxFx0.Bridge.StatePersistence (loadState)
import QxFx0.ExceptionPolicy (QxFx0Exception(..), renderQxFx0ExceptionForLog, throwQxFx0, tryIO, tryQxFx0)
import QxFx0.Governance.Replay (rebuildGovernedSystemState)
import QxFx0.Self.Blanket (computeSelfBlanket)
import QxFx0.Self.Invariants (checkInitialBlanket, renderBlanketViolations)
import QxFx0.Resources
  ( ReadinessMode(..)
  , assessResourceReadiness
  , computeReadinessMode
  , loadMorphologyData
  )
import QxFx0.Runtime.Wiring
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
import QxFx0.Runtime.Mode (RuntimeMode(..), resolveRuntimeMode)
import QxFx0.Runtime.Paths (resolveDbPath)
import QxFx0.Runtime.Session.Types
import QxFx0.Semantic.SemanticScene (defaultScenes)
import QxFx0.Types.State.Governance (GovernanceRuntimeFault(..))
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
import QxFx0.Types.Domain.Atoms (MorphologyData(..))
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
    ts <- prepareTx db "bootstrap_runtime_session" "INSERT OR IGNORE INTO runtime_sessions(id, agency, tension, status) VALUES(?, 0.5, 0.3, 'active')"
    bindTextOrFail ts 1 sessionId
    stepOrFail ts
    pure ()
    ) :: IO (Either QxFx0Exception (Either Text ()))
  case schemaInitResult of
    Left err -> do
      hPutStrLn stderr $ "[runtime_init_debug] schema_init_qxfx0_exception db=" <> dbPath <> " detail=" <> T.unpack (renderQxFx0ExceptionForLog err)
      throwQxFx0 (RuntimeInitError $ "Cannot initialize schema: " <> renderQxFx0ExceptionForLog err)
    Right (Left err) -> do
      hPutStrLn stderr $ "[runtime_init_debug] schema_init_sql_error db=" <> dbPath <> " detail=" <> T.unpack err
      throwQxFx0 (RuntimeInitError $ "Cannot initialize schema: " <> err)
    Right (Right _) -> pure ()

  morphologyResult <- tryQxFx0 loadMorphologyData
  morphology <- case morphologyResult of
    Left err -> do
      hPutStrLn stderr $ "[runtime_init_debug] morphology_load_failed detail=" <> T.unpack (renderQxFx0ExceptionForLog err)
      throwQxFx0 (RuntimeInitError $ "Cannot load morphology data: " <> renderQxFx0ExceptionForLog err)
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
        let rendered = renderPersistenceDiagnostics diagnostics
        unless quiet $
          hPutStrLn stderr $
            "[runtime_init_debug] persisted_state_corrupt session=" <> T.unpack sessionId <> " detail=" <> T.unpack rendered
        case runtimeMode of
          StrictRuntime ->
            throwQxFx0 (RuntimeInitError ("Persisted state is corrupt: " <> rendered))
          DegradedRuntime -> do
            unless quiet $
              hPutStrLn stderr $
                "[warn] persisted state is corrupt, entering non-authoritative recovery bootstrap: " <> T.unpack rendered
            pure
              ( RecoveredCorruptOrigin
              , freshState { ssGovernanceRuntimeFault = Just (GrfRecoveredCorruptBootstrap rendered) }
              )
      Right (LoadStateRestored ss) ->
        if ssTurnCount ss == 0 && null (ssHistory ss)
          then pure (FreshOrigin, freshState)
          else
            let restored0 = ss
                  { ssDialogue = (ssDialogue ss) {dsActiveScene = firstScene}
                  , ssMorphology = mergeMorphology morphology (ssMorphology ss)
                  , ssIdentity = (ssIdentity ss)
                    { idsIdentityClaims = if null (ssIdentityClaims ss) then idClaims else ssIdentityClaims ss
                    }
                  , ssSemantic = (ssSemantic ss)
                    { semClusters = if null (ssClusters ss) then clusters else ssClusters ss
                    }
                  , ssSessionId = sessionId
                  }
            in case rebuildGovernedSystemState restored0 of
                 Right restored1 ->
                   pure
                     ( RestoredOrigin
                     , restored1
                     )
                 Left err -> pure
                    ( RecoveredCorruptOrigin
                    , freshState { ssGovernanceRuntimeFault = Just (GrfRecoveredCorruptBootstrap err) }
                    )
  -- Phase 1: verify that the freshly bootstrapped state forms a
  -- structurally coherent self (see docs/THEORY.md §4.1 and
  -- docs/adr/0007-dual-mode-conatus.md). Failure here is categorical:
  -- the session was unable to come into being as /this system/, and
  -- there is nothing to recover.
  case checkInitialBlanket (computeSelfBlanket restored) of
    [] -> pure ()
    vs -> throwQxFx0 (IdentityRupture ("bootstrap: " <> renderBlanketViolations vs))
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

-- | Merge persisted morphology with resource-loaded morphology.
-- Resource morphology takes precedence; persisted morphology may fill
-- only gaps and must not outrun the current provenance boundary.
mergeMorphology :: MorphologyData -> MorphologyData -> MorphologyData
mergeMorphology resource persisted = MorphologyData
  { mdPrepositional = M.union (mdPrepositional resource) (mdPrepositional persisted)
  , mdGenitive      = M.union (mdGenitive resource)      (mdGenitive persisted)
  , mdNominative    = M.union (mdNominative resource)    (mdNominative persisted)
  , mdFormsBySurface = M.union (mdFormsBySurface resource) (mdFormsBySurface persisted)
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
