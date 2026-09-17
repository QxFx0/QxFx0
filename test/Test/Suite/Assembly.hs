{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for 'QxFx0.Semantic.Assembly' (shadow-only v1).
-- Pins the bridge rule: shared concept + differing sources compose;
-- identical sources and bridgeless pairs do not.
module Test.Suite.Assembly
  ( assemblyTests
  ) where

import qualified Data.Map.Strict as M
import qualified Data.Set as S
import qualified Data.Text as T
import Test.HUnit

import QxFx0.Semantic.Assembly
import QxFx0.Semantic.Composition
import QxFx0.Semantic.ContentSelector.Types (selectorMathVersion)
import QxFx0.Types.Semantic.AtomGraph
import QxFx0.Types.Semantic.ContentSelector (ContentSelector(..))
import QxFx0.Types.Semantic.Content (PredicateRole(..), SemanticPredicate(..))
import QxFx0.Semantic.Space.Types (emptySemanticSpace)
import QxFx0.Semantic.Content.AtomStore (seedGraph)

testLemmaMap :: M.Map T.Text T.Text
testLemmaMap = M.fromList
  [ ("требует", "требовать")
  , ("ответственности", "ответственность")
  , ("свободы", "свобода")
  , ("исключает", "исключать")
  ]

term :: T.Text -> PredicateTerm
term = parsePredicateTerm testLemmaMap

assemblyTests :: [Test]
assemblyTests =
  [ TestLabel "shared bridge composes" $ TestCase $ do
      let a = ("свобода", "свобода требует ответственности",
               term "свобода требует ответственности")
          b = ("ответственность", "ответственность исключает произвол",
               term "ответственность исключает произвол")
      case assemblePair a b of
        Nothing -> assertFailure "bridge on ответственность expected"
        Just asm -> do
          assertEqual "bridge concept"
            "ответственность" (asmBridge asm)
          assertEqual "head donor is A"
            (Just "свобода") (ptHead (asmTerm asm))
          assertEqual "two sources recorded" 2 (length (asmSources asm))
          assertEqual "skeleton path length" 1 (asmPathLen asm)
          assertBool "union carries both relations"
            (S.size (ptRels (asmTerm asm)) == 2)

  , TestLabel "identical sources are rejected (non-tautology)" $ TestCase $ do
      let a = ("свобода", "свобода требует ответственности",
               term "свобода требует ответственности")
      assertEqual "same topic and term must not assemble"
        Nothing (assemblePair a a)

  , TestLabel "bridgeless pairs are rejected (no invented bridge)" $ TestCase $ do
      let a = ("свобода", "свобода требует ответственности",
               term "свобода требует ответственности")
          b = ("зло", "зло", term "зло")
      assertEqual "disjoint concepts must not assemble"
        Nothing (assemblePair a b)

  , TestLabel "bridge is deterministic (smallest shared concept)" $ TestCase $ do
      let a = ("свобода", "свобода требует осознанной ответственности",
               term "свобода требует осознанной ответственности")
          b = ("ответственность", "ответственность требует осознанной свободы",
               term "ответственность требует осознанной свободы")
          r1 = assemblePair a b
          r2 = assemblePair a b
      assertEqual "same inputs, same assembly" r1 r2
      case r1 of
        Nothing -> assertFailure "expected a bridge"
        Just asm -> assertEqual "lexicographically smallest shared concept"
          (S.findMin (S.intersection (assemblyConcepts (term "свобода требует осознанной ответственности"))
                                     (assemblyConcepts (term "ответственность требует осознанной свободы"))))
          (asmBridge asm)

  , TestLabel "negation is never silently dropped" $ TestCase $ do
      let a = ("свобода", "свобода требует ответственности",
               term "свобода требует ответственности")
          b = ("ответственность", "не ответственность исключает произвол",
               term "не ответственность исключает произвол")
      case assemblePair a b of
        Nothing -> assertFailure "expected a bridge"
        Just asm -> assertBool "negation survives composition"
          (ptNeg (asmTerm asm))

  , TestLabel "proposition view is total and lemma-formed" $ TestCase $ do
      let a = ("свобода", "свобода требует ответственности",
               term "свобода требует ответственности")
          b = ("ответственность", "ответственность исключает произвол",
               term "ответственность исключает произвол")
      case assemblePair a b of
        Nothing -> assertFailure "expected a bridge"
        Just asm ->
          assertEqual "head plus both relation pairs"
            (Just "свобода",
             [("исключать", "произвол"), ("требовать", "ответственность")])
            (assemblyProposition asm)

  , TestLabel "assembly stays close to both sources" $ TestCase $ do
      let ta = term "свобода требует ответственности"
          tb = term "ответственность исключает произвол"
          a = ("свобода", "свобода требует ответственности", ta)
          b = ("ответственность", "ответственность исключает произвол", tb)
      case assemblePair a b of
        Nothing -> assertFailure "expected a bridge"
        Just asm -> do
          let (oa, ob) = assemblySourceOverlap asm ta tb
          assertBool ("overlap with A too low: " ++ show oa) (oa >= 0.5)
          assertBool ("overlap with B too low: " ++ show ob) (ob >= 0.5)

  , TestLabel "rating labels are the decided two" $ TestCase $
      assertEqual "coherent + grounded"
        ["assembly_coherent", "assembly_grounded"] assemblyRatingLabels
  ] ++ graphAssemblyTests ++ endorsementTests

-- ---------------------------------------------------------------------------
-- Graph wiring (selector math v4)
-- ---------------------------------------------------------------------------

testGraph :: RelationSource -> AtomGraph
testGraph src = AtomGraph
  [edge]
  (M.singleton (AtomId "свобода") [edge])
  "test-fixture"
  where
    edge = Relation
      { relFrom = AtomId "свобода"
      , relTo = AtomId "ответственность"
      , relType = RelRequires
      , relObjectCase = CaseNominative
      , relObjectText = "ответственность"
      , relVerbText = Just "требовать"
      , relRuOriginal = "свобода требует ответственности"
      , relEnOriginal = "freedom requires responsibility"
      , relSource = src
      , relTopic = "свобода"
      , relRationale = Nothing
      , relCounter = Nothing
      , relSynthesis = Nothing
      }

graphAssemblyTests :: [Test]
graphAssemblyTests =
  [ TestLabel "validated graph path wires the assembly" $ TestCase $ do
      let a = ("свобода", "свобода требует ответственности",
               term "свобода требует ответственности")
          b = ("ответственность", "ответственность исключает произвол",
               term "ответственность исключает произвол")
          res = assembleViaGraph (testGraph Curated)
                  (S.singleton "свобода") (S.singleton "ответственность") a b
      case res of
        ((asm, proof, _score) : _) -> do
          assertEqual "direct bridge ranks first" "ответственность" (asmBridge asm)
          assertEqual "one validated edge" 1 (length (ppEdges proof))
        [] -> assertFailure "expected at least one wired assembly"

  , TestLabel "raw-substrate path is blocked by the gate" $ TestCase $ do
      let a = ("свобода", "свобода требует ответственности",
               term "свобода требует ответственности")
          b = ("ответственность", "ответственность исключает произвол",
               term "ответственность исключает произвол")
      assertEqual "G4 must block SubstrateExtractedRaw"
        []
        (assembleViaGraph (testGraph SubstrateExtractedRaw)
          (S.singleton "свобода") (S.singleton "ответственность") a b)

  , TestLabel "unreached topic yields no assembly" $ TestCase $ do
      let a = ("свобода", "свобода требует ответственности",
               term "свобода требует ответственности")
          b = ("ответственность", "ответственность исключает произвол",
               term "ответственность исключает произвол")
      assertEqual "no path into зло"
        []
        (assembleViaGraph (testGraph Curated)
          (S.singleton "свобода") (S.singleton "зло") a b)

  , TestLabel "skeleton bridge still required with a graph" $ TestCase $ do
      let a = ("свобода", "свобода требует ответственности",
               term "свобода требует ответственности")
          b = ("зло", "зло", term "зло")
      assertEqual "bridgeless terms never wire"
        []
        (assembleViaGraph (testGraph Curated)
          (S.singleton "свобода") (S.singleton "зло") a b)

  , TestLabel "mediated bridge composes across a validated path" $ TestCase $ do
      let a = ("свобода", "свобода держит выбор",
               term "свобода держит выбор")
          b = ("ответственность", "ответственность исключает произвол",
               term "ответственность исключает произвол")
      assertEqual "no shared concept, skeleton refuses"
        Nothing (assemblePair a b)
      case assembleViaGraph (testGraph Curated)
             (S.singleton "свобода") (S.singleton "ответственность") a b of
        [] -> assertFailure "validated свобода→ответственность path expected"
        ((asm, proof, _score) : _) -> do
          assertEqual "path bridge" "свобода\8594ответственность" (asmBridge asm)
          assertEqual "one validated edge" 1 (length (ppEdges proof))
          assertBool "path verb contributes a relation pair"
            (S.member ("требовать", "ответственность") (ptRels (asmTerm asm)))

  , TestLabel "seed graph wires свобода/ответственность (integration pin)" $ TestCase $ do
      let a = ("свобода", "свобода предполагает возможность выбора",
               parsePredicateTerm M.empty "свобода предполагает возможность выбора")
          b = ("ответственность", "ответственность требует осознания последствий",
               parsePredicateTerm M.empty "ответственность требует осознания последствий")
          res = assembleViaGraph seedGraph
                  (S.singleton "свобода") (S.singleton "ответственность") a b
      assertBool "real seed graph must yield at least one assembly" (not (null res))

  , TestLabel "selector math version stamps the endorsement regime" $ TestCase $
      assertEqual "math v4"
        "selector-math-v5-topic-field-activation-ontology-assembly-endorsement"
        selectorMathVersion

  , TestLabel "relation-type verb map is total and non-empty" $ TestCase $
      assertBool "every RelationType maps to a non-empty verb"
        (all (not . T.null . relTypeVerb) [minBound .. maxBound])
  ]

-- ---------------------------------------------------------------------------
-- Selection endorsement (selector math v5)
-- ---------------------------------------------------------------------------

endorseFixtureSelector :: ContentSelector
endorseFixtureSelector = ContentSelector
  { csSpace = emptySemanticSpace
  , csTopicAtoms = M.fromList
      [ ("свобода", S.fromList ["свобода", "выбор"])
      , ("ответственность", S.fromList ["ответственность"])
      ]
  , csTopicPredicates = M.empty
  , csLemmaMap = M.fromList
      [ ("требует", "требовать")
      , ("ответственности", "ответственность")
      ]
  , csOntology = Nothing
  }

endorsePred :: T.Text -> T.Text -> SemanticPredicate
endorsePred topic surface = SemanticPredicate
  RoleProperty surface surface topic Nothing Nothing Nothing Nothing

endorsementTests :: [Test]
endorsementTests =
  [ TestLabel "endorsement bonus value is pinned" $ TestCase $
      assertEqual "hand-set v1" 0.15 assemblyEndorsementBonus

  , TestLabel "gate-passing assembly boosts both topics" $ TestCase $ do
      let entries =
            [ ("свобода", endorsePred "свобода" "свобода требует ответственности", 0.5, 0.40)
            , ("ответственность", endorsePred "ответственность" "ответственность исключает произвол", 0.5, 0.35)
            ]
          boosted = endorseComposition (testGraph Curated) endorseFixtureSelector "свобода" entries
      case boosted of
        [(t1, _, _, w1), (t2, _, _, w2)] -> do
          assertEqual "query boosted" 0.55 w1
          assertEqual "partner boosted" 0.50 w2
          assertEqual "topics preserved" ["свобода", "ответственность"] [t1, t2]
        _ -> assertFailure "expected two endorsed entries"

  , TestLabel "raw-substrate graph endorses nothing" $ TestCase $ do
      let entries =
            [ ("свобода", endorsePred "свобода" "свобода требует ответственности", 0.5, 0.40)
            , ("ответственность", endorsePred "ответственность" "ответственность исключает произвол", 0.5, 0.35)
            ]
      assertEqual "weights untouched"
        entries
        (endorseComposition (testGraph SubstrateExtractedRaw) endorseFixtureSelector "свобода" entries)

  , TestLabel "missing query entry passes through" $ TestCase $ do
      let entries =
            [ ("ответственность", endorsePred "ответственность" "ответственность исключает произвол", 0.5, 0.35) ]
      assertEqual "no query, no endorsement"
        entries
        (endorseComposition (testGraph Curated) endorseFixtureSelector "свобода" entries)

  , TestLabel "verbalization cites grounds and marks construction" $ TestCase $ do
      let a = ("свобода", "свобода требует ответственности",
               term "свобода требует ответственности")
          b = ("ответственность", "ответственность исключает произвол",
               term "ответственность исключает произвол")
      case assemblePair a b of
        Nothing -> assertFailure "expected a bridge"
        Just asm ->
          assertEqual "explicit construction, not fluent prose"
            "свобода — ответственность-связь: исключать произвол; требовать ответственность. Основания: свобода требует ответственности + ответственность исключает произвол"
            (verbalizeAssembly asm)
  , TestLabel "utterable assembly selects the top gated candidate" $ TestCase $ do
      let predA = endorsePred "свобода" "свобода требует ответственности"
          predB = endorsePred "ответственность" "ответственность исключает произвол"
          cs = endorseFixtureSelector
            { csTopicPredicates = M.fromList
                [ ("свобода", [predA]), ("ответственность", [predB]) ] }
      case utterableAssembly (testGraph Curated) cs "свобода"
             [("свобода", "свобода требует ответственности"),
              ("ответственность", "ответственность исключает произвол")] of
        Nothing -> assertFailure "expected an utterable assembly"
        Just asm -> assertBool "carries relations"
          (not (S.null (ptRels (asmTerm asm))))

  , TestLabel "utterable assembly is silent without a qualifying pair" $ TestCase $ do
      let predA = endorsePred "свобода" "свобода требует ответственности"
          cs = endorseFixtureSelector
      assertEqual "single topic cannot assemble"
        Nothing
        (utterableAssembly (testGraph Curated) cs "свобода"
          [("свобода", "свобода требует ответственности")])
  ]
