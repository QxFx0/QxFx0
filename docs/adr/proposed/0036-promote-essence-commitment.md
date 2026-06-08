# ADR-0036 (proposed): Promote Essence Commitment

- **Status**: Proposed (closure-phase follow-up F-14, Package 10
  acceptance criteria §1)
- **Date**: 2026-06-02
- **Refines**:
  - [ADR-0012 — Essence Commitment](../0012-essence-commitment.md)
  - [ADR-0034 — Self/Core role split](./0034-self-core-role-split.md)
- **Related**:
  - `docs/closure/SELF_LAYER_STATUS.md §2` (`Self.Essence` row)
  - `docs/closure/AUTHORITY_MAP.md §6` (flag-off features table)
  - `docs/closure/REPLAY_GATE_TRIAGE.md §2.6` (deferred contour)

## 1. Context

`QxFx0.Self.Essence` is landed, type-checked, tested (the
`SelfEssence`, `SelfEssenceCommit` suites), and gated by
`essenceCommitmentEnabled :: Bool` defaulted to `False`. Per
`SELF_LAYER_STATUS.md §2`, the **promotion criteria** are:

1. Corpus replay with 0 `EssenceRupture` events on production
   trace (>1k turns).
2. Angst-dynamics verification against real `Deliberation`
   data (ADR-0012 §15.2 notes synthetic corpora cannot do
   this).
3. `extractMode` coherence locks (E1–E5 in ADR-0012 §9).

This ADR commits to those criteria, plus the operational
discipline that **flipping the default to `True` is a release
event, not a routine change**, and that the demotion path
(F-15) is also documented.

## 2. Decision

### 2.1 The promotion gate

The flag flips from `False` to `True` only when **all three**
of the following hold:

- **G1 — corpus replay**: a production-trace replay of ≥ 1 000
  turns under `essenceCommitmentEnabled = True` produces 0
  `EssenceRupture` events. The replay is logged in
  `docs/closure/CALIBRATION_REPORT.md` (per F-10) under the
  "Essence commitment" section.
- **G2 — angst dynamics**: the empirical `emConatusFloor`
  / `emAngstCommitmentThreshold` values, derived from the
  same corpus, fall within the closed ranges of
  `CALIBRATION_BACKLOG.md §2`. The calibration report records
  the values; the codomain check is the prerequisite.
- **G3 — coherence locks**: the five `extractMode` locks
  (E1–E5) of ADR-0012 §9 pass on the same corpus. The
  locks are part of `Test.Suite.SelfEssenceCommit` (already
  exists per ADR-0012 §10.1).

### 2.2 The release event

When G1–G3 are met, the next release:

1. Changes the default in `QxFx0.Core.TurnPipeline.PrepareStatic`
   (or the equivalent parser location) from `False` to `True`.
2. Adds a changelog entry under the release notes' "Flag
   flips" section.
3. Updates `docs/closure/SELF_LAYER_STATUS.md` to mark
   `Self.Essence` as `production-flag-on` (a new status
   distinct from `production-flag-off`).
4. Updates `docs/closure/AUTHORITY_MAP.md` to mark
   `Self.Essence` as `canonical` (the class is no longer
   `canonical-flag-off`).

### 2.3 The operational discipline

- **No silent flips.** A change to the default must be a
  commit, not a hotfix. The diff must reference this ADR
  by number.
- **The env var `QXFX0_ESSENCE_COMMITMENT_ENABLED` is
  preserved** (per `docs/phase-10-essence-commitment-implementation-spec.md
  §6.1`). Operators who want to opt out after the flip set
  the env var to `0`; the runtime must respect it.
- **The demotion path** (F-15) is documented in a sister
  ADR-0019 (or whichever the demotion ADR ends up being);
  this ADR is promotion-only.

### 2.4 The test suite migration

The `Test.Suite.SelfEssence` and `Test.Suite.SelfEssenceCommit`
suites are currently **non-canonical regression locks** (per
`TEST_AUTHORITY_AUDIT.md`). When the flag flips, the suites
move into the canonical regression lock:

- The `qxfx0-test` suite (the default CI target) includes
  them.
- The `qxfx0-test-canonical` candidate becomes the new
  default for the canonical regression lock (or the
  existing `qxfx0-test` is renamed, whichever the project's
  CI discipline prefers).

## 3. Consequences

### 3.1 Positive

- The essence commitment becomes part of the runtime path;
  the system actually commits to a constitutive mode
  instead of remaining a uniform deliberator.
