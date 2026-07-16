{-# LANGUAGE OverloadedStrings #-}

-- | Curated seed ontology for general philosophy and ethics in Russian.
--
-- These edges are treated as ground-truth anchors for logical verification
-- during autonomous learning. They are loaded with 'ProvenanceCurated' and
-- 'NamespaceGlobal' so they outrank runtime LLM discoveries and survive
-- across sessions.
module QxFx0.Semantic.Ontology.Philosophy
  ( philosophySeedEdges
  , philosophySeedNetwork
  , topicDomain
  , topicTemporalScope
  ) where

import qualified Data.Map.Strict as M
import qualified Data.Set as S
import Data.Text (Text)

import QxFx0.Semantic.Content.AtomStore (RelationType(..))
import QxFx0.Semantic.Network.Types
  ( DomainTag(..)
  , EdgeNamespace(..)
  , EdgeProvenance(..)
  , EdgeSource(..)
  , SemanticEdge(..)
  , SemanticNetwork(..)
  , TemporalScope(..)
  , emptySemanticNetwork
  )

-- | Static mapping from well-known philosophical concepts to their
-- primary domain. Used both for seed edges and for validating LLM
-- discoveries (cross-domain edges can be admitted but with lower weight).
topicDomain :: Text -> DomainTag
topicDomain t =
  case t of
    "свобода"          -> DomainPoliticalPhilosophy
    "ответственность"  -> DomainEthics
    "справедливость"   -> DomainEthics
    "добро"            -> DomainEthics
    "зло"              -> DomainEthics
    "истина"           -> DomainEpistemology
    "красота"          -> DomainAesthetics
    "долг"             -> DomainEthics
    "совесть"          -> DomainEthics
    "честь"            -> DomainEthics
    "достоинство"      -> DomainEthics
    "власть"           -> DomainPoliticalPhilosophy
    "право"            -> DomainPoliticalPhilosophy
    "любовь"           -> DomainAnthropology
    "доверие"          -> DomainEthics
    "дружба"           -> DomainAnthropology
    "бытие"            -> DomainOntology
    "ничто"            -> DomainOntology
    "смысл"            -> DomainOntology
    "сознание"         -> DomainPhilosophyOfMind
    "воля"             -> DomainPhilosophyOfMind
    "разум"            -> DomainPhilosophyOfMind
    "время"            -> DomainOntology
    "смерть"           -> DomainOntology
    "язык"             -> DomainMethodology
    "правда"           -> DomainEpistemology
    _                  -> DomainGeneral

-- | Temporal scope for concepts. Most abstract concepts are treated as
-- transhistorical; historically situated concepts can be added later.
topicTemporalScope :: Text -> TemporalScope
topicTemporalScope _ = TranshistoricalPeriod

-- | Curated seed edges. Each edge carries a logical relation type, a
-- domain tag, and a temporal scope. These form the "pre-correct scenario"
-- against which runtime LLM discoveries are verified.
philosophySeedEdges :: [SemanticEdge]
philosophySeedEdges =
  [ seed "свобода" "ответственность" RelRequires DomainPoliticalPhilosophy
  , seed "свобода" "воля" RelPresupposes DomainPoliticalPhilosophy
  , seed "свобода" "долг" RelLimitedBy DomainEthics
  , seed "ответственность" "долг" RelRequires DomainEthics
  , seed "ответственность" "справедливость" RelPointsTo DomainEthics
  , seed "справедливость" "добро" RelIsA DomainEthics
  , seed "справедливость" "право" RelDetermines DomainPoliticalPhilosophy
  , seed "добро" "зло" RelContrastsWith DomainEthics
  , seed "истина" "проверка" RelVerifiedBy DomainEpistemology
  , seed "истина" "знание" RelDetermines DomainEpistemology
  , seed "красота" "истина" RelRelatedTo DomainAesthetics
  , seed "красота" "добро" RelRelatedTo DomainAesthetics
  , seed "долг" "совесть" RelRequires DomainEthics
  , seed "совесть" "истина" RelPointsTo DomainEthics
  , seed "честь" "достоинство" RelPreserves DomainEthics
  , seed "власть" "ответственность" RelRequires DomainPoliticalPhilosophy
  , seed "право" "справедливость" RelClaims DomainPoliticalPhilosophy
  , seed "любовь" "доверие" RelRequires DomainAnthropology
  , seed "любовь" "свобода" RelPresupposes DomainAnthropology
  , seed "доверие" "дружба" RelNecessaryFor DomainAnthropology
  , seed "дружба" "доверие" RelRequires DomainAnthropology
  , seed "бытие" "сознание" RelIncludes DomainOntology
  , seed "бытие" "время" RelIncludes DomainOntology
  , seed "смысл" "бытие" RelDependsOn DomainOntology
  , seed "смысл" "язык" RelExpresses DomainMethodology
  , seed "сознание" "разум" RelIncludes DomainPhilosophyOfMind
  , seed "сознание" "ответственность" RelSupports DomainPhilosophyOfMind
  , seed "воля" "свобода" RelSupports DomainPhilosophyOfMind
  , seed "разум" "истина" RelPointsTo DomainEpistemology
  ]

seed :: Text -> Text -> RelationType -> DomainTag -> SemanticEdge
seed from to rt dom = SemanticEdge
  { seFrom          = from
  , seTo            = to
  , seWeight        = 0.9
  , seCoOccurrence  = 1
  , seSource        = ExplicitEdge
  , seRelationType  = Just rt
  , seDomain        = Just dom
  , seTemporalScope = Just TranshistoricalPeriod
  , seVerb          = Nothing
  , seRationale     = Just "curated seed ontology"
  , seCounter       = Nothing
  , seSynthesis     = Nothing
  , seConfidence    = 0.95
  , seProvenance    = ProvenanceCurated
  , seNamespace     = Just NamespaceGlobal
  , seLineage       = Nothing
  }

-- | Seed network built from curated philosophy edges.
philosophySeedNetwork :: SemanticNetwork
philosophySeedNetwork =
  let edges = M.fromList [((seFrom e, seTo e), e) | e <- philosophySeedEdges]
      nodes = S.fromList (concatMap (\e -> [seFrom e, seTo e]) philosophySeedEdges)
  in emptySemanticNetwork
       { snNodes = nodes
       , snEdges = edges
       }
