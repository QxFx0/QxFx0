{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Promotion boundary between runtime LLM hypotheses and user-visible
-- semantic predicates. Runtime edges remain associative evidence; only an
-- explicitly gated, versioned overlay is loaded into the content selector.
module QxFx0.Learning.Promotion
  ( PromotionSnapshot(..)
  , PromotionCandidate(..)
  , PromotionEvaluation(..)
  , InformativenessResult(..)
  , evaluateCandidateInformativeness
  , informativenessSemanticGainThreshold
  , promotionGatePolicyVersion
  , promotionEvaluationCorpusVersion
  , promotionRuntimeCorpusVersion
  , ensurePromotionSchema
  , createPromotionSnapshot
  , buildPromotionCandidates
  , runPromotionGates
  , createDraftOverlay
  , activatePromotionOverlay
  , recordPromotionHumanRelease
  , rollbackPromotionOverlay
  , loadActivePromotionOverlay
  , loadActivePromotionCorpus
  , renderPromotionCorpus
  , renderPromotionOverlay
  , runPromotionEvaluation
  ) where

import Control.Exception (onException)
import Control.Monad (forM_, unless, when)
import Data.Int (Int64)
import Data.List (partition, sort, sortOn)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe, isJust, mapMaybe)
import Data.Set (Set)
import qualified Data.Set as S
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time.Clock (UTCTime, getCurrentTime)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime, utcTimeToPOSIXSeconds)

import QxFx0.Bridge.SQLite (QxFx0DB(..), withDB)
import qualified QxFx0.Bridge.NativeSQLite as NSQL
import QxFx0.Bridge.TxStatement
  ( TxStmt
  , bindDoubleOrFail
  , bindInt64OrFail
  , bindNullOrFail
  , bindTextOrFail
  , prepareTx
  , stepOrFail
  )
import QxFx0.Learning.Events
  ( RuntimeEvidence(..)
  , loadRuntimeEvidenceOnConnection
  )
import QxFx0.Learning.JobQueue (currentLearningPolicyVersion)
import QxFx0.Learning.CorroborationQueue (currentCorroborationPolicyVersion)
import QxFx0.Learning.Quarantine (sha256Hex)
import QxFx0.Semantic.Content
  ( DefinitionContent(..)
  , CanonicalPredicateRelation(..)
  , PredicateRole(..)
  , SemanticPredicate(..)
  , definitionCorpus
  , normalizeTopic
  )
import QxFx0.Semantic.Morphology (instrumentalForm)
import QxFx0.Types (MorphologyData)
import QxFx0.Semantic.Content.AtomStore
  ( Atom(..)
  , AtomId(..)
  , Relation(..)
  , RelationType(..)
  , atomStore
  , relationStore
  )
import QxFx0.Types.RuntimeRegime (currentMathVersion)
import QxFx0.Types.State.System (CuratedOverlayRuntime(..))
import QxFx0.ExceptionPolicy (mkSQLiteError, throwQxFx0)

data PromotionSnapshot = PromotionSnapshot
  { psSnapshotId :: !Text
  , psCreatedAt :: !UTCTime
  , psEdgeCount :: !Int
  , psChecksum :: !Text
  }
  deriving stock (Eq, Show)

data PromotionCandidate = PromotionCandidate
  { pcCandidateId :: !Text
  , pcSnapshotId :: !Text
  , pcTopic :: !Text
  , pcSubject :: !Text
  , pcRelationType :: !Text
  , pcObject :: !Text
  , pcRenderedRu :: !Text
  , pcConfidence :: !Double
  , pcSupportCount :: !Int
  , pcStatus :: !Text
  }
  deriving stock (Eq, Show)

data PromotionEvaluation = PromotionEvaluation
  { peEvaluationId :: !Text
  , peBaselineContentful :: !Int
  , peCandidateContentful :: !Int
  , peBaselineConflicts :: !Int
  , peCandidateConflicts :: !Int
  , peBaselineRefusals :: !Int
  , peCandidateRefusals :: !Int
  }
  deriving stock (Eq, Show)

data InformativenessResult = InformativenessResult
  { irNotTautological :: !Bool
  , irAddsNovelInformation :: !Bool
  , irNotTopicParaphrase :: !Bool
  , irSemanticGain :: !Double
  , irPassed :: !Bool
  }
  deriving stock (Eq, Show)

informativenessSemanticGainThreshold :: Double
informativenessSemanticGainThreshold = 0.75

-- | A relation shape used solely at the promotion boundary.  The base corpus
-- is represented by typed AtomStore relations; overlays retain the same
-- canonical subject/relation/object shape in SQLite.  This keeps duplicate
-- detection independent of Russian surface wording.
data CanonicalRelation = CanonicalRelation
  { crSubject :: !Text
  , crRelation :: !Text
  , crObject :: !Text
  }
  deriving stock (Eq, Ord, Show)

-- | The policy is versioned independently from candidate and overlay ids. A
-- revalidation can therefore be audited without treating an old draft as new
-- evidence for its own candidate.
promotionGatePolicyVersion :: Text
promotionGatePolicyVersion = "promotion-v6-session-scoped-corroboration"

promotionGatePolicyDescription :: Text
promotionGatePolicyDescription =
  "canonical curated and historical duplicate/subsumption gates; "
    <> "candidate identity is snapshot-scoped, and only the same candidate "
    <> "plus snapshot is idempotent history rather than evidence; "
    <> "independent support requires complete model/parser/admission/source lineage; "
    <> "session-local support is partitioned by session owner and only an explicit overlay promotion globalizes it; "
    <> "curated corroboration requires an exact canonical triple"

promotionGatePolicyChecksum :: Text
promotionGatePolicyChecksum = sha256Hex (TE.encodeUtf8
  (promotionGatePolicyVersion <> "\n" <> promotionGatePolicyDescription))

-- | Version of the deterministic corpus-level precheck in
-- 'runPromotionEvaluation'. Runtime renderer evaluation has its own version.
promotionEvaluationCorpusVersion :: Text
promotionEvaluationCorpusVersion = "promotion-corpus-precheck-v1"

promotionRuntimeCorpusVersion :: Text
promotionRuntimeCorpusVersion = "promotion-runtime-ab-v1"

data HistoricalOverlayRelation = HistoricalOverlayRelation
  { horOverlayVersion :: !Text
  , horSnapshotId :: !Text
  , horCandidateId :: !Text
  , horRelation :: !CanonicalRelation
  }
  deriving stock (Eq, Show)

ensurePromotionSchema :: QxFx0DB -> IO ()
ensurePromotionSchema db = do
  result <- withDB (qdbPath db) $ \conn -> withTransaction conn $ do
    let statements =
          [ "CREATE TABLE IF NOT EXISTS learning_schema_versions (owner TEXT PRIMARY KEY, version INTEGER NOT NULL, updated_at INTEGER NOT NULL)"
          , "CREATE TABLE IF NOT EXISTS promotion_snapshots (snapshot_id TEXT PRIMARY KEY, created_at INTEGER NOT NULL, edge_count INTEGER NOT NULL, checksum TEXT NOT NULL, status TEXT NOT NULL)"
          , "CREATE TABLE IF NOT EXISTS learning_apply_proofs (source_kind TEXT NOT NULL, request_id TEXT NOT NULL, policy TEXT NOT NULL, dispatch_token TEXT NOT NULL, applied_at INTEGER NOT NULL, PRIMARY KEY(source_kind, request_id))"
          , "CREATE TABLE IF NOT EXISTS promotion_snapshot_edges (snapshot_id TEXT NOT NULL, edge_id INTEGER NOT NULL, edge_from TEXT NOT NULL, edge_to TEXT NOT NULL, relation_type TEXT, confidence REAL NOT NULL, provenance TEXT NOT NULL, namespace TEXT NOT NULL DEFAULT 'global', session_id TEXT, owner TEXT NOT NULL DEFAULT 'global', captured_at INTEGER NOT NULL, PRIMARY KEY(snapshot_id, edge_id))"
          , "CREATE TABLE IF NOT EXISTS promotion_snapshot_edge_lineage (snapshot_id TEXT NOT NULL, edge_id INTEGER NOT NULL, request_id TEXT NOT NULL, prompt_hash TEXT NOT NULL, response_hash TEXT NOT NULL, evidence_source TEXT NOT NULL, model TEXT, parser_decision TEXT, admission_decision TEXT, event_timestamp INTEGER, namespace TEXT NOT NULL DEFAULT 'global', session_id TEXT, owner TEXT NOT NULL DEFAULT 'global', PRIMARY KEY(snapshot_id, edge_id, request_id, response_hash))"
          , "CREATE TABLE IF NOT EXISTS promotion_candidate_exclusions (snapshot_id TEXT NOT NULL, edge_id INTEGER NOT NULL, edge_from TEXT NOT NULL, edge_to TEXT NOT NULL, relation_type TEXT, reason_code TEXT NOT NULL, created_at INTEGER NOT NULL, PRIMARY KEY(snapshot_id, edge_id, reason_code))"
          , promotionCandidatesSchema
          , "CREATE TABLE IF NOT EXISTS promotion_gate_runs (candidate_id TEXT NOT NULL, gate_run_id TEXT NOT NULL, gate_name TEXT NOT NULL, gate_version TEXT NOT NULL, decision TEXT NOT NULL, score REAL, reason_code TEXT NOT NULL, detail TEXT NOT NULL, evaluated_at INTEGER NOT NULL, PRIMARY KEY(candidate_id, gate_run_id, gate_name))"
          , "CREATE TABLE IF NOT EXISTS promotion_overlays (overlay_version TEXT PRIMARY KEY, parent_version TEXT, prior_runtime_evaluation_id TEXT, snapshot_id TEXT NOT NULL, status TEXT NOT NULL, created_at INTEGER NOT NULL, activated_at INTEGER, checksum TEXT NOT NULL)"
          , "CREATE TABLE IF NOT EXISTS promotion_overlay_predicates (overlay_version TEXT NOT NULL, predicate_id TEXT NOT NULL, candidate_id TEXT NOT NULL, topic TEXT NOT NULL, predicate_role TEXT NOT NULL, predicate_ru TEXT NOT NULL, subject_atom TEXT NOT NULL, relation_type TEXT NOT NULL, object_atom TEXT NOT NULL, confidence REAL NOT NULL, PRIMARY KEY(overlay_version, predicate_id), UNIQUE(overlay_version, candidate_id))"
          , "CREATE TABLE IF NOT EXISTS promotion_active (singleton INTEGER PRIMARY KEY CHECK(singleton = 1), overlay_version TEXT, runtime_evaluation_id TEXT, updated_at INTEGER NOT NULL)"
          , "CREATE TABLE IF NOT EXISTS promotion_evaluations (evaluation_id TEXT PRIMARY KEY, overlay_version TEXT NOT NULL, created_at INTEGER NOT NULL, corpus_version TEXT NOT NULL, overlay_checksum TEXT NOT NULL, passed INTEGER NOT NULL CHECK(passed IN (0, 1)), baseline_contentful INTEGER NOT NULL, candidate_contentful INTEGER NOT NULL, baseline_conflicts INTEGER NOT NULL, candidate_conflicts INTEGER NOT NULL, baseline_refusals INTEGER NOT NULL, candidate_refusals INTEGER NOT NULL)"
          , "CREATE TABLE IF NOT EXISTS promotion_evaluation_cases (evaluation_id TEXT NOT NULL, case_id TEXT NOT NULL, topic TEXT NOT NULL, baseline_contentful INTEGER NOT NULL, candidate_contentful INTEGER NOT NULL, baseline_conflicts INTEGER NOT NULL, candidate_conflicts INTEGER NOT NULL, method TEXT NOT NULL, PRIMARY KEY(evaluation_id, case_id))"
          , promotionRuntimeReleaseGatesSchema
          , "CREATE TABLE IF NOT EXISTS promotion_runtime_evaluations (evaluation_id TEXT PRIMARY KEY, overlay_version TEXT NOT NULL, corpus_evaluation_id TEXT NOT NULL, completed_at INTEGER NOT NULL, runtime_corpus_version TEXT NOT NULL, math_version INTEGER NOT NULL, overlay_checksum TEXT NOT NULL, automated_passed INTEGER NOT NULL CHECK(automated_passed IN (0, 1)), overlay_usage_cases INTEGER NOT NULL, details TEXT NOT NULL)"
          , "CREATE TABLE IF NOT EXISTS promotion_gate_policies (policy_version TEXT PRIMARY KEY, policy_checksum TEXT NOT NULL, description TEXT NOT NULL, created_at INTEGER NOT NULL)"
          , "CREATE TABLE IF NOT EXISTS promotion_gate_run_lineage (gate_run_id TEXT PRIMARY KEY, snapshot_id TEXT NOT NULL, policy_version TEXT NOT NULL, policy_checksum TEXT NOT NULL, snapshot_checksum TEXT NOT NULL, created_at INTEGER NOT NULL)"
          , "CREATE TABLE IF NOT EXISTS promotion_overlay_lineage (overlay_version TEXT PRIMARY KEY, snapshot_id TEXT NOT NULL, snapshot_checksum TEXT NOT NULL, predicate_checksum TEXT NOT NULL, gate_run_id TEXT NOT NULL, policy_version TEXT NOT NULL, policy_checksum TEXT NOT NULL, created_at INTEGER NOT NULL)"
          , "CREATE INDEX IF NOT EXISTS idx_promotion_snapshot_edges_snapshot ON promotion_snapshot_edges(snapshot_id)"
          , "CREATE INDEX IF NOT EXISTS idx_promotion_candidates_status ON promotion_candidates(lifecycle_status)"
          , "CREATE INDEX IF NOT EXISTS idx_promotion_overlay_topic ON promotion_overlay_predicates(overlay_version, topic)"
          , "CREATE INDEX IF NOT EXISTS idx_promotion_evaluations_latest ON promotion_evaluations(overlay_version, created_at DESC, evaluation_id DESC)"
          , "CREATE INDEX IF NOT EXISTS idx_promotion_runtime_evaluations_latest ON promotion_runtime_evaluations(overlay_version, completed_at DESC, evaluation_id DESC)"
          ]
    mapM_ (execOrFail conn) statements
    scopeVersion <- promotionScopeSchemaVersion conn
    when (scopeVersion > 1) (throwPromotionError "promotion scope schema is newer than this runtime")
    mapM_ (ensurePromotionLineageColumn conn)
      [ ("model", "TEXT")
      , ("parser_decision", "TEXT")
      , ("admission_decision", "TEXT")
      , ("event_timestamp", "INTEGER")
      , ("namespace", "TEXT")
      , ("session_id", "TEXT")
      , ("owner", "TEXT")
      ]
    mapM_ (ensurePromotionTableColumn conn "promotion_snapshot_edges")
      [ ("namespace", "TEXT")
      , ("session_id", "TEXT")
      , ("owner", "TEXT")
      ]
    when (scopeVersion < 1) $ do
      execOrFail conn "UPDATE promotion_snapshot_edges SET namespace='global', session_id=NULL, owner='legacy_global' WHERE owner IS NULL OR owner=''"
      execOrFail conn "UPDATE promotion_snapshot_edge_lineage SET namespace='global', session_id=NULL, owner='legacy_global' WHERE owner IS NULL OR owner=''"
      now <- getCurrentTime
      marker <- prepareTx conn "promotion_scope_schema_version"
        "INSERT INTO learning_schema_versions(owner, version, updated_at) VALUES('promotion_scope', 1, ?) ON CONFLICT(owner) DO UPDATE SET version=excluded.version, updated_at=excluded.updated_at"
      bindInt64OrFail marker 1 (utcMicros now)
      stepOrFail marker
    migratePromotionCandidateSchema conn
    mapM_ (ensurePromotionTableColumn conn "promotion_overlay_lineage")
      [ ("snapshot_checksum", "TEXT NOT NULL DEFAULT ''")
      , ("predicate_checksum", "TEXT NOT NULL DEFAULT ''")
      ]
    mapM_ (ensurePromotionTableColumn conn "promotion_evaluations")
      [ ("corpus_version", "TEXT NOT NULL DEFAULT ''")
      , ("overlay_checksum", "TEXT NOT NULL DEFAULT ''")
      , ("passed", "INTEGER NOT NULL DEFAULT 0 CHECK(passed IN (0, 1))")
      ]
    mapM_ (ensurePromotionTableColumn conn "promotion_runtime_evaluations")
      [ ("corpus_evaluation_id", "TEXT NOT NULL DEFAULT ''")
      , ("runtime_corpus_version", "TEXT NOT NULL DEFAULT ''")
      , ("math_version", "INTEGER NOT NULL DEFAULT -1")
      , ("overlay_checksum", "TEXT NOT NULL DEFAULT ''")
      ]
    ensurePromotionTableColumn conn "promotion_active"
      ("runtime_evaluation_id", "TEXT")
    ensurePromotionTableColumn conn "promotion_overlays"
      ("prior_runtime_evaluation_id", "TEXT")
    migratePromotionReleaseGateSchema conn
    execOrFail conn "CREATE INDEX IF NOT EXISTS idx_promotion_candidates_status ON promotion_candidates(lifecycle_status)"
    execOrFail conn "CREATE INDEX IF NOT EXISTS idx_promotion_candidates_snapshot_canonical ON promotion_candidates(snapshot_id, canonical_hash)"
    execOrFail conn "CREATE INDEX IF NOT EXISTS idx_promotion_evaluations_latest ON promotion_evaluations(overlay_version, created_at DESC, evaluation_id DESC)"
    execOrFail conn "CREATE INDEX IF NOT EXISTS idx_promotion_runtime_evaluations_latest ON promotion_runtime_evaluations(overlay_version, completed_at DESC, evaluation_id DESC)"
    installPromotionImmutabilityTriggers conn
  either throwPromotionError pure result

