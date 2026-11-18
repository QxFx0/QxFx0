# Pre-registration — replay envelope v1 (2026-11-17)

- **Status**: PRE-REGISTERED. Predictions below are stated **before** the
  implementation and before any replay measurement. The Result section is
  filled only after the post-change runs.
- **Trigger**: the 2026-11-17 truth pass narrowed the README claim to
  "turn path deterministic by construction; the global replay claim is
  withheld until the persisted replay envelope lands"
  (`docs/closure/REPLAY_GATE_SPEC.md` §3.1 already specifies an envelope with
  `inputText`, but no such type exists in code). The DB stores no input text
  (`turn_quality.scene_request` is `tiBestTopic`, not the prompt) and no turn
  time, so a DB round-trip replay is impossible today.
- **Scope**: one optional trace sub-record (`trcReplayEnvelope`), one optional
  `EffectSnapshot` field (`esCurrentTime`), the replay overlay
  (`mkReplayPipelineIOWith`), one opt-in `RuntimeContext` field
  (`rcReplayTrace`), one new test suite, and one trace-schema section. **No**
  routing, threshold, weight, marker-lexicon, contour, move-graph, crisis-gate
  or persistence-schema change. `currentMathVersion` is **not** bumped (no
  math change); `r5EncoderVersion` stays `2`.

## 1. The gap (measured, not inferred)

| Needed for replay | Where it lives today | Persisted? |
|---|---|---|
| raw input text | `PrepareStatic.psInputText` / `InputPropositionFrame.ipfRawText` | **no** — `turn_quality.scene_request` is `tiBestTopic` |
| turn time (`tiStartTime`) | `TurnReqCurrentTime` → `tiStartTime` | **no** |
| request id | `TurnReqRequestId` → `trcRequestId` | yes (trace) |
| `apiHealthy` | `TurnReqApiHealth` → `trcEffectSnapshot.esApiHealthy` | yes (trace) |

`mkReplayPipelineIO` replays only `TurnReqApiHealth`; every other effect falls
through to `defaultTestInterpreter` (fixed test time, `"request-id-test"`), so
it is a unit-test replay, not a session replay.

## 2. The envelope (v1)

New trace sub-record:

```
ReplayEnvelope
  { reEnvelopeVersion :: !Int   -- 1
  , reInputText       :: !Text  -- exact raw input (ipfRawText)
  }
```

New `EffectSnapshot` field:

```
esCurrentTime :: !(Maybe UTCTime)  -- tiStartTime captured at prepare time
```

`trcReplayEnvelope :: !(Maybe ReplayEnvelope)` is populated in
`buildTurnProjection`; `esCurrentTime` in the same function. Old traces decode
with `Nothing` (backward-compatible); old snapshots decode with
`esCurrentTime = Nothing`.

Replay overlay (`mkReplayPipelineIOWith base trace`):

| request | replayed value |
|---|---|
| `TurnReqApiHealth` | `esApiHealthy` |
| `TurnReqCurrentTime` | `esCurrentTime` when present; otherwise **delegate to `base`** (old traces are explicitly not time-replayable) |
| `TurnReqRequestId` | `trcRequestId` |
| everything else | delegate to `base` |

`mkReplayPipelineIO trace = mkReplayPipelineIOWith <stateless test base> trace`,
so the existing narrow replay keeps its behaviour.

`RuntimeContext` gains `rcReplayTrace :: !(Maybe TurnReplayTrace)` (default
`Nothing`). `toPipelineIO` applies the overlay only when it is `Just`; the
production path is byte-identical when `Nothing`. This is the opt-in session
replay mode: `runTurnInSession` keeps its readiness/autonomous/persistence
behaviour, but the three non-deterministic ambient inputs come from the
recorded trace.

## 3. What is **not** in v1

The envelope does **not** record `TurnReqNixGuard`, `TurnReqShadow`,
`TurnReqEmbedding`, GF linearization, the Agda witness, checkpoints or the
feedback mirror. A replay re-executes those effects; the claim below is
therefore limited to the three recorded ambient inputs. If a re-executed
effect differs between two runs, that is a finding, not a silent pass.

## 4. Claim

For a recorded session, re-running the **same binary + resources** with the
recorded input texts and the recorded ambient inputs (time, request id,
`apiHealthy`) reproduces the user-visible surface and the full
`TurnReplayTrace`. Allowed diffs: wall-clock phase logs (not in the trace), DB
autoincrement ids, filesystem paths. **Not** allowed silently: any trace field
difference.

## 5. Predictions (before measurement)

