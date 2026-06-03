{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Observability
  ( LogicalBond
  , AuthorityClass(..)
  , TruthContractStatus(..)
  , ResponseSurfaceKind(..)
  , AssemblyPath(..)
  , ReplayProvenanceStatus(..)
  , ArtifactManifest(..)
  , GfLinearizationResult(..)
  , ExecutedTurnOutcome(..)
  , truthContractStatusForAuthority
  , mkExecutedTurnOutcome
  , ContractProvenance(..)
  , SurfaceProvenance(..)
  , LiveRenderTelemetry(..)
  , MeaningGraph(..)
  , emptyMeaningGraph
  , GeodesicPlan(..)
  , MeaningEdge(..)
  , MeaningState(..)
  , MeaningStateId
  , ResonanceBand(..)
  , DepthBand(..)
  , DensityBand(..)
  , ResponseDepth(..)
  , ResponseStance(..)
  , ConvMove(..)
  , ResponseStrategy(..)
  , PressureBand(..)
  , KernelPulse(..)
  , emptyKernelPulse
  , ConstitutionalThresholds(..)
  , emptyConstitutionalThresholds
  , DepthMode(..)
  , depthModeText
  , ObservabilityState(..)
  , emptyObservabilityState
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson
  ( FromJSON(..)
  , ToJSON(..)
  , (.:)
  , (.:?)
  , (.=)
  , defaultOptions
  , genericParseJSON
  , genericToJSON
  , object
  , withObject
  )
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Text (Text)
import Data.Time (UTCTime)
import GHC.Generics (Generic)

import QxFx0.Types.Domain (CanonicalMoveFamily(..), IllocutionaryForce(..), NixGuardStatus(..))
import QxFx0.Types.Thresholds
  ( DepthMode(..)
  , constitutionalAgencyMinDefault
  , constitutionalAmbiguityPenaltyDefault
  , constitutionalLocalRecoveryThresholdDefault
  , constitutionalShadowDivergencePenaltyDefault
  , constitutionalTensionMaxDefault
  , depthModeText
  , kernelPulseAgencySignalDefault
  , kernelPulseCoherenceDefault
  )

data LogicalBond = LogicalBond
  { lbPremise :: !Text
  , lbConclusion :: !Text
  , lbStrength :: !Double
  , lbIsDefeasible :: !Bool
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)
instance ToJSON LogicalBond where toJSON = genericToJSON defaultOptions
instance FromJSON LogicalBond where parseJSON = genericParseJSON defaultOptions

data AuthorityClass
  = AuthorityCanonical
  | AuthorityAssembled
  | AuthorityRecovery
  | AuthorityFallback
  | AuthorityShim
  | AuthorityDefault
  | AuthorityGeneratedArtifact
  | AuthorityLegacyIncomplete
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData)
instance ToJSON AuthorityClass where toJSON = genericToJSON defaultOptions
instance FromJSON AuthorityClass where parseJSON = genericParseJSON defaultOptions

data TruthContractStatus
  = CanonicalSurfacePreserved
  | AssembledSurfacePreserved
  | ExplicitFallbackSurface
  | NonExpansiveRecoverySurface
  | CompatibilityShimSurface
  | DefaultedSurface
  | GeneratedArtifactSurface
  | LegacyIncompleteSurface
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData)
instance ToJSON TruthContractStatus where toJSON = genericToJSON defaultOptions
instance FromJSON TruthContractStatus where parseJSON = genericParseJSON defaultOptions

data ResponseSurfaceKind
  = SurfaceAuthoritative
  | SurfaceAdvisory
  | SurfaceDegraded
  | SurfaceFallback
  | SurfaceObservationalOnly
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData)
instance ToJSON ResponseSurfaceKind where toJSON = genericToJSON defaultOptions
instance FromJSON ResponseSurfaceKind where parseJSON = genericParseJSON defaultOptions