promotionRuntimeReleaseGatesSchema :: Text
promotionRuntimeReleaseGatesSchema =
  "CREATE TABLE IF NOT EXISTS promotion_runtime_release_gates (overlay_version TEXT NOT NULL, evaluation_id TEXT NOT NULL, completed_at INTEGER NOT NULL, release_passed INTEGER NOT NULL CHECK(release_passed IN (0, 1)), human_reviewed INTEGER NOT NULL CHECK(human_reviewed IN (0, 1)), details TEXT NOT NULL, PRIMARY KEY(overlay_version, evaluation_id))"

-- | The original release table kept only one row per overlay. Rebuild it with
-- evaluation-scoped identity so an old human release remains auditable but can
-- never attest a newer runtime evaluation.
migratePromotionReleaseGateSchema :: NSQL.Database -> IO ()
migratePromotionReleaseGateSchema conn = do
  schema <- loadTableSchema conn "promotion_runtime_release_gates"
  when ("overlay_version text primary key" `T.isInfixOf` T.toLower schema) $ do
    execOrFail conn "ALTER TABLE promotion_runtime_release_gates RENAME TO promotion_runtime_release_gates_legacy"
    execOrFail conn promotionRuntimeReleaseGatesSchema
    execOrFail conn
      "INSERT INTO promotion_runtime_release_gates(overlay_version, evaluation_id, completed_at, release_passed, human_reviewed, details) SELECT overlay_version, evaluation_id, completed_at, release_passed, human_reviewed, details FROM promotion_runtime_release_gates_legacy"
    execOrFail conn "DROP TABLE promotion_runtime_release_gates_legacy"

loadTableSchema :: NSQL.Database -> Text -> IO Text
loadTableSchema conn tableName = do
  prepared <- NSQL.prepare conn
    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?"
  case prepared of
    Left err -> throwPromotionError err
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 tableName
      hasRow <- NSQL.stepRow stmt
      schema <- if hasRow then NSQL.columnText stmt 0 else pure ""
      NSQL.finalize stmt
      pure schema

installPromotionImmutabilityTriggers :: NSQL.Database -> IO ()
installPromotionImmutabilityTriggers conn = mapM_ (execOrFail conn)
  [ "CREATE TRIGGER IF NOT EXISTS promotion_overlay_predicates_no_update BEFORE UPDATE ON promotion_overlay_predicates BEGIN SELECT RAISE(ABORT, 'promotion overlay predicates are immutable'); END"
  , "CREATE TRIGGER IF NOT EXISTS promotion_overlay_predicates_no_delete BEFORE DELETE ON promotion_overlay_predicates BEGIN SELECT RAISE(ABORT, 'promotion overlay predicates are immutable'); END"
  , "CREATE TRIGGER IF NOT EXISTS promotion_overlay_predicates_no_late_insert BEFORE INSERT ON promotion_overlay_predicates WHEN EXISTS (SELECT 1 FROM promotion_overlays o WHERE o.overlay_version=NEW.overlay_version AND o.status<>'draft') BEGIN SELECT RAISE(ABORT, 'non-draft promotion overlay predicates are immutable'); END"
  , "CREATE TRIGGER IF NOT EXISTS promotion_overlay_artifact_no_update BEFORE UPDATE OF snapshot_id, checksum, created_at ON promotion_overlays BEGIN SELECT RAISE(ABORT, 'promotion overlay artifact is immutable'); END"
  , "CREATE TRIGGER IF NOT EXISTS promotion_overlay_parent_no_late_update BEFORE UPDATE OF parent_version ON promotion_overlays WHEN OLD.status<>'draft' AND NEW.parent_version IS NOT OLD.parent_version BEGIN SELECT RAISE(ABORT, 'non-draft promotion overlay parent is immutable'); END"
  , "CREATE TRIGGER IF NOT EXISTS promotion_overlay_no_delete BEFORE DELETE ON promotion_overlays BEGIN SELECT RAISE(ABORT, 'promotion overlays are immutable'); END"
  , "CREATE TRIGGER IF NOT EXISTS promotion_overlay_lineage_no_update BEFORE UPDATE ON promotion_overlay_lineage BEGIN SELECT RAISE(ABORT, 'promotion overlay lineage is immutable'); END"
  , "CREATE TRIGGER IF NOT EXISTS promotion_overlay_lineage_no_delete BEFORE DELETE ON promotion_overlay_lineage BEGIN SELECT RAISE(ABORT, 'promotion overlay lineage is immutable'); END"
  , "CREATE TRIGGER IF NOT EXISTS promotion_evaluations_no_update BEFORE UPDATE ON promotion_evaluations BEGIN SELECT RAISE(ABORT, 'promotion evaluations are immutable'); END"
  , "CREATE TRIGGER IF NOT EXISTS promotion_evaluations_no_delete BEFORE DELETE ON promotion_evaluations BEGIN SELECT RAISE(ABORT, 'promotion evaluations are immutable'); END"
  , "CREATE TRIGGER IF NOT EXISTS promotion_runtime_evaluations_no_update BEFORE UPDATE ON promotion_runtime_evaluations BEGIN SELECT RAISE(ABORT, 'promotion runtime evaluations are immutable'); END"
  , "CREATE TRIGGER IF NOT EXISTS promotion_runtime_evaluations_no_delete BEFORE DELETE ON promotion_runtime_evaluations BEGIN SELECT RAISE(ABORT, 'promotion runtime evaluations are immutable'); END"
  , "CREATE TRIGGER IF NOT EXISTS promotion_runtime_releases_no_update BEFORE UPDATE ON promotion_runtime_release_gates BEGIN SELECT RAISE(ABORT, 'promotion runtime releases are immutable'); END"
  , "CREATE TRIGGER IF NOT EXISTS promotion_runtime_releases_no_delete BEFORE DELETE ON promotion_runtime_release_gates BEGIN SELECT RAISE(ABORT, 'promotion runtime releases are immutable'); END"
  ]

-- | Promotion owns this additive table evolution. Legacy rows intentionally
-- retain NULLs, which makes them auditable but ineligible as independent
-- support under the current policy.
ensurePromotionLineageColumn :: NSQL.Database -> (Text, Text) -> IO ()
ensurePromotionLineageColumn conn (columnName, columnType) = do
  prepared <- NSQL.prepare conn
    "SELECT 1 FROM pragma_table_info('promotion_snapshot_edge_lineage') WHERE name = ? LIMIT 1"
  exists <- case prepared of
    Left err -> throwPromotionError err
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 columnName
      found <- NSQL.stepRow stmt
      NSQL.finalize stmt
      pure found
  unless exists $ do
    altered <- NSQL.execSql conn
      ("ALTER TABLE promotion_snapshot_edge_lineage ADD COLUMN " <> columnName <> " " <> columnType)
    either throwPromotionError pure altered

ensurePromotionTableColumn :: NSQL.Database -> Text -> (Text, Text) -> IO ()
ensurePromotionTableColumn conn tableName (columnName, columnType) = do
  prepared <- NSQL.prepare conn
    ("SELECT 1 FROM pragma_table_info('" <> tableName <> "') WHERE name = ? LIMIT 1")
  exists <- case prepared of
    Left err -> throwPromotionError err
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 columnName
      found <- NSQL.stepRow stmt
      NSQL.finalize stmt
      pure found
  unless exists $ execOrFail conn
    ("ALTER TABLE " <> tableName <> " ADD COLUMN " <> columnName <> " " <> columnType)

promotionScopeSchemaVersion :: NSQL.Database -> IO Int
promotionScopeSchemaVersion conn = do
  prepared <- NSQL.prepare conn
    "SELECT version FROM learning_schema_versions WHERE owner='promotion_scope'"
  case prepared of
    Left err -> throwPromotionError err
    Right stmt -> do
      found <- NSQL.stepRow stmt
      version <- if found then NSQL.columnInt stmt 0 else pure 0
      NSQL.finalize stmt
      pure version

promotionCandidatesSchema :: Text
promotionCandidatesSchema =
  "CREATE TABLE IF NOT EXISTS promotion_candidates (candidate_id TEXT PRIMARY KEY, snapshot_id TEXT NOT NULL, topic TEXT NOT NULL, subject_atom TEXT NOT NULL, relation_type TEXT NOT NULL, object_atom TEXT NOT NULL, rendered_ru TEXT NOT NULL, confidence_raw REAL NOT NULL, support_count INTEGER NOT NULL, lifecycle_status TEXT NOT NULL, canonical_hash TEXT NOT NULL, created_at INTEGER NOT NULL, UNIQUE(snapshot_id, canonical_hash))"

-- | Older module-owned schemas made 'canonical_hash' globally unique. That
-- suppresses the candidate record needed to audit a later snapshot, before
-- the historical-overlay gate has a chance to make its explicit decision.
-- Rebuild only that narrow table, preserving every existing row and all
-- dependent identifiers. There are no SQLite foreign keys to this table.
migratePromotionCandidateSchema :: NSQL.Database -> IO ()
migratePromotionCandidateSchema conn = do
  legacySchema <- loadPromotionCandidatesSchema conn
  when ("canonical_hash text not null unique" `T.isInfixOf` T.toLower legacySchema) $ do
    execOrFail conn "ALTER TABLE promotion_candidates RENAME TO promotion_candidates_legacy"
    execOrFail conn promotionCandidatesSchema
    execOrFail conn
      "INSERT INTO promotion_candidates(candidate_id, snapshot_id, topic, subject_atom, relation_type, object_atom, rendered_ru, confidence_raw, support_count, lifecycle_status, canonical_hash, created_at) SELECT candidate_id, snapshot_id, topic, subject_atom, relation_type, object_atom, rendered_ru, confidence_raw, support_count, lifecycle_status, canonical_hash, created_at FROM promotion_candidates_legacy"
    execOrFail conn "DROP TABLE promotion_candidates_legacy"

loadPromotionCandidatesSchema :: NSQL.Database -> IO Text
loadPromotionCandidatesSchema conn = do
  prepared <- NSQL.prepare conn
    "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'promotion_candidates'"
  case prepared of
    Left err -> throwPromotionError err
    Right stmt -> do
      hasRow <- NSQL.stepRow stmt
      schema <- if hasRow then NSQL.columnText stmt 0 else pure ""
      NSQL.finalize stmt
      pure schema