- **P1 (envelope round-trip)**. `encodePersistedReplayTrace` /
  `decodePersistedReplayTrace` round-trips `trcReplayEnvelope` and
  `esCurrentTime` exactly. A pre-v1 trace with neither field decodes to
  `Nothing` / `Nothing`; a v1 trace with `esCurrentTime = Nothing` decodes as
  `Nothing`.
- **P2 (overlay)**. `mkReplayPipelineIO` returns the recorded time and request
  id; with `esCurrentTime = Nothing` it delegates to the base interpreter
  (fixed test time), and that fallback is documented, not silent.
- **P3 (bounded recorded session, CI)**. A 3-turn session is run twice in two
  fresh DBs with the same resources: run A records the traces; run B replays
  from the **recorded envelopes and snapshots only** (input text from
  `reInputText`, time from `esCurrentTime`, request id from `trcRequestId`,
  `apiHealthy` from `esApiHealthy`). Prediction: **3/3 surfaces identical and
  3/3 full traces identical** (`Eq`). The test makes `apiHealthy`
  discriminating: run A's health cache is seeded `True`, run B's cache is
  seeded `False`; a working replay must still produce `True` (the recorded
  value).
- **P4 (12-turn recorded session, eval leg)**. The same mechanism on a 12-turn
  definition/challenge session: prediction **12/12 surfaces and 12/12
  traces identical**. This is the largest bounded leg that fits the current
  matrix budget.
- **P5 (80-turn capture, deferred)**. The existing 2026-11-13 capture
  **predates this envelope** (no input text, no `esCurrentTime`), so it cannot
  be replayed exactly. A fresh 80-turn capture with the new binary is a
  separate eval run (~48 min capture + ~48 min replay) and is **not** a bar
  for this landing; it is reported separately if run. No numeric prediction is
  made here for that leg.

## 6. Red checks

- Drop `esCurrentTime` population/replay → **P2** and **P3** must fail on the
  time-derived trace fields.
- Drop `trcReplayEnvelope` population → **P3** cannot obtain the input text
  from the trace (the test must read it from the envelope, not from an
  in-memory list).
- Drop the `rcReplayTrace` overlay → **P3** must fail the discriminating
  `apiHealthy` assertion (run B would use the seeded `False`).

## 7. Governance

- Trace schema: new optional sub-record (§13 of `TRACE_SCHEMA.md`); old
  traces remain readable.
- No persistence-schema migration: the envelope lives inside the already
  persisted `replay_trace_json`.
- No math-version bump; no `MATH_CHANGE_PROTOCOL.md` row.
- The README global determinism claim stays **withheld** until P3 (and, if
  run, P4) are green; this pre-registration does not by itself widen the
  README claim.

## 8. Result

_Filled after the post-change runs; predictions are not rewritten._

### P1 — envelope round-trip: PASS

Measured 2026-11-17 by `Test.Suite.ReplayEnvelope` (fast suite,
`QXFX0_FAST_SUITE=replayenvelope`):

- pre-v1 `EffectSnapshot` JSON (`{"esApiHealthy":true}`) decodes with
  `esCurrentTime = Nothing`;
- a v1 snapshot round-trips the captured time exactly;
- `ReplayEnvelope` round-trips with `reEnvelopeVersion = 1`;
- every recorded live turn carries an envelope with the exact raw input and a
  snapshot with a non-`Nothing` time, read back through
  `decodePersistedReplayTrace` (the real DB codec), not from an in-memory
  list.

### P2 — overlay: PASS

Measured 2026-11-17:

- `mkReplayPipelineIO` returns the recorded time, the recorded request id and
  the recorded `apiHealthy = True` while the stateless base interpreter
  answers `fixedTestTime`, `"request-id-test"` and `False`;
- a pre-v1 trace (`esCurrentTime = Nothing`) delegates the clock to the base
  (fixed test time) and a trace with no snapshot delegates `apiHealthy` to
  the base (`False`) — the fallback is explicit, not silent.

### P3 — bounded 3-turn recorded session: PASS on surfaces and traces; the apiHealthy sub-clause as written is a **test-design miss**

Measured 2026-11-17 (`Cases: 6 Tried: 6 Errors: 0 Failures: 0`, exit 0):
run A recorded three turns with `rcTimeSource` fixed at
`1800000000 / +60 / +120`; run B replayed them in a fresh DB with
`rcTimeSource` deliberately wrong (`-100000 s` from epoch) and the input text
taken from `reInputText`. Result: **3/3 surfaces identical and 3/3 full
`TurnReplayTrace` values identical** (`Eq`).

