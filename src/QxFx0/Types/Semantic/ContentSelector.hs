{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Semantic.ContentSelector
  ( ContentSelector(..)
  , SelectedPredicate(..)
  , SelectorDiagnostic(..)

    -- * Index types
  , TopicPredicateIndex
  , AtomTopicIndex
  , buildTopicPredicateIndex
  , buildAtomTopicIndex

    -- * Score cache types
  , ScoreCacheKey(..)
  , ScoreCache
  , emptyScoreCache

    -- * Extended selector state
  , ContentSelectorState(..)
  , emptyContentSelectorState
  , initContentSelectorState
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, FromJSONKey, ToJSON, ToJSONKey)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Set (Set)
import qualified Data.Set as S
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

import QxFx0.Types.Semantic.Content (SemanticPredicate)
import QxFx0.Types.Semantic.Ontology (Ontology)
import QxFx0.Types.Semantic.Ontology.Dynamic
  ( OntologyLearningConfig, DynamicOntologyState, defaultLearningConfig, emptyDynamicOntologyState )
import QxFx0.Types.Semantic.Space (SemanticSpace(..))

data ContentSelector = ContentSelector
  { csSpace           :: !SemanticSpace
  , csTopicAtoms      :: !(Map Text (Set Text))
  , csTopicPredicates :: !(Map Text [SemanticPredicate])
  , csLemmaMap        :: !(Map Text Text)
  , csOntology        :: !(Maybe Ontology)
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

data SelectedPredicate = SelectedPredicate
  { spPredicateId :: Text
  , spScore       :: Double
  , spPredicates  :: [SemanticPredicate]
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

data SelectorDiagnostic = SelectorDiagnostic
  { sdQueryTopic             :: !Text
  , sdCandidateTopic         :: !Text
  , sdPredicateSurface       :: !(Maybe Text)
  , sdScore                  :: !(Maybe Double)
  , sdSelected               :: !Bool
  , sdReason                 :: !Text
  , sdTopicRelevance         :: !(Maybe Double)
  , sdFieldAffinity          :: !(Maybe Double)
  , sdFieldModulation        :: !(Maybe Double)
  , sdActivationBonus        :: !(Maybe Double)
  , sdOntologyContribution   :: !(Maybe Double)
  , sdOovAtoms               :: !(Maybe [Text])
  , sdMarginalSemanticGain   :: !(Maybe Double)
  , sdPolicyVersion          :: !(Maybe Text)
  , sdMathVersion            :: !(Maybe Text)
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- ==========================================================================
-- Index types
-- ==========================================================================

-- | Index for fast predicate lookup by topic: topic -> [(predicate_id, predicate)]
type TopicPredicateIndex = Map Text [(Text, SemanticPredicate)]

-- | Reverse index for atom lookup: atom -> [topics containing this atom]
type AtomTopicIndex = Map Text [Text]

-- | Build an index for fast predicate lookup by topic
buildTopicPredicateIndex :: ContentSelector -> TopicPredicateIndex
buildTopicPredicateIndex cs =
  M.fromList [ (topic, zip [T.pack (show i) | i <- [0..]] preds)
             | (topic, preds) <- M.toList (csTopicPredicates cs) ]

-- | Build a reverse index: atom -> [topics that contain this atom]
buildAtomTopicIndex :: ContentSelector -> AtomTopicIndex
buildAtomTopicIndex cs =
  let atomTopicPairs = [ (atom, topic)
                       | (topic, atoms) <- M.toList (csTopicAtoms cs)
                       , atom <- S.toList atoms ]
  in M.fromListWith (++) [ (atom, [topic]) | (atom, topic) <- atomTopicPairs ]

-- ==========================================================================
-- Score cache types
-- ==========================================================================

-- | Cache key for predicate scoring
-- Uses topic + predicate surface as the key for simplicity
-- In production, could include field signature for more precision
data ScoreCacheKey = ScoreCacheKey
  { sckTopic :: !Text
  , sckPredicate :: !Text  -- spRu predicate text
  } deriving stock (Eq, Ord, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON, ToJSONKey, FromJSONKey)

-- | Simple cache type: maps (topic, predicate) to computed score
type ScoreCache = Map ScoreCacheKey Double

-- | Empty cache
emptyScoreCache :: ScoreCache
emptyScoreCache = M.empty

-- ==========================================================================
-- Extended selector state
-- ==========================================================================

-- | Extended state for ContentSelector with optimization data
data ContentSelectorState = ContentSelectorState
  { cssContentSelector :: !ContentSelector
  , cssPredicateIndex :: !TopicPredicateIndex
  , cssAtomIndex :: !AtomTopicIndex
  , cssScoreCache :: !ScoreCache
  , cssLearningConfig :: !OntologyLearningConfig
  , cssLearningState :: !DynamicOntologyState
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

-- | Initialize ContentSelectorState from a base ContentSelector
initContentSelectorState :: ContentSelector -> ContentSelectorState
initContentSelectorState cs = ContentSelectorState
  { cssContentSelector = cs
  , cssPredicateIndex = buildTopicPredicateIndex cs
  , cssAtomIndex = buildAtomTopicIndex cs
  , cssScoreCache = emptyScoreCache
  , cssLearningConfig = defaultLearningConfig
  , cssLearningState = emptyDynamicOntologyState
  }

-- | Empty ContentSelectorState
emptyContentSelectorState :: ContentSelectorState
emptyContentSelectorState = initContentSelectorState emptyContentSelector
  where
    emptyContentSelector = ContentSelector
      { csSpace           = SemanticSpace 0 M.empty M.empty M.empty M.empty
      , csTopicAtoms      = M.empty
      , csTopicPredicates = M.empty
      , csLemmaMap        = M.empty
      , csOntology        = Nothing
      }