# Warm-turn latency probe (2026-11-01)

- **Status**: diagnostic measurement, no runtime change. Numbers are
  single-machine observations, not yet a benchmark.
- **Why**: the M7 confirmatory run reported `avg_latency_ms = 78,699` in
  isolated mode, where every prompt pays a full bootstrap. That number cannot
  answer "how long does a turn take".
- **Method**: one `qxfx0-main --worker-stdio` process per scenario (JSON
  command protocol: `["hello","1"]`, `["turn",sid,"dialogue",text]`,
  `["shutdown"]`). The process keeps the runtime session in memory, so turns
  2..n are genuinely warm. Wall time measured from write to response line.

## Results

| scenario | bootstrap (`hello`) | turn 1 | warm turns | notes |
|---|---:|---:|---:|---|
| 3 covered definitions | 24.1 s | 47.3 s | 39.6, 44.1 s | `привет`-free, all `CMDefine` |
| mixed (4 def + 3 chat) | 23.2 s | 47.7 s | 39.8, 53.4, 49.9 s (def) / 2.6, 3.8, 2.3 s (chat) | chat turns are 10-20× cheaper |
| covered vs uncovered vs other family | 23.3 s | 47.5 s | 3.8 s (uncovered def), 2.7 s (`объясни …`) | uncovered path does not pay the cost |
| 3× identical prompt | 25.8 s | 47.7 s | 48.0, 45.9 s | **no caching** of a repeated prompt |
| same, `brain_kb.jsonl` removed | **12.1 s** | 36.6 s | 30.1 s | substrate ablation |

## What the numbers say

1. **Latency is content-path specific, not startup-dominated.** A warm
   conversational turn costs 2.3–3.8 s; a warm *covered definition* turn costs
   40–53 s. The same process serves both, so the cost lives in the semantic
   definition path (curated content + semantic network + GF-mapped predicate
   selection + linearization), not in the process.
2. **Uncovered definitions are cheap** (3.8 s), so the cost is not "definitions"
   as such — it is the corpus-backed pipeline that runs only when the topic is
   present in the merged runtime corpus (172 seed topics + 4 036 curated), not
   when the topic is unknown. `isCoveredTopic` (the 172-topic gate that decides
   *framing*) is a different predicate from "has content to select"; do not
   confuse the two.
3. **Bootstrap is ~23 s, and the substrate costs ~11 s of it.** Removing
   `brain_kb.jsonl` (53,146 entries) drops bootstrap from 23.3 s to 12.1 s and
   the covered definition turn from ~47 s to ~30–37 s. So substrate adds
   roughly 10–12 s per covered turn.
4. **~30 s per covered turn remains unexplained by these timings alone.** The
   allocation run below shows it is mostly allocation and GC, not IO or a
   subprocess. Nothing in the trace reports stage timings, so the split between
   selection and linearization still needs instrumentation.
5. **Repeating an identical prompt does not get cheaper** (47.7 → 48.0 → 45.9 s),
   so there is no per-predicate or per-surface cache to blame or to lean on.

## Consistency with the packet runs

Isolated mode = bootstrap + one turn ≈ 23 + 45 ≈ 68 s, which matches the
observed 57–74 s spread in the M7 packets. So the earlier "70 s per turn"
figure is really "23 s startup + 45 s covered-definition turn", and the M7
report's caveat was correct.

## What is not measured

- The split *inside* the covered turn between predicate selection, activation,
  and GF linearization. `trc*` fields are semantic, not temporal.
- Whether any subprocess (nix/souffle/GF) contributes. No `strace` or `perf`
  evidence was collected; the allocation figure makes a subprocess-dominated
  cost unlikely but does not exclude a short one.
- Multi-core behaviour, cache warmth across processes, and any warm-up
  strategy. Substrate is a data dependency, not a code path: it was removed
  by moving the file, and restored immediately after (verified present).

## Allocation measurement (2026-11-01, `+RTS -s`)

Timings alone say "slow"; allocation says why. Three runs, all strict mode:

| run | prompts | bytes allocated | GC time / total |
|---|---|---:|---|
| isolated | `что такое свобода?` | 96.0 GB | 28.1 s / 72.5 s (39%) |
| isolated | `привет` | 31.4 GB | 6.7 s / 26.4 s (25%) |
| one worker, 3 turns | def, привет, def | 157.1 GB | 47.0 s / 112.8 s (42%) |

