{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Semantic.Network
  ( SemanticEdge(..)
  , EdgeSource(..)
  , SemanticNetwork(..)
  , ActivationArtifact(..)
  , ActivationStep(..)
  , EdgeProvenance(..)
  , DomainTag(..)
  , EdgeNamespace(..)
  , EdgeRef
  , TemporalScope(..)
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON(..), ToJSON(..), object, withObject, (.:), (.:?), (.!=), (.=))
import Data.Map.Strict (Map)
import Data.Sequence (Seq)
import Data.Set (Set)
import Data.Text (Text)
import GHC.Generics (Generic)

import QxFx0.Types.Semantic.AtomGraph (RelationType)

data DomainTag
  = DomainOntology | DomainEthics | DomainAesthetics | DomainEpistemology
  | DomainPoliticalPhilosophy | DomainAnthropology | DomainMethodology
  | DomainLogic | DomainSocialPhilosophy | DomainPhilosophyOfMind
  | DomainArtHistory | DomainGeneral
  deriving stock (Eq, Show, Ord, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data EdgeNamespace = NamespaceSessionLocal | NamespaceUserLocal | NamespaceGlobal
  deriving stock (Eq, Show, Ord, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

type EdgeRef = (Text, Text, RelationType, EdgeNamespace)

data TemporalScope
  = TemporalPoint | TemporalInterval | TemporalEternal | AncientPeriod
  | ClassicalPeriod | MedievalPeriod | RenaissancePeriod | EarlyModernPeriod
  | ModernPeriod | ContemporaryPeriod | TranshistoricalPeriod | SpecificEra Text
  deriving stock (Eq, Show, Ord, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data EdgeProvenance
  = ProvenanceCurated | ProvenanceCorpus | ProvenanceSubstrate | ProvenanceIngested
  | ProvenanceSelfPlay | ProvenanceDialogueFeedback | ProvenanceRuntimeLLM
  | ProvenanceHumanCorrection | ProvenanceDerived
  deriving stock (Eq, Show, Ord, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data EdgeSource = ExplicitEdge | SubstrateEdge
  deriving stock (Eq, Show, Ord, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data SemanticEdge = SemanticEdge
  { seFrom          :: !Text
  , seTo            :: !Text
  , seWeight        :: !Double
  , seCoOccurrence  :: !Int
  , seSource        :: !EdgeSource
  , seRelationType  :: !(Maybe RelationType)
  , seVerb          :: !(Maybe Text)
  , seRationale     :: !(Maybe Text)
  , seCounter       :: !(Maybe Text)
  , seSynthesis     :: !(Maybe Text)
  , seConfidence    :: !Double
  , seProvenance    :: !EdgeProvenance
  , seDomain        :: !(Maybe DomainTag)
  , seTemporalScope :: !(Maybe TemporalScope)
  , seNamespace     :: !(Maybe EdgeNamespace)
  , seLineage       :: !(Maybe [EdgeRef])
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON SemanticEdge where
  toJSON e = object
    [ "seFrom" .= seFrom e, "seTo" .= seTo e, "seWeight" .= seWeight e
    , "seCoOccurrence" .= seCoOccurrence e, "seSource" .= seSource e
    , "relation_type" .= seRelationType e, "verb" .= seVerb e
    , "rationale" .= seRationale e, "counter" .= seCounter e
    , "synthesis" .= seSynthesis e, "confidence" .= seConfidence e
    , "provenance" .= seProvenance e, "seDomain" .= seDomain e
    , "seTemporalScope" .= seTemporalScope e, "seNamespace" .= seNamespace e
    , "seLineage" .= seLineage e
    ]

instance FromJSON SemanticEdge where
  parseJSON = withObject "SemanticEdge" $ \o -> SemanticEdge
    <$> o .: "seFrom" <*> o .: "seTo" <*> o .: "seWeight"
    <*> o .: "seCoOccurrence" <*> o .: "seSource"
    <*> o .:? "relation_type" <*> o .:? "verb" <*> o .:? "rationale"
    <*> o .:? "counter" <*> o .:? "synthesis"
    <*> o .:? "confidence" .!= 1.0
    <*> o .:? "provenance" .!= ProvenanceCurated
    <*> o .:? "seDomain" <*> o .:? "seTemporalScope"
    <*> o .:? "seNamespace" <*> o .:? "seLineage"

data SemanticNetwork = SemanticNetwork
  { snNodes         :: !(Set Text)
  , snEdges         :: !(Map (Text, Text) SemanticEdge)
  , snActivation    :: !(Map Text Double)
  , snDecayRate     :: !Double
  , snMaxHops       :: !Int
  , snActivationLog :: !(Seq ActivationStep)
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- | Turn-local spreading activation used by selection, trace, and feedback.
-- The graph remains separately owned by 'SemanticNetwork'; this artifact only
-- carries the exact activation result and the edges traversed to produce it.
data ActivationArtifact = ActivationArtifact
  { aaSeedTopics :: ![Text]
  , aaActivation :: !(Map Text Double)
  , aaSteps :: !(Seq ActivationStep)
  , aaUsedEdges :: ![SemanticEdge]
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

data ActivationStep = ActivationStep
  { asNode   :: !Text
  , asSource :: !EdgeSource
  , asVia    :: !Text
  , asHop    :: !Int
  , asWeight :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)
