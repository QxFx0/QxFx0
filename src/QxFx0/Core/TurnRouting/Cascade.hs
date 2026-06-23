{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE StrictData #-}

{-| Routing cascade from semantic/identity signals to guarded family decisions. -}
module QxFx0.Core.TurnRouting.Cascade
  ( runFamilyCascade
  , applyPrincipledFamily
  , applyGuardGating
  , applyConatusGateRestriction
  , buildGuardReport
  , commitmentFamilyHint
  ) where

import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Memory.Episodic (EpisodicEvent(..), EpisodicKind(..), episodicRecallActive)
import QxFx0.Core.StanceClassifier (ConsciousnessNarrative)
import QxFx0.Core.ConsciousnessLoop (doubtSuppressionThreshold, doubtLoopActive)
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
import QxFx0.Self.Conatus (ConatusEnergy(..), lowEnergyThreshold)
import QxFx0.Self.Salience
  ( Salience(..)
  , SalienceDriver(..)
  , SalienceModulation(..)
  , defaultSalienceModulation
  )
import QxFx0.Types
import QxFx0.Types.Thresholds
import QxFx0.Types.Thresholds.Routing
  ( identityGuardDefaultAgencyBaseline
  , identityGuardDefaultTensionBaseline
  )
import QxFx0.Types.PropositionType (PropositionType(..))
import QxFx0.Types.State.SemanticCommitment (CommitmentEngagement(..))

-- | WP-B R-B3: check if retrieved episodes contain recent system decisions.
-- If yes, suppress doubt-driven CMClarify override (don't re-ask established facts).
hasRecentSystemDecision :: [EpisodicEvent] -> Bool
hasRecentSystemDecision episodes =
  any (\e -> eeKind e == EpisodicSystemDecision) episodes

-- | SUBJECT-SEAM-1: when the turn contradicts a held commitment, hint
-- toward CMReflect (soft re-assertion) rather than passive continuation.
commitmentFamilyHint :: CommitmentEngagement -> Maybe CanonicalMoveFamily
commitmentFamilyHint ce
  | ceContradicted ce = Just CMReflect
  | otherwise         = Nothing

runFamilyCascade :: RoutingPhase -> SystemState -> UserState -> InputPropositionFrame -> AtomSet -> [Text] -> Text
                 -> Maybe ConsciousnessNarrative -> Double -> Bool -> Salience -> ConatusEnergy -> Double -> [EpisodicEvent] -> CommitmentEngagement -> FamilyCascade
runFamilyCascade RoutingPhase{..} systemState _nextUserState frame _atomSet _history input narrative intuitionPosterior isNixBlocked salience conatusEnergy doubt retrievedEpisodes commitmentEngagement =
  let parserLockedFamily =
        if (hasChallengeMarker input
              || ipfPropositionType frame `elem` [ConfrontQ, MisunderstandingReport, RepairSignal]
              || ipfConfidence frame >= parserHighConfidenceThreshold)
              && ipfPropositionType frame /= PlainAssert
          then Just (if hasChallengeMarker input then CMConfront else ipfCanonicalFamily frame)
          else Nothing
      familyAfterIdentity =
        case parserLockedFamily of
          Just parserFamily -> parserFamily
          Nothing ->
            maybe rpFamilyAfterStrategy (`preferFamily` rpFamilyAfterStrategy) (identityFamilyHint rpIdentitySignal0)
      familyAfterCommitment =
        case parserLockedFamily of
          Just parserFamily -> parserFamily
          Nothing -> maybe familyAfterIdentity (`preferFamily` familyAfterIdentity) (commitmentFamilyHint commitmentEngagement)
      narrativeHint = narrative >>= narrativeFamilyHint
      familyAfterNarrative =
        case parserLockedFamily of
          Just parserFamily -> parserFamily
          Nothing -> maybe familyAfterCommitment (`preferFamily` familyAfterCommitment) narrativeHint
      familyAfterIntuition =
        case parserLockedFamily of
          Just parserFamily -> parserFamily
          Nothing -> maybe familyAfterNarrative (`preferFamily` familyAfterNarrative) (intuitionFamilyHint intuitionPosterior)
      familyAfterPrincipled =
        case parserLockedFamily of
          Just parserFamily -> parserFamily
          Nothing -> applyPrincipledFamilyModulated salienceGuardDivergenceEnabled salience rpPrincipledModeResult familyAfterIntuition
      guardReportPre = buildGuardReport (ssLastGuardReport systemState) (ssEgo systemState) rpPreEgo
      familyAfterGuard = applyGuardGatingModulated salienceGuardDivergenceEnabled salience guardReportPre familyAfterPrincipled
      -- P1 Conatus Gate: when energy is low, restrict to restorative families.
      -- Low energy (< lowEnergyThreshold) prohibits high-risk families
      -- (CMConfront, CMHypothesis, CMDistinguish) and allows only restorative
      -- families (CMContact, CMAnchor, CMRepair). This implements the
      -- self-preservation routing constraint specified in ADR-0045.
      familyAfterConatusGate =
        case parserLockedFamily of
          Just parserFamily -> parserFamily
          Nothing ->
            if ceScalar conatusEnergy < lowEnergyThreshold
              then applyConatusGateRestriction familyAfterGuard
              else familyAfterGuard
      -- WP-D + WP-B R-B3: doubt-driven family override with episodic memory check.
      -- When doubt is high (≥ threshold) and the doubt loop is active, prefer
      -- CMClarify to signal uncertainty — UNLESS retrieved episodes show the
      -- system already provided a decision on this topic (don't re-ask).
      familyAfterDoubt =
        case parserLockedFamily of
          Just parserFamily -> parserFamily
          Nothing ->
            let shouldClarify = doubtLoopActive
                             && doubt >= doubtSuppressionThreshold
                             && not (episodicRecallActive && hasRecentSystemDecision retrievedEpisodes)
            in if shouldClarify
              then CMClarify
              else familyAfterConatusGate
      familyCascade = fromMaybe familyAfterDoubt (antiStuck (ssConsecutiveReflect systemState) rpPreEgo familyAfterDoubt)
      -- Guard Blocked no longer forces CMRepair. Instead, the cascaded
      -- family is preserved; the guard block is recorded in the trace
      -- and truth-contract classification. This prevents the systematic
      -- fallback-to-repair that blocked 2/5 covered definition topics
      -- (svoboda, istina) in B2 evaluation. The guard still blocks
      -- constitutionally; the route simply doesn't discard the user's
      -- intent (definition/distinction) because of it.
      finalFamily = familyCascade
      -- Phase 8 Package D: salience-modulated guard divergence (always enabled)
      salienceGuardDivergenceEnabled = True
   in FamilyCascade
         { fcFamilyAfterIdentity = familyAfterIdentity
         , fcFamilyAfterCommitment = familyAfterCommitment
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
applyPrincipledFamilyModulated :: Bool -> Salience -> Maybe PrincipledMode -> CanonicalMoveFamily -> CanonicalMoveFamily
applyPrincipledFamilyModulated salienceGuardDivergenceEnabled salience mode family =
  case salienceDriver salience of
    DrivenByConatusGate -> applyPrincipledFamily mode family
    _ | salienceGuardDivergenceEnabled && salienceHolisticBias salience > smModulationHolisticBiasFloor defaultSalienceModulation -> family
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
applyGuardGatingModulated :: Bool -> Salience -> IdentityGuardReport -> CanonicalMoveFamily -> CanonicalMoveFamily
applyGuardGatingModulated salienceGuardDivergenceEnabled salience guard family
  | salienceDriver salience == DrivenByConatusGate = applyGuardGating guard family
  | salienceGuardDivergenceEnabled && salienceHolisticBias salience > smModulationHolisticBiasFloor defaultSalienceModulation =
      if GuardAgencyCollapse `elem` igrWarnings guard then CMRepair else family
  | otherwise = applyGuardGating guard family

-- | Apply Conatus gate restriction: when energy is low, map high-risk
-- families to restorative alternatives. This is the core P1 integration
-- that closes the gap between Conatus computation and routing behaviour.
--
-- Mapping:
-- * CMConfront → CMContact (restorative engagement)
-- * CMHypothesis → CMAnchor (grounding in established facts)
-- * CMDistinguish → CMRepair (structural recovery)
-- * All other families → unchanged (already safe or restorative)
applyConatusGateRestriction :: CanonicalMoveFamily -> CanonicalMoveFamily
applyConatusGateRestriction family =
  case family of
    CMConfront    -> CMContact
    CMHypothesis  -> CMAnchor
    CMDistinguish -> CMRepair
    _             -> family  -- CMContact, CMAnchor, CMRepair, CMClarify, CMGround, CMDeepen already safe

buildGuardReport :: Maybe IdentityGuardReport -> EgoState -> EgoState -> IdentityGuardReport
buildGuardReport lastGuard oldEgo newEgo =
  let (baseAgency, baseTension) =
        case lastGuard of
          Just _ -> (egoAgency oldEgo, egoTension oldEgo)
          Nothing -> (identityGuardDefaultAgencyBaseline, identityGuardDefaultTensionBaseline)
    in buildIdentityGuardReportSimple defaultIdentityGuardCalibration
         baseAgency (egoAgency newEgo) baseTension (egoTension newEgo)

hasChallengeMarker :: Text -> Bool
hasChallengeMarker input =
  let lowered = T.toLower input
  in any (`T.isInfixOf` lowered) (map T.pack
       [ "разве", "не согласен", "не согласна", "противореч", "неверно"
       , "ошибаешься", "не прав", "спорю", "возраж", "сомневаюсь"
       , "ты говоришь", "оспариваю"
       , "это просто", "не более чем", "сводится к"
       , "всего лишь", "это лишь"
       ])
