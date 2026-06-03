{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

module QxFx0.Governance.Replay
  ( rebuildGovernedPerspectiveState
  , verifyPerspectiveRegistryRebuild
  , rebuildGovernanceProjection
  , governanceReplayProof
  , rebuildGovernedViews
  , rebuildGovernedSystemState
  ) where

import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Core.TruthContract (truthContractIsAuthoritative)
import QxFx0.Self.Perspective.Reduce
  ( applyPerspectiveDecision
  , buildActivePerspectiveProjections
  )
import QxFx0.Types.State.Governance
  ( GovernanceDecision(..)
  , GovernanceEvent(..)
  , GovernanceEventEnvelope(..)
  , GovernanceProvenanceLink
  , GovernedProjectionRef(..)
  , GovernedSubject(..)
  , GovernancePayload(..)
  , GovernanceProjection(..)
  , PerspectivePayload(..)
  , ProjectionMeta(..)
  , canonicalizeGovernanceHistory
  , currentProjectionVersion
  , currentReducerVersion
  , governanceDecisionFromPerspectivePromotion
  , governanceProjectionChecksum
  , governanceProvenanceTrail
  )
import QxFx0.Types.State.Perspective
  ( IdentitySlice(..)
  , PerspectiveInputBundle(..)
  , PerspectivePromotionDecision(..)
  , PerspectiveRegistry(..)
  , emptyPerspectiveRegistry
  )
import QxFx0.Types.State.System
  ( SystemState(..)
  )

rebuildGovernedPerspectiveState :: [GovernanceEvent] -> Either Text PerspectiveRegistry
rebuildGovernedPerspectiveState events = do
  ordered <- canonicalizeGovernanceHistory events
  foldGovernanceEvent emptyPerspectiveRegistry ordered

verifyPerspectiveRegistryRebuild :: [GovernanceEvent] -> PerspectiveRegistry -> Either Text PerspectiveRegistry
verifyPerspectiveRegistryRebuild events expectedRegistry = do
  rebuilt <- rebuildGovernedPerspectiveState events
  if rebuilt == expectedRegistry
    then Right rebuilt
    else Left "governance perspective registry rebuild mismatch"

rebuildGovernanceProjection :: [GovernanceEvent] -> Either Text GovernanceProjection
rebuildGovernanceProjection events = do
  ordered <- canonicalizeGovernanceHistory events
  registry <- foldGovernanceEvent emptyPerspectiveRegistry ordered
  let projections = buildActivePerspectiveProjections registry
      governedRefs = map governanceProjectionRef ordered
      meta = ProjectionMeta
        { pmProjectionVersion = currentProjectionVersion
        , pmReducerVersion = currentReducerVersion
        , pmSnapshotTurn = Just (prLastUpdatedTurn registry)
        }
      checksum = governanceProjectionChecksum meta registry projections governedRefs
  pure GovernanceProjection
    { gpMeta = meta
    , gpPerspectiveRegistry = registry
    , gpActivePerspectiveProjections = projections
    , gpGovernedRefs = governedRefs
    , gpProjectionChecksum = checksum
    }

rebuildGovernedViews :: SystemState -> Either Text (PerspectiveRegistry, GovernanceProjection)
rebuildGovernedViews ss = do
  if not (truthContractIsAuthoritative (ssTruthContractStatus ss))
    then Left "governance_replay_non_authoritative_truth_contract"
    else pure ()
  projection <- rebuildGovernanceProjection (ssGovernanceHistory ss)
  pure (gpPerspectiveRegistry projection, projection)

rebuildGovernedSystemState :: SystemState -> Either Text SystemState
rebuildGovernedSystemState ss = do
  (registry, projection) <- rebuildGovernedViews ss
  pure ss
    { ssPerspectiveRegistry = registry
    , ssGovernanceProjection = projection
    }

governanceReplayProof :: [GovernanceEvent] -> PerspectiveRegistry -> Either Text [GovernanceProvenanceLink]
governanceReplayProof events expectedRegistry = do
  _ <- verifyPerspectiveRegistryRebuild events expectedRegistry
  governanceProvenanceTrail events

foldGovernanceEvent :: PerspectiveRegistry -> [GovernanceEvent] -> Either Text PerspectiveRegistry
foldGovernanceEvent registry [] = Right registry
foldGovernanceEvent registry (event:rest) = do
  next <- applyGovernanceEvent registry event
  foldGovernanceEvent next rest

applyGovernanceEvent :: PerspectiveRegistry -> GovernanceEvent -> Either Text PerspectiveRegistry
applyGovernanceEvent registry event =
  case gePayload event of
    GpPerspective payload -> applyPerspectiveGovernancePayload registry (geEnvelope event) payload
    _ ->
      Right registry { prLastUpdatedTurn = fromMaybe (prLastUpdatedTurn registry) (geeTurnId (geEnvelope event)) }

applyPerspectiveGovernancePayload :: PerspectiveRegistry -> GovernanceEventEnvelope -> PerspectivePayload -> Either Text PerspectiveRegistry
applyPerspectiveGovernancePayload registry envelope payload = do
  ensurePerspectiveReplayConsistency envelope payload
  case geeDecision envelope of
    GovObserveOnly -> Right registry { prLastUpdatedTurn = eventTurn }
    GovDeny -> Right registry { prLastUpdatedTurn = eventTurn }
    GovQuarantine -> applyResolved PpdQuarantine
    GovAcceptBounded -> applyResolved PpdAcceptBounded
    GovPromote -> applyResolvedPerspectivePromote
    GovSuspend -> applyResolved PpdSuspendActive
    GovRollback -> applyResolved PpdRollbackPrior
    GovFreeze -> Left "governance replay cannot apply GovFreeze to perspective payload"
  where
    eventTurn = fromMaybe (isTurnCount (pibIdentitySlice (ppPerspectiveInput payload))) (geeTurnId envelope)

    applyResolved :: PerspectivePromotionDecision -> Either Text PerspectiveRegistry
    applyResolved expectedDecision
      | ppResolvedDecision payload == expectedDecision =
          Right (applyPerspectiveDecision eventTurn registry (ppPerspectiveInput payload) (ppPerspectiveCandidate payload) expectedDecision)
      | otherwise =
          Left
            ( "governance replay payload decision mismatch: expected "
                <> payloadDecisionTag expectedDecision
                <> ", got "
                <> payloadDecisionTag (ppResolvedDecision payload)
            )

    applyResolvedPerspectivePromote :: Either Text PerspectiveRegistry
    applyResolvedPerspectivePromote =
      case ppResolvedDecision payload of
        PpdPromoteEndorsed -> Right (applyPerspectiveDecision eventTurn registry (ppPerspectiveInput payload) (ppPerspectiveCandidate payload) PpdPromoteEndorsed)
        PpdReviseActive -> Right (applyPerspectiveDecision eventTurn registry (ppPerspectiveInput payload) (ppPerspectiveCandidate payload) PpdReviseActive)
        other ->
          Left
            ( "governance replay payload decision mismatch: GovPromote requires promote/revise payload, got "
                <> payloadDecisionTag other
            )

ensurePerspectiveReplayConsistency :: GovernanceEventEnvelope -> PerspectivePayload -> Either Text ()
ensurePerspectiveReplayConsistency envelope payload = do
  let canonicalDecision = geeDecision envelope
      resolvedDecision = ppResolvedDecision payload
      sameSubject = geeSubject envelope == SubjectPerspective (ppPerspectiveId payload)
  if not sameSubject
    then Left "governance replay subject mismatch for perspective payload"
    else pure ()
  case geeResolvedDecision envelope of
    Just resolvedGov
      | resolvedGov /= canonicalDecision ->
          Left "governance replay envelope resolved decision mismatch"
    _ -> pure ()
  case canonicalDecision of
    GovDeny
      | resolvedDecision == PpdObserveOnly -> pure ()
      | governanceDecisionFromPerspectivePromotion resolvedDecision == GovDeny -> pure ()
      | otherwise ->
          Left
            ( "governance replay envelope/payload decision mismatch: envelope="
                <> T.pack (show canonicalDecision)
                <> ", payload="
                <> payloadDecisionTag resolvedDecision
            )
    _
      | governanceDecisionFromPerspectivePromotion resolvedDecision == canonicalDecision -> pure ()
      | otherwise ->
          Left
            ( "governance replay envelope/payload decision mismatch: envelope="
                <> T.pack (show canonicalDecision)
                <> ", payload="
                <> payloadDecisionTag resolvedDecision
            )

payloadTag :: GovernancePayload -> Text
payloadTag payload =
  case payload of
    GpPerspective _ -> "GpPerspective"
    GpClaimStance _ -> "GpClaimStance"
    GpCapability _ -> "GpCapability"
    GpFreeze _ -> "GpFreeze"
    GpCarry _ -> "GpCarry"
    GpNormativeRevision _ -> "GpNormativeRevision"

payloadDecisionTag :: PerspectivePromotionDecision -> Text
payloadDecisionTag = T.pack . show

governanceProjectionRef :: GovernanceEvent -> GovernedProjectionRef
governanceProjectionRef event =
  let envelope = geEnvelope event
  in GovernedProjectionRef
      { gprEventId = geeId envelope
      , gprSubject = geeSubject envelope
      , gprDecision = geeDecision envelope
      , gprLifecycleStatus = geeLifecycleStatus envelope
      , gprEffectRef = geeEffectRef envelope
      }
