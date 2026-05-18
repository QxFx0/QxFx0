{-# LANGUAGE RecordWildCards #-}
{-| Facade for routing-phase synthesis, family hints, and guard-aware cascade. -}
module QxFx0.Core.TurnRouting
  ( routeFamily
  , mergeFamilySignals
  , preferFamily
  , semanticInputFamilyHint
  , strategyFamilyHint
  , identityFamilyHint
  , applyPrincipledFamily
  , applyGuardGating
  , RoutingPhase(..)
  , FamilyCascade(..)
  , computeRoutingPhase
  , runFamilyCascade
  ) where

import QxFx0.Types
import QxFx0.Core.TurnPipeline.Types (RoutingDecision(..))
import QxFx0.Core.Ego (updateEgoFromTurn)
import QxFx0.Core.IdentitySignal (buildIdentitySignalSimple)
import QxFx0.Semantic.SemanticInput (buildSemanticInputSimple)
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
  , salienceFromConatusEnergy
  )
import QxFx0.Core.TurnRouting.Cascade
  ( applyGuardGating
  , applyPrincipledFamily
  , buildGuardReport
  , runFamilyCascade
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
            -> RoutingDecision
routeFamily recommendedFamily frame atomSet nextUserState ss history input isNixBlocked currentTopic mNarrative intuitPosterior conatusEnergy preparedField =
  let phase@RoutingPhase{..} = computeRoutingPhase recommendedFamily frame atomSet nextUserState ss history input
      routingSalience = salienceFromConatusEnergy conatusEnergy preparedField
      cascade = runFamilyCascade phase ss nextUserState frame atomSet history input mNarrative intuitPosterior isNixBlocked routingSalience
      FamilyCascade{..} = cascade

      -- Phase 8 (M1/M2): build hemispheric proposals and reconcile.
      -- Package D: family divergence is feature-flagged (default
      -- False) so baseline behaviour is preserved while the
      -- adjunction mapping is corrected.
      familyDivergenceEnabled = False
      formalFamily   = fcFinalFamily
      holisticFamily = if familyDivergenceEnabled then nearestHolistic fcFinalFamily else fcFinalFamily
      renderStrategy = rpChosenStrategy

      baseStyle =
        let styleIdentitySignal = buildIdentitySignalSimple rpOrbitalPhase rpEncounterMode rpPrevDirective
                                  (asRegister atomSet) (usNeedLayer nextUserState) fcFinalFamily (forceForFamily fcFinalFamily)
            styleSemanticInput  = buildSemanticInputSimple input atomSet frame fcFinalFamily (asRegister atomSet) (usNeedLayer nextUserState)
            styleSemanticAnchor = deriveSemanticAnchor (ssSemanticAnchor ss) styleSemanticInput currentTopic (ssTurnCount ss + 1)
         in renderStyleFromDecision renderStrategy rpPrincipledModeResult styleIdentitySignal styleSemanticAnchor styleSemanticInput
      salienceStyle = applySalienceToStyle routingSalience preparedField baseStyle

      -- Phase 8 Package C: observability-grade divergence.
      -- Both proposals share the same reconciled family and style
      -- (behaviour-preserving baseline), but the holistic proposal
      -- carries a narrative tone derived from field atmosphere.
      -- This produces trace-visible 'DivergeOnTone' without changing
      -- runtime output, because 'planNarrativeTone' is not yet read
      -- downstream for rendering (§1 ADR-0011 Package C note).
      formalPlan = defaultPlan
        { planFamily      = formalFamily
        , planRenderStyle = salienceStyle
        }
      holisticPlan = defaultPlan
        { planFamily      = holisticFamily
        , planRenderStyle = salienceStyle
        , planNarrativeTone =
            let a = fieldAtmosphere preparedField
                dm = defaultDeliberationModulation
             in if atmosphereArousal a > dmToneArousalFloor dm && atmosphereValence a >= dmToneValenceNeutral dm
                   then NarrativeWarm
                 else if atmosphereArousal a > dmToneArousalFloor dm && atmosphereValence a < dmToneValenceNeutral dm
                   then NarrativeTerse
                   else NarrativeNeutral
        , planConfidence  = salienceConfidence routingSalience
        }
      -- Package D: formal hemisphere probes the field; holistic
      -- hemisphere carries atmosphere-derived tone already baked
      -- into the Plan, so the wrapper is field-independent.
      deliberation = reconcile routingSalience (holisticProposal holisticPlan emptyField) (formalProposal (\_fd -> formalPlan)) preparedField
      reconciledPlan = delibReconciled deliberation
      reconciledFamily = planFamily reconciledPlan
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
