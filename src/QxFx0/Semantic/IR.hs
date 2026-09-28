{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Semantic.IR
Description : canonical — executable semantic IR skeleton (Stage-0 miniature).

Status (2026-09-28): SHADOW ONLY. Nothing in the runtime calls this
module. It is the types-first landing of the meaning-machine thesis:
terms and propositions as data, a tiny total s-expression syntax for
hand-authored gold parses, and a structural validator. Selection,
rendering, and persistence are untouched; wiring needs its own
pre-registered landing (shadow → trace → gated cutover, like every
other regime).

An 'Atom' ('QxFx0.Types.Semantic.AtomGraph') is a curated utterance
node (surface + provenance). An IR 'Proposition' is a claim about the
world: ownable, negatable, comparable, checkable. The two layers are
deliberately different things; the bridge between them is future work,
not an import.

Validator discipline (structural, frozen v1):
  * 'Apply' carries at least one role binding (a predicate opens roles).
  * Quantifiers bind a variable that occurs in the body (no vacuous
    quantification).
  * A top-level proposition is closed (no free variables): unresolved
    references belong to 'Interpretation.unresolved', not to the claim.

s-expression grammar (total parser 'parseProposition', 'Nothing' on
any malformed input):

  prop := (Apply pred ((role term)*))
        | (Not prop) | (And prop+) | (Or prop+)
        | (Implies prop prop)
        | (Forall var prop) | (Exists var prop)
        | (Modal mod prop) | (AtTime t prop) | (InScope s prop)
  term := ?var | (Concept id) | (Entity id) | (Event id)

Conventions for the gold corpus: predicates, roles, modalities and
concept ids are lowercase English tokens ('require', 'agent',
'freedom'); variables are '?'-prefixed ('?x'); Russian lives only in
the 'text' field of a gold row, never in the 'sexpr' field.
-}
module QxFx0.Semantic.IR
  ( -- * Identifiers
    EntityId(..)
  , ConceptId(..)
  , PredicateId(..)
  , VarId(..)
  , EventId(..)
    -- * Terms and propositions
  , Quantifier(..)
  , Modality(..)
  , Term(..)
  , RoleBinding(..)
  , Proposition(..)
    -- * Interpretation (one utterance, possibly several)
  , SpeechAct(..)
  , Interpretation(..)
    -- * Structural validation (total)
  , freeVariables
  , validateProposition
  , validateClosedProposition
    -- * s-expression surface (total both ways)
  , prettyProposition
  , parseProposition
  ) where

import Control.DeepSeq (NFData)
import Data.Set (Set)
import qualified Data.Set as S
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

newtype EntityId = EntityId { unEntityId :: Text }
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData)

newtype ConceptId = ConceptId { unConceptId :: Text }
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData)

newtype PredicateId = PredicateId { unPredicateId :: Text }
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData)

newtype VarId = VarId { unVarId :: Text }
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData)

newtype EventId = EventId { unEventId :: Text }
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData)

data Quantifier
  = Forall
  | Exists
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData)

data Modality
  = Necessary
  | Possible
  | Obligatory
  | Permitted
  | Believed
  | Asserted
  | Hypothetical
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData)

data Term
  = Entity EntityId
  | Concept ConceptId
  | Variable VarId
  | Event EventId
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData)

data RoleBinding = RoleBinding
  { rbRole :: !Text
  , rbTerm :: !Term
  } deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData)

data Proposition
  = Apply PredicateId [RoleBinding]
  | Not Proposition
  | And [Proposition]
  | Or [Proposition]
  | Implies Proposition Proposition
  | Quantified Quantifier VarId Proposition
  | Modal Modality Proposition
  | AtTime Text Proposition
  | InScope Text Proposition
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData)

data SpeechAct
  = ActAssert
  | ActAskDefine
  | ActChallenge
  | ActClarify
  | ActConcede
  | ActHypothesize
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (NFData)

-- | One utterance may carry several interpretations; each is explicit,
-- evidenced, and independently committable. The runtime does not read
-- this type yet (shadow).
data Interpretation = Interpretation
  { inProposition :: !Proposition
  , inSpeechAct :: !SpeechAct
  , inBindings :: ![(Text, Text)]
  , inEvidence :: ![Text]
  , inUnresolved :: ![Text]
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData)

-- | All variables occurring free (unbound by an enclosing quantifier).
freeVariables :: Proposition -> Set VarId
freeVariables = go S.empty
  where
    go bound prop = case prop of
      Apply _ args -> S.unions (map (termFree bound . rbTerm) args)
      Not p -> go bound p
      And ps -> S.unions (map (go bound) ps)
      Or ps -> S.unions (map (go bound) ps)
      Implies p q -> go bound p `S.union` go bound q
      Quantified _ v p -> go (S.insert v bound) p
      Modal _ p -> go bound p
      AtTime _ p -> go bound p
      InScope _ p -> go bound p
    termFree bound term = case term of
      Variable v | v `S.member` bound -> S.empty
                 | otherwise -> S.singleton v
      _ -> S.empty

