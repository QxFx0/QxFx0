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
import Data.List (sort)
import Data.Maybe (isJust)
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import qualified Data.Text as T
import Test.HUnit

import QxFx0.Semantic.IR
import QxFx0.Semantic.IREval
import QxFx0.Semantic.IREval.Batch
import QxFx0.Semantic.IRCompose
  ( CompositionDef(..)
  , expandComposition
  , expansionConflicts
  )
import QxFx0.Semantic.IRState
  ( TimeStep(..)
  , FluentSupport(..)
  , EventSpec(..)
  , applyEvent
  , emptyState
  , fluentsAt
  , foldHistory
  , lineageOf
  , reviseHistory
  )

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
  ] ++ stage1Batch1Tests ++ evalTests ++ splitIntegrityTests ++ scenarioTests ++ clusterGoldTests ++ exitHarnessTests ++ scenarioExpectationTests ++ stage1Batch2Tests ++ compositionTests ++ stateEngineTests

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

-- | Lenient JSONL reader (implementation moved to
-- 'QxFx0.Semantic.IREval.Batch'; behavior unchanged).
readJsonlRows :: (Aeson.FromJSON a) => FilePath -> IO [a]
readJsonlRows = readJsonlRowsLenient

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

-- ---------------------------------------------------------------------------
-- Stage-1 batch 2 (ADR-0054): rules + minimal pairs. Schema validation
-- only — the evaluator is a later batch; no runtime reads these files.
-- ---------------------------------------------------------------------------

data RuleRow = RuleRow
  { ruleId :: !T.Text
  , ruleKind :: !T.Text
  , rulePremises :: ![T.Text]
  , ruleConclusion :: !T.Text
  , ruleScope :: !T.Text
  , ruleExceptions :: ![T.Text]
  , rulePriority :: !(Maybe Int)
  , ruleProvenance :: !T.Text
  } deriving stock (Eq, Show)

instance Aeson.FromJSON RuleRow where
  parseJSON = Aeson.withObject "RuleRow" $ \o -> RuleRow
    <$> o Aeson..: "id"
    <*> o Aeson..: "kind"
    <*> o Aeson..: "premises"
    <*> o Aeson..: "conclusion"
    <*> o Aeson..: "scope"
    <*> o Aeson..: "exceptions"
    <*> o Aeson..: "priority"
    <*> o Aeson..: "provenance"

data PairRow = PairRow
  { pairId :: !T.Text
  , pairRelation :: !T.Text
  , pairSexprA :: !T.Text
  , pairSexprB :: !T.Text
  } deriving stock (Eq, Show)

instance Aeson.FromJSON PairRow where
  parseJSON = Aeson.withObject "PairRow" $ \o -> PairRow
    <$> o Aeson..: "id"
    <*> o Aeson..: "relation"
    <*> o Aeson..: "sexpr_a"
    <*> o Aeson..: "sexpr_b"

parseSexprOrFail :: T.Text -> T.Text -> IO Proposition
parseSexprOrFail ctx sexpr = case parseProposition sexpr of
  Just p -> pure p
  Nothing -> assertFailure ("must parse (" <> T.unpack ctx <> ")")

stage1Batch2Tests :: [Test]
stage1Batch2Tests =
  [ TestLabel "rules schema holds" $ TestCase $ do
      rows <- readJsonlRows "data/semantic_ir/rules.jsonl" :: IO [RuleRow]
      assertEqual "16 rules" 16 (length rows)
      assertEqual "unique ids" 16 (length (foldr (\r acc -> if ruleId r `elem` acc then acc else ruleId r : acc) [] rows))
      mapM_ validateRule rows
  , TestLabel "minimal pairs schema holds" $ TestCase $ do
      rows <- readJsonlRows "data/semantic_ir/minimal_pairs.jsonl" :: IO [PairRow]
      assertEqual "20 pairs" 20 (length rows)
      mapM_ validatePair rows
  ]

validateRule :: RuleRow -> Assertion
validateRule row = do
  assertBool ("rule kind: " <> T.unpack (ruleId row))
    (ruleKind row `elem` ["strict", "defeasible"])
  assertBool ("premises non-empty: " <> T.unpack (ruleId row))
    (not (null (rulePremises row)))
  assertEqual ("human provenance: " <> T.unpack (ruleId row))
    "human-authored stage-1 batch 2" (ruleProvenance row)
  premiseProps <- mapM (parseSexprOrFail (ruleId row)) (rulePremises row)
  conclusionProp <- parseSexprOrFail (ruleId row) (ruleConclusion row)
  -- Variable discipline: a rule proves nothing about unbound variables.
  let premVars = S.unions (map freeVariables premiseProps)
  assertBool ("conclusion vars bound by premises: " <> T.unpack (ruleId row))
    (freeVariables conclusionProp `S.isSubsetOf` premVars)
  case ruleKind row of
    "strict" -> do
      assertEqual ("strict has no exceptions: " <> T.unpack (ruleId row))
        [] (ruleExceptions row)
      assertEqual ("strict has no priority: " <> T.unpack (ruleId row))
        Nothing (rulePriority row)
    _ -> do
      assertBool ("defeasible carries exceptions: " <> T.unpack (ruleId row))
        (not (null (ruleExceptions row)))
      case rulePriority row of
        Just n -> assertBool ("priority positive: " <> T.unpack (ruleId row)) (n >= 1)
        Nothing -> assertFailure ("defeasible needs priority: " <> T.unpack (ruleId row))
      mapM_ (parseSexprOrFail (ruleId row)) (ruleExceptions row)
      pure ()

