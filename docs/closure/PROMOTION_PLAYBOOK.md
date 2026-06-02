# Promotion Playbook (QxFx0_v3)

- **Status**: Active (closure-phase work product, Package 10
  acceptance criteria §9)
- **Date**: 2026-06-02
- **Refines**:
  - [ADR-0036 — Promote Essence Commitment](./../adr/proposed/0036-promote-essence-commitment.md)
  - [ADR-0019 — Promote Family Divergence](./../adr/proposed/0019-promote-family-divergence.md)
  - [ADR-0020 — Promote Perspective Operator](./../adr/proposed/0020-promote-perspective-operator.md)
  - [ADR-0021 — Promote External LLM Transport](./../adr/proposed/0021-promote-external-llm-transport.md)
  - [ADR-0022 — Promote Adaptive Mutation](./../adr/proposed/0022-promote-adaptive-mutation.md)
  - [ADR-0023 — Demotion Procedure](./../adr/proposed/0023-demotion-procedure.md)
- **Related**:
  - `docs/closure/SELF_LAYER_STATUS.md`
  - `docs/closure/AUTHORITY_MAP.md §6`
  - `docs/closure/CALIBRATION_REPORT.md`

## 0. What this playbook is

The five promotion ADRs (0018–0022) each define a
**promotion gate** (G1, G2, ... G4) and a **release
event** (the steps to flip the default). This playbook
**collects** the steps into a single operational
discipline: the next contributor who wants to flip a
flag follows this playbook, not the per-ADR "release
event" section in isolation.

The playbook is the **bridge** between the
"design-complete" closure plan and the "executed"
post-closure plan. It is a **checklist**, not a
**substitute** for reading the relevant ADR.

## 1. The pre-flight

Before any promotion, the next contributor verifies:

- [ ] The relevant promotion ADR is **Proposed** (not
      superseded by a demotion ADR 0023+).
- [ ] The flag's current default is `False` (or `off`).
- [ ] The flag's env var (if any) is wired (per
      `docs/phase-10-essence-commitment-implementation-spec.md
      §6.1` for the pattern).
- [ ] The flag's test suite is **non-canonical** (per
      `TEST_AUTHORITY_AUDIT.md`); the test exists but is
      not in the default CI lock.
- [ ] The flag's trace fields (if any) are landed in
      `TurnReplayTrace` and are serializable.

If any of the above fails, **stop**. The pre-flight is
the prerequisite for the gate; the gate cannot pass if
the pre-flight fails.

## 2. The gate

The gate is the **set of criteria** the relevant
promotion ADR defines (G1, G2, ...). For each
criterion:

- [ ] Read the criterion in the ADR.
- [ ] Run the relevant test (if mechanical) or do the
      audit (if human).
- [ ] Record the result in
      `docs/closure/CALIBRATION_REPORT.md` under the
      relevant section.
- [ ] Mark the criterion as `met` in the ADR's "Status"
      section.

When **all** criteria are met, the gate is **passed**.

## 3. The release event

The release event is the **change** that flips the
default. The next contributor:

1. **Update the source** — change the default from
   `False` to `True` in the relevant module
   (`QxFx0.Core.TurnPipeline.PrepareStatic`,
   `QxFx0/Core/TurnRouting/Cascade.hs`,
   `QxFx0/Lexicon/Morphology/Parser.hs`, or the
   equivalent parser location).
2. **Update the env-var doc** — if the env var is
   preserved (per ADR-0036 §2.3), update the
   `QXFX0_*_ENABLED` documentation to reflect the
   new default; the env var is the **opt-out** lever.
3. **Update the test suite migration** — move the
   test suite from non-canonical to canonical. The
   `qxfx0-test` suite (or the equivalent canonical
   regression lock) now includes the test.
4. **Update the architecture check** — if the
   promotion adds a new `check_architecture.sh` rule
   (per F-12), make sure the rule is green.
5. **Update `docs/closure/SELF_LAYER_STATUS.md`** —
   mark the relevant module as `production-flag-on`
   (a new status distinct from `production-flag-off`).
6. **Update `docs/closure/AUTHORITY_MAP.md §6`** —
   mark the flag-off feature as `promoted` (or remove
   the row entirely, if the feature is now canonical).
7. **Add a changelog entry** under the release notes'
   "Flag flips" section. The entry must reference
   the promotion ADR by number.
8. **Update the relevant promotion ADR's status** —
   mark it as `Accepted (release vN)`.

The release event is a **commit** (or a small set of
commits), not a hotfix. The diff must reference the
relevant ADR.

## 4. The post-flight

After the release, the next contributor verifies:

