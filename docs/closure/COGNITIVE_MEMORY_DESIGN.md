# Cognitive Memory Design

- **Status**: Active (closure-phase work product, Package 7)
- **Date**: 2026-06-02
- **Refines**: AGENTS.md, ADRs 0007–0012, `docs/system_state_taxonomy.md`
- **Related**:
  - `docs/closure/SEMANTIC_CORE_MIN_SLICE.md` (Package 2)
  - `docs/closure/REPLAY_GATE_SPEC.md` (Package 3)
  - `docs/closure/BOUNDED_LEARNING_DESIGN.md` (Package 8)
  - `docs/closure/METACOGNITION_LOOP_DESIGN.md` (Package 9)
  - `docs/adr/proposed/0034-self-core-role-split.md` (Package 1)

## 0. Why this design exists

The closure plan's Package 7 says: "persisted state exists but
cognitive memory does not. We need episodic memory contour,
retrieval/indexing, connection to commitments / corrections /
contradictions / unresolved loops, and authority rules for
write / extract / forget / reuse. Without forgetting policy,
memory becomes an append-only dump."

This document specifies the cognitive memory design. It builds
on the typed semantic commitments (Package 2) and the replay
gate (Package 3). The design is **minimal on purpose**: one
episodic contour, one retrieval index, one forgetting policy,
and explicit authority rules for each.

## 1. What is in the design

### 1.1 The three contours

The design separates memory into three contours, each with its
own authority rules:

| Contour | Owner | Lifecycle | Replay-visible? |
|---|---|---|---|
| **Semantic commitments** | Package 2 (`Semantic.Commitment`) | commit / revise / retract / contradict | yes (Package 2 §4) |
| **Episodic memory** | `QxFx0.Memory.Episodic` (new) | encode / retrieve / forget | yes (Package 3) |
| **Trace / projection** | existing `QxFx0.Types.TurnProjection` | per-turn snapshot | yes (existing) |

The closure plan's Package 7 ships the **episodic** contour. The
semantic contour is from Package 2. The trace contour is
existing.

The three contours are **not** interchangeable:
- Semantic commitments are **typed** (Package 2 Σ-type
  discipline). They are facts the system has decided to commit
  to.
- Episodic memory is **per-turn observations**. It is what
  happened on turn N, indexed for retrieval.
- Trace is **per-turn snapshots**. It is the full state of the
  turn, for debugging and replay.

### 1.2 The episodic contour

```haskell
data EpisodicStore = EpisodicStore
  { esEvents   :: !(Seq EpisodicEvent)     -- append-only log
  , esIndex    :: !EpisodicIndex            -- retrieval index
  , esForgotten :: !(HashSet EpisodicId)    -- explicitly forgotten events
  , esSessionId :: !SessionId
  } deriving stock (Eq, Show, Generic)

data EpisodicEvent = EpisodicEvent
  { eeId        :: !EpisodicId
  , eeTurnSeq   :: !TurnSeq
  , eeKind      :: !EpisodicKind
  , eeContent   :: !EpisodicContent         -- tagged sum; see §1.3
  , eeLinked    :: ![CommitmentId]          -- links to semantic commitments
  } deriving stock (Eq, Show, Generic)

newtype EpisodicId = EpisodicId { unEpisodicId :: Int }
  deriving stock (Eq, Ord, Show, Generic)

data EpisodicKind
  = EpisodicUserInput       -- raw user text
  | EpisodicSystemDecision  -- family, style, tone
  | EpisodicCommitment     -- tied to a commitment id
  | EpisodicContradiction  -- tied to a contradiction event
  | EpisodicRetraction     -- tied to a retraction
  | EpisodicUnresolved     -- explicit unresolved loop
  deriving stock (Eq, Show, Generic, Bounded, Enum)
```

### 1.3 The `EpisodicContent` tagged sum

The content is a tagged sum, not a free text:

```haskell
data EpisodicContent
  = EpisodicUserText !Text                   -- raw user text
  | EpisodicFamilyDecision !CanonicalMoveFamily
  | EpisodicStyleDecision !RenderStyle
  | EpisodicToneDecision !NarrativeTone
  | EpisodicCommitmentCreated !CommitmentId
  | EpisodicCommitmentRevised !(CommitmentId, TurnSeq)
  | EpisodicCommitmentRetracted !(CommitmentId, RetractionReason)
  | EpisodicContradiction !(CommitmentId, CommitmentId, ContradictionKind)
  | EpisodicUnresolved !Text                 -- short tag, not full text
  deriving stock (Eq, Show, Generic)
```

