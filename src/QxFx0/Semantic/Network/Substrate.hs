{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Semantic.Network.Substrate
Description : Substrate Network — brain_kb enrichment of SemanticNetwork edges.

Two-layer knowledge graph:
  Explicit: 30 philosophical topics, ~50 edges, weight 1.0
  Substrate: same 30 topics, ~78 edges, weight 0.3

Substrate adds edges between existing explicit topics via co-occurrence
of philosophical words in brain_kb triggers. Substrate edges never appear
in output — they only route spreading activation.
-}
module QxFx0.Semantic.Network.Substrate
  ( BrainKBEntry(..)
  , SubstrateEdgeInfo(..)
  , loadBrainKB
  , resolveBrainKBPath
  , buildSubstrateEdges
  , countSubstrateActivated
  ) where

import Control.DeepSeq (NFData)
import Data.Aeson (FromJSON(..), ToJSON(..), (.:), (.:?), (.!=), withObject)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as BL
import Data.List (foldl')
import Data.Maybe (mapMaybe)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Set (Set)
import qualified Data.Set as S
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.ByteString as BS
import GHC.Generics (Generic)
import System.Directory (doesFileExist)
import System.Environment (lookupEnv)

-- | A single brain_kb entry parsed from JSONL.
data BrainKBEntry = BrainKBEntry
  { beText     :: !Text
  , beTopics   :: ![Text]
  , beTriggers :: ![Text]
  , beLayer    :: !Text
  , beKind     :: !Text
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON)

-- | A substrate edge between two explicit topics.
data SubstrateEdgeInfo = SubstrateEdgeInfo
  { seiFrom   :: !Text
  , seiTo     :: !Text
  , seiWeight :: !Double
  , seiCooc   :: !Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (NFData, ToJSON, FromJSON)

instance FromJSON BrainKBEntry where
  parseJSON = withObject "BrainKBEntry" $ \o ->
    BrainKBEntry
      <$> o .: "text"
      <*> o .:? "topic" .!= []
      <*> o .:? "triggers" .!= []
      <*> o .:? "layer" .!= ""
      <*> o .:? "kind" .!= ""

-- | Allowed layers for substrate edges.
allowedLayers :: [Text]
allowedLayers = ["ontology", "dialogue", "metaphor", "dialog_moves", "human_signals"]

-- | Load brain_kb.jsonl from a file path. Parses JSONL (one JSON object
-- per line), not a JSON array. Returns empty list if file not found or
-- parse fails.
loadBrainKB :: FilePath -> IO [BrainKBEntry]
loadBrainKB path = do
  exists <- doesFileExist path
  if not exists
    then pure []
    else do
      content <- BS.readFile path
      let lines = filter (not . BS.null) (BS.split 10 content)
          parsed = mapMaybe parseLine lines
      pure parsed
  where
    parseLine :: BS.ByteString -> Maybe BrainKBEntry
    parseLine line =
      case Aeson.eitherDecode' (BL.fromStrict line) of
        Right entry -> Just entry
        Left _ -> Nothing

-- | Resolve brain_kb path: try QXFX0_BRAIN_KB_PATH env var, then
-- QXFX0_ROOT/brain_kb.jsonl, then relative path.
resolveBrainKBPath :: IO FilePath
resolveBrainKBPath = do
  mEnv <- lookupEnv "QXFX0_BRAIN_KB_PATH"
  case mEnv of
    Just p -> pure p
    Nothing -> do
      mRoot <- lookupEnv "QXFX0_ROOT"
      case mRoot of
        Just root -> pure (root <> "/brain_kb.jsonl")
        Nothing -> pure "brain_kb.jsonl"

-- | Build substrate edges from brain_kb entries.
-- Uses beTriggers with substring matching against explicitTopicSet.
-- Only entries with >=2 philosophical triggers in allowed layers are used.
buildSubstrateEdges :: [BrainKBEntry] -> Set Text -> [SubstrateEdgeInfo]
buildSubstrateEdges entries explicitTopicSet =
  let explicitTopicList = S.toList explicitTopicSet
      -- Filter entries: allowed layer, >=2 philosophical triggers
      filtered = filter (isRelevantEntry explicitTopicList) entries
      -- Extract pairs of philosophical triggers from each entry
      topicPairs = concatMap (extractPhilosophicalPairs explicitTopicList) filtered
      -- Count co-occurrences
      coocMap = countCooccurrences topicPairs
      -- Build edges with cooc >= 2, weight = 0.3
      edges =
        [ SubstrateEdgeInfo t1 t2 0.3 cooc
        | ((t1, t2), cooc) <- M.toList coocMap
        , cooc >= 2
        ]
  in edges

-- | Check if an entry is relevant for substrate edges.
isRelevantEntry :: [Text] -> BrainKBEntry -> Bool
isRelevantEntry explicitTopicList entry =
  beLayer entry `elem` allowedLayers
  && length (findPhilosophicalTriggers explicitTopicList (beTriggers entry)) >= 2

-- | Find philosophical triggers in a trigger list using substring matching.
findPhilosophicalTriggers :: [Text] -> [Text] -> [Text]
findPhilosophicalTriggers explicitTopicList triggers =
  filter (\t -> any (`T.isInfixOf` t) explicitTopicList) triggers

-- | Extract bidirectional pairs of philosophical triggers from an entry.
extractPhilosophicalPairs :: [Text] -> BrainKBEntry -> [((Text, Text), Int)]
extractPhilosophicalPairs explicitTopicList entry =
  let philTriggers = findPhilosophicalTriggers explicitTopicList (beTriggers entry)
      uniquePhil = S.toList (S.fromList philTriggers)
      pairs = [ (tupleSort t1 t2, 1)
              | t1 <- uniquePhil
              , t2 <- uniquePhil
              , t1 < t2
              ]
  in pairs

-- | Sort a pair of texts lexicographically.
tupleSort :: Text -> Text -> (Text, Text)
tupleSort a b = if a <= b then (a, b) else (b, a)

-- | Count co-occurrences of pairs.
countCooccurrences :: [((Text, Text), Int)] -> Map (Text, Text) Int
countCooccurrences = foldl' (\acc (pair, count) -> M.insertWith (+) pair count acc) M.empty

-- | Count how many substrate edges were used in an activation map.
-- Compares activated topics against substrate edge targets.
countSubstrateActivated :: Map (Text, Text) edge -> Set Text -> Int
countSubstrateActivated allEdges activatedTopics =
  length [ () | (_, to) <- M.keys allEdges, to `S.member` activatedTopics ]
