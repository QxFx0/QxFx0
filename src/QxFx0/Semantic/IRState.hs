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
  ) where

import Data.Aeson (FromJSON, FromJSONKey, ToJSON, ToJSONKey)
import qualified Data.Map.Strict as M
import Data.Text (Text)
import GHC.Generics (Generic)

import QxFx0.Semantic.IR (Proposition(..))

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

-- | Apply one event to a state. Preconditions are checked against
-- the union of all recorded fluents (structural equality); on
-- violation the event is rejected ('Left'). Withdrawn fluents
-- (and anything they contradict... no: only exact structural
-- matches) leave; contradicted survivors leave too; everything
-- else persists with 'SupportPersisted'; assertions arrive with
-- 'SupportAsserted'. The result is recorded at 'evAdvancesTo'.
applyEvent :: FluentState -> TimeStep -> EventSpec -> Either String FluentState
applyEvent st from ev = do
  prior <- case M.lookup from (unFluentState st) of
    Nothing -> Left ("no state at time: " <> show (unTimeStep from))
    Just recs -> Right recs
  let held = map frFluent prior
  mapM_ (\pre -> if pre `elem` held
                   then Right ()
                   else Left ("precondition violated by " <> show (evId ev)
                               <> ": " <> show pre))
        (evPreconditions ev)
  let withdrawn p = p `elem` evWithdraws ev
      contradicted p = any (contradicts p) (evWithdraws ev ++ evAsserts ev)
      survivors =
        [ FluentRecord (frFluent r) (SupportPersisted (evId ev) from)
        | r <- prior
        , not (withdrawn (frFluent r))
        , not (contradicted (frFluent r))
        ]
      asserted =
        [ FluentRecord p (SupportAsserted (evId ev))
        | p <- evAsserts ev
        ]
      -- Asserts win over survivors on direct collision: a freshly
      -- asserted fluent and a persisted structural duplicate cannot
      -- both stand; the event's own assertion is authoritative.
      deduped = asserted ++ filter (\r -> frFluent r `notElem` evAsserts ev) survivors
  pure (FluentState (M.insert (evAdvancesTo ev) deduped (unFluentState st)))

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
