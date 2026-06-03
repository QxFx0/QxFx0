{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.SelfPerspective
  ( selfPerspectiveTests
  ) where

import Data.Aeson (decode)
import qualified Data.ByteString.Lazy.Char8 as BL8
import qualified Data.Map.Strict as M
import qualified Data.Text as T
import Test.HUnit

import QxFx0.Self.Conatus (ConatusComponents(..), ConatusEnergy(..))
import QxFx0.Self.Field (emptyField)
import QxFx0.Self.Perspective
  ( applyPerspectiveDecision
  , assemblePerspectiveInput
  , buildPerspectiveProjection
  , decidePerspectivePromotion
  , evaluatePerspectiveAdmissibility
  , opinionCore
  )
import QxFx0.Types.State
  ( AdaptiveDecision(..)
  , AdaptiveDecisionRecord(..)
  , AdaptiveMutationKind(..)
  , ClaimStanceRef(..)
  , ConatusSlice(..)
  , CounterargumentRef(..)
  , DialogueOutcomeKind(..)
  , DialogueOutcomeLearningState(..)
  , DialogueOutcomeSample(..)
  , EvidenceRef(..)
  , EvidenceStrength(..)
  , IdentitySlice(..)
  , NormativeProfile(..)
  , NormativeProfileId(..)
  , PerspectiveAdmissibility(..)
  , PerspectiveCandidate(..)
  , PerspectiveInputBundle(..)
  , PerspectiveProjection(..)
  , PerspectivePromotionDecision(..)
  , PerspectiveRegistry(..)
  , PerspectiveRevisionRecord
  , PerspectiveScope(..)
  , PerspectiveThread(..)
  , SystemState(..)
  , defaultNormativeProfile
  , defaultPerspectiveRegistry
  , emptyDialogueOutcomeLearningState
  , emptySystemState
  )

selfPerspectiveTests :: [Test]
selfPerspectiveTests =
  [ TestLabel "SelfPerspective rejects insufficient evidence" testPerspectiveAdmissibilityRejectsInsufficientEvidence
  , TestLabel "SelfPerspective rejects empty identity session" testPerspectiveAdmissibilityRejectsEmptySession
  , TestLabel "SelfPerspective promotion requires strong stability" testPerspectivePromotionRequiresStabilityAndStrongEvidence
  , TestLabel "SelfPerspective activation scope selects matching profile" testPerspectiveActivationScopeSelectsMatchingNormativeProfile
  , TestLabel "SelfPerspective duplicate threads fail decode" testPerspectiveRegistryRejectsDuplicateThreads
  , TestLabel "SelfPerspective rollback restores prior projection" testPerspectiveRollbackRestoresPriorProjection
  , TestLabel "SelfPerspective projection is explainable and safe" testPerspectiveProjectionIsExplainableAndSafe
  , TestLabel "SelfPerspective candidate is NaN-safe" testPerspectiveCandidateIsNaNSafe
  ]

testPerspectiveAdmissibilityRejectsInsufficientEvidence :: Test
testPerspectiveAdmissibilityRejectsInsufficientEvidence = TestCase $ do
  let bundle = mkPerspectiveBundle [] [] [] defaultNormativeProfile []
      candidate = opinionCore bundle
  assertEqual "candidate without evidence must be inadmissible"
    (PerspectiveInadmissible "insufficient_evidence")
    (evaluatePerspectiveAdmissibility bundle candidate)

testPerspectiveAdmissibilityRejectsEmptySession :: Test
testPerspectiveAdmissibilityRejectsEmptySession = TestCase $ do
  let bundle0 = mkPerspectiveBundle [EvidenceRef "knowledge:x"] [] [] defaultNormativeProfile []
      bundle = bundle0
        { pibIdentitySlice = (pibIdentitySlice bundle0) { isSessionId = "" } }
      candidate = opinionCore bundle
  assertEqual "empty session id must fail perspective admissibility"
    (PerspectiveInadmissible "identity_violation:empty_session")
    (evaluatePerspectiveAdmissibility bundle candidate)

testPerspectivePromotionRequiresStabilityAndStrongEvidence :: Test
testPerspectivePromotionRequiresStabilityAndStrongEvidence = TestCase $ do
  let weakBundle = mkPerspectiveBundle [EvidenceRef "thanks_ack"] [] [] defaultNormativeProfile []
      weakCandidate = opinionCore weakBundle
      stableBundle = mkPerspectiveBundle
        [ EvidenceRef "knowledge:freedom is bounded agency"
        , EvidenceRef "dialogue:DialogueOutcomeSuccess:freedom"
        ]
        [ClaimStanceRef "stance:BeliefAffirmed:freedom requires responsibility"]
        []
        defaultNormativeProfile
        []
      stableCandidate = opinionCore stableBundle
      registry = defaultPerspectiveRegistry
  assertEqual "weak evidence can be admissible but must not promote"
    PpdObserveOnly
    (decidePerspectivePromotion registry weakBundle weakCandidate PerspectiveAdmissibleAccepted)
  assertEqual "stable corroborated candidate can be promoted"
    PpdPromoteEndorsed
    (decidePerspectivePromotion registry stableBundle stableCandidate (evaluatePerspectiveAdmissibility stableBundle stableCandidate))

testPerspectiveActivationScopeSelectsMatchingNormativeProfile :: Test
testPerspectiveActivationScopeSelectsMatchingNormativeProfile = TestCase $ do
  let defaultScoped = defaultNormativeProfile
        { npVersionId = 1
        , npActivationScope = Just (ScopeTopic "other")
        }
      freedomProfile = defaultNormativeProfile
        { npId = NormativeProfileId "freedom-profile"
        , npVersionId = 7
        , npActivationScope = Just (ScopeTopic "freedom")
        }
      registry = defaultPerspectiveRegistry
        { prNormativeProfiles = M.fromList [(npId defaultScoped, defaultScoped), (npId freedomProfile, freedomProfile)]
        , prActiveNormativeProfileId = npId defaultScoped
        }
      outcome = emptyDialogueOutcomeLearningState
        { dolRecentOutcomes = [mkDialogueOutcomeSample 1 DialogueOutcomeSuccess "freedom"]
        }
      ss = emptySystemState
        { ssSessionId = "test-session"
        , ssPerspectiveRegistry = registry
        , ssDialogueOutcomeLearning = outcome
        }
      bundle = assemblePerspectiveInput ss (ConatusEnergy 10.0 (ConatusComponents 0 0 0 0)) False emptyField
      candidate = opinionCore bundle
  assertEqual "matching activation scope must select the scoped profile"
    7 (pcNormativeProfileVersion candidate)

testPerspectiveRegistryRejectsDuplicateThreads :: Test
testPerspectiveRegistryRejectsDuplicateThreads = TestCase $ do
  let duplicateJson = BL8.pack
        "{\"threads\":[{\"ptPerspectiveId\":\"p1\",\"ptScope\":{\"tag\":\"ScopeTopic\",\"contents\":\"freedom\"},\"ptActiveVersion\":null,\"ptVersions\":[],\"ptRevisionHistory\":[],\"ptStatus\":\"PerspectiveSuspended\",\"ptLastUpdatedTurn\":1},{\"ptPerspectiveId\":\"p2\",\"ptScope\":{\"tag\":\"ScopeTopic\",\"contents\":\"freedom\"},\"ptActiveVersion\":null,\"ptVersions\":[],\"ptRevisionHistory\":[],\"ptStatus\":\"PerspectiveSuspended\",\"ptLastUpdatedTurn\":2}],\"normativeProfiles\":[],\"activeNormativeProfileId\":\"default\"}"
      decoded = decode duplicateJson :: Maybe PerspectiveRegistry
  assertEqual "duplicate scope threads must not decode by overwriting"
    Nothing decoded

testPerspectiveRollbackRestoresPriorProjection :: Test
testPerspectiveRollbackRestoresPriorProjection = TestCase $ do
  let bundle = mkPerspectiveBundle
        [EvidenceRef "knowledge:freedom is bounded agency", EvidenceRef "dialogue:DialogueOutcomeSuccess:freedom"]
        [ClaimStanceRef "stance:BeliefAffirmed:freedom requires responsibility"]
        []
        defaultNormativeProfile
        []
      candidate = opinionCore bundle
      registry1 = applyPerspectiveDecision 1 defaultPerspectiveRegistry bundle candidate PpdPromoteEndorsed
      bundle2 = bundle { pibRevisionLineage = maybe [] ptRevisionHistory (M.lookup (pibScope bundle) (prThreads registry1)) }
      candidate2 = (opinionCore bundle2) { pcThesis = "revision one" }
      registry2 = applyPerspectiveDecision 2 registry1 bundle2 candidate2 PpdReviseActive
      rollbackBundle = bundle2 { pibCounterarguments = [CounterargumentRef "counter:a", CounterargumentRef "counter:b"] }
      rollbackCandidate = (opinionCore rollbackBundle) { pcCounterargumentPressure = 0.50 }
      decision = decidePerspectivePromotion registry2 rollbackBundle rollbackCandidate PerspectiveAdmissibleQuarantined
      registry3 = applyPerspectiveDecision 3 registry2 rollbackBundle rollbackCandidate decision
  assertEqual "rollback must be reachable from promotion policy"
    PpdRollbackPrior decision
  case buildPerspectiveProjection registry3 (pibScope bundle) of
    Nothing -> assertFailure "expected restored prior projection"
    Just projection -> assertBool "rollback must not expose withdrawn active version"
      (ppSummary projection /= "revision one")

testPerspectiveProjectionIsExplainableAndSafe :: Test
testPerspectiveProjectionIsExplainableAndSafe = TestCase $ do
  let bundle = mkPerspectiveBundle
        [ EvidenceRef "knowledge:freedom is bounded agency"
        , EvidenceRef "dialogue:DialogueOutcomeSuccess:freedom"
        ]
        [ClaimStanceRef "stance:BeliefAffirmed:freedom requires responsibility"]
        [CounterargumentRef "counter:freedom can conflict with safety"]
        defaultNormativeProfile
        []
      candidate = opinionCore bundle
      registry = applyPerspectiveDecision 1 defaultPerspectiveRegistry bundle candidate PpdPromoteEndorsed
  case buildPerspectiveProjection registry (pibScope bundle) of
    Nothing -> assertFailure "expected safe perspective projection"
    Just projection -> do
      assertEqual "projection exposes profile provenance"
        1 (ppNormativeProfileVersion projection)
      assertBool "projection exposes explanation handle"
        (not (T.null (ppExplanationHandle projection)))
      assertEqual "projection keeps counterarguments as counts only"
        1 (ppCounterargumentCount projection)

-- | Regression lock G1: 'opinionCore' must not propagate NaN or
-- Infinity from a degenerate 'ConatusSlice' into the candidate's
-- confidence, counterargument pressure, normative alignment, or
-- internal tension surfaces.  The NaN-safe 'clampUnit' in
-- "QxFx0.Self.Perspective" guarantees a finite candidate at the
-- perspective-evaluation boundary.
testPerspectiveCandidateIsNaNSafe :: Test
testPerspectiveCandidateIsNaNSafe = TestCase $ do
  let bundle0 = mkPerspectiveBundle
        [EvidenceRef "knowledge:freedom is bounded agency"]
        [ClaimStanceRef "stance:BeliefAffirmed:freedom requires responsibility"]
        [CounterargumentRef "counter:contested"]
        defaultNormativeProfile
        []
      bundle = bundle0
        { pibConatusSlice = (pibConatusSlice bundle0)
            { csEnergy          = 0/0
            , csFieldConfidence = 1/0
            , csStability       = (-1)/0
            }
        }
      candidate = opinionCore bundle
  assertBool "candidate confidence must not be NaN under non-finite Conatus slice"
    (not (isNaN (pcConfidence candidate)))
  assertBool "candidate confidence must not be Infinity under non-finite Conatus slice"
    (not (isInfinite (pcConfidence candidate)))
  assertBool "candidate counterargument pressure must remain finite"
    (not (isNaN (pcCounterargumentPressure candidate)) && not (isInfinite (pcCounterargumentPressure candidate)))
  assertBool "candidate normative alignment must remain finite"
    (not (isNaN (pcNormativeAlignment candidate)) && not (isInfinite (pcNormativeAlignment candidate)))
  assertBool "candidate internal tension must remain finite"
    (not (isNaN (pcInternalTension candidate)) && not (isInfinite (pcInternalTension candidate)))
  assertBool "all candidate scores must stay bounded to the unit interval"
    ( pcConfidence candidate              >= 0.0 && pcConfidence candidate              <= 1.0
   && pcCounterargumentPressure candidate >= 0.0 && pcCounterargumentPressure candidate <= 1.0
   && pcNormativeAlignment candidate      >= 0.0 && pcNormativeAlignment candidate      <= 1.0
   && pcInternalTension candidate         >= 0.0 && pcInternalTension candidate         <= 1.0
    )

mkPerspectiveBundle
  :: [EvidenceRef]
  -> [ClaimStanceRef]
  -> [CounterargumentRef]
  -> NormativeProfile
  -> [PerspectiveRevisionRecord]
  -> PerspectiveInputBundle
mkPerspectiveBundle evidence stance counterarguments profile lineage = PerspectiveInputBundle
  { pibScope = ScopeTopic "freedom"
  , pibEvidence = evidence
  , pibStanceSlice = stance
  , pibIdentitySlice = IdentitySlice
      { isSessionId = "test-session"
      , isIdentityClaims = []
      , isIdentityClaimCount = 0
      , isTurnCount = 1
      }
  , pibConatusSlice = ConatusSlice
      { csEnergy = 10.0
      , csGateFired = False
      , csFieldConfidence = 1.0
      , csStability = 1.0
      }
  , pibNormativeProfile = profile
  , pibCounterarguments = counterarguments
  , pibRevisionLineage = lineage
  }

mkDialogueOutcomeSample :: Int -> DialogueOutcomeKind -> T.Text -> DialogueOutcomeSample
mkDialogueOutcomeSample turn kind topic = DialogueOutcomeSample
  { dosTurn = turn
  , dosKind = kind
  , dosTopic = topic
  , dosSignals = ["test"]
  , dosEvidenceStrength = EvidenceStrong
  , dosStrongUpdate = True
  , dosDecisionRecord = AdaptiveDecisionRecord
      { adrTurn = turn
      , adrCause = "test"
      , adrEvidence = ["test"]
      , adrConfidence = 0.8
      , adrBoundedDelta = ["recent_outcomes<=12"]
      , adrDecision = AdaptiveAccepted
      , adrTargets = [MutDialogueOutcome]
      , adrMutationRecords = []
      }
  }
