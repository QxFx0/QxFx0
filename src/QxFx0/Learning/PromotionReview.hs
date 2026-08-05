{-# LANGUAGE OverloadedStrings #-}

-- | Human-readable, deterministic review artifact for a promotion draft.
-- The report is read-only with respect to the operator database; its runtime
-- evidence is supplied by the isolated renderer A/B harness.
module QxFx0.Learning.PromotionReview
  ( renderPromotionReview
  , renderPromotionRevalidationReport
  ) where

import Control.Monad (forM)
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Bridge.SQLite (QxFx0DB(..))
import qualified QxFx0.Bridge.NativeSQLite as NSQL
import QxFx0.Learning.PromotionRuntime
  ( PromotionRuntimeCase(..)
  , RuntimeEvaluationCase(..)
  , RuntimeEvaluationMetrics(..)
  , RuntimeEvaluationSide(..)
  , RuntimePromotionEvaluation(..)
  )

data SnapshotMetadata = SnapshotMetadata
  { smEdgeCount :: !Int
  , smChecksum :: !Text
  }

data OverlayLineage = OverlayLineage
  { olGateRunId :: !Text
  , olPolicyVersion :: !Text
  , olPolicyChecksum :: !Text
  , olStatus :: !Text
  }

data GateRunLineage = GateRunLineage
  { glGateRunId :: !Text
  , glPolicyVersion :: !Text
  , glPolicyChecksum :: !Text
  }

data CandidateReview = CandidateReview
  { crCandidateId :: !Text
  , crTopic :: !Text
  , crSubject :: !Text
  , crRelation :: !Text
  , crObject :: !Text
  , crRendered :: !Text
  , crConfidence :: !Double
  , crSupportCount :: !Int
  , crStatus :: !Text
  , crGateDecisions :: ![(Text, Text, Text, Text)]
  , crEvidenceLineage :: ![EvidenceLineage]
  }

data EvidenceLineage = EvidenceLineage
  { elRequestId :: !Text
  , elPromptHash :: !Text
  , elResponseHash :: !Text
  , elEvidenceSource :: !Text
  , elModel :: !(Maybe Text)
  , elParserDecision :: !(Maybe Text)
  , elAdmissionDecision :: !(Maybe Text)
  , elEventTimestamp :: !(Maybe Int)
  }

renderPromotionReview
  :: QxFx0DB
  -> Text
  -> Text
  -> RuntimePromotionEvaluation
  -> IO Text
renderPromotionReview db snapshotId overlayVersion runtimeEvaluation = do
  snapshot <- loadSnapshotMetadata (qdbConn db) snapshotId
  overlayLineage <- loadOverlayLineage (qdbConn db) overlayVersion
  candidates <- loadCandidatesForReview (qdbConn db) snapshotId (olGateRunId overlayLineage)
  pure (renderReview snapshotId overlayVersion snapshot overlayLineage candidates runtimeEvaluation)

-- | Report a revalidation that stops before draft creation. This is the only
-- honest outcome when the stronger policy leaves no eligible candidates, so
-- the runtime harness has no candidate corpus to evaluate.
renderPromotionRevalidationReport :: QxFx0DB -> Text -> Text -> IO Text
renderPromotionRevalidationReport db snapshotId priorOverlayVersion = do
  snapshot <- loadSnapshotMetadata (qdbConn db) snapshotId
  gateLineage <- loadLatestGateRunLineage (qdbConn db) snapshotId
  priorStatus <- loadOverlayStatus (qdbConn db) priorOverlayVersion
  candidates <- loadPriorOverlayCandidatesForReview
    (qdbConn db) snapshotId priorOverlayVersion (glGateRunId gateLineage)
  pure (renderRevalidationReport
    snapshotId priorOverlayVersion snapshot gateLineage priorStatus candidates)

loadSnapshotMetadata :: NSQL.Database -> Text -> IO SnapshotMetadata
loadSnapshotMetadata conn snapshotId = do
  prepared <- NSQL.prepare conn
    "SELECT edge_count, checksum FROM promotion_snapshots WHERE snapshot_id = ?"
  case prepared of
    Left err -> fail (T.unpack err)
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 snapshotId
      hasRow <- NSQL.stepRow stmt
      metadata <- if hasRow
        then SnapshotMetadata <$> NSQL.columnInt stmt 0 <*> NSQL.columnText stmt 1
        else fail ("promotion snapshot not found: " <> T.unpack snapshotId)
      NSQL.finalize stmt
      pure metadata

loadOverlayLineage :: NSQL.Database -> Text -> IO OverlayLineage
loadOverlayLineage conn overlayVersion = do
  prepared <- NSQL.prepare conn
    "SELECT l.gate_run_id, l.policy_version, l.policy_checksum, o.status FROM promotion_overlay_lineage l JOIN promotion_overlays o ON o.overlay_version = l.overlay_version WHERE l.overlay_version = ?"
  case prepared of
    Left err -> fail (T.unpack err)
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 overlayVersion
      hasRow <- NSQL.stepRow stmt
      lineage <- if hasRow
        then OverlayLineage <$> NSQL.columnText stmt 0 <*> NSQL.columnText stmt 1 <*> NSQL.columnText stmt 2 <*> NSQL.columnText stmt 3
        else fail ("promotion overlay has no policy lineage: " <> T.unpack overlayVersion)
      NSQL.finalize stmt
      pure lineage

loadLatestGateRunLineage :: NSQL.Database -> Text -> IO GateRunLineage
loadLatestGateRunLineage conn snapshotId = do
  prepared <- NSQL.prepare conn
    "SELECT gate_run_id, policy_version, policy_checksum FROM promotion_gate_run_lineage WHERE snapshot_id = ? ORDER BY created_at DESC, gate_run_id DESC LIMIT 1"
  case prepared of
    Left err -> fail (T.unpack err)
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 snapshotId
      hasRow <- NSQL.stepRow stmt
      lineage <- if hasRow
        then GateRunLineage <$> NSQL.columnText stmt 0 <*> NSQL.columnText stmt 1 <*> NSQL.columnText stmt 2
        else fail ("promotion snapshot has no gate lineage: " <> T.unpack snapshotId)
      NSQL.finalize stmt
      pure lineage

loadOverlayStatus :: NSQL.Database -> Text -> IO (Maybe Text)
loadOverlayStatus conn overlayVersion = do
  prepared <- NSQL.prepare conn
    "SELECT status FROM promotion_overlays WHERE overlay_version = ?"
  case prepared of
    Left err -> fail (T.unpack err)
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 overlayVersion
      hasRow <- NSQL.stepRow stmt
      status <- if hasRow then Just <$> NSQL.columnText stmt 0 else pure Nothing
      NSQL.finalize stmt
      pure status

loadCandidatesForReview :: NSQL.Database -> Text -> Text -> IO [CandidateReview]
loadCandidatesForReview conn snapshotId gateRunId = do
  prepared <- NSQL.prepare conn
    "SELECT candidate_id, topic, subject_atom, relation_type, object_atom, rendered_ru, confidence_raw, support_count, lifecycle_status FROM promotion_candidates WHERE snapshot_id = ? ORDER BY topic, subject_atom, relation_type, object_atom"
  case prepared of
    Left err -> fail (T.unpack err)
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 snapshotId
      rows <- collect stmt []
      forM rows $ \(candidateId, topic, subject, relation, object, rendered, confidence, supportCount, status) -> do
        decisions <- loadGateDecisions conn candidateId gateRunId
        evidenceLineage <- loadEvidenceLineage conn snapshotId subject relation object
        pure CandidateReview
          { crCandidateId = candidateId
          , crTopic = topic
          , crSubject = subject
          , crRelation = relation
          , crObject = object
          , crRendered = rendered
          , crConfidence = confidence
          , crSupportCount = supportCount
          , crStatus = status
          , crGateDecisions = decisions
          , crEvidenceLineage = evidenceLineage
          }
  where
    collect stmt acc = do
      hasRow <- NSQL.stepRow stmt
      if not hasRow
        then NSQL.finalize stmt >> pure (reverse acc)
        else do
          row <- (,,,,,,,,)
            <$> NSQL.columnText stmt 0 <*> NSQL.columnText stmt 1 <*> NSQL.columnText stmt 2
            <*> NSQL.columnText stmt 3 <*> NSQL.columnText stmt 4 <*> NSQL.columnText stmt 5
            <*> NSQL.columnDouble stmt 6 <*> NSQL.columnInt stmt 7 <*> NSQL.columnText stmt 8
          collect stmt (row : acc)

loadPriorOverlayCandidatesForReview :: NSQL.Database -> Text -> Text -> Text -> IO [CandidateReview]
loadPriorOverlayCandidatesForReview conn snapshotId overlayVersion gateRunId = do
  prepared <- NSQL.prepare conn
    "SELECT c.candidate_id, c.topic, c.subject_atom, c.relation_type, c.object_atom, c.rendered_ru, c.confidence_raw, c.support_count, c.lifecycle_status FROM promotion_overlay_predicates p JOIN promotion_candidates c ON c.candidate_id = p.candidate_id WHERE p.overlay_version = ? AND c.snapshot_id = ? ORDER BY c.topic, c.subject_atom, c.relation_type, c.object_atom"
  case prepared of
    Left err -> fail (T.unpack err)
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 overlayVersion
      _ <- NSQL.bindText stmt 2 snapshotId
      rows <- collect stmt []
      forM rows $ \(candidateId, topic, subject, relation, object, rendered, confidence, supportCount, status) -> do
        decisions <- loadGateDecisions conn candidateId gateRunId
        evidenceLineage <- loadEvidenceLineage conn snapshotId subject relation object
        pure CandidateReview
          { crCandidateId = candidateId
          , crTopic = topic
          , crSubject = subject
          , crRelation = relation
          , crObject = object
          , crRendered = rendered
          , crConfidence = confidence
          , crSupportCount = supportCount
          , crStatus = status
          , crGateDecisions = decisions
          , crEvidenceLineage = evidenceLineage
          }
  where
    collect stmt acc = do
      hasRow <- NSQL.stepRow stmt
      if not hasRow
        then NSQL.finalize stmt >> pure (reverse acc)
        else do
          row <- (,,,,,,,,)
            <$> NSQL.columnText stmt 0 <*> NSQL.columnText stmt 1 <*> NSQL.columnText stmt 2
            <*> NSQL.columnText stmt 3 <*> NSQL.columnText stmt 4 <*> NSQL.columnText stmt 5
            <*> NSQL.columnDouble stmt 6 <*> NSQL.columnInt stmt 7 <*> NSQL.columnText stmt 8
          collect stmt (row : acc)

loadGateDecisions :: NSQL.Database -> Text -> Text -> IO [(Text, Text, Text, Text)]
loadGateDecisions conn candidateId gateRunId = do
  prepared <- NSQL.prepare conn
    "SELECT gate_name, decision, reason_code, detail FROM promotion_gate_runs WHERE candidate_id = ? AND gate_run_id = ? ORDER BY gate_name"
  case prepared of
    Left err -> fail (T.unpack err)
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 candidateId
      _ <- NSQL.bindText stmt 2 gateRunId
      collect stmt []
  where
    collect stmt acc = do
      hasRow <- NSQL.stepRow stmt
      if not hasRow
        then NSQL.finalize stmt >> pure (reverse acc)
        else do
          decision <- (,,,)
            <$> NSQL.columnText stmt 0 <*> NSQL.columnText stmt 1
            <*> NSQL.columnText stmt 2 <*> NSQL.columnText stmt 3
          collect stmt (decision : acc)

-- | Candidate identity is the normalized subject/relation/object triple. The
-- snapshot holds the immutable edge-to-request lineage, so the report joins it
-- back to that triple instead of inferring support from an overlay record.
loadEvidenceLineage :: NSQL.Database -> Text -> Text -> Text -> Text -> IO [EvidenceLineage]
loadEvidenceLineage conn snapshotId subject relation object = do
  prepared <- NSQL.prepare conn
    "SELECT DISTINCT l.request_id, l.prompt_hash, l.response_hash, l.evidence_source, l.model, l.parser_decision, l.admission_decision, l.event_timestamp FROM promotion_snapshot_edges e JOIN promotion_snapshot_edge_lineage l ON l.snapshot_id = e.snapshot_id AND l.edge_id = e.edge_id WHERE e.snapshot_id = ? AND lower(trim(e.edge_from)) = lower(trim(?)) AND lower(trim(COALESCE(e.relation_type, ''))) = lower(trim(?)) AND lower(trim(e.edge_to)) = lower(trim(?)) ORDER BY l.request_id, l.response_hash"
  case prepared of
    Left err -> fail (T.unpack err)
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 snapshotId
      _ <- NSQL.bindText stmt 2 subject
      _ <- NSQL.bindText stmt 3 relation
      _ <- NSQL.bindText stmt 4 object
      collect stmt []
  where
    collect stmt acc = do
      hasRow <- NSQL.stepRow stmt
      if not hasRow
        then NSQL.finalize stmt >> pure (reverse acc)
        else do
          lineage <- EvidenceLineage
            <$> NSQL.columnText stmt 0 <*> NSQL.columnText stmt 1
            <*> NSQL.columnText stmt 2 <*> NSQL.columnText stmt 3
            <*> columnTextMaybe stmt 4 <*> columnTextMaybe stmt 5
            <*> columnTextMaybe stmt 6 <*> columnIntMaybe stmt 7
          collect stmt (lineage : acc)

columnTextMaybe :: NSQL.Statement -> Int -> IO (Maybe Text)
columnTextMaybe stmt index = do
  isNull <- NSQL.columnIsNull stmt (fromIntegral index)
  if isNull then pure Nothing else Just <$> NSQL.columnText stmt (fromIntegral index)

columnIntMaybe :: NSQL.Statement -> Int -> IO (Maybe Int)
columnIntMaybe stmt index = do
  isNull <- NSQL.columnIsNull stmt (fromIntegral index)
  if isNull then pure Nothing else Just <$> NSQL.columnInt stmt (fromIntegral index)

renderReview
  :: Text
  -> Text
  -> SnapshotMetadata
  -> OverlayLineage
  -> [CandidateReview]
  -> RuntimePromotionEvaluation
  -> Text
renderReview snapshotId overlayVersion snapshot lineage candidates runtimeEvaluation =
  T.unlines
    [ "# Promotion Review"
    , ""
    , "## Lineage"
    , "- Snapshot: `" <> snapshotId <> "`"
    , "- Snapshot checksum: `" <> smChecksum snapshot <> "`"
    , "- Runtime edges: " <> showText (smEdgeCount snapshot)
    , "- Overlay: `" <> overlayVersion <> "`"
    , "- Overlay status: `" <> olStatus lineage <> "`"
    , "- Gate run: `" <> olGateRunId lineage <> "`"
    , "- Policy: `" <> olPolicyVersion lineage <> "`"
    , "- Policy checksum: `" <> olPolicyChecksum lineage <> "`"
    , "- Request/response lineage: shown below when the snapshot captured it; legacy rows without complete lineage remain explicitly empty."
    , ""
    , "## Candidates"
    ]
    <> T.concat (map renderCandidateReview candidates)
    <> T.unlines
      [ "## Renderer A/B"
      , "- Runtime evaluation: `" <> rpeEvaluationId runtimeEvaluation <> "`"
      , "- Corpus evaluation: `" <> rpeCorpusEvaluationId runtimeEvaluation <> "`"
      , "- Evaluation corpus: `" <> rpeCorpusVersion runtimeEvaluation <> "`"
      , "- Runtime math version: `" <> showText (rpeMathVersion runtimeEvaluation) <> "`"
      , "- Automated runtime gate: " <> boolText (rpeAutomatedGatePassed runtimeEvaluation)
      , "- Activation: blocked (`" <> rpeActivationBlocker runtimeEvaluation <> "`)"
      , ""
      ]
    <> renderMetrics (rpeMetrics runtimeEvaluation)
    <> T.unlines ["", "### Answer Examples", ""]
    <> T.concat (map renderEvaluationCase (take 4 (rpeCases runtimeEvaluation)))

renderRevalidationReport
  :: Text
  -> Text
  -> SnapshotMetadata
  -> GateRunLineage
  -> Maybe Text
  -> [CandidateReview]
  -> Text
renderRevalidationReport snapshotId priorOverlayVersion snapshot lineage priorStatus candidates =
  T.unlines
    [ "# Promotion Revalidation Review"
    , ""
    , "## Lineage"
    , "- Snapshot: `" <> snapshotId <> "`"
    , "- Snapshot checksum: `" <> smChecksum snapshot <> "`"
    , "- Runtime edges: " <> showText (smEdgeCount snapshot)
    , "- Prior overlay: `" <> priorOverlayVersion <> "`"
    , "- Prior overlay status: `" <> maybe "missing" id priorStatus <> "`"
    , "- Gate run: `" <> glGateRunId lineage <> "`"
    , "- Policy: `" <> glPolicyVersion lineage <> "`"
    , "- Policy checksum: `" <> glPolicyChecksum lineage <> "`"
    , "- Request/response lineage: shown below when the snapshot captured it; legacy rows without complete lineage remain explicitly empty."
    , ""
    , "## Outcome"
    , "- Previous overlay candidates: " <> showText (length candidates)
    , "- Eligible after revalidation: " <> showText (length (filter ((== "eligible_for_draft") . crStatus) candidates))
    , "- No new draft was created and no renderer A/B was run: the policy left no candidate corpus to evaluate."
    , "- Activation remains blocked."
    , ""
    , "## Candidate Gate Details"
    , ""
    ]
    <> T.concat (map renderCandidateReview candidates)

renderCandidateReview :: CandidateReview -> Text
renderCandidateReview candidate =
  T.unlines
    [ "### `" <> crCandidateId candidate <> "`"
    , "- Topic: `" <> crTopic candidate <> "`"
    , "- Canonical triple: `" <> crSubject candidate <> " | " <> crRelation candidate <> " | " <> crObject candidate <> "`"
    , "- Russian predicate: " <> crRendered candidate
    , "- Confidence/support: " <> showText (crConfidence candidate) <> " / " <> showText (crSupportCount candidate)
    , "- Status: `" <> crStatus candidate <> "`"
    , "- Evidence lineage: " <> renderEvidenceLineage (crEvidenceLineage candidate)
    , "- Gate details: " <> renderGateDecisions (crGateDecisions candidate)
    , ""
    ]

renderGateDecisions :: [(Text, Text, Text, Text)] -> Text
renderGateDecisions decisions =
  T.intercalate "; "
    [ gateName <> "=" <> decision <> "(" <> reason <> ": " <> detail <> ")"
    | (gateName, decision, reason, detail) <- decisions
    ]

renderEvidenceLineage :: [EvidenceLineage] -> Text
renderEvidenceLineage [] = "none captured"
renderEvidenceLineage lineage =
  T.intercalate "; "
    [ "request=" <> elRequestId entry
        <> ", prompt=" <> elPromptHash entry
        <> ", response=" <> elResponseHash entry
        <> ", source=" <> elEvidenceSource entry
        <> ", model=" <> maybe "missing" id (elModel entry)
        <> ", parser=" <> maybe "missing" id (elParserDecision entry)
        <> ", admission=" <> maybe "missing" id (elAdmissionDecision entry)
        <> ", timestamp=" <> maybe "missing" showText (elEventTimestamp entry)
    | entry <- lineage
    ]

renderMetrics :: RuntimeEvaluationMetrics -> Text
renderMetrics metrics =
  T.unlines
    [ "### Metrics"
    , "- Contentful: baseline=" <> showText (remBaselineContentful metrics)
        <> ", candidate=" <> showText (remCandidateContentful metrics)
    , "- Refusals: baseline=" <> showText (remBaselineRefusals metrics)
        <> ", candidate=" <> showText (remCandidateRefusals metrics)
    , "- Structural conflicts: baseline=" <> showText (remBaselineConflicts metrics)
        <> ", candidate=" <> showText (remCandidateConflicts metrics)
    , "- Unsupported assertions: baseline=" <> showText (remBaselineUnsupportedAssertions metrics)
        <> ", candidate=" <> showText (remCandidateUnsupportedAssertions metrics)
    , "- Repeated answers: baseline=" <> showText (remBaselineRepeatedAnswers metrics)
        <> ", candidate=" <> showText (remCandidateRepeatedAnswers metrics)
    , "- Overlay usage cases: " <> showText (remOverlayUsageCases metrics)
    , "- Base regressions: " <> showText (remBaseRegressionCases metrics)
    , "- Runtime failures/timeouts: " <> showText (remRuntimeFailures metrics)
        <> "/" <> showText (remRuntimeTimeouts metrics)
    ]

renderEvaluationCase :: RuntimeEvaluationCase -> Text
renderEvaluationCase evaluationCase =
  let testCase = recCase evaluationCase
  in T.unlines
    [ "#### `" <> prcCaseId testCase <> "` (`" <> prcCategory testCase <> "`)"
    , "Prompt: " <> prcPrompt testCase
    , "Verdict: `" <> recFinalVerdict evaluationCase <> "`"
    , "Baseline: " <> renderSide (recBaseline evaluationCase)
    , "Candidate: " <> renderSide (recCandidate evaluationCase)
    , ""
    ]

renderSide :: RuntimeEvaluationSide -> Text
renderSide side =
  T.intercalate " | "
    [ "response=" <> quoted (resResponse side)
    , "selected=" <> listText (resSelectedPredicates side)
    , "overlay_ids=" <> listText (resOverlayPredicateIds side)
    , "content_source=" <> maybe "none" id (resContentSource side)
    , "replay_trace=" <> if hasTrace side then "recorded" else "missing"
    , "failure=" <> maybe "none" id (resFailure side)
    ]
  where
    hasTrace = maybe False (const True) . resReplayTrace

quoted :: Text -> Text
quoted = ("`" <>) . (<> "`") . T.replace "`" "'" . T.replace "\n" " "

listText :: [Text] -> Text
listText = ("[" <>) . (<> "]") . T.intercalate ", "

showText :: Show a => a -> Text
showText = T.pack . show

boolText :: Bool -> Text
boolText True = "pass"
boolText False = "fail"
