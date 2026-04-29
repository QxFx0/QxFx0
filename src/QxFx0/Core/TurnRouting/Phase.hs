{-# LANGUAGE StrictData #-}

{-| Routing-phase signal synthesis and preferred-family selection helpers. -}
module QxFx0.Core.TurnRouting.Phase
  ( computeRoutingPhase
  , mergeFamilySignals
  , preferFamily
  , semanticInputFamilyHint
  , strategyFamilyHint
  , identityFamilyHint
  ) where

import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Core.Ego (updateEgoFromTurn)
import QxFx0.Core.IdentitySignal (IdentitySignal(..), buildIdentitySignalSimple)
import QxFx0.Core.MeaningGraph (defaultStrategy, predictStrategy, toDepthBand)
import QxFx0.Core.PrincipledCore
  ( classifyPressure
  , detectPressure
  , pressureBandFromState
  , principledMode
  )
import QxFx0.Core.R5Dynamics
  ( EncounterMode(..)
  , classifyEncounterModeSimple
  , classifyOrbitalPhaseSimple
  , defaultCoreDirective
  , steerDirectiveWithOrbitalSimple
  , updateOrbitalMemorySimple
  )
import QxFx0.Core.TurnModulation (computeTensionDelta)
import QxFx0.Core.TurnRouting.Types (RoutingPhase(..))
import QxFx0.Core.Semantic.SemanticInput (SemanticInput(..), buildSemanticInputSimple)
import QxFx0.Types.Thresholds (parserHighConfidenceThreshold)
import QxFx0.Types

computeRoutingPhase :: CanonicalMoveFamily -> InputPropositionFrame -> AtomSet -> UserState
                    -> SystemState -> [Text] -> Text -> RoutingPhase
computeRoutingPhase recommendedFamily frame atomSet nextUserState systemState history input =
  let propositionFamily = ipfCanonicalFamily frame
      familyByParserConfidence =
        if ipfConfidence frame >= parserHighConfidenceThreshold
          then propositionFamily
          else recommendedFamily
      semanticInput0 =
        buildSemanticInputSimple input atomSet frame recommendedFamily (asRegister atomSet) (usNeedLayer nextUserState)
      semanticFamily = semanticInputFamilyHint semanticInput0
      familyMerged = mergeFamilySignalsWithFrame recommendedFamily frame familyByParserConfidence semanticFamily
      parserLocked =
        ipfConfidence frame >= parserHighConfidenceThreshold
          && ipfPropositionType frame /= T.pack "PlainAssert"
      pressure = detectPressure input history
      principledModeResult = fmap principledMode pressure
      pressureBand = pressureBandFromState (classifyPressure pressure history)
      fromMeaningState = MeaningState ResonanceMed pressureBand (toDepthBand (ssTurnCount systemState))
      toMeaningState = MeaningState ResonanceMed pressureBand (toDepthBand (ssTurnCount systemState + 1))
      predictedStrategy = predictStrategy fromMeaningState toMeaningState (ssMeaningGraph systemState)
      chosenStrategy = fromMaybe (defaultStrategy fromMeaningState) predictedStrategy
      strategyFamily = strategyFamilyHint chosenStrategy
      familyAfterStrategy
        | parserLocked = familyMerged
        | otherwise = maybe familyMerged (`preferFamily` familyMerged) strategyFamily
      preEgo = updateEgoFromTurn (ssEgo systemState) familyAfterStrategy (computeTensionDelta input systemState)
      prevDirective = steerDirectiveWithOrbitalSimple (ssOrbitalMemory systemState) defaultCoreDirective
      collapseRisk = egoTension preEgo
      freezeRisk = 1.0 - egoAgency preEgo
      orbitalPhase = classifyOrbitalPhaseSimple collapseRisk freezeRisk
      encounterMode = classifyEncounterModeSimple orbitalPhase (egoTension preEgo)
      updatedOrbital = updateOrbitalMemorySimple (ssOrbitalMemory systemState) orbitalPhase encounterMode prevDirective
      identitySignal0 =
        buildIdentitySignalSimple orbitalPhase encounterMode prevDirective
          (asRegister atomSet) (usNeedLayer nextUserState) familyAfterStrategy (forceForFamily familyAfterStrategy)
   in RoutingPhase
        { rpFamilyMerged = familyMerged
        , rpMPressure = pressure
        , rpPrincipledModeResult = principledModeResult
        , rpPressureBand = pressureBand
        , rpFromMs = fromMeaningState
        , rpToMs = toMeaningState
        , rpChosenStrategy = chosenStrategy
        , rpStrategyFamily = strategyFamily
        , rpFamilyAfterStrategy = familyAfterStrategy
        , rpPreEgo = preEgo
        , rpPrevDirective = prevDirective
        , rpOrbitalPhase = orbitalPhase
        , rpEncounterMode = encounterMode
        , rpUpdatedOrbital = updatedOrbital
        , rpIdentitySignal0 = identitySignal0
        }

mergeFamilySignals :: CanonicalMoveFamily -> CanonicalMoveFamily -> CanonicalMoveFamily -> CanonicalMoveFamily
mergeFamilySignals recommended parser semantic
  | parser /= recommended && parser /= CMGround = parser
  | semantic /= recommended && semantic /= CMGround = semantic
  | otherwise = recommended

mergeFamilySignalsWithFrame :: CanonicalMoveFamily -> InputPropositionFrame -> CanonicalMoveFamily -> CanonicalMoveFamily -> CanonicalMoveFamily
mergeFamilySignalsWithFrame recommended frame parser semantic
  | ipfConfidence frame >= parserHighConfidenceThreshold
      && ipfPropositionType frame /= T.pack "PlainAssert"
      && parser /= recommended = parser
  | otherwise = mergeFamilySignals recommended parser semantic

preferFamily :: CanonicalMoveFamily -> CanonicalMoveFamily -> CanonicalMoveFamily
preferFamily preferred _ = preferred

semanticInputFamilyHint :: SemanticInput -> CanonicalMoveFamily
semanticInputFamilyHint semanticInput =
  let atoms = asAtoms (siAtomSet semanticInput)
      frame = siPropositionFrame semanticInput
      recommended = siRecommendedFamily semanticInput
      rawLower = T.toLower (ipfRawText frame)
      hasConfrontLexeme = T.pack "противореч" `T.isInfixOf` rawLower
      hasAtom p = any (\a -> p (maTag a)) atoms
      isContact (NeedContact _) = True; isContact _ = False
      isRepair (Exhaustion _) = True; isRepair (AgencyLost _) = True; isRepair _ = False
      isConfront (Contradiction _ _) = True; isConfront _ = False
      isDeepen (NeedMeaning _) = True; isDeepen (Searching _) = True; isDeepen _ = False
      isClarify (Verification _) = True; isClarify (Doubt _) = True; isClarify _ = False
      isAnchor (Anchoring _) = True; isAnchor (AgencyFound _) = True; isAnchor _ = False
      keepRecommendedOnClarify =
        not (ipfIsQuestion frame)
          && recommended `elem` [CMGround, CMDefine, CMDistinguish, CMDescribe, CMPurpose, CMContact, CMDeepen]
          && ipfPropositionType frame `notElem` map T.pack ["ClarifyQ", "EpistemicQ", "RequestQ"]
      keepRecommendedOnAnchorQuestion =
        recommended `elem` [CMGround, CMDefine, CMDistinguish, CMDescribe, CMPurpose]
          && ipfPropositionType frame `elem` map T.pack
            [ "SelfStateQ"
            , "SelfKnowledgeQ"
            , "SystemLogicQ"
            , "WorldCauseQ"
            , "OperationalCauseQ"
            , "ConceptKnowledgeQ"
            , "PurposeQ"
            , "DistinctionQ"
            , "ComparisonPlausibilityQ"
            ]
  in if hasConfrontLexeme then CMConfront
     else if hasAtom isContact then CMContact
     else if hasAtom isRepair then CMRepair
     else if hasAtom isConfront then CMConfront
     else if hasAtom isDeepen then CMDeepen
     else if hasAtom isClarify
       then if keepRecommendedOnClarify then recommended else CMClarify
     else if hasAtom isAnchor
       then if keepRecommendedOnAnchorQuestion then recommended else CMAnchor
     else case (siNeedLayer semanticInput, siRegister semanticInput) of
       (ContactLayer, _) -> CMContact
       (_, Contact) -> CMContact
       (_, Exhaust) -> CMRepair
       (_, Anchor) -> CMAnchor
       (_, Search) -> CMDeepen
       _ -> recommended

strategyFamilyHint :: ResponseStrategy -> Maybe CanonicalMoveFamily
strategyFamilyHint strategy =
  case rsMove strategy of
    CounterMove -> Just CMConfront
    ReframeMove -> Just CMClarify
    QuestionMove -> Just CMDeepen
    ValidateMove -> Just CMContact
    SilenceMove -> Just CMAnchor

identityFamilyHint :: IdentitySignal -> Maybe CanonicalMoveFamily
identityFamilyHint signal =
  case isEncounterMode signal of
    EncounterRecovery -> Just CMContact
    EncounterHolding -> Just CMAnchor
    EncounterPressure -> Just CMRepair
    EncounterCounterweight -> Just CMClarify
    EncounterMirroring -> Just CMReflect
    EncounterExploration -> Nothing
