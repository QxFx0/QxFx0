{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.PromotionRuntime
  ( promotionRuntimeTests
  ) where

import Control.Exception (SomeException, finally, try)
import qualified Data.Map.Strict as M
import Data.Maybe (listToMaybe)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import System.Environment (lookupEnv)
import Test.HUnit

import qualified QxFx0.Bridge.NativeSQLite as NSQL
import QxFx0.Bridge.SQLite (QxFx0DB(..))
import QxFx0.Learning.Promotion
  ( InformativenessResult(..)
  , PromotionCandidate(..)
  , activatePromotionOverlay
  , buildPromotionCandidates
  , ensurePromotionSchema
  , evaluateCandidateInformativeness
  , informativenessSemanticGainThreshold
  , loadActivePromotionOverlay
  , promotionEvaluationCorpusVersion
  , promotionRuntimeCorpusVersion
  , recordPromotionHumanRelease
  , rollbackPromotionOverlay
  , runPromotionGates
  )
import QxFx0.Learning.PromotionRuntime
  ( PromotionRuntimeCase(..)
  , RuntimeEvaluationMetrics(..)
  , RuntimeEvaluationSide(..)
  , RuntimePredicateFact(..)
  , effectiveBasePredicateSurfaces
  , failedRuntimeEvaluationSide
  , hasStructuralConflict
  , hasUnsupportedAssertion
  , promotionRuntimeEvaluationCases
  , runtimeAutomatedGatePassed
  )
import QxFx0.Learning.Quarantine (sha256Hex)
import QxFx0.Runtime (Session(..), runTurnInSession, withBootstrappedSession)
import QxFx0.Semantic.Content (DefinitionContent(..), SemanticPredicate(..))
import QxFx0.Semantic.ContentSelector
  ( selectPredicatesWithDiagnostics
  )
import QxFx0.Semantic.ContentSelector.Types
  ( SelectedPredicate(..)
  , SelectorDiagnostic(..)
  , csTopicPredicates
  , selectorMathVersion
  , selectorPolicyVersion
  )
import QxFx0.Self.Field (Field(..), Resonance(..), emptyField)
import QxFx0.Types.State.System
  ( CuratedOverlayRuntime(..)
  , SystemState(..)
  )
import QxFx0.Types.TurnProjection
  ( TurnReplayTrace(..)
  , decodePersistedReplayTrace
  )
import QxFx0.Types.RuntimeRegime (currentMathVersion)
import Test.Support
  ( assertExec
  , freshTestDbPath
  , queryCount
  , removeIfExists
  , withEnvVar
  , withRuntimeEnv
  )

testEvaluationCorpusIsDeterministicAndBounded :: Test
testEvaluationCorpusIsDeterministicAndBounded =
  TestLabel "promotion runtime corpus is deterministic and bounded" $ TestCase $ do
    let topics = ["topic-9", "topic-1", "topic-3", "topic-2", "topic-5", "topic-4", "topic-7", "topic-6", "topic-8"]
        forward = promotionRuntimeEvaluationCases topics
        reverseOrder = promotionRuntimeEvaluationCases (reverse topics)
    assertEqual "six fixed cases plus two cases for eight canonical topics" 22 (length forward)
    assertEqual "input ordering cannot change the review corpus" forward reverseOrder
    assertEqual "fixed regression cases remain first"
      ["base_regression", "base_regression", "unknown", "conflict", "ambiguous", "refusal_quality"]
      (map prcCategory (take 6 forward))

testCuratedPredicateIsSupported :: Test
testCuratedPredicateIsSupported =
  TestLabel "runtime assertion check accepts bootstrap curated predicates" $ TestCase $ do
    allowed <- effectiveBasePredicateSurfaces
    assertBool "curated-only predicate must be available to runtime assertion check"
      (not (hasUnsupportedAssertion ["действие это проявление активности"] allowed))
    assertBool "invented predicate must remain unsupported"
      (hasUnsupportedAssertion ["действие превращает знание в телепортацию"] allowed)

testStructuralConflictDoesNotReadRecoveryWords :: Test
testStructuralConflictDoesNotReadRecoveryWords =
  TestLabel "runtime conflict check uses declared relation facts" $ TestCase $ do
    let positive = RuntimePredicateFact "свобода" "requires" "ответственность"
        negative = RuntimePredicateFact "свобода" "contrasts_with" "ответственность"
        factsBySurface = M.fromList [("свобода требует ответственности", [positive])]
    assertBool "opposite relation facts on the same endpoints conflict"
      (hasStructuralConflict ["свобода требует ответственности"] factsBySurface [positive, negative])
    assertBool "recovery prose alone is not a structural conflict"
      (not (hasStructuralConflict ["Конфликт: Балансировать конфликует"] M.empty [positive, negative]))

testStructuralConflictRequiresMatchingEndpoints :: Test
testStructuralConflictRequiresMatchingEndpoints =
  TestLabel "runtime structural conflict is limited to the emitted triple endpoints" $ TestCase $ do
    let selected = RuntimePredicateFact "свобода" "requires" "ответственность"
        unrelated = RuntimePredicateFact "действие" "contrasts_with" "ответственность"
        factsBySurface = M.fromList [("свобода требует ответственности", [selected])]
    assertBool "an opposite relation for another subject cannot reject the selected predicate"
      (not (hasStructuralConflict ["свобода требует ответственности"] factsBySurface [unrelated]))

testFailureSidePreservesTimeout :: Test
testFailureSidePreservesTimeout =
  TestLabel "runtime timeout is represented as a failed side" $ TestCase $ do
    let side = failedRuntimeEvaluationSide "turn_timeout" True
    assertEqual "timeout reason is retained" (Just "turn_timeout") (resFailure side)
    assertBool "timeout remains distinguishable from an ordinary failure" (resTimedOut side)
    assertEqual "failed side cannot claim selected predicates" [] (resSelectedPredicates side)

testAutomatedGateRequiresObservedOverlayUsage :: Test
testAutomatedGateRequiresObservedOverlayUsage =
  TestLabel "runtime release gate requires observed overlay usage" $ TestCase $ do
    let healthyExceptUsage usage = RuntimeEvaluationMetrics
          { remBaselineContentful = 1
          , remCandidateContentful = 1
          , remBaselineRefusals = 0
          , remCandidateRefusals = 0
          , remBaselineConflicts = 0
          , remCandidateConflicts = 0
          , remBaselineUnsupportedAssertions = 0
          , remCandidateUnsupportedAssertions = 0
          , remBaselineRepeatedAnswers = 0
          , remCandidateRepeatedAnswers = 0
          , remOverlayUsageCases = usage
          , remBaseRegressionCases = 0
          , remRuntimeFailures = 0
          , remRuntimeTimeouts = 0
          }
    assertBool "baseline-equivalent responses without overlay evidence must fail"
      (not (runtimeAutomatedGatePassed (healthyExceptUsage 0)))
    assertBool "overlay evidence allows the remaining release conditions to pass"
      (runtimeAutomatedGatePassed (healthyExceptUsage 1))

testActiveOverlayReachesSelectorOrRecordsLoss :: Test
testActiveOverlayReachesSelectorOrRecordsLoss =
  TestLabel "active overlay reaches selector with explicit selection or loss reason" $ TestCase $
    withRuntimeEnv "qxfx0_test_selector_overlay.db" $ do
      dbPath <- lookupEnv "QXFX0_DB"
      path <- case dbPath of
        Nothing -> assertFailure "QXFX0_DB must be set by withRuntimeEnv" >> fail "unreachable"
        Just value -> pure value
      let overlayVersion = "overlay-selector-test"
          predicateId = "overlay-selector-predicate"
          topic = "история"
          rawSurface = "история связано с прошлое"
          surface = "история связана с прошлым"
          insertOverlay conn = do
            let db = QxFx0DB path conn
            ensurePromotionSchema db
            overlayChecksum <- seedArtifactOverlay db overlayVersion "snapshot-selector-test"
              predicateId topic "property" rawSurface "история" "related_to" "прошлое" 0.6 "active"
            insertCorpusEvaluation conn "selector-corpus-evaluation" overlayVersion overlayChecksum 1
              promotionEvaluationCorpusVersion True
            insertRuntimeEvaluation conn "selector-evaluation" "selector-corpus-evaluation"
              overlayVersion overlayChecksum 1 promotionRuntimeCorpusVersion currentMathVersion True
            assertExec conn "selector_test_release_gate"
              ("INSERT INTO promotion_runtime_release_gates(overlay_version, evaluation_id, completed_at, release_passed, human_reviewed, details) VALUES('"
                <> overlayVersion <> "', 'selector-evaluation', 1, 1, 1, 'test-only')")
            assertExec conn "selector_test_active"
              ("INSERT INTO promotion_active(singleton, overlay_version, runtime_evaluation_id, updated_at) VALUES(1, '"
                <> overlayVersion <> "', 'selector-evaluation', 1)")
            statusOk <- queryCount conn "SELECT COUNT(*) FROM promotion_overlays WHERE overlay_version='overlay-selector-test' AND status='active'"
            evaluationOk <- queryCount conn "SELECT COUNT(*) FROM promotion_evaluations WHERE overlay_version='overlay-selector-test'"
            releaseOk <- queryCount conn "SELECT COUNT(*) FROM promotion_runtime_release_gates g JOIN promotion_runtime_evaluations e ON e.evaluation_id=g.evaluation_id AND e.overlay_version=g.overlay_version WHERE g.overlay_version='overlay-selector-test' AND g.release_passed=1 AND g.human_reviewed=1"
            lineageOk <- queryCount conn "SELECT COUNT(*) FROM promotion_overlay_lineage WHERE overlay_version='overlay-selector-test'"
            governedOk <- queryCount conn "SELECT COUNT(*) FROM promotion_overlay_predicates p JOIN promotion_candidates c ON c.candidate_id=p.candidate_id AND c.snapshot_id='snapshot-selector-test' JOIN promotion_gate_runs g ON g.candidate_id=p.candidate_id JOIN promotion_overlay_lineage l ON l.overlay_version=p.overlay_version AND l.gate_run_id=g.gate_run_id WHERE p.overlay_version='overlay-selector-test' AND c.lifecycle_status='eligible_for_draft' AND g.decision='pass'"
            assertEqual "selector fixture active status" 1 statusOk
            assertEqual "selector fixture evaluation" 1 evaluationOk
            assertEqual "selector fixture reviewed release" 1 releaseOk
            assertEqual "selector fixture lineage" 1 lineageOk
            assertEqual "selector fixture complete governed predicate" 13 governedOk
            preloaded <- loadActivePromotionOverlay db
            assertBool "governed selector fixture is loadable before bootstrap"
              (maybe False (const True) preloaded)
      opened <- NSQL.open path
      case opened of
        Left err -> assertFailure ("cannot open selector overlay DB: " <> T.unpack err)
        Right conn -> insertOverlay conn `finally` NSQL.close conn
      withEnvVar "QXFX0_AUTONOMOUS_LEARNING" (Just "0") $
        withEnvVar "QXFX0_USE_SELFPLAY" (Just "0") $
          withBootstrappedSession True "selector-overlay-test" $ \session -> do
            let ss = sessSystemState session
                selector = ssContentSelector ss
                mContent = M.lookup topic (ssDefinitionCorpus ss)
                predicates = M.findWithDefault [] topic (csTopicPredicates selector)
                (selected, diagnostics) = selectPredicatesWithDiagnostics
                  selector (emptyField { fieldResonance = Resonance 0.8 }) topic (Just (ssSemanticNetwork ss))
                overlayDiagnostic = listToMaybe
                  [ diagnostic
                  | diagnostic <- diagnostics
                  , sdPredicateSurface diagnostic == Just surface
                  ]
            case mContent of
              Nothing -> assertFailure "active overlay topic missing from effective corpus"
              Just content -> assertBool
                ("overlay predicate present in effective corpus: " <> show (map spRu (dcPredicates content)))
                (any ((== surface) . spRu) (dcPredicates content))
            assertBool "overlay predicate present in ContentSelector topic pool"
              (any ((== surface) . spRu) predicates)
            case ssCuratedOverlay ss of
              Nothing -> assertFailure "active overlay provenance missing from bootstrap state"
              Just overlay -> do
                assertEqual "active overlay version" overlayVersion (corVersion overlay)
                assertEqual "overlay surface maps to predicate id"
                  (Just predicateId)
                  (M.lookup (T.toLower (T.strip surface)) (corPredicateIdsBySurface overlay))
            let selectedOverlay = any ((== surface) . spRu)
                  (concatMap spPredicates selected)
            case overlayDiagnostic of
              Nothing -> assertFailure "selector did not emit a diagnostic for overlay predicate"
              Just diagnostic
                | selectedOverlay -> assertBool "direct selector marks overlay as selected"
                    (sdSelected diagnostic)
                | otherwise -> do
                    assertBool "canonical overlay receives non-zero field score"
                      (maybe False (> 0.0) (sdFieldAffinity diagnostic))
                    assertEqual "canonical overlay has no OOV atoms" (Just []) (sdOovAtoms diagnostic)
                    assertEqual "selector policy version is recorded"
                      (Just selectorPolicyVersion) (sdPolicyVersion diagnostic)
                    assertEqual "selector math version is recorded"
                      (Just selectorMathVersion) (sdMathVersion diagnostic)
                    assertBool "direct selector records an explicit overlay loss reason"
                      (sdReason diagnostic `elem`
                        [ "below_score_threshold"
                        , "lost_to_higher_score"
                        , "not_in_composition_top_3"
                        , "generated_predicate_gate_rejected"
                        ])
            (sessionAfter, _) <- runTurnInSession session "Что такое история?"
            trace <- loadLatestTrace path (sessSessionId sessionAfter)
            assertEqual "candidate session keeps active overlay in replay trace"
              (Just overlayVersion) (trcCuratedOverlayVersion trace)
            let traceDiagnostic = listToMaybe
                  [ diagnostic
                  | diagnostic <- trcSelectorDiagnostics trace
                  , sdPredicateSurface diagnostic == Just surface
                  ]
                traceSelected = predicateId `elem` trcOverlayPredicateIds trace
            if traceSelected
              then pure ()
              else case traceDiagnostic of
                Just diagnostic
                  | sdSelected diagnostic -> assertFailure
                      "overlay selector marked predicate selected but attribution missed its id"
                  | sdReason diagnostic `elem`
                      [ "below_score_threshold"
                      , "lost_to_higher_score"
                      , "not_in_composition_top_3"
                      , "generated_predicate_gate_rejected"
                      ] -> pure ()
                _ -> assertFailure "overlay was neither attributed nor given an explicit selector loss reason"

testInformativenessGateRejectsLowInformationPredicate :: Test
testInformativenessGateRejectsLowInformationPredicate =
  TestLabel "informativeness gate rejects a topic paraphrase with no semantic gain" $ TestCase $ do
    let candidate = PromotionCandidate
          { pcCandidateId = "low-information"
          , pcSnapshotId = "snapshot-test"
          , pcTopic = "история"
          , pcSubject = "история"
          , pcRelationType = "related_to"
          , pcObject = "прошлое"
          , pcRenderedRu = "история связана с прошлым"
          , pcConfidence = 0.6
          , pcSupportCount = 2
          , pcStatus = "discovered"
          }
        result = evaluateCandidateInformativeness candidate
    assertBool "candidate is not tautological" (irNotTautological result)
    assertBool "candidate has no sufficient novel information" (not (irAddsNovelInformation result))
    assertBool "candidate is not accepted by informativeness gate" (not (irPassed result))
    assertBool "semantic gain is below useful threshold"
      (irSemanticGain result < informativenessSemanticGainThreshold)

testInformativenessGateAcceptsNovelConstraint :: Test
testInformativenessGateAcceptsNovelConstraint =
  TestLabel "informativeness gate accepts a novel constrained object" $ TestCase $ do
    let candidate = PromotionCandidate
          { pcCandidateId = "novel-constraint"
          , pcSnapshotId = "snapshot-test"
          , pcTopic = "истина"
          , pcSubject = "истина"
          , pcRelationType = "requires"
          , pcObject = "проверяемая воспроизводимость"
          , pcRenderedRu = "истина требует проверяемую воспроизводимость"
          , pcConfidence = 0.8
          , pcSupportCount = 2
          , pcStatus = "discovered"
          }
        result = evaluateCandidateInformativeness candidate
    assertBool "novel constrained candidate passes informativeness" (irPassed result)
    assertBool "novel constrained candidate has semantic gain"
      (irSemanticGain result >= informativenessSemanticGainThreshold)

testSupportGateRequiresCanonicalCuratedTriple :: Test
testSupportGateRequiresCanonicalCuratedTriple =
  TestLabel "promotion support accepts exact curated triples but not endpoint substring coincidence" $ TestCase $
    withPromotionTestDb "qxfx0_test_promotion_canonical_support.db" $ \db -> do
      let conn = qdbConn db
      assertExec conn "canonical_support_snapshot"
        "INSERT INTO promotion_snapshots(snapshot_id, created_at, edge_count, checksum, status) VALUES('support-snapshot', 0, 1, 'support-checksum', 'created')"
      assertExec conn "canonical_support_provenance"
        "INSERT INTO promotion_snapshot_edges(snapshot_id, edge_id, edge_from, edge_to, relation_type, confidence, provenance, captured_at) VALUES('support-snapshot', 1, 'свобода', 'выбор', 'presupposes', 0.9, 'runtime_llm', 0)"
      assertExec conn "canonical_support_exact_candidate"
        "INSERT INTO promotion_candidates(candidate_id, snapshot_id, topic, subject_atom, relation_type, object_atom, rendered_ru, confidence_raw, support_count, lifecycle_status, canonical_hash, created_at) VALUES('support-exact', 'support-snapshot', 'свобода', 'свобода', 'presupposes', 'выбор', 'свобода предполагает выбор', 0.9, 1, 'discovered', 'support-exact-hash', 0)"
      assertExec conn "canonical_support_relation_mismatch_candidate"
        "INSERT INTO promotion_candidates(candidate_id, snapshot_id, topic, subject_atom, relation_type, object_atom, rendered_ru, confidence_raw, support_count, lifecycle_status, canonical_hash, created_at) VALUES('support-mismatch', 'support-snapshot', 'свобода', 'свобода', 'requires', 'выбор', 'свобода требует выбор', 0.9, 1, 'discovered', 'support-mismatch-hash', 0)"
      assertExec conn "canonical_support_independent_candidate"
        "INSERT INTO promotion_candidates(candidate_id, snapshot_id, topic, subject_atom, relation_type, object_atom, rendered_ru, confidence_raw, support_count, lifecycle_status, canonical_hash, created_at) VALUES('support-independent', 'support-snapshot', 'свобода', 'свобода', 'causes', 'квантовый маяк', 'свобода вызывает квантовый маяк', 0.9, 2, 'discovered', 'support-independent-hash', 0)"
      _ <- runPromotionGates db "support-snapshot"
      exactPass <- queryCount conn
        "SELECT COUNT(*) FROM promotion_gate_runs WHERE candidate_id='support-exact' AND gate_name='support' AND decision='pass'"
      mismatchFail <- queryCount conn
        "SELECT COUNT(*) FROM promotion_gate_runs WHERE candidate_id='support-mismatch' AND gate_name='support' AND decision='fail' AND reason_code='insufficient_support'"
      independentPass <- queryCount conn
        "SELECT COUNT(*) FROM promotion_gate_runs WHERE candidate_id='support-independent' AND gate_name='support' AND decision='pass'"
      assertEqual "the exact canonical curated triple corroborates one observation" 1 exactPass
      assertEqual "the same endpoint words under another relation do not corroborate" 1 mismatchFail
      assertEqual "two independent observations still satisfy support" 1 independentPass

testRollbackRequiresGovernedParent :: Test
testRollbackRequiresGovernedParent =
  TestLabel "promotion rollback preserves the active pointer until its parent passes every governance gate" $ TestCase $
    withPromotionTestDb "qxfx0_test_promotion_governed_rollback.db" $ \db -> do
      let conn = qdbConn db
      overlayChecksum <- seedArtifactOverlay db "rollback-parent" "rollback-snapshot"
        "rollback-candidate" "история" "relation" "история требует свидетельство"
        "история" "requires" "свидетельство" 0.9 "superseded"
      assertExec conn "rollback_child"
        "INSERT INTO promotion_overlays(overlay_version, parent_version, prior_runtime_evaluation_id, snapshot_id, status, created_at, checksum) VALUES('rollback-child', 'rollback-parent', 'rollback-evaluation', 'rollback-snapshot', 'active', 0, 'child-checksum')"
      assertExec conn "rollback_active_pointer"
        "INSERT INTO promotion_active(singleton, overlay_version, runtime_evaluation_id, updated_at) VALUES(1, 'rollback-child', 'rollback-child-evaluation', 0)"
      assertRollbackRejected db "parent without evaluation"
      insertCorpusEvaluation conn "rollback-corpus-evaluation" "rollback-parent" overlayChecksum 1
        promotionEvaluationCorpusVersion True
      insertRuntimeEvaluation conn "rollback-evaluation" "rollback-corpus-evaluation"
        "rollback-parent" overlayChecksum 1 promotionRuntimeCorpusVersion currentMathVersion True
      assertRollbackRejected db "parent without release review"
      _ <- recordPromotionHumanRelease db "rollback-parent" "test-reviewed"
      rollbackPromotionOverlay db
      activeParent <- queryCount conn
        "SELECT COUNT(*) FROM promotion_active a JOIN promotion_overlays o ON o.overlay_version=a.overlay_version WHERE a.singleton=1 AND a.overlay_version='rollback-parent' AND o.status='active'"
      assertEqual "fully governed parent is reactivated" 1 activeParent

testLoadActiveOverlayFailsClosed :: Test
testLoadActiveOverlayFailsClosed =
  TestLabel "active promotion load rejects invalid pointers and preserves a valid active overlay" $ TestCase $
    withPromotionTestDb "qxfx0_test_promotion_governed_load.db" $ \db -> do
      let conn = qdbConn db
      overlayChecksum <- seedArtifactOverlay db "load-overlay" "load-snapshot"
        "load-candidate" "история" "relation" "история требует свидетельство"
        "история" "requires" "свидетельство" 0.9 "active"
      assertExec conn "load_active_pointer"
        "INSERT INTO promotion_active(singleton, overlay_version, runtime_evaluation_id, updated_at) VALUES(1, 'load-overlay', 'load-evaluation', 0)"
      assertLoadRejectedWithoutPointerMutation db "active overlay without release gate"
      insertCorpusEvaluation conn "load-corpus-evaluation" "load-overlay" overlayChecksum 1
        promotionEvaluationCorpusVersion True
      insertRuntimeEvaluation conn "load-evaluation" "load-corpus-evaluation"
        "load-overlay" overlayChecksum 1 promotionRuntimeCorpusVersion currentMathVersion True
      assertLoadRejectedWithoutPointerMutation db "active overlay without human review"
      _ <- recordPromotionHumanRelease db "load-overlay" "test-reviewed"
      loaded <- loadActivePromotionOverlay db
      case loaded of
        Nothing -> assertFailure "valid active overlay was rejected"
        Just (runtime, corpus) -> do
          assertEqual "valid active overlay version is preserved" "load-overlay" (corVersion runtime)
          assertBool "valid active overlay corpus is loaded" (M.member "история" corpus)

testMonotonicPromotionRevalidation :: Test
testMonotonicPromotionRevalidation =
  TestLabel "promotion revalidation is monotonic and active overlays use immutable artifacts" $ TestCase $
    withPromotionTestDb "qxfx0_test_promotion_monotonic_revalidation.db" $ \db -> do
      let conn = qdbConn db
          overlayVersion = "monotonic-overlay"
          snapshotId = "monotonic-snapshot"
          candidateId = "monotonic-candidate"
      overlayChecksum <- seedArtifactOverlay db overlayVersion snapshotId candidateId
        "история" "relation" "история требует свидетельство"
        "история" "requires" "свидетельство" 0.9 "evaluated"
      insertCorpusEvaluation conn "corpus-e1" overlayVersion overlayChecksum 1
        promotionEvaluationCorpusVersion True
      insertRuntimeEvaluation conn "runtime-e1" "corpus-e1" overlayVersion overlayChecksum 1
        promotionRuntimeCorpusVersion currentMathVersion True
      releasedE1 <- recordPromotionHumanRelease db overlayVersion "E1 reviewed pass"
      assertEqual "E1 release is bound to E1" "runtime-e1" releasedE1
      activatePromotionOverlay db overlayVersion
      assertOverlayLoaded db overlayVersion "E1 pass and release permit explicit activation"

      -- Rebuilding the mutable working candidate resets its lifecycle status,
      -- but cannot rewrite or invalidate the active overlay artifact.
      rebuilt <- buildPromotionCandidates db snapshotId
      assertEqual "empty immutable snapshot rebuild has no candidate groups" 0 rebuilt
      candidateDiscovered <- queryCount conn
        "SELECT COUNT(*) FROM promotion_candidates WHERE candidate_id='monotonic-candidate' AND lifecycle_status='discovered'"
      assertEqual "working candidate lifecycle was rebuilt" 1 candidateDiscovered
      assertOverlayLoaded db overlayVersion "candidate rebuild cannot disable the immutable active overlay"
      unchangedSurface <- queryCount conn
        "SELECT COUNT(*) FROM promotion_overlay_predicates WHERE overlay_version='monotonic-overlay' AND predicate_ru='история требует свидетельство'"
      assertEqual "candidate rebuild cannot silently alter active predicate rows" 1 unchangedSurface
      lateInsert <- NSQL.execSql conn
        "INSERT INTO promotion_overlay_predicates(overlay_version, predicate_id, candidate_id, topic, predicate_role, predicate_ru, subject_atom, relation_type, object_atom, confidence) VALUES('monotonic-overlay', 'late-predicate', 'monotonic-candidate', 'история', 'relation', 'late mutation', 'история', 'requires', 'свидетельство', 0.9)"
      case lateInsert of
        Left _ -> pure ()
        Right () -> assertFailure "active immutable overlay accepted a late predicate insertion"

      insertRuntimeEvaluation conn "runtime-e2" "corpus-e1" overlayVersion overlayChecksum 2
        promotionRuntimeCorpusVersion currentMathVersion False
      assertOverlayLoaded db overlayVersion "an unreleased review evaluation cannot revoke the active E1 binding"
      assertActivationRejected db overlayVersion "newer failed E2"
      assertActiveBinding conn "runtime-e1" "failed revalidation does not rewrite the active pointer"

      insertRuntimeEvaluation conn "runtime-e3-stale-corpus" "corpus-e1" overlayVersion overlayChecksum 3
        "promotion-runtime-ab-stale" currentMathVersion True
      assertOverlayLoaded db overlayVersion "stale review evidence does not replace the active binding"
      assertReleaseRejected db overlayVersion "stale runtime corpus version"

      insertRuntimeEvaluation conn "runtime-e4-stale-math" "corpus-e1" overlayVersion overlayChecksum 4
        promotionRuntimeCorpusVersion (currentMathVersion - 1) True
      assertOverlayLoaded db overlayVersion "stale-math review evidence does not replace the active binding"
      assertReleaseRejected db overlayVersion "stale runtime math version"

      insertCorpusEvaluation conn "corpus-e2-stale" overlayVersion overlayChecksum 2
        "promotion-corpus-precheck-stale" True
      insertRuntimeEvaluation conn "runtime-e5" "corpus-e2-stale" overlayVersion overlayChecksum 5
        promotionRuntimeCorpusVersion currentMathVersion True
      assertOverlayLoaded db overlayVersion "stale corpus review evidence does not replace the active binding"
      assertReleaseRejected db overlayVersion "stale corpus evaluation version"

      insertCorpusEvaluation conn "corpus-e3" overlayVersion overlayChecksum 3
        promotionEvaluationCorpusVersion True
      insertRuntimeEvaluation conn "runtime-e6" "corpus-e3" overlayVersion overlayChecksum 6
        promotionRuntimeCorpusVersion currentMathVersion True
      releasedE6 <- recordPromotionHumanRelease db overlayVersion "E6 reviewed pass"
      assertEqual "newest passing evaluation can be released" "runtime-e6" releasedE6
      assertOverlayLoaded db overlayVersion "release does not disable or silently rebind the active overlay"
      assertActiveBinding conn "runtime-e1" "human release alone does not mutate activation binding"
      activatePromotionOverlay db overlayVersion
      assertActiveBinding conn "runtime-e6" "explicit activation binds the newest released evaluation"
      assertOverlayLoaded db overlayVersion "newest current pass permits explicit activation"

      releaseCount <- queryCount conn
        "SELECT COUNT(*) FROM promotion_runtime_release_gates WHERE overlay_version='monotonic-overlay'"
      assertEqual "E1 and E6 releases remain append-only audit artifacts" 2 releaseCount

testPromotionSchemaMigratesEvaluationScopedReleases :: Test
testPromotionSchemaMigratesEvaluationScopedReleases =
  TestLabel "promotion schema migrates one-release-per-overlay rows to evaluation-scoped history" $ TestCase $ do
    dbPath <- freshTestDbPath "qxfx0_test_promotion_release_migration.db"
    let artifacts = [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
        cleanup = mapM_ removeIfExists artifacts
    cleanup
    opened <- NSQL.open dbPath
    conn <- case opened of
      Left err -> assertFailure ("cannot open promotion migration DB: " <> T.unpack err) >> fail "unreachable"
      Right value -> pure value
    (do
        assertExec conn "legacy_release_schema"
          "CREATE TABLE promotion_runtime_release_gates (overlay_version TEXT PRIMARY KEY, evaluation_id TEXT NOT NULL, completed_at INTEGER NOT NULL, release_passed INTEGER NOT NULL CHECK(release_passed IN (0, 1)), human_reviewed INTEGER NOT NULL CHECK(human_reviewed IN (0, 1)), details TEXT NOT NULL)"
        assertExec conn "legacy_release_row"
          "INSERT INTO promotion_runtime_release_gates VALUES('legacy-overlay', 'legacy-e1', 1, 1, 1, 'legacy')"
        ensurePromotionSchema (QxFx0DB dbPath conn)
        assertExec conn "second_evaluation_release"
          "INSERT INTO promotion_runtime_release_gates VALUES('legacy-overlay', 'legacy-e2', 2, 1, 1, 'new')"
        releases <- queryCount conn
          "SELECT COUNT(*) FROM promotion_runtime_release_gates WHERE overlay_version='legacy-overlay'"
        assertEqual "legacy release is preserved and a newer evaluation gets its own immutable row" 2 releases
        migratedColumns <- queryCount conn
          "SELECT COUNT(*) FROM pragma_table_info('promotion_runtime_evaluations') WHERE name IN ('corpus_evaluation_id', 'runtime_corpus_version', 'math_version', 'overlay_checksum')"
        assertEqual "runtime evaluation version and artifact columns are migrated" 4 migratedColumns
      ) `finally` NSQL.close conn
    cleanup

testChildOverlayIsCumulativeAndRollbackRestoresExactParent :: Test
testChildOverlayIsCumulativeAndRollbackRestoresExactParent =
  TestLabel "child overlays are cumulative and rollback restores the exact prior binding" $ TestCase $
    withPromotionTestDb "qxfx0_test_promotion_cumulative_child.db" $ \db -> do
      let conn = qdbConn db
      parentChecksum <- seedArtifactOverlay db "cumulative-parent" "cumulative-parent-snapshot"
        "cumulative-parent-candidate" "история" "relation" "история требует свидетельство"
        "история" "requires" "свидетельство" 0.9 "evaluated"
      insertCorpusEvaluation conn "cumulative-parent-corpus-e1" "cumulative-parent" parentChecksum 1
        promotionEvaluationCorpusVersion True
      insertRuntimeEvaluation conn "cumulative-parent-runtime-e1" "cumulative-parent-corpus-e1"
        "cumulative-parent" parentChecksum 1 promotionRuntimeCorpusVersion currentMathVersion True
      _ <- recordPromotionHumanRelease db "cumulative-parent" "parent E1"
      activatePromotionOverlay db "cumulative-parent"

      -- A later released review remains append-only; the active parent is still
      -- exactly bound to E1 when the child transition occurs.
      insertRuntimeEvaluation conn "cumulative-parent-runtime-e2" "cumulative-parent-corpus-e1"
        "cumulative-parent" parentChecksum 2 promotionRuntimeCorpusVersion currentMathVersion True
      _ <- recordPromotionHumanRelease db "cumulative-parent" "parent E2"

      childChecksum <- seedArtifactOverlay db "cumulative-child" "cumulative-child-snapshot"
        "cumulative-child-candidate" "истина" "relation" "истина требует проверяемость"
        "истина" "requires" "проверяемость" 0.9 "evaluated"
      assertExec conn "cumulative_child_parent"
        "UPDATE promotion_overlays SET status='draft' WHERE overlay_version='cumulative-child'; UPDATE promotion_overlays SET parent_version='cumulative-parent' WHERE overlay_version='cumulative-child'; UPDATE promotion_overlays SET status='evaluated' WHERE overlay_version='cumulative-child'"
      insertCorpusEvaluation conn "cumulative-child-corpus" "cumulative-child" childChecksum 1
        promotionEvaluationCorpusVersion True
      insertRuntimeEvaluation conn "cumulative-child-runtime" "cumulative-child-corpus"
        "cumulative-child" childChecksum 1 promotionRuntimeCorpusVersion currentMathVersion True
      _ <- recordPromotionHumanRelease db "cumulative-child" "child reviewed"
      activatePromotionOverlay db "cumulative-child"

      loaded <- loadActivePromotionOverlay db
      case loaded of
        Nothing -> assertFailure "cumulative child did not load"
        Just (runtime, corpus) -> do
          assertEqual "leaf version remains the runtime identity" "cumulative-child" (corVersion runtime)
          assertBool "parent predicate remains active in the child" (M.member "история" corpus)
          assertBool "child predicate is added monotonically" (M.member "истина" corpus)

      rollbackPromotionOverlay db
      assertActiveBinding conn "cumulative-parent-runtime-e1"
        "rollback restores the evaluation active immediately before the child"
      restored <- loadActivePromotionOverlay db
      case restored of
        Nothing -> assertFailure "rolled-back parent did not load"
        Just (runtime, corpus) -> do
          assertEqual "parent version is restored" "cumulative-parent" (corVersion runtime)
          assertBool "parent content remains" (M.member "история" corpus)
          assertBool "child-only content is removed" (not (M.member "истина" corpus))

testActivationRequiresCurrentParentAndRootRollbackClearsActive :: Test
testActivationRequiresCurrentParentAndRootRollbackClearsActive =
  TestLabel "activation compares parent atomically and root rollback restores no overlay" $ TestCase $
    withPromotionTestDb "qxfx0_test_promotion_parent_transition.db" $ \db -> do
      let conn = qdbConn db
      rootChecksum <- seedArtifactOverlay db "transition-root" "transition-root-snapshot"
        "transition-root-candidate" "история" "relation" "история требует свидетельство"
        "история" "requires" "свидетельство" 0.9 "evaluated"
      insertCorpusEvaluation conn "transition-root-corpus" "transition-root" rootChecksum 1
        promotionEvaluationCorpusVersion True
      insertRuntimeEvaluation conn "transition-root-runtime" "transition-root-corpus"
        "transition-root" rootChecksum 1 promotionRuntimeCorpusVersion currentMathVersion True
      _ <- recordPromotionHumanRelease db "transition-root" "root reviewed"
      activatePromotionOverlay db "transition-root"

      let seedChild version snapshot candidate topic object = do
            checksum <- seedArtifactOverlay db version snapshot candidate topic "relation"
              (topic <> " требует " <> object) topic "requires" object 0.9 "evaluated"
            assertExec conn "transition_child_parent"
              ("UPDATE promotion_overlays SET status='draft' WHERE overlay_version='" <> version
                <> "'; UPDATE promotion_overlays SET parent_version='transition-root' WHERE overlay_version='" <> version
                <> "'; UPDATE promotion_overlays SET status='evaluated' WHERE overlay_version='" <> version <> "'")
            insertCorpusEvaluation conn (version <> "-corpus") version checksum 1
              promotionEvaluationCorpusVersion True
            insertRuntimeEvaluation conn (version <> "-runtime") (version <> "-corpus")
              version checksum 1 promotionRuntimeCorpusVersion currentMathVersion True
            _ <- recordPromotionHumanRelease db version "child reviewed"
            pure ()
      seedChild "transition-child-a" "transition-child-a-snapshot" "transition-child-a-candidate" "истина" "проверяемость"
      seedChild "transition-child-b" "transition-child-b-snapshot" "transition-child-b-candidate" "доверие" "уязвимость"
      activatePromotionOverlay db "transition-child-a"
      assertActivationRejected db "transition-child-b" "sibling parent is no longer active"
      activeA <- queryCount conn
        "SELECT COUNT(*) FROM promotion_active WHERE overlay_version='transition-child-a' AND runtime_evaluation_id='transition-child-a-runtime'"
      assertEqual "failed sibling activation leaves the current child untouched" 1 activeA

      rollbackPromotionOverlay db
      rollbackPromotionOverlay db
      cleared <- queryCount conn
        "SELECT COUNT(*) FROM promotion_active WHERE singleton=1 AND overlay_version IS NULL AND runtime_evaluation_id IS NULL"
      assertEqual "rolling back the first overlay restores the overlay-free state" 1 cleared
      assertEqual "no overlay loads after root rollback" Nothing =<< loadActivePromotionOverlay db

withPromotionTestDb :: FilePath -> (QxFx0DB -> IO a) -> IO a
withPromotionTestDb stem action = do
  dbPath <- freshTestDbPath stem
  let artifacts = [dbPath, dbPath <> "-wal", dbPath <> "-shm"]
      cleanup = mapM_ removeIfExists artifacts
  cleanup
  opened <- NSQL.open dbPath
  db <- case opened of
    Left err -> assertFailure ("cannot open promotion test DB: " <> T.unpack err) >> fail "unreachable"
    Right conn -> pure (QxFx0DB dbPath conn)
  ensurePromotionSchema db
  (action db `finally` NSQL.close (qdbConn db)) `finally` cleanup

seedCurrentPolicyLineage :: QxFx0DB -> T.Text -> IO ()
seedCurrentPolicyLineage db snapshotId = do
  let conn = qdbConn db
  assertExec conn "governance_snapshot"
    ("INSERT INTO promotion_snapshots(snapshot_id, created_at, edge_count, checksum, status) VALUES('"
      <> snapshotId <> "', 0, 0, '" <> snapshotId <> "-checksum', 'created')")
  _ <- runPromotionGates db snapshotId
  pure ()

seedArtifactOverlay
  :: QxFx0DB -> T.Text -> T.Text -> T.Text -> T.Text -> T.Text -> T.Text
  -> T.Text -> T.Text -> T.Text -> Double -> T.Text -> IO T.Text
seedArtifactOverlay db overlayVersion snapshotId candidateId topic role surface
    subject relation object confidence status = do
  seedCurrentPolicyLineage db snapshotId
  let conn = qdbConn db
  (gateRunId, policyVersion, policyChecksum) <- loadGateLineage conn snapshotId
  snapshotChecksum <- loadScalarText conn
    "SELECT checksum FROM promotion_snapshots WHERE snapshot_id=?" snapshotId
  let predicateChecksum = sha256Hex . TE.encodeUtf8 $ T.intercalate "|"
        [ candidateId, candidateId, topic, role, surface, subject, relation, object
        , T.pack (show confidence)
        ]
      overlayChecksum = sha256Hex . TE.encodeUtf8 $ T.intercalate "\n"
        [ snapshotId, snapshotChecksum, gateRunId, policyVersion, policyChecksum, predicateChecksum ]
  assertExec conn "artifact_overlay"
    ("INSERT INTO promotion_overlays(overlay_version, snapshot_id, status, created_at, checksum) VALUES('"
      <> overlayVersion <> "', '" <> snapshotId <> "', 'draft', 0, '" <> overlayChecksum <> "')")
  assertExec conn "artifact_overlay_lineage"
    ("INSERT INTO promotion_overlay_lineage(overlay_version, snapshot_id, snapshot_checksum, predicate_checksum, gate_run_id, policy_version, policy_checksum, created_at) VALUES('"
      <> overlayVersion <> "', '" <> snapshotId <> "', '" <> snapshotChecksum <> "', '"
      <> predicateChecksum <> "', '" <> gateRunId <> "', '" <> policyVersion <> "', '"
      <> policyChecksum <> "', 0)")
  insertGovernedCandidate conn overlayVersion snapshotId candidateId topic subject relation object
  assertExec conn "artifact_overlay_predicate"
    ("INSERT INTO promotion_overlay_predicates(overlay_version, predicate_id, candidate_id, topic, predicate_role, predicate_ru, subject_atom, relation_type, object_atom, confidence) VALUES('"
      <> overlayVersion <> "', '" <> candidateId <> "', '" <> candidateId <> "', '" <> topic
      <> "', '" <> role <> "', '" <> surface <> "', '" <> subject <> "', '" <> relation
      <> "', '" <> object <> "', " <> T.pack (show confidence) <> ")")
  assertExec conn "artifact_overlay_status"
    ("UPDATE promotion_overlays SET status='" <> status <> "' WHERE overlay_version='" <> overlayVersion <> "'")
  pure overlayChecksum

loadGateLineage :: NSQL.Database -> T.Text -> IO (T.Text, T.Text, T.Text)
loadGateLineage conn snapshotId = do
  prepared <- NSQL.prepare conn
    "SELECT gate_run_id, policy_version, policy_checksum FROM promotion_gate_run_lineage WHERE snapshot_id=? ORDER BY created_at DESC, gate_run_id DESC LIMIT 1"
  stmt <- either (fail . T.unpack) pure prepared
  _ <- NSQL.bindText stmt 1 snapshotId
  hasRow <- NSQL.stepRow stmt
  value <- if hasRow
    then (,,) <$> NSQL.columnText stmt 0 <*> NSQL.columnText stmt 1 <*> NSQL.columnText stmt 2
    else assertFailure "missing gate lineage" >> fail "unreachable"
  NSQL.finalize stmt
  pure value

loadScalarText :: NSQL.Database -> T.Text -> T.Text -> IO T.Text
loadScalarText conn sql parameter = do
  prepared <- NSQL.prepare conn sql
  stmt <- either (fail . T.unpack) pure prepared
  _ <- NSQL.bindText stmt 1 parameter
  hasRow <- NSQL.stepRow stmt
  value <- if hasRow then NSQL.columnText stmt 0 else assertFailure "missing scalar row" >> fail "unreachable"
  NSQL.finalize stmt
  pure value

insertCorpusEvaluation
  :: NSQL.Database -> T.Text -> T.Text -> T.Text -> Int -> T.Text -> Bool -> IO ()
insertCorpusEvaluation conn evaluationId overlayVersion overlayChecksum timestamp corpusVersion passed =
  assertExec conn "promotion_corpus_evaluation_fixture"
    ("INSERT INTO promotion_evaluations(evaluation_id, overlay_version, created_at, corpus_version, overlay_checksum, passed, baseline_contentful, candidate_contentful, baseline_conflicts, candidate_conflicts, baseline_refusals, candidate_refusals) VALUES('"
      <> evaluationId <> "', '" <> overlayVersion <> "', " <> T.pack (show timestamp) <> ", '"
      <> corpusVersion <> "', '" <> overlayChecksum <> "', " <> boolSql passed <> ", 1, 1, 0, 0, 0, 0)")

insertRuntimeEvaluation
  :: NSQL.Database -> T.Text -> T.Text -> T.Text -> T.Text -> Int -> T.Text -> Int -> Bool -> IO ()
insertRuntimeEvaluation conn evaluationId corpusEvaluationId overlayVersion overlayChecksum timestamp runtimeCorpusVersion mathVersion passed =
  assertExec conn "promotion_runtime_evaluation_fixture"
    ("INSERT INTO promotion_runtime_evaluations(evaluation_id, overlay_version, corpus_evaluation_id, completed_at, runtime_corpus_version, math_version, overlay_checksum, automated_passed, overlay_usage_cases, details) VALUES('"
      <> evaluationId <> "', '" <> overlayVersion <> "', '" <> corpusEvaluationId <> "', "
      <> T.pack (show timestamp) <> ", '" <> runtimeCorpusVersion <> "', " <> T.pack (show mathVersion)
      <> ", '" <> overlayChecksum <> "', " <> boolSql passed <> ", 1, 'test-only')")

boolSql :: Bool -> T.Text
boolSql True = "1"
boolSql False = "0"

insertGovernedCandidate
  :: NSQL.Database -> T.Text -> T.Text -> T.Text -> T.Text
  -> T.Text -> T.Text -> T.Text -> IO ()
insertGovernedCandidate conn overlayVersion snapshotId candidateId topic subject relation object = do
  assertExec conn "governed_overlay_candidate"
    ("INSERT INTO promotion_candidates(candidate_id, snapshot_id, topic, subject_atom, relation_type, object_atom, rendered_ru, confidence_raw, support_count, lifecycle_status, canonical_hash, created_at) VALUES('"
      <> candidateId <> "', '" <> snapshotId <> "', '" <> topic <> "', '" <> subject <> "', '"
      <> relation <> "', '" <> object <> "', '" <> subject <> " " <> relation <> " " <> object
      <> "', 0.9, 2, 'eligible_for_draft', '" <> candidateId <> "-canonical', 0)")
  assertExec conn "governed_overlay_gate"
    ("WITH gate_names(name) AS (VALUES ('type'),('normalization'),('support'),('provenance'),('topic_authority'),('contradiction'),('confidence'),('curated_canonical_duplicate'),('curated_canonical_subsumption'),('historical_overlay_self_revalidation'),('historical_overlay_duplicate'),('historical_overlay_subsumption'),('informativeness')) INSERT INTO promotion_gate_runs(candidate_id, gate_run_id, gate_name, gate_version, decision, score, reason_code, detail, evaluated_at) SELECT '"
      <> candidateId <> "', l.gate_run_id, n.name, l.policy_version, 'pass', 1, 'ok', 'test-only', 0 FROM promotion_overlay_lineage l CROSS JOIN gate_names n WHERE l.overlay_version='"
      <> overlayVersion <> "'")

assertRollbackRejected :: QxFx0DB -> String -> IO ()
assertRollbackRejected db label = do
  result <- try (rollbackPromotionOverlay db) :: IO (Either SomeException ())
  case result of
    Left _ -> pure ()
    Right () -> assertFailure (label <> " unexpectedly allowed rollback")
  unchanged <- queryCount (qdbConn db)
    "SELECT COUNT(*) FROM promotion_active WHERE singleton=1 AND overlay_version='rollback-child'"
  assertEqual (label <> " must not change active pointer") 1 unchanged

assertLoadRejectedWithoutPointerMutation :: QxFx0DB -> String -> IO ()
assertLoadRejectedWithoutPointerMutation db label = do
  loaded <- loadActivePromotionOverlay db
  assertEqual (label <> " must fail closed") Nothing loaded
  unchanged <- queryCount (qdbConn db)
    "SELECT COUNT(*) FROM promotion_active WHERE singleton=1 AND overlay_version='load-overlay'"
  assertEqual (label <> " must not rewrite active pointer") 1 unchanged

assertOverlayLoaded :: QxFx0DB -> T.Text -> String -> IO ()
assertOverlayLoaded db overlayVersion label = do
  loaded <- loadActivePromotionOverlay db
  case loaded of
    Just (runtime, _) -> assertEqual label overlayVersion (corVersion runtime)
    Nothing -> assertFailure (label <> ": overlay was not loadable")

assertActivationRejected :: QxFx0DB -> T.Text -> String -> IO ()
assertActivationRejected db overlayVersion label = do
  result <- try (activatePromotionOverlay db overlayVersion) :: IO (Either SomeException ())
  case result of
    Left _ -> pure ()
    Right () -> assertFailure (label <> " unexpectedly permitted activation")

assertReleaseRejected :: QxFx0DB -> T.Text -> String -> IO ()
assertReleaseRejected db overlayVersion label = do
  result <- try (recordPromotionHumanRelease db overlayVersion "must fail")
    :: IO (Either SomeException T.Text)
  case result of
    Left _ -> pure ()
    Right evaluationId -> assertFailure
      (label <> " unexpectedly released evaluation " <> T.unpack evaluationId)

assertActiveBinding :: NSQL.Database -> T.Text -> String -> IO ()
assertActiveBinding conn evaluationId label = do
  count <- queryCount conn
    ("SELECT COUNT(*) FROM promotion_active WHERE singleton=1 AND runtime_evaluation_id='"
      <> evaluationId <> "'")
  assertEqual label 1 count

loadLatestTrace :: FilePath -> T.Text -> IO TurnReplayTrace
loadLatestTrace dbPath sessionId = do
  opened <- NSQL.open dbPath
  conn <- case opened of
    Left err -> assertFailure ("cannot reopen selector trace DB: " <> T.unpack err) >> fail "unreachable"
    Right value -> pure value
  result <- (do
      prepared <- NSQL.prepare conn
        "SELECT replay_trace_json FROM turn_quality WHERE session_id = ? ORDER BY turn DESC LIMIT 1"
      stmt <- case prepared of
        Left err -> assertFailure ("trace query failed: " <> T.unpack err) >> fail "unreachable"
        Right value -> pure value
      _ <- NSQL.bindText stmt 1 sessionId
      hasRow <- NSQL.stepRow stmt
      raw <- if hasRow then NSQL.columnTextLenient stmt 0 else pure ""
      NSQL.finalize stmt
      case decodePersistedReplayTrace (TE.encodeUtf8 raw) of
        Left err -> assertFailure ("trace decode failed: " <> err) >> fail "unreachable"
        Right trace -> pure trace
    ) `finally` NSQL.close conn
  pure result

promotionRuntimeTests :: [Test]
promotionRuntimeTests =
  [ testEvaluationCorpusIsDeterministicAndBounded
  , testCuratedPredicateIsSupported
  , testStructuralConflictDoesNotReadRecoveryWords
  , testStructuralConflictRequiresMatchingEndpoints
  , testFailureSidePreservesTimeout
  , testAutomatedGateRequiresObservedOverlayUsage
  , testActiveOverlayReachesSelectorOrRecordsLoss
  , testInformativenessGateRejectsLowInformationPredicate
  , testInformativenessGateAcceptsNovelConstraint
  , testSupportGateRequiresCanonicalCuratedTriple
  , testRollbackRequiresGovernedParent
  , testLoadActiveOverlayFailsClosed
  , testMonotonicPromotionRevalidation
  , testPromotionSchemaMigratesEvaluationScopedReleases
  , testChildOverlayIsCumulativeAndRollbackRestoresExactParent
  , testActivationRequiresCurrentParentAndRootRollbackClearsActive
  ]
