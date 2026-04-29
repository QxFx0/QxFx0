{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.TurnPipelineProtocol
  ( turnPipelineProtocolTests
  ) where

import Control.Concurrent (threadDelay)
import Control.Exception (try)
import Control.Monad (foldM, unless)
import Data.Aeson (encode)
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef)
import Data.List (sort)
import Data.Time.Clock (UTCTime(..))
import Data.Time.Calendar (Day(ModifiedJulianDay))
import qualified Data.Text as T
import Test.HUnit hiding (Testable)
import Test.QuickCheck
  ( Result(..)
  , Testable
  , elements
  , forAll
  , ioProperty
  , maxSuccess
  , quickCheckWithResult
  , stdArgs
  )

import QxFx0.Types
import QxFx0.Types.Thresholds (blockedConceptsRetentionLimit, parserLowConfidenceThreshold)
import QxFx0.Core.PipelineIO
  ( PipelineIO
  , PipelineRuntimeMode(..)
  , ShadowPolicy(..)
  , TestPipelineConfig(..)
  , defaultTestPipelineConfig
  , mkTestPipelineIO
  , pipelineShadowPolicy
  , pipelineUpdateHistory
  )
import QxFx0.ExceptionPolicy (QxFx0Exception(..))
import QxFx0.Core.TurnPipeline.Protocol
  ( RoutingDecision(..)
  , TurnArtifacts(..)
  , TurnInput(..)
  , TurnPlan(..)
  , TurnSignals(..)
  , PrepareEffectPlan(..)
  , PrepareEffectRequest(..)
  , PrepareStatic(..)
  , TurnEffectRequest(..)
  , TurnEffectResult(..)
  , RouteEffectPlan(..)
  , RouteEffectRequest(..)
  , RouteStatic(..)
  , RenderEffectPlan(..)
  , LocalRecoveryPlan(..)
  , RenderStatic(..)
  , FinalizeCommitPlan(..)
  , FinalizeCommitResults(..)
  , FinalizePrecommitBundle(..)
  , FinalizePrecommitPlan(..)
  , FinalizePrecommitRequest(..)
  , FinalizeStatic(..)
  , buildFinalizePrecommit
  , buildRouteTurnPlan
  , buildTurnArtifacts
  , buildTurnInput
  , buildTurnSignals
  , planPrepareEffects
  , planFinalizeCommit
  , planFinalizePrecommit
  , planRenderEffects
  , planRenderEffectsForRuntime
  , planRouteEffects
  , resolveFinalizePrecommit
  , resolveFinalizeCommit
  , resolvePrepareEffects
  , resolveRenderEffects
  , resolveRouteEffects
  )
import QxFx0.Core.Observability (PhaseTiming(..), TurnMetrics(..))
import qualified QxFx0.Semantic.Embedding as Emb
import qualified QxFx0.Semantic.Morphology as Morph
import qualified QxFx0.Core.Intuition as Intuition
import qualified QxFx0.Core.ConsciousnessLoop as CLoop
import QxFx0.Types.ShadowDivergence
  ( ShadowSnapshotId(..)
  , ShadowDivergenceSeverity(..)
  , emptyShadowDivergence
  )
import Test.Support (withEnvVar)

turnPipelineProtocolTests :: [Test]
turnPipelineProtocolTests =
  [ testPrepareEffectPlanDeterministicProperty
  , testRouteEffectPlanDeterministicProperty
  , testRenderEffectPlanDeterministicProperty
  , testFinalizePrecommitPlanDeterministicProperty
  , testFinalizeCommitPlanDeterministicProperty
  , testFinalizeCommitRecoversRuntimeStateAfterCommitFailure
  , testFinalizeCommitRollsBackPersistedStateAfterRecoveryFailure
  , testReplayEnvelopeDeterministicProperty
  , testReplayEnvelopeJsonDeterministicProperty
  , testBlockedConceptsRetentionIsBoundedAndDeduplicated
  , testPrepareEffectsResolveConcurrently
  , testPrepareMetricsExposeHonestPhaseNames
  , testRouteEffectsResolveConcurrently
  , testRouteEffectsFailOnAgdaInStrictRuntime
  , testNarrativeHintCannotBypassShadowGate
  , testAdvisoryShadowDivergenceDoesNotTriggerRecovery
  , testOperationalDiagnosticQuestionRendersDirectStatus
  , testOperationalCauseQuestionPreservesGroundDiagnosticFamily
  , testSystemLogicQuestionRendersDirectExplanation
  , testSelfKnowledgeAboutSelfRendersStructuredDescription
  , testSelfKnowledgeAboutUserRendersStructuredBoundary
  , testWorldCauseQuestionRendersGroundedExplanation
  , testWorldCauseSkyQuestionRendersGroundedExplanation
  , testLocationFormationQuestionRendersStructuredExplanation
  , testEverydayPurchaseStatementAvoidsLexicalFallback
  , testEverydayResidenceStatementAvoidsLexicalFallback
  , testAffectiveHelpQuestionUsesContactWithoutLexicalFallback
  , testGreetingSmallTalkUsesContactWithoutDistressFallback
  , testSmallTalkHowLifeUsesContactWithoutDistressFallback
  , testPurposeQuestionUsesObjectTopicWithoutCaseRegression
  , testPurposeQuestionHandsAvoidsBrokenGenitive
  , testPurposeQuestionExistenceAvoidsInfinitiveGenitive
  , testConceptQuestionUsesPrepositionalFallbackCase
  , testComparisonQuestionRendersStructuredDistinction
  , testMisunderstandingReportRendersRepairWithoutLexicalFallback
  , testDialogueInvitationRendersDeepenWithoutLexicalFallback
  , testConceptKnowledgeQuestionRendersDefinitionWithoutLexicalFallback
  , testConceptKnowledgeBeingSmartRendersNaturalFrame
  , testSelfStateQuestionRendersDescriptionWithoutLexicalFallback
  , testGenerativePromptRendersDirectThought
  , testGenerativePromptAnotherThoughtRendersNewThought
  , testGenerativePromptFreshThoughtRendersDistinctSurface
  , testGenerativePromptLogicalQualityRendersLogicalSurface
  , testSelfKnowledgeWhatYouAreRendersStructuredDescription
  , testSelfKnowledgeThoughtCapacityRendersDirectAnswer
  , testSelfKnowledgeCapabilityQuestionRendersCapabilitySurface
  , testSelfKnowledgeHelpQuestionRendersHelpSurface
  , testSelfKnowledgeUserIdentityQuestionRendersBoundarySurface
  , testSystemLogicQuestionWithUtebyaRendersDirectExplanation
  , testSystemIdentityProbeAvoidsReflectFallback
  , testMustRouteNameQuestionUsesDescribe
  , testMustRoutePurposeQuestionUsesPurpose
  , testMustRouteDefineQuestionUsesDefine
  , testMustRouteDistinguishQuestionUsesDistinguish
  , testWorkEnableQuestionUsesOperationalStatusNotUserBoundary
  , testContemplativeTopicRendersDeepenWithoutLexicalFallback
  , testReflectiveAssertionRendersConceptTopicWithoutLexicalFallback
  , testLowLegitimacyUsesLocalRecoveryWithoutExternalCall
  , testRuntimeDegradedUsesVisibleLocalRecovery
  , testParserLowConfidenceUsesDistinguishCandidates
  , testRenderBlockedPersistsSafeRecoveryTrace
  , testFinalizePrecommitResolveConcurrently
  ]

testPrepareEffectPlanDeterministicProperty :: Test
testPrepareEffectPlanDeterministicProperty = quickCheckTest "prepare effect planning is deterministic" $
  forAll (elements prepareInputs) $ \rawInput ->
    let input = T.pack rawInput
        plan1 = summarizePreparePlan (planPrepareEffects emptySystemState input)
        plan2 = summarizePreparePlan (planPrepareEffects emptySystemState input)
    in plan1 == plan2
  where
    prepareInputs =
      [ "что такое свобода"
      , "мне нужен контакт"
      , "я устал и не могу"
      , "где граница между смыслом и пустотой"
      , "что делать дальше"
      ]

    summarizePreparePlan :: PrepareEffectPlan -> (CanonicalMoveFamily, [PrepareEffectRequest])
    summarizePreparePlan plan =
      ( psRecommendedFamily (pepStatic plan)
      , [ pepEmbeddingRequest plan
        , pepNixGuardRequest plan
        , pepConsciousnessRequest plan
        , pepIntuitionRequest plan
        , pepApiHealthRequest plan
        ]
      )