validatePair :: PairRow -> Assertion
validatePair row = do
  assertBool ("pair relation: " <> T.unpack (pairId row))
    (pairRelation row `elem` ["equivalent", "contrast", "scope-shift"])
  pa <- parseSexprOrFail (pairId row <> "/a") (pairSexprA row)
  pb <- parseSexprOrFail (pairId row <> "/b") (pairSexprB row)
  mapM_ (\p -> assertEqual ("pair validates: " <> T.unpack (pairId row))
             Nothing (validateProposition p)) [pa, pb]
  mapM_ (\p -> assertEqual ("pair closed: " <> T.unpack (pairId row))
             Nothing (validateClosedProposition p)) [pa, pb]
  case pairRelation row of
    "equivalent" -> assertEqual ("equivalent pair shares IR: " <> T.unpack (pairId row)) pa pb
    _ -> assertBool ("non-equivalent pair differs: " <> T.unpack (pairId row)) (pa /= pb)

-- ---------------------------------------------------------------------------
-- Stage-1 batch 3 (ADR-0054): shadow evaluator pins. No runtime reads.
-- ---------------------------------------------------------------------------

evalTests :: [Test]
evalTests =
  [ TestLabel "variable binds consistently" $ TestCase $ do
      let pat = Apply (PredicateId "chose")
                  [ RoleBinding "agent" (Variable (VarId "?x")) ]
          fact = Apply (PredicateId "chose")
                   [ RoleBinding "agent" (Concept (ConceptId "he")) ]
      assertEqual "binds on match"
        (Just (Subst [(VarId "?x", Concept (ConceptId "he"))]))
        (matchPattern pat fact)
      let pat2 = And
            [ Apply (PredicateId "chose") [RoleBinding "agent" (Variable (VarId "?x"))]
            , Apply (PredicateId "refused") [RoleBinding "agent" (Variable (VarId "?x"))]
            ]
          factSame = And
            [ Apply (PredicateId "chose") [RoleBinding "agent" (Concept (ConceptId "he"))]
            , Apply (PredicateId "refused") [RoleBinding "agent" (Concept (ConceptId "he"))]
            ]
          factDiff = And
            [ Apply (PredicateId "chose") [RoleBinding "agent" (Concept (ConceptId "he"))]
            , Apply (PredicateId "refused") [RoleBinding "agent" (Concept (ConceptId "she"))]
            ]
      assertBool "consistent rebinding matches" (matchPattern pat2 factSame /= Nothing)
      assertEqual "inconsistent rebinding fails" Nothing (matchPattern pat2 factDiff)

  , TestLabel "shape mismatches fail" $ TestCase $ do
      let base = Apply (PredicateId "limits")
                   [ RoleBinding "agent" (Concept (ConceptId "coercion"))
                   , RoleBinding "theme" (Concept (ConceptId "freedom")) ]
          wrongPred = Apply (PredicateId "expands")
                        [ RoleBinding "agent" (Concept (ConceptId "coercion"))
                        , RoleBinding "theme" (Concept (ConceptId "freedom")) ]
          wrongRole = Apply (PredicateId "limits")
                        [ RoleBinding "patient" (Concept (ConceptId "coercion"))
                        , RoleBinding "theme" (Concept (ConceptId "freedom")) ]
          shortArity = Apply (PredicateId "limits")
                         [ RoleBinding "agent" (Concept (ConceptId "coercion")) ]
          wrongSort = Apply (PredicateId "limits")
                        [ RoleBinding "agent" (Entity (EntityId "coercion"))
                        , RoleBinding "theme" (Concept (ConceptId "freedom")) ]
      mapM_ (\p -> assertEqual ("mismatch fails: " <> T.unpack (prettyProposition p))
               Nothing (matchPattern p base))
        [wrongPred, wrongRole, shortArity, wrongSort]

  , TestLabel "binders match strictly" $ TestCase $ do
      let body = Apply (PredicateId "person") [RoleBinding "theme" (Variable (VarId "?x"))]
          forallX = Quantified Forall (VarId "?x") body
          forallY = Quantified Forall (VarId "?y")
                      (Apply (PredicateId "person") [RoleBinding "theme" (Variable (VarId "?y"))])
          existsX = Quantified Exists (VarId "?x") body
      assertBool "identical binders match" (matchPattern forallX forallX /= Nothing)
      assertEqual "renamed binder fails (no alpha-equivalence in v1)" Nothing (matchPattern forallX forallY)
      assertEqual "different quantifier fails" Nothing (matchPattern forallX existsX)

  , TestLabel "forward chaining derives with proof" $ TestCase $ do
      let factA = Apply (PredicateId "aware") [RoleBinding "theme" (Concept (ConceptId "agent-generic"))]
          ruleB = StrictRule "r-b" [factA]
                    (Apply (PredicateId "exists") [RoleBinding "theme" (Concept (ConceptId "responsibility"))])
          ruleC = StrictRule "r-c"
                    [Apply (PredicateId "exists") [RoleBinding "theme" (Concept (ConceptId "responsibility"))]]
                    (Apply (PredicateId "acknowledged") [RoleBinding "theme" (Concept (ConceptId "responsibility"))])
          (closed1, proof1) = forwardChain 32 [ruleB] [factA]
      assertBool "one-step derivation" (Apply (PredicateId "exists") [RoleBinding "theme" (Concept (ConceptId "responsibility"))] `elem` closed1)
      assertEqual "proof cites rule and premise" ["r-b"] [psRuleId s | s <- proof1]
      let (closed2, proof2) = forwardChain 32 [ruleB, ruleC] [factA]
      assertEqual "two-step chain length" 2 (length proof2)
      assertEqual "chain order" ["r-b", "r-c"] [psRuleId s | s <- proof2]
      let (closed0, proof0) = forwardChain 0 [ruleB, ruleC] [factA]
      assertEqual "fuel zero derives nothing" ([factA], []) (closed0, proof0)

  , TestLabel "defeasible respects exceptions and scope" $ TestCase $ do
      let rule = DefeasibleRule "rd-t"
            [Apply (PredicateId "promised") [RoleBinding "agent" (Variable (VarId "?x")), RoleBinding "theme" (Variable (VarId "?p"))]]
            (Modal Obligatory (Apply (PredicateId "fulfilled") [RoleBinding "theme" (Variable (VarId "?p"))]))
            [Apply (PredicateId "coerced") [RoleBinding "theme" (Variable (VarId "?p"))]]
            2 ""
          base = [Apply (PredicateId "promised")
                    [ RoleBinding "agent" (Concept (ConceptId "he"))
                    , RoleBinding "theme" (Concept (ConceptId "vow")) ]]
      case defeasibleFire "" rule base of
        Right concl -> assertEqual "instantiated conclusion"
          (Modal Obligatory (Apply (PredicateId "fulfilled") [RoleBinding "theme" (Concept (ConceptId "vow"))])) concl
        Left _ -> assertFailure "should fire without exception"
      let baseExc = base ++ [Apply (PredicateId "coerced") [RoleBinding "theme" (Concept (ConceptId "vow"))]]
      case defeasibleFire "" rule baseExc of
        Left _ -> pure ()
        Right _ -> assertFailure "exception must block"
      let scoped = rule { drScope = "oaths" }
      case defeasibleFire "other" scoped base of
        Left _ -> pure ()
        Right _ -> assertFailure "scope mismatch must block"
      case defeasibleFire "oaths" scoped base of
        Right _ -> pure ()
        Left _ -> assertFailure "matching scope must fire"

  , TestLabel "presuppositions and conflicts" $ TestCase $ do
      let fact = Apply (PredicateId "person") [RoleBinding "theme" (Concept (ConceptId "he"))]
          held = Apply (PredicateId "person") [RoleBinding "theme" (Variable (VarId "?x"))]
          missing = Apply (PredicateId "immortal") [RoleBinding "theme" (Variable (VarId "?x"))]
      assertEqual "held and missing flagged"
        [(held, True), (missing, False)]
        (checkPresuppositions [fact] [held, missing])
      let p = Apply (PredicateId "free") [RoleBinding "theme" (Concept (ConceptId "he"))]
      assertEqual "no conflict" Nothing (detectConflict [fact, p])
      assertEqual "direct contradiction found"
        (Just (Not p, p)) (detectConflict [fact, Not p, p])

  , TestLabel "verdicts serialize to JSON" $ TestCase $ do
      let step = ProofStep "rs-05" [0] (Subst [])
                 (Not (Apply (PredicateId "exists") [RoleBinding "theme" (Concept (ConceptId "responsibility"))]))
          verdict = Entails [step]
      assertEqual "json round trip"
        (Just verdict) (Aeson.decode (Aeson.encode verdict))
      assertEqual "refuted round trip"
        (Just (Refuted [step])) (Aeson.decode (Aeson.encode (Refuted [step])))
      assertEqual "boundary round trip"
        (Just (NotEntailed OpenWorldMissingFacts))
        (Aeson.decode (Aeson.encode (NotEntailed OpenWorldMissingFacts)))
      assertEqual "fuel report round trip"
        (Just (NotEntailed (FuelExhausted (FuelReport 1 0))))
        (Aeson.decode (Aeson.encode (NotEntailed (FuelExhausted (FuelReport 1 0)))))

  , TestLabel "verdict taxonomy: refuted vs open-world vs fuel vs unsupported" $ TestCase $ do
      let p = Apply (PredicateId "holds") [RoleBinding "theme" (Concept (ConceptId "oath"))]
          q = Apply (PredicateId "binding") [RoleBinding "theme" (Concept (ConceptId "oath"))]
          r = Apply (PredicateId "answers-for") [RoleBinding "theme" (Concept (ConceptId "oath"))]
          strange = Apply (PredicateId "never-seen-pred") [RoleBinding "theme" (Concept (ConceptId "oath"))]
          rulePQ = StrictRule "t-pq" [p] q
          ruleQR = StrictRule "t-qr" [q] r
      -- entailed through a chain
      case entailmentVerdict 32 [rulePQ, ruleQR] [p] r of
        Entails _ -> pure ()
        other -> assertFailure ("chain should entail: " <> show other)
      -- refuted: negation derived
      case entailmentVerdict 32 [StrictRule "t-nq" [p] (Not q)] [p] q of
        Refuted _ -> pure ()
        other -> assertFailure ("negation should refute: " <> show other)
      -- open world: fixpoint, known predicates, nothing derived
      case entailmentVerdict 32 [rulePQ] [] q of
        NotEntailed OpenWorldMissingFacts -> pure ()
        other -> assertFailure ("underived query should stay open: " <> show other)
      -- fuel exhausted: reversed two-step chain on fuel 1
      -- (foldl' chains in-order rules within one round, so the
      -- reversed order genuinely needs two rounds)
      case entailmentVerdict 1 [ruleQR, rulePQ] [p] r of
        NotEntailed (FuelExhausted _) -> pure ()
        other -> assertFailure ("starved chain should exhaust fuel: " <> show other)
      -- unsupported: predicate outside the inventory
      case entailmentVerdict 32 [rulePQ] [p] strange of
        NotEntailed UnsupportedPredicate -> pure ()
        other -> assertFailure ("unknown predicate should be unsupported: " <> show other)

  , TestLabel "status mapping never asserts the unproven" $ TestCase $ do
      assertEqual "entails grounds"
        StatusGrounded (statusOfVerdict (Entails []))
      assertEqual "refuted is explicit"
        StatusRefuted (statusOfVerdict (Refuted []))
      assertEqual "open world abstains"
        StatusAbstain (statusOfVerdict (NotEntailed OpenWorldMissingFacts))
      assertEqual "starved search abstains"
        StatusAbstain (statusOfVerdict (NotEntailed (FuelExhausted (FuelReport 1 1))))
      assertEqual "unsupported abstains"
        StatusAbstain (statusOfVerdict (NotEntailed UnsupportedPredicate))
      assertEqual "defeated abstains"
        StatusAbstain (statusOfVerdict (DefeatedBy "r" (Apply (PredicateId "p") [])))
      assertEqual "grounded renders content unchanged"
        "thesis" (renderStatusSurface StatusGrounded "thesis")
      assertEqual "refuted marks negation"
        "Установлено, что неверно: thesis" (renderStatusSurface StatusRefuted "thesis")
      assertBool "hypothesis marks itself"
        ("Гипотеза: " `T.isPrefixOf` renderStatusSurface StatusHypothesis "thesis")
      assertBool "abstain owns the gap"
        (not (T.null (renderStatusSurface StatusAbstain "thesis")))

  , TestLabel "forwardChainFuel signals fixpoint vs exhaustion" $ TestCase $ do
      let p = Apply (PredicateId "holds") [RoleBinding "theme" (Concept (ConceptId "oath"))]
          q = Apply (PredicateId "binding") [RoleBinding "theme" (Concept (ConceptId "oath"))]
          rulePQ = StrictRule "t-pq" [p] q
          (_, _, fixOutcome) = forwardChainFuel 32 [rulePQ] [p]
          (_, _, starvedOutcome) = forwardChainFuel 0 [rulePQ] [p]
      assertEqual "quiescent base reports fixpoint" ReachedFixpoint fixOutcome
      assertEqual "starved base reports exhaustion" (ExhaustedFuel 0) starvedOutcome

  , TestLabel "rules file fires end to end" $ TestCase $ do
      fileRules <- readJsonlRows "data/semantic_ir/rules.jsonl" :: IO [RuleFileRow]
      strict <- mapM toStrict [ r | r <- fileRules, frKind r == "strict" ]
      def <- mapM toDefeasible [ r | r <- fileRules, frKind r == "defeasible" ]
      assertEqual "8 strict rules" 8 (length strict)
      assertEqual "8 defeasible rules" 8 (length def)
      -- rs-05: unawareness present, responsibility absent.
      let kb = [Not (Apply (PredicateId "aware") [RoleBinding "theme" (Concept (ConceptId "agent-generic"))])]
          (closed, proof) = forwardChain 32 strict kb
          wanted = Not (Apply (PredicateId "exists") [RoleBinding "theme" (Concept (ConceptId "responsibility"))])
      assertBool "rs-05 derives" (wanted `elem` closed)
      assertBool "proof cites rs-05" ("rs-05" `elem` [psRuleId s | s <- proof])
      -- rd-02 fires clean, blocked by the coercion exception.
      let rd02 = head [ r | r <- def, drId r == "rd-02" ]
          vow = Apply (PredicateId "promised")
                  [ RoleBinding "agent" (Concept (ConceptId "he"))
                  , RoleBinding "theme" (Concept (ConceptId "vow")) ]
      case defeasibleFire "" rd02 [vow] of
        Right _ -> pure ()
        Left _ -> assertFailure "rd-02 should fire clean"
      case defeasibleFire "" rd02 [vow, Apply (PredicateId "coerced") [RoleBinding "theme" (Concept (ConceptId "vow"))]] of
        Left _ -> pure ()
        Right _ -> assertFailure "rd-02 coercion exception must block"
  ]

