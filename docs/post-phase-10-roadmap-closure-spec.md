# Post-Phase-10 Roadmap Closure
## Implementation Specification for KIMI

- **Predecessors landed**: [`Phase 9`](./phase-9-essence-implementation-spec.md), [`Phase 10`](./phase-10-essence-commitment-implementation-spec.md), [`Step 10.10`](./phase-10-step-10-corpus-replay-spec.md). Tree at HEAD: 582/582 PASS, ADR-0012 = *Accepted (Phase 9 + 10, fully landed)*.
- **Status of this spec**: Normative for execution-class sections. Design-triage sections require explicit user sign-off before any code changes follow.
- **Date**: 2026-05-19.
- **Scope**: closure of six follow-up items enumerated by the spec author in the post-Phase-10 review. Each item lives in its own section with a clear "KIMI can execute / KIMI must triage and ask" boundary.

## 0. Master index, execution order, hard rules

Six numbered sections, in dependency-aware execution order. The order is **prescriptive**: do not start a later section before the earlier one is green unless the section is explicitly marked independent.

| § | Item | Class | Depends on | Approx. effort |
|---|------|-------|------------|----------------|
| 1 | Test-tightening of two tautological essence tests | Execution | none | S |
| 6.7 | Runtime override of `FieldHeuristics` (ROADMAP long-term #7) | Execution | none | S–M |
| 6.4 | Release artifact reproducibility (ROADMAP long-term #4) | Execution | none | M |
| 6.5 | Broader interop documentation (ROADMAP long-term #5) | Documentation | none | M |
| 3 | Longer-session corpus harness | Execution | none | M–L |
| 4 | Calibration addendum to ADR-0012 | Empirical | §3 | M |
| 2 | Production flag-flip decision support | Operations | §4 | S (doc only) |
| 6.6 | Effects-interpreter conatus-aware prior (ROADMAP long-term #6) | Execution | none, but heavy | L |
| 5 | Four future-ADR triage stubs | Design | none | M (triage only) |
| 6.3 | Domain-specific reasoning packs (ROADMAP long-term #3) | Research | none | XL (defer) |

ROADMAP long-term **#1 (Phase 7)** and **#2 (Phase 8 Package D)** are already landed — do not re-execute.

**Hard rules across all sections.**

- One section per session. Do not bundle two sections into one commit unless explicitly authorised.
- Test count never goes down. Tightening that *replaces* a tautological test must keep the suite count the same or increase it.
- Design-triage sections (§5, §6.3) produce **triage stubs in `docs/adr/proposed/`**, not new ADRs. Full ADRs require a separate design conversation with the user.
- Operations sections (§2) produce **documentation and scripts**, not the actual flag-flip. The flip itself is the user's call.
- Any section may be aborted mid-execution if KIMI discovers that the spec is wrong; abort cleanly, report findings, do not improvise.

## 1. Test-tightening (essence regression)

Two tests in `@/home/liskil/my-haskell-project/QxFx0/test/Test/Suite/SelfEssenceCommit.hs` are tautological as written. Tighten both without changing the suite count (8 → 8).

### 1.1 `propStickyCommitment`

Current (lines 272-284) builds `EssenceCommitted traj' commitment` directly and pattern-matches on it. The constructor is the assertion. Replace with a property that runs **N continuations** through the actual `witness` morphism and verifies the commitment remains invariant:

```haskell
propStickyCommitment :: Property
propStickyCommitment =
  forAll arbitraryEssenceCommitment $ \commitment ->
  forAll arbitraryEssenceTrajectory $ \trajBase ->
  forAll (choose (1, 20))             $ \n ->
  forAll (vectorOf n arbitraryStepInput) $ \steps ->
    let initial = EssenceCommitted trajBase commitment
        step e (ord, (ce, fd, delib)) =
          case e of
            EssenceCommitted t c ->
              EssenceCommitted
                (witness defaultEssenceModulation ord ce fd delib t)
                c
            EssenceUncommitted _ -> e  -- unreachable from this seed
        final = foldl' step initial (zip [1..] steps)
    in case final of
         EssenceCommitted _ c' -> c' === commitment
         EssenceUncommitted _  -> counterexample "commitment lost" False
  where
    arbitraryStepInput =
      (,,) <$> arbitraryConatusEnergy <*> arbitraryField <*> arbitraryDeliberation
```

Notes:

- `arbitraryDeliberation` does not yet exist — add a generator that produces an arbitrary `Deliberation` (any `dtRule`, any `dtAgreement`, any `dtDivergence` in `[0, 1]`). Reuse `defaultDeliberation` as a base, override the trace.
- Use `===` from `Test.QuickCheck` for diagnostic counterexamples.
- N ∈ [1, 20] is enough to exercise the ring-buffer trim path of `witness`.

### 1.2 `testFlagOffNoBehaviouralChange`

Current (lines 357-372) simulates what `buildNextSystemState` does instead of invoking it. Replace with an actual `buildNextSystemState` call.

KIMI must first read `@/home/liskil/my-haskell-project/QxFx0/test/Test/Suite/TurnPipelineProtocol.hs` (or wherever the integration suite builds `SystemState` / `TurnInput` / `TurnPlan` / `TurnArtifacts` fixtures) to find a reusable fixture builder. If a clean reusable builder exists, use it. If not:

- **Option A**: extract a minimal `makePhase10TestFixture :: TurnInput -> ... -> (SystemState, TurnInput, TurnSignals, TurnPlan, TurnArtifacts, DreamState, MeaningGraph)` helper into `@/home/liskil/my-haskell-project/QxFx0/test/Test/Fixtures/Phase10.hs` (new module). Use it from `testFlagOffNoBehaviouralChange`.
- **Option B**: if the existing test fixtures are too coupled to extract cleanly without a full refactor, KIMI stops and reports. Leave the current tautological test in place but rename it to `testFlagOffEssenceUncommittedShape` to honestly reflect what it asserts. Add a TODO comment pointing to this spec.

Acceptance: 8 tests still, but at least one of the two no longer tautological. Property test still passes 200 maxSuccess.

### 1.3 Verification

```bash
cabal test qxfx0-test --test-show-details=streaming
# 582 / 582 PASS unchanged.
cabal test qxfx0-test-property
# Includes the strengthened propStickyCommitment.
```

## 2. Production flag-flip decision support (operations)

KIMI cannot flip `essenceCommitmentEnabled = True` in production. KIMI **can** produce the artifact that the operator needs to make that decision.

### 2.1 Output

Create `@/home/liskil/my-haskell-project/QxFx0/docs/operations/phase-10-flag-flip-checklist.md`. Structure:

```markdown
# Phase 10 Flag-Flip Operations Checklist

## Preconditions (all must hold before flip)

1. Calibration addendum (ADR-0012 §15) merged.
2. Long-session corpus replay (see §3 of post-phase-10 spec) executed
   with `QXFX0_ESSENCE_COMMITMENT_ENABLED=1` on at least N sessions
   each ≥ 15 turns, producing zero `EssenceRupture` events and at
   least one `EssenceCommitted` row in the trace.
3. `defaultEssenceModulation` calibrated against observed dynamics
   from the long corpus (not the consvervative defaults from Phase 9).
4. Operator has validated that the calibrated `EssenceModulation`
   defaults still pass `Test.Suite.SelfEssence` and
   `Test.Suite.SelfEssenceCommit`.

## Procedure

1. Locate the env-var parser (file and line — KIMI: find via
   grep `QXFX0_ESSENCE_COMMITMENT_ENABLED`).
2. Change the default from `False` to `True` in the parser.
3. Bump version in `qxfx0.cabal`.
4. Update `CHANGELOG.md` with a release note.
5. Run `scripts/verify.sh` and `scripts/release-smoke.sh`.
6. Tag release.
7. Roll out.

## Rollback procedure

If post-flip production traces show unexpected `EssenceRupture`
events, the operator can roll back by:

1. Setting `QXFX0_ESSENCE_COMMITMENT_ENABLED=0` in the runtime env.
2. Re-deploying the previous tag.
3. Filing an incident report referencing the rupture trace and the
   committed `EssenceMode` that the plan violated.

## Telemetry to watch post-flip

- Count of `trcEssenceCommitted = true` per session.
- Mode distribution (`trcEssenceMode`).
- Trigger distribution (`trcEssenceTrigger`).
- Any `EssenceRupture` events in the application log.
```

KIMI fills in the concrete file/line locations by `grep_search`. Does NOT execute the flip.

### 2.2 Acceptance

File exists, file references real grep-verifiable locations in the codebase, no code changes.

## 3. Longer-session corpus harness

Current integration corpus has 25 sessions × 1-3 turns each, which never reaches `emAngstCommitmentThreshold = 0.75`. To exercise the commitment + rupture paths under realistic load, we need longer sessions with sustained divergence.

### 3.1 Two execution paths, choose one

**Option A — Synthetic long-session fixtures.** Hand-craft a small set (3-5) of synthetic 15-25 turn sessions designed to provoke commitment. Each session is a JSONL file of `InputPropositionFrame` records replayed through `runTurnInSession` in a new integration test.

**Option B — Historical corpus replay.** If a corpus of historical traces exists somewhere on disk, build a replay harness that consumes them. KIMI checks `@/home/liskil/my-haskell-project/QxFx0/data/` and any `corpus/` / `fixtures/` directory; if no historical corpus is present, Option A is the only path.

KIMI executes Option A unless the user explicitly directs otherwise.

### 3.2 Synthetic session structure

Create `@/home/liskil/my-haskell-project/QxFx0/test/fixtures/long-sessions/` with:

- `dialogical-commitment.jsonl` — 15-20 turns of sustained dialogical divergence (RuleHolisticAdvantage with high divergence), designed to reach the angst threshold around turn 12-15 and commit to `EssenceDialogical`.
- `contemplative-commitment.jsonl` — same pattern but with formal-side advantage (RuleFormalAdvantage), committing to `EssenceContemplative` around turn 12-15.
- `integrative-no-commitment.jsonl` — 20+ turns of agreement (RuleAgreement, divergence 0); angst stays at 0; no commitment fires. Lock for "calm dialogue never spuriously commits".
- `conatus-erosion.jsonl` — 10+ turns with sustained sub-floor `ConatusEnergy` (≤ 0.4); trigger should be `TriggerConatusErosion`, not angst.
- `mixed-divergence.jsonl` — natural mix; commitment may or may not fire. Lock for "no rupture under realistic mixed dynamics".

Each fixture is a JSONL file where each line is one human input. The harness replays the fixture through `runTurnInSession`, captures the per-turn `trcEssence*` fields, and asserts:

- No `EssenceRupture` thrown.
- For the four named fixtures: expected commitment outcome (mode, trigger) matches.
- For the `mixed-divergence` fixture: passes silently.

### 3.3 Test integration

New suite: `@/home/liskil/my-haskell-project/QxFx0/test/Test/Suite/LongSessionCorpus.hs`. Five tests (one per fixture). Wired into:

- `qxfx0-test-integration` (primary).
- `qxfx0-test` (meta).
- **Not** in `fast` / `unit` / `property` (these are long-running).

Test count target: 582 + 5 = **587 / 587 PASS**.

### 3.4 Acceptance

```bash
QXFX0_ESSENCE_COMMITMENT_ENABLED=1 \
  cabal test qxfx0-test-integration --test-show-details=streaming \
  2>&1 | tee /tmp/qxfx0-long-corpus.log

grep -ci 'EssenceRupture' /tmp/qxfx0-long-corpus.log
# Expected: 0

grep -ci 'EssenceCommitted' /tmp/qxfx0-long-corpus.log
# Expected: > 0 (at least the four named fixtures produced commitment)
```

Acceptance: 30/30 PASS in integration (25 existing + 5 new), zero ruptures, at least four commitment events observed.

### 3.5 Hard rule

If the synthetic fixtures cannot reach the angst threshold within 25 turns under `defaultEssenceModulation`, **do not** tune the modulation defaults in this section. Note the observation, leave the fixture failing, escalate to §4 (calibration is the right place to address this).

## 4. Calibration addendum to ADR-0012

**Status: partially completed** (2026-05-19).

- `emConatusStructuralFloor`: corrected from unit-mismatch (0.5 → 7.0).
- Angst-side parameters: deferred — upstream deliberation-pipeline blockage
  prevents synthetic JSONL fixtures from producing observable angst dynamics.
- See `docs/calibration/phase-10-corpus-observations.md` and ADR-0012 §15.

Depends on §3 producing observable angst / Conatus-floor dynamics.

### 4.1 Empirical analysis

Run §3.4 with extended logging (KIMI may add temporary `hPutStrLn` calls or use the existing trace JSON). Extract:

- `etAngstLevel` distribution across all turns of all long-session fixtures: min, median, p75, p95, max.
- `etConatusFloor` distribution: same statistics.
- Turn ordinal of first `EssenceCommitted = true` per session.
- Histogram of `ewConatusScalar` from `etWitnesses` across the corpus.

Record raw numbers (CSV or markdown table) in `@/home/liskil/my-haskell-project/QxFx0/docs/calibration/phase-10-corpus-observations.md`.

### 4.2 Recalibration

Compare observed numbers against the current `defaultEssenceModulation` values:

```haskell
emAngstCommitmentThreshold    = 0.75
emAngstAccrualRate            = 0.05
emAngstDecayRate              = 0.02
emAngstAccrualDivergenceFloor = 0.5
emConatusFloorWindow          = 8
emConatusStructuralFloor      = 0.5
emTrajectoryCapacity          = 32
```

Adjust each parameter by *at most one factor of 2* per iteration. Conservative bias toward "harder to commit, easier to decay" — false-positive ruptures are worse than missed commitments.

### 4.3 ADR-0012 §15

Append a new section to `@/home/liskil/my-haskell-project/QxFx0/docs/adr/0012-essence-commitment.md` immediately before `— end of ADR-0012 —`:

```markdown
## 15. Phase 10 calibration addendum (post-corpus)

After the long-session corpus harness from
`docs/post-phase-10-roadmap-closure-spec.md` §3 ran with
`QXFX0_ESSENCE_COMMITMENT_ENABLED=1`, observed dynamics on the
synthetic long-session corpus were:

| Parameter | Observed | Phase 9 default | Recommended |
|-----------|----------|-----------------|-------------|
| Median `etAngstLevel` at turn 15 | <observed> | n/a | n/a |
| First commit turn ordinal (mean) | <observed> | n/a | n/a |
| Sub-floor `ewConatusScalar` rate | <observed> | n/a | n/a |
| `emAngstCommitmentThreshold` | n/a | 0.75 | <recommended> |
| `emAngstAccrualRate`         | n/a | 0.05 | <recommended> |
| `emAngstDecayRate`           | n/a | 0.02 | <recommended> |
| `emConatusFloorWindow`       | n/a | 8    | <recommended> |
| `emConatusStructuralFloor`   | n/a | 0.5  | <recommended> |

The recommended values are conservative: any deviation from the
Phase 9 defaults biases toward harder commitment and faster decay.
The calibration was applied to `defaultEssenceModulation` in
`QxFx0.Self.Essence` on <date>; previous defaults remain accessible
as a constant `phase9EssenceModulation` for regression testing.
```

### 4.4 Code change

Update `@/home/liskil/my-haskell-project/QxFx0/src/QxFx0/Self/Essence.hs`:

- Add a new constant `phase9EssenceModulation :: EssenceModulation` with the original Phase 9 defaults, exported. Used by regression tests that want to lock against the original behaviour.
- Update `defaultEssenceModulation` with the recommended calibrated values.
- Update Haddock to note the calibration history.

### 4.5 Acceptance

- ADR-0012 §15 appended with concrete numbers (no placeholders).
- `defaultEssenceModulation` updated; `phase9EssenceModulation` exported.
- All existing tests still pass: 587/587 (after §3).
- `Test.Suite.SelfEssence` and `Test.Suite.SelfEssenceCommit` audited to ensure they don't accidentally lock against the *old* defaults; any that do are split into two: one against `phase9EssenceModulation`, one against `defaultEssenceModulation`.

## 5. Future-ADR triage (four stubs)

The four out-of-scope items from ADR-0012 §10 each need their own ADR before any code change. KIMI **does not** write the ADRs — those require human design conversation. KIMI **does** write triage stubs that frame the question.

Output directory: `@/home/liskil/my-haskell-project/QxFx0/docs/adr/proposed/`. Create the directory if it does not exist.

### 5.1 Stub template (use for all four)

```markdown
# ADR-XXXX (proposed): <Title>

- **Status**: Proposed (triage stub, not yet a full ADR)
- **Date**: <date>
- **Refines**:
  - [ADR-0012 — Essence Commitment](../0012-essence-commitment.md)

## 1. Problem statement

<1-2 paragraphs framing the question. What is the gap in the
current architecture that this proposed ADR would close?>

## 2. Current architecture (what would change)

<Concrete enumeration of files/modules/types that this proposal
would touch. KIMI: use grep_search to find real names.>

## 3. Open design questions

<List of N questions that must be answered before a full ADR can
be written. Each question explicit and answerable.>

## 4. Estimated complexity

<S / M / L / XL with one-paragraph justification.>

## 5. Why this is not in scope yet

<What downstream system or research question must mature first.>

— end of proposed ADR-XXXX —
```

### 5.2 Four stubs to write

| Topic | Filename | Estimated complexity |
|-------|----------|----------------------|
| Cross-session essence persistence | `0013-cross-session-essence-persistence.md` | L |
| Multiple essences per session | `0014-multiple-essences-per-session.md` | XL (dissociation vs. selfhood is a philosophical question with engineering consequences) |
| External essence summons | `0015-external-essence-summons.md` | M (operator override as third `CommitmentTrigger`) |
| Essence-aware `ConatusWeights` | `0016-essence-aware-conatus-weights.md` | M (tuning `ConatusWeights` under committed `EssenceMode`) |

For each, fill the stub template with:

- **Problem statement**: 1-2 paragraphs grounded in ADR-0012 §10.
- **Current architecture**: 3-5 bullets pointing at concrete code locations (e.g. `tiEssence` plumbing for #0013, `Essence` Σ-type for #0014, `CommitmentTrigger` for #0015, `ConatusWeights` for #0016).
- **Open design questions**: 4-8 numbered questions per stub.
- **Estimated complexity**: as in the table.
- **Why not in scope yet**: each stub must explain the prerequisite — usually "Phase 10 must be production-validated first" or "requires runtime layer change beyond `Self.*`".

### 5.3 Acceptance

Four files in `docs/adr/proposed/`, each ≤ 200 lines, each grounded in real code references. **No code changes**.

## 6. Long-term roadmap items #3-7

ROADMAP `Long term` #1 (Phase 7) and #2 (Phase 8 Package D) are already landed — skip. The remaining five are listed in execution order (easiest first).

### 6.7 Runtime override of `FieldHeuristics` (ROADMAP #7)

Wire `FieldHeuristics` through `PrepareStatic` → `TurnInput` so env-var or config-file can override `defaultFieldHeuristics`.

**Concrete steps:**

1. Add `psFieldHeuristics :: !FieldHeuristics` to `PrepareStatic`.
2. Add `tiFieldHeuristics :: !FieldHeuristics` to `TurnInput`.
3. In `buildPrepareEffectPlan`, source `psFieldHeuristics` from an env-var-parsed config (default = `defaultFieldHeuristics`). Mirror the existing `familyDivergenceEnabled` / `essenceCommitmentEnabled` parsing pattern.
4. In `buildTurnInput`, copy `tiFieldHeuristics = psFieldHeuristics`.
5. Replace direct references to `defaultFieldHeuristics` in the turn pipeline with `tiFieldHeuristics`.
6. Add one unit test in `Test.Suite.SelfField`: under override, the heuristics are honored.

Acceptance: 588/588 PASS (after §3 added 5).

### 6.4 Release artifact reproducibility (ROADMAP #4)

**Concrete steps:**

1. Audit `scripts/verify.sh` and `scripts/release-smoke.sh` for nondeterminism sources (timestamps, random seeds, parallel build ordering, etc.).
2. Document findings in `@/home/liskil/my-haskell-project/QxFx0/docs/operations/release-reproducibility.md`.
3. For each nondeterminism source, propose a fix (e.g. `SOURCE_DATE_EPOCH`, fixed `-jN`, deterministic test ordering via `Test.Tasty`).
4. Implement fixes that are local to the scripts (do not touch library code).
5. Verify by running `scripts/verify.sh` twice from clean and diffing output byte-by-byte.

Acceptance: documented audit + 2 reproducible runs.

### 6.5 Broader interop documentation (ROADMAP #5)

**Concrete steps:**

1. Create `@/home/liskil/my-haskell-project/QxFx0/docs/interop/README.md`.
2. Document the trace JSON schema (currently scattered across multiple modules).
3. Document the SQLite persistence schema with column-level semantics.
4. Document the env-var contract (all `QXFX0_*` variables with type, default, meaning).
5. Document the env-var contract one ADR at a time would be ideal; for this ticket, one consolidated reference is sufficient.

Acceptance: README.md present, four sub-docs linked, no code changes.

### 6.6 Effects-interpreter conatus-aware prior (ROADMAP #6, ADR-0007 §4.3)

Large concrete arch change. **KIMI writes an implementation spec** (like Phase 9 / Phase 10), does not execute.

**Output**: `@/home/liskil/my-haskell-project/QxFx0/docs/effects-conatus-prior-implementation-spec.md`. Structure mirrors Phase 9 / Phase 10 specs: §0 decisions, §1 step-by-step plan, §2 touchpoints, §3 acceptance, §4 verification commands, §5 out of scope.

KIMI consults ADR-0007 §4.3 for the architecture intent. The spec must:

- Enumerate every `TurnEffectRequest` constructor.
- Propose a `ConatusPrior` data type that scores each effect request by conatus-weighted urgency.
- Propose how the `PipelineIO` interpreter consumes the prior to schedule effects.
- Propose the regression locks (probably 3-5 property tests over scheduling determinism).
- Estimate the +N tests delta.

**No code change** in this ticket. Only the spec. Acceptance: spec present, ≥ 300 lines, references real types from `@/home/liskil/my-haskell-project/QxFx0/src/QxFx0/Core/TurnPipeline/Effects.hs`.

### 6.3 Domain-specific reasoning packs (ROADMAP #3)

Research-scale. **KIMI writes only a triage stub** (like §5).

Output: `@/home/liskil/my-haskell-project/QxFx0/docs/adr/proposed/0017-domain-reasoning-packs.md`. Same template as §5.1.

Open questions to include:

- What is the contract between the core runtime and a domain pack?
- How does a pack express its uncertainty boundaries to `validatePlan` / safety guards?
- Are packs hot-pluggable or compile-time?
- How does pack composition interact with `Essence` commitment?
- What is the calibration story for pack-specific Conatus weights?

Estimated complexity: **XL**. Why not in scope yet: "Phase 11+ — requires domain-expert collaboration, labelled corpus per domain, and explicit safety review process; not engineering-feasible to spec without those prerequisites."

## 7. Cross-cutting acceptance

Done with the entire post-Phase-10 closure roadmap when **all** hold:

- §1 tightened tests, 8/8 in `SelfEssenceCommit`, ≤1 tautology remaining (with rename).
- §6.7 `FieldHeuristics` overridable; test added.
- §6.4 release reproducibility audited and (where applicable) fixed.
- §6.5 interop README present.
- §3 long-session corpus harness present; 30/30 integration PASS under flag-on.
- §4 ADR-0012 §15 appended with concrete calibrated numbers; `defaultEssenceModulation` updated; `phase9EssenceModulation` exported.
- §2 flag-flip checklist present in `docs/operations/`.
- §6.6 Effects prior implementation spec present.
- §5 four future-ADR stubs present in `docs/adr/proposed/`.
- §6.3 domain-packs stub present in `docs/adr/proposed/`.

Test count target by end of full closure: **588 / 588 PASS** (582 from Phase 10 + 5 from §3 long-session corpus + 1 from §6.7 FieldHeuristics override).

If any section produces unexpected failures, **stop and report** before continuing to the next section.

## 8. Reporting cadence

After each section completes (one per session), KIMI produces a one-paragraph summary:

- What was done (concrete file list).
- What tests landed / changed.
- Current aggregate test count.
- What's next per this spec's execution order.

The user reviews and either green-lights the next section or pauses.

— end of post-Phase-10 closure spec —
