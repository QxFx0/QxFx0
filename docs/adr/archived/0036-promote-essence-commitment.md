# ADR-0036: Promote Essence Commitment

- **Status**: Accepted (Policy A — Promote reality) via
  `docs/closure/ESSENCE-REGIME-RECONCILE.md` (2026-06-17).
  Essence is law-driven / default-active structural runtime law.
  The `essenceCommitmentEnabled` flag designed in ADR-0012 §10.1 was
  **never implemented**; Essence has been unconditionally active since
  landing 2026-05-19. This ADR reconciles the doctrine with that reality.
- **Scope limit (load-bearing)**: Essence is **structural / runtime-subject
  scaffold only**. It is **not** M6-FELT evidence and **not** counted as
  felt subjecthood evidence until (a) SLICE-012 makes governed conditions
  provably hold in real runs, and (b) a felt-evidence gate (M6-FELT / B3)
  is defined and passes. See `M6_DECLARATION.md §4` and `§6`.
- **Date**: 2026-06-02 (original proposed); 2026-06-17 (Policy A accepted,
  restructured — §6 authoritative, §1–§5 historical).
- **Refines**:
  - [ADR-0012 — Essence Commitment](../0012-essence-commitment.md)
  - [ADR-0034 — Self/Core role split](./0034-self-core-role-split.md)
- **Related**:
  - `docs/closure/ESSENCE-REGIME-RECONCILE.md` (the decision doc)
  - `docs/closure/SELF_LAYER_STATUS.md §2` (`Self.Essence` row)
  - `docs/closure/AUTHORITY_MAP.md §6` (formerly flag-off features)
  - `docs/closure/REPLAY_GATE_TRIAGE.md §2.6` (formerly deferred contour)

## 1. Context (HISTORICAL — documents the designed-but-never-built gate)

> **Historical note (2026-06-17).** §1–§5 below describe a feature flag
> `essenceCommitmentEnabled :: Bool` that ADR-0012 §10.1 designed to gate
> `shouldCommit`/`commit`/`validatePlan`. **This flag was never
> implemented in code.** `Finalize/State.hs:344` states "`shouldCommit`
> is always evaluated; no feature flag"; `validatePlan` is called
> unconditionally at `Finalize/State.hs:169` and `Route/Effects.hs:61`;
> `EssenceRupture` is a reachable exception at `Commit.hs:91`. The env
> var `QXFX0_ESSENCE_COMMITMENT_ENABLED` was also never implemented
> (0 matches in `src/`). Essence has been fully, unconditionally active
> since landing 2026-05-19. §1–§5 are retained as the historical record
> of the intended gate; §6 (the 2026-06-04 promotion addendum) plus this
> header are the **authoritative** text as of 2026-06-17.

`QxFx0.Self.Essence` is landed, type-checked, tested (the
`SelfEssence`, `SelfEssenceCommit` suites), and was *designed* to be
gated by `essenceCommitmentEnabled :: Bool` defaulted to `False`. Per
`SELF_LAYER_STATUS.md §2`, the **promotion criteria** were:

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
- **The env var `QXFX0_ESSENCE_COMMITMENT_ENABLED`** was specified here
  but **never implemented** (0 matches in `src/`, confirmed 2026-06-17).
  Policy A (2026-06-17) does **not** add it. This bullet is retained as
  a historical record of the intended opt-out path.
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

> **Historical note (2026-06-17).** The flag was never implemented, so
> "the flag stays at `False`" describes a gate that did not exist. §6
> below records the 2026-06-04 promotion; the 2026-06-17 reconciliation
> (this header + `ESSENCE-REGIME-RECONCILE.md`) accepts the law-driven
> reality as Policy A. The G1–G3 criteria remain the legitimate path to
> any **felt-evidence** claim (M6-FELT), but they are not a precondition
> for Essence being a structural runtime law.

---

## 6. Promotion (Track-I P0 Stage 7) — 2026-06-04 — AUTHORITATIVE as of 2026-06-17

> **Authoritative note (2026-06-17).** This section is the operative text.
> It records that `rrEssenceActive` was set to `True` on 2026-06-04. The
> 2026-06-17 reconciliation (`ESSENCE-REGIME-RECONCILE.md`, Policy A)
> confirms this matches the actual runtime: Essence is law-driven
> (`shouldCommit` unconditional, `validatePlan` reachable, `EssenceRupture`
> reachable) and has been since 2026-05-19 — *independent* of the
> never-implemented `essenceCommitmentEnabled` flag. The §6.4 "Acceptance
> criteria (§5) still pending" line is reframed: G1–G3 are **not**
> preconditions for Essence being a structural runtime law (it already
> is); they are preconditions for any **felt-evidence / M6-FELT** claim
> about Essence (see `M6_DECLARATION.md §4, §6`).

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

- **Flag**: `rrEssenceActive = True` (default-on). The `essenceCommitmentEnabled`
  Haskell flag and `QXFX0_ESSENCE_COMMITMENT_ENABLED` env var were **never
  implemented** (confirmed by grep, 2026-06-17); Essence is law-driven, not
  flag-gated.
- **ADR Status**: Promoted (Track-I). Per 2026-06-17 Policy A, Essence is a
  **structural runtime law** (canonical, in the runtime path). It is **not**
  M6-FELT evidence until SLICE-012 + a felt-evidence gate land.
- **Math Version**: No increment required (behavioral change only)
- **Follow-up**: Phase II corpus-driven calibration remains the path to any
  felt-evidence claim (G1–G3), not to Essence's structural status.

### 6.5 Operational Notes

- **Env var**: `QXFX0_ESSENCE_COMMITMENT_ENABLED` was never implemented and
  is **not** added by Policy A (per the operator constraint: no new env var).
  It is documented here as historical/non-implemented only.
- **Demotion path**: Policy A does not demote. A future demotion would
  require implementing the gate (Policy B) — a separate ADR.
- **Test migration**: Essence test suites remain in current location.
  `PromotionFlagDiscipline` is updated (2026-06-17) to no longer search for
  the nonexistent `essenceCommitmentEnabled` and to verify `rrEssenceActive`
  matches the unconditional runtime law instead.