Solving the three equations (bootstrap `b`, covered turn `c`, chat turn `h`,
second covered turn ≈ 0.85·c):

```
b + c        = 96.0
b + h        = 31.4
b + 1.85·c + h = 157.1
=> c ≈ 68 GB, b ≈ 28 GB, h ≈ 3 GB
```

So one warm covered-definition turn allocates **~68 GB** to produce three
sentences, and GC is **~40% of wall time**. Peak residency is only ~0.9 GB, so
this is pure churn, not a large working set. A chat turn allocates ~3 GB, i.e.
the covered path is ~20× more expensive in allocation as well as in wall time.

That is consistent with the static reading below: `scorePred` builds a
`dimCount`-sized vector for every candidate predicate of every activated topic,
and `computeFieldAffinity` walks it ten times.

**Caveat**: `+RTS -s` gives per-process totals; the per-turn split above is
derived from three runs, not instrumented. The three runs were taken on the
same machine but while the test matrix was running, so the *allocation* numbers
are stable (deterministic work) while the wall times are inflated.

## Candidate root cause from static reading (hypothesis, not yet measured)

The asymmetry "covered definition 40–53 s / uncovered definition 3.8 s /
chat 2.3–3.8 s" points at the *covered-domain selection* path, and that path
has an obvious quadratic shape:

- `QxFx0/Render/Dialogue.hs:589` calls
  `composeFromArtifactWithDiagnostics` for covered topics.
- It scans every topic whose atom set intersects the activated atoms
  (`ContentSelector.hs:201`), and runs `scorePred` once per candidate
  predicate of every such topic (`:208`).
- `scorePred` (`ContentSelector.hs:145`) builds a fresh
  `V.replicate dimCount 0.0` vector per predicate (`buildVector`, `:160`)
  and then `computeFieldAffinity` (`Space.hs:47`) walks that vector
  **five times** for the dot product and **five more times** for `normPV`
  (recomputed identically each call), plus once for the prototype norm.
- `dimCount` is the size of `snNodes ∪ topic atoms ∪ prototype atoms`
  (`Space.hs:66-68`) — with the 53,146-entry substrate merged in, that node
  set is large, and it grows every time substrate edges are added.

So the per-turn cost is roughly
`candidateTopics × predicatesPerTopic × dimCount`, with `dimCount` inflated
by the substrate. That is consistent with all four observations above:
it is covered-only, it scales with substrate, repetition does not help, and
chat turns never enter it.

Two more things worth writing down while reading:

- `Finalize/State.hs:655-675` rebuilds `topicAtomsMap`, `topicAtomsSetMap`
  (twice the same work), `buildSemanticSpace` and `buildContentSelector`
  **every turn**, even though the corpus-derived inputs are immutable at
  runtime. Only the network part changes.
- `normPV` does not depend on the field prototype, so recomputing it inside
  `computeFieldAffinity` for all five dimensions is pure redundancy.

None of this is proven yet. The cheap confirmation is a diagnostic run that
prints `dimCount`, `|activated atoms|`, `|candidateTopics|`, and the number of
`scorePred` calls for one covered turn; the definitive confirmation is a
profiling build (`-p`) of the same turn.


## Recommended next step

Add **pre-registered, opt-in stage timings** to the replay trace (for example
`trcStageTimings` with per-stage milliseconds, gated by an env flag so the
default trace schema is unchanged), then re-run this probe. Without that,
further "make it faster" work is guesswork.

An interim, cheap experiment that does not need instrumentation: bisect the
covered path by disabling one component at a time (substrate already done;
next candidates are the GF linearizer and the embedding backend).

**Order that follows from the static reading above** (each step is
behaviour-neutral until step 3):

1. Print the four diagnostic counts for one covered turn (`dimCount`,
   activated atoms, candidate topics, `scorePred` calls). If they confirm the
   arithmetic, the fix does not depend on timers at all.
2. Behaviour-neutral micro-fixes that cannot change surfaces: hoist `normPV`
   out of the five-dimension loop, build the two `topicAtoms*` maps once, and
   replace the repeated `getActivatedAtoms` scans in
   `composeFromActivation` (`ContentSelector.hs:216-222`) with a single
   `topicAct` map.
3. Only then consider the structural change — caching the immutable
   corpus-derived parts of the selector across turns. That one changes
   initialisation semantics and needs pre-registration plus the full matrix.