-- | Row types and total builders moved to
-- 'QxFx0.Semantic.IREval.Batch'; these wrappers preserve the
-- assertion behavior the pins rely on.
mustParseRow :: T.Text -> T.Text -> IO Proposition
mustParseRow ctx sexpr = either assertFailure pure (parseRowEither ctx sexpr)

toStrict :: RuleFileRow -> IO StrictRule
toStrict r = either assertFailure pure (toStrictEither r)

toDefeasible :: RuleFileRow -> IO DefeasibleRule
toDefeasible r = either assertFailure pure (toDefeasibleEither r)

-- ---------------------------------------------------------------------------
-- Stage-1 Batch C (ADR-0054): typed composition with entailment
-- boundaries. Operators in code, domain composites as data (Batch E
-- owns the ownership domain; here abstract machinery checks).
-- ---------------------------------------------------------------------------

compositionTests :: [Test]
compositionTests =
  [ TestLabel "compositions file holds" $ TestCase $ do
      rows <- readJsonlRows "data/semantic_ir/compositions.jsonl" :: IO [FileComposition]
      assertEqual "2 synthetic compositions" 2 (length rows)
      assertEqual "unique ids" 2 (length (foldr (\r acc -> if fcId r `elem` acc then acc else fcId r : acc) [] rows))
  , TestLabel "file composition expands" $ TestCase $ do
      rows <- readJsonlRows "data/semantic_ir/compositions.jsonl" :: IO [FileComposition]
      case [ r | r <- rows, fcId r == "cmp-blocked-conclusion" ] of
        [fc] -> case expandFileComposites fc of
          Left err -> assertFailure ("must expand: " <> err)
          Right (cid, rules) -> do
            assertEqual "id carried" "cmp-blocked-conclusion" cid
            blocked <- mapM (parseSexprOrFail cid) (fcBlocked fc)
            kept <- parseSexprOrFail cid "(Apply kept ((theme (Concept oath))))"
            let conclusions = map srConclusion rules
            assertBool "blocked conclusion withheld"
              (all (`notElem` blocked) conclusions)
            assertBool "unblocked conclusion kept"
              (kept `elem` conclusions)
        _ -> assertFailure "cmp-blocked-conclusion missing"
  , TestLabel "temporary transfer: entailment boundaries" $ TestCase $ do
      gave <- parseSexprOrFail "t" "(Apply gave ((agent ?a) (recipient ?b) (theme ?x)))"
      temporary <- parseSexprOrFail "t" "(Apply temporary ((theme ?x)))"
      owns <- parseSexprOrFail "t" "(Apply owns ((agent ?b) (theme ?x)))"
      mustReturn <- parseSexprOrFail "t" "(Apply must-return ((agent ?b) (theme ?x)))"
      let base = StrictRule "t-give" [gave] owns
          comp = CompositionDef "t-temp" [base] [temporary] [mustReturn] [owns]
      case expandComposition comp of
        Left err -> assertFailure ("must expand: " <> err)
        Right rules -> do
          assertBool "blocked ownership withheld"
            (all (\r -> srConclusion r /= owns) rules)
          assertBool "added obligation kept"
            (any (\r -> srConclusion r == mustReturn) rules)
          let facts = [ Apply (PredicateId "gave")
                          [ RoleBinding "agent" (Entity (EntityId "a"))
                          , RoleBinding "recipient" (Entity (EntityId "b"))
                          , RoleBinding "theme" (Concept (ConceptId "book"))
                          ]
                      , Apply (PredicateId "temporary")
                          [ RoleBinding "theme" (Concept (ConceptId "book")) ]
                      ]
              holder = Apply (PredicateId "must-return")
                         [ RoleBinding "agent" (Entity (EntityId "b"))
                         , RoleBinding "theme" (Concept (ConceptId "book"))
                         ]
              owner = Apply (PredicateId "owns")
                        [ RoleBinding "agent" (Entity (EntityId "b"))
                        , RoleBinding "theme" (Concept (ConceptId "book"))
                        ]
          case entailmentVerdict 32 rules facts holder of
            Entails _ -> pure ()
            other -> assertFailure ("obligation should entail: " <> show other)
          -- Blocked is absence, never refutation. Withheld
          -- ownership leaves the theory's vocabulary
          -- (UnsupportedPredicate); an in-vocabulary but
          -- underivable claim stays open world. Neither refutes.
          case entailmentVerdict 32 rules facts owner of
            NotEntailed UnsupportedPredicate -> pure ()
            other -> assertFailure ("withheld ownership should stay unproven: " <> show other)
          let stranger = Apply (PredicateId "must-return")
                           [ RoleBinding "agent" (Entity (EntityId "c"))
                           , RoleBinding "theme" (Concept (ConceptId "book"))
                           ]
          case entailmentVerdict 32 rules facts stranger of
            NotEntailed OpenWorldMissingFacts -> pure ()
            other -> assertFailure ("third-party claim should stay open: " <> show other)
  , TestLabel "dangling variables rejected" $ TestCase $ do
      gave <- parseSexprOrFail "t" "(Apply gave ((agent ?a) (theme ?x)))"
      stray <- parseSexprOrFail "t" "(Apply owes ((agent ?z) (theme ?x)))"
      let comp = CompositionDef "t-stray" [] [] [stray] []
          _ = gave
      case expandComposition comp of
        Left _ -> pure ()
        Right _ -> assertFailure "unbound ?z must fail role compatibility"
  , TestLabel "scope wrappers preserved" $ TestCase $ do
      premise <- parseSexprOrFail "t" "(Modal Obligatory (Apply obeys ((agent ?x) (theme ?o))))"
      conclusion <- parseSexprOrFail "t" "(Apply bound ((agent ?x) (theme ?o)))"
      extra <- parseSexprOrFail "t" "(Apply witnessed ((theme ?o)))"
      let comp = CompositionDef "t-scope" [StrictRule "t-r" [premise] conclusion] [extra] [] []
      case expandComposition comp of
        Left err -> assertFailure ("must expand: " <> err)
        Right [refined] -> assertEqual "modal premise carried intact"
          [premise, extra] (srPremises refined)
        Right _ -> assertFailure "one base rule in, one refined rule out"
  , TestLabel "conflicts propagate, never silence" $ TestCase $ do
      p <- parseSexprOrFail "t" "(Apply kept ((theme (Concept oath))))"
      let comp = CompositionDef "t-conf"
            [ StrictRule "t-a" [p] p
            , StrictRule "t-b" [p] (Not p)
            ] [] [] []
      case expandComposition comp of
        Left err -> assertFailure ("must expand: " <> err)
        Right rules -> assertBool "conflict surfaces"
          (isJust (expansionConflicts rules))
  ]

