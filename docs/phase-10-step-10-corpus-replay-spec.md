# Phase 10 Step 10.10 — Corpus Replay Verification and Doc Sync
## Implementation Specification for KIMI

- **Authoritative architecture**: [`ADR-0012`](./adr/0012-essence-commitment.md).
- **Predecessor specs**:
  [`Phase 9`](./phase-9-essence-implementation-spec.md),
  [`Phase 10`](./phase-10-essence-commitment-implementation-spec.md).
- **Status of Phase 10 implementation**: Steps 10.1–10.9 **landed** (582/582 PASS, zero new warnings). Only Step 10.10 remains.
- **Status of this spec**: Normative.
- **Date**: 2026-05-19.
- **Single contract**: Run `qxfx0-test-integration` with `QXFX0_ESSENCE_COMMITMENT_ENABLED=1`, observe **zero `EssenceRupture` events**, then sync the documentation. **Do not sync docs first.** Do not pretend default-off coverage substitutes for flag-on corpus replay — it does not.

## 0. Why this exists as a separate spec

KIMI's previous report claimed the corpus replay was "implicitly verified" by the 582 default-off tests. That claim is incorrect: with `essenceCommitmentEnabled = False`, `validatePlan` is never invoked, so zero ruptures is a tautology. The actual contract from ADR-0012 §9 lock E8 — *zero ruptures on the corpus under flag-on* — has not been exercised. This spec closes that gap explicitly.

## 1. Execution

### Step 10.10.1 — Run the flag-on integration suite

From `@/home/liskil/my-haskell-project/QxFx0/`:

```bash
QXFX0_ESSENCE_COMMITMENT_ENABLED=1 \
  cabal test qxfx0-test-integration --test-show-details=streaming \
  2>&1 | tee /tmp/qxfx0-phase-10-corpus-replay.log
```

The build must already be green from Step 10.9. If it is not, **stop and report** — Step 10.10 is not the place to fix Step 10.9 regressions.

### Step 10.10.2 — Inspect the log for ruptures

```bash
grep -ci 'EssenceRupture' /tmp/qxfx0-phase-10-corpus-replay.log
grep -ci 'PASS\|FAIL' /tmp/qxfx0-phase-10-corpus-replay.log
```

Three possible outcomes; each has a deterministic handling.

#### Outcome A — 25/25 PASS, zero `EssenceRupture` matches

The flag-on path is safe under the integration corpus. Proceed to Step 10.10.3 (observation capture) and Step 10.10.4 (doc sync).

#### Outcome B — 25/25 PASS, but `EssenceRupture` strings appear in passing tests

This means a test **expects** rupture (e.g. a future negative test). Inspect each match:

```bash
grep -nB2 -A5 'EssenceRupture' /tmp/qxfx0-phase-10-corpus-replay.log
```

If every match is inside a test that explicitly asserts the rupture (e.g. `assertBool "rupture expected" …`), Outcome B reduces to Outcome A. **Currently no such test exists**, so any rupture string in a passing run is suspicious — stop and report.

#### Outcome C — One or more integration tests FAIL with `EssenceRupture`

This is **not** a bug to suppress. It is a calibration signal. Do not modify `validatePlan` to make tests pass. Do not catch and ignore the exception. Instead:

1. **Capture the violation**: every `EssenceRupture` payload renders an `EssenceViolation`. Log:
   - The `EssenceMode` that was committed (from the rendered text).
   - The offending field (family / tone / style) and its value.
   - The session id and turn ordinal of the failing turn.

2. **Classify** the cause. Pick exactly one of:

   | Cause | Symptom | Calibration delta |
   |-------|---------|-------------------|
   | **Premature commitment** | `etAngstLevel` crossed `0.75` after just 1–2 divergent turns | Raise `emAngstCommitmentThreshold` to `0.85` or `0.9`. |
   | **Inadmissible style** for a real recovery turn | `ViolationStyleMismatch EssenceContemplative StyleWarm` on a `CMRepair` turn | Relax `admissibleStyles` for the affected mode, or document that `StyleWarm` is admissible under recovery context. |
   | **Wrong mode extraction** | `extractMode` chose `EssenceContemplative` but trajectory was clearly dialogical | Inspect `extractMode` tally; the bug is in the histogram, not the validator. |
   | **Genuine essence/plan conflict** | Real semantic incompatibility caught honestly | The system is acting against its committed essence. This is what the rupture is for — keep it. Document the case as a known limitation; the integration test corpus needs broader CMRepair coverage. |