data AssemblyPath
  = DialogueAssemblyRoute
  | FactualAssemblyRoute
  | TemplateFallbackRoute
  | StructuredFallbackRoute
  | PgfClaimRoute
  | PgfAtomsRoute
  | RussianCompatShimRoute
  | GuardRecoveryRoute
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData)
instance ToJSON AssemblyPath where toJSON = genericToJSON defaultOptions
instance FromJSON AssemblyPath where parseJSON = genericParseJSON defaultOptions

data ReplayProvenanceStatus
  = ReplayProvenanceComplete
  | ReplayProvenanceLegacyIncomplete
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData)
instance ToJSON ReplayProvenanceStatus where toJSON = genericToJSON defaultOptions
instance FromJSON ReplayProvenanceStatus where parseJSON = genericParseJSON defaultOptions

data ArtifactManifest = ArtifactManifest
  { amPgfPath :: !(Maybe FilePath)
  , amPgfHash :: !(Maybe Text)
  , amPgfSourceManifestHash :: !(Maybe Text)
  , amGeneratedInputLexiconHash :: !(Maybe Text)
  , amGfMapHash :: !(Maybe Text)
  , amToolchainIdentity :: !(Maybe Text)
  , amToolchainMarker :: !Text
  } deriving stock (Eq, Show, Read, Generic)
    deriving anyclass (NFData)
instance ToJSON ArtifactManifest where toJSON = genericToJSON defaultOptions
instance FromJSON ArtifactManifest where parseJSON = genericParseJSON defaultOptions

data GfLinearizationResult = GfLinearizationResult
  { glrText :: !Text
  , glrLanguage :: !Text
  , glrAuthorityClass :: !AuthorityClass
  , glrAssemblyPath :: !AssemblyPath
  , glrArtifactManifest :: !ArtifactManifest
  , glrFallbackReason :: !(Maybe Text)
  } deriving stock (Eq, Show, Read, Generic)
    deriving anyclass (NFData)
instance ToJSON GfLinearizationResult where toJSON = genericToJSON defaultOptions
instance FromJSON GfLinearizationResult where parseJSON = genericParseJSON defaultOptions

data ExecutedTurnOutcome = ExecutedTurnOutcome
  { etoFamily :: !CanonicalMoveFamily
  , etoForce :: !IllocutionaryForce
  , etoAuthorityClass :: !AuthorityClass
  , etoTruthContractStatus :: !TruthContractStatus
  , etoResponseSurfaceKind :: !ResponseSurfaceKind
  , etoContractProvenance :: !ContractProvenance
  , etoSurfaceProvenance :: !SurfaceProvenance
  , etoAssemblyPath :: !AssemblyPath
  , etoArtifactManifest :: !ArtifactManifest
  , etoTransitionWon :: !Bool
  } deriving stock (Eq, Show, Read, Generic)
    deriving anyclass (NFData)
instance ToJSON ExecutedTurnOutcome where toJSON = genericToJSON defaultOptions
instance FromJSON ExecutedTurnOutcome where parseJSON = genericParseJSON defaultOptions

mkExecutedTurnOutcome
  :: CanonicalMoveFamily
  -> IllocutionaryForce
  -> AuthorityClass
  -> ContractProvenance
  -> SurfaceProvenance
  -> AssemblyPath
  -> ArtifactManifest
  -> Either Text ExecutedTurnOutcome
mkExecutedTurnOutcome family force authority contractProv surfaceProv assemblyPath manifest = do
  let bad condition msg = if condition then Left msg else Right ()
      transitionWon = authority `elem` [AuthorityCanonical, AuthorityAssembled]
      truthStatus = truthContractStatusForAuthority authority assemblyPath
      responseSurfaceKind = responseSurfaceKindFor authority truthStatus
  bad (assemblyPath == RussianCompatShimRoute && authority /= AuthorityShim)
      "executed_outcome_invalid:russian_compat_must_be_shim"
  bad (assemblyPath == GuardRecoveryRoute && transitionWon)
      "executed_outcome_invalid:recovery_route_cannot_win"
  bad (authority `elem` [AuthorityFallback, AuthorityShim, AuthorityDefault, AuthorityGeneratedArtifact, AuthorityLegacyIncomplete, AuthorityRecovery] && transitionWon)
      "executed_outcome_invalid:non_authoritative_route_cannot_win"
  pure ExecutedTurnOutcome
    { etoFamily = family
    , etoForce = force
    , etoAuthorityClass = authority
    , etoTruthContractStatus = truthStatus
    , etoResponseSurfaceKind = responseSurfaceKind
    , etoContractProvenance = contractProv
    , etoSurfaceProvenance = surfaceProv
    , etoAssemblyPath = assemblyPath
    , etoArtifactManifest = manifest
    , etoTransitionWon = transitionWon
    }