-- | Structural validity. 'Nothing' means valid; 'Just' carries the
-- first violation found (deterministic order: shape, then children).
validateProposition :: Proposition -> Maybe Text
validateProposition prop = case prop of
  Apply (PredicateId p) []
    | T.null (T.strip p) -> Just "apply: empty predicate"
    | otherwise -> Just "apply: predicate opens no roles"
  Apply _ args -> firstJust
    [ if T.null (T.strip (rbRole b)) then Just "apply: empty role" else Nothing
    | b <- args
    ]
  Not p -> validateProposition p
  And [] -> Just "and: empty conjunction"
  And ps -> firstJust (map validateProposition ps)
  Or [] -> Just "or: empty disjunction"
  Or ps -> firstJust (map validateProposition ps)
  Implies p q -> firstJust [validateProposition p, validateProposition q]
  Quantified _ v p
    | v `S.notMember` allVariables p -> Just "quantified: vacuous binding"
    | otherwise -> validateProposition p
  Modal _ p -> validateProposition p
  AtTime t p
    | T.null (T.strip t) -> Just "attime: empty time ref"
    | otherwise -> validateProposition p
  InScope s p
    | T.null (T.strip s) -> Just "inscope: empty scope"
    | otherwise -> validateProposition p
  where
    firstJust = foldr (\m acc -> case m of Just _ -> m; Nothing -> acc) Nothing

-- | Top-level closedness: no free variables. Unresolved references
-- belong to 'Interpretation.inUnresolved', never to a bare claim.
-- The gold corpus asserts this for every row alongside
-- 'validateProposition'.
validateClosedProposition :: Proposition -> Maybe Text
validateClosedProposition prop
  | S.null (freeVariables prop) = Nothing
  | otherwise = Just "closed: free variables escape"

-- | Every variable occurring anywhere (free or bound): the vacuity check.
allVariables :: Proposition -> Set VarId
allVariables prop = case prop of
  Apply _ args -> S.unions (map (termVars . rbTerm) args)
  Not p -> allVariables p
  And ps -> S.unions (map allVariables ps)
  Or ps -> S.unions (map allVariables ps)
  Implies p q -> allVariables p `S.union` allVariables q
  Quantified _ v p -> S.insert v (allVariables p)
  Modal _ p -> allVariables p
  AtTime _ p -> allVariables p
  InScope _ p -> allVariables p
  where
    termVars (Variable v) = S.singleton v
    termVars _ = S.empty

-- | Canonical s-expression rendering. 'parseProposition . prettyProposition'
-- is the identity on valid inputs (pinned by unit tests).
prettyProposition :: Proposition -> Text
prettyProposition prop = case prop of
  Apply (PredicateId p) args ->
    "(Apply " <> p <> " (" <> T.intercalate " " ["(" <> rbRole b <> " " <> prettyTerm (rbTerm b) <> ")" | b <- args] <> "))"
  Not p -> "(Not " <> prettyProposition p <> ")"
  And ps -> "(And" <> T.concat [" " <> prettyProposition p | p <- ps] <> ")"
  Or ps -> "(Or" <> T.concat [" " <> prettyProposition p | p <- ps] <> ")"
  Implies p q -> "(Implies " <> prettyProposition p <> " " <> prettyProposition q <> ")"
  Quantified Forall (VarId v) p -> "(Forall " <> v <> " " <> prettyProposition p <> ")"
  Quantified Exists (VarId v) p -> "(Exists " <> v <> " " <> prettyProposition p <> ")"
  Modal m p -> "(Modal " <> T.pack (show m) <> " " <> prettyProposition p <> ")"
  AtTime t p -> "(AtTime " <> t <> " " <> prettyProposition p <> ")"
  InScope s p -> "(InScope " <> s <> " " <> prettyProposition p <> ")"

prettyTerm :: Term -> Text
prettyTerm term = case term of
  Entity (EntityId i) -> "(Entity " <> i <> ")"
  Concept (ConceptId i) -> "(Concept " <> i <> ")"
  Variable (VarId v) -> v
  Event (EventId i) -> "(Event " <> i <> ")"

-- | Total s-expression parser. 'Nothing' on any malformed input:
-- unbalanced parens, unknown heads, wrong arity, empty atoms.
parseProposition :: Text -> Maybe Proposition
parseProposition input = case parseTokens (tokenize input) of
  Just (prop, []) -> Just prop
  _ -> Nothing