3. **Apply the calibration delta** in the same session. Re-run Step 10.10.1. Iterate until Outcome A.

4. **Record the iterations** in `progress.txt` (Step 10.10.4) — every delta with rationale. Calibration history is part of the audit trail.

**Hard rule**: if more than three calibration iterations are needed to reach Outcome A, **stop and report**. The validator or modulation defaults are mismatched at a level that requires a human design call, not a tuning pass.

### Step 10.10.3 — Observation capture (Outcome A path)

Even on a green replay, capture *what actually happened* during the run. Integration tests are short (1–3 turns each), so it is plausible that **no commitment fires at all** — `etAngstLevel` reaches at most ~0.05–0.10 before the test ends. This is a valid result. Do not pretend the rupture path was exercised when it was not.

Extract from the log (or from the persisted `replay_trace_json` of the test SQLite DBs, if your harness keeps them):

- Total turns across all 25 integration tests: `T`.
- Turns with `trcEssenceCommitted = true`: `K`. Likely `0` for the current corpus.
- If `K > 0`: mode distribution (contemplative / dialogical / integrative) and trigger distribution (angst_threshold / conatus_erosion).
- Highest `trcEssenceAngstLevel` observed across all turns: `A_max`. Useful as a calibration anchor.

If extraction is non-trivial, simply state: *"Observation capture: no `trcEssenceCommitted = true` rows produced; `A_max` not measured; corpus is too short to exercise commitment."* This is honest and acceptable.

### Step 10.10.4 — Doc sync (Outcome A path only)

Update four artifacts. Use the exact wording below — no improvisation, no extra exclamation, no emojis.

#### `@/home/liskil/my-haskell-project/QxFx0/progress.txt`

Append a new block at the bottom:

```
## Session 2026-05-19 — Phase 10 corpus replay (Step 10.10)

- `QXFX0_ESSENCE_COMMITMENT_ENABLED=1 cabal test qxfx0-test-integration`
  ran with: 25 / 25 PASS, zero `EssenceRupture` events observed in the
  test log.
- Observed commitment dynamics on the integration corpus:
  - Total turns across 25 sessions: <T>.
  - Turns with `trcEssenceCommitted = true`: <K>.
  - Highest `trcEssenceAngstLevel` observed: <A_max>.
  - <If K = 0: "Commitment path is wired but not exercised by the
    current short-session integration corpus.  Longer-session corpus
    replay (manual or scripted, future work) will exercise the commit
    and rupture branches.">
  - <If K > 0: mode and trigger distribution, formatted as a short list.>
- <If iterations > 1: list each calibration delta with rationale.>
- ADR-0012 status flipped to **Accepted (Phase 10, fully landed)**.
- ROADMAP.md and AGENTS.md updated to reflect Phase 10 closure.
- Test status: 582 / 582 PASS unchanged from Step 10.9.
```

Replace `<T>`, `<K>`, `<A_max>` with concrete values or with the honest "not measured" line from Step 10.10.3.

#### `@/home/liskil/my-haskell-project/QxFx0/ROADMAP.md`

Find the long-term item #8 ("Phase 9 — Essence selection infrastructure landed; Phase 10 queued"). Rewrite it to reflect Phase 10 closure:

