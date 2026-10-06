{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Semantic.IREval
Description : canonical — shadow evaluator for Stage-1 IR rules.

Status (2026-09-29, ADR-0054 batch 3): SHADOW ONLY. Nothing in the
runtime calls this module. It executes the rule corpus
(@data\/semantic_ir\/rules.jsonl@) over IR fact bases: strict
forward chaining with proof objects, single-step defeasible firing
with exceptions, presupposition checks, and conflict detection.

Matching discipline (frozen v1, pre-registered 2026-09-29):
  * Structural: predicates, roles, and arities must coincide;
    'Concept'\/'Entity'\/'Event' match by identifier equality.
  * Pattern variables (free in the pattern) bind on first
    occurrence and must be consistent afterwards.
  * Binders ('Forall'\/'Exists') match only structurally with
    IDENTICAL variable names — no alpha-equivalence in v1.
    Gold and rules are authored with canonical names.
  * Total: every function terminates (forward chaining carries
    fuel; matching is structural recursion).

Priority discipline: strict rules always beat defeasible ones;
among contradictory defeasible conclusions the higher number
wins. Scope: a rule with non-empty scope fires only under an
equal query scope; empty scope fires anywhere.
-}
module QxFx0.Semantic.IREval
  ( -- * Substitutions and matching
    Subst(..)
  , matchPattern
  , applySubst
    -- * Rules, proofs and verdicts
  , StrictRule(..)
  , DefeasibleRule(..)
  , ProofStep(..)
  , Verdict(..)
  , SearchBoundary(..)
  , FuelReport(..)
  , FuelOutcome(..)
    -- * Strict forward chaining
  , forwardChain
  , forwardChainFuel
  , entailmentVerdict
    -- * Defeasible firing
  , defeasibleFire
    -- * Presuppositions and conflicts
  , checkPresuppositions
  , detectConflict
  ) where

import Data.Aeson (FromJSON, ToJSON)
import Data.List (foldl')
import qualified Data.Set as S
import Data.Text (Text)
import qualified Data.Text as T
import GHC.Generics (Generic)

import QxFx0.Semantic.IR
  ( ConceptId
  , EntityId
  , EventId
  , PredicateId(..)
  , Proposition(..)
  , Quantifier
  , RoleBinding(..)
  , Term(..)
  , VarId
  )

-- | Variable substitution: pattern variables to matched terms, as an
-- association list. Fresh matches only ever introduce new keys (bound
-- variables are substituted away before matching), so plain '(++)'
-- is a correct union here.
newtype Subst = Subst { unSubst :: [(VarId, Term)] }
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

-- | Match a pattern (possibly with free variables) against a fact.
-- Returns the binding substitution, or 'Nothing' on any shape
-- mismatch. Deterministic: first-occurrence binding wins; later
-- occurrences must agree (enforced by substituting the accumulated
-- substitution into the pattern before matching).
matchPattern :: Proposition -> Proposition -> Maybe Subst
matchPattern = matchWith []
  where
    matchWith subst pat fact = case matchShape subst pat fact of
      Nothing -> Nothing
      Just subst' -> Just (Subst subst')
    matchShape subst pat fact = case (applySubst (Subst subst) pat, fact) of
      (Apply p1 args1, Apply p2 args2)
        | p1 == p2 -> matchBindings subst args1 args2
        | otherwise -> Nothing
      (Not p, Not q) -> matchProp subst p q
      (And ps, And qs) -> matchList subst ps qs
      (Or ps, Or qs) -> matchList subst ps qs
      (Implies p1 q1, Implies p2 q2) -> do
        subst1 <- matchProp subst p1 p2
        matchProp subst1 q1 q2
      (Quantified qu1 v1 p, Quantified qu2 v2 q)
        | qu1 == qu2 && v1 == v2 -> matchProp subst p q
        | otherwise -> Nothing
      (Modal m1 p, Modal m2 q)
        | m1 == m2 -> matchProp subst p q
        | otherwise -> Nothing
      (AtTime t1 p, AtTime t2 q)
        | t1 == t2 -> matchProp subst p q
        | otherwise -> Nothing
      (InScope s1 p, InScope s2 q)
        | s1 == s2 -> matchProp subst p q
        | otherwise -> Nothing
      _ -> Nothing
    -- NOTE (pre-registered): binding arities must coincide, like
    -- every other shape in the matcher. A rule constrains whole
    -- bindings; partial patterns are written as separate rules.
    matchBindings subst [] [] = Just subst
    matchBindings subst (RoleBinding r1 t1 : bs1) (RoleBinding r2 t2 : bs2)
      | r1 == r2 = do
          subst' <- matchTerm subst t1 t2
          matchBindings subst' bs1 bs2
      | otherwise = Nothing
    matchBindings _ _ _ = Nothing
    matchList subst [] [] = Just subst
    matchList subst (p:ps) (q:qs) = do
      subst' <- matchProp subst p q
      matchList subst' ps qs
    matchList _ _ _ = Nothing
    matchProp subst p q = matchShape subst p q
    matchTerm subst pat fc = case (pat, fc) of
      (Variable v, t) -> case lookup v subst of
        Nothing -> Just ((v, t) : subst)
        Just t' | t' == t -> Just subst
                | otherwise -> Nothing
      (Concept c1, Concept c2) | c1 == c2 -> Just subst
      (Entity e1, Entity e2) | e1 == e2 -> Just subst
      (Event v1, Event v2) | v1 == v2 -> Just subst
      _ -> Nothing

