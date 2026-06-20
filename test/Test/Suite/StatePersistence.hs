{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.StatePersistence
  ( statePersistenceFastTests
  , statePersistenceSlowTests
  , statePersistenceTests
  ) where

import qualified Data.Sequence as Seq
import QxFx0.Core.CommitmentStoreAdmission (CommitmentStoreAdmissionDecision(..))
import QxFx0.Types.CognitiveSignals (emptyCognitiveSignals)
import QxFx0.Types.State.SemanticCommitment (MatchKind(..))
import Control.Exception (try)
import Control.Monad (forM_)
import qualified Data.Aeson as Aeson
import Data.Aeson (Value(..), eitherDecodeStrict')
import qualified Data.Aeson.Key as Key
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.ByteString.Lazy as BL
import qualified Data.Map.Strict as M
import qualified Data.Text as T
import Data.Text.Encoding (encodeUtf8)
import qualified Data.Text.Encoding as TE
import qualified Data.Vector as V
import Test.HUnit hiding (Testable)
import Test.QuickCheck
  ( Result(..)
  , Testable
  , maxSuccess
  , quickCheckWithResult
  , stdArgs
  )

import QxFx0.Learning.KnowledgeTree
  ( KnowledgeSource(..)
  , KnowledgeFruit(..)
  , emptyKnowledgeTree
  , graftFruit
  )
import QxFx0.Types
import QxFx0.Types.Persistence
  ( LoadStateResult(..)
  , PersistenceDiagnostic(..)
  , PersistenceEnvelope(..)
  , currentPersistenceEnvelopeVersion
  , renderPersistenceDiagnostics
  )
import QxFx0.Types.ShadowDivergence
  ( ShadowDivergenceKind(..)
  , ShadowDivergenceSeverity(..)
  , ShadowSnapshotId(..)
  )
import QxFx0.Types.Thresholds (LegitimacyStatus(..), ScenePressure(..))
import qualified QxFx0.Bridge.NativeSQLite as NSQL
import qualified QxFx0.Bridge.StatePersistence as StatePersistence
import QxFx0.ExceptionPolicy (QxFx0Exception(..), RuntimeInitErrorDetails(..))
import qualified QxFx0.Runtime as Runtime
import QxFx0.Types.TurnProjection (TurnReplayTrace(..), EffectSnapshot(..))
import QxFx0.Core.PipelineIO (mkReplayPipelineIO, checkPipelineApiHealth)
import QxFx0.Self.Conatus (ConatusComponents(..), ConatusEnergy(..))
import QxFx0.Self.Essence
  ( CommitmentTrigger(..)
  , Essence(..)
  , EssenceCommitment(..)
  , EssenceMode(..)
  , TrajectoryHash(..)
  , emptyTrajectory
  )
import QxFx0.Self.Field (emptyField)
import QxFx0.Self.Perspective (applyPerspectiveOperator)
import QxFx0.Types.State.Governance (GovernanceRuntimeFault(..))
import QxFx0.Types.State.SelfState (SelfState(..))
import Test.Support (assertExec, queryCount, withEnvVar, withRuntimeEnv, withStrictRuntimeEnv)
import QxFx0.Types.Evidence (EvidenceAdmissibility(..))

statePersistenceFastTests :: [Test]
statePersistenceFastTests =
  [ testBootstrapRestoresNonAuthoritativePersistedState
  , testLoadStateRebuildsDerivedGovernanceViewsFromCanonicalHistory
  , testBootstrapSessionRestoresCanonicalGovernanceViews
  , testBootstrapSessionStrictRestoresNonAuthoritativePersistedState
  , testBootstrapSessionDegradedRestoresNonAuthoritativePersistedState
  , testLoadStateCorruptBlobIsReported
  , testLoadStateCorruptUtf8BlobIsReported
  , testLoadStateLegacyNumericTrajectoryHashRestores
  , testBootstrapSessionMarksRecoveredCorruption
  , testStateBlobDiagnosticsDetectsMissingOptionalFields
  , testLoadStateMissingRequiredTopLevelFieldsFailsDecode
  , testSaveStateReturnsRightOnSuccess
  , testPersistedStatePreservesTruthContractStatusVerbatim
  , testPersistedStateCanonicalizeIsIdempotent
  , testPersistedStateEnvelopeRoundTrip
  , testPersistedStateBareRoundTrip
  ]

-- | Match both plain and structured RuntimeInitError variants.
matchRuntimeInitError :: QxFx0Exception -> Maybe T.Text
matchRuntimeInitError ex = case ex of
  RuntimeInitError msg -> Just msg
  RuntimeInitErrorStructured d -> Just (riedErrorCode d)
  _ -> Nothing

statePersistenceSlowTests :: [Test]
statePersistenceSlowTests =
  [ testSaveStateWithProjectionFailureRollsBackTransaction
  , testPersistedSystemStateSessionIdMatchesBootstrapId
  , testPersistedReplayTraceDeterministicAcrossFreshSessionsProperty
  , testPersistedReplayTraceDeterministicWithFixedTimeProperty
  , testSaveStateWithDivergencePersistsShadowLog
  , testReplayTraceDbRoundTripFeedsReplayPipeline
  ]

-- | Item #1 (production half): the REAL on-disk DB round-trip. Run a live turn
-- through the runtime (which persists the trace blob via persistTurnQuality),
-- read the @replay_trace_json@ column straight back from SQLite, decode it with
-- the now-existing 'FromJSON TurnReplayTrace', and feed it to
-- 'mkReplayPipelineIO'. This is the half the unit-suite P5 deferred: not just
-- @decode . encode@ in memory, but blob -> on-disk SQLite -> blob -> decode ->
-- replay, end to end.
testReplayTraceDbRoundTripFeedsReplayPipeline :: Test
testReplayTraceDbRoundTripFeedsReplayPipeline = TestCase $
  withRuntimeEnv "qxfx0_test_replay_db_roundtrip.db" $ do
    let sid = "replay_db_roundtrip"
    session0 <- Runtime.bootstrapSession True sid
    (session1, _resp) <- Runtime.runTurnInSession session0 "что такое свобода"
    let rt = Runtime.sessRuntime session1
    blob <- Runtime.withRuntimeDb rt (`fetchLatestReplayTraceJson` sid)
    assertBool "a replay_trace_json row must have been persisted by the live turn"
      (not (T.null blob))
    case Aeson.eitherDecodeStrict' (encodeUtf8 blob) :: Either String TurnReplayTrace of
      Left err ->
        assertFailure ("persisted trace blob must decode as TurnReplayTrace: " <> err)
      Right trace -> do
        assertEqual "decoded trace session id must match the live session"
          sid (trcSessionId trace)
        -- The decoded trace drives replay: mkReplayPipelineIO must return the
        -- apiHealthy recorded in the persisted snapshot (or False if pre-vX /
        -- absent), proving the blob -> decode -> replay path is wired.
        let expectedHealthy = maybe False esApiHealthy (trcEffectSnapshot trace)
        replayHealthy <- checkPipelineApiHealth (mkReplayPipelineIO trace)
        assertEqual "replay pipeline must reproduce the persisted apiHealthy"
          expectedHealthy replayHealthy

statePersistenceTests :: [Test]
statePersistenceTests = statePersistenceFastTests ++ statePersistenceSlowTests

-- SLICE-013 Option 1: a non-authoritative persisted blob (valid JSON, marker
-- LegacyIncompleteSurface) is a valid compatibility/provenance state, NOT
-- corruption. loadState must RESTORE it with the marker preserved verbatim and
-- restart authority demoted (semanticAnchor / lastTurnDecision -> Nothing). It is
-- no longer LoadStateCorrupt. (Truly corrupt JSON is still corrupt — see
-- testLoadStateCorruptBlobIsReported.)
testBootstrapRestoresNonAuthoritativePersistedState :: Test
testBootstrapRestoresNonAuthoritativePersistedState = TestCase $ do
  withRuntimeEnv "qxfx0_test_bootstrap_non_authoritative.db" $ do
    session0 <- Runtime.bootstrapSession True "bootstrap_non_authoritative"
    let rt = Runtime.sessRuntime session0
        ss0 = authoritativeGovernedState (Runtime.sessSystemState session0)
    saveResult <- StatePersistence.saveState (Runtime.withRuntimeDb rt) ss0 "bootstrap_non_authoritative"
    case saveResult of
      Left err -> assertFailure ("failed to persist non-authoritative state fixture: " <> T.unpack (renderPersistenceDiagnostics [err]))
      Right _ -> pure ()
    writeNonAuthoritativePersistedTruthBlob rt "bootstrap_non_authoritative"
    result <- StatePersistence.loadState (Runtime.withRuntimeDb rt) "bootstrap_non_authoritative"
    case result of
      LoadStateRestored restored -> do
        assertEqual "non-authoritative persisted state must remain restorable with its marker preserved verbatim"
          LegacyIncompleteSurface
          (ssTruthContractStatus restored)
        assertEqual "non-authoritative restore must deny restart authority: semantic anchor stripped"
          Nothing
          (ssSemanticAnchor restored)
        assertEqual "non-authoritative restore must deny restart authority: last turn decision stripped"
          Nothing
          (ssLastTurnDecision restored)
      other -> assertFailure ("expected non-authoritative persisted state to remain restorable, got: " <> show other)

testLoadStateRebuildsDerivedGovernanceViewsFromCanonicalHistory :: Test
testLoadStateRebuildsDerivedGovernanceViewsFromCanonicalHistory = TestCase $ do
  withRuntimeEnv "qxfx0_test_governance_load_rebuild.db" $ do
    session0 <- Runtime.bootstrapSession True "governance_load_rebuild"
    let rt = Runtime.sessRuntime session0
        governedState = authoritativeGovernedState (Runtime.sessSystemState session0)
        stalePersistedState = governedState
          { ssSelfState = (ssSelfState governedState)
              { selfPerspectiveRegistry = selfPerspectiveRegistry (ssSelfState emptySystemState) }
          , ssGovernanceProjection = ssGovernanceProjection emptySystemState
          }
    assertBool "governed fixture must record canonical governance history"
      (not (null (ssGovernanceHistory governedState)))
    assertBool "governed fixture must produce a non-empty derived perspective registry"
      (selfPerspectiveRegistry (ssSelfState governedState) /= selfPerspectiveRegistry (ssSelfState emptySystemState))
    saveResult <- StatePersistence.saveState (Runtime.withRuntimeDb rt) stalePersistedState "governance_load_rebuild"
    case saveResult of
      Left err -> assertFailure ("failed to persist governed state fixture: " <> T.unpack (renderPersistenceDiagnostics [err]))
      Right _ -> pure ()
    loaded <- StatePersistence.loadState (Runtime.withRuntimeDb rt) "governance_load_rebuild"
    case loaded of
      LoadStateRestored restored -> do
        assertEqual "canonical governance history must be preserved on load"
          (ssGovernanceHistory governedState)
          (ssGovernanceHistory restored)
        assertEqual "derived perspective registry must be rebuilt from canonical history"
          (selfPerspectiveRegistry (ssSelfState governedState))
          (selfPerspectiveRegistry (ssSelfState restored))
        assertEqual "governance projection must be rebuilt from canonical history"
          (ssGovernanceProjection governedState)
          (ssGovernanceProjection restored)
      other -> assertFailure ("expected restored governed state, got: " <> show other)

testBootstrapSessionRestoresCanonicalGovernanceViews :: Test
testBootstrapSessionRestoresCanonicalGovernanceViews = TestCase $ do
  withRuntimeEnv "qxfx0_test_governance_bootstrap_restore.db" $ do
    session0 <- Runtime.bootstrapSession True "governance_bootstrap_restore"
    let rt = Runtime.sessRuntime session0
        governedState = authoritativeGovernedState (Runtime.sessSystemState session0)
        stalePersistedState = governedState
          { ssSelfState = (ssSelfState governedState)
              { selfPerspectiveRegistry = selfPerspectiveRegistry (ssSelfState emptySystemState) }
          , ssGovernanceProjection = ssGovernanceProjection emptySystemState
          }
    assertBool "bootstrap governed fixture must record canonical governance history"
      (not (null (ssGovernanceHistory governedState)))
    assertBool "bootstrap governed fixture must produce a non-empty derived perspective registry"
      (selfPerspectiveRegistry (ssSelfState governedState) /= selfPerspectiveRegistry (ssSelfState emptySystemState))
    saveResult <- StatePersistence.saveState (Runtime.withRuntimeDb rt) stalePersistedState "governance_bootstrap_restore"
    case saveResult of
      Left err -> assertFailure ("failed to persist governed bootstrap fixture: " <> T.unpack (renderPersistenceDiagnostics [err]))
      Right _ -> pure ()
    restored <- Runtime.bootstrapSession True "governance_bootstrap_restore"
    let restoredState = Runtime.sessSystemState restored
    assertEqual "bootstrap should report restored origin for authoritative governed state"
      Runtime.RestoredOrigin
      (Runtime.sessStateOrigin restored)
    assertEqual "bootstrap must preserve canonical governance history"
      (ssGovernanceHistory governedState)
      (ssGovernanceHistory restoredState)
    assertEqual "bootstrap must rebuild perspective registry from canonical history"
      (selfPerspectiveRegistry (ssSelfState governedState))
      (selfPerspectiveRegistry (ssSelfState restoredState))
    assertEqual "bootstrap must rebuild governance projection from canonical history"
      (ssGovernanceProjection governedState)
      (ssGovernanceProjection restoredState)

-- SLICE-013 Option 1: strict rejects corruption, not compatibility. A
-- non-authoritative (LegacyIncompleteSurface) persisted blob is valid
-- compatibility state, so STRICT bootstrap must RESTORE it (marker preserved,
-- restart authority demoted), not fail closed. NA-001/H1 holds because the
-- semantic anchor is denied, not because the state is rejected.
testBootstrapSessionStrictRestoresNonAuthoritativePersistedState :: Test
testBootstrapSessionStrictRestoresNonAuthoritativePersistedState = TestCase $ do
  withStrictRuntimeEnv "qxfx0_test_bootstrap_non_authoritative_strict.db" $ do
    session0 <- Runtime.bootstrapSession True "bootstrap_non_authoritative_strict"
    let rt = Runtime.sessRuntime session0
        ss0 = authoritativeGovernedState (Runtime.sessSystemState session0)
    saveResult <- StatePersistence.saveState (Runtime.withRuntimeDb rt) ss0 "bootstrap_non_authoritative_strict"
    case saveResult of
      Left err -> assertFailure ("failed to persist strict non-authoritative state fixture: " <> T.unpack (renderPersistenceDiagnostics [err]))
      Right _ -> pure ()
    writeNonAuthoritativePersistedTruthBlob rt "bootstrap_non_authoritative_strict"
    result <- try (Runtime.bootstrapSession True "bootstrap_non_authoritative_strict") :: IO (Either QxFx0Exception Runtime.Session)
    case result of
      Right restored -> do
        assertEqual "strict bootstrap must restore non-authoritative state with its marker preserved"
          LegacyIncompleteSurface
          (ssTruthContractStatus (Runtime.sessSystemState restored))
        assertEqual "strict restore of non-authoritative state must deny semantic anchor restart authority"
          Nothing
          (ssSemanticAnchor (Runtime.sessSystemState restored))
      Left ex ->
        assertFailure ("strict bootstrap must not fail closed on a valid non-authoritative (compatibility) persisted state, got: " <> show ex)

-- SLICE-013 Option 1: a non-authoritative persisted blob is compatibility state,
-- not corruption, so DEGRADED bootstrap RESTORES it (marker preserved, restart
-- authority demoted) rather than reporting RecoveredCorruptOrigin / surfacing a
-- corrupt-recovery governance fault. (RecoveredCorruptOrigin is reserved for truly
-- corrupt blobs — see testBootstrapSessionMarksRecoveredCorruption.)
testBootstrapSessionDegradedRestoresNonAuthoritativePersistedState :: Test
testBootstrapSessionDegradedRestoresNonAuthoritativePersistedState = TestCase $ do
  withRuntimeEnv "qxfx0_test_bootstrap_non_authoritative_degraded.db" $ do
    session0 <- Runtime.bootstrapSession True "bootstrap_non_authoritative_degraded"
    let rt = Runtime.sessRuntime session0
        ss0 = authoritativeGovernedState (Runtime.sessSystemState session0)
    saveResult <- StatePersistence.saveState (Runtime.withRuntimeDb rt) ss0 "bootstrap_non_authoritative_degraded"
    case saveResult of
      Left err -> assertFailure ("failed to persist degraded non-authoritative state fixture: " <> T.unpack (renderPersistenceDiagnostics [err]))
      Right _ -> pure ()
    writeNonAuthoritativePersistedTruthBlob rt "bootstrap_non_authoritative_degraded"
    restored <- Runtime.bootstrapSession True "bootstrap_non_authoritative_degraded"
    assertBool "degraded bootstrap must NOT treat a valid non-authoritative state as recovered-corrupt"
      (Runtime.sessStateOrigin restored /= Runtime.RecoveredCorruptOrigin)
    assertEqual "degraded bootstrap must restore the non-authoritative marker verbatim"
      LegacyIncompleteSurface
      (ssTruthContractStatus (Runtime.sessSystemState restored))
    assertEqual "degraded restore of non-authoritative state must deny semantic anchor restart authority"
      Nothing
      (ssSemanticAnchor (Runtime.sessSystemState restored))
    assertEqual "degraded restore of a valid non-authoritative state must not raise a corrupt-recovery governance fault"
      Nothing
      (ssGovernanceRuntimeFault (Runtime.sessSystemState restored))

testLoadStateCorruptBlobIsReported :: Test
testLoadStateCorruptBlobIsReported = TestCase $ do
  withRuntimeEnv "qxfx0_test_corrupt_field.db" $ do
    session0 <- Runtime.bootstrapSession True "test_corrupt"
    let rt = Runtime.sessRuntime session0
    Runtime.withRuntimeDb rt $ \db -> do
      let sql = "INSERT OR REPLACE INTO dialogue_state(session_id, key, value, updated_at) VALUES(?, ?, ?, datetime('now'))"
      mStmt <- NSQL.prepare db sql
      case mStmt of
        Left _ -> pure ()
        Right stmt -> do
          _ <- NSQL.bindText stmt 1 "test_corrupt"
          _ <- NSQL.bindText stmt 2 "__system_state__"
          _ <- NSQL.bindText stmt 3 "{not valid json"
          _ <- NSQL.step stmt
          NSQL.finalize stmt
          pure ()
    loaded <- StatePersistence.loadState (Runtime.withRuntimeDb rt) "test_corrupt"
    case loaded of
      StatePersistence.LoadStateCorrupt _ -> pure ()
      other -> assertFailure ("expected corrupt load result, got: " <> show other)

testLoadStateCorruptUtf8BlobIsReported :: Test
testLoadStateCorruptUtf8BlobIsReported = TestCase $ do
  withRuntimeEnv "qxfx0_test_corrupt_utf8_blob.db" $ do
    session0 <- Runtime.bootstrapSession True "test_corrupt_utf8"
    let rt = Runtime.sessRuntime session0
    Runtime.withRuntimeDb rt $ \db -> do
      let sql = "INSERT OR REPLACE INTO dialogue_state(session_id, key, value, updated_at) VALUES(?, ?, CAST(X'80' AS TEXT), datetime('now'))"
      mStmt <- NSQL.prepare db sql
      case mStmt of
        Left _ -> pure ()
        Right stmt -> do
          _ <- NSQL.bindText stmt 1 "test_corrupt_utf8"
          _ <- NSQL.bindText stmt 2 "__system_state__"
          _ <- NSQL.step stmt
          NSQL.finalize stmt
          pure ()
    loaded <- StatePersistence.loadState (Runtime.withRuntimeDb rt) "test_corrupt_utf8"
    case loaded of
      StatePersistence.LoadStateCorrupt diagnostics ->
        assertBool "invalid UTF-8 must be classified as corrupt decode"
          (PdCorruptDecode `elem` diagnostics)
      other ->
        assertFailure ("expected corrupt UTF-8 load result, got: " <> show other)

testLoadStateLegacyNumericTrajectoryHashRestores :: Test
testLoadStateLegacyNumericTrajectoryHashRestores = TestCase $ do
  withRuntimeEnv "qxfx0_test_legacy_numeric_trajectory_hash.db" $ do
    session0 <- Runtime.bootstrapSession True "test_legacy_numeric_trajectory_hash"
    let rt = Runtime.sessRuntime session0
        ss0 = (Runtime.sessSystemState session0)
          { ssSelfState = (ssSelfState (Runtime.sessSystemState session0))
              { selfEssence = EssenceCommitted emptyTrajectory
                  (EssenceCommitment EssenceContemplative TriggerAngstThreshold 1 (TrajectoryHash "sha256:legacy-fixture"))
              }
          }
    saveResult <- StatePersistence.saveState (Runtime.withRuntimeDb rt) ss0 "test_legacy_numeric_trajectory_hash"
    case saveResult of
      Left err -> assertFailure ("failed to persist legacy trajectory hash fixture: " <> T.unpack (renderPersistenceDiagnostics [err]))
      Right _ -> pure ()
    Runtime.withRuntimeDb rt $ \db -> do
      let selectSql = "SELECT value FROM dialogue_state WHERE session_id = ? AND key = ?"
      mSelect <- NSQL.prepare db selectSql
      selectStmt <- case mSelect of
        Left err -> assertFailure ("failed to prepare legacy trajectory hash select: " <> T.unpack err) >> fail "unreachable"
        Right stmt -> pure stmt
      _ <- NSQL.bindText selectStmt 1 "test_legacy_numeric_trajectory_hash"
      _ <- NSQL.bindText selectStmt 2 "__system_state__"
      hasRow <- NSQL.stepRow selectStmt
      blob <- if hasRow then NSQL.columnText selectStmt 0 else assertFailure "missing persisted state blob for legacy trajectory hash fixture" >> fail "unreachable"
      NSQL.finalize selectStmt
      let updateSql = "INSERT OR REPLACE INTO dialogue_state(session_id, key, value, updated_at) VALUES(?, ?, ?, datetime('now'))"
      mUpdate <- NSQL.prepare db updateSql
      updateStmt <- case mUpdate of
        Left err -> assertFailure ("failed to prepare legacy trajectory hash update: " <> T.unpack err) >> fail "unreachable"
        Right stmt -> pure stmt
      legacyBlob <-
        case (Aeson.decode (BL.fromStrict (encodeUtf8 blob)) :: Maybe Value) of
          Nothing -> assertFailure "failed to decode persisted legacy trajectory fixture JSON" >> fail "unreachable"
          Just value ->
            pure (TE.decodeUtf8 . BL.toStrict . Aeson.encode $ injectLegacyNumericTrajectoryHash value)
      _ <- NSQL.bindText updateStmt 1 "test_legacy_numeric_trajectory_hash"
      _ <- NSQL.bindText updateStmt 2 "__system_state__"
      _ <- NSQL.bindText updateStmt 3 legacyBlob
      _ <- NSQL.step updateStmt
      NSQL.finalize updateStmt
    loaded <- StatePersistence.loadState (Runtime.withRuntimeDb rt) "test_legacy_numeric_trajectory_hash"
    case loaded of
      StatePersistence.LoadStateRestored restored ->
        case selfEssence (ssSelfState restored) of
          EssenceCommitted _ commitment ->
            assertEqual "legacy numeric trajectory hash should restore as text-compatible value"
              (TrajectoryHash "0")
              (ecWitnessHash commitment)
          other -> assertFailure ("expected committed essence after legacy trajectory restore, got: " <> show other)
      other ->
        assertFailure ("expected restored state for legacy numeric trajectory hash, got: " <> show other)

-- Navigates the REAL persisted path to the committed essence's witness hash:
-- ssSelfState -> selfEssence -> contents[1] -> ecWitnessHash. (The earlier
-- "essence" top-level key was stale — SystemState keys it "ssSelfState" and
-- SelfState keys it "selfEssence" via generic-default field names, so the old
-- path silently no-op'd and the fixture hash survived unchanged.)
injectLegacyNumericTrajectoryHash :: Value -> Value
injectLegacyNumericTrajectoryHash value =
  case value of
    Object root ->
      Object (updateKeyMap (Key.fromText "ssSelfState") updateSelfState root)
    _ -> value
  where
    updateSelfState selfStateVal =
      case selfStateVal of
        Object selfStateObj ->
          Object (updateKeyMap (Key.fromText "selfEssence") updateEssence selfStateObj)
        _ -> selfStateVal
    updateEssence essenceVal =
      case essenceVal of
        Object essenceObj ->
          Object (updateKeyMap (Key.fromText "contents") updateCommitmentContents essenceObj)
        _ -> essenceVal
    updateCommitmentContents contentsVal =
      case contentsVal of
        Array xs
          | length xs >= 2 ->
              let updated = xs V.// [(1, updateCommitment (xs V.! 1))]
              in Array updated
        _ -> contentsVal
    updateCommitment commitmentVal =
      case commitmentVal of
        Object commitmentObj ->
          Object (KeyMap.insert (Key.fromText "ecWitnessHash") (Number 0) commitmentObj)
        _ -> commitmentVal

updateKeyMap :: Key.Key -> (Value -> Value) -> KeyMap.KeyMap Value -> KeyMap.KeyMap Value
updateKeyMap key f km =
  case KeyMap.lookup key km of
    Just current -> KeyMap.insert key (f current) km
    Nothing -> km

injectNonAuthoritativeTruthContract :: Value -> Value
injectNonAuthoritativeTruthContract value =
  case value of
    Object root -> Object (KeyMap.insert (Key.fromText "truthContractStatus") (String "LegacyIncompleteSurface") root)
    _ -> value

writeNonAuthoritativePersistedTruthBlob :: Runtime.RuntimeContext -> T.Text -> IO ()
writeNonAuthoritativePersistedTruthBlob rt sessionId =
  Runtime.withRuntimeDb rt $ \db -> do
    let selectSql = "SELECT value FROM dialogue_state WHERE session_id = ? AND key = ?"
    mSelect <- NSQL.prepare db selectSql
    selectStmt <- case mSelect of
      Left err -> assertFailure ("failed to prepare non-authoritative persisted-state select: " <> T.unpack err) >> fail "unreachable"
      Right stmt -> pure stmt
    _ <- NSQL.bindText selectStmt 1 sessionId
    _ <- NSQL.bindText selectStmt 2 "__system_state__"
    hasRow <- NSQL.stepRow selectStmt
    blob <- if hasRow then NSQL.columnText selectStmt 0 else assertFailure "missing persisted state blob for non-authoritative fixture" >> fail "unreachable"
    NSQL.finalize selectStmt
    mutatedBlob <-
      case (Aeson.decode (BL.fromStrict (encodeUtf8 blob)) :: Maybe Value) of
        Nothing -> assertFailure "failed to decode persisted state JSON for non-authoritative fixture" >> fail "unreachable"
        Just value -> pure (TE.decodeUtf8 . BL.toStrict . Aeson.encode $ injectNonAuthoritativeTruthContract value)
    let updateSql = "INSERT OR REPLACE INTO dialogue_state(session_id, key, value, updated_at) VALUES(?, ?, ?, datetime('now'))"
    mUpdate <- NSQL.prepare db updateSql
    updateStmt <- case mUpdate of
      Left err -> assertFailure ("failed to prepare non-authoritative persisted-state update: " <> T.unpack err) >> fail "unreachable"
      Right stmt -> pure stmt
    _ <- NSQL.bindText updateStmt 1 sessionId
    _ <- NSQL.bindText updateStmt 2 "__system_state__"
    _ <- NSQL.bindText updateStmt 3 mutatedBlob
    _ <- NSQL.step updateStmt
    NSQL.finalize updateStmt

testBootstrapSessionMarksRecoveredCorruption :: Test
testBootstrapSessionMarksRecoveredCorruption = TestCase $ do
  withRuntimeEnv "qxfx0_test_corrupt_bootstrap.db" $ do
    session0 <- Runtime.bootstrapSession True "test_corrupt_bootstrap"
    let rt = Runtime.sessRuntime session0
    Runtime.withRuntimeDb rt $ \db -> do
      let sql = "INSERT OR REPLACE INTO dialogue_state(session_id, key, value, updated_at) VALUES(?, ?, ?, datetime('now'))"
      mStmt <- NSQL.prepare db sql
      case mStmt of
        Left _ -> pure ()
        Right stmt -> do
          _ <- NSQL.bindText stmt 1 "test_corrupt_bootstrap"
          _ <- NSQL.bindText stmt 2 "__system_state__"
          _ <- NSQL.bindText stmt 3 "{corrupt"
          _ <- NSQL.step stmt
          NSQL.finalize stmt
          pure ()
    recovered <- Runtime.bootstrapSession True "test_corrupt_bootstrap"
    assertEqual
      "corrupt persisted state should not masquerade as fresh bootstrap"
      Runtime.RecoveredCorruptOrigin
      (Runtime.sessStateOrigin recovered)

testStateBlobDiagnosticsDetectsMissingOptionalFields :: Test
testStateBlobDiagnosticsDetectsMissingOptionalFields = TestCase $ do
  let minimalBlob = T.pack "{\"history\":[],\"rawInputHistory\":[],\"turnCount\":0,\"lastTopic\":\"\",\"lastFamily\":\"CMGround\",\"lastForce\":\"IFAssert\",\"lastLayer\":\"ContentLayer\",\"lastEmbedding\":[],\"consecutiveReflect\":0,\"recentFamilies\":[],\"activeScene\":\"None\",\"userState\":{\"claims\":[],\"topics\":[]},\"ego\":{\"tension\":0.0,\"agency\":1.0,\"narrative\":\"\"},\"identityClaims\":[],\"orbitalMemory\":[],\"trace\":[],\"meaningGraph\":{\"edges\":[],\"turnCount\":0},\"kernelPulse\":\"Neutral\",\"blockedConcepts\":[],\"clusters\":[],\"intuitConfidence\":0.5,\"sessionId\":\"test\",\"outputMode\":\"text\",\"morphology\":{\"entries\":[]},\"observability\":{\"lastQualityScore\":0.0,\"lastShadowDivergence\":null,\"lastCheckpointTurn\":0}}"
      diagnostics = StatePersistence.stateBlobDiagnostics minimalBlob
      completeBlob = T.pack "{\"history\":[],\"rawInputHistory\":[],\"turnCount\":0,\"lastTopic\":\"\",\"lastFamily\":\"CMGround\",\"lastForce\":\"IFAssert\",\"lastLayer\":\"ContentLayer\",\"lastEmbedding\":[],\"consecutiveReflect\":0,\"recentFamilies\":[],\"activeScene\":\"None\",\"userState\":{\"claims\":[],\"topics\":[]},\"ego\":{\"tension\":0.0,\"agency\":1.0,\"narrative\":\"\"},\"identityClaims\":[],\"orbitalMemory\":[],\"lastGuardReport\":null,\"trace\":[],\"meaningGraph\":{\"edges\":[],\"turnCount\":0},\"kernelPulse\":\"Neutral\",\"blockedConcepts\":[],\"clusters\":[],\"dreamState\":null,\"intuitionState\":null,\"semanticAnchor\":null,\"lastTurnDecision\":null,\"intuitConfidence\":0.5,\"sessionId\":\"test\",\"outputMode\":\"text\",\"morphology\":{\"entries\":[]},\"observability\":{\"lastQualityScore\":0.0,\"lastShadowDivergence\":null,\"lastCheckpointTurn\":0}}"
      diagnosticsComplete = StatePersistence.stateBlobDiagnostics completeBlob
  assertEqual "state blob diagnostics should surface omitted optional compatibility fields explicitly"
    [PdSchemaMissingFields ["lastGuardReport", "dreamState", "intuitionState", "semanticAnchor", "lastTurnDecision"]]
    diagnostics
  assertEqual "complete blob should have no diagnostics" [] diagnosticsComplete

testLoadStateMissingRequiredTopLevelFieldsFailsDecode :: Test
testLoadStateMissingRequiredTopLevelFieldsFailsDecode = TestCase $ do
  withRuntimeEnv "qxfx0_test_missing_required_state_fields.db" $ do
    session0 <- Runtime.bootstrapSession True "test_missing_required_state_fields"
    let rt = Runtime.sessRuntime session0
    Runtime.withRuntimeDb rt $ \db -> do
      let blob = T.pack "{\"history\":[],\"rawInputHistory\":[],\"turnCount\":0,\"lastTopic\":\"\",\"lastFamily\":\"CMGround\",\"lastForce\":\"IFAssert\",\"lastLayer\":\"ContentLayer\",\"lastEmbedding\":[],\"consecutiveReflect\":0,\"recentFamilies\":[],\"activeScene\":\"None\",\"userState\":{\"claims\":[],\"topics\":[]},\"ego\":{\"tension\":0.0,\"agency\":1.0,\"narrative\":\"\"},\"identityClaims\":[],\"orbitalMemory\":[],\"trace\":[],\"meaningGraph\":{\"edges\":[],\"turnCount\":0},\"kernelPulse\":\"Neutral\",\"blockedConcepts\":[],\"clusters\":[],\"intuitConfidence\":0.5,\"sessionId\":\"test\",\"outputMode\":\"text\",\"observability\":{\"lastQualityScore\":0.0,\"lastShadowDivergence\":null,\"lastCheckpointTurn\":0}}"
          sql = "INSERT OR REPLACE INTO dialogue_state(session_id, key, value, updated_at) VALUES(?, ?, ?, datetime('now'))"
      mStmt <- NSQL.prepare db sql
      case mStmt of
        Left _ -> pure ()
        Right stmt -> do
          _ <- NSQL.bindText stmt 1 "test_missing_required_state_fields"
          _ <- NSQL.bindText stmt 2 "__system_state__"
          _ <- NSQL.bindText stmt 3 blob
          _ <- NSQL.step stmt
          NSQL.finalize stmt
    loaded <- StatePersistence.loadState (Runtime.withRuntimeDb rt) "test_missing_required_state_fields"
    case loaded of
      StatePersistence.LoadStateCorrupt diagnostics ->
        assertBool "missing required top-level fields must fail decode instead of silently defaulting"
          (PdCorruptDecode `elem` diagnostics)
      other ->
        assertFailure ("expected corrupt result for missing required state fields, got: " <> show other)

testSaveStateReturnsRightOnSuccess :: Test
testSaveStateReturnsRightOnSuccess = TestCase $ do
  withRuntimeEnv "qxfx0_test_save_success.db" $ do
    session0 <- Runtime.bootstrapSession True "test_save_ok"
    let rt = Runtime.sessRuntime session0
        governedState = authoritativeGovernedState (Runtime.sessSystemState session0)
        ss0 = governedState
          { ssOutputMode = SemanticIntrospectionOutput
          , ssTruthContractStatus = NonExpansiveRecoverySurface
          , ssGovernanceRuntimeFault = Just GrfRebuildMismatch
          }
    result <- StatePersistence.saveState (Runtime.withRuntimeDb rt) ss0 "test_save_ok"
    case result of
      Left err -> assertFailure ("saveState should return Right on success, got Left: " <> T.unpack (renderPersistenceDiagnostics [err]))
      Right ss -> do
        assertBool "saved runtime continuation should preserve turn count" (ssTurnCount ss == ssTurnCount ss0)
        assertEqual "saved runtime continuation should preserve output mode"
          SemanticIntrospectionOutput
          (ssOutputMode ss)
        assertEqual "saved runtime continuation should preserve runtime governance fault"
          (Just GrfRebuildMismatch)
          (ssGovernanceRuntimeFault ss)
        assertEqual "saved runtime continuation should preserve live perspective registry"
          (selfPerspectiveRegistry (ssSelfState ss0))
          (selfPerspectiveRegistry (ssSelfState ss))
        persistedBlob <- Runtime.withRuntimeDb rt $ \db -> do
          mStmt <- NSQL.prepare db "SELECT value FROM dialogue_state WHERE session_id = ? AND key = ? ORDER BY updated_at DESC LIMIT 1"
          stmt <- case mStmt of
            Left sqlErr -> assertFailure ("Failed to prepare persisted-state query: " <> T.unpack sqlErr) >> fail "unreachable"
            Right s -> pure s
          _ <- NSQL.bindText stmt 1 "test_save_ok"
          _ <- NSQL.bindText stmt 2 "__system_state__"
          hasRow <- NSQL.stepRow stmt
          payload <- if hasRow then NSQL.columnText stmt 0 else pure ""
          NSQL.finalize stmt
          pure payload
        case (eitherDecodeStrict' (encodeUtf8 persistedBlob) :: Either String SystemState) of
          Left decodeErr ->
            assertFailure ("Persisted system state should decode as JSON: " <> decodeErr)
          Right persistedState -> do
            assertEqual "persisted canonical state must clear output mode"
              DialogueOutput
              (ssOutputMode persistedState)
            assertEqual "persisted state must preserve truth-contract status verbatim (no manufactured authority: non-authoritative marker is neither upgraded nor collapsed)"
              NonExpansiveRecoverySurface
              (ssTruthContractStatus persistedState)
            assertEqual "persisted canonical state must clear runtime governance fault"
              Nothing
              (ssGovernanceRuntimeFault persistedState)
            assertEqual "persisted canonical state must not carry rebuildable registry"
               (selfPerspectiveRegistry (ssSelfState emptySystemState))
               (selfPerspectiveRegistry (ssSelfState persistedState))

-- | SLICE-013 truth-contract policy: persistence cleanup preserves the
-- truth-contract status verbatim and never manufactures authority. For every
-- status — authoritative or non-authoritative — the persisted artifact must
-- carry exactly the same status it went in with: no upgrade, no downgrade, no
-- collapse of one marker into another. (Restart-authority demotion is the
-- restore path's concern, tested separately.) This is the explicit guard for
-- the StatePersistence-case-11 vs RuntimeInfrastructure-18/19/26 conflict.
testPersistedStatePreservesTruthContractStatusVerbatim :: Test
testPersistedStatePreservesTruthContractStatusVerbatim =
  TestList
    [ TestLabel ("persist preserves " <> show status) (mkCase status)
    | status <- [minBound .. maxBound] :: [TruthContractStatus]
    ]
  where
    mkCase status = TestCase $
      withRuntimeEnv "qxfx0_test_truthcontract_verbatim.db" $ do
        session0 <- Runtime.bootstrapSession True "truthcontract_verbatim"
        let rt = Runtime.sessRuntime session0
            ss0 = (authoritativeGovernedState (Runtime.sessSystemState session0))
              { ssTruthContractStatus = status }
        result <- StatePersistence.saveState (Runtime.withRuntimeDb rt) ss0 "truthcontract_verbatim"
        case result of
          Left err ->
            assertFailure ("saveState should succeed, got Left: " <> T.unpack (renderPersistenceDiagnostics [err]))
          Right _ -> do
            persistedBlob <- Runtime.withRuntimeDb rt $ \db -> do
              mStmt <- NSQL.prepare db "SELECT value FROM dialogue_state WHERE session_id = ? AND key = ? ORDER BY updated_at DESC LIMIT 1"
              stmt <- case mStmt of
                Left sqlErr -> assertFailure ("Failed to prepare persisted-state query: " <> T.unpack sqlErr) >> fail "unreachable"
                Right s -> pure s
              _ <- NSQL.bindText stmt 1 "truthcontract_verbatim"
              _ <- NSQL.bindText stmt 2 "__system_state__"
              hasRow <- NSQL.stepRow stmt
              payload <- if hasRow then NSQL.columnText stmt 0 else pure ""
              NSQL.finalize stmt
              pure payload
            case (eitherDecodeStrict' (encodeUtf8 persistedBlob) :: Either String SystemState) of
              Left decodeErr ->
                assertFailure ("Persisted system state should decode as JSON: " <> decodeErr)
              Right persistedState -> do
                assertEqual ("truth-contract status must be preserved verbatim for " <> show status)
                  status
                  (ssTruthContractStatus persistedState)
                -- Save-path cleanup still happens regardless of status.
                assertEqual "persisted state must still clear output mode"
                  DialogueOutput
                  (ssOutputMode persistedState)

-- | Idempotency: re-persisting an already-persisted state changes neither the
-- truth-contract status nor the cleared derived/runtime-local views, for every
-- status. canonicalize is monotonic-by-authority with a fixed point on
-- already-canonical state.
testPersistedStateCanonicalizeIsIdempotent :: Test
testPersistedStateCanonicalizeIsIdempotent =
  TestList
    [ TestLabel ("idempotent persist for " <> show status) (mkCase status)
    | status <- [minBound .. maxBound] :: [TruthContractStatus]
    ]
  where
    mkCase status = TestCase $
      withRuntimeEnv "qxfx0_test_truthcontract_idem.db" $ do
        session0 <- Runtime.bootstrapSession True "truthcontract_idem"
        let rt = Runtime.sessRuntime session0
            ss0 = (authoritativeGovernedState (Runtime.sessSystemState session0))
              { ssTruthContractStatus = status }
        r1 <- StatePersistence.saveState (Runtime.withRuntimeDb rt) ss0 "truthcontract_idem"
        case r1 of
          Left err -> assertFailure ("first saveState failed: " <> T.unpack (renderPersistenceDiagnostics [err]))
          Right s1 -> do
            r2 <- StatePersistence.saveState (Runtime.withRuntimeDb rt) s1 "truthcontract_idem"
            case r2 of
              Left err -> assertFailure ("second saveState failed: " <> T.unpack (renderPersistenceDiagnostics [err]))
              Right s2 -> do
                assertEqual ("status stable across re-persist for " <> show status)
                  (ssTruthContractStatus s1)
                  (ssTruthContractStatus s2)
                assertEqual ("status still equals input for " <> show status)
                  status
                  (ssTruthContractStatus s2)
                assertEqual "output mode stable across re-persist"
                  (ssOutputMode s1)
                  (ssOutputMode s2)

testPersistedStateEnvelopeRoundTrip :: Test
testPersistedStateEnvelopeRoundTrip = TestCase $ do
  withRuntimeEnv "qxfx0_test_envelope_roundtrip.db" $ do
    session0 <- Runtime.bootstrapSession True "envelope_roundtrip"
    let rt = Runtime.sessRuntime session0
        ss0 = authoritativeGovernedState (Runtime.sessSystemState session0)
        envelope = PersistenceEnvelope
          { peVersion = currentPersistenceEnvelopeVersion
          , peState = ss0
          }
        blob = TE.decodeUtf8 . BL.toStrict . Aeson.encode $ envelope
    result <- StatePersistence.saveState (Runtime.withRuntimeDb rt) ss0 "envelope_roundtrip"
    case result of
      Left err -> assertFailure ("saveState should succeed: " <> T.unpack (renderPersistenceDiagnostics [err]))
      Right _ -> pure ()
    loaded <- StatePersistence.loadState (Runtime.withRuntimeDb rt) "envelope_roundtrip"
    case loaded of
      LoadStateRestored restored ->
        assertEqual "envelope round-trip must restore state"
          (ssTurnCount ss0)
          (ssTurnCount restored)
      other -> assertFailure ("expected envelope round-trip success, got: " <> show other)

testPersistedStateBareRoundTrip :: Test
testPersistedStateBareRoundTrip = TestCase $ do
  withRuntimeEnv "qxfx0_test_bare_roundtrip.db" $ do
    session0 <- Runtime.bootstrapSession True "bare_roundtrip"
    let rt = Runtime.sessRuntime session0
        ss0 = authoritativeGovernedState (Runtime.sessSystemState session0)
        blob = TE.decodeUtf8 . BL.toStrict . Aeson.encode $ ss0
    -- Write a bare blob directly (legacy format) to verify decode fallback
    Runtime.withRuntimeDb rt $ \db -> do
      mStmt <- NSQL.prepare db "INSERT OR REPLACE INTO dialogue_state(session_id, key, value, updated_at) VALUES(?, ?, ?, datetime('now'))"
      case mStmt of
        Left sqlErr -> assertFailure ("prepare failed: " <> T.unpack sqlErr) >> fail "unreachable"
        Right stmt -> do
          _ <- NSQL.bindText stmt 1 "bare_roundtrip"
          _ <- NSQL.bindText stmt 2 "__system_state__"
          _ <- NSQL.bindText stmt 3 blob
          _ <- NSQL.stepRow stmt
          NSQL.finalize stmt
          pure ()
    loaded <- StatePersistence.loadState (Runtime.withRuntimeDb rt) "bare_roundtrip"
    case loaded of
      LoadStateRestored restored ->
        assertEqual "bare round-trip must restore state"
          (ssTurnCount ss0)
          (ssTurnCount restored)
      other -> assertFailure ("expected bare round-trip success, got: " <> show other)

testSaveStateWithProjectionFailureRollsBackTransaction :: Test
testSaveStateWithProjectionFailureRollsBackTransaction = TestCase $ do
  withRuntimeEnv "qxfx0_test_save_projection_rollback.db" $ do
    let sessionId = "test_save_projection_rollback"
    session0 <- Runtime.bootstrapSession True sessionId
    let rt = Runtime.sessRuntime session0
        ss0 = Runtime.sessSystemState session0
        projection = TurnProjection
          { tqpTurn = 1
          , tqpParserMode = ParserFrameV1
          , tqpParserConfidence = 0.31
          , tqpParserErrors = ["projection_failure_fixture"]
          , tqpPlannerMode = DefaultPlanner
          , tqpPlannerDecision = CMGround
          , tqpAtomRegister = Search
          , tqpAtomLoad = 0.7
          , tqpScenePressure = PressureHigh
          , tqpSceneRequest = "rollback_fixture"
          , tqpSceneStance = MetaLayer
          , tqpRenderLane = ValidateMove
          , tqpRenderStyle = StyleFormal
          , tqpLegitimacyStatus = LegitimacyDegraded
          , tqpLegitimacyReason = ReasonShadowDivergence
          , tqpWarrantedMode = AlwaysWarranted
          , tqpDecisionDisposition = DispositionRepair
          , tqpOwnerFamily = CMGround
          , tqpOwnerForce = IFAssert
          , tqpShadowStatus = ShadowDiverged
          , tqpShadowSnapshotId = ShadowSnapshotId "shadow:projection_rollback_fixture"
          , tqpShadowDivergenceKind = ShadowVerdictMismatch
          , tqpShadowFamily = Just CMConfront
          , tqpShadowForce = Just IFConfront
          , tqpShadowMessage = "fixture_divergence"
          , tqpReplayTrace = fixtureReplayTrace sessionId 0.31 "ok" Nothing
          , tqpDivergence = True
          }
    beforeCount <- Runtime.withRuntimeDb rt $ \db ->
      queryCount db "SELECT count(*) FROM turn_quality WHERE session_id = 'test_save_projection_rollback'"
    Runtime.withRuntimeDb rt $ \db ->
      assertExec db "drop shadow_divergence_log" "DROP TABLE IF EXISTS shadow_divergence_log;"
    result <- StatePersistence.saveStateWithProjection
      (Runtime.withRuntimeDb rt)
      ss0
      sessionId
      (Just projection)
    case result of
      Left _ -> pure ()
      Right _ -> assertFailure "saveStateWithProjection should fail when divergence table is missing"
    afterCount <- Runtime.withRuntimeDb rt $ \db ->
      queryCount db "SELECT count(*) FROM turn_quality WHERE session_id = 'test_save_projection_rollback'"
    assertEqual "failed projection persistence must rollback turn_quality insert" beforeCount afterCount

testPersistedSystemStateSessionIdMatchesBootstrapId :: Test
testPersistedSystemStateSessionIdMatchesBootstrapId = TestCase $ do
  withRuntimeEnv "qxfx0_test_session_id_persist.db" $ do
    let sessionId = "test_session_id_persist"
    session0 <- Runtime.bootstrapSession True sessionId
    (session1, output1) <- Runtime.runTurnInSession session0 "Что такое свобода?"
    assertBool "turn output should not be empty" (not (T.null output1))
    let rt = Runtime.sessRuntime session1
    persistedBlob <- Runtime.withRuntimeDb rt $ \db -> do
      mStmt <- NSQL.prepare db "SELECT value FROM dialogue_state WHERE session_id = ? AND key = ? ORDER BY updated_at DESC LIMIT 1"
      stmt <- case mStmt of
        Left err -> assertFailure ("Failed to prepare persisted-state query: " <> T.unpack err) >> fail "unreachable"
        Right s -> pure s
      _ <- NSQL.bindText stmt 1 sessionId
      _ <- NSQL.bindText stmt 2 "__system_state__"
      hasRow <- NSQL.stepRow stmt
      payload <- if hasRow then NSQL.columnText stmt 0 else pure ""
      NSQL.finalize stmt
      pure payload
    case eitherDecodeStrict' (encodeUtf8 persistedBlob) of
      Left err ->
        assertFailure ("Persisted system state should decode as JSON: " <> err)
      Right (Object obj) ->
        case KeyMap.lookup "sessionId" obj of
          Just (String persistedSessionId) ->
            assertEqual "Persisted SystemState.sessionId should match runtime session id"
              sessionId
              persistedSessionId
          other ->
            assertFailure ("Persisted SystemState.sessionId should be JSON string, got: " <> show other)
      Right other ->
        assertFailure ("Persisted system state should be JSON object, got: " <> show other)

testPersistedReplayTraceDeterministicAcrossFreshSessionsProperty :: Test
testPersistedReplayTraceDeterministicAcrossFreshSessionsProperty =
  TestCase $ do
    forM_ replayInputs $ \rawInput ->
      withStrictRuntimeEnv "qxfx0_test_replay_trace_determinism.db" $ do
        sessionA <- Runtime.bootstrapSession True "fresh_det_session_a"
        _ <- Runtime.runTurnInSession sessionA (T.pack rawInput)
        sessionB <- Runtime.bootstrapSession True "fresh_det_session_b"
        _ <- Runtime.runTurnInSession sessionB (T.pack rawInput)
        let rt = Runtime.sessRuntime sessionB
        replayA <- Runtime.withRuntimeDb rt $ \db ->
          fetchLatestReplayTraceJson db "fresh_det_session_a"
        replayB <- Runtime.withRuntimeDb rt $ \db ->
          fetchLatestReplayTraceJson db "fresh_det_session_b"
        normalizedA <- normalizeReplayTraceJson "fresh_det_session_a" replayA
        normalizedB <- normalizeReplayTraceJson "fresh_det_session_b" replayB
        assertEqual ("persisted replay trace should be deterministic across fresh sessions for input: " <> rawInput)
          normalizedA
          normalizedB
  where
    replayInputs =
      [ "Что такое свобода?"
      , "Мне нужен контакт."
      , "Где граница между смыслом и пустотой?"
      ]

testPersistedReplayTraceDeterministicWithFixedTimeProperty :: Test
testPersistedReplayTraceDeterministicWithFixedTimeProperty =
  TestCase $ do
    forM_ replayInputs $ \rawInput ->
      withEnvVar "QXFX0_TEST_FIXED_TIME" (Just "0") $
        withStrictRuntimeEnv "qxfx0_test_replay_trace_fixed_time.db" $ do
          sessionA <- Runtime.bootstrapSession True "fixed_time_session_a"
          _ <- Runtime.runTurnInSession sessionA (T.pack rawInput)
          sessionB <- Runtime.bootstrapSession True "fixed_time_session_b"
          _ <- Runtime.runTurnInSession sessionB (T.pack rawInput)
          let rt = Runtime.sessRuntime sessionB
          replayA <- Runtime.withRuntimeDb rt $ \db ->
            fetchLatestReplayTraceJson db "fixed_time_session_a"
          replayB <- Runtime.withRuntimeDb rt $ \db ->
            fetchLatestReplayTraceJson db "fixed_time_session_b"
          normalizedA <- normalizeReplayTraceJson "fixed_time_session_a" replayA
          normalizedB <- normalizeReplayTraceJson "fixed_time_session_b" replayB
          assertEqual ("persisted replay trace should be deterministic with fixed time for input: " <> rawInput)
            normalizedA
            normalizedB
  where
    replayInputs =
      [ "Что такое свобода?"
      , "Мне нужен контакт."
      , "Где граница между смыслом и пустотой?"
      ]

testSaveStateWithDivergencePersistsShadowLog :: Test
testSaveStateWithDivergencePersistsShadowLog = TestCase $ do
  withRuntimeEnv "qxfx0_test_shadow_divergence.db" $ do
    let sessionId = "test_shadow_divergence"
    session0 <- Runtime.bootstrapSession True sessionId
    let rt = Runtime.sessRuntime session0
        ss0 = Runtime.sessSystemState session0
        projection = TurnProjection
          { tqpTurn = 1
          , tqpParserMode = ParserFrameV1
          , tqpParserConfidence = 0.3
          , tqpParserErrors = ["low_confidence"]
          , tqpPlannerMode = DefaultPlanner
          , tqpPlannerDecision = CMGround
          , tqpAtomRegister = Search
          , tqpAtomLoad = 0.8
          , tqpScenePressure = PressureHigh
          , tqpSceneRequest = "свобода"
          , tqpSceneStance = MetaLayer
          , tqpRenderLane = ValidateMove
          , tqpRenderStyle = StyleFormal
          , tqpLegitimacyStatus = LegitimacyDegraded
          , tqpLegitimacyReason = ReasonShadowDivergence
          , tqpWarrantedMode = AlwaysWarranted
          , tqpDecisionDisposition = DispositionRepair
          , tqpOwnerFamily = CMGround
          , tqpOwnerForce = IFAssert
          , tqpShadowStatus = ShadowDiverged
          , tqpShadowSnapshotId = ShadowSnapshotId "shadow:test_divergence_fixture"
          , tqpShadowDivergenceKind = ShadowVerdictMismatch
          , tqpShadowFamily = Just CMConfront
          , tqpShadowForce = Just IFConfront
          , tqpShadowMessage = "fixture_divergence"
          , tqpReplayTrace = fixtureReplayTrace sessionId 0.3 "degraded" (Just "low_confidence")
          , tqpDivergence = True
          }
    saveResult <- StatePersistence.saveStateWithProjection
      (Runtime.withRuntimeDb rt)
      ss0
      sessionId
      (Just projection)
    case saveResult of
      Left err -> assertFailure ("saveStateWithProjection should persist divergence fixture: " <> T.unpack (renderPersistenceDiagnostics [err]))
      Right _ -> pure ()
    shadowCount <- Runtime.withRuntimeDb rt $ \db ->
      queryCount db "SELECT count(*) FROM shadow_divergence_log WHERE session_id = 'test_shadow_divergence'"
    assertEqual "divergent projection should persist one shadow log row" 1 shadowCount

fetchLatestReplayTraceJson :: NSQL.Database -> T.Text -> IO T.Text
fetchLatestReplayTraceJson db sessionId = do
  mStmt <- NSQL.prepare db "SELECT replay_trace_json FROM turn_quality WHERE session_id = ? ORDER BY turn DESC LIMIT 1"
  stmt <- case mStmt of
    Left err -> assertFailure ("Failed to prepare replay_trace_json query: " <> T.unpack err) >> fail "unreachable"
    Right s -> pure s
  _ <- NSQL.bindText stmt 1 sessionId
  hasRow <- NSQL.stepRow stmt
  value <- if hasRow then NSQL.columnText stmt 0 else pure ""
  NSQL.finalize stmt
  pure value

normalizeReplayTraceJson :: String -> T.Text -> IO Value
normalizeReplayTraceJson label payload =
  case eitherDecodeStrict' (encodeUtf8 payload) of
    Left err -> assertFailure ("Failed to decode replay trace JSON for " <> label <> ": " <> err) >> fail "unreachable"
    Right value -> pure (normalizeReplayTraceValue value)

normalizeReplayTraceValue :: Value -> Value
normalizeReplayTraceValue (Object objectValue) =
  Object
    ( KeyMap.insert "trcSessionId" (String "<normalized-session>")
    $ KeyMap.insert "trcRequestId" (String "<normalized-request>") objectValue
    )
normalizeReplayTraceValue other = other

quickCheckTest :: Testable prop => Int -> String -> prop -> Test
quickCheckTest maxCases label prop = TestCase $ do
  result <- quickCheckWithResult stdArgs { maxSuccess = maxCases } prop
  case result of
    Success{} -> pure ()
    _ -> assertFailure ("QuickCheck failed: " <> label)

fixtureReplayTrace :: T.Text -> Double -> T.Text -> Maybe T.Text -> TurnReplayTrace
fixtureReplayTrace sessionId parserConfidence parserStatus parserDegradationReason =
  TurnReplayTrace
    { trcRequestId = "req_projection_fixture"
    , trcSessionId = sessionId
    , trcRuntimeMode = "strict"
    , trcShadowPolicy = "block_on_unavailable_or_divergence"
    , trcLocalRecoveryPolicy = "enabled"
    , trcRecoveryCause = Just RecoveryShadowDivergence
    , trcRecoveryStrategy = Just StrategyNarrowScope
    , trcRecoveryEvidence = ["shadow_status=diverged"]
    , trcSemanticIntrospectionEnabled = False
    , trcWarnMorphologyFallbackEnabled = False
    , trcRequestedFamily = CMGround
    , trcStrategyFamily = Just CMGround
    , trcNarrativeHint = Nothing
    , trcIntuitionHint = Nothing
    , trcPreShadowFamily = CMGround
    , trcShadowSnapshotId = ShadowSnapshotId "shadow:projection_fixture"
    , trcShadowStatus = ShadowDiverged
    , trcShadowDivergenceKind = ShadowVerdictMismatch
    , trcShadowDivergenceSeverity = ShadowSeverityContract
    , trcShadowResolvedFamily = CMConfront
    , trcFinalFamily = CMGround
    , trcFinalForce = IFAssert
    , trcDecisionDisposition = DispositionRepair
    , trcLegitimacyReason = ReasonShadowDivergence
    , trcParserConfidence = parserConfidence
    , trcParserBackend = "local_rule_based"
    , trcParserStatus = parserStatus
    , trcParserDegradationReason = parserDegradationReason
    , trcParserLatencyMs = 0
    , trcEmbeddingQuality = "heuristic"
    , trcClaimAst = Nothing
    , trcPreSafetyRenderedRaw = "fixture_pre_safety"
    , trcRenderedAfterRebind = "fixture_rendered"
    , trcLinearizationLang = Nothing
    , trcLinearizationOk = False
    , trcFallbackReason = Nothing
    , trcContractProvenance = Just FallbackRoute
    , trcSurfaceProvenance = Just FromFallback
    , trcAuthorityClass = Just AuthorityFallback
    , trcTruthContractStatus = ExplicitFallbackSurface
    , trcAssemblyPath = Just TemplateFallbackRoute
    , trcArtifactManifest = Just (ArtifactManifest Nothing Nothing Nothing Nothing Nothing Nothing "fixture_manifest")
    , trcReplayProvenanceStatus = ReplayProvenanceComplete
    , trcDerivationTags = []
    , trcConatusEnergy = positiveConatus
    , trcConatusGateFired = False
    , trcField = emptyField
    , trcSalienceDriver = "default"
    , trcSalienceHolisticBias = 0.5
    , trcSalienceConfidence = 1.0
    , trcDeliberationRule = Nothing
    , trcDeliberationAgreement = Nothing
    , trcDeliberationDivergence = Nothing
    , trcDeliberationNarrativeTone = Nothing
    , trcEssenceMode = Nothing
    , trcEssenceCommitted = Nothing
    , trcEssenceAngstLevel = Nothing
    , trcEssenceTrigger = Nothing
    , trcLearningQueryType = Nothing
    , trcExternalTool = Nothing
    , trcLearningValidationStatus = Nothing
    , trcLearningSandboxResult = Nothing
    , trcLearningGraftTurn = Nothing
    , trcLearningRejectReason = Nothing
    , trcSenseAnchor = "fixture_anchor"
    , trcSenseOperator = Nothing
    , trcSensePreservedAxes = []
    , trcDialogueFocus = "fixture_focus"
    , trcDialogueFocusBefore = "fixture_focus"
    , trcDialogueFocusAfter = "fixture_focus"
    , trcDialoguePhase = Exploring
    , trcDialoguePhaseBefore = Exploring
    , trcDialoguePhaseAfter = Exploring
    , trcDialogueCommitmentCount = 0
    , trcDialogueCommitmentCountBefore = 0
    , trcDialogueCommitmentCountAfter = 0
    , trcIdentityClaims = []
    , trcMicroPlanMoves = []
    , trcMicroPlanExplicitness = 0.5
    , trcPerspectiveProjection = Nothing
    , trcPerspectiveProjections = []
    , trcResponseSurfaceKind = Nothing
    , trcExternalActionReason = Nothing
    , trcExternalActionNeed = Nothing
    , trcPreActorFailureEvent = Nothing
    , trcDreamPressureDatalogClass = Nothing
    , trcDreamPressureIntuitionClass = Nothing
    , trcDreamPressureAgreement = Nothing
    , trcDreamPressureStrength = Nothing
    , trcDreamPressureCandidateThresholdFired = Nothing
    , trcDreamPressureCandidateKinds = []
    , trcDreamPressureBiasApplied = Nothing
    , trcDreamCandidateLifecycleStatuses = []
    , trcDreamCandidateDecisionReasons = []
    , trcDreamCandidateApplied = Nothing
    , trcEpisodicEncoding = []
    , trcEpisodicRetrieval = Nothing
    , trcEpisodicForgetting = (0, Nothing)
    , trcRegimeVersion = 1
    , trcMorphologyVersion = 0
    , trcFamilyDivergenceActive = False
  , trcSemanticCommitmentCount = 0
  , trcQuarantinedCommitmentCount = 0
  , trcPromotedFromQuarantineCount = 0
   , trcCommitmentStoreDecision = CsaAdmitCanonical
    , trcCommitmentEngaged = 0
    , trcCommitmentContradicted = False
    , trcCommitmentMatchKind = NoMatch
    , trcCommitmentFamilyHint = Nothing
   , trcCognitiveSignals = emptyCognitiveSignals
    , trcDoubtScore = Nothing
    , trcEpisodicRetrievalCount = Nothing
    , trcContentSaliencyDominantCluster = Nothing
    , trcMoodValence = Nothing
    , trcMoodArousal = Nothing
    , trcAffectDecoupled = False
    , trcMood = 0.0
    , trcUserModelTopIntent = Nothing
    , trcUserModelConfidence = Nothing
    , trcDerivedInferenceCount = Nothing
    , trcFamilyDivergenceOccurred = Nothing
    , trcFmarDetectorFamily = Nothing
    , trcFmarFamily = Nothing
    , trcFmarFamiliesMatch = Nothing
    , trcFmarFieldDistance = Nothing
    , trcFmarMode = Nothing
    , trcFamilyDerivationChain = []
    , trcGenerationTrace = []
    , trcEffectSnapshot = Nothing
    , trcEvidenceAdmissibility = EvidenceGoverned
    , trcIntentType = Nothing
    , trcFrameType = Nothing
    , trcContentSource = Nothing
    , trcAnalogicalSource = Nothing
    , trcSubstrateActivated = []
    , trcSubstrateEdgesUsed = 0
    , trcActivationSteps = Seq.empty
    , trcSubstrateHops = 0
    }

authoritativeGovernedState :: SystemState -> SystemState
authoritativeGovernedState ss0 =
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