testRouteEffectPlanDeterministicProperty :: Test
testRouteEffectPlanDeterministicProperty = quickCheckTest "route effect planning is deterministic" $
  forAll (elements protocolInputs) $ \rawInput ->
    ioProperty $ do
      (ss, ti, ts) <- withDeterministicEmbedding (buildPreparedFixture (T.pack rawInput))
      let plan1 = summarizeRoutePlan (planRouteEffects ss ti ts)
          plan2 = summarizeRoutePlan (planRouteEffects ss ti ts)
      pure (plan1 == plan2)

testRenderEffectPlanDeterministicProperty :: Test
testRenderEffectPlanDeterministicProperty = quickCheckTest "render effect planning is deterministic" $
  forAll (elements protocolInputs) $ \rawInput ->
    ioProperty $ do
      (ss, ti, ts, tp) <- withDeterministicEmbedding (buildPlannedFixture (T.pack rawInput))
      let plan1 = summarizeRenderPlan (planRenderEffects LocalRecoveryEnabled ss ti ts tp)
          plan2 = summarizeRenderPlan (planRenderEffects LocalRecoveryEnabled ss ti ts tp)
      pure (plan1 == plan2)

testFinalizePrecommitPlanDeterministicProperty :: Test
testFinalizePrecommitPlanDeterministicProperty = quickCheckTest "finalize precommit planning is deterministic" $
  forAll (elements protocolInputs) $ \rawInput ->
    ioProperty $ do
      (ss, ti, ts, tp, ta) <- withDeterministicEmbedding (buildRenderedFixture (T.pack rawInput))
      let plan1 = summarizeFinalizePrecommitPlan (planFinalizePrecommit ss ti ts tp ta)
          plan2 = summarizeFinalizePrecommitPlan (planFinalizePrecommit ss ti ts tp ta)
      pure (plan1 == plan2)

testFinalizeCommitPlanDeterministicProperty :: Test
testFinalizeCommitPlanDeterministicProperty = quickCheckTest "finalize commit planning is deterministic" $
  forAll (elements protocolInputs) $ \rawInput ->
    ioProperty $ do
      (ss, _ti, ts, _tp, ta, bundle) <- withDeterministicEmbedding (buildFinalizeFixture (T.pack rawInput))
      let plan1 = summarizeFinalizeCommitPlan (planFinalizeCommit "session-prop" ss ts ta bundle)
          plan2 = summarizeFinalizeCommitPlan (planFinalizeCommit "session-prop" ss ts ta bundle)
      pure (plan1 == plan2)

testFinalizeCommitRecoversRuntimeStateAfterCommitFailure :: Test
testFinalizeCommitRecoversRuntimeStateAfterCommitFailure = TestCase $
  withDeterministicEmbedding $ do
    commitAttemptsRef <- newIORef 0
    let recoveryPio =
          mkTestPipelineIO
            defaultTestPipelineConfig
              { tpcInterpreter = failingCommitThenRecoverInterpreter commitAttemptsRef
              }
    (ss, _ti, ts, _tp, ta, bundle) <- buildFinalizeFixture "что такое свобода"
    let commitPlan = planFinalizeCommit "session-recovery" ss ts ta bundle
    _ <- resolveFinalizeCommit recoveryPio commitPlan
    attempts <- readIORef commitAttemptsRef
    assertEqual "commit effect should be retried once on recovery path" 2 attempts

testFinalizeCommitRollsBackPersistedStateAfterRecoveryFailure :: Test
testFinalizeCommitRollsBackPersistedStateAfterRecoveryFailure = TestCase $
  withDeterministicEmbedding $ do
    saveRequestsRef <- newIORef ([] :: [(T.Text, Int, Bool)])
    let rollbackPio =
          mkTestPipelineIO
            defaultTestPipelineConfig
              { tpcInterpreter = failingCommitWithRollbackInterpreter saveRequestsRef
              }
    (ss, _ti, ts, _tp, ta, bundle) <- buildFinalizeFixture "что такое свобода"
    let commitPlan = planFinalizeCommit "session-rollback" ss ts ta bundle
    result <- try (resolveFinalizeCommit rollbackPio commitPlan) :: IO (Either QxFx0Exception FinalizeCommitResults)
    case result of
      Left (PersistenceError detail) -> do
        let hasProjectionRollback = "projections rollback=ok" `T.isInfixOf` detail
            hasStateRollback = "state rollback=ok" `T.isInfixOf` detail
        unless (hasProjectionRollback && hasStateRollback) $
          assertFailure ("double-failure path must expose projection and state rollback status, got: " <> T.unpack detail)
      Left other ->
        assertFailure ("unexpected exception while testing rollback path: " <> show other)
      Right _ ->
        assertFailure "commit path must fail when commit and recovery both fail"
    requests <- readIORef saveRequestsRef
    assertEqual
      "double-failure path should save, cleanup persisted projections, then rollback state"
      [ ("save", ssTurnCount (fpbNextSs bundle), True)
      , ("cleanup", ssTurnCount ss, False)
      , ("save", ssTurnCount ss, False)
      ]
      requests

testBlockedConceptsRetentionIsBoundedAndDeduplicated :: Test
testBlockedConceptsRetentionIsBoundedAndDeduplicated = TestCase $
  withDeterministicEmbedding $ do
    (ss0, ti0, ts, tp, ta) <- buildRenderedFixture "что такое свобода"
    let updateState :: SystemState -> T.Text -> IO SystemState
        updateState state blockedReason =
          let tiBlocked = ti0 { tiNixStatus = Blocked blockedReason }
              precommitPlan = planFinalizePrecommit state tiBlocked ts tp ta
          in do
            precommitResults <- resolveFinalizePrecommit testProtocolPipelineIO precommitPlan
            let bundle =
                  buildFinalizePrecommit
                    (pipelineUpdateHistory testProtocolPipelineIO)
                    state
                    tiBlocked
                    ts
                    tp
                    ta
                    precommitPlan
                    precommitResults
            pure (fpbNextSs bundle)
    dedupedState <- foldM updateState ss0 (replicate 10 "same_reason")
    let dedupedReasons = ssBlockedConcepts dedupedState
        uniqueReasons = map (\n -> "reason_" <> T.pack (show n)) [1 .. blockedConceptsRetentionLimit + 15]
    boundedState <- foldM updateState ss0 uniqueReasons
    let boundedReasons = ssBlockedConcepts boundedState
    assertEqual "blocked reasons should deduplicate repeated values" ["same_reason"] dedupedReasons
    assertEqual "blocked reasons list should be capped at retention limit"
      blockedConceptsRetentionLimit
      (length boundedReasons)
    assertEqual "latest blocked reason should stay at the head"
      ("reason_" <> T.pack (show (blockedConceptsRetentionLimit + 15)))
      (head boundedReasons)

testReplayEnvelopeDeterministicProperty :: Test
testReplayEnvelopeDeterministicProperty = quickCheckTest "replay envelope is deterministic for identical inputs" $
  forAll (elements protocolInputs) $ \rawInput ->
    ioProperty $ do
      (_ss1, _ti1, _ts1, _tp1, _ta1, bundle1) <- withDeterministicEmbedding (buildFinalizeFixture (T.pack rawInput))
      (_ss2, _ti2, _ts2, _tp2, _ta2, bundle2) <- withDeterministicEmbedding (buildFinalizeFixture (T.pack rawInput))
      let trace1 = tqpReplayTrace (fpbProjection bundle1)
          trace2 = tqpReplayTrace (fpbProjection bundle2)
      pure (trace1 == trace2)

testReplayEnvelopeJsonDeterministicProperty :: Test
testReplayEnvelopeJsonDeterministicProperty = quickCheckTest "replay envelope JSON is deterministic for identical inputs" $
  forAll (elements protocolInputs) $ \rawInput ->
    ioProperty $ do
      (_ss1, _ti1, _ts1, _tp1, _ta1, bundle1) <- withDeterministicEmbedding (buildFinalizeFixture (T.pack rawInput))
      (_ss2, _ti2, _ts2, _tp2, _ta2, bundle2) <- withDeterministicEmbedding (buildFinalizeFixture (T.pack rawInput))
      let payload1 = encode (tqpReplayTrace (fpbProjection bundle1))
          payload2 = encode (tqpReplayTrace (fpbProjection bundle2))
      pure (payload1 == payload2)

