{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.Semantic.Network.Seed
  ( seedFromCorpus
  , useAtomGraphSeed
  , overlayConfidence
  , contentDensity
  , DensityConfig(..)
  , defaultDensityConfig
  , readDensityConfig
  , starvingTopics
  , buildTopicAtomsMap
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Set (Set)
import qualified Data.Set as S
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Sequence as Seq
import System.Environment (lookupEnv)

import QxFx0.Semantic.Content (definitionCorpus, DefinitionContent(..), SemanticPredicate(..))
import QxFx0.Semantic.Network.Types (SemanticNetwork(..), SemanticEdge(..), EdgeSource(..), semanticEdge)

-- | Overlay persisted confidence values onto a freshly built semantic
-- network.  For every edge that exists in both networks, the resulting
-- confidence is a weighted blend of the fresh and restored values capped
-- at 0.95.  Edges that only exist in the fresh network are kept as-is,
-- and all non-edge fields are taken from the fresh network.  This closes
-- the write-without-read feedback loop: the graph structure always comes
-- from the current seed/build, while learned confidence is preserved
-- across restarts.
overlayConfidence :: SemanticNetwork -> SemanticNetwork -> SemanticNetwork
overlayConfidence fresh restored =
  fresh { snEdges = M.mapWithKey overlayEdge (snEdges fresh) }
  where
    restoredEdges = snEdges restored
    overlayEdge key freshEdge =
      case M.lookup key restoredEdges of
        Nothing -> freshEdge
        Just restoredEdge ->
          let c = min 0.95 (0.3 * seConfidence freshEdge + 0.7 * seConfidence restoredEdge)
          in freshEdge { seConfidence = c }

-- | Compile-time feature flag for Variant C atom-graph seeding.
-- P0.1 makes the atom-graph seed the default.
useAtomGraphSeed :: Bool
useAtomGraphSeed = True

-- ---------------------------------------------------------------------------
-- ADR-0054 M2: Content Density Gate
-- ---------------------------------------------------------------------------

-- | Configuration for the content density gate.
--   * 'dcKappa' — target average degree per atom (default 3).
--   * 'dcThreshold' — density below which a topic is 'starving' (default 0.15).
data DensityConfig = DensityConfig
  { dcKappa     :: !Double
  , dcThreshold :: !Double
  }
  deriving stock (Eq, Show)

-- | Safe defaults: κ = 3, τ = 0.15.
defaultDensityConfig :: DensityConfig
defaultDensityConfig = DensityConfig
  { dcKappa     = 3.0
  , dcThreshold = 0.15
  }

-- | Read density config from environment.  Falls back to defaults
-- when env vars are missing or unparseable.
--   * @QXFX0_LEARNING_DENSITY_THRESHOLD@ — 'dcThreshold'.
--   * @QXFX0_LEARNING_DENSITY_KAPPA@ — 'dcKappa'.
readDensityConfig :: IO DensityConfig
readDensityConfig = do
  mT <- lookupEnv "QXFX0_LEARNING_DENSITY_THRESHOLD"
  mK <- lookupEnv "QXFX0_LEARNING_DENSITY_KAPPA"
  let dcT = dcThreshold defaultDensityConfig
      dcK = dcKappa defaultDensityConfig
      parsedT = case mT of
        Just s  -> case reads (dropWhile (== ' ') s) :: [(Double, String)] of
                     [(n, "")] -> n
                     _         -> dcT
        Nothing -> dcT
      parsedK = case mK of
        Just s  -> case reads (dropWhile (== ' ') s) :: [(Double, String)] of
                     [(n, "")] -> n
                     _         -> dcK
        Nothing -> dcK
  pure DensityConfig
    { dcKappa     = parsedK
    , dcThreshold = parsedT
    }

-- | Compute topic density ρ(T) = |E_T| / (|A_T| * κ).
--   * 'topicAtoms' — set of atoms associated with the topic.
--   * 'network' — the semantic network whose edges are counted.
-- Returns 0.0 when the topic has no atoms (avoid division by zero).
contentDensity :: SemanticNetwork -> Set Text -> Double -> Double
contentDensity network topicAtoms kappa
  | S.null topicAtoms = 0.0
  | otherwise         =
      let edges = snEdges network
          internal = M.size (M.filter
            (\e -> S.member (seFrom e) topicAtoms && S.member (seTo e) topicAtoms)
            edges)
          atomCount = fromIntegral (S.size topicAtoms)
      in fromIntegral internal / (atomCount * kappa)

-- | Return topics whose density ρ(T) is below 'dcThreshold'.
--   * 'topicAtomsMap' — Map Topic (Set Atom) from 'QxFx0.Semantic.Content'.
starvingTopics
  :: SemanticNetwork
  -> Map Text (Set Text)
  -> DensityConfig
  -> [Text]
starvingTopics network topicAtomsMap cfg =
  [ topic
  | (topic, atoms) <- M.toList topicAtomsMap
  , contentDensity network atoms (dcKappa cfg) < dcThreshold cfg
  ]

-- | Build the topic → atoms map from the curated definition corpus by
-- tokenising each topic's predicate surface forms.  Used by the
-- density gate triggers.
buildTopicAtomsMap :: Map Text Text -> Map Text (Set Text)
buildTopicAtomsMap lemmaMap =
  M.fromList
    [ (topic, S.unions [tokenizePredicate lemmaMap (spRu p) | p <- dcPredicates dc])
    | (topic, dc) <- M.toList definitionCorpus
    ]

-- | Seed a SemanticNetwork from definitionCorpus.
-- Creates edges between topics that share atoms in their predicates.
-- Uses lemmaMap to normalize tokens to lemmas for consistency with runtime.
seedFromCorpus :: Map Text Text -> SemanticNetwork
seedFromCorpus lemmaMap =
  let topicAtoms :: [(Text, Set Text)]
      topicAtoms =
        [ (topic, S.unions [tokenizePredicate lemmaMap (spRu p) | p <- dcPredicates dc])
        | (topic, dc) <- M.toList definitionCorpus
        ]

      allNodes :: Set Text
      allNodes = S.unions [atoms | (_, atoms) <- topicAtoms]

      corpusEdges :: [SemanticEdge]
      corpusEdges =
        [ semanticEdge t1 t2 (fromIntegral sharedCount / 10.0) sharedCount ExplicitEdge
        | (t1, atoms1) <- topicAtoms
        , (t2, atoms2) <- topicAtoms
        , t1 < t2
        , let shared = S.intersection atoms1 atoms2
              sharedCount = S.size shared
        , sharedCount > 0
        ]

      edgeMap :: Map (Text, Text) SemanticEdge
      edgeMap = M.fromList [((seFrom e, seTo e), e) | e <- corpusEdges]
  in SemanticNetwork
    { snNodes = allNodes
    , snEdges = edgeMap
    , snActivation = M.empty
    , snDecayRate = 0.5
    , snMaxHops = 3
    , snActivationLog = Seq.empty
    }

-- | Extract content words from a Russian predicate, filtering stop words and normalizing to lemmas.
-- Uses lemmaMap to normalize tokens for consistency with runtime tokenization.
tokenizePredicate :: Map Text Text -> Text -> Set Text
tokenizePredicate lemmaMap text =
  let ws = T.words (T.toLower text)
      filtered = filter (\w -> T.length w > 3 && not (isStopWord w)) ws
      normalized = map (\token -> M.findWithDefault token token lemmaMap) filtered
  in S.fromList normalized
  where
    isStopWord :: Text -> Bool
    isStopWord w = w `elem`
      [ "это", "есть", "является", "быть", "было", "будет"
      , "и", "или", "но", "а", "в", "на", "с", "по", "для"
      , "что", "как", "когда", "где", "кто", "который", "которая"
      , "не", "ни", "же", "ли", "бы", "то", "так", "только"
      , "может", "могут", "должен", "должна", "должно"
      , "через", "между", "перед", "после", "при", "во", "со"
      , "the", "and", "or", "but", "is", "are", "was", "were"
      , "of", "to", "in", "on", "at", "for", "with", "by"
      , "that", "which", "who", "when", "where", "how"
      ]