createPromotionSnapshot :: QxFx0DB -> IO PromotionSnapshot
createPromotionSnapshot db = do
  ensurePromotionSchema db
  now <- getCurrentTime
  result <- withDB (qdbPath db) $ \conn -> withTransaction conn $ do
    edges <- loadRuntimeEdges conn
    evidence <- loadSnapshotEvidence conn edges
    let edgeCanonical =
          [ T.intercalate "|" ["edge", T.pack (show eid), ef, et, fromMaybe "" rel, T.pack (show conf), T.pack (show cooc), prov, namespace, fromMaybe "" session, owner]
          | (eid, ef, et, rel, conf, cooc, prov, namespace, session, owner) <- sortOn edgeId edges
          ]
        lineageCanonical =
          [ T.intercalate "|"
              [ "lineage"
              , reEdgeFrom item
              , reEdgeTo item
              , reRelationType item
               , reRequestId item
               , reResponseHash item
               , rePromptHash item
               , reModel item
               , reParserDecision item
               , reAdmissionDecision item
               , reEvidenceSource item
                , T.pack (show (reEventTimestamp item))
                , reNamespace item
                , fromMaybe "" (reSessionId item)
                , reOwner item
              ]
          | item <- sort evidence
          ]
        canonical = T.intercalate "\n" (edgeCanonical ++ lineageCanonical)
        checksum = sha256Hex (TE.encodeUtf8 canonical)
        snapshotId = "promotion-snapshot-" <> checksum
    insertSnapshot conn snapshotId now (length edges) checksum
    forM_ edges $ \(eid, ef, et, rel, conf, _cooc, prov, namespace, session, owner) ->
      insertSnapshotEdge conn snapshotId eid ef et rel conf prov namespace session owner now
    captureSnapshotEdgeLineage conn snapshotId
    pure (PromotionSnapshot snapshotId now (length edges) checksum)
  either throwPromotionError pure result
  where
    loadSnapshotEvidence conn edges = do
      eventsAvailable <- tableExists conn "learning_events"
      columnsAvailable <- learningEvidenceColumnsAvailable conn
      if not eventsAvailable || not columnsAvailable
        then pure []
        else do
          evidence <- loadRuntimeEvidenceOnConnection conn
          let shapes = S.fromList
                [ (ef, et, fromMaybe "" rel, namespace, scopeSession namespace session, owner)
                | (_, ef, et, rel, _, _, _, namespace, session, owner) <- edges
                ]
          pure
            [ item
            | item <- evidence
            , (reEdgeFrom item, reEdgeTo item, reRelationType item, reNamespace item, scopeSession (reNamespace item) (reSessionId item), reOwner item) `S.member` shapes
            , T.toLower (reModel item) /= "mock"
            ]
    scopeSession namespace session = if namespace == "global" then Nothing else session

buildPromotionCandidates :: QxFx0DB -> Text -> IO Int
buildPromotionCandidates db snapshotId = do
  ensurePromotionSchema db
  now <- getCurrentTime
  result <- withDB (qdbPath db) $ \conn -> withTransaction conn $ do
    edges <- loadSnapshotEdges conn snapshotId
    independentSupport <- loadSnapshotIndependentSupport conn snapshotId
    resetSnapshotCandidateEvidence conn snapshotId
    -- Only edges with a complete, captured request/response lineage may enter
    -- the candidate store. Snapshot rows remain audit observations, not facts.
    let lineageComplete edge = M.member (snapshotEdgeId edge) independentSupport
        classified = map classifyEdge (filter lineageComplete edges)
        exclusions = [excluded | Left excluded <- classified]
        groups = M.elems (M.fromListWith combine [group | Right group <- classified])
    forM_ exclusions $ \(reason, edge) ->
      insertCandidateExclusion conn snapshotId edge reason now
    forM_ groups $ \(topic, subject, relation, object, confidence, edgeIds, namespace, session, owner) -> do
      let (requestIds, responseHashes) = foldl combineSupport (S.empty, S.empty)
            [ M.findWithDefault (S.empty, S.empty) edgeId independentSupport
            | edgeId <- S.toList edgeIds
            ]
          support = min (S.size requestIds) (S.size responseHashes)
          candidateId = candidateHash (snapshotId <> "|" <> namespace <> "|" <> fromMaybe "" session <> "|" <> owner) topic subject relation object
          rendered = renderCandidate subject relation object
      insertCandidate conn candidateId snapshotId topic subject relation object rendered confidence support
    pure (length groups)
  either throwPromotionError pure result
  where
    classifyEdge edge@(edgeId, subject, object, mRelation, confidence, _prov, namespace, session, owner, _captured) =
      case mRelation of
        Nothing -> Left ("missing_relation_type", edge)
        Just relation -> case promotionSubjectTopic subject of
          Nothing -> Left ("subject_not_definition_topic", edge)
          Just topic ->
            let canonicalRelation = normalizeAtom relation
                canonicalObject = normalizeAtom object
            in Right
              ( (topic, canonicalRelation, canonicalObject, namespace, session, owner)
              , (topic, topic, canonicalRelation, canonicalObject, confidence, S.singleton edgeId, namespace, session, owner)
              )
    combine (topic, subject, relation, object, confidence, edgeIds, namespace, session, owner)
      (_, _, _, _, nextConfidence, nextEdgeIds, _, _, _) =
      (topic, subject, relation, object, max confidence nextConfidence, S.union edgeIds nextEdgeIds, namespace, session, owner)
    combineSupport (requestIds, responseHashes) (nextRequests, nextResponses) =
      (S.union requestIds nextRequests, S.union responseHashes nextResponses)

runPromotionGates :: QxFx0DB -> Text -> IO Int
runPromotionGates db snapshotId = do
  ensurePromotionSchema db
  now <- getCurrentTime
  gateRunId <- pure ("gate-" <> T.pack (show (utcMicros now)))
  result <- withDB (qdbPath db) $ \conn -> withTransaction conn $ do
    candidates <- loadCandidates conn snapshotId
    provenanceOk <- snapshotHasRuntimeProvenance conn snapshotId
    historicalOverlayFacts <- loadHistoricalOverlayRelations conn
    snapshotChecksum <- loadSnapshotChecksum conn snapshotId
    ensureGatePolicy conn now
    insertGateRunLineage conn gateRunId snapshotId snapshotChecksum now
    let curatedFacts = curatedCanonicalRelations
    results <- mapM (gateCandidate provenanceOk curatedFacts historicalOverlayFacts conn gateRunId now) candidates
    pure (length (filter id results))
  either throwPromotionError pure result
  where
    gateCandidate provenanceOk curatedFacts historicalOverlayFacts conn gateRunId now c = do
      let candidateFact = canonicalCandidateRelation c
          informativeness = evaluateCandidateInformativeness c
          (selfHistory, externalHistory) = partition (isSelfRevalidation c) historicalOverlayFacts
          curatedDuplicate = any (== candidateFact) curatedFacts
          curatedSubsumption = any (`strictlySubsumes` candidateFact) curatedFacts
          historicalDuplicate = any ((== candidateFact) . horRelation) externalHistory
          historicalSubsumption = any ((`strictlySubsumes` candidateFact) . horRelation) externalHistory
          selfRevalidationDetail
            | null selfHistory = "no_self_record"
            | otherwise = "idempotent_self_record_ignored"
      let checks =
            [ ("type", relationAllowed (pcRelationType c), "relation_not_allowed", "relation type must be promotion-allowed")
            , ("normalization", normalizedCandidate c, "normalization_failed", "topic and triple terms are normalized")
            , ("support", pcSupportCount c >= 2 || curatedDuplicate, "insufficient_support", "two independent observations or an exact curated canonical triple")
            , ("provenance", provenanceOk, "missing_provenance", "snapshot includes runtime_llm provenance")
            , ("topic_authority", trustedPromotionTopic c, "topic_not_in_definition_corpus", "subject is a seed definition topic")
            , ("contradiction", not (contradictoryRelation (pcRelationType c)), "contradiction", "negative runtime relations cannot promote")
            , ("confidence", pcConfidence c >= 0.2, "low_confidence", "candidate confidence meets policy floor")
            , ("curated_canonical_duplicate", not curatedDuplicate, "curated_relation_duplicate", "canonical triple is absent from curated relations")
            , ("curated_canonical_subsumption", not curatedSubsumption, "curated_relation_subsumes_candidate", "curated relation does not subsume candidate")
            , ("historical_overlay_self_revalidation", True, "ok", selfRevalidationDetail)
            , ("historical_overlay_duplicate", not historicalDuplicate, "historical_overlay_duplicate", "external historical overlay has no exact canonical triple")
             , ("historical_overlay_subsumption", not historicalSubsumption, "historical_overlay_subsumes_candidate", "external historical overlay does not subsume candidate")
             , ("informativeness", irPassed informativeness, informativenessReason informativeness, informativenessDetail informativeness)
             ]
          passed = all (\(_, ok, _, _) -> ok) checks
          status = if passed then "eligible_for_draft" else "rejected"
      forM_ checks $ \(name, ok, reason, detail) ->
        insertGate conn promotionGatePolicyVersion (pcCandidateId c) gateRunId name (if ok then "pass" else "fail")
          (if ok then 1 else 0) (if ok then "ok" else reason) detail now
      updateCandidateStatus conn (pcCandidateId c) status
      pure passed
      where
        informativenessReason result
          | not (irNotTautological result) = "tautological_candidate"
          | not (irNotTopicParaphrase result) = "topic_paraphrase"
          | not (irAddsNovelInformation result) = "no_novel_object_relation_or_constraint"
          | otherwise = "semantic_gain_below_threshold"
        informativenessDetail result =
          "not_tautological=" <> boolText (irNotTautological result)
            <> ";adds_novel_information=" <> boolText (irAddsNovelInformation result)
            <> ";not_topic_paraphrase=" <> boolText (irNotTopicParaphrase result)
            <> ";semantic_gain=" <> T.pack (show (irSemanticGain result))

evaluateCandidateInformativeness :: PromotionCandidate -> InformativenessResult
evaluateCandidateInformativeness candidate =
  let topic = normalizeAtom (pcTopic candidate)
      subject = normalizeAtom (pcSubject candidate)
      relation = normalizeAtom (pcRelationType candidate)
      object = normalizeAtom (pcObject candidate)
      candidateAtoms = S.fromList [subject, relation, object]
      basePredicates = maybe [] dcPredicates (M.lookup topic definitionCorpus)
      baseAtomSets = map (contentAtoms . spRu) basePredicates
      baseAtoms = S.unions baseAtomSets
      maxOverlap = maximum (0.0 : [jaccard candidateAtoms atoms | atoms <- baseAtomSets])
      semanticGain = 1.0 - maxOverlap
      newObject = object `S.notMember` baseAtoms
      constraint = relation `elem`
        [ "requires", "limited_by", "contrasts_with", "presupposes", "causes" ]
      newRelation = relation `S.notMember` baseAtoms
      addsNovel = newObject || constraint || (newRelation && semanticGain >= informativenessSemanticGainThreshold)
      notTautological = not (T.null subject) && not (T.null relation)
        && not (T.null object) && subject /= object
      notTopicParaphrase = notTautological
        && object /= topic
        && normalizeAtom (pcRenderedRu candidate) /= topic
      passed = notTautological && notTopicParaphrase && addsNovel
        && semanticGain >= informativenessSemanticGainThreshold
  in InformativenessResult notTautological addsNovel notTopicParaphrase semanticGain passed
  where
    contentAtoms text = S.fromList
      [ atom
      | word <- T.words (T.toLower text)
      , let atom = normalizeAtom word
      , T.length atom > 3
      , atom `notElem` stopWords
      ]
    jaccard left right =
      let intersection = S.size (S.intersection left right)
          union = S.size (S.union left right)
      in if union == 0 then 0.0 else fromIntegral intersection / fromIntegral union
    stopWords = ["это", "что", "как", "для", "или", "при", "через", "между", "перед", "после"]

boolText :: Bool -> Text
boolText True = "true"
boolText False = "false"

createDraftOverlay :: QxFx0DB -> Text -> IO Text
createDraftOverlay db snapshotId = do
  ensurePromotionSchema db
  now <- getCurrentTime
  result <- withDB (qdbPath db) $ \conn -> withTransaction conn $ do
    candidates <- loadEligibleCandidates conn snapshotId
    gateLineage <- loadLatestGateRunLineage conn snapshotId
    snapshotChecksum <- loadSnapshotChecksum conn snapshotId
    let (gateRunId, policyVersion, policyChecksum) = gateLineage
        predicateChecksum = candidatePredicateChecksum candidates
        checksum = promotionOverlayChecksum snapshotId snapshotChecksum gateRunId
          policyVersion policyChecksum predicateChecksum
        overlayVersion = "overlay-" <> checksum
    parent <- loadActiveVersion conn
    exists <- overlayExists conn overlayVersion
    unless exists $ do
      insertOverlay conn overlayVersion parent snapshotId now checksum
      insertOverlayLineage conn overlayVersion snapshotId snapshotChecksum predicateChecksum
        gateRunId policyVersion policyChecksum now
      forM_ candidates $ \candidate -> insertOverlayPredicate conn overlayVersion candidate
    pure overlayVersion
  either throwPromotionError pure result

activatePromotionOverlay :: QxFx0DB -> Text -> IO ()
activatePromotionOverlay db overlayVersion = do
  ensurePromotionSchema db
  now <- getCurrentTime
  result <- withDB (qdbPath db) $ \conn -> withTransaction conn $ do
    status <- loadOverlayStatus conn overlayVersion
    unless (status `elem` [Just "evaluated", Just "active"])
      (throwPromotionError "overlay must have a passing evaluation before activation")
    lineageValid <- overlayLineageArtifactsValid conn overlayVersion
    unless lineageValid (throwPromotionError "overlay lineage is not a complete current-policy governed artifact chain")
    runtimeEvaluationId <- loadCurrentReleasedEvaluation conn overlayVersion
      >>= maybe (throwPromotionError "latest corpus/runtime evaluation and its human release are required before activation") pure
    current <- loadActivePointerAllowLegacy conn
    parent <- loadParentVersion conn overlayVersion
    case current of
      Just (currentVersion, _) | currentVersion == overlayVersion -> do
        -- Explicit re-activation only advances the evaluation binding. It must
        -- not overwrite the state to which the original activation rolls back.
        updateOverlayActive conn overlayVersion now
        upsertActive conn (Just overlayVersion) (Just runtimeEvaluationId) now
      _ -> do
        unless (fmap fst current == parent)
          (throwPromotionError "overlay parent does not match the current active overlay")
        priorEvaluation <- case current of
          Nothing -> pure Nothing
          Just (currentVersion, Just evaluationId) -> do
            priorValid <- loadReleasedEvaluationById conn currentVersion evaluationId
            unless priorValid (throwPromotionError "current active overlay is not bound to a valid released evaluation")
            pure (Just evaluationId)
          Just (_, Nothing) ->
            throwPromotionError "current active overlay has no evaluation binding"
        setOverlayPriorEvaluation conn overlayVersion priorEvaluation
        execOrFail conn "UPDATE promotion_overlays SET status='superseded' WHERE status='active'"
        updateOverlayActive conn overlayVersion now
        upsertActive conn (Just overlayVersion) (Just runtimeEvaluationId) now
    pure ()
  either throwPromotionError pure result