testPrepareEffectsResolveConcurrently :: Test
testPrepareEffectsResolveConcurrently = TestCase $ do
  activeRef <- newIORef 0
  maxRef <- newIORef 0
  let pio =
        mkTestPipelineIO
          defaultTestPipelineConfig
            { tpcInterpreter = trackedPrepareInterpreter activeRef maxRef
            }
      preparePlan = planPrepareEffects emptySystemState "что такое свобода"
  _ <- resolvePrepareEffects pio preparePlan
  maxActive <- readIORef maxRef
  assertBool "prepare effects should overlap instead of running strictly one-by-one" (maxActive >= 3)

testPrepareMetricsExposeHonestPhaseNames :: Test
testPrepareMetricsExposeHonestPhaseNames = TestCase $
  withDeterministicEmbedding $ do
    let ss = emptySystemState
        preparePlan = planPrepareEffects ss "что такое свобода"
    prepareResults <- resolvePrepareEffects testProtocolPipelineIO preparePlan
    let ti = buildTurnInput ss "request-phase" "session-phase" preparePlan prepareResults
        phaseNames = sort (map ptPhase (tmPhases (tiMetrics ti)))
    assertBool "prepare metrics should stop pretending forced bookkeeping is logic" ("logic" `notElem` phaseNames)
    assertEqual
      "prepare metrics should expose the real prepare phase set"
      ["api_health", "consciousness", "embedding", "intuition", "nix_check", "prepare_static"]
      phaseNames

testRouteEffectsResolveConcurrently :: Test
testRouteEffectsResolveConcurrently = TestCase $
  withDeterministicEmbedding $ do
    activeRef <- newIORef 0
    maxRef <- newIORef 0
    let routePio =
          mkTestPipelineIO
            defaultTestPipelineConfig
              { tpcInterpreter = trackedRouteInterpreter activeRef maxRef
              }
    (ss, ti, ts) <- buildPreparedFixture "что такое свобода"
    let routePlan = planRouteEffects ss ti ts
    _ <- resolveRouteEffects routePio routePlan
    maxActive <- readIORef maxRef
    assertBool "route shadow/agda effects should resolve concurrently" (maxActive >= 2)

testRouteEffectsFailOnAgdaInStrictRuntime :: Test
testRouteEffectsFailOnAgdaInStrictRuntime = TestCase $
  withDeterministicEmbedding $ do
    let strictPio =
          mkTestPipelineIO
            defaultTestPipelineConfig
              { tpcRuntimeMode = RuntimeStrict
              , tpcInterpreter = strictAgdaFailInterpreter
              }
    (ss, ti, ts) <- buildPreparedFixture "что такое свобода"
    let routePlan = planRouteEffects ss ti ts
    result <- try (resolveRouteEffects strictPio routePlan >> pure ()) :: IO (Either QxFx0Exception ())
    case result of
      Left (AgdaGateError detail) ->
        assertBool "strict Agda gate should expose typed failing status" ("agda_status=" `T.isPrefixOf` detail)
      Left other ->
        assertFailure ("unexpected exception while testing strict Agda gate: " <> show other)
      Right () ->
        assertFailure "strict runtime must fail route resolution when Agda verification is not ready"

testNarrativeHintCannotBypassShadowGate :: Test
testNarrativeHintCannotBypassShadowGate = TestCase $
  withDeterministicEmbedding $ do
    let strictShadowPio =
          mkTestPipelineIO
            defaultTestPipelineConfig
              { tpcRuntimeMode = RuntimeStrict
              , tpcShadowPolicy = ShadowBlockOnUnavailableOrDivergence
              , tpcInterpreter = strictShadowUnavailableInterpreter
              }
    (ss, ti, ts0) <- buildPreparedFixture "что такое свобода"
    let ts = ts0 { tsNarrativeFragment = Just "narrative_override_attempt" }
        routePlan = planRouteEffects ss ti ts
    routeResults <- resolveRouteEffects strictShadowPio routePlan
    let turnPlan = buildRouteTurnPlan (pipelineShadowPolicy strictShadowPio) ss ti ts routePlan routeResults
        renderPlan = planRenderEffects LocalRecoveryEnabled ss ti ts turnPlan
    renderResults <- resolveRenderEffects strictShadowPio renderPlan
    let turnArtifacts = buildTurnArtifacts ss ti ts turnPlan renderPlan renderResults
        precommitPlan = planFinalizePrecommit ss ti ts turnPlan turnArtifacts
    precommitResults <- resolveFinalizePrecommit strictShadowPio precommitPlan
    let precommitBundle =
          buildFinalizePrecommit
            (pipelineUpdateHistory strictShadowPio)
            ss
            ti
            ts
            turnPlan
            turnArtifacts
            precommitPlan
            precommitResults
        projection = fpbProjection precommitBundle
    assertEqual "shadow unavailable should remain visible in projection" ShadowUnavailable (tqpShadowStatus projection)
    assertEqual "narrative hint must not bypass hard shadow gate" CMRepair (tqpOwnerFamily projection)

testAdvisoryShadowDivergenceDoesNotTriggerRecovery :: Test
testAdvisoryShadowDivergenceDoesNotTriggerRecovery = TestCase $
  withDeterministicEmbedding $ do
    let strictPio =
          mkTestPipelineIO
            defaultTestPipelineConfig
              { tpcRuntimeMode = RuntimeStrict
              , tpcInterpreter = testProtocolInterpreter
              }
    (ss0, ti, ts, tp0) <- buildPlannedFixture "логика это истина бытия?"
    let ss =
          ss0
            { ssMorphology =
                Morph.buildMorphologyData
                  (map Morph.analyzeMorph ["логика", "истина", "бытие"])
            }
    let tp =
          tp0
            { tpFinalFamily = CMReflect
            , tpShadowStatus = ShadowDiverged
            , tpShadowDivergence = True
            , tpShadowDivergenceSeverity = ShadowSeverityAdvisory
            }
        renderPlan = planRenderEffects LocalRecoveryEnabled ss ti ts tp
    assertEqual "advisory shadow divergence must not plan local recovery"
      Nothing
      (repLocalRecoveryPlan renderPlan)
    renderResults <- resolveRenderEffects testProtocolPipelineIO renderPlan
    let turnArtifacts = buildTurnArtifacts ss ti ts tp renderPlan renderResults
    assertEqual "advisory shadow divergence must not surface as local recovery"
      Nothing
      (taLocalRecoveryCause turnArtifacts)
    assertBool "advisory non-repair turn must not leak repair rupture language"
      (not ("Признаю разрыв" `T.isInfixOf` taRendered turnArtifacts))
    let precommitPlan = planFinalizePrecommit ss ti ts tp turnArtifacts
    precommitResults <- resolveFinalizePrecommit strictPio precommitPlan
    let bundle =
          buildFinalizePrecommit
            (pipelineUpdateHistory strictPio)
            ss
            ti
            ts
            tp
            turnArtifacts
            precommitPlan
            precommitResults
        projection = fpbProjection bundle
        replayTrace = tqpReplayTrace projection
    assertEqual "projection should keep the non-repair owner family"
      CMReflect
      (tqpOwnerFamily projection)
    assertEqual "replay trace should persist advisory shadow severity"
      ShadowSeverityAdvisory
      (trcShadowDivergenceSeverity replayTrace)
    assertEqual "advisory shadow divergence must not persist recovery cause"
      Nothing
      (trcRecoveryCause replayTrace)

