{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Semantic.IREval.Batch
Description : canonical — Stage-1 file batch runners and JSON trace schema.

Status (2026-10-02, ADR-0054 §2.3): SHADOW ONLY. Nothing in the
runtime calls this module. Row types and runners moved here
(verbatim semantics) from @Test.Suite.SemanticIR@ so the
standalone @qxfx0-stage1-traces@ emitter and the unit suite
share one implementation: rules are the model, and now the
runners are single-sourced too.

Totality: every runner returns 'Either String'; parse failures
are data errors ('Left'), never exceptions. The test suite
wraps these with assertions; the emitter serializes them.
-}
module QxFx0.Semantic.IREval.Batch
  ( -- * File row types (moved from the suite, semantics unchanged)
    RuleFileRow(..)
  , InlineStrictRule(..)
  , InlineDefRule(..)
  , ExitTaskRow(..)
  , ExitStrictRow(..)
  , ExpectTurns(..)
  , ScenarioExpectation(..)
  , ScenarioTurnRow(..)
  , ScenarioRow(..)
  , ScenarioRowEx(..)
    -- * Total row readers
  , readJsonlRowsLenient
  , parseRowEither
    -- * Total rule builders
  , toStrictEither
  , toDefeasibleEither
  , toDefRuleEither
  , toStrictFileRuleEither
    -- * Shared predicates
  , contradictory
  , resolveDuel
    -- * Task outcomes (Bool runners for pins, detail runners for traces)
  , StrictOutcome(..)
  , runStrictDetail
  , runStrictVerdict
  , FileComposition(..)
  , expandFileComposites
  , DefOutcome(..)
  , runDefeasibleDetail
  , ConflictOutcome(..)
  , runConflictDetail
  , PresupOutcome(..)
  , runPresupDetail
  , runScenarioDetail
    -- * JSON trace schema (ADR-0054 §2.3)
  , traceProvenance
  , ExitTrace(..)
  , ScenarioTrace(..)
  , BatchSummary(..)
  ) where

import Data.Aeson (FromJSON(..), ToJSON(..))
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as BL
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

import QxFx0.Semantic.IR (Proposition(..), parseProposition)
import QxFx0.Semantic.IRCompose
  ( CompositionDef(..)
  , expandComposition
  )
import QxFx0.Semantic.IREval
  ( DefeasibleRule(..)
  , ProofStep(..)
  , StrictRule(..)
  , Verdict(..)
  , checkPresuppositions
  , defeasibleFire
  , detectConflict
  , entailmentVerdict
  , forwardChain
  )

-- ---------------------------------------------------------------------------
-- File row types (moved verbatim from Test.Suite.SemanticIR).
-- ---------------------------------------------------------------------------

data RuleFileRow = RuleFileRow
  { frId :: !Text
  , frKind :: !Text
  , frPremises :: ![Text]
  , frConclusion :: !Text
  , frExceptions :: ![Text]
  , frPriority :: !(Maybe Int)
  , frScope :: !Text
  } deriving stock (Eq, Show)

instance FromJSON RuleFileRow where
  parseJSON = Aeson.withObject "RuleFileRow" $ \o -> RuleFileRow
    <$> o Aeson..: "id"
    <*> o Aeson..: "kind"
    <*> o Aeson..: "premises"
    <*> o Aeson..: "conclusion"
    <*> o Aeson..: "exceptions"
    <*> o Aeson..: "priority"
    <*> o Aeson..: "scope"

data InlineStrictRule = InlineStrictRule
  { isrPremises :: ![Text]
  , isrConclusion :: !Text
  } deriving stock (Eq, Show)

instance FromJSON InlineStrictRule where
  parseJSON = Aeson.withObject "InlineStrictRule" $ \o -> InlineStrictRule
    <$> o Aeson..: "premises"
    <*> o Aeson..: "conclusion"

data InlineDefRule = InlineDefRule
  { idrPremises :: ![Text]
  , idrConclusion :: !Text
  , idrExceptions :: ![Text]
  , idrPriority :: !Int
  , idrScope :: !Text
  } deriving stock (Eq, Show)

instance FromJSON InlineDefRule where
  parseJSON = Aeson.withObject "InlineDefRule" $ \o -> InlineDefRule
    <$> o Aeson..: "premises"
    <*> o Aeson..: "conclusion"
    <*> o Aeson..:? "exceptions" Aeson..!= []
    <*> o Aeson..:? "priority" Aeson..!= 0
    <*> o Aeson..:? "scope" Aeson..!= ""