-- | Record explicit human release of the latest current-version passing
-- runtime evaluation. This is append-only and deliberately does not activate
-- the overlay.
recordPromotionHumanRelease :: QxFx0DB -> Text -> Text -> IO Text
recordPromotionHumanRelease db overlayVersion details = do
  ensurePromotionSchema db
  now <- getCurrentTime
  result <- withDB (qdbPath db) $ \conn -> withTransaction conn $ do
    artifactValid <- overlayArtifactValid conn overlayVersion
    unless artifactValid (throwPromotionError "cannot release an invalid promotion overlay artifact")
    evaluationId <- loadLatestCurrentPassingEvaluation conn overlayVersion
      >>= maybe (throwPromotionError "latest corpus/runtime evaluation is not a current-version pass") pure
    insertHumanRelease conn overlayVersion evaluationId now details
    pure evaluationId
  either throwPromotionError pure result

rollbackPromotionOverlay :: QxFx0DB -> IO ()
rollbackPromotionOverlay db = do
  ensurePromotionSchema db
  now <- getCurrentTime
  result <- withDB (qdbPath db) $ \conn -> withTransaction conn $ do
    current <- loadActiveVersion conn
    currentVersion <- maybe (throwPromotionError "no active promotion overlay to roll back") pure current
    currentStatus <- loadOverlayStatus conn currentVersion
    unless (currentStatus == Just "active")
      (throwPromotionError "active promotion pointer does not reference an active overlay")
    parent <- loadParentVersion conn currentVersion
    priorEvaluation <- loadPriorRuntimeEvaluation conn currentVersion
    execOrFail conn "UPDATE promotion_overlays SET status='superseded' WHERE status='active'"
    case parent of
      Nothing -> upsertActive conn Nothing Nothing now
      Just parentVersion -> do
        runtimeEvaluationId <- maybe
          (throwPromotionError "active overlay does not record the immediately prior evaluation")
          pure priorEvaluation
        lineageValid <- overlayLineageArtifactsValid conn parentVersion
        unless lineageValid (throwPromotionError "parent overlay lineage is not a valid governed artifact chain")
        evaluationValid <- loadReleasedEvaluationById conn parentVersion runtimeEvaluationId
        unless evaluationValid
          (throwPromotionError "immediately prior overlay evaluation is no longer a valid released evaluation")
        updateOverlayActive conn parentVersion now
        upsertActive conn (Just parentVersion) (Just runtimeEvaluationId) now
  either throwPromotionError pure result

loadActivePromotionOverlay :: QxFx0DB -> IO (Maybe (CuratedOverlayRuntime, Map Text DefinitionContent))
loadActivePromotionOverlay db = do
  ensurePromotionSchema db
  result <- withDB (qdbPath db) $ \conn -> withReadTransaction conn $ do
    activePointer <- loadActivePointer conn
    case activePointer of
      Nothing -> pure Nothing
      Just (version, boundEvaluationId) -> do
        activeStatus <- ((== Just "active") <$> loadOverlayStatus conn version)
        lineageValid <- overlayLineageArtifactsValid conn version
        evaluationBound <- loadReleasedEvaluationById conn version boundEvaluationId
        if not (activeStatus && lineageValid && evaluationBound)
          then pure Nothing
          else do
            rows <- loadOverlayPredicatesWithIdsLineage conn version
            let predicateIdsBySurface = M.fromList
                  [ (T.toLower (T.strip ru), predicateId)
                  | (predicateId, _topic, _role, ru, _subject, _relation, _object, _confidence) <- rows
                  ]
                corpus = M.mapWithKey (\topic predicates -> DefinitionContent topic predicates)
                  (M.fromListWith (++) (map toPredicate rows))
            pure (Just (CuratedOverlayRuntime version predicateIdsBySurface, corpus))
  either throwPromotionError pure result
  where
    toPredicate (_predicateId, topic, role, ru, subject, relation, object, _confidence) =
      ( topic
       , [SemanticPredicate role ru "" (normalizeAtom subject)
            (Just (CanonicalPredicateRelation (normalizeAtom subject) (normalizeAtom relation) (normalizeAtom object)))
            Nothing Nothing Nothing]
      )

loadActivePromotionCorpus :: QxFx0DB -> IO (Map Text DefinitionContent)
loadActivePromotionCorpus db = do
  active <- loadActivePromotionOverlay db
  pure (maybe M.empty snd active)

-- | Render canonical overlay relations only after bootstrap has loaded local
-- morphology. Canonical atoms remain the selector input; the Russian surface
-- is a presentation artifact.
renderPromotionCorpus :: MorphologyData -> Map Text DefinitionContent -> Map Text DefinitionContent
renderPromotionCorpus morphology = M.map renderContent
  where
    renderContent content = content
      { dcPredicates = map renderPredicate (dcPredicates content) }

    renderPredicate predicate =
      case spCanonicalRelation predicate of
        Nothing -> predicate
        Just relation -> predicate { spRu = renderRelation morphology relation }

renderPromotionOverlay
  :: MorphologyData
  -> CuratedOverlayRuntime
  -> Map Text DefinitionContent
  -> (CuratedOverlayRuntime, Map Text DefinitionContent)
renderPromotionOverlay morphology runtime corpus =
  let renderedCorpus = renderPromotionCorpus morphology corpus
      renderedIds = M.fromList
        [ (normalizeSurface (spRu renderedPredicate), predicateId)
        | (topic, rawContent) <- M.toList corpus
        , renderedContent <- maybeToList (M.lookup topic renderedCorpus)
        , (rawPredicate, renderedPredicate) <- zip (dcPredicates rawContent) (dcPredicates renderedContent)
        , Just _ <- [spCanonicalRelation rawPredicate]
        , Just predicateId <- [M.lookup (normalizeSurface (spRu rawPredicate)) (corPredicateIdsBySurface runtime)]
        ]
      renderedRuntime = runtime
        { corPredicateIdsBySurface = M.union renderedIds (corPredicateIdsBySurface runtime) }
  in (renderedRuntime, renderedCorpus)
  where
    maybeToList Nothing = []
    maybeToList (Just value) = [value]
    normalizeSurface = T.toLower . T.strip

renderRelation :: MorphologyData -> CanonicalPredicateRelation -> Text
renderRelation morphology relation =
  let subject = cprSubject relation
      object = cprObject relation
      relationType = cprRelation relation
  in case relationType of
       "related_to" -> subject <> " связана с " <> overlayInstrumental morphology object
       "presupposes" -> subject <> " предполагает " <> object
       "requires" -> subject <> " требует " <> object
       "causes" -> subject <> " вызывает " <> object
       "contrasts_with" -> subject <> " контрастирует с " <> overlayInstrumental morphology object
       "limited_by" -> subject <> " ограничена " <> overlayInstrumental morphology object
       _ -> subject <> " " <> relationType <> " " <> object

overlayInstrumental :: MorphologyData -> Text -> Text
overlayInstrumental morphology object =
  let rendered = instrumentalForm morphology object
  in if T.isSuffixOf "ое" object
       then T.dropEnd 2 object <> "ым"
       else if T.isSuffixOf "ее" object
         then T.dropEnd 2 object <> "им"
         else if rendered /= object
           then rendered
           else object

runPromotionEvaluation :: QxFx0DB -> Text -> IO PromotionEvaluation
runPromotionEvaluation db overlayVersion = do
  ensurePromotionSchema db
  now <- getCurrentTime
  let evaluationId = "eval-" <> T.pack (show (utcMicros now))
  result <- withDB (qdbPath db) $ \conn -> withTransaction conn $ do
    artifactValid <- overlayArtifactValid conn overlayVersion
    unless artifactValid (throwPromotionError "promotion corpus evaluation requires a valid immutable overlay artifact")
    overlayChecksum <- loadOverlayChecksum conn overlayVersion
    overlayRows <- loadOverlayPredicates conn overlayVersion
    parent <- loadParentVersion conn overlayVersion
    parentRows <- maybe (pure []) (loadOverlayPredicatesLineage conn) parent
    let parentCorpus = rowsToCorpus parentRows
        overlayCorpus = rowsToCorpus overlayRows
        baselineCorpus = M.unionWith mergeOverlayTopic definitionCorpus parentCorpus
        candidateCorpus = M.unionWith mergeOverlayTopic baselineCorpus overlayCorpus
        topics = sort (S.toList (S.fromList (M.keys baselineCorpus ++ M.keys overlayCorpus)))
        baselineContentful = length [topic | topic <- topics, topicHasContent baselineCorpus topic]
        candidateContentful = length [topic | topic <- topics, topicHasContent candidateCorpus topic]
        baselineRefusals = length topics - baselineContentful
        candidateRefusals = length topics - candidateContentful
        candidateConflicts = length [() | (_, _, _, _, relation, _, _) <- overlayRows, contradictoryRelation relation]
        passed = candidateConflicts == 0 && candidateContentful >= baselineContentful
    execInsertEvaluation conn evaluationId overlayVersion now overlayChecksum passed
      baselineContentful candidateContentful 0 candidateConflicts baselineRefusals candidateRefusals
    forM_ topics $ \topic -> do
      let baselineHas = topicHasContent baselineCorpus topic
          candidateHas = topicHasContent candidateCorpus topic
      insertEvaluationCase conn evaluationId topic baselineHas candidateHas False (contradictoryTopic overlayRows topic) "corpus_precheck"
    when passed $
      markOverlayEvaluated conn overlayVersion
    pure (PromotionEvaluation evaluationId baselineContentful candidateContentful 0 candidateConflicts baselineRefusals candidateRefusals)
  either throwPromotionError pure result
  where
    rowsToCorpus rows = M.mapWithKey (\topic predicates -> DefinitionContent topic predicates)
      (M.fromListWith (++) (map overlayEvalPredicate rows))
    overlayEvalPredicate (topic, role, ru, subject, relation, object, confidence) =
      (topic, [SemanticPredicate role ru "" (normalizeAtom subject)
        (Just (CanonicalPredicateRelation (normalizeAtom subject) (normalizeAtom relation) (normalizeAtom object)))
        Nothing Nothing Nothing])
    mergeOverlayTopic base overlay = base { dcPredicates = dcPredicates base ++ dcPredicates overlay }
    topicHasContent corpus topic =
      case M.lookup topic corpus of
        Just content -> length (dcPredicates content) >= 2
        Nothing -> False
    contradictoryTopic rows topic = any (\(t, _, _, _, relation, _, _) -> t == topic && contradictoryRelation relation) rows

-- SQL and conversion helpers -------------------------------------------------

type RuntimeEdgeRow = (Int64, Text, Text, Maybe Text, Double, Int, Text, Text, Maybe Text, Text)
type SnapshotEdgeRow = (Int64, Text, Text, Maybe Text, Double, Text, Text, Maybe Text, Text, UTCTime)

edgeId :: RuntimeEdgeRow -> Int64
edgeId (eid, _, _, _, _, _, _, _, _, _) = eid

snapshotEdgeId :: SnapshotEdgeRow -> Int64
snapshotEdgeId (eid, _, _, _, _, _, _, _, _, _) = eid

withTransaction :: NSQL.Database -> IO a -> IO a
withTransaction conn action = do
  begun <- NSQL.execSql conn "BEGIN IMMEDIATE;"
  either throwPromotionError pure begun
  value <- action `onException` rollback conn
  committed <- NSQL.execSql conn "COMMIT;"
  case committed of
    Right () -> pure value
    Left err -> rollback conn >> throwPromotionError err

withReadTransaction :: NSQL.Database -> IO a -> IO a
withReadTransaction conn action = do
  begun <- NSQL.execSql conn "BEGIN;"
  either throwPromotionError pure begun
  value <- action `onException` rollback conn
  committed <- NSQL.execSql conn "COMMIT;"
  case committed of
    Right () -> pure value
    Left err -> rollback conn >> throwPromotionError err

rollback :: NSQL.Database -> IO ()
rollback conn = do
  _ <- NSQL.execSql conn "ROLLBACK;"
  pure ()

execOrFail :: NSQL.Database -> Text -> IO ()
execOrFail conn sql = do
  result <- NSQL.execSql conn sql
  either throwPromotionError pure result

loadRuntimeEdges :: NSQL.Database -> IO [RuntimeEdgeRow]
loadRuntimeEdges conn = do
  prepared <- NSQL.prepare conn "SELECT id, edge_from, edge_to, relation_type, confidence, co_occurrence, provenance, namespace, session_id, owner FROM semantic_edges_runtime WHERE provenance = 'runtime_llm' ORDER BY id ASC"
  case prepared of
    Left err -> throwPromotionError err
    Right stmt -> collect stmt []
  where
    collect stmt acc = do
      hasRow <- NSQL.stepRow stmt
      if not hasRow
        then NSQL.finalize stmt >> pure (reverse acc)
        else do
          row <- (,,,,,,,,,) <$> NSQL.columnInt64 stmt 0 <*> NSQL.columnText stmt 1 <*> NSQL.columnText stmt 2 <*> maybeText stmt 3 <*> NSQL.columnDouble stmt 4 <*> NSQL.columnInt stmt 5 <*> NSQL.columnText stmt 6 <*> NSQL.columnText stmt 7 <*> maybeText stmt 8 <*> NSQL.columnText stmt 9
          collect stmt (row : acc)

loadSnapshotEdges :: NSQL.Database -> Text -> IO [SnapshotEdgeRow]
loadSnapshotEdges conn snapshotId = do
  prepared <- NSQL.prepare conn "SELECT edge_id, edge_from, edge_to, relation_type, confidence, provenance, namespace, session_id, owner, captured_at FROM promotion_snapshot_edges WHERE snapshot_id = ? ORDER BY edge_id ASC"
  case prepared of
    Left err -> throwPromotionError err
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 snapshotId
      collectSnapshot stmt []
  where
    collectSnapshot stmt acc = do
      hasRow <- NSQL.stepRow stmt
      if not hasRow
        then NSQL.finalize stmt >> pure (reverse acc)
        else do
          row <- (,,,,,,,,,) <$> NSQL.columnInt64 stmt 0 <*> NSQL.columnText stmt 1 <*> NSQL.columnText stmt 2 <*> maybeText stmt 3 <*> NSQL.columnDouble stmt 4 <*> NSQL.columnText stmt 5 <*> NSQL.columnText stmt 6 <*> maybeText stmt 7 <*> NSQL.columnText stmt 8 <*> (microsToUtc <$> NSQL.columnInt64 stmt 9)
          collectSnapshot stmt (row : acc)

