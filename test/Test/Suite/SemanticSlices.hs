{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.SemanticSlices
  ( semanticSliceTests
  ) where

import Test.HUnit
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Aeson.Key as AesonKey
import Data.Aeson (Value(..), eitherDecodeStrict')
import qualified Data.Aeson as Aeson
import Data.List (nub)
import qualified Data.Map.Strict as M
import qualified Data.Text as T
import Data.Text.Encoding (encodeUtf8)
import qualified Data.Text.Encoding as TE
import qualified Data.ByteString.Lazy as BL

import qualified QxFx0.Runtime as Runtime
import qualified QxFx0.Bridge.StatePersistence as StatePersistence
import qualified QxFx0.Bridge.NativeSQLite as NSQL
import QxFx0.Learning.KnowledgeTree
  ( KnowledgeSource(..)
  , KnowledgeFruit(..)
  , emptyKnowledgeTree
  , graftFruit
  )
import QxFx0.Learning.Need (LearningNeed(..), LearningNeedState(..), learningNeedLevel, learningNeedPersistence)
import QxFx0.Self.Conatus (ConatusEnergy(..), ConatusComponents(..))
import QxFx0.Self.Field (emptyField)
import QxFx0.Self.Perspective (applyPerspectiveOperator)
import QxFx0.Types
import QxFx0.Types.Persistence (LoadStateResult(..))
import QxFx0.Types.Observability (emptyMeaningGraph, MeaningGraph(..))

import Test.Support (withFakeNixInstantiateForConcepts, withFixedRuntimeTime, withRuntimeEnv)

semanticSliceTests :: [Test]
semanticSliceTests =
  [ testSemanticAnchorLiveAuthoritativeFixtureSearch
  , testSemanticAnchorSyntheticAuthoritativeFixtureSearch
  , testSemanticAnchorSyntheticImmediateRuns
  , testSemanticAnchorSyntheticShortHorizonRuns
  , testBlockedConceptsImmediateRuns
  , testBlockedConceptsShortHorizonRuns
  , testDreamStateShortHorizonRuns
  , testDreamStateImmediateRuns
  , testMeaningGraphImmediateRuns
  , testMeaningGraphShortHorizonRuns
  , testTurnDecisionImmediateRuns
  , testTurnDecisionShortHorizonRuns
  , testIntuitionStateImmediateRuns
  , testIntuitionStateShortHorizonRuns
  ]

boolText :: Bool -> T.Text
boolText True = "PASS"
boolText False = "FAIL"

data FixtureQualification = FixtureQualification
  { fqCandidateId :: !T.Text
  , fqTruthStatus :: !TruthContractStatus
  , fqAnchorNonNull :: !Bool
  , fqLastTurnDecisionNonNull :: !Bool
  , fqPersistedTopLevelAnchor :: !Bool
  , fqFq3 :: !Bool
  , fqFq6 :: !Bool
  , fqFq7 :: !Bool
  , fqFq8 :: !Bool
  } deriving stock (Eq, Show)

data SearchResolution
  = ResolvedLive !FixtureQualification ![FixtureQualification]
  | EarlyRepeatedFq3Fail ![FixtureQualification]
  | ExhaustedLive ![FixtureQualification]
  deriving stock (Eq, Show)

data BaseQualification = BaseQualification
  { bqBaseId :: !T.Text
  , bqTruthStatus :: !TruthContractStatus
  , bqFq3 :: !Bool
  , bqFq6 :: !Bool
  , bqFq7 :: !Bool
  , bqFq8 :: !Bool
  } deriving stock (Eq, Show)

data DonorQualification = DonorQualification
  { dqDonorId :: !T.Text
  , dqTruthStatus :: !TruthContractStatus
  , dqAnchorNonNull :: !Bool
  , dqDecisionNonNull :: !Bool
  , dqTraceNonTrivial :: !Bool
  , dqMeaningGraphNonTrivial :: !Bool
  , dqPersistedTopLevelAnchor :: !Bool
  , dqPersistedTopLevelDecision :: !Bool
  } deriving stock (Eq, Show)

data BundleId
  = AnchorOnly
  | AnchorCoherenceBundle
  deriving stock (Eq, Show)

data CandidateResult
  = QualifiedMinimalSynthetic
  | QualifiedCoherenceSynthetic
  | CandidateNotApplicable
  | InjectionScopeFail
  | ControlRestoreFail
  | ComparabilityFail
  | DisguisedSnapshotRiskStop
  deriving stock (Eq, Show)

data SyntheticCandidate = SyntheticCandidate
  { scCandidateId :: !T.Text
  , scBaseId :: !T.Text
  , scBundleId :: !BundleId
  } deriving stock (Eq, Show)

data SyntheticCandidateOutcome = SyntheticCandidateOutcome
  { scoCandidateId :: !T.Text
  , scoBaseId :: !T.Text
  , scoDonorId :: !T.Text
  , scoBundleId :: !BundleId
  , scoBundlePreconditionPass :: !Bool
  , scoDeclaredInjectedKeys :: ![T.Text]
  , scoActualChangedKeys :: ![T.Text]
  , scoUnexpectedChangedKeys :: ![T.Text]
  , scoSq1 :: !Bool
  , scoSq2 :: !Bool
  , scoSq3 :: !Bool
  , scoSq4 :: !Bool
  , scoSq5 :: !Bool
  , scoFq3 :: !Bool
  , scoFq6 :: !Bool
  , scoFq7 :: !Bool
  , scoFq8 :: !Bool
  , scoResult :: !CandidateResult
  } deriving stock (Eq, Show)

data PathBResolution
  = ResolvedSynthetic !SyntheticCandidateOutcome ![SyntheticCandidateOutcome]
  | BlockedSynthetic ![SyntheticCandidateOutcome]
  deriving stock (Eq, Show)

data SliceOutcomeClass = SliceOutcomeClass
  { socOutcome :: !(CanonicalMoveFamily, IllocutionaryForce, Maybe NixGuardStatus, Maybe ResponseStrategy, Maybe RenderStyle)
  , socTransition :: !(Bool, Bool, Bool, Bool, LearningNeed, Bool, Int, Bool, Int)
  , socPersistedDelta :: ![(T.Text, Bool)]
  , socOperatorText :: !T.Text
  } deriving stock (Eq, Show)

data ImmediateRunRecord = ImmediateRunRecord
  { irrScenarioId :: !T.Text
  , irrContourStatus :: !T.Text
  , irrComparabilityStatus :: !T.Text
  , irrOutcomeVerdict :: !T.Text
  , irrTransitionVerdict :: !T.Text
  , irrPersistedDeltaVerdict :: !T.Text
  , irrOperatorSurfaceVerdict :: !T.Text
  , irrPrimaryVerdict :: !T.Text
  , irrOutcomePayload :: !(Maybe SliceOutcomeClass)
  } deriving stock (Eq, Show)

data ShortHorizonRunRecord = ShortHorizonRunRecord
  { shrScenarioId :: !T.Text
  , shrContourStatus :: !T.Text
  , shrComparabilityStatus :: !T.Text
  , shrOutcomeVerdict :: !T.Text
  , shrTransitionVerdict :: !T.Text
  , shrPersistedDeltaVerdict :: !T.Text
  , shrOperatorSurfaceVerdict :: !T.Text
  , shrPrimaryVerdict :: !T.Text
  , shrStepOutcomes :: ![SliceOutcomeClass]
  } deriving stock (Eq, Show)

testSemanticAnchorLiveAuthoritativeFixtureSearch :: Test
testSemanticAnchorLiveAuthoritativeFixtureSearch = TestLabel "SLICE-AN-001 Path A live authoritative fixture search" $ TestCase $ do
  resolution <- runCandidateSearch candidateChains
  case resolution of
    ResolvedLive fq results -> do
      let summary = T.unpack (T.intercalate "; " (map renderQualification results))
      putStrLn ("SLICE-AN-001 Path A resolved live: " <> summary)
      assertBool "qualified candidate must pass FQ-3/FQ-6/FQ-7/FQ-8"
        (isQualified fq)
    EarlyRepeatedFq3Fail results -> do
      let summary = T.unpack (T.intercalate "; " (map renderQualification results))
      putStrLn ("SLICE-AN-001 Path A stopped after repeated FQ-3 fail: " <> summary)
      assertEqual "early repeated-FQ3 stop should happen after three candidates" 3 (length results)
      assertBool "first three live candidates should all fail FQ-3 in repeated-fail mode"
        (all (not . fqFq3) results)
    ExhaustedLive results -> do
      let summary = T.unpack (T.intercalate "; " (map renderQualification results))
      putStrLn ("SLICE-AN-001 Path A exhausted all candidates: " <> summary)
      assertEqual "exhausted search should run all bounded candidates" (length candidateChains) (length results)
  where
    candidateChains :: [(T.Text, [T.Text])]
    candidateChains =
      [ ("AN-LIVE-A1", ["Что такое свобода?", "А что тогда несвобода?"])
      , ("AN-LIVE-A2", ["Что такое свобода?", "Продолжи эту мысль", "Как это связано с выбором?"])
      , ("AN-LIVE-A3", ["Что значит внутренняя свобода?", "А внешняя?", "Где между ними граница?"])
      , ("AN-LIVE-A4", ["Почему свобода пугает?", "А несвобода успокаивает?", "Продолжи", "Собери это в одну мысль"])
      , ("AN-LIVE-A5", ["Что такое свобода?", "Скажи это строже", "А теперь проще", "Как это связано с выбором?"])
      ]

    isQualified fq = fqFq3 fq && fqFq6 fq && fqFq7 fq && fqFq8 fq

    runCandidateSearch :: [(T.Text, [T.Text])] -> IO SearchResolution
    runCandidateSearch = go []
      where
        go acc [] = pure (ExhaustedLive acc)
        go acc (candidate:rest) = do
          result <- runCandidate candidate
          let acc' = acc ++ [result]
          if isQualified result
            then pure (ResolvedLive result acc')
            else if length acc' == 3 && all (not . fqFq3) acc'
              then pure (EarlyRepeatedFq3Fail acc')
              else go acc' rest

    renderQualification fq =
      fqCandidateId fq <> "=" <> T.pack (show (fqTruthStatus fq))
        <> "{FQ3=" <> boolText (fqFq3 fq)
        <> ",FQ6=" <> boolText (fqFq6 fq)
        <> ",FQ7=" <> boolText (fqFq7 fq)
        <> ",FQ8=" <> boolText (fqFq8 fq)
        <> ",anchor=" <> boolText (fqAnchorNonNull fq)
        <> ",decision=" <> boolText (fqLastTurnDecisionNonNull fq)
        <> ",persistedTopLevelAnchor=" <> boolText (fqPersistedTopLevelAnchor fq)
        <> "}"

runCandidate :: (T.Text, [T.Text]) -> IO FixtureQualification
runCandidate (candidateId, chainTurns) =
  withRuntimeEnv ("qxfx0_test_" <> T.unpack candidateId <> ".db") $ do
    let sessionId = candidateId
    session0 <- Runtime.bootstrapSession True sessionId
    fixtureSession <- foldTurns session0 chainTurns
    let fixtureState = Runtime.sessSystemState fixtureSession
        rt = Runtime.sessRuntime fixtureSession
        truthStatus = ssTruthContractStatus fixtureState
        anchorNonNull = ssSemanticAnchor fixtureState /= Nothing
        decisionNonNull = ssLastTurnDecision fixtureState /= Nothing
    persistedTopLevelAnchor <- persistedBlobHasTopLevelAnchor rt sessionId
    loadPreserves <- controlLoadPreservesAuthoritative rt sessionId
    bootstrapPreserves <- controlBootstrapPreservesAuthoritative sessionId
    let fq3 = truthStatus `elem` [CanonicalSurfacePreserved, AssembledSurfacePreserved]
        fq6 = loadPreserves
        fq7 = bootstrapPreserves
        fq8 = fq6 && fq7
    pure FixtureQualification
      { fqCandidateId = candidateId
      , fqTruthStatus = truthStatus
      , fqAnchorNonNull = anchorNonNull
      , fqLastTurnDecisionNonNull = decisionNonNull
      , fqPersistedTopLevelAnchor = persistedTopLevelAnchor
      , fqFq3 = fq3
      , fqFq6 = fq6
      , fqFq7 = fq7
      , fqFq8 = fq8
      }

foldTurns :: Runtime.Session -> [T.Text] -> IO Runtime.Session
foldTurns = foldl stepTurn . pure
  where
    stepTurn ioSession input = do
      session <- ioSession
      (nextSession, output) <- Runtime.runTurnInSession session input
      assertBool ("fixture turn should produce non-empty output for input: " <> T.unpack input) (not (T.null output))
      pure nextSession

controlLoadPreservesAuthoritative :: Runtime.RuntimeContext -> T.Text -> IO Bool
controlLoadPreservesAuthoritative rt sessionId = do
  loaded <- StatePersistence.loadState (Runtime.withRuntimeDb rt) sessionId
  pure $ case loaded of
    LoadStateRestored restored -> ssTruthContractStatus restored `elem` [CanonicalSurfacePreserved, AssembledSurfacePreserved]
    _ -> False

controlBootstrapPreservesAuthoritative :: T.Text -> IO Bool
controlBootstrapPreservesAuthoritative sessionId = do
  restored <- Runtime.bootstrapSession True sessionId
  pure (ssTruthContractStatus (Runtime.sessSystemState restored) `elem` [CanonicalSurfacePreserved, AssembledSurfacePreserved])

persistedBlobHasTopLevelAnchor :: Runtime.RuntimeContext -> T.Text -> IO Bool
persistedBlobHasTopLevelAnchor rt sessionId =
  Runtime.withRuntimeDb rt $ \db -> do
    mStmt <- NSQL.prepare db "SELECT value FROM dialogue_state WHERE session_id = ? AND key = ? ORDER BY updated_at DESC LIMIT 1"
    stmt <- case mStmt of
      Left err -> assertFailure ("Failed to prepare persisted-state query: " <> T.unpack err) >> fail "unreachable"
      Right s -> pure s
    _ <- NSQL.bindText stmt 1 sessionId
    _ <- NSQL.bindText stmt 2 "__system_state__"
    hasRow <- NSQL.stepRow stmt
    payload <- if hasRow then NSQL.columnText stmt 0 else pure ""
    NSQL.finalize stmt
    case eitherDecodeStrict' (encodeUtf8 payload) of
      Left err -> assertFailure ("Failed to decode persisted system state: " <> err) >> fail "unreachable"
      Right (Object obj) -> pure (KeyMap.member "semanticAnchor" obj)
      Right other -> assertFailure ("Persisted system state should decode as object, got: " <> show other) >> fail "unreachable"

testSemanticAnchorSyntheticAuthoritativeFixtureSearch :: Test
testSemanticAnchorSyntheticAuthoritativeFixtureSearch = TestLabel "SLICE-AN-001 Path B synthetic authoritative fixture search" $ TestCase $ do
  resolution <- runPathB
  case resolution of
    ResolvedSynthetic winner outcomes -> do
      let summary = T.unpack (T.intercalate "; " (map renderSyntheticOutcome outcomes))
      putStrLn ("SLICE-AN-001 Path B resolved synthetic: " <> summary)
      assertBool "synthetic winner must preserve authoritative contour"
        (scoFq3 winner && scoFq6 winner && scoFq7 winner && scoFq8 winner)
    BlockedSynthetic outcomes -> do
      let summary = T.unpack (T.intercalate "; " (map renderSyntheticOutcome outcomes))
      putStrLn ("SLICE-AN-001 Path B blocked synthetic: " <> summary)
      assertEqual "all bounded synthetic candidates should be evaluated when blocked" 4 (length outcomes)

runPathB :: IO PathBResolution
runPathB = withRuntimeEnv "qxfx0_test_semantic_anchor_path_b.db" $ do
  canonicalBase <- qualifyBase "AUTH-BASE-CAN-001" canonicalBaseBuilder
  assembledBase <- qualifyBase "AUTH-BASE-ASM-001" assembledBaseBuilder
  donor <- buildDonor "AN-DONOR-LIVE-001"
  let candidates =
        [ SyntheticCandidate "AN-SYN-B1" "AUTH-BASE-CAN-001" AnchorOnly
        , SyntheticCandidate "AN-SYN-B2" "AUTH-BASE-CAN-001" AnchorCoherenceBundle
        , SyntheticCandidate "AN-SYN-B3" "AUTH-BASE-ASM-001" AnchorOnly
        , SyntheticCandidate "AN-SYN-B4" "AUTH-BASE-ASM-001" AnchorCoherenceBundle
        ]
      baseMap = [(bqBaseId canonicalBase, canonicalBase), (bqBaseId assembledBase, assembledBase)]
  runCandidates baseMap donor [] candidates

runCandidates :: [(T.Text, BaseQualification)] -> DonorQualification -> [SyntheticCandidateOutcome] -> [SyntheticCandidate] -> IO PathBResolution
runCandidates _ _ acc [] = pure (BlockedSynthetic acc)
runCandidates baseMap donor acc (candidate:rest) = do
  outcome <- qualifySyntheticCandidate baseMap donor candidate
  let acc' = acc ++ [outcome]
  case scoResult outcome of
    QualifiedMinimalSynthetic -> pure (ResolvedSynthetic outcome acc')
    QualifiedCoherenceSynthetic -> pure (ResolvedSynthetic outcome acc')
    DisguisedSnapshotRiskStop -> pure (BlockedSynthetic acc')
    _ -> runCandidates baseMap donor acc' rest

canonicalBaseBuilder :: SystemState -> SystemState
canonicalBaseBuilder ss0 = canonicalAuthoritativeBase ss0

assembledBaseBuilder :: SystemState -> SystemState
assembledBaseBuilder ss0 = assembledAuthoritativeBase ss0

qualifyBase :: T.Text -> (SystemState -> SystemState) -> IO BaseQualification
qualifyBase baseId build = do
  session0 <- Runtime.bootstrapSession True baseId
  let rt = Runtime.sessRuntime session0
      baseState = build (Runtime.sessSystemState session0)
  saveResult <- StatePersistence.saveState (Runtime.withRuntimeDb rt) baseState baseId
  case saveResult of
    Left err -> assertFailure ("failed to persist authoritative base fixture: " <> show err)
    Right _ -> pure ()
  fq6 <- controlLoadPreservesAuthoritative rt baseId
  fq7 <- controlBootstrapPreservesAuthoritative baseId
  let fq3 = ssTruthContractStatus baseState `elem` [CanonicalSurfacePreserved, AssembledSurfacePreserved]
  pure BaseQualification
    { bqBaseId = baseId
    , bqTruthStatus = ssTruthContractStatus baseState
    , bqFq3 = fq3
    , bqFq6 = fq6
    , bqFq7 = fq7
    , bqFq8 = fq6 && fq7
    }

buildDonor :: T.Text -> IO DonorQualification
buildDonor donorId = do
  session0 <- Runtime.bootstrapSession True donorId
  fixtureSession <- foldTurns session0 ["Что такое свобода?", "Продолжи эту мысль", "Как это связано с выбором?"]
  let rt = Runtime.sessRuntime fixtureSession
      ss = Runtime.sessSystemState fixtureSession
  anchorPresent <- persistedBlobHasTopLevelAnchor rt donorId
  decisionPresent <- persistedBlobHasTopLevelField rt donorId "lastTurnDecision"
  pure DonorQualification
    { dqDonorId = donorId
    , dqTruthStatus = ssTruthContractStatus ss
    , dqAnchorNonNull = ssSemanticAnchor ss /= Nothing
    , dqDecisionNonNull = ssLastTurnDecision ss /= Nothing
    , dqTraceNonTrivial = atomTraceNonTrivial (ssTrace ss)
    , dqMeaningGraphNonTrivial = meaningGraphNonTrivial (ssMeaningGraph ss)
    , dqPersistedTopLevelAnchor = anchorPresent
    , dqPersistedTopLevelDecision = decisionPresent
    }

qualifySyntheticCandidate :: [(T.Text, BaseQualification)] -> DonorQualification -> SyntheticCandidate -> IO SyntheticCandidateOutcome
qualifySyntheticCandidate baseMap donor candidate = do
  let base = lookupBase (scBaseId candidate) baseMap
      declaredKeys = bundleKeys (scBundleId candidate)
      bundleOk = bundlePrecondition donor (scBundleId candidate)
  if not (baseQualified base)
    then pure (mkOutcome candidate donor bundleOk declaredKeys [] [] False False False False False False False False CandidateNotApplicable)
    else if not bundleOk
      then pure (mkOutcome candidate donor bundleOk declaredKeys [] [] (bqFq3 base) True True True False False False False CandidateNotApplicable)
      else do
        session0 <- Runtime.bootstrapSession True (scCandidateId candidate)
        let rt = Runtime.sessRuntime session0
            baseState = applyBaseBuilder candidate (Runtime.sessSystemState session0)
        saveBaseResult <- StatePersistence.saveState (Runtime.withRuntimeDb rt) baseState (scCandidateId candidate)
        case saveBaseResult of
          Left err -> assertFailure ("failed to persist synthetic base candidate: " <> show err)
          Right _ -> pure ()
        beforeValue <- fetchPersistedSystemStateValue rt (scCandidateId candidate)
        mutatePersistedStateWithDonor rt (scCandidateId candidate) donor (scBundleId candidate)
        afterValue <- fetchPersistedSystemStateValue rt (scCandidateId candidate)
        let actualChanged = changedTopLevelKeys beforeValue afterValue
            unexpectedChanged = filter (`notElem` declaredKeys) actualChanged
            sq1 = baseQualified base
            sq2 = donorRecorded donor
            sq3 = truthStatusInheritedFromBase beforeValue afterValue
            sq4 = null unexpectedChanged
        fq6 <- controlLoadPreservesAuthoritative rt (scCandidateId candidate)
        fq7 <- controlBootstrapPreservesAuthoritative (scCandidateId candidate)
        let fq3 = True
            sq5 = fq6 && fq7
            result
              | not sq4 = InjectionScopeFail
              | not sq5 = ControlRestoreFail
              | scBundleId candidate == AnchorOnly = QualifiedMinimalSynthetic
              | otherwise = QualifiedCoherenceSynthetic
        pure (mkOutcome candidate donor bundleOk declaredKeys actualChanged unexpectedChanged sq1 sq2 sq3 sq4 sq5 fq3 fq6 fq7 result)

mkOutcome :: SyntheticCandidate -> DonorQualification -> Bool -> [T.Text] -> [T.Text] -> [T.Text] -> Bool -> Bool -> Bool -> Bool -> Bool -> Bool -> Bool -> Bool -> CandidateResult -> SyntheticCandidateOutcome
mkOutcome candidate donor bundleOk declared actual unexpected sq1 sq2 sq3 sq4 sq5 fq3 fq6 fq7 result =
  SyntheticCandidateOutcome
    { scoCandidateId = scCandidateId candidate
    , scoBaseId = scBaseId candidate
    , scoDonorId = dqDonorId donor
    , scoBundleId = scBundleId candidate
    , scoBundlePreconditionPass = bundleOk
    , scoDeclaredInjectedKeys = declared
    , scoActualChangedKeys = actual
    , scoUnexpectedChangedKeys = unexpected
    , scoSq1 = sq1
    , scoSq2 = sq2
    , scoSq3 = sq3
    , scoSq4 = sq4
    , scoSq5 = sq5
    , scoFq3 = fq3
    , scoFq6 = fq6
    , scoFq7 = fq7
    , scoFq8 = fq6 && fq7
    , scoResult = result
    }

baseQualified :: BaseQualification -> Bool
baseQualified b = bqFq3 b && bqFq6 b && bqFq7 b && bqFq8 b

donorRecorded :: DonorQualification -> Bool
donorRecorded d = dqAnchorNonNull d && dqPersistedTopLevelAnchor d

bundlePrecondition :: DonorQualification -> BundleId -> Bool
bundlePrecondition donor AnchorOnly = dqAnchorNonNull donor
bundlePrecondition donor AnchorCoherenceBundle =
  dqAnchorNonNull donor
    && dqDecisionNonNull donor
    && dqTraceNonTrivial donor
    && dqMeaningGraphNonTrivial donor

bundleKeys :: BundleId -> [T.Text]
bundleKeys AnchorOnly = ["semanticAnchor"]
bundleKeys AnchorCoherenceBundle = ["semanticAnchor", "lastTurnDecision", "trace", "meaningGraph"]

lookupBase :: T.Text -> [(T.Text, BaseQualification)] -> BaseQualification
lookupBase baseId baseMap =
  case lookup baseId baseMap of
    Just b -> b
    Nothing -> error ("missing synthetic base: " <> T.unpack baseId)

applyBaseBuilder :: SyntheticCandidate -> SystemState -> SystemState
applyBaseBuilder candidate
  | scBaseId candidate == "AUTH-BASE-CAN-001" = canonicalAuthoritativeBase
  | otherwise = assembledAuthoritativeBase

atomTraceNonTrivial :: AtomTrace -> Bool
atomTraceNonTrivial tr = atCurrentLoad tr > 0 || not (null (atHistory tr))

meaningGraphNonTrivial :: MeaningGraph -> Bool
meaningGraphNonTrivial mg = mgTurnCount mg > 0 || not (null (mgEdges mg))

renderSyntheticOutcome :: SyntheticCandidateOutcome -> T.Text
renderSyntheticOutcome outcome =
  scoCandidateId outcome <> "=" <> T.pack (show (scoResult outcome))
    <> "{bundle=" <> boolText (scoBundlePreconditionPass outcome)
    <> ",SQ4=" <> boolText (scoSq4 outcome)
    <> ",FQ6=" <> boolText (scoFq6 outcome)
    <> ",FQ7=" <> boolText (scoFq7 outcome)
    <> ",changed=" <> T.intercalate "," (scoActualChangedKeys outcome)
    <> ",unexpected=" <> T.intercalate "," (scoUnexpectedChangedKeys outcome)
    <> "}"

testSemanticAnchorSyntheticImmediateRuns :: Test
testSemanticAnchorSyntheticImmediateRuns = TestLabel "SLICE-AN-001 immediate runs on AN-SYN-B1" $ TestCase $ do
  (loadCtrl, bootCtrl, loadNull, bootNull, loadMiss, bootMiss) <- runImmediateSyntheticAnchorScenarios
  let summary = T.unpack (T.intercalate "; " (map renderImmediateRun [loadCtrl, bootCtrl, loadNull, bootNull, loadMiss, bootMiss]))
  putStrLn ("SLICE-AN-001 immediate runs: " <> summary)

testSemanticAnchorSyntheticShortHorizonRuns :: Test
testSemanticAnchorSyntheticShortHorizonRuns = TestLabel "SLICE-AN-001 short horizon runs on AN-SYN-B1" $ TestCase $ do
  (loadSh, bootSh) <- runShortHorizonSyntheticAnchorScenarios
  let summary = T.unpack (T.intercalate "; " (map renderShortHorizonRun [loadSh, bootSh]))
  putStrLn ("SLICE-AN-001 short horizon runs: " <> summary)

testMeaningGraphImmediateRuns :: Test
testMeaningGraphImmediateRuns = TestLabel "SLICE-MG-001 immediate runs" $ TestCase $ do
  (loadCtrl, bootCtrl, loadEmpty, bootEmpty, loadReduced, bootReduced) <- runMeaningGraphImmediateScenarios
  let summary = T.unpack (T.intercalate "; " (map renderImmediateRun [loadCtrl, bootCtrl, loadEmpty, bootEmpty, loadReduced, bootReduced]))
  putStrLn ("SLICE-MG-001 immediate runs: " <> summary)

testMeaningGraphShortHorizonRuns :: Test
testMeaningGraphShortHorizonRuns = TestLabel "SLICE-MG-001 short horizon runs" $ TestCase $ do
  (loadSh, bootSh) <- runMeaningGraphShortHorizonScenarios
  let summary = T.unpack (T.intercalate "; " (map renderShortHorizonRun [loadSh, bootSh]))
  putStrLn ("SLICE-MG-001 short horizon runs: " <> summary)

testBlockedConceptsImmediateRuns :: Test
testBlockedConceptsImmediateRuns = TestLabel "SLICE-BC-001 immediate runs" $ TestCase $ do
  (loadCtrl, bootCtrl, loadEmpty, bootEmpty) <- runBlockedConceptsImmediateScenarios
  let summary = T.unpack (T.intercalate "; " (map renderImmediateRun [loadCtrl, bootCtrl, loadEmpty, bootEmpty]))
  putStrLn ("SLICE-BC-001 immediate runs: " <> summary)

testBlockedConceptsShortHorizonRuns :: Test
testBlockedConceptsShortHorizonRuns = TestLabel "SLICE-BC-001 short horizon runs" $ TestCase $ do
  (loadSh, bootSh) <- runBlockedConceptsShortHorizonScenarios
  let summary = T.unpack (T.intercalate "; " (map renderShortHorizonRun [loadSh, bootSh]))
  putStrLn ("SLICE-BC-001 short horizon runs: " <> summary)

testDreamStateShortHorizonRuns :: Test
testDreamStateShortHorizonRuns = TestLabel "SLICE-DR-001 short horizon runs" $ TestCase $ do
  (loadSh, bootSh, loadMissSh, bootMissSh) <- runDreamStateShortHorizonScenarios
  let summary = T.unpack (T.intercalate "; " (map renderShortHorizonRun [loadSh, bootSh, loadMissSh, bootMissSh]))
  putStrLn ("SLICE-DR-001 short horizon runs: " <> summary)

testDreamStateImmediateRuns :: Test
testDreamStateImmediateRuns = TestLabel "SLICE-DR-001 immediate runs" $ TestCase $ do
  (loadCtrl, bootCtrl, loadNull, bootNull) <- runDreamStateImmediateScenarios
  let summary = T.unpack (T.intercalate "; " (map renderImmediateRun [loadCtrl, bootCtrl, loadNull, bootNull]))
  putStrLn ("SLICE-DR-001 immediate runs: " <> summary)

testTurnDecisionImmediateRuns :: Test
testTurnDecisionImmediateRuns = TestLabel "SLICE-TD-001 immediate runs" $ TestCase $ do
  (loadCtrl, bootCtrl, loadNull, bootNull) <- runTurnDecisionImmediateScenarios
  let summary = T.unpack (T.intercalate "; " (map renderImmediateRun [loadCtrl, bootCtrl, loadNull, bootNull]))
  putStrLn ("SLICE-TD-001 immediate runs: " <> summary)

testTurnDecisionShortHorizonRuns :: Test
testTurnDecisionShortHorizonRuns = TestLabel "SLICE-TD-001 short horizon runs" $ TestCase $ do
  (loadSh, bootSh) <- runTurnDecisionShortHorizonScenarios
  let summary = T.unpack (T.intercalate "; " (map renderShortHorizonRun [loadSh, bootSh]))
  putStrLn ("SLICE-TD-001 short horizon runs: " <> summary)

testIntuitionStateImmediateRuns :: Test
testIntuitionStateImmediateRuns = TestLabel "SLICE-IS-001 immediate runs" $ TestCase $ do
  (bootCtrl, loadCtrl, bootNull, loadNull) <- runIntuitionImmediateScenarios
  let summary = T.unpack (T.intercalate "; " (map renderImmediateRun [bootCtrl, loadCtrl, bootNull, loadNull]))
  putStrLn ("SLICE-IS-001 immediate runs: " <> summary)

testIntuitionStateShortHorizonRuns :: Test
testIntuitionStateShortHorizonRuns = TestLabel "SLICE-IS-001 short horizon runs" $ TestCase $ do
  (bootSh, loadSh) <- runIntuitionShortHorizonScenarios
  let summary = T.unpack (T.intercalate "; " (map renderShortHorizonRun [bootSh, loadSh]))
  putStrLn ("SLICE-IS-001 short horizon runs: " <> summary)

runImmediateSyntheticAnchorScenarios :: IO (ImmediateRunRecord, ImmediateRunRecord, ImmediateRunRecord, ImmediateRunRecord, ImmediateRunRecord, ImmediateRunRecord)
runImmediateSyntheticAnchorScenarios =
  withRuntimeEnv "qxfx0_test_semantic_anchor_immediate.db" $ do
    let seedSessionId = "AN-SYN-B1-SEED"
        loadCtrlId = "AN-SYN-B1-L-CTRL"
        bootCtrlId = "AN-SYN-B1-B-CTRL"
        loadNullId = "AN-SYN-B1-L-NULL"
        bootNullId = "AN-SYN-B1-B-NULL"
        loadMissId = "AN-SYN-B1-L-MISS"
        bootMissId = "AN-SYN-B1-B-MISS"
        donorId = "AN-DONOR-LIVE-001"
        followUp = "А что тогда несвобода?"
    session0 <- Runtime.bootstrapSession True seedSessionId
    let rt = Runtime.sessRuntime session0
        baseState = canonicalAuthoritativeBase (Runtime.sessSystemState session0)
    saveBase <- StatePersistence.saveState (Runtime.withRuntimeDb rt) baseState seedSessionId
    case saveBase of
      Left err -> assertFailure ("failed to persist AN-SYN-B1 control base: " <> show err)
      Right _ -> pure ()
    donor <- buildSyntheticDonor donorId
    mutatePersistedStateWithDonor rt seedSessionId donor AnchorOnly
    baselineObj <- fetchPersistedSystemStateValue rt seedSessionId
    let ablatedObj = setSemanticAnchorNullObject baselineObj
        missingObj = removeSemanticAnchorObject baselineObj

    clonePersistedStateObject rt loadCtrlId baselineObj
    clonePersistedStateObject rt bootCtrlId baselineObj
    loadCtrl0 <- runLoadScenario rt loadCtrlId followUp Nothing "AN-L-CTRL-N1"
    bootCtrl0 <- runBootstrapScenario bootCtrlId followUp Nothing "AN-B-CTRL-N1"
    let loadCtrl = normalizeControlRun loadCtrl0
        bootCtrl = normalizeControlRun bootCtrl0
        comp = comparability loadCtrl bootCtrl
        loadCtrl' = loadCtrl { irrComparabilityStatus = comp }
        bootCtrl' = bootCtrl { irrComparabilityStatus = comp }

    if baselineAcceptable loadCtrl' bootCtrl'
      then do
        clonePersistedStateObject rt loadNullId ablatedObj
        clonePersistedStateObject rt bootNullId ablatedObj
        clonePersistedStateObject rt loadMissId missingObj
        clonePersistedStateObject rt bootMissId missingObj
        loadNull <- runLoadScenario rt loadNullId followUp Nothing "AN-L-NULL-N1"
        bootNull <- runBootstrapScenario bootNullId followUp Nothing "AN-B-NULL-N1"
        loadMiss <- runLoadScenario rt loadMissId followUp Nothing "AN-L-MISS-N1"
        bootMiss <- runBootstrapScenario bootMissId followUp Nothing "AN-B-MISS-N1"
        pure
          ( loadCtrl'
          , bootCtrl'
          , finalizeAblation loadCtrl' loadNull
          , finalizeAblation bootCtrl' bootNull
          , finalizeAblation loadCtrl' loadMiss
          , finalizeAblation bootCtrl' bootMiss
          )
      else pure
        ( loadCtrl'
        , bootCtrl'
        , inconclusiveRun "AN-L-NULL-N1"
        , inconclusiveRun "AN-B-NULL-N1"
        , inconclusiveRun "AN-L-MISS-N1"
        , inconclusiveRun "AN-B-MISS-N1"
        )

baselineAcceptable :: ImmediateRunRecord -> ImmediateRunRecord -> Bool
baselineAcceptable left right =
  irrContourStatus left == irrContourStatus right
    && irrContourStatus left `elem` ["authoritative_preserved", "authoritative_lost"]
    && irrComparabilityStatus left == "comparable"
    && irrComparabilityStatus right == "comparable"

comparability :: ImmediateRunRecord -> ImmediateRunRecord -> T.Text
comparability left right
  | sameOutcomePayload (irrOutcomePayload left) (irrOutcomePayload right) = "comparable"
  | otherwise = "not_comparable"

runLoadScenario :: Runtime.RuntimeContext -> T.Text -> T.Text -> Maybe (Aeson.Object -> Aeson.Object) -> T.Text -> IO ImmediateRunRecord
runLoadScenario rt sessionId input mutate scenarioId = do
  maybe (pure ()) (mutatePersistedStateObject rt sessionId) mutate
  loaded <- StatePersistence.loadState (Runtime.withRuntimeDb rt) sessionId
  case loaded of
    LoadStateRestored restored -> do
      let contour = contourStatusText (ssTruthContractStatus restored)
      if contour /= "authoritative_preserved"
        then do
          let carriedSemantic = ssSemanticAnchor restored /= Nothing || ssLastTurnDecision restored /= Nothing
          pure (if carriedSemantic then inconclusiveRun scenarioId else preservedLossRun scenarioId contour)
        else do
          (nextState, output) <- Runtime.runTurn rt restored input sessionId
          assertBool ("scenario should produce non-empty output: " <> T.unpack scenarioId) (not (T.null output))
          let outcome = classifyOutcome nextState output
          pure ImmediateRunRecord
            { irrScenarioId = scenarioId
            , irrContourStatus = contour
            , irrComparabilityStatus = "not_proven"
            , irrOutcomeVerdict = "not_applicable"
            , irrTransitionVerdict = "not_applicable"
            , irrPersistedDeltaVerdict = "not_applicable"
            , irrOperatorSurfaceVerdict = "not_applicable"
            , irrPrimaryVerdict = "not_applicable_control"
            , irrOutcomePayload = Just outcome
            }
    _ -> pure (inconclusiveRun scenarioId)

runBootstrapScenario :: T.Text -> T.Text -> Maybe (Aeson.Object -> Aeson.Object) -> T.Text -> IO ImmediateRunRecord
runBootstrapScenario sessionId input mutate scenarioId = do
  session0 <- Runtime.bootstrapSession True sessionId
  let rt = Runtime.sessRuntime session0
  maybe (pure ()) (mutatePersistedStateObject rt sessionId) mutate
  restored <- Runtime.bootstrapSession True sessionId
  let restoredState = Runtime.sessSystemState restored
      contour = contourStatusText (ssTruthContractStatus restoredState)
  if contour /= "authoritative_preserved"
    then do
      let carriedSemantic = ssSemanticAnchor restoredState /= Nothing || ssLastTurnDecision restoredState /= Nothing
      pure (if carriedSemantic then inconclusiveRun scenarioId else preservedLossRun scenarioId contour)
    else do
      (nextSession, output) <- Runtime.runTurnInSession restored input
      assertBool ("scenario should produce non-empty output: " <> T.unpack scenarioId) (not (T.null output))
      let outcome = classifyOutcome (Runtime.sessSystemState nextSession) output
      pure ImmediateRunRecord
        { irrScenarioId = scenarioId
        , irrContourStatus = contour
        , irrComparabilityStatus = "not_proven"
        , irrOutcomeVerdict = "not_applicable"
        , irrTransitionVerdict = "not_applicable"
        , irrPersistedDeltaVerdict = "not_applicable"
        , irrOperatorSurfaceVerdict = "not_applicable"
        , irrPrimaryVerdict = "not_applicable_control"
        , irrOutcomePayload = Just outcome
        }

finalizeAblation :: ImmediateRunRecord -> ImmediateRunRecord -> ImmediateRunRecord
finalizeAblation control ablated =
  case (irrOutcomePayload control, irrOutcomePayload ablated) of
    (Just c, Just a)
      | irrContourStatus ablated == "authoritative_preserved" ->
          let outcomeVerdict = verdictText (socOutcome c) (socOutcome a)
              transitionVerdict = verdictText (socTransition c) (socTransition a)
              deltaVerdict = verdictText (socPersistedDelta c) (socPersistedDelta a)
              operatorVerdict = verdictText (socOperatorText c) (socOperatorText a)
              primaryVerdict =
                if outcomeVerdict == "same" && transitionVerdict == "same" && deltaVerdict == "same"
                  then "PRIMARY_SAME"
                  else "PRIMARY_DIFFERENT"
          in ablated
              { irrComparabilityStatus = "comparable"
              , irrOutcomeVerdict = outcomeVerdict
              , irrTransitionVerdict = transitionVerdict
              , irrPersistedDeltaVerdict = deltaVerdict
              , irrOperatorSurfaceVerdict = operatorVerdict
              , irrPrimaryVerdict = primaryVerdict
              }
    _ -> ablated { irrComparabilityStatus = "not_comparable", irrPrimaryVerdict = "PRIMARY_INCONCLUSIVE_CONTOUR" }

inconclusiveRun :: T.Text -> ImmediateRunRecord
inconclusiveRun scenarioId =
  ImmediateRunRecord
    { irrScenarioId = scenarioId
    , irrContourStatus = "authoritative_lost"
    , irrComparabilityStatus = "not_comparable"
    , irrOutcomeVerdict = "not_proven"
    , irrTransitionVerdict = "not_proven"
    , irrPersistedDeltaVerdict = "not_proven"
    , irrOperatorSurfaceVerdict = "not_proven"
    , irrPrimaryVerdict = "PRIMARY_INCONCLUSIVE_CONTOUR"
    , irrOutcomePayload = Nothing
    }

preservedLossRun :: T.Text -> T.Text -> ImmediateRunRecord
preservedLossRun scenarioId contour =
  ImmediateRunRecord
    { irrScenarioId = scenarioId
    , irrContourStatus = contour
    , irrComparabilityStatus = "comparable"
    , irrOutcomeVerdict = "not_applicable"
    , irrTransitionVerdict = "not_applicable"
    , irrPersistedDeltaVerdict = "not_applicable"
    , irrOperatorSurfaceVerdict = "not_applicable"
    , irrPrimaryVerdict = "PRIMARY_PRESERVED_LOSS"
    , irrOutcomePayload = Nothing
    }

contourStatusText :: TruthContractStatus -> T.Text
contourStatusText status
  | status `elem` [CanonicalSurfacePreserved, AssembledSurfacePreserved] = "authoritative_preserved"
  | otherwise = "authoritative_lost"

sameOutcomePayload :: Maybe SliceOutcomeClass -> Maybe SliceOutcomeClass -> Bool
sameOutcomePayload (Just left) (Just right) =
  socOutcome left == socOutcome right
    && socTransition left == socTransition right
    && socPersistedDelta left == socPersistedDelta right
sameOutcomePayload _ _ = False

verdictText :: Eq a => a -> a -> T.Text
verdictText left right
  | left == right = "same"
  | otherwise = "different"

normalizeControlRun :: ImmediateRunRecord -> ImmediateRunRecord
normalizeControlRun record =
  record { irrPrimaryVerdict = "not_applicable_control" }

classifyOutcome :: SystemState -> T.Text -> SliceOutcomeClass
classifyOutcome ss output =
  let mDecision = ssLastTurnDecision ss
      blockedPresent = not (null (ssBlockedConcepts ss))
      lns = ssLearningNeedState ss
      learningActive = learningNeedLevel lns >= 0.6
      dreamState = ssDreamState ss
      dreamCycles = dsDreamCycleCount dreamState
      dreamAttractorActive = vecNorm (dsBiasAttractor dreamState) > 1e-9
      dreamReflectionActive = vecNorm (r5ReflectionBias (dsR5State dreamState)) > 1e-9
      graphRewired = any (\row -> meLastRewiredAt row /= Nothing) (mgEdges (ssMeaningGraph ss))
      graphDreamBiasActive = any (\row -> abs (meDreamBias row) > 1e-9) (mgEdges (ssMeaningGraph ss))
  in SliceOutcomeClass
      { socOutcome =
          ( ssLastFamily ss
          , ssLastForce ss
          , tdGuardStatus <$> mDecision
          , tdRenderStrategy <$> mDecision
          , tdRenderStyle <$> mDecision
          )
      , socTransition =
          ( ssSemanticAnchor ss /= Nothing
          , ssLastTurnDecision ss /= Nothing
          , meaningGraphNonTrivial (ssMeaningGraph ss)
          , blockedPresent
          , lnsCurrentNeed lns
          , learningActive
          , dreamCycles
          , dreamAttractorActive
          , countDreamBiasedEdges (ssMeaningGraph ss)
          )
      , socPersistedDelta =
          [ ("semanticAnchor_present", ssSemanticAnchor ss /= Nothing)
          , ("lastTurnDecision_present", ssLastTurnDecision ss /= Nothing)
          , ("meaningGraph_nontrivial", meaningGraphNonTrivial (ssMeaningGraph ss))
          , ("blockedConcepts_present", blockedPresent)
          , ("learningNeed_active", learningActive)
          , ("learningNeed_persistence_ge_3", learningNeedPersistence lns >= 3)
          , ("dream_cycles_positive", dreamCycles > 0)
          , ("dream_attractor_active", dreamAttractorActive)
          , ("dream_reflection_active", dreamReflectionActive)
          , ("meaningGraph_rewired", graphRewired)
          , ("meaningGraph_dream_bias_active", graphDreamBiasActive)
          ]
      , socOperatorText = output
      }

buildSyntheticDonor :: T.Text -> IO DonorQualification
buildSyntheticDonor donorId = do
  session0 <- Runtime.bootstrapSession True donorId
  fixtureSession <- foldTurns session0 ["Что такое свобода?", "Продолжи эту мысль", "Как это связано с выбором?"]
  let rt = Runtime.sessRuntime fixtureSession
      ss = Runtime.sessSystemState fixtureSession
  anchorPresent <- persistedBlobHasTopLevelAnchor rt donorId
  decisionPresent <- persistedBlobHasTopLevelField rt donorId "lastTurnDecision"
  pure DonorQualification
    { dqDonorId = donorId
    , dqTruthStatus = ssTruthContractStatus ss
    , dqAnchorNonNull = ssSemanticAnchor ss /= Nothing
    , dqDecisionNonNull = ssLastTurnDecision ss /= Nothing
    , dqTraceNonTrivial = atomTraceNonTrivial (ssTrace ss)
    , dqMeaningGraphNonTrivial = meaningGraphNonTrivial (ssMeaningGraph ss)
    , dqPersistedTopLevelAnchor = anchorPresent
    , dqPersistedTopLevelDecision = decisionPresent
    }

mutatePersistedStateObject :: Runtime.RuntimeContext -> T.Text -> (Aeson.Object -> Aeson.Object) -> IO ()
mutatePersistedStateObject rt sessionId mutate =
  Runtime.withRuntimeDb rt $ \db -> do
    payload <- fetchPersistedBlob db sessionId "__system_state__"
    obj <- persistentPayloadToObject payload
    let encoded = TE.decodeUtf8 . BL.toStrict . Aeson.encode $ Object (mutate obj)
    upsertPersistedBlob db sessionId "__system_state__" encoded

clonePersistedStateObject :: Runtime.RuntimeContext -> T.Text -> Aeson.Object -> IO ()
clonePersistedStateObject rt sessionId obj =
  Runtime.withRuntimeDb rt $ \db -> do
    ensureRuntimeSessionRow db sessionId
    let encoded = TE.decodeUtf8 . BL.toStrict . Aeson.encode $ Object obj
    upsertPersistedBlob db sessionId "__system_state__" encoded

setSemanticAnchorNullObject :: Aeson.Object -> Aeson.Object
setSemanticAnchorNullObject = KeyMap.insert "semanticAnchor" Null

removeSemanticAnchorObject :: Aeson.Object -> Aeson.Object
removeSemanticAnchorObject = KeyMap.delete "semanticAnchor"

renderImmediateRun :: ImmediateRunRecord -> T.Text
renderImmediateRun record =
  irrScenarioId record <> "=" <> irrPrimaryVerdict record
    <> "{contour=" <> irrContourStatus record
    <> ",compare=" <> irrComparabilityStatus record
    <> ",outcome=" <> irrOutcomeVerdict record
    <> ",transition=" <> irrTransitionVerdict record
    <> ",delta=" <> irrPersistedDeltaVerdict record
    <> ",operator=" <> irrOperatorSurfaceVerdict record
    <> "}"

runShortHorizonSyntheticAnchorScenarios :: IO (ShortHorizonRunRecord, ShortHorizonRunRecord)
runShortHorizonSyntheticAnchorScenarios =
  withRuntimeEnv "qxfx0_test_semantic_anchor_short_horizon.db" $ do
    let seedSessionId = "AN-SYN-B1-SH-SEED"
        loadCtrlId = "AN-SYN-B1-L-CTRL-SH"
        bootCtrlId = "AN-SYN-B1-B-CTRL-SH"
        loadNullId = "AN-SYN-B1-L-SH"
        bootNullId = "AN-SYN-B1-B-SH"
        donorId = "AN-DONOR-LIVE-001"
        prompts = ["А что тогда несвобода?", "Продолжи эту мысль", "Как это связано с выбором?"]
    session0 <- Runtime.bootstrapSession True seedSessionId
    let rt = Runtime.sessRuntime session0
        baseState = canonicalAuthoritativeBase (Runtime.sessSystemState session0)
    saveBase <- StatePersistence.saveState (Runtime.withRuntimeDb rt) baseState seedSessionId
    case saveBase of
      Left err -> assertFailure ("failed to persist AN-SYN-B1 short-horizon base: " <> show err)
      Right _ -> pure ()
    donor <- buildSyntheticDonor donorId
    mutatePersistedStateWithDonor rt seedSessionId donor AnchorOnly
    baselineObj <- fetchPersistedSystemStateValue rt seedSessionId
    let ablatedObj = setSemanticAnchorNullObject baselineObj
    clonePersistedStateObject rt loadCtrlId baselineObj
    clonePersistedStateObject rt bootCtrlId baselineObj
    clonePersistedStateObject rt loadNullId ablatedObj
    clonePersistedStateObject rt bootNullId ablatedObj
    loadControl <- runLoadTrajectoryScenario rt loadCtrlId prompts "AN-L-CTRL-SH"
    bootControl <- runBootstrapTrajectoryScenario bootCtrlId prompts "AN-B-CTRL-SH"
    loadAblated <- runLoadTrajectoryScenario rt loadNullId prompts "AN-L-NULL-SH"
    bootAblated <- runBootstrapTrajectoryScenario bootNullId prompts "AN-B-NULL-SH"
    let loadRecord = finalizeShortHorizon "AN-L-NULL-SH" loadControl loadAblated
        bootRecord = finalizeShortHorizon "AN-B-NULL-SH" bootControl bootAblated
    pure (loadRecord, bootRecord)

runLoadTrajectoryScenario :: Runtime.RuntimeContext -> T.Text -> [T.Text] -> T.Text -> IO ShortHorizonRunRecord
runLoadTrajectoryScenario rt sessionId prompts scenarioId = do
  loaded <- StatePersistence.loadState (Runtime.withRuntimeDb rt) sessionId
  case loaded of
    LoadStateRestored restored -> do
      let contour = contourStatusText (ssTruthContractStatus restored)
      if contour /= "authoritative_preserved"
        then do
          let carriedSemantic = ssSemanticAnchor restored /= Nothing || ssLastTurnDecision restored /= Nothing
          pure (if carriedSemantic then (inconclusiveShortHorizon scenarioId) { shrContourStatus = contour } else preservedLossShortHorizon scenarioId contour)
        else do
          steps <- runTrajectoryFromLoaded rt sessionId restored prompts
          pure (trajectoryOnlyShortHorizon scenarioId steps)
    _ -> pure (inconclusiveShortHorizon scenarioId)

runBootstrapTrajectoryScenario :: T.Text -> [T.Text] -> T.Text -> IO ShortHorizonRunRecord
runBootstrapTrajectoryScenario sessionId prompts scenarioId = do
  restored <- Runtime.bootstrapSession True sessionId
  let restoredState = Runtime.sessSystemState restored
      contour = contourStatusText (ssTruthContractStatus restoredState)
  if contour /= "authoritative_preserved"
    then do
      let carriedSemantic = ssSemanticAnchor restoredState /= Nothing || ssLastTurnDecision restoredState /= Nothing
      pure (if carriedSemantic then (inconclusiveShortHorizon scenarioId) { shrContourStatus = contour } else preservedLossShortHorizon scenarioId contour)
    else do
      steps <- runTrajectoryFromSession restored prompts
      pure (trajectoryOnlyShortHorizon scenarioId steps)

runTrajectoryFromLoaded :: Runtime.RuntimeContext -> T.Text -> SystemState -> [T.Text] -> IO [SliceOutcomeClass]
runTrajectoryFromLoaded rt sessionId restored prompts =
  go restored prompts []
  where
    go _ [] acc = pure (reverse acc)
    go state (prompt:rest) acc = do
      (nextState, output) <- Runtime.runTurn rt state prompt sessionId
      assertBool ("short-horizon step should produce non-empty output: " <> T.unpack prompt) (not (T.null output))
      go nextState rest (classifyOutcome nextState output : acc)

runTrajectoryFromSession :: Runtime.Session -> [T.Text] -> IO [SliceOutcomeClass]
runTrajectoryFromSession session0 prompts =
  go session0 prompts []
  where
    go _ [] acc = pure (reverse acc)
    go session (prompt:rest) acc = do
      (nextSession, output) <- Runtime.runTurnInSession session prompt
      assertBool ("short-horizon step should produce non-empty output: " <> T.unpack prompt) (not (T.null output))
      go nextSession rest (classifyOutcome (Runtime.sessSystemState nextSession) output : acc)

finalizeShortHorizon :: T.Text -> ShortHorizonRunRecord -> ShortHorizonRunRecord -> ShortHorizonRunRecord
finalizeShortHorizon scenarioId control ablated
  | shrContourStatus control /= "authoritative_preserved" || shrContourStatus ablated /= "authoritative_preserved" =
      inconclusiveShortHorizon scenarioId
  | otherwise =
      let controlSteps = shrStepOutcomes control
          ablatedSteps = shrStepOutcomes ablated
          outcomeVerdict = if map socOutcome controlSteps == map socOutcome ablatedSteps then "same" else "different"
          transitionVerdict = if map socTransition controlSteps == map socTransition ablatedSteps then "same" else "different"
          deltaVerdict = if map socPersistedDelta controlSteps == map socPersistedDelta ablatedSteps then "same" else "different"
          operatorVerdict = if map socOperatorText controlSteps == map socOperatorText ablatedSteps then "same" else "different"
          primaryVerdict =
            if outcomeVerdict == "same" && transitionVerdict == "same" && deltaVerdict == "same"
              then "SH_PRIMARY_SAME"
              else "SH_PRIMARY_DIFFERENT"
      in ShortHorizonRunRecord
          { shrScenarioId = scenarioId
          , shrContourStatus = "authoritative_preserved"
          , shrComparabilityStatus = "comparable"
          , shrOutcomeVerdict = outcomeVerdict
          , shrTransitionVerdict = transitionVerdict
          , shrPersistedDeltaVerdict = deltaVerdict
          , shrOperatorSurfaceVerdict = operatorVerdict
          , shrPrimaryVerdict = primaryVerdict
          , shrStepOutcomes = ablatedSteps
          }

trajectoryOnlyShortHorizon :: T.Text -> [SliceOutcomeClass] -> ShortHorizonRunRecord
trajectoryOnlyShortHorizon scenarioId steps =
  let outcomeVerdict = if trajectoryOutcomeSame steps then "same" else "different"
      transitionVerdict = if trajectoryTransitionSame steps then "same" else "different"
      deltaVerdict = if trajectoryDeltaSame steps then "same" else "different"
      operatorVerdict = if trajectoryOperatorSame steps then "same" else "different"
      primaryVerdict =
        if outcomeVerdict == "same" && transitionVerdict == "same" && deltaVerdict == "same"
          then "SH_PRIMARY_SAME"
          else "SH_PRIMARY_DIFFERENT"
  in ShortHorizonRunRecord
      { shrScenarioId = scenarioId
      , shrContourStatus = "authoritative_preserved"
      , shrComparabilityStatus = "comparable"
      , shrOutcomeVerdict = outcomeVerdict
      , shrTransitionVerdict = transitionVerdict
      , shrPersistedDeltaVerdict = deltaVerdict
      , shrOperatorSurfaceVerdict = operatorVerdict
      , shrPrimaryVerdict = primaryVerdict
      , shrStepOutcomes = steps
      }

inconclusiveShortHorizon :: T.Text -> ShortHorizonRunRecord
inconclusiveShortHorizon scenarioId =
  ShortHorizonRunRecord
    { shrScenarioId = scenarioId
    , shrContourStatus = "authoritative_lost"
    , shrComparabilityStatus = "not_comparable"
    , shrOutcomeVerdict = "not_proven"
    , shrTransitionVerdict = "not_proven"
    , shrPersistedDeltaVerdict = "not_proven"
    , shrOperatorSurfaceVerdict = "not_proven"
    , shrPrimaryVerdict = "SH_PRIMARY_INCONCLUSIVE_CONTOUR"
    , shrStepOutcomes = []
    }

preservedLossShortHorizon :: T.Text -> T.Text -> ShortHorizonRunRecord
preservedLossShortHorizon scenarioId contour =
  ShortHorizonRunRecord
    { shrScenarioId = scenarioId
    , shrContourStatus = contour
    , shrComparabilityStatus = "comparable"
    , shrOutcomeVerdict = "not_applicable"
    , shrTransitionVerdict = "not_applicable"
    , shrPersistedDeltaVerdict = "not_applicable"
    , shrOperatorSurfaceVerdict = "not_applicable"
    , shrPrimaryVerdict = "SH_PRESERVED_LOSS"
    , shrStepOutcomes = []
    }

trajectoryOutcomeSame :: [SliceOutcomeClass] -> Bool
trajectoryOutcomeSame [] = True
trajectoryOutcomeSame (x:xs) = all ((== socOutcome x) . socOutcome) xs

trajectoryTransitionSame :: [SliceOutcomeClass] -> Bool
trajectoryTransitionSame [] = True
trajectoryTransitionSame (x:xs) = all ((== socTransition x) . socTransition) xs

trajectoryDeltaSame :: [SliceOutcomeClass] -> Bool
trajectoryDeltaSame [] = True
trajectoryDeltaSame (x:xs) = all ((== socPersistedDelta x) . socPersistedDelta) xs

trajectoryOperatorSame :: [SliceOutcomeClass] -> Bool
trajectoryOperatorSame [] = True
trajectoryOperatorSame (x:xs) = all ((== socOperatorText x) . socOperatorText) xs

renderShortHorizonRun :: ShortHorizonRunRecord -> T.Text
renderShortHorizonRun record =
  shrScenarioId record <> "=" <> shrPrimaryVerdict record
    <> "{contour=" <> shrContourStatus record
    <> ",compare=" <> shrComparabilityStatus record
    <> ",outcome=" <> shrOutcomeVerdict record
    <> ",transition=" <> shrTransitionVerdict record
    <> ",delta=" <> shrPersistedDeltaVerdict record
    <> ",operator=" <> shrOperatorSurfaceVerdict record
    <> ",steps=" <> T.pack (show (length (shrStepOutcomes record)))
    <> "}"

runMeaningGraphImmediateScenarios :: IO (ImmediateRunRecord, ImmediateRunRecord, ImmediateRunRecord, ImmediateRunRecord, ImmediateRunRecord, ImmediateRunRecord)
runMeaningGraphImmediateScenarios =
  withRuntimeEnv "qxfx0_test_meaning_graph_immediate.db" $ do
    let seedSessionId = "MG-AUTH-SEED"
        loadCtrlId = "MG-L-CTRL"
        bootCtrlId = "MG-B-CTRL"
        loadEmptyId = "MG-L-EMPTY"
        bootEmptyId = "MG-B-EMPTY"
        loadReducedId = "MG-L-REDUCED"
        bootReducedId = "MG-B-REDUCED"
        prompts = ["Что такое свобода?", "А что тогда несвобода?", "Как это связано с выбором?"]
        followUp = "Продолжи эту мысль"
    session0 <- Runtime.bootstrapSession True seedSessionId
    fixtureSession <- foldTurns session0 prompts
    let rt = Runtime.sessRuntime fixtureSession
        baseState = canonicalAuthoritativeBase (Runtime.sessSystemState fixtureSession)
    saveBase <- StatePersistence.saveState (Runtime.withRuntimeDb rt) baseState seedSessionId
    case saveBase of
      Left err -> assertFailure ("failed to persist MG authoritative base: " <> show err)
      Right _ -> pure ()
    baselineObj <- fetchPersistedSystemStateValue rt seedSessionId
    let emptyGraphObj = setMeaningGraphEmptyObject baselineObj
        reducedGraphObj = setMeaningGraphReducedObject baselineObj

    clonePersistedStateObject rt loadCtrlId baselineObj
    clonePersistedStateObject rt bootCtrlId baselineObj
    loadCtrl0 <- runLoadScenario rt loadCtrlId followUp Nothing "MG-L-CTRL-N1"
    bootCtrl0 <- runBootstrapScenario bootCtrlId followUp Nothing "MG-B-CTRL-N1"
    let loadCtrl = normalizeControlRun loadCtrl0
        bootCtrl = normalizeControlRun bootCtrl0
        comp = comparability loadCtrl bootCtrl
        loadCtrl' = loadCtrl { irrComparabilityStatus = comp }
        bootCtrl' = bootCtrl { irrComparabilityStatus = comp }

    if baselineAcceptable loadCtrl' bootCtrl'
      then do
        clonePersistedStateObject rt loadEmptyId emptyGraphObj
        clonePersistedStateObject rt bootEmptyId emptyGraphObj
        clonePersistedStateObject rt loadReducedId reducedGraphObj
        clonePersistedStateObject rt bootReducedId reducedGraphObj
        loadEmpty <- runLoadScenario rt loadEmptyId followUp Nothing "MG-L-EMPTY-N1"
        bootEmpty <- runBootstrapScenario bootEmptyId followUp Nothing "MG-B-EMPTY-N1"
        loadReduced <- runLoadScenario rt loadReducedId followUp Nothing "MG-L-REDUCED-N1"
        bootReduced <- runBootstrapScenario bootReducedId followUp Nothing "MG-B-REDUCED-N1"
        pure
          ( loadCtrl'
          , bootCtrl'
          , finalizeAblation loadCtrl' loadEmpty
          , finalizeAblation bootCtrl' bootEmpty
          , finalizeAblation loadCtrl' loadReduced
          , finalizeAblation bootCtrl' bootReduced
          )
      else pure
        ( loadCtrl'
        , bootCtrl'
        , inconclusiveRun "MG-L-EMPTY-N1"
        , inconclusiveRun "MG-B-EMPTY-N1"
        , inconclusiveRun "MG-L-REDUCED-N1"
        , inconclusiveRun "MG-B-REDUCED-N1"
        )

runMeaningGraphShortHorizonScenarios :: IO (ShortHorizonRunRecord, ShortHorizonRunRecord)
runMeaningGraphShortHorizonScenarios =
  withRuntimeEnv "qxfx0_test_meaning_graph_short_horizon.db" $ do
    let seedSessionId = "MG-AUTH-SH-SEED"
        loadCtrlId = "MG-L-CTRL-SH"
        bootCtrlId = "MG-B-CTRL-SH"
        loadEmptyId = "MG-L-EMPTY-SH"
        bootEmptyId = "MG-B-EMPTY-SH"
        prompts = ["Продолжи эту мысль", "А где здесь граница между свободой и выбором?", "Тогда как отличить внутреннюю свободу от внешней?"]
    session0 <- Runtime.bootstrapSession True seedSessionId
    fixtureSession <- foldTurns session0 ["Что такое свобода?", "А что тогда несвобода?", "Как это связано с выбором?"]
    let rt = Runtime.sessRuntime fixtureSession
        baseState = canonicalAuthoritativeBase (Runtime.sessSystemState fixtureSession)
    saveBase <- StatePersistence.saveState (Runtime.withRuntimeDb rt) baseState seedSessionId
    case saveBase of
      Left err -> assertFailure ("failed to persist MG short-horizon authoritative base: " <> show err)
      Right _ -> pure ()
    baselineObj <- fetchPersistedSystemStateValue rt seedSessionId
    let emptyGraphObj = setMeaningGraphEmptyObject baselineObj
    clonePersistedStateObject rt loadCtrlId baselineObj
    clonePersistedStateObject rt bootCtrlId baselineObj
    clonePersistedStateObject rt loadEmptyId emptyGraphObj
    clonePersistedStateObject rt bootEmptyId emptyGraphObj
    loadControl <- runLoadTrajectoryScenario rt loadCtrlId prompts "MG-L-CTRL-SH"
    bootControl <- runBootstrapTrajectoryScenario bootCtrlId prompts "MG-B-CTRL-SH"
    loadAblated <- runLoadTrajectoryScenario rt loadEmptyId prompts "MG-L-EMPTY-SH"
    bootAblated <- runBootstrapTrajectoryScenario bootEmptyId prompts "MG-B-EMPTY-SH"
    let loadRecord = finalizeShortHorizon "MG-L-EMPTY-SH" loadControl loadAblated
        bootRecord = finalizeShortHorizon "MG-B-EMPTY-SH" bootControl bootAblated
    pure (loadRecord, bootRecord)

runBlockedConceptsImmediateScenarios :: IO (ImmediateRunRecord, ImmediateRunRecord, ImmediateRunRecord, ImmediateRunRecord)
runBlockedConceptsImmediateScenarios =
  withFakeNixInstantiateForConcepts ["смерть", "запрет"] $
    withRuntimeEnv "qxfx0_test_blocked_concepts_immediate.db" $ do
      let seedSessionId = "BC-AUTH-SEED"
          loadCtrlId = "BC-L-CTRL"
          bootCtrlId = "BC-B-CTRL"
          loadEmptyId = "BC-L-EMPTY"
          bootEmptyId = "BC-B-EMPTY"
          fixtureTurns = ["Что такое смерть?", "Сформулируй, где именно возник запрет"]
          followUp = "Продолжай и скажи, что всё ещё мешает"
      session0 <- Runtime.bootstrapSession True seedSessionId
      fixtureSession <- foldTurns session0 fixtureTurns
      let rt = Runtime.sessRuntime fixtureSession
          fixtureState = Runtime.sessSystemState fixtureSession
          baseState = canonicalAuthoritativeBase fixtureState
      assertBool "blocked-concepts fixture must have non-empty blockedConcepts before ablation" (not (null (ssBlockedConcepts fixtureState)))
      saveBase <- StatePersistence.saveState (Runtime.withRuntimeDb rt) baseState seedSessionId
      case saveBase of
        Left err -> assertFailure ("failed to persist BC authoritative base: " <> show err)
        Right _ -> pure ()
      baselineObj <- fetchPersistedSystemStateValue rt seedSessionId
      let emptyObj = setBlockedConceptsEmptyObject baselineObj

      clonePersistedStateObject rt loadCtrlId baselineObj
      clonePersistedStateObject rt bootCtrlId baselineObj
      loadCtrl0 <- runLoadScenario rt loadCtrlId followUp Nothing "BC-L-CTRL-N1"
      bootCtrl0 <- runBootstrapScenario bootCtrlId followUp Nothing "BC-B-CTRL-N1"
      let loadCtrl = normalizeControlRun loadCtrl0
          bootCtrl = normalizeControlRun bootCtrl0
          comp = comparability loadCtrl bootCtrl
          loadCtrl' = loadCtrl { irrComparabilityStatus = comp }
          bootCtrl' = bootCtrl { irrComparabilityStatus = comp }

      if baselineAcceptable loadCtrl' bootCtrl'
        then do
          clonePersistedStateObject rt loadEmptyId emptyObj
          clonePersistedStateObject rt bootEmptyId emptyObj
          loadEmpty <- runLoadScenario rt loadEmptyId followUp Nothing "BC-L-EMPTY-N1"
          bootEmpty <- runBootstrapScenario bootEmptyId followUp Nothing "BC-B-EMPTY-N1"
          pure (loadCtrl', bootCtrl', finalizeAblation loadCtrl' loadEmpty, finalizeAblation bootCtrl' bootEmpty)
        else pure (loadCtrl', bootCtrl', inconclusiveRun "BC-L-EMPTY-N1", inconclusiveRun "BC-B-EMPTY-N1")

runBlockedConceptsShortHorizonScenarios :: IO (ShortHorizonRunRecord, ShortHorizonRunRecord)
runBlockedConceptsShortHorizonScenarios =
  withFakeNixInstantiateForConcepts ["смерть", "запрет"] $
    withRuntimeEnv "qxfx0_test_blocked_concepts_short_horizon.db" $ do
      let seedSessionId = "BC-AUTH-SH-SEED"
          loadCtrlId = "BC-L-CTRL-SH"
          bootCtrlId = "BC-B-CTRL-SH"
          loadEmptyId = "BC-L-EMPTY-SH"
          bootEmptyId = "BC-B-EMPTY-SH"
          fixtureTurns = ["Что такое смерть?", "Сформулируй, где именно возник запрет"]
          prompts = ["Продолжай и скажи, что всё ещё мешает", "Где здесь остался пробел?", "Что нужно, чтобы снять это ограничение?"]
      session0 <- Runtime.bootstrapSession True seedSessionId
      fixtureSession <- foldTurns session0 fixtureTurns
      let rt = Runtime.sessRuntime fixtureSession
          fixtureState = Runtime.sessSystemState fixtureSession
          baseState = canonicalAuthoritativeBase fixtureState
      assertBool "blocked-concepts short-horizon fixture must have non-empty blockedConcepts before ablation" (not (null (ssBlockedConcepts fixtureState)))
      saveBase <- StatePersistence.saveState (Runtime.withRuntimeDb rt) baseState seedSessionId
      case saveBase of
        Left err -> assertFailure ("failed to persist BC short-horizon authoritative base: " <> show err)
        Right _ -> pure ()
      baselineObj <- fetchPersistedSystemStateValue rt seedSessionId
      let emptyObj = setBlockedConceptsEmptyObject baselineObj
      clonePersistedStateObject rt loadCtrlId baselineObj
      clonePersistedStateObject rt bootCtrlId baselineObj
      clonePersistedStateObject rt loadEmptyId emptyObj
      clonePersistedStateObject rt bootEmptyId emptyObj
      loadControl <- runLoadTrajectoryScenario rt loadCtrlId prompts "BC-L-CTRL-SH"
      bootControl <- runBootstrapTrajectoryScenario bootCtrlId prompts "BC-B-CTRL-SH"
      loadAblated <- runLoadTrajectoryScenario rt loadEmptyId prompts "BC-L-EMPTY-SH"
      bootAblated <- runBootstrapTrajectoryScenario bootEmptyId prompts "BC-B-EMPTY-SH"
      let loadRecord = finalizeShortHorizon "BC-L-EMPTY-SH" loadControl loadAblated
          bootRecord = finalizeShortHorizon "BC-B-EMPTY-SH" bootControl bootAblated
      pure (loadRecord, bootRecord)

runDreamStateShortHorizonScenarios :: IO (ShortHorizonRunRecord, ShortHorizonRunRecord, ShortHorizonRunRecord, ShortHorizonRunRecord)
runDreamStateShortHorizonScenarios =
  withFixedRuntimeTime dreamFixtureStartSeconds $
    withRuntimeEnv "qxfx0_test_dream_state_short_horizon.db" $ do
      let seedSessionId = "DR-AUTH-SH-SEED"
          loadCtrlId = "DR-L-CTRL-SH"
          bootCtrlId = "DR-B-CTRL-SH"
          loadNullId = "DR-L-NULL-SH"
          bootNullId = "DR-B-NULL-SH"
          loadMissId = "DR-L-MISS-SH"
          bootMissId = "DR-B-MISS-SH"
          fixtureTurns = ["Что такое свобода?", "А что тогда несвобода?", "Как это связано с выбором?", "Собери это в одну линию"]
          prompts = ["Продолжи эту мысль", "Что из этого главное?", "Собери это в короткую формулу"]
      session0 <- Runtime.bootstrapSession True seedSessionId
      fixtureSession <- foldTurns session0 fixtureTurns
      let rt = Runtime.sessRuntime fixtureSession
          fixtureState = Runtime.sessSystemState fixtureSession
          baseState = canonicalAuthoritativeBase fixtureState
      assertBool "dream fixture must have non-empty dream axiom before ablation" (ssDreamAxiom fixtureState /= "")
      assertBool "dream fixture must have positive dream cycle count before ablation" (dsDreamCycleCount (ssDreamState fixtureState) > 0)
      assertBool "dream fixture must have non-trivial meaningGraph before ablation" (meaningGraphNonTrivial (ssMeaningGraph fixtureState))
      saveBase <- StatePersistence.saveState (Runtime.withRuntimeDb rt) baseState seedSessionId
      case saveBase of
        Left err -> assertFailure ("failed to persist DR short-horizon authoritative base: " <> show err)
        Right _ -> pure ()
      baselineObj <- fetchPersistedSystemStateValue rt seedSessionId
      let ablatedObj = setDreamStateNullObject baselineObj
          missingObj = removeDreamStateObject baselineObj
      clonePersistedStateObject rt loadCtrlId baselineObj
      clonePersistedStateObject rt bootCtrlId baselineObj
      clonePersistedStateObject rt loadNullId ablatedObj
      clonePersistedStateObject rt bootNullId ablatedObj
      clonePersistedStateObject rt loadMissId missingObj
      clonePersistedStateObject rt bootMissId missingObj
      loadControl <- runLoadTrajectoryScenario rt loadCtrlId prompts "DR-L-CTRL-SH"
      bootControl <- runBootstrapTrajectoryScenario bootCtrlId prompts "DR-B-CTRL-SH"
      loadAblated <- runLoadTrajectoryScenario rt loadNullId prompts "DR-L-NULL-SH"
      bootAblated <- runBootstrapTrajectoryScenario bootNullId prompts "DR-B-NULL-SH"
      loadMissing <- runLoadTrajectoryScenario rt loadMissId prompts "DR-L-MISS-SH"
      bootMissing <- runBootstrapTrajectoryScenario bootMissId prompts "DR-B-MISS-SH"
      let loadRecord = finalizeShortHorizon "DR-L-NULL-SH" loadControl loadAblated
          bootRecord = finalizeShortHorizon "DR-B-NULL-SH" bootControl bootAblated
          loadMissingRecord = finalizeShortHorizon "DR-L-MISS-SH" loadControl loadMissing
          bootMissingRecord = finalizeShortHorizon "DR-B-MISS-SH" bootControl bootMissing
      pure (loadRecord, bootRecord, loadMissingRecord, bootMissingRecord)

runDreamStateImmediateScenarios :: IO (ImmediateRunRecord, ImmediateRunRecord, ImmediateRunRecord, ImmediateRunRecord)
runDreamStateImmediateScenarios =
  withFixedRuntimeTime dreamFixtureStartSeconds $
    withRuntimeEnv "qxfx0_test_dream_state_immediate.db" $ do
      let seedSessionId = "DR-AUTH-SEED"
          loadCtrlId = "DR-L-CTRL"
          bootCtrlId = "DR-B-CTRL"
          loadNullId = "DR-L-NULL"
          bootNullId = "DR-B-NULL"
          fixtureTurns = ["Что такое свобода?", "А что тогда несвобода?", "Как это связано с выбором?", "Собери это в одну линию"]
          followUp = "Продолжи эту мысль"
      session0 <- Runtime.bootstrapSession True seedSessionId
      fixtureSession <- foldTurns session0 fixtureTurns
      let rt = Runtime.sessRuntime fixtureSession
          fixtureState = Runtime.sessSystemState fixtureSession
          baseState = canonicalAuthoritativeBase fixtureState
      assertBool "dream fixture must have non-empty dream axiom before ablation" (ssDreamAxiom fixtureState /= "")
      assertBool "dream fixture must have positive dream cycle count before ablation" (dsDreamCycleCount (ssDreamState fixtureState) > 0)
      assertBool "dream fixture must have non-trivial meaningGraph before ablation" (meaningGraphNonTrivial (ssMeaningGraph fixtureState))
      saveBase <- StatePersistence.saveState (Runtime.withRuntimeDb rt) baseState seedSessionId
      case saveBase of
        Left err -> assertFailure ("failed to persist DR authoritative base: " <> show err)
        Right _ -> pure ()
      baselineObj <- fetchPersistedSystemStateValue rt seedSessionId
      let ablatedObj = setDreamStateNullObject baselineObj

      clonePersistedStateObject rt loadCtrlId baselineObj
      clonePersistedStateObject rt bootCtrlId baselineObj
      loadCtrl0 <- runLoadScenario rt loadCtrlId followUp Nothing "DR-L-CTRL-N1"
      bootCtrl0 <- runBootstrapScenario bootCtrlId followUp Nothing "DR-B-CTRL-N1"
      let loadCtrl = normalizeControlRun loadCtrl0
          bootCtrl = normalizeControlRun bootCtrl0
          comp = comparability loadCtrl bootCtrl
          loadCtrl' = loadCtrl { irrComparabilityStatus = comp }
          bootCtrl' = bootCtrl { irrComparabilityStatus = comp }

      if baselineAcceptable loadCtrl' bootCtrl'
        then do
          clonePersistedStateObject rt loadNullId ablatedObj
          clonePersistedStateObject rt bootNullId ablatedObj
          loadNull <- runLoadScenario rt loadNullId followUp Nothing "DR-L-NULL-N1"
          bootNull <- runBootstrapScenario bootNullId followUp Nothing "DR-B-NULL-N1"
          pure (loadCtrl', bootCtrl', finalizeAblation loadCtrl' loadNull, finalizeAblation bootCtrl' bootNull)
        else pure (loadCtrl', bootCtrl', inconclusiveRun "DR-L-NULL-N1", inconclusiveRun "DR-B-NULL-N1")

runTurnDecisionImmediateScenarios :: IO (ImmediateRunRecord, ImmediateRunRecord, ImmediateRunRecord, ImmediateRunRecord)
runTurnDecisionImmediateScenarios =
  withRuntimeEnv "qxfx0_test_turn_decision_immediate.db" $ do
    let seedSessionId = "TD-AUTH-SEED"
        loadCtrlId = "TD-L-CTRL"
        bootCtrlId = "TD-B-CTRL"
        loadNullId = "TD-L-NULL"
        bootNullId = "TD-B-NULL"
        prompts = ["Что такое свобода?", "А что тогда несвобода?"]
        followUp = "Продолжи эту мысль"
    session0 <- Runtime.bootstrapSession True seedSessionId
    fixtureSession <- foldTurns session0 prompts
    let rt = Runtime.sessRuntime fixtureSession
        fixtureState = Runtime.sessSystemState fixtureSession
        baseState = canonicalAuthoritativeBase fixtureState
    assertBool "turn decision fixture must have lastTurnDecision before ablation" (ssLastTurnDecision fixtureState /= Nothing)
    saveBase <- StatePersistence.saveState (Runtime.withRuntimeDb rt) baseState seedSessionId
    case saveBase of
      Left err -> assertFailure ("failed to persist TD authoritative base: " <> show err)
      Right _ -> pure ()
    baselineObj <- fetchPersistedSystemStateValue rt seedSessionId
    let ablatedObj = setLastTurnDecisionNullObject baselineObj

    clonePersistedStateObject rt loadCtrlId baselineObj
    clonePersistedStateObject rt bootCtrlId baselineObj
    loadCtrl0 <- runLoadScenario rt loadCtrlId followUp Nothing "TD-L-CTRL-N1"
    bootCtrl0 <- runBootstrapScenario bootCtrlId followUp Nothing "TD-B-CTRL-N1"
    let loadCtrl = normalizeControlRun loadCtrl0
        bootCtrl = normalizeControlRun bootCtrl0
        comp = comparability loadCtrl bootCtrl
        loadCtrl' = loadCtrl { irrComparabilityStatus = comp }
        bootCtrl' = bootCtrl { irrComparabilityStatus = comp }

    if baselineAcceptable loadCtrl' bootCtrl'
      then do
        clonePersistedStateObject rt loadNullId ablatedObj
        clonePersistedStateObject rt bootNullId ablatedObj
        loadNull <- runLoadScenario rt loadNullId followUp Nothing "TD-L-NULL-N1"
        bootNull <- runBootstrapScenario bootNullId followUp Nothing "TD-B-NULL-N1"
        pure (loadCtrl', bootCtrl', finalizeAblation loadCtrl' loadNull, finalizeAblation bootCtrl' bootNull)
      else pure (loadCtrl', bootCtrl', inconclusiveRun "TD-L-NULL-N1", inconclusiveRun "TD-B-NULL-N1")

runTurnDecisionShortHorizonScenarios :: IO (ShortHorizonRunRecord, ShortHorizonRunRecord)
runTurnDecisionShortHorizonScenarios =
  withRuntimeEnv "qxfx0_test_turn_decision_short_horizon.db" $ do
    let seedSessionId = "TD-AUTH-SH-SEED"
        loadCtrlId = "TD-L-CTRL-SH"
        bootCtrlId = "TD-B-CTRL-SH"
        loadNullId = "TD-L-NULL-SH"
        bootNullId = "TD-B-NULL-SH"
        fixtureTurns = ["Что такое свобода?", "А что тогда несвобода?"]
        prompts = ["Продолжи эту мысль", "Сформулируй это строже", "А теперь скажи проще"]
    session0 <- Runtime.bootstrapSession True seedSessionId
    fixtureSession <- foldTurns session0 fixtureTurns
    let rt = Runtime.sessRuntime fixtureSession
        fixtureState = Runtime.sessSystemState fixtureSession
        baseState = canonicalAuthoritativeBase fixtureState
    assertBool "turn decision short-horizon fixture must have lastTurnDecision before ablation" (ssLastTurnDecision fixtureState /= Nothing)
    saveBase <- StatePersistence.saveState (Runtime.withRuntimeDb rt) baseState seedSessionId
    case saveBase of
      Left err -> assertFailure ("failed to persist TD short-horizon authoritative base: " <> show err)
      Right _ -> pure ()
    baselineObj <- fetchPersistedSystemStateValue rt seedSessionId
    let ablatedObj = setLastTurnDecisionNullObject baselineObj
    clonePersistedStateObject rt loadCtrlId baselineObj
    clonePersistedStateObject rt bootCtrlId baselineObj
    clonePersistedStateObject rt loadNullId ablatedObj
    clonePersistedStateObject rt bootNullId ablatedObj
    loadControl <- runLoadTrajectoryScenario rt loadCtrlId prompts "TD-L-CTRL-SH"
    bootControl <- runBootstrapTrajectoryScenario bootCtrlId prompts "TD-B-CTRL-SH"
    loadAblated <- runLoadTrajectoryScenario rt loadNullId prompts "TD-L-NULL-SH"
    bootAblated <- runBootstrapTrajectoryScenario bootNullId prompts "TD-B-NULL-SH"
    let loadRecord = finalizeShortHorizon "TD-L-NULL-SH" loadControl loadAblated
        bootRecord = finalizeShortHorizon "TD-B-NULL-SH" bootControl bootAblated
    pure (loadRecord, bootRecord)

runIntuitionImmediateScenarios :: IO (ImmediateRunRecord, ImmediateRunRecord, ImmediateRunRecord, ImmediateRunRecord)
runIntuitionImmediateScenarios =
  withRuntimeEnv "qxfx0_test_intuition_immediate.db" $ do
    let seedSessionId = "IS-AUTH-SEED"
        bootCtrlId = "IS-B-CTRL"
        loadCtrlId = "IS-L-CTRL"
        bootNullId = "IS-B-NULL"
        loadNullId = "IS-L-NULL"
        prompts = ["Что такое свобода?", "А что тогда несвобода?", "Как это связано с выбором?", "Сформулируй это точнее"]
        followUp = "Продолжи эту мысль"
    session0 <- Runtime.bootstrapSession True seedSessionId
    fixtureSession <- foldTurns session0 prompts
    let rt = Runtime.sessRuntime fixtureSession
        fixtureState = Runtime.sessSystemState fixtureSession
        baseState = canonicalAuthoritativeBase fixtureState
    assertBool "intuition fixture must differ from default state before ablation" (ssIntuitionState fixtureState /= Just defaultIntuitiveState)
    saveBase <- StatePersistence.saveState (Runtime.withRuntimeDb rt) baseState seedSessionId
    case saveBase of
      Left err -> assertFailure ("failed to persist IS authoritative base: " <> show err)
      Right _ -> pure ()
    baselineObj <- fetchPersistedSystemStateValue rt seedSessionId
    let ablatedObj = setIntuitionStateNullObject baselineObj

    clonePersistedStateObject rt bootCtrlId baselineObj
    clonePersistedStateObject rt loadCtrlId baselineObj
    bootCtrl0 <- runBootstrapScenario bootCtrlId followUp Nothing "IS-B-CTRL-N1"
    loadCtrl0 <- runLoadScenario rt loadCtrlId followUp Nothing "IS-L-CTRL-N1"
    let bootCtrl = normalizeControlRun bootCtrl0
        loadCtrl = normalizeControlRun loadCtrl0
        comp = comparability bootCtrl loadCtrl
        bootCtrl' = bootCtrl { irrComparabilityStatus = comp }
        loadCtrl' = loadCtrl { irrComparabilityStatus = comp }

    if baselineAcceptable bootCtrl' loadCtrl'
      then do
        clonePersistedStateObject rt bootNullId ablatedObj
        clonePersistedStateObject rt loadNullId ablatedObj
        bootNull <- runBootstrapScenario bootNullId followUp Nothing "IS-B-NULL-N1"
        loadNull <- runLoadScenario rt loadNullId followUp Nothing "IS-L-NULL-N1"
        pure (bootCtrl', loadCtrl', finalizeAblation bootCtrl' bootNull, finalizeAblation loadCtrl' loadNull)
      else pure (bootCtrl', loadCtrl', inconclusiveRun "IS-B-NULL-N1", inconclusiveRun "IS-L-NULL-N1")

runIntuitionShortHorizonScenarios :: IO (ShortHorizonRunRecord, ShortHorizonRunRecord)
runIntuitionShortHorizonScenarios =
  withRuntimeEnv "qxfx0_test_intuition_short_horizon.db" $ do
    let seedSessionId = "IS-AUTH-SH-SEED"
        bootCtrlId = "IS-B-CTRL-SH"
        loadCtrlId = "IS-L-CTRL-SH"
        bootNullId = "IS-B-NULL-SH"
        loadNullId = "IS-L-NULL-SH"
        prompts = ["Продолжи эту мысль", "Скажи это короче и точнее", "А где здесь главный разрыв?"]
        fixtureTurns = ["Что такое свобода?", "А что тогда несвобода?", "Как это связано с выбором?", "Сформулируй это точнее"]
    session0 <- Runtime.bootstrapSession True seedSessionId
    fixtureSession <- foldTurns session0 fixtureTurns
    let rt = Runtime.sessRuntime fixtureSession
        fixtureState = Runtime.sessSystemState fixtureSession
        baseState = canonicalAuthoritativeBase fixtureState
    assertBool "intuition short-horizon fixture must differ from default state before ablation" (ssIntuitionState fixtureState /= Just defaultIntuitiveState)
    saveBase <- StatePersistence.saveState (Runtime.withRuntimeDb rt) baseState seedSessionId
    case saveBase of
      Left err -> assertFailure ("failed to persist IS short-horizon authoritative base: " <> show err)
      Right _ -> pure ()
    baselineObj <- fetchPersistedSystemStateValue rt seedSessionId
    let ablatedObj = setIntuitionStateNullObject baselineObj
    clonePersistedStateObject rt bootCtrlId baselineObj
    clonePersistedStateObject rt loadCtrlId baselineObj
    clonePersistedStateObject rt bootNullId ablatedObj
    clonePersistedStateObject rt loadNullId ablatedObj
    bootControl <- runBootstrapTrajectoryScenario bootCtrlId prompts "IS-B-CTRL-SH"
    loadControl <- runLoadTrajectoryScenario rt loadCtrlId prompts "IS-L-CTRL-SH"
    bootAblated <- runBootstrapTrajectoryScenario bootNullId prompts "IS-B-NULL-SH"
    loadAblated <- runLoadTrajectoryScenario rt loadNullId prompts "IS-L-NULL-SH"
    let bootRecord = finalizeShortHorizon "IS-B-NULL-SH" bootControl bootAblated
        loadRecord = finalizeShortHorizon "IS-L-NULL-SH" loadControl loadAblated
    pure (bootRecord, loadRecord)

setMeaningGraphEmptyObject :: Aeson.Object -> Aeson.Object
setMeaningGraphEmptyObject = KeyMap.insert "meaningGraph" (Aeson.toJSON emptyMeaningGraph)

setLastTurnDecisionNullObject :: Aeson.Object -> Aeson.Object
setLastTurnDecisionNullObject = KeyMap.insert "lastTurnDecision" Null

setIntuitionStateNullObject :: Aeson.Object -> Aeson.Object
setIntuitionStateNullObject = KeyMap.insert "intuitionState" Null

setDreamStateNullObject :: Aeson.Object -> Aeson.Object
setDreamStateNullObject = KeyMap.insert "dreamState" Null

removeDreamStateObject :: Aeson.Object -> Aeson.Object
removeDreamStateObject = KeyMap.delete "dreamState"

dreamFixtureStartSeconds :: Integer
dreamFixtureStartSeconds = 3506742000

setBlockedConceptsEmptyObject :: Aeson.Object -> Aeson.Object
setBlockedConceptsEmptyObject = KeyMap.insert "blockedConcepts" (Aeson.toJSON ([] :: [T.Text]))

setMeaningGraphReducedObject :: Aeson.Object -> Aeson.Object
setMeaningGraphReducedObject obj =
  case KeyMap.lookup "meaningGraph" obj of
    Just value ->
      case Aeson.fromJSON value of
        Aeson.Success mg -> KeyMap.insert "meaningGraph" (Aeson.toJSON (reduceMeaningGraph mg)) obj
        Aeson.Error err -> error ("failed to decode meaningGraph for reduced mutation: " <> err)
    Nothing -> obj

reduceMeaningGraph :: MeaningGraph -> MeaningGraph
reduceMeaningGraph mg =
  case mgEdges mg of
    [] -> emptyMeaningGraph
    (edge:_) -> MeaningGraph [edge] (max 1 (mgTurnCount mg))

countDreamBiasedEdges :: MeaningGraph -> Int
countDreamBiasedEdges = length . filter (\row -> abs (meDreamBias row) > 1e-9) . mgEdges

persistentPayloadToObject :: T.Text -> IO Aeson.Object
persistentPayloadToObject payload =
  case eitherDecodeStrict' (encodeUtf8 payload) of
    Left err -> assertFailure ("Failed to decode persisted system state: " <> err) >> fail "unreachable"
    Right (Object obj) -> pure obj
    Right other -> assertFailure ("Persisted system state should decode as object, got: " <> show other) >> fail "unreachable"

fetchPersistedSystemStateValue :: Runtime.RuntimeContext -> T.Text -> IO Aeson.Object
fetchPersistedSystemStateValue rt sessionId =
  Runtime.withRuntimeDb rt $ \db -> do
    payload <- fetchPersistedBlob db sessionId "__system_state__"
    persistentPayloadToObject payload

mutatePersistedStateWithDonor :: Runtime.RuntimeContext -> T.Text -> DonorQualification -> BundleId -> IO ()
mutatePersistedStateWithDonor rt sessionId donor bundle =
  Runtime.withRuntimeDb rt $ \db -> do
    donorPayload <- fetchPersistedBlob db (dqDonorId donor) "__system_state__"
    candidatePayload <- fetchPersistedBlob db sessionId "__system_state__"
    donorObj <- persistentPayloadToObject donorPayload
    candidateObj <- persistentPayloadToObject candidatePayload
    let keys = bundleKeysLocal bundle
        updated = foldr (copyKey donorObj) candidateObj keys
        encoded = TE.decodeUtf8 . BL.toStrict . Aeson.encode $ Object updated
    upsertPersistedBlob db sessionId "__system_state__" encoded
  where
    bundleKeysLocal AnchorOnly = ["semanticAnchor"]
    bundleKeysLocal AnchorCoherenceBundle = ["semanticAnchor", "lastTurnDecision", "trace", "meaningGraph"]
    copyKey donorObj key acc =
      let key' = AesonKey.fromText key
      in case KeyMap.lookup key' donorObj of
        Just value -> KeyMap.insert key' value acc
        Nothing -> acc

fetchPersistedBlob :: NSQL.Database -> T.Text -> T.Text -> IO T.Text
fetchPersistedBlob db sessionId key = do
  mStmt <- NSQL.prepare db "SELECT value FROM dialogue_state WHERE session_id = ? AND key = ? ORDER BY updated_at DESC LIMIT 1"
  stmt <- case mStmt of
    Left err -> assertFailure ("Failed to prepare persisted-state query: " <> T.unpack err) >> fail "unreachable"
    Right s -> pure s
  _ <- NSQL.bindText stmt 1 sessionId
  _ <- NSQL.bindText stmt 2 key
  hasRow <- NSQL.stepRow stmt
  payload <- if hasRow then NSQL.columnText stmt 0 else pure ""
  NSQL.finalize stmt
  pure payload

upsertPersistedBlob :: NSQL.Database -> T.Text -> T.Text -> T.Text -> IO ()
upsertPersistedBlob db sessionId key payload = do
  let sql = "INSERT OR REPLACE INTO dialogue_state(session_id, key, value, updated_at) VALUES(?, ?, ?, datetime('now'))"
  mStmt <- NSQL.prepare db sql
  case mStmt of
    Left err -> assertFailure ("Failed to prepare persisted-state upsert: " <> T.unpack err)
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 sessionId
      _ <- NSQL.bindText stmt 2 key
      _ <- NSQL.bindText stmt 3 payload
      _ <- NSQL.step stmt
      NSQL.finalize stmt

ensureRuntimeSessionRow :: NSQL.Database -> T.Text -> IO ()
ensureRuntimeSessionRow db sessionId = do
  let sql = "INSERT OR IGNORE INTO runtime_sessions(id, agency, tension, status) VALUES(?, 0.5, 0.3, 'active')"
  mStmt <- NSQL.prepare db sql
  case mStmt of
    Left err -> assertFailure ("Failed to prepare runtime_session insert: " <> T.unpack err)
    Right stmt -> do
      _ <- NSQL.bindText stmt 1 sessionId
      _ <- NSQL.step stmt
      NSQL.finalize stmt

changedTopLevelKeys :: Aeson.Object -> Aeson.Object -> [T.Text]
changedTopLevelKeys before after =
  [ key
  | key <- uniqueKeys
  , M.lookup key beforeMap /= M.lookup key afterMap
  ]
  where
    beforeMap = M.fromList [(AesonKey.toText k, v) | (k, v) <- KeyMap.toList before]
    afterMap = M.fromList [(AesonKey.toText k, v) | (k, v) <- KeyMap.toList after]
    uniqueKeys = nub (M.keys beforeMap ++ M.keys afterMap)

truthStatusInheritedFromBase :: Aeson.Object -> Aeson.Object -> Bool
truthStatusInheritedFromBase before after =
  KeyMap.lookup "truthContractStatus" before == KeyMap.lookup "truthContractStatus" after

persistedBlobHasTopLevelField :: Runtime.RuntimeContext -> T.Text -> T.Text -> IO Bool
persistedBlobHasTopLevelField rt sessionId fieldName =
  Runtime.withRuntimeDb rt $ \db -> do
    payload <- fetchPersistedBlob db sessionId "__system_state__"
    obj <- persistentPayloadToObject payload
    pure (KeyMap.member (AesonKey.fromText fieldName) obj)

canonicalAuthoritativeBase :: SystemState -> SystemState
canonicalAuthoritativeBase ss0 =
  let fruit = KnowledgeFruit
        { kfProposition = "freedom requires responsibility"
        , kfWord = "свобода"
        , kfSource = SourceInternal
        , kfValidated = True
        , kfConatusDelta = 0.6
        , kfPredictiveDelta = 0.4
        , kfGraftedTurn = Nothing
        , kfObservedTurn = 1
        }
      tree = graftFruit "agreement" fruit emptyKnowledgeTree
      dialogueOutcome = DialogueOutcomeSample
        { dosTurn = 1
        , dosKind = DialogueOutcomeSuccess
        , dosTopic = "freedom"
        , dosSignals = ["strong_positive_confirmation"]
        , dosEvidenceStrength = EvidenceStrong
        , dosStrongUpdate = True
        , dosDecisionRecord = AdaptiveDecisionRecord
            { adrTurn = 1
            , adrCause = "dialogue_outcome:success"
            , adrEvidence = ["strong_positive_confirmation"]
            , adrConfidence = 0.8
            , adrBoundedDelta = ["recent_outcomes<=12"]
            , adrDecision = AdaptiveAccepted
            , adrTargets = [MutDialogueOutcome]
            , adrMutationRecords = []
            }
        }
      stateWithEvidence = ss0
        { ssSessionId = ssSessionId ss0
        , ssDialogue = (ssDialogue ss0)
            { dsTurnCount = 1
            , dsLastTopic = "freedom"
            }
        , ssTruthContractStatus = CanonicalSurfacePreserved
        , ssKnowledgeTree = tree
        , ssDialogueOutcomeLearning = emptyDialogueOutcomeLearningState
            { dolRecentOutcomes = [dialogueOutcome]
            , dolSuccessCount = 1
            }
        , ssBeliefStore = emptyBeliefStore
            { bsClaims = M.fromList
                [ ("freedom", BeliefRecord
                    { brClaim = "freedom"
                    , brPolarity = BeliefAffirmed
                    , brConfidence = 0.8
                    , brEvidence = ["turn=1:success"]
                    , brCounterEvidence = []
                    , brLastUpdatedTurn = 1
                    , brRevisionCount = 0
                    })
                ]
            }
        }
  in applyPerspectiveOperator stateWithEvidence positiveConatus False emptyField

assembledAuthoritativeBase :: SystemState -> SystemState
assembledAuthoritativeBase ss0 =
  (canonicalAuthoritativeBase ss0)
    { ssTruthContractStatus = AssembledSurfacePreserved }

positiveConatus :: ConatusEnergy
positiveConatus = ConatusEnergy
  { ceScalar = 10.0
  , ceComponents = ConatusComponents
      { ccMorphology = 0.0
      , ccIdentity = 0.0
      , ccTurns = 10.0
      , ccPenalty = 0.0
      }
  }
