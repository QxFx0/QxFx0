# Semantic Authority Core — Minimal Slice

- **Status**: Active (closure-phase work product, Package 2)
- **Date**: 2026-06-02
- **Refines**: ADRs 0007–0012, `docs/semantic_authority_inventory.md`,
  `docs/commitment_store_relation_hardening.md`,
  `docs/semantic_slice_result_ledger.md`
- **Related**:
  - `docs/closure/REPLAY_GATE_SPEC.md` (Package 3)
  - `docs/closure/GF_AUTHORITY_SUBSET.md` (Package 4)
  - `docs/closure/COGNITIVE_MEMORY_DESIGN.md` (Package 7)
  - `docs/adr/proposed/0034-self-core-role-split.md` (Package 1)

## 0. Why this slice exists

The closure plan's Package 2 says: "build a minimal but real
semantic core with typed commitments, explicit revision /
retraction / contradiction, persistent storage, replay/rebuild
from state, and connection with parsing, sense extraction, and
dialogue outcomes."

This document specifies that minimal slice. The slice is **small
on purpose**: one commitment class, one contradiction type, one
storage backend, one consumer. The goal is not a complete semantic
authority system; it is a **load-bearing, replay-visible,
rebuild-able** typed-commitment contour that the rest of the
runtime can rely on. Slice expansion (more classes, more
contradiction kinds, more consumers) is a separate package.

## 1. What is in the slice

### 1.1 The data

```haskell
-- A typed commitment is a Σ-type witness: the second component
-- (the payload) is dependent on the first (the kind).
data SemanticCommitment
  = FactualClaim !FactualClaimPayload
  deriving stock (Eq, Show, Generic)
  deriving anyclass (NFData, ToJSON, FromJSON)

data FactualClaimPayload = FactualClaimPayload
  { fcpStatement  :: !Text             -- normalised, non-text-shaped: subject/predicate/object triples
  , fcpConfidence :: !Double           -- in [0, 1]; from sense extraction posterior
  , fcpOrigin     :: !CommitmentOrigin -- which turn, which parser, which signal
  , fcpTurnSeq    :: !TurnSeq          -- monotonic per session
  , fcpDeps       :: ![CommitmentId]   -- commitments this depends on (for contradiction tracking)
  } deriving stock (Eq, Show, Generic)

data CommitmentOrigin
  = OriginParser !Text         -- parser name
  | OriginDialogueOutcome !Int -- turn outcome tag
  | OriginManual               -- for tests; should be unreachable in production
  deriving stock (Eq, Show, Generic)

newtype CommitmentId = CommitmentId { unCommitmentId :: Int }
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (Hashable, ToJSON, FromJSON)
```

A `SemanticCommitment` is **not** free text. The closure plan's
Package 4 (`GF_AUTHORITY_SUBSET.md`) defines which surface language
the parser is allowed to commit; the slice assumes the parser has
produced a typed statement and refuses to commit otherwise.

### 1.2 The operations

Four pure morphisms close the layer:

```haskell
-- 1. Create a commitment from a parsed observation.
commit
  :: CommitmentId              -- fresh id (caller manages the counter)
  -> FactualClaimPayload
  -> SemanticCommitmentStore   -- current store
  -> SemanticCommitmentStore   -- updated store, no-op if id already present

-- 2. Replace a commitment's content; preserves the id; updates
--    the lineage. Revisions are NOT retractions: the old payload
--    is retained in the lineage for replay.
revise
  :: CommitmentId
  -> FactualClaimPayload       -- new payload (must parse, must be post-original turn)
  -> SemanticCommitmentStore
  -> SemanticCommitmentStore

-- 3. Mark a commitment as retracted. Retraction is irrevocable
--    (mirror of `Essence` commitment discipline, ADR-0012).
--    The retracted payload is retained for replay but the
--    commitment is no longer active in reasoning.
retract
  :: CommitmentId
  -> RetractionReason
  -> TurnSeq
  -> SemanticCommitmentStore
  -> SemanticCommitmentStore

-- 4. Record a contradiction between two commitments. The
--    contradiction is itself a typed event; it does not auto-
--    resolve. Resolution is via revise/retract.
contradict
  :: CommitmentId              -- left
  -> CommitmentId              -- right
  -> ContradictionKind
  -> TurnSeq
  -> SemanticCommitmentStore
  -> SemanticCommitmentStore
```

```haskell
data RetractionReason
  = RetractionUserDenied
  | RetractionParserContradiction
  | RetractionOutOfScope
  | RetractionSuperseded
  deriving stock (Eq, Show, Generic)

data ContradictionKind
  = ContradictionStatement
  | ContradictionScope
  deriving stock (Eq, Show, Generic)
```

