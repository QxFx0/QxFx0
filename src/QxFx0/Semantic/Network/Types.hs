{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Semantic.Network.Types
  ( SemanticEdge(..)
  , SemanticNetwork(..)
  , emptySemanticNetwork
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON, ToJSON)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Set (Set)
import qualified Data.Set as S
import Data.Text (Text)
import GHC.Generics (Generic)

data SemanticEdge = SemanticEdge
  { seFrom         :: !Text
  , seTo           :: !Text
  , seWeight       :: !Double
  , seCoOccurrence :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

data SemanticNetwork = SemanticNetwork
  { snNodes      :: !(Set Text)
  , snEdges      :: !(Map (Text, Text) SemanticEdge)
  , snActivation :: !(Map Text Double)
  , snDecayRate  :: !Double
  , snMaxHops    :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

emptySemanticNetwork :: SemanticNetwork
emptySemanticNetwork = SemanticNetwork
  { snNodes = S.empty
  , snEdges = M.empty
  , snActivation = M.empty
  , snDecayRate = 0.5
  , snMaxHops = 3
  }