tokenize :: Text -> [Text]
tokenize = filter (not . T.null) . T.words . markParens
  where
    markParens = T.replace "(" " ( " . T.replace ")" " ) "

parseTokens :: [Text] -> Maybe (Proposition, [Text])
parseTokens ("(":rest) = do
  (head_, afterHead) <- case rest of
    [] -> Nothing
    (h:hs) -> Just (h, hs)
  case head_ of
    "Apply" -> parseApply afterHead
    "Not" -> do
      (p, r1) <- parseProp afterHead
      case r1 of
        ")":r2 -> Just (Not p, r2)
        _ -> Nothing
    "And" -> parseMany And afterHead
    "Or" -> parseMany Or afterHead
    "Implies" -> do
      (p, r1) <- parseProp afterHead
      (q, r2) <- parseProp r1
      case r2 of
        ")":r3 -> Just (Implies p q, r3)
        _ -> Nothing
    "Forall" -> parseQuantified Forall afterHead
    "Exists" -> parseQuantified Exists afterHead
    "Modal" -> do
      (m, r1) <- case afterHead of
        (x:xs) -> flip (,) xs <$> parseModality x
        [] -> Nothing
      (p, r2) <- parseProp r1
      case r2 of
        ")":r3 -> Just (Modal m p, r3)
        _ -> Nothing
    "AtTime" -> parseScoped AtTime afterHead
    "InScope" -> parseScoped InScope afterHead
    _ -> Nothing
parseTokens _ = Nothing

parseProp :: [Text] -> Maybe (Proposition, [Text])
parseProp ("(":rest) = parseTokens ("(":rest)
parseProp _ = Nothing

parseApply :: [Text] -> Maybe (Proposition, [Text])
parseApply (pred_:rest)
  | T.null pred_ || pred_ == ")" = Nothing
  | otherwise = do
      (bindings, r1) <- parseBindings rest
      case r1 of
        ")":r2 -> Just (Apply (PredicateId pred_) bindings, r2)
        _ -> Nothing
parseApply [] = Nothing

parseBindings :: [Text] -> Maybe ([RoleBinding], [Text])
parseBindings ("(":rest) = parseItems rest
  where
    parseItems (")":r) = Just ([], r)
    parseItems ("(":role:rest2) = do
      (term, r1) <- parseTerm rest2
      case r1 of
        ")":r2 -> do
          (more, r3) <- parseItems r2
          Just (RoleBinding role term : more, r3)
        _ -> Nothing
    parseItems _ = Nothing
parseBindings _ = Nothing

parseTerm :: [Text] -> Maybe (Term, [Text])
parseTerm ("(":kind:ident:")":rest)
  | kind == "Concept" = Just (Concept (ConceptId ident), rest)
  | kind == "Entity" = Just (Entity (EntityId ident), rest)
  | kind == "Event" = Just (Event (EventId ident), rest)
  | otherwise = Nothing
parseTerm (tok:rest)
  | "?" `T.isPrefixOf` tok && T.length tok > 1 = Just (Variable (VarId tok), rest)
  | otherwise = Nothing
parseTerm [] = Nothing

parseMany :: ([Proposition] -> Proposition) -> [Text] -> Maybe (Proposition, [Text])
parseMany ctor toks = do
  (ps, rest) <- parseSome toks
  case rest of
    ")":r2 -> Just (ctor ps, r2)
    _ -> Nothing
  where
    parseSome ts = case ts of
      ")":_ -> Just ([], ts)
      _ -> do
        (p, r1) <- parseProp ts
        (more, r2) <- parseSome r1
        Just (p : more, r2)

parseQuantified :: Quantifier -> [Text] -> Maybe (Proposition, [Text])
parseQuantified q (var:rest)
  | "?" `T.isPrefixOf` var && T.length var > 1 = do
      (p, r1) <- parseProp rest
      case r1 of
        ")":r2 -> Just (Quantified q (VarId var) p, r2)
        _ -> Nothing
  | otherwise = Nothing
parseQuantified _ [] = Nothing

parseScoped :: (Text -> Proposition -> Proposition) -> [Text] -> Maybe (Proposition, [Text])
parseScoped ctor (scope:rest)
  | T.null scope || scope == ")" = Nothing
  | otherwise = do
      (p, r1) <- parseProp rest
      case r1 of
        ")":r2 -> Just (ctor scope p, r2)
        _ -> Nothing
parseScoped _ [] = Nothing

parseModality :: Text -> Maybe Modality
parseModality tok = case tok of
  "Necessary" -> Just Necessary
  "Possible" -> Just Possible
  "Obligatory" -> Just Obligatory
  "Permitted" -> Just Permitted
  "Believed" -> Just Believed
  "Asserted" -> Just Asserted
  "Hypothetical" -> Just Hypothetical
  _ -> Nothing
