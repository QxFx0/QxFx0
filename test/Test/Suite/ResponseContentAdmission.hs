{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.ResponseContentAdmission
Description : CTS-41 anti-rot tests for constitution-aware response content admission.

7 unit tests covering all 4 decision branches:
1. NonExpansiveRecoverySurface + CMGround           → RadRerouteClarify
2. NonExpansiveRecoverySurface + CMClarify           → RadAdmitPlans
3. ShadowSeverityAdvisory + any legitScore           → RadAdmitPlans
4. ShadowSeverityContract + legitScore < threshold   → RadWeakenStance
5. ShadowSeverityContract + legitScore ≥ threshold   → RadSoftenExplicitness
6. ShadowSeveritySafety   + legitScore < threshold   → RadWeakenStance
7. AssembledSurfacePreserved + ShadowSeverityClean   → RadAdmitPlans
-}
module Test.Suite.ResponseContentAdmission
  ( responseContentAdmissionTests
  ) where

import Test.HUnit (Test (..), assertBool, assertEqual)

import QxFx0.Core.ResponseContentAdmission
  ( ResponseContentAdmissionInput(..)
  , ResponseContentAdmissionDecision(..)
  , AdmittedResponseContent(..)
  , admitResponseContent
  )
import QxFx0.Types
  ( TruthContractStatus(..)
  , ResponseMeaningPlan(..)
  , ResponseContentPlan(..)
  , CanonicalMoveFamily(..)
  , StanceMarker(..)
  , ContentMove(..)
  , RenderStyle(..)
  , SpeechAct(..)
  , SemanticRelation(..)
  , AnswerStrategy(..)
  , EpistemicStatus(..)
  , ContractProvenance(..)
  , DepthMode(..)
  , IllocutionaryForce(..)
  , emptyMicroPlan
  , emptyResponseSensePlan
  , MicroPlan(..)
  )
import QxFx0.Types.Sense (ImplicationDirection(..))
import QxFx0.Types.ShadowDivergence (ShadowDivergenceSeverity(..))
import QxFx0.Types.Thresholds (legitimacyRecoveryThreshold)

-- | Minimal RMP fixture with configurable family, stance, commitment, and explicitness.
mkRMP :: CanonicalMoveFamily -> StanceMarker -> Double -> Double -> ResponseMeaningPlan
mkRMP family stance commitment explicitness =
  ResponseMeaningPlan
    { rmpFamily = family
    , rmpForce = IFAssert
    , rmpSpeechAct = Assert
    , rmpRelation = SRGround
    , rmpStrategy = DirectThenGround
    , rmpStance = stance
    , rmpEpistemic = Known 0.5
    , rmpTopic = "test-topic"
    , rmpPrimaryClaim = "test-claim"
    , rmpPrimaryClaimAst = Nothing
    , rmpScope = Nothing
    , rmpContrastAxis = ""
    , rmpImplicationDirection = DirForward
    , rmpProvenance = BuiltClaim
    , rmpTruthContractStatus = AssembledSurfacePreserved
    , rmpCommitmentStrength = commitment
    , rmpDepthMode = DeepDepth
    , rmpSensePlan = emptyResponseSensePlan
    , rmpMicroPlan = emptyMicroPlan { mpExplicitness = explicitness }
    }

-- | Minimal RCP fixture with configurable family and style.
mkRCP :: CanonicalMoveFamily -> RenderStyle -> ResponseContentPlan
mkRCP family style =
  ResponseContentPlan
    { rcpFamily = family
    , rcpOpening = MoveGroundKnown
    , rcpCore = MoveGroundKnown
    , rcpLimit = MoveGroundKnown
    , rcpContinuation = MoveGroundKnown
    , rcpStyle = style
    }

-- | Minimal input fixture with configurable truth status, severity, and legit score.
mkInput :: TruthContractStatus -> ShadowDivergenceSeverity -> Double -> ResponseContentAdmissionInput
mkInput truth severity legit =
  ResponseContentAdmissionInput
    { rcaiTruthContractStatus = truth
    , rcaiShadowDivergenceSeverity = severity
    , rcaiLegitScore = legit
    }

