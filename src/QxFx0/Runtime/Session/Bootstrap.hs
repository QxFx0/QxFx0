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
import Control.Monad (unless, when)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Map.Strict as M
import qualified QxFx0.Observability.Logging as Log
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
import QxFx0.Bridge.StatePersistence (loadState, loadStateRevision)
import QxFx0.ExceptionPolicy
  ( QxFx0Exception(..)
  , RuntimeInitErrorDetails(..)
  , SQLiteErrorDetails(..)
  , mkRuntimeInitError
  , renderQxFx0ExceptionForLog
  , throwQxFx0
  , tryIO
  , tryQxFx0
  )
import QxFx0.Governance.Replay (rebuildGovernedSystemState)
import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
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
import QxFx0.Semantic.Lexicon.RuntimeParadigms (loadDefaultRuntimeParadigms, allParadigmLemmas, emptyRuntimeParadigms)
import QxFx0.Types.RuntimeRegime (defaultRuntimeRegime, rrRglMorphologyActive)
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
import QxFx0.Types.State.Governance (GovernanceRuntimeFault(..))
import System.Directory (createDirectoryIfMissing)
import System.FilePath (takeDirectory)
import System.IO (hPutStrLn, stderr)

bootstrapSession :: Bool -> Text -> IO Session
bootstrapSession quiet sessionId = do
  Log.logInfo "Starting session bootstrap"
    (Log.addContext "session_id" sessionId Log.emptyContext)
  dbPath <- resolveDbPath
  runtimeMode <- resolveRuntimeMode
  createDirectoryIfMissing True (takeDirectory dbPath)
  readiness <- assessResourceReadiness dbPath
  let readinessMode = computeReadinessMode readiness
  Log.logDebug "Resource readiness assessed"
    (Log.addContext "readiness_mode" (T.pack $ show readinessMode) $
     Log.addContext "db_path" (T.pack dbPath) Log.emptyContext)
  case evaluateBootstrapReadiness runtimeMode readinessMode of
    Left failure -> do
      Log.logError "Bootstrap readiness gate failed"
        (Log.addContext "failure" (renderBootstrapGateFailure failure) Log.emptyContext)
      throwQxFx0 $ mkRuntimeInitError "Bootstrap" "readiness_gate" "BOOTSTRAP_GATE_FAILURE"
        (M.fromList [("failure", renderBootstrapGateFailure failure)])
    Right _ ->
      case readinessMode of
        Degraded failed -> do
          Log.logWarn "Bootstrap in degraded mode"
            (Log.addContext "failed_components" (T.pack $ show failed) Log.emptyContext)
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
      Log.logException err
        (Log.addContext "db_path" (T.pack dbPath) $
         Log.addContext "stage" "schema_init" Log.emptyContext)
      hPutStrLn stderr $ "[runtime_init_debug] schema_init_qxfx0_exception db=" <> dbPath <> " detail=" <> T.unpack (renderQxFx0ExceptionForLog err)
      throwQxFx0 $ mkRuntimeInitError "Bootstrap" "schema_init" "SCHEMA_INIT_EXCEPTION"
        (M.fromList [("db_path", T.pack dbPath), ("detail", runtimeInitDetail err)])
    Right (Left err) -> do
      Log.logError "Schema initialization SQL error"
        (Log.addContext "db_path" (T.pack dbPath) $
         Log.addContext "detail" err Log.emptyContext)
      hPutStrLn stderr $ "[runtime_init_debug] schema_init_sql_error db=" <> dbPath <> " detail=" <> T.unpack err
      throwQxFx0 $ mkRuntimeInitError "Bootstrap" "schema_init" "SCHEMA_INIT_SQL_ERROR"
        (M.fromList [("db_path", T.pack dbPath), ("detail", err)])
    Right (Right _) -> do
      Log.logInfo "Schema initialization complete"
        (Log.addContext "db_path" (T.pack dbPath) Log.emptyContext)
      pure ()

  morphologyResult <- tryQxFx0 loadMorphologyData
  morphology <- case morphologyResult of
    Left err -> do
      Log.logException err
        (Log.addContext "stage" "morphology_load" Log.emptyContext)
      hPutStrLn stderr $ "[runtime_init_debug] morphology_load_failed detail=" <> T.unpack (renderQxFx0ExceptionForLog err)
      throwQxFx0 $ mkRuntimeInitError "Bootstrap" "morphology_load" "MORPHOLOGY_LOAD_FAILED"
        (M.fromList [("detail", renderQxFx0ExceptionForLog err)])
    Right md -> do
      Log.logInfo "Morphology data loaded" Log.emptyContext
      pure md
  -- R1 + flag gate (RGL Russian): load runtime morphology paradigms only when
  -- 'rrRglMorphologyActive' is set. The flag is static (set in
  -- 'defaultRuntimeRegime', not changed mid-session), so gating the LOAD here
  -- makes it a real switch: flag off → empty paradigms → 'lookupNounForm' always
  -- misses → 'lookupLemmaForm' uses the JSON path everywhere → RGL is genuinely
  -- inert (the documented "rrRglMorphologyActive = False ⇒ JSON production"
  -- contract). Flag on → RGL-backed morphology for covered lemmas. Load failure
  -- is non-fatal: an empty set degrades gracefully to JSON.
  runtimeParadigms <-
    if rrRglMorphologyActive defaultRuntimeRegime
      then do
        ps <- loadDefaultRuntimeParadigms
        when (null (allParadigmLemmas ps)) $
          Log.logInfo "Runtime paradigms empty (JSON morphology fallback active)" Log.emptyContext
        pure ps
      else pure emptyRuntimeParadigms
  runtime <- initRuntimeContext dbPath
  health <- checkHealth runtime
  case evaluateStrictHealth runtimeMode health of
    Left failure -> do
      Log.logError "Health gate failed"
        (Log.addContext "failure" (renderBootstrapGateFailure failure) Log.emptyContext)
      throwQxFx0 $ mkRuntimeInitError "Bootstrap" "health_gate" "HEALTH_GATE_FAILURE"
        (M.fromList [("failure", renderBootstrapGateFailure failure)])
    Right _ -> do
      Log.logInfo "Health check passed" Log.emptyContext
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
        , ssRuntimeParadigms = runtimeParadigms
        , ssIdentity = (ssIdentity emptySystemState) {idsIdentityClaims = idClaims}
        , ssSemantic = (ssSemantic emptySystemState) {semClusters = clusters}
        , ssSessionId = sessionId
        }
  stateRevision <- loadStateRevision (withRuntimeDb runtime) sessionId
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
          DegradedRuntime -> do
            let recovered = freshState
                  { ssSessionId = sessionId
                  , ssGovernanceRuntimeFault = Just (GrfRecoveredCorruptBootstrap rendered)
                  }
            unless quiet $
              hPutStrLn stderr $
                "[runtime_init_debug] persisted_state_corrupt_degraded_recovery session=" <> T.unpack sessionId
            pure (RecoveredCorruptOrigin, recovered)
          StrictRuntime ->
            throwQxFx0 $ mkRuntimeInitError "Bootstrap" "state_restore" "STATE_CORRUPT"
              (M.fromList [("session_id", sessionId), ("diagnostics", rendered)])
      Right (LoadStateRestored ss) ->
        if ssTurnCount ss == 0 && null (ssHistory ss)
          then pure (FreshOrigin, freshState)
          else
            -- Bootstrap currently performs three lifecycle roles in one local block:
            -- (1) authoritative restore admission has already happened inside
            --     'loadState' / 'rebuildDerivedViewsAfterLoad';
            -- (2) substrate backfill/overlay applies scene, morphology, cluster,
            --     identity-claim, and live-session adjustments;
            -- (3) authoritative governance rebuild may rerun after those overlays.
            -- The current front documents these as distinct lifecycle phases even
            -- though the implementation still keeps them adjacent here.
            let restored0 = ss
                  { ssDialogue = (ssDialogue ss) {dsActiveScene = firstScene}
                  , ssMorphology = mergeMorphology morphology (ssMorphology ss)
                  , ssRuntimeParadigms = runtimeParadigms
                  , ssIdentity = (ssIdentity ss)
                    { idsIdentityClaims = if null (ssIdentityClaims ss) then idClaims else ssIdentityClaims ss
                    }
                  , ssSemantic = (ssSemantic ss)
                     { semClusters = if null (ssClusters ss) then clusters else ssClusters ss
                     }
                   , ssSessionId = sessionId
                   }
             in if truthContractIsAuthoritative (ssTruthContractStatus restored0)
                  then case rebuildGovernedSystemState restored0 of
                         Right restored1 -> pure (RestoredOrigin, restored1)
                         Left err -> throwQxFx0 $ mkRuntimeInitError "Bootstrap" "governance_rebuild" "GOVERNANCE_REBUILD_FAILED"
                           (M.fromList [("session_id", sessionId), ("error", err)])
                  else pure (RestoredOrigin, restored0)
  -- Phase 1: verify that the freshly bootstrapped state forms a
  -- structurally coherent self (see docs/THEORY.md §4.1 and
  -- docs/adr/0007-dual-mode-conatus.md). Failure here is categorical:
  -- the session was unable to come into being as /this system/, and
  -- there is nothing to recover.
  case checkInitialBlanket (computeSelfBlanket restored) of
    [] -> do
      Log.logInfo "Self-blanket verification passed"
        (Log.addContext "state_origin" (T.pack $ show stateOrigin) Log.emptyContext)
      pure ()
    vs -> do
      let violations = renderBlanketViolations vs
      Log.logError "Self-blanket verification failed"
        (Log.addContext "violations" violations Log.emptyContext)
      throwQxFx0 (IdentityRupture ("bootstrap: " <> violations))
  hydrateRuntimeTurnState runtime restored
  Log.logInfo "Session bootstrap complete"
    (Log.addContext "session_id" sessionId $
     Log.addContext "state_origin" (T.pack $ show stateOrigin) $
     Log.addContext "turn_count" (T.pack $ show $ ssTurnCount restored) Log.emptyContext)
  pure Session
    { sessSystemState = restored
    , sessOutputMode = DialogueMode
    , sessSessionId = sessionId
    , sessDbPath = dbPath
    , sessStateOrigin = stateOrigin
    , sessStateRevision = stateRevision
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

runtimeInitDetail :: QxFx0Exception -> Text
runtimeInitDetail ex =
  case ex of
    SQLiteErrorStructured details -> sedOperation details <> ": " <> sedErrorCode details
    RuntimeInitError msg -> msg
    RuntimeInitErrorStructured details -> riedOperation details <> ": " <> riedErrorCode details
    _ -> renderQxFx0ExceptionForLog ex

withBootstrappedSession :: Bool -> Text -> (Session -> IO a) -> IO a
withBootstrappedSession quiet sessionId =
  bracket (bootstrapSession quiet sessionId) closeSession

closeSession :: Session -> IO ()
closeSession session = do
  Log.logInfo "Closing session"
    (Log.addContext "session_id" (sessSessionId session) Log.emptyContext)
  releaseRuntimeContext (sessRuntime session)

checkSessionReadiness :: Session -> IO ReadinessMode
checkSessionReadiness session = do
  readiness <- assessResourceReadiness (sessDbPath session)
  pure (computeReadinessMode readiness)