testOperationalDiagnosticQuestionRendersDirectStatus :: Test
testOperationalDiagnosticQuestionRendersDirectStatus = TestCase $
  withDeterministicEmbedding $ do
    (ss, ti, ts, tp) <- buildPlannedFixture "ты не работаешь?"
    assertEqual "operational status diagnostic should preserve clarifying family" CMClarify (tpFinalFamily tp)
    let renderPlan = planRenderEffects LocalRecoveryEnabled ss ti ts tp
    assertEqual "operational diagnostic question should not plan local recovery" Nothing (repLocalRecoveryPlan renderPlan)
    renderResults <- resolveRenderEffects testProtocolPipelineIO renderPlan
    let turnArtifacts = buildTurnArtifacts ss ti ts tp renderPlan renderResults
        rendered = taRendered turnArtifacts
        lowered = T.toLower rendered
    assertEqual "decision family should stay aligned with the status diagnostic trace" CMClarify (tdFamily (taDecision turnArtifacts))
    assertBool "diagnostic output should state operational status directly" ("я работаю" `T.isInfixOf` lowered)
    assertBool "diagnostic output should not collapse into what-means template" (not ("что значит" `T.isInfixOf` lowered))
    assertBool "diagnostic output should not leak local recovery banner" (not ("локальный режим восстановления" `T.isInfixOf` lowered))
    assertBool "diagnostic output should stay declarative" (not (T.isSuffixOf "?" (T.strip lowered)))

testOperationalCauseQuestionPreservesGroundDiagnosticFamily :: Test
testOperationalCauseQuestionPreservesGroundDiagnosticFamily = TestCase $
  withDeterministicEmbedding $ do
    (ss, ti, ts, tp) <- buildPlannedFixture "почему ты не работаешь?"
    assertEqual "operational cause diagnostic should preserve ground family" CMGround (tpFinalFamily tp)
    let renderPlan = planRenderEffects LocalRecoveryEnabled ss ti ts tp
    assertEqual "operational cause diagnostic should not plan local recovery" Nothing (repLocalRecoveryPlan renderPlan)
    renderResults <- resolveRenderEffects testProtocolPipelineIO renderPlan
    let turnArtifacts = buildTurnArtifacts ss ti ts tp renderPlan renderResults
        rendered = taRendered turnArtifacts
        lowered = T.toLower rendered
    assertEqual "decision family should stay aligned with the cause diagnostic trace" CMGround (tdFamily (taDecision turnArtifacts))
    assertBool "cause diagnostic output should explain routing failure directly" ("проблема сейчас в разборе смысла и маршрутизации" `T.isInfixOf` lowered)
    assertBool "cause diagnostic output should not collapse into what-means template" (not ("что значит" `T.isInfixOf` lowered))
    assertBool "cause diagnostic output should not leak local recovery banner" (not ("локальный режим восстановления" `T.isInfixOf` lowered))

testSystemLogicQuestionRendersDirectExplanation :: Test
testSystemLogicQuestionRendersDirectExplanation = TestCase $
  withDeterministicEmbedding $ do
    (ss, ti, ts, tp) <- buildPlannedFixture "в чём твоя логика?"
    assertEqual "system-logic diagnostic should preserve describe family" CMDescribe (tpFinalFamily tp)
    let renderPlan = planRenderEffects LocalRecoveryEnabled ss ti ts tp
    assertEqual "system-logic question should not plan local recovery" Nothing (repLocalRecoveryPlan renderPlan)
    renderResults <- resolveRenderEffects testProtocolPipelineIO renderPlan
    let turnArtifacts = buildTurnArtifacts ss ti ts tp renderPlan renderResults
        rendered = taRendered turnArtifacts
        lowered = T.toLower rendered
    assertEqual "decision family should stay aligned with the system-logic trace" CMDescribe (tdFamily (taDecision turnArtifacts))
    assertBool "system-logic output should explain the local pipeline directly" ("моя текущая логика локальная" `T.isInfixOf` lowered)
    assertBool "system-logic output should not collapse into what-means template" (not ("что значит" `T.isInfixOf` lowered))
    assertBool "system-logic output should not leak local recovery banner" (not ("локальный режим восстановления" `T.isInfixOf` lowered))
    assertBool "system-logic output should stay declarative" (not (T.isSuffixOf "?" (T.strip lowered)))

testSelfKnowledgeAboutSelfRendersStructuredDescription :: Test
testSelfKnowledgeAboutSelfRendersStructuredDescription = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "что ты знаешь о себе?"
      CMDescribe
      [ "я — локальная система диалога"
      , "свою роль"
      ]

testSelfKnowledgeAboutUserRendersStructuredBoundary :: Test
testSelfKnowledgeAboutUserRendersStructuredBoundary = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "что ты знаешь обо мне?"
      CMDescribe
      [ "о тебе я знаю только то"
      , "текущего разговора"
      ]

testWorldCauseQuestionRendersGroundedExplanation :: Test
testWorldCauseQuestionRendersGroundedExplanation = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "почему солнце светит?"
      CMGround
      [ "если говорить о причине солнца"
      , "внешнем мире"
      ]

testWorldCauseSkyQuestionRendersGroundedExplanation :: Test
testWorldCauseSkyQuestionRendersGroundedExplanation = TestCase $
  withDeterministicEmbedding $ do
    (_ss, _ti, _ts, tp, ta) <- buildRenderedFixture "почему небо голубое?"
    let lowered = T.toLower (taRendered ta)
    assertEqual "sky-cause question should keep ground family" CMGround (tpFinalFamily tp)
    assertBool "sky-cause question should avoid lexical fallback" (not ("что значит" `T.isInfixOf` lowered))
    assertBool "sky-cause question should avoid recovery banner" (not ("локальный режим восстановления" `T.isInfixOf` lowered))
    assertBool "sky-cause question should keep sky concept in output" ("неб" `T.isInfixOf` lowered)

testEverydayPurchaseStatementAvoidsLexicalFallback :: Test
testEverydayPurchaseStatementAvoidsLexicalFallback = TestCase $
  withDeterministicEmbedding $ do
    (_ss, _ti, _ts, tp, ta) <- buildRenderedFixture "я купил дом"
    let lowered = T.toLower (taRendered ta)
    assertBool "purchase statement should avoid reflective fallback family" (tpFinalFamily tp /= CMReflect)
    assertBool "purchase statement should avoid lexical fallback" (not ("что значит" `T.isInfixOf` lowered))
    assertBool "purchase statement should avoid recovery banner" (not ("локальный режим восстановления" `T.isInfixOf` lowered))
    assertBool "purchase statement should use stable prepositional form" ("о доме" `T.isInfixOf` lowered)

testEverydayResidenceStatementAvoidsLexicalFallback :: Test
testEverydayResidenceStatementAvoidsLexicalFallback = TestCase $
  withDeterministicEmbedding $ do
    (_ss, _ti, _ts, tp, ta) <- buildRenderedFixture "я живу дома"
    let lowered = T.toLower (taRendered ta)
    assertBool "residence statement should avoid reflective fallback family" (tpFinalFamily tp /= CMReflect)
    assertBool "residence statement should avoid lexical fallback" (not ("что значит" `T.isInfixOf` lowered))
    assertBool "residence statement should avoid recovery banner" (not ("локальный режим восстановления" `T.isInfixOf` lowered))
    assertBool "residence statement should use stable prepositional form" ("о доме" `T.isInfixOf` lowered)

testAffectiveHelpQuestionUsesContactWithoutLexicalFallback :: Test
testAffectiveHelpQuestionUsesContactWithoutLexicalFallback = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "что делать если грустно?"
      CMContact
      [ "нужна опора"
      , "\"грустно\""
      , "один короткий шаг"
      ]

testGreetingSmallTalkUsesContactWithoutDistressFallback :: Test
testGreetingSmallTalkUsesContactWithoutDistressFallback = TestCase $
  withDeterministicEmbedding $ do
    (_ss, _ti, _ts, tp, ta) <- buildRenderedFixture "привет"
    let lowered = T.toLower (taRendered ta)
    assertEqual "greeting should keep contact family" CMContact (tpFinalFamily tp)
    assertBool "greeting should avoid distress framing" (not ("нужна опора" `T.isInfixOf` lowered))
    assertBool "greeting should avoid tension-step framing" (not ("точку напряжения" `T.isInfixOf` lowered))
    assertBool "greeting should keep healthy contact response" ("на связи" `T.isInfixOf` lowered)

testSmallTalkHowLifeUsesContactWithoutDistressFallback :: Test
testSmallTalkHowLifeUsesContactWithoutDistressFallback = TestCase $
  withDeterministicEmbedding $ do
    (_ss, _ti, _ts, tp, ta) <- buildRenderedFixture "как жизнь?"
    let lowered = T.toLower (taRendered ta)
    assertEqual "small-talk life question should keep contact family" CMContact (tpFinalFamily tp)
    assertBool "small-talk should avoid distress framing" (not ("нужна опора" `T.isInfixOf` lowered))
    assertBool "small-talk should keep healthy contact response" ("на связи" `T.isInfixOf` lowered)