-- | Apply a substitution to a proposition.
applySubst :: Subst -> Proposition -> Proposition
applySubst subst@(Subst m) prop = case prop of
  Apply p args -> Apply p [ RoleBinding r (substTerm t) | RoleBinding r t <- args ]
  Not p -> Not (go p)
  And ps -> And (map go ps)
  Or ps -> Or (map go ps)
  Implies p q -> Implies (go p) (go q)
  Quantified qu v p -> Quantified qu v (go p)
  Modal md p -> Modal md (go p)
  AtTime t p -> AtTime t (go p)
  InScope s p -> InScope s (go p)
  where
    go = applySubst subst
    substTerm t = case t of
      Variable v -> case lookup v m of
        Just t' -> t'
        Nothing -> t
      _ -> t

-- | A strict rule: identifier, premise patterns, conclusion pattern.
data StrictRule = StrictRule
  { srId :: !Text
  , srPremises :: ![Proposition]
  , srConclusion :: !Proposition
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

-- | A defeasible rule: premises, conclusion, blocking exceptions,
-- priority (higher wins), and scope (empty fires anywhere).
data DefeasibleRule = DefeasibleRule
  { drId :: !Text
  , drPremises :: ![Proposition]
  , drConclusion :: !Proposition
  , drExceptions :: ![Proposition]
  , drPriority :: !Int
  , drScope :: !Text
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

-- | One derived step: which rule, which base indices, under which
-- substitution, yielding what conclusion.
data ProofStep = ProofStep
  { psRuleId :: !Text
  , psPremiseIndices :: ![Int]
  , psSubstitution :: !Subst
  , psConclusion :: !Proposition
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

-- | Evaluation verdicts. JSON-serializable for the trace scripts.
-- Batch A (2026-10-07): 'Refuted' and the 'NotEntailed' payload
-- distinguish known-false from unproven. 'AmbiguousInterpretation'
-- is deferred (needs interpretation alternatives — Batch D/E).
data Verdict
  = Entails ![ProofStep]
  | Refuted ![ProofStep]
  | NotEntailed !SearchBoundary
  | DefeatedBy !Text !Proposition
  | Conflict !Proposition !Proposition
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

-- | Why a query is not entailed. Carries the reason so traces and
-- exit metrics never conflate false / unknown / under-resourced.
data SearchBoundary
  = OpenWorldMissingFacts
    -- ^ Fixpoint reached, neither the query nor its negation derived:
    -- absence of proof, not proof of absence.
  | FuelExhausted !FuelReport
    -- ^ The fuel budget ran out with rules still firing: the search
    -- was cut short, not completed.
  | UnsupportedPredicate
    -- ^ The query mentions predicates outside the rules+facts
    -- inventory: no derivation could even start.
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

-- | Fuel accounting for a bounded forward-chaining run.
data FuelReport = FuelReport
  { frFuelAllocated :: !Int
  , frRulesFired :: !Int
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

-- | How a bounded forward-chaining run terminated.
data FuelOutcome
  = ReachedFixpoint
  | ExhaustedFuel !Int
    -- ^ Fuel consumed when the budget ran out with rules pending.
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

-- | Forward-chain strict rules over a fact base with fuel. Each
-- iteration fires every rule whose premises match (premises may match
-- facts or previously derived conclusions), appending each new
-- conclusion once (structural equality). Terminates on fixpoint or
-- fuel exhaustion. Returns the closed base plus the proof trace in
-- derivation order (deterministic: rules and facts in given order).
forwardChain :: Int -> [StrictRule] -> [Proposition] -> ([Proposition], [ProofStep])
forwardChain fuel rules facts =
  let (closed, proof, _) = forwardChainFuel fuel rules facts
  in (closed, proof)

-- | Bounded forward chaining with a fuel outcome. At budget
-- exhaustion one extra dry round distinguishes a fixpoint that
-- coincides with fuel-out ('ReachedFixpoint') from a cut-short
-- search ('ExhaustedFuel').
forwardChainFuel :: Int -> [StrictRule] -> [Proposition] -> ([Proposition], [ProofStep], FuelOutcome)
forwardChainFuel fuel rules facts = go fuel facts []
  where
    go 0 base proof =
      let (_, newSteps) = foldl' fireRule (base, []) rules
      in (base, proof, if null newSteps then ReachedFixpoint else ExhaustedFuel fuel)
    go n base proof =
      let (base', newSteps) = foldl' fireRule (base, []) rules
      in if null newSteps
           then (base, proof, ReachedFixpoint)
           else go (n - 1) base' (proof ++ newSteps)
    fireRule (base, steps) rule =
      case matchPremises base (srPremises rule) of
        Nothing -> (base, steps)
        Just (subst, indices) ->
          let derived = applySubst subst (srConclusion rule)
          in if derived `elem` base
               then (base, steps)
               else (base ++ [derived], steps ++ [ProofStep (srId rule) indices subst derived])
    matchPremises base premises = goPremises [] [] (zip [0 :: Int ..] premises)
      where
        goPremises subst indices [] = Just (Subst subst, indices)
        goPremises subst indices ((i, pat) : rest) =
          case [ (j, s) | (j, fact) <- zip [0 :: Int ..] base
                        , Just s <- [matchWith subst pat fact] ] of
            [] -> Nothing
            ((j, s) : _) -> goPremises (unSubst s) (indices ++ [j]) rest
        matchWith subst pat fact = matchPattern (applySubst (Subst subst) pat) fact >>= unionSubst subst
        unionSubst subst (Subst s) = Just (Subst (s ++ subst))

-- | Total strict-evaluation verdict for one query. Priority:
-- entailed, then explicitly refuted (negation entailed), then
-- structurally unsupported predicates, then fuel exhaustion, else
-- open-world absence of proof. The 'Entails'/'Refuted' proof is the
-- whole derivation trace in derivation order; dependency-sliced
-- proofs arrive with Batch D lineage.
entailmentVerdict :: Int -> [StrictRule] -> [Proposition] -> Proposition -> Verdict
entailmentVerdict fuel rules facts query =
  let (closed, proof, fuelOut) = forwardChainFuel fuel rules facts
  in if query `elem` closed
       then Entails proof
       else if negateProposition query `elem` closed
         then Refuted proof
         else if not (propositionPredicates query `S.isSubsetOf` inventoryPredicates rules facts)
           then NotEntailed UnsupportedPredicate
           else case fuelOut of
             ExhaustedFuel _ -> NotEntailed (FuelExhausted (FuelReport fuel (length proof)))
             ReachedFixpoint -> NotEntailed OpenWorldMissingFacts
  where
    negateProposition (Not p) = p
    negateProposition p = Not p
    inventoryPredicates rs fs =
      S.unions (map rulePredicates rs ++ map propositionPredicates fs)
    rulePredicates r =
      S.unions (map propositionPredicates (srPremises r))
        `S.union` propositionPredicates (srConclusion r)

-- | Predicate identifiers occurring anywhere in a proposition.
propositionPredicates :: Proposition -> S.Set Text
propositionPredicates prop = case prop of
  Apply (PredicateId p) args ->
    S.insert p (S.unions (map (termPredicates . rbTerm) args))
  Not p -> propositionPredicates p
  And ps -> S.unions (map propositionPredicates ps)
  Or ps -> S.unions (map propositionPredicates ps)
  Implies p q -> propositionPredicates p `S.union` propositionPredicates q
  Quantified _ _ p -> propositionPredicates p
  Modal _ p -> propositionPredicates p
  AtTime _ p -> propositionPredicates p
  InScope _ p -> propositionPredicates p
  where
    termPredicates _ = S.empty

-- | Attempt one defeasible firing under a query scope. Returns the
-- instantiated conclusion, or the blocking exception (premises
-- unsatisfied and scope mismatch surface as synthetic localized
-- propositions, never as silent failure).
defeasibleFire :: Text -> DefeasibleRule -> [Proposition] -> Either Proposition Proposition
defeasibleFire queryScope rule base
  | not (T.null (drScope rule)) && drScope rule /= queryScope =
      Left (Apply (PredicateId "scope-mismatch") [])
  | otherwise = case matchAll [] [] (drPremises rule) of
      Nothing -> Left (Apply (PredicateId "premises-unsatisfied") [])
      Just (subst, _indices) ->
        case findException subst base of
          Just exc -> Left exc
          Nothing -> Right (applySubst subst (drConclusion rule))
  where
    indexed = zip [0 :: Int ..] base
    matchAll subst indices [] = Just (Subst subst, indices)
    matchAll subst indices (pat : rest) =
      case [ (j, s) | (j, fact) <- indexed
                    , Just s <- [matchWith subst pat fact] ] of
        [] -> Nothing
        ((j, s) : _) -> matchAll (unSubst s) (indices ++ [j]) rest
    matchWith subst pat fact = matchPattern (applySubst (Subst subst) pat) fact >>= unionSubst subst
    unionSubst subst (Subst s) = Just (Subst (s ++ subst))
    findException subst facts =
      let bound = map (applySubst subst) (drExceptions rule)
      in foldr (\exc acc -> case acc of
                  Just _ -> acc
                  Nothing -> if any (matchesExc exc) facts then Just exc else Nothing)
           Nothing bound
    matchesExc exc fact = case matchPattern exc fact of
      Just _ -> True
      Nothing -> False

-- | Check presuppositions against a base: each must match some fact.
checkPresuppositions :: [Proposition] -> [Proposition] -> [(Proposition, Bool)]
checkPresuppositions base presupps =
  [ (p, any (matches p) base) | p <- presupps ]
  where
    matches p fact = case matchPattern p fact of
      Just _ -> True
      Nothing -> False

-- | Detect a direct contradiction: both P and (Not P) present
-- (structural equality). Returns the first such pair found.
detectConflict :: [Proposition] -> Maybe (Proposition, Proposition)
detectConflict base =
  case [ (p, q) | p <- base, q <- base, isNegationOf p q ] of
    [] -> Nothing
    (pair : _) -> Just pair
  where
    isNegationOf (Not p) q = p == q
    isNegationOf _ _ = False
