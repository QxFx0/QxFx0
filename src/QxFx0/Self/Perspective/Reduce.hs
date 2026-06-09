{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : QxFx0.Self.Perspective.Reduce
Description : canonical — Perspective reduction and projection builders.
-}

module QxFx0.Self.Perspective.Reduce
  ( applyPerspectiveDecision
  , buildPerspectiveProjection
  , buildActivePerspectiveProjections
  ) where

import Data.List (sortOn)
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Ord (Down(..))
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Types.State.Perspective

applyPerspectiveDecision :: Int -> PerspectiveRegistry -> PerspectiveInputBundle -> PerspectiveCandidate -> PerspectivePromotionDecision -> PerspectiveRegistry
applyPerspectiveDecision turn registry bundle candidate decision =
  case decision of
    PpdObserveOnly -> registry { prLastUpdatedTurn = turn }
    PpdQuarantine -> upsertThread turn registry bundle candidate decision PerspectiveContested Nothing
    PpdAcceptBounded -> upsertThread turn registry bundle candidate decision PerspectiveContested Nothing
    PpdPromoteEndorsed -> upsertThread turn registry bundle candidate decision PerspectiveActive (Just turn)
    PpdReviseActive -> upsertThread turn registry bundle candidate decision PerspectiveActive (Just turn)
    PpdSuspendActive -> suspendActivePerspective turn registry candidate decision
    PpdRollbackPrior -> rollbackPriorPerspective turn registry candidate decision

buildPerspectiveProjection :: PerspectiveRegistry -> PerspectiveScope -> Maybe PerspectiveProjection
buildPerspectiveProjection registry scope = do
  thread <- M.lookup scope (prThreads registry)
  endorsed <- activeEndorsedPerspective thread
  pure PerspectiveProjection
    { ppScope = epScope endorsed
    , ppSummary = T.take 180 (epThesis endorsed)
    , ppOrientation = epOrientation endorsed
    , ppConfidenceBand = confidenceBand (epConfidence endorsed)
    , ppCautionLevel = cautionLevel endorsed
    , ppContested = epStatus endorsed `elem` [PerspectiveContested, PerspectiveSuspended]
    , ppPerspectiveVersion = epVersion endorsed
    , ppNormativeProfileId = epNormativeProfileId endorsed
    , ppNormativeProfileVersion = epNormativeProfileVersion endorsed
    , ppEvidenceCount = length (epSupportingClaims endorsed)
    , ppCounterargumentCount = length (epCounterarguments endorsed)
    , ppExplanationHandle = explanationHandle endorsed
    }

buildActivePerspectiveProjections :: PerspectiveRegistry -> [PerspectiveProjection]
buildActivePerspectiveProjections registry =
  mapMaybe (buildPerspectiveProjection registry) (activePerspectiveProjectionScopes registry)

upsertThread :: Int -> PerspectiveRegistry -> PerspectiveInputBundle -> PerspectiveCandidate -> PerspectivePromotionDecision -> PerspectiveStatus -> Maybe Int -> PerspectiveRegistry
upsertThread turn registry bundle candidate decision status endorsedTurn =
  let scope = pcScope candidate
      oldThread = M.lookup scope (prThreads registry)
      perspectiveId = maybe (PerspectiveId ("perspective-" <> T.pack (show (prNextPerspectiveOrdinal registry)))) ptPerspectiveId oldThread
      version = PerspectiveVersionId (prNextVersionOrdinal registry)
      priorActive = oldThread >>= ptActiveVersion
      oldConfidence = maybe 0.0 epConfidence (oldThread >>= activeEndorsedPerspective)
      oldNormative = maybe (npVersionId (pibNormativeProfile bundle)) epNormativeProfileVersion (oldThread >>= activeEndorsedPerspective)
      endorsed = EndorsedPerspective
        { epId = perspectiveId
        , epVersion = version
        , epScope = scope
        , epThesis = pcThesis candidate
        , epOrientation = pcOrientation candidate
        , epConfidence = pcConfidence candidate
        , epNormativeProfileId = npId (pibNormativeProfile bundle)
        , epNormativeProfileVersion = npVersionId (pibNormativeProfile bundle)
        , epStatus = status
        , epCreatedTurn = turn
        , epEndorsedTurn = endorsedTurn
        , epSupportingClaims = take 8 (pcSupportingClaims candidate)
        , epCounterarguments = take 8 (map renderCounterargumentRef (pibCounterarguments bundle))
        }
      revision = PerspectiveRevisionRecord
        { prrFromVersion = priorActive
        , prrToVersion = version
        , prrTrigger = promotionTrigger decision candidate
        , prrEvidenceDelta = fromIntegral (length (pibEvidence bundle))
        , prrCounterargumentDelta = pcCounterargumentPressure candidate
        , prrConfidenceDelta = pcConfidence candidate - oldConfidence
        , prrNormativeDelta = fromIntegral (npVersionId (pibNormativeProfile bundle) - oldNormative)
        , prrNormativeProfileVersion = npVersionId (pibNormativeProfile bundle)
        , prrDecision = decision
        , prrRollbackOf = Nothing
        }
      oldVersions = maybe [] ptVersions oldThread
      oldRevisions = maybe [] ptRevisionHistory oldThread
      activeVersion = if status == PerspectiveActive then Just version else priorActive
      thread = PerspectiveThread
        { ptPerspectiveId = perspectiveId
        , ptScope = scope
        , ptActiveVersion = activeVersion
        , ptVersions = boundVersions registry (endorsed : markPriorRevised status oldVersions)
        , ptRevisionHistory = take (prMaxRevisionsPerScope registry) (revision : oldRevisions)
        , ptStatus = status
        , ptLastUpdatedTurn = turn
        }
      threads = enforceRegistryBounds registry (M.insert scope thread (prThreads registry))
      nextPerspectiveOrdinal = case oldThread of
        Nothing -> prNextPerspectiveOrdinal registry + 1
        Just _ -> prNextPerspectiveOrdinal registry
  in registry
      { prThreads = threads
      , prNextPerspectiveOrdinal = nextPerspectiveOrdinal
      , prNextVersionOrdinal = prNextVersionOrdinal registry + 1
      , prLastUpdatedTurn = turn
      }

