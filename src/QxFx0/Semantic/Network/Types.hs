{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Semantic.Network.Types
  ( SemanticEdge(..)
  , EdgeSource(..)
  , SemanticNetwork(..)
  , ActivationStep(..)
  , EdgeProvenance(..)
  , semanticEdge
  , emptySemanticNetwork
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson
  ( FromJSON(parseJSON)
  , ToJSON(toJSON)
  , object
  , withObject
  , (.!=)
  , (.:)
  , (.:?)
  , (.=)
  )
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Sequence (Seq)
import qualified Data.Sequence as Seq
import Data.Set (Set)
import qualified Data.Set as S
import Data.Text (Text)
import GHC.Generics (Generic)

import QxFx0.Semantic.Content.AtomStore (RelationType)

-- | Provenance of a semantic edge, distinguishing curated, corpus,
-- substrate, and externally-ingested origins.
data EdgeProvenance
  = ProvenanceCurated
  | ProvenanceCorpus
  | ProvenanceSubstrate
  | ProvenanceIngested
  deriving stock (Eq, Show, Ord, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

-- | Source of an edge in the SemanticNetwork.
data EdgeSource
  = ExplicitEdge
    -- ^ Edge from seedFromCorpus (definitionCorpus predicates)
  | SubstrateEdge
    -- ^ Edge from brain_kb co-occurrence
  deriving stock (Eq, Show, Ord, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data SemanticEdge = SemanticEdge
  { seFrom         :: !Text
  , seTo           :: !Text
  , seWeight       :: !Double
  , seCoOccurrence :: !Int
  , seSource       :: !EdgeSource
  , seRelationType :: !(Maybe RelationType)
  , seVerb         :: !(Maybe Text)
  , seRationale    :: !(Maybe Text)
  , seCounter      :: !(Maybe Text)
  , seSynthesis    :: !(Maybe Text)
  , seConfidence   :: !Double
  , seProvenance   :: !EdgeProvenance
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON SemanticEdge where
  toJSON e = object
    [ "seFrom"         .= seFrom e
    , "seTo"           .= seTo e
    , "seWeight"       .= seWeight e
    , "seCoOccurrence" .= seCoOccurrence e
    , "seSource"       .= seSource e
    , "relation_type"  .= seRelationType e
    , "verb"           .= seVerb e
    , "rationale"      .= seRationale e
    , "counter"        .= seCounter e
    , "synthesis"      .= seSynthesis e
    , "confidence"     .= seConfidence e
    , "provenance"     .= seProvenance e
    ]

instance FromJSON SemanticEdge where
  parseJSON = withObject "SemanticEdge" $ \o ->
    SemanticEdge
      <$> o .:  "seFrom"
      <*> o .:  "seTo"
      <*> o .:  "seWeight"
      <*> o .:  "seCoOccurrence"
      <*> o .:  "seSource"
      <*> o .:? "relation_type"
      <*> o .:? "verb"
      <*> o .:? "rationale"
      <*> o .:? "counter"
      <*> o .:? "synthesis"
      <*> o .:? "confidence" .!= 1.0
      <*> o .:? "provenance" .!= ProvenanceCurated

-- | Convenience constructor for edges that do not carry rich relation
-- semantics. Optional fields are left empty, confidence is 1.0, and
-- provenance is inferred from the edge source.
semanticEdge :: Text -> Text -> Double -> Int -> EdgeSource -> SemanticEdge
semanticEdge from to weight cooc source =
  SemanticEdge from to weight cooc source Nothing Nothing Nothing Nothing Nothing 1.0 provenance
  where
    provenance = case source of
      ExplicitEdge  -> ProvenanceCorpus
      SubstrateEdge -> ProvenanceSubstrate

data SemanticNetwork = SemanticNetwork
  { snNodes        :: !(Set Text)
  , snEdges        :: !(Map (Text, Text) SemanticEdge)
  , snActivation   :: !(Map Text Double)
  , snDecayRate    :: !Double
  , snMaxHops      :: !Int
  , snActivationLog :: !(Seq ActivationStep)
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- | A single step in the spreading activation trace.
-- Records which node was activated, through which edge source
-- (explicit or substrate), from which node, at which hop,
-- and with what weight.
data ActivationStep = ActivationStep
  { asNode   :: !Text
  , asSource :: !EdgeSource
  , asVia    :: !Text
  , asHop    :: !Int
  , asWeight :: !Double
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

emptySemanticNetwork :: SemanticNetwork
emptySemanticNetwork = SemanticNetwork
  { snNodes = S.empty
  , snEdges = M.empty
  , snActivation = M.empty
  , snDecayRate = 0.5
  , snMaxHops = 3
  , snActivationLog = Seq.empty
  }
