{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : QxFx0.Semantic.Network.Seed.Select
Description : Selection logic that sits above 'QxFx0.Semantic.Network.Seed'
              and chooses between the curated atom-graph seed and the
              definition-corpus heuristic seed.

This module lives above 'Seed' and 'Ingest' in the import graph so that
'QxFx0.Semantic.Network.Seed' can stay below 'QxFx0.Semantic.Network'
without forming an import cycle.

The default seed is the curated atom graph (P0.1).  The environment
variable @QXFX0_USE_ATOM_GRAPH_SEED@ is retained only as a test-harness
override so that tests can pin a deterministic seed regardless of the
compile-time default.  In production the default is always used.
-}
module QxFx0.Semantic.Network.Seed.Select
  ( selectSeedNetwork
  , selectSeedNetworkIO
  , selectSeedNetworkFor
  , readUseAtomGraphSeed
  ) where

import Control.Monad (when)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Text (Text)
import qualified Data.Text as T
import System.Environment (lookupEnv)

import QxFx0.Semantic.Content.AtomStore (AtomGraph(..), seedGraph)
import QxFx0.Semantic.Network (contentDensityGate)
import QxFx0.Semantic.Network.Ingest (buildNetworkFromAtomGraph)
import QxFx0.Semantic.Network.Seed (seedFromCorpus)
import QxFx0.Semantic.Network.Types (SemanticNetwork(..))

-- | Read the test-harness override for atom-graph seeding.
-- Defaults to 'True' (atom-graph seed).  Only values @"0"@, @"false"@,
-- @"no"@, or @"disable"@ select the corpus seed.
readUseAtomGraphSeed :: IO Bool
readUseAtomGraphSeed = do
  mEnv <- lookupEnv "QXFX0_USE_ATOM_GRAPH_SEED"
  pure $ maybe True (\raw ->
    T.toLower (T.pack raw) `notElem` ["0", "false", "no", "disable"]) mEnv

-- | Select the seed network for the runtime.
-- Always try the curated atom graph first; if it does not satisfy the
-- content-density gate, fall back to the definition-corpus heuristic.
selectSeedNetwork :: Map Text Text -> SemanticNetwork
selectSeedNetwork = selectSeedNetworkFor seedGraph

-- | 'IO' variant that honours the @QXFX0_USE_ATOM_GRAPH_SEED@ test-harness
-- override.  Used by bootstrap and tests that need a deterministic seed.
selectSeedNetworkIO :: Map Text Text -> IO SemanticNetwork
selectSeedNetworkIO lemmaMap = do
  useAtom <- readUseAtomGraphSeed
  pure $ if useAtom
           then selectSeedNetwork lemmaMap
           else seedFromCorpus lemmaMap

-- | Generalised variant that lets callers supply a different atom graph,
-- mainly so tests can exercise the fallback branch with a sparse graph.
selectSeedNetworkFor :: AtomGraph -> Map Text Text -> SemanticNetwork
selectSeedNetworkFor atomGraph lemmaMap =
  let atomSeed = buildNetworkFromAtomGraph atomGraph
  in if contentDensityGate atomSeed
       then atomSeed
       else seedFromCorpus lemmaMap
