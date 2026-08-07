{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.EssenceCollapse
Description : B-slice tests: single canonical collapse branch (BD2)
              and Essence-commit reachability within 14-15 turns
              (BD3).

Pins, offline:

  * 'collapseEssenceAt' is total on both 'Essence' constructors and
    always repacks as 'EssenceUncommitted' (single reset branch);
  * sustained hemispheric advantage with out-of-envelope divergence
    drives a fresh (zero-angst) trajectory to 'TriggerAngstThreshold'
    on turn 15 and never before turn 14 — the commitment is reachable
    inside the 14-15 window, not later;
  * a zero-divergence agreement regime never commits (no spurious
    commitment inside the reachability window);
  * after a soft collapse the trajectory recommits within the same
    14-15 turn window (the soft rupture does not poison the loop).
-}
module Test.Suite.EssenceCollapse
  ( essenceCollapseTests
  ) where

import Test.HUnit (Test (..), assertBool, assertEqual)

import qualified Data.Sequence as Seq

import QxFx0.Self.Conatus (ConatusEnergy (..), ConatusComponents (..))
import QxFx0.Self.Deliberation
  ( Agreement (..)
  , Deliberation (..)
  , DeliberationTrace (..)
  , ReconcileRule (..)
  , defaultDeliberation
  )
import QxFx0.Self.Essence
  ( Essence (..)
  , CommitmentTrigger (..)
  , EssenceCommitment (..)
  , EssenceMode (..)
  , EssenceResetEvent (..)
  , EssenceTrajectory (..)
  , EssenceWitness (..)
  , TrajectoryHash (..)
  , collapseEssence
  , collapseEssenceAt
  , defaultEssenceModulation
  , emptyTrajectory
  , fieldSignature
  , shouldCommit
  , witness
  )
import QxFx0.Self.Field (emptyField)
import QxFx0.Types.Self.Essence (EssenceModulation (..))
import QxFx0.Types.Self.Salience (SalienceDriver (..))

-- ---------------------------------------------------------------------------
-- Test-suite entry point
-- ---------------------------------------------------------------------------

essenceCollapseTests :: [Test]
essenceCollapseTests =
  [ TestLabel "BD2: collapseEssenceAt is total on both constructors" $
      TestCase $ do
        testTotalOnUncommitted
        testTotalOnCommitted
        testCanonicalEventMatchesTrajectoryCollapse
  , TestLabel "BD3: commitment reachable on turn 15, never before turn 14" $
      TestCase testCommitReachabilityWindow
  , TestLabel "BD3: zero-divergence agreement never commits in the window" $
      TestCase testNoSpuriousCommitUnderAgreement
  , TestLabel "BD3: post-collapse recommitment within the 14-15 window" $
      TestCase testRecommitAfterSoftCollapse
  ]

-- ---------------------------------------------------------------------------
-- BD2 — single canonical collapse branch
-- ---------------------------------------------------------------------------

testTotalOnUncommitted :: IO ()
testTotalOnUncommitted = do
  let traj = emptyTrajectory
        { etAngstLevel = 0.9
        , etWitnesses = Seq.fromList [mkWitness 1, mkWitness 2]
        }
      (resetEssence, resetEvent) = collapseEssenceAt 7 (EssenceUncommitted traj)
  assertEqual "repacks as EssenceUncommitted" True
    (case resetEssence of EssenceUncommitted _ -> True; EssenceCommitted _ _ -> False)
  case resetEssence of
    EssenceUncommitted resetTraj -> do
      assertEqual "angst cleared" 0.0 (etAngstLevel resetTraj)
      assertEqual "witnesses cleared" 0 (Seq.length (etWitnesses resetTraj))
      assertEqual "conatus floor restored" 1.0 (etConatusFloor resetTraj)
    _ -> pure ()
  assertEqual "event turn is the collapse turn" 7 (ereTurn resetEvent)
  assertEqual "event carries previous angst" 0.9 (erePreviousAngst resetEvent)
  assertEqual "event carries previous witness count" 2 (erePreviousWitnessCount resetEvent)

testTotalOnCommitted :: IO ()
testTotalOnCommitted = do
  let traj = emptyTrajectory { etAngstLevel = 0.8 }
      committed = EssenceCommitted traj (defaultCommitment)
      (resetUncommitted, _) = collapseEssenceAt 3 (EssenceUncommitted traj)
      (resetCommitted, _) = collapseEssenceAt 3 committed
  assertEqual "committed collapses to EssenceUncommitted" True
    (case resetCommitted of EssenceUncommitted _ -> True; EssenceCommitted _ _ -> False)
  assertEqual "committed and uncommitted collapse agree"
    resetUncommitted resetCommitted

testCanonicalEventMatchesTrajectoryCollapse :: IO ()
testCanonicalEventMatchesTrajectoryCollapse = do
  let traj = emptyTrajectory { etAngstLevel = 0.8 }
      (resetTraj, ev1) = collapseEssence 5 traj
      (EssenceUncommitted resetAt, ev2) = collapseEssenceAt 5 (EssenceUncommitted traj)
  assertEqual "canonical trajectory equals collapseEssence" resetTraj resetAt
  assertEqual "canonical event equals collapseEssence event" ev1 ev2

