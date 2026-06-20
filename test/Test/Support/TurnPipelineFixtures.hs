{-# LANGUAGE OverloadedStrings #-}

module Test.Support.TurnPipelineFixtures
  ( buildPreparedFixture
  , buildPlannedFixture
  , buildRenderedFixture
  , buildFinalizeFixture
  , buildFinalizeFixtureWithState
  , buildRenderedFixtureWithState
  , buildPlannedFixtureWithState
  , buildPreparedFixtureWithState
  , buildAuthoritativePerspectiveFinalizeFixture
  , forceAuthoritativeTurnArtifacts
  , testEpochZero
  , testProtocolPipelineIO
  , testProtocolInterpreter
  , withDeterministicEmbedding
  ) where

import Data.Time.Calendar (Day(ModifiedJulianDay))
import Data.Time.Clock (UTCTime(..))
import qualified Data.Map.Strict as Map
import qualified Data.Text as T

import QxFx0.Core.FMAR (FmarMode(..))
import QxFx0.Types
import QxFx0.Types.Readiness ()
import QxFx0.Core.PipelineIO
  ( PipelineIO
  , TestPipelineConfig(..)
  , defaultTestPipelineConfig
  , mkTestPipelineIO
  , pipelineShadowPolicy
  , pipelineUpdateHistory
  , pipelineParseAuthoritySurface
  )
import QxFx0.Core.TurnPipeline.Protocol
  ( FinalizePrecommitBundle
  , TurnArtifacts(..)
  , TurnInput
  , TurnPlan
  , TurnSignals
  , TurnEffectRequest(..)
  , TurnEffectResult(..)
  , buildFinalizePrecommit
  , buildRouteTurnPlan
  , buildTurnArtifacts
  , buildTurnInput
  , buildTurnSignals
  , planFinalizePrecommit
  , planRenderEffects
  , planPrepareEffects
  , planRouteEffects
  , resolveFinalizePrecommit
  , resolvePrepareEffects
  , resolveRenderEffects
  , resolveRouteEffects
  )
import qualified QxFx0.Core.ConsciousnessLoop as CLoop
import qualified QxFx0.Core.Intuition as Intuition
import qualified QxFx0.Semantic.Embedding as Emb
import QxFx0.Types.Domain.Atoms ()
import QxFx0.Types.ExternalQuery ()
import QxFx0.Types.ShadowDivergence (ShadowSnapshotId(..), emptyShadowDivergence)
import QxFx0.Bridge.ExternalLLM
  ( buildTransportFromConfig
  , defaultExternalQueryConfig
  , queryExternalTool
  )
import Test.Support (withEnvVar)

buildPreparedFixture :: T.Text -> IO (SystemState, TurnInput, TurnSignals)
buildPreparedFixture rawInput = do
  let pio = mkProtocolPipelineIO
  buildPreparedFixtureWithPipeline pio defaultProtocolFixtureState rawInput

buildPlannedFixture :: T.Text -> IO (SystemState, TurnInput, TurnSignals, TurnPlan)
buildPlannedFixture rawInput = do
  let pio = mkProtocolPipelineIO
  (ss, ti, ts) <- buildPreparedFixtureWithPipeline pio defaultProtocolFixtureState rawInput
  let routePlan = planRouteEffects ss ti ts
  routeResults <- resolveRouteEffects pio routePlan
  let tp = buildRouteTurnPlan FmarOff (pipelineShadowPolicy pio) Nothing False ss ti ts routePlan routeResults
  pure (ss, ti, ts, tp)

buildRenderedFixture :: T.Text -> IO (SystemState, TurnInput, TurnSignals, TurnPlan, TurnArtifacts)
buildRenderedFixture rawInput = do
  let pio = mkProtocolPipelineIO
  (ss, ti, ts, tp) <- buildPlannedFixtureWithPipeline pio defaultProtocolFixtureState rawInput
  let renderPlan = planRenderEffects LocalRecoveryEnabled ss ti ts tp
  renderResults <- resolveRenderEffects pio renderPlan
  let ta = buildTurnArtifacts ss ti ts tp renderPlan renderResults
  pure (ss, ti, ts, tp, ta)

buildFinalizeFixture :: T.Text -> IO (SystemState, TurnInput, TurnSignals, TurnPlan, TurnArtifacts, FinalizePrecommitBundle)
buildFinalizeFixture rawInput = do
  let pio = mkProtocolPipelineIO
  (ss, ti, ts, tp, ta) <- buildRenderedFixtureWithPipeline pio defaultProtocolFixtureState rawInput
  let precommitPlan = planFinalizePrecommit ss ti ts tp ta
  precommitResults <- resolveFinalizePrecommit pio precommitPlan
  bundle <-
        buildFinalizePrecommit
          (pipelineUpdateHistory pio)
          (pipelineParseAuthoritySurface pio)
          ss
          ti
          ts
          tp
          ta
          precommitPlan
          precommitResults
  pure (ss, ti, ts, tp, ta, bundle)

buildFinalizeFixtureWithState
  :: SystemState
  -> T.Text
  -> IO (SystemState, TurnInput, TurnSignals, TurnPlan, TurnArtifacts, FinalizePrecommitBundle)
buildFinalizeFixtureWithState startSs rawInput = do
  let pio = mkProtocolPipelineIO
  (ss, ti, ts, tp, ta) <- buildRenderedFixtureWithPipeline pio startSs rawInput
  let precommitPlan = planFinalizePrecommit ss ti ts tp ta
  precommitResults <- resolveFinalizePrecommit pio precommitPlan
  bundle <-
        buildFinalizePrecommit
          (pipelineUpdateHistory pio)
          (pipelineParseAuthoritySurface pio)
          ss
          ti
          ts
          tp
          ta
          precommitPlan
          precommitResults
  pure (ss, ti, ts, tp, ta, bundle)

buildRenderedFixtureWithState
  :: SystemState
  -> T.Text
  -> IO (SystemState, TurnInput, TurnSignals, TurnPlan, TurnArtifacts)
buildRenderedFixtureWithState startSs rawInput = do
  let pio = mkProtocolPipelineIO
  (ss, ti, ts, tp) <- buildPlannedFixtureWithPipeline pio startSs rawInput
  let renderPlan = planRenderEffects LocalRecoveryEnabled ss ti ts tp
  renderResults <- resolveRenderEffects pio renderPlan
  let ta = buildTurnArtifacts ss ti ts tp renderPlan renderResults
  pure (ss, ti, ts, tp, ta)

buildPlannedFixtureWithState
  :: SystemState
  -> T.Text
  -> IO (SystemState, TurnInput, TurnSignals, TurnPlan)
buildPlannedFixtureWithState startSs rawInput = do
  let pio = mkProtocolPipelineIO
  (ss, ti, ts) <- buildPreparedFixtureWithPipeline pio startSs rawInput
  let routePlan = planRouteEffects ss ti ts
  routeResults <- resolveRouteEffects pio routePlan
  let tp = buildRouteTurnPlan FmarOff (pipelineShadowPolicy pio) Nothing False ss ti ts routePlan routeResults
  pure (ss, ti, ts, tp)

buildPreparedFixtureWithState
  :: SystemState
  -> T.Text
  -> IO (SystemState, TurnInput, TurnSignals)
buildPreparedFixtureWithState startSs rawInput = do
  let pio = mkProtocolPipelineIO
  buildPreparedFixtureWithPipeline pio startSs rawInput

buildAuthoritativePerspectiveFinalizeFixture :: SystemState -> T.Text -> IO (FinalizePrecommitBundle, TurnArtifacts)
buildAuthoritativePerspectiveFinalizeFixture startSs rawInput = do
  let pio = mkProtocolPipelineIO
  (ss, ti, ts, tp, ta0) <- buildRenderedFixtureWithPipeline pio startSs rawInput
  let ta = forceAuthoritativeTurnArtifacts ta0
      precommitPlan = planFinalizePrecommit ss ti ts tp ta
  precommitResults <- resolveFinalizePrecommit pio precommitPlan
  bundle <-
        buildFinalizePrecommit
          (pipelineUpdateHistory pio)
          (pipelineParseAuthoritySurface pio)
          ss
          ti
          ts
          tp
          ta
          precommitPlan
          precommitResults
  pure (bundle, ta)

testProtocolPipelineIO :: PipelineIO
testProtocolPipelineIO = mkProtocolPipelineIO

testProtocolInterpreter :: TurnEffectRequest -> IO TurnEffectResult
testProtocolInterpreter request =
  case request of
    TurnReqEmbedding inputText ->
      TurnResEmbedding <$> Emb.textToEmbeddingResult inputText
    TurnReqNixGuard _ _ _ ->
      pure (TurnResNixGuard Allowed)
    TurnReqConsciousness semanticInput humanTheta resonance _conatusEnergy _salienceWeights -> do
      let (loop1, fragment) = CLoop.runConsciousnessLoop CLoop.initialLoop semanticInput humanTheta resonance
      pure (TurnResConsciousness loop1 (CLoop.clLastNarrative loop1) (if T.null fragment then Nothing else Just fragment))
    TurnReqIntuition inputText resonance tension turnNumber _conatusEnergy _salienceWeights _semanticConfig -> do
      let (mFlash, intuitionState) =
            Intuition.checkIntuitionWithInput inputText resonance tension turnNumber Intuition.defaultIntuitiveState
      pure (TurnResIntuition mFlash (Intuition.effectivePosterior intuitionState) intuitionState)
    TurnReqApiHealth ->
      pure (TurnResApiHealth True)
    TurnReqShadow family force _ ->
      pure (TurnResShadow (Just (family, force)) ShadowMatch emptyShadowDivergence (ShadowSnapshotId "shadow:test_protocol") [])
    TurnReqAgdaVerify ->
      pure (TurnResAgdaVerify AgdaVerified)
    TurnReqCurrentTime ->
      pure (TurnResCurrentTime protocolFixedTime)
    TurnReqRequestId ->
      pure (TurnResRequestId "request-id-protocol")
    TurnReqReadEnv _ ->
      pure (TurnResReadEnv Nothing)
    TurnReqTestMarkOnceFile _ ->
      pure (TurnResTestMarkOnceFile False)
    TurnReqSemanticIntrospectionEnv ->
      pure (TurnResSemanticIntrospectionEnv False)
    TurnReqCommitRuntimeState _ _ _ ->
      pure TurnResCommitRuntimeState
    TurnReqSaveState ss _ _ _ ->
      pure (TurnResSaveState (Right ss))
    TurnReqRollbackTurnProjections _ _ ->
      pure (TurnResRollbackTurnProjections (Right ()))
    TurnReqCheckpoint _ ->
      pure TurnResCheckpointCompleted
    TurnReqLinearizeClaimAst _ _ _ ->
      pure (TurnResLinearizeClaimAst (Left "pgf_unavailable_test_protocol"))
    TurnReqLinearizeDialogAtoms _ _ _ ->
      pure (TurnResLinearizeDialogAtoms (Left "pgf_unavailable_test_protocol"))
    TurnReqExternalQuery tool need queryText -> do
      transport <- buildTransportFromConfig explicitMockExternalQueryConfig
      result <- queryExternalTool transport tool need queryText
      pure (TurnResExternalQuery result)

withDeterministicEmbedding :: IO a -> IO a
withDeterministicEmbedding =
  withEnvVar "QXFX0_EMBEDDING_BACKEND" (Just "local-deterministic")
    . withEnvVar "EMBEDDING_API_URL" Nothing

testEpochZero :: UTCTime
testEpochZero = UTCTime (ModifiedJulianDay 0) 0

buildPreparedFixtureWithPipeline :: PipelineIO -> SystemState -> T.Text -> IO (SystemState, TurnInput, TurnSignals)
buildPreparedFixtureWithPipeline pio startSs rawInput = do
  let preparePlan = planPrepareEffects startSs rawInput testEpochZero
  prepareResults <- resolvePrepareEffects pio preparePlan
  let ti = buildTurnInput startSs "request-prop" "session-prop" preparePlan prepareResults
      ts = buildTurnSignals prepareResults
  pure (startSs, ti, ts)

buildPlannedFixtureWithPipeline :: PipelineIO -> SystemState -> T.Text -> IO (SystemState, TurnInput, TurnSignals, TurnPlan)
buildPlannedFixtureWithPipeline pio startSs rawInput = do
  (ss, ti, ts) <- buildPreparedFixtureWithPipeline pio startSs rawInput
  let routePlan = planRouteEffects ss ti ts
  routeResults <- resolveRouteEffects pio routePlan
  let tp = buildRouteTurnPlan FmarOff (pipelineShadowPolicy pio) Nothing False ss ti ts routePlan routeResults
  pure (ss, ti, ts, tp)

buildRenderedFixtureWithPipeline :: PipelineIO -> SystemState -> T.Text -> IO (SystemState, TurnInput, TurnSignals, TurnPlan, TurnArtifacts)
buildRenderedFixtureWithPipeline pio startSs rawInput = do
  (ss, ti, ts, tp) <- buildPlannedFixtureWithPipeline pio startSs rawInput
  let renderPlan = planRenderEffects LocalRecoveryEnabled ss ti ts tp
  renderResults <- resolveRenderEffects pio renderPlan
  let ta = buildTurnArtifacts ss ti ts tp renderPlan renderResults
  pure (ss, ti, ts, tp, ta)

mkProtocolPipelineIO :: PipelineIO
mkProtocolPipelineIO =
  mkTestPipelineIO
    defaultTestPipelineConfig
      { tpcInterpreter = testProtocolInterpreter
      }

defaultProtocolFixtureState :: SystemState
defaultProtocolFixtureState =
  emptySystemState
    { ssSessionId = "fixture-session"
    , ssMorphology = MorphologyData
        (Map.singleton "о" "preposition")
        Map.empty
        Map.empty
        Map.empty
    }

explicitMockExternalQueryConfig :: ExternalQueryConfig
explicitMockExternalQueryConfig =
  defaultExternalQueryConfig
    { eqcTransportMode = "mock"
    , eqcFallbackReason = Just TfrExplicitMock
    }

protocolFixedTime :: UTCTime
protocolFixedTime = UTCTime (ModifiedJulianDay 0) 0

forceAuthoritativeTurnArtifacts :: TurnArtifacts -> TurnArtifacts
forceAuthoritativeTurnArtifacts ta0 =
  let outcome0 = taExecutedOutcome ta0
      outcome = outcome0
        { etoAuthorityClass = AuthorityCanonical
        , etoTruthContractStatus = CanonicalSurfacePreserved
        , etoContractProvenance = BuiltClaim
        , etoSurfaceProvenance = FromDB
        , etoAssemblyPath = DialogueAssemblyRoute
        , etoTransitionWon = True
        }
  in ta0
      { taSurfaceProv = FromDB
      , taContractProv = BuiltClaim
      , taAuthorityClass = AuthorityCanonical
      , taTruthContractStatus = CanonicalSurfacePreserved
      , taAssemblyPath = DialogueAssemblyRoute
      , taExecutedOutcome = outcome
      , taLocalRecoveryCause = Nothing
      , taLocalRecoveryStrategy = Nothing
      , taLocalRecoveryEvidence = []
      }
