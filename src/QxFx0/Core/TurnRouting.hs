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
import QxFx0.Core.Semantic.SemanticInput (buildSemanticInputSimple)
import QxFx0.Core.TurnModulation (computeTensionDelta)
import QxFx0.Core.TurnRender
  ( deriveSemanticAnchor
  , renderStyleFromDecision
  )
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

routeFamily :: CanonicalMoveFamily -> InputPropositionFrame -> AtomSet -> UserState
            -> SystemState -> [Text] -> Text -> Bool -> Text
            -> Maybe ConsciousnessNarrative -> Double
            -> RoutingDecision
routeFamily recommendedFamily frame atomSet nextUserState ss history input isNixBlocked currentTopic mNarrative intuitPosterior =
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
      renderStyle = renderStyleFromDecision renderStrategy rpPrincipledModeResult identitySignal semanticAnchor semanticInput
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
