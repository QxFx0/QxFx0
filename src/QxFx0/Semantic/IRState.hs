{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : QxFx0.Semantic.IRState
Description : canonical — generic state-transition engine with lineage.

Status (2026-10-07, Stage-1 Batch D, ADR-0054): SHADOW ONLY.
Nothing in the runtime calls this module. Event-sourced design:
a history is a fold over events, so correction is event
replacement plus refold — no incremental truth maintenance.
Fluents persist across events (frame axiom) unless withdrawn
or structurally contradicted. Every fluent carries its support
(event id + kind), which is the Explain substrate alongside
Batch A proof objects.

Domain contracts (ownership, transfer) live in data and arrive
with Batch E; here only the generic machinery plus abstract
test histories.
-}
module QxFx0.Semantic.IRState
  ( TimeStep(..)
  , FluentSupport(..)
  , FluentRecord(..)
  , EventSpec(..)
  , FluentState(..)
  , emptyState
  , applyEvent
  , foldHistory
  , reviseHistory
  , fluentsAt
  , lineageOf
  , matchAllPatterns
  , FileOwnershipRow(..)
  , toEventSpec
  , toOwnershipRule
  ) where

import Data.Aeson (FromJSON(..), FromJSONKey, ToJSON, ToJSONKey)
import qualified Data.Aeson as Aeson
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import Data.Text (Text)
import GHC.Generics (Generic)

import QxFx0.Semantic.IR
  ( Proposition(..)
  , Term(..)
  , VarId(..)
  , freeVariables
  , parseProposition
  )
import QxFx0.Semantic.IREval
  ( Subst(..)
  , applySubst
  , matchPattern
  )

-- | Opaque ordered time labels ("t0", "t1", ...). Ordering is
-- lexicographic by construction site convention; the engine
-- never interprets them beyond equality and succession.
newtype TimeStep = TimeStep { unTimeStep :: Text }
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)
  deriving newtype (ToJSONKey, FromJSONKey)

-- | How a fluent entered the state.
data FluentSupport
  = SupportInitial
    -- ^ Present in the initial state.
  | SupportAsserted !Text
    -- ^ Asserted by the named event.
  | SupportPersisted !Text !TimeStep
    -- ^ Carried over by the named event from the named time.
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