testPurposeQuestionUsesObjectTopicWithoutCaseRegression :: Test
testPurposeQuestionUsesObjectTopicWithoutCaseRegression = TestCase $
  withDeterministicEmbedding $ do
    (_ss, _ti, _ts, tp, ta) <- buildRenderedFixture "в чём функция стола?"
    let lowered = T.toLower (taRendered ta)
    assertEqual "purpose question should stay in purpose family" CMPurpose (tpFinalFamily tp)
    assertBool "purpose question should keep object in genitive form" ("функции стола" `T.isInfixOf` lowered)
    assertBool "purpose question should avoid broken genitive fallback" (not ("функции стол " `T.isInfixOf` lowered))

testPurposeQuestionHandsAvoidsBrokenGenitive :: Test
testPurposeQuestionHandsAvoidsBrokenGenitive = TestCase $
  withDeterministicEmbedding $ do
    (_ss, _ti, _ts, tp, ta) <- buildRenderedFixture "зачем человеку руки?"
    let lowered = T.toLower (taRendered ta)
    assertEqual "hands purpose question should stay in purpose family" CMPurpose (tpFinalFamily tp)
    assertBool "hands purpose question should avoid broken suffix -а artifact"
      (not ("рукиа" `T.isInfixOf` lowered))

testPurposeQuestionExistenceAvoidsInfinitiveGenitive :: Test
testPurposeQuestionExistenceAvoidsInfinitiveGenitive = TestCase $
  withDeterministicEmbedding $ do
    (_ss, _ti, _ts, tp, ta) <- buildRenderedFixture "зачем ты есть?"
    let lowered = T.toLower (taRendered ta)
    assertEqual "existence purpose question should stay in purpose family" CMPurpose (tpFinalFamily tp)
    assertBool "existence purpose question should avoid broken infinitive genitive"
      (not ("быти" `T.isInfixOf` lowered))

testConceptQuestionUsesPrepositionalFallbackCase :: Test
testConceptQuestionUsesPrepositionalFallbackCase = TestCase $
  withDeterministicEmbedding $ do
    (_ss, _ti, _ts, tp, ta) <- buildRenderedFixture "что такое осень?"
    let lowered = T.toLower (taRendered ta)
    assertEqual "concept question should stay in define family" CMDefine (tpFinalFamily tp)
    assertBool "concept question should keep prepositional case for topic"
      ("о осени" `T.isInfixOf` lowered || "об осени" `T.isInfixOf` lowered)
    assertBool "concept question should avoid broken prepositional fallback" (not ("о осень" `T.isInfixOf` lowered))
    assertBool "concept question should carry claim AST into turn artifacts" (taClaimAst ta /= Nothing)
    assertBool "concept question should mark successful AST linearization" (taLinearizationOk ta)

testLocationFormationQuestionRendersStructuredExplanation :: Test
testLocationFormationQuestionRendersStructuredExplanation = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "где формируется мысль?"
      CMGround
      [ "если говорить о мысли"
      , "структуре связей"
      ]

testComparisonQuestionRendersStructuredDistinction :: Test
testComparisonQuestionRendersStructuredDistinction = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "стол на стуле. или стул на столе. что логичнее?"
      CMDistinguish
      [ "если речь о бытовой устойчивости"
      , "стул на столе"
      ]

testMisunderstandingReportRendersRepairWithoutLexicalFallback :: Test
testMisunderstandingReportRendersRepairWithoutLexicalFallback = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "я не понимаю тебя"
      CMRepair
      [ "сигнал сбоя взаимопонимания"
      , "в смысле, тоне или ходе рассуждения"
      ]

testDialogueInvitationRendersDeepenWithoutLexicalFallback :: Test
testDialogueInvitationRendersDeepenWithoutLexicalFallback = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "поговорим о логике?"
      CMDeepen
      [ "да, поговорим о логике"
      , "не потерять фокус"
      ]

testConceptKnowledgeQuestionRendersDefinitionWithoutLexicalFallback :: Test
testConceptKnowledgeQuestionRendersDefinitionWithoutLexicalFallback = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "знаешь что такое солнце?"
      CMDefine
      [ "солнце — это звезда"
      , "внешнего мира"
      ]

testConceptKnowledgeBeingSmartRendersNaturalFrame :: Test
testConceptKnowledgeBeingSmartRendersNaturalFrame = TestCase $
  withDeterministicEmbedding $ do
    (ss, ti, ts, tp) <- buildPlannedFixture "что значит быть умным?"
    assertEqual "being-smart concept question should preserve define family" CMDefine (tpFinalFamily tp)
    let renderPlan = planRenderEffects LocalRecoveryEnabled ss ti ts tp
    renderResults <- resolveRenderEffects testProtocolPipelineIO renderPlan
    let turnArtifacts = buildTurnArtifacts ss ti ts tp renderPlan renderResults
        rendered = T.toLower (taRendered turnArtifacts)
    assertBool "being-smart question should render the full phrase naturally"
      ("что значит быть умным" `T.isInfixOf` rendered)
    assertBool "being-smart question should not produce broken prepositional grammar"
      (not ("о умным" `T.isInfixOf` rendered))

testSelfStateQuestionRendersDescriptionWithoutLexicalFallback :: Test
testSelfStateQuestionRendersDescriptionWithoutLexicalFallback = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "о чём ты думаешь?"
      CMDescribe
      [ "мой внутренний ход"
      , "текущего состояния диалога"
      ]

testGenerativePromptRendersDirectThought :: Test
testGenerativePromptRendersDirectThought = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "скажи любую мысль"
      CMDescribe
      [ "одна мысль"
      , "связи"
      ]

testGenerativePromptAnotherThoughtRendersNewThought :: Test
testGenerativePromptAnotherThoughtRendersNewThought = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "а еще одну интересную мысль?"
      CMDescribe
      [ "другая мысль"
      , "удержать различие"
      ]

testGenerativePromptFreshThoughtRendersDistinctSurface :: Test
testGenerativePromptFreshThoughtRendersDistinctSurface = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "скажи новую интересную мысль"
      CMDescribe
      [ "новая мысль"
      , "менять собственную рамку"
      ]

testGenerativePromptLogicalQualityRendersLogicalSurface :: Test
testGenerativePromptLogicalQualityRendersLogicalSurface = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "скажи что-то логичное"
      CMDescribe
      [ "логичная мысль"
      , "посылками и выводом"
      ]

testSelfKnowledgeWhatYouAreRendersStructuredDescription :: Test
testSelfKnowledgeWhatYouAreRendersStructuredDescription = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "чем ты являешься?"
      CMDescribe
      [ "я — локальная система диалога"
      , "типизированный разбор"
      ]

testSelfKnowledgeThoughtCapacityRendersDirectAnswer :: Test
testSelfKnowledgeThoughtCapacityRendersDirectAnswer = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "у тебя всего одна интересная мысль?"
      CMDescribe
      [ "нет, не одна"
      , "генеративный слой"
      ]

testSelfKnowledgeCapabilityQuestionRendersCapabilitySurface :: Test
testSelfKnowledgeCapabilityQuestionRendersCapabilitySurface = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "ты умеешь обобщать?"
      CMDescribe
      [ "могу работать с обобщением"
      , "локальный разбор"
      ]

testSelfKnowledgeHelpQuestionRendersHelpSurface :: Test
testSelfKnowledgeHelpQuestionRendersHelpSurface = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "ты можешь мне помочь?"
      CMDescribe
      [ "да, я могу помочь"
      , "локальную рамку"
      ]

testSelfKnowledgeUserIdentityQuestionRendersBoundarySurface :: Test
testSelfKnowledgeUserIdentityQuestionRendersBoundarySurface = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "кто я такой?"
      CMDescribe
      [ "о тебе я знаю только то"
      , "вне текущего разговора"
      ]

testSystemLogicQuestionWithUtebyaRendersDirectExplanation :: Test
testSystemLogicQuestionWithUtebyaRendersDirectExplanation = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "у тебя есть логика?"
      CMDescribe
      [ "логика локальная"
      , "выборе семьи"
      ]