- [ ] The release is out; the new default is in
      production.
- [ ] The trace JSON for at least one production turn
      reflects the new default (i.e. the trace has the
      flag-on shape, not the flag-off shape).
- [ ] The calibration report's first pass
      (`docs/closure/CALIBRATION_REPORT.md`) records
      the new value as `empirically calibrated` (or
      `no change (hand-set)` if the value is unchanged
      from the flag-off default).
- [ ] No `EssenceRupture` (or analogous exception) is
      raised in the first 1k turns of production
      traffic.

If any of the above fails, **revert**. The post-flight
is the safety net; a failure here is a signal that the
promotion was premature.

## 5. The five ADRs in one table

The five promotion ADRs (0018–0022) have different
gates, different release events, and different
post-flights. This table is the **summary**.

| ADR | Feature | G1 | G2 | G3 | G4 | Release event | Post-flight |
|---|---|---|---|---|---|---|---|
| 0018 | Essence commitment | corpus 0 ruptures | angst dynamics in range | E1–E5 coherence | — | `essenceCommitmentEnabled = True` | 1k turns, 0 ruptures |
| 0019 | Family divergence | caller audit | replay parity | divergence observability | — | `familyDivergenceEnabled = True` | trace shows non-neutral divergence |
| 0020 | Perspective operator | lineage audit | projection coherence | replay parity | — | `perspectiveOperatorEnabled = True` | projection derivable from registry |
| 0021 | External LLM transport | provider keys | rate limits | cost gates | replay-trace | `QXFX0_LLM_TRANSPORT=on` | local-first path unchanged |
| 0022 | Adaptive mutation | record shape | bounded log | replay parity | observability | `QXFX0_ADAPTIVE_MUTATION=on` | mutation in trace, log bounded |

## 6. The interactions

Some promotions **interact**. The next contributor
must check the interactions before any release event.

- **0018 (essence) ↔ 0022 (adaptive mutation)**: the
  `ssAdaptiveMutationLog` is read by the essence contour
  (per `REPLAY_GATE_TRIAGE.md §2.9`); promoting essence
  before adaptive mutation is **safe** (the read is
  gated by the adaptive mutation flag).
- **0020 (perspective) ↔ 0022 (adaptive mutation)**:
  the perspective projection is read by the adaptive
  mutation log; promoting perspective before adaptive
  mutation is **safe**.
- **0021 (LLM) ↔ all others**: the LLM transport is a
  **supplier**; it does not interact with the
  self-layer's canonical contours. Promoting LLM is
  **independent** of the other four.

The interactions are documented in
`docs/closure/REPLAY_GATE_TRIAGE.md §2.9` (learning
contour's `ssAdaptiveMutationLog` row).

## 7. The discipline

The discipline of this playbook is:

- **No silent flips.** A change to a default must be a
  commit that references the relevant ADR by number.
- **The env var is the opt-out lever.** The default
  flips; the env var is preserved (per ADR-0036 §2.3)
  so operators can opt out.
- **The pre-flight is the prerequisite.** A promotion
  that skips the pre-flight is a violation.
- **The gate is the contract.** A criterion that is
  not met is a gate failure; the gate cannot be
  waived.
- **The post-flight is the safety net.** A failure
  here is a signal to revert.
- **The playbook is the bridge.** The next contributor
  follows the playbook, not the per-ADR "release
  event" section in isolation.

## 8. The first promotion (when)

As of 2026-06-02, no promotion has been done. The
**first candidate** is ADR-0019 (Family Divergence):

- The flag is already in code (`familyDivergenceEnabled`
  is hardcoded `False` in
  `QxFx0/Core/TurnRouting/Cascade.hs:74`).
- The caller audit (G1) is a one-time event, not a
  corpus-dependent gate.
- The replay parity (G2) is a fixed-fixture check, not
  a production-trace corpus.
- The divergence observability (G3) is a check that
  the trace field is writable.

The first promotion is expected to land within the
next release cycle. The other four (0018, 0020, 0021,
0022) are gated on production-trace corpora and are
expected to land later.

## 9. Acceptance criteria for this playbook

This playbook is **closed** when:

- [ ] The first promotion (ADR-0019) has been executed
      using this playbook.
- [ ] The release notes for the first promotion
      reference the playbook.
- [ ] The playbook is updated with the lessons learned
      from the first promotion.
- [ ] The remaining four ADRs (0018, 0020, 0021, 0022)
      are gated on the production-trace corpus (per
      F-09).

The playbook is **deferred** until the first
promotion is done. Until then, the playbook is
**documented but unused**; the promotion path is a
**plan**, not a **practice**.
