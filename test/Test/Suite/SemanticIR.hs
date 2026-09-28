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
  ]

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
