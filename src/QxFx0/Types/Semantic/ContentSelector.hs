{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Types.Semantic.ContentSelector
  ( ContentSelector(..)
  , SelectedPredicate(..)
  , SelectorDiagnostic(..)
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import Data.Map.Strict (Map)
import Data.Set (Set)
import Data.Text (Text)
import GHC.Generics (Generic)

import QxFx0.Types.Semantic.Content (SemanticPredicate)
import QxFx0.Types.Semantic.Ontology (Ontology)
import QxFx0.Types.Semantic.Space (SemanticSpace)

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