-- | Snapshot lineage is copied only from governed edge-admission events.  The
-- relation marker is emitted with the event, so an endpoint pair with several
-- relation types cannot borrow evidence from a different triple.
captureSnapshotEdgeLineage :: NSQL.Database -> Text -> IO ()
captureSnapshotEdgeLineage conn snapshotId = do
  eventsAvailable <- tableExists conn "learning_events"
  when eventsAvailable $ do
    stmt <- prepareTx conn "promotion_snapshot_edge_lineage_capture"
       "INSERT OR IGNORE INTO promotion_snapshot_edge_lineage(snapshot_id, edge_id, request_id, prompt_hash, response_hash, evidence_source, model, parser_decision, admission_decision, event_timestamp, namespace, session_id, owner) SELECT ?, e.edge_id, le.request_id, le.prompt_hash, le.response_hash, le.evidence_source, le.model, le.parser_decision, le.admission_decision, le.ts, e.namespace, e.session_id, e.owner FROM promotion_snapshot_edges e JOIN learning_events le ON le.kind IN ('edge_admitted', 'edge_corroborated') AND le.provenance = 'runtime_llm' AND le.edge_from = e.edge_from AND le.edge_to = e.edge_to AND COALESCE(le.edge_namespace, CASE WHEN le.session_id IS NULL THEN 'global' ELSE 'session_local' END)=e.namespace AND COALESCE(le.edge_owner, CASE WHEN le.session_id IS NULL THEN 'legacy_global' ELSE le.session_id END)=e.owner AND (e.namespace='global' OR COALESCE(le.session_id, '')=COALESCE(e.session_id, '')) WHERE e.snapshot_id = ? AND le.request_id <> '' AND le.prompt_hash IS NOT NULL AND le.response_hash IS NOT NULL AND le.model IS NOT NULL AND lower(le.model) <> 'mock' AND le.parser_decision IS NOT NULL AND le.admission_decision IN ('runtime_admitted', 'runtime_corroborated') AND le.evidence_source IS NOT NULL AND instr(COALESCE(le.reason, ''), 'relation_type=' || COALESCE(e.relation_type, '')) > 0 AND EXISTS (SELECT 1 FROM learning_apply_proofs ap WHERE ap.request_id=le.request_id AND ap.dispatch_token<>'' AND ((ap.source_kind='broad' AND ap.policy=?) OR (ap.source_kind='corroboration' AND ap.policy=?)))"
    bindTextOrFail stmt 1 snapshotId
    bindTextOrFail stmt 2 snapshotId
    bindTextOrFail stmt 3 currentLearningPolicyVersion
    bindTextOrFail stmt 4 currentCorroborationPolicyVersion
    stepOrFail stmt

-- | Repeated parsing of the same provider request is one observation. A
-- candidate's support count is the number of distinct request ids, each of
-- which must carry both prompt and response hashes in the snapshot lineage.
loadSnapshotIndependentSupport :: NSQL.Database -> Text -> IO (Map Int64 (Set Text, Set Text))
loadSnapshotIndependentSupport conn snapshotId = do
  prepared <- NSQL.prepare conn
    "SELECT edge_id, request_id, response_hash FROM promotion_snapshot_edge_lineage WHERE snapshot_id = ? AND request_id <> '' AND prompt_hash <> '' AND response_hash <> '' AND model <> '' AND lower(model) <> 'mock' AND parser_decision <> '' AND admission_decision IN ('runtime_admitted', 'runtime_corroborated') AND evidence_source <> '' AND event_timestamp IS NOT NULL"
  case prepared of
    Left err -> throwPromotionError err
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 snapshotId
      collect stmt M.empty
  where
    collect stmt support = do
      hasRow <- NSQL.stepRow stmt
      if not hasRow
        then NSQL.finalize stmt >> pure support
        else do
          edgeId <- NSQL.columnInt64 stmt 0
          requestId <- NSQL.columnText stmt 1
          responseHash <- NSQL.columnText stmt 2
          let prior = M.findWithDefault (S.empty, S.empty) edgeId support
              next = (S.insert requestId (fst prior), S.insert responseHash (snd prior))
          collect stmt (M.insert edgeId next support)

insertCandidateExclusion :: NSQL.Database -> Text -> SnapshotEdgeRow -> Text -> UTCTime -> IO ()
insertCandidateExclusion conn snapshotId (edgeId, edgeFrom, edgeTo, relation, _confidence, _provenance, _namespace, _session, _owner, _captured) reason now = do
  stmt <- prepareTx conn "promotion_candidate_exclusion_insert"
    "INSERT OR IGNORE INTO promotion_candidate_exclusions(snapshot_id, edge_id, edge_from, edge_to, relation_type, reason_code, created_at) VALUES(?, ?, ?, ?, ?, ?, ?)"
  bindTextOrFail stmt 1 snapshotId
  bindInt64OrFail stmt 2 edgeId
  bindTextOrFail stmt 3 edgeFrom
  bindTextOrFail stmt 4 edgeTo
  bindMaybeText stmt 5 relation
  bindTextOrFail stmt 6 reason
  bindInt64OrFail stmt 7 (utcMicros now)
  stepOrFail stmt

tableExists :: NSQL.Database -> Text -> IO Bool
tableExists conn name = do
  prepared <- NSQL.prepare conn "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1"
  case prepared of
    Left err -> throwPromotionError err
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 name
      exists <- NSQL.stepRow stmt
      NSQL.finalize stmt
      pure exists

learningEvidenceColumnsAvailable :: NSQL.Database -> IO Bool
learningEvidenceColumnsAvailable conn = do
  let required = ["model", "parser_decision", "admission_decision", "evidence_source"]
  results <- mapM (columnExists conn "learning_events") required
  pure (and results)

columnExists :: NSQL.Database -> Text -> Text -> IO Bool
columnExists conn tableName columnName = do
  prepared <- NSQL.prepare conn
    ("SELECT 1 FROM pragma_table_info('" <> T.replace "'" "''" tableName
      <> "') WHERE name = '" <> T.replace "'" "''" columnName <> "' LIMIT 1")
  case prepared of
    Left err -> throwPromotionError err
    Right stmt -> do
      exists <- NSQL.stepRow stmt
      NSQL.finalize stmt
      pure exists

-- The TxStatement API is deliberately used for writes; native bind is needed
-- for read statements because it avoids opening a transaction wrapper.
maybeText :: NSQL.Statement -> Int -> IO (Maybe Text)
maybeText stmt ix = do
  let column = fromIntegral ix
  nullValue <- NSQL.columnIsNull stmt column
  if nullValue then pure Nothing else Just <$> NSQL.columnText stmt column

insertSnapshot :: NSQL.Database -> Text -> UTCTime -> Int -> Text -> IO ()
insertSnapshot conn sid now count checksum = do
  stmt <- prepareTx conn "promotion_snapshot_insert" "INSERT OR REPLACE INTO promotion_snapshots(snapshot_id, created_at, edge_count, checksum, status) VALUES(?, ?, ?, ?, 'created')"
  bindTextOrFail stmt 1 sid
  bindInt64OrFail stmt 2 (utcMicros now)
  bindInt64OrFail stmt 3 (fromIntegral count)
  bindTextOrFail stmt 4 checksum
  stepOrFail stmt

insertSnapshotEdge :: NSQL.Database -> Text -> Int64 -> Text -> Text -> Maybe Text -> Double -> Text -> Text -> Maybe Text -> Text -> UTCTime -> IO ()
insertSnapshotEdge conn sid eid ef et rel confidence prov namespace session owner captured = do
  stmt <- prepareTx conn "promotion_snapshot_edge_insert" "INSERT OR REPLACE INTO promotion_snapshot_edges(snapshot_id, edge_id, edge_from, edge_to, relation_type, confidence, provenance, namespace, session_id, owner, captured_at) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
  bindTextOrFail stmt 1 sid
  bindInt64OrFail stmt 2 eid
  bindTextOrFail stmt 3 ef
  bindTextOrFail stmt 4 et
  bindMaybeText stmt 5 rel
  bindDoubleOrFail stmt 6 confidence
  bindTextOrFail stmt 7 prov
  bindTextOrFail stmt 8 namespace
  bindMaybeText stmt 9 session
  bindTextOrFail stmt 10 owner
  bindInt64OrFail stmt 11 (utcMicros captured)
  stepOrFail stmt

insertCandidate :: NSQL.Database -> Text -> Text -> Text -> Text -> Text -> Text -> Text -> Double -> Int -> IO ()
insertCandidate conn cid sid topic subject relation object rendered confidence support = do
  stmt <- prepareTx conn "promotion_candidate_insert" "INSERT INTO promotion_candidates(candidate_id, snapshot_id, topic, subject_atom, relation_type, object_atom, rendered_ru, confidence_raw, support_count, lifecycle_status, canonical_hash, created_at) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, 'discovered', ?, ?) ON CONFLICT(candidate_id) DO UPDATE SET topic=excluded.topic, subject_atom=excluded.subject_atom, relation_type=excluded.relation_type, object_atom=excluded.object_atom, rendered_ru=excluded.rendered_ru, confidence_raw=excluded.confidence_raw, support_count=excluded.support_count, lifecycle_status=excluded.lifecycle_status, canonical_hash=excluded.canonical_hash"
  now <- getCurrentTime
  bindTextOrFail stmt 1 cid
  bindTextOrFail stmt 2 sid
  bindTextOrFail stmt 3 topic
  bindTextOrFail stmt 4 subject
  bindTextOrFail stmt 5 relation
  bindTextOrFail stmt 6 object
  bindTextOrFail stmt 7 rendered
  bindDoubleOrFail stmt 8 confidence
  bindInt64OrFail stmt 9 (fromIntegral support)
  bindTextOrFail stmt 10 cid
  bindInt64OrFail stmt 11 (utcMicros now)
  stepOrFail stmt

-- | A rebuild of an existing immutable snapshot must recompute support from
-- its captured request/response lineage. Keeping a prior count here would let
-- an earlier gate result masquerade as fresh evidence during self-revalidation.
resetSnapshotCandidateEvidence :: NSQL.Database -> Text -> IO ()
resetSnapshotCandidateEvidence conn snapshotId = do
  stmt <- prepareTx conn "promotion_candidate_reset_snapshot_evidence"
    "UPDATE promotion_candidates SET support_count=0, lifecycle_status='discovered' WHERE snapshot_id = ?"
  bindTextOrFail stmt 1 snapshotId
  stepOrFail stmt

ensureGatePolicy :: NSQL.Database -> UTCTime -> IO ()
ensureGatePolicy conn now = do
  stmt <- prepareTx conn "promotion_gate_policy_insert"
    "INSERT OR IGNORE INTO promotion_gate_policies(policy_version, policy_checksum, description, created_at) VALUES(?, ?, ?, ?)"
  bindTextOrFail stmt 1 promotionGatePolicyVersion
  bindTextOrFail stmt 2 promotionGatePolicyChecksum
  bindTextOrFail stmt 3 promotionGatePolicyDescription
  bindInt64OrFail stmt 4 (utcMicros now)
  stepOrFail stmt

insertGateRunLineage :: NSQL.Database -> Text -> Text -> Text -> UTCTime -> IO ()
insertGateRunLineage conn gateRunId snapshotId snapshotChecksum now = do
  stmt <- prepareTx conn "promotion_gate_run_lineage_insert"
    "INSERT INTO promotion_gate_run_lineage(gate_run_id, snapshot_id, policy_version, policy_checksum, snapshot_checksum, created_at) VALUES(?, ?, ?, ?, ?, ?)"
  bindTextOrFail stmt 1 gateRunId
  bindTextOrFail stmt 2 snapshotId
  bindTextOrFail stmt 3 promotionGatePolicyVersion
  bindTextOrFail stmt 4 promotionGatePolicyChecksum
  bindTextOrFail stmt 5 snapshotChecksum
  bindInt64OrFail stmt 6 (utcMicros now)
  stepOrFail stmt

loadSnapshotChecksum :: NSQL.Database -> Text -> IO Text
loadSnapshotChecksum conn snapshotId = do
  prepared <- NSQL.prepare conn "SELECT checksum FROM promotion_snapshots WHERE snapshot_id = ?"
  case prepared of
    Left err -> throwPromotionError err
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 snapshotId
      hasRow <- NSQL.stepRow stmt
      checksum <- if hasRow
        then NSQL.columnText stmt 0
        else throwPromotionError ("promotion snapshot not found: " <> snapshotId)
      NSQL.finalize stmt
      pure checksum

loadLatestGateRunLineage :: NSQL.Database -> Text -> IO (Text, Text, Text)
loadLatestGateRunLineage conn snapshotId = do
  prepared <- NSQL.prepare conn
    "SELECT gate_run_id, policy_version, policy_checksum FROM promotion_gate_run_lineage WHERE snapshot_id = ? ORDER BY created_at DESC, gate_run_id DESC LIMIT 1"
  case prepared of
    Left err -> throwPromotionError err
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 snapshotId
      hasRow <- NSQL.stepRow stmt
      lineage <- if hasRow
        then (,,) <$> NSQL.columnText stmt 0 <*> NSQL.columnText stmt 1 <*> NSQL.columnText stmt 2
        else throwPromotionError ("promotion draft requires a gate run for snapshot: " <> snapshotId)
      NSQL.finalize stmt
      pure lineage

insertGate :: NSQL.Database -> Text -> Text -> Text -> Text -> Text -> Double -> Text -> Text -> UTCTime -> IO ()
insertGate conn policyVersion cid runId name decision score reason detail now = do
  stmt <- prepareTx conn "promotion_gate_insert" "INSERT OR REPLACE INTO promotion_gate_runs(candidate_id, gate_run_id, gate_name, gate_version, decision, score, reason_code, detail, evaluated_at) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)"
  bindTextOrFail stmt 1 cid
  bindTextOrFail stmt 2 runId
  bindTextOrFail stmt 3 name
  bindTextOrFail stmt 4 policyVersion
  bindTextOrFail stmt 5 decision
  bindDoubleOrFail stmt 6 score
  bindTextOrFail stmt 7 reason
  bindTextOrFail stmt 8 detail
  bindInt64OrFail stmt 9 (utcMicros now)
  stepOrFail stmt

loadCandidates :: NSQL.Database -> Text -> IO [PromotionCandidate]
loadCandidates conn snapshotId = loadCandidateQuery conn "SELECT candidate_id, snapshot_id, topic, subject_atom, relation_type, object_atom, rendered_ru, confidence_raw, support_count, lifecycle_status FROM promotion_candidates WHERE snapshot_id = ?" snapshotId