testSystemIdentityProbeAvoidsReflectFallback :: Test
testSystemIdentityProbeAvoidsReflectFallback = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "ты промт машина?"
      CMDescribe
      [ "локальная система диалога"
      , "текущей сессии"
      ]

testMustRouteNameQuestionUsesDescribe :: Test
testMustRouteNameQuestionUsesDescribe = TestCase $
  withDeterministicEmbedding $ do
    (_ss, _ti, _ts, tp, ta) <- buildRenderedFixture "как тебя зовут?"
    let lowered = T.toLower (taRendered ta)
    assertEqual "name question must route to CMDescribe" CMDescribe (tpFinalFamily tp)
    assertBool "name question should avoid reflect fallback marker" (not ("смысловая точка:" `T.isInfixOf` lowered))

testMustRoutePurposeQuestionUsesPurpose :: Test
testMustRoutePurposeQuestionUsesPurpose = TestCase $
  withDeterministicEmbedding $ do
    (_ss, _ti, _ts, tp, ta) <- buildRenderedFixture "зачем ты тут?"
    let lowered = T.toLower (taRendered ta)
    assertEqual "purpose question must route to CMPurpose" CMPurpose (tpFinalFamily tp)
    assertBool "purpose question should keep purpose framing" ("функц" `T.isInfixOf` lowered)

testMustRouteDefineQuestionUsesDefine :: Test
testMustRouteDefineQuestionUsesDefine = TestCase $
  withDeterministicEmbedding $ do
    (_ss, _ti, _ts, tp, ta) <- buildRenderedFixture "что такое логика?"
    let lowered = T.toLower (taRendered ta)
    assertEqual "define question must route to CMDefine" CMDefine (tpFinalFamily tp)
    assertBool "define question should keep define framing" ("определ" `T.isInfixOf` lowered || "является" `T.isInfixOf` lowered)

testMustRouteDistinguishQuestionUsesDistinguish :: Test
testMustRouteDistinguishQuestionUsesDistinguish = TestCase $
  withDeterministicEmbedding $ do
    (_ss, _ti, _ts, tp, ta) <- buildRenderedFixture "как отличить ложь от правды?"
    let lowered = T.toLower (taRendered ta)
    assertEqual "distinguish question must route to CMDistinguish" CMDistinguish (tpFinalFamily tp)
    assertBool "distinguish question should keep both entities in rendered answer"
      ("лож" `T.isInfixOf` lowered && "правд" `T.isInfixOf` lowered)

testWorkEnableQuestionUsesOperationalStatusNotUserBoundary :: Test
testWorkEnableQuestionUsesOperationalStatusNotUserBoundary = TestCase $
  withDeterministicEmbedding $ do
    (_ss, _ti, _ts, tp, ta) <- buildRenderedFixture "что мне сделать, чтобы ты работал?"
    let lowered = T.toLower (taRendered ta)
    assertBool "work-enable question should not collapse into user-boundary self-knowledge surface"
      (not ("о тебе я знаю только то" `T.isInfixOf` lowered))
    assertBool "work-enable question should return operational status framing"
      ("я работаю" `T.isInfixOf` lowered)
    assertBool "work-enable question should not be CMDescribe after self-knowledge misroute"
      (tpFinalFamily tp /= CMDescribe)

testContemplativeTopicRendersDeepenWithoutLexicalFallback :: Test
testContemplativeTopicRendersDeepenWithoutLexicalFallback = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "тишина"
      CMDeepen
      [ "если держаться слова"
      , "поле смыслов"
      ]

testReflectiveAssertionRendersConceptTopicWithoutLexicalFallback :: Test
testReflectiveAssertionRendersConceptTopicWithoutLexicalFallback = TestCase $
  withDeterministicEmbedding $
    assertStructuredTurn
      "я думаю, что важно сохранять свою субъектность"
      CMDeepen
      [ "субъектность"
      , "поле смыслов"
      ]

testLowLegitimacyUsesLocalRecoveryWithoutExternalCall :: Test
testLowLegitimacyUsesLocalRecoveryWithoutExternalCall = TestCase $
  withDeterministicEmbedding $ do
    (ss, ti, ts, tp0) <- buildPlannedFixture "неясный запрос без устойчивой рамки"
    let tp =
          tp0
            { tpLegitScore = 0.0
            , tpShadowStatus = ShadowMatch
            , tpShadowDivergence = False
            }
        renderPlan = planRenderEffects LocalRecoveryEnabled ss ti ts tp
    case repLocalRecoveryPlan renderPlan of
      Nothing ->
        assertFailure "low legitimacy must produce a local recovery plan"
      Just recoveryPlan -> do
        assertEqual "low legitimacy should be typed as local recovery cause"
          RecoveryLowLegitimacy
          (lrpCause recoveryPlan)
        assertEqual "low legitimacy should expose uncertainty locally"
          StrategyExposeUncertainty
          (lrpStrategy recoveryPlan)
    renderResults <- resolveRenderEffects testProtocolPipelineIO renderPlan
    let turnArtifacts = buildTurnArtifacts ss ti ts tp renderPlan renderResults
    assertBool "local recovery turn must still produce non-empty output"
      (not (T.null (T.strip (taRendered turnArtifacts))))
    assertEqual "artifact must carry recovery cause into replay envelope"
      (Just RecoveryLowLegitimacy)
      (taLocalRecoveryCause turnArtifacts)

testRuntimeDegradedUsesVisibleLocalRecovery :: Test
testRuntimeDegradedUsesVisibleLocalRecovery = TestCase $
  withDeterministicEmbedding $ do
    (ss, ti0, ts, tp0) <- buildPlannedFixture "что такое свобода"
    let ti = ti0 { tiBestTopic = "" }
    let tp =
          tp0
            { tpShadowStatus = ShadowMatch
            , tpShadowDivergence = False
            }
        renderPlan =
          planRenderEffectsForRuntime RuntimeDegraded LocalRecoveryEnabled ss ti ts tp
    case repLocalRecoveryPlan renderPlan of
      Nothing ->
        assertFailure "degraded runtime must expose a visible local recovery plan"
      Just recoveryPlan -> do
        assertEqual "degraded runtime should be typed as local recovery cause"
          RecoveryRuntimeDegraded
          (lrpCause recoveryPlan)
        assertEqual "degraded runtime should narrow scope explicitly"
          StrategyNarrowScope
          (lrpStrategy recoveryPlan)
    renderResults <- resolveRenderEffects testProtocolPipelineIO renderPlan
    let turnArtifacts = buildTurnArtifacts ss ti ts tp renderPlan renderResults
    assertEqual "degraded runtime local recovery cause should propagate to artifacts"
      (Just RecoveryRuntimeDegraded)
      (taLocalRecoveryCause turnArtifacts)
    assertBool "degraded runtime output should include local recovery surface"
      ("Локальный режим восстановления." `T.isInfixOf` taRendered turnArtifacts)
    let precommitPlan = planFinalizePrecommit ss ti ts tp turnArtifacts
    precommitResults <- resolveFinalizePrecommit testProtocolPipelineIO precommitPlan
    let bundle =
          buildFinalizePrecommit
            (pipelineUpdateHistory testProtocolPipelineIO)
            ss
            ti
            ts
            tp
            turnArtifacts
            precommitPlan
            precommitResults
        replayTrace = tqpReplayTrace (fpbProjection bundle)
    assertEqual "degraded runtime replay trace should keep typed recovery cause"
      (Just RecoveryRuntimeDegraded)
      (trcRecoveryCause replayTrace)
    assertEqual "degraded runtime replay trace should keep typed recovery strategy"
      (Just StrategyNarrowScope)
      (trcRecoveryStrategy replayTrace)

