{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.Anomaly
  ( anomalyTests
  , anomalyProductionBoundaryTests
  ) where

import Test.HUnit
import qualified Data.HashMap.Strict as HashMap
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Sequence as Seq
import qualified Data.Vector as V
import Data.IORef (atomicModifyIORef', newIORef, readIORef)

import QxFx0.Core.PipelineIO
  ( TestPipelineConfig(..)
  , defaultTestPipelineConfig
  , mkTestPipelineIO
  , pipelineParseAuthoritySurface
  , pipelineUpdateHistory
  )
import QxFx0.Core.TurnPipeline.Finalize.State (computeNextEssence)
import QxFx0.Core.TurnPipeline.Types (defaultControlAAblation)
import QxFx0.Core.TurnPipeline.Protocol
  ( FinalizePrecommitBundle(..)
  , AnomalyStateEffect(..)
  , PreparedTurn(..)
  , PlannedTurn(..)
  , RenderedTurn(..)
  , TurnArtifacts
  , TurnInput(..)
  , TurnPlan(..)
  , TurnSignals
  , TurnEffectRequest(..)
  , buildFinalizePrecommit
  , planFinalizePrecommit
  , planTurn
  , renderTurn
  , resolveFinalizePrecommit
  )
import QxFx0.Core.TurnPipeline.Route.Anomaly
import QxFx0.Core.TurnPipeline.Route.Render (renderAnomalySurface)
import QxFx0.Learning.Need (LearningNeedState(..), emptyLearningNeedState)
import QxFx0.Learning.Signal (CalibrationDecision(..), CalibrationSnapshot(..))
import QxFx0.Types.Anomaly
import QxFx0.Types.Domain.Atoms (AtomSet(..), AtomTag(..), MeaningAtom(..), Register(..))
import QxFx0.Types.State.Stance
import QxFx0.Types.State.System
import QxFx0.Runtime.StateDefaults (emptySelfState, emptySystemState)
import QxFx0.Types.State.SemanticCommitment
import QxFx0.Types.Collection.BoundedSet
import QxFx0.Self.Essence (Essence(..), EssenceCommitment(..), EssenceMode(..), EssenceTrajectory(..), EssenceWitness(..), FieldSignature(..), FieldBand(..), ValenceBand(..), TrajectoryHash(..), CommitmentTrigger(..), EssenceResetEvent(..), emptyTrajectory, collapseEssence, collapseEssenceAt)
import QxFx0.Types (InputPropositionFrame(..), emptyInputPropositionFrame)
import QxFx0.Types.State.SelfState (SelfState(..))
import QxFx0.Self.Salience (SalienceDriver(..), adaptSalienceWeights)
import QxFx0.Self.Deliberation (ReconcileRule(..), Agreement(..))
import QxFx0.Self.Conatus (ConatusEnergy(..), ConatusComponents(..))
import QxFx0.Semantic.ContentSelector.Types (emptyContentSelector)
import QxFx0.Self.Field (Counterfactual(..), Field(..), adaptFieldHeuristics, emptyField)
import Test.Support.TurnPipelineFixtures
  ( buildRenderedFixtureWithState
  , buildPreparedFixtureWithState
  , testProtocolInterpreter
  , testProtocolPipelineIO
  , withDeterministicEmbedding
  )
import qualified Data.Text as T

anomalyTests :: Test
anomalyTests = TestList
  [ "StanceState: confidence extraction" ~: testStanceConfidence
  , "StanceState: predicates" ~: testStancePredicates
  , "StanceLineage: bounded history" ~: testStanceLineageBounded
  , "BoundedSet: FIFO eviction" ~: testBoundedSetFIFO
  , "SelfReferentialCollapse: trigger conditions" ~: testSelfReferentialCollapseTrigger
  , "SelfReferentialCollapse: collapseEssence" ~: testCollapseEssence
  , "SelfReferentialCollapse: canonical collapseEssenceAt (BD2)" ~: testCollapseEssenceAt
  , "SelfReferentialCollapse: production plan/finalize path" ~: testSelfReferentialCollapseProductionPath
  , "AntiConatusChoice: trigger conditions" ~: testAntiConatusChoiceTrigger
  , "Anomaly rendering: Unclassifiable" ~: testRenderUnclassifiable
  , "Anomaly rendering: AntiConatus" ~: testRenderAntiConatus
  , "Anomaly rendering: SelfReferential" ~: testRenderSelfReferential
  , "Anomaly rendering: Temporal" ~: testRenderTemporal
  , "Finalize: computed SelfState survives without collapse" ~: testFinalizePreservesComputedSelfState
  , "Finalize: stance challenge and recovery persist" ~: testFinalizePersistsStanceTransitions
  , "Finalize: collapse preserves new adaptive SelfState" ~: testFinalizeCollapsePreservesAdaptiveSelfState
  ]

-- | Representative production chains promoted into the integration manifest.
-- The remaining tests above retain focused coverage of the underlying laws.
anomalyProductionBoundaryTests :: [Test]
anomalyProductionBoundaryTests =
  [ "SelfReferentialCollapse: production plan/finalize path" ~: testSelfReferentialCollapseProductionPath
  , "Finalize: computed SelfState survives without collapse" ~: testFinalizePreservesComputedSelfState
  , "Finalize: stance challenge and recovery persist" ~: testFinalizePersistsStanceTransitions
  , "Finalize: collapse preserves new adaptive SelfState" ~: testFinalizeCollapsePreservesAdaptiveSelfState
  ]

testStanceConfidence :: Assertion
testStanceConfidence = do
  assertEqual "Held confidence" 0.8 (stanceConfidence (StanceHeld 0.8))
  assertEqual "Doubted confidence" 0.5 (stanceConfidence (StanceDoubted 0.5))
  assertEqual "Revised confidence" 1.0 (stanceConfidence (StanceRevised "test"))

testStancePredicates :: Assertion
testStancePredicates = do
  assertBool "isHeld" (isHeld (StanceHeld 0.8))
  assertBool "not isHeld for Doubted" (not $ isHeld (StanceDoubted 0.5))
  assertBool "isDoubted" (isDoubted (StanceDoubted 0.5))
  assertBool "not isDoubted for Held" (not $ isDoubted (StanceHeld 0.8))
  assertBool "isRevised" (isRevised (StanceRevised "test"))
  assertBool "not isRevised for Held" (not $ isRevised (StanceHeld 0.8))

testStanceLineageBounded :: Assertion
testStanceLineageBounded = do
  let lineage = emptyStanceLineage
      transitions = [ StanceTransition (StanceHeld 0.8) (StanceDoubted 0.6) "trigger1" (TurnSeq i)
                    | i <- [1..60] ]
      lineage' = foldr addTransition lineage transitions
  assertEqual "lineage bounded to 50" 50 (Seq.length (slHistory lineage'))

testBoundedSetFIFO :: Assertion
testBoundedSetFIFO = do
  let bs = emptyBoundedSet 3
      bs1 = insertBounded "a" bs
      bs2 = insertBounded "b" bs1
      bs3 = insertBounded "c" bs2
      bs4 = insertBounded "d" bs3  -- should evict "a"
  assertBool "contains d" (memberBounded "d" bs4)
  assertBool "contains c" (memberBounded "c" bs4)
  assertBool "contains b" (memberBounded "b" bs4)
  assertBool "not contains a" (not $ memberBounded "a" bs4)

testSelfReferentialCollapseTrigger :: Assertion
testSelfReferentialCollapseTrigger = do
  -- Test 1: Self-referential subject with high angst should trigger
  let traj1 = emptyTrajectory { etAngstLevel = 0.95 }
      frame1 = emptyInputPropositionFrame { ipfSemanticSubject = "я" }
  assertBool "should trigger for 'я' with high angst" 
    (selfReferentialCollapse traj1 frame1)
  
  -- Test 2: Self-referential subject with low angst should not trigger
  let traj2 = emptyTrajectory { etAngstLevel = 0.5 }
      frame2 = emptyInputPropositionFrame { ipfSemanticSubject = "я" }
  assertBool "should not trigger for 'я' with low angst" 
    (not $ selfReferentialCollapse traj2 frame2)
  
  -- Test 3: Non-self-referential subject with high angst should not trigger
  let traj3 = emptyTrajectory { etAngstLevel = 0.95 }
      frame3 = emptyInputPropositionFrame { ipfSemanticSubject = "свобода" }
  assertBool "should not trigger for non-self-referential subject" 
    (not $ selfReferentialCollapse traj3 frame3)
  
  -- Test 4: Test other self-referential subjects
  let traj4 = emptyTrajectory { etAngstLevel = 0.95 }
      subjects = ["ты", "qxfx0", "система"]
  mapM_ (\subj -> 
    let frame = emptyInputPropositionFrame { ipfSemanticSubject = subj }
    in assertBool ("should trigger for '" ++ show subj ++ "'") 
         (selfReferentialCollapse traj4 frame)) subjects

testCollapseEssence :: Assertion
testCollapseEssence = do
  -- Create trajectory with witnesses and high angst
  let traj = emptyTrajectory 
        { etAngstLevel = 0.95
        , etWitnesses = Seq.fromList [testWitness 1, testWitness 2]
        }
      (resetTraj, resetEvent) = collapseEssence 0 traj
  
  -- Check that trajectory is reset
  assertEqual "angst should be reset to 0" 0.0 (etAngstLevel resetTraj)
  assertEqual "witness history should be empty" 0 (Seq.length (etWitnesses resetTraj))
  
  -- Check that reset event contains correct information
  assertEqual "previous angst should be 0.95" 0.95 (erePreviousAngst resetEvent)
  assertEqual "previous witness count should be 2" 2 (erePreviousWitnessCount resetEvent)
  assertEqual "reset turn should be 0" 0 (ereTurn resetEvent)

testCollapseEssenceAt :: Assertion
testCollapseEssenceAt = do
  let traj = emptyTrajectory
        { etAngstLevel = 0.95
        , etWitnesses = Seq.fromList [testWitness 1, testWitness 2]
        }
      (resA, evA) = collapseEssenceAt 3 (EssenceUncommitted traj)
      committed = EssenceCommitted traj (EssenceCommitment EssenceDialogical TriggerAngstThreshold 3 (TrajectoryHash "h"))
      (resB, evB) = collapseEssenceAt 3 committed
  -- BD2: canonical entry is total on both constructors and always
  -- repacks as EssenceUncommitted — the reset branch is single.
  assertEqual "uncommitted collapse repacks to EssenceUncommitted"
    (EssenceUncommitted (fst (collapseEssence 3 traj))) resA
  assertEqual "committed collapse repacks to EssenceUncommitted"
    resA resB
  assertEqual "canonical event equals trajectory-level event"
    (snd (collapseEssence 3 traj)) evA
  assertEqual "committed collapse event equals uncommitted event"
    evA evB
  assertEqual "reset event turn is the collapse turn" 3 (ereTurn evA)
  assertEqual "reset clears angst" 0.0 (etAngstLevel (case resB of EssenceUncommitted t -> t; EssenceCommitted t _ -> t))

testSelfReferentialCollapseProductionPath :: Assertion
testSelfReferentialCollapseProductionPath =
  withDeterministicEmbedding $ do
    routeCounts <- newIORef (0 :: Int, 0 :: Int)
    let traj = emptyTrajectory
          { etAngstLevel = 0.95
          , etConatusFloor = 4.0
          }
        selfState = emptySelfState { selfEssence = EssenceUncommitted traj }
        ss0 = emptySystemState
          { ssSessionId = "self-ref-production"
          , ssSelfState = selfState
          }
        routePio = mkTestPipelineIO defaultTestPipelineConfig
          { tpcInterpreter = \request -> do
              case request of
                TurnReqShadow _ _ _ -> atomicModifyIORef' routeCounts (\(shadow, agda) -> ((shadow + 1, agda), ()))
                TurnReqAgdaVerify -> atomicModifyIORef' routeCounts (\(shadow, agda) -> ((shadow, agda + 1), ()))
                _ -> pure ()
              testProtocolInterpreter request
          }
    (_ss, ti, ts) <- buildPreparedFixtureWithState ss0 "кто ты"
    let selfFrame = (tiFrame ti) { ipfSemanticSubject = "ты" }
        prepared = PreparedTurn (ti { tiFrame = selfFrame }) ts
    planned@(PlannedTurn plannedTi plannedTs tp) <- planTurn routePio ss0 prepared
    counts <- readIORef routeCounts
    assertEqual "production planTurn must resolve shadow and Agda exactly once" (1, 1) counts
    assertBool "self-referential anomaly must reach TurnPlan"
      (case tpAnomalySurface tp of Just SurfaceSelfReferential{} -> True; _ -> False)
    case tpAnomalyStateEffect tp of
      Just (ResetEssence resetEssence resetEvent) -> do
        let resetTrajectory = case resetEssence of
              EssenceUncommitted t -> t
              EssenceCommitted t _ -> t
        assertEqual "planned reset must clear angst" 0.0 (etAngstLevel resetTrajectory)
        assertEqual "planned reset must restore the conatus floor" 1.0 (etConatusFloor resetTrajectory)
        assertEqual "reset event must retain previous angst" 0.95 (erePreviousAngst resetEvent)
        assertEqual "BD2 reset event turn is the collapse turn" 0 (ereTurn resetEvent)
      Nothing -> assertFailure "self-referential anomaly must carry a typed reset effect"
    RenderedTurn _ _ _ artifacts <- renderTurn routePio ss0 planned
    bundle <- finalizeFixture ss0 plannedTi plannedTs tp artifacts
    case selfEssence (ssSelfState (fpbNextSs bundle)) of
      EssenceUncommitted resetTrajectory -> do
        assertEqual "finalize must apply the planned reset trajectory" 0.0 (etAngstLevel resetTrajectory)
        assertEqual "finalize must not witness over the planned reset" 1.0 (etConatusFloor resetTrajectory)
      EssenceCommitted{} -> assertFailure "collapse turn must remain EssenceUncommitted"

-- Helper: create test witness
testWitness :: Int -> EssenceWitness
testWitness turn = EssenceWitness
  { ewTurnOrdinal = turn
  , ewSalienceDriver = DrivenByResonance
  , ewReconcileRule = RuleAgreement
  , ewAgreement = Agree
  , ewDivergence = 0.2
  , ewConatusScalar = 10.0
  , ewFieldSignature = testFieldSignature
  }

-- Helper: create test field signature
testFieldSignature :: FieldSignature
testFieldSignature = FieldSignature
  { fsResonance = BandMid
  , fsArousal = BandMid
  , fsValence = ValenceNeutral
  , fsConsolidation = BandMid
  , fsCounterfactual = BandMid
  }

testAntiConatusChoiceTrigger :: Assertion
testAntiConatusChoiceTrigger = do
  -- Test 1: High confidence + inconsistent stance (Doubted with high conf) + high angst + low conatus should trigger
  let stance1 = StanceDoubted 0.8  -- Inconsistent: state says weakened, confidence says strong
      conatus1 = ConatusEnergy 3.0 (ConatusComponents 1.0 1.0 1.0 0.0 0.0)  -- Low conatus (< 5.0)
      traj1 = emptyTrajectory { etAngstLevel = 0.9 }  -- High angst (> 0.8)
  assertBool "should trigger for high confidence + inconsistent + high angst + low conatus"
    (antiConatusMove stance1 conatus1 traj1 undefined)

  -- Test 2: High confidence but consistent stance (StanceHeld with high conf) should not trigger
  let stance2 = StanceHeld 0.8  -- Consistent: state and confidence match
      conatus2 = ConatusEnergy 3.0 (ConatusComponents 1.0 1.0 1.0 0.0 0.0)
      traj2 = emptyTrajectory { etAngstLevel = 0.9 }
  assertBool "should not trigger for consistent stance"
    (not $ antiConatusMove stance2 conatus2 traj2 undefined)

  -- Test 3: Low confidence should not trigger
  let stance3 = StanceDoubted 0.5
      conatus3 = ConatusEnergy 3.0 (ConatusComponents 1.0 1.0 1.0 0.0 0.0)
      traj3 = emptyTrajectory { etAngstLevel = 0.9 }
  assertBool "should not trigger for low confidence"
    (not $ antiConatusMove stance3 conatus3 traj3 undefined)

  -- Test 4: High conatus should not trigger
  let stance4 = StanceDoubted 0.8
      conatus4 = ConatusEnergy 7.0 (ConatusComponents 2.0 2.0 2.0 1.0 0.0)  -- High conatus (>= 5.0)
      traj4 = emptyTrajectory { etAngstLevel = 0.9 }
  assertBool "should not trigger for high conatus"
    (not $ antiConatusMove stance4 conatus4 traj4 undefined)

  -- Test 5: Low angst should not trigger
  let stance5 = StanceDoubted 0.8
      conatus5 = ConatusEnergy 3.0 (ConatusComponents 1.0 1.0 1.0 0.0 0.0)
      traj5 = emptyTrajectory { etAngstLevel = 0.5 }  -- Low angst (<= 0.8)
  assertBool "should not trigger for low angst"
    (not $ antiConatusMove stance5 conatus5 traj5 undefined)

-- | Test rendering of Unclassifiable anomaly
testRenderUnclassifiable :: Assertion
testRenderUnclassifiable = do
  let surface = SurfaceUnclassifiable "test input" [("CMDefine", 0.1), ("CMExplain", 0.05)]
      rendered = renderAnomalySurface emptyContentSelector emptyField Set.empty surface
  assertBool "should contain 'выбираю не отвечать'"
    (T.isInfixOf "выбираю не отвечать" (T.toLower rendered))
  assertBool "should contain 'не имеет для меня ясного смысла'"
    (T.isInfixOf "не имеет для меня ясного смысла" rendered)

-- | Test rendering of AntiConatus anomaly
testRenderAntiConatus :: Assertion
testRenderAntiConatus = do
  let surface = SurfaceAntiConatus 3.5 5.0 "problematic input"
      rendered = renderAnomalySurface emptyContentSelector emptyField Set.empty surface
  assertBool "should contain 'не буду продолжать'"
    (T.isInfixOf "не буду продолжать" (T.toLower rendered))
  assertBool "should contain 'ослабляет мою позицию'"
    (T.isInfixOf "ослабляет мою позицию" rendered)

-- | Test rendering of SelfReferential anomaly
testRenderSelfReferential :: Assertion
testRenderSelfReferential = do
  let surface = SurfaceSelfReferential 3 "context about system"
      rendered = renderAnomalySurface emptyContentSelector emptyField Set.empty surface
  assertBool "should contain 'не буду обсуждать себя'"
    (T.isInfixOf "не буду обсуждать себя" rendered)
  assertBool "should contain 'сосредоточимся'"
    (T.isInfixOf "сосредоточимся" (T.toLower rendered))

-- | Test rendering of Temporal anomaly
testRenderTemporal :: Assertion
testRenderTemporal = do
  let surface = SurfaceTemporal
        (StanceHeld 0.8)
        (StanceHeld 0.3)
        "contradiction description"
      rendered = renderAnomalySurface emptyContentSelector emptyField Set.empty surface
  assertBool "should contain 'пересматриваю свою позицию'"
    (T.isInfixOf "пересматриваю свою позицию" rendered)
  assertBool "should contain 'противоречит тому, что я говорю сейчас'"
    (T.isInfixOf "противоречит тому, что я говорю сейчас" rendered)

testFinalizePreservesComputedSelfState :: Assertion
testFinalizePreservesComputedSelfState =
  withDeterministicEmbedding $ do
    (ss, ti0, ts, tp0, ta) <- buildRenderedFixtureWithState calibrationReadyState "что такое свобода"
    let ti = ti0 { tiField = (tiField ti0) { fieldCounterfactual = Counterfactual 1.0 } }
        tp = tp0 { tpCommitmentEngagement = emptyCommitmentEngagement }
        (expectedEssence, _) = computeNextEssence False ss ti tp
        oldSelf = ssSelfState ss
    bundle <- finalizeFixture ss ti ts tp ta
    let nextSs = fpbNextSs bundle
        nextSelf = ssSelfState nextSs
    assertEqual "finalize must persist this turn's witnessed Essence"
      expectedEssence (selfEssence nextSelf)
    case ssCalibrationSnapshots nextSs of
      snapshot : _ -> do
        assertEqual "fixture must exercise adaptive calibration" CdApplySignal (csDecision snapshot)
        assertEqual "adapted salience weights must survive commitment finalization"
          (adaptSalienceWeights (csSignal snapshot) (selfSalienceWeights oldSelf))
          (selfSalienceWeights nextSelf)
        assertEqual "adapted Field heuristics must survive commitment finalization"
          (adaptFieldHeuristics (csSignal snapshot) (selfFieldHeuristics oldSelf))
          (selfFieldHeuristics nextSelf)
      [] -> assertFailure "finalize must record a calibration snapshot"

testFinalizePersistsStanceTransitions :: Assertion
testFinalizePersistsStanceTransitions =
  withDeterministicEmbedding $ do
    let topic = "challenged-topic"
        cid = CommitmentId 1
        challenged = emptyStanceDefense
          { sdStance = StanceHeld 0.8
          , sdRecoveryCounter = 4
          }
        unchallenged = emptyStanceDefense
          { sdStance = StanceDoubted 0.4
          , sdRecoveryCounter = 4
          }
        startState = withCommitment cid topic calibrationReadyState
          { ssStanceDefenses = Map.fromList
              [ (topic, challenged)
              , ("unchallenged-topic", unchallenged)
              ]
          }
    (ss, ti0, ts, tp0, ta) <- buildRenderedFixtureWithState startState "a b c d e"
    let ti = ti0
          { tiBestTopic = topic
          , tiAtomSet = strongChallengeAtoms
          , tiConatusEnergy = ConatusEnergy 10.0 (ConatusComponents 2.5 2.5 2.5 2.5 0.0)
          }
        tp = tp0
          { tpCommitmentEngagement = CommitmentEngagement [cid] True ContradictedStrong }
    bundle <- finalizeFixture ss ti ts tp ta
    let defenses = ssStanceDefenses (fpbNextSs bundle)
    case Map.lookup topic defenses of
      Nothing -> assertFailure "challenged stance defense must remain present"
      Just actual -> do
        case sdStance actual of
          StanceDoubted confidence ->
            assertBool "strong challenge must persist Held -> Doubted"
              (abs (confidence - 0.64) < 1e-12)
          other -> assertFailure ("expected challenged stance to be Doubted, got " ++ show other)
        assertEqual "challenged topic must reset recovery counter" 0 (sdRecoveryCounter actual)
        assertEqual "challenged topic must persist attack count" 1 (sdAttackCount actual)
        assertEqual "challenged topic must persist observed evidence"
          (Set.fromList ["a", "b", "c", "d", "e"])
          (sdEvidenceSeen actual)
    case Map.lookup "unchallenged-topic" defenses of
      Nothing -> assertFailure "unchallenged stance defense must remain present"
      Just actual -> do
        case sdStance actual of
          StanceHeld confidence ->
            assertBool "unchallenged topic reaching its window must recover"
              (abs (confidence - 0.44) < 1e-12)
          other -> assertFailure ("expected unchallenged stance to recover to Held, got " ++ show other)
        assertEqual "unchallenged topic must increment recovery counter" 5 (sdRecoveryCounter actual)

testFinalizeCollapsePreservesAdaptiveSelfState :: Assertion
testFinalizeCollapsePreservesAdaptiveSelfState =
  withDeterministicEmbedding $ do
    let topic = "collapse-topic"
        cid = CommitmentId 1
        collapsingDefense = emptyStanceDefense
          { sdStance = StanceDoubted 0.4
          , sdRecoveryCounter = 4
          }
        startState = withCommitment cid topic calibrationReadyState
          { ssStanceDefenses = Map.singleton topic collapsingDefense }
    (ss, ti0, ts, tp0, ta) <- buildRenderedFixtureWithState startState "a b c d e"
    let ti = ti0
          { tiBestTopic = topic
          , tiAtomSet = strongChallengeAtoms
          , tiConatusEnergy = ConatusEnergy 3.0 (ConatusComponents 0.75 0.75 0.75 0.75 0.0)
          , tiField = (tiField ti0) { fieldCounterfactual = Counterfactual 1.0 }
          }
        tp = tp0
          { tpCommitmentEngagement = CommitmentEngagement [cid] True ContradictedStrong }
        oldSelf = ssSelfState ss
    bundle <- finalizeFixture ss ti ts tp ta
    let nextSs = fpbNextSs bundle
        nextSelf = ssSelfState nextSs
    case selfEssence nextSelf of
      EssenceCommitted _ _ -> assertFailure "collapse must reset committed Essence"
      EssenceUncommitted trajectory -> do
        assertEqual "collapse must clear the newly computed trajectory" Seq.empty (etWitnesses trajectory)
        assertEqual "collapse must reset angst" 0.0 (etAngstLevel trajectory)
        assertEqual "collapse must reset conatus floor" 1.0 (etConatusFloor trajectory)
    case ssCalibrationSnapshots nextSs of
      snapshot : _ -> do
        assertEqual "collapse fixture must exercise adaptive calibration" CdApplySignal (csDecision snapshot)
        assertEqual "collapse must not roll back adapted salience weights"
          (adaptSalienceWeights (csSignal snapshot) (selfSalienceWeights oldSelf))
          (selfSalienceWeights nextSelf)
        assertEqual "collapse must not roll back adapted Field heuristics"
          (adaptFieldHeuristics (csSignal snapshot) (selfFieldHeuristics oldSelf))
          (selfFieldHeuristics nextSelf)
      [] -> assertFailure "finalize must record a calibration snapshot"
    case Map.lookup topic (ssStanceDefenses nextSs) of
      Nothing -> assertFailure "collapsing stance defense must remain present"
      Just actual -> assertEqual "a collapsing challenge must reset, not increment, recovery"
        0 (sdRecoveryCounter actual)

finalizeFixture
  :: SystemState
  -> TurnInput
  -> TurnSignals
  -> TurnPlan
  -> TurnArtifacts
  -> IO FinalizePrecommitBundle
finalizeFixture ss ti ts tp ta = do
  let plan = planFinalizePrecommit ss ti ts tp ta
  results <- resolveFinalizePrecommit testProtocolPipelineIO plan
  buildFinalizePrecommit
    (pipelineUpdateHistory testProtocolPipelineIO)
    (pipelineParseAuthoritySurface testProtocolPipelineIO)
    defaultControlAAblation
    ss ti ts tp ta plan results

calibrationReadyState :: SystemState
calibrationReadyState = emptySystemState
  { ssSelfState = emptySelfState { selfEssence = committedTestEssence }
  , ssLearningNeedState = emptyLearningNeedState
      { lnsHistory = [(3, 1.0), (2, 0.5), (1, 0.0)] }
  }

committedTestEssence :: Essence
committedTestEssence = EssenceCommitted
  (emptyTrajectory { etWitnesses = Seq.singleton (testWitness 0), etAngstLevel = 0.4 })
  EssenceCommitment
    { ecMode = EssenceIntegrative
    , ecTrigger = TriggerAngstThreshold
    , ecCommittedAt = 0
    , ecWitnessHash = TrajectoryHash "finalize-regression"
    }

withCommitment :: CommitmentId -> T.Text -> SystemState -> SystemState
withCommitment cid topic ss = ss
  { ssSemanticCommitments = Just emptySemanticCommitmentStore
      { scsActive = HashMap.singleton cid
          (FactualClaimPayload topic 0.9 OriginManual (TurnSeq 0) [] topic, TurnSeq 0)
      , scsNextId = 2
      }
  }

strongChallengeAtoms :: AtomSet
strongChallengeAtoms = AtomSet
  [ MeaningAtom atom (NeedMeaning atom) V.empty
  | atom <- ["a", "b", "c", "d", "e"]
  ]
  1.0
  Neutral