loadEligibleCandidates :: NSQL.Database -> Text -> IO [PromotionCandidate]
loadEligibleCandidates conn snapshotId = loadCandidateQuery conn "SELECT candidate_id, snapshot_id, topic, subject_atom, relation_type, object_atom, rendered_ru, confidence_raw, support_count, lifecycle_status FROM promotion_candidates WHERE snapshot_id = ? AND lifecycle_status = 'eligible_for_draft'" snapshotId

loadCandidateQuery :: NSQL.Database -> Text -> Text -> IO [PromotionCandidate]
loadCandidateQuery conn sql snapshotId = do
  prepared <- NSQL.prepare conn sql
  case prepared of
    Left err -> throwPromotionError err
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 snapshotId
      collectCandidates stmt []
  where
    collectCandidates stmt acc = do
      hasRow <- NSQL.stepRow stmt
      if not hasRow
        then NSQL.finalize stmt >> pure (reverse acc)
        else do
          candidate <- PromotionCandidate
            <$> NSQL.columnText stmt 0 <*> NSQL.columnText stmt 1 <*> NSQL.columnText stmt 2
            <*> NSQL.columnText stmt 3 <*> NSQL.columnText stmt 4 <*> NSQL.columnText stmt 5
            <*> NSQL.columnText stmt 6 <*> NSQL.columnDouble stmt 7 <*> NSQL.columnInt stmt 8 <*> NSQL.columnText stmt 9
          collectCandidates stmt (candidate : acc)

updateCandidateStatus :: NSQL.Database -> Text -> Text -> IO ()
updateCandidateStatus conn cid status = do
  stmt <- prepareTx conn "promotion_candidate_status" "UPDATE promotion_candidates SET lifecycle_status = ? WHERE candidate_id = ?"
  bindTextOrFail stmt 1 status
  bindTextOrFail stmt 2 cid
  stepOrFail stmt

insertOverlay :: NSQL.Database -> Text -> Maybe Text -> Text -> UTCTime -> Text -> IO ()
insertOverlay conn version parent snapshotId now checksum = do
  stmt <- prepareTx conn "promotion_overlay_insert" "INSERT OR REPLACE INTO promotion_overlays(overlay_version, parent_version, snapshot_id, status, created_at, checksum) VALUES(?, ?, ?, 'draft', ?, ?)"
  bindTextOrFail stmt 1 version
  bindMaybeText stmt 2 parent
  bindTextOrFail stmt 3 snapshotId
  bindInt64OrFail stmt 4 (utcMicros now)
  bindTextOrFail stmt 5 checksum
  stepOrFail stmt

insertOverlayLineage :: NSQL.Database -> Text -> Text -> Text -> Text -> Text -> Text -> Text -> UTCTime -> IO ()
insertOverlayLineage conn overlayVersion snapshotId snapshotChecksum predicateChecksum gateRunId policyVersion policyChecksum now = do
  stmt <- prepareTx conn "promotion_overlay_lineage_insert"
    "INSERT INTO promotion_overlay_lineage(overlay_version, snapshot_id, snapshot_checksum, predicate_checksum, gate_run_id, policy_version, policy_checksum, created_at) VALUES(?, ?, ?, ?, ?, ?, ?, ?)"
  bindTextOrFail stmt 1 overlayVersion
  bindTextOrFail stmt 2 snapshotId
  bindTextOrFail stmt 3 snapshotChecksum
  bindTextOrFail stmt 4 predicateChecksum
  bindTextOrFail stmt 5 gateRunId
  bindTextOrFail stmt 6 policyVersion
  bindTextOrFail stmt 7 policyChecksum
  bindInt64OrFail stmt 8 (utcMicros now)
  stepOrFail stmt

insertOverlayPredicate :: NSQL.Database -> Text -> PromotionCandidate -> IO ()
insertOverlayPredicate conn version candidate = do
  stmt <- prepareTx conn "promotion_overlay_predicate_insert" "INSERT OR REPLACE INTO promotion_overlay_predicates(overlay_version, predicate_id, candidate_id, topic, predicate_role, predicate_ru, subject_atom, relation_type, object_atom, confidence) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
  let predicateId = pcCandidateId candidate
  bindTextOrFail stmt 1 version
  bindTextOrFail stmt 2 predicateId
  bindTextOrFail stmt 3 (pcCandidateId candidate)
  bindTextOrFail stmt 4 (pcTopic candidate)
  bindTextOrFail stmt 5 (roleText (roleForRelation (pcRelationType candidate)))
  bindTextOrFail stmt 6 (pcRenderedRu candidate)
  bindTextOrFail stmt 7 (pcSubject candidate)
  bindTextOrFail stmt 8 (pcRelationType candidate)
  bindTextOrFail stmt 9 (pcObject candidate)
  bindDoubleOrFail stmt 10 (pcConfidence candidate)
  stepOrFail stmt

loadOverlayPredicates :: NSQL.Database -> Text -> IO [(Text, PredicateRole, Text, Text, Text, Text, Double)]
loadOverlayPredicates conn version = do
  prepared <- NSQL.prepare conn "SELECT topic, predicate_role, predicate_ru, subject_atom, relation_type, object_atom, confidence FROM promotion_overlay_predicates WHERE overlay_version = ? ORDER BY topic, predicate_id"
  case prepared of
    Left err -> throwPromotionError err
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 version
      collectOverlay stmt []
  where
    collectOverlay stmt acc = do
      hasRow <- NSQL.stepRow stmt
      if not hasRow
        then NSQL.finalize stmt >> pure (reverse acc)
        else do
          topic <- NSQL.columnText stmt 0
          role <- roleFromText <$> NSQL.columnText stmt 1
          ru <- NSQL.columnText stmt 2
          subject <- NSQL.columnText stmt 3
          relation <- NSQL.columnText stmt 4
          object <- NSQL.columnText stmt 5
          confidence <- NSQL.columnDouble stmt 6
          collectOverlay stmt ((topic, role, ru, subject, relation, object, confidence) : acc)

loadOverlayPredicatesLineage :: NSQL.Database -> Text -> IO [(Text, PredicateRole, Text, Text, Text, Text, Double)]
loadOverlayPredicatesLineage conn version = do
  versions <- loadOverlayLineageVersions conn version
  concat <$> mapM (loadOverlayPredicates conn) versions

-- | Variant used only by runtime provenance wiring. Predicate ids remain
-- opaque to rendering and are resolved after the renderer reports the
-- emitted predicate surface.
loadOverlayPredicatesWithIds :: NSQL.Database -> Text -> IO [(Text, Text, PredicateRole, Text, Text, Text, Text, Double)]
loadOverlayPredicatesWithIds conn version = do
  prepared <- NSQL.prepare conn "SELECT predicate_id, topic, predicate_role, predicate_ru, subject_atom, relation_type, object_atom, confidence FROM promotion_overlay_predicates WHERE overlay_version = ? ORDER BY topic, predicate_id"
  case prepared of
    Left err -> throwPromotionError err
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 version
      collectOverlay stmt []
  where
    collectOverlay stmt acc = do
      hasRow <- NSQL.stepRow stmt
      if not hasRow
        then NSQL.finalize stmt >> pure (reverse acc)
        else do
          predicateId <- NSQL.columnText stmt 0
          topic <- NSQL.columnText stmt 1
          role <- roleFromText <$> NSQL.columnText stmt 2
          ru <- NSQL.columnText stmt 3
          subject <- NSQL.columnText stmt 4
          relation <- NSQL.columnText stmt 5
          object <- NSQL.columnText stmt 6
          confidence <- NSQL.columnDouble stmt 7
          collectOverlay stmt ((predicateId, topic, role, ru, subject, relation, object, confidence) : acc)

loadOverlayPredicatesWithIdsLineage :: NSQL.Database -> Text -> IO [(Text, Text, PredicateRole, Text, Text, Text, Text, Double)]
loadOverlayPredicatesWithIdsLineage conn version = do
  versions <- loadOverlayLineageVersions conn version
  concat <$> mapM (loadOverlayPredicatesWithIds conn) versions

-- | Return ancestors before descendants so a cumulative overlay preserves all
-- previously active predicates while allowing the child to win any surface-id
-- map collision. Cycles and dangling parents fail closed.
loadOverlayLineageVersions :: NSQL.Database -> Text -> IO [Text]
loadOverlayLineageVersions conn = go S.empty
  where
    go seen version
      | version `S.member` seen = throwPromotionError "promotion overlay parent cycle detected"
      | otherwise = do
          exists <- overlayExists conn version
          unless exists (throwPromotionError ("promotion overlay lineage references missing parent: " <> version))
          parent <- loadParentVersion conn version
          ancestors <- maybe (pure []) (go (S.insert version seen)) parent
          pure (ancestors ++ [version])

loadActiveVersion :: NSQL.Database -> IO (Maybe Text)
loadActiveVersion conn = fmap fst <$> loadActivePointerAllowLegacy conn

loadActivePointer :: NSQL.Database -> IO (Maybe (Text, Text))
loadActivePointer conn = do
  pointer <- loadActivePointerAllowLegacy conn
  pure $ case pointer of
    Just (version, Just evaluationId) -> Just (version, evaluationId)
    _ -> Nothing

loadActivePointerAllowLegacy :: NSQL.Database -> IO (Maybe (Text, Maybe Text))
loadActivePointerAllowLegacy conn = do
  prepared <- NSQL.prepare conn
    "SELECT overlay_version, runtime_evaluation_id FROM promotion_active WHERE singleton = 1"
  case prepared of
    Left err -> throwPromotionError err
    Right stmt -> do
      hasRow <- NSQL.stepRow stmt
      overlayNull <- if hasRow then NSQL.columnIsNull stmt 0 else pure True
      value <- if overlayNull
        then pure Nothing
        else do
          version <- NSQL.columnText stmt 0
          evaluationId <- maybeText stmt 1
          pure (Just (version, evaluationId))
      NSQL.finalize stmt
      pure value

loadParentVersion :: NSQL.Database -> Text -> IO (Maybe Text)
loadParentVersion conn version = do
  prepared <- NSQL.prepare conn "SELECT parent_version FROM promotion_overlays WHERE overlay_version = ?"
  case prepared of
    Left err -> throwPromotionError err
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 version
      hasRow <- NSQL.stepRow stmt
      nullValue <- if hasRow then NSQL.columnIsNull stmt 0 else pure True
      value <- if nullValue then pure Nothing else Just <$> NSQL.columnText stmt 0
      NSQL.finalize stmt
      pure value

loadPriorRuntimeEvaluation :: NSQL.Database -> Text -> IO (Maybe Text)
loadPriorRuntimeEvaluation conn version = do
  prepared <- NSQL.prepare conn
    "SELECT prior_runtime_evaluation_id FROM promotion_overlays WHERE overlay_version = ?"
  case prepared of
    Left err -> throwPromotionError err
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 version
      hasRow <- NSQL.stepRow stmt
      value <- if hasRow then maybeText stmt 0 else pure Nothing
      NSQL.finalize stmt
      pure value

overlayExists :: NSQL.Database -> Text -> IO Bool
overlayExists conn version = do
  prepared <- NSQL.prepare conn "SELECT 1 FROM promotion_overlays WHERE overlay_version = ?"
  case prepared of
    Left err -> throwPromotionError err
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 version
      value <- NSQL.stepRow stmt
      NSQL.finalize stmt
      pure value

loadOverlayStatus :: NSQL.Database -> Text -> IO (Maybe Text)
loadOverlayStatus conn version = do
  prepared <- NSQL.prepare conn "SELECT status FROM promotion_overlays WHERE overlay_version = ?"
  case prepared of
    Left err -> throwPromotionError err
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 version
      hasRow <- NSQL.stepRow stmt
      value <- if hasRow then Just <$> NSQL.columnText stmt 0 else pure Nothing
      NSQL.finalize stmt
      pure value

-- | An evaluated overlay remains an audit artifact, but it cannot cross the
-- activation boundary unless it was produced by the current gate policy.
-- Legacy overlays intentionally have no row here and therefore fail closed.
overlayHasCurrentPolicyLineage :: NSQL.Database -> Text -> IO Bool
overlayHasCurrentPolicyLineage conn version = do
  prepared <- NSQL.prepare conn
    "SELECT 1 FROM promotion_overlay_lineage l JOIN promotion_overlays o ON o.overlay_version = l.overlay_version JOIN promotion_gate_run_lineage g ON g.gate_run_id = l.gate_run_id WHERE l.overlay_version = ? AND l.snapshot_id = o.snapshot_id AND g.snapshot_id = l.snapshot_id AND l.policy_version = ? AND l.policy_checksum = ? AND g.policy_version = l.policy_version AND g.policy_checksum = l.policy_checksum LIMIT 1"
  case prepared of
    Left err -> throwPromotionError err
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 version
      _ <- NSQL.bindText stmt 2 promotionGatePolicyVersion
      _ <- NSQL.bindText stmt 3 promotionGatePolicyChecksum
      matches <- NSQL.stepRow stmt
      NSQL.finalize stmt
      pure matches

loadOverlayChecksum :: NSQL.Database -> Text -> IO Text
loadOverlayChecksum conn version = do
  prepared <- NSQL.prepare conn
    "SELECT checksum FROM promotion_overlays WHERE overlay_version = ?"
  case prepared of
    Left err -> throwPromotionError err
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 version
      hasRow <- NSQL.stepRow stmt
      checksum <- if hasRow
        then NSQL.columnText stmt 0
        else throwPromotionError ("promotion overlay not found: " <> version)
      NSQL.finalize stmt
      pure checksum

data LatestCorpusEvaluation = LatestCorpusEvaluation
  { lceEvaluationId :: !Text
  , lceCorpusVersion :: !Text
  , lceOverlayChecksum :: !Text
  , lcePassed :: !Bool
  }

data LatestRuntimeEvaluation = LatestRuntimeEvaluation
  { lreEvaluationId :: !Text
  , lreCorpusEvaluationId :: !Text
  , lreRuntimeCorpusVersion :: !Text
  , lreMathVersion :: !Int
  , lreOverlayChecksum :: !Text
  , lreAutomatedPassed :: !Bool
  , lreOverlayUsageCases :: !Int
  }

