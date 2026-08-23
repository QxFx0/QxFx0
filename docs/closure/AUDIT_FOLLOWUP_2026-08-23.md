# Audit 2026-08-23 — session backup

Session: audit-research → follow-up landing. Toolchain: GHC 9.6.7 /
base 4.18.3.0, `index-state` pinned (ENV_CONTRACT.md). RAM budget for
all runs: 10 GB free → `jobs: 1` + `+RTS -M8G -RTS` already pinned in
`cabal.project`; **never run two GHC suites concurrently**.

## 1. What was audited

Four read-only research passes over the repo (concept-v3 regime,
turn pipeline/trace coherence, test infrastructure, docs/debt).
Verdict: AGENTS.md claims about concept-v3 verified line-by-line,
wiring complete, no dead code in the new regime. Found: 2 doc
factual errors, ~6 open debts, several background risks. Full details
live in the session transcript; the durable register is §4 below.

## 2. Landed this session (2026-08-23, UNCOMMITTED)

Two logical changesets, both verified by full runs:

**(a) audit follow-up hygiene**
- `AGENTS.md` — dangling `ADR-0013 Rule 5` → `ADR-0034 §3 Rule 5` /
  FOLLOWUPS Rule [15]; test-count table resynced (qxfx0-test 1239 was
  stale by 64 cases).
- `docs/GAPS.md` — Summary totals 311/312 annotated as
  curation-inventory numbers (runtime corpus is 120 topics,
  `Semantic/Content.hs`).
- `Runtime/Session/Bootstrap.hs` — empty substrate no longer degrades
  silently: `logWarn "brain_kb.jsonl loaded 0 entries…"` (+ `logInfo`
  with entry count on success). WARN confirmed in live run logs.
- `Test/Suite/SubstrateNetwork.hs` — first direct tests for
  `loadBrainKB`: missing path → `[]`; JSONL parse with bad-line skip.
  NOTE the encoding trap hit during development: a string literal via
  `BL.writeFile` under `OverloadedStrings` encodes Cyrillic Latin-1
  truncated — must go through `TE.encodeUtf8`.
- `Test/Suite/RenderAuthorityStub.hs` deleted (self-invented fake
  framework; coverage lives in `Test.Suite.AuthoritySurface`);
  removed from `qxfx0.cabal`.
- `Test/Suite/MorphologicalNormalization.hs` (6 cases, born-dead,
  proper HUnit) reactivated in `TestMain.hs` (`qxfx0-test`).
- `.gitignore` — `*_test_*.db` pattern covers the root artifact
  `qxfx0_test_native_sqlite_nulls.db` (no tracked files matched).

**(b) live-regime trace fix**
- `Finalize/Projection.hs` — `trcRegimeVersion`,
  `trcFamilyDivergenceActive`, and the `familyDivergenceOccurred` gate
  now read `liveRegime = ssCurrentRegime nextSs` instead of static
  `defaultRuntimeRegime` (closes the "left for a separate pass" note
  from the R4 morphology fix). Fresh sessions: no behavior change
  (live == default). Restored sessions with a foreign persisted regime
  now surface it verbatim in the trace.
- `Test/Suite/M5Regime.hs` — regression pin
  `m5RegimeStampsLiveSessionRegime` via `buildFinalizeFixtureWithState`
  (foreign mathVersion `currentMathVersion + 99`, inverted
  familyDivergence flag; trace must stamp exactly those).
- `trcFamilyDivergenceOccurred` is write-only in runtime (grep: only
  tests reference it) — no downstream breakage.

**Verification**: `qxfx0-test` **1304 cases, 0 errors, 0 failures,
exit 0** (growth: concept-v3 +56 before this session, this work +9);
`qxfx0-test-integration` **46/46 green**. NOT re-run since the
changes: fast / unit / property / slow (their counts in AGENTS.md are
the 2026-08-22 snapshot; suites compile the changed modules via
test-common, so a re-run is due).

