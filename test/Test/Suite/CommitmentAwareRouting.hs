{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.CommitmentAwareRouting
Description : SUBJECT-SEAM-1 witness — commitment detection and routing.

- Phase 1: detect commitment engagement and contradiction, trace it, update ledger.
- Phase 2: when contradicted, route family hint to CMReflect.
-}
module Test.Suite.CommitmentAwareRouting
  ( commitmentAwareRoutingTests
  ) where

import Test.HUnit (Test (..), assertEqual, assertBool)
import Data.Maybe (isJust, fromJust)
import qualified Data.HashMap.Strict as HashMap
import qualified Data.Text as T
import qualified Data.Vector as V

import QxFx0.Semantic.Retrieve (detectCommitmentEngagement)
import QxFx0.Types.Domain.Atoms
  ( AtomSet(..)
  , AtomTag(..)
  , MeaningAtom(..)
  , Register(..)
  )
import QxFx0.Types.State.SemanticCommitment
  ( CommitmentEngagement(..)
  , CommitmentId(..)
  , CommitmentOrigin(..)
  , FactualClaimPayload(..)
  , LineageEvent(..)
  , MatchKind(..)
  , SemanticCommitmentStore(..)
  , TurnSeq(..)
  , emptySemanticCommitmentStore
  , emptyCommitmentEngagement
  )
import QxFx0.Types.State.System (SystemState(..), emptySystemState, ssSemanticCommitments)
import QxFx0.Types.TurnProjection
  ( tqpReplayTrace
  , trcCommitmentEngaged
  , trcCommitmentContradicted
  , trcCommitmentMatchKind
  , trcCommitmentFamilyHint
  )
import QxFx0.Core.TurnPipeline.Protocol
  ( FinalizePrecommitBundle(..)
  , TurnArtifacts(..)
  , TurnInput(..)
  , planFinalizePrecommit
  , resolveFinalizePrecommit
  , buildFinalizePrecommit
  , buildRouteTurnPlan
  , buildTurnArtifacts
  , planRenderEffects
  , resolveRenderEffects
  , planRouteEffects
  , resolveRouteEffects
  , buildTurnInput
  , buildTurnSignals
  )
import QxFx0.Core.PipelineIO
  ( pipelineShadowPolicy
  , pipelineUpdateHistory
  , pipelineParseAuthoritySurface
  )
import QxFx0.Core.FMAR (FmarMode(..))
import QxFx0.Types.Domain (CanonicalMoveFamily(..))
import Test.Support.TurnPipelineFixtures
  ( testProtocolPipelineIO
  , testEpochZero
  , forceAuthoritativeTurnArtifacts
  , buildPreparedFixtureWithState
  )
import QxFx0.Types.Recovery (LocalRecoveryPolicy(..))

-- ---------------------------------------------------------------------------
-- Unit tests: detectCommitmentEngagement
-- ---------------------------------------------------------------------------

makeStoreWithClaim :: T.Text -> SemanticCommitmentStore
makeStoreWithClaim stmt =
  let payload = FactualClaimPayload
        { fcpStatement = stmt
        , fcpConfidence = 0.9
        , fcpOrigin = OriginParser "test"
        , fcpTurnSeq = TurnSeq 1
        , fcpDeps = []
        }
      cid = CommitmentId 1
  in emptySemanticCommitmentStore
       { scsActive = HashMap.singleton cid (payload, TurnSeq 1)
       , scsLineage = HashMap.singleton cid [LineageCommitted (TurnSeq 1)]
       , scsNextId = 2
       }

atomWithContradiction :: MeaningAtom
atomWithContradiction = MeaningAtom
  { maText = "нет свободы"
  , maTag = Contradiction "свобода" "нет"
  , maEmbedding = V.empty
  }

atomSetWithContradiction :: AtomSet
atomSetWithContradiction = AtomSet
  { asAtoms = [atomWithContradiction]
  , asLoad = 1.0
  , asRegister = Neutral
  }

