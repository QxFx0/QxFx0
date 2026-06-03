# QxFx0_v3 — Onboarding (for the next contributor)

- **Status**: Active (closure-phase work product)
- **Date**: 2026-06-02
- **Audience**: anyone joining the project after the closure
  plan's design pass (per `TECH_DEBT_CLOSURE_INDEX.md`).
- **Related**:
  - `docs/closure/TECH_DEBT_CLOSURE_INDEX.md` (the master
    index of the closure plan)
  - `docs/closure/FOLLOWUPS.md` (the execution tracker)
  - `docs/closure/PROMOTION_PLAYBOOK.md` (the operational
    discipline for the 5 promotion ADRs)

## 0. What this doc is

The closure plan has a growing set of docs in `docs/closure/` and
12 ADRs in `docs/adr/proposed/`. The
"first read" order is implicit. This doc makes it explicit.

If you are a new contributor and have **one hour**, read §1
and §2. If you have **one day**, read §1–§4. If you have
**one week**, read everything; then start with §5 (the
next concrete thing to do).

## 1. The 30-second pitch

`QxFx0_v3` is a Haskell-only, local-first, deterministic
dialogue runtime. It has a **pure self-layer**
(`QxFx0.Self.*`, Phases 1–10) and a **narrative content
supplier** (`QxFx0.Core/Consciousness/*`). The architecture
is **frozen** for runtime authority (per
`docs/AUTHORITY_BOUNDARY.md` 2026-05-26); the closure plan
is the **execution** of the freeze — every flag-off feature
is either promoted (default flipped to `True`) or demoted
(feature retired), every authority-bearing contour has a
replay gate, every Python in the authority path is replaced
by Haskell.

The closure plan is **design-complete** (closure docs + proposed
ADRs are in the repo); the
**execution** is the open work.

## 2. The five-minute read

In order:

1. `docs/closure/TECH_DEBT_CLOSURE_INDEX.md` — the master
   index. §3 has the 7 conditions for closure; §4 has the
   11 packages in 3 stages. Read §1–§4, skim §5–§7.
2. `docs/AUTHORITY_BOUNDARY.md` (2026-05-26) — the freeze
   rules. §1 has the principle, §4 has the rules.
3. `docs/adr/proposed/0034-self-core-role-split.md` — the
   role split. §2 has the role classes, §3 has the 7
   boundary rules, §4 has the per-module map.
4. `docs/closure/AUTHORITY_MAP.md` — the per-module
   table. §3 has the canonical / canonical-flag-off /
   supplier / observer / derived roles; §6 has the
   flag-off features.
5. `docs/closure/SELF_LAYER_STATUS.md` — the per-module
   production status. §2 has the table; §3 has the
   canonical runtime table.

At this point you know: the architecture, the role split,
the flag-off features, and the production status. You can
**read the code**.

## 3. The one-hour read

Add to the five-minute read:

6. `docs/closure/REPLAY_GATE_TRIAGE.md` — the 13
   authority-bearing contours, classified as
   `passing` / `passing-with-notes` / `needs-work` /
   `deferred`. The triage is the **work list** for the
   Packages 2, 4, 7, 8, 9, 11.
7. `docs/closure/PYTHON_STATUS_LEDGER.md` — the 31 Python
   scripts, classified as `A. canonical-build` /
   `B. canonical-runtime` / `C. supplier-build` /
   `D. eval-only` / `E. test-only` / `F. dead`. The
   closure plan's "Python free" goal is the work list
   here.
8. `docs/closure/CALIBRATION_BACKLOG.md` — the 18+
   calibration parameters, with codomains and promotion
   gates. The closure plan's Package 11 is the
   **execution** of the calibration.
9. The 5 promotion ADRs in `docs/adr/proposed/`:
   - `0036-promote-essence-commitment.md`
   - `0019-promote-family-divergence.md`
   - `0020-promote-perspective-operator.md`
   - `0021-promote-external-llm-transport.md`
   - `0022-promote-adaptive-mutation.md`
10. `docs/closure/PROMOTION_PLAYBOOK.md` — the
    operational discipline for the 5 promotion ADRs.
    The playbook is the **bridge** between the design
    and the execution.

At this point you know: the work list, the Python
migration, the calibration backlog, and the promotion
playbook. You can **pick up a task**.

## 4. The one-day read

Add to the one-hour read:

11. The 5 walkthroughs / examples (F-05 through F-08):
    - `docs/closure/SEMANTIC_CORE_EXAMPLE.md` (Package 2)
    - `docs/closure/EPISTEMIC_MEMORY_EXAMPLE.md` (Package 7)
    - `docs/closure/LEARNING_EXAMPLE.md` (Package 8)
    - `docs/closure/METACOGNITION_EXAMPLE.md` (Package 9)
12. The 4 design docs that the walkthroughs refine:
    - `docs/closure/SEMANTIC_CORE_MIN_SLICE.md` (Package 2)
    - `docs/closure/COGNITIVE_MEMORY_DESIGN.md` (Package 7)
    - `docs/closure/BOUNDED_LEARNING_DESIGN.md` (Package 8)
    - `docs/closure/METACOGNITION_LOOP_DESIGN.md` (Package 9)
13. The replay gate spec:
    - `docs/closure/REPLAY_GATE_SPEC.md` (the four
      properties P1–P4; `REPLAY_GATE_TRIAGE.md` §2
      applies them)