suspendActivePerspective :: Int -> PerspectiveRegistry -> PerspectiveCandidate -> PerspectivePromotionDecision -> PerspectiveRegistry
suspendActivePerspective turn registry candidate decision =
  case M.lookup (pcScope candidate) (prThreads registry) of
    Nothing -> registry { prLastUpdatedTurn = turn }
    Just thread ->
      let revision = PerspectiveRevisionRecord
            { prrFromVersion = ptActiveVersion thread
            , prrToVersion = fromMaybe (PerspectiveVersionId (prNextVersionOrdinal registry)) (ptActiveVersion thread)
            , prrTrigger = "counterargument_pressure_suspend"
            , prrEvidenceDelta = 0.0
            , prrCounterargumentDelta = pcCounterargumentPressure candidate
            , prrConfidenceDelta = 0.0
            , prrNormativeDelta = 0.0
            , prrNormativeProfileVersion = pcNormativeProfileVersion candidate
            , prrDecision = decision
            , prrRollbackOf = Nothing
            }
          thread' = thread
            { ptActiveVersion = Nothing
            , ptVersions = map (setStatusForActive (ptActiveVersion thread) PerspectiveSuspended) (ptVersions thread)
            , ptRevisionHistory = take (prMaxRevisionsPerScope registry) (revision : ptRevisionHistory thread)
            , ptStatus = PerspectiveSuspended
            , ptLastUpdatedTurn = turn
            }
      in registry
          { prThreads = enforceRegistryBounds registry (M.insert (pcScope candidate) thread' (prThreads registry))
          , prLastUpdatedTurn = turn
          }

rollbackPriorPerspective :: Int -> PerspectiveRegistry -> PerspectiveCandidate -> PerspectivePromotionDecision -> PerspectiveRegistry
rollbackPriorPerspective turn registry candidate decision =
  case M.lookup (pcScope candidate) (prThreads registry) of
    Nothing -> registry { prLastUpdatedTurn = turn }
    Just thread ->
      let active = ptActiveVersion thread
          remaining = filter (isViableRollbackVersion active) (ptVersions thread)
          replacement = case remaining of
            x:_ -> Just (epVersion x)
            [] -> Nothing
          revision = PerspectiveRevisionRecord
            { prrFromVersion = active
            , prrToVersion = fromMaybe (PerspectiveVersionId (prNextVersionOrdinal registry)) replacement
            , prrTrigger = "rollback_prior_promotion"
            , prrEvidenceDelta = 0.0
            , prrCounterargumentDelta = pcCounterargumentPressure candidate
            , prrConfidenceDelta = 0.0
            , prrNormativeDelta = 0.0
            , prrNormativeProfileVersion = pcNormativeProfileVersion candidate
            , prrDecision = decision
            , prrRollbackOf = active
            }
          thread' = thread
            { ptActiveVersion = replacement
            , ptVersions = map (statusAfterRollback active replacement) (ptVersions thread)
            , ptRevisionHistory = take (prMaxRevisionsPerScope registry) (revision : ptRevisionHistory thread)
            , ptStatus = maybe PerspectiveWithdrawn (const PerspectiveActive) replacement
            , ptLastUpdatedTurn = turn
            }
      in registry
          { prThreads = enforceRegistryBounds registry (M.insert (pcScope candidate) thread' (prThreads registry))
          , prLastUpdatedTurn = turn
          }

promotionTrigger :: PerspectivePromotionDecision -> PerspectiveCandidate -> Text
promotionTrigger decision candidate =
  promotionDecisionText decision <> ":confidence=" <> T.pack (show (pcConfidence candidate))

promotionDecisionText :: PerspectivePromotionDecision -> Text
promotionDecisionText decision =
  case decision of
    PpdObserveOnly -> "observe_only"
    PpdQuarantine -> "quarantine"
    PpdAcceptBounded -> "accept_bounded"
    PpdPromoteEndorsed -> "promote_endorsed"
    PpdReviseActive -> "revise_active"
    PpdSuspendActive -> "suspend_active"
    PpdRollbackPrior -> "rollback_prior"

boundVersions :: PerspectiveRegistry -> [EndorsedPerspective] -> [EndorsedPerspective]
boundVersions registry versions =
  let active = filter ((== PerspectiveActive) . epStatus) versions
      inactive = filter ((/= PerspectiveActive) . epStatus) versions
  in take (prMaxActivePerScope registry) active <> take (prMaxInactiveVersions registry) inactive

enforceRegistryBounds :: PerspectiveRegistry -> M.Map PerspectiveScope PerspectiveThread -> M.Map PerspectiveScope PerspectiveThread
enforceRegistryBounds registry threads =
  let activeThreads = filter (hasActiveThread . snd) (M.toList threads)
      allowedActiveScopes = map fst . take (prMaxActivePerspectives registry) . sortOn (Down . ptLastUpdatedTurn . snd) $ activeThreads
  in M.mapWithKey (enforceActiveScope allowedActiveScopes) threads

hasActiveThread :: PerspectiveThread -> Bool
hasActiveThread thread = activeEndorsedPerspective thread /= Nothing

enforceActiveScope :: [PerspectiveScope] -> PerspectiveScope -> PerspectiveThread -> PerspectiveThread
enforceActiveScope allowedScopes scope thread
  | scope `elem` allowedScopes = thread
  | hasActiveThread thread = suspendThreadForActiveCap thread
  | otherwise = thread

suspendThreadForActiveCap :: PerspectiveThread -> PerspectiveThread
suspendThreadForActiveCap thread = thread
  { ptActiveVersion = Nothing
  , ptVersions = map (setStatusForActive (ptActiveVersion thread) PerspectiveSuspended) (ptVersions thread)
  , ptStatus = PerspectiveSuspended
  }

markPriorRevised :: PerspectiveStatus -> [EndorsedPerspective] -> [EndorsedPerspective]
markPriorRevised status versions
  | status == PerspectiveActive = map reviseActive versions
  | otherwise = versions
  where
    reviseActive ep
      | epStatus ep == PerspectiveActive = ep { epStatus = PerspectiveRevised }
      | otherwise = ep

setStatusForActive :: Maybe PerspectiveVersionId -> PerspectiveStatus -> EndorsedPerspective -> EndorsedPerspective
setStatusForActive activeVersion status ep
  | Just (epVersion ep) == activeVersion = ep { epStatus = status }
  | otherwise = ep

setStatusForVersion :: Maybe PerspectiveVersionId -> PerspectiveStatus -> EndorsedPerspective -> EndorsedPerspective
setStatusForVersion version status ep
  | Just (epVersion ep) == version = ep { epStatus = status }
  | otherwise = ep

statusAfterRollback :: Maybe PerspectiveVersionId -> Maybe PerspectiveVersionId -> EndorsedPerspective -> EndorsedPerspective
statusAfterRollback active replacement =
  setStatusForVersion replacement PerspectiveActive . setStatusForActive active PerspectiveWithdrawn

isViableRollbackVersion :: Maybe PerspectiveVersionId -> EndorsedPerspective -> Bool
isViableRollbackVersion active ep =
  Just (epVersion ep) /= active
    && epStatus ep `elem` [PerspectiveRevised, PerspectiveContested, PerspectiveActive]

confidenceBand :: Double -> Text
confidenceBand value
  | value >= 0.80 = "high"
  | value >= 0.60 = "medium"
  | value >= 0.40 = "low"
  | otherwise = "minimal"

cautionLevel :: EndorsedPerspective -> Text
cautionLevel ep
  | epStatus ep `elem` [PerspectiveContested, PerspectiveSuspended] = "high"
  | epConfidence ep < 0.60 = "medium"
  | null (epCounterarguments ep) = "low"
  | otherwise = "medium"

explanationHandle :: EndorsedPerspective -> Text
explanationHandle ep =
  renderPerspectiveId (epId ep)
    <> ":v"
    <> T.pack (show (unPerspectiveVersionId (epVersion ep)))
    <> ":np"
    <> T.pack (show (epNormativeProfileVersion ep))

renderCounterargumentRef :: CounterargumentRef -> Text
renderCounterargumentRef (CounterargumentRef value) = value
