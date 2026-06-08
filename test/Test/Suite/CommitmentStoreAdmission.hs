{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.CommitmentStoreAdmission
Description : CTS-42 — unit and integration tests for commitment store admission.

Unit tests: exhaustive pattern-match on all 8 TruthContractStatus constructors.
Integration tests: verify that canonical surfaces admit claims and degraded
surfaces suppress them.
-}
module Test.Suite.CommitmentStoreAdmission
  ( commitmentStoreAdmissionTests
  ) where

import Test.HUnit (Test (..), assertEqual, assertBool)
import Data.Maybe (isJust, isNothing)
import qualified Data.HashMap.Strict as HashMap

import QxFx0.Core.CommitmentStoreAdmission
  ( CommitmentStoreAdmissionDecision (..)
  , admitCommitmentToStore
  )
import QxFx0.Types.Observability (TruthContractStatus (..))
import QxFx0.Types.State.SemanticCommitment
  ( SemanticCommitmentStore (..)
  , emptySemanticCommitmentStore
  )
import QxFx0.Types.State.System (ssSemanticCommitments, ssTruthContractStatus)
import QxFx0.Types.TurnProjection (tqpReplayTrace, trcCommitmentStoreDecision)
import QxFx0.Core.TurnPipeline.Protocol
  ( FinalizePrecommitBundle(..)
  , TurnArtifacts(..)
  , planFinalizePrecommit
  , resolveFinalizePrecommit
  , buildFinalizePrecommit
  )
import QxFx0.Core.PipelineIO (pipelineUpdateHistory)
import QxFx0.Types.Observability (AuthorityClass(..), TruthContractStatus(..))
import Test.Suite.TurnPipelineProtocol (withDeterministicEmbedding)
import Test.Support.TurnPipelineFixtures
  ( buildRenderedFixture
  , buildFinalizeFixtureWithState
  , forceAuthoritativeTurnArtifacts
  , testProtocolPipelineIO
  )

-- ---------------------------------------------------------------------------
-- Unit tests: exhaustive pattern-match on all 8 constructors
-- ---------------------------------------------------------------------------

unitTests :: [Test]
unitTests =
  [ TestLabel "CanonicalSurfacePreserved → CsaAdmitCanonical" $
      TestCase $ assertEqual "canonical"
        CsaAdmitCanonical (admitCommitmentToStore CanonicalSurfacePreserved)
  , TestLabel "AssembledSurfacePreserved → CsaAdmitCanonical" $
      TestCase $ assertEqual "assembled"
        CsaAdmitCanonical (admitCommitmentToStore AssembledSurfacePreserved)
  , TestLabel "ExplicitFallbackSurface → CsaSuppress" $
      TestCase $ assertEqual "fallback"
        CsaSuppress (admitCommitmentToStore ExplicitFallbackSurface)
  , TestLabel "NonExpansiveRecoverySurface → CsaSuppress" $
      TestCase $ assertEqual "recovery"
        CsaSuppress (admitCommitmentToStore NonExpansiveRecoverySurface)
  , TestLabel "CompatibilityShimSurface → CsaSuppress" $
      TestCase $ assertEqual "shim"
        CsaSuppress (admitCommitmentToStore CompatibilityShimSurface)
  , TestLabel "DefaultedSurface → CsaSuppress" $
      TestCase $ assertEqual "defaulted"
        CsaSuppress (admitCommitmentToStore DefaultedSurface)
  , TestLabel "GeneratedArtifactSurface → CsaSuppress" $
      TestCase $ assertEqual "generated"
        CsaSuppress (admitCommitmentToStore GeneratedArtifactSurface)
  , TestLabel "LegacyIncompleteSurface → CsaSuppress" $
      TestCase $ assertEqual "legacy"
        CsaSuppress (admitCommitmentToStore LegacyIncompleteSurface)
  ]

-- ---------------------------------------------------------------------------
-- Integration tests: verify store behaviour under canonical vs degraded
-- ---------------------------------------------------------------------------

-- | A canonical surface (forced authoritative) produces commitments.
integrationCanonicalAdmits :: Test
integrationCanonicalAdmits = TestLabel "CTS-42: canonical surface admits claims to store" $
  TestCase $
    withDeterministicEmbedding $ do
      (ss, ti, ts, tp, ta) <- buildRenderedFixture "что такое свобода?"
      let taAuth = forceAuthoritativeTurnArtifacts ta
          precommitPlan = planFinalizePrecommit ss ti ts tp taAuth
      precommitResults <- resolveFinalizePrecommit testProtocolPipelineIO precommitPlan
      bundle <- buildFinalizePrecommit
                    (pipelineUpdateHistory testProtocolPipelineIO)
                    ss ti ts tp taAuth precommitPlan precommitResults
      let nextSs = fpbNextSs bundle
          trace = tqpReplayTrace (fpbProjection bundle)
          mStore = ssSemanticCommitments nextSs
      assertBool "store must be Just"
        (isJust mStore)
      let count = maybe 0 (HashMap.size . scsActive) mStore
      assertBool ("count must be >= 1, got: " <> show count)
        (count >= 1)
      assertEqual "trace decision must be CsaAdmitCanonical"
        CsaAdmitCanonical (trcCommitmentStoreDecision trace)

-- | A degraded surface (fallback, as produced by the normal test fixture)
-- does NOT add claims to the store.
integrationDegradedSuppresses :: Test
integrationDegradedSuppresses = TestLabel "CTS-42: degraded surface suppresses claims" $
  TestCase $
    withDeterministicEmbedding $ do
      -- First turn: canonical (force authoritative artifacts)
      (ss, ti, ts, tp, ta) <- buildRenderedFixture "что такое свобода?"
      let taAuth = forceAuthoritativeTurnArtifacts ta
          precommitPlan = planFinalizePrecommit ss ti ts tp taAuth
      precommitResults <- resolveFinalizePrecommit testProtocolPipelineIO precommitPlan
      bundle1 <- buildFinalizePrecommit
                    (pipelineUpdateHistory testProtocolPipelineIO)
                    ss ti ts tp taAuth precommitPlan precommitResults
      let ss1 = fpbNextSs bundle1
          count1 = maybe 0 (HashMap.size . scsActive) (ssSemanticCommitments ss1)
      -- Second turn: degraded (normal fallback artifacts from the fixture)
      (_, _, _, _, _, bundle2) <- buildFinalizeFixtureWithState ss1 "расскажи подробнее"
      let nextSs = fpbNextSs bundle2
          mStore = ssSemanticCommitments nextSs
          trace = tqpReplayTrace (fpbProjection bundle2)
          count2 = maybe 0 (HashMap.size . scsActive) mStore
      -- The trace must reflect the suppressed decision
      assertEqual "trace decision must be CsaSuppress"
        CsaSuppress (trcCommitmentStoreDecision trace)
      -- The store must NOT have grown from the degraded turn
      assertBool ("count after degraded turn (" <> show count2 <> ") must not exceed count after first turn (" <> show count1 <> ")")
        (count2 <= count1)

commitmentStoreAdmissionTests :: [Test]
commitmentStoreAdmissionTests = unitTests ++ [integrationCanonicalAdmits, integrationDegradedSuppresses]