14. The GF authority subset:
    - `docs/closure/GF_AUTHORITY_SUBSET.md` (the
      `AuthoritySurface` round-trip; F-11 stub
      `src/QxFx0/Render/Authority.hs`)
15. The system state authority map:
    - `docs/closure/SYSTEM_STATE_AUTHORITY.md` (per-field
      classification of every `ss*` field)
16. The test authority audit:
    - `docs/closure/TEST_AUTHORITY_AUDIT.md` (per-test
      classification of the 30 test suites)
17. The Python supplier allowlist:
    - `docs/closure/PYTHON_SUPPLIER_ALLOWLIST.md` (the
      empty allowlist; the discipline)
18. The learning closed lists:
    - `docs/closure/LEARNING_ALLOWED_TARGETS.md`
    - `docs/closure/LEARNING_ALLOWED_SOURCES.md`
19. The calibration report template:
    - `docs/closure/CALIBRATION_REPORT.md` (F-10)
20. The metacognition corpus spec:
    - `docs/closure/METACOGNITION_CORPUS.md` (F-09)

At this point you know: every closure-plan doc. You
can **land a PR**.

## 5. The next concrete thing to do

The next concrete thing is determined by the smallest
T-shirt size, the least-blocking, and the highest
leverage. As of 2026-06-02:

### 5.1 The smallest task (S-sized, 1 day)

**Land ADR-0019 (Family Divergence) promotion** per
`PROMOTION_PLAYBOOK.md`. The flag
(`familyDivergenceEnabled`) is already in code as a
hardcoded `False` literal in
`QxFx0/Core/TurnRouting/Cascade.hs:74`. The promotion
gate is:

- **G1 — adjunction caller audit** (one-time
  audit, no corpus needed).
- **G2 — replay parity** (fixed-fixture replay;
  the fixtures exist in `test/Test/Suite/`).
- **G3 — divergence observability** (check that
  `trcDeliberationDivergence` is writable).

The promotion is the **first** execution of the
playbook; the playbook is "documented but unused"
until this lands.

### 5.2 The next-smallest task (M-sized, 1 week)

**Land the `check_replay_gate.sh` CI script** that
runs the four property tests (P1–P4) on every
canonical contour. The triage list
(`REPLAY_GATE_TRIAGE.md`) is the input; the script
is the output. The script is post-Package 3 and is
the only "needs-work" item in F-13.

### 5.3 The biggest task (L-sized, 2 weeks)

**Land the F-09 corpus** (1k unlabelled + 100
labelled records per `METACOGNITION_CORPUS.md`).
The corpus is the prerequisite for the F-10
calibration report's first pass. The corpus
requires production-trace data; the next
contributor with codebase access can extract the
traces and label them.

## 6. The current state (snapshot)

As of 2026-06-02:

### 6.1 Docs and ADRs

- closure docs in `docs/closure/` (count changes as the working
  tree evolves).
- 12 ADRs in `docs/adr/proposed/` (the 5 promotion ADRs,
  the demotion procedure, and earlier design stubs).
- proposed ADRs stay in `docs/adr/proposed/` until they land.

### 6.2 Code artifacts

- 1 new module: `src/QxFx0/Render/Authority.hs`
  (the Package 4 stub).
- 1 new test: `test/Test/Suite/RenderAuthorityStub.hs`.
- 1 new data file: `data/calibration/ranges.json`
  (13 parameters).
- 2 new CI scripts: `scripts/check_calibration_codomain.sh`
  (Package 11), `scripts/check_architecture.sh` extended
  with rules [13]–[20] (Package 1).
- 2 CI hooks: `ci_gate_contract.sh` (Gate 3b) and
  `verify.sh` (step [10b/10]).

### 6.3 F-01..F-15 status

All 15 follow-ups are **drafted**. The execution is
the open work. The tracker is in
`docs/closure/FOLLOWUPS.md`.

## 7. The discipline

The discipline of this closure plan is:

- **No silent flips.** A change to a default must
  reference the relevant ADR by number.
- **The replay gate is the contract.** P1–P4 must
  hold for every authority-bearing contour; the
  triage list is the work list.
- **The codomain check is the prerequisite.** Every
  parameter in `data/calibration/ranges.json` is
  in a closed range; the script enforces this.
- **The architecture check is the discipline.** The
  7 boundary rules of ADR-0034 §3 are enforced
  by `check_architecture.sh` rules [13]–[20].
- **The Python → Haskell migration is tracked.** The
  closure plan's "Python free" goal is the work
  list in `PYTHON_MIGRATION_TRACKER.md`.
- **The promotion is gated.** The 5 promotion ADRs
  have explicit gates (G1–G4); the playbook is
  the operational discipline.

## 8. The honest limits

- This doc is **dated** (2026-06-02). The current
  state is a snapshot; the next contributor
  updates the snapshot as the work progresses.
- The "next concrete thing" (§5) is the smallest
  T-shirt size, not the highest-priority. The
  highest-priority is the F-09 corpus (L-sized),
  but the corpus requires production-trace data
  that the next contributor may not have.
- The discipline (§7) is the **default**, not a
  rule. The next contributor can deviate with
  justification; the deviation is recorded in
  the relevant ADR.