testParserLowConfidenceUsesDistinguishCandidates :: Test
testParserLowConfidenceUsesDistinguishCandidates = TestCase $
  withDeterministicEmbedding $ do
    (ss, ti0, ts, tp0) <- buildPlannedFixture "свобода или ответственность"
    let frame =
          (tiFrame ti0)
            { ipfRawText = "свобода или ответственность"
            , ipfCanonicalFamily = CMClarify
            , ipfConfidence = parserLowConfidenceThreshold / 2.0
            }
        ti =
          ti0
            { tiFrame = frame
            , tiRecommendedFamily = CMDescribe
            }
        tp =
          tp0
            { tpPreShadowFamily = CMGround
            , tpFinalFamily = CMDescribe
            , tpStrategyFamily = Just CMDistinguish
            , tpShadowStatus = ShadowMatch
            , tpShadowDivergence = False
            }
        renderPlan = planRenderEffects LocalRecoveryEnabled ss ti ts tp
    case repLocalRecoveryPlan renderPlan of
      Nothing ->
        assertFailure "low parser confidence with competing candidates must produce local recovery"
      Just recoveryPlan -> do
        assertEqual "parser branch should stay typed as parser low confidence"
          RecoveryParserLowConfidence
          (lrpCause recoveryPlan)
        assertEqual "parser ambiguity should use distinguish-candidates strategy"
          StrategyDistinguishCandidates
          (lrpStrategy recoveryPlan)
        assertBool "recovery evidence should include candidate family set"
          (any ("candidate_families=" `T.isPrefixOf`) (lrpEvidence recoveryPlan))

testRenderBlockedPersistsSafeRecoveryTrace :: Test
testRenderBlockedPersistsSafeRecoveryTrace = TestCase $
  withDeterministicEmbedding $ do
    (ss, ti, ts, tp) <- buildPlannedFixture "что такое свобода"
    let renderPlan0 = planRenderEffects LocalRecoveryEnabled ss ti ts tp
        renderStatic0 = repRenderStatic renderPlan0
        renderPlan =
          renderPlan0
            { repRenderStatic =
                renderStatic0
                  { rsRenderWithBg = "phase 0"
                  }
            }
    renderResults <- resolveRenderEffects testProtocolPipelineIO renderPlan
    let turnArtifacts = buildTurnArtifacts ss ti ts tp renderPlan renderResults
    assertEqual "blocked render should switch to recovery provenance"
      FromRecovery
      (taSurfaceProv turnArtifacts)
    assertEqual "blocked render should be typed as render-blocked recovery"
      (Just RecoveryRenderBlocked)
      (taLocalRecoveryCause turnArtifacts)
    assertEqual "blocked render should persist safe-recovery strategy"
      (Just StrategySafeRecovery)
      (taLocalRecoveryStrategy turnArtifacts)
    assertBool "safe recovery output should be non-empty"
      (not (T.null (T.strip (taRendered turnArtifacts))))
    let precommitPlan = planFinalizePrecommit ss ti ts tp turnArtifacts
    precommitResults <- resolveFinalizePrecommit testProtocolPipelineIO precommitPlan
    let bundle =
          buildFinalizePrecommit
            (pipelineUpdateHistory testProtocolPipelineIO)
            ss
            ti
            ts
            tp
            turnArtifacts
            precommitPlan
            precommitResults
        replayTrace = tqpReplayTrace (fpbProjection bundle)
    assertEqual "render-blocked replay trace should keep typed recovery cause"
      (Just RecoveryRenderBlocked)
      (trcRecoveryCause replayTrace)
    assertEqual "render-blocked replay trace should keep safe-recovery strategy"
      (Just StrategySafeRecovery)
      (trcRecoveryStrategy replayTrace)

testFinalizePrecommitResolveConcurrently :: Test
testFinalizePrecommitResolveConcurrently = TestCase $
  withDeterministicEmbedding $ do
    activeRef <- newIORef 0
    maxRef <- newIORef 0
    let precommitPio =
          mkTestPipelineIO
            defaultTestPipelineConfig
              { tpcInterpreter = trackedFinalizePrecommitInterpreter activeRef maxRef
              }
    (ss, ti, ts, tp, ta) <- buildRenderedFixture "что такое свобода"
    let precommitPlan = planFinalizePrecommit ss ti ts tp ta
    _ <- resolveFinalizePrecommit precommitPio precommitPlan
    maxActive <- readIORef maxRef
    assertBool "finalize precommit effects should resolve concurrently" (maxActive >= 2)

protocolInputs :: [String]
protocolInputs =
  [ "что такое свобода"
  , "мне нужен контакт"
  , "я устал и не могу"
  , "где граница между смыслом и пустотой"
  , "что делать дальше"
  ]

testProtocolPipelineIO :: PipelineIO
testProtocolPipelineIO =
  mkTestPipelineIO
    defaultTestPipelineConfig
      { tpcInterpreter = testProtocolInterpreter
      }

testProtocolInterpreter :: TurnEffectRequest -> IO TurnEffectResult
testProtocolInterpreter request =
  case request of
    TurnReqEmbedding inputText ->
      TurnResEmbedding <$> Emb.textToEmbeddingResult (T.unpack inputText)
    TurnReqNixGuard _ _ _ ->
      pure (TurnResNixGuard Allowed)
    TurnReqConsciousness semanticInput humanTheta resonance -> do
      let (loop1, fragment) = CLoop.runConsciousnessLoop CLoop.initialLoop semanticInput humanTheta resonance
      pure (TurnResConsciousness loop1 (CLoop.clLastNarrative loop1) (if T.null fragment then Nothing else Just fragment))
    TurnReqIntuition resonance tension turnNumber -> do
      let (mFlash, intuitionState) = Intuition.checkIntuition resonance tension turnNumber Intuition.defaultIntuitiveState
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
    TurnReqSaveState ss _ _ ->
      pure (TurnResSaveState (Right ss))
    TurnReqRollbackTurnProjections _ _ ->
      pure (TurnResRollbackTurnProjections (Right ()))
    TurnReqCheckpoint _ ->
      pure TurnResCheckpointCompleted
    TurnReqLinearizeClaimAst _ _ ->
      pure (TurnResLinearizeClaimAst (Left "pgf_unavailable_test_protocol"))

protocolFixedTime :: UTCTime
protocolFixedTime = UTCTime (ModifiedJulianDay 0) 0

trackedPrepareInterpreter :: IORef Int -> IORef Int -> TurnEffectRequest -> IO TurnEffectResult
trackedPrepareInterpreter activeRef maxRef request =
  case request of
    TurnReqEmbedding _ ->
      trackConcurrentEffect activeRef maxRef (testProtocolInterpreter request)
    TurnReqNixGuard _ _ _ ->
      trackConcurrentEffect activeRef maxRef (testProtocolInterpreter request)
    TurnReqConsciousness _ _ _ ->
      trackConcurrentEffect activeRef maxRef (testProtocolInterpreter request)
    TurnReqIntuition _ _ _ ->
      trackConcurrentEffect activeRef maxRef (testProtocolInterpreter request)
    TurnReqApiHealth ->
      trackConcurrentEffect activeRef maxRef (testProtocolInterpreter request)
    _ ->
      testProtocolInterpreter request

trackedRouteInterpreter :: IORef Int -> IORef Int -> TurnEffectRequest -> IO TurnEffectResult
trackedRouteInterpreter activeRef maxRef request =
  case request of
    TurnReqShadow _ _ _ ->
      trackConcurrentEffect activeRef maxRef (testProtocolInterpreter request)
    TurnReqAgdaVerify ->
      trackConcurrentEffect activeRef maxRef (testProtocolInterpreter request)
    _ ->
      testProtocolInterpreter request

strictAgdaFailInterpreter :: TurnEffectRequest -> IO TurnEffectResult
strictAgdaFailInterpreter request =
  case request of
    TurnReqAgdaVerify ->
      pure (TurnResAgdaVerify AgdaMissingWitness)
    _ ->
      testProtocolInterpreter request

strictShadowUnavailableInterpreter :: TurnEffectRequest -> IO TurnEffectResult
strictShadowUnavailableInterpreter request =
  case request of
    TurnReqShadow _ _ _ ->
      pure
        (TurnResShadow
          Nothing
          ShadowUnavailable
          emptyShadowDivergence
          (ShadowSnapshotId "shadow:test_unavailable")
          ["shadow_unavailable_test"])
    TurnReqAgdaVerify ->
      pure (TurnResAgdaVerify AgdaVerified)
    _ ->
      testProtocolInterpreter request

