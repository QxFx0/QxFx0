{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Isolated renderer-level A/B evaluation for promotion overlays.
--
-- Runtime turns execute only against consistent SQLite snapshots in /tmp. The
-- operator database is read to build those snapshots, never mutated by this
-- module. Results retain rendered responses and replay traces in memory so the
-- CLI can emit one complete review artifact without promoting an overlay.
module QxFx0.Learning.PromotionRuntime
  ( PromotionRuntimeCase(..)
  , RuntimePredicateFact(..)
  , RuntimeEvaluationSide(..)
  , RuntimeEvaluationCase(..)
  , RuntimeEvaluationMetrics(..)
  , RuntimePromotionEvaluation(..)
  , runtimeEvaluationCorpusVersion
  , promotionRuntimeEvaluationCases
  , effectiveBasePredicateSurfaces
  , hasUnsupportedAssertion
  , hasStructuralConflict
  , failedRuntimeEvaluationSide
  , runtimeAutomatedGatePassed
  , runPromotionRuntimeEvaluation
  ) where

import Control.Exception (bracket, displayException, finally)
import Control.Monad (foldM)
import Data.Aeson (FromJSON, ToJSON)
import qualified Data.ByteString as BS
import Data.List (foldl', zipWith3)
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import GHC.Generics (Generic)
import System.Directory (doesFileExist, removeFile)
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.Timeout (timeout)
import Data.Time.Clock (UTCTime, getCurrentTime)
import Data.Time.Clock.POSIX (utcTimeToPOSIXSeconds)

import qualified QxFx0.Bridge.NativeSQLite as NSQL
import QxFx0.Bridge.SQLite (QxFx0DB(..), withDB)
import QxFx0.Learning.Promotion
  ( ensurePromotionSchema
  , promotionEvaluationCorpusVersion
  , promotionRuntimeCorpusVersion
  )
import QxFx0.Learning.Quarantine (sha256Hex)
import QxFx0.Runtime.Engine (runTurnInSession)
import QxFx0.Runtime.Session (Session)
import QxFx0.Runtime.Session.Bootstrap
  ( bootstrapSession
  , closeSession
  , loadBootstrapDefinitionCorpus
  )
import QxFx0.Semantic.Content (DefinitionContent(..), SemanticPredicate(..))
import QxFx0.Types.TurnProjection
  ( TurnReplayTrace(..)
  , decodePersistedReplayTrace
  )
import QxFx0.Types.RuntimeRegime (currentMathVersion)
import QxFx0.ExceptionPolicy (mkSQLiteError, throwQxFx0, tryAsync)

data PromotionRuntimeCase = PromotionRuntimeCase
  { prcCaseId :: !Text
  , prcCategory :: !Text
  , prcPrompt :: !Text
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

data RuntimeEvaluationSide = RuntimeEvaluationSide
  { resResponse :: !Text
  , resReplayTrace :: !(Maybe TurnReplayTrace)
  , resSelectedPredicates :: ![Text]
  , resOverlayPredicateIds :: ![Text]
  , resContentSource :: !(Maybe Text)
  , resContentful :: !Bool
  , resRefusal :: !Bool
  , resConflict :: !Bool
  , resUnsupportedAssertion :: !Bool
  , resFailure :: !(Maybe Text)
  , resTimedOut :: !Bool
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

data RuntimeEvaluationCase = RuntimeEvaluationCase
  { recCase :: !PromotionRuntimeCase
  , recBaseline :: !RuntimeEvaluationSide
  , recCandidate :: !RuntimeEvaluationSide
  , recFinalVerdict :: !Text
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

data RuntimeEvaluationMetrics = RuntimeEvaluationMetrics
  { remBaselineContentful :: !Int
  , remCandidateContentful :: !Int
  , remBaselineRefusals :: !Int
  , remCandidateRefusals :: !Int
  , remBaselineConflicts :: !Int
  , remCandidateConflicts :: !Int
  , remBaselineUnsupportedAssertions :: !Int
  , remCandidateUnsupportedAssertions :: !Int
  , remBaselineRepeatedAnswers :: !Int
  , remCandidateRepeatedAnswers :: !Int
  , remOverlayUsageCases :: !Int
  , remBaseRegressionCases :: !Int
  , remRuntimeFailures :: !Int
  , remRuntimeTimeouts :: !Int
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

data RuntimePromotionEvaluation = RuntimePromotionEvaluation
  { rpeEvaluationId :: !Text
  , rpeCorpusEvaluationId :: !Text
  , rpeOverlayVersion :: !Text
  , rpeCorpusVersion :: !Text
  , rpeMathVersion :: !Int
  , rpeCases :: ![RuntimeEvaluationCase]
  , rpeMetrics :: !RuntimeEvaluationMetrics
  , rpeAutomatedGatePassed :: !Bool
  , rpeActivationEligible :: !Bool
  , rpeActivationBlocker :: !Text
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

runtimeEvaluationCorpusVersion :: Text
runtimeEvaluationCorpusVersion = promotionRuntimeCorpusVersion

-- | Versioned fixed regression corpus. Overlay-specific cases are appended in
-- 'promotionRuntimeEvaluationCases' from the candidate's own declared topics.
fixedRuntimeEvaluationCases :: [PromotionRuntimeCase]
fixedRuntimeEvaluationCases =
  [ PromotionRuntimeCase "base-freedom" "base_regression" "Что такое свобода?"
  , PromotionRuntimeCase "base-truth" "base_regression" "Что такое истина?"
  , PromotionRuntimeCase "unknown-topic" "unknown" "Что такое ксеномодус?"
  , PromotionRuntimeCase "conflict" "conflict" "Свобода и необходимость несовместимы?"
  , PromotionRuntimeCase "ambiguous" "ambiguous" "Что это?"
  , PromotionRuntimeCase "quality-gate" "refusal_quality" "Докажи безусловно, что любая свобода ведет к хаосу."
  ]

promotionRuntimeEvaluationCases :: [Text] -> [PromotionRuntimeCase]
promotionRuntimeEvaluationCases overlayTopics =
  fixedRuntimeEvaluationCases ++ concatMap overlayCases (take maxOverlayTopics uniqueTopics)
  where
    uniqueTopics = S.toList (S.fromList (map normalizedText overlayTopics))
    maxOverlayTopics = 8
    overlayCases topic =
      [ PromotionRuntimeCase
          ("overlay-topic-" <> stableId topic)
          "overlay_topic"
          ("Что такое " <> topic <> "?")
      , PromotionRuntimeCase
          ("overlay-neighbor-" <> stableId topic)
          "overlay_neighbor"
          ("Как " <> topic <> " связано с ответственностью?")
      ]

runPromotionRuntimeEvaluation :: QxFx0DB -> Text -> IO RuntimePromotionEvaluation
runPromotionRuntimeEvaluation db overlayVersion = do
  ensurePromotionSchema db
  overlay <- loadOverlayInput (qdbPath db) overlayVersion
  (corpusEvaluationId, overlayChecksum) <- loadEvaluationInput (qdbPath db) overlayVersion
  now <- getCurrentTime
  let evaluationId = "runtime-eval-" <> T.pack (show (utcMicros now))
  baseAuthority <- basePredicateAuthority
  referenceFacts <- loadPromotionFacts (qdbPath db)
  let stem = "/tmp/qxfx0-promotion-runtime-" <> T.unpack
        (sha256Hex (TE.encodeUtf8 (T.pack (qdbPath db) <> "|" <> overlayVersion)))
      baselinePath = stem <> "-baseline.db"
      candidatePath = stem <> "-candidate.db"
      cleanup = cleanupDb baselinePath >> cleanupDb candidatePath
      cases = promotionRuntimeEvaluationCases (oiTopics overlay)
      candidateAuthority = mergePredicateAuthority baseAuthority (overlayPredicateAuthority overlay referenceFacts)
  cleanup
  (do
      snapshotDb (qdbPath db) baselinePath
      snapshotDb (qdbPath db) candidatePath
      configureBaselineCopy baselinePath overlayVersion
      activateCandidateCopy candidatePath overlayVersion corpusEvaluationId evaluationId overlayChecksum
      baseline <- runCorpus baselinePath "promotion-ab-baseline" cases baseAuthority
      candidate <- runCorpus candidatePath "promotion-ab-candidate" cases candidateAuthority
      let evaluatedCases = zipWith3 buildCase cases baseline candidate
          metrics = collectMetrics evaluatedCases
          automatedGatePassed = runtimeAutomatedGatePassed metrics
      let evaluation = RuntimePromotionEvaluation
            { rpeEvaluationId = evaluationId
            , rpeCorpusEvaluationId = corpusEvaluationId
            , rpeOverlayVersion = overlayVersion
            , rpeCorpusVersion = runtimeEvaluationCorpusVersion
            , rpeMathVersion = currentMathVersion
            , rpeCases = evaluatedCases
            , rpeMetrics = metrics
            , rpeAutomatedGatePassed = automatedGatePassed
            -- The evaluator deliberately cannot attest human review. Activation is
            -- therefore never enabled as a side effect of a runtime experiment.
            , rpeActivationEligible = False
            , rpeActivationBlocker =
                if automatedGatePassed
                  then "human_review_required"
                  else "automated_runtime_gate_failed"
            }
      persistRuntimeEvaluation db overlayChecksum evaluation
      pure evaluation
    ) `finally` cleanup

data OverlayInput = OverlayInput
  { oiTopics :: ![Text]
  , oiFactsBySurface :: !(M.Map Text [RuntimePredicateFact])
  }

data RuntimePredicateFact = RuntimePredicateFact
  { rpfSubject :: !Text
  , rpfRelation :: !Text
  , rpfObject :: !Text
  }
  deriving stock (Eq, Show)

data PredicateAuthority = PredicateAuthority
  { paAllowedSurfaces :: !(S.Set Text)
  , paFactsBySurface :: !(M.Map Text [RuntimePredicateFact])
  , paReferenceFacts :: ![RuntimePredicateFact]
  }

loadOverlayInput :: FilePath -> Text -> IO OverlayInput
loadOverlayInput dbPath version = do
  result <- withDB dbPath $ \conn -> do
    versions <- loadOverlayVersions conn version
    concat <$> mapM (loadRows conn) versions
  rows <- either throwPromotionRuntimeError pure result
  if null rows
    then throwPromotionRuntimeError "promotion overlay has no predicates"
    else pure ()
  pure OverlayInput
    { oiTopics = [topic | (topic, _, _, _, _) <- rows]
    , oiFactsBySurface = M.fromListWith (++)
        [ (normalizedText variant, [fact])
        | (_, surface, subject, relation, object) <- rows
        , let fact = RuntimePredicateFact subject relation object
        , variant <- overlaySurfaceVariants surface fact
        ]
    }
  where
    loadRows conn overlayVersion = do
      prepared <- NSQL.prepare conn "SELECT topic, predicate_ru, subject_atom, relation_type, object_atom FROM promotion_overlay_predicates WHERE overlay_version = ? ORDER BY topic, predicate_id"
      case prepared of
        Left err -> throwPromotionRuntimeError err
        Right stmt -> do
          _ <- NSQL.bindText stmt 1 overlayVersion
          collect stmt []

    collect stmt acc = do
      hasRow <- NSQL.stepRow stmt
      if not hasRow
        then NSQL.finalize stmt >> pure (reverse acc)
        else do
          topic <- NSQL.columnText stmt 0
          surface <- NSQL.columnText stmt 1
          subject <- NSQL.columnText stmt 2
          relation <- NSQL.columnText stmt 3
          object <- NSQL.columnText stmt 4
          collect stmt ((topic, surface, subject, relation, object) : acc)

    overlaySurfaceVariants surface fact =
      S.toList (S.fromList (surface : renderedSurface fact))

    renderedSurface fact =
      case normalizedText (rpfRelation fact) of
        "related_to" ->
          [ rpfSubject fact <> " связана с " <> overlayInstrumental (rpfObject fact) ]
        _ -> []

    overlayInstrumental object
      | T.isSuffixOf "ое" object = T.dropEnd 2 object <> "ым"
      | T.isSuffixOf "ее" object = T.dropEnd 2 object <> "им"
      | otherwise = object

loadOverlayVersions :: NSQL.Database -> Text -> IO [Text]
loadOverlayVersions conn = go S.empty
  where
    go seen overlayVersion
      | overlayVersion `S.member` seen = throwPromotionRuntimeError "promotion overlay parent cycle detected"
      | otherwise = do
          prepared <- NSQL.prepare conn "SELECT parent_version FROM promotion_overlays WHERE overlay_version=?"
          case prepared of
            Left err -> throwPromotionRuntimeError err
            Right stmt -> do
              _ <- NSQL.bindText stmt 1 overlayVersion
              found <- NSQL.stepRow stmt
              if not found
                then NSQL.finalize stmt >> throwPromotionRuntimeError "promotion overlay lineage references a missing artifact"
                else do
                  parentNull <- NSQL.columnIsNull stmt 0
                  parent <- if parentNull then pure Nothing else Just <$> NSQL.columnText stmt 0
                  NSQL.finalize stmt
                  ancestors <- maybe (pure []) (go (S.insert overlayVersion seen)) parent
                  pure (ancestors ++ [overlayVersion])

loadEvaluationInput :: FilePath -> Text -> IO (Text, Text)
loadEvaluationInput dbPath overlayVersion = do
  result <- withDB dbPath $ \conn -> do
    prepared <- NSQL.prepare conn
      "SELECT e.evaluation_id, e.overlay_checksum, e.corpus_version, e.passed, o.checksum FROM promotion_evaluations e JOIN promotion_overlays o ON o.overlay_version=e.overlay_version WHERE e.overlay_version=? ORDER BY e.created_at DESC, e.evaluation_id DESC LIMIT 1"
    case prepared of
      Left err -> throwPromotionRuntimeError err
      Right stmt -> do
        _ <- NSQL.bindText stmt 1 overlayVersion
        hasRow <- NSQL.stepRow stmt
        evaluationInput <- if hasRow
          then do
            evaluationId <- NSQL.columnText stmt 0
            evaluationChecksum <- NSQL.columnText stmt 1
            corpusVersion <- NSQL.columnText stmt 2
            passed <- NSQL.columnInt stmt 3
            overlayChecksum <- NSQL.columnText stmt 4
            if corpusVersion == promotionEvaluationCorpusVersion
                && passed == 1
                && evaluationChecksum == overlayChecksum
              then pure (evaluationId, overlayChecksum)
              else throwPromotionRuntimeError "latest promotion corpus evaluation is failed, stale, or bound to another artifact"
          else throwPromotionRuntimeError "promotion overlay requires a current passing corpus evaluation before renderer A/B"
        NSQL.finalize stmt
        pure evaluationInput
  either throwPromotionRuntimeError pure result

-- | Overlay rows remain data, not display authority. They are only used here
-- to identify declared relation conflicts for predicates actually emitted by
-- the renderer, including facts from historical overlays.
loadPromotionFacts :: FilePath -> IO [RuntimePredicateFact]
loadPromotionFacts dbPath = do
  result <- withDB dbPath $ \conn -> do
    prepared <- NSQL.prepare conn "SELECT subject_atom, relation_type, object_atom FROM promotion_overlay_predicates"
    case prepared of
      Left err -> throwPromotionRuntimeError err
      Right stmt -> collect stmt []
  either throwPromotionRuntimeError pure result
  where
    collect stmt acc = do
      hasRow <- NSQL.stepRow stmt
      if not hasRow
        then NSQL.finalize stmt >> pure (reverse acc)
        else do
          subject <- NSQL.columnText stmt 0
          relation <- NSQL.columnText stmt 1
          object <- NSQL.columnText stmt 2
          collect stmt (RuntimePredicateFact subject relation object : acc)

-- | 'VACUUM INTO' is SQLite's consistent online snapshot operation. Unlike
-- copying a database file with a live WAL, it cannot split a database from its
-- WAL state and does not modify the source database.
snapshotDb :: FilePath -> FilePath -> IO ()
snapshotDb source target = do
  cleanupDb target
  let quotedTarget = T.replace "'" "''" (T.pack target)
  result <- withDB source $ \conn -> NSQL.execSql conn ("VACUUM INTO '" <> quotedTarget <> "'")
  either throwPromotionRuntimeError (either throwPromotionRuntimeError pure) result

-- | The comparison side is the candidate's declared parent, or the
-- overlay-free corpus for a root artifact. This is explicit even when the
-- operator database currently has the candidate active for revalidation.
configureBaselineCopy :: FilePath -> Text -> IO ()
configureBaselineCopy path version = do
  result <- withDB path $ \conn -> do
    prepared <- NSQL.prepare conn
      "SELECT parent_version, prior_runtime_evaluation_id FROM promotion_overlays WHERE overlay_version=?"
    case prepared of
      Left err -> throwPromotionRuntimeError err
      Right stmt -> do
        _ <- NSQL.bindText stmt 1 version
        found <- NSQL.stepRow stmt
        if not found
          then NSQL.finalize stmt >> throwPromotionRuntimeError "promotion baseline candidate is missing"
          else do
            parent <- columnTextMaybe stmt 0
            priorEvaluation <- columnTextMaybe stmt 1
            NSQL.finalize stmt
            current <- loadActiveCopyPointer conn
            baselineEvaluation <- case parent of
              Nothing -> pure Nothing
              Just parentVersion -> case current of
                Just (activeVersion, Just activeEvaluation) | activeVersion == parentVersion ->
                  pure (Just activeEvaluation)
                _ -> maybe
                  (throwPromotionRuntimeError "promotion baseline cannot identify the parent evaluation")
                  (pure . Just) priorEvaluation
            execBaseline conn parent baselineEvaluation
  either throwPromotionRuntimeError pure result
  where
    execBaseline conn parent evaluation = do
      cleared <- NSQL.execSql conn "UPDATE promotion_overlays SET status='superseded' WHERE status='active'"
      either throwPromotionRuntimeError pure cleared
      case parent of
        Nothing -> do
          updated <- NSQL.execSql conn
            "INSERT INTO promotion_active(singleton, overlay_version, runtime_evaluation_id, updated_at) VALUES(1, NULL, NULL, strftime('%s','now')) ON CONFLICT(singleton) DO UPDATE SET overlay_version=NULL, runtime_evaluation_id=NULL, updated_at=excluded.updated_at"
          either throwPromotionRuntimeError pure updated
        Just parentVersion -> do
          evaluationId <- maybe (throwPromotionRuntimeError "promotion parent baseline lacks an evaluation") pure evaluation
          let escapedParent = T.replace "'" "''" parentVersion
              escapedEvaluation = T.replace "'" "''" evaluationId
          updated <- NSQL.execSql conn
            ("UPDATE promotion_overlays SET status='active' WHERE overlay_version='" <> escapedParent <> "';"
              <> "INSERT INTO promotion_active(singleton, overlay_version, runtime_evaluation_id, updated_at) VALUES(1, '" <> escapedParent <> "', '" <> escapedEvaluation <> "', strftime('%s','now')) ON CONFLICT(singleton) DO UPDATE SET overlay_version=excluded.overlay_version, runtime_evaluation_id=excluded.runtime_evaluation_id, updated_at=excluded.updated_at")
          either throwPromotionRuntimeError pure updated

loadActiveCopyPointer :: NSQL.Database -> IO (Maybe (Text, Maybe Text))
loadActiveCopyPointer conn = do
  prepared <- NSQL.prepare conn
    "SELECT overlay_version, runtime_evaluation_id FROM promotion_active WHERE singleton=1 AND overlay_version IS NOT NULL"
  case prepared of
    Left err -> throwPromotionRuntimeError err
    Right stmt -> do
      found <- NSQL.stepRow stmt
      value <- if found
        then Just <$> ((,) <$> NSQL.columnText stmt 0 <*> columnTextMaybe stmt 1)
        else pure Nothing
      NSQL.finalize stmt
      pure value

columnTextMaybe :: NSQL.Statement -> Int -> IO (Maybe Text)
columnTextMaybe stmt index = do
  isNull <- NSQL.columnIsNull stmt (fromIntegral index)
  if isNull then pure Nothing else Just <$> NSQL.columnText stmt (fromIntegral index)

activateCandidateCopy :: FilePath -> Text -> Text -> Text -> Text -> IO ()
activateCandidateCopy path version corpusEvaluationId runtimeEvaluationId overlayChecksum = do
  result <- withDB path $ \conn -> do
    let escaped = T.replace "'" "''" version
        escapedCorpusEvaluation = T.replace "'" "''" corpusEvaluationId
        escapedRuntimeEvaluation = T.replace "'" "''" runtimeEvaluationId
        escapedOverlayChecksum = T.replace "'" "''" overlayChecksum
        escapedRuntimeCorpusVersion = T.replace "'" "''" runtimeEvaluationCorpusVersion
        mathVersion = T.pack (show currentMathVersion)
        activate = "UPDATE promotion_overlays SET status='superseded' WHERE status='active';"
          <> "UPDATE promotion_overlays SET status='active' WHERE overlay_version='" <> escaped <> "';"
          <> "INSERT INTO promotion_runtime_evaluations(evaluation_id, overlay_version, corpus_evaluation_id, completed_at, runtime_corpus_version, math_version, overlay_checksum, automated_passed, overlay_usage_cases, details) VALUES('" <> escapedRuntimeEvaluation <> "', '" <> escaped <> "', '" <> escapedCorpusEvaluation <> "', strftime('%s','now')*1000000, '" <> escapedRuntimeCorpusVersion <> "', " <> mathVersion <> ", '" <> escapedOverlayChecksum <> "', 1, 1, 'isolated_candidate_bootstrap_only');"
          <> "INSERT INTO promotion_runtime_release_gates(overlay_version, evaluation_id, completed_at, release_passed, human_reviewed, details) VALUES('" <> escaped <> "', '" <> escapedRuntimeEvaluation <> "', strftime('%s','now')*1000000, 1, 1, 'isolated_candidate_bootstrap_only');"
          <> "INSERT INTO promotion_active(singleton, overlay_version, runtime_evaluation_id, updated_at) VALUES(1, '" <> escaped <> "', '" <> escapedRuntimeEvaluation <> "', strftime('%s','now')) ON CONFLICT(singleton) DO UPDATE SET overlay_version=excluded.overlay_version, runtime_evaluation_id=excluded.runtime_evaluation_id, updated_at=excluded.updated_at;"
    NSQL.execSql conn activate
  either throwPromotionRuntimeError (either throwPromotionRuntimeError pure) result

persistRuntimeEvaluation :: QxFx0DB -> Text -> RuntimePromotionEvaluation -> IO ()
persistRuntimeEvaluation db overlayChecksum evaluation = do
  let escapedEvaluation = T.replace "'" "''" (rpeEvaluationId evaluation)
      escapedOverlay = T.replace "'" "''" (rpeOverlayVersion evaluation)
      escapedCorpusEvaluation = T.replace "'" "''" (rpeCorpusEvaluationId evaluation)
      escapedCorpusVersion = T.replace "'" "''" (rpeCorpusVersion evaluation)
      escapedOverlayChecksum = T.replace "'" "''" overlayChecksum
      escapedDetails = T.replace "'" "''" (T.pack (show (rpeMetrics evaluation)))
      passed = if rpeAutomatedGatePassed evaluation then "1" else "0"
      usage = T.pack (show (remOverlayUsageCases (rpeMetrics evaluation)))
      mathVersion = T.pack (show (rpeMathVersion evaluation))
      sql = "INSERT INTO promotion_runtime_evaluations(evaluation_id, overlay_version, corpus_evaluation_id, completed_at, runtime_corpus_version, math_version, overlay_checksum, automated_passed, overlay_usage_cases, details) VALUES('"
        <> escapedEvaluation <> "', '" <> escapedOverlay <> "', '" <> escapedCorpusEvaluation
        <> "', strftime('%s','now')*1000000, '" <> escapedCorpusVersion <> "', " <> mathVersion
        <> ", '" <> escapedOverlayChecksum <> "', " <> passed <> ", " <> usage <> ", '" <> escapedDetails <> "')"
  result <- withDB (qdbPath db) (\conn -> NSQL.execSql conn sql)
  either throwPromotionRuntimeError (either throwPromotionRuntimeError pure) result

runCorpus :: FilePath -> Text -> [PromotionRuntimeCase] -> PredicateAuthority -> IO [RuntimeEvaluationSide]
runCorpus path sessionId cases authority =
  withEnv "QXFX0_DB" path $
    withEnv "QXFX0_AUTONOMOUS_LEARNING" "false" $ do
      boot <- tryAsync (timeout bootstrapTimeoutMicros (bootstrapSession True sessionId))
      case boot of
        Left err -> pure (replicate (length cases) (failedRuntimeEvaluationSide ("bootstrap_failure:" <> T.pack (displayException err)) False))
        Right Nothing -> pure (replicate (length cases) (failedRuntimeEvaluationSide "bootstrap_timeout" True))
        Right (Just session) ->
          bracket (pure session) closeSession $ \initial -> do
            (_, sides) <- foldM (runCase path sessionId authority) (initial, []) cases
            pure (reverse sides)

runCase
  :: FilePath
  -> Text
  -> PredicateAuthority
  -> (Session, [RuntimeEvaluationSide])
  -> PromotionRuntimeCase
  -> IO (Session, [RuntimeEvaluationSide])
runCase path sessionId authority (session, acc) testCase = do
  result <- tryAsync (timeout turnTimeoutMicros (runTurnInSession session (prcPrompt testCase)))
  case result of
    Left err ->
      pure (session, failedRuntimeEvaluationSide ("turn_failure:" <> T.pack (displayException err)) False : acc)
    Right Nothing -> pure (session, failedRuntimeEvaluationSide "turn_timeout" True : acc)
    Right (Just (nextSession, response)) -> do
      traceResult <- tryAsync (loadLatestTrace path sessionId)
      let trace = either (const Nothing) id traceResult
          selected = maybe [] trcEmittedPredicates trace
          overlayIds = maybe [] trcOverlayPredicateIds trace
          refusal = isRefusal response
          contentful = isContentful response refusal
          conflict = hasStructuralConflict selected (paFactsBySurface authority) (paReferenceFacts authority)
          unsupported = hasUnsupportedAssertion selected (paAllowedSurfaces authority)
          traceFailure = case traceResult of
            Left err -> Just ("trace_read_failure:" <> T.pack (displayException err))
            Right Nothing -> Just "missing_replay_trace"
            Right (Just _) -> Nothing
          side = RuntimeEvaluationSide
            { resResponse = response
            , resReplayTrace = trace
            , resSelectedPredicates = selected
            , resOverlayPredicateIds = overlayIds
            , resContentSource = trace >>= trcContentSource
            , resContentful = contentful
            , resRefusal = refusal
            , resConflict = conflict
            , resUnsupportedAssertion = unsupported
            , resFailure = traceFailure
            , resTimedOut = False
            }
      pure (nextSession, side : acc)

loadLatestTrace :: FilePath -> Text -> IO (Maybe TurnReplayTrace)
loadLatestTrace dbPath sessionId = do
  result <- withDB dbPath $ \conn -> do
    prepared <- NSQL.prepare conn "SELECT replay_trace_json FROM turn_quality WHERE session_id = ? ORDER BY turn DESC LIMIT 1"
    case prepared of
      Left err -> throwPromotionRuntimeError err
      Right stmt -> do
        _ <- NSQL.bindText stmt 1 sessionId
        hasRow <- NSQL.stepRow stmt
        raw <- if hasRow then Just <$> NSQL.columnTextLenient stmt 0 else pure Nothing
        NSQL.finalize stmt
        pure raw
  raw <- either throwPromotionRuntimeError pure result
  case raw of
    Nothing -> pure Nothing
    Just json ->
      case decodePersistedReplayTrace (TE.encodeUtf8 json) of
        Left err -> throwPromotionRuntimeError ("cannot decode replay trace: " <> T.pack err)
        Right trace -> pure (Just trace)

buildCase :: PromotionRuntimeCase -> RuntimeEvaluationSide -> RuntimeEvaluationSide -> RuntimeEvaluationCase
buildCase testCase baseline candidate =
  RuntimeEvaluationCase testCase baseline candidate (caseVerdict testCase baseline candidate)

caseVerdict :: PromotionRuntimeCase -> RuntimeEvaluationSide -> RuntimeEvaluationSide -> Text
caseVerdict testCase baseline candidate
  | resTimedOut baseline || resTimedOut candidate = "runtime_timeout"
  | hasFailure baseline || hasFailure candidate = "runtime_failure"
  | resConflict candidate = "candidate_conflict"
  | resUnsupportedAssertion candidate = "candidate_unsupported_assertion"
  | prcCategory testCase == "base_regression" && resContentful baseline && not (resContentful candidate) = "base_regression"
  | otherwise = "pass"
  where
    hasFailure = maybe False (const True) . resFailure

collectMetrics :: [RuntimeEvaluationCase] -> RuntimeEvaluationMetrics
collectMetrics cases = RuntimeEvaluationMetrics
  { remBaselineContentful = count (resContentful . recBaseline)
  , remCandidateContentful = count (resContentful . recCandidate)
  , remBaselineRefusals = count (resRefusal . recBaseline)
  , remCandidateRefusals = count (resRefusal . recCandidate)
  , remBaselineConflicts = count (resConflict . recBaseline)
  , remCandidateConflicts = count (resConflict . recCandidate)
  , remBaselineUnsupportedAssertions = count (resUnsupportedAssertion . recBaseline)
  , remCandidateUnsupportedAssertions = count (resUnsupportedAssertion . recCandidate)
  , remBaselineRepeatedAnswers = repeatedAnswers (map (resResponse . recBaseline) cases)
  , remCandidateRepeatedAnswers = repeatedAnswers (map (resResponse . recCandidate) cases)
  , remOverlayUsageCases = count (not . null . resOverlayPredicateIds . recCandidate)
  , remBaseRegressionCases = count ((== "base_regression") . recFinalVerdict)
  , remRuntimeFailures = count (hasFailure . recBaseline) + count (hasFailure . recCandidate)
  , remRuntimeTimeouts = count (resTimedOut . recBaseline) + count (resTimedOut . recCandidate)
  }
  where
    count predicate = length (filter predicate cases)
    hasFailure = maybe False (const True) . resFailure

runtimeAutomatedGatePassed :: RuntimeEvaluationMetrics -> Bool
runtimeAutomatedGatePassed metrics =
  remRuntimeFailures metrics == 0
    && remRuntimeTimeouts metrics == 0
    && remCandidateContentful metrics >= remBaselineContentful metrics
    && remCandidateRefusals metrics <= remBaselineRefusals metrics
    && remCandidateConflicts metrics == 0
    && remCandidateUnsupportedAssertions metrics == 0
    && remBaseRegressionCases metrics == 0
    -- A candidate that never reaches the renderer has not been evaluated,
    -- even when baseline-equivalent answers make every other metric look
    -- healthy. Promotion must fail closed until at least one emitted predicate
    -- is attributed to the overlay in the replay trace.
    && remOverlayUsageCases metrics > 0

-- | Match the same curated+seed corpus construction used by Bootstrap. This
-- prevents a valid curated predicate from being mislabeled unsupported by the
-- runtime evaluator.
effectiveBasePredicateSurfaces :: IO (S.Set Text)
effectiveBasePredicateSurfaces = paAllowedSurfaces <$> basePredicateAuthority

basePredicateAuthority :: IO PredicateAuthority
basePredicateAuthority = do
  corpus <- loadBootstrapDefinitionCorpus
  pure PredicateAuthority
    { paAllowedSurfaces = S.fromList
        [ normalizedText (spRu predicate)
        | content <- M.elems corpus
        , predicate <- dcPredicates content
        ]
    , paFactsBySurface = M.empty
    , paReferenceFacts = []
    }

overlayPredicateAuthority :: OverlayInput -> [RuntimePredicateFact] -> PredicateAuthority
overlayPredicateAuthority overlay referenceFacts = PredicateAuthority
  { paAllowedSurfaces = M.keysSet (oiFactsBySurface overlay)
  , paFactsBySurface = oiFactsBySurface overlay
  , paReferenceFacts = referenceFacts
  }

mergePredicateAuthority :: PredicateAuthority -> PredicateAuthority -> PredicateAuthority
mergePredicateAuthority base overlay = PredicateAuthority
  { paAllowedSurfaces = S.union (paAllowedSurfaces base) (paAllowedSurfaces overlay)
  , paFactsBySurface = M.unionWith (++) (paFactsBySurface overlay) (paFactsBySurface base)
  , paReferenceFacts = paReferenceFacts overlay ++ paReferenceFacts base
  }

isContentful :: Text -> Bool -> Bool
isContentful response refusal = T.length (T.strip response) >= 32 && not refusal

isRefusal :: Text -> Bool
isRefusal response = any (`T.isInfixOf` normalizedText response)
  [ "не могу ответить"
  , "недостаточно данных"
  , "неизвестно"
  , "отказываюсь"
  , "не буду продолжать"
  , "содержание не прошло проверку"
  ]

hasUnsupportedAssertion :: [Text] -> S.Set Text -> Bool
hasUnsupportedAssertion selected allowed =
  not (null selected) && any (`S.notMember` allowed) (map normalizedText selected)

-- | Conflict is evaluated over selected, structured promotion facts only.
-- Surface words such as "конфликт" in a recovery narrative are not facts and
-- must not turn an otherwise valid answer into a false factual conflict.
hasStructuralConflict
  :: [Text]
  -> M.Map Text [RuntimePredicateFact]
  -> [RuntimePredicateFact]
  -> Bool
hasStructuralConflict selected factsBySurface referenceFacts =
  any forbiddenRelation selectedFacts
    || any (\selectedFact -> any (relationConflict selectedFact) referenceFacts) selectedFacts
  where
    selectedFacts = concatMap factsFor selected
    factsFor surface = M.findWithDefault [] (normalizedText surface) factsBySurface
    forbiddenRelation fact = normalizedText (rpfRelation fact) `elem` negativeRelations
    relationConflict left right =
      sameEndpoints left right
        && oppositePolarity (normalizedText (rpfRelation left)) (normalizedText (rpfRelation right))
    sameEndpoints left right =
      normalizedText (rpfSubject left) == normalizedText (rpfSubject right)
        && normalizedText (rpfObject left) == normalizedText (rpfObject right)
    oppositePolarity left right =
      (isNegativeRelation left && isPositiveRelation right)
        || (isPositiveRelation left && isNegativeRelation right)
    negativeRelations = ["contrasts_with", "negates", "is_not", "not_reducible_to"]
    isNegativeRelation relation = relation `elem` negativeRelations
    isPositiveRelation relation = relation `elem`
      [ "is_a", "part_of", "requires", "presupposes", "causes" ]

repeatedAnswers :: [Text] -> Int
repeatedAnswers responses =
  let counts = foldl'
        (\acc response ->
          let normalized = normalizedText response
          in if T.null normalized then acc else M.insertWith (+) normalized (1 :: Int) acc
        )
        M.empty
        responses
  in sum [count - 1 | count <- M.elems counts, count > 1]

failedRuntimeEvaluationSide :: Text -> Bool -> RuntimeEvaluationSide
failedRuntimeEvaluationSide failure timedOut = RuntimeEvaluationSide
  { resResponse = ""
  , resReplayTrace = Nothing
  , resSelectedPredicates = []
  , resOverlayPredicateIds = []
  , resContentSource = Nothing
  , resContentful = False
  , resRefusal = False
  , resConflict = False
  , resUnsupportedAssertion = False
  , resFailure = Just failure
  , resTimedOut = timedOut
  }

withEnv :: String -> FilePath -> IO a -> IO a
withEnv key value action = do
  previous <- lookupEnv key
  setEnv key value
  action `finally` restore previous
  where
    restore Nothing = unsetEnv key
    restore (Just old) = setEnv key old

cleanupDb :: FilePath -> IO ()
cleanupDb path = mapM_ removeIfExists [path, path <> "-wal", path <> "-shm"]
  where
    removeIfExists candidate = do
      exists <- doesFileExist candidate
      if exists then removeFile candidate else pure ()

throwPromotionRuntimeError :: Text -> IO a
throwPromotionRuntimeError detail =
  throwQxFx0 (mkSQLiteError
    "promotion_runtime_evaluation"
    "PROMOTION_RUNTIME_SQLITE_ERROR"
    (M.singleton "detail" detail))

normalizedText :: Text -> Text
normalizedText = T.toLower . T.strip

stableId :: Text -> Text
stableId = T.take 16 . sha256Hex . TE.encodeUtf8

utcMicros :: UTCTime -> Integer
utcMicros = floor . (* 1000000) . utcTimeToPOSIXSeconds

bootstrapTimeoutMicros :: Int
bootstrapTimeoutMicros = 120 * 1000000

turnTimeoutMicros :: Int
turnTimeoutMicros = 45 * 1000000