-- ---------------------------------------------------------------------------
-- Stage-1 Batch D (ADR-0054): generic state-transition engine.
-- Abstract fluents/events; domain contracts wait for Batch E.
-- ---------------------------------------------------------------------------

stateEngineTests :: [Test]
stateEngineTests =
  [ TestLabel "apply asserts and withdraws" $ TestCase $ do
      holds <- parseSexprOrFail "t" "(Apply holds ((theme (Concept oath))))"
      kept <- parseSexprOrFail "t" "(Apply kept ((theme (Concept oath))))"
      gone <- parseSexprOrFail "t" "(Apply gone ((theme (Concept oath))))"
      let ev = EventSpec "e1" [holds] [gone] [kept] (TimeStep "t1")
      st <- either assertFailure pure
        (foldHistory (TimeStep "t0") [holds, gone] [ev] >>= \(st, _) -> pure st)
      assertBool "asserted present" (kept `elem` fluentsAt st (TimeStep "t1"))
      assertBool "withdrawn absent" (gone `notElem` fluentsAt st (TimeStep "t1"))
      assertBool "unrelated persists" (holds `elem` fluentsAt st (TimeStep "t1"))
      assertEqual "support recorded"
        (Just (SupportAsserted "e1")) (lineageOf st (TimeStep "t1") kept)
      assertEqual "persistence recorded"
        (Just (SupportPersisted "e1" (TimeStep "t0"))) (lineageOf st (TimeStep "t1") holds)
  , TestLabel "precondition violation rejects" $ TestCase $ do
      holds <- parseSexprOrFail "t" "(Apply holds ((theme (Concept oath))))"
      missing <- parseSexprOrFail "t" "(Apply missing ((theme (Concept oath))))"
      kept <- parseSexprOrFail "t" "(Apply kept ((theme (Concept oath))))"
      let ev = EventSpec "e1" [missing] [] [kept] (TimeStep "t1")
      case foldHistory (TimeStep "t0") [holds] [ev] of
        Left _ -> pure ()
        Right _ -> assertFailure "violated precondition must reject"
  , TestLabel "contradiction revises state" $ TestCase $ do
      p <- parseSexprOrFail "t" "(Apply kept ((theme (Concept oath))))"
      let ev = EventSpec "e1" [] [] [Not p] (TimeStep "t1")
      st <- either assertFailure pure
        (foldHistory (TimeStep "t0") [p] [ev] >>= \(st, _) -> pure st)
      assertBool "contradicted fluent leaves" (p `notElem` fluentsAt st (TimeStep "t1"))
      assertBool "negation arrives" (Not p `elem` fluentsAt st (TimeStep "t1"))
  , TestLabel "revision recomputes dependents only" $ TestCase $ do
      holds <- parseSexprOrFail "t" "(Apply holds ((theme (Concept oath))))"
      kept <- parseSexprOrFail "t" "(Apply kept ((theme (Concept oath))))"
      dropped <- parseSexprOrFail "t" "(Apply dropped ((theme (Concept oath))))"
      other <- parseSexprOrFail "t" "(Apply other ((theme (Concept artifact))))"
      let ev1 = EventSpec "e1" [holds] [] [kept] (TimeStep "t1")
          ev2 = EventSpec "e2" [kept] [] [dropped] (TimeStep "t2")
          ev2alt = EventSpec "e2" [kept] [] [other] (TimeStep "t2")
      (st, times) <- either assertFailure pure
        (foldHistory (TimeStep "t0") [holds] [ev1, ev2])
      assertEqual "times advance" [TimeStep "t0", TimeStep "t1", TimeStep "t2"] times
      assertBool "dependent present" (dropped `elem` fluentsAt st (TimeStep "t2"))
      (st2, _) <- either assertFailure pure
        (reviseHistory (TimeStep "t0") [holds] [ev1, ev2] "e2" ev2alt)
      assertBool "dependent recomputed" (dropped `notElem` fluentsAt st2 (TimeStep "t2"))
      assertBool "replacement present" (other `elem` fluentsAt st2 (TimeStep "t2"))
      assertBool "independent persists" (holds `elem` fluentsAt st2 (TimeStep "t2"))
      assertBool "t1 byte-identical"
        (fluentsAt st (TimeStep "t1") == fluentsAt st2 (TimeStep "t1"))
  , TestLabel "unknown event revision fails" $ TestCase $ do
      holds <- parseSexprOrFail "t" "(Apply holds ((theme (Concept oath))))"
      kept <- parseSexprOrFail "t" "(Apply kept ((theme (Concept oath))))"
      let ev = EventSpec "e1" [holds] [] [kept] (TimeStep "t1")
      case reviseHistory (TimeStep "t0") [holds] [ev] "nope" ev of
        Left _ -> pure ()
        Right _ -> assertFailure "unknown event must fail"
  , TestLabel "state types serialize to JSON" $ TestCase $ do
      assertEqual "timestep round trip"
        (Just (TimeStep "t0")) (Aeson.decode (Aeson.encode (TimeStep "t0")))
      assertEqual "support round trip"
        (Just (SupportAsserted "e1")) (Aeson.decode (Aeson.encode (SupportAsserted "e1")))
  ]

