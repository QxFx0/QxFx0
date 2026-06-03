{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-| P5 governance event spine: append-only typed canonical history atoms. -}
module QxFx0.Types.State.Governance
  ( GovernanceEventId(..)
  , GovernanceActor(..)
  , GovernedSubject(..)
  , GovernanceDecision(..)
  , GovernanceLifecycleStatus(..)
  , GovernanceReason(..)
  , ProjectionVersion(..)
  , ReducerVersion(..)
  , EvaluatorVersion(..)
  , FreezeScope(..)
  , GovernanceRef(..)
  , ConfidenceBand(..)
  , ConfidenceSnapshot(..)
  , CapabilityEvidence(..)
  , CapabilityEntry(..)
  , CapabilityModel(..)
  , DriftSignal(..)
  , MetaEvaluationSignal(..)
  , BudgetWindow(..)
  , StaleStatus(..)
  , ProjectionMeta(..)
  , RollbackPlan(..)
  , GovernancePermission(..)
  , GovernanceDataClass(..)
  , EpistemicStatus(..)
  , epistemicStatusClass
  , renderEpistemicStatus
  , GovernedProjectionRef(..)
  , GovernanceProvenanceLink(..)
  , GovernanceProjection(..)
  , GovernanceRuntimeFault(..)
  , GovernanceSchemaEvolutionContract(..)
  , GovernanceReplayOrderingContract(..)
  , GovernanceArchiveContract(..)
  , PerspectivePayload(..)
  , ClaimStancePayload(..)
  , CapabilityPayload(..)
  , FreezePayload(..)
  , CarryPayload(..)
  , NormativeRevisionPayload(..)
  , GovernancePayload(..)
  , GovernanceEventEnvelope(..)
  , GovernanceEvent(..)
  , currentGovernanceSchemaVersion
  , currentGovernancePayloadVersion
  , currentProjectionVersion
  , currentReducerVersion
  , currentEvaluatorVersion
  , buildPerspectiveGovernanceEvent
  , appendGovernanceEventToHistory
  , canonicalizeGovernanceHistory
  , normalizeGovernanceEventChecked
  , validateGovernanceEventContract
  , governancePermission
  , governancePermissionAllowed
  , supportedGovernedSubject
  , governanceProjectionChecksum
  , governanceProvenanceTrail
  , defaultGovernanceSchemaEvolutionContract
  , defaultGovernanceReplayOrderingContract
  , defaultGovernanceArchiveContract
  , governanceDeterminismBoundary
  , governanceDecisionFromPerspectivePromotion
  , governanceEventIdText
  , governanceEventHashText
  , governanceEventPayloadHashText
  , governanceHistoryFingerprint
  ) where

import Control.DeepSeq (NFData)
import qualified Crypto.Hash.SHA256 as SHA256
import Data.Bits (xor)
import Data.Aeson (FromJSON, ToJSON, encode)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy.Char8 as BL8
import Data.Function (on)
import Data.List (groupBy, sortOn)
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Word (Word64)
import GHC.Generics (Generic)
import Numeric (showHex)

import QxFx0.Types.State.Perspective
  ( EndorsedPerspective(..)
  , PerspectiveAdmissibility(..)
  , PerspectiveCandidate(..)
  , IdentitySlice(..)
  , PerspectiveId(..)
  , PerspectiveInputBundle(..)
  , PerspectiveProjection
  , PerspectivePromotionDecision(..)
  , PerspectiveRegistry(..)
  , PerspectiveScope
  , PerspectiveStatus(..)
  , PerspectiveThread(..)
  , PerspectiveVersionId(..)
  , latestEndorsedPerspective
  , renderPerspectiveScope
  )

newtype GovernanceEventId = GovernanceEventId { unGovernanceEventId :: Text }
  deriving stock (Eq, Ord, Show, Read, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data GovernanceHashScheme
  = GovernanceHashLegacyFNV
  | GovernanceHashSha256
  deriving stock (Eq, Show)

data GovernanceActor
  = ActorRuntime
  | ActorOperator
  | ActorOfflineGovernance
  | ActorReplayRebuild
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData, FromJSON, ToJSON)

data FreezeScope
  = FreezeGlobal
  | FreezePerspectiveScope Text
  | FreezeContour Text
  deriving stock (Eq, Ord, Show, Read, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data GovernedSubject
  = SubjectPerspective PerspectiveId
  | SubjectClaimStance Text
  | SubjectCapability Text
  | SubjectCrossSessionCarry Text
  | SubjectFreeze FreezeScope
  | SubjectNormativeProfile Text
  deriving stock (Eq, Ord, Show, Read, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data GovernanceDecision
  = GovObserveOnly
  | GovQuarantine
  | GovAcceptBounded
  | GovPromote
  | GovFreeze
  | GovSuspend
  | GovRollback
  | GovDeny
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData, FromJSON, ToJSON)

data GovernanceLifecycleStatus
  = GlsIntent
  | GlsEvaluated
  | GlsCommitted
  | GlsDenied
  | GlsRolledBack
  | GlsArchived
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData, FromJSON, ToJSON)