truthContractStatusForAuthority :: AuthorityClass -> AssemblyPath -> TruthContractStatus
truthContractStatusForAuthority authority assemblyPath =
  case (authority, assemblyPath) of
    (AuthorityCanonical, _) -> CanonicalSurfacePreserved
    (AuthorityAssembled, _) -> AssembledSurfacePreserved
    (AuthorityRecovery, _) -> NonExpansiveRecoverySurface
    (AuthorityFallback, _) -> ExplicitFallbackSurface
    (AuthorityShim, _) -> CompatibilityShimSurface
    (AuthorityDefault, _) -> DefaultedSurface
    (AuthorityGeneratedArtifact, _) -> GeneratedArtifactSurface
    (AuthorityLegacyIncomplete, _) -> LegacyIncompleteSurface

responseSurfaceKindFor :: AuthorityClass -> TruthContractStatus -> ResponseSurfaceKind
responseSurfaceKindFor authority truthStatus =
  case authority of
    AuthorityCanonical -> SurfaceAuthoritative
    AuthorityAssembled -> SurfaceAdvisory
    AuthorityRecovery -> SurfaceDegraded
    AuthorityFallback -> SurfaceFallback
    AuthorityShim -> SurfaceDegraded
    AuthorityDefault -> SurfaceAdvisory
    AuthorityGeneratedArtifact -> SurfaceObservationalOnly
    AuthorityLegacyIncomplete -> SurfaceObservationalOnly

data ContractProvenance
  = BuiltClaim | FallbackRoute | RecoveryRoute
  | NixGuarded | OperatorMapping | AssembledClaim
  | ShimRoute | DefaultRoute | GeneratedArtifactRoute
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData)
instance ToJSON ContractProvenance where toJSON = genericToJSON defaultOptions
instance FromJSON ContractProvenance where parseJSON = genericParseJSON defaultOptions

data SurfaceProvenance
  = FromDB | FromFallback | FromRecovery
  | FromNixGuard | FromOperator | FromHardFallback
  | FromShim | FromDefault | FromGeneratedArtifact
  deriving stock (Eq, Ord, Show, Read, Generic, Bounded, Enum)
  deriving anyclass (NFData)
instance ToJSON SurfaceProvenance where toJSON = genericToJSON defaultOptions
instance FromJSON SurfaceProvenance where parseJSON = genericParseJSON defaultOptions

data LiveRenderTelemetry = LiveRenderTelemetry
  { lrtEmbeddingMs :: !Double
  , lrtLogicMs :: !Double
  , lrtNixCheckMs :: !Double
  , lrtRenderMs :: !Double
  , lrtSaveMs :: !Double
  , lrtTotalMs :: !Double
  , lrtSurfaceRoute :: !SurfaceProvenance
  , lrtGuardStatus :: !NixGuardStatus
  , lrtApiHealthy :: !Bool
  , lrtFamily :: !CanonicalMoveFamily
  , lrtTopic :: !Text
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)
instance ToJSON LiveRenderTelemetry where toJSON = genericToJSON defaultOptions
instance FromJSON LiveRenderTelemetry where parseJSON = genericParseJSON defaultOptions

data ResonanceBand
  = ResonanceLow | ResonanceMed | ResonanceHigh
  deriving stock (Show, Read, Eq, Ord, Enum, Bounded, Generic)
  deriving anyclass (NFData)