-- | A fluent with its derivation support.
data FluentRecord = FluentRecord
  { frFluent :: !Proposition
  , frSupport :: !FluentSupport
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

-- | An event: checked preconditions, withdrawals, assertions,
-- and the time it advances to.
data EventSpec = EventSpec
  { evId :: !Text
  , evPreconditions :: ![Proposition]
  , evWithdraws :: ![Proposition]
  , evAsserts :: ![Proposition]
  , evAdvancesTo :: !TimeStep
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

-- | Time-indexed fluent sets.
newtype FluentState = FluentState
  { unFluentState :: M.Map TimeStep [FluentRecord]
  } deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

-- | The empty state.
emptyState :: FluentState
emptyState = FluentState M.empty

-- | Seed a state at one time with initial (supported) fluents.
seedState :: TimeStep -> [Proposition] -> FluentState
seedState t props =
  FluentState (M.singleton t [ FluentRecord p SupportInitial | p <- props ])

-- | Structural contradiction: P vs (Not P) in either direction.
contradicts :: Proposition -> Proposition -> Bool
contradicts (Not p) q = p == q
contradicts p (Not q) = p == q
contradicts _ _ = False

-- | Apply one event to a state. Preconditions match conjunctively
-- against held fluents with variable binding (same discipline as
-- rule premises); on failure the event is rejected ('Left').
-- Withdrawals and assertions are instantiated with the binding;
-- surviving free variables are a data error ('Left'). Withdrawn
-- fluents (structural match on instantiated forms) leave;
-- contradicted survivors leave too; everything else persists
-- with 'SupportPersisted'. Assertions arrive with
-- 'SupportAsserted' and win direct collisions. The result is
-- recorded at 'evAdvancesTo'.
applyEvent :: FluentState -> TimeStep -> EventSpec -> Either String FluentState
applyEvent st from ev = do
  prior <- case M.lookup from (unFluentState st) of
    Nothing -> Left ("no state at time: " <> show (unTimeStep from))
    Just recs -> Right recs
  let held = map frFluent prior
  subst <- case matchAllPatterns (evPreconditions ev) held of
    Nothing -> Left ("precondition violated by " <> show (evId ev))
    Just s -> Right s
  let withdraws = map (applySubst subst) (evWithdraws ev)
      asserts = map (applySubst subst) (evAsserts ev)
      unbound = filter (not . S.null . freeVariables) (withdraws ++ asserts)
  case unbound of
    (bad : _) -> Left ("unbound variables after match by " <> show (evId ev)
                        <> ": " <> show bad)
    [] -> Right ()
  let withdrawn p = p `elem` withdraws
      contradicted p = any (contradicts p) (withdraws ++ asserts)
      survivors =
        [ FluentRecord (frFluent r) (SupportPersisted (evId ev) from)
        | r <- prior
        , not (withdrawn (frFluent r))
        , not (contradicted (frFluent r))
        ]
      asserted =
        [ FluentRecord p (SupportAsserted (evId ev))
        | p <- asserts
        ]
      -- Asserts win over survivors on direct collision: a freshly
      -- asserted fluent and a persisted structural duplicate cannot
      -- both stand; the event's own assertion is authoritative.
      deduped = asserted ++ filter (\r -> frFluent r `notElem` asserts) survivors
  pure (FluentState (M.insert (evAdvancesTo ev) deduped (unFluentState st)))

-- | Conjunctive pattern match (first match wins per pattern, in
-- order), mirroring rule-premise matching.
matchAllPatterns :: [Proposition] -> [Proposition] -> Maybe Subst
matchAllPatterns pats facts = go (Subst []) pats
  where
    go subst [] = Just subst
    go subst (pat : rest) =
      case [ s | fact <- facts, Just s <- [matchPattern (applySubst subst pat) fact] ] of
        [] -> Nothing
        (s : _) -> go (unionSubst subst s) rest
    unionSubst (Subst a) (Subst b) = Subst (b ++ a)

-- | Fold a seeded history: initial time, initial fluents, then
-- events applied in order, each from the previous event's time.
foldHistory :: TimeStep -> [Proposition] -> [EventSpec] -> Either String (FluentState, [TimeStep])
foldHistory t0 inits events = go (seedState t0 inits) t0 events [t0]
  where
    go st _ [] times = Right (st, times)
    go st from (ev : rest) times = do
      st' <- applyEvent st from ev
      go st' (evAdvancesTo ev) rest (times ++ [evAdvancesTo ev])

-- | Revise a history: replace the event with the given id and
-- refold from the seed. Dependent fluents recompute; independent
-- ones are byte-identical (purity guarantees it — no hidden state).
reviseHistory :: TimeStep -> [Proposition] -> [EventSpec] -> Text -> EventSpec -> Either String (FluentState, [TimeStep])
reviseHistory t0 inits events replaceId replacement =
  let swapped = [ if evId ev == replaceId then replacement else ev | ev <- events ]
  in if any ((== replaceId) . evId) events
       then foldHistory t0 inits swapped
       else Left ("no such event: " <> show replaceId)

-- | Fluents recorded at one time.
fluentsAt :: FluentState -> TimeStep -> [Proposition]
fluentsAt st t =
  maybe [] (map frFluent) (M.lookup t (unFluentState st))

-- | The recorded support of one fluent at one time, if present.
lineageOf :: FluentState -> TimeStep -> Proposition -> Maybe FluentSupport
lineageOf st t p =
  case filter ((== p) . frFluent) (fluentsAtRecords st t) of
    (r : _) -> Just (frSupport r)
    [] -> Nothing
  where
    fluentsAtRecords s tm = maybe [] id (M.lookup tm (unFluentState s))

-- ---------------------------------------------------------------------------
-- Ownership contract library (Batch E): file rows plus pure
-- converters. Times stay scenario-bound (tests assign them).
-- ---------------------------------------------------------------------------

-- | One ownership-library row: an event template or a strict rule.
data FileOwnershipRow = FileOwnershipRow
  { foId :: !Text
  , foKind :: !Text
  , foPreconditions :: ![Text]
  , foWithdraws :: ![Text]
  , foAsserts :: ![Text]
  , foPremises :: ![Text]
  , foConclusion :: !(Maybe Text)
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON)

instance FromJSON FileOwnershipRow where
  parseJSON = Aeson.withObject "FileOwnershipRow" $ \o -> FileOwnershipRow
    <$> o Aeson..: "id"
    <*> o Aeson..: "kind"
    <*> o Aeson..:? "preconditions" Aeson..!= []
    <*> o Aeson..:? "withdraws" Aeson..!= []
    <*> o Aeson..:? "asserts" Aeson..!= []
    <*> o Aeson..:? "premises" Aeson..!= []
    <*> o Aeson..:? "conclusion"

-- | Convert a file event template into an 'EventSpec' advancing to
-- the given time under the given environment (variable bindings,
-- e.g. participants named by the utterance). Fails on unparseable
-- s-exprs, non-event rows, and variables unbound after the
-- environment and precondition matching (variable discipline:
-- the event must not invent participants the context never
-- named — existential introduction is explicit, never silent).
toEventSpec :: FileOwnershipRow -> TimeStep -> [(VarId, Term)] -> Either String EventSpec
toEventSpec row advancesTo env = do
  whenKind
  pre <- mapM (parseRow (foId row)) (foPreconditions row)
  wd <- mapM (parseRow (foId row)) (foWithdraws row)
  as <- mapM (parseRow (foId row)) (foAsserts row)
  let applyEnv = applySubst (Subst env)
      pre' = map applyEnv pre
      wd' = map applyEnv wd
      as' = map applyEnv as
      bound = S.unions (map freeVariables pre')
      dangling = S.unions (map freeVariables (wd' ++ as')) `S.difference` bound
  case S.toList dangling of
    (v : _) -> Left ("unbound variable in " <> show (foId row) <> ": " <> show v)
    [] -> Right (EventSpec (foId row) pre' wd' as' advancesTo)
  where
    whenKind
      | foKind row /= "event" =
          Left ("not an event row: " <> show (foId row))
      | otherwise = Right ()
    parseRow ctx sexpr = case parseProposition sexpr of
      Just p -> Right p
      Nothing -> Left ("s-expr must parse (" <> show ctx <> ")")

-- | Convert a file strict-rule row. Fails on unparseable s-exprs,
-- non-strict rows, and conclusion variables unbound by premises.
toOwnershipRule :: FileOwnershipRow -> Either String (Text, [Proposition], Proposition)
toOwnershipRule row
  | foKind row /= "strict" =
      Left ("not a strict row: " <> show (foId row))
  | otherwise = do
      pre <- mapM (parseRow (foId row)) (foPremises row)
      conclu <- case foConclusion row of
        Nothing -> Left ("strict row needs conclusion: " <> show (foId row))
        Just sexpr -> parseRow (foId row) sexpr
      let bound = S.unions (map freeVariables pre)
      case S.toList (freeVariables conclu `S.difference` bound) of
        (v : _) -> Left ("unbound conclusion variable in " <> show (foId row) <> ": " <> show v)
        [] -> Right (foId row, pre, conclu)
  where
    parseRow ctx sexpr = case parseProposition sexpr of
      Just p -> Right p
      Nothing -> Left ("s-expr must parse (" <> show ctx <> ")")