-- ---------------------------------------------------------------------------
-- Stage-1 batch 4 (ADR-0054 §2.4): frozen held-out split. Content-hash
-- integrity lives in scripts/split_semantic_ir.py --check; unit pins
-- the partition structure. Rules stay unsplit by design (model, not
-- test data — recorded in the batch note).
-- ---------------------------------------------------------------------------

data SplitsFile = SplitsFile
  { splitsSource :: !T.Text
  , splitsDigest :: !T.Text
  , splitsTrain :: ![T.Text]
  , splitsDev :: ![T.Text]
  , splitsTest :: ![T.Text]
  } deriving stock (Eq, Show)

instance Aeson.FromJSON SplitsFile where
  parseJSON = Aeson.withObject "SplitsFile" $ \o -> do
    splits <- o Aeson..: "splits"
    SplitsFile <$> o Aeson..: "source"
               <*> o Aeson..: "source_sha256"
               <*> splits Aeson..: "train"
               <*> splits Aeson..: "dev"
               <*> splits Aeson..: "test"

sortGold :: [T.Text] -> [T.Text]
sortGold = sort

splitIntegrityTests :: [Test]
splitIntegrityTests =
  [ TestLabel "frozen split partitions gold" $ TestCase $ do
      goldRows <- readJsonlRows "data/semantic_ir/gold.jsonl" :: IO [GoldRow]
      content <- BL.readFile "data/semantic_ir/splits.json"
      case Aeson.decode content :: Maybe SplitsFile of
        Nothing -> assertFailure "splits.json must decode"
        Just splits -> do
          let goldIds = [ goldId r | r <- goldRows ]
              seen = splitsTrain splits ++ splitsDev splits ++ splitsTest splits
          assertEqual "split source" "data/semantic_ir/gold.jsonl" (splitsSource splits)
          assertBool "digest recorded" (not (T.null (splitsDigest splits)))
          assertEqual "partition covers gold ids"
            (sortGold goldIds) (sortGold seen)
          assertEqual "split ids disjoint" (length seen) (length goldIds)
          assertEqual "train size" 63 (length (splitsTrain splits))
          assertEqual "dev size" 16 (length (splitsDev splits))
          assertEqual "test size" 21 (length (splitsTest splits))
  ]