responseContentAdmissionTests :: [Test]
responseContentAdmissionTests =
  [ -- Test 1: NonExpansiveRecoverySurface + CMGround → RadRerouteClarify
    TestLabel "CTS-41: NonExpansiveRecoverySurface + CMGround → RadRerouteClarify" $
      TestCase $ do
        let input = mkInput NonExpansiveRecoverySurface ShadowSeverityClean 0.8
            rmp = mkRMP CMGround Commit 0.7 0.5
            rcp = mkRCP CMGround StyleStandard
            AdmittedResponseContent dec admittedRmp admittedRcp = admitResponseContent input rmp rcp
        assertEqual "decision should be RadRerouteClarify" RadRerouteClarify dec
        assertEqual "rcpFamily should become CMClarify" CMClarify (rcpFamily admittedRcp)
        assertBool "all ContentMove fields should be MoveClarifyDisambiguate" $
          rcpOpening admittedRcp == MoveClarifyDisambiguate
          && rcpCore admittedRcp == MoveClarifyDisambiguate
          && rcpLimit admittedRcp == MoveClarifyDisambiguate
          && rcpContinuation admittedRcp == MoveClarifyDisambiguate
        assertEqual "rcpStyle should become StyleStandard" StyleStandard (rcpStyle admittedRcp)

  -- Test 2: NonExpansiveRecoverySurface + CMClarify → RadAdmitPlans (already in recovery mode)
  , TestLabel "CTS-41: NonExpansiveRecoverySurface + CMClarify → RadAdmitPlans" $
      TestCase $ do
        let input = mkInput NonExpansiveRecoverySurface ShadowSeverityClean 0.8
            rmp = mkRMP CMClarify Commit 0.7 0.5
            rcp = mkRCP CMClarify StyleStandard
            AdmittedResponseContent dec admittedRmp admittedRcp = admitResponseContent input rmp rcp
        assertEqual "decision should be RadAdmitPlans" RadAdmitPlans dec
        assertEqual "RMP should be unchanged" (rmpFamily rmp) (rmpFamily admittedRmp)
        assertEqual "RCP should be unchanged" (rcpFamily rcp) (rcpFamily admittedRcp)

  -- Test 3: ShadowSeverityAdvisory + any legitScore → RadAdmitPlans (advisory doesn't trigger)
  , TestLabel "CTS-41: ShadowSeverityAdvisory → RadAdmitPlans" $
      TestCase $ do
        let input = mkInput AssembledSurfacePreserved ShadowSeverityAdvisory 0.3
            rmp = mkRMP CMGround Commit 0.7 0.5
            rcp = mkRCP CMGround StyleStandard
            AdmittedResponseContent dec _ _ = admitResponseContent input rmp rcp
        assertEqual "advisory severity should admit plans" RadAdmitPlans dec

  -- Test 4: ShadowSeverityContract + legitScore < threshold → RadWeakenStance
  , TestLabel "CTS-41: ShadowSeverityContract + low legit → RadWeakenStance" $
      TestCase $ do
        let input = mkInput AssembledSurfacePreserved ShadowSeverityContract 0.2
            rmp = mkRMP CMGround Commit 0.7 0.5
            rcp = mkRCP CMGround StyleStandard
            AdmittedResponseContent dec admittedRmp _ = admitResponseContent input rmp rcp
        assertEqual "decision should be RadWeakenStance" RadWeakenStance dec
        assertEqual "stance should become HoldBack" HoldBack (rmpStance admittedRmp)
        assertBool "commitment should be min(0.7, 0.3) = 0.3" $
          rmpCommitmentStrength admittedRmp <= 0.3

  -- Test 5: ShadowSeverityContract + legitScore ≥ threshold → RadSoftenExplicitness
  , TestLabel "CTS-41: ShadowSeverityContract + high legit → RadSoftenExplicitness" $
      TestCase $ do
        let input = mkInput AssembledSurfacePreserved ShadowSeverityContract 0.8
            rmp = mkRMP CMGround Commit 0.7 0.5
            rcp = mkRCP CMGround StyleStandard
            AdmittedResponseContent dec admittedRmp _ = admitResponseContent input rmp rcp
        assertEqual "decision should be RadSoftenExplicitness" RadSoftenExplicitness dec
        assertBool "explicitness should be halved: 0.5 * 0.5 = 0.25" $
          mpExplicitness (rmpMicroPlan admittedRmp) == 0.25

  -- Test 6: ShadowSeveritySafety + legitScore < threshold → RadWeakenStance
  , TestLabel "CTS-41: ShadowSeveritySafety + low legit → RadWeakenStance" $
      TestCase $ do
        let input = mkInput AssembledSurfacePreserved ShadowSeveritySafety 0.1
            rmp = mkRMP CMGround Firm 0.9 0.8
            rcp = mkRCP CMGround StyleFormal
            AdmittedResponseContent dec admittedRmp _ = admitResponseContent input rmp rcp
        assertEqual "decision should be RadWeakenStance" RadWeakenStance dec
        assertEqual "stance should become HoldBack" HoldBack (rmpStance admittedRmp)
        assertBool "commitment should be min(0.9, 0.3) = 0.3" $
          rmpCommitmentStrength admittedRmp <= 0.3

  -- Test 7: AssembledSurfacePreserved + ShadowSeverityClean → RadAdmitPlans (passthrough)
  , TestLabel "CTS-41: AssembledSurfacePreserved + ShadowSeverityClean → RadAdmitPlans" $
      TestCase $ do
        let input = mkInput AssembledSurfacePreserved ShadowSeverityClean 0.9
            rmp = mkRMP CMGround Commit 0.7 0.5
            rcp = mkRCP CMGround StyleStandard
            AdmittedResponseContent dec admittedRmp admittedRcp = admitResponseContent input rmp rcp
        assertEqual "decision should be RadAdmitPlans" RadAdmitPlans dec
        assertEqual "RMP should be unchanged" (rmpFamily rmp) (rmpFamily admittedRmp)
        assertEqual "RCP should be unchanged" (rcpFamily rcp) (rcpFamily admittedRcp)
  ]
