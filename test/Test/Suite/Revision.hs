{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.Revision (revisionTests) where

import Test.HUnit
import qualified Data.HashMap.Strict as HashMap
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import qualified Data.Text as T
import Data.Aeson (decodeStrict')
import Data.Maybe (fromJust)
import QxFx0.Semantic.Revision
import QxFx0.Types.State.SemanticCommitment (CommitmentId(..), ContradictionKind(..), SemanticCommitmentStore(..), FactualClaimPayload(..), TurnSeq(..), CommitmentOrigin(..), CommitmentEngagement(..), MatchKind(..), LineageEvent(..), emptySemanticCommitmentStore)
import QxFx0.Types.State.System (ssSemanticCommitments)
import QxFx0.Self.Conatus (ConatusEnergy(..), ConatusComponents(..))
import QxFx0.Self.Essence (Essence(..), EssenceTrajectory(..), emptyTrajectory)
import QxFx0.Types.State.Stance (StanceDefense(..), StanceState(..), emptyStanceDefense)
import QxFx0.Semantic.Stance (defendOrAdapt, evidenceWeight, recoverStance, selectNearestSatisfying, selectFarthestPoint, extractUserStance, stanceSimilarity, collapseThreshold, Collapse(..))
import Data.Maybe (fromJust, fromMaybe, isJust)
import QxFx0.Core.TurnPipeline.Protocol
  ( TurnPlan(..)
  , TurnInput(..)
  , FinalizePrecommitBundle(..)
  , planFinalizePrecommit
  , resolveFinalizePrecommit
  , buildFinalizePrecommit
  )
import QxFx0.Core.PipelineIO (pipelineUpdateHistory, pipelineParseAuthoritySurface)
import Test.Suite.TurnPipelineProtocol (withDeterministicEmbedding)
import Test.Support.TurnPipelineFixtures
  ( buildRenderedFixture
  , forceAuthoritativeTurnArtifacts
  , testProtocolPipelineIO
  )
import QxFx0.Semantic.Network.Seed (seedFromCorpus)
import QxFx0.Semantic.Network (mergeSemanticNetworks, contentDensityGate)
import QxFx0.Semantic.Network.Types (SemanticNetwork(..), SemanticEdge(..))

revisionTests :: [Test]
revisionTests =
  [ TestLabel "revisePosition (v3.0 pentagon)" $ TestList
      [ TestCase $ do
          let cid = CommitmentId 1
              kind = ContradictionStatement
              sd = emptyStanceDefense { sdStance = StanceHeld 0.5 }
              conatus = ConatusEnergy 10.0 (ConatusComponents 2.5 2.5 2.5 2.5)
              challengeAtoms = S.fromList ["atom1", "atom2", "atom3"]
              result = revisePosition cid kind sd conatus challengeAtoms
          case result of
            Left _ -> assertFailure "should not collapse"
            Right rc -> assertEqual "stable defense should retain" (RcRetained cid kind) rc

      , TestCase $ do
          let cid = CommitmentId 2
              kind = ContradictionStatement
              sd = emptyStanceDefense { sdStance = StanceDoubted 0.4 }
              conatus = ConatusEnergy 3.0 (ConatusComponents 0.75 0.75 0.75 0.75)
              challengeAtoms = S.fromList ["atom1", "atom2", "atom3"]
              result = revisePosition cid kind sd conatus challengeAtoms
          case result of
            Left _ -> assertFailure "should not collapse with low conatus"
            Right rc -> assertEqual "low conatus while doubted should retain" (RcRetained cid kind) rc

      , TestCase $ do
          let cid = CommitmentId 3
              kind = ContradictionStatement
              sd = emptyStanceDefense { sdStance = StanceHeld 0.5 }
              conatus = ConatusEnergy 10.0 (ConatusComponents 2.5 2.5 2.5 2.5)
              challengeAtoms = S.fromList ["atom1", "atom2", "atom3"]
              result = revisePosition cid kind sd conatus challengeAtoms
          case result of
            Left _ -> assertFailure "should not collapse"
            Right rc -> assertEqual "stable state should retain" (RcRetained cid kind) rc

      , TestCase $ do
          let cid = CommitmentId 4
              kind = ContradictionStatement
              sd = emptyStanceDefense { sdStance = StanceDoubted 0.4, sdAttackCount = 3 }
              conatus = ConatusEnergy 10.0 (ConatusComponents 2.5 2.5 2.5 2.5)
              challengeAtoms = S.fromList ["atom1", "atom2", "atom3"]
              result = revisePosition cid kind sd conatus challengeAtoms
          case result of
            Left _ -> assertFailure "should not collapse"
            Right rc -> assertEqual "doubted with momentum should retain" (RcRetained cid kind) rc

      , TestCase $ do
          let cid = CommitmentId 5
              kind = ContradictionStatement
              sd = emptyStanceDefense { sdStance = StanceHeld 0.5 }
              conatus = ConatusEnergy 5.0 (ConatusComponents 1.25 1.25 1.25 1.25)
              challengeAtoms = S.fromList ["atom1", "atom2", "atom3"]
              result = revisePosition cid kind sd conatus challengeAtoms
          case result of
            Left _ -> assertFailure "should not collapse"
            Right rc -> assertEqual "conatus at threshold should retain" (RcRetained cid kind) rc

      , TestCase $ do
          let cid = CommitmentId 6
              kind = ContradictionStatement
              sd = emptyStanceDefense { sdStance = StanceDoubted 0.3, sdAttackCount = 5 }
              conatus = ConatusEnergy 10.0 (ConatusComponents 2.5 2.5 2.5 2.5)
              challengeAtoms = S.fromList ["atom1", "atom2", "atom3", "atom4", "atom5"]
              result = revisePosition cid kind sd conatus challengeAtoms
          case result of
            Left _ -> assertFailure "should not collapse"
            Right rc -> assertEqual "strong challenge while doubted should revise" (RcRevised cid kind) rc

      , TestCase $ do
          let cid = CommitmentId 7
              kind = ContradictionScope
              sd = emptyStanceDefense { sdStance = StanceDoubted 0.3, sdAttackCount = 5 }
              conatus = ConatusEnergy 10.0 (ConatusComponents 2.5 2.5 2.5 2.5)
              challengeAtoms = S.fromList ["atom1", "atom2", "atom3", "atom4", "atom5"]
              result = revisePosition cid kind sd conatus challengeAtoms
          case result of
            Left _ -> assertFailure "should not collapse"
            Right rc -> assertEqual "scope contradiction with strong challenge should revise" (RcRevised cid kind) rc
      ]
  , TestLabel "applyRevisionDecision M.empty" $ TestList
      [ TestCase $ do
          let cid = CommitmentId 1
              ts = TurnSeq 5
              payload = FactualClaimPayload "test" 0.8 OriginManual (TurnSeq 0) [] ""
              store = emptySemanticCommitmentStore
                { scsActive = HashMap.singleton cid (payload, TurnSeq 0)
                , scsNextId = 2
                }
              decision = RcQuarantined cid ContradictionStatement
              result = applyRevisionDecision M.empty ts store Nothing decision
          assertBool "should be removed from active" $ HashMap.null (scsActive result)
          assertBool "should be in quarantine" $ HashMap.member cid (scsQuarantine result)

      , TestCase $ do
          let cid = CommitmentId 2
              ts = TurnSeq 5
              payload = FactualClaimPayload "test" 0.8 OriginManual (TurnSeq 0) [] ""
              store = emptySemanticCommitmentStore
                { scsActive = HashMap.singleton cid (payload, TurnSeq 0)
                , scsNextId = 3
                }
              decision = RcRetained cid ContradictionStatement
              result = applyRevisionDecision M.empty ts store Nothing decision
          assertBool "should remain in active" $ HashMap.member cid (scsActive result)
          assertBool "should not be in quarantine" $ HashMap.null (scsQuarantine result)

      , TestCase $ do
          let cid = CommitmentId 3
              ts = TurnSeq 5
              payload = FactualClaimPayload "test" 0.8 OriginManual (TurnSeq 0) [] ""
              store = emptySemanticCommitmentStore
                { scsActive = HashMap.singleton cid (payload, TurnSeq 0)
                , scsNextId = 4
                }
              decision = RcRevised cid ContradictionStatement
              result = applyRevisionDecision M.empty ts store Nothing decision
          assertBool "should remain in active" $ HashMap.member cid (scsActive result)
          assertBool "should not be in quarantine" $ HashMap.null (scsQuarantine result)
          let (revisedPayload, _) = HashMap.lookupDefault (payload, TurnSeq 0) cid (scsActive result)
          assertEqual "confidence should decay by 0.9" (0.8 * 0.9) (fcpConfidence revisedPayload)
          assertEqual "lineage should have one revision event" 1 (length $ HashMap.lookupDefault [] cid (scsLineage result))
          assertEqual "contradictions should have one event" 1 (length $ scsContradictions result)

      , TestCase $ do
          let cid1 = CommitmentId 1
              cid2 = CommitmentId 2
              ts = TurnSeq 5
              payload = FactualClaimPayload "test" 0.8 OriginManual (TurnSeq 0) [] ""
              store = emptySemanticCommitmentStore
                { scsActive = HashMap.fromList
                    [ (cid1, (payload, TurnSeq 0))
                    , (cid2, (payload, TurnSeq 0))
                    ]
                , scsNextId = 3
                }
              decisions = [ RcQuarantined cid1 ContradictionStatement
                          , RcRetained cid2 ContradictionStatement
                          ]
              result = foldl (\s dec -> applyRevisionDecision M.empty ts s Nothing dec) store decisions
          assertBool "cid1 should be removed from active" $ not (HashMap.member cid1 (scsActive result))
          assertBool "cid2 should remain in active" $ HashMap.member cid2 (scsActive result)
          assertBool "cid1 should be in quarantine" $ HashMap.member cid1 (scsQuarantine result)
          assertBool "cid2 should not be in quarantine" $ not (HashMap.member cid2 (scsQuarantine result))

      , TestCase $ do
          let cid = CommitmentId 99
              ts = TurnSeq 5
              store = emptySemanticCommitmentStore { scsNextId = 1 }
              decision = RcQuarantined cid ContradictionStatement
              result = applyRevisionDecision M.empty ts store Nothing decision
          assertBool "store should be unchanged" $ result == store
      ]
  , TestLabel "synthesizeResolution M.empty" $ TestList
      [ TestCase $ do
          let oldPayload = FactualClaimPayload "свобода предполагает выбор" 0.8 OriginManual (TurnSeq 1) [] "свобода"
              newPayload = FactualClaimPayload "свобода требует ответственности" 0.9 OriginManual (TurnSeq 2) [] "свобода"
              result = synthesizeResolution M.empty oldPayload newPayload
          assertBool "should return Just" $ isJust result
          let Just resolution = result
          assertEqual "should be Conjunction" Conjunction (srType resolution)
          assertBool "statement should contain 'и вместе с тем'" $ T.isInfixOf "и вместе с тем" (srStatement resolution)
          assertEqual "confidence should be 0.5" 0.5 (fcpConfidence (srPayload resolution))
          assertEqual "origin should be OriginSynthetic" OriginSynthetic (fcpOrigin (srPayload resolution))

      , TestCase $ do
          let oldPayload = FactualClaimPayload "свобода это выбор" 0.8 OriginManual (TurnSeq 1) [] "свобода"
              newPayload = FactualClaimPayload "ответственность это долг" 0.9 OriginManual (TurnSeq 2) [] "ответственность"
              result = synthesizeResolution M.empty oldPayload newPayload
          assertBool "should return Just" $ isJust result
          let Just resolution = result
          assertEqual "should be Irreducible" Irreducible (srType resolution)
          assertBool "statement should contain 'несовместимы'" $ T.isInfixOf "несовместимы" (srStatement resolution)
          assertEqual "confidence should be 0.3" 0.3 (fcpConfidence (srPayload resolution))
          assertEqual "origin should be OriginSynthetic" OriginSynthetic (fcpOrigin (srPayload resolution))

      , TestCase $ do
          let cid = CommitmentId 1
              ts = TurnSeq 5
              oldPayload = FactualClaimPayload "свобода предполагает выбор" 0.8 OriginManual (TurnSeq 1) [] "свобода"
              newPayload = FactualClaimPayload "свобода требует ответственности" 0.9 OriginManual (TurnSeq 2) [] "свобода"
              store = emptySemanticCommitmentStore
                { scsActive = HashMap.singleton cid (oldPayload, TurnSeq 1)
                , scsNextId = 2
                }
              decision = RcRevised cid ContradictionStatement
              result = applyRevisionDecision M.empty ts store (Just newPayload) decision
          assertBool "should have synthesized commitment" $ HashMap.size (scsActive result) == 2
          let synthesizedCid = CommitmentId 2
          assertBool "synthesized commitment should be in active" $ HashMap.member synthesizedCid (scsActive result)
          let (synthPayload, _) = HashMap.lookupDefault (oldPayload, TurnSeq 0) synthesizedCid (scsActive result)
          assertEqual "synthesized should have OriginSynthetic" OriginSynthetic (fcpOrigin synthPayload)
          assertBool "synthesized should contain 'и вместе с тем'" $ T.isInfixOf "и вместе с тем" (fcpStatement synthPayload)
      ]
  , TestLabel "integration" $ TestList
      [ TestCase $
          withDeterministicEmbedding $ do
            -- Build a real fixture, then override tp/ti to force contradiction
            (ss, ti, ts, tp, ta) <- buildRenderedFixture "что такое свобода"
            -- Add a commitment to the store so we have something to engage
            let cid = CommitmentId 1
                payload = FactualClaimPayload "свобода" 0.9 OriginManual (TurnSeq 0) [] "свобода"
                store0 = fromMaybe emptySemanticCommitmentStore (ssSemanticCommitments ss)
                store1 = store0
                  { scsActive = HashMap.insert cid (payload, TurnSeq 0) (scsActive store0)
                  , scsNextId = max (scsNextId store0) 2
                  }
                ssWithStore = ss { ssSemanticCommitments = Just store1 }
            -- Override tp to force ceContradicted = True with engaged = [cid]
            let tp' = tp { tpCommitmentEngagement = CommitmentEngagement [cid] True ContradictedStrong }
            -- Override ti to have high angst (triggers RcRevised)
            let trajHighAngst = (emptyTrajectory) { etAngstLevel = 0.9 }
                ti' = ti { tiEssence = EssenceUncommitted trajHighAngst }
            -- Run through finalize
            let precommitPlan = planFinalizePrecommit ssWithStore ti' ts tp' ta
            precommitResults <- resolveFinalizePrecommit testProtocolPipelineIO precommitPlan
            bundle <- buildFinalizePrecommit
                        (pipelineUpdateHistory testProtocolPipelineIO)
                        (pipelineParseAuthoritySurface testProtocolPipelineIO)
                        ssWithStore ti' ts tp' ta precommitPlan precommitResults
            let nextSs = fpbNextSs bundle
                mStore = ssSemanticCommitments nextSs
            assertBool "store must be Just" (isJust mStore)
            let store = fromJust mStore
            -- RcRevised: confidence should have decayed by 0.9
            let (revisedPayload, _) = HashMap.lookupDefault (payload, TurnSeq 0) cid (scsActive store)
            assertEqual "confidence should decay by 0.9" (0.9 * 0.9) (fcpConfidence revisedPayload)
            -- Lineage should have LineageRevised event
            let lineage = HashMap.lookupDefault [] cid (scsLineage store)
            assertBool "lineage should have revision event" (any isLineageRevised lineage)
            -- Contradictions should have an event
            assertBool "contradictions should be non-empty" (not (null (scsContradictions store)))
      ]
  , TestLabel "seedFromCorpus" $ TestList
      [ TestCase $ do
          let net = seedFromCorpus M.empty
              nodeCount = S.size (snNodes net)
              edgeCount = M.size (snEdges net)
          -- Content density gate requires >= 50 edges and >= 15 nodes
          assertBool ("seedFromCorpus should have >= 15 nodes, got " ++ show nodeCount) (nodeCount >= 15)
          assertBool ("seedFromCorpus should have >= 50 edges, got " ++ show edgeCount) (edgeCount >= 50)
      ]
  , TestLabel "mergeSemanticNetworks" $ TestList
      [ TestCase $ do
          let base = seedFromCorpus M.empty
              update = SemanticNetwork
                { snNodes = S.fromList ["newNode1", "newNode2"]
                , snEdges = M.singleton ("newNode1", "newNode2")
                    (SemanticEdge "newNode1" "newNode2" 1.0 1)
                , snActivation = M.empty
                , snDecayRate = 0.3
                , snMaxHops = 5
                }
              merged = mergeSemanticNetworks base update
              mergedNodes = S.size (snNodes merged)
              mergedEdges = M.size (snEdges merged)
          assertBool "merged should contain base nodes" (S.member "свобода" (snNodes merged))
          assertBool "merged should contain update nodes" (S.member "newNode1" (snNodes merged))
          assertBool "merged should contain base edges" (M.member ("свобода", "ответственность") (snEdges merged))
          assertBool "merged should contain update edges" (M.member ("newNode1", "newNode2") (snEdges merged))
          assertEqual "merged should preserve base decayRate" 0.5 (snDecayRate merged)
          assertEqual "merged should preserve base maxHops" 3 (snMaxHops merged)
          assertBool "merged activation should be empty" (M.null (snActivation merged))
          assertBool ("merged should have >= base nodes, got " ++ show mergedNodes) (mergedNodes >= S.size (snNodes base))
          assertBool ("merged should have >= base edges, got " ++ show mergedEdges) (mergedEdges >= M.size (snEdges base))
      ]
  , TestLabel "fcpTopic backward compatibility" $ TestList
      [ TestCase $ do
          let oldJson = "{\"fcpStatement\":\"test\",\"fcpConfidence\":0.8,\"fcpOrigin\":\"OriginManual\",\"fcpTurnSeq\":1,\"fcpDeps\":[]}"
          let parsed = decodeStrict' oldJson :: Maybe FactualClaimPayload
          assertBool "should parse old JSON without fcpTopic" (isJust parsed)
          let payload = fromJust parsed
          assertEqual "fcpTopic should default to empty" "" (fcpTopic payload)
          assertEqual "fcpStatement should be preserved" "test" (fcpStatement payload)
      ]
  ]
  where
    isLineageRevised (LineageRevised _ _) = True
    isLineageRevised _ = False