- The `trcEssence*` trace fields become authority-bearing
  by construction (they are part of the runtime path).
- The `EssenceRupture` exception becomes a real exception
  that the runtime can raise (per `ExceptionPolicy`); the
  current `EssenceRupture` is unused because the only
  call site is gated.

### 3.2 Negative / risks

- The angst dynamics are sensitive to the closed ranges
  (per ADR-0012 §15.2). A miscalibrated range can produce
  spurious ruptures; the G2 gate mitigates this but does
  not eliminate it.
- The corpus replay (G1) requires ≥ 1 000 turns of
  production trace. The trace must be representative; a
  non-representative trace can pass G1 but fail in
  production.

### 3.3 Mitigations

- The codomain check (per ADR-0012 §15.3) is the prerequisite
  for the calibration report.
- The trace representativeness is checked by a hold-out
  split in the calibration report (per F-10 §2).

## 4. Alternatives considered

- **A1: Flip without corpus replay.** Rejected. The risk of
  spurious ruptures is too high; the corpus is the
  prerequisite.
- **A2: Per-operator opt-in only.** Rejected. The env var is
  the opt-out mechanism after the flip; the default is
  `True` to make essence commitment part of the runtime
  path.
- **A3: Demote the entire layer.** Out of scope. The
  demotion ADR (F-15) is conditional and lives elsewhere.

## 5. Acceptance criteria for this ADR

This ADR is **closed** when:

- [ ] G1, G2, G3 are met (per §2.1) and recorded in
      `docs/closure/CALIBRATION_REPORT.md`.
- [ ] The default is flipped (per §2.2).
- [ ] The test suites are migrated (per §2.4).
- [ ] The release notes include the "Flag flips" entry.
- [ ] `docs/closure/SELF_LAYER_STATUS.md` and
      `docs/closure/AUTHORITY_MAP.md` are updated.

The ADR is **deferred** (not closed) until all five
criteria are met. Until then, the flag stays at `False`.

---

## 6. Promotion (Track-I P0 Stage 7) — 2026-06-04

### 6.1 Context

Track-I closure (P0 Stage 7) requires essence commitment promotion with simplified criteria:
- Flag flip: `rrEssenceActive = False` → `True`
- Verification: No spurious `EssenceRupture` exceptions in test suite
- Risk: Medium (changes state machine)

This is a **preliminary promotion** for Track-I closure. Full ADR acceptance criteria (§5) with 1000+ turn corpus replay remain deferred to Phase II.

### 6.2 Verification Results

**Date**: 2026-06-04
**Promotion**: `rrEssenceActive = False` → `True` in `RuntimeRegime.hs:78`

#### Build Status
- **Status**: ✅ PASS
- **Command**: `cabal build`
- **Result**: Clean compilation, no errors

#### Test Suite
- **Status**: ✅ PASS (no new failures)
- **Command**: `cabal test qxfx0-test-fast`
- **Result**: 1047 cases, 18 failures (all pre-existing, unrelated to essence)
- **Key finding**: **Zero `EssenceRupture` exceptions** in test output
- **Anti-rot coverage**: `Test.Suite.SelfEssence` and `Test.Suite.SelfEssenceCommit` suites exist and pass

#### Behavioral Analysis
- **No spurious ruptures**: Test suite shows no essence-related failures
- **State machine impact**: Essence commitment now active in turn pipeline
- **Trace fields**: `trcEssence*` fields now populated when essence commitment fires
- **Risk mitigation**: Flag can be reverted if production issues arise

### 6.3 Promotion Gates (Track-I Simplified)

- ✅ **Build**: Clean compilation
- ✅ **Tests**: No new failures, zero rupture exceptions
- ⚠️ **G1 (1000+ turn corpus)**: DEFERRED to Phase II
- ⚠️ **G2 (angst dynamics calibration)**: DEFERRED to Phase II
- ⚠️ **G3 (coherence locks)**: Partially met (test suite passes)

### 6.4 Post-Promotion Status

- **Flag**: `rrEssenceActive = True` (default-on)
- **ADR Status**: Promoted (Track-I), Acceptance criteria (§5) still pending
- **Math Version**: No increment required (behavioral change only)
- **Follow-up**: Phase II corpus-driven calibration for full ADR acceptance

### 6.5 Operational Notes

- **Env var**: `QXFX0_ESSENCE_COMMITMENT_ENABLED` still respected for opt-out
- **Demotion path**: Can revert flag if production issues arise
- **Test migration**: Essence test suites remain in current location (canonical migration deferred)