data GovernanceReason = GovernanceReason
  { grTag :: !Text
  , grDetails :: ![Text]
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

newtype ProjectionVersion = ProjectionVersion { unProjectionVersion :: Int }
  deriving stock (Eq, Ord, Show, Read, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

newtype ReducerVersion = ReducerVersion { unReducerVersion :: Int }
  deriving stock (Eq, Ord, Show, Read, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

newtype EvaluatorVersion = EvaluatorVersion { unEvaluatorVersion :: Int }
  deriving stock (Eq, Ord, Show, Read, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data GovernanceRef
  = GovRefEvent GovernanceEventId
  | GovRefPerspective PerspectiveId
  | GovRefClaim Text
  | GovRefCapability Text
  | GovRefSnapshot Text
  deriving stock (Eq, Ord, Show, Read, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data ConfidenceBand
  = CbVeryLow
  | CbLow
  | CbMedium
  | CbHigh
  | CbVeryHigh
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData, FromJSON, ToJSON)

data ConfidenceSnapshot = ConfidenceSnapshot
  { csEvidence :: !Double
  , csStance :: !Double
  , csPerspective :: !Double
  , csCapability :: !Double
  , csAction :: !Double
  , csGovernance :: !Double
  , csBand :: !ConfidenceBand
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data CapabilityEntry = CapabilityEntry
  { cmeScope :: !Text
  , cmeOperation :: !Text
  , cmeMode :: !Text
  , cmeConfidence :: !Double
  , cmeEvidence :: !CapabilityEvidence
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data CapabilityModel = CapabilityModel
  { cmVersion :: !Int
  , cmEntries :: ![CapabilityEntry]
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data DriftSignal = DriftSignal
  { dsTag :: !Text
  , dsSeverity :: !Double
  , dsEvidence :: ![Text]
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data MetaEvaluationSignal = MetaEvaluationSignal
  { mesSignals :: ![DriftSignal]
  , mesMismatches :: ![Text]
  , mesInstabilityScore :: !Double
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data BudgetWindow = BudgetWindow
  { bwSize :: !Int
  , bwMaxPromotions :: !Int
  , bwMaxRevisions :: !Int
  , bwMaxRollbacks :: !Int
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data StaleStatus
  = StaleFresh
  | StaleCooling
  | StaleSuspended
  | StaleExpired
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData, FromJSON, ToJSON)

data ProjectionMeta = ProjectionMeta
  { pmProjectionVersion :: !ProjectionVersion
  , pmReducerVersion :: !ReducerVersion
  , pmSnapshotTurn :: !(Maybe Int)
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data RollbackPlan = RollbackPlan
  { rpTargetEvent :: !GovernanceEventId
  , rpReason :: !GovernanceReason
  , rpScope :: !FreezeScope
  , rpAllowedByPolicy :: !Bool
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data GovernancePermission
  = GovernanceAllowed
  | GovernanceDenied Text
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data GovernanceDataClass
  = GdcCanonical
  | GdcDerived
  | GdcObservational
  | GdcDiagnostic
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData, FromJSON, ToJSON)

data EpistemicStatus
  = EpstAuthoritative
  | EpstAdvisory
  | EpstDegraded
  | EpstFallback
  | EpstObservationalOnly
  | EpstNonAuthoritative
  | EpstNonDriving
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData, FromJSON, ToJSON)

epistemicStatusClass :: EpistemicStatus -> GovernanceDataClass
epistemicStatusClass EpstAuthoritative = GdcCanonical
epistemicStatusClass EpstAdvisory = GdcDerived
epistemicStatusClass EpstDegraded = GdcDerived
epistemicStatusClass EpstFallback = GdcObservational
epistemicStatusClass EpstObservationalOnly = GdcObservational
epistemicStatusClass EpstNonAuthoritative = GdcDiagnostic
epistemicStatusClass EpstNonDriving = GdcDiagnostic

renderEpistemicStatus :: EpistemicStatus -> Text
renderEpistemicStatus EpstAuthoritative = "authoritative"
renderEpistemicStatus EpstAdvisory = "advisory"
renderEpistemicStatus EpstDegraded = "degraded"
renderEpistemicStatus EpstFallback = "fallback"
renderEpistemicStatus EpstObservationalOnly = "observational_only"
renderEpistemicStatus EpstNonAuthoritative = "non_authoritative"
renderEpistemicStatus EpstNonDriving = "non_driving"

data GovernanceProjection = GovernanceProjection
  { gpMeta :: !ProjectionMeta
  , gpPerspectiveRegistry :: !PerspectiveRegistry
  , gpActivePerspectiveProjections :: ![PerspectiveProjection]
  , gpGovernedRefs :: ![GovernedProjectionRef]
  , gpProjectionChecksum :: !Text
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data GovernanceRuntimeFault
  = GrfAppendRejected !Text
  | GrfRebuildUnavailable !Text
  | GrfRebuildMismatch
  | GrfRecoveredCorruptBootstrap !Text
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data GovernedProjectionRef = GovernedProjectionRef
  { gprEventId :: !GovernanceEventId
  , gprSubject :: !GovernedSubject
  , gprDecision :: !GovernanceDecision
  , gprLifecycleStatus :: !GovernanceLifecycleStatus
  , gprEffectRef :: !(Maybe GovernanceRef)
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data GovernanceProvenanceLink = GovernanceProvenanceLink
  { gplEventId :: !GovernanceEventId
  , gplSubject :: !GovernedSubject
  , gplParentRefs :: ![GovernanceEventId]
  , gplReasonTag :: !Text
  , gplEffectRef :: !(Maybe GovernanceRef)
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data GovernanceSchemaEvolutionContract = GovernanceSchemaEvolutionContract
  { gsecSchemaVersionPolicy :: !Text
  , gsecPayloadVersionPolicy :: !Text
  , gsecBackwardCompatibilityRules :: ![Text]
  , gsecMigrationRules :: ![Text]
  , gsecOldVersionReplaySemantics :: !Text
  , gsecUnsupportedVersionHandling :: !Text
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data GovernanceReplayOrderingContract = GovernanceReplayOrderingContract
  { grocCausalOrdering :: !Text
  , grocPartitionSemantics :: !Text
  , grocTotalOrderTieBreakRule :: !Text
  , grocReducerIdempotence :: !Text
  , grocMergeSemantics :: !Text
  , grocConflictHandling :: !Text
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data GovernanceArchiveContract = GovernanceArchiveContract
  { gacCanonicalHistoryCompactionAllowed :: !Bool
  , gacCompactionTargets :: ![Text]
  , gacArchiveRule :: !Text
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data PerspectivePayload = PerspectivePayload
  { ppPerspectiveId :: !PerspectiveId
  , ppPerspectiveScope :: !PerspectiveScope
  , ppPerspectiveVersion :: !(Maybe PerspectiveVersionId)
  , ppPerspectiveStatus :: !PerspectiveStatus
  , ppPerspectiveInput :: !PerspectiveInputBundle
  , ppPerspectiveCandidate :: !PerspectiveCandidate
  , ppPerspectiveAdmissibility :: !PerspectiveAdmissibility
  , ppRequestedDecision :: !(Maybe PerspectivePromotionDecision)
  , ppResolvedDecision :: !PerspectivePromotionDecision
  , ppPerspectiveProjection :: !(Maybe PerspectiveProjection)
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data ClaimStancePayload = ClaimStancePayload
  { cspClaimRef :: !Text
  , cspBefore :: !(Maybe Text)
  , cspAfter :: !(Maybe Text)
  , cspReason :: !GovernanceReason
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data CapabilityEvidence = CapabilityEvidence
  { ceObservedFailures :: !Int
  , ceSandboxFailures :: !Int
  , ceFreezeCount :: !Int
  , ceRollbackCount :: !Int
  , ceDegradedCount :: !Int
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data CapabilityPayload = CapabilityPayload
  { cpCapabilityRef :: !Text
  , cpScope :: !Text
  , cpOperation :: !Text
  , cpMode :: !Text
  , cpBeforeConfidence :: !(Maybe Double)
  , cpAfterConfidence :: !Double
  , cpEvidence :: !CapabilityEvidence
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data FreezePayload = FreezePayload
  { fpScope :: !FreezeScope
  , fpEntryReason :: !GovernanceReason
  , fpReleaseConditions :: ![Text]
  , fpCooldownTurns :: !Int
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data CarryPayload = CarryPayload
  { cpCarryKey :: !Text
  , cpSourceSession :: !(Maybe Text)
  , cpTargetSession :: !(Maybe Text)
  , cpEligibilityReason :: !GovernanceReason
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data NormativeRevisionPayload = NormativeRevisionPayload
  { nrpProfileId :: !Text
  , nrpVersionId :: !Int
  , nrpRevisionPolicy :: !Text
  , nrpAuditReason :: !GovernanceReason
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data GovernancePayload
  = GpPerspective PerspectivePayload
  | GpClaimStance ClaimStancePayload
  | GpCapability CapabilityPayload
  | GpFreeze FreezePayload
  | GpCarry CarryPayload
  | GpNormativeRevision NormativeRevisionPayload
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data GovernanceEventEnvelope = GovernanceEventEnvelope
  { geeId :: !GovernanceEventId
  , geeSchemaVersion :: !Int
  , geePayloadVersion :: !Int
  , geeLifecycleStatus :: !GovernanceLifecycleStatus
  , geeSubject :: !GovernedSubject
  , geeActor :: !GovernanceActor
  , geeTurnId :: !(Maybe Int)
  , geeSessionId :: !(Maybe Text)
  , geeStreamId :: !Text
  , geePartitionId :: !Text
  , geeSequenceNo :: !Int
  , geeParentRefs :: ![GovernanceEventId]
  , geeDecision :: !GovernanceDecision
  , geeRequestedDecision :: !(Maybe GovernanceDecision)
  , geeResolvedDecision :: !(Maybe GovernanceDecision)
  , geeReason :: !GovernanceReason
  , geeNormativeProfileVersion :: !(Maybe Int)
  , geeProjectionVersion :: !ProjectionVersion
  , geeReducerVersion :: !ReducerVersion
  , geeNormativeEvaluatorVersion :: !EvaluatorVersion
  , geeConfidenceAlgebraVersion :: !EvaluatorVersion
  , geeCapabilityEvaluatorVersion :: !EvaluatorVersion
  , geeSandboxVersion :: !EvaluatorVersion
  , geeRollbackLink :: !(Maybe GovernanceEventId)
  , geeBeforeRef :: !(Maybe GovernanceRef)
  , geeAfterRef :: !(Maybe GovernanceRef)
  , geeEffectRef :: !(Maybe GovernanceRef)
  , geeEventHash :: !(Maybe Text)
  , geePrevHash :: !(Maybe Text)
  , geePayloadHash :: !(Maybe Text)
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data GovernanceEvent = GovernanceEvent
  { geEnvelope :: !GovernanceEventEnvelope
  , gePayload :: !GovernancePayload
  }
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

currentGovernanceSchemaVersion :: Int
currentGovernanceSchemaVersion = 1

currentGovernancePayloadVersion :: Int
currentGovernancePayloadVersion = 1

currentProjectionVersion :: ProjectionVersion
currentProjectionVersion = ProjectionVersion 1

currentReducerVersion :: ReducerVersion
currentReducerVersion = ReducerVersion 1

currentEvaluatorVersion :: EvaluatorVersion
currentEvaluatorVersion = EvaluatorVersion 1

defaultGovernanceSchemaEvolutionContract :: GovernanceSchemaEvolutionContract
defaultGovernanceSchemaEvolutionContract = GovernanceSchemaEvolutionContract
  { gsecSchemaVersionPolicy = "major-only"
  , gsecPayloadVersionPolicy = "major-only"
  , gsecBackwardCompatibilityRules = ["older payloads must normalize or fail closed"]
  , gsecMigrationRules = ["new schema versions require explicit migration logic"]
  , gsecOldVersionReplaySemantics = "replay via canonical normalization before reduction"
  , gsecUnsupportedVersionHandling = "reject with explicit error"
  }

defaultGovernanceReplayOrderingContract :: GovernanceReplayOrderingContract
defaultGovernanceReplayOrderingContract = GovernanceReplayOrderingContract
  { grocCausalOrdering = "event parent hash chain followed by sequence order"
  , grocPartitionSemantics = "per-partition stream events preserve stream identity"
  , grocTotalOrderTieBreakRule = "sequence_no, partition_id, event_id"
  , grocReducerIdempotence = "duplicate ids must be semantically identical"
  , grocMergeSemantics = "canonical sort then deterministic fold"
  , grocConflictHandling = "conflicting duplicates are rejected"
  }

defaultGovernanceArchiveContract :: GovernanceArchiveContract
defaultGovernanceArchiveContract = GovernanceArchiveContract
  { gacCanonicalHistoryCompactionAllowed = False
  , gacCompactionTargets = ["snapshots", "projections", "caches", "derived_views"]
  , gacArchiveRule = "canonical history is append-only and must remain semantically intact"
  }

governanceDeterminismBoundary :: [(Text, GovernanceDataClass)]
governanceDeterminismBoundary =
  [ ("canonical_history", GdcCanonical)
  , ("derived_views", GdcDerived)
  , ("observational_trace", GdcObservational)
  , ("diagnostic_trace", GdcDiagnostic)
  ]

buildPerspectiveGovernanceEvent
  :: GovernanceActor
  -> Int
  -> Text
  -> Maybe GovernanceEvent
  -> PerspectiveRegistry
  -> PerspectiveRegistry
  -> PerspectiveInputBundle
  -> PerspectiveCandidate
  -> PerspectiveAdmissibility
  -> Maybe PerspectivePromotionDecision
  -> PerspectivePromotionDecision
  -> Maybe PerspectiveProjection
  -> GovernanceEvent
buildPerspectiveGovernanceEvent actor sequenceNo sessionId previousEvent beforeRegistry afterRegistry bundle candidate admissibility requestedDecision resolvedDecision projection =
  normalizeGovernanceEvent rawEvent
  where
    turnId = isTurnCount (pibIdentitySlice bundle)
    scope = pcScope candidate
    (perspectiveId, perspectiveVersion, perspectiveStatus) = perspectiveIdentityForScope sequenceNo sessionId scope afterRegistry
    requestedGov = governanceDecisionFromPerspectivePromotion <$> requestedDecision
    resolvedGov = governanceDecisionFromPerspectiveOutcome admissibility resolvedDecision
    previousHash = previousEvent >>= geeEventHash . geEnvelope
    previousId = geeId . geEnvelope <$> previousEvent
    payload = GpPerspective PerspectivePayload
      { ppPerspectiveId = perspectiveId
      , ppPerspectiveScope = scope
      , ppPerspectiveVersion = perspectiveVersion
      , ppPerspectiveStatus = perspectiveStatus
      , ppPerspectiveInput = bundle
      , ppPerspectiveCandidate = candidate
      , ppPerspectiveAdmissibility = admissibility
      , ppRequestedDecision = requestedDecision
      , ppResolvedDecision = resolvedDecision
      , ppPerspectiveProjection = projection
      }
    eventId = GovernanceEventId
      ( T.intercalate ":"
          [ "gov"
          , safeEventText sessionId
          , "turn" <> T.pack (show turnId)
          , "seq" <> T.pack (show sequenceNo)
          , safeEventText (renderPerspectiveScope scope)
          , safeEventText (T.pack (show resolvedGov))
          ]
      )
    envelope = GovernanceEventEnvelope
      { geeId = eventId
      , geeSchemaVersion = currentGovernanceSchemaVersion
      , geePayloadVersion = currentGovernancePayloadVersion
      , geeLifecycleStatus = lifecycleForPerspective admissibility resolvedDecision
      , geeSubject = SubjectPerspective perspectiveId
      , geeActor = actor
      , geeTurnId = Just turnId
      , geeSessionId = if T.null sessionId then Nothing else Just sessionId
      , geeStreamId = "governance:" <> if T.null sessionId then "anonymous" else sessionId
      , geePartitionId = "perspective"
      , geeSequenceNo = sequenceNo
      , geeParentRefs = maybe [] pure previousId
      , geeDecision = resolvedGov
      , geeRequestedDecision = requestedGov
      , geeResolvedDecision = Just resolvedGov
      , geeReason = perspectiveGovernanceReason scope admissibility candidate resolvedGov
      , geeNormativeProfileVersion = Just (pcNormativeProfileVersion candidate)
      , geeProjectionVersion = currentProjectionVersion
      , geeReducerVersion = currentReducerVersion
      , geeNormativeEvaluatorVersion = currentEvaluatorVersion
      , geeConfidenceAlgebraVersion = currentEvaluatorVersion
      , geeCapabilityEvaluatorVersion = currentEvaluatorVersion
      , geeSandboxVersion = currentEvaluatorVersion
      , geeRollbackLink = if resolvedDecision == PpdRollbackPrior then previousId else Nothing
      , geeBeforeRef = Just (GovRefSnapshot ("perspective-registry:" <> perspectiveRegistryHash beforeRegistry))
      , geeAfterRef = Just (GovRefSnapshot ("perspective-registry:" <> perspectiveRegistryHash afterRegistry))
      , geeEffectRef = Just (GovRefPerspective perspectiveId)
      , geeEventHash = Nothing
      , geePrevHash = previousHash
      , geePayloadHash = Nothing
      }
    rawEvent = GovernanceEvent envelope payload

appendGovernanceEventToHistory :: GovernanceEvent -> [GovernanceEvent] -> Either Text [GovernanceEvent]
appendGovernanceEventToHistory event history = do
  normalized <- normalizeGovernanceEventChecked event
  let eventId = geeId (geEnvelope normalized)
      sameId existing = geeId (geEnvelope existing) == eventId
  normalizedHistory <- traverse normalizeGovernanceEventChecked history
  validateGovernanceHashChain normalizedHistory
  case filter sameId normalizedHistory of
    [] -> do
      validateGovernanceAppend normalized normalizedHistory
      pure (history <> [normalized])
    existing:_
      | existing == normalized -> pure history
      | otherwise -> Left ("duplicate governance event id with conflicting semantics: " <> governanceEventIdText eventId)

canonicalizeGovernanceHistory :: [GovernanceEvent] -> Either Text [GovernanceEvent]
canonicalizeGovernanceHistory events = do
  normalized <- traverse normalizeGovernanceEventChecked events
  let groups = groupBy ((==) `on` (geeId . geEnvelope)) (sortOn (geeId . geEnvelope) normalized)
  deduped <- traverse dedupeGovernanceGroup groups
  let ordered = sortOn governanceOrderKey deduped
  validateGovernanceHashChain ordered
  pure ordered

normalizeGovernanceEventChecked :: GovernanceEvent -> Either Text GovernanceEvent
normalizeGovernanceEventChecked event = do
  let envelope = geEnvelope event
  if geeSchemaVersion envelope /= currentGovernanceSchemaVersion
    then Left ("unsupported governance schema version: " <> T.pack (show (geeSchemaVersion envelope)))
    else pure ()
  if geePayloadVersion envelope /= currentGovernancePayloadVersion
    then Left ("unsupported governance payload version: " <> T.pack (show (geePayloadVersion envelope)))
    else pure ()
  if geeSequenceNo envelope <= 0
    then Left ("invalid governance sequence number: " <> T.pack (show (geeSequenceNo envelope)))
    else pure ()
  let scheme = detectGovernanceHashScheme envelope
      normalized = normalizeGovernanceEventWith scheme event
      normalizedEnvelope = geEnvelope normalized
  case geePayloadHash envelope of
    Just payloadHash | payloadHash /= fromMaybe "" (geePayloadHash normalizedEnvelope) ->
      Left ("governance payload hash mismatch: " <> governanceEventIdText (geeId envelope))
    _ -> pure ()
  case geeEventHash envelope of
    Just eventHash | eventHash /= fromMaybe "" (geeEventHash normalizedEnvelope) ->
      Left ("governance event hash mismatch: " <> governanceEventIdText (geeId envelope))
    _ -> pure ()
  validateGovernanceEventContract normalized
  pure normalized

validateGovernanceEventContract :: GovernanceEvent -> Either Text ()
validateGovernanceEventContract event = do
  let envelope = geEnvelope event
      eventId = geeId envelope
      failWith reason = Left (reason <> ": " <> governanceEventIdText eventId)
  validateGovernanceRefs event
  case geeResolvedDecision envelope of
    Just resolved | resolved /= geeDecision envelope ->
      failWith "resolved decision must equal canonical decision"
    _ -> pure ()
  if payloadSubject event /= geeSubject envelope
    then failWith "governance subject does not match typed payload"
    else pure ()
  if supportedGovernedSubject (geeSubject envelope)
    then pure ()
    else failWith "governed subject family is declared but not yet canonically replay-supported"
  case governancePermission (geeActor envelope) (geeSubject envelope) (geeDecision envelope) of
    GovernanceAllowed -> pure ()
    GovernanceDenied reason -> failWith ("governance permission denied: " <> reason)

data GovernanceRefRequirement
  = RefRequired
  | RefOptional
  | RefForbidden

data GovernanceRefsContract = GovernanceRefsContract
  { grcBeforeRef :: !GovernanceRefRequirement
  , grcAfterRef :: !GovernanceRefRequirement
  , grcEffectRef :: !GovernanceRefRequirement
  , grcRollbackLink :: !GovernanceRefRequirement
  , grcResolvedDecision :: !GovernanceRefRequirement
  }

validateGovernanceRefs :: GovernanceEvent -> Either Text ()
validateGovernanceRefs event = do
  let envelope = geEnvelope event
      eventId = governanceEventIdText (geeId envelope)
      contract = requiredRefsForEvent event
      failWith reason = Left (reason <> ": " <> eventId)
  validateRefField failWith "before_ref" (grcBeforeRef contract) (geeBeforeRef envelope)
  validateRefField failWith "after_ref" (grcAfterRef contract) (geeAfterRef envelope)
  validateRefField failWith "effect_ref" (grcEffectRef contract) (geeEffectRef envelope)
  validateRefField failWith "rollback_link" (grcRollbackLink contract) (geeRollbackLink envelope)
  validateRefField failWith "resolved decision" (grcResolvedDecision contract) (geeResolvedDecision envelope)

requiredRefsForEvent :: GovernanceEvent -> GovernanceRefsContract
requiredRefsForEvent event =
  subjectRefContract (geeSubject envelope) (geeLifecycleStatus envelope) (geeDecision envelope)
  where
    envelope = geEnvelope event

subjectRefContract :: GovernedSubject -> GovernanceLifecycleStatus -> GovernanceDecision -> GovernanceRefsContract
subjectRefContract subject lifecycle decision =
  case subject of
    SubjectPerspective _ -> lifecycleRefContract lifecycle decision
    SubjectFreeze _ -> lifecycleRefContract lifecycle decision
    SubjectClaimStance _ -> lifecycleRefContract lifecycle decision
    SubjectCapability _ -> lifecycleRefContract lifecycle decision
    SubjectCrossSessionCarry _ -> lifecycleRefContract lifecycle decision
    SubjectNormativeProfile _ -> lifecycleRefContract lifecycle decision

lifecycleRefContract :: GovernanceLifecycleStatus -> GovernanceDecision -> GovernanceRefsContract
lifecycleRefContract lifecycle decision = GovernanceRefsContract
  { grcBeforeRef = RefRequired
  , grcAfterRef = afterEffectRefRequirement lifecycle decision
  , grcEffectRef = afterEffectRefRequirement lifecycle decision
  , grcRollbackLink = if decision == GovRollback || lifecycle == GlsRolledBack then RefRequired else RefOptional
  , grcResolvedDecision = RefRequired
  }

afterEffectRefRequirement :: GovernanceLifecycleStatus -> GovernanceDecision -> GovernanceRefRequirement
afterEffectRefRequirement lifecycle decision
  | decision == GovDeny = RefOptional
  | otherwise =
      case lifecycle of
        GlsEvaluated -> RefRequired
        GlsCommitted -> RefRequired
        GlsRolledBack -> RefRequired
        GlsDenied -> RefOptional
        GlsIntent -> RefOptional
        GlsArchived -> RefOptional

validateRefField :: (Text -> Either Text ()) -> Text -> GovernanceRefRequirement -> Maybe a -> Either Text ()
validateRefField failWith label requirement value =
  case (requirement, value) of
    (RefRequired, Nothing) -> failWith ("governance event missing " <> label)
    (RefForbidden, Just _) -> failWith ("governance event unexpected " <> label)
    _ -> pure ()

governancePermission :: GovernanceActor -> GovernedSubject -> GovernanceDecision -> GovernancePermission
governancePermission actor subject decision =
  case (actor, subject, decision) of
    (ActorReplayRebuild, _, _) -> GovernanceDenied "replay actor is read-only"
    (ActorRuntime, SubjectNormativeProfile _, _) -> GovernanceDenied "runtime cannot revise normative profile"
    (ActorRuntime, SubjectFreeze _, GovFreeze) -> GovernanceDenied "runtime cannot freeze governed subjects"
    (ActorRuntime, SubjectFreeze _, GovSuspend) -> GovernanceDenied "runtime cannot govern freeze release"
    (ActorRuntime, SubjectCrossSessionCarry _, GovPromote) -> GovernanceDenied "runtime cannot promote cross-session carry"
    (ActorRuntime, SubjectCapability _, GovPromote) -> GovernanceDenied "runtime cannot promote capability updates"
    (ActorRuntime, SubjectPerspective _, GovObserveOnly) -> GovernanceAllowed
    (ActorRuntime, SubjectPerspective _, GovQuarantine) -> GovernanceAllowed
    (ActorRuntime, SubjectPerspective _, GovAcceptBounded) -> GovernanceAllowed
    (ActorRuntime, SubjectPerspective _, GovPromote) -> GovernanceAllowed
    (ActorRuntime, SubjectPerspective _, GovSuspend) -> GovernanceAllowed
    (ActorRuntime, SubjectPerspective _, GovRollback) -> GovernanceAllowed
    (ActorRuntime, SubjectPerspective _, GovDeny) -> GovernanceAllowed
    (ActorRuntime, SubjectClaimStance _, GovObserveOnly) -> GovernanceAllowed
    (ActorRuntime, SubjectClaimStance _, GovQuarantine) -> GovernanceAllowed
    (ActorRuntime, SubjectClaimStance _, GovDeny) -> GovernanceAllowed
    (ActorRuntime, SubjectCapability _, GovObserveOnly) -> GovernanceAllowed
    (ActorRuntime, SubjectCapability _, GovQuarantine) -> GovernanceAllowed
    (ActorRuntime, SubjectCapability _, GovDeny) -> GovernanceAllowed
    (ActorRuntime, SubjectCrossSessionCarry _, GovObserveOnly) -> GovernanceAllowed
    (ActorRuntime, SubjectCrossSessionCarry _, GovQuarantine) -> GovernanceAllowed
    (ActorRuntime, SubjectCrossSessionCarry _, GovDeny) -> GovernanceAllowed
    (actor', subject', decision')
      | actor' == ActorOperator || actor' == ActorOfflineGovernance ->
          privilegedGovernancePermission subject' decision'
    _ -> GovernanceDenied "action not explicitly allowed"

privilegedGovernancePermission :: GovernedSubject -> GovernanceDecision -> GovernancePermission
privilegedGovernancePermission subject decision =
  case (subject, decision) of
    (SubjectPerspective _, GovObserveOnly) -> GovernanceAllowed
    (SubjectPerspective _, GovQuarantine) -> GovernanceAllowed
    (SubjectPerspective _, GovAcceptBounded) -> GovernanceAllowed
    (SubjectPerspective _, GovPromote) -> GovernanceAllowed
    (SubjectPerspective _, GovSuspend) -> GovernanceAllowed
    (SubjectPerspective _, GovRollback) -> GovernanceAllowed
    (SubjectPerspective _, GovDeny) -> GovernanceAllowed
    (SubjectClaimStance _, GovObserveOnly) -> GovernanceAllowed
    (SubjectClaimStance _, GovQuarantine) -> GovernanceAllowed
    (SubjectClaimStance _, GovPromote) -> GovernanceAllowed
    (SubjectClaimStance _, GovSuspend) -> GovernanceAllowed
    (SubjectClaimStance _, GovRollback) -> GovernanceAllowed
    (SubjectClaimStance _, GovDeny) -> GovernanceAllowed
    (SubjectCapability _, GovObserveOnly) -> GovernanceAllowed
    (SubjectCapability _, GovQuarantine) -> GovernanceAllowed
    (SubjectCapability _, GovPromote) -> GovernanceAllowed
    (SubjectCapability _, GovSuspend) -> GovernanceAllowed
    (SubjectCapability _, GovRollback) -> GovernanceAllowed
    (SubjectCapability _, GovDeny) -> GovernanceAllowed
    (SubjectCrossSessionCarry _, GovObserveOnly) -> GovernanceAllowed
    (SubjectCrossSessionCarry _, GovQuarantine) -> GovernanceAllowed
    (SubjectCrossSessionCarry _, GovPromote) -> GovernanceAllowed
    (SubjectCrossSessionCarry _, GovSuspend) -> GovernanceAllowed
    (SubjectCrossSessionCarry _, GovRollback) -> GovernanceAllowed
    (SubjectCrossSessionCarry _, GovDeny) -> GovernanceAllowed
    (SubjectFreeze _, GovObserveOnly) -> GovernanceAllowed
    (SubjectFreeze _, GovFreeze) -> GovernanceAllowed
    (SubjectFreeze _, GovSuspend) -> GovernanceAllowed
    (SubjectFreeze _, GovRollback) -> GovernanceAllowed
    (SubjectFreeze _, GovDeny) -> GovernanceAllowed
    (SubjectNormativeProfile _, GovObserveOnly) -> GovernanceAllowed
    (SubjectNormativeProfile _, GovQuarantine) -> GovernanceAllowed
    (SubjectNormativeProfile _, GovPromote) -> GovernanceAllowed
    (SubjectNormativeProfile _, GovSuspend) -> GovernanceAllowed
    (SubjectNormativeProfile _, GovRollback) -> GovernanceAllowed
    (SubjectNormativeProfile _, GovDeny) -> GovernanceAllowed
    _ -> GovernanceDenied "privileged action not explicitly allowed"

governancePermissionAllowed :: GovernanceActor -> GovernedSubject -> GovernanceDecision -> Bool
governancePermissionAllowed actor subject decision =
  case governancePermission actor subject decision of
    GovernanceAllowed -> True
    GovernanceDenied _ -> False

supportedGovernedSubject :: GovernedSubject -> Bool
supportedGovernedSubject _ = True

governanceProjectionChecksum :: ProjectionMeta -> PerspectiveRegistry -> [PerspectiveProjection] -> [GovernedProjectionRef] -> Text
governanceProjectionChecksum meta registry projections governedRefs =
  hashString
    ( BL8.unpack (encode meta)
        <> "|" <> BL8.unpack (encode registry)
        <> "|" <> BL8.unpack (encode projections)
        <> "|" <> BL8.unpack (encode governedRefs)
    )

governanceProvenanceTrail :: [GovernanceEvent] -> Either Text [GovernanceProvenanceLink]
governanceProvenanceTrail events = do
  ordered <- canonicalizeGovernanceHistory events
  pure (map provenanceLink ordered)
  where
    provenanceLink event =
      let envelope = geEnvelope event
      in GovernanceProvenanceLink
           { gplEventId = geeId envelope
           , gplSubject = geeSubject envelope
           , gplParentRefs = geeParentRefs envelope
           , gplReasonTag = grTag (geeReason envelope)
           , gplEffectRef = geeEffectRef envelope
           }

payloadSubject :: GovernanceEvent -> GovernedSubject
payloadSubject event =
  case gePayload event of
    GpPerspective payload -> SubjectPerspective (ppPerspectiveId payload)
    GpClaimStance payload -> SubjectClaimStance (cspClaimRef payload)
    GpCapability payload -> SubjectCapability (cpCapabilityRef payload)
    GpFreeze payload -> SubjectFreeze (fpScope payload)
    GpCarry payload -> SubjectCrossSessionCarry (cpCarryKey payload)
    GpNormativeRevision payload -> SubjectNormativeProfile (nrpProfileId payload)

normalizeGovernanceEvent :: GovernanceEvent -> GovernanceEvent
normalizeGovernanceEvent = normalizeGovernanceEventWith GovernanceHashSha256

normalizeGovernanceEventWith :: GovernanceHashScheme -> GovernanceEvent -> GovernanceEvent
normalizeGovernanceEventWith scheme event =
  event { geEnvelope = envelope { geePayloadHash = Just payloadHash, geeEventHash = Just eventHash } }
  where
    envelope = geEnvelope event
    payloadHash = governanceEventPayloadHashTextWith scheme event
    eventHash = governanceEventHashTextWith scheme event payloadHash

detectGovernanceHashScheme :: GovernanceEventEnvelope -> GovernanceHashScheme
detectGovernanceHashScheme envelope =
  fromMaybe GovernanceHashSha256
    ( (geePayloadHash envelope >>= hashSchemeFromText)
      <|> (geeEventHash envelope >>= hashSchemeFromText)
      <|> (geePrevHash envelope >>= hashSchemeFromText)
    )

governanceDecisionFromPerspectivePromotion :: PerspectivePromotionDecision -> GovernanceDecision
governanceDecisionFromPerspectivePromotion decision =
  case decision of
    PpdObserveOnly -> GovObserveOnly
    PpdQuarantine -> GovQuarantine
    PpdAcceptBounded -> GovAcceptBounded
    PpdPromoteEndorsed -> GovPromote
    PpdReviseActive -> GovPromote
    PpdSuspendActive -> GovSuspend
    PpdRollbackPrior -> GovRollback

governanceDecisionFromPerspectiveOutcome :: PerspectiveAdmissibility -> PerspectivePromotionDecision -> GovernanceDecision
governanceDecisionFromPerspectiveOutcome admissibility decision =
  case admissibility of
    PerspectiveInadmissible _ -> GovDeny
    _ -> governanceDecisionFromPerspectivePromotion decision

governanceEventIdText :: GovernanceEventId -> Text
governanceEventIdText = unGovernanceEventId

governanceEventPayloadHashText :: GovernanceEvent -> Text
governanceEventPayloadHashText = governanceEventPayloadHashTextWith GovernanceHashSha256

governanceEventPayloadHashTextWith :: GovernanceHashScheme -> GovernanceEvent -> Text
governanceEventPayloadHashTextWith scheme = hashStringWith scheme . BL8.unpack . encode . gePayload

governanceEventHashText :: GovernanceEvent -> Text -> Text
governanceEventHashText = governanceEventHashTextWith GovernanceHashSha256

governanceEventHashTextWith :: GovernanceHashScheme -> GovernanceEvent -> Text -> Text
governanceEventHashTextWith scheme event payloadHash =
  hashStringWith scheme (T.unpack (governanceEnvelopeCoreText (geEnvelope event) payloadHash))

governanceHistoryFingerprint :: [GovernanceEvent] -> Text
governanceHistoryFingerprint events =
  case canonicalizeGovernanceHistory events of
    Right ordered ->
      hashString (T.unpack (T.intercalate "|" (map (fromMaybe "" . geeEventHash . geEnvelope) ordered)))
    Left _ ->
      "invalid:" <> hashString (T.unpack (T.intercalate "|" (map (fromMaybe "" . geeEventHash . geEnvelope . normalizeGovernanceEvent) events)))

perspectiveRegistryHash :: PerspectiveRegistry -> Text
perspectiveRegistryHash = hashString . BL8.unpack . encode

perspectiveIdentityForScope :: Int -> Text -> PerspectiveScope -> PerspectiveRegistry -> (PerspectiveId, Maybe PerspectiveVersionId, PerspectiveStatus)
perspectiveIdentityForScope sequenceNo sessionId scope registry =
  case M.lookup scope (prThreads registry) of
    Just thread ->
      ( ptPerspectiveId thread
      , ptActiveVersion thread <|> (epVersion <$> latestEndorsedPerspective thread)
      , ptStatus thread
      )
    Nothing ->
      ( PerspectiveId ("pending:" <> safeEventText sessionId <> ":" <> T.pack (show sequenceNo) <> ":" <> renderPerspectiveScope scope)
      , Nothing
      , PerspectiveContested
      )

lifecycleForPerspective :: PerspectiveAdmissibility -> PerspectivePromotionDecision -> GovernanceLifecycleStatus
lifecycleForPerspective admissibility decision =
  case admissibility of
    PerspectiveInadmissible _ -> GlsDenied
    _ -> case decision of
      PpdObserveOnly -> GlsEvaluated
      PpdRollbackPrior -> GlsRolledBack
      _ -> GlsCommitted

perspectiveGovernanceReason :: PerspectiveScope -> PerspectiveAdmissibility -> PerspectiveCandidate -> GovernanceDecision -> GovernanceReason
perspectiveGovernanceReason scope admissibility candidate decision = GovernanceReason
  { grTag = "perspective:" <> T.pack (show decision)
  , grDetails =
      [ "scope=" <> renderPerspectiveScope scope
      , "admissibility=" <> T.pack (show admissibility)
      , "confidence=" <> T.pack (show (pcConfidence candidate))
      , "counterargument_pressure=" <> T.pack (show (pcCounterargumentPressure candidate))
      , "normative_alignment=" <> T.pack (show (pcNormativeAlignment candidate))
      , "internal_tension=" <> T.pack (show (pcInternalTension candidate))
      ]
  }

governanceEnvelopeCoreText :: GovernanceEventEnvelope -> Text -> Text
governanceEnvelopeCoreText envelope payloadHash = T.intercalate "|"
  [ governanceEventIdText (geeId envelope)
  , T.pack (show (geeSchemaVersion envelope))
  , T.pack (show (geePayloadVersion envelope))
  , T.pack (show (geeLifecycleStatus envelope))
  , T.pack (show (geeSubject envelope))
  , T.pack (show (geeActor envelope))
  , T.pack (show (geeTurnId envelope))
  , T.pack (show (geeSessionId envelope))
  , geeStreamId envelope
  , geePartitionId envelope
  , T.pack (show (geeSequenceNo envelope))
  , T.intercalate "," (map governanceEventIdText (geeParentRefs envelope))
  , T.pack (show (geeDecision envelope))
  , T.pack (show (geeRequestedDecision envelope))
  , T.pack (show (geeResolvedDecision envelope))
  , grTag (geeReason envelope)
  , T.intercalate "," (grDetails (geeReason envelope))
  , T.pack (show (geeNormativeProfileVersion envelope))
  , T.pack (show (geeProjectionVersion envelope))
  , T.pack (show (geeReducerVersion envelope))
  , T.pack (show (geeNormativeEvaluatorVersion envelope))
  , T.pack (show (geeConfidenceAlgebraVersion envelope))
  , T.pack (show (geeCapabilityEvaluatorVersion envelope))
  , T.pack (show (geeSandboxVersion envelope))
  , T.pack (show (geeRollbackLink envelope))
  , T.pack (show (geeBeforeRef envelope))
  , T.pack (show (geeAfterRef envelope))
  , T.pack (show (geeEffectRef envelope))
  , T.pack (show (geePrevHash envelope))
  , payloadHash
  ]

governanceOrderKey :: GovernanceEvent -> (Int, Text, Text)
governanceOrderKey event =
  let envelope = geEnvelope event
  in (geeSequenceNo envelope, geePartitionId envelope, governanceEventIdText (geeId envelope))

dedupeGovernanceGroup :: [GovernanceEvent] -> Either Text GovernanceEvent
dedupeGovernanceGroup [] = Left "empty governance duplicate group"
dedupeGovernanceGroup (event:rest)
  | all (== event) rest = pure event
  | otherwise = Left ("duplicate governance event id with conflicting semantics: " <> governanceEventIdText (geeId (geEnvelope event)))

validateGovernanceHashChain :: [GovernanceEvent] -> Either Text ()
validateGovernanceHashChain = go Nothing
  where
    go _ [] = pure ()
    go expectedPrev (event:rest) = do
      let envelope = geEnvelope event
      if geePrevHash envelope /= expectedPrev
        then Left ("governance hash chain mismatch: " <> governanceEventIdText (geeId envelope))
        else go (geeEventHash envelope) rest

validateGovernanceAppend :: GovernanceEvent -> [GovernanceEvent] -> Either Text ()
validateGovernanceAppend event history = do
  validateGovernanceHashChain history
  case history of
    [] ->
      if geePrevHash envelope == Nothing
        then pure ()
        else Left ("first governance event must not carry prev_hash: " <> eventId)
    previous : rest -> do
      let previousEvent = foldl (\_ current -> current) previous rest
          previousEnvelope = geEnvelope previousEvent
      if geeSequenceNo envelope > geeSequenceNo previousEnvelope
        then pure ()
        else Left ("governance sequence must increase on append: " <> eventId)
      if geePrevHash envelope == geeEventHash previousEnvelope
        then pure ()
        else Left ("governance append prev_hash mismatch: " <> eventId)
  where
    envelope = geEnvelope event
    eventId = governanceEventIdText (geeId envelope)

safeEventText :: Text -> Text
safeEventText = T.map safeChar
  where
    safeChar ch
      | ch == ':' || ch == '|' || ch == '/' || ch == '\\' || ch == ' ' = '_'
      | otherwise = ch

hashString :: String -> Text
hashString = hashStringWith GovernanceHashSha256

hashStringWith :: GovernanceHashScheme -> String -> Text
hashStringWith scheme input = case scheme of
  GovernanceHashLegacyFNV -> legacyFNV input
  GovernanceHashSha256 -> "sha256:" <> sha256Hex (SHA256.hashlazy (BL8.pack input))
  where
    sha256Hex = T.pack . concatMap byteToHex . BS.unpack
    byteToHex byte =
      let raw = showHex byte ""
      in case raw of
           [single] -> ['0', single]
           other -> other

legacyFNV :: String -> Text
legacyFNV input = T.pack ("fnv1a64:" <> showHex (foldl fnvStep fnvOffset input) "")
  where
    fnvOffset :: Word64
    fnvOffset = 14695981039346656037

    fnvStep :: Word64 -> Char -> Word64
    fnvStep h ch = (h `xor` fromIntegral (fromEnum ch)) * 1099511628211

hashSchemeFromText :: Text -> Maybe GovernanceHashScheme
hashSchemeFromText value
  | "fnv1a64:" `T.isPrefixOf` value = Just GovernanceHashLegacyFNV
  | "sha256:" `T.isPrefixOf` value = Just GovernanceHashSha256
  | otherwise = Nothing

(<|>) :: Maybe a -> Maybe a -> Maybe a
Just a <|> _ = Just a
Nothing <|> b = b
