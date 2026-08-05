{-# LANGUAGE OverloadedStrings #-}
module Test.Suite.CuratedOntologyIntegration
  ( curatedOntologyIntegrationTests
  ) where

import qualified Data.Map.Strict as M
import Test.HUnit

import QxFx0.Types
import QxFx0.Types.State.System
import QxFx0.Core.TurnPipeline.Types
import QxFx0.Core.TurnPipeline.Finalize.State (buildNextSystemState)
import QxFx0.Semantic.ContentSelector
import QxFx0.Semantic.Content
import QxFx0.Runtime.Session.Bootstrap (withBootstrappedSession)
import QxFx0.Runtime.Session.Types (Session(..))
import Test.Support.TurnPipelineFixtures (buildRenderedFixtureWithState)

-- | Integration test: bootstrap -> turn -> next turn.
-- Verifies that curated predicates and ontology are wired in and preserved.
testCuratedAndOntologyPersistence :: Test
testCuratedAndOntologyPersistence = TestLabel "Curated and ontology persistence integration" $ TestCase $ do
  let sessId = "test-integration-curated-lifecycle"

  -- We run the real bootstrap.
  withBootstrappedSession True sessId $ \sess -> do
    let ss = sessSystemState sess
        selector = ssContentSelector ss
        ontology = ssOntology ss

  -- 1. Verify that bootstrap loaded curated predicates (e.g., "смысл" from curated_predicates.jsonl)
  -- and the ontology.
    assertBool "Selector should have ontology" (isJust (csOntology selector))
    assertBool "Curated topic 'смысл' should be present in initial selector"
               (M.member "смысл" (csTopicPredicates selector))

  -- 2. Simulate a turn to trigger buildNextSystemState.
    (ss', ti, ts, tp, ta) <- buildRenderedFixtureWithState ss "что такое смысл?"
    let dream = ssDreamState ss'
        graph = ssMeaningGraph ss'
        family = tpFamily tp
        verdict = mkVerdict family
        consec = 0
        feedback = False

    let (nextSs, _, _, _) = buildNextSystemState
                              (\_ h -> h) -- history
                              Nothing      -- claim
                              ss
                              ti
                              ts
                              tp
                              ta
                              dream
                              graph
                              family
                              verdict
                              consec
                              feedback

  -- 3. Verify persistence in the next state.
    let nextSelector = ssContentSelector nextSs

    assertEqual "Ontology must be preserved in next selector"
                (Just ontology)
                (csOntology nextSelector)

    assertBool "Curated topic 'смысл' must be preserved in next selector"
               (M.member "смысл" (csTopicPredicates nextSelector))

isJust :: Maybe a -> Bool
isJust (Just _) = True
isJust Nothing  = False

curatedOntologyIntegrationTests :: [Test]
curatedOntologyIntegrationTests =
  [ testCuratedAndOntologyPersistence
  ]