The tagged sum is the **discipline** of cognitive memory: every
event is typed, never free text. The closure plan rejects free-
text episodic memory because it cannot be replay-traced
meaningfully.

### 1.4 The retrieval index

```haskell
data EpisodicIndex = EpisodicIndex
  { eiByKind     :: !(HashMap EpisodicKind (Set EpisodicId))
  , eiByTurn     :: !(HashMap TurnSeq EpisodicId)
  , eiByCommitment :: !(HashMap CommitmentId (Set EpisodicId))
  , eiByTag      :: !(HashMap Text (Set EpisodicId))  -- unresolved-loop tags
  } deriving stock (Eq, Show, Generic)

retrieve :: EpisodicQuery -> EpisodicStore -> [EpisodicEvent]
retrieve q store = ...   -- simple set operations on the index
```

`retrieve` is **pure** and **replay-visible**: given a query
and a store, it returns the same events. The query and the
result go into `trcEpisodicRetrieval` on `TurnReplayTrace`.

Three initial query shapes:

| Query | What it returns |
|---|---|
| `ByKind !EpisodicKind` | All events of a kind in the window. |
| `ByCommitment !CommitmentId` | All events linked to a commitment. |
| `ByTurnRange !(TurnSeq, TurnSeq)` | All events in a turn range. |

More query shapes (e.g. by tag, by contradiction) are a
follow-up.

## 2. Authority rules

The closure plan's Package 7 requires explicit authority rules
for write / extract / forget / reuse. The rules:

### 2.1 Write authority

- The **only** writer of `EpisodicStore` is the `QxFx0.Memory.Episodic`
  module. No other module is allowed to append to `esEvents` or
  modify `esIndex`.
- The write API is `encode :: TurnInput -> TurnDecision ->
  [CommitmentId] -> EpisodicStore -> EpisodicStore`. It is
  invoked once per turn, in the **Finalize** stage, after all
  decisions are made and all commitments are recorded.
- A write is **replay-visible**: the `trcEpisodicEncoding` field
  on `TurnReplayTrace` carries the new `EpisodicId`s.

### 2.2 Extract (read) authority

- Any module can call `retrieve` with a query. The query and
  result go into the trace.
- A module that wants to **consume** the result (use it to
  influence a decision) must declare the consumption in its
  module Haddock. Undeclared consumption is a `check_architecture.sh`
  violation.
- The **only** consumers of episodic memory in the runtime
  today are:
  - The semantic retrieval contour (Package 2 §1.5): "did the
    user mention this before?".
  - The metacognitive evaluation contour (Package 9): "what
    decisions did I make in the recent past?".
  - Future consumers go through an explicit consumer ADR.

### 2.3 Forget authority

Forgetting is **explicit and irrevocable**, mirroring the
`Essence` commitment discipline (ADR-0012) and the semantic
retraction (Package 2 §1.2).

```haskell
forget
  :: EpisodicId
  -> ForgettingReason
  -> TurnSeq
  -> EpisodicStore
  -> EpisodicStore
```

`forget` does **not** delete the event. It marks the event as
forgotten in `esForgotten`; the event is still in `esEvents`
for replay, but `retrieve` filters it out. The discipline is
the same as `retract` in the semantic contour.

`ForgettingReason` is a closed enum:

```haskell
data ForgettingReason
  = ForgetByCapacity    -- ring buffer overflow
  | ForgetByAge         -- older than window
  | ForgetByUser        -- user explicitly asked
  | ForgetByPolicy      -- automated policy (e.g. low-importance)
  deriving stock (Eq, Show, Generic)
```

### 2.4 Reuse authority

Reuse means using a retrieved event in a downstream decision.
The closure plan's Package 7 requires that reuse is **typed**:
the consumer declares the event's role in the decision.

```haskell
data ReuseAnnotation
  = ReuseAsContext         -- event is background for the decision
  | ReuseAsConstraint      -- event constrains the decision
  | ReuseAsTrigger         -- event triggered the decision
  | ReuseAsEvidence        -- event is evidence for the decision
  deriving stock (Eq, Show, Generic)
```

The annotation goes into the trace. A decision without
`ReuseAnnotation` for any reused event is a `check_architecture.sh`
violation.

## 3. The forgetting policy

The closure plan's Package 7 says: "without forgetting policy,
memory becomes an append-only dump". The policy is:

1. **Hard capacity.** `esEvents` is a `Seq` with a max length
   `episodicCapacity` (default 1 000 events). When the cap is
   reached, the oldest event is forgotten with reason
   `ForgetByCapacity`. This is a hard ring buffer.
