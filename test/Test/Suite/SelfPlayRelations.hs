{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.SelfPlayRelations
Description : Tests for ADR-0052 Phase III self-play relation corpus.
-}
module Test.Suite.SelfPlayRelations
  ( selfPlayRelationsTests
  ) where

import Control.Exception (bracket_)
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import qualified Data.Text as T
import System.Directory (doesFileExist)
import System.Environment (lookupEnv, setEnv, unsetEnv)
import Test.HUnit

import QxFx0.Runtime.Session
  ( bootstrapSemanticNetwork
  , minimalMorphologyFallback
  , readSelfPlayRelationsPath
  )
import QxFx0.Semantic.Content.AtomStore
  ( Atom(..)
  , AtomId(..)
  , atomStore
  )
import QxFx0.Semantic.Network.Ingest
  ( LoadedRelation(..)
  , loadSelfPlayRelations
  , mergeSelfPlayRelations
  , normalizeRelationText
  )
import QxFx0.Semantic.Network.Substrate (loadBrainKB, resolveBrainKBPath)
import QxFx0.Semantic.Network.Types
  ( EdgeProvenance(..)
  , SemanticEdge(..)
  , SemanticNetwork(..)
  , emptySemanticNetwork
  )

selfPlayPath :: FilePath
selfPlayPath = "resources/knowledge/selfplay_relations.jsonl"

-- | The bundled self-play corpus must contain exactly 80 relations.
testSelfPlayFileHas80Relations :: Test
testSelfPlayFileHas80Relations = TestCase $ do
  exists <- doesFileExist selfPlayPath
  assertBool "selfplay_relations.jsonl must exist" exists
  rels <- loadSelfPlayRelations selfPlayPath
  assertEqual "selfplay relations must contain exactly 80 entries"
    80 (length rels)
  assertBool "every selfplay relation must have author selfplay"
    (all (\lr -> lrAuthor lr == "selfplay") rels)
  assertBool "every selfplay relation must have version 1"
    (all (\lr -> lrVersion lr == 1) rels)

-- | Merging self-play relations into a network must add edges that carry
-- the dedicated 'ProvenanceSelfPlay' provenance.
testMergeSelfPlayRelationsAddsProvenance :: Test
testMergeSelfPlayRelationsAddsProvenance = TestCase $ do
  merged <- mergeSelfPlayRelations selfPlayPath emptySemanticNetwork
  assertBool "merged network must contain selfplay edges"
    (not (M.null (snEdges merged)))
  assertBool "all edges must have ProvenanceSelfPlay"
    (all (\e -> seProvenance e == ProvenanceSelfPlay)
         (M.elems (snEdges merged)))
  assertBool "selfplay nodes must be present"
    (S.size (snNodes merged) > 0)

-- | Helpers to enable/disable the self-play feature via the environment
-- variable, restoring the previous value afterwards.
withSelfPlayEnabled :: IO a -> IO a
withSelfPlayEnabled action = do
  old <- lookupEnv "QXFX0_USE_SELFPLAY"
  bracket_ (setEnv "QXFX0_USE_SELFPLAY" "1")
           (restore old)
           action
  where
    restore Nothing   = unsetEnv "QXFX0_USE_SELFPLAY"
    restore (Just v)  = setEnv "QXFX0_USE_SELFPLAY" v

withoutSelfPlay :: IO a -> IO a
withoutSelfPlay action = do
  old <- lookupEnv "QXFX0_USE_SELFPLAY"
  bracket_ (setEnv "QXFX0_USE_SELFPLAY" "0")
           (restore old)
           action
  where
    restore Nothing   = unsetEnv "QXFX0_USE_SELFPLAY"
    restore (Just v)  = setEnv "QXFX0_USE_SELFPLAY" v

-- | With self-play enabled via the environment, bootstrapping must
-- include at least one node coming from the self-play corpus.
testBootstrapWithSelfPlayEnabled :: Test
testBootstrapWithSelfPlayEnabled = TestCase $ do
  rels <- loadSelfPlayRelations selfPlayPath
  brainKBEntries <- loadBrainKB =<< resolveBrainKBPath
  let firstRel = head rels
      expectedNodes = S.fromList [lrFrom firstRel, lrTo firstRel]
  network <- withSelfPlayEnabled $
    bootstrapSemanticNetwork minimalMorphologyFallback brainKBEntries False
  assertBool "selfplay nodes must be present in bootstrapped network"
    (expectedNodes `S.isSubsetOf` snNodes network)
  assertBool "bootstrapped network must contain selfplay edges"
    (any (\e -> seProvenance e == ProvenanceSelfPlay)
         (M.elems (snEdges network)))