**Miss (reported, not patched).** P3 predicted that seeding run B's health
cache `False` would make the session-level `apiHealthy` replay discriminating.
It cannot: `checkEmbeddingHealthWithManager` short-circuits the
`EmbeddingBackendLocalDeterministic` branch and returns `ehOperational = True`
**without consulting the cache**, so `readApiHealth` is `True` in both runs
regardless of the seed, and run A can only ever record `True`. The
discriminating `apiHealthy` assertion therefore lives at the overlay level
(P2: base `False` vs recorded `True`), not at session level. Time and request
id remain discriminating at session level: without the overlay, run B would
use the wrong clock and a fresh UUID, and the full-trace comparison fails
(red check C).

### P4 — 12-turn recorded session: PASS

Measured 2026-11-17 (`QXFX0_REPLAY_12_TURN=1`,
`QXFX0_FAST_SUITE=replayenvelope`): **12/12 surfaces identical and 12/12
full traces identical**, 24 turns total (12 record + 12 replay), exit 0.
The record phase ran 14:05:26→14:12:24 and the replay phase
14:12:24→14:19:19 (≈14 min for the leg); `+RTS -s` reports 1.28 GB maximum
residency and 2.76 GB total memory, `-M12G`.

Operational note: the combined 7-test process (3-turn + 12-turn in one
heap) exhausted `-M10G` during the replay bootstrap after the 12 recorded
turns (`Heap exhausted`, exit 251); the 12-turn leg was therefore measured
in isolation under `-M12G`. The 3-turn leg is measured separately (P3) and
the committed suite keeps both entries — the 12-turn entry is a no-op
unless the env var is set.

**Operational trap found during red check A (2026-11-17).**
`cabal build qxfx0-test-fast -O0` builds the library into
`.../qxfx0-0.1.0.0/noopt/build`, but the inplace package registration
(`dist-newstyle/packagedb/ghc-9.6.7/qxfx0-0.1.0.0-inplace.conf`) still points
at the default `.../qxfx0-0.1.0.0/build`; the `-O0` test binary therefore
links the **default** archive. A library edit followed by an `-O0` test run
can silently test stale code (the first red-check A run passed for exactly
this reason). The red checks are therefore run in the default profile
(`cabal build qxfx0-test-fast`), which rebuilds the archive the test
actually links.

### Red checks (measured 2026-11-17)

- **A — recorded-time replay branch removed** (`Replay.hs`):
  `Cases: 7 Tried: 7 Failures: 2`, exit 1. (1) `replay overlay: recorded
  time, request id and apiHealthy win` fails on `recorded time wins`
  (expected `2027-01-15 08:00:00 UTC`, base answers `1858-11-17 00:00:00
  UTC`, i.e. `fixedTestTime`); (2) the recorded-session test fails with
  `differing trace fields: ["trcEffectSnapshot"]` — the surface still
  reproduces, so the clock is pinned by the snapshot field alone. This
  matches the P2/P3 prediction: `trcEffectSnapshot` is the only
  time-derived trace field.
- **B — `trcReplayEnvelope` population removed**
  (`Finalize/Projection.hs`): `Failures: 1`, exit 1. The recorded-session
  test fails at `Test/Suite/ReplayEnvelope.hs:181` with `live turn must
  record a replay envelope`; the replay phase never starts, because the
  input text is obtainable only from the envelope (the test does not keep an
  in-memory input list for the replay leg).
- **C — `rcReplayTrace` overlay removed** (`Wiring/Pipeline.hs`):
  `Failures: 1`, exit 1. The recorded-session test fails with `differing
  trace fields: ["trcEffectSnapshot","trcRequestId"]`; the surfaces still
  reproduce, so the overlay is pinned by the recorded clock and request id.
  The pre-reg's §6 text predicted the session-level `apiHealthy` assertion
  would fail here; that prediction is the documented test-design miss (the
  local-deterministic backend never consults the health cache), and the
  actual failing fields are time and request id, as the P3 result note
  already stated.

### Green re-run on the committed tree (2026-11-17)

After all three red-check edits were reverted, the default-profile binary was
rebuilt (`cabal build qxfx0-test-fast`, 1 m 27 s) and the suite re-run:
`Cases: 7 Tried: 7 Errors: 0 Failures: 0`, exit 0, 6 session turns
(3 record + 3 replay). The 12-turn entry stayed a no-op (env var unset), as
designed. This is the measured green state of the committed suite; the
12-turn leg's own green state is the P4 record above.

### Miss M1 — the recorded clock breaks two pre-existing fresh-session pins (2026-11-18)