instance ToJSON ResonanceBand where toJSON = genericToJSON defaultOptions
instance FromJSON ResonanceBand where parseJSON = genericParseJSON defaultOptions

data DepthBand
  = DepthShallow | DepthMech | DepthPattern | DepthAxiom
  deriving stock (Show, Read, Eq, Ord, Enum, Bounded, Generic)
  deriving anyclass (NFData)
instance ToJSON DepthBand where toJSON = genericToJSON defaultOptions
instance FromJSON DepthBand where parseJSON = genericParseJSON defaultOptions

data DensityBand
  = DensityLow | DensityMed | DensityHigh
  deriving stock (Show, Read, Eq, Ord, Enum, Bounded, Generic)
  deriving anyclass (NFData)
instance ToJSON DensityBand where toJSON = genericToJSON defaultOptions
instance FromJSON DensityBand where parseJSON = genericParseJSON defaultOptions

data PressureBand = PressNone | PressLight | PressHeavy
  deriving stock (Show, Read, Eq, Ord, Enum, Bounded, Generic)
  deriving anyclass (NFData)
instance ToJSON PressureBand where toJSON = genericToJSON defaultOptions
instance FromJSON PressureBand where parseJSON = genericParseJSON defaultOptions

data MeaningState = MeaningState
  { msResonance :: !ResonanceBand
  , msPressure  :: !PressureBand
  , msDepth     :: !DepthBand
  } deriving stock (Show, Read, Eq, Ord, Generic)
  deriving anyclass (NFData)
instance ToJSON MeaningState where toJSON = genericToJSON defaultOptions
instance FromJSON MeaningState where parseJSON = genericParseJSON defaultOptions

type MeaningStateId = String

data ResponseDepth
  = ShallowResp | ModerateResp | DeepResp
  deriving stock (Show, Read, Eq, Ord, Enum, Bounded, Generic)
  deriving anyclass (NFData)
instance ToJSON ResponseDepth where toJSON = genericToJSON defaultOptions
instance FromJSON ResponseDepth where parseJSON = genericParseJSON defaultOptions

data ResponseStance
  = HoldStance | OpenStance | RedirectStance | AcknowledgeStance
  deriving stock (Show, Read, Eq, Ord, Enum, Bounded, Generic)
  deriving anyclass (NFData)
instance ToJSON ResponseStance where toJSON = genericToJSON defaultOptions
instance FromJSON ResponseStance where parseJSON = genericParseJSON defaultOptions

data ConvMove
  = CounterMove | ReframeMove | QuestionMove | ValidateMove | SilenceMove
  deriving stock (Show, Read, Eq, Ord, Enum, Bounded, Generic)
  deriving anyclass (NFData)
instance ToJSON ConvMove where toJSON = genericToJSON defaultOptions
instance FromJSON ConvMove where parseJSON = genericParseJSON defaultOptions

data ResponseStrategy = ResponseStrategy
  { rsDepth    :: !ResponseDepth
  , rsStance   :: !ResponseStance
  , rsMove     :: !ConvMove
  , rsDensityT :: !DensityBand
  } deriving stock (Show, Read, Eq, Generic)
  deriving anyclass (NFData)
instance ToJSON ResponseStrategy where toJSON = genericToJSON defaultOptions
instance FromJSON ResponseStrategy where parseJSON = genericParseJSON defaultOptions

data MeaningEdge = MeaningEdge
  { meFromId     :: !MeaningStateId
  , meToId       :: !MeaningStateId
  , meFrom       :: !MeaningState
  , meTo         :: !MeaningState
  , meStrategy   :: !ResponseStrategy
  , meCount      :: !Int
  , meWins       :: !Int
  , meDreamBias  :: !Double
  , meLastRewiredAt :: !(Maybe UTCTime)
  } deriving stock (Show, Read, Eq, Generic)
  deriving anyclass (NFData)
instance ToJSON MeaningEdge where toJSON = genericToJSON defaultOptions
instance FromJSON MeaningEdge where parseJSON = genericParseJSON defaultOptions

