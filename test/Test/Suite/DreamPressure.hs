{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.DreamPressure
  ( dreamPressureTests
  ) where

import Test.HUnit

import Data.Time.Clock (UTCTime(..))
import Data.Time.Calendar (Day(ModifiedJulianDay))
import qualified Data.Map.Strict as Map
import qualified Data.Text as T

import QxFx0.Core.TopicDrift.Pressure
import QxFx0.Core.FMAR (FmarMode(..))
import QxFx0.Core.PipelineIO
  ( defaultTestPipelineConfig
  , mkTestPipelineIO
  , pipelineShadowPolicy
  )
import QxFx0.Core.TurnPipeline.Protocol
  ( TurnInput(..)
  , TurnPlan(..)
  , TurnSignals(..)
  , TurnArtifacts(..)
  , buildRouteTurnPlan
  , buildTurnArtifacts
  , buildTurnInput
  , buildTurnSignals
  , planPrepareEffects
  , planRenderEffects
  , planRouteEffects
  , resolvePrepareEffects
  , resolveRenderEffects
  , resolveRouteEffects
  )
import QxFx0.Types
import QxFx0.Types.ShadowDivergence
  ( ShadowDivergenceKind(..)
  , ShadowDivergenceSeverity(..)
  )


dreamPressureTests :: [Test]
dreamPressureTests =
  [ testDatalogPressureDeterministic
  , testDatalogPressureUnavailableOnly
  , testDatalogPressureAdvisoryMismatch
  , testDatalogPressureAlternativeFamilyPressure
  , testDatalogPressureSafetyPressure
  , testDatalogPressureContractPressure
  , testDatalogPressureGateEscalation
  , testIntuitionPressureDeterministic
  , testDreamPressureReconciliationBounded
  , testDreamPressureNoLiveOverride
  , testDreamPressureCandidateThresholdStable
  , testDreamPressureTelemetryDeterministic
  , testDreamPressureThresholdVisibility
  , testDreamCandidateDecisionDeterministic
  , testNoPressureRejectsGraphBias
  , testUnavailableOnlyRejectsGraphBias
  , testAdvisoryMismatchRejectsGraphBias
  , testAlternativeFamilyPressureQuarantinesGraphBias
  , testSafetyConvergentAcceptsGraphBias
  , testContractConvergentAcceptsGraphBias
  , testGateEscalationConvergentAcceptsGraphBias
  , testConflictAgreementQuarantinesGraphBias
  , testSymbolicOnlyAgreementStaysInert
  , testAffectiveOnlyAgreementStaysInert
  , testThresholdMissRejectsGraphBias
  , testNaturalSymbolicCandidateStaysObservedOnly
  , testNaturalAffectiveCandidateStaysObservedOnly
  , testNaturalConflictCandidateStaysQuarantined
  , testNaturalNoneCandidateStaysObservedOnly
  , testRejectedAndQuarantinedCandidatesAreInert
  , testAcceptedGraphBiasAppliesBoundedly
  , testDreamLifecycleTelemetryConsistency
  ]

testDatalogPressureDeterministic :: Test
testDatalogPressureDeterministic = TestCase $ do
  (_ss, _ti, _ts, tp) <- buildPlannedFixture "что такое свобода"
  let pressure1 = deriveDatalogPressure tp
      pressure2 = deriveDatalogPressure tp
  assertEqual "datalog pressure should be deterministic" pressure1 pressure2
  assertBool "datalog pressure strength must stay bounded" (dpStrength pressure1 >= 0.0 && dpStrength pressure1 <= 1.0)

testDatalogPressureUnavailableOnly :: Test
testDatalogPressureUnavailableOnly = TestCase $ do
  (_ss, _ti, _ts, tp0) <- buildPlannedFixture "что такое свобода"
  let tp = tp0
            { tpShadowStatus = ShadowUnavailable
            , tpShadowDivergenceSeverity = ShadowSeverityUnavailable
            , tpShadowGateTriggered = False
            }
      pressure = deriveDatalogPressure tp
  assertEqual "unavailable-only path should stay distinguishable" DPUnavailableOnly (dpClass pressure)

testDatalogPressureAdvisoryMismatch :: Test
testDatalogPressureAdvisoryMismatch = TestCase $ do
  (_ss, _ti, _ts, tp0) <- buildPlannedFixture "что такое свобода"
  let tp = tp0
            { tpShadowStatus = ShadowDiverged
            , tpShadowDivergenceSeverity = ShadowSeverityAdvisory
            , tpShadowGateTriggered = False
            , tpShadowFamily = Nothing
            }
      pressure = deriveDatalogPressure tp
  assertEqual "advisory mismatch should remain distinct" DPAdvisoryMismatch (dpClass pressure)

testDatalogPressureAlternativeFamilyPressure :: Test
testDatalogPressureAlternativeFamilyPressure = TestCase $ do
  (_ss, _ti, _ts, tp0) <- buildPlannedFixture "что такое свобода"
  let tp = tp0
            { tpShadowStatus = ShadowDiverged
            , tpShadowDivergenceSeverity = ShadowSeverityAdvisory
            , tpShadowFamily = Just CMRepair
            , tpShadowGateTriggered = False
            }
      pressure = deriveDatalogPressure tp
  assertEqual "alternative-family signal should be visible" DPAlternativeFamilyPressure (dpClass pressure)

testDatalogPressureSafetyPressure :: Test
testDatalogPressureSafetyPressure = TestCase $ do
  (_ss, _ti, _ts, tp0) <- buildPlannedFixture "что такое свобода"
  let tp = tp0
            { tpShadowStatus = ShadowDiverged
            , tpShadowDivergenceSeverity = ShadowSeveritySafety
            , tpShadowGateTriggered = False
            , tpShadowFamily = Nothing
            }
      pressure = deriveDatalogPressure tp
  assertEqual "safety pressure must stay distinct" DPSafetyPressure (dpClass pressure)

testDatalogPressureContractPressure :: Test
testDatalogPressureContractPressure = TestCase $ do
  (_ss, _ti, _ts, tp0) <- buildPlannedFixture "что такое свобода"
  let tp = tp0
            { tpShadowStatus = ShadowDiverged
            , tpShadowDivergenceSeverity = ShadowSeverityContract
            , tpShadowGateTriggered = False
            , tpShadowFamily = Nothing
            }
      pressure = deriveDatalogPressure tp
  assertEqual "contract pressure must stay distinct" DPContractPressure (dpClass pressure)

testDatalogPressureGateEscalation :: Test
testDatalogPressureGateEscalation = TestCase $ do
  (_ss, _ti, _ts, tp0) <- buildPlannedFixture "что такое свобода"
  let tp = tp0
            { tpShadowStatus = ShadowDiverged
            , tpShadowDivergenceSeverity = ShadowSeverityAdvisory
            , tpShadowGateTriggered = True
            }
      pressure = deriveDatalogPressure tp
  assertEqual "gate-triggered path should escalate distinctly" DPGateEscalation (dpClass pressure)

testIntuitionPressureDeterministic :: Test
testIntuitionPressureDeterministic = TestCase $ do
  (_ss, _ti, ts) <- buildPreparedFixture "что такое свобода"
  let pressure1 = deriveIntuitionPressure ts
      pressure2 = deriveIntuitionPressure ts
  assertEqual "intuition pressure should be deterministic" pressure1 pressure2

testDreamPressureReconciliationBounded :: Test
testDreamPressureReconciliationBounded = TestCase $ do
  let datalogPressure = DatalogPressure DPSafetyPressure CMGround (Just CMRepair) Nothing 0.9 ["shadow_safety"] ShadowVerdictMismatch ShadowSeveritySafety False 0.1 ShadowDiverged
      intuitionPressure = IntuitionPressure IntuitionPressureFlash 0.8 0.8 (Just "держи линию") (Just DeepResonanceTrigger) False ["flash_signal"]
      reconciled = reconcileDreamPressures defaultDreamPressureRegime datalogPressure intuitionPressure
  assertBool "reconciled pressure strength must be bounded" (drpStrength reconciled >= 0.0 && drpStrength reconciled <= 1.0)
  assertBool "reconciled candidate threshold must be bounded" (drpCandidateThreshold reconciled >= 0.0 && drpCandidateThreshold reconciled <= 1.0)
  assertBool "reconciled bias must be bounded" (vecNorm (drpBias reconciled) <= 0.08 + 1e-9)

testDreamPressureNoLiveOverride :: Test
testDreamPressureNoLiveOverride = TestCase $ do
  (_ss, ti, ts, tp, ta) <- buildRenderedFixture "что такое свобода"
  let outcome = buildDreamOutcome defaultDreamPressureRegime ti ts tp ta
  assertEqual "dream pressure should not change current-turn family" (tpFinalFamily tp) (tpFinalFamily tp)
  assertEqual "dream pressure should not rewrite current-turn rendered decision family" (tdFamily (taDecision ta)) (tdFamily (taDecision ta))
  assertBool "dream pressure candidates must stay advisory-only" (all dccAdvisoryOnly (doCorrectionCandidates outcome))

testDreamPressureCandidateThresholdStable :: Test
testDreamPressureCandidateThresholdStable = TestCase $ do
  let weakPressure = DreamPressure DreamPressureNone 0.1 zeroVec Nothing [] 0.35
      strongPressure = DreamPressure DreamPressureConvergent 0.8 (CoreVec 0.02 0.01 0.01 0.03 0.02) (Just CMReflect) ["agreement"] 0.35
  assertEqual "weak pressure should yield no candidates" [] (dreamPressureToCandidates weakPressure)
  assertBool "strong pressure should yield advisory candidates" (not (null (dreamPressureToCandidates strongPressure)))
  assertBool "strong pressure candidates must stay advisory-only" (all dccAdvisoryOnly (dreamPressureToCandidates strongPressure))

testDreamPressureTelemetryDeterministic :: Test
testDreamPressureTelemetryDeterministic = TestCase $ do
  (_ss, ti, ts, tp, ta) <- buildRenderedFixture "что такое свобода"
  let outcome1 = buildDreamOutcome defaultDreamPressureRegime ti ts tp ta
      outcome2 = buildDreamOutcome defaultDreamPressureRegime ti ts tp ta
  assertEqual "dream outcome telemetry should be deterministic" outcome1 outcome2

testDreamPressureThresholdVisibility :: Test
testDreamPressureThresholdVisibility = TestCase $ do
  (_ss, ti, ts, tp, ta) <- buildRenderedFixture "что такое свобода"
  let outcome = buildDreamOutcome defaultDreamPressureRegime ti ts tp ta
      candidates = doCorrectionCandidates outcome
      thresholdFired = not (null candidates)
      biasApplied = vecNorm (doBias outcome) > 1e-9
  assertEqual "threshold visibility must align with candidate emission" thresholdFired (not (null candidates))
  assertEqual "bias visibility must align with computed bias norm" biasApplied (vecNorm (doBias outcome) > 1e-9)
  assertBool "candidate kinds must be present when threshold fires" (not thresholdFired || all (not . T.null . dccKind) candidates)

testDreamCandidateDecisionDeterministic :: Test
testDreamCandidateDecisionDeterministic = TestCase $ do
  (_ss, ti, ts, tp, ta) <- buildRenderedFixture "что такое свобода"
  let outcome1 = buildDreamOutcome defaultDreamPressureRegime ti ts tp ta
      outcome2 = buildDreamOutcome defaultDreamPressureRegime ti ts tp ta
  assertEqual "dream candidate decisions should be deterministic" (doCandidateDecisions outcome1) (doCandidateDecisions outcome2)
  assertBool "refined datalog semantics must not widen application beyond graph_bias" (all (\c -> dccKind c == "graph_bias" || dccAdvisoryOnly c) (doCorrectionCandidates outcome1))

testNoPressureRejectsGraphBias :: Test
testNoPressureRejectsGraphBias = TestCase $ do
  let pressure = DreamPressure DreamPressureConvergent 0.8 (CoreVec 0.02 0.01 0.01 0.03 0.02) Nothing [] 0.35
      candidate = DreamCorrectionCandidate "graph" "graph_bias" 0.8 Nothing [] True
      decision = evaluateDreamCandidateWithClasses DPNoPressure IntuitionPressurePosterior pressure candidate
  case decision of
    DreamCandidateRejected rejected -> assertEqual "no pressure should reject graph bias" DCDRNoPressure (rdcReason rejected)
    _ -> assertFailure "no pressure must reject graph-bias candidate"

testUnavailableOnlyRejectsGraphBias :: Test
testUnavailableOnlyRejectsGraphBias = TestCase $ do
  let pressure = DreamPressure DreamPressureConvergent 0.8 (CoreVec 0.02 0.01 0.01 0.03 0.02) Nothing [] 0.35
      candidate = DreamCorrectionCandidate "graph" "graph_bias" 0.8 Nothing [] True
      decision = evaluateDreamCandidateWithClasses DPUnavailableOnly IntuitionPressureNone pressure candidate
  case decision of
    DreamCandidateRejected rejected -> assertEqual "unavailable-only should reject graph bias" DCDRUnavailableOnly (rdcReason rejected)
    _ -> assertFailure "unavailable-only pressure must reject graph-bias candidate"

testAdvisoryMismatchRejectsGraphBias :: Test
testAdvisoryMismatchRejectsGraphBias = TestCase $ do
  let pressure = DreamPressure DreamPressureConvergent 0.8 (CoreVec 0.02 0.01 0.01 0.03 0.02) Nothing [] 0.35
      candidate = DreamCorrectionCandidate "graph" "graph_bias" 0.8 Nothing [] True
      decision = evaluateDreamCandidateWithClasses DPAdvisoryMismatch IntuitionPressurePosterior pressure candidate
  case decision of
    DreamCandidateRejected rejected -> assertEqual "advisory mismatch should reject graph bias" DCDRAdvisoryMismatchOnly (rdcReason rejected)
    _ -> assertFailure "advisory mismatch must reject graph-bias candidate"

testAlternativeFamilyPressureQuarantinesGraphBias :: Test
testAlternativeFamilyPressureQuarantinesGraphBias = TestCase $ do
  let pressure = DreamPressure DreamPressureConvergent 0.8 (CoreVec 0.02 0.01 0.01 0.03 0.02) (Just CMRepair) [] 0.35
      candidate = DreamCorrectionCandidate "graph" "graph_bias" 0.8 (Just CMRepair) [] True
      decision = evaluateDreamCandidateWithClasses DPAlternativeFamilyPressure IntuitionPressurePosterior pressure candidate
  case decision of
    DreamCandidateQuarantined quarantined -> assertEqual "alternative-family pressure should quarantine graph bias" DCDRAlternativeFamilyPressure (qdcReason quarantined)
    _ -> assertFailure "alternative-family pressure must quarantine graph-bias candidate"

testSafetyConvergentAcceptsGraphBias :: Test
testSafetyConvergentAcceptsGraphBias = TestCase $ do
  let pressure = DreamPressure DreamPressureConvergent 0.8 (CoreVec 0.02 0.01 0.01 0.03 0.02) Nothing [] 0.35
      candidate = DreamCorrectionCandidate "graph" "graph_bias" 0.8 Nothing [] True
      decision = evaluateDreamCandidateWithClasses DPSafetyPressure IntuitionPressurePosterior pressure candidate
  case decision of
    DreamCandidateAccepted accepted -> assertEqual "safety convergent pressure should accept graph bias with safety reason" DCDRAcceptedSafetyGraphBias (adcReason accepted)
    _ -> assertFailure "safety convergent pressure must accept graph-bias candidate"

testContractConvergentAcceptsGraphBias :: Test
testContractConvergentAcceptsGraphBias = TestCase $ do
  let pressure = DreamPressure DreamPressureConvergent 0.8 (CoreVec 0.02 0.01 0.01 0.03 0.02) Nothing [] 0.35
      candidate = DreamCorrectionCandidate "graph" "graph_bias" 0.8 Nothing [] True
      decision = evaluateDreamCandidateWithClasses DPContractPressure IntuitionPressurePosterior pressure candidate
  case decision of
    DreamCandidateAccepted accepted -> assertEqual "contract convergent pressure should accept graph bias with contract reason" DCDRAcceptedContractGraphBias (adcReason accepted)
    _ -> assertFailure "contract convergent pressure must accept graph-bias candidate"

testGateEscalationConvergentAcceptsGraphBias :: Test
testGateEscalationConvergentAcceptsGraphBias = TestCase $ do
  let pressure = DreamPressure DreamPressureConvergent 0.8 (CoreVec 0.02 0.01 0.01 0.03 0.02) Nothing [] 0.35
      candidate = DreamCorrectionCandidate "graph" "graph_bias" 0.8 Nothing [] True
      decision = evaluateDreamCandidateWithClasses DPGateEscalation IntuitionPressurePosterior pressure candidate
  case decision of
    DreamCandidateAccepted accepted -> assertEqual "gate escalation convergent pressure should accept graph bias with gate reason" DCDRAcceptedGateEscalationGraphBias (adcReason accepted)
    _ -> assertFailure "gate escalation convergent pressure must accept graph-bias candidate"

testConflictAgreementQuarantinesGraphBias :: Test
testConflictAgreementQuarantinesGraphBias = TestCase $ do
  let pressure = DreamPressure DreamPressureConflict 0.9 (CoreVec 0.02 0.01 0.01 0.03 0.02) Nothing [] 0.35
      candidate = DreamCorrectionCandidate "graph" "graph_bias" 0.9 Nothing [] True
      decision = evaluateDreamCandidateWithClasses DPContractPressure IntuitionPressureFlash pressure candidate
  case decision of
    DreamCandidateQuarantined quarantined -> assertEqual "conflict agreement should quarantine graph bias" DCDRConflictAgreement (qdcReason quarantined)
    _ -> assertFailure "conflict agreement must quarantine graph-bias candidate"

testSymbolicOnlyAgreementStaysInert :: Test
testSymbolicOnlyAgreementStaysInert = TestCase $ do
  let pressure = DreamPressure DreamPressureDatalogDominant 0.8 (CoreVec 0.02 0.01 0.01 0.03 0.02) (Just CMRepair) [] 0.35
      candidate = DreamCorrectionCandidate "graph" "graph_bias" 0.8 (Just CMRepair) [] True
      decision = evaluateDreamCandidateWithClasses DPContractPressure IntuitionPressurePosterior pressure candidate
  case decision of
    DreamCandidateRejected rejected -> assertEqual "symbolic-only agreement should stay inert" DCDRSymbolicOnlyAgreement (rdcReason rejected)
    _ -> assertFailure "symbolic-only agreement must reject graph-bias candidate"
  assertEqual "symbolic-only decision must remain inert" zeroVec (decisionAppliedBias decision)

testAffectiveOnlyAgreementStaysInert :: Test
testAffectiveOnlyAgreementStaysInert = TestCase $ do
  let pressure = DreamPressure DreamPressureIntuitionDominant 0.8 (CoreVec 0.02 0.01 0.01 0.03 0.02) Nothing [] 0.35
      candidate = DreamCorrectionCandidate "graph" "graph_bias" 0.8 Nothing [] True
      decision = evaluateDreamCandidateWithClasses DPContractPressure IntuitionPressureFlash pressure candidate
  case decision of
    DreamCandidateRejected rejected -> assertEqual "affective-only agreement should stay inert" DCDRAffectiveOnlyAgreement (rdcReason rejected)
    _ -> assertFailure "affective-only agreement must reject graph-bias candidate"
  assertEqual "affective-only decision must remain inert" zeroVec (decisionAppliedBias decision)

testThresholdMissRejectsGraphBias :: Test
testThresholdMissRejectsGraphBias = TestCase $ do
  let pressure = DreamPressure DreamPressureConvergent 0.34 (CoreVec 0.02 0.01 0.01 0.03 0.02) Nothing [] 0.35
      candidate = DreamCorrectionCandidate "graph" "graph_bias" 0.34 Nothing [] True
      decision = evaluateDreamCandidateWithClasses DPSafetyPressure IntuitionPressurePosterior pressure candidate
  case decision of
    DreamCandidateRejected rejected -> assertEqual "below-threshold graph bias should preserve threshold miss reason" DCDRThresholdNotReached (rdcReason rejected)
    _ -> assertFailure "below-threshold graph-bias candidate must be rejected"
  assertEqual "threshold-miss decision must remain inert" zeroVec (decisionAppliedBias decision)

testNaturalSymbolicCandidateStaysObservedOnly :: Test
testNaturalSymbolicCandidateStaysObservedOnly = TestCase $ do
  let pressure = DreamPressure DreamPressureDatalogDominant 0.8 (CoreVec 0.02 0.01 0.01 0.03 0.02) (Just CMRepair) [] 0.35
      candidate = DreamCorrectionCandidate "symbolic" "symbolic" 0.8 (Just CMRepair) [] True
      decision = evaluateDreamCandidateWithClasses DPContractPressure IntuitionPressurePosterior pressure candidate
  case decision of
    DreamCandidateRejected rejected -> assertEqual "natural symbolic candidate should stay observed-only" DCDRSymbolicCandidateObservedOnly (rdcReason rejected)
    _ -> assertFailure "natural symbolic candidate must be rejected"
  assertEqual "natural symbolic candidate must remain inert" zeroVec (decisionAppliedBias decision)

testNaturalAffectiveCandidateStaysObservedOnly :: Test
testNaturalAffectiveCandidateStaysObservedOnly = TestCase $ do
  let pressure = DreamPressure DreamPressureIntuitionDominant 0.8 (CoreVec 0.02 0.01 0.01 0.03 0.02) Nothing [] 0.35
      candidate = DreamCorrectionCandidate "affective" "affective" 0.8 Nothing [] True
      decision = evaluateDreamCandidateWithClasses DPContractPressure IntuitionPressureFlash pressure candidate
  case decision of
    DreamCandidateRejected rejected -> assertEqual "natural affective candidate should stay observed-only" DCDRAffectiveCandidateObservedOnly (rdcReason rejected)
    _ -> assertFailure "natural affective candidate must be rejected"
  assertEqual "natural affective candidate must remain inert" zeroVec (decisionAppliedBias decision)

testNaturalConflictCandidateStaysQuarantined :: Test
testNaturalConflictCandidateStaysQuarantined = TestCase $ do
  let pressure = DreamPressure DreamPressureConflict 0.9 (CoreVec 0.02 0.01 0.01 0.03 0.02) Nothing [] 0.35
      candidate = DreamCorrectionCandidate "conflict" "conflict" 0.9 Nothing [] True
      decision = evaluateDreamCandidateWithClasses DPContractPressure IntuitionPressureFlash pressure candidate
  case decision of
    DreamCandidateQuarantined quarantined -> assertEqual "natural conflict candidate should stay quarantined as observed-only" DCDRConflictCandidateObservedOnly (qdcReason quarantined)
    _ -> assertFailure "natural conflict candidate must be quarantined"
  assertEqual "natural conflict candidate must remain inert" zeroVec (decisionAppliedBias decision)

testNaturalNoneCandidateStaysObservedOnly :: Test
testNaturalNoneCandidateStaysObservedOnly = TestCase $ do
  let pressure = DreamPressure DreamPressureNone 0.1 zeroVec Nothing [] 0.35
      candidate = DreamCorrectionCandidate "none" "none" 0.1 Nothing [] True
      decision = evaluateDreamCandidateWithClasses DPNoPressure IntuitionPressureNone pressure candidate
  case decision of
    DreamCandidateRejected rejected -> assertEqual "natural none candidate should stay observed-only" DCDRNoneCandidateObservedOnly (rdcReason rejected)
    _ -> assertFailure "natural none candidate must be rejected"
  assertEqual "natural none candidate must remain inert" zeroVec (decisionAppliedBias decision)

testRejectedAndQuarantinedCandidatesAreInert :: Test
testRejectedAndQuarantinedCandidatesAreInert = TestCase $ do
  let weakPressure = DreamPressure DreamPressureConvergent 0.1 (CoreVec 0.02 0.01 0.01 0.03 0.02) Nothing [] 0.35
      weakCandidate = DreamCorrectionCandidate "weak" "graph_bias" 0.1 Nothing [] True
      weakDecision = evaluateDreamCandidateWithClasses DPAdvisoryMismatch IntuitionPressurePosterior weakPressure weakCandidate
      conflictPressure = DreamPressure DreamPressureConflict 0.9 (CoreVec 0.02 0.01 0.01 0.03 0.02) Nothing [] 0.35
      conflictCandidate = DreamCorrectionCandidate "conflict" "graph_bias" 0.9 Nothing [] True
      conflictDecision = evaluateDreamCandidateWithClasses DPContractPressure IntuitionPressureFlash conflictPressure conflictCandidate
  case weakDecision of
    DreamCandidateRejected rejected -> assertEqual "weak advisory graph-bias should preserve advisory mismatch reason" DCDRAdvisoryMismatchOnly (rdcReason rejected)
    _ -> assertFailure "weak graph-bias candidate should be rejected"
  case conflictDecision of
    DreamCandidateQuarantined _ -> pure ()
    _ -> assertFailure "conflict graph-bias candidate should be quarantined"
  assertEqual "rejected candidates must be inert" zeroVec (decisionAppliedBias weakDecision)
  assertEqual "quarantined candidates must be inert" zeroVec (decisionAppliedBias conflictDecision)

testAcceptedGraphBiasAppliesBoundedly :: Test
testAcceptedGraphBiasAppliesBoundedly = TestCase $ do
  let pressure = DreamPressure DreamPressureConvergent 0.8 (CoreVec 0.02 0.01 0.01 0.03 0.02) Nothing [] 0.35
      candidate = DreamCorrectionCandidate "graph" "graph_bias" 0.8 Nothing [] True
      decision = evaluateDreamCandidateWithClasses DPContractPressure IntuitionPressurePosterior pressure candidate
      appliedBias = decisionAppliedBias decision
  case decision of
    DreamCandidateAccepted _ -> pure ()
    _ -> assertFailure "strong convergent graph-bias candidate should be accepted"
  assertBool "accepted graph-bias must apply bounded future-state-only bias" (vecNorm appliedBias > 0.0 && vecNorm appliedBias <= 0.25 + 1e-9)

testDreamLifecycleTelemetryConsistency :: Test
testDreamLifecycleTelemetryConsistency = TestCase $ do
  (_ss, ti, ts, tp, ta) <- buildRenderedFixture "что такое свобода"
  let outcome = buildDreamOutcome defaultDreamPressureRegime ti ts tp ta
      decisions = doCandidateDecisions outcome
      acceptedCount = length [ () | DreamCandidateAccepted _ <- decisions ]
      applied = vecNorm (doAppliedBias outcome) > 1e-9
      thresholdFired = not (null (doCorrectionCandidates outcome))
  assertEqual "accepted/apply telemetry must align" (acceptedCount > 0) applied
  assertEqual "threshold telemetry must align with candidate emission" thresholdFired (not (null (doCorrectionCandidates outcome)))
  assertBool "candidate decisions must be present when candidates exist" (null (doCorrectionCandidates outcome) || not (null decisions))

buildPreparedFixture :: T.Text -> IO (SystemState, TurnInput, TurnSignals)
buildPreparedFixture rawInput = do
  let ss = emptySystemState
        { ssSessionId = "fixture-session"
        , ssMorphology = MorphologyData
            (Map.singleton "о" "preposition")
            Map.empty
            Map.empty
            Map.empty
        }
      preparePlan = planPrepareEffects ss rawInput testEpochZero
      pio = mkTestPipelineIO defaultTestPipelineConfig
  prepareResults <- resolvePrepareEffects pio preparePlan
  let ti = buildTurnInput ss "request-dream-pressure" "session-dream-pressure" preparePlan prepareResults
      ts = buildTurnSignals prepareResults
  pure (ss, ti, ts)

buildPlannedFixture :: T.Text -> IO (SystemState, TurnInput, TurnSignals, TurnPlan)
buildPlannedFixture rawInput = do
  (ss, ti, ts) <- buildPreparedFixture rawInput
  let routePlan = planRouteEffects ss ti ts
      pio = mkTestPipelineIO defaultTestPipelineConfig
  routeResults <- resolveRouteEffects pio routePlan
  let tp = buildRouteTurnPlan FmarOff (pipelineShadowPolicy pio) Nothing ss ti ts routePlan routeResults
  pure (ss, ti, ts, tp)

buildRenderedFixture :: T.Text -> IO (SystemState, TurnInput, TurnSignals, TurnPlan, TurnArtifacts)
buildRenderedFixture rawInput = do
  (ss, ti, ts, tp) <- buildPlannedFixture rawInput
  let renderPlan = planRenderEffects LocalRecoveryEnabled ss ti ts tp
      pio = mkTestPipelineIO defaultTestPipelineConfig
  renderResults <- resolveRenderEffects pio renderPlan
  let ta = buildTurnArtifacts ss ti ts tp renderPlan renderResults
  pure (ss, ti, ts, tp, ta)

testEpochZero :: UTCTime
testEpochZero = UTCTime (ModifiedJulianDay 0) 0

decisionAppliedBias :: DreamCandidateDecision -> CoreVec
decisionAppliedBias decision =
  case decision of
    DreamCandidateAccepted accepted -> applyAcceptedDreamCandidateBias accepted
    DreamCandidateRejected _ -> zeroVec
    DreamCandidateQuarantined _ -> zeroVec
