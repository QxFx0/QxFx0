{-# LANGUAGE RecordWildCards #-}
{-| Facade for routing-phase synthesis, family hints, and guard-aware cascade. -}
module QxFx0.Core.TurnRouting
  ( routeFamily
  , routeFamilyWithSelfVerdict
  , mergeFamilySignals
  , preferFamily
  , semanticInputFamilyHint
  , strategyFamilyHint
  , identityFamilyHint
  , applyPrincipledFamily
  , applyGuardGating
  , applyConatusGateRestriction
  , RoutingPhase(..)
  , FamilyCascade(..)
  , computeRoutingPhase
  , runFamilyCascade
  ) where

import QxFx0.Types
import QxFx0.Types.State.SelfState (SelfState(..))
import QxFx0.Core.TurnPipeline.Types (RoutingDecision(..))
import QxFx0.Core.Ego (updateEgoFromTurn)
import QxFx0.Core.IdentitySignal (buildIdentitySignalSimple)
import QxFx0.Semantic.SemanticInput (buildSemanticInputSimple)
import QxFx0.Semantic.Retrieve (detectCommitmentEngagement)
import QxFx0.Core.TurnModulation (computeTensionDelta)
import QxFx0.Core.TurnRender
  ( deriveSemanticAnchor
  , renderStyleFromDecision
  , applySalienceToStyle
  )
import QxFx0.Self.Conatus (ConatusEnergy)
import QxFx0.Self.Deliberation
  ( Plan(..)
  , defaultPlan
  , defaultDeliberationModulation
  , DeliberationModulation(..)
  , holisticProposal
  , formalProposal
  , Deliberation(..)
  , reconcile
  , NarrativeTone(..)
  )
import QxFx0.Self.Field (Field, emptyField, fieldAtmosphere, Atmosphere(..))
import QxFx0.Self.Salience
  ( Salience(..)
  , computeSelfVerdict
  , SelfVerdict(..)
  , SalienceVerdict(..)
  )
import QxFx0.Self.Adjunction (holisticFormalContextSplitActive)
import QxFx0.Core.ContentCluster (computeContentSaliency)  -- WP-C (renamed from Spectral, WP-I Tier-0)
import QxFx0.Memory.Episodic (EpisodicEvent)
import QxFx0.Types.State.SemanticCommitment (CommitmentEngagement(..), MatchKind(..))
import QxFx0.Core.TurnRouting.Cascade
  ( applyConatusGateRestriction
  , applyGuardGating
  , applyPrincipledFamily
  , buildGuardReport
  , runFamilyCascade
  )
import QxFx0.Core.FamilyAdmission
  ( FamilyAdmissionInput(..)
  , AdmittedFamily(..)
  , admitFamilyCrystallization
  )
import QxFx0.Core.TurnRouting.Phase
  ( computeRoutingPhase
  , identityFamilyHint
  , mergeFamilySignals
  , preferFamily
  , semanticInputFamilyHint
  , strategyFamilyHint
  )
import QxFx0.Core.TurnRouting.Types
  ( FamilyCascade(..)
  , RoutingPhase(..)
  )

import Data.Text (Text)

nearestHolistic :: CanonicalMoveFamily -> CanonicalMoveFamily
nearestHolistic CMAnchor      = CMReflect
nearestHolistic CMDistinguish = CMDefine
nearestHolistic CMClarify     = CMHypothesis
nearestHolistic CMNextStep    = CMPurpose
nearestHolistic other         = other

supportsHolisticFamilyDivergence :: CanonicalMoveFamily -> Bool
supportsHolisticFamilyDivergence family =
  family `elem` [CMAnchor, CMDistinguish, CMClarify]



-- | Phase 6 (M6) + Phase 5.5d: 'routeFamily' takes the per-turn
-- 'ConatusEnergy' and 'Field' precomputed by the Prepare stage
-- (see 'QxFx0.Core.TurnPipeline.Effects.psConatusEnergy' \/
-- 'psField', threaded through 'tiConatusEnergy' \/ 'tiField').
-- The previous local computeSelfBlanket \/ checkInitialBlanket
-- \/ salienceFromBlanket triple was already collapsed in M6;
-- this commit additionally replaces the @emptyField@ default in
-- 'salienceFromConatusEnergy' with the canonical pre-turn
-- 'Field' carrying the runtime Resonance component.
routeFamily :: CanonicalMoveFamily -> InputPropositionFrame -> AtomSet -> UserState
            -> SystemState -> [Text] -> Text -> Bool -> Text
            -> Maybe ConsciousnessNarrative -> Double -> ConatusEnergy -> Field
            -> Double -> Maybe (Plan -> Bool) -> [EpisodicEvent]
            -> RoutingDecision
routeFamily recommendedFamily frame atomSet nextUserState ss history input isNixBlocked currentTopic mNarrative intuitPosterior conatusEnergy preparedField doubt mCourtesy retrievedEpisodes =
  let contentSaliency = computeContentSaliency (ssMeaningGraph ss)  -- WP-C: top-down content signal
  in routeFamilyWithSelfVerdict
    recommendedFamily
    frame
    atomSet
    nextUserState
    ss
    history
    input
    isNixBlocked
    currentTopic
    mNarrative
    intuitPosterior
    preparedField
    (computeSelfVerdict (selfSalienceWeights (ssSelfState ss)) conatusEnergy preparedField contentSaliency)
    conatusEnergy
    doubt
    mCourtesy
    retrievedEpisodes

routeFamilyWithSelfVerdict :: CanonicalMoveFamily -> InputPropositionFrame -> AtomSet -> UserState
                          -> SystemState -> [Text] -> Text -> Bool -> Text
                          -> Maybe ConsciousnessNarrative -> Double -> Field -> SelfVerdict -> ConatusEnergy
                          -> Double -> Maybe (Plan -> Bool) -> [EpisodicEvent]
                          -> RoutingDecision
routeFamilyWithSelfVerdict recommendedFamily frame atomSet nextUserState  ss history input isNixBlocked currentTopic mNarrative intuitPosterior preparedField selfVerdict conatusEnergy doubt mCourtesy retrievedEpisodes =
  let phase@RoutingPhase{..} = computeRoutingPhase recommendedFamily frame atomSet nextUserState ss history input
      routingSalience = svSalience selfVerdict
      commitmentEngagement =
        case ssSemanticCommitments ss of
          Just store -> detectCommitmentEngagement store currentTopic atomSet
          Nothing    -> CommitmentEngagement [] False NoMatch
      cascade = runFamilyCascade phase ss nextUserState frame atomSet history input mNarrative intuitPosterior isNixBlocked routingSalience conatusEnergy doubt retrievedEpisodes commitmentEngagement
      FamilyCascade{..} = cascade

      -- Phase 8 (M1/M2): build hemispheric proposals and reconcile.
      -- Package D: family divergence for reconcile is dynamically determined
      -- based on self-verdict and family support for holistic divergence.
      reconcileFamilyDivergence =
        case svVerdict selfVerdict of
          PreferHolistic _ -> supportsHolisticFamilyDivergence fcFinalFamily
          PreferFormal _   -> False
          Tied             -> False
      formalFamily   = fcFinalFamily
      holisticFamily = if reconcileFamilyDivergence then nearestHolistic fcFinalFamily else fcFinalFamily
      renderStrategy = rpChosenStrategy
      atmosphereTone =
        let a = fieldAtmosphere preparedField
            dm = defaultDeliberationModulation
        in if atmosphereArousal a > dmToneArousalFloor dm && atmosphereValence a >= dmToneValenceNeutral dm
             then NarrativeWarm
           else if atmosphereArousal a > dmToneArousalFloor dm && atmosphereValence a < dmToneValenceNeutral dm
             then NarrativeTerse
           else NarrativeNeutral

      baseStyle =
        let styleIdentitySignal = buildIdentitySignalSimple rpOrbitalPhase rpEncounterMode rpPrevDirective
                                  (asRegister atomSet) (usNeedLayer nextUserState) fcFinalFamily (forceForFamily fcFinalFamily)
            styleSemanticInput  = buildSemanticInputSimple input atomSet frame fcFinalFamily (asRegister atomSet) (usNeedLayer nextUserState)
            styleSemanticAnchor = deriveSemanticAnchor (ssSemanticAnchor ss) styleSemanticInput currentTopic (ssTurnCount ss + 1)
         in renderStyleFromDecision renderStrategy rpPrincipledModeResult atmosphereTone styleIdentitySignal styleSemanticAnchor styleSemanticInput
      salienceStyle = applySalienceToStyle (selfSalienceWeights (ssSelfState ss)) routingSalience preparedField baseStyle

      -- WP-H3 (ADR-0019 promoted, divergence IS real): the two proposals
      -- carry different families (holisticFamily vs formalFamily) and the
      -- 'reconcile' function in 'Self.Deliberation' can pick either under
      -- 'RuleHolisticAdvantage'/'RuleFormalAdvantage', so 'reconciledFamily'
      -- genuinely affects the rendered output. The 'DivergeOnTone' trace tag
      -- is now 'DivergeOnFamily'/'DivergeOnTone' depending on what actually
      -- differed. Narrative tone still diverges when the holistic plan carries
      -- an atmosphere-derived tone and the formal one does not.
      -- P4: Holistic/Formal context split. When flag is on, formal proposal
      -- sees emptyField (no atmosphere, no salience bias) and holistic proposal
      -- sees full preparedField. When flag is off, both see preparedField
      -- (current behaviour preserved).
      formalFieldContext = if holisticFormalContextSplitActive then emptyField else preparedField
      holisticFieldContext = preparedField
      
      formalPlan = defaultPlan
        { planFamily      = formalFamily
        , planRenderStyle = salienceStyle
        }
      holisticPlan = defaultPlan
        { planFamily      = holisticFamily
        , planRenderStyle = salienceStyle
        , planNarrativeTone = atmosphereTone
        , planConfidence  = salienceConfidence routingSalience
        }
      -- The formal proposal is field-independent (ADR-0011 §1: formal mode
      -- treats the field as a strategy, not a value), but 'reconcile' still
      -- evaluates both and can pick the holistic one.
      -- P4: holisticProposal receives holisticFieldContext (full Field when flag on),
      -- formalProposal receives formalFieldContext (emptyField when flag on).
      deliberation = reconcile mCourtesy routingSalience (holisticProposal holisticPlan holisticFieldContext) (formalProposal (\_fd -> formalPlan)) formalFieldContext
      reconciledPlan = delibReconciled deliberation
      rawReconciledFamily = planFamily reconciledPlan
      admittedFamily = admitFamilyCrystallization
        (FamilyAdmissionInput (ssTruthContractStatus ss) selfVerdict)
        rawReconciledFamily
        frame
      reconciledFamily = afFamily admittedFamily
      reconciledStyle  = planRenderStyle reconciledPlan

      -- Recompute downstream context if the reconciled family
      -- diverges from the salience-escalated candidate.
      newEgo = updateEgoFromTurn (ssEgo ss) reconciledFamily (computeTensionDelta input ss)
      identitySignal = buildIdentitySignalSimple rpOrbitalPhase rpEncounterMode rpPrevDirective
                         (asRegister atomSet) (usNeedLayer nextUserState) reconciledFamily (forceForFamily reconciledFamily)
      guardReport = buildGuardReport (ssLastGuardReport ss) (ssEgo ss) newEgo
      semanticInput = buildSemanticInputSimple input atomSet frame reconciledFamily (asRegister atomSet) (usNeedLayer nextUserState)
      semanticAnchor = deriveSemanticAnchor (ssSemanticAnchor ss) semanticInput currentTopic (ssTurnCount ss + 1)
   in RoutingDecision
        { rdFamily = reconciledFamily
       , rdNewEgo = newEgo
       , rdIdentitySignal = identitySignal
       , rdGuardReport = guardReport
       , rdSemanticInput = semanticInput
       , rdSemanticAnchor = semanticAnchor
       , rdRenderStrategy = renderStrategy
       , rdRenderStyle = reconciledStyle
       , rdPrincipledMode = rpPrincipledModeResult
       , rdPressure = rpMPressure
       , rdUpdatedOrbital = rpUpdatedOrbital
       , rdFromMs = rpFromMs
       , rdToMs = rpToMs
       , rdStrategyFamily = rpStrategyFamily
       , rdDeliberation = Just deliberation
       }
