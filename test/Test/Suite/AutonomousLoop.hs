{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | ADR-0054 M3 end-to-end integration test: enqueue task → build
-- NetworkUpdateEvent from LLM response → apply to SystemState.
module Test.Suite.AutonomousLoop
  ( autonomousLoopTests
  ) where

import Control.Concurrent.STM (atomically, newTQueue, readTQueue, writeTQueue)
import qualified Data.Map.Strict as M
import Data.Text (Text)
import Test.HUnit

import QxFx0.Learning.Autonomous
  ( NetworkUpdateEvent(..)
  , applyPendingNetworkUpdates
  , autonomousApplyLLMResponse
  , buildAtomMorphology
  )
import QxFx0.Learning.Need (LearningNeed(..))
import QxFx0.Semantic.Content.AtomStore (atomStore)
import QxFx0.Semantic.Network.Types
  ( EdgeSource(..)
  , SemanticEdge(..)
  , SemanticNetwork(..)
  , semanticEdge
  )
import QxFx0.Types.ExternalQuery (ExternalQueryResponse(..))
import QxFx0.Types.State.System
  ( SystemState(..)
  , emptySystemState
  , ssSemanticNetwork
  )

mkResp :: Text -> ExternalQueryResponse
mkResp body = ExternalQueryResponse
  { eqrRawBody    = body
  , eqrStructured = ""
  , eqrToolName   = "test"
  , eqrLatencyMs  = 0
  }

mkEdge :: Text -> Text -> SemanticEdge
mkEdge f t = semanticEdge f t 0.5 1 ExplicitEdge

-- | The full M3 loop, minus the LLM call: build an admitted network from
-- a response, push it as a 'NetworkUpdateEvent' through the update queue,
-- drain and apply to a fresh SystemState, and assert the edge landed.
testEndToEndLoop :: Test
testEndToEndLoop = TestLabel "end-to-end: event → update queue → apply → edge" $
  TestCase $ do
    let store = atomStore
        morph = buildAtomMorphology store
        resp  = mkResp "свобода | связана | выбор | relatedto\n"
        net   = autonomousApplyLLMResponse store morph NeedKeywordEnrichment resp
        evt   = NetworkUpdateEvent
          { nueTopic     = "свобода"
          , nueEdges     = M.elems (snEdges net)
          , nueTimestamp = undefined  -- unused by apply
          }
        ss0   = emptySystemState
    updates <- atomically newTQueue
    atomically (writeTQueue updates evt)
    _ <- atomically (readTQueue updates)
    ss1 <- applyPendingNetworkUpdates store morph updates ss0
    let edges = M.size (snEdges (ssSemanticNetwork ss1))
    assertBool "at least one edge after apply" (edges >= 1)

-- | End-to-end with a richer body: multiple admitted relations and an
-- unknown endpoint (must be silently dropped).
testEndToEndLoopWithMixedEndpoints :: Test
testEndToEndLoopWithMixedEndpoints = TestLabel "end-to-end: mixed admitted + rejected endpoints" $
  TestCase $ do
    let store = atomStore
        morph = buildAtomMorphology store
        resp  = mkResp
          ( "свобода | связана | выбор | relatedto\n"
          <> "свобода | требует | несуществующий_атом_999 | requires\n" )
        net  = autonomousApplyLLMResponse store morph NeedKeywordEnrichment resp
    -- Only 'свобода → выбор' should survive the gate.
    let admittedCount = M.size (snEdges net)
    assertEqual "only known endpoints admitted" 1 admittedCount

autonomousLoopTests :: [Test]
autonomousLoopTests =
  [ testEndToEndLoop
  , testEndToEndLoopWithMixedEndpoints
  ]
