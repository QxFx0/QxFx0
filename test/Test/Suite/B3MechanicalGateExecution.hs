{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.B3MechanicalGateExecution
Description : B3 mechanical gate execution — integrated Gates 1-5 verdict.

This is the /mechanical B3 gate execution/ front. It assembles the
verdict from the per-gate tests in 'SemanticContentB3' (Gates 1-2) and
'SemanticRepairB3' (Gates 3-4), plus a Gate 5 (non-fallback
precondition) check, into a single conjunctive verdict.

Per B3 Decision 4: the overall MVS pass is the conjunction
Gate 5 ∧ Gate 1 ∧ Gate 2 ∧ Gate 3 ∧ Gate 4 — no averaging across layers.

The verdict is recorded but M6-FELT remains NOT PROVEN until B2
human-eval execution passes (per the B2 hard guard: B2 MUST NOT run
until B3 gates mechanically pass, and M6-FELT is not declared by
B3 alone).
-}
module Test.Suite.B3MechanicalGateExecution
  ( b3MechanicalGateExecutionTests
  , b3GateVerdict
  ) where

import Test.HUnit (Test(..), assertBool)

import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Semantic.Content
  ( coveredTopics, lookupDefinitionContent, lookupDistinctionContent
  , hasMinimumPredicates, substantivePredicateCount
  , DefinitionContent(..), DistinctionContent(..)
  , SemanticPredicate(..)
  )
import QxFx0.Semantic.Commitment (commitObservation)
import QxFx0.Semantic.Retrieve (detectCommitmentEngagement)
import QxFx0.Types.State.SemanticCommitment
import QxFx0.Types.Domain.Atoms (AtomSet(..), Register(..))

import qualified Data.HashMap.Strict as HashMap

-- ============================================================================
-- Gate 5: Non-fallback precondition (data-level check)
-- ============================================================================

-- | Gate 5 precondition: covered topics have semantic content data that
-- makes non-fallback output possible. This is a /data-level/ check — the
-- /runtime-level/ check (trcAuthorityClass ≠ Fallback) requires a live
-- turn, which needs the full pipeline. Here we verify the precondition:
-- the content layer exists and is non-empty for all covered topics.
--
-- If this fails, no covered topic can pass Gate 1 (no predicates →
-- fallback-only). If this passes, the content layer is present and the
-- render wiring (M4-001) can produce non-fallback output for covered
-- topics.
testGate5PreconditionContentLayerExists :: Test
testGate5PreconditionContentLayerExists =
  TestLabel "B3 Gate 5 (precondition): content layer exists for all covered topics" $
    TestCase $ do
      let missing = [ topic
                   | topic <- coveredTopics
                   , case lookupDefinitionContent topic of
                       Just dc -> substantivePredicateCount dc == 0
                       Nothing -> True
                   ]
      assertBool ("Topics with no content (Gate 5 precondition fail): " <> show missing)
                 (null missing)

-- ============================================================================
-- Integrated B3 verdict: Gates 1-5 conjunction
-- ============================================================================

-- | The B3 gate verdict — a conjunctive pass/fail across all 5 gates.
-- Per B3 Decision 4: no averaging. All gates must pass.
data B3GateVerdict = B3GateVerdict
  { b3vGate5Precondition :: !Bool
  , b3vGate1Definition :: !Bool
  , b3vGate2Distinction :: !Bool
  , b3vGate3Repair :: !Bool
  , b3vGate4Commitment :: !Bool
  , b3vOverallPass :: !Bool
  } deriving stock (Eq, Show)