data ExitTaskRow = ExitTaskRow
  { exitId :: !Text
  , exitKind :: !Text
  , exitFacts :: ![Text]
  , exitRules :: ![InlineDefRule]
  , exitRule :: !(Maybe InlineDefRule)
  , exitScope :: !Text
  , exitQuery :: !(Maybe Text)
  , exitExpected :: !Text
  , exitPresupps :: ![Text]
  } deriving stock (Eq, Show)

instance FromJSON ExitTaskRow where
  parseJSON = Aeson.withObject "ExitTaskRow" $ \o -> ExitTaskRow
    <$> o Aeson..: "id"
    <*> o Aeson..: "kind"
    <*> o Aeson..:? "facts" Aeson..!= []
    <*> o Aeson..:? "rules" Aeson..!= []
    <*> o Aeson..:? "rule"
    <*> o Aeson..:? "scope" Aeson..!= ""
    <*> o Aeson..:? "query"
    <*> o Aeson..: "expected"
    <*> o Aeson..:? "presupps" Aeson..!= []

data ExitStrictRow = ExitStrictRow
  { esrId :: !Text
  , esrFacts :: ![Text]
  , esrRules :: ![InlineStrictRule]
  , esrQuery :: !Text
  , esrExpected :: !Text
  } deriving stock (Eq, Show)

instance FromJSON ExitStrictRow where
  parseJSON = Aeson.withObject "ExitStrictRow" $ \o -> ExitStrictRow
    <$> o Aeson..: "id"
    <*> o Aeson..:? "facts" Aeson..!= []
    <*> o Aeson..:? "rules" Aeson..!= []
    <*> o Aeson..: "query"
    <*> o Aeson..: "expected"

data ExpectTurns = AllTurns | TurnIndices [Int]
  deriving stock (Eq, Show)

instance FromJSON ExpectTurns where
  parseJSON (Aeson.String "all") = pure AllTurns
  parseJSON v = TurnIndices <$> Aeson.parseJSON v

data ScenarioExpectation = ScenarioExpectation
  { expKind :: !Text
  , expTurns :: !ExpectTurns
  , expQuery :: !(Maybe Text)
  } deriving stock (Eq, Show)

instance FromJSON ScenarioExpectation where
  parseJSON = Aeson.withObject "ScenarioExpectation" $ \o -> ScenarioExpectation
    <$> o Aeson..: "kind"
    <*> o Aeson..: "turns"
    <*> o Aeson..:? "query"

data ScenarioTurnRow = ScenarioTurnRow
  { turnSpeaker :: !Text
  , turnText :: !Text
  , turnInterpretations :: ![Text]
  , turnAct :: !Text
  , turnUnresolved :: ![Text]
  } deriving stock (Eq, Show)

instance FromJSON ScenarioTurnRow where
  parseJSON = Aeson.withObject "ScenarioTurnRow" $ \o -> ScenarioTurnRow
    <$> o Aeson..: "speaker"
    <*> o Aeson..: "text"
    <*> o Aeson..: "interpretations"
    <*> o Aeson..: "act"
    <*> o Aeson..: "unresolved"

data ScenarioRow = ScenarioRow
  { scenarioId :: !Text
  , scenarioTurns :: ![ScenarioTurnRow]
  , scenarioProvenance :: !Text
  } deriving stock (Eq, Show)

instance FromJSON ScenarioRow where
  parseJSON = Aeson.withObject "ScenarioRow" $ \o -> ScenarioRow
    <$> o Aeson..: "id"
    <*> o Aeson..: "turns"
    <*> o Aeson..: "provenance"

data ScenarioRowEx = ScenarioRowEx
  { scExId :: !Text
  , scExTurns :: ![ScenarioTurnRow]
  , scExExpectations :: ![ScenarioExpectation]
  } deriving stock (Eq, Show)

instance FromJSON ScenarioRowEx where
  parseJSON = Aeson.withObject "ScenarioRowEx" $ \o -> ScenarioRowEx
    <$> o Aeson..: "id"
    <*> o Aeson..: "turns"
    <*> o Aeson..: "expectations"

-- ---------------------------------------------------------------------------
-- Total row readers and rule builders.
-- ---------------------------------------------------------------------------