### 1.3 The store

```haskell
data SemanticCommitmentStore = SemanticCommitmentStore
  { scsActive   :: !(HashMap CommitmentId (FactualClaimPayload, TurnSeq))
  , scsLineage  :: !(HashMap CommitmentId [LineageEvent])   -- full history per id
  , scsContradictions :: ![ContradictionEvent]
  , scsNextId   :: !Int
  , scsSessionId :: !SessionId
  } deriving stock (Eq, Show, Generic)

data LineageEvent
  = LineageCommitted !TurnSeq
  | LineageRevised !TurnSeq !FactualClaimPayload
  | LineageRetracted !TurnSeq !RetractionReason
  deriving stock (Eq, Show, Generic)

data ContradictionEvent = ContradictionEvent
  { ceLeft   :: !CommitmentId
  , ceRight  :: !CommitmentId
  , ceKind   :: !ContradictionKind
  , ceTurnSeq :: !TurnSeq
  } deriving stock (Eq, Show, Generic)
```

The store is a **HashMap of id → active payload + lineage list**.
It is `Eq`, `Show`, `Generic`, and JSON-serialisable. The lineage
list is the replay source of truth.

### 1.4 The integration point

The store lives in `SystemState.ssSemanticCommitments :: Maybe
SemanticCommitmentStore`. The `Maybe` is intentional: the closure
plan's Package 1 classifies the field as `canonical` (not
`canonical-flag-off`) but the field is initialised to `Nothing`
and only populated when Package 2 lands.

A new `Core/TurnPipeline/Effects` action `commitObservation` is
the only call site. It is invoked at the **Prepare** stage, after
sense extraction produces a typed observation, and only when the
observation parses to a valid `FactualClaimPayload`. Failed
parses are logged to trace, not committed.

### 1.5 The consumer (next-turn reasoning)

