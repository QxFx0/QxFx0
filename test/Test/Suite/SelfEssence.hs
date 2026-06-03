{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

{-|
Module      : Test.Suite.SelfEssence
Description : Property and unit tests for the Phase-9 essence
              selection infrastructure.

Verifies, by QuickCheck and HUnit, the laws asserted in
@docs/adr/0012-essence-commitment.md@ §9:

  * 'extractMode' is deterministic and never returns
    'EssenceWitnessing';
  * angst decays under 'FullAgreement' with zero divergence;
  * angst accrues under hemispheric advantage with sufficient
    divergence;
  * 'shouldCommit' is monotone once fired (vacuously true for
    most random trajectories under default thresholds);
  * trigger priority: 'TriggerAngstThreshold' beats
    'TriggerConatusErosion' when both fire simultaneously;
  * 'emptyEssence' has the expected structural shape;
  * 'fieldSignature' is total on every well-formed 'Field'.
-}
module Test.Suite.SelfEssence
  ( selfEssenceTests
  ) where

import Test.HUnit (Test (..), assertBool, assertEqual, assertFailure)
import Test.QuickCheck
  ( Gen
  , Property
  , arbitrary
  , choose
  , elements
  , forAll
  , listOf
  , maxSuccess
  , quickCheckWithResult
  , stdArgs
  , vectorOf
  , (==>)
  , property
  )
import Test.QuickCheck.Test (isSuccess)

import qualified Data.Sequence as Seq
import Data.Text (Text)
import qualified Data.Text as T

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
import QxFx0.Self.Salience (SalienceDriver (..))

-- ---------------------------------------------------------------------------
-- Test-suite entry point
-- ---------------------------------------------------------------------------

selfEssenceTests :: [Test]
selfEssenceTests =
  [ -- E1 — extractMode determinism + non-Witnessing
    TestLabel "extractMode is deterministic and never returns EssenceWitnessing" $
      quickCheckProperty "extractMode deterministic / non-witnessing"
        propExtractModeDeterministic

    -- E2 — angst decays under FullAgreement
  , TestLabel "angst decays under FullAgreement with zero divergence" $
      quickCheckProperty "angst decay under agreement"
        propAngstDecaysUnderAgreement

    -- E3 — angst accrues under hemispheric advantage with divergence
  , TestLabel "angst accrues under hemispheric advantage with divergence" $
      quickCheckProperty "angst accrues under advantage"
        propAngstAccruesUnderDivergence

    -- E4 — shouldCommit monotone (mostly vacuous under defaults)
  , TestLabel "shouldCommit is monotone once fired" $
      quickCheckProperty "shouldCommit monotone"
        propShouldCommitMonotone

    -- E5 — trigger priority: angst beats Conatus
  , TestLabel "trigger priority: Angst beats Conatus when both fire" $
      quickCheckProperty "trigger priority Angst > Conatus"
        propTriggerPriorityAngst

    -- Unit — emptyEssence shape
  , TestLabel "emptyEssence has expected shape" $
      TestCase testEmptyEssenceShape

    -- Unit — fieldSignature totality
  , TestLabel "fieldSignature is total on emptyField" $
      TestCase testFieldSignatureTotal
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
-- Generators
-- ---------------------------------------------------------------------------

arbitraryUnitDouble :: Gen Double
arbitraryUnitDouble = choose (0.0, 1.0)

arbitrarySignedDouble :: Gen Double
arbitrarySignedDouble = choose (-1.0, 1.0)

arbitraryField :: Gen Field
arbitraryField = do
  r  <- arbitraryUnitDouble
  v  <- arbitrarySignedDouble
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

arbitraryDeliberation :: Gen Deliberation
arbitraryDeliberation = do
  rule     <- arbitraryReconcileRule
  agr      <- arbitraryAgreement
  divg     <- arbitraryUnitDouble
  driver   <- arbitrarySalienceDriver
  hPlan    <- arbitraryPlan
  fPlan    <- arbitraryPlan
  rPlan    <- arbitraryPlan
  pure $ Deliberation
    { delibHolistic   = hPlan
    , delibFormal     = fPlan
    , delibReconciled = rPlan
    , delibTrace      = DeliberationTrace
        { dtAgreement      = agr
        , dtDivergence     = divg
        , dtRule           = rule
        , dtSalienceDriver = driver
        }
    }

arbitraryPlan :: Gen Plan
arbitraryPlan = do
  conf <- arbitraryUnitDouble
  pure $ defaultPlan { planConfidence = conf }

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

-- ---------------------------------------------------------------------------
-- Properties
-- ---------------------------------------------------------------------------

-- | E1 — extractMode determinism + non-Witnessing.
propExtractModeDeterministic :: Property
propExtractModeDeterministic =
  forAll arbitraryEssenceTrajectory $ \t ->
    let m1 = extractMode t
        m2 = extractMode t
    in m1 == m2 && m1 /= EssenceWitnessing

-- | E2 — angst decays under FullAgreement with zero divergence.
propAngstDecaysUnderAgreement :: Property
propAngstDecaysUnderAgreement =
  forAll arbitraryEssenceTrajectory $ \traj ->
    forAll arbitraryField $ \fd ->
    forAll arbitraryConatusEnergy $ \ce ->
    let deliberation = (defaultDeliberation :: Deliberation)
          { delibTrace = (delibTrace defaultDeliberation)
              { dtAgreement  = Agree
              , dtDivergence = 0.0
              , dtRule       = RuleAgreement
              }
          }
        traj' = witness defaultEssenceModulation 1 ce fd deliberation traj
        a0 = etAngstLevel traj
        a1 = etAngstLevel traj'
    in a1 <= a0 || a1 == 0.0

-- | E3 — angst accrues under hemispheric advantage with divergence.
propAngstAccruesUnderDivergence :: Property
propAngstAccruesUnderDivergence =
  forAll arbitraryEssenceTrajectory $ \traj ->
    etAngstLevel traj < 1.0 ==>  -- only meaningful when there is room to accrue
    forAll arbitraryField $ \fd ->
    forAll arbitraryConatusEnergy $ \ce ->
    forAll (choose (0.5, 1.0)) $ \divg ->
    forAll (elements [RuleHolisticAdvantage, RuleFormalAdvantage]) $ \rule ->
    let deliberation = (defaultDeliberation :: Deliberation)
          { delibTrace = (delibTrace defaultDeliberation)
              { dtDivergence = divg
              , dtRule       = rule
              }
          }
        traj' = witness defaultEssenceModulation 1 ce fd deliberation traj
        a0 = etAngstLevel traj
        a1 = etAngstLevel traj'
    in a1 >= a0 || a1 == 1.0

-- | E4 — shouldCommit monotone once fired.
-- Vacuously true for most random trajectories because default
-- thresholds (0.75 angst, 8 witnesses) are rarely hit.
propShouldCommitMonotone :: Property
propShouldCommitMonotone =
  forAll arbitraryEssenceTrajectory $ \traj ->
    forAll arbitraryField $ \fd ->
    forAll arbitraryConatusEnergy $ \ce ->
    forAll arbitraryDeliberation $ \delib ->
    let m0 = shouldCommit defaultEssenceModulation traj
        traj' = witness defaultEssenceModulation 1 ce fd delib traj
        m1 = shouldCommit defaultEssenceModulation traj'
    in case m0 of
         Nothing -> True
         Just _  -> case m1 of
                      Nothing -> False
                      Just _  -> True

-- | E5 — trigger priority: Angst beats Conatus when both fire.
propTriggerPriorityAngst :: Property
propTriggerPriorityAngst =
  let traj = EssenceTrajectory
        { etWitnesses    = Seq.fromList (replicate 8 (emptyWitness 1))
        , etAngstLevel   = 0.80
        , etConatusFloor = 0.40
        , etCapacity     = emTrajectoryCapacity defaultEssenceModulation
        }
  in property (shouldCommit defaultEssenceModulation traj == Just TriggerAngstThreshold)

emptyWitness :: Int -> EssenceWitness
emptyWitness n = EssenceWitness
  { ewTurnOrdinal     = n
  , ewSalienceDriver  = DrivenByDefault
  , ewReconcileRule   = RuleSalienceLead
  , ewAgreement       = Agree
  , ewDivergence      = 0.0
  , ewConatusScalar   = 1.0
  , ewFieldSignature  = fieldSignature defaultEssenceModulation emptyField
  }

-- ---------------------------------------------------------------------------
-- Unit tests
-- ---------------------------------------------------------------------------

testEmptyEssenceShape :: IO ()
testEmptyEssenceShape = do
  let e = emptyEssence
  case e of
    EssenceUncommitted t -> do
      assertEqual "emptyEssence witnesses" Seq.empty (etWitnesses t)
      assertEqual "emptyEssence angst" 0.0 (etAngstLevel t)
      assertEqual "emptyEssence floor" 1.0 (etConatusFloor t)
      assertEqual "emptyEssence capacity"
        (emTrajectoryCapacity defaultEssenceModulation)
        (etCapacity t)
    EssenceCommitted _ _ ->
      assertBool "emptyEssence should be Uncommitted" False

testFieldSignatureTotal :: IO ()
testFieldSignatureTotal = do
  let sig = fieldSignature defaultEssenceModulation emptyField
  -- Totality: no exception, and all bands are valid inhabitants.
  assertBool "resonance band valid" (isValidFieldBand (fsResonance sig))
  assertBool "arousal band valid"   (isValidFieldBand (fsArousal sig))
  assertBool "valence band valid"   (isValidValenceBand (fsValence sig))
  assertBool "consolidation band valid" (isValidFieldBand (fsConsolidation sig))
  assertBool "counterfactual band valid" (isValidFieldBand (fsCounterfactual sig))

isValidFieldBand :: FieldBand -> Bool
isValidFieldBand b = b `elem` [BandLow, BandMid, BandHigh]

isValidValenceBand :: ValenceBand -> Bool
isValidValenceBand b = b `elem` [ValenceNegative, ValenceNeutral, ValencePositive]