-- ---------------------------------------------------------------------------
-- Stage-1 batch 5 (ADR-0054): 30 multi-turn scenarios. Schema validation
-- only — scenario simulation is a later batch; no runtime reads.
-- ---------------------------------------------------------------------------

-- | Scenario row types moved to 'QxFx0.Semantic.IREval.Batch'.
scenarioActSet :: [T.Text]
scenarioActSet =
  ["Assert", "Challenge", "Concede", "Distinguish", "Clarify"
  , "Revise", "AskDefine", "Abstain", "Hypothesize"]

scenarioTests :: [Test]
scenarioTests =
  [ TestLabel "scenarios schema holds" $ TestCase $ do
      rows <- readJsonlRows "data/semantic_ir/scenarios.jsonl" :: IO [ScenarioRow]
      assertEqual "30 scenarios" 30 (length rows)
      assertEqual "unique ids" 30 (length (foldr (\r acc -> if scenarioId r `elem` acc then acc else scenarioId r : acc) [] rows))
      mapM_ validateScenario rows
  ]

validateScenario :: ScenarioRow -> Assertion
validateScenario row = do
  assertEqual ("human provenance: " <> T.unpack (scenarioId row))
    "human-authored stage-1 batch 5" (scenarioProvenance row)
  assertBool ("at least two turns: " <> T.unpack (scenarioId row))
    (length (scenarioTurns row) >= 2)
  assertBool ("opens with user or system claim: " <> T.unpack (scenarioId row))
    (turnSpeaker (head (scenarioTurns row)) `elem` ["user", "system"])
  mapM_ (validateTurn (scenarioId row)) (scenarioTurns row)
  mapM_ (\(prev, cur) -> assertBool ("alternation in " <> T.unpack (scenarioId row))
           (turnSpeaker prev /= turnSpeaker cur))
    (zip (scenarioTurns row) (drop 1 (scenarioTurns row)))