The slice's only consumer is a `retrieve :: CommitmentQuery ->
Maybe [FactualClaimPayload]` function in `Semantic.Retrieve`. It
takes a query (a `Text` statement) and returns the active
commitments whose statement shares a normalised-form overlap with
the query. The retrieval is **replay-visible** (the query and
result go into `TurnReplayTrace` as `trcCommitmentRetrieval`).

This is intentionally a thin retrieval. The closure plan's
Package 7 (`COGNITIVE_MEMORY_DESIGN.md`) extends retrieval with
indexing, episodic memory, and forgetting policy. The slice
proves the **plumbing**, not the full retrieval.

## 2. What is NOT in the slice (out of scope for Package 2)

- More commitment classes (e.g. `UserPreference`,
  `DialogueCommitment`, `BeliefStore`). Deferred to a later slice.
- Contradiction resolution (auto-revising one side of a
  contradiction). Deferred; the slice only **records** contradictions.
- Cross-session persistence. `SemanticCommitmentStore` is
  in-session only. The closure plan's Package 1 classifies the
  related `ssEssence` field as `canonical-flag-off`; semantic
  commitments follow the same pattern (deferred cross-session per
  `docs/adr/proposed/0041-cross-session-essence-persistence.md`).
- Distributed / multi-store semantics. The slice is single-session,
  single-store, in-memory with JSON-serialisable boundary.
- Indexing beyond the simple HashMap. Package 7 adds indexing.
- Forgetting policy. Package 7 adds it.
- Auto-commit from parser. The slice is **manual** at the call
  site (the parser produces an observation, the orchestrator
  decides whether to commit). Auto-commit policy is a follow-up.

## 3. The Σ-type discipline

The `SemanticCommitment` is a sum-of-products Σ-type, mirroring
the `Essence` discipline (ADR-0012 §4). The slice currently has
one constructor (`FactualClaim`); future slices add more. Each
constructor is dependent on its payload, so the runtime cannot
manufacture a `SemanticCommitment` whose payload is malformed for
its kind: the only constructor for `FactualClaim` is the one that
takes a `FactualClaimPayload`, and `FactualClaimPayload` is a
closed record.

This is what makes the commitments "typed" rather than "text":
the type system rules out free-form content. Combined with
Package 4 (GF authority subset), the system **cannot** commit a
text fragment it cannot re-parse.

## 4. Replay visibility (handoff to Package 3)

Every operation on the store is replay-visible. The minimum
guarantee is:

1. Given a `SemanticCommitmentStore` snapshot, all four operations
   are deterministic (pure functions of inputs).
2. The lineage list per `CommitmentId` is the canonical source for
   "what happened to this commitment". It is preserved across
   revise/retract; it is never truncated.
3. `replayFromSnapshot :: SemanticCommitmentStore -> [TurnSeq] ->
   [LineageEvent]` reconstructs the full event stream that
   produced the store, in turn order.

Package 3 (`REPLAY_GATE_SPEC.md`) commits the broader replay
discipline; the slice's replay-visibility is a strict subset of
Package 3.

## 5. Acceptance criteria for Package 2 closure

The minimal slice is closed when:

- [ ] `QxFx0.Semantic.Commitment` module (new) exposes the four
      morphisms, the `SemanticCommitment` Σ-type, and the
      `SemanticCommitmentStore` type. No other constructor for
      `SemanticCommitment` exists.
- [ ] `QxFx0.Semantic.Retrieve` module (new) exposes the
      `retrieve` function with `trcCommitmentRetrieval` trace
      field on `TurnReplayTrace`.
- [ ] `SystemState.ssSemanticCommitments :: Maybe
      SemanticCommitmentStore` is added; the field is
      `Nothing` in `emptySystemState` and becomes `Just _` only
      after a successful `commitObservation` call.
- [ ] `Test.Suite.SemanticCommitment` (new) ships with at least:
      - determinism of all four operations;
      - revise preserves lineage;
      - retract is irrevocable (no API path reverts it);
      - contradiction is recorded but does not auto-resolve;
      - retrieval is replay-visible (the trace field is populated);
      - malformed payloads are rejected at the type level (compile-
        time guarantee, no runtime test needed).
- [ ] `Core/Consciousness/Kernel/Pulse.hs` no longer produces
      text-shaped narrative for factual claims. Instead it emits
      a typed observation; the `commitObservation` action decides
      whether to commit. (The closure plan's Package 2 ships
      this rewrite; the keyword-conditional pulse is reduced to
      a thin typed-observation emitter.)
- [ ] Replay produces identical `SemanticCommitmentStore` for
      identical `TurnInput` sequences (property test).
- [ ] Documentation: a single end-to-end example in
      `docs/closure/SEMANTIC_CORE_EXAMPLE.md` walks through one
      commit, one revise, one contradict, one retract, and the
      resulting `SemanticCommitmentStore`.

## 6. Honest limits

- The slice is **one commitment class**. A real semantic core
  needs at least three (factual, preference, dialogue). The
  closure plan defers the other two to follow-up slices.
- The slice does not address **commitment compression**. A long
  session produces a long lineage list; the closure plan's
  Package 7 handles this via forgetting policy.
- The slice does not address **commitment provenance across
  parsers**. `CommitmentOrigin.OriginParser` carries the parser
  name, but the slice does not enforce "parsers must agree on
  format". That is a follow-up.
- The slice assumes the GF authority subset (Package 4) is in
  place. Without Package 4, the parser is allowed to commit free-
  form text, which defeats the Σ-type discipline.
- The slice assumes the replay gate (Package 3) is in place.
  Without Package 3, the lineage is just data, not a replay-
  visible authority-bearing trail.

## 7. Open design questions

1. **Id management.** The slice has the caller manage the
   `CommitmentId` counter. Should the store manage it itself? A
   future slice can change this; the current shape preserves the
   `IO` boundary.
2. **Lineage truncation.** The slice preserves all lineage events.
   A long session will grow the store. Package 7 introduces
   forgetting; the slice does not.
3. **Cross-session provenance.** Out of scope; deferred per
   `docs/adr/proposed/0041-cross-session-essence-persistence.md`.
4. **Auto-commit policy.** The slice is manual at the call site.
   A future slice can introduce an auto-commit threshold (e.g.
   "if parser confidence ≥ 0.95, commit without orchestrator
   veto"). The closure plan defers this.

## 8. Why this is the **right** minimal slice

The closure plan rejects "everything is text" and rejects
"everything is a PhD thesis on epistemic commitment". The minimal
slice has:
- **One typed class** (factual claim) that proves the type
  discipline.
- **Four pure operations** (commit, revise, retract, contradict)
  that prove the lifecycle.
- **One consumer** (next-turn retrieval) that proves the
  integration.
- **Replay-visible lineage** that proves the audit story.
- **One external integration point** (parser observation →
  orchestrator → commit) that proves the boundary.

If the slice is too small to be useful in production, the
follow-up slices (more classes, auto-commit, indexing, forgetting,
cross-session) each have a small, well-defined scope. If the
slice is too large, it is rejected at review and trimmed.