trackedFinalizePrecommitInterpreter :: IORef Int -> IORef Int -> TurnEffectRequest -> IO TurnEffectResult
trackedFinalizePrecommitInterpreter activeRef maxRef request =
  case request of
    TurnReqCurrentTime ->
      trackConcurrentEffect activeRef maxRef (testProtocolInterpreter request)
    TurnReqSemanticIntrospectionEnv ->
      trackConcurrentEffect activeRef maxRef (testProtocolInterpreter request)
    _ ->
      testProtocolInterpreter request

failingCommitThenRecoverInterpreter :: IORef Int -> TurnEffectRequest -> IO TurnEffectResult
failingCommitThenRecoverInterpreter attemptsRef request =
  case request of
    TurnReqCommitRuntimeState _ _ _ -> do
      attempt <- atomicModifyIORef' attemptsRef $ \n ->
        let next = n + 1
        in (next, next)
      if attempt == 1
        then ioError (userError "forced_commit_runtime_failure_once")
        else pure TurnResCommitRuntimeState
    _ ->
      testProtocolInterpreter request

failingCommitWithRollbackInterpreter :: IORef [(T.Text, Int, Bool)] -> TurnEffectRequest -> IO TurnEffectResult
failingCommitWithRollbackInterpreter saveRequestsRef request =
  case request of
    TurnReqCommitRuntimeState _ _ _ ->
      ioError (userError "forced_commit_runtime_failure_always")
    TurnReqSaveState ss _ mProjection -> do
      atomicModifyIORef' saveRequestsRef $ \items ->
        (items <> [("save", ssTurnCount ss, maybe False (const True) mProjection)], ())
      pure (TurnResSaveState (Right ss))
    TurnReqRollbackTurnProjections _ stableTurn -> do
      atomicModifyIORef' saveRequestsRef $ \items ->
        (items <> [("cleanup", stableTurn, False)], ())
      pure (TurnResRollbackTurnProjections (Right ()))
    _ ->
      testProtocolInterpreter request

trackConcurrentEffect :: IORef Int -> IORef Int -> IO a -> IO a
trackConcurrentEffect activeRef maxRef action = do
  activeNow <- atomicModifyIORef' activeRef $ \active ->
    let next = active + 1
    in (next, next)
  atomicModifyIORef' maxRef $ \currentMax ->
    (max currentMax activeNow, ())
  threadDelay 50000
  result <- action
  atomicModifyIORef' activeRef $ \active -> (active - 1, ())
  pure result

buildPreparedFixture :: T.Text -> IO (SystemState, TurnInput, TurnSignals)
buildPreparedFixture rawInput = do
  let ss = emptySystemState
      preparePlan = planPrepareEffects ss rawInput
  prepareResults <- resolvePrepareEffects testProtocolPipelineIO preparePlan
  let ti = buildTurnInput ss "request-prop" "session-prop" preparePlan prepareResults
      ts = buildTurnSignals prepareResults
  pure (ss, ti, ts)

buildPlannedFixture :: T.Text -> IO (SystemState, TurnInput, TurnSignals, TurnPlan)
buildPlannedFixture rawInput = do
  (ss, ti, ts) <- buildPreparedFixture rawInput
  let routePlan = planRouteEffects ss ti ts
  routeResults <- resolveRouteEffects testProtocolPipelineIO routePlan
  let tp = buildRouteTurnPlan (pipelineShadowPolicy testProtocolPipelineIO) ss ti ts routePlan routeResults
  pure (ss, ti, ts, tp)

buildRenderedFixture :: T.Text -> IO (SystemState, TurnInput, TurnSignals, TurnPlan, TurnArtifacts)
buildRenderedFixture rawInput = do
  (ss, ti, ts, tp) <- buildPlannedFixture rawInput
  let renderPlan = planRenderEffects LocalRecoveryEnabled ss ti ts tp
  renderResults <- resolveRenderEffects testProtocolPipelineIO renderPlan
  let ta = buildTurnArtifacts ss ti ts tp renderPlan renderResults
  pure (ss, ti, ts, tp, ta)

buildFinalizeFixture :: T.Text -> IO (SystemState, TurnInput, TurnSignals, TurnPlan, TurnArtifacts, FinalizePrecommitBundle)
buildFinalizeFixture rawInput = do
  (ss, ti, ts, tp, ta) <- buildRenderedFixture rawInput
  let precommitPlan = planFinalizePrecommit ss ti ts tp ta
  precommitResults <- resolveFinalizePrecommit testProtocolPipelineIO precommitPlan
  let bundle =
        buildFinalizePrecommit
          (pipelineUpdateHistory testProtocolPipelineIO)
          ss
          ti
          ts
          tp
          ta
          precommitPlan
          precommitResults
  pure (ss, ti, ts, tp, ta, bundle)

withDeterministicEmbedding :: IO a -> IO a
withDeterministicEmbedding =
  withEnvVar "QXFX0_EMBEDDING_BACKEND" (Just "local-deterministic")
    . withEnvVar "EMBEDDING_API_URL" Nothing

assertStructuredTurn :: T.Text -> CanonicalMoveFamily -> [T.Text] -> IO ()
assertStructuredTurn rawInput expectedFamily requiredFragments = do
  (_ss, _ti, _ts, tp, ta) <- buildRenderedFixture rawInput
  let rendered = taRendered ta
      lowered = T.toLower rendered
  assertEqual "structured turn should preserve expected family" expectedFamily (tpFinalFamily tp)
  assertEqual "structured turn decision must stay aligned with final family" expectedFamily (tdFamily (taDecision ta))
  assertEqual "structured turn should not leak local recovery cause" Nothing (taLocalRecoveryCause ta)
  assertBool "structured turn should not collapse into what-means template" (not ("что значит" `T.isInfixOf` lowered))
  assertBool "structured turn should not leak local recovery banner" (not ("локальный режим восстановления" `T.isInfixOf` lowered))
  assertBool "structured turn should not leak legacy translit fallback phrase" (not ("moya identichnost formiruetsya cherez dialog" `T.isInfixOf` lowered))
  assertBool "structured turn should produce a non-trivial Russian surface" (T.length (T.strip rendered) > 60)
  mapM_ (\fragment -> assertBool ("structured turn should mention: " <> T.unpack fragment) (fragment `T.isInfixOf` lowered)) requiredFragments

summarizeRoutePlan
  :: RouteEffectPlan
  -> ( CanonicalMoveFamily
     , Maybe CanonicalMoveFamily
     , ResponseStrategy
     , RenderStyle
     , RouteEffectRequest
     , RouteEffectRequest
     )
summarizeRoutePlan plan =
  let decision = rsRoutingDecision (repStatic plan)
  in ( rdFamily decision
     , rdStrategyFamily decision
     , rdRenderStrategy decision
     , rdRenderStyle decision
     , repShadowRequest plan
     , repAgdaRequest plan
     )

summarizeRenderPlan :: RenderEffectPlan -> (Maybe LocalRecoveryPlan, Maybe T.Text, T.Text)
summarizeRenderPlan plan =
  ( repLocalRecoveryPlan plan
  , repRenderMorphologyWarning plan
  , rsRenderWithBg (repRenderStatic plan)
  )

summarizeFinalizePrecommitPlan
  :: FinalizePrecommitPlan
  -> ( CanonicalMoveFamily
     , R5Verdict
     , Int
     , Bool
     , Int
     , FinalizePrecommitRequest
     , FinalizePrecommitRequest
     )
summarizeFinalizePrecommitPlan plan =
  let static = fppStatic plan
  in ( fsOutcomeFamily static
     , fsOutcomeVerdict static
     , fsConsecReflect static
     , fsTransitionWon static
     , length (mgEdges (fsMeaningGraphBase static))
     , fppCurrentTimeRequest plan
     , fppIntrospectionRequest plan
     )

summarizeFinalizeCommitPlan :: FinalizeCommitPlan -> (T.Text, Int, T.Text, Int)
summarizeFinalizeCommitPlan plan =
  ( CLoop.roSurfaceText (fcpResponseObservation plan)
  , ssTurnCount (fcpSaveState plan)
  , fcpSessionId plan
  , fcpRewireEventsCount plan
  )

quickCheckTest :: Testable prop => String -> prop -> Test
quickCheckTest label prop = TestCase $ do
  result <- quickCheckWithResult stdArgs { maxSuccess = 100 } prop
  case result of
    Success{} -> pure ()
    _ -> assertFailure ("QuickCheck failed: " <> label)