loadLatestCorpusEvaluation :: NSQL.Database -> Text -> IO (Maybe LatestCorpusEvaluation)
loadLatestCorpusEvaluation conn version = do
  prepared <- NSQL.prepare conn
    "SELECT evaluation_id, corpus_version, overlay_checksum, passed FROM promotion_evaluations WHERE overlay_version=? ORDER BY created_at DESC, evaluation_id DESC LIMIT 1"
  case prepared of
    Left err -> throwPromotionError err
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 version
      hasRow <- NSQL.stepRow stmt
      value <- if hasRow
        then Just <$> (LatestCorpusEvaluation
          <$> NSQL.columnText stmt 0
          <*> NSQL.columnText stmt 1
          <*> NSQL.columnText stmt 2
          <*> ((== 1) <$> NSQL.columnInt stmt 3))
        else pure Nothing
      NSQL.finalize stmt
      pure value

loadLatestRuntimeEvaluation :: NSQL.Database -> Text -> IO (Maybe LatestRuntimeEvaluation)
loadLatestRuntimeEvaluation conn version = do
  prepared <- NSQL.prepare conn
    "SELECT evaluation_id, corpus_evaluation_id, runtime_corpus_version, math_version, overlay_checksum, automated_passed, overlay_usage_cases FROM promotion_runtime_evaluations WHERE overlay_version=? ORDER BY completed_at DESC, evaluation_id DESC LIMIT 1"
  case prepared of
    Left err -> throwPromotionError err
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 version
      hasRow <- NSQL.stepRow stmt
      value <- if hasRow
        then Just <$> (LatestRuntimeEvaluation
          <$> NSQL.columnText stmt 0
          <*> NSQL.columnText stmt 1
          <*> NSQL.columnText stmt 2
          <*> NSQL.columnInt stmt 3
          <*> NSQL.columnText stmt 4
          <*> ((== 1) <$> NSQL.columnInt stmt 5)
          <*> NSQL.columnInt stmt 6)
        else pure Nothing
      NSQL.finalize stmt
      pure value

-- | Select first, validate second. In particular, version predicates are not
-- placed in SQL WHERE clauses: a newer stale or failed evaluation must block
-- rather than exposing an older passing release.
loadLatestCurrentPassingEvaluation :: NSQL.Database -> Text -> IO (Maybe Text)
loadLatestCurrentPassingEvaluation conn version = do
  overlayChecksum <- loadOverlayChecksum conn version
  corpusEvaluation <- loadLatestCorpusEvaluation conn version
  runtimeEvaluation <- loadLatestRuntimeEvaluation conn version
  pure $ case (corpusEvaluation, runtimeEvaluation) of
    (Just corpus, Just runtime)
      | lcePassed corpus
      , lceCorpusVersion corpus == promotionEvaluationCorpusVersion
      , lceOverlayChecksum corpus == overlayChecksum
      , lreCorpusEvaluationId runtime == lceEvaluationId corpus
      , lreRuntimeCorpusVersion runtime == promotionRuntimeCorpusVersion
      , lreMathVersion runtime == currentMathVersion
      , lreOverlayChecksum runtime == overlayChecksum
      , lreAutomatedPassed runtime
      , lreOverlayUsageCases runtime > 0
      -> Just (lreEvaluationId runtime)
    _ -> Nothing

loadCurrentReleasedEvaluation :: NSQL.Database -> Text -> IO (Maybe Text)
loadCurrentReleasedEvaluation conn version = do
  current <- loadLatestCurrentPassingEvaluation conn version
  case current of
    Nothing -> pure Nothing
    Just evaluationId -> do
      prepared <- NSQL.prepare conn
        "SELECT release_passed, human_reviewed FROM promotion_runtime_release_gates WHERE overlay_version=? AND evaluation_id=?"
      case prepared of
        Left err -> throwPromotionError err
        Right stmt -> do
          _ <- NSQL.bindText stmt 1 version
          _ <- NSQL.bindText stmt 2 evaluationId
          hasRow <- NSQL.stepRow stmt
          released <- if hasRow
            then (&&) <$> ((== 1) <$> NSQL.columnInt stmt 0)
                      <*> ((== 1) <$> NSQL.columnInt stmt 1)
            else pure False
          NSQL.finalize stmt
          pure (if released then Just evaluationId else Nothing)

-- | Validate the immutable evaluation selected when an overlay became active.
-- A later review evaluation is append-only evidence and must not revoke this
-- binding merely because it is newer and has not been released.
loadReleasedEvaluationById :: NSQL.Database -> Text -> Text -> IO Bool
loadReleasedEvaluationById conn version evaluationId = do
  overlayChecksum <- loadOverlayChecksum conn version
  prepared <- NSQL.prepare conn
    "SELECT 1 FROM promotion_runtime_evaluations r JOIN promotion_evaluations c ON c.evaluation_id=r.corpus_evaluation_id AND c.overlay_version=r.overlay_version JOIN promotion_runtime_release_gates g ON g.overlay_version=r.overlay_version AND g.evaluation_id=r.evaluation_id WHERE r.overlay_version=? AND r.evaluation_id=? AND r.runtime_corpus_version=? AND r.math_version=? AND r.overlay_checksum=? AND r.automated_passed=1 AND r.overlay_usage_cases>0 AND c.corpus_version=? AND c.overlay_checksum=? AND c.passed=1 AND g.release_passed=1 AND g.human_reviewed=1 LIMIT 1"
  case prepared of
    Left err -> throwPromotionError err
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 version
      _ <- NSQL.bindText stmt 2 evaluationId
      _ <- NSQL.bindText stmt 3 promotionRuntimeCorpusVersion
      _ <- NSQL.bindInt64 stmt 4 (fromIntegral currentMathVersion)
      _ <- NSQL.bindText stmt 5 overlayChecksum
      _ <- NSQL.bindText stmt 6 promotionEvaluationCorpusVersion
      _ <- NSQL.bindText stmt 7 overlayChecksum
      found <- NSQL.stepRow stmt
      NSQL.finalize stmt
      pure found

insertHumanRelease :: NSQL.Database -> Text -> Text -> UTCTime -> Text -> IO ()
insertHumanRelease conn overlayVersion evaluationId now details = do
  stmt <- prepareTx conn "promotion_human_release_insert"
    "INSERT OR IGNORE INTO promotion_runtime_release_gates(overlay_version, evaluation_id, completed_at, release_passed, human_reviewed, details) VALUES(?, ?, ?, 1, 1, ?)"
  bindTextOrFail stmt 1 overlayVersion
  bindTextOrFail stmt 2 evaluationId
  bindInt64OrFail stmt 3 (utcMicros now)
  bindTextOrFail stmt 4 details
  stepOrFail stmt

-- | Every active predicate must be the exact candidate governed by the gate
-- run captured in this overlay's current-policy lineage.
overlayPredicatesGoverned :: NSQL.Database -> Text -> IO Bool
overlayPredicatesGoverned conn version = do
  prepared <- NSQL.prepare conn
    "SELECT COUNT(*), (SELECT COUNT(*) FROM promotion_overlay_predicates WHERE overlay_version=?) FROM promotion_overlay_predicates p JOIN promotion_overlay_lineage l ON l.overlay_version=p.overlay_version WHERE p.overlay_version=? AND ((SELECT COUNT(DISTINCT g.gate_name) FROM promotion_gate_runs g WHERE g.candidate_id=p.candidate_id AND g.gate_run_id=l.gate_run_id AND g.decision='pass')<>13 OR EXISTS (SELECT 1 FROM promotion_gate_runs g WHERE g.candidate_id=p.candidate_id AND g.gate_run_id=l.gate_run_id AND g.decision<>'pass'))"
  case prepared of
    Left err -> throwPromotionError err
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 version
      _ <- NSQL.bindText stmt 2 version
      hasRow <- NSQL.stepRow stmt
      invalid <- if hasRow then NSQL.columnInt stmt 0 else pure 1
      predicateCount <- if hasRow then NSQL.columnInt stmt 1 else pure 0
      NSQL.finalize stmt
      pure (invalid == 0 && predicateCount > 0)

overlayLineageArtifactsValid :: NSQL.Database -> Text -> IO Bool
overlayLineageArtifactsValid conn version = do
  versions <- loadOverlayLineageVersions conn version
  and <$> mapM valid versions
  where
    valid item = do
      currentPolicy <- overlayHasCurrentPolicyLineage conn item
      artifactValid <- overlayArtifactValid conn item
      governed <- overlayPredicatesGoverned conn item
      pure (currentPolicy && artifactValid && governed)

overlayArtifactValid :: NSQL.Database -> Text -> IO Bool
overlayArtifactValid conn version = do
  prepared <- NSQL.prepare conn
    "SELECT o.snapshot_id, o.checksum, s.checksum, l.snapshot_checksum, l.predicate_checksum, l.gate_run_id, l.policy_version, l.policy_checksum FROM promotion_overlays o JOIN promotion_snapshots s ON s.snapshot_id=o.snapshot_id JOIN promotion_overlay_lineage l ON l.overlay_version=o.overlay_version AND l.snapshot_id=o.snapshot_id WHERE o.overlay_version=?"
  case prepared of
    Left err -> throwPromotionError err
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 version
      hasRow <- NSQL.stepRow stmt
      metadata <- if hasRow
        then Just <$> ((,,,,,,,)
          <$> NSQL.columnText stmt 0 <*> NSQL.columnText stmt 1
          <*> NSQL.columnText stmt 2 <*> NSQL.columnText stmt 3
          <*> NSQL.columnText stmt 4 <*> NSQL.columnText stmt 5
          <*> NSQL.columnText stmt 6 <*> NSQL.columnText stmt 7)
        else pure Nothing
      NSQL.finalize stmt
      case metadata of
        Nothing -> pure False
        Just (snapshotId, storedOverlayChecksum, snapshotChecksum, boundSnapshotChecksum,
              boundPredicateChecksum, gateRunId, policyVersion, policyChecksum) -> do
          predicateRows <- loadOverlayArtifactRows conn version
          let actualPredicateChecksum = overlayPredicateChecksum predicateRows
              actualOverlayChecksum = promotionOverlayChecksum snapshotId snapshotChecksum gateRunId
                policyVersion policyChecksum actualPredicateChecksum
          -- Empty drafts are valid checksum artifacts; activation separately
          -- requires a non-empty governed predicate set.
          pure (snapshotChecksum == boundSnapshotChecksum
            && actualPredicateChecksum == boundPredicateChecksum
            && actualOverlayChecksum == storedOverlayChecksum)

type OverlayArtifactRow = (Text, Text, Text, Text, Text, Text, Text, Text, Double)

loadOverlayArtifactRows :: NSQL.Database -> Text -> IO [OverlayArtifactRow]
loadOverlayArtifactRows conn version = do
  prepared <- NSQL.prepare conn
    "SELECT predicate_id, candidate_id, topic, predicate_role, predicate_ru, subject_atom, relation_type, object_atom, confidence FROM promotion_overlay_predicates WHERE overlay_version=? ORDER BY predicate_id"
  case prepared of
    Left err -> throwPromotionError err
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 version
      collect stmt []
  where
    collect stmt acc = do
      hasRow <- NSQL.stepRow stmt
      if not hasRow
        then NSQL.finalize stmt >> pure (reverse acc)
        else do
          row <- (,,,,,,,,)
            <$> NSQL.columnText stmt 0 <*> NSQL.columnText stmt 1
            <*> NSQL.columnText stmt 2 <*> NSQL.columnText stmt 3
            <*> NSQL.columnText stmt 4 <*> NSQL.columnText stmt 5
            <*> NSQL.columnText stmt 6 <*> NSQL.columnText stmt 7
            <*> NSQL.columnDouble stmt 8
          collect stmt (row : acc)

candidatePredicateChecksum :: [PromotionCandidate] -> Text
candidatePredicateChecksum = overlayPredicateChecksum . map candidateRow
  where
    candidateRow candidate =
      ( pcCandidateId candidate
      , pcCandidateId candidate
      , pcTopic candidate
      , roleText (roleForRelation (pcRelationType candidate))
      , pcRenderedRu candidate
      , pcSubject candidate
      , pcRelationType candidate
      , pcObject candidate
      , pcConfidence candidate
      )

overlayPredicateChecksum :: [OverlayArtifactRow] -> Text
overlayPredicateChecksum rows = sha256Hex . TE.encodeUtf8 . T.intercalate "\n" $
  [ T.intercalate "|"
      [ predicateId, candidateId, topic, role, surface, subject, relation, object
      , T.pack (show confidence)
      ]
  | (predicateId, candidateId, topic, role, surface, subject, relation, object, confidence)
      <- sortOn (\(predicateId, _, _, _, _, _, _, _, _) -> predicateId) rows
  ]

promotionOverlayChecksum :: Text -> Text -> Text -> Text -> Text -> Text -> Text
promotionOverlayChecksum snapshotId snapshotChecksum gateRunId policyVersion policyChecksum predicateChecksum =
  sha256Hex . TE.encodeUtf8 . T.intercalate "\n" $
    [ snapshotId, snapshotChecksum, gateRunId, policyVersion, policyChecksum, predicateChecksum ]

-- | All overlays except an exact self-revalidation record participate in
-- duplicate detection. A previous overlay for the same candidate and snapshot
-- is audit history, not independent support for the candidate itself.
loadHistoricalOverlayRelations :: NSQL.Database -> IO [HistoricalOverlayRelation]
loadHistoricalOverlayRelations conn = do
  prepared <- NSQL.prepare conn
    "SELECT p.overlay_version, o.snapshot_id, p.candidate_id, p.subject_atom, p.relation_type, p.object_atom FROM promotion_overlay_predicates p JOIN promotion_overlays o ON o.overlay_version = p.overlay_version ORDER BY p.overlay_version, p.predicate_id"
  case prepared of
    Left err -> throwPromotionError err
    Right stmt -> collect stmt []
  where
    collect stmt acc = do
      hasRow <- NSQL.stepRow stmt
      if not hasRow
        then NSQL.finalize stmt >> pure (reverse acc)
        else do
          overlayVersion <- NSQL.columnText stmt 0
          snapshotId <- NSQL.columnText stmt 1
          candidateId <- NSQL.columnText stmt 2
          subject <- NSQL.columnText stmt 3
          relation <- NSQL.columnText stmt 4
          object <- NSQL.columnText stmt 5
          let next = case promotionRelationName relation of
                Nothing -> acc
                Just canonicalRelation ->
                  HistoricalOverlayRelation
                    overlayVersion
                    snapshotId
                    candidateId
                    (CanonicalRelation
                      (canonicalAtomTerm subject)
                      canonicalRelation
                      (canonicalAtomTerm object))
                  : acc
          collect stmt next

isSelfRevalidation :: PromotionCandidate -> HistoricalOverlayRelation -> Bool
isSelfRevalidation candidate historical =
  horCandidateId historical == pcCandidateId candidate
    && horSnapshotId historical == pcSnapshotId candidate

