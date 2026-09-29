{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for 'QxFx0.Semantic.IR' (Stage-0 miniature, shadow-only).
-- Pins the validator discipline, the s-expression round-trip, and the
-- 100-row gold corpus: every row decodes, parses, validates, and is
-- closed; paraphrase pairs share byte-identical IR.
module Test.Suite.SemanticIR
  ( semanticIRTests
  ) where

import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as BL
import qualified Data.Map.Strict as M
import qualified Data.Text as T
import Test.HUnit

import QxFx0.Semantic.IR

semanticIRTests :: [Test]
semanticIRTests =
  [ TestLabel "empty apply rejected" $ TestCase $
      assertBool "predicate must open roles"
        (validateProposition (Apply (PredicateId "is") []) /= Nothing)

  , TestLabel "empty role rejected" $ TestCase $
      assertBool "roles must be named"
        (validateProposition
           (Apply (PredicateId "is") [RoleBinding "" (Concept (ConceptId "x"))])
         /= Nothing)

  , TestLabel "vacuous quantification rejected" $ TestCase $
      assertEqual "unused binder"
        (Just "quantified: vacuous binding")
        (validateProposition
           (Quantified Forall (VarId "?x") (Apply (PredicateId "is") [RoleBinding "theme" (Concept (ConceptId "y"))])))

  , TestLabel "unclosed proposition caught" $ TestCase $
      assertEqual "free variable escapes"
        (Just "closed: free variables escape")
        (validateClosedProposition
           (Apply (PredicateId "is") [RoleBinding "theme" (Variable (VarId "?x"))]))

  , TestLabel "valid sample passes both gates" $ TestCase $ do
      let sample = Quantified Forall (VarId "?x")
            (Implies (Apply (PredicateId "person") [RoleBinding "theme" (Variable (VarId "?x"))])
                     (Apply (PredicateId "can-choose") [RoleBinding "agent" (Variable (VarId "?x"))]))
      assertEqual "structurally valid" Nothing (validateProposition sample)
      assertEqual "closed" Nothing (validateClosedProposition sample)

  , TestLabel "malformed sexpr is Nothing" $ TestCase $ do
      assertEqual "unbalanced" Nothing (parseProposition "(Not (Apply is")
      assertEqual "unknown head" Nothing (parseProposition "(Frobnicate x)")
      assertEqual "empty input" Nothing (parseProposition "")
      assertEqual "bare atom" Nothing (parseProposition "freedom")

  , TestLabel "pretty-parse round trip" $ TestCase $ do
      let samples =
            [ Apply (PredicateId "is") [RoleBinding "theme" (Concept (ConceptId "freedom"))]
            , Not (Apply (PredicateId "equals") [RoleBinding "theme" (Concept (ConceptId "a")), RoleBinding "value" (Concept (ConceptId "b"))])
            , Quantified Exists (VarId "?x") (Apply (PredicateId "choice") [RoleBinding "theme" (Variable (VarId "?x"))])
            , Modal Necessary (Apply (PredicateId "distinguish") [RoleBinding "agent" (Concept (ConceptId "anyone"))])
            , AtTime "always" (Apply (PredicateId "holds") [RoleBinding "theme" (Concept (ConceptId "rule"))])
            ]
      mapM_ (\p -> assertEqual ("round trip: " <> T.unpack (prettyProposition p))
               (Just p) (parseProposition (prettyProposition p))) samples

  , TestLabel "gold corpus validates end to end" $ TestCase $ do
      content <- BL.readFile "data/semantic_ir/gold.jsonl"
      let rows = [ r | line <- BL.split 0x0a content
                     , not (BL.null line)
                     , Just r <- [Aeson.decode line :: Maybe GoldRow] ]
      assertEqual "100 gold rows" 100 (length rows)
      mapM_ validateRow rows
      let strata = M.fromListWith (+) [(goldStratum r, 1) | r <- rows]
      assertEqual "negation stratum" (Just 30) (M.lookup "negation" strata)
      assertEqual "quantifier stratum" (Just 30) (M.lookup "quantifier" strata)
      assertEqual "polysemy stratum" (Just 25) (M.lookup "polysemy" strata)
      assertEqual "paraphrase stratum" (Just 15) (M.lookup "paraphrase" strata)
      let pairs = M.fromListWith (++) [(p, [goldSexpr r]) | r <- rows, Just p <- [goldPair r]]
      mapM_ (\(p, sexprs) -> assertBool ("pair shares IR: " <> T.unpack p)
               (all (== head sexprs) sexprs)) (M.toList pairs)
  ] ++ stage1Batch1Tests

data GoldRow = GoldRow
  { goldId :: !T.Text
  , goldStratum :: !T.Text
  , goldPair :: !(Maybe T.Text)
  , goldText :: !T.Text
  , goldSexpr :: !T.Text
  } deriving stock (Eq, Show)

instance Aeson.FromJSON GoldRow where
  parseJSON = Aeson.withObject "GoldRow" $ \o -> GoldRow
    <$> o Aeson..: "id"
    <*> o Aeson..: "stratum"
    <*> o Aeson..: "pair"
    <*> o Aeson..: "text"
    <*> o Aeson..: "sexpr"

validateRow :: GoldRow -> Assertion
validateRow row = do
  assertBool ("non-empty text: " <> T.unpack (goldId row))
    (not (T.null (T.strip (goldText row))))
  case parseProposition (goldSexpr row) of
    Nothing -> assertFailure ("gold sexpr must parse: " <> T.unpack (goldId row))
    Just prop -> do
      assertEqual ("gold validates: " <> T.unpack (goldId row))
        Nothing (validateProposition prop)
      assertEqual ("gold closed: " <> T.unpack (goldId row))
        Nothing (validateClosedProposition prop)
      assertEqual ("gold round-trips: " <> T.unpack (goldId row))
        (Just prop) (parseProposition (prettyProposition prop))

-- ---------------------------------------------------------------------------
-- Stage-1 batch 1 (ADR-0054): primitives + freedom/will senses.
-- Schema validation only — no runtime reads these files.
-- ---------------------------------------------------------------------------

data PrimitiveRow = PrimitiveRow
  { primId :: !T.Text
  , primKind :: !T.Text
  , primAtom :: !(Maybe T.Text)
  , primJustification :: !(Maybe T.Text)
  } deriving stock (Eq, Show)

instance Aeson.FromJSON PrimitiveRow where
  parseJSON = Aeson.withObject "PrimitiveRow" $ \o -> PrimitiveRow
    <$> o Aeson..: "id"
    <*> o Aeson..: "kind"
    <*> o Aeson..: "atom"
    <*> o Aeson..: "justification"

data SenseRow = SenseRow
  { senseId :: !T.Text
  , senseConcept :: !T.Text
  , senseLexicalizations :: ![T.Text]
  , senseFrameRoles :: ![T.Text]
  , senseExamples :: ![T.Text]
  , senseCounterExamples :: ![T.Text]
  , senseProvenance :: !T.Text
  } deriving stock (Eq, Show)

instance Aeson.FromJSON SenseRow where
  parseJSON = Aeson.withObject "SenseRow" $ \o -> SenseRow
    <$> o Aeson..: "id"
    <*> o Aeson..: "concept"
    <*> o Aeson..: "lexicalizations"
    <*> o Aeson..: "frame_roles"
    <*> o Aeson..: "examples"
    <*> o Aeson..: "counter_examples"
    <*> o Aeson..: "provenance"

readJsonlRows :: (Aeson.FromJSON a) => FilePath -> IO [a]
readJsonlRows path = do
  content <- BL.readFile path
  pure [ r | line <- BL.split 10 content
           , not (BL.null line)
           , Just r <- [Aeson.decode line] ]

stage1Batch1Tests :: [Test]
stage1Batch1Tests =
  [ TestLabel "primitives schema holds" $ TestCase $ do
      rows <- readJsonlRows "data/semantic_ir/primitives.jsonl" :: IO [PrimitiveRow]
      assertEqual "24 primitives" 24 (length rows)
      assertEqual "unique ids" 24 (length (map primId rows `asSetOf` id))
      let kinds = ["agent", "action", "object", "quality", "relation", "circumstance"]
      mapM_ (\r -> assertBool ("closed kind: " <> T.unpack (primId r))
               (primKind r `elem` kinds)) rows
      mapM_ (\r -> case primAtom r of
                Nothing -> assertBool ("null atom needs justification: " <> T.unpack (primId r))
                             (maybe False (not . T.null . T.strip) (primJustification r))
                Just _ -> assertEqual ("present atom needs no justification: " <> T.unpack (primId r))
                             Nothing (primJustification r)) rows

  , TestLabel "senses schema holds" $ TestCase $ do
      rows <- readJsonlRows "data/semantic_ir/senses.jsonl" :: IO [SenseRow]
      assertEqual "6 senses in batch 1" 6 (length rows)
      mapM_ (\r -> assertBool ("cluster concept: " <> T.unpack (senseId r))
               (senseConcept r `elem` ["свобода", "воля"])) rows
      mapM_ (\r -> do
        assertBool ("lexicalizations: " <> T.unpack (senseId r))
          (not (null (senseLexicalizations r)))
        assertBool ("frame roles: " <> T.unpack (senseId r))
          (not (null (senseFrameRoles r)))
        assertBool ("examples: " <> T.unpack (senseId r))
          (not (null (senseExamples r)))
        assertBool ("counter-examples: " <> T.unpack (senseId r))
          (not (null (senseCounterExamples r)))
        assertEqual ("human provenance: " <> T.unpack (senseId r))
          "human-authored stage-1 batch 1" (senseProvenance r)) rows
  ]
  where
    asSetOf xs f = foldr (\x acc -> if f x `elem` acc then acc else f x : acc) [] xs