atomSetWithoutContradiction :: AtomSet
atomSetWithoutContradiction = AtomSet
  { asAtoms = []
  , asLoad = 0.0
  , asRegister = Neutral
  }

-- | Contradiction token about a DIFFERENT topic (cross-topic false positive).
atomWithCrossTopicContradiction :: MeaningAtom
atomWithCrossTopicContradiction = MeaningAtom
  { maText = "нет нравственности"
  , maTag = Contradiction "нравственность" "нет"
  , maEmbedding = V.empty
  }

atomSetWithCrossTopicContradiction :: AtomSet
atomSetWithCrossTopicContradiction = AtomSet
  { asAtoms = [atomWithCrossTopicContradiction]
  , asLoad = 1.0
  , asRegister = Neutral
  }

-- | Poor-token contradiction (amplified) — fallback to weak.
atomWithPoorContradiction :: MeaningAtom
atomWithPoorContradiction = MeaningAtom
  { maText = "amplified"
  , maTag = Contradiction "amplified" "amplified"
  , maEmbedding = V.empty
  }

atomSetWithPoorContradiction :: AtomSet
atomSetWithPoorContradiction = AtomSet
  { asAtoms = [atomWithPoorContradiction]
  , asLoad = 1.0
  , asRegister = Neutral
  }

unitEngagedNotContradicted :: Test
unitEngagedNotContradicted = TestLabel "engaged without contradiction atom" $
  TestCase $ do
    let store = makeStoreWithClaim "свобода есть право человека"
        result = detectCommitmentEngagement store "свобода" atomSetWithoutContradiction
    assertEqual "ceEngaged should be non-empty"
      1 (length (ceEngaged result))
    assertEqual "ceContradicted should be False"
      False (ceContradicted result)
    assertEqual "ceMatchKind should be EngagedOnly"
      EngagedOnly (ceMatchKind result)

unitContradicted :: Test
unitContradicted = TestLabel "engaged with contradiction atom" $
  TestCase $ do
    let store = makeStoreWithClaim "свобода есть право человека"
        result = detectCommitmentEngagement store "свобода" atomSetWithContradiction
    assertEqual "ceEngaged should be non-empty"
      1 (length (ceEngaged result))
    assertEqual "ceContradicted should be True"
      True (ceContradicted result)
    assertEqual "ceMatchKind should be ContradictedStrong"
      ContradictedStrong (ceMatchKind result)

unitNotEngaged :: Test
unitNotEngaged = TestLabel "no overlap" $
  TestCase $ do
    let store = makeStoreWithClaim "свобода есть право человека"
        result = detectCommitmentEngagement store "нравственность" atomSetWithContradiction
    assertEqual "ceEngaged should be empty"
      0 (length (ceEngaged result))
    assertEqual "ceContradicted should be False"
      False (ceContradicted result)
    assertEqual "ceMatchKind should be NoMatch"
      NoMatch (ceMatchKind result)

unitEmptyStore :: Test
unitEmptyStore = TestLabel "empty store" $
  TestCase $ do
    let result = detectCommitmentEngagement emptySemanticCommitmentStore "свобода" atomSetWithContradiction
    assertEqual "ceEngaged should be empty"
      0 (length (ceEngaged result))
    assertEqual "ceContradicted should be False"
      False (ceContradicted result)
    assertEqual "ceMatchKind should be NoMatch"
      NoMatch (ceMatchKind result)

unitInfixNoEngage :: Test
unitInfixNoEngage = TestLabel "infix does not engage (word boundary)" $
  TestCase $ do
    let store = makeStoreWithClaim "несвобода — это рабство"
        result = detectCommitmentEngagement store "свобода" atomSetWithoutContradiction
    assertEqual "ceEngaged should be empty (no whole-word overlap)"
      0 (length (ceEngaged result))
    assertEqual "ceContradicted should be False"
      False (ceContradicted result)
    assertEqual "ceMatchKind should be NoMatch"
      NoMatch (ceMatchKind result)