**One-off flakiness**: the first qxfx0-test run of the session showed
2 extra failures that did not reproduce in three subsequent full runs
(names not captured — first log was truncated by `tail`). Re-observe
on the next full run before treating as real.

**Suggested commit split**: (a) as
`fix(audit-followup): substrate observability, dead-suite cleanup, doc integrity`;
(b) as
`fix(trace): stamp live ssCurrentRegime in regime trace fields (M5 pin)`.

## 3. Why RAM matters here

`cabal.project` pins `jobs: 1` and `ghc-options: +RTS -M8G -RTS`.
One GHC build+run at a time fits the 10 GB budget; two concurrent
suites do not. Full `qxfx0-test` run ≈ 30–40 min wall-clock; log to
a file (`> /tmp/run.log 2>&1`) because HUnit progress lines are
carriage-return dense and `tail` of a pipe loses failure names.

## 4. Open debt register (durable findings)

P1 — observability gaps:
1. Write-only trace fields (no runtime readers; only tests/JSON):
   `trcSelfDivergence*` (4), `trcEssenceResetEvent`, `trcFmarMode`,
   `trcFamilyDerivationChain`, `trcGenerationTrace`,
   `trcAnalogicalSource`. Precedent for the fix: `analyzeUserRegime`
   (`Observability/TraceAnalysis.hs:447-467`) turned regime traces
   from write-only into flagged anomalies.
2. R5 residual audit exposes only the current-turn
   `ur5PredictionError`; no window aggregate in `UserR5Trace` —
   model degradation is invisible in real time.
3. `trcSubstrateHops` == `trcSubstrateEdgesUsed` (duplicate value,
   `Projection.hs:454,456`).

P2 — doc/code small rot:
4. `Semantic/MoveGraph.hs:33-35` doc comment promises
   resonance+confidence mid-point blending in `viabilityTarget`;
   code blends only confidence.
5. README numbers: "~35 philosophical topics" (corpus is 120),
   "1247 fast tests" (fast is 1754 on the 2026-08-22 snapshot).

P3 — infrastructure:
6. test-common compiles all 149 Test.Suite modules into each of the
   6 suites (build-time cost); split per-suite other-modules.
7. `Test/Suite/SelfEssenceCommit.hs:98,424` — two TODO tests assert
   shape only, not the real `buildNextSystemState`.
8. `brain_kb.jsonl` (53K entries) still absent; source undocumented
   (ops task). Empty-substrate is now WARN-observable but the layer
   itself remains empty on fresh clones.
9. Four concept-v3 follow-ups (receiver-conditioned decompression,
   offline encoder/effect-matrix fitting, learning-targets ADR,
   ssUserModel absorption) live only in AGENTS.md — not mirrored in
   GAPS/FOLLOWUPS.

## 5. Forward plan

1. **Commit** the two changesets (split above). Working tree is
   otherwise clean; nothing else staged.
2. **Re-run fast / unit / property** sequentially under the RAM
   budget to refresh the stale rows (slow optional); update the
   AGENTS.md table rows and the "re-verified" annotation.
3. **P1.1 trace readers** (next substantive pass): extend
   `TraceAnalysis` with a self-layer analyzer consuming the
   self-divergence group + `trcEssenceResetEvent` (pattern:
   `analyzeUserRegime`); decide flags names first
   (e.g. `self_divergence_sustained`, `essence_reset_without_event`).
4. **P1.2**: add `ur5WindowMean` to `UserR5Trace` (state already
   carries `u5DivergenceWindow`; `pushR5Sample` maintains it).
5. **P2 batch** (cheap): MoveGraph doc comment, README numbers,
   `trcSubstrateHops` dedup decision (keep both names but distinct
   semantics, or deprecate one).
6. **P3**: SelfEssenceCommit TODO tests; test-common split (measure
   build time before/after); brain_kb provenance doc or fixture.
7. **Flaky watch**: on every full run, capture failure names to a
   file before anything else; if the 2 ghost failures recur, bisect
   by suite (suspects: env-dependent/network-marked tests).
