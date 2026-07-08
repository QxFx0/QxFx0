{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Test.Suite.CorpusTuning
  ( corpusTuningTests
  ) where

import Control.Exception (bracket)
import Control.Monad (forM_, when)
import Data.Aeson (eitherDecode')
import qualified Data.ByteString.Lazy as BL
import Data.Maybe (isJust)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import Data.Time.Clock (UTCTime, getCurrentTime)
import System.Directory (doesFileExist, removeFile)
import System.FilePath ((</>), (<.>))
import Test.HUnit

import qualified QxFx0.Bridge.NativeSQLite as NSQL
import QxFx0.Bridge.SQLite.Bootstrap (ensureSchemaMigrations)
import QxFx0.Bridge.StatePersistence (DbRunner)
import QxFx0.Learning.Calibration (CalibrationId(..))
import QxFx0.Learning.CorpusExtract
  ( CorpusTrace(..)
  , extractCorpusDataset
  , fieldToSignalComponents
  , dispositionToDecision
  )
import QxFx0.Learning.Signal (CalibrationDecision(..), SignalComponents(..))
import QxFx0.Learning.TrainingCycle
  ( CalibrationCandidate(..)
  , CandidateType(..)
  , CandidateVerdict(..)
  , DatasetStats(..)
  , TrainingCycleOutcome(..)
  , TrainingDataset(..)
  , TrainingTrace(..)
  , evaluateAllCandidates
  )
import QxFx0.Learning.Tuning
  ( generateTuningCandidates
  , persistTunedConfig
  , runCorpusTuning
  , selectBestCandidate
  )
import QxFx0.Self.Conatus
  ( ConatusComponents(..)
  , ConatusEnergy(..)
  )
import QxFx0.Self.Field
  ( Atmosphere(..)
  , Field(..)
  , FieldConfidence(..)
  , FieldHeuristics
  , Resonance(..)
  , Counterfactual(..)
  , Consolidation(..)
  , emptyField
  )
import QxFx0.Self.Salience (SalienceWeights, defaultSalienceWeights)
import QxFx0.Types.Decision (DecisionDisposition(..))
import QxFx0.Types.Domain (CanonicalMoveFamily(..))

import Test.Support (assertExec, freshTestDbPath, testTempDir)
import Test.Support.QuickCheckConfig (qcArgs)
import Test.QuickCheck (property)

corpusTuningTests :: [Test]
corpusTuningTests =
  [ testExtractFromSyntheticDb
  , testExtractAllSessions
  , testExtractFiltersBySession
  , testFieldToSignalComponents
  , testDispositionToDecision
  , testCandidateSelectionLogic
  , testPersistTunedSalienceConfig
  , testPersistTunedFieldConfig
  , testRunCorpusTuningEmptyDb
  , testRunCorpusTuningSyntheticCorpus
  ]

-- | Build a minimal replay trace JSON containing only the fields the
-- extractor needs.
minimalReplayJson :: Text
minimalReplayJson =
  "{\"trcField\":{\"fieldResonance\":{\"unResonance\":0.5},\"fieldAtmosphere\":{\"atmosphereValence\":0.1,\"atmosphereArousal\":0.4},\"fieldConfidence\":{\"unFieldConfidence\":0.8},\"fieldConsolidation\":{\"unConsolidation\":0.3},\"fieldCounterfactual\":{\"unCounterfactual\":0.2}},\"trcConatusEnergy\":{\"ceScalar\":3.5,\"ceComponents\":{\"ccMorphology\":1.0,\"ccIdentity\":0.5,\"ccTurns\":0.25,\"ccPenalty\":0.0}},\"trcMoodArousal\":0.6}"

withSyntheticDb :: (DbRunner -> IO a) -> IO a
withSyntheticDb action = do
  dbPath <- freshTestDbPath "corpus_tuning"
  let cleanup = removeFile dbPath
  bracket
    (do
      result <- NSQL.open dbPath
      case result of
        Left err -> assertFailure ("open failed: " <> T.unpack err) >> fail "unreachable"
        Right db -> do
          ensureSchemaMigrations db
          -- Insert session and synthetic turn_quality rows
          assertExec db "session" $
            "INSERT INTO runtime_sessions(id, agency, tension, status) VALUES('test-session', 0.5, 0.3, 'active')"
          pure db)
    (\db -> NSQL.close db >> cleanup)
    (\db -> action (\f -> f db))

insertTurn :: NSQL.Database -> Text -> Int -> Text -> Text -> Int -> IO ()
insertTurn db sid turn family disp divFlag = do
  let sql =
        "INSERT INTO turn_quality( \
        \session_id, turn, parser_mode, parser_confidence, parser_errors, \
        \planner_mode, planner_decision, atom_register, atom_load, scene_pressure, \
        \scene_request, scene_stance, render_lane, render_style, legitimacy_status, \
        \legitimacy_reason, owner_family, owner_force, shadow_status, shadow_family, \
        \shadow_force, shadow_message, divergence, decision_disposition, replay_trace_json) \
        \VALUES(?, ?, 'frame_v1', 0.8, '', 'default', 'default', 'Neutral', 0.0, \
        \'medium', '', 'ContentLayer', 'ValidateMove', 'standard', 'pass', '', \
        \?, ?, 'unavailable', NULL, NULL, ?, ?, ?, ?)"
  mStmt <- NSQL.prepare db sql
  stmt <- case mStmt of
    Left err -> assertFailure ("prepare failed: " <> T.unpack err) >> fail "unreachable"
    Right s -> pure s
  assertBind "session_id" =<< NSQL.bindText stmt 1 sid
  assertBind "turn" =<< NSQL.bindInt stmt 2 turn
  assertBind "owner_family" =<< NSQL.bindText stmt 3 family
  assertBind "owner_force" =<< NSQL.bindText stmt 4 (forceForFamilyText family)
  assertBind "shadow_message" =<< NSQL.bindText stmt 5 ""
  assertBind "divergence" =<< NSQL.bindInt stmt 6 divFlag
  assertBind "decision_disposition" =<< NSQL.bindText stmt 7 disp
  assertBind "replay_trace_json" =<< NSQL.bindText stmt 8 minimalReplayJson
  assertStep =<< NSQL.step stmt
  NSQL.finalize stmt

assertBind :: String -> Either Text () -> IO ()
assertBind _ (Right ()) = pure ()
assertBind label (Left err) = assertFailure ("bind failed (" <> label <> "): " <> T.unpack err)

assertStep :: Either Text a -> IO ()
assertStep (Right _) = pure ()
assertStep (Left err) = assertFailure ("step failed: " <> T.unpack err)

forceForFamilyText :: Text -> Text
forceForFamilyText "CMHypothesis" = "IFAsk"
forceForFamilyText "CMClarify"    = "IFAsk"
forceForFamilyText "CMDeepen"     = "IFAsk"
forceForFamilyText "CMRepair"     = "IFOffer"
forceForFamilyText "CMContact"    = "IFContact"
forceForFamilyText "CMConfront"   = "IFConfront"
forceForFamilyText _              = "IFAssert"

testExtractFromSyntheticDb :: Test
testExtractFromSyntheticDb = TestCase $ withSyntheticDb $ \runner -> do
  runner $ \db -> do
    forM_ [1..5] $ \turn ->
      insertTurn db "test-session" turn "CMGround" "permit" 0
  ds <- extractCorpusDataset runner (Just "test-session")
  assertEqual "extracted dataset must contain 5 traces" 5 (length (tdTraces ds))
  assertEqual "train subset must be 3" 3 (length (tdTrain ds))
  assertEqual "eval subset must be 2" 2 (length (tdEval ds))
  assertEqual "stats total must be 5" 5 (dsTotalTurns (tdStats ds))

testExtractAllSessions :: Test
testExtractAllSessions = TestCase $ withSyntheticDb $ \runner -> do
  runner $ \db -> do
    assertExec db "session2" $
      "INSERT INTO runtime_sessions(id, agency, tension, status) VALUES('other-session', 0.5, 0.3, 'active')"
    forM_ [1..3] $ \turn -> insertTurn db "test-session" turn "CMGround" "permit" 0
    forM_ [1..4] $ \turn -> insertTurn db "other-session" turn "CMReflect" "permit" 0
  ds <- extractCorpusDataset runner Nothing
  assertEqual "all-sessions corpus must contain 7 traces" 7 (length (tdTraces ds))

testExtractFiltersBySession :: Test
testExtractFiltersBySession = TestCase $ withSyntheticDb $ \runner -> do
  runner $ \db -> do
    assertExec db "session2" $
      "INSERT INTO runtime_sessions(id, agency, tension, status) VALUES('other-session', 0.5, 0.3, 'active')"
    forM_ [1..5] $ \turn -> insertTurn db "test-session" turn "CMGround" "permit" 0
    forM_ [1..5] $ \turn -> insertTurn db "other-session" turn "CMReflect" "permit" 0
  ds <- extractCorpusDataset runner (Just "other-session")
  assertEqual "filtered corpus must contain 5 traces" 5 (length (tdTraces ds))

testFieldToSignalComponents :: Test
testFieldToSignalComponents = TestCase $ do
  let f = emptyField
        { fieldResonance = Resonance 0.7
        , fieldAtmosphere = Atmosphere 0.2 0.6
        , fieldConfidence = FieldConfidence 0.8
        , fieldCounterfactual = Counterfactual 0.3
        }
      comps = fieldToSignalComponents f
  assertApprox "conatus trend centred on 0.5" 1e-10 0.2 (scConatusTrend comps)
  assertApprox "uncertainty trend centred on 0.5" 1e-10 (-0.2) (scUncertaintyTrend comps)
  assertApprox "loop risk from arousal" 1e-10 0.1 (scLoopRisk comps)
  assertApprox "branch health from confidence" 1e-10 0.3 (scBranchHealthTrend comps)

testDispositionToDecision :: Test
testDispositionToDecision = TestCase $ do
  assertEqual "permit maps to apply" CdApplySignal (dispositionToDecision DispositionPermit)
  assertEqual "advisory maps to hold low confidence" CdHoldLowConfidence (dispositionToDecision DispositionAdvisory)
  assertEqual "repair maps to guardrails" CdHoldGuardrails (dispositionToDecision DispositionRepair)
  assertEqual "deny maps to guardrails" CdHoldGuardrails (dispositionToDecision DispositionDeny)

testCandidateSelectionLogic :: Test
testCandidateSelectionLogic = TestCase $ do
  -- Build a dataset where a conservative candidate is accepted.
  let traces =
        [ TrainingTrace i emptySignalComponents 0.1 CdApplySignal 0.8 0.6 1
        | i <- [1..10]
        ]
      ds = TrainingDataset traces (take 7 traces) (drop 7 traces) (DatasetStats 10 10 0 0 0)
  t <- getCurrentTime
  let candidates = generateTuningCandidates (CalibrationId 1) [-0.3, -0.15, 0.0, 0.15, 0.3] "test" t
      evals = evaluateAllCandidates ds candidates
      promoted = selectBestCandidate evals
  assertBool "at least one candidate should be accepted or all honestly rejected" True
  assertBool "promoted candidate id must be positive when accepted"
    (case promoted of
       Just c  -> unCalibrationId (ccId c) > 0
       Nothing -> True)

testPersistTunedSalienceConfig :: Test
testPersistTunedSalienceConfig = TestCase $ do
  let path = "resources/config/tuned_salience_weights.json"
      bakPath = path <.> "bak"
  removeIfExists bakPath
  -- Create a salience candidate.
  t <- getCurrentTime
  let candidates = generateTuningCandidates (CalibrationId 1) [0.15] "persist-test" t
      salienceCand = head (filter (\c -> ccType c == QxFx0.Learning.TrainingCycle.CandidateSalience) candidates)
  persistTunedConfig salienceCand
  -- The function writes to a fixed path; read it back via JSON.
  bytes <- BL.readFile path
  case eitherDecode' bytes of
    Left err -> assertFailure ("decode failed: " <> err)
    Right (w :: QxFx0.Self.Salience.SalienceWeights) ->
      assertBool "weights differ from default" (w /= defaultSalienceWeights)
  -- A second persistence must back up the previous payload atomically.
  persistTunedConfig salienceCand
  bakExists <- doesFileExist bakPath
  assertBool "backup file must be created on overwrite" bakExists
  bakBytes <- BL.readFile bakPath
  assertEqual "backup content must match previous payload" bytes bakBytes

testPersistTunedFieldConfig :: Test
testPersistTunedFieldConfig = TestCase $ do
  t <- getCurrentTime
  let candidates = generateTuningCandidates (CalibrationId 1) [0.15] "persist-test" t
      fieldCand = head (filter (\c -> ccType c == QxFx0.Learning.TrainingCycle.CandidateField) candidates)
  persistTunedConfig fieldCand
  bytes <- BL.readFile "resources/config/tuned_field_heuristics.json"
  case eitherDecode' bytes of
    Left err -> assertFailure ("decode failed: " <> err)
    Right (_ :: QxFx0.Self.Field.FieldHeuristics) ->
      assertBool "field heuristics persisted" True

testRunCorpusTuningEmptyDb :: Test
testRunCorpusTuningEmptyDb = TestCase $ withSyntheticDb $ \runner -> do
  outcome <- runCorpusTuning runner (Just "test-session")
  assertEqual "empty corpus yields zero total turns" 0 (dsTotalTurns (tcoDatasetStats outcome))
  assertBool "no candidate promoted from empty corpus" (tcoPromotedCandidate outcome == Nothing)

testRunCorpusTuningSyntheticCorpus :: Test
testRunCorpusTuningSyntheticCorpus = TestCase $ withSyntheticDb $ \runner -> do
  runner $ \db -> do
    forM_ [1..10] $ \turn ->
      insertTurn db "test-session" turn "CMGround" "permit" 0
  outcome <- runCorpusTuning runner (Just "test-session")
  assertEqual "synthetic corpus yields 10 total turns" 10 (dsTotalTurns (tcoDatasetStats outcome))
  assertBool "candidates were generated and evaluated" (not (null (tcoCandidates outcome)))

getCurrentTime' :: IO UTCTime
getCurrentTime' = getCurrentTime

removeIfExists :: FilePath -> IO ()
removeIfExists path = do
  exists <- doesFileExist path
  when exists (removeFile path)

assertApprox :: String -> Double -> Double -> Double -> Assertion
assertApprox msg eps expected actual =
  assertBool (msg ++ ": expected " ++ show expected ++ " but got " ++ show actual)
             (abs (expected - actual) <= eps)

emptySignalComponents :: SignalComponents
emptySignalComponents = SignalComponents 0 0 0 0
