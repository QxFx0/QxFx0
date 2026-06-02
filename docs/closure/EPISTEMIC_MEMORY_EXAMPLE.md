# Episodic Memory — End-to-End Example

- **Status**: Active (closure-phase follow-up F-06, Package 7
  acceptance criteria §6)
- **Date**: 2026-06-02
- **Refines**: `docs/closure/COGNITIVE_MEMORY_DESIGN.md` §1.2
- **Related**:
  - `docs/closure/SEMANTIC_CORE_EXAMPLE.md` (F-05)
  - `docs/closure/LEARNING_EXAMPLE.md` (F-07)

## 0. What this example is

A single end-to-end walkthrough of one `encode`, one
`retrieve`, and one `forget` against the `EpisodicStore`
from Package 7 §1.2. The example uses the typed
`EpisodicContent` tagged sum; it does not exercise free-text
content (that is forbidden by the design).

The example continues the scenario from
`SEMANTIC_CORE_EXAMPLE.md` (F-05): the same 4-turn dialogue,
with episodic events linked to the commitments produced
there.

## 1. The scenario

A 4-turn dialogue. The system records one episodic event per
turn, links it to the relevant commitment (if any), then
retrieves a query and forgets an old event.

| Turn | Episodic event | Linked commitment |
|---|---|---|
| 1 | `EpisodicUserText "I am a software developer."` | — (turn 1) |
| 1 | `EpisodicCommitmentCreated 1` | CommitmentId 1 |
| 2 | `EpisodicUserText "I work in Haskell."` | — (turn 2) |
| 2 | `EpisodicCommitmentCreated 2` | CommitmentId 2 |
| 3 | `EpisodicCommitmentRevised (2, 3)` | CommitmentId 2 |
| 4 | `EpisodicCommitmentRetracted (1, UserDenied)` | CommitmentId 1 |

## 2. Turn 1: encode

### 2.1 The events

```haskell
events1 :: [EpisodicEvent]
events1 =
  [ EpisodicEvent
      { eeId      = EpisodicId 1
      , eeTurnSeq = TurnSeq 1
      , eeKind    = EpisodicUserInput
      , eeContent = EpisodicUserText "I am a software developer."
      , eeLinked  = []
      }
  , EpisodicEvent
      { eeId      = EpisodicId 2
      , eeTurnSeq = TurnSeq 1
      , eeKind    = EpisodicCommitment
      , eeContent = EpisodicCommitmentCreated (CommitmentId 1)
      , eeLinked  = [CommitmentId 1]
      }
  ]
```

### 2.2 The morphism

```haskell
store0 :: EpisodicStore
store0 = emptyEpisodicStore (SessionId "sess-1")

store1 :: EpisodicStore
store1 = encode events1 store0
```

### 2.3 The result

`store1` has:

- `esEvents = fromList [event1, event2]`
- `esIndex` updated:
  - `eiByKind = {EpisodicUserInput → {1}, EpisodicCommitment → {2}}`
  - `eiByTurn = {1 → 2}`  (last event of turn 1)
  - `eiByCommitment = {1 → {2}}`
  - `eiByTag = {}`  (no unresolved-loop tags)
- `esForgotten = {}`

The `trcEpisodicEncoding` trace field on `TurnReplayTrace`
records the new `EpisodicId`s `[1, 2]`.

## 3. Turn 2: encode (more events)

### 3.1 The events

```haskell
events2 :: [EpisodicEvent]
events2 =
  [ EpisodicEvent
      { eeId      = EpisodicId 3
      , eeTurnSeq = TurnSeq 2
      , eeKind    = EpisodicUserInput
      , eeContent = EpisodicUserText "I work in Haskell."
      , eeLinked  = []
      }
  , EpisodicEvent
      { eeId      = EpisodicId 4
      , eeTurnSeq = TurnSeq 2
      , eeKind    = EpisodicCommitment
      , eeContent = EpisodicCommitmentCreated (CommitmentId 2)
      , eeLinked  = [CommitmentId 2]
      }
  ]
```

### 3.2 The morphism

```haskell
store2 :: EpisodicStore
store2 = encode events2 store1
```

### 3.3 The result

`store2` has `esEvents` of length 4 and an updated index.

## 4. Turn 3: encode (revision)

```haskell
events3 :: [EpisodicEvent]
events3 =
  [ EpisodicEvent
      { eeId      = EpisodicId 5
      , eeTurnSeq = TurnSeq 3
      , eeKind    = EpisodicCommitment
      , eeContent = EpisodicCommitmentRevised (CommitmentId 2, TurnSeq 3)
      , eeLinked  = [CommitmentId 2]
      }
  ]
```