validateTurn :: T.Text -> ScenarioTurnRow -> Assertion
validateTurn sid turn = do
  assertBool ("non-empty text in " <> T.unpack sid)
    (not (T.null (T.strip (turnText turn))))
  assertBool ("non-empty interpretations in " <> T.unpack sid)
    (not (null (turnInterpretations turn)))
  assertBool ("known act in " <> T.unpack sid)
    (turnAct turn `elem` scenarioActSet)
  mapM_ (\sexpr -> case parseProposition sexpr of
           Nothing -> assertFailure ("scenario sexpr must parse in " <> T.unpack sid <> ": " <> T.unpack (T.take 60 sexpr))
           Just prop -> do
             assertEqual ("scenario validates in " <> T.unpack sid) Nothing (validateProposition prop)
             assertEqual ("scenario closed in " <> T.unpack sid) Nothing (validateClosedProposition prop))
    (turnInterpretations turn)

-- ---------------------------------------------------------------------------
-- Stage-1 batch 6a (ADR-0054): freedom-cluster gold. Same row schema as
-- gold.jsonl; pair groups share byte-identical IR.
-- ---------------------------------------------------------------------------

clusterGoldTests :: [Test]
clusterGoldTests =
  [ TestLabel "cluster gold validates end to end" $ TestCase $ do
      content <- BL.readFile "data/semantic_ir/cluster_freedom.jsonl"
      let rows = [ r | line <- BL.split 10 content
                     , not (BL.null line)
                     , Just r <- [Aeson.decode line :: Maybe GoldRow] ]
      assertEqual "500 cluster rows" 500 (length rows)
      assertEqual "unique ids" 500 (length (foldr (\r acc -> if goldId r `elem` acc then acc else goldId r : acc) [] rows))
      mapM_ validateRow rows
      let pairs = M.fromListWith (++) [(p, [goldSexpr r]) | r <- rows, Just p <- [goldPair r]]
      assertBool "has pair groups" (not (M.null pairs))
      mapM_ (\(p, sexprs) -> assertBool ("cluster pair shares IR: " <> T.unpack p)
               (all (== head sexprs) sexprs)) (M.toList pairs)
  ]

-- ---------------------------------------------------------------------------
-- Stage-1 exit harness (ADR-0054 §2.5/§6): mechanical exit criteria over
-- exit_tasks.jsonl. Thresholds preset here, not fitted after:
-- strict entailment >= 0.80, defeasible >= 0.60, conflicts and
-- presuppositions exact. v1 is green by construction (tasks authored
-- with known answers); the gate's teeth are for future changes.
-- ---------------------------------------------------------------------------

