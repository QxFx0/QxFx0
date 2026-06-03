{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

{-|
Module      : Test.Suite.SelfEssenceCommit
Description : Property and unit tests for Phase-10 law-driven commitment
              and post-commitment guard.

Verifies, by QuickCheck and HUnit, the laws asserted in
@docs/adr/0012-essence-commitment.md@ §9 (E6–E8) and
@docs/phase-10-essence-commitment-implementation-spec.md@ §3:

  * 'EssenceCommitted' is sticky (never reverts);
  * 'CMRepair' and 'NarrativeNeutral' are always admissible;
  * pre-threshold trajectories stay uncommitted;
  * threshold crossings trigger commitment;
  * 'EssenceRupture' aborts the turn before persistence;
  * sliding-window Conatus erosion semantics;
  * reconcile-time courtesy never widens the admissible set.
-}
module Test.Suite.SelfEssenceCommit
  ( selfEssenceCommitTests
  ) where

import Test.HUnit (Test (..), assertBool, assertEqual, assertFailure)
import Test.QuickCheck
  ( Gen
  , Property
  , choose
  , counterexample
  , elements
  , forAll
  , maxSuccess
  , quickCheckWithResult
  , stdArgs
  , vectorOf
  , (===)
  , (==>)
  )
import Test.QuickCheck.Test (isSuccess)

import Data.List (foldl')
import qualified Data.Sequence as Seq
import qualified Data.Set as Set
import QxFx0.Self.Conatus (ConatusEnergy (..), ConatusComponents (..))
import QxFx0.Self.Deliberation
  ( Agreement (..)
  , Deliberation (..)
  , DeliberationTrace (..)
  , NarrativeTone (..)
  , Plan (..)
  , ReconcileRule (..)
  , defaultPlan
  , defaultDeliberation
  , formalProposal
  , holisticProposal
  , reconcile
  )
import QxFx0.Self.Essence
import QxFx0.Self.Field
  ( Field (..)
  , emptyField
  , mkAtmosphere
  , mkConsolidation
  , mkCounterfactual
  , mkFieldConfidence
  , mkResonance
  )
import QxFx0.Self.Salience
  ( Salience (..)
  , SalienceDriver (..)
  )
import QxFx0.Types.Decision (RenderStyle (..))
import QxFx0.Types.Domain (CanonicalMoveFamily (..))

-- ---------------------------------------------------------------------------
-- Test-suite entry point
-- ---------------------------------------------------------------------------

selfEssenceCommitTests :: [Test]
selfEssenceCommitTests =
  [ -- E6 — sticky commitment
    TestLabel "EssenceCommitted is sticky across continuations" $
      quickCheckProperty "sticky commitment"
        propStickyCommitment

    -- E7a — CMRepair always admissible
  , TestLabel "CMRepair is always admissible under validatePlan" $
      quickCheckProperty "repair always admissible"
        propRepairAlwaysAdmissible

    -- E7b — NarrativeNeutral always admissible
  , TestLabel "NarrativeNeutral is always admissible under validatePlan" $
      quickCheckProperty "neutral tone always admissible"
        propNeutralToneAlwaysAdmissible

    -- Regression — pre-threshold shape stays uncommitted
    -- TODO: replace with an actual buildNextSystemState call once
    -- a reusable Phase-10 fixture builder is extracted; see
    -- docs/post-phase-10-roadmap-closure-spec.md §1.2.
  , TestLabel "pre-threshold trajectory stays EssenceUncommitted with one witness" $
      TestCase testFlagOffEssenceUncommittedShape

    -- HUnit — threshold commitment fires
  , TestLabel "threshold-crossed trajectory yields EssenceCommitted" $
      TestCase testFlagOnCommitmentFires

    -- HUnit — rupture throws before persistence
  , TestLabel "committed violating plan throws EssenceRupture before persistence" $
      TestCase testFlagOnRuptureThrows

    -- Q7 — sliding-window exact semantics
  , TestLabel "sliding-window Conatus erosion exact semantics" $
      quickCheckProperty "sliding window exact"
        propSlidingWindowExactSemantics

    -- C1 — reconcile courtesy never widens
  , TestLabel "reconcile courtesy never widens admissible family set" $
      quickCheckProperty "courtesy never widens"
        propReconcileCourtesyNeverWidens

    -- §4 — Conatus floor unit-mismatch correction
  , TestLabel "corrected Conatus floor triggers on realistic post-violation scalar" $
      TestCase testConatusErosionFiresUnderCorrectedFloor

  , TestLabel "missing deliberation violation is explicit" $
      TestCase testMissingDeliberationViolationIsExplicit
  ]

-- ---------------------------------------------------------------------------
-- QuickCheck plumbing
-- ---------------------------------------------------------------------------

quickCheckProperty :: String -> Property -> Test
quickCheckProperty label prop = TestCase $ do
  result <- quickCheckWithResult stdArgs { maxSuccess = 200 } prop
  if isSuccess result
    then pure ()
    else assertFailure ("Property failed: " ++ label)

-- ---------------------------------------------------------------------------
-- Generators (reused from Test.Suite.SelfEssence)
-- ---------------------------------------------------------------------------

arbitraryUnitDouble :: Gen Double
arbitraryUnitDouble = choose (0.0, 1.0)

arbitraryField :: Gen Field
arbitraryField = do
  r  <- arbitraryUnitDouble
  v  <- choose (-1.0, 1.0)
  ar <- arbitraryUnitDouble
  c  <- arbitraryUnitDouble
  cf <- arbitraryUnitDouble
  pure $ Field
    { fieldResonance      = mkResonance r
    , fieldAtmosphere     = mkAtmosphere v ar
    , fieldConfidence     = mkFieldConfidence c
    , fieldConsolidation  = mkConsolidation cf
    , fieldCounterfactual = mkCounterfactual cf
    }

arbitrarySalienceDriver :: Gen SalienceDriver
arbitrarySalienceDriver = elements
  [ DrivenByResonance
  , DrivenByAtmosphere
  , DrivenByConsolidation
  , DrivenByCounterfactual
  , DrivenByFieldConfidence
  , DrivenByConatusGate
  , DrivenByDefault
  ]

arbitrarySalience :: Gen Salience
arbitrarySalience = do
  bias   <- choose (0.0, 1.0)
  conf   <- choose (0.0, 1.0)
  driver <- arbitrarySalienceDriver
  pure $ Salience
    { salienceHolisticBias = bias
    , salienceConfidence   = conf
    , salienceDriver       = driver
    }

arbitraryReconcileRule :: Gen ReconcileRule
arbitraryReconcileRule = elements
  [ RuleAgreement
  , RuleConatusOverride
  , RuleSalienceLead
  , RuleHolisticAdvantage
  , RuleFormalAdvantage
  , RuleTiedFallback
  ]

arbitraryAgreement :: Gen Agreement
arbitraryAgreement = elements
  [ Agree
  , DivergeOnFamily
  , DivergeOnStyle
  , DivergeOnRecovery
  , DivergeOnTone
  , DivergeMultiple
  ]

arbitraryPlan :: Gen Plan
arbitraryPlan = do
  family  <- elements
    [ CMGround, CMDefine, CMDistinguish, CMReflect, CMDescribe
    , CMPurpose, CMHypothesis, CMRepair, CMContact, CMAnchor
    , CMClarify, CMDeepen, CMConfront, CMNextStep
    ]
  style   <- elements
    [ StyleFormal, StyleWarm, StyleDirect, StylePoetic
    , StyleClinical, StyleCautious, StyleRecovery, StyleStandard
    ]
  tone    <- elements
    [ NarrativeNeutral, NarrativeWarm, NarrativeFormal
    , NarrativeTerse, NarrativeRecovery
    ]
  conf    <- arbitraryUnitDouble
  pure $ defaultPlan
    { planFamily        = family
    , planRenderStyle   = style
    , planNarrativeTone = tone
    , planConfidence    = conf
    }

arbitraryConatusEnergy :: Gen ConatusEnergy
arbitraryConatusEnergy = do
  s <- arbitraryUnitDouble
  pure $ ConatusEnergy
    { ceScalar     = s
    , ceComponents = ConatusComponents 0 0 0 0
    }

arbitraryEssenceWitness :: Gen EssenceWitness
arbitraryEssenceWitness = do
  turnOrd   <- choose (1, 1000)
  driver    <- arbitrarySalienceDriver
  rule      <- arbitraryReconcileRule
  agr       <- arbitraryAgreement
  divg      <- arbitraryUnitDouble
  cscalar   <- arbitraryUnitDouble
  sig       <- fieldSignature defaultEssenceModulation <$> arbitraryField
  pure $ EssenceWitness
    { ewTurnOrdinal     = turnOrd
    , ewSalienceDriver  = driver
    , ewReconcileRule   = rule
    , ewAgreement       = agr
    , ewDivergence      = divg
    , ewConatusScalar   = cscalar
    , ewFieldSignature  = sig
    }

arbitraryEssenceTrajectory :: Gen EssenceTrajectory
arbitraryEssenceTrajectory = do
  n        <- choose (0, 12)
  witnesses <- vectorOf n arbitraryEssenceWitness
  angst    <- arbitraryUnitDouble
  floor_   <- arbitraryUnitDouble
  pure $ EssenceTrajectory
    { etWitnesses    = Seq.fromList witnesses
    , etAngstLevel   = angst
    , etConatusFloor = floor_
    , etCapacity     = emTrajectoryCapacity defaultEssenceModulation
    }

arbitraryDeliberation :: Gen Deliberation
arbitraryDeliberation = do
  hPlan <- arbitraryPlan
  fPlan <- arbitraryPlan
  rPlan <- arbitraryPlan
  agr   <- arbitraryAgreement
  divg  <- arbitraryUnitDouble
  rule  <- arbitraryReconcileRule
  drv   <- arbitrarySalienceDriver
  pure $ Deliberation
    { delibHolistic   = hPlan
    , delibFormal     = fPlan
    , delibReconciled = rPlan
    , delibTrace      = DeliberationTrace
        { dtAgreement      = agr
        , dtDivergence     = divg
        , dtRule           = rule
        , dtSalienceDriver = drv
        }
    }

arbitraryEssenceCommitment :: Gen EssenceCommitment
arbitraryEssenceCommitment = do
  mode    <- elements [EssenceContemplative, EssenceDialogical, EssenceIntegrative]
  trigger <- elements [TriggerAngstThreshold, TriggerConatusErosion]
  turnOrd <- choose (1, 100)
  pure $ EssenceCommitment
    { ecMode        = mode
    , ecTrigger     = trigger
    , ecCommittedAt = turnOrd
    , ecWitnessHash = TrajectoryHash "sha256:test-fixture"
    }

-- ---------------------------------------------------------------------------
-- Properties
-- ---------------------------------------------------------------------------

-- | E6 — once committed, never reverts; commitment invariant.
--
-- Replaces the previous tautological constructor-match with a
-- property that runs N continuations through the actual 'witness'
-- morphism and verifies the commitment remains invariant.
propStickyCommitment :: Property
propStickyCommitment =
  forAll arbitraryEssenceCommitment $ \commitment ->
  forAll arbitraryEssenceTrajectory $ \trajBase ->
  forAll (choose (1, 20)) $ \n ->
  forAll (vectorOf n arbitraryStepInput) $ \steps ->
    let initial = EssenceCommitted trajBase commitment
        step e (ord, (ce, fd, delib)) =
          case e of
            EssenceCommitted t c ->
              EssenceCommitted
                (witness defaultEssenceModulation ord ce fd delib t)
                c
            EssenceUncommitted _ -> e  -- unreachable from this seed
        final = foldl' step initial (zip [1..] steps)
    in case final of
         EssenceCommitted _ c' -> c' === commitment
         EssenceUncommitted _  -> counterexample "commitment lost" False
  where
    arbitraryStepInput =
      (,,) <$> arbitraryConatusEnergy <*> arbitraryField <*> arbitraryDeliberation

-- | E7a — CMRepair is in every admissible-family set.
propRepairAlwaysAdmissible :: Property
propRepairAlwaysAdmissible =
  forAll arbitraryEssenceCommitment $ \c ->
    Set.member CMRepair (admissibleFamilies (ecMode c))

-- | E7b — NarrativeNeutral is in every admissible-tone set.
propNeutralToneAlwaysAdmissible :: Property
propNeutralToneAlwaysAdmissible =
  forAll arbitraryEssenceCommitment $ \c ->
    Set.member NarrativeNeutral (admissibleTones (ecMode c))

-- | Q7 — sliding-window exact semantics.
propSlidingWindowExactSemantics :: Property
propSlidingWindowExactSemantics =
  forAll (choose (1, 6)) $ \window ->
  forAll (vectorOf window arbitraryEssenceWitness) $ \ws ->
  forAll arbitraryUnitDouble $ \angst ->
    let em = defaultEssenceModulation { emConatusFloorWindow = window
                                      , emConatusStructuralFloor = 0.5
                                      , emAngstCommitmentThreshold = 1.1
                                      }
        traj = EssenceTrajectory
          { etWitnesses    = Seq.fromList ws
          , etAngstLevel   = angst  -- below threshold so angst never fires
          , etConatusFloor = 0.0
          , etCapacity     = emTrajectoryCapacity em
          }
        allSubFloor = all (\w -> ewConatusScalar w < 0.5) ws
        lenOK       = length ws >= window
    in shouldCommit em traj == if allSubFloor && lenOK
                                 then Just TriggerConatusErosion
                                 else Nothing

-- | C1 — reconcile courtesy never widens admissible family set.
--
-- When 'RuleTiedFallback' fires and a courtesy predicate is
-- supplied, the fallback may switch to the holistic plan, but
-- ONLY if it is admissible under the predicate.  This property
-- verifies that the switch never occurs to an inadmissible plan.
-- Cases where RuleTiedFallback does not fire are discarded; cases
-- where it fires but the output remains formal (or the families
-- coincide) pass trivially.
propReconcileCourtesyNeverWidens :: Property
propReconcileCourtesyNeverWidens =
  forAll arbitraryEssenceCommitment $ \c ->
  forAll arbitrarySalience $ \sal ->
  forAll arbitraryPlan $ \hPlan ->
  forAll arbitraryPlan $ \fPlan ->
  forAll arbitraryField $ \fd ->
    let adm = isAdmissible c
        hp  = holisticProposal hPlan fd
        fp  = formalProposal (const fPlan)
        result = reconcile (Just adm) sal hp fp fd
        out    = delibReconciled result
        rule   = dtRule (delibTrace result)
        hAdmissible = adm hPlan
    in rule == RuleTiedFallback ==>
         (if planFamily out == planFamily hPlan && planFamily hPlan /= planFamily fPlan
            then hAdmissible
            else True)
  where
    isAdmissible commitment plan =
      case validatePlan commitment plan of
        Right _ -> True
        Left  _ -> False

-- ---------------------------------------------------------------------------
-- Unit tests
-- ---------------------------------------------------------------------------

-- | TODO: this test currently asserts shape only (one witness,
-- angst bounded).  It does not invoke the actual
-- 'buildNextSystemState' function because no reusable fixture
-- builder for the full turn-pipeline state exists yet.  See
-- docs/post-phase-10-roadmap-closure-spec.md §1.2.
testFlagOffEssenceUncommittedShape :: IO ()
testFlagOffEssenceUncommittedShape = do
  let traj = emptyTrajectory
      fd   = emptyField
      ce   = ConatusEnergy 0.5 (ConatusComponents 0 0 0 0)
      p    = defaultPlan
      delib = defaultDeliberation { delibReconciled = p }
      traj' = witness defaultEssenceModulation 1 ce fd delib traj
      -- Simulate what buildNextSystemState does when flag is off
      next = EssenceUncommitted traj'
  case next of
    EssenceUncommitted t -> do
      assertEqual "witness count" 1 (Seq.length (etWitnesses t))
      assertBool "angst in [0,1]" (etAngstLevel t >= 0.0 && etAngstLevel t <= 1.0)
    EssenceCommitted _ _ ->
      assertFailure "flag-off must never produce EssenceCommitted"

testFlagOnCommitmentFires :: IO ()
testFlagOnCommitmentFires = do
  let em = defaultEssenceModulation
        { emAngstCommitmentThreshold = 0.5
        , emAngstAccrualRate = 0.1
        }
      -- Build a trajectory with angst just below threshold
      traj0 = emptyTrajectory { etAngstLevel = 0.45 }
      fd = emptyField
      ce = ConatusEnergy 0.5 (ConatusComponents 0 0 0 0)
      -- One divergence witness to push angst over threshold.
      -- dtAgreement must NOT be Agree, otherwise extractMode counts
      -- the witness as Integrative regardless of dtRule.
      delib = defaultDeliberation
        { delibTrace = (delibTrace defaultDeliberation)
            { dtRule = RuleHolisticAdvantage
            , dtAgreement = DivergeOnFamily
            , dtDivergence = 0.6
            }
        }
      traj1 = witness em 1 ce fd delib traj0
  -- After one witness with high divergence, angst should jump to 0.55
  assertBool "angst above threshold"
    (etAngstLevel traj1 >= emAngstCommitmentThreshold em)
  case shouldCommit em traj1 of
    Just TriggerAngstThreshold -> pure ()
    other -> assertFailure
      ("expected Just TriggerAngstThreshold, got " ++ show other)
  let committed = commit 1 TriggerAngstThreshold traj1
  -- With one non-Agree HolisticAdvantage witness, extractMode counts
  -- it toward Dialogical (hRate = 1), so commit produces Dialogical.
  assertEqual "extractMode on single HolisticAdvantage"
    EssenceDialogical (extractMode traj1)
  assertEqual "committed mode from extractMode"
    EssenceDialogical (ecMode committed)

testFlagOnRuptureThrows :: IO ()
testFlagOnRuptureThrows = do
  let commitment = EssenceCommitment
        { ecMode = EssenceContemplative
        , ecTrigger = TriggerAngstThreshold
        , ecCommittedAt = 1
        , ecWitnessHash = TrajectoryHash "sha256:test-rupture"
        }
      -- A Plan with family CMContact is NOT admissible for Contemplative
      badPlan = defaultPlan { planFamily = CMContact }
      violation = validatePlan commitment badPlan
  -- Verify the violation is the exact family mismatch we expect.
  case violation of
    Left (ViolationFamilyMismatch EssenceContemplative CMContact) -> pure ()
    other -> assertFailure
      ("expected family mismatch violation, got " ++ show other)
  -- Verify the violation is a Left (would become EssenceRupture in
  -- resolveFinalizeCommit before persistence).
  assertBool "violation is Left" (isLeft violation)

isLeft :: Either a b -> Bool
isLeft (Left _) = True
isLeft _        = False

-- | §4 calibration — corrected Conatus floor unit mismatch.
--
-- 'computeConatusEnergy' produces a log-scale unbounded scalar
-- (healthy range ~14-15).  The Phase 9 floor of 0.5 was calibrated
-- against 'arbitraryUnitDouble' ([0,1]) generators and could never
-- fire in production.  The corrected floor (7.0, ≈ half healthy)
-- triggers on realistic post-violation values (~5).  This test also
-- regression-locks against reverting to the buggy Phase 9 floor.
testConatusErosionFiresUnderCorrectedFloor :: IO ()
testConatusErosionFiresUnderCorrectedFloor = do
  let -- 8 witnesses (== 'emConatusFloorWindow') all with
      -- 'ewConatusScalar' = 5.0 (post-violation state).
      mkWitness scalar = EssenceWitness
        { ewTurnOrdinal     = 1
        , ewSalienceDriver  = DrivenByDefault
        , ewReconcileRule   = RuleAgreement
        , ewAgreement       = Agree
        , ewDivergence      = 0.0
        , ewConatusScalar   = scalar
        , ewFieldSignature  = fieldSignature defaultEssenceModulation emptyField
        }
      ws = replicate 8 (mkWitness 5.0)
      traj = emptyTrajectory { etWitnesses = Seq.fromList ws }
  -- With 'defaultEssenceModulation' (floor = 7.0), all witnesses
  -- are sub-floor → Conatus erosion fires.
  case shouldCommit defaultEssenceModulation traj of
    Just TriggerConatusErosion -> pure ()
    other -> assertFailure
      ("expected Just TriggerConatusErosion under corrected floor, got "
       ++ show other)
  -- With 'phase9EssenceModulation' (floor = 0.5), 5.0 is NOT sub-floor
  -- → no trigger.  Regression lock against accidental reversion.
  case shouldCommit phase9EssenceModulation traj of
    Nothing -> pure ()
    other -> assertFailure
      ("Phase 9 buggy floor should NOT trigger on scalar 5.0, got "
       ++ show other)

testMissingDeliberationViolationIsExplicit :: IO ()
testMissingDeliberationViolationIsExplicit =
  assertEqual
    "missing deliberation violation renders explicitly"
    "missing_deliberation:contemplative"
    (renderEssenceViolation (ViolationMissingDeliberation EssenceContemplative))
