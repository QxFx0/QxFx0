{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.PhaseM2d
Description : Unit tests for Phase 2.5 (M2d) + 5.5e + RecoveryConatusGate.

Pure tests covering the artefacts introduced by:

  * /Phase 2.5 (M2d)/ — runtime Conatus replaces the placeholder
    in 'PrepareEffectPlan' construction; 'psConatusEnergy' carries
    the canonical per-turn energy; 'PrepareReqConsciousness' \/
    'PrepareReqIntuition' carry the energy through to the handlers.

  * /Phase 5.5e/ — 'renderSalienceDriver' exposes a stable
    snake_case tag for every 'SalienceDriver' variant.

  * /RecoveryConatusGate/ — dedicated 'LocalRecoveryCause' variant
    and matching 'renderLocalRecoveryCause' \/ 'ToJSON' rendering.

Tests are pure and require no IO or pipeline fixtures beyond
'emptySystemState' and a minimal 'MorphologyData'.

See:
  * @docs\/adr\/0010-salience-controller.md@ §5
  * @docs\/THEORY.md@ §4.1
  * commits e70fade (M2d), fc4cc0a (5.5e), 2be7506 (RecoveryConatusGate)
-}
module Test.Suite.PhaseM2d
  ( phaseM2dTests
  ) where

import qualified Data.Map.Strict as Map
import Data.Aeson (Value (String), toJSON)
import Test.HUnit (Test (..), (@?=), assertBool, assertFailure)

import QxFx0.Core.TurnPipeline
  ( PrepareEffectPlan (..)
  , PrepareEffectRequest (..)
  , PrepareStatic (..)
  , buildPrepareEffectPlan
  )
import QxFx0.Self.Blanket (computeSelfBlanket)
import QxFx0.Self.Conatus
  ( ConatusEnergy (..)
  , computeConatusEnergy
  )
import QxFx0.Self.Invariants (checkInitialBlanket)
import QxFx0.Self.Salience
  ( SalienceDriver (..)
  , renderSalienceDriver
  )
import QxFx0.Types
  ( MorphologyData (..)
  , SystemState (..)
  )
import QxFx0.Types.Recovery
  ( LocalRecoveryCause (..)
  , renderLocalRecoveryCause
  )
import QxFx0.Types.State (emptySystemState)

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

-- | A minimal 'SystemState' that satisfies 'checkInitialBlanket'
-- (non-empty session id + non-empty morphology). Mirrors
-- 'Test.Suite.SelfBlanket.viableSystemState'.
viableSystemState :: SystemState
viableSystemState =
  let base  = emptySystemState
      morph = MorphologyData
        (Map.singleton "о" "preposition")
        Map.empty
        Map.empty
        Map.empty
   in base
        { ssSessionId  = "phaseM2d_demo"
        , ssMorphology = morph
        }

-- ---------------------------------------------------------------------------
-- Test-suite entry point
-- ---------------------------------------------------------------------------

phaseM2dTests :: [Test]
phaseM2dTests =
  [ -- Phase 5.5e — renderSalienceDriver coverage
    TestLabel "renderSalienceDriver covers all 7 variants with stable snake_case tags" $
      TestCase $ do
        renderSalienceDriver DrivenByResonance       @?= "resonance"
        renderSalienceDriver DrivenByAtmosphere      @?= "atmosphere"
        renderSalienceDriver DrivenByConsolidation   @?= "consolidation"
        renderSalienceDriver DrivenByCounterfactual  @?= "counterfactual"
        renderSalienceDriver DrivenByFieldConfidence @?= "field_confidence"
        renderSalienceDriver DrivenByConatusGate     @?= "conatus_gate"
        renderSalienceDriver DrivenByDefault         @?= "default"

    -- RecoveryConatusGate — text rendering and JSON tag
  , TestLabel "renderLocalRecoveryCause RecoveryConatusGate renders to conatus_gate" $
      TestCase $
        renderLocalRecoveryCause RecoveryConatusGate @?= "conatus_gate"

  , TestLabel "ToJSON RecoveryConatusGate produces String \"conatus_gate\"" $
      TestCase $
        toJSON RecoveryConatusGate @?= String "conatus_gate"

  , TestLabel "renderLocalRecoveryCause RecoveryRuntimeDegraded preserves runtime_degraded after split" $
      TestCase $
        renderLocalRecoveryCause RecoveryRuntimeDegraded @?= "runtime_degraded"

    -- Phase 2.5 (M2d) — psConatusEnergy invariant
  , TestLabel "buildPrepareEffectPlan stores psConatusEnergy matching direct computation" $
      TestCase $ do
        let plan       = buildPrepareEffectPlan viableSystemState "пробный ввод"
            blanket    = computeSelfBlanket viableSystemState
            violations = checkInitialBlanket blanket
            expected   = computeConatusEnergy blanket violations
        psConatusEnergy (pepStatic plan) @?= expected

  , TestLabel "buildPrepareEffectPlan threads conatusEnergy into PrepareReqConsciousness" $
      TestCase $ do
        let plan     = buildPrepareEffectPlan viableSystemState "пробный ввод"
            expected = psConatusEnergy (pepStatic plan)
        case pepConsciousnessRequest plan of
          PrepareReqConsciousness _ _ _ ce ->
            ce @?= expected
          _ ->
            assertFailure "pepConsciousnessRequest must be PrepareReqConsciousness"

  , TestLabel "buildPrepareEffectPlan threads conatusEnergy into PrepareReqIntuition" $
      TestCase $ do
        let plan     = buildPrepareEffectPlan viableSystemState "пробный ввод"
            expected = psConatusEnergy (pepStatic plan)
        case pepIntuitionRequest plan of
          PrepareReqIntuition _ _ _ _ ce ->
            ce @?= expected
          _ ->
            assertFailure "pepIntuitionRequest must be PrepareReqIntuition"

  , TestLabel "viable SystemState yields a healthy ConatusEnergy (gate does not fire)" $
      TestCase $ do
        let plan = buildPrepareEffectPlan viableSystemState "пробный ввод"
            ce   = psConatusEnergy (pepStatic plan)
        assertBool
          ("ceScalar should be >= 0 on a viable state, got " ++ show (ceScalar ce))
          (ceScalar ce >= 0.0)
  ]
