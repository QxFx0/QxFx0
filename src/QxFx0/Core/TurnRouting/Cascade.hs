{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE StrictData #-}

{-| Routing cascade from semantic/identity signals to guarded family decisions. -}
module QxFx0.Core.TurnRouting.Cascade
  ( runFamilyCascade
  , applyPrincipledFamily
  , applyGuardGating
  , buildGuardReport
  ) where

import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Core.Consciousness (ConsciousnessNarrative)
import QxFx0.Core.IdentityGuard
  ( IdentityGuardReport(..)
  , IdentityGuardWarning(..)
  , buildIdentityGuardReportSimple
  , defaultIdentityGuardCalibration
  )
import QxFx0.Core.PrincipledCore (PrincipledMode(..))
import QxFx0.Core.TurnModulation (intuitionFamilyHint, narrativeFamilyHint)
import QxFx0.Core.TurnPlanning (antiStuck)
import QxFx0.Core.TurnRouting.Phase (identityFamilyHint, preferFamily)
import QxFx0.Core.TurnRouting.Types
  ( FamilyCascade(..)
  , RoutingPhase(..)
  )
import QxFx0.Self.Salience
  ( Salience(..)
  , SalienceDriver(..)
  , SalienceModulation(..)
  , defaultSalienceModulation
  )
import QxFx0.Types
import QxFx0.Types.Thresholds
  ( identityGuardDefaultAgencyBaseline
  , identityGuardDefaultTensionBaseline
  , parserHighConfidenceThreshold
  )

runFamilyCascade :: RoutingPhase -> SystemState -> UserState -> InputPropositionFrame -> AtomSet -> [Text] -> Text
                 -> Maybe ConsciousnessNarrative -> Double -> Bool -> Salience -> FamilyCascade
runFamilyCascade RoutingPhase{..} systemState _nextUserState frame _atomSet _history _input narrative intuitionPosterior isNixBlocked salience =
  let parserLockedFamily =
        if ipfConfidence frame >= parserHighConfidenceThreshold
             && ipfPropositionType frame /= T.pack "PlainAssert"
          then Just (ipfCanonicalFamily frame)
          else Nothing
      familyAfterIdentity =
        case parserLockedFamily of
          Just parserFamily -> parserFamily
          Nothing ->
            maybe rpFamilyAfterStrategy (`preferFamily` rpFamilyAfterStrategy) (identityFamilyHint rpIdentitySignal0)
      narrativeHint = narrative >>= narrativeFamilyHint
      familyAfterNarrative =
        case parserLockedFamily of
          Just parserFamily -> parserFamily
          Nothing -> maybe familyAfterIdentity (`preferFamily` familyAfterIdentity) narrativeHint
      familyAfterIntuition =
        case parserLockedFamily of
          Just parserFamily -> parserFamily
          Nothing -> maybe familyAfterNarrative (`preferFamily` familyAfterNarrative) (intuitionFamilyHint intuitionPosterior)
      familyAfterPrincipled =
        case parserLockedFamily of
          Just parserFamily -> parserFamily
          Nothing -> applyPrincipledFamilyModulated salience rpPrincipledModeResult familyAfterIntuition
      guardReportPre = buildGuardReport (ssLastGuardReport systemState) (ssEgo systemState) rpPreEgo
      familyAfterGuard = applyGuardGatingModulated salience guardReportPre familyAfterPrincipled
      familyCascade = fromMaybe familyAfterGuard (antiStuck (ssConsecutiveReflect systemState) rpPreEgo familyAfterGuard)
      finalFamily = if isNixBlocked then CMRepair else familyCascade
   in FamilyCascade
        { fcFamilyAfterIdentity = familyAfterIdentity
        , fcFamilyAfterNarrative = familyAfterNarrative
        , fcFamilyAfterIntuition = familyAfterIntuition
        , fcFamilyAfterPrincipled = familyAfterPrincipled
        , fcGuardReportPre = guardReportPre
        , fcFamilyAfterGuard = familyAfterGuard
        , fcFamilyCascade = familyCascade
        , fcFinalFamily = finalFamily
        }

applyPrincipledFamily :: Maybe PrincipledMode -> CanonicalMoveFamily -> CanonicalMoveFamily
applyPrincipledFamily mode family =
  case mode of
    Just HoldGround
      | family `elem` [CMConfront, CMHypothesis] -> CMGround
      | otherwise -> family
    Just OpenToUpdate
      | family == CMGround -> CMClarify
      | otherwise -> family
    Just AcknowledgeAndHold
      | family `elem` [CMConfront, CMDeepen] -> CMContact
      | otherwise -> family
    Nothing -> family

-- | Salience-modulated principled-family application.
-- When the controller strongly prefers Holistic (above
-- 'smModulationHolisticBiasFloor'), principled constraints are
-- relaxed so intuition/narrative signals retain more influence.
-- Conatus-gate events force the strict formal path.
--
-- Threshold sourced from 'defaultSalienceModulation'; Phase 7
-- calibration goes through that single record rather than this
-- function.
applyPrincipledFamilyModulated :: Salience -> Maybe PrincipledMode -> CanonicalMoveFamily -> CanonicalMoveFamily
applyPrincipledFamilyModulated salience mode family =
  case salienceDriver salience of
    DrivenByConatusGate -> family
    _ | salienceHolisticBias salience > smModulationHolisticBiasFloor defaultSalienceModulation -> family
    _ -> applyPrincipledFamily mode family

applyGuardGating :: IdentityGuardReport -> CanonicalMoveFamily -> CanonicalMoveFamily
applyGuardGating guardReport family
  | igrWithinBounds guardReport = family
  | GuardAgencyCollapse `elem` igrWarnings guardReport = CMRepair
  | GuardHighTensionDrift `elem` igrWarnings guardReport =
      case family of
        CMConfront -> CMAnchor
        CMDeepen -> CMGround
        _ -> family
  | GuardTransitionOutsideManifold `elem` igrWarnings guardReport =
      case family of
        CMConfront -> CMAnchor
        CMHypothesis -> CMGround
        _ -> family
  | otherwise = family

-- | Salience-modulated guard gating.
-- Holistic-preferring turns (above
-- 'smModulationHolisticBiasFloor') keep all families except
-- agency-collapse (which is always repaired).  Formal/Conatus
-- turns apply the full guard cascade.
--
-- Threshold sourced from 'defaultSalienceModulation'.
applyGuardGatingModulated :: Salience -> IdentityGuardReport -> CanonicalMoveFamily -> CanonicalMoveFamily
applyGuardGatingModulated salience guard family
  | salienceDriver salience == DrivenByConatusGate = applyGuardGating guard family
  | salienceHolisticBias salience > smModulationHolisticBiasFloor defaultSalienceModulation =
      if GuardAgencyCollapse `elem` igrWarnings guard then CMRepair else family
  | otherwise = applyGuardGating guard family

buildGuardReport :: Maybe IdentityGuardReport -> EgoState -> EgoState -> IdentityGuardReport
buildGuardReport lastGuard oldEgo newEgo =
  let (baseAgency, baseTension) =
        case lastGuard of
          Just _ -> (egoAgency oldEgo, egoTension oldEgo)
          Nothing -> (identityGuardDefaultAgencyBaseline, identityGuardDefaultTensionBaseline)
   in buildIdentityGuardReportSimple defaultIdentityGuardCalibration
        baseAgency (egoAgency newEgo) baseTension (egoTension newEgo)
