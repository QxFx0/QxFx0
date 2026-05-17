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
  , renderStyleFromDecisionWithSalience
  )
import QxFx0.Self.Conatus (ConatusEnergy)
import QxFx0.Self.Field (Field)
import QxFx0.Self.Salience (salienceFromConatusEnergy)
import QxFx0.Core.Consciousness (ConsciousnessNarrative(..))
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
      cascade = runFamilyCascade phase ss nextUserState frame atomSet history input mNarrative intuitPosterior isNixBlocked
      FamilyCascade{..} = cascade

      newEgo = updateEgoFromTurn (ssEgo ss) fcFinalFamily (computeTensionDelta input ss)
      identitySignal = buildIdentitySignalSimple rpOrbitalPhase rpEncounterMode rpPrevDirective
                         (asRegister atomSet) (usNeedLayer nextUserState) fcFinalFamily (forceForFamily fcFinalFamily)
      guardReport = buildGuardReport (ssLastGuardReport ss) (ssEgo ss) newEgo
      semanticInput = buildSemanticInputSimple input atomSet frame fcFinalFamily (asRegister atomSet) (usNeedLayer nextUserState)
      semanticAnchor = deriveSemanticAnchor (ssSemanticAnchor ss) semanticInput currentTopic (ssTurnCount ss + 1)
      renderStrategy = rpChosenStrategy
      routingSalience = salienceFromConatusEnergy conatusEnergy preparedField
      renderStyle = renderStyleFromDecisionWithSalience routingSalience renderStrategy rpPrincipledModeResult identitySignal semanticAnchor semanticInput
  in RoutingDecision
       { rdFamily = fcFinalFamily
       , rdNewEgo = newEgo
       , rdIdentitySignal = identitySignal
       , rdGuardReport = guardReport
       , rdSemanticInput = semanticInput
       , rdSemanticAnchor = semanticAnchor
       , rdRenderStrategy = renderStrategy
       , rdRenderStyle = renderStyle
       , rdPrincipledMode = rpPrincipledModeResult
       , rdPressure = rpMPressure
       , rdUpdatedOrbital = rpUpdatedOrbital
       , rdFromMs = rpFromMs
       , rdToMs = rpToMs
       , rdStrategyFamily = rpStrategyFamily
       }
