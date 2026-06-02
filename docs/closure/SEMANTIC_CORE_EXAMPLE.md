# Semantic Core — End-to-End Example

- **Status**: Active (closure-phase follow-up F-05, Package 2
  acceptance criteria §5)
- **Date**: 2026-06-02
- **Refines**: `docs/closure/SEMANTIC_CORE_MIN_SLICE.md` §5
- **Related**:
  - `docs/closure/REPLAY_GATE_SPEC.md` (Package 3)
  - `docs/closure/GF_AUTHORITY_SUBSET.md` (Package 4)

## 0. What this example is

A single end-to-end walkthrough of one `commit`, one
`revise`, one `contradict`, and one `retract` against the
`SemanticCommitmentStore` from Package 2 §1.3. The example
uses the typed observation API and the four pure morphisms;
it does not exercise the rendering surface (that is
Package 4's example).

The example is **synthetic**: the typed observations are
hand-built. A real session would have them produced by the
parser. The synthetic form lets the example focus on the
store operations, not the parser.

## 1. The scenario

A 4-turn dialogue in which the system learns three facts
about the user, revises one, contradicts another, and
retracts a fourth.

| Turn | User text | System action |
|---|---|---|
| 1 | "I am a software developer." | `commit` the fact. |
| 2 | "I work in Haskell." | `commit` the fact. |
| 3 | "Actually I work in OCaml, not Haskell." | `revise` the Haskell fact to OCaml. |
| 4 | "I lied, I am not a developer at all." | `contradict` the developer fact and `retract` it. |

The store is mutated only via the four pure morphisms; no
direct field writes.

## 2. Turn 1: commit

### 2.1 The typed observation

```haskell
observation1 :: FactualClaimPayload
observation1 = FactualClaimPayload
  { fcpStatement  = "user_occupation = software_developer"
  , fcpConfidence = 0.92
  , fcpOrigin     = OriginParser "Semantic.Sense.Extract"
  , fcpTurnSeq    = TurnSeq 1
  , fcpDeps       = []
  }
```

### 2.2 The morphism

```haskell
store0 :: SemanticCommitmentStore
store0 = emptyStore (SessionId "sess-1")  -- from Package 2 §1.3

store1 :: SemanticCommitmentStore
store1 = commit (CommitmentId 1) observation1 store0
```

### 2.3 The result

`store1` has:

- `scsActive = {CommitmentId 1 → (observation1, TurnSeq 1)}`
- `scsLineage = {CommitmentId 1 → [LineageCommitted (TurnSeq 1)]}`
- `scsContradictions = []`
- `scsNextId = 2`

The `trcCommitmentEncoding` trace field on `TurnReplayTrace`
records the new `CommitmentId 1`.

## 3. Turn 2: commit (linked)

### 3.1 The typed observation

```haskell
observation2 :: FactualClaimPayload
observation2 = FactualClaimPayload
  { fcpStatement  = "user_language = haskell"
  , fcpConfidence = 0.85
  , fcpOrigin     = OriginParser "Semantic.Sense.Extract"
  , fcpTurnSeq    = TurnSeq 2
  , fcpDeps       = [CommitmentId 1]  -- depends on "is a developer"
  }
```

### 3.2 The morphism

```haskell
store2 :: SemanticCommitmentStore
store2 = commit (CommitmentId 2) observation2 store1
```

### 3.3 The result

`store2` has:

- `scsActive = {1 → (observation1, 1), 2 → (observation2, 2)}`
- `scsLineage = {1 → [Committed 1], 2 → [Committed 2]}`
- `scsContradictions = []`
- `scsNextId = 3`

The `fcpDeps` field on `observation2` links it to commitment 1.
This is the dependency tracking for future contradiction
detection.

## 4. Turn 3: revise

### 4.1 The new typed observation

```haskell
observation3 :: FactualClaimPayload
observation3 = observation2
  { fcpStatement  = "user_language = ocaml"
  , fcpConfidence = 0.88
  , fcpTurnSeq    = TurnSeq 3
  }
```

### 4.2 The morphism

```haskell
store3 :: SemanticCommitmentStore
store3 = revise (CommitmentId 2) observation3 store2
```

### 4.3 The result

`store3` has:

- `scsActive = {1 → (observation1, 1), 2 → (observation3, 3)}`
- `scsLineage = {1 → [Committed 1], 2 → [Committed 2, Revised 3 observation3]}`
- `scsContradictions = []`
- `scsNextId = 3`  -- unchanged; the id is preserved on revise

The active payload is now the OCaml one, but the lineage
preserves the Haskell version. The id (`CommitmentId 2`)
is the same; future contradictions or retrievals reference
this id.

## 5. Turn 4: contradict + retract

### 5.1 The contradiction

A new observation arrives:

```haskell
observation4 :: FactualClaimPayload
observation4 = FactualClaimPayload
  { fcpStatement  = "user_occupation = not_developer"
  , fcpConfidence = 0.70
  , fcpOrigin     = OriginDialogueOutcome 4
  , fcpTurnSeq    = TurnSeq 4
  , fcpDeps       = []
  }
```

This contradicts commitment 1 (the developer fact). The
orchestrator **records** the contradiction but does not
auto-resolve (per Package 2 §2.2).

```haskell
store4 :: SemanticCommitmentStore
store4 = contradict
  (CommitmentId 1)            -- left
  (CommitmentId 5)            -- right (the new commitment id)
  ContradictionStatement      -- kind
  (TurnSeq 4)
  store3
```

(commitment 5 is the id of `observation4` after a `commit`
call; the example skips the `commit` for brevity.)

After the contradict, `store4.scsContradictions` has one
entry: `(1, 5, Statement, 4)`.

### 5.2 The retract

Following the contradiction, the user explicitly asks the
system to retract the developer fact. The orchestrator
calls `retract`:

```haskell
store5 :: SemanticCommitmentStore
store5 = retract
  (CommitmentId 1)
  RetractionUserDenied
  (TurnSeq 4)
  store4
```

### 5.3 The result

`store5` has:

- `scsActive = {2 → (observation3, 3), 5 → (observation4, 4)}`
  -- commitment 1 is no longer active
- `scsLineage = {1 → [Committed 1, Retracted 4 RetractionUserDenied], ...}`
  -- commitment 1's lineage shows the retraction
- `scsContradictions = [(1, 5, Statement, 4)]`
  -- the contradiction is recorded but not resolved
- `scsNextId = 6`

The commitment 1 entry is preserved in the lineage but
removed from the active set. The contradiction with
commitment 5 is recorded for replay.

## 6. Replay verification

The replay gate (Package 3) requires:

```haskell
replay :: SemanticCommitmentStore -> [TurnSeq] -> [LineageEvent]
replay finalStore _ = concatMap
  (\cid -> sortBy turnSeq (scsLineage finalStore M.! cid))
  (M.keys (scsLineage finalStore))
```

For the example, `replay store5 _` returns the lineage in
turn order:

```
[LineageCommitted 1, LineageCommitted 2, LineageRevised 3 observation3,
 LineageCommitted 4, LineageCommitted 5, LineageRetracted 4 UserDenied]
```

(A real replay would also include the contradiction events
as `ContradictionEvent`s.)

The reconstruction is total and deterministic; a property
test verifies `replay finalStore _` equals the expected
event stream for a given input.

## 7. Retrieval

A consumer (Package 2 §1.5) calls:

```haskell
retrieve :: CommitmentQuery -> SemanticCommitmentStore -> [FactualClaimPayload]
retrieve q s = filter (matches q) (M.elems (scsActive s))
```

For `q = "user_language"`, the result is `[observation3]`
(the OCaml fact). Commitment 1 (developer) and commitment
2's pre-revision Haskell fact are not in the result.
Commitment 5 (not_developer) is in the active set but does
not match the query.

## 8. What this example does not show

- The **parser pipeline** that produces the typed
  observations. The example uses hand-built observations.
  A real session has them produced by
  `QxFx0.Semantic.Sense.Extract` (post-Package 4) with the
  `AuthoritySurface` parser.
- The **rendering** of the authority surface. That is
  Package 4's example.
- The **episodic memory** linking. Each commitment has an
  `EpisodicEvent` linked via `eeLinked`; the example skips
  this for brevity. Package 7's example shows the link.
- The **learning** that observes the contradiction or
  retraction. Package 8's example shows this.
- The **metacognitive evaluation** of the retract. Package
  9's example shows this.

## 9. Acceptance criteria for F-05

F-05 is closed when:

- [ ] This file is merged.
- [ ] The example compiles against `QxFx0.Semantic.Commitment`
      (post-Package 2) without modification.
- [ ] The replay verification is part of
      `Test.Suite.SemanticCommitment` (new) as a property
      test.
- [ ] The retrieval step is part of
      `Test.Suite.SemanticCommitment` as a unit test.