activeContains :: NSQL.Database -> PromotionCandidate -> IO Bool
activeContains conn candidate = do
  prepared <- NSQL.prepare conn
    "SELECT 1 FROM promotion_active a JOIN promotion_overlay_predicates p ON p.overlay_version = a.overlay_version WHERE a.singleton = 1 AND p.topic = ? AND p.subject_atom = ? AND p.relation_type = ? AND p.object_atom = ? LIMIT 1"
  case prepared of
    Left err -> throwPromotionError err
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 (pcTopic candidate)
      _ <- NSQL.bindText stmt 2 (pcSubject candidate)
      _ <- NSQL.bindText stmt 3 (pcRelationType candidate)
      _ <- NSQL.bindText stmt 4 (pcObject candidate)
      found <- NSQL.stepRow stmt
      NSQL.finalize stmt
      pure found

snapshotHasRuntimeProvenance :: NSQL.Database -> Text -> IO Bool
snapshotHasRuntimeProvenance conn snapshotId = do
  prepared <- NSQL.prepare conn "SELECT 1 FROM promotion_snapshot_edges WHERE snapshot_id = ? AND provenance = 'runtime_llm' LIMIT 1"
  case prepared of
    Left err -> throwPromotionError err
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 snapshotId
      found <- NSQL.stepRow stmt
      NSQL.finalize stmt
      pure found

loadActiveKeys :: NSQL.Database -> IO (Set Text)
loadActiveKeys conn = do
  prepared <- NSQL.prepare conn "SELECT p.topic, p.subject_atom, p.relation_type, p.object_atom FROM promotion_active a JOIN promotion_overlay_predicates p ON p.overlay_version = a.overlay_version WHERE a.singleton = 1"
  case prepared of
    Left err -> throwPromotionError err
    Right stmt -> collect stmt S.empty
  where
    collect stmt acc = do
      hasRow <- NSQL.stepRow stmt
      if not hasRow
        then NSQL.finalize stmt >> pure acc
        else do
          topic <- NSQL.columnText stmt 0
          subject <- NSQL.columnText stmt 1
          relation <- NSQL.columnText stmt 2
          object <- NSQL.columnText stmt 3
          collect stmt (S.insert (T.intercalate "|" [topic, subject, relation, object]) acc)

candidateKey :: PromotionCandidate -> Text
candidateKey c = T.intercalate "|" [pcTopic c, pcSubject c, pcRelationType c, pcObject c]

canonicalCandidateRelation :: PromotionCandidate -> CanonicalRelation
canonicalCandidateRelation candidate = CanonicalRelation
  { crSubject = canonicalAtomTerm (pcSubject candidate)
  , crRelation = normalizeAtom (pcRelationType candidate)
  , crObject = canonicalAtomTerm (pcObject candidate)
  }

curatedCanonicalRelations :: [CanonicalRelation]
curatedCanonicalRelations = mapMaybe canonicalCuratedRelation relationStore

canonicalCuratedRelation :: Relation -> Maybe CanonicalRelation
canonicalCuratedRelation relation = do
  relationType <- promotionRelationType (relType relation)
  let AtomId subject = relFrom relation
      AtomId object = relTo relation
  pure CanonicalRelation
    { crSubject = canonicalAtomTerm subject
    , crRelation = relationType
    , crObject = canonicalAtomTerm object
    }

promotionRelationType :: RelationType -> Maybe Text
promotionRelationType relation = case relation of
  RelIsA -> Just "is_a"
  RelPartOf -> Just "part_of"
  RelRequires -> Just "requires"
  RelPresupposes -> Just "presupposes"
  RelCauses -> Just "causes"
  RelRelatedTo -> Just "related_to"
  RelContrastsWith -> Just "contrasts_with"
  _ -> Nothing

promotionRelationName :: Text -> Maybe Text
promotionRelationName relation =
  let normalized = normalizeAtom relation
  in if relationAllowed normalized then Just normalized else Nothing

-- | Runtime candidates commonly name a broader atom than a curated relation's
-- target (for example @уязвимость@ versus @уязвимость перед другим@).  The
-- canonical atom id preserves the structured atom boundary, and token-set
-- inclusion allows only the safe, directional broadening check.
strictlySubsumes :: CanonicalRelation -> CanonicalRelation -> Bool
strictlySubsumes existing candidate =
  existing /= candidate
    && crSubject existing == crSubject candidate
    && relationSubsumes (crRelation existing) (crRelation candidate)
    && objectSubsumes (crObject existing) (crObject candidate)

relationSubsumes :: Text -> Text -> Bool
relationSubsumes existing candidate =
  existing == candidate
    || (existing == "presupposes" && candidate == "requires")

objectSubsumes :: Text -> Text -> Bool
objectSubsumes existing candidate =
  not (S.null candidateTokens)
    && candidateTokens `S.isSubsetOf` existingTokens
  where
    existingTokens = canonicalAtomTokens existing
    candidateTokens = canonicalAtomTokens candidate

canonicalAtomTerm :: Text -> Text
canonicalAtomTerm raw =
  M.findWithDefault normalized normalized canonicalAtomAliases
  where
    normalized = canonicalText raw

canonicalAtomAliases :: Map Text Text
canonicalAtomAliases = M.fromList
  [ (canonicalText alias, canonicalText atomKey)
  | (AtomId atomKey, atom) <- M.toList atomStore
  , alias <- [atomKey, atomSurface atom, atomDisplay atom]
  ]

-- | Runtime edges may legitimately use arbitrary AtomStore endpoints for
-- associative navigation. Promotion accepts only subjects that can be mapped
-- back to a curated definition topic; the mapping happens before candidate
-- creation rather than letting atom fragments accumulate in the gate queue.
promotionSubjectTopic :: Text -> Maybe Text
promotionSubjectTopic subject =
  M.lookup (canonicalAtomTerm subject) promotionTopicsByCanonicalAtom

promotionTopicsByCanonicalAtom :: Map Text Text
promotionTopicsByCanonicalAtom = M.fromList
  [ (canonicalAtomTerm topic, topic)
  | topic <- M.keys definitionCorpus
  ]

canonicalAtomTokens :: Text -> Set Text
canonicalAtomTokens = S.fromList . T.words . canonicalText

canonicalText :: Text -> Text
canonicalText = T.unwords . T.words . T.replace "_" " " . normalizeAtom

updateOverlayActive :: NSQL.Database -> Text -> UTCTime -> IO ()
updateOverlayActive conn version now = do
  stmt <- prepareTx conn "promotion_overlay_activate" "UPDATE promotion_overlays SET status='active', activated_at=? WHERE overlay_version=?"
  bindInt64OrFail stmt 1 (utcMicros now)
  bindTextOrFail stmt 2 version
  stepOrFail stmt

setOverlayPriorEvaluation :: NSQL.Database -> Text -> Maybe Text -> IO ()
setOverlayPriorEvaluation conn version evaluationId = do
  stmt <- prepareTx conn "promotion_overlay_prior_evaluation"
    "UPDATE promotion_overlays SET prior_runtime_evaluation_id=? WHERE overlay_version=?"
  bindMaybeText stmt 1 evaluationId
  bindTextOrFail stmt 2 version
  stepOrFail stmt

upsertActive :: NSQL.Database -> Maybe Text -> Maybe Text -> UTCTime -> IO ()
upsertActive conn version evaluationId now = do
  stmt <- prepareTx conn "promotion_active_upsert" "INSERT INTO promotion_active(singleton, overlay_version, runtime_evaluation_id, updated_at) VALUES(1, ?, ?, ?) ON CONFLICT(singleton) DO UPDATE SET overlay_version=excluded.overlay_version, runtime_evaluation_id=excluded.runtime_evaluation_id, updated_at=excluded.updated_at"
  bindMaybeText stmt 1 version
  bindMaybeText stmt 2 evaluationId
  bindInt64OrFail stmt 3 (utcMicros now)
  stepOrFail stmt

markOverlayEvaluated :: NSQL.Database -> Text -> IO ()
markOverlayEvaluated conn version = do
  stmt <- prepareTx conn "promotion_overlay_evaluated" "UPDATE promotion_overlays SET status='evaluated' WHERE overlay_version = ? AND status='draft'"
  bindTextOrFail stmt 1 version
  stepOrFail stmt

execInsertEvaluation :: NSQL.Database -> Text -> Text -> UTCTime -> Text -> Bool -> Int -> Int -> Int -> Int -> Int -> Int -> IO ()
execInsertEvaluation conn eid version now overlayChecksum passed b c bc cc br cr = do
  stmt <- prepareTx conn "promotion_evaluation_insert" "INSERT INTO promotion_evaluations(evaluation_id, overlay_version, created_at, corpus_version, overlay_checksum, passed, baseline_contentful, candidate_contentful, baseline_conflicts, candidate_conflicts, baseline_refusals, candidate_refusals) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
  bindTextOrFail stmt 1 eid
  bindTextOrFail stmt 2 version
  bindInt64OrFail stmt 3 (utcMicros now)
  bindTextOrFail stmt 4 promotionEvaluationCorpusVersion
  bindTextOrFail stmt 5 overlayChecksum
  bindInt64OrFail stmt 6 (boolInt passed)
  mapM_ (uncurry (bindInt64OrFail stmt)) [(7, fromIntegral b), (8, fromIntegral c), (9, fromIntegral bc), (10, fromIntegral cc), (11, fromIntegral br), (12, fromIntegral cr)]
  stepOrFail stmt

insertEvaluationCase :: NSQL.Database -> Text -> Text -> Bool -> Bool -> Bool -> Bool -> Text -> IO ()
insertEvaluationCase conn evaluationId topic baselineContentful candidateContentful baselineConflict candidateConflict method = do
  stmt <- prepareTx conn "promotion_evaluation_case_insert"
    "INSERT OR REPLACE INTO promotion_evaluation_cases(evaluation_id, case_id, topic, baseline_contentful, candidate_contentful, baseline_conflicts, candidate_conflicts, method) VALUES(?, ?, ?, ?, ?, ?, ?, ?)"
  let caseId = sha256Hex (TE.encodeUtf8 (evaluationId <> "|" <> topic))
  bindTextOrFail stmt 1 evaluationId
  bindTextOrFail stmt 2 caseId
  bindTextOrFail stmt 3 topic
  bindInt64OrFail stmt 4 (boolInt baselineContentful)
  bindInt64OrFail stmt 5 (boolInt candidateContentful)
  bindInt64OrFail stmt 6 (boolInt baselineConflict)
  bindInt64OrFail stmt 7 (boolInt candidateConflict)
  bindTextOrFail stmt 8 method
  stepOrFail stmt

boolInt :: Bool -> Int64
boolInt value = if value then 1 else 0

countOverlay :: NSQL.Database -> Text -> IO Int
countOverlay conn version = do
  prepared <- NSQL.prepare conn "SELECT COUNT(*) FROM promotion_overlay_predicates WHERE overlay_version = ?"
  case prepared of
    Left err -> throwPromotionError err
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 version
      hasRow <- NSQL.stepRow stmt
      value <- if hasRow then NSQL.columnInt stmt 0 else pure 0
      NSQL.finalize stmt
      pure value

normalizeAtom :: Text -> Text
normalizeAtom = T.toLower . T.strip . T.dropWhileEnd (`elem` ("?!.,;:" :: String))

candidateHash :: Text -> Text -> Text -> Text -> Text -> Text
candidateHash snapshot topic subject relation object =
  sha256Hex (TE.encodeUtf8 (T.intercalate "|" [snapshot, topic, subject, relation, object]))

renderCandidate :: Text -> Text -> Text -> Text
renderCandidate subject relation object =
  let x = subject
      y = object
  in case relation of
       "is_a" -> x <> " относится к " <> y
       "part_of" -> x <> " является частью " <> y
       "requires" -> x <> " требует " <> y
       "presupposes" -> x <> " предполагает " <> y
       "causes" -> x <> " связано с возникновением " <> y
       "contrasts_with" -> x <> " контрастирует с " <> y
       "related_to" -> x <> " связано с " <> y
       _ -> x <> " связано с " <> y

relationAllowed :: Text -> Bool
relationAllowed relation = relation `S.member` S.fromList
  ["is_a", "part_of", "requires", "presupposes", "causes", "related_to", "contrasts_with"]

contradictoryRelation :: Text -> Bool
contradictoryRelation relation = relation `elem` ["negates", "is_not"]

normalizedCandidate :: PromotionCandidate -> Bool
normalizedCandidate candidate =
  all valid [pcTopic candidate, pcSubject candidate, pcRelationType candidate, pcObject candidate]
  where
    valid value = not (T.null value) && value == normalizeAtom value

-- | LLM-derived relations may enrich an established display topic, but cannot
-- create a new topic authority merely by appearing in the runtime graph.
-- The broad curated JSONL is intentionally not an admission registry: it is
-- display material and contains concepts outside the conservative seed scope.
trustedPromotionTopic :: PromotionCandidate -> Bool
trustedPromotionTopic candidate =
  let topic = normalizeTopic (pcTopic candidate)
  in topic == normalizeTopic (pcSubject candidate)
     && M.member topic definitionCorpus

roleForRelation :: Text -> PredicateRole
roleForRelation relation
  | relation `elem` ["is_a", "part_of"] = RoleStructure
  | relation `elem` ["requires", "presupposes", "causes"] = RoleRelation
  | otherwise = RoleProperty

roleText :: PredicateRole -> Text
roleText RoleProperty = "property"
roleText RoleRelation = "relation"
roleText RoleStructure = "structure"
roleText RoleDifferentiator = "differentiator"

roleFromText :: Text -> PredicateRole
roleFromText "relation" = RoleRelation
roleFromText "structure" = RoleStructure
roleFromText "differentiator" = RoleDifferentiator
roleFromText _ = RoleProperty

utcMicros :: UTCTime -> Int64
utcMicros = round . (* 1000000) . realToFrac . utcTimeToPOSIXSeconds

microsToUtc :: Int64 -> UTCTime
microsToUtc = posixSecondsToUTCTime . (/ 1000000) . fromIntegral

bindMaybeText :: TxStmt -> Int -> Maybe Text -> IO ()
bindMaybeText stmt index = maybe (bindNullOrFail stmt (fromIntegral index)) (bindTextOrFail stmt (fromIntegral index))

throwPromotionError :: Text -> IO a
throwPromotionError detail =
  throwQxFx0 (mkSQLiteError
    "learning_promotion"
    "PROMOTION_SQLITE_ERROR"
    (M.singleton "detail" detail))