-- | Cross-topic contradiction: overlap exists, but contradiction atom is about a different topic.
unitCrossTopicNoContradiction :: Test
unitCrossTopicNoContradiction = TestLabel "cross-topic contradiction is not contradicted" $
  TestCase $ do
    let store = makeStoreWithClaim "свобода есть право человека"
        result = detectCommitmentEngagement store "свобода" atomSetWithCrossTopicContradiction
    assertEqual "ceEngaged should be non-empty"
      1 (length (ceEngaged result))
    assertEqual "ceContradicted should be False (cross-topic)"
      False (ceContradicted result)
    assertEqual "ceMatchKind should be EngagedOnly"
      EngagedOnly (ceMatchKind result)

-- | Poor-token contradiction: "amplified" fallback keeps contradicted = True.
unitPoorTokenFallback :: Test
unitPoorTokenFallback = TestLabel "poor-token contradiction falls back to contradicted" $
  TestCase $ do
    let store = makeStoreWithClaim "свобода есть право человека"
        result = detectCommitmentEngagement store "свобода" atomSetWithPoorContradiction
    assertEqual "ceEngaged should be non-empty"
      1 (length (ceEngaged result))
    assertEqual "ceContradicted should be True (poor fallback)"
      True (ceContradicted result)
    assertEqual "ceMatchKind should be ContradictedWeak"
      ContradictedWeak (ceMatchKind result)

-- ---------------------------------------------------------------------------
-- Integration test: through the pipeline with overridden atom set
-- ---------------------------------------------------------------------------