```
8. ~~**Phase 9 — Essence selection infrastructure**
    (ADR-0012, accepted 2026-05-19).~~ **Landed 2026-05-19.**
    ~~**Phase 10 — Forced commitment and post-commitment guard.**~~
    **Landed 2026-05-19.** `essenceCommitmentEnabled` flag with
    forced commitments (`shouldCommit` → `commit`), post-commitment
    `validatePlan` guard in `Finalize.Commit`, `EssenceRupture`
    exception, sliding-window Conatus erosion, reconcile-time
    courtesy that never widens. Eight regression locks
    (E6, E7a/b, Q7, C1 + 3 unit) in `Test.Suite.SelfEssenceCommit`.
    Default `essenceCommitmentEnabled = False`; flag-flip in
    production deferred to a separate operations ticket once a
    longer-session corpus exists.
    - **Out of scope, deferred to future ADRs**:
      cross-session essence persistence, multiple essences per
      session, external essence summons, essence-aware
      `ConatusWeights`.
```

#### `@/home/liskil/my-haskell-project/QxFx0/AGENTS.md`

Find the line beginning `**Phase 9 (essence selection infrastructure) in progress 2026-05-19**`. Replace the whole bullet with:

```
**Phase 9–10 (essence commitment) landed 2026-05-19**: pure
`QxFx0.Self.Essence` module with `Essence` Σ-type, `witness` /
`shouldCommit` / `extractMode` / `commit` morphisms,
`EssenceModulation` tunables, `validatePlan` post-commitment guard,
trajectory threading through `SystemState` / `TurnInput` /
`PrepareStatic`, four nullable trace fields in `TurnReplayTrace`,
`EssenceRupture` exception in `QxFx0.ExceptionPolicy`,
reconcile-time courtesy via optional predicate to `reconcile`.
Default `essenceCommitmentEnabled = False`; flag-on integration
replay confirms zero spurious ruptures.
```

#### `@/home/liskil/my-haskell-project/QxFx0/docs/adr/0012-essence-commitment.md`

Top-of-file status line: change

```
- **Status**: Accepted (Phase 9, infrastructure only)
```

to

```
- **Status**: Accepted (Phase 9 + 10, fully landed)
```

Append a new closing section before `— end of ADR-0012 —`:

```markdown
## 14. Phase 10 closure note

Phase 10 landed 2026-05-19. Concrete deltas vs. the architecture
described above:

- `essenceCommitmentEnabled :: Bool` is plumbed through
  `PrepareStatic` and `TurnInput` (single-source-of-truth, M6).
  Default `False`.
- `validatePlan :: EssenceCommitment -> Plan -> Either EssenceViolation Plan`
  with admissibility tables exactly as §7.  `CMRepair` and
  `NarrativeNeutral` always admissible (locked by E7a/E7b).
- `shouldCommit` uses true sliding-window semantics over the last
  `emConatusFloorWindow` witnesses (Q7), replacing the Phase-9
  approximation.
- The validator is computed in `Finalize.State` (where `tiEssence`
  and `tpDeliberation` are in scope) and thrown in `Finalize.Commit`
  immediately after `checkBlanketTransition`, before persistence.
- A turn that *causes* commitment is not validated by the new
  commitment (Q5) — the commitment binds future turns only.
- Reconcile-time courtesy: `reconcile` accepts an optional
  `Maybe (Plan -> Bool)` predicate.  When `RuleTiedFallback` fires
  and exactly one tied proposal satisfies the predicate, the fallback
  switches to it.  Never widens (locked by C1).
- Corpus replay under `QXFX0_ESSENCE_COMMITMENT_ENABLED=1` produced
  zero `EssenceRupture` events on the 25-session integration corpus
  on 2026-05-19.

The four §10 out-of-scope items remain so.  The §11 open questions
and §13 Phase-9 resolutions are now historical record.

— end of Phase 10 closure note —
```

## 2. Acceptance criteria

Done when **all** hold:

1. `QXFX0_ESSENCE_COMMITMENT_ENABLED=1 cabal test qxfx0-test-integration` reports **25 / 25 PASS**.
2. `grep -ci 'EssenceRupture' /tmp/qxfx0-phase-10-corpus-replay.log` returns **0** (or only matches inside test names that explicitly assert rupture, of which there are currently none).
3. Default-off `cabal test qxfx0-test` still reports **582 / 582 PASS**, byte-identical to Step 10.9.
4. `progress.txt`, `ROADMAP.md`, `AGENTS.md`, ADR-0012 status updated per Step 10.10.4 wording.
5. ADR-0012 §14 closure note appended.