2. **Soft age.** Events older than `episodicWindow` (default 50
   turns) are candidates for `ForgetByAge`. The forget is
   applied at the Finalize stage, but only for events that are
   not linked to any active commitment.
3. **User-driven forget.** `ForgetByUser` is invoked when the
   user explicitly asks. (This requires a new surface; the
   initial slice does not ship the surface but ships the API.)
4. **Policy-driven forget.** `ForgetByPolicy` is for future
   importance-based forgetting. The initial slice does not
   implement it; the API is in place.

The closure plan's Package 11 (calibration) tunes
`episodicCapacity` and `episodicWindow` against the production
trace corpus.

## 4. Replay gate (handoff to Package 3)

Episodic memory is subject to the replay gate (§3.2 of
`REPLAY_GATE_SPEC.md`):

- **P1 (Serializable)**: `EpisodicStore` is `ToJSON / FromJSON`;
  the roundtrip is identity (property test).
- **P2 (Replayable)**: given a snapshot + an event trail, the
  store is reconstructable. The event trail is `esEvents`
  itself (the append-only log).
- **P3 (Reconstructable)**: snapshot byte budget 256 KB;
  event-trail byte budget per event 256 B; reconstruction is
  total.
- **P4 (Trace-explainable)**: every decision that consumes an
  episodic event has a `trcEpisodicRetrieval` field with the
  query, the result, and the `ReuseAnnotation`.

## 5. What is NOT in this design

- **Long-term / cross-session memory.** Deferred per
  `docs/adr/proposed/0041-cross-session-essence-persistence.md`.
  The closure plan's Package 7 is in-session only.
- **Distributed memory.** Single-session, single-store.
- **Indexing beyond HashMap.** The design uses simple
  `HashMap`-based indexes. More sophisticated indexes (e.g.
  vector search) are a follow-up.
- **Auto-commit of episodic events.** Every event is encoded
  explicitly by the orchestrator. The design does not have an
  auto-encode mode.
- **Memory consolidation / summarisation.** The design preserves
  the raw event; summarisation is a follow-up.
- **Importance scoring.** `ForgetByPolicy` requires importance
  scoring; the API is in place but the score is hard-coded to
  `1.0` (no scoring yet).

## 6. Acceptance criteria for Package 7 closure

- [ ] `QxFx0.Memory.Episodic` module (new) exposes the
      `EpisodicStore`, `encode`, `retrieve`, `forget`,
      `ReuseAnnotation`, and the four `ForgettingReason`s.
- [ ] `SystemState.ssEpisodic :: Maybe EpisodicStore` is added;
      `Nothing` in `emptySystemState`; populated after a
      successful `encode` call.
- [ ] `trcEpisodicEncoding`, `trcEpisodicRetrieval`,
      `trcEpisodicForgetting` fields on `TurnReplayTrace`.
- [ ] `Test.Suite.EpisodicMemory` (new) ships with:
      - `encode` is total and pure;
      - `retrieve` is total, pure, and replay-visible;
      - `forget` is irrevocable (no API path reverts it);
      - hard capacity is enforced at `episodicCapacity`;
      - soft age is enforced at `episodicWindow` for events
        with no active commitment link;
      - `ReuseAnnotation` is required for every consumer.
- [ ] `scripts/check_architecture.sh` enforces:
      - only `QxFx0.Memory.Episodic` writes to `EpisodicStore`;
      - every consumer declares its `ReuseAnnotation`;
      - every retrieval is trace-visible.
- [ ] Documentation: a single end-to-end example in
      `docs/closure/EPISTEMIC_MEMORY_EXAMPLE.md` walks through
      one encode, one retrieve, one forget, and the resulting
      `EpisodicStore`.

## 7. Honest limits

- The design is **one** episodic contour. A real cognitive
  memory needs working memory, semantic memory, episodic
  memory, and procedural memory (per cognitive science). The
  closure plan ships episodic; the others are deferred.
- The forgetting policy is a **ring buffer + age cutoff**.
  Importance-based forgetting is a research problem; the API
  is in place but the score is not yet meaningful.
- The retrieval index is `HashMap`-based. Vector search,
  inverted indexes, and graph-based retrieval are all future
  work.
- The design does not address **memory consolidation** (turning
  many small events into one large event). This is a known
  gap; the design preserves the raw event so consolidation is
  possible later.
- The design assumes the semantic contour (Package 2) is in
  place. Without typed commitments, the `eeLinked` field has
  nothing to link to.
