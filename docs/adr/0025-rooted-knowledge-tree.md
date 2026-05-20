# ADR-0025: Rooted Knowledge Tree

- **Status**: Accepted
- **Date**: 2026-05-20
- **Refines**:
  - [ADR-0012 — Essence Commitment](./0012-essence-commitment.md)
  - [ADR-0017 — Post-Commitment Adaptation](./0017-post-commitment-adaptation.md)
- **Related**:
  - `QxFx0.Learning.KnowledgeTree`
  - `QxFx0.Core.TurnPipeline.Finalize.State.buildNextSystemState`

## 1. Context

The endogenous learning architecture (WP1–WP5) detects deficits, selects
tools, and runs a closed calibration loop, but it accumulates knowledge
only inside short-lived proposal/rule objects.  There is no persistent,
inspectable structure that records which fruits of learning were
validated, which remain provisional, and which have been refuted.

Without such a structure:
- Unbounded growth of provisional rules risks memory leaks.
- There is no structural health signal to feed back into calibration.
- Rollback reverts to a previous version but does not explain *why* the
  tree decayed.

We need a bounded, rooted tree that mirrors the agent’s epistemic
state: branches for rule families, fruits for individual propositions,
and explicit lifecycle states (grafted / quarantined / pruned).

## 2. Decision

### 2.1 Introduce `KnowledgeTree`

A tree with three partitions:

1. **Branches** (`Map Text [Branch]`) — validated fruits grouped by rule
   family (e.g. "agreement").  Each branch carries a health score that
   decays when fruits are removed.
2. **Quarantine** (`[KnowledgeFruit]`) — provisional fruits that have not
   yet met the promotion criteria.
3. **Counters** — monotonic counters for grafted, quarantined, promoted,
   and pruned fruits, so telemetry can report growth and decay rates
   without scanning the full structure.

```haskell
data KnowledgeTree = KnowledgeTree
  { ktBranches      :: !(Map Text [Branch])
  , ktQuarantine    :: ![KnowledgeFruit]
  , ktGraftedCount  :: !Int
  , ktQuarantinedCount :: !Int
  , ktPromotedCount :: !Int
  , ktPrunedCount   :: !Int
  }

data Branch = Branch
  { brRule        :: !Text
  , brFruits      :: ![KnowledgeFruit]
  , brHealth      :: !Double   -- ∈ [-1, 1], decaying -> negative
  , brCreatedTurn :: !Int
  }

data KnowledgeFruit = KnowledgeFruit
  { kfProposition    :: !Text
  , kfSource         :: !KnowledgeSource
  , kfValidated      :: !Bool
  , kfConatusDelta   :: !Double
  , kfPredictiveDelta:: !Double
  , kfGraftedTurn    :: !(Maybe Int)
  , kfObservedTurn   :: !Int
  }
```

### 2.2 Lifecycle operations

| Operation | Trigger | Effect |
|-----------|---------|--------|
| `graftFruit` | Fruit is `validated=True` and net delta > 0 | Fruit enters branch; `ktGraftedCount` increments |
| `quarantineFruit` | Fruit is marginal (weak deltas) | Fruit enters `ktQuarantine`; `ktQuarantinedCount` increments |
| `promoteFromQuarantine` | After ≥`minQuarantineTurns` and net delta > 0 | Moves fruit to branch; increments `ktPromotedCount` |
| `pruneFruits` | Fruit is `validated=False` or `netDelta < -0.3` | Drops fruit; decrements branch health by 0.05 |
| `pruneBranches` | Branch health < `-0.5` after ≥`minDecayTurns` | Removes branch; increments `ktPrunedCount` by fruit count |

### 2.3 Health and calibration signal

Branch health starts at `0.0` and drops by `0.05` for every pruned
fruit.  If a branch stays below `-0.5` for at least `3` turns, it is
removed entirely.  The average branch health is exposed via
`branchHealthTrend` and consumed by `computeCalibrationSignal`
(ADR-0026) as an inverted component: a decaying tree raises adaptation
pressure.

### 2.4 Persistence

`KnowledgeTree` has full `FromJSON`/`ToJSON` instances with
`.!=` backward-compatible defaults, and is carried in `SystemState` as
`ssKnowledgeTree`.  `buildNextSystemState` syncs the tree root at the
end of every turn (prune, health update, counter reset if needed).

## 3. Consequences

- **Bounded memory**: quarantine size is capped by promotion and pruning;
  branch count is bounded by health-driven removal.
- **Explainable structure**: telemetry can report which rule families are
  healthy vs. decaying without inspecting raw state history.
- **Calibration feedback**: tree health directly feeds the bounded
  calibration signal, closing the loop between structural retention and
  weight adaptation.
- **No weakening of gates**: the tree is pure data; no thresholds or
  commitment-law contracts are modified.

## 4. Acceptance Criteria

- [x] `KnowledgeTree`, `Branch`, `KnowledgeFruit` implemented with pure
  lifecycle functions.
- [x] `graftFruit`, `quarantineFruit`, `promoteFromQuarantine`,
  `pruneFruits`, `pruneBranches` covered by unit tests.
- [x] JSON round-trip with backward-compatible defaults verified.
- [x] `branchHealthTrend` feeds into `computeCalibrationSignal`.
- [x] `buildNextSystemState` wires tree root sync and pruning.
- [x] Architecture gate 12/12 PASS (no bare partial functions in new
  modules).
- [x] Fast suite: 527/527 PASS; full suite: 654/654 PASS.