-- ---------------------------------------------------------------------------
-- BD3 — commit reachability window (14-15 turns)
-- ---------------------------------------------------------------------------

-- | Angst accrues at 'emAngstAccrualRate' (0.05) per witnessed turn of
-- hemispheric advantage with divergence above the accrual floor, so a
-- fresh trajectory crosses the 0.75 threshold on turn 15 and stays
-- below it on turn 14.
testCommitReachabilityWindow :: IO ()
testCommitReachabilityWindow = do
  let em = defaultEssenceModulation
      traj14 = escalateN 14 em
      traj15 = escalateN 15 em
      angst14 = etAngstLevel traj14
  assertBool
    ( "angst on turn 14 must stay below the 0.75 commitment threshold; got "
        ++ show angst14)
    (angst14 < emAngstCommitmentThreshold em)
  assertEqual "no commitment on turn 14" Nothing (shouldCommit em traj14)
  assertEqual "commitment fires exactly on turn 15"
    (Just TriggerAngstThreshold) (shouldCommit em traj15)
  assertBool
    ( "angst on turn 15 must reach the 0.75 commitment threshold; got "
        ++ show (etAngstLevel traj15))
    (etAngstLevel traj15 >= emAngstCommitmentThreshold em)

-- | A zero-divergence agreement regime decays angst and must not
-- produce a commitment inside the window (no spurious reduction).
testNoSpuriousCommitUnderAgreement :: IO ()
testNoSpuriousCommitUnderAgreement = do
  let em = defaultEssenceModulation
      traj = foldWitness 15 em agreeingWitness emptyTrajectory
  assertEqual "angst stays at floor" 0.0 (etAngstLevel traj)
  assertEqual "no spurious commitment" Nothing (shouldCommit em traj)

-- | A soft collapse resets angst to zero; re-escalation commits again
-- inside the same 14-15 window.
testRecommitAfterSoftCollapse :: IO ()
testRecommitAfterSoftCollapse = do
  let em = defaultEssenceModulation
      committedTraj = escalateN 15 em
      (EssenceUncommitted resetTraj, _) =
        collapseEssenceAt 16 (EssenceUncommitted committedTraj)
      recommitted = escalateFrom resetTraj 15 em
  assertEqual "post-collapse recommit within 15 turns"
    (Just TriggerAngstThreshold) (shouldCommit em recommitted)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- | One escalating witness: hemispheric advantage with out-of-envelope
-- divergence and a healthy log-scale Conatus scalar.
escalatingWitness :: EssenceModulation -> Int -> EssenceTrajectory -> EssenceTrajectory
escalatingWitness em turn traj =
  witness
    em
    turn
    healthyEnergy
    emptyField
    (defaultDeliberation
       { delibTrace = DeliberationTrace
           { dtAgreement = DivergeMultiple
           , dtDivergence = 0.6
           , dtRule = RuleHolisticAdvantage
           , dtSalienceDriver = DrivenByResonance
           }
       })
    traj

-- | @n@ escalating witnesses starting from 'emptyTrajectory'.
escalateN :: Int -> EssenceModulation -> EssenceTrajectory
escalateN n em = escalateFrom emptyTrajectory n em

-- | @n@ escalating witnesses starting from a given trajectory.
escalateFrom :: EssenceTrajectory -> Int -> EssenceModulation -> EssenceTrajectory
escalateFrom seed n em =
  foldWitness n em escalatingWitness seed

-- | A zero-divergence agreement witness (angst decays toward zero).
agreeingWitness :: EssenceModulation -> Int -> EssenceTrajectory -> EssenceTrajectory
agreeingWitness em turn traj =
  witness
    em
    turn
    healthyEnergy
    emptyField
    (defaultDeliberation
       { delibTrace = DeliberationTrace
           { dtAgreement = Agree
           , dtDivergence = 0.0
           , dtRule = RuleAgreement
           , dtSalienceDriver = DrivenByResonance
           }
       })
    traj

-- | Fold @n@ witnesses with increasing turn ordinals.
foldWitness
  :: Int
  -> EssenceModulation
  -> (EssenceModulation -> Int -> EssenceTrajectory -> EssenceTrajectory)
  -> EssenceTrajectory
  -> EssenceTrajectory
foldWitness n em step seed =
  foldl (\t i -> step em i t) seed [1 .. n]

healthyEnergy :: ConatusEnergy
healthyEnergy = ConatusEnergy
  { ceScalar = 14.0
  , ceComponents = ConatusComponents 3.0 3.0 3.0 3.0 1.0
  }

defaultCommitment :: EssenceCommitment
defaultCommitment = EssenceCommitment
  { ecMode = EssenceContemplative
  , ecTrigger = TriggerAngstThreshold
  , ecCommittedAt = 1
  , ecWitnessHash = TrajectoryHash "h"
  }

mkWitness :: Int -> EssenceWitness
mkWitness turn = EssenceWitness
  { ewTurnOrdinal = turn
  , ewSalienceDriver = DrivenByResonance
  , ewReconcileRule = RuleHolisticAdvantage
  , ewAgreement = DivergeMultiple
  , ewDivergence = 0.6
  , ewConatusScalar = 14.0
  , ewFieldSignature = fieldSignature defaultEssenceModulation emptyField
  }
