{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE StrictData #-}
module QxFx0.Types.TurnProjection
  ( TurnReplayTrace(..)
  , PreActorFailureKind(..)
  , PreActorFailureEvent(..)
  , EffectSnapshot(..)
  , TurnFamilyDerivationStep(..)
  , GenerationAttempt(..)
  , TurnProjection(..)
  ) where

import QxFx0.Types.Domain (CanonicalMoveFamily(..), IllocutionaryForce(..), Register(..), SemanticLayer(..), WarrantedMoveMode(..))
import QxFx0.Types.Decision (RenderStyle(..), ShadowStatus(..), LegitimacyReason(..), PlannerMode(..), ParserMode(..), DecisionDisposition(..))
import QxFx0.Core.CommitmentStoreAdmission (CommitmentStoreAdmissionDecision)
import QxFx0.Types.Observability (ArtifactManifest, AssemblyPath, AuthorityClass, ContractProvenance, ConvMove(..), ReplayProvenanceStatus, ResponseSurfaceKind, SurfaceProvenance, TruthContractStatus)
import QxFx0.Types.Recovery (LocalRecoveryCause, LocalRecoveryStrategy)
import QxFx0.Types.Thresholds (LegitimacyStatus(..), ScenePressure(..))
import QxFx0.Types.ShadowDivergence (ShadowDivergenceKind, ShadowDivergenceSeverity, ShadowSnapshotId)
import QxFx0.Types.Decision (ClaimAst)
import QxFx0.Types.State.Perspective (PerspectiveProjection)
import QxFx0.Types.Sense (SenseAxis, SenseOperator, RhetoricalMove)
import QxFx0.Types.State.DialogueDevelopment (DialoguePhase)
import QxFx0.Types.Domain.User (IdentityClaimRef)
import QxFx0.Self.Conatus (ConatusEnergy)
import QxFx0.Self.Field (Field)
import QxFx0.Types.CognitiveSignals (CognitiveSignals)
import QxFx0.Memory.Episodic
  ( EpisodicQuery
  , EpisodicId
  , ReuseAnnotation
  )
import Data.Aeson (ToJSON, FromJSON)
import Data.Text (Text)
import GHC.Generics (Generic)
import QxFx0.Core.FMAR (FmarMode(..))

data PreActorFailureKind
  = PreActorTransportFailure
  | PreActorFallbackNonAuthoritative
  | PreActorNoExecutableTool
  deriving stock (Show, Eq, Generic)
  deriving anyclass (ToJSON, FromJSON)

data PreActorFailureEvent = PreActorFailureEvent
  { pafeKind :: !PreActorFailureKind
  , pafeActionKind :: !Text
  , pafeReason :: !Text
  } deriving stock (Show, Eq, Generic)
    deriving anyclass (ToJSON, FromJSON)

-- | Runtime effect snapshots recorded at prepare time and replayed by
-- 'QxFx0.Core.PipelineIO.Replay.mkReplayPipelineIO'.  A sub-record
-- so the wide path (all resolved effects become replay inputs) grows
-- this field, not the top-level god-record.
--
-- Old traces (pre-vX) serialise as 'Nothing'; only traces produced
-- after this field was added carry the snapshot.
data EffectSnapshot = EffectSnapshot
  { esApiHealthy :: !Bool
  } deriving stock (Show, Eq, Generic)
    deriving anyclass (ToJSON, FromJSON)

-- | One step in the family derivation chain from routing to rendering.
data TurnFamilyDerivationStep = TurnFamilyDerivationStep
  { tfdsLabel  :: !Text
  , tfdsFamily :: !CanonicalMoveFamily
  } deriving stock (Show, Eq, Generic)
    deriving anyclass (ToJSON, FromJSON)

-- | One attempt in the text-generation pipeline (assembly path, PGF, etc.).
data GenerationAttempt = GenerationAttempt
  { gaPath    :: !Text
  , gaOutcome :: !Text
  } deriving stock (Show, Eq, Generic)
    deriving anyclass (ToJSON, FromJSON)

-- | Canonical replay/projection envelope for a turn.
-- Rich replay visibility does not imply that every field carries canonical
-- authority: this record intentionally mixes canonical truth caps,
-- projection-truth classifications, observational fields, and
-- compatibility/shim markers in one replay plane.
data TurnReplayTrace = TurnReplayTrace
  { trcRequestId :: !Text
  , trcSessionId :: !Text
  , trcRuntimeMode :: !Text
  , trcShadowPolicy :: !Text
  , trcLocalRecoveryPolicy :: !Text
  , trcRecoveryCause :: !(Maybe LocalRecoveryCause)
  , trcRecoveryStrategy :: !(Maybe LocalRecoveryStrategy)
  , trcRecoveryEvidence :: ![Text]
  , trcSemanticIntrospectionEnabled :: !Bool
  , trcWarnMorphologyFallbackEnabled :: !Bool
  , trcRequestedFamily :: !CanonicalMoveFamily
  , trcStrategyFamily :: !(Maybe CanonicalMoveFamily)
  , trcNarrativeHint :: !(Maybe Text)
  , trcIntuitionHint :: !(Maybe Text)
  , trcPreShadowFamily :: !CanonicalMoveFamily
  , trcShadowSnapshotId :: !ShadowSnapshotId
  , trcShadowStatus :: !ShadowStatus
  , trcShadowDivergenceKind :: !ShadowDivergenceKind
  , trcShadowDivergenceSeverity :: !ShadowDivergenceSeverity
  , trcShadowResolvedFamily :: !CanonicalMoveFamily
  , trcFinalFamily :: !CanonicalMoveFamily
  , trcFinalForce :: !IllocutionaryForce
  , trcDecisionDisposition :: !DecisionDisposition
  , trcLegitimacyReason :: !LegitimacyReason
  , trcParserConfidence :: !Double
  , trcParserBackend :: !Text
  , trcParserStatus :: !Text
  , trcParserDegradationReason :: !(Maybe Text)
  , trcParserLatencyMs :: !Int
  , trcEmbeddingQuality :: !Text
  , trcClaimAst :: !(Maybe ClaimAst)
  , trcPreSafetyRenderedRaw :: !Text
  , trcRenderedAfterRebind :: !Text
  , trcLinearizationLang :: !(Maybe Text)
  , trcLinearizationOk :: !Bool
  , trcFallbackReason :: !(Maybe Text)
  , trcContractProvenance :: !(Maybe ContractProvenance)
  , trcSurfaceProvenance :: !(Maybe SurfaceProvenance)
   , trcAuthorityClass :: !(Maybe AuthorityClass)
     -- ^ Response/projection authority classification for the executed turn.
     --   This is not itself the canonical authority root; it is a typed
     --   outcome classification persisted in the replay plane.
   , trcTruthContractStatus :: !TruthContractStatus
     -- ^ Canonical truth-contract cap mirrored into replay. Replay persistence
     --   does not upgrade this field beyond the authoritative state machine.
   , trcResponseSurfaceKind :: !(Maybe ResponseSurfaceKind)
   , trcAssemblyPath :: !(Maybe AssemblyPath)
   , trcArtifactManifest :: !(Maybe ArtifactManifest)
     -- ^ Provenance/audit manifest for the rendered surface. It is a replay
     --   and operator-facing proof aid, not a standalone source-of-truth root.
   , trcReplayProvenanceStatus :: !ReplayProvenanceStatus
     -- ^ Replay completeness / trustworthiness warning surface. This status is
     --   about replay/provenance quality, not canonical runtime authority.
  , trcDerivationTags :: ![Text]
  , trcSalienceDriver :: !Text
    -- ^ Phase 5.5e: rendered snake_case tag for the dominant
    --   'QxFx0.Self.Salience.SalienceDriver' on this turn.
    --   Closed enum tag; stable across builds.
  , trcSalienceHolisticBias :: !Double
    -- ^ Phase 5.5e: 'salienceHolisticBias' in @[0, 1]@.
    --   @0@ = pure formal, @1@ = pure holistic, @0.5@ = neutral.
  , trcSalienceConfidence :: !Double
    -- ^ Phase 5.5e: 'salienceConfidence' in @[0, 1]@.
    --   @1@ = one driver decisively dominates,
    --   @0@ = contributions cancel.
  , trcDeliberationRule :: !(Maybe Text)
  , trcDeliberationAgreement :: !(Maybe Text)
  , trcDeliberationDivergence :: !(Maybe Double)
  , trcDeliberationNarrativeTone :: !(Maybe Text)
  , trcEssenceMode :: !(Maybe Text)
    -- ^ Phase 9: snake_case 'renderEssenceMode' tag of the
    --   post-turn essence.  @Just "witnessing"@ pre-commit;
    --   @Just "contemplative" | "dialogical" | "integrative"@
    --   post-commit (Phase 10).  @Nothing@ only when the essence
    --   layer is statically disabled (not currently exposed).
  , trcEssenceCommitted :: !(Maybe Bool)
    -- ^ Phase 9: @Just False@ pre-commit, @Just True@ post-commit
    --   (Phase 10).  Always @Just False@ in Phase 9 by contract.
  , trcEssenceAngstLevel :: !(Maybe Double)
    -- ^ Phase 9: 'etAngstLevel' of the post-turn trajectory in
    --   @[0, 1]@.  Tracks accumulated unresolved divergence.
  , trcEssenceTrigger :: !(Maybe Text)
    -- ^ Phase 9: snake_case 'renderCommitmentTrigger' tag set only
    --   on the turn a commitment fires (Phase 10).  Always
    --   @Nothing@ in Phase 9.
  , trcLearningQueryType :: !(Maybe Text)
    -- ^ Phase 8: type of learning query, e.g. "definition",
    --   "declension", "concept".  Nothing when no learning loop
    --   was activated this turn.
  , trcExternalTool :: !(Maybe Text)
    -- ^ Phase 8: canonical tool name selected for the learning query.
  , trcLearningValidationStatus :: !(Maybe Text)
    -- ^ Phase 8: "accept" | "reject" | "invalid_response" |
    --   "sandbox_reject" | "not_attempted".
  , trcLearningSandboxResult :: !(Maybe Text)
    -- ^ Phase 8: JSON-encoded 'SandboxMetrics' or reject reason.
  , trcLearningGraftTurn :: !(Maybe Int)
    -- ^ Phase 8: turn number when the fruit was grafted (if accepted).
  , trcLearningRejectReason :: !(Maybe Text)
    -- ^ Phase 8: human-readable reject reason for audit.
  , trcExternalActionReason :: !(Maybe Text)
    -- ^ AS1-03: typed allow/deny/no-action rationale rendered into a stable text tag.
  , trcExternalActionNeed :: !(Maybe Text)
    -- ^ AS1-03: active learning need associated with the outbound action decision.
  , trcPreActorFailureEvent :: !(Maybe PreActorFailureEvent)
    -- ^ AS1-04: typed failure event for outbound attempts that failed before
    --   any executed actor identity existed. Denied/no-action paths remain
    --   actor-clean without fabricating this event.
  , trcSenseAnchor :: !Text
  , trcSenseOperator :: !(Maybe SenseOperator)
  , trcSensePreservedAxes :: ![SenseAxis]
  , trcDialogueFocus :: !Text
  , trcDialogueFocusBefore :: !Text
  , trcDialogueFocusAfter :: !Text
  , trcDialoguePhase :: !DialoguePhase
  , trcDialoguePhaseBefore :: !DialoguePhase
  , trcDialoguePhaseAfter :: !DialoguePhase
  , trcDialogueCommitmentCount :: !Int
  , trcDialogueCommitmentCountBefore :: !Int
   , trcDialogueCommitmentCountAfter :: !Int
   , trcMicroPlanMoves :: ![RhetoricalMove]
   , trcMicroPlanExplicitness :: !Double
   , trcDreamPressureDatalogClass :: !(Maybe Text)
   , trcDreamPressureIntuitionClass :: !(Maybe Text)
   , trcDreamPressureAgreement :: !(Maybe Text)
   , trcDreamPressureStrength :: !(Maybe Double)
   , trcDreamPressureCandidateThresholdFired :: !(Maybe Bool)
   , trcDreamPressureCandidateKinds :: ![Text]
   , trcDreamPressureBiasApplied :: !(Maybe Bool)
   , trcDreamCandidateLifecycleStatuses :: ![Text]
   , trcDreamCandidateDecisionReasons :: ![Text]
   , trcDreamCandidateApplied :: !(Maybe Bool)
   , trcPerspectiveProjection :: !(Maybe PerspectiveProjection)
     -- ^ P4: runtime-safe endorsed perspective projection. Raw candidate
    --   internals and registry lineage are not exposed to render/replay.
  , trcPerspectiveProjections :: ![PerspectiveProjection]
    -- ^ P4: bounded list of active safe projections, preserving the fact
    --   that the canonical registry may contain multiple active scopes.
  , trcConatusEnergy :: !ConatusEnergy
    -- ^ P3: full ConatusEnergy record (ceScalar + ceComponents) from the
    --   current turn's PrepareStatic. Replay can reconstruct the scalar
    --   and per-axis decomposition from this field alone.
  , trcConatusGateFired :: !Bool
    -- ^ P3: True when the structural-energy gate fired this turn
    --   (conatusGateFires). Together with trcConatusEnergy enables
    --   replay-time explanation of Conatus-driven behaviour.
  , trcField :: !Field
    -- ^ P3: full Field Σ-type (resonance, atmosphere, confidence,
    --   consolidation, counterfactual) from the current turn.
    --   Carries all five components so replay has full reconstructability.
  , trcIdentityClaims :: ![IdentityClaimRef]
    -- ^ P3: identity claim references active at turn time,
    --   sourced from ssIdentityClaims. Enables replay-time inspection
    --   of which identity claims were in play.
  , trcEpisodicEncoding :: ![EpisodicId]
    -- ^ P7: EpisodicIds encoded on this turn, empty if no encode was
    --   performed. Enables replay-time explanation of what was recorded.
  , trcEpisodicRetrieval :: !(Maybe (EpisodicQuery, Int))
    -- ^ P7: the query and result count for any episodic retrieval this
    --   turn. @Nothing@ if no retrieval was performed.
  , trcEpisodicForgetting :: !(Int, Maybe EpisodicId)
    -- ^ P7: (count of forgotten events, maybe the last forgotten id).
    --   Enables replay-time explanation of forgetting that occurred.
  , trcRegimeVersion :: !Int
    -- ^ M5: math version active during this turn (from
    --   'QxFx0.Types.RuntimeRegime.currentMathVersion').
    --   Replay can use this to select the correct calibration corpus.
  , trcFamilyDivergenceActive :: !Bool
    -- ^ M5: whether holistic-formal family divergence modulation was active
    --   during this turn (ADR-0019). Replay needs this to reconstruct
    --   salience-modulated routing decisions.
  , trcSemanticCommitmentCount :: !Int
    -- ^ C3 (Package 2): number of active semantic commitments in
    --   'ssSemanticCommitments' at turn completion. Zero when the store
    --   is Nothing (Package 2 not yet initialised). Non-zero indicates
    --   typed domain commitments are accumulating.
  , trcQuarantinedCommitmentCount :: !Int
    -- ^ CTS-43: number of quarantined (suppressed) commitments in
    --   'ssSemanticCommitments' at turn completion. Visible for review;
    --   quarantined claims do NOT feed reasoning.
  , trcPromotedFromQuarantineCount :: !Int
    -- ^ CTS-44: number of claims promoted from quarantine to active
    --   this turn (matching statement normalized). Zero when no promotion
    --   occurred.
  , trcCommitmentStoreDecision :: !CommitmentStoreAdmissionDecision
    -- ^ CTS-42: the admission decision applied to this turn's factual
    --   claims (anchor + surface-parsed). Captures the decision that was
    --   actually applied, not a re-computation from 'trcTruthContractStatus',
    --   so replay under a future constitution version does not alter the
    --   persisted decision.
  , trcCognitiveSignals :: !CognitiveSignals
    -- ^ WP-S: the compute-once derived-signal bundle (counterfactual entropy,
    --   field confidence, shadow disagreement, max posterior) shared by the
    --   doubt loop (WP-D) and affect (WP-E). Surfaced here as the living
    --   consumer of the seam.
  , trcDoubtScore :: !(Maybe Double)
    -- ^ P8 (WP-D): doubt score in @[0,1]@ from 'tiDoubtScore'. High doubt
    --   (≥ 0.7) signals uncertainty and can drive routing toward clarifying
    --   moves or reduce explicitness. @Nothing@ when doubt computation is
    --   disabled or unavailable.
  , trcEpisodicRetrievalCount :: !(Maybe Int)
    -- ^ P8 (WP-B): count of episodes retrieved from 'tiRetrievedEpisodes'.
    --   Enables replay-time inspection of episodic memory influence on
    --   routing decisions. @Nothing@ when episodic recall is inactive.
  , trcContentSaliencyDominantCluster :: !(Maybe Int)
    -- ^ P8 (WP-C): dominant cluster ID from spectral clustering of the
    --   meaning graph. Derived from 'csContentSaliency' in 'trcCognitiveSignals'.
    --   @Nothing@ when content saliency is inactive or no clusters exist.
  , trcMoodValence :: !(Maybe Double)
    -- ^ P8 (WP-E): mood valence in @[-1,1]@ from 'atmosphereValence' of
    --   'tiField'. Negative = negative affect, positive = positive affect.
    --   @Nothing@ when affect model is disabled.
  , trcMoodArousal :: !(Maybe Double)
    -- ^ P8 (WP-E): mood arousal in @[0,1]@ from 'atmosphereArousal' of
    --   'tiField'. Low = calm, high = excited. @Nothing@ when affect
    --   model is disabled.
  , trcAffectDecoupled :: !Bool
    -- ^ P8 (WP-E): whether affect decoupled mode was active this turn
    --   ('affectDecoupledActive' flag). When True, atmosphere is computed
    --   from persistent mood rather than immediate turn valence.
  , trcMood :: !Double
    -- ^ P8 (WP-E): persistent mood baseline from 'ssMood' in @[-1,1]@.
    --   Slow affective EMA over ~'moodWindowTurns'. Enables replay-time
    --   inspection of long-term affective state evolution.
  , trcUserModelTopIntent :: !(Maybe Text)
    -- ^ P8 (WP-A): top-ranked intent from 'ssUserModel' posterior.
    --   Enables replay-time inspection of user model influence on routing.
    --   @Nothing@ when user model is empty or disabled.
  , trcUserModelConfidence :: !(Maybe Double)
    -- ^ P8 (WP-A): confidence (posterior probability) of the top intent
    --   from 'ssUserModel'. In @[0,1]@. @Nothing@ when user model is
    --   empty or disabled.
  , trcDerivedInferenceCount :: !(Maybe Int)
    -- ^ P8 (WP-G): count of derived atoms in the Datalog knowledge base.
    --   Enables replay-time inspection of inference engine activity.
    --   @Nothing@ when derived inference tracking is disabled.
  , trcFamilyDivergenceOccurred :: !(Maybe Bool)
    -- ^ P8 (WP-H3): @Just True@ when holistic and formal families diverged
    --   this turn ('holisticFamily /= formalFamily'). @Just False@ when
    --   they agreed. @Nothing@ when family divergence tracking is disabled
    --   ('familyDivergenceEnabled' flag off).
  , trcFmarDetectorFamily :: !(Maybe CanonicalMoveFamily)
    -- ^ FMAR Phase-8: the keyword-detector family recommendation, carried
    --   for shadow-mode comparison against 'trcFmarFamily'. @Nothing@ when
    --   FMAR is off (@QXFX0_FMAR@ unset).
  , trcFmarFamily :: !(Maybe CanonicalMoveFamily)
    -- ^ FMAR Phase-8: the family FMAR selected from the Field position.
    --   @Nothing@ when FMAR is off.
  , trcFmarFamiliesMatch :: !(Maybe Bool)
    -- ^ FMAR Phase-8: @Just True@ when detector and FMAR agree, @Just False@
    --   when FMAR overrode the detector. The core shadow-calibration signal.
    --   @Nothing@ when FMAR is off.
  , trcFmarFieldDistance :: !(Maybe Double)
    -- ^ FMAR Phase-8: distance from the current 8D position to the chosen
    --   family's target Field. Lets calibration judge override quality.
    --   @Nothing@ when FMAR is off.
  , trcFmarMode :: !(Maybe FmarMode)
    -- ^ FMAR Phase-9: the FMAR operating mode. @Just FmarShadow@ or
    --   @Just FmarLive@ when FMAR is active, @Nothing@ when FMAR is off.
    --   Disambiguates trcFmarFamiliesMatch — in shadow mode @Just True@
    --   means cascade==fmar but FMAR did NOT drive the rendering family.
  , trcFamilyDerivationChain :: ![TurnFamilyDerivationStep]
    -- ^ P9: ordered list of family derivation steps from routing through
    --   shadow resolution, legitimacy, diagnostic lock, sense bundle, FMAR,
    --   to renderingFamily.  Includes intermediate points lost in the
    --   compressed tpFamily/tpFinalFamily projection.
  , trcGenerationTrace :: ![GenerationAttempt]
    -- ^ P9: ordered list of text-generation attempts (assembly, factual,
    --   template, structured fallback, PGF) with per-attempt outcomes.
  , trcMorphologyVersion :: !Int
    -- ^ P9 (RGL Russian): morphology version (0 = JSON, 1 = RGL).
    --   Replay needs this to distinguish JSON-backed vs RGL-backed
    --   morphology paths in 'linearizeClaimAstRus'.
  , trcEffectSnapshot :: !(Maybe EffectSnapshot)
    -- ^ Runtime effect snapshots (apiHealthy) recorded at prepare-time.
    --   Consumed by replay to make legitimacy-score deterministic.
    --   'Nothing' for traces recorded before this field was added
    --   (pre-vX — not apiHealthy-deterministic).
  } deriving stock (Show, Eq, Generic)
    deriving anyclass (ToJSON, FromJSON)

data TurnProjection = TurnProjection
  { tqpTurn              :: !Int
  , tqpParserMode        :: !ParserMode
  , tqpParserConfidence  :: !Double
  , tqpParserErrors      :: ![Text]
  , tqpPlannerMode       :: !PlannerMode
  , tqpPlannerDecision   :: !CanonicalMoveFamily
  , tqpAtomRegister      :: !Register
  , tqpAtomLoad          :: !Double
  , tqpScenePressure     :: !ScenePressure
  , tqpSceneRequest      :: !Text
  , tqpSceneStance       :: !SemanticLayer
  , tqpRenderLane        :: !ConvMove
  , tqpRenderStyle       :: !RenderStyle
  , tqpLegitimacyStatus  :: !LegitimacyStatus
  , tqpLegitimacyReason  :: !LegitimacyReason
  , tqpWarrantedMode     :: !WarrantedMoveMode
  , tqpDecisionDisposition :: !DecisionDisposition
  , tqpOwnerFamily       :: !CanonicalMoveFamily
  , tqpOwnerForce        :: !IllocutionaryForce
  , tqpShadowStatus      :: !ShadowStatus
  , tqpShadowSnapshotId  :: !ShadowSnapshotId
  , tqpShadowDivergenceKind :: !ShadowDivergenceKind
  , tqpShadowFamily      :: !(Maybe CanonicalMoveFamily)
  , tqpShadowForce       :: !(Maybe IllocutionaryForce)
  , tqpShadowMessage     :: !Text
  , tqpReplayTrace       :: !TurnReplayTrace
  , tqpDivergence        :: !Bool
  } deriving stock (Show, Eq)