If acceptance criterion 1 fails: do **not** proceed to docs. Drop into Outcome C handling (§1 Step 10.10.2). Report exact violation, propose calibration delta, ask before re-running.

## 3. Verification commands (copy-paste)

```bash
# 1. Flag-on corpus replay
QXFX0_ESSENCE_COMMITMENT_ENABLED=1 \
  cabal test qxfx0-test-integration --test-show-details=streaming \
  2>&1 | tee /tmp/qxfx0-phase-10-corpus-replay.log

# 2. Rupture grep
grep -ci 'EssenceRupture' /tmp/qxfx0-phase-10-corpus-replay.log

# 3. Default-off regression (must still be 582 / 582)
cabal test qxfx0-test 2>&1 | tail -20

# 4. After doc sync, sanity-check the four artifacts
grep -n 'Phase 10 corpus replay' /home/liskil/my-haskell-project/QxFx0/progress.txt
grep -n 'Landed 2026-05-19' /home/liskil/my-haskell-project/QxFx0/ROADMAP.md
grep -n 'Phase 9–10' /home/liskil/my-haskell-project/QxFx0/AGENTS.md
grep -n 'Accepted (Phase 9 + 10' /home/liskil/my-haskell-project/QxFx0/docs/adr/0012-essence-commitment.md
```

## 4. Hard limits — what NOT to do

- **Do not** modify `validatePlan` admissibility tables to make a failing test pass. If a real test fails, the calibration delta is in `EssenceModulation` defaults or in the test fixture, not in the validator.
- **Do not** wrap the `EssenceRupture` throw in a `try` / `catch` to make tests green. The throw is the contract.
- **Do not** flip the default of `essenceCommitmentEnabled` from `False` to `True` in this ticket. Production flag-flip is a separate operations decision after a longer-session corpus exists.
- **Do not** sync docs if rupture count is non-zero. The doc sync is the *result* of a green replay, not its precursor.
- **Do not** invent observation numbers if `T` / `K` / `A_max` cannot be cleanly measured from the test harness. Use the honest "not measured" wording from §1 Step 10.10.3.

## 5. Out of scope (do not touch in this ticket)

- Test-tightening for `testFlagOffNoBehaviouralChange` and `propStickyCommitment` (both noted as tautological by the spec author). Tracked as a separate follow-up.
- Production flag-flip of `essenceCommitmentEnabled = True`.
- Longer-session corpus generation for richer commitment-path coverage.
- Any work on the four §10 out-of-scope items (cross-session persistence, multiple essences, external summons, essence-aware Conatus weights).

## 6. If something is unclear

| Ambiguity | Resolution |
|-----------|------------|
| The integration test harness does not persist `replay_trace_json` to a queryable place | Fall back to the honest "not measured" wording in §1 Step 10.10.3. Do not rebuild the harness for observation capture in this ticket. |
| One specific integration test fails under flag-on but the failure is environmental (e.g. SQLite path collision under `/tmp`) | Distinguish carefully: a true `EssenceRupture` failure shows the exception in the test output. An environmental failure shows a different cause. Only the former triggers Outcome C. |
| `grep` matches `EssenceRupture` in test names or comments only (not in actual exception output) | Inspect the surrounding lines (`grep -B2 -A5`). If every match is in a test name string, the count is conceptually zero. Document the false positives in the report. |
| Calibration delta would require changing the *type* of `EssenceModulation` (e.g. adding a new field) | **Stop and report.** This exceeds Step 10.10 scope and requires a Phase-10 amendment. |
| Doc sync wording in §1 Step 10.10.4 doesn't fit existing surrounding text in `progress.txt` / `ROADMAP.md` / `AGENTS.md` | Adapt the wording minimally to fit local style, but preserve every concrete fact (test counts, status flip, observation numbers, hard rule about flag default staying `False`). |

— end of Step 10.10 spec —
