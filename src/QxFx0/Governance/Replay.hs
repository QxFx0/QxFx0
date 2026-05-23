{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

module QxFx0.Governance.Replay
  ( rebuildGovernedPerspectiveState
  , verifyPerspectiveRegistryRebuild
  , rebuildGovernanceProjection
  , governanceReplayProof
  , rebuildGovernedSystemState
  ) where

import Data.Maybe (fromMaybe)
import Data.Text (Text)

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
  , GovernancePayload(..)
  , GovernanceProjection(..)
  , PerspectivePayload(..)
  , ProjectionMeta(..)
  , canonicalizeGovernanceHistory
  , currentProjectionVersion
  , currentReducerVersion
  , governanceProjectionChecksum
  , governanceProvenanceTrail
  )
import QxFx0.Types.State.Perspective
  ( IdentitySlice(..)
  , PerspectiveInputBundle(..)
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

rebuildGovernedSystemState :: SystemState -> Either Text SystemState
rebuildGovernedSystemState ss = do
  registry <- rebuildGovernedPerspectiveState (ssGovernanceHistory ss)
  pure ss { ssPerspectiveRegistry = registry }

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
    _ -> Left "governance replay does not support this governed payload family yet"

applyPerspectiveGovernancePayload :: PerspectiveRegistry -> GovernanceEventEnvelope -> PerspectivePayload -> Either Text PerspectiveRegistry
applyPerspectiveGovernancePayload registry envelope payload =
  case geeDecision envelope of
    GovObserveOnly -> Right registry { prLastUpdatedTurn = eventTurn }
    GovDeny -> Right registry { prLastUpdatedTurn = eventTurn }
    _ -> Right (applyPerspectiveDecision eventTurn registry (ppPerspectiveInput payload) (ppPerspectiveCandidate payload) (ppResolvedDecision payload))
  where
    eventTurn = fromMaybe (isTurnCount (pibIdentitySlice (ppPerspectiveInput payload))) (geeTurnId envelope)

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
