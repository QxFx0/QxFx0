{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.Anomaly (anomalyTests) where

import Test.HUnit
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Sequence as Seq

import QxFx0.Core.TurnPipeline.Route.Anomaly
import QxFx0.Core.TurnPipeline.Route.Render (renderAnomalySurface)
import QxFx0.Types.Anomaly
import QxFx0.Types.State.Stance
import QxFx0.Types.State.System
import QxFx0.Types.State.SemanticCommitment
import QxFx0.Types.Collection.BoundedSet
import QxFx0.Self.Essence (EssenceTrajectory(..), EssenceWitness(..), FieldSignature(..), FieldBand(..), ValenceBand(..), EssenceResetEvent(..), emptyTrajectory, collapseEssence)
import QxFx0.Types (InputPropositionFrame(..), emptyInputPropositionFrame)
import QxFx0.Types.State.SelfState (SelfState(..), emptySelfState)
import QxFx0.Self.Salience (SalienceDriver(..))
import QxFx0.Self.Deliberation (ReconcileRule(..), Agreement(..))
import QxFx0.Self.Conatus (ConatusEnergy(..), ConatusComponents(..))
import QxFx0.Semantic.ContentSelector.Types (emptyContentSelector)
import QxFx0.Self.Field (emptyField)
import qualified Data.Text as T

anomalyTests :: Test
anomalyTests = TestList
  [ "StanceState: confidence extraction" ~: testStanceConfidence
  , "StanceState: predicates" ~: testStancePredicates
  , "StanceLineage: bounded history" ~: testStanceLineageBounded
  , "BoundedSet: FIFO eviction" ~: testBoundedSetFIFO
  , "SelfReferentialCollapse: trigger conditions" ~: testSelfReferentialCollapseTrigger
  , "SelfReferentialCollapse: collapseEssence" ~: testCollapseEssence
  , "AntiConatusChoice: trigger conditions" ~: testAntiConatusChoiceTrigger
  , "Anomaly rendering: Unclassifiable" ~: testRenderUnclassifiable
  , "Anomaly rendering: AntiConatus" ~: testRenderAntiConatus
  , "Anomaly rendering: SelfReferential" ~: testRenderSelfReferential
  , "Anomaly rendering: Temporal" ~: testRenderTemporal
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
      conatus1 = ConatusEnergy 3.0 (ConatusComponents 1.0 1.0 1.0 0.0)  -- Low conatus (< 5.0)
      traj1 = emptyTrajectory { etAngstLevel = 0.9 }  -- High angst (> 0.8)
  assertBool "should trigger for high confidence + inconsistent + high angst + low conatus"
    (antiConatusMove stance1 conatus1 traj1 undefined)

  -- Test 2: High confidence but consistent stance (StanceHeld with high conf) should not trigger
  let stance2 = StanceHeld 0.8  -- Consistent: state and confidence match
      conatus2 = ConatusEnergy 3.0 (ConatusComponents 1.0 1.0 1.0 0.0)
      traj2 = emptyTrajectory { etAngstLevel = 0.9 }
  assertBool "should not trigger for consistent stance"
    (not $ antiConatusMove stance2 conatus2 traj2 undefined)

  -- Test 3: Low confidence should not trigger
  let stance3 = StanceDoubted 0.5
      conatus3 = ConatusEnergy 3.0 (ConatusComponents 1.0 1.0 1.0 0.0)
      traj3 = emptyTrajectory { etAngstLevel = 0.9 }
  assertBool "should not trigger for low confidence"
    (not $ antiConatusMove stance3 conatus3 traj3 undefined)

  -- Test 4: High conatus should not trigger
  let stance4 = StanceDoubted 0.8
      conatus4 = ConatusEnergy 7.0 (ConatusComponents 2.0 2.0 2.0 1.0)  -- High conatus (>= 5.0)
      traj4 = emptyTrajectory { etAngstLevel = 0.9 }
  assertBool "should not trigger for high conatus"
    (not $ antiConatusMove stance4 conatus4 traj4 undefined)

  -- Test 5: Low angst should not trigger
  let stance5 = StanceDoubted 0.8
      conatus5 = ConatusEnergy 3.0 (ConatusComponents 1.0 1.0 1.0 0.0)
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