**Not predicted.** P1–P5 covered the new suite only. The 2026-11-17 matrix
(10 steps, tree frozen) found **3 red steps** — `main-runtime`, `slow-state`,
`slow-runtime` — each with **exactly one** failure, and all three are the same
two pre-existing pins:

- `Test.Suite.RuntimeInfrastructure` — QuickCheck property `persisted replay
  trace json deterministic across fresh sessions` (failure at
  `RuntimeInfrastructure.hs:3029`, inside `quickCheckTest`);
- `Test.Suite.StatePersistence` — `persisted replay trace should be
  deterministic across fresh sessions for input: Что такое свобода?`
  (`StatePersistence.hs:1427`).

Both compare the persisted `replay_trace_json` of two **fresh sessions running
the same input under the live clock**, normalizing only `trcSessionId` and
`trcRequestId`. Envelope v1 puts `tiStartTime` into the trace
(`trcEffectSnapshot.esCurrentTime`), so the two traces now differ by that one
field. Measured evidence (slow-state log): both JSON blobs are 6 178 449
characters, identical up to index 171 272, where the only difference is
`esCurrentTime` — `2026-11-17T18:51:19.281423752Z` vs
`2026-11-17T18:52:22.018372769Z`. Nothing else differs.

This is a real semantic narrowing, not a test artifact: the persisted trace is
now deterministic **modulo the recorded clock**, because the clock is now one
of the recorded ambient inputs (that is what makes time replay possible).

Fix (test-only, no runtime change): the live-clock pin normalizes
`esCurrentTime` inside `trcEffectSnapshot` exactly like the session and
request ids (`normalizeRecordedClock` in both suites), and the fixed-time pin
(`QXFX0_TEST_FIXED_TIME`, which stayed green in the same matrix) keeps exact
equality **including** the clock. The narrowing is stated in
`docs/closure/TRACE_SCHEMA.md` §12.

### Final matrix (2026-11-18, after the M1 fix)

Matrix `2026-11-17b`, tree `7f10674` + 22 uncommitted paths, substrate active,
tree byte-identical start→end (12:20:10→17:43:01 UTC), **10/10 steps exit 0**:

| step | cases | result |
|---|---|---|
| unit | 1861 | 0 failures |
| fast | 1962 | 0 failures |
| property | 244 | 0 failures |
| integration | 47 | 0 failures |
| main-http | 23 | 0 failures |
| slow-http | 23 | 0 failures |
| slow-lifecycle | 11 | 0 failures |
| main-runtime | 106 | 0 failures |
| slow-state | 50 | 0 failures |
| slow-runtime | 106 | 0 failures |

Total **4 433 cases** (the 2026-11-16 landing was 4 425; the difference is the
7 `ReplayEnvelope` cases plus 1 new `RoundTrip` case). The main core slice
(1261 = 1254 + 7) was not re-run — same 15 GB OOM contour as before. The first
run of this matrix (2026-11-17, tree `7f10674` + 22 paths, before the M1 fix)
was 7/10 with the M1 pin red in three groups; that record is kept in
`reports/eval_runs/_logs/matrix-20261117/` and is not overwritten.

### Honest limit: no production replay driver in v1

The landing makes a recorded turn *replayable*; it does not ship a CLI/ops
driver that reads a session from the DB and re-executes it. The test suite is
the only consumer of `reInputText` today; the runtime opt-in
(`rcReplayTrace`) consumes the trace's ambient values, not the envelope. The
`reEnvelopeVersion` rule ("reject an unknown version, do not guess") is
therefore a contract for the future driver, pinned today only by the
round-trip and `version == 1` assertions.

### P5 — 80-turn capture: deferred as pre-registered

The 2026-11-13 capture predates the envelope and carries neither
`trcReplayEnvelope` nor `esCurrentTime`, so it is not replayable. No fresh
80-turn capture was run for this landing.

### Clerical corrections and observed artifacts

- §7 of this document said "§13 of `TRACE_SCHEMA.md`"; topic-resolution is
  §13, the envelope is the new **§14**. Corrected in `TRACE_SCHEMA.md`.
- Replay mode replays `tiStartTime`, so the per-turn log line's `total_ms` is
  computed against a recorded (future) timestamp and can be **negative**
  (observed `total:-5.08e9 ms`). This is a wall-clock log artifact only — the
  trace carries no duration field — and it exists only in the opt-in replay
  mode.
- The 3-turn suite took ~30 min wall clock; the last replayed turn's render
  took 342 s (the known long-render/stall class, not a replay regression).