-- | With self-play disabled, bootstrapping must not introduce any
-- self-play provenance into the semantic network.
testBootstrapWithSelfPlayDisabled :: Test
testBootstrapWithSelfPlayDisabled = TestCase $ do
  brainKBEntries <- loadBrainKB =<< resolveBrainKBPath
  network <- withoutSelfPlay $
    bootstrapSemanticNetwork minimalMorphologyFallback brainKBEntries False
  let selfPlayEdges = filter (\e -> seProvenance e == ProvenanceSelfPlay)
                             (M.elems (snEdges network))
      isSelfPlayNode node =
        any (\e -> seFrom e == node || seTo e == node) selfPlayEdges
  assertBool "disabled selfplay must not add selfplay edges"
    (null selfPlayEdges)
  assertBool "disabled selfplay must not add selfplay nodes"
    (S.null (S.filter isSelfPlayNode (snNodes network)))

-- | Check whether a normalized relation endpoint is admitted by the
-- atom store.  Matching uses the atom identifier, display text, or head
-- noun.
isAdmittedAtomText :: T.Text -> Bool
isAdmittedAtomText t =
  let normalized = normalizeRelationText t
      byId    = M.lookup (AtomId normalized) atomStore
      byDisplay = M.lookup normalized displayMap
      byHead    = M.lookup normalized headMap
  in not (T.null normalized) && (isJust byId || isJust byDisplay || isJust byHead)
  where
    displayMap = M.fromList [ (atomDisplay a, a) | (_, a) <- M.toList atomStore ]
    headMap    = M.fromList [ (atomHead a, a) | (_, a) <- M.toList atomStore ]
    isJust Nothing = False
    isJust (Just _) = True

-- | A prepositional LLM artifact must be rejected by the admission gate.
testNormalizeRelationRejectsPrepositionalPhrase :: Test
testNormalizeRelationRejectsPrepositionalPhrase = TestCase $ do
  let result = normalizeRelationText "на возможность будущего"
  assertBool "normalized text must not be admitted"
    (not (isAdmittedAtomText "на возможность будущего"))
  assertBool "normalization must strip the preposition"
    (not ("на " `T.isPrefixOf` result))

-- | A bare nominative atom must be accepted by the admission gate.
testNormalizeRelationAcceptsNominative :: Test
testNormalizeRelationAcceptsNominative = TestCase $ do
  assertEqual "свобода must normalize to itself"
    "свобода" (normalizeRelationText "свобода")
  assertBool "свобода must be admitted"
    (isAdmittedAtomText "свобода")

-- | An internal preposition is stripped and the head noun is recovered.
-- The phrase "вечность в мгновении" corresponds to the curated atom
-- whose head noun is "вечность".
testNormalizeRelationStripsPreposition :: Test
testNormalizeRelationStripsPreposition = TestCase $ do
  let result = normalizeRelationText "вечность в мгновении"
  assertEqual "вечность в мгновении must normalize to its head noun"
    "вечность" result
  assertBool "вечность must be admitted as an atom head"
    (isAdmittedAtomText "вечность в мгновении")

-- | Loading the bundled self-play corpus and merging it must reject at
-- least one relation because some endpoints are prepositional LLM
-- artifacts not present in the atom store.
testSelfPlayMergeRejectsAll :: Test
testSelfPlayMergeRejectsAll = TestCase $ do
  rawRels <- loadSelfPlayRelations selfPlayPath
  merged <- mergeSelfPlayRelations selfPlayPath emptySemanticNetwork
  let admittedCount = M.size (snEdges merged)
      rejectedCount = length rawRels - admittedCount
  assertBool "some selfplay relations must be rejected by the admission gate"
    (rejectedCount > 0)
  assertBool "some selfplay relations must be admitted"
    (admittedCount > 0)

selfPlayRelationsTests :: [Test]
selfPlayRelationsTests =
  [ TestLabel "selfplay file has 80 relations" testSelfPlayFileHas80Relations
  , TestLabel "mergeSelfPlayRelations adds ProvenanceSelfPlay edges" testMergeSelfPlayRelationsAddsProvenance
  , TestLabel "bootstrap with selfplay enabled includes selfplay nodes" testBootstrapWithSelfPlayEnabled
  , TestLabel "bootstrap with selfplay disabled does not change network" testBootstrapWithSelfPlayDisabled
  , TestLabel "normalize relation rejects prepositional phrase" testNormalizeRelationRejectsPrepositionalPhrase
  , TestLabel "normalize relation accepts nominative" testNormalizeRelationAcceptsNominative
  , TestLabel "normalize relation strips preposition" testNormalizeRelationStripsPreposition
  , TestLabel "selfplay merge rejects some relations" testSelfPlayMergeRejectsAll
  ]