-- | Compute the B3 gate verdict from the content layer and commitment
-- store infrastructure. This is the mechanical check — it does not run
-- the full pipeline (that requires governed-evidence conditions), but
-- it checks that the /substrate/ for all 5 gates is present and correct.
b3GateVerdict :: B3GateVerdict
b3GateVerdict =
  let gate5 = all (\t -> case lookupDefinitionContent t of
                      Just dc -> substantivePredicateCount dc > 0
                      Nothing -> False) coveredTopics

      gate1 = all (\t -> case lookupDefinitionContent t of
                      Just dc -> hasMinimumPredicates dc
                      Nothing -> False) coveredTopics

      coveredPairs = [ ("свобода", "произвол")
                     , ("истина", "мнение")
                     , ("память", "воспоминание")
                     , ("сознание", "самосознание")
                     , ("свобода", "ответственность")
                     ]
      gate2 = all (\(a, b) -> case lookupDistinctionContent a b of
                      Just dc -> not (null (dcDifferentiators dc))
                      Nothing -> False) coveredPairs

      -- Gate 3: domain-bearing commitments are findable by topic
      gate3 = all (\topic ->
        let Just dc = lookupDefinitionContent topic
            preds = map spRu (dcPredicates dc)
            stmt = "Dialogue channel: define. Topic: " <> topic <> ". "
                   <> T.intercalate " " preds
                   <> " (established at turn 1)"
            payload = FactualClaimPayload
              { fcpStatement = stmt
              , fcpConfidence = 0.5
              , fcpOrigin = OriginParser "anchor:define"
              , fcpTurnSeq = TurnSeq 1
              , fcpDeps = []
              }
            store0 = emptySemanticCommitmentStore
            (store1, _) = commitObservation payload store0
            engagement = detectCommitmentEngagement store1 topic emptyAtomSet
        in not (null (ceEngaged engagement))
        ) coveredTopics

      -- Gate 4: 10-turn accumulation + persistence + challenge
      topics10 = [ "свобода", "произвол", "ответственность", "истина", "мнение"
                 , "память", "воспоминание", "сознание", "самосознание", "свобода"
                 ]
      payloads10 = map (\(topic, turn) ->
        let Just dc = lookupDefinitionContent topic
            preds = map spRu (dcPredicates dc)
            stmt = "Dialogue channel: define. Topic: " <> topic <> ". "
                   <> T.intercalate " " preds
                   <> " (established at turn " <> T.pack (show turn) <> ")"
        in FactualClaimPayload
          { fcpStatement = stmt
          , fcpConfidence = 0.5
          , fcpOrigin = OriginParser "anchor:define"
          , fcpTurnSeq = TurnSeq turn
          , fcpDeps = []
          }
        ) (zip topics10 [1..])
      storeS = foldr (\p s -> fst (commitObservation p s)) emptySemanticCommitmentStore payloads10
      activeCount = HashMap.size (scsActive storeS)
      challengeEngaged = not (null (ceEngaged (detectCommitmentEngagement storeS "свобода" emptyAtomSet)))
      gate4 = activeCount >= 9 && challengeEngaged

      overall = gate5 && gate1 && gate2 && gate3 && gate4

  in B3GateVerdict
       { b3vGate5Precondition = gate5
       , b3vGate1Definition = gate1
       , b3vGate2Distinction = gate2
       , b3vGate3Repair = gate3
       , b3vGate4Commitment = gate4
       , b3vOverallPass = overall
       }

-- | The integrated B3 verdict test — all 5 gates must pass (conjunction).
testB3IntegratedVerdict :: Test
testB3IntegratedVerdict =
  TestLabel "B3 integrated verdict: Gate 5 ∧ Gate 1 ∧ Gate 2 ∧ Gate 3 ∧ Gate 4 (conjunction, no averaging)" $
    TestCase $ do
      let verdict = b3GateVerdict
      assertBool ("Gate 5 precondition failed: " <> show verdict)
                 (b3vGate5Precondition verdict)
      assertBool ("Gate 1 definition failed: " <> show verdict)
                 (b3vGate1Definition verdict)
      assertBool ("Gate 2 distinction failed: " <> show verdict)
                 (b3vGate2Distinction verdict)
      assertBool ("Gate 3 repair failed: " <> show verdict)
                 (b3vGate3Repair verdict)
      assertBool ("Gate 4 commitment failed: " <> show verdict)
                 (b3vGate4Commitment verdict)
      assertBool ("B3 overall pass failed (conjunction): " <> show verdict)
                 (b3vOverallPass verdict)

-- | Per-gate verdict breakdown (for diagnostics and reporting).
testB3PerGateBreakdown :: Test
testB3PerGateBreakdown =
  TestLabel "B3 per-gate breakdown: each gate individually reported" $
    TestCase $ do
      let v = b3GateVerdict
          -- Each gate is checked individually so failures are visible
          -- per-gate, not hidden behind a single conjunction.
          gateStatuses =
            [ ("Gate 5 (precondition)", b3vGate5Precondition v)
            , ("Gate 1 (definition)", b3vGate1Definition v)
            , ("Gate 2 (distinction)", b3vGate2Distinction v)
            , ("Gate 3 (repair)", b3vGate3Repair v)
            , ("Gate 4 (commitment)", b3vGate4Commitment v)
            ]
          failed = [ name | (name, pass) <- gateStatuses, not pass ]
      assertBool ("Individual gate failures: " <> show failed)
                 (null failed)

-- ============================================================================
-- Helpers
-- ============================================================================

emptyAtomSet :: AtomSet
emptyAtomSet = AtomSet [] 0.0 Neutral

-- ============================================================================
-- Test group
-- ============================================================================

b3MechanicalGateExecutionTests :: [Test]
b3MechanicalGateExecutionTests =
  [ testGate5PreconditionContentLayerExists
  , testB3IntegratedVerdict
  , testB3PerGateBreakdown
  ]