-- | Lenient JSONL reader (moved verbatim): silently drops blank
-- and undecodable lines. The suite keeps this behavior;
-- the emitter uses it too (a corrupt committed file surfaces
-- as a count mismatch in the summary gate).
readJsonlRowsLenient :: (FromJSON a) => FilePath -> IO [a]
readJsonlRowsLenient path = do
  content <- BL.readFile path
  pure [ r | line <- BL.split 10 content
           , not (BL.null line)
           , Just r <- [Aeson.decode line] ]

-- | Total s-expression parse: 'Left' carries the data context.
parseRowEither :: Text -> Text -> Either String Proposition
parseRowEither ctx sexpr = case parseProposition sexpr of
  Just p -> Right p
  Nothing -> Left ("sexpr must parse (" <> T.unpack ctx <> "): " <> T.unpack (T.take 80 sexpr))

toStrictEither :: RuleFileRow -> Either String StrictRule
toStrictEither r = StrictRule (frId r)
  <$> mapM (parseRowEither (frId r)) (frPremises r)
  <*> parseRowEither (frId r) (frConclusion r)

toDefeasibleEither :: RuleFileRow -> Either String DefeasibleRule
toDefeasibleEither r = DefeasibleRule (frId r)
  <$> mapM (parseRowEither (frId r)) (frPremises r)
  <*> parseRowEither (frId r) (frConclusion r)
  <*> mapM (parseRowEither (frId r)) (frExceptions r)
  <*> pure (case frPriority r of Just n -> n; Nothing -> 0)
  <*> pure (frScope r)

toDefRuleEither :: Text -> InlineDefRule -> Either String DefeasibleRule
toDefRuleEither ctx r = DefeasibleRule ctx
  <$> mapM (parseRowEither ctx) (idrPremises r)
  <*> parseRowEither ctx (idrConclusion r)
  <*> mapM (parseRowEither ctx) (idrExceptions r)
  <*> pure (idrPriority r)
  <*> pure (idrScope r)

toStrictFileRuleEither :: RuleFileRow -> Either String StrictRule
toStrictFileRuleEither = toStrictEither

-- ---------------------------------------------------------------------------
-- Shared predicates (moved verbatim).
-- ---------------------------------------------------------------------------

contradictory :: Proposition -> Proposition -> Bool
contradictory (Not p) q = p == q
contradictory p (Not q) = p == q
contradictory _ _ = False

-- | Duel resolution (frozen doctrine): both fire and contradict
-- -> higher priority wins; tie -> both stand and the conflict is kept
-- (paraconsistency, not silent suppression).
resolveDuel :: Text -> DefeasibleRule -> DefeasibleRule -> [Proposition] -> Text
resolveDuel scope r1 r2 facts =
  case (defeasibleFire scope r1 facts, defeasibleFire scope r2 facts) of
    (Right c1, Right c2)
      | contradictory c1 c2 ->
          if drPriority r1 > drPriority r2 then "higher-wins"
          else if drPriority r2 > drPriority r1 then "higher-wins"
          else "tie-kept"
      | otherwise -> "both-stand"
    _ -> "no-duel"

-- ---------------------------------------------------------------------------
-- Task outcomes.
-- ---------------------------------------------------------------------------

