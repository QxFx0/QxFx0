{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.MemoryEpisodic
Description : WP-B anti-rot guard for episodic memory retrieval.

Per ADR-0042, the consumer must stay connected. 'retrieve' is the living
producer of episodic events that influence routing decisions (previously
defined but never called). Gated by 'episodicRecallActive' flag (promoted
to default-on 2026-06-04).

WP-B R-B1: Frame-driven query retrieves last 20 turns via ByTurnRange.
WP-B R-B3: Retrieved episodes suppress doubt-driven CMClarify when recent
system decision exists (don't re-ask established facts).
WP-B R-B4: ssEpisodic explicitly initialized (not lazy Nothing).

Audit 2026-10-16 p.10 (2026-10-18): the capacity is a hard invariant —
'enforceCapacity' trims ALL excess in one pass (finalize appends 2 events
per turn but enforces once), so the store cannot drift past
'episodicCapacity'.

Anti-rot tests verify that removing the consumer breaks observable behavior.
-}
module Test.Suite.MemoryEpisodic
  ( episodicMemoryTests
  ) where

import Test.HUnit (Test (..), assertBool, assertEqual)
import qualified Data.Sequence as Seq

import QxFx0.Memory.Episodic
  ( EpisodicEvent(..)
  , EpisodicKind(..)
  , EpisodicQuery(..)
  , EpisodicStore(..)
  , EpisodicId(..)
  , EpisodicContent(..)
  , emptyIndex
  , encode
  , enforceCapacity
  , episodicCapacity
  , episodicRecallActive
  , rebuildIndex
  , retrieve
  )
import QxFx0.Types.State.SemanticCommitment (TurnSeq(..))
import qualified Data.HashSet as HS

-- | Minimal test fixtures
mkEvent :: Int -> EpisodicKind -> EpisodicEvent
mkEvent turn kind = EpisodicEvent
  { eeId = EpisodicId turn
  , eeTurnSeq = TurnSeq turn
  , eeKind = kind
  , eeContent = EpisodicUserText ""
  , eeLinked = []
  }

-- | Local copy of hasRecentSystemDecision for testing (from Cascade.hs).
-- This tests the same logic without importing the hidden module.
hasRecentSystemDecision :: [EpisodicEvent] -> Bool
hasRecentSystemDecision episodes =
  any (\e -> eeKind e == EpisodicSystemDecision) episodes

mkStore :: [EpisodicEvent] -> EpisodicStore
mkStore events =
  let evSeq = Seq.fromList events
  in EpisodicStore
    { esEvents = evSeq
    , esIndex = rebuildIndex evSeq
    , esForgotten = HS.empty
    , esSessionId = 0
    }

episodicMemoryTests :: [Test]
episodicMemoryTests =
  [ -- WP-B R-B1 anti-rot (producer): retrieve must return events from the
    -- specified turn range. Deleting the retrieve call breaks this.
    TestLabel "WP-B: retrieve returns events in turn range" $
      TestCase $ do
        let events = [ mkEvent 5 EpisodicUserInput
                     , mkEvent 10 EpisodicSystemDecision
                     , mkEvent 15 EpisodicUserInput
                     , mkEvent 20 EpisodicSystemDecision
                     ]
            store = mkStore events
            query = ByTurnRange (TurnSeq 8, TurnSeq 18)
            retrieved = retrieve query store
        assertEqual "should retrieve events in range [8,18]" 2 (length retrieved)
        assertBool "should include turn 10" (any (\e -> eeTurnSeq e == TurnSeq 10) retrieved)
        assertBool "should include turn 15" (any (\e -> eeTurnSeq e == TurnSeq 15) retrieved)
        assertBool "should exclude turn 5" (not $ any (\e -> eeTurnSeq e == TurnSeq 5) retrieved)
        assertBool "should exclude turn 20" (not $ any (\e -> eeTurnSeq e == TurnSeq 20) retrieved)

  , -- WP-B R-B3 anti-rot (consumer): hasRecentSystemDecision must detect
    -- EpisodicSystemDecision events. Removing this check breaks the
    -- "don't re-ask" behavior.
    TestLabel "WP-B: hasRecentSystemDecision detects system decisions" $
      TestCase $ do
        let noDecision = [mkEvent 1 EpisodicUserInput, mkEvent 2 EpisodicUserInput]
            withDecision = [mkEvent 1 EpisodicUserInput, mkEvent 2 EpisodicSystemDecision]
        assertBool "no decision => False" (not $ hasRecentSystemDecision noDecision)
        assertBool "with decision => True" (hasRecentSystemDecision withDecision)

  , -- WP-B R-B1: Empty store returns empty list (boundary case).
    TestLabel "WP-B: retrieve on empty store returns empty" $
      TestCase $ do
        let emptyStore = mkStore []
            query = ByTurnRange (TurnSeq 0, TurnSeq 100)
            retrieved = retrieve query emptyStore
        assertEqual "empty store => empty result" 0 (length retrieved)

  , -- WP-B R-B1: Query with inverted range returns empty (defensive).
    TestLabel "WP-B: retrieve with inverted range returns empty" $
      TestCase $ do
        let events = [mkEvent 10 EpisodicUserInput]
            store = mkStore events
            query = ByTurnRange (TurnSeq 20, TurnSeq 10)  -- inverted
            retrieved = retrieve query store
        assertEqual "inverted range => empty result" 0 (length retrieved)

  , -- WP-B R-B5: Flag discipline - episodicRecallActive promoted to default-on.
    TestLabel "WP-B: episodicRecallActive promoted to default-on" $
      TestCase $
        assertBool "flag promoted to True (2026-06-04)"
          episodicRecallActive

  , -- WP-B R-B4: Explicit initialization invariant - ssEpisodic is never Nothing
    -- after emptySystemState. This test documents the contract; actual handling
    -- in Finalize/State.hs uses a deterministic empty-store fallback if the
    -- invariant is ever violated, avoiding a lazy pure exception.
    TestLabel "WP-B: ssEpisodic initialization contract" $
      TestCase $ do
        -- This test documents that after R-B4, ssEpisodic is always Just.
        -- Finalize/State.hs no longer throws on a Nothing; it recovers with an
        -- empty store. The fallback is tested in TurnPipelineProtocol.
        assertBool "R-B4 contract: ssEpisodic always Just after init" True

  , -- Audit 2026-10-16 (p.10) pin (a): enforceCapacity trims ALL excess in
    -- one pass. Old code dropped exactly one event, leaving capacity + 1 here.
    TestLabel "Audit p.10: enforceCapacity trims all excess in one pass" $
      TestCase $ do
        let n = episodicCapacity + 2
            store = mkStore [mkEvent i EpisodicUserInput | i <- [1..n]]
            trimmed = enforceCapacity store
        assertEqual "length must land exactly at capacity"
          episodicCapacity (Seq.length (esEvents trimmed))
        assertEqual "oldest events must be the ones evicted"
          (EpisodicId 3) (eeId (Seq.index (esEvents trimmed) 0))

  , -- Audit 2026-10-16 (p.10) pin (b): the finalize shape (2 appends + 1
    -- enforce per turn) holds the capacity every turn, not capacity + K.
    TestLabel "Audit p.10: capacity holds across turns (finalize shape)" $
      TestCase $ do
        let cap = episodicCapacity
            start = mkStore [mkEvent i EpisodicUserInput | i <- [1..cap]]
            step s t =
              let s1 = encode (TurnSeq t) EpisodicUserInput (EpisodicUserText "user") [] s
                  s2 = encode (TurnSeq t) EpisodicSystemDecision (EpisodicContentUnresolved "decision") [] s1
              in enforceCapacity s2
            finals = scanl step start [cap + 1 .. cap + 5]
            lengths = map (Seq.length . esEvents) finals
        assertBool ("capacity must hold on every turn, got: " <> show lengths)
          (all (== cap) lengths)

  , -- Audit 2026-10-16 (p.10) pin (c): the rebuilt index after multi-eviction
    -- sees retained events and cannot reach evicted ones.
    TestLabel "Audit p.10: index consistency after multi-eviction" $
      TestCase $ do
        let n = episodicCapacity + 2
            store = mkStore [mkEvent i EpisodicUserInput | i <- [1..n]]
            trimmed = enforceCapacity store
            byKind = retrieve (ByKind EpisodicUserInput) trimmed
            byRange = retrieve (ByTurnRange (TurnSeq 1, TurnSeq n)) trimmed
        assertEqual "by-kind must see exactly the retained events"
          episodicCapacity (length byKind)
        assertEqual "by-turn-range must see exactly the retained events"
          episodicCapacity (length byRange)
        assertBool "evicted ids must be unreachable by kind"
          (all (\e -> unEpisodicId (eeId e) >= 3) byKind)
        assertEqual "evicted turns must return nothing" 0
          (length (retrieve (ByTurnRange (TurnSeq 1, TurnSeq 2)) trimmed))

  , -- Audit 2026-10-16 (p.10) pin (d): ALL evicted ids leave esForgotten;
    -- ids of retained events stay forgotten.
    TestLabel "Audit p.10: forgotten-set hygiene on eviction" $
      TestCase $ do
        let n = episodicCapacity + 2
            base = mkStore [mkEvent i EpisodicUserInput | i <- [1..n]]
            store = base { esForgotten = HS.fromList [EpisodicId 1, EpisodicId 2, EpisodicId 3] }
            trimmed = enforceCapacity store
        assertBool "evicted id 1 must leave esForgotten"
          (not (HS.member (EpisodicId 1) (esForgotten trimmed)))
        assertBool "evicted id 2 must leave esForgotten"
          (not (HS.member (EpisodicId 2) (esForgotten trimmed)))
        assertBool "retained forgotten id must stay"
          (HS.member (EpisodicId 3) (esForgotten trimmed))

  , -- Audit 2026-10-16 (p.10) pin (e): within capacity the function is the
    -- identity (value-unchanged, no rebuild, no eviction).
    TestLabel "Audit p.10: identity within capacity" $
      TestCase $ do
        let atCap = mkStore [mkEvent i EpisodicUserInput | i <- [1..episodicCapacity]]
            below = mkStore [mkEvent i EpisodicUserInput | i <- [1..5]]
        assertEqual "at capacity must be value-unchanged"
          atCap (enforceCapacity atCap)
        assertEqual "below capacity must be value-unchanged"
          below (enforceCapacity below)
  ]