-- | Exit row types, 'contradictory' and 'resolveDuel' moved to
-- 'QxFx0.Semantic.IREval.Batch'; this wrapper preserves pins.
toDefRule :: T.Text -> InlineDefRule -> IO DefeasibleRule
toDefRule ctx r = either assertFailure pure (toDefRuleEither ctx r)

exitHarnessTests :: [Test]
exitHarnessTests =
  [ TestLabel "exit tasks load with shape" $ TestCase $ do
      rows <- readJsonlRows "data/semantic_ir/exit_tasks.jsonl" :: IO [ExitTaskRow]
      assertEqual "41 exit tasks" 41 (length rows)
      assertEqual "17 strict" 17 (length [ r | r <- rows, exitKind r == "strict" ])
      assertEqual "10 single defeasible" 10 (length [ r | r <- rows, exitKind r == "defeasible" ])
      assertEqual "2 duels" 2 (length [ r | r <- rows, exitKind r == "defeasible-duel" ])
      assertEqual "6 conflicts" 6 (length [ r | r <- rows, exitKind r == "conflict" ])
      assertEqual "6 presuppositions" 6 (length [ r | r <- rows, exitKind r == "presupposition" ])

  , TestLabel "strict entailment accuracy >= 0.80" $ TestCase $ do
      rows <- readJsonlRows "data/semantic_ir/exit_tasks.jsonl" :: IO [ExitStrictRow]
      let strict = [ r | r <- rows ]
      results <- mapM runStrictTask strict
      let total = length results
          correct = length (filter id results)
      assertBool ("strict accuracy >= 0.80, got " <> show correct <> "/" <> show total)
        (correct * 5 >= total * 4)

  , TestLabel "defeasible accuracy >= 0.60" $ TestCase $ do
      rows <- readJsonlRows "data/semantic_ir/exit_tasks.jsonl" :: IO [ExitTaskRow]
      results <- mapM runDefeasibleTask [ r | r <- rows, exitKind r `elem` ["defeasible", "defeasible-duel"] ]
      let total = length results
          correct = length (filter id results)
      assertBool ("defeasible accuracy >= 0.60, got " <> show correct <> "/" <> show total)
        (correct * 5 >= total * 3)

  , TestLabel "conflicts exact" $ TestCase $ do
      rows <- readJsonlRows "data/semantic_ir/exit_tasks.jsonl" :: IO [ExitTaskRow]
      mapM_ runConflictTask [ r | r <- rows, exitKind r == "conflict" ]

  , TestLabel "presuppositions exact" $ TestCase $ do
      rows <- readJsonlRows "data/semantic_ir/exit_tasks.jsonl" :: IO [ExitTaskRow]
      mapM_ runPresupTask [ r | r <- rows, exitKind r == "presupposition" ]
  ]

runStrictTask :: ExitStrictRow -> IO Bool
runStrictTask row = case runStrictDetail row of
  Left e -> assertFailure e >> pure False
  Right outcome -> pure (soPass outcome)

runDefeasibleTask :: ExitTaskRow -> IO Bool
runDefeasibleTask row = case runDefeasibleDetail row of
  Left e -> assertFailure e >> pure False
  Right outcome -> pure (dfoPass outcome)

runConflictTask :: ExitTaskRow -> IO ()
runConflictTask row = case runConflictDetail row of
  Left e -> assertFailure e
  Right outcome -> assertBool ("conflict holds on " <> T.unpack (exitId row)) (coPass outcome)

runPresupTask :: ExitTaskRow -> IO ()
runPresupTask row = case runPresupDetail row of
  Left e -> assertFailure e
  Right outcome -> assertBool ("presupposition holds on " <> T.unpack (exitId row)) (poPass outcome)

-- ---------------------------------------------------------------------------
-- Stage-1 batch 7 (ADR-0054): scenario expectations (soundness leg) +
-- exit-tasks growth. No thresholds here — soundness invariants assert
-- 100%; accuracy thresholds live in the exit harness above.
-- ---------------------------------------------------------------------------

-- | Scenario expectation types moved to 'QxFx0.Semantic.IREval.Batch'.

scenarioExpectationTests :: [Test]
scenarioExpectationTests =
  [ TestLabel "scenario expectations hold" $ TestCase $ do
      fileRules <- readJsonlRows "data/semantic_ir/rules.jsonl" :: IO [RuleFileRow]
      strict <- mapM toStrictFileRule fileRules
      content <- BL.readFile "data/semantic_ir/scenarios.jsonl"
      let rows = [ r | line <- BL.split 10 content
                     , not (BL.null line)
                     , Just r <- [Aeson.decode line :: Maybe ScenarioRowEx] ]
      assertEqual "30 scenarios with expectations" 30 (length rows)
      results <- concat <$> mapM (runScenario strict) rows
      assertEqual "40 expectations" 40 (length results)
      mapM_ (\(sid, kind, holds) -> assertBool
               ("expectation holds: " <> T.unpack sid <> "/" <> T.unpack kind) holds) results
  ]

-- | Scenario row type moved to 'QxFx0.Semantic.IREval.Batch'.
toStrictFileRule :: RuleFileRow -> IO StrictRule
toStrictFileRule r = either assertFailure pure (toStrictFileRuleEither r)

runScenario :: [StrictRule] -> ScenarioRowEx -> IO [(T.Text, T.Text, Bool)]
runScenario rules row = case runScenarioDetail rules row of
  Left e -> assertFailure e >> pure []
  Right results -> pure results