data StrictOutcome = StrictOutcome
  { soPass :: !Bool
  , soEntailed :: !Bool
  , soProof :: ![ProofStep]
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

runStrictDetail :: ExitStrictRow -> Either String StrictOutcome
runStrictDetail row = do
  facts <- mapM (parseRowEither (esrId row)) (esrFacts row)
  rules <- mapM (\(i, r) -> toStrictInline (esrId row) i r) (zip [0 :: Int ..] (esrRules row))
  query <- parseRowEither (esrId row) (esrQuery row)
  let (closed, proof) = forwardChain 32 rules facts
      entailed = query `elem` closed
  pass <- case esrExpected row of
    "entails" -> Right entailed
    "not-entailed" -> Right (not entailed)
    other -> Left ("unknown strict expectation: " <> T.unpack other)
  pure (StrictOutcome pass entailed proof)
  where
    toStrictInline ctx i r = StrictRule (ctx <> "#s" <> T.pack (show i))
      <$> mapM (parseRowEither ctx) (isrPremises r)
      <*> parseRowEither ctx (isrConclusion r)

-- | Batch A (2026-10-07): the logical verdict for a strict task,
-- via 'entailmentVerdict' (fuel 32, same budget as the harness).
runStrictVerdict :: ExitStrictRow -> Either String Verdict
runStrictVerdict row = do
  facts <- mapM (parseRowEither (esrId row)) (esrFacts row)
  rules <- mapM (\(i, r) -> toStrictInline (esrId row) i r) (zip [0 :: Int ..] (esrRules row))
  query <- parseRowEither (esrId row) (esrQuery row)
  pure (entailmentVerdict 32 rules facts query)
  where
    toStrictInline ctx i r = StrictRule (ctx <> "#s" <> T.pack (show i))
      <$> mapM (parseRowEither ctx) (isrPremises r)
      <*> parseRowEither ctx (isrConclusion r)

data DefOutcome = DefOutcome
  { dfoPass :: !Bool
  , dfoDetail :: !Text
  , dfoVerdict :: !(Maybe Verdict)
    -- ^ Batch A (schema v2): the logical verdict for single
    -- firings ('Entails []' on fire, 'DefeatedBy' on block);
    -- 'Nothing' for duels (resolution outcome, not a verdict).
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

runDefeasibleDetail :: ExitTaskRow -> Either String DefOutcome
runDefeasibleDetail row = case exitKind row of
  "defeasible" -> case exitRule row of
    Nothing -> Left ("defeasible needs rule: " <> T.unpack (exitId row))
    Just inline -> do
      rule <- toDefRuleEither (exitId row) inline
      facts <- mapM (parseRowEither (exitId row)) (exitFacts row)
      Right $ case (defeasibleFire (exitScope row) rule facts, exitExpected row) of
        (Right _, "fires") -> DefOutcome True "fires" (Just (Entails []))
        (Left exc, "blocked") -> DefOutcome True "blocked" (Just (DefeatedBy (exitId row) exc))
        (Right _, _) -> DefOutcome False "fired-unexpected" (Just (Entails []))
        (Left exc, _) -> DefOutcome False "blocked-unexpected" (Just (DefeatedBy (exitId row) exc))
  "defeasible-duel" -> do
    rules <- mapM (toDefRuleEither (exitId row)) (exitRules row)
    facts <- mapM (parseRowEither (exitId row)) (exitFacts row)
    case rules of
      [r1, r2] ->
        let got = resolveDuel (exitScope row) r1 r2 facts
        in Right (DefOutcome (got == exitExpected row) got Nothing)
      _ -> Left ("duel needs two rules: " <> T.unpack (exitId row))
  other -> Left ("unknown defeasible kind: " <> T.unpack other)

data ConflictOutcome = ConflictOutcome
  { coPass :: !Bool
  , coFound :: !Bool
  , coVerdict :: !(Maybe Verdict)
    -- ^ Batch A (schema v2): 'Just (Conflict p q)' when a
    -- conflicting pair is found, 'Nothing' otherwise.
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

runConflictDetail :: ExitTaskRow -> Either String ConflictOutcome
runConflictDetail row = do
  facts <- mapM (parseRowEither (exitId row)) (exitFacts row)
  let foundPair = detectConflict facts
      found = case foundPair of
        Just _ -> True
        Nothing -> False
  pass <- case exitExpected row of
    "conflict" -> Right found
    "none" -> Right (not found)
    want -> Left ("conflict mismatch on " <> T.unpack (exitId row) <> ": want " <> T.unpack want)
  pure (ConflictOutcome pass found (uncurry Conflict <$> foundPair))

data PresupOutcome = PresupOutcome
  { poPass :: !Bool
  , poHeld :: ![Bool]
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

runPresupDetail :: ExitTaskRow -> Either String PresupOutcome
runPresupDetail row = do
  facts <- mapM (parseRowEither (exitId row)) (exitFacts row)
  presupps <- mapM (parseRowEither (exitId row)) (exitPresupps row)
  let held = [ ok | (_, ok) <- checkPresuppositions facts presupps ]
  pass <- case exitExpected row of
    "all-held" -> Right (and held)
    "missing" -> Right (not (and held))
    other -> Left ("unknown presupposition expectation: " <> T.unpack other)
  pure (PresupOutcome pass held)

-- | Scenario soundness expectations over the file strict rules.
-- Returns (scenario id, expectation kind, holds) per expectation.
runScenarioDetail :: [StrictRule] -> ScenarioRowEx -> Either String [(Text, Text, Bool)]
runScenarioDetail rules row = mapM (runExpectation rules row) (scExExpectations row)

runExpectation :: [StrictRule] -> ScenarioRowEx -> ScenarioExpectation -> Either String (Text, Text, Bool)
runExpectation rules row exp = do
  let selected = case expTurns exp of
        AllTurns -> scExTurns row
        TurnIndices idxs -> [ t | (i, t) <- zip [0 :: Int ..] (scExTurns row), i `elem` idxs ]
  kb <- concat <$> mapM (parseTurn (scExId row)) selected
  case expKind exp of
    "no-conflict" -> pure (scExId row, expKind exp, detectConflict kb == Nothing)
    "not-entailed" -> case expQuery exp of
      Nothing -> Left ("not-entailed needs query: " <> T.unpack (scExId row))
      Just q -> do
        query <- parseRowEither (scExId row) q
        let (closed, _) = forwardChain 32 rules kb
        pure (scExId row, expKind exp, not (query `elem` closed))
    "entails" -> case expQuery exp of
      Nothing -> Left ("entails needs query: " <> T.unpack (scExId row))
      Just q -> do
        query <- parseRowEither (scExId row) q
        let (closed, _) = forwardChain 32 rules kb
        pure (scExId row, expKind exp, query `elem` closed)
    other -> Left ("unknown expectation kind: " <> T.unpack other)
  where
    parseTurn sid turn = mapM (parseRowEither sid) (turnInterpretations turn)

-- | File composition row (Batch C): self-contained composite
-- with inline base rules (mirrors exit-task inline rules, no
-- coupling to rules.jsonl). Domain data waits for Batch E;
-- the two shipped rows are abstract machinery checks.
data FileComposition = FileComposition
  { fcId :: !Text
  , fcRules :: ![InlineStrictRule]
  , fcExtraPremises :: ![Text]
  , fcAddedConclusions :: ![Text]
  , fcBlocked :: ![Text]
  } deriving stock (Eq, Show)

instance FromJSON FileComposition where
  parseJSON = Aeson.withObject "FileComposition" $ \o -> FileComposition
    <$> o Aeson..: "id"
    <*> o Aeson..:? "rules" Aeson..!= []
    <*> o Aeson..:? "extra_premises" Aeson..!= []
    <*> o Aeson..:? "added_conclusions" Aeson..!= []
    <*> o Aeson..:? "blocked" Aeson..!= []

-- | Expand file composites into named strict-rule sets.
expandFileComposites :: FileComposition -> Either String (Text, [StrictRule])
expandFileComposites fc = do
  bases <- mapM (\(i, r) -> toStrictInline (fcId fc) i r) (zip [0 :: Int ..] (fcRules fc))
  extra <- mapM (parseRowEither (fcId fc)) (fcExtraPremises fc)
  added <- mapM (parseRowEither (fcId fc)) (fcAddedConclusions fc)
  blocked <- mapM (parseRowEither (fcId fc)) (fcBlocked fc)
  expanded <- expandComposition (CompositionDef (fcId fc) bases extra added blocked)
  pure (fcId fc, expanded)
  where
    toStrictInline ctx i r = StrictRule (ctx <> "#s" <> T.pack (show i))
      <$> mapM (parseRowEither ctx) (isrPremises r)
      <*> parseRowEither ctx (isrConclusion r)

-- ---------------------------------------------------------------------------
-- JSON trace schema (ADR-0054 §2.3). Provenance tags mark every
-- derived claim as shadow evaluation output, never curated fact.
-- ---------------------------------------------------------------------------

-- | Frozen provenance tag stamped on every emitted trace.
traceProvenance :: Text
traceProvenance = "stage1-shadow"

data ExitTrace = ExitTrace
  { etId :: !Text
  , etKind :: !Text
  , etExpected :: !Text
  , etPass :: !Bool
  , etProvenance :: !Text
  , etStrict :: !(Maybe StrictOutcome)
  , etDefeasible :: !(Maybe DefOutcome)
  , etConflict :: !(Maybe ConflictOutcome)
  , etPresup :: !(Maybe PresupOutcome)
  , etVerdict :: !(Maybe Verdict)
    -- ^ Batch A (schema v2): the logical verdict where the task
    -- kind admits one (strict, single defeasible, conflict-found).
    -- Old fields kept; readers ignore unknown/missing fields.
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

data ScenarioTrace = ScenarioTrace
  { stId :: !Text
  , stKind :: !Text
  , stPass :: !Bool
  , stProvenance :: !Text
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

data BatchSummary = BatchSummary
  { bsExitTotal :: !Int
  , bsStrict :: !(Int, Int)
  , bsDefeasible :: !(Int, Int)
  , bsConflicts :: !(Int, Int)
  , bsPresuppositions :: !(Int, Int)
  , bsScenarios :: !(Int, Int)
  , bsGatesPass :: !Bool
  , bsProvenance :: !Text
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)
