{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

{-|
Module      : Test.Suite.SelfDeliberation
Description : Property tests for the Phase-8 deliberation framework.

Verifies, by QuickCheck, the laws asserted in ADR-0011:

  * 'RuleConatusOverride' always forces formal plan with recovery;
  * 'RuleAgreement' is idempotent and sets confidence to max;
  * recovery is never silenced ('pickHigherSeverity' wins);
  * 'RuleTiedFallback' always returns the formal plan;
  * divergence is bounded in @[0, 1]@;
  * determinism: identical inputs yield identical 'Deliberation'.
-}
module Test.Suite.SelfDeliberation
  ( selfDeliberationTests
  ) where

import Test.HUnit (Test (..), assertFailure)
import Test.QuickCheck
  ( Gen
  , Property
  , choose
  , elements
  , forAll
  , quickCheckWithResult
  , (==>)
  )
import Test.QuickCheck.Test (isSuccess)

import qualified Data.Text as T

import QxFx0.Self.Deliberation
  ( Agreement (..)
  , Deliberation (..)
  , DeliberationTrace (..)
  , NarrativeTone (..)
  , Plan (..)
  , ReconcileRule (..)
  , formalProposal
  , holisticProposal
  , reconcile
  , renderAgreement
  , renderReconcileRule
  )
import QxFx0.Self.Field
  ( Field (..)
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
import QxFx0.Types.Recovery (LocalRecoveryCause (..))
import Test.Support.QuickCheckConfig (qcArgs)

-- ---------------------------------------------------------------------------
-- Test-suite entry point
-- ---------------------------------------------------------------------------

selfDeliberationTests :: [Test]
selfDeliberationTests =
  [ TestLabel "Conatus override forces formal plan with recovery" $
      quickCheckProperty "propConatusOverridesEverything" propConatusOverridesEverything
  , TestLabel "Agreement rule is idempotent and picks max confidence" $
      quickCheckProperty "propAgreementIsIdempotent" propAgreementIsIdempotent
  , TestLabel "Recovery is never silenced" $
      quickCheckProperty "propRecoveryNeverSilenced" propRecoveryNeverSilenced
  , TestLabel "Tied fallback is formal plan" $
      quickCheckProperty "propTiedFallbackIsFormal" propTiedFallbackIsFormal
  , TestLabel "Divergence bounded in [0,1]" $
      quickCheckProperty "propDivergenceBounded" propDivergenceBounded
  , TestLabel "Determinism: identical inputs give identical Deliberation" $
      quickCheckProperty "propDeterminism" propDeterminism
  , TestLabel "renderAgreement is total and stable" $
      quickCheckProperty "propRenderAgreementTotal" propRenderAgreementTotal
  , TestLabel "renderReconcileRule is total and stable" $
      quickCheckProperty "propRenderReconcileRuleTotal" propRenderReconcileRuleTotal
  ]

-- ---------------------------------------------------------------------------
-- QuickCheck plumbing
-- ---------------------------------------------------------------------------

quickCheckProperty :: String -> Property -> Test
quickCheckProperty label prop = TestCase $ do
  args <- qcArgs
  result <- quickCheckWithResult args prop
  if isSuccess result
    then pure ()
    else assertFailure ("Property failed: " ++ label)

-- ---------------------------------------------------------------------------
-- Generators
-- ---------------------------------------------------------------------------

arbitraryField :: Gen Field
arbitraryField = do
  r  <- choose (0.0, 1.0)
  v  <- choose (-1.0, 1.0)
  ar <- choose (0.0, 1.0)
  c  <- choose (0.0, 1.0)
  cf <- choose (0.0, 1.0)
  pure $ Field
    { fieldResonance      = mkResonance r
    , fieldAtmosphere     = mkAtmosphere v ar
    , fieldConfidence     = mkFieldConfidence c
    , fieldConsolidation  = mkConsolidation cf
    , fieldCounterfactual = mkCounterfactual cf
    }

arbitraryPlan :: Gen Plan
arbitraryPlan = do
  family  <- elements [CMGround, CMDefine, CMDistinguish, CMReflect, CMDescribe
                      , CMPurpose, CMHypothesis, CMRepair, CMContact, CMAnchor
                      , CMClarify, CMDeepen, CMConfront, CMNextStep]
  style   <- elements [StyleFormal, StyleWarm, StyleDirect, StylePoetic
                      , StyleClinical, StyleCautious, StyleRecovery, StyleStandard]
  mCause  <- elements [Nothing, Just RecoveryLowLegitimacy
                      , Just RecoveryParserLowConfidence
                      , Just RecoveryConatusGate]
  tone    <- elements [NarrativeNeutral, NarrativeWarm, NarrativeFormal
                      , NarrativeTerse, NarrativeRecovery]
  conf    <- choose (0.0, 1.0)
  pure $ Plan
    { planFamily        = family
    , planRenderStyle   = style
    , planRecoveryCause = mCause
    , planNarrativeTone = tone
    , planConfidence    = conf
    }

arbitrarySalience :: Gen Salience
arbitrarySalience = do
  bias  <- choose (0.0, 1.0)
  conf  <- choose (0.0, 1.0)
  driver <- elements
    [ DrivenByResonance
    , DrivenByAtmosphere
    , DrivenByConsolidation
    , DrivenByCounterfactual
    , DrivenByFieldConfidence
    , DrivenByConatusGate
    , DrivenByDefault
    ]
  pure $ Salience
    { salienceHolisticBias = bias
    , salienceConfidence   = conf
    , salienceDriver       = driver
    }

-- | Same as 'arbitrarySalience' but excluding 'DrivenByConatusGate',
-- which forces 'RuleConatusOverride' regardless of the proposal
-- shape. Used by properties that test non-override behaviour.
arbitraryNonConatusSalience :: Gen Salience
arbitraryNonConatusSalience = do
  bias  <- choose (0.0, 1.0)
  conf  <- choose (0.0, 1.0)
  driver <- elements
    [ DrivenByResonance
    , DrivenByAtmosphere
    , DrivenByConsolidation
    , DrivenByCounterfactual
    , DrivenByFieldConfidence
    , DrivenByDefault
    ]
  pure $ Salience
    { salienceHolisticBias = bias
    , salienceConfidence   = conf
    , salienceDriver       = driver
    }

-- ---------------------------------------------------------------------------
-- Properties
-- ---------------------------------------------------------------------------

-- B.6.1
propConatusOverridesEverything :: Property
propConatusOverridesEverything =
  forAll arbitraryPlan $ \hPlan ->
  forAll arbitraryPlan $ \fPlan ->
  forAll arbitraryField $ \fd ->
  forAll arbitrarySalience $ \salience ->
    let conatusSalience = salience { salienceDriver = DrivenByConatusGate }
        hp = holisticProposal hPlan fd
        fp = formalProposal (\_ -> fPlan)
        d  = reconcile Nothing conatusSalience hp fp fd
        r  = delibReconciled d
        t  = delibTrace d
     in planRenderStyle r == StyleRecovery
        && planRecoveryCause r == Just RecoveryConatusGate
        && planNarrativeTone r == NarrativeRecovery
        && planConfidence r == 1.0
        && dtRule t == RuleConatusOverride

-- B.6.2 — when both proposals are identical and the salience
-- driver is not 'DrivenByConatusGate' (which legitimately
-- rewrites the plan into recovery shape), 'reconcile' returns
-- the same plan and tags 'RuleAgreement' with 'Agree'.
propAgreementIsIdempotent :: Property
propAgreementIsIdempotent =
  forAll arbitraryPlan $ \plan ->
  forAll arbitraryField $ \fd ->
  forAll arbitraryNonConatusSalience $ \salience ->
    let hp = holisticProposal plan fd
        fp = formalProposal (\_ -> plan)
        d  = reconcile Nothing salience hp fp fd
        r  = delibReconciled d
        t  = delibTrace d
     in r == plan
        && dtAgreement t == Agree
        && dtRule t == RuleAgreement

-- B.6.3
propRecoveryNeverSilenced :: Property
propRecoveryNeverSilenced =
  forAll arbitraryPlan $ \hPlan ->
  forAll arbitraryPlan $ \fPlan ->
  forAll arbitraryField $ \fd ->
  forAll arbitrarySalience $ \salience ->
    let hHasRecovery = planRecoveryCause hPlan /= Nothing
        fHasRecovery = planRecoveryCause fPlan /= Nothing
        hp = holisticProposal hPlan fd
        fp = formalProposal (\_ -> fPlan)
        d  = reconcile Nothing salience hp fp fd
        r  = delibReconciled d
     in (hHasRecovery || fHasRecovery)
        ==> (planRecoveryCause r /= Nothing)

-- B.6.4
propTiedFallbackIsFormal :: Property
propTiedFallbackIsFormal =
  forAll arbitraryPlan $ \hPlan ->
  forAll arbitraryPlan $ \fPlan ->
  forAll arbitraryField $ \fd ->
    let salience = Salience
          { salienceHolisticBias = 0.5
          , salienceConfidence   = 0.0
          , salienceDriver       = DrivenByDefault
          }
        hp = holisticProposal hPlan fd
        fp = formalProposal (\_ -> fPlan)
        d  = reconcile Nothing salience hp fp fd
        r  = delibReconciled d
        t  = delibTrace d
     in dtRule t == RuleTiedFallback
        ==> (r == fPlan { planRecoveryCause = planRecoveryCause r })

-- B.6.5
propDivergenceBounded :: Property
propDivergenceBounded =
  forAll arbitraryPlan $ \hPlan ->
  forAll arbitraryPlan $ \fPlan ->
  forAll arbitraryField $ \fd ->
  forAll arbitrarySalience $ \salience ->
    let hp = holisticProposal hPlan fd
        fp = formalProposal (\_ -> fPlan)
        d  = reconcile Nothing salience hp fp fd
        divg = dtDivergence (delibTrace d)
     in divg >= 0.0 && divg <= 1.0

-- B.6.6
propDeterminism :: Property
propDeterminism =
  forAll arbitraryPlan $ \hPlan ->
  forAll arbitraryPlan $ \fPlan ->
  forAll arbitraryField $ \fd ->
  forAll arbitrarySalience $ \salience ->
    let hp = holisticProposal hPlan fd
        fp = formalProposal (\_ -> fPlan)
        d1 = reconcile Nothing salience hp fp fd
        d2 = reconcile Nothing salience hp fp fd
     in d1 == d2

-- Extra: renderAgreement is total (no pattern-match failure)
propRenderAgreementTotal :: Property
propRenderAgreementTotal =
  forAll (elements [Agree, DivergeOnFamily, DivergeOnStyle
                   , DivergeOnRecovery, DivergeOnTone, DivergeMultiple]) $ \ag ->
    let txt = renderAgreement ag
     in not (T.null txt)

-- Extra: renderReconcileRule is total (no pattern-match failure)
propRenderReconcileRuleTotal :: Property
propRenderReconcileRuleTotal =
  forAll (elements [RuleAgreement, RuleConatusOverride, RuleSalienceLead
                   , RuleHolisticAdvantage, RuleFormalAdvantage, RuleTiedFallback]) $ \rule ->
    let txt = renderReconcileRule rule
     in not (T.null txt)