After `encode events3 store2`, `store3` has length 5 and the
commitment index shows `CommitmentId 2` linked to events
`{4, 5}`.

## 5. Turn 4: encode (retraction)

```haskell
events4 :: [EpisodicEvent]
events4 =
  [ EpisodicEvent
      { eeId      = EpisodicId 6
      , eeTurnSeq = TurnSeq 4
      , eeKind    = EpisodicCommitment
      , eeContent = EpisodicCommitmentRetracted (CommitmentId 1, RetractionUserDenied)
      , eeLinked  = [CommitmentId 1]
      }
  ]
```

After `encode events4 store3`, `store4` has length 6 and the
commitment index still has `CommitmentId 1` linked (the
retraction is itself an event linked to the commitment).

## 6. Retrieval: by commitment

A consumer (e.g. the next-turn reasoning) calls:

```haskell
query1 :: CommitmentId
query1 = CommitmentId 2

result1 :: [EpisodicEvent]
result1 = retrieve (ByCommitment query1) store4
```

`result1` is the events linked to commitment 2:

```
[event4 (commitment created at turn 2),
 event5 (commitment revised at turn 3)]
```

The `trcEpisodicRetrieval` trace field records the query
and the result ids.

## 7. Retrieval: by kind

Another consumer calls:

```haskell
query2 :: EpisodicKind
query2 = EpisodicCommitment

result2 :: [EpisodicEvent]
result2 = retrieve (ByKind query2) store4
```

`result2` is all 4 commitment events (events 2, 4, 5, 6) in
turn order.

## 8. Forgetting: capacity-driven

After many turns, the `esEvents` ring buffer hits
`episodicCapacity = 1000` (default). The oldest event is
forgotten with reason `ForgetByCapacity`.

```haskell
store5 :: EpisodicStore
store5 = forget (EpisodicId 1) ForgetByCapacity (TurnSeq N) store4
```

`store5.esForgotten` now contains `EpisodicId 1`. The event
is still in `esEvents` (for replay), but `retrieve` filters
it out. The `trcEpisodicForgetting` trace field records the
forgetting.

## 9. Reuse with annotation

A consumer wants to use the OCaml-revised commitment
(event 5) as **context** for a future decision. It declares:

```haskell
consumer :: [EpisodicEvent] -> Decision
consumer events = ...   -- uses event5 as background

-- The consumer module declares:
reuseAnnotation :: ReuseAnnotation
reuseAnnotation = ReuseAsContext
```

The trace records:

```haskell
trcEpisodicRetrieval = Just RetrievalTrace
  { rtQuery  = ByCommitment (CommitmentId 2)
  , rtResult = [EpisodicId 4, EpisodicId 5]
  , rtReuse  = [ReuseAsContext]
  }
```

A consumer that does **not** declare a `ReuseAnnotation` is
a `check_architecture.sh` violation (per Package 7 §2.4).

## 10. Replay verification

The replay gate (Package 3) requires:

```haskell
replay :: EpisodicStore -> [TurnSeq] -> [EpisodicEvent]
replay store _ = toList (esEvents store)
```

For the example, `replay store4 _` returns the 6 events in
turn order, including forgotten events (the discipline
preserves them for replay).

The reconstruction is total and deterministic; a property
test verifies `replay finalStore _` equals the expected
event stream for a given input.

## 11. What this example does not show

- The **commitment store** that the events link to. The
  example uses commitment ids directly; a real session
  has the `SemanticCommitmentStore` from F-05. The link
  is `eeLinked :: [CommitmentId]`; the commitment
  existence is checked via the commitment store.
- The **forgetting policy** for soft age and policy-driven
  forget. The example uses only `ForgetByCapacity`.
- The **auto-encoding** of events. The example is
  manual; the orchestrator explicitly calls `encode` with
  the events it has produced.
- The **importance scoring** for `ForgetByPolicy`. The
  scoring API is in place; the score is hard-coded to
  `1.0` in the initial slice.

## 12. Acceptance criteria for F-06

F-06 is closed when:

- [ ] This file is merged.
- [ ] The example compiles against `QxFx0.Memory.Episodic`
      (post-Package 7) without modification.
- [ ] The replay verification is part of
      `Test.Suite.EpisodicMemory` (new) as a property
      test.
- [ ] The retrieval and forget steps are part of
      `Test.Suite.EpisodicMemory` as unit tests.
- [ ] The `ReuseAnnotation` discipline is part of the
      `check_architecture.sh` extension.
