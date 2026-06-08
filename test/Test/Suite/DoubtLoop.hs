{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.DoubtLoop
Description : WP-D anti-rot guard for the doubt metacognition loop.

Per ADR-0042, the consumer must stay connected. 'computeDoubt' is the living
producer of 'clDoubtScore' (previously initialised to 0.0 and never written),
derived from the salience verdict. Gated by the default-off 'doubtLoopActive'
flag (ADR-0045).

WP-D R-D2: Doubt influences routing (family selection) and explicitness.
Anti-rot tests verify that removing the consumer breaks observable behavior.
-}
module Test.Suite.DoubtLoop
  ( doubtLoopTests
  ) where

import Test.HUnit (Test (..), assertBool, assertEqual)

import QxFx0.Core.ConsciousnessLoop
  ( computeDoubt
  , doubtLoopActive
  , doubtSuppressionThreshold
  )
import QxFx0.Self.Salience
  ( Salience(..)
  , SalienceDriver(..)
  )
import QxFx0.Core.SensePlan (buildMicroPlan)
import QxFx0.Types
  ( CanonicalMoveFamily(..)
  , DialogueCommitmentLedger(..)
  , DialoguePhase(..)
  , ResponseSensePlan(..)
  , SenseOperator(..)
  , MicroPlan(..)
  , emptySenseVector
  , emptyResponseSensePlan
  )
import QxFx0.Types.State.DialogueDevelopment (emptyDialogueThread)

-- | Minimal test fixtures
emptyDialogueCommitmentLedger :: DialogueCommitmentLedger
emptyDialogueCommitmentLedger = DialogueCommitmentLedger []

-- | A salience verdict with a chosen confidence and driver.
mkSalience :: Double -> SalienceDriver -> Salience
mkSalience conf drv = Salience
  { salienceHolisticBias = 0.5
  , salienceConfidence   = conf
  , salienceDriver       = drv
  }

doubtLoopTests :: [Test]
doubtLoopTests =
  [ -- WP-D anti-rot (producer): computeDoubt must turn a low-confidence verdict
    -- into high doubt. Deleting the (1 - confidence) derivation breaks this.
    TestLabel "WP-D: computeDoubt is the complement of confidence" $
      TestCase $ do
        let lowConf  = computeDoubt (mkSalience 0.1 DrivenByResonance)
            highConf = computeDoubt (mkSalience 0.95 DrivenByResonance)
        assertBool "low confidence => high doubt" (lowConf >= 0.85)
        assertBool "high confidence => low doubt" (highConf <= 0.15)
        assertBool "doubt is monotone in (1 - confidence)" (lowConf > highConf)

    -- Conatus-gate verdicts force high doubt (structural threat).
  , TestLabel "WP-D: Conatus gate forces high doubt" $
      TestCase $
        assertBool "conatus gate => doubt >= 0.9"
          (computeDoubt (mkSalience 0.8 DrivenByConatusGate) >= 0.9)

    -- Counterfactual (ambiguity) driver amplifies doubt above the base.
  , TestLabel "WP-D: counterfactual driver amplifies doubt" $
      TestCase $ do
        let base = computeDoubt (mkSalience 0.5 DrivenByResonance)
            ambi = computeDoubt (mkSalience 0.5 DrivenByCounterfactual)
        assertBool "ambiguity raises doubt above base" (ambi > base)

    -- The suppression threshold is in range and the flag is now on (promoted).
  , TestLabel "WP-D: doubt loop is promoted with an in-range threshold" $
      TestCase $ do
        assertEqual "promoted to default-on (ADR-0045, 2026-06-04)" True doubtLoopActive
        assertBool "threshold in (0,1]"
          (doubtSuppressionThreshold > 0.0 && doubtSuppressionThreshold <= 1.0)

    -- WP-D R-D2 anti-rot (consumer): High doubt must reduce explicitness.
    -- Deleting the doubtPenalty logic in buildMicroPlan breaks this.
  , TestLabel "WP-D anti-rot: high doubt reduces explicitness" $
      TestCase $ do
        let thread = emptyDialogueThread
            ledger = emptyDialogueCommitmentLedger
            phase = Exploring
            sensePlan = ResponseSensePlan
              { rspInputVector = emptySenseVector
              , rspChosenOperator = OpGround
              , rspPreservedAxes = []
              , rspShiftReason = "test"
              , rspDistance = 0
              }
            lowDoubt = 0.1
            highDoubt = 0.9
            mpLow = buildMicroPlan thread ledger phase sensePlan lowDoubt
            mpHigh = buildMicroPlan thread ledger phase sensePlan highDoubt
        -- High doubt (0.9 >= 0.75) should reduce explicitness
        assertBool "high doubt reduces explicitness below low doubt"
          (mpExplicitness mpHigh < mpExplicitness mpLow)
        -- The reduction should be significant (at least 0.1)
        assertBool "doubt penalty is significant"
          ((mpExplicitness mpLow - mpExplicitness mpHigh) >= 0.1)
  ]
