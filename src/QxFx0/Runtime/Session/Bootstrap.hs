{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

{-| Session bootstrap, readiness gating, and runtime lifecycle wiring. -}
module QxFx0.Runtime.Session.Bootstrap
  ( bootstrapSession
  , withBootstrappedSession
  , closeSession
  , checkSessionReadiness
  , generateFallbackSessionId
  , minimalMorphologyFallback
  , recoverBootstrapBlanket
  , useExternalKnowledge
  , readExternalKnowledgeEnabled
  , resolveKnowledgePath
  , bootstrapSemanticNetwork
  , buildNetworkFromAtomGraph
  , readSelfPlayEnabled
  , readSelfPlayRelationsPath
  , selfPlayRelationsPath
  , useSelfPlay
  ) where

import Control.Exception (bracket, try, IOException)
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
import QxFx0.Self.Types (BlanketViolation (..))
import QxFx0.Resources
  ( ReadinessMode(..)
  , assessResourceReadiness
  , computeReadinessMode
  , loadMorphologyData
  )
import QxFx0.Runtime.Wiring
  ( hydrateRuntimeTurnState
  , initRuntimeContext
  , rcCaches
  , releaseRuntimeContext
  , withRuntimeDb
  )
import QxFx0.Runtime.Wiring.Context (rtcPgf)
import QxFx0.Runtime.Gate
  ( evaluateBootstrapReadiness
  , evaluateStrictHealth
  , renderBootstrapGateFailure
  )
import QxFx0.Runtime.Health (checkHealth)
import QxFx0.Runtime.PGF (cachedReadPGF, defaultPgfPath)
import QxFx0.Lexicon.GfMap (preloadGfMap, GfMapLoadStatus(..))
import QxFx0.Runtime.Mode (RuntimeMode(..), resolveRuntimeMode)
import QxFx0.Runtime.Paths (resolveDbPath)
import QxFx0.Runtime.Session.Types
import QxFx0.Semantic.SemanticScene (defaultScenes)
import QxFx0.Semantic.Lexicon.RuntimeParadigms (loadDefaultRuntimeParadigms, allParadigmLemmas, emptyRuntimeParadigms)
import QxFx0.Semantic.ContentSelector (buildContentSelector)
import QxFx0.Semantic.Space (buildSemanticSpace)
import QxFx0.Semantic.Content (definitionCorpus, DefinitionContent(..), SemanticPredicate(..), coveredTopics)
import QxFx0.Semantic.Ontology (loadOntology, emptyOntology)
import QxFx0.Semantic.Network (mergeSemanticNetworks)
import QxFx0.Semantic.Network.Seed.Select (selectSeedNetwork, selectSeedNetworkIO, readUseAtomGraphSeed)
import QxFx0.Semantic.Network.Ingest (buildNetworkFromAtomGraph, ingestExternalKnowledge, mergeSelfPlayRelations)
import QxFx0.Semantic.Content.AtomStore (seedGraph)
import Data.Maybe (fromMaybe)
import QxFx0.Semantic.Network.Substrate (BrainKBEntry(..), loadBrainKB, resolveBrainKBPath, buildSubstrateEdges, SubstrateEdgeInfo(..))
import QxFx0.Semantic.Content.SubstrateCandidate
  ( extractCandidates, admitCandidates, promoteAll, defaultAdmissionConfig )
import QxFx0.Semantic.Content.AtomStore (AtomId(..), allTopics, allAtomIds, relationStore, Relation(..), RelationSource(..), seedGraph, withPromoted, atomStore, Atom(..), AtomCategory(..))
import QxFx0.Semantic.Content.AtomDiscovery (discoverAtoms, DiscoveredAtom(..))
import qualified QxFx0.Semantic.Network.Types as NetTypes
import QxFx0.Semantic.Network.Types (SemanticEdge(..), EdgeSource(..), SemanticNetwork)
import qualified Data.Set as S
import qualified Data.Text as T
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
import QxFx0.Types.Domain.Atoms (LexemeCase(..), LexemeForm(..), LexemeNumber(..), MorphologyData(..), SourceTier(..))
import QxFx0.Semantic.Morphology (buildLemmaMap)
import QxFx0.Types.State.Governance (GovernanceRuntimeFault(..))
import Data.Time.Clock (getCurrentTime)
import Data.Time.Format (defaultTimeLocale, formatTime)
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUIDv4
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.Environment (lookupEnv)
import System.FilePath (takeDirectory)
import System.IO (hPutStrLn, stderr)
import Paths_qxfx0 (getDataFileName)

-- | Compile-time feature flag for ADR-0052 Phase II external knowledge
-- ingestion. Defaults to 'False' so runtime behavior is unchanged.
useExternalKnowledge :: Bool
useExternalKnowledge = False

-- | Read whether external knowledge ingestion should be enabled.
-- The compile-time 'useExternalKnowledge' flag can force it on; otherwise
-- the @QXFX0_USE_EXTERNAL_KNOWLEDGE@ environment variable enables it
-- when set to @\"1\"@, @\"true\"@, or @\"yes\"@.
readExternalKnowledgeEnabled :: IO Bool
readExternalKnowledgeEnabled = do
  mEnv <- lookupEnv "QXFX0_USE_EXTERNAL_KNOWLEDGE"
  let envEnabled = maybe False (`elem` ["1", "true", "yes"]) mEnv
  pure (envEnabled || useExternalKnowledge)

-- | Compile-time feature flag for ADR-0052 Phase III self-play relation
-- ingestion. Defaults to 'False' so runtime behavior is unchanged.
useSelfPlay :: Bool
useSelfPlay = False

-- | Read whether self-play relation ingestion should be enabled.
-- The compile-time 'useSelfPlay' flag can force it on; otherwise the
-- @QXFX0_USE_SELFPLAY@ environment variable enables it when set to
-- @\"1\"@, @\"true\"@, or @\"yes\"@.
readSelfPlayEnabled :: IO Bool
readSelfPlayEnabled = do
  mEnv <- lookupEnv "QXFX0_USE_SELFPLAY"
  let envEnabled = maybe False (`elem` ["1", "true", "yes"]) mEnv
  pure (envEnabled || useSelfPlay)

-- | Resolve the path to the self-play relations file. The
-- @QXFX0_SELFPLAY_RELATIONS_PATH@ environment variable overrides the
-- default @resources/knowledge/selfplay_relations.jsonl@.
readSelfPlayRelationsPath :: IO FilePath
readSelfPlayRelationsPath = do
  mEnv <- lookupEnv "QXFX0_SELFPLAY_RELATIONS_PATH"
  pure (fromMaybe "resources/knowledge/selfplay_relations.jsonl" mEnv)

-- | Alias for 'readSelfPlayRelationsPath'.
selfPlayRelationsPath :: IO FilePath
selfPlayRelationsPath = readSelfPlayRelationsPath

-- | Resolve a knowledge file path. First try the path as given; if it
-- does not exist, fall back to a @Paths_qxfx0@ data-file path; finally
-- return the original path so that a later stage can report a sensible
-- \"file not found\" error.
resolveKnowledgePath :: FilePath -> IO FilePath
resolveKnowledgePath path = do
  exists <- doesFileExist path
  if exists
    then pure path
    else do
      dataResult <- tryIO (getDataFileName path)
      case dataResult of
        Right dataPath -> pure dataPath
        Left _         -> pure path

-- | Build the bootstrapped semantic network from morphology and brain_kb
-- substrate, optionally merging external ontology/relations.
bootstrapSemanticNetwork :: MorphologyData -> [BrainKBEntry] -> Bool -> IO SemanticNetwork
bootstrapSemanticNetwork morphology brainKBEntries useExternal =
  let lemmaMap = buildLemmaMap morphology
      explicitTopicSet = S.fromList coveredTopics
      substrateEdges = buildSubstrateEdges brainKBEntries explicitTopicSet
      substrateEdgeMap = M.fromList
        [ ((seiFrom e, seiTo e), NetTypes.semanticEdge (seiFrom e) (seiTo e) (seiWeight e) (seiCooc e) NetTypes.SubstrateEdge)
        | e <- substrateEdges
        ]
  in do
      seedNetwork <- selectSeedNetworkIO lemmaMap
      let seedEdges = NetTypes.snEdges seedNetwork
          mergedEdges = M.union seedEdges substrateEdgeMap
          mergedNetwork = seedNetwork { NetTypes.snEdges = mergedEdges }
      withExternal <- if not useExternal
        then pure mergedNetwork
        else do
          ontologyPath <- resolveKnowledgePath "resources/knowledge/ontology.jsonl"
          relationsPath <- resolveKnowledgePath "resources/knowledge/relations.jsonl"
          mExternal <- ingestExternalKnowledge ontologyPath relationsPath
          pure $ maybe mergedNetwork (mergeSemanticNetworks mergedNetwork) mExternal
      selfPlayEnabled <- readSelfPlayEnabled
      if not selfPlayEnabled
        then pure withExternal
        else do
          selfPlayPath <- resolveKnowledgePath =<< readSelfPlayRelationsPath
          selfPlayExists <- doesFileExist selfPlayPath
          if not selfPlayExists
            then pure withExternal
            else mergeSelfPlayRelations selfPlayPath withExternal

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
  gfMapPreloadStatus <- preloadGfMap
  case gfMapPreloadStatus of
    GfMapLoaded _ ->
      Log.logInfo "GF lexicon map preloaded" Log.emptyContext
    GfMapLoadFailed reason ->
      Log.logWarn "GF lexicon map preload failed; runtime will degrade gracefully on GF map paths"
        (Log.addContext "reason" reason Log.emptyContext)
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
  pgfPreloadResult <- try $ do
    _ <- cachedReadPGF (rtcPgf (rcCaches runtime)) defaultPgfPath
    pure (Right ())
  case pgfPreloadResult of
    Left (err :: IOException) ->
      Log.logWarn "PGF grammar preload failed; runtime will degrade gracefully on PGF paths"
        (Log.addContext "error" (T.pack (show err)) Log.emptyContext)
    Right _ ->
      Log.logInfo "PGF grammar preloaded" Log.emptyContext
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

  -- Load brain_kb for substrate network enrichment
  brainKBPath <- resolveBrainKBPath
  brainKBEntries <- loadBrainKB brainKBPath

  -- ADR-0052 Phase IV: load ontology once for category classification.
  -- Failure is non-fatal: the classifier falls back to lexical markers.
  ontologyPath <- resolveKnowledgePath "resources/knowledge/ontology.jsonl"
  ontologyResult <- try @IOException (loadOntology ontologyPath)
  ontology <- case ontologyResult of
    Left err -> do
      Log.logWarn "Ontology load failed; category classifier will fall back to lexical markers"
        (Log.addContext "error" (T.pack (show err)) Log.emptyContext)
      pure emptyOntology
    Right ot -> do
      Log.logInfo "Ontology loaded" Log.emptyContext
      pure ot

  externalEnabled <- readExternalKnowledgeEnabled
  finalNetwork <- bootstrapSemanticNetwork morphology brainKBEntries externalEnabled

  let firstScene = case (scenes ++ defaultScenes) of
        s : _ -> s
        [] -> ssActiveScene emptySystemState

      -- Initialize ContentSelector from seed network and definition corpus
      lemmaMap = buildLemmaMap morphology
      topicAtoms = M.fromList
        [ (topic, S.unions [tokenizePredicateForSeed (spRu p) | p <- dcPredicates dc])
        | (topic, dc) <- M.toList definitionCorpus
        ]
      topicPredicates = M.map dcPredicates definitionCorpus
      -- Substrate candidate extraction + admission
      -- Use allAtomIds (85+ atoms) for admission, not just allTopics (30+)
      -- Also include discovered atoms from brain_kb
      topicList = allTopics
      discoveredAtoms = discoverAtoms brainKBEntries
      discoveredAtomIds = map (atomId . daAtom) discoveredAtoms
      knownAtomIds = allAtomIds ++ discoveredAtomIds
      candidates = extractCandidates brainKBEntries topicList
      (admitted, _rejected) = admitCandidates defaultAdmissionConfig knownAtomIds candidates
      promotedRelations = promoteAll admitted
      seedSpace = buildSemanticSpace finalNetwork topicAtoms
      seedSelector = buildContentSelector seedSpace topicAtoms topicPredicates lemmaMap

      freshState = emptySystemState
        { ssDialogue = (ssDialogue emptySystemState) {dsActiveScene = firstScene}
        , ssMorphology = morphology
        , ssRuntimeParadigms = runtimeParadigms
        , ssIdentity = (ssIdentity emptySystemState) {idsIdentityClaims = idClaims}
        , ssSemantic = (ssSemantic emptySystemState) {semClusters = clusters}
        , ssSessionId = sessionId
        , ssContentSelector = seedSelector
        , ssLemmaMap = buildLemmaMap morphology
        , ssSemanticNetwork = finalNetwork
        , ssOntology = ontology
        , ssRuntimeGraph = withPromoted promotedRelations seedGraph
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
                   , ssSemanticNetwork = finalNetwork
                   , ssOntology = ontology
                   , ssRuntimeGraph = withPromoted promotedRelations seedGraph
                   }
             in if truthContractIsAuthoritative (ssTruthContractStatus restored0)
                  then case rebuildGovernedSystemState restored0 of
                         Right restored1 -> pure (RestoredOrigin, restored1)
                         Left err -> throwQxFx0 $ mkRuntimeInitError "Bootstrap" "governance_rebuild" "GOVERNANCE_REBUILD_FAILED"
                           (M.fromList [("session_id", sessionId), ("error", err)])
                  else pure (RestoredOrigin, restored0)
  -- Phase 1: verify that the freshly bootstrapped state forms a
  -- structurally coherent self (see docs/THEORY.md §4.1 and
  -- docs/adr/0007-dual-mode-conatus.md). Some failures are recoverable
  -- (empty session identifier, empty morphology). Recovered fields are
  -- threaded back into 'restored' and 'sessionId' so the remainder of
  -- bootstrap uses the repaired values.
  (remainingVs, restored', sessionId') <-
    recoverBootstrapBlanket morphology restored sessionId
  case remainingVs of
    [] -> do
      if sessionId' /= sessionId || restored' /= restored
        then Log.logWarn "Self-blanket verification recovered"
               (Log.addContext "state_origin" (T.pack $ show stateOrigin) $
                Log.addContext "recovered_session_id" sessionId' Log.emptyContext)
        else Log.logInfo "Self-blanket verification passed"
               (Log.addContext "state_origin" (T.pack $ show stateOrigin) Log.emptyContext)
      pure ()
    vs -> do
      let violations = renderBlanketViolations vs
      Log.logError "Self-blanket verification failed"
        (Log.addContext "violations" violations Log.emptyContext)
      throwQxFx0 (IdentityRupture ("bootstrap: " <> violations))
  hydrateRuntimeTurnState runtime restored'
  Log.logInfo "Session bootstrap complete"
    (Log.addContext "session_id" sessionId' $
     Log.addContext "state_origin" (T.pack $ show stateOrigin) $
     Log.addContext "turn_count" (T.pack $ show $ ssTurnCount restored') Log.emptyContext)
  pure Session
    { sessSystemState = restored'
    , sessOutputMode = DialogueMode
    , sessSessionId = sessionId'
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

-- | Tokenize predicate text into atoms for ContentSelector initialization.
-- Filters stop words and short words (≤3 chars).
tokenizePredicateForSeed :: T.Text -> S.Set T.Text
tokenizePredicateForSeed text =
  let words = T.words (T.toLower text)
      filtered = filter (\w -> T.length w > 3 && not (isStopWord w)) words
  in S.fromList filtered
  where
    isStopWord w = w `elem`
      [ "это", "есть", "является", "быть", "было", "будет"
      , "и", "или", "но", "а", "в", "на", "с", "по", "для"
      , "что", "как", "когда", "где", "кто", "который", "которая"
      , "не", "ни", "же", "ли", "бы", "то", "так", "только"
      , "может", "могут", "должен", "должна", "должно"
      , "через", "между", "перед", "после", "при", "во", "со"
      , "the", "and", "or", "but", "is", "are", "was", "were"
      , "of", "to", "in", "on", "at", "for", "with", "by"
      , "that", "which", "who", "when", "where", "how"
      ]

-- | Generate a stable, human-readable fallback session identifier.
-- Used when the bootstrap self-blanket reports 'BlanketEmptySession'.
-- Format: @bootstrap-recovery-<utc>-<uuid>@.
generateFallbackSessionId :: IO Text
generateFallbackSessionId = do
  now <- getCurrentTime
  uuid <- UUIDv4.nextRandom
  pure $ T.concat
    [ "bootstrap-recovery-"
    , T.pack (formatTime defaultTimeLocale "%Y%m%dT%H%M%S%Q" now)
    , "-"
    , UUID.toText uuid
    ]

-- | A minimal, valid morphology that guarantees
-- @sbMorphologyTotalSize > 0@. It contains a single surface form
-- mapped to itself so the system can always normalise at least one
-- token. This is the morphology used by 'recoverBootstrapBlanket' when
-- the loaded morphology is completely empty.
minimalMorphologyFallback :: MorphologyData
minimalMorphologyFallback = MorphologyData
  { mdPrepositional = M.empty
  , mdGenitive      = M.empty
  , mdNominative    = M.singleton "qxfx0" "qxfx0"
  , mdFormsBySurface = M.singleton "qxfx0"
      [ LexemeForm
          { lfSurface = "qxfx0"
          , lfLemma   = "qxfx0"
          , lfPOS     = "noun"
          , lfCase    = NominativeCase
          , lfNumber  = SingularNumber
          , lfTier    = CuratedTier
          , lfQuality = 1.0
          }
      ]
  }

-- | Recover a bootstrapped state that fails the initial self-blanket.
-- Currently handles two recoverable violations:
--
--   * 'BlanketEmptySession'      -> generate a fallback session id;
--   * 'BlanketEmptyMorphology'   -> install 'minimalMorphologyFallback'
--                                   and recompute the lemma map.
--
-- After repairs the blanket is recomputed. Remaining (non-recoverable)
-- violations, the repaired state, and the final session id are
-- returned to the caller.
recoverBootstrapBlanket
  :: MorphologyData
  -> SystemState
  -> Text
  -> IO ([BlanketViolation], SystemState, Text)
recoverBootstrapBlanket originalMorphology state sessionIdIn = do
  let initialVs = checkInitialBlanket (computeSelfBlanket state)
  if null initialVs
    then pure ([], state, sessionIdIn)
    else do
      let sessionIdOut
            | BlanketEmptySession `elem` initialVs = Nothing
            | otherwise                            = Just sessionIdIn
          stateWithMorph
            | BlanketEmptyMorphology `elem` initialVs =
                let fallback = minimalMorphologyFallback
                in state
                     { ssMorphology = fallback
                     , ssLemmaMap   = buildLemmaMap fallback
                     }
            | otherwise = state
      recoveredSessionId <- maybe generateFallbackSessionId pure sessionIdOut
      let stateOut = stateWithMorph { ssSessionId = recoveredSessionId }
          remainingVs = checkInitialBlanket (computeSelfBlanket stateOut)
      unless (null remainingVs) $ do
        Log.logWarn "Bootstrap blanket recovery attempted but violations remain"
          (Log.addContext "violations" (renderBlanketViolations remainingVs) Log.emptyContext)
      when (BlanketEmptySession `elem` initialVs) $ do
        Log.logWarn "Generated fallback session id during bootstrap blanket recovery"
          (Log.addContext "fallback_session_id" recoveredSessionId Log.emptyContext)
      when (BlanketEmptyMorphology `elem` initialVs) $ do
        Log.logWarn "Installed minimal morphology fallback during bootstrap blanket recovery"
          (Log.addContext "original_morphology_size"
             (T.pack $ show $ M.size (mdNominative originalMorphology)
                       + M.size (mdGenitive originalMorphology)
                       + M.size (mdPrepositional originalMorphology)
                       + M.size (mdFormsBySurface originalMorphology))
             Log.emptyContext)
      pure (remainingVs, stateOut, recoveredSessionId)
