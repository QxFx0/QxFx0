{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Semantic.Network.Seed
  ( seedFromCorpus
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Set (Set)
import qualified Data.Set as S
import Data.Text (Text)
import qualified Data.Text as T
import QxFx0.Semantic.Network.Types (SemanticNetwork(..), SemanticEdge(..))
import QxFx0.Semantic.Content (definitionCorpus, DefinitionContent(..), SemanticPredicate(..))

-- | Seed a SemanticNetwork from definitionCorpus.
-- Creates edges between topics that share atoms in their predicates.
seedFromCorpus :: SemanticNetwork
seedFromCorpus =
  let topicAtoms :: [(Text, Set Text)]
      topicAtoms =
        [ (topic, S.unions [tokenizePredicate (spRu p) | p <- dcPredicates dc])
        | (topic, dc) <- M.toList definitionCorpus
        ]
      
      allNodes :: Set Text
      allNodes = S.unions [atoms | (_, atoms) <- topicAtoms]
      
      corpusEdges :: [SemanticEdge]
      corpusEdges =
        [ SemanticEdge t1 t2 (fromIntegral sharedCount / 10.0) sharedCount
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
    }

-- | Extract content words from a Russian predicate, filtering stop words.
-- Inlined here to avoid circular dependency with Semantic.Space.
tokenizePredicate :: Text -> Set Text
tokenizePredicate text =
  let ws = T.words (T.toLower text)
      filtered = filter (\w -> T.length w > 3 && not (isStopWord w)) ws
  in S.fromList filtered
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
