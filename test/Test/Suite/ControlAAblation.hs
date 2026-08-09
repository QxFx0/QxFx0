{-# LANGUAGE OverloadedStrings #-}

{-|
Description : B2 Control-A ablation hooks (structure-ablated, fluency-matched).
Anti-rot pins for the five QXFX0_CONTROL_A_DISABLE_* env hooks:
semantic-first/content (route), repair (route), essence + admission (finalize).
-}
module Test.Suite.ControlAAblation
  ( controlAAblationTests
  ) where

import Test.HUnit (Test(..), assertBool, assertEqual, assertFailure)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.HashMap.Strict as HashMap
import qualified Data.Sequence as Seq
import qualified Data.Vector as V

import QxFx0.Core.PipelineIO
  ( PipelineIO
  , TestPipelineConfig(..)
  , defaultTestPipelineConfig
  , mkTestPipelineIO
  , pipelineShadowPolicy
  )
import QxFx0.Core.TurnPipeline.Protocol
  ( planRouteEffects
  , resolveRouteEffects
  , buildRouteTurnPlan
  , TurnInput(..)
  , TurnEffectRequest(..)
  , TurnEffectResult(..)
  )
import QxFx0.Core.TurnPipeline.Finalize.State (buildNextSystemState, computeNextEssence)
import QxFx0.Core.TurnPipeline.Protocol
  ( planRouteEffects
  , resolveRouteEffects
  , buildRouteTurnPlan
  , TurnInput(..)
  )
import QxFx0.Core.TurnPipeline.Protocol
  ( routeTurnPlan
  , readControlAAblation
  )
import QxFx0.Types.State.SemanticCommitment
  ( CommitmentEngagement(..)
  , FactualClaimPayload(..)
  , CommitmentId(..)
  , CommitmentOrigin(..)
  , TurnSeq(..)
  , SemanticCommitmentStore(..)
  , emptySemanticCommitmentStore
  , LineageEvent(..)
  )
import QxFx0.Core.TurnPipeline.Types
  ( ControlAAblation(..)
  , defaultControlAAblation
  , controlAEnvVarNames
  , TurnPlan(..)
  )
import QxFx0.Core.CommitmentStoreAdmission (CommitmentStoreAdmissionDecision(..))
import QxFx0.Self.Essence
  ( Essence(..)
  , EssenceTrajectory(..)
  , emptyTrajectory
  , shouldCommit
  , defaultEssenceModulation
  , CommitmentTrigger(..)
  )
import QxFx0.Core.FMAR (FmarMode(..))
import QxFx0.Runtime.StateDefaults (emptySystemState)
import QxFx0.Types
  ( ssSessionId
  , ssSemanticCommitments
  , ssDreamState
  , MeaningAtom(..)
  , AtomTag(..)
  , AtomSet(..)
  , Register(..)
  , ssMeaningGraph
  , mkVerdict
  , CanonicalMoveFamily(..)
  )
import Test.Support.TurnPipelineFixtures
  ( buildPreparedFixture
  , buildPreparedFixtureWithState
  , buildPlannedFixture
  , buildRenderedFixture
  , testProtocolPipelineIO
  , testProtocolInterpreter
  )

-- | PipelineIO whose env reads are driven by a fixed map (deterministic
-- surrogate for process env in the B2 generation harness).
envPio :: Map.Map Text Text -> PipelineIO
envPio env = mkTestPipelineIO defaultTestPipelineConfig
  { tpcInterpreter = \req ->
      case req of
        TurnReqReadEnv key -> pure (TurnResReadEnv (Map.lookup key env))
        other              -> testProtocolInterpreter other
  }

expectedEnvNames :: [Text]
expectedEnvNames =
  [ "QXFX0_CONTROL_A_DISABLE_SEMANTIC_FIRST"
  , "QXFX0_CONTROL_A_DISABLE_ESSENCE"
  , "QXFX0_CONTROL_A_DISABLE_ADMISSION"
  , "QXFX0_CONTROL_A_DISABLE_REPAIR"
  , "QXFX0_CONTROL_A_DISABLE_CONTENT"
  ]

testDefaultsAndEnvNames :: Test
testDefaultsAndEnvNames = TestLabel "Control-A defaults and env key list" $ TestCase $ do
  assertEqual "default ablation is all-off"
    (ControlAAblation False False False False False)
    defaultControlAAblation
  assertEqual "env var names match the five hooks"
    expectedEnvNames
    controlAEnvVarNames

testReader :: Test
testReader = TestLabel "Control-A ablation reader maps env to flags" $ TestCase $ do
  allOn <- readControlAAblation (envPio (Map.fromList [(k, "1") | k <- controlAEnvVarNames]))
  assertEqual "all env vars set -> all five flags on"
    (ControlAAblation True True True True True)
    allOn
  noneOn <- readControlAAblation (envPio Map.empty)
  assertEqual "no env vars -> all flags off"
    defaultControlAAblation
    noneOn
  essenceOnly <- readControlAAblation (envPio (Map.singleton "QXFX0_CONTROL_A_DISABLE_ESSENCE" "1"))
  assertEqual "single env var -> only that flag"
    (defaultControlAAblation { caDisableEssence = True })
    essenceOnly

testEssenceAblation :: Test
testEssenceAblation = TestLabel "Control-A essence ablation bypasses shouldCommit" $ TestCase $ do
  (ss, ti0, ts, tp) <- buildPlannedFixture "какой смысл в свободе?"
  -- 0.80 angst: above the 0.75 commitment threshold; worst-case single
  -- decay step (0.02) keeps it >= 0.75, so the live path must commit.
  let traj = emptyTrajectory { etAngstLevel = 0.80 }
      ti = ti0 { tiEssence = EssenceUncommitted traj }
      (nextAblated, triggerAblated) = computeNextEssence True ss ti tp
      (_nextLive, triggerLive) = computeNextEssence False ss ti tp
  assertBool "positive control: trajectory would commit without ablation"
    (shouldCommit defaultEssenceModulation traj == Just TriggerAngstThreshold)
  assertEqual "ablated: no commitment trigger" Nothing triggerAblated
  assertBool "ablated: trajectory stays uncommitted" (isUncommitted nextAblated)
  assertBool "ablated: trajectory is still witnessed"
    (not (Seq.null (etWitnesses (uncommittedTrajectory nextAblated))))
  assertEqual "live: commitment triggers (angst 0.80 >= 0.75)"
    (Just TriggerAngstThreshold) triggerLive
  where
    isUncommitted (EssenceUncommitted _) = True
    isUncommitted _ = False
    uncommittedTrajectory (EssenceUncommitted t) = t
    uncommittedTrajectory _ = error "unreachable"

testRepairAblation :: Test
testRepairAblation = TestLabel "Control-A repair ablation routes challenges generically" $ TestCase $ do
  let pio = testProtocolPipelineIO
      input = "разве свобода иллюзорна?"
  (ss, ti0, ts) <- buildPreparedFixtureWithState storeState input
  -- A Contradiction-tagged atom overlapping the engaged topic makes the
  -- challenge turn contradict the stored commitment ("свобода есть право
  -- человека"), which is what the repair path reacts to in Finalize.
  let ti = ti0 { tiAtomSet = contradictionAtomSet, tiBestTopic = "свобода" }
      routePlan = planRouteEffects ss ti ts
  routeResults <- resolveRouteEffects pio routePlan
  let tpRepairOn = buildRouteTurnPlan FmarOff (pipelineShadowPolicy pio) Nothing False False ss ti ts routePlan routeResults
      tpRepairOff = buildRouteTurnPlan FmarOff (pipelineShadowPolicy pio) Nothing False True ss ti ts routePlan routeResults
  assertBool "repair on: challenge engages contradiction (repair path)"
    (ceContradicted (tpCommitmentEngagement tpRepairOn))
  assertBool "repair off: challenge routed to generic response, no repair path"
    (not (ceContradicted (tpCommitmentEngagement tpRepairOff)))
  assertEqual "repair on: challenge family stays CMConfront"
    CMConfront (tpFamily tpRepairOn)
  where
    contradictionAtom = MeaningAtom
      { maText = "нет свободы"
      , maTag = Contradiction "свобода" "нет"
      , maEmbedding = V.empty
      }
    contradictionAtomSet = AtomSet { asAtoms = [contradictionAtom], asLoad = 0.0, asRegister = Neutral }
    storeState =
      let payload = FactualClaimPayload
            { fcpStatement = "свобода есть право человека"
            , fcpConfidence = 0.9
            , fcpOrigin = OriginParser "test"
            , fcpTurnSeq = TurnSeq 1
            , fcpDeps = []
            , fcpTopic = "свобода"
            }
          store = emptySemanticCommitmentStore
            { scsActive = HashMap.singleton (CommitmentId 1) (payload, TurnSeq 1)
            , scsLineage = HashMap.singleton (CommitmentId 1) [LineageCommitted (TurnSeq 1)]
            , scsNextId = 2
            }
      in emptySystemState
           { ssSessionId = "fixture-session"
           , ssSemanticCommitments = Just store
           }

testSemanticContentAblation :: Test
testSemanticContentAblation = TestLabel "Control-A semantic-first/content ablation via env" $ TestCase $ do
  let pio = testProtocolPipelineIO
  (ss, ti, ts) <- buildPreparedFixture "что такое свобода?"
  let routePlan = planRouteEffects ss ti ts
  routeResults <- resolveRouteEffects pio routePlan
  tpSemantic <- routeTurnPlan (envPio (Map.singleton "QXFX0_CONTROL_A_DISABLE_SEMANTIC_FIRST" "1")) ss ti ts routePlan routeResults
  assertBool "semantic-first env -> semantic path disabled"
    (tpSemanticFirstDisabled tpSemantic)
  tpContent <- routeTurnPlan (envPio (Map.singleton "QXFX0_CONTROL_A_DISABLE_CONTENT" "1")) ss ti ts routePlan routeResults
  assertBool "content env also disables the semantic path (template-only)"
    (tpSemanticFirstDisabled tpContent)
  tpLive <- routeTurnPlan pio ss ti ts routePlan routeResults
  assertBool "no ablation -> semantic path enabled"
    (not (tpSemanticFirstDisabled tpLive))

testAdmissionAblation :: Test
testAdmissionAblation = TestLabel "Control-A admission ablation bypasses CTS-42" $ TestCase $ do
  (ss, ti, ts, tp, ta) <- buildRenderedFixture "свобода предполагает ответственность"
  let dream = ssDreamState ss
      graph = ssMeaningGraph ss
      family = tpFamily tp
      verdict = mkVerdict family
      run ab = buildNextSystemState (\_ h -> h) Nothing ab ss ti ts tp ta dream graph family verdict 0 False
      (_, _, bypassDecision, _) = run (defaultControlAAblation { caDisableAdmission = True })
      (_, _, liveDecision, _) = run defaultControlAAblation
  assertEqual "admission bypass: every claim admitted as canonical"
    CsaAdmitCanonical bypassDecision
  assertBool "unablated decision stays in the CTS-42 decision set"
    (liveDecision == CsaAdmitCanonical || liveDecision == CsaSuppress)

controlAAblationTests :: [Test]
controlAAblationTests =
  [ testDefaultsAndEnvNames
  , testReader
  , testEssenceAblation
  , testRepairAblation
  , testSemanticContentAblation
  , testAdmissionAblation
  ]