integrationContradictionTraceAndLedger :: Test
integrationContradictionTraceAndLedger = TestLabel "contradiction trace and ledger" $
  TestCase $ do
    let pio = testProtocolPipelineIO
        store = makeStoreWithClaim "свобода есть право человека"
        startSs = emptySystemState
          { ssSessionId = "fixture-session"
          , ssSemanticCommitments = Just store
          }

    -- Build prepared fixture
    (ss, ti, ts) <- buildPreparedFixtureWithState startSs "нет свободы"

    -- Override atom set with Contradiction atom and ensure topic overlaps
    let tiOverride = ti { tiAtomSet = atomSetWithContradiction, tiBestTopic = "свобода" }

    -- Rebuild route plan with overridden input
    let routePlan = planRouteEffects ss tiOverride ts
    routeResults <- resolveRouteEffects pio routePlan
    let tp = buildRouteTurnPlan FmarOff (pipelineShadowPolicy pio) ss tiOverride ts routePlan routeResults

    -- Render
    let renderPlan = planRenderEffects LocalRecoveryEnabled ss tiOverride ts tp
    renderResults <- resolveRenderEffects pio renderPlan
    let ta = buildTurnArtifacts ss tiOverride ts tp renderPlan renderResults

    -- Finalize
    let precommitPlan = planFinalizePrecommit ss tiOverride ts tp ta
    precommitResults <- resolveFinalizePrecommit pio precommitPlan
    bundle <- buildFinalizePrecommit
                (pipelineUpdateHistory pio)
                (pipelineParseAuthoritySurface pio)
                ss tiOverride ts tp ta precommitPlan precommitResults

    let trace = tqpReplayTrace (fpbProjection bundle)
        nextSs = fpbNextSs bundle

    -- Phase 1 assertions
    assertBool "trcCommitmentEngaged should be > 0"
      (trcCommitmentEngaged trace > 0)
    assertEqual "trcCommitmentContradicted should be True"
      True (trcCommitmentContradicted trace)

    -- Phase 2 assertions
    assertEqual "trcCommitmentFamilyHint should be Just CMReflect"
      (Just CMReflect) (trcCommitmentFamilyHint trace)

    -- Phase 3 assertions
    assertEqual "trcCommitmentMatchKind should be ContradictedStrong"
      ContradictedStrong (trcCommitmentMatchKind trace)

    -- Ledger assertion
    let mStore = ssSemanticCommitments nextSs
    assertBool "store should be present"
      (isJust mStore)
    let store' = fromJust mStore
    assertBool "scsContradictions should be non-empty"
      (not (null (scsContradictions store')))

    -- Ensure the engagement is still recorded
    assertEqual "trcCommitmentEngaged should be 1"
      1 (trcCommitmentEngaged trace)

-- ---------------------------------------------------------------------------
-- Integration test: non-contradiction case (no CMReflect hint)
-- ---------------------------------------------------------------------------

integrationNoContradictionNoHint :: Test
integrationNoContradictionNoHint = TestLabel "no contradiction -> no CMReflect hint" $
  TestCase $ do
    let pio = testProtocolPipelineIO
        store = makeStoreWithClaim "свобода есть право человека"
        startSs = emptySystemState
          { ssSessionId = "fixture-session"
          , ssSemanticCommitments = Just store
          }

    -- Build prepared fixture
    (ss, ti, ts) <- buildPreparedFixtureWithState startSs "расскажи о свободе"

    -- Override atom set WITHOUT Contradiction atom and ensure topic overlaps
    let tiOverride = ti { tiAtomSet = atomSetWithoutContradiction, tiBestTopic = "свобода" }

    -- Rebuild route plan with overridden input
    let routePlan = planRouteEffects ss tiOverride ts
    routeResults <- resolveRouteEffects pio routePlan
    let tp = buildRouteTurnPlan FmarOff (pipelineShadowPolicy pio) ss tiOverride ts routePlan routeResults

    -- Render
    let renderPlan = planRenderEffects LocalRecoveryEnabled ss tiOverride ts tp
    renderResults <- resolveRenderEffects pio renderPlan
    let ta = buildTurnArtifacts ss tiOverride ts tp renderPlan renderResults

    -- Finalize
    let precommitPlan = planFinalizePrecommit ss tiOverride ts tp ta
    precommitResults <- resolveFinalizePrecommit pio precommitPlan
    bundle <- buildFinalizePrecommit
                (pipelineUpdateHistory pio)
                (pipelineParseAuthoritySurface pio)
                ss tiOverride ts tp ta precommitPlan precommitResults

    let trace = tqpReplayTrace (fpbProjection bundle)
        nextSs = fpbNextSs bundle

    -- Phase 1 assertions
    assertBool "trcCommitmentEngaged should be > 0"
      (trcCommitmentEngaged trace > 0)
    assertEqual "trcCommitmentContradicted should be False"
      False (trcCommitmentContradicted trace)

    -- Phase 2 assertions
    assertEqual "trcCommitmentFamilyHint should be Nothing"
      Nothing (trcCommitmentFamilyHint trace)

    -- Phase 3 assertions
    assertEqual "trcCommitmentMatchKind should be EngagedOnly"
      EngagedOnly (trcCommitmentMatchKind trace)

    -- Ledger assertion: no contradictions recorded
    let mStore = ssSemanticCommitments nextSs
    assertBool "store should be present"
      (isJust mStore)
    let store' = fromJust mStore
    assertEqual "scsContradictions should be empty"
      [] (scsContradictions store')

-- ---------------------------------------------------------------------------
-- Test list
-- ---------------------------------------------------------------------------

commitmentAwareRoutingTests :: [Test]
commitmentAwareRoutingTests =
  [ unitEngagedNotContradicted
  , unitContradicted
  , unitNotEngaged
  , unitEmptyStore
  , unitInfixNoEngage
  , unitCrossTopicNoContradiction
  , unitPoorTokenFallback
  , integrationContradictionTraceAndLedger
  , integrationNoContradictionNoHint
  ]
