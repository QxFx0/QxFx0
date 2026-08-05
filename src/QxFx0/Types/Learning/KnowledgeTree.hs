{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Learning.KnowledgeTree
  ( KnowledgeSource(..)
  , KnowledgeFruit(..)
  , Branch(..)
  , KnowledgeTree(..)
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON(..), ToJSON(..), object, withObject, (.:), (.:?), (.!=), (.=))
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Text (Text)
import GHC.Generics (Generic)

data KnowledgeSource = SourceInternal | SourceLLM | SourceHuman | SourceScript
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, FromJSON, ToJSON)

data KnowledgeFruit = KnowledgeFruit
  { kfProposition     :: !Text
  , kfWord            :: !Text
  , kfSource          :: !KnowledgeSource
  , kfValidated       :: !Bool
  , kfConatusDelta    :: !Double
  , kfPredictiveDelta :: !Double
  , kfGraftedTurn     :: !(Maybe Int)
  , kfObservedTurn    :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON KnowledgeFruit where
  toJSON f = object
    [ "proposition" .= kfProposition f
    , "word" .= kfWord f
    , "source" .= kfSource f
    , "validated" .= kfValidated f
    , "conatusDelta" .= kfConatusDelta f
    , "predictiveDelta" .= kfPredictiveDelta f
    , "graftedTurn" .= kfGraftedTurn f
    , "observedTurn" .= kfObservedTurn f
    ]

instance FromJSON KnowledgeFruit where
  parseJSON = withObject "KnowledgeFruit" $ \o -> KnowledgeFruit
    <$> o .: "proposition"
    <*> o .:? "word" .!= ""
    <*> o .: "source"
    <*> o .:? "validated" .!= False
    <*> (clampFruitDelta (-0.35) 0.40 <$> o .:? "conatusDelta" .!= 0.0)
    <*> (clampFruitDelta (-0.40) 0.50 <$> o .:? "predictiveDelta" .!= 0.0)
    <*> o .:? "graftedTurn" .!= Nothing
    <*> o .:? "observedTurn" .!= 0

clampFruitDelta :: Double -> Double -> Double -> Double
clampFruitDelta lo hi x
  | isNaN x || isInfinite x = 0.0
  | otherwise = max lo (min hi x)

data Branch = Branch
  { brRule        :: !Text
  , brFruits      :: ![KnowledgeFruit]
  , brHealth      :: !Double
  , brCreatedTurn :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON Branch where
  toJSON b = object
    [ "rule" .= brRule b
    , "fruits" .= brFruits b
    , "health" .= brHealth b
    , "createdTurn" .= brCreatedTurn b
    ]

instance FromJSON Branch where
  parseJSON = withObject "Branch" $ \o -> Branch
    <$> o .: "rule"
    <*> o .:? "fruits" .!= []
    <*> o .:? "health" .!= 0.0
    <*> o .:? "createdTurn" .!= 0

data KnowledgeTree = KnowledgeTree
  { ktRootMode         :: !Text
  , ktRootTrigger      :: !Text
  , ktBranches         :: !(Map Text [Branch])
  , ktQuarantine       :: ![KnowledgeFruit]
  , ktPrunedCount      :: !Int
  , ktGraftedCount     :: !Int
  , ktQuarantinedCount :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData)

instance ToJSON KnowledgeTree where
  toJSON t = object
    [ "rootMode" .= ktRootMode t
    , "rootTrigger" .= ktRootTrigger t
    , "branches" .= ktBranches t
    , "quarantine" .= ktQuarantine t
    , "prunedCount" .= ktPrunedCount t
    , "graftedCount" .= ktGraftedCount t
    , "quarantinedCount" .= ktQuarantinedCount t
    ]

instance FromJSON KnowledgeTree where
  parseJSON = withObject "KnowledgeTree" $ \o -> KnowledgeTree
    <$> o .:? "rootMode" .!= ""
    <*> o .:? "rootTrigger" .!= ""
    <*> o .:? "branches" .!= M.empty
    <*> o .:? "quarantine" .!= []
    <*> o .:? "prunedCount" .!= 0
    <*> o .:? "graftedCount" .!= 0
    <*> o .:? "quarantinedCount" .!= 0