data MeaningGraph = MeaningGraph
  { mgEdges     :: ![MeaningEdge]
  , mgTurnCount :: !Int
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)
instance ToJSON MeaningGraph where toJSON = genericToJSON defaultOptions
instance FromJSON MeaningGraph where parseJSON = genericParseJSON defaultOptions

emptyMeaningGraph :: MeaningGraph
emptyMeaningGraph = MeaningGraph [] 0

data GeodesicPlan
  = DirectJump
  | BridgedJump [Text]
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data KernelPulse = KernelPulse
  { kpActive :: !Bool
  , kpCoherence :: !Double
  , kpValence :: !Double
  , kpAgencySignal :: !Double
  , kpLastUpdate :: !Int
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)
instance ToJSON KernelPulse where toJSON = genericToJSON defaultOptions
instance FromJSON KernelPulse where parseJSON = genericParseJSON defaultOptions

emptyKernelPulse :: KernelPulse
emptyKernelPulse = KernelPulse False kernelPulseCoherenceDefault 0.0 kernelPulseAgencySignalDefault 0

data ConstitutionalThresholds = ConstitutionalThresholds
  { ctAgencyMin :: !Double
  , ctTensionMax :: !Double
  , ctAmbiguityPenalty :: !Double
  , ctShadowDivergencePenalty :: !Double
  , ctLocalRecoveryThreshold :: !Double
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)
instance ToJSON ConstitutionalThresholds where
  toJSON ct =
    object
      [ "ctAgencyMin" .= ctAgencyMin ct
      , "ctTensionMax" .= ctTensionMax ct
      , "ctAmbiguityPenalty" .= ctAmbiguityPenalty ct
      , "ctShadowDivergencePenalty" .= ctShadowDivergencePenalty ct
      , "ctLocalRecoveryThreshold" .= ctLocalRecoveryThreshold ct
      ]

instance FromJSON ConstitutionalThresholds where
  parseJSON = withObject "ConstitutionalThresholds" $ \obj -> do
    localRecoveryThreshold <-
      obj .:? "ctLocalRecoveryThreshold"
        >>= maybe
          (obj .:? "ctLlmFallbackThreshold")
          (pure . Just)
    ConstitutionalThresholds
      <$> obj .: "ctAgencyMin"
      <*> obj .: "ctTensionMax"
      <*> obj .: "ctAmbiguityPenalty"
      <*> obj .: "ctShadowDivergencePenalty"
      <*> pure (maybe constitutionalLocalRecoveryThresholdDefault id localRecoveryThreshold)

emptyConstitutionalThresholds :: ConstitutionalThresholds
emptyConstitutionalThresholds =
  ConstitutionalThresholds
    constitutionalAgencyMinDefault
    constitutionalTensionMaxDefault
    constitutionalAmbiguityPenaltyDefault
    constitutionalShadowDivergencePenaltyDefault
    constitutionalLocalRecoveryThresholdDefault

data ObservabilityState = ObservabilityState
  { obsNixCache :: !(Map Text NixGuardStatus)
  , obsLastPersistedTurn :: !Int
  , obsTelemetry :: !LiveRenderTelemetry
  , obsEmbeddingApiHealthy :: !Bool
  , obsLastLegitimacyScore :: !Double
  , obsConstitutionalThresholds :: !ConstitutionalThresholds
  , obsEvidenceBonds :: ![LogicalBond]
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)
instance ToJSON ObservabilityState where toJSON = genericToJSON defaultOptions
instance FromJSON ObservabilityState where parseJSON = genericParseJSON defaultOptions

emptyObservabilityState :: ObservabilityState
emptyObservabilityState = ObservabilityState
  { obsNixCache = M.empty
  , obsLastPersistedTurn = 0
  , obsTelemetry = LiveRenderTelemetry 0 0 0 0 0 0 FromDB Allowed True CMGround ""
  , obsEmbeddingApiHealthy = True
  , obsLastLegitimacyScore = 1.0
  , obsConstitutionalThresholds = emptyConstitutionalThresholds
  , obsEvidenceBonds = []
  }
