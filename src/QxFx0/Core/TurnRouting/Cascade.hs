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
import QxFx0.Types
import QxFx0.Types.Thresholds
  ( identityGuardDefaultAgencyBaseline
  , identityGuardDefaultTensionBaseline
  , parserHighConfidenceThreshold
  )

runFamilyCascade :: RoutingPhase -> SystemState -> UserState -> InputPropositionFrame -> AtomSet -> [Text] -> Text
                 -> Maybe ConsciousnessNarrative -> Double -> Bool -> FamilyCascade
runFamilyCascade RoutingPhase{..} systemState _nextUserState frame _atomSet _history _input narrative intuitionPosterior isNixBlocked =
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
          Nothing -> applyPrincipledFamily rpPrincipledModeResult familyAfterIntuition
      guardReportPre = buildGuardReport (ssLastGuardReport systemState) (ssEgo systemState) rpPreEgo
      familyAfterGuard = applyGuardGating guardReportPre familyAfterPrincipled
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

buildGuardReport :: Maybe IdentityGuardReport -> EgoState -> EgoState -> IdentityGuardReport
buildGuardReport lastGuard oldEgo newEgo =
  let (baseAgency, baseTension) =
        case lastGuard of
          Just _ -> (egoAgency oldEgo, egoTension oldEgo)
          Nothing -> (identityGuardDefaultAgencyBaseline, identityGuardDefaultTensionBaseline)
   in buildIdentityGuardReportSimple defaultIdentityGuardCalibration
        baseAgency (egoAgency newEgo) baseTension (egoTension newEgo)
