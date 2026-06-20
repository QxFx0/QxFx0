{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Semantic.Network.Types
  ( SemanticEdge(..)
  , EdgeSource(..)
  , SemanticNetwork(..)
  , ActivationStep(..)
  , emptySemanticNetwork
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Sequence (Seq)
import qualified Data.Sequence as Seq
import Data.Set (Set)
import qualified Data.Set as S
import Data.Text (Text)
import GHC.Generics (Generic)

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
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

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
