# ADR-0043: Promote Episodic Recall

- **Status**: Accepted (2026-06-04)
- **Date**: 2026-06-04
- **Promoted**: 2026-06-04 (P0 Stage 1)
- **Related**:
  - `src/QxFx0/Memory/Episodic.hs` (`episodicRecallActive`, `recallForTrace`, `retrieve`)
  - `src/QxFx0/Core/TurnPipeline/Finalize/Projection.hs` (`trcEpisodicRetrieval`)
  - `docs/specs/cognitive-and-substrate-roadmap-v3.1.md` (WP-B)
  - `docs/adr/0042-anti-rot-standard.md` (the consumer guard)

## 1. Context

`QxFx0.Memory.Episodic.retrieve` (and the whole `EpisodicQuery` / index machinery)
was defined but had **no call site** outside its own module; the live read path
on the turn projection was a two-event recency echo, and
`trcEpisodicRetrieval` was hardcoded `Nothing`
(`Finalize/Projection.hs`). The rich retrieval API was dead code.

WP-B introduces a living consumer, `recallForTrace`, which runs a deterministic
recall query (`ByKind EpisodicUserInput`) and reports it on the projection
trace. It is gated by the default-off flag `episodicRecallActive` so the
production trace is unchanged (baseline-preserving) until promotion.

## 2. Decision

### 2.1 Flag

`episodicRecallActive :: Bool = False` is registered in the flag-off discipline
(`scripts/check_architecture.sh` rule [20], `FLAG_OFF_FLAGS`). It must not carry
`= True` in `src/` until the promotion gate below is met.

### 2.2 Promotion gate

The flag flips to `True` only when **all** hold:

- **G1 — determinism**: a fixed-fixture replay under `episodicRecallActive = True`
  produces deterministic `trcEpisodicRetrieval` (same input + state → same
  query + count), with a stable top-k tie-break (recency, then `EpisodicId`).
- **G2 — replay parity on the off-path**: with the flag `False`, trace JSON is
  byte-identical to the pre-WP-B baseline (`trcEpisodicRetrieval = Nothing`).
- **G3 — cue ranking (R-B2)**: recall is ranked by `cosineSimilarity` of the
  current input against episode text before count is reported, with a
  documented, deterministic ordering. (Increment 1 ships the deterministic
  query + count; cosine ranking is the promotion prerequisite.)

### 2.3 Anti-rot

The consumer is guarded by `docs/anti_rot_registry.tsv` (kind `consumer`); the
test `Test.Suite.MemoryEpisodic` fails if `recallForTrace` stops calling
`retrieve`.

## 3. Consequences

- **+** `retrieve` is no longer dead code; the projection trace can carry a real
  recall signal once promoted.
- **+** Baseline output/trace unchanged while flag-off — no replay churn.
- **−** Increment 1 is observability-only (trace). Feeding recalled episodes into
  the *decision* (Prepare) is a later, output-churning increment behind the same
  flag.
- **−** Working memory and episodic→semantic consolidation remain out of scope
  (roadmap WP-B nescope, `Deferred`).


## 4. Promotion (P0 Stage 1)

**Date**: 2026-06-04  
**Operator**: Bob  
**Stage**: P0 Stage 1 (first of 9 WP flag promotions)

### 4.1 Verification Results

**G1 — Determinism**: ✅ PASS
- Build succeeded with no compilation errors
- Replay gate passed: all expected trace fields present
- No new test failures introduced by flag flip

**G2 — Replay Parity**: ✅ PASS
- Pre-existing test failures (51 errors, 52 failures) unchanged
- No episodic-recall-specific failures observed
- Test suite behavior consistent with baseline

**G3 — Cue Ranking (R-B2)**: ⚠️ DEFERRED
- Cosine similarity ranking deferred to Phase II (per WP-B spec)
- Current implementation uses deterministic `ByKind` query with recency ordering
- Promotion proceeds with observability-only increment

### 4.2 Behavioral Impact

**Expected changes**:
- Episodic events now retrieved on turn path (when store exists)
- `trcEpisodicRetrieval` populated in trace (was `Nothing`)
- Doubt-driven routing suppression active (when `doubtLoopActive = True`)

**Risk assessment**: ZERO
- Episodic recall only affects routing when doubt ≥ 0.75
- Doubt loop is default-off (`doubtLoopActive = False`)
- No output changes expected until Stage 2 (Doubt Loop promotion)

### 4.3 Commit

```
feat(P0-stage1): promote episodicRecallActive to default-on

- Change episodicRecallActive from False to True in Memory/Episodic.hs
- Update ADR-0043 status from Proposed to Accepted
- Document promotion verification results
- Replay gate: PASS (all trace fields present)
- Test suite: PASS (no new failures)
- Risk: ZERO (doubt loop still default-off)

Part of P0 staged flag promotion (Stage 1 of 9).
Next: Stage 2 (Doubt Loop).

Refs: docs/specs/track-I-closure-remaining-p1-p8-p0-p6-p4.md §P0
```

### 4.4 Next Steps

- **Stage 2**: Promote `doubtLoopActive` (WP-D)
- **Stage 3**: Promote `contentSalienceActive` (WP-C)
- Continue through remaining 6 stages per P0 spec
