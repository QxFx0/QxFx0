# Release Checklist (QxFx0_v3)

- **Status**: Active (operational discipline, post-closure)
- **Date**: 2026-06-02
- **Audience**: anyone cutting a release
- **Related**:
  - `docs/closure/PROMOTION_PLAYBOOK.md` (sister doc;
    the promotion counterpart)
  - `docs/closure/CALIBRATION_REPORT.md` (the calibration
    record that goes with every release)
  - `docs/closure/ENFORCEMENT_MATRIX.md` (the CI gates)

## 0. What this checklist is

The release event combines **four** kinds of work:

1. **Architecture check** — `check_architecture.sh`
   must be green.
2. **Calibration check** — `check_calibration_codomain.sh`
   must be green; the calibration report
   (`CALIBRATION_REPORT.md`) must be filled.
3. **Replay gate** — `check_replay_gate.sh` must be
   green; the property tests in `qxfx0-test` must pass.
4. **Promotion / demotion** — any flag flips per
   `PROMOTION_PLAYBOOK.md`; any demotions per
   `ADR-0023` (Demotion Procedure).

This checklist is the **end-to-end** discipline: the
next contributor cuts a release by following the
checklist, not by remembering each gate.

## 1. Pre-release (T-7 days)

The pre-release is the **planning** phase. The
release manager:

- [ ] Reads the `PROMOTION_PLAYBOOK.md` and decides
      which (if any) promotions land in this release.
- [ ] Reads the `PYTHON_MIGRATION_TRACKER.md` and
      decides which (if any) Python scripts are
      migrated or deleted.
- [ ] Reads the `CALIBRATION_BACKLOG.md` and decides
      which (if any) parameters are empirically
      calibrated.
- [ ] Updates the release notes (in
      `docs/closure/CHANGELOG.md` or equivalent) with
      the planned changes.
- [ ] Notifies the team of the release window.

If no promotions or migrations are planned, the
release is a **calibration-only** release; the only
required work is the calibration report (per §3).

## 2. Architecture check (T-3 days)

The architecture check is the **first CI gate**. The
release manager:

- [ ] Runs `scripts/check_architecture.sh`. **MUST be
      green.**
- [ ] If any rule fails, fix the violation or
      update the relevant ADR (per
      `AUTHORITY_BOUNDARY.md §4`).
- [ ] Runs `scripts/check_calibration_codomain.sh`.
      **MUST be green** (or the new parameter
      entries are added to
      `data/calibration/ranges.json`).
- [ ] Runs `scripts/check_replay_gate.sh` (static
      checks only). **MUST be green.**
- [ ] Runs the dynamic replay gate tests via
      `cabal test qxfx0-test` (specifically
      `Test.Suite.ReplayGate`). **MUST be green.**

A red light at any of these is a **blocker**; the
release is delayed.

## 3. Calibration report (T-2 days)

The calibration report is the **record of evidence**.
The release manager:

- [ ] Updates `docs/closure/CALIBRATION_REPORT.md`
      with the current release's per-parameter
      results.
- [ ] Records the codomain check (per §2) in the
      "Status" column.
- [ ] Records the CI pass/fail in the "Status"
      column.
- [ ] Updates the "Per-contour results" table with
      the replay gate's pass/fail.
- [ ] Updates the "Status table" at the end with
      the current counts (e.g. "X empirically
      calibrated, Y no change, Z deferred").

The calibration report is the **only place** where
calibration evidence is recorded; without it, the
release is not auditable.

## 4. Promotion (T-1 day)

The promotion is the **flag flip**. The release
manager (or the package owner) follows the
`PROMOTION_PLAYBOOK.md`:

- [ ] Pre-flight: verify the ADR is Proposed, the
      flag's default is False, the env var is wired,
      the test suite is non-canonical.
- [ ] Gate: verify all G1–G4 (per the ADR) are met.
- [ ] Release event: change the default, update the
      env-var doc, migrate the test suite, update
      `SELF_LAYER_STATUS.md` and `AUTHORITY_MAP.md`,
      add a "Flag flips" entry to the release notes,
      update the ADR's status to "Accepted (release
      vN)".
- [ ] Post-flight: verify the trace JSON reflects
      the new default, the calibration report
      records the new value, no `EssenceRupture` (or
      analogous exception) in the first 1k turns.

A promotion that fails the pre-flight or the
post-flight is **rolled back**; the release is
delayed.

## 5. Demotion (T-1 day, if any)

The demotion is the **feature retirement**. The
release manager follows the
`docs/adr/proposed/0023-demotion-procedure.md`:

- [ ] Verify the demotion ADR exists and is
      Proposed.
- [ ] Verify the demotion criteria (D1–D4) are met.
- [ ] Land the demotion: remove the modules, retire
      the tests, remove the trace fields, remove the
      state fields, update the architecture check,
      update the docs, update the promotion ADR's
      status to "superseded by demotion ADR".
- [ ] Verify the trace JSON compatibility window
      (one release cycle) is in place.

A demotion is **irreversible** within a release
cycle. Re-introducing a demoted feature requires a
new design ADR.

## 6. Migration (T-1 day, if any)

The Python → Haskell migration is the **build-time
cleanup**. The release manager follows the
`PYTHON_MIGRATION_TRACKER.md`:

- [ ] Verify the migration order (A → B → C → D →
      E) is followed.
- [ ] Land the Haskell replacement.
- [ ] Update the CI to use the Haskell command.
- [ ] Delete the Python script (or move to
      `scripts/eval/` for `D.` class).
- [ ] Update the tracker.

A migration that fails the order is a **regression**;
the next contributor re-orders it.

## 7. Release (T-0)

The release is the **cut**. The release manager:

- [ ] Tags the release (`vN`).
- [ ] Updates `docs/closure/CHANGELOG.md` with the
      release date and the tag.
- [ ] Updates `docs/closure/SELF_LAYER_STATUS.md` and
      `docs/closure/AUTHORITY_MAP.md` to reflect the
      new state.
- [ ] Notifies the team.

## 8. Post-release (T+1 day)

The post-release is the **verification**. The
release manager:

- [ ] Monitors the first 1k turns of production
      traffic for the post-flight criteria.
- [ ] Updates the `CALIBRATION_REPORT.md` with the
      actual values from production.
- [ ] Re-runs the architecture check, codomain
      check, replay gate, and calibration report to
      verify the release is clean.

A post-release failure is a **rollback**; the
release is reverted and the next release cycle
starts over.

## 9. The discipline

The discipline of this checklist is:

- **No silent flips.** Every change to a default
  must reference the relevant ADR by number.
- **The checklist is the order.** The pre-release,
  architecture, calibration, promotion, demotion,
  migration, release, post-release steps are
  sequential; a step that is skipped is a
  violation.
- **The calibration report is the evidence.** A
  release without a calibration report is not
  auditable.
- **The post-release is the verification.** A
  release that fails the post-release is rolled
  back; the next release cycle starts over.
- **The checklist is regenerated** at every
  release; the discipline evolves as the project
  evolves.

## 10. Acceptance criteria for this checklist

This checklist is **closed** when:

- [ ] The first release (v1) is cut using this
      checklist.
- [ ] The release notes for v1 reference this
      checklist.
- [ ] The post-release verification is recorded
      in `CALIBRATION_REPORT.md`.
- [ ] The checklist is updated with the lessons
      learned from v1.

The checklist is **deferred** until the first
release is cut. Until then, it is **documented but
unused**; the discipline evolves with the project.
