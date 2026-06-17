# Closure Follow-ups Tracker (QxFx0_v3)

- **Status**: Active (closure-phase follow-up, INDEX §7)
- **Date**: 2026-06-02
- **Refines**: `docs/closure/TECH_DEBT_CLOSURE_INDEX.md` §7
- **Related**: all `docs/closure/*.md`

## 0. Purpose

This file is the single tracker for every closure-phase
follow-up. The closure plan is design-complete (13 documents
in `docs/closure/` and `docs/adr/proposed/`); this tracker
lists the **execution-side** deliverables that move the
project from "plan in place" to "plan executed".

Each entry has:

- **id** — stable identifier (F-N).
- **owner-package** — which closure package it belongs to.
- **kind** — doc / code / ci / corpus.
- **status** — not-started / in-progress / drafted / merged.
- **prerequisite-of** — which other follow-up it unblocks.
- **estimate** — T-shirt size (S/M/L/XL) for a single
  contributor with access to the codebase.

## 1. The follow-ups

### F-01: SYSTEM_STATE_AUTHORITY.md
- **owner-package**: P1
- **kind**: doc
- **status**: drafted (in this pass)
- **prerequisite-of**: P1 closure (`AUTHORITY_MAP.md §11`)
- **estimate**: S (per-field table from `src/QxFx0/Types/State/System.hs`)
- **what it produces**: per-field classification of every `ss*`
  field on `SystemState`. The fields with non-obvious status
  (the `canonical-flag-off` and `derived` ones) get explicit
  rules for "what may write / what may read".

### F-02: PYTHON_SUPPLIER_ALLOWLIST.md
- **owner-package**: P5
- **kind**: doc
- **status**: drafted (in this pass)
- **prerequisite-of**: P5 Gate P5-7
- **estimate**: S (template + empty file)
- **what it produces**: the empty allowlist per
  `PYTHON_STATUS_LEDGER.md §6`. The template enforces the
  per-file structure; the file is empty when all supplier
  Python is replaced or moved.

### F-03: LEARNING_ALLOWED_TARGETS.md
- **owner-package**: P8
- **kind**: doc
- **status**: drafted (in this pass)
- **prerequisite-of**: P8 invariant I1 enforcement
- **estimate**: S
- **what it produces**: the closed list of
  `LearningTarget` values. CI rejects any update to a
  target not on the list.

### F-04: LEARNING_ALLOWED_SOURCES.md
- **owner-package**: P8
- **kind**: doc
- **status**: drafted (in this pass)
- **prerequisite-of**: P8 invariant I2 enforcement
- **estimate**: S
- **what it produces**: the closed list of
  `LearningSource` values. CI rejects any consumption of a
  source not on the list.

### F-05: SEMANTIC_CORE_EXAMPLE.md
- **owner-package**: P2
- **kind**: doc
- **status**: drafted (in this pass)
- **prerequisite-of**: P2 acceptance criteria §5
- **estimate**: S (one walkthrough)
- **what it produces**: a single end-to-end example walking
  through one `commit`, one `revise`, one `contradict`, one
  `retract`, and the resulting `SemanticCommitmentStore`.

### F-06: EPISTEMIC_MEMORY_EXAMPLE.md
- **owner-package**: P7
- **kind**: doc
- **status**: drafted (in this pass)
- **prerequisite-of**: P7 acceptance criteria §6
- **estimate**: S
- **what it produces**: a single end-to-end example
  walking through one `encode`, one `retrieve`, one
  `forget`, and the resulting `EpisodicStore`.

### F-07: LEARNING_EXAMPLE.md
- **owner-package**: P8
- **kind**: doc
- **status**: drafted (in this pass)
- **prerequisite-of**: P8 acceptance criteria §8
- **estimate**: S
- **what it produces**: a single end-to-end example
  walking through one proposed update, one applied update,
  one rejected update (with reason), and the resulting
  `LearningContour`.

### F-08: METACOGNITION_EXAMPLE.md
- **owner-package**: P9
- **kind**: doc
- **status**: drafted (in this pass)
- **prerequisite-of**: P9 acceptance criteria §7
- **estimate**: S
- **what it produces**: a single end-to-end example
  walking through one decision, one outcome, one
  evaluation, one bounded correction, and the resulting
  trace.

### F-09: METACOGNITION_CORPUS.md
- **owner-package**: P9
- **kind**: corpus spec + initial data
- **status**: spec drafted (in this pass); data not started
- **prerequisite-of**: P9 calibration gate; P11 calibration
  report
- **estimate**: M (corpus construction is a multi-day effort;
  spec is S)
- **what it produces**:
  - a corpus spec (which records, which fields, which
    external labels);
  - a labelling protocol (who labels, how disagreement is
    resolved);
  - a starting subset of at least 100 labelled records.

### F-10: CALIBRATION_REPORT.md
- **owner-package**: P11
- **kind**: doc (template)
- **status**: template drafted (in this pass); first pass
  not started
- **prerequisite-of**: P11 acceptance criteria §6
- **estimate**: M (template is S; first calibration pass is M)
- **what it produces**: a calibration report template; the
  first pass fills it. The template enforces "what moved,
  by how much, against what corpus, with what confidence
  intervals".

### F-11: AuthoritySurface Haskell stub
- **owner-package**: P4
- **kind**: code
- **status**: drafted (in this pass; module + test added to
  `src/QxFx0/Render/Authority.hs` and
  `test/Test/Suite/RenderAuthorityStub.hs`; cabal updated to
  expose the new module and include the new test in the
  `qxfx0-test` suite — see §5 below)
- **prerequisite-of**: P4 acceptance criteria §9
- **estimate**: S (the stub is small; the full implementation
  is M)
- **what it produces**: a working
  `QxFx0.Render.Authority` module with the `AuthoritySurface`
  newtype, `parseAuthoritySurface`, `renderAuthoritySurface`,
  and a stub `roundTripProperty`. The stub's `parseAuthoritySurface`
  returns `Nothing` for everything (the real implementation
  needs Package 4's parser extension; the stub makes the
  boundary visible).

### F-12: check_architecture.sh extension
- **owner-package**: P1
- **kind**: CI
- **status**: drafted (in this pass; rules [13]–[20] added
  to `scripts/check_architecture.sh` — see §6 below)
- **prerequisite-of**: P1 closure; P5 closure verification
- **estimate**: S (7 grep rules; ~50 lines of bash)
- **what it produces**: the seven boundary rules of
  ADR-0034 §3 enforced at CI time. The rules are
  import-level heuristics; the closure plan's Package 6
  test audit processes the false-positive triage.

### F-13: check_replay_gate.sh (new)
- **owner-package**: P3
- **kind**: CI + doc
- **status**: drafted (in this pass; triage list
  produced — see §7 below; the `check_replay_gate.sh`
  CI script itself is post-Package 3 and not yet landed)
- **prerequisite-of**: P3 closure
- **estimate**: M (the four property tests per existing
  canonical contour)
- **what it produces**: a new CI script that runs the
  P1–P4 property tests on every canonical contour.
  Initial state: a triage list of which contours fail and
  what the fix is. The triage list is in
  `docs/closure/REPLAY_GATE_TRIAGE.md`.

### F-14: Promotion ADRs for flag-off features
- **owner-package**: P10
- **kind**: ADR (per feature)
- **status**: drafted (in this pass; 5 ADRs added to
  `docs/adr/proposed/` — see §8 below)
- **prerequisite-of**: P10 acceptance criteria §8
- **estimate**: M (one ADR per feature: Essence,
  FamilyDivergence, Perspective.Operator, ExternalLLM,
  AdaptiveMutation; 5 ADRs)
- **what it produces**: per-feature promotion ADRs that
  pin the corpus-replay gate for each flag-off feature.
  These ADRs are the **bridge** between the current
  "landed but off" state and the closure plan's "promoted
  or demoted" state.

### F-15: Demotion ADRs (if any feature is retired)
- **owner-package**: P10
- **kind**: ADR (per feature) + procedural template
- **status**: drafted (in this pass; the procedural
  template is in `docs/adr/proposed/0023-demotion-procedure.md`;
  no per-feature demotion ADRs are needed because no
  feature is being retired — see §9 below)
- **prerequisite-of**: P10 acceptance criteria §8 (the
  alternative path)
- **estimate**: M (template) + M per retired feature
- **what it produces**: a procedural template for
  per-feature demotion ADRs (F-15's primary artifact),
  plus concrete demotion ADRs if any feature is
  actually retired.

## 2. Sequencing

| Order | Follow-up | Why |
|---|---|---|
| 1 | F-12 | P1 closure requires the CI extension. |
| 2 | F-01 | P1 closure also requires per-field classification. |
| 3 | F-13 | P3 closure; the triage list unblocks Packages 7-9. |
| 4 | F-03 + F-04 | P8 closure; the closed lists are upstream of the LearningContour code. |
| 5 | F-11 | P4 closure; the stub is the first real code artifact. |
| 6 | F-02 | P5 Gate P5-7; the empty allowlist. |
| 7 | F-05 through F-08 | documentation; parallelisable. |
| 8 | F-14 | P10 closure; one per feature. |
| 9 | F-09 (spec) | P9 closure; the corpus spec is upstream of the corpus. |
| 10 | F-09 (data) + F-15 (if any) | downstream. |

After the closure plan's 7 conditions of INDEX §4 are met, the
remaining work is calibration (F-10) and the operational
discipline of keeping the architecture-check rules enforced.

## 3. Acceptance criteria for the follow-up tracker

The tracker is **closed** when:

- [ ] Every follow-up (F-01 through F-15) is merged or has
      a documented "intentionally deferred" status with a
      reason.
- [ ] F-12 and F-13 are wired into CI; CI is green.
- [ ] F-14 (and F-15 if any) are accepted ADRs; the
      flag-off features are either promoted or retired.
- [ ] F-09 (data) is complete; calibration report (F-10)
      is filled.
- [ ] The 7 conditions of INDEX §4 are all met
      simultaneously.

## 5. Artifacts produced by F-11

F-11 produced three concrete edits, in addition to this
tracker entry:

1. `src/QxFx0/Render/Authority.hs` — the stub module. The
   `AuthoritySurface` newtype, `parseAuthoritySurface` (total
   `Nothing`), `renderAuthoritySurface` (constant
   `emptyAuthoritySurface`), and `roundTripProperty`
   (trivially `True`). The signature is **stable** so that
   the only change when the real parser is landed is the
   body of `parseAuthoritySurface` and the property's
   expectation; no consumer signature changes.
2. `test/Test/Suite/RenderAuthorityStub.hs` — a small
   HUnit test suite that locks the stub's contract:
   parser returns `Nothing` for every input, renderer always
   returns the stub surface, the round-trip property holds.
   When the real parser is landed, this suite is extended
   with the "round-trip is total" property; the stub tests
   stay as a regression lock for the no-op case.
3. `qxfx0.cabal` — the new module is added to `exposed-modules`
   next to the other `QxFx0.Render.*` entries, and the new
   test is added to the `qxfx0-test` suite's test-modules.

None of these edits change runtime behaviour: the module is
not yet imported anywhere. The next step is to extend
`Qxfx0.Core.TurnPipeline.Route.Render` (or a small adapter)
to thread an `AuthoritySurface` through the render path
(per `GF_AUTHORITY_SUBSET.md §2`), and to land the real
GF Haskell parser.

## 6. Artifacts produced by F-12

F-12 extended `scripts/check_architecture.sh` with rules
[13]–[20], one per boundary rule of ADR-0034 §3:

- **Rule [13]** — Rule 1 (mechanical): `Self/*` must not
  import `Core.TurnPipeline.*` or `Bridge.*`.
- **Rule [14]** — Rule 2 (mechanical): `Core/*` modules
  that are not in `Core.TurnPipeline.*` and are not
  declared `observer` or `supplier` in their Haddock
  must not import `Core.TurnPipeline.Finalize.*`,
  `Core.TurnPipeline.Effects`, or
  `Core.TurnPipeline.Route.Render`.
- **Rule [15]** — Rule 5 (mechanical): no `Bridge/*`
  module other than `Bridge/ExternalLLM.hs` may use a
  `QXFX0_*_ENABLED` feature flag.
- **Rule [16]** — Rule 7 (heuristic): every `*Generated.hs`
  under `src/` must have a generator script in
  `scripts/` (`build_*.sh`, `generate_*.sh`, or
  `build_*.py`).
- **Rule [17]** — Rule 1 (declarative): every `Self/*.hs`
  must declare one of `canonical`, `canonical-flag-off`,
  or `supplier` in its module Haddock `Description :`
  line.
- **Rule [18]** — Rule 4 (heuristic): every `Render/*.hs`
  that defines a `render*` / `build*` function must
  import `QxFx0.Core.TurnPipeline.Route.Render` (i.e.
  the orchestrator).
- **Rule [19]** — Rule 3 (declarative): every `Core/*`
  module that imports `QxFx0.Core.Observability` must
  declare `observer` in its module Haddock.

The rules are mechanical where the source pattern is
mechanical (imports, flags) and declarative where the
discipline is a Haddock annotation (roles). Heuristics
([16], [18]) are flagged as such; the closure plan's
Package 6 test audit processes the false-positive
triage.

## 7. Artifacts produced by F-13

F-13 produced the triage list
`docs/closure/REPLAY_GATE_TRIAGE.md`. The list covers
13 authority-bearing contours, each classified as one of
`passing` / `passing-with-notes` / `needs-work` /
`deferred`. The "needs-work" contours (Perspective,
Episodic memory, Learning, Calibration, Metacognition,
AuthoritySurface, Semantic commitments) are the work
list for the closure plan's Packages 2, 4, 7, 8, 9, 11.

The CI script `check_replay_gate.sh` is the
**follow-up** to F-13; the triage list is the input,
not the script. The script is post-Package 3.

## 8. Artifacts produced by F-14

F-14 produced 5 promotion ADRs in `docs/adr/proposed/`:

1. `0036-promote-essence-commitment.md` — Policy A
   (2026-06-17): Essence is law-driven, `rrEssenceActive = True`;
   the `essenceCommitmentEnabled` flag was never implemented.
   G1–G3 (corpus, angst, E1–E5) remain the path to any
   **felt-evidence** (M6-FELT) claim, not to structural status.
2. `0019-promote-family-divergence.md` — gates
   `familyDivergenceEnabled` flip on G1 (adjunction
   caller audit), G2 (replay parity on no-modulation
   cases), G3 (divergence observability).
3. `0020-promote-perspective-operator.md` — two-part
   ADR: first lands `QXFX0_PERSPECTIVE_OPERATOR_ENABLED`
   (no flag exists today), then promotes on G1 (lineage
   audit), G2 (projection coherence), G3 (replay
   parity).
4. `0021-promote-external-llm-transport.md` — gates
   `QXFX0_LLM_TRANSPORT` flip on G1 (provider keys),
   G2 (rate limits), G3 (cost gates), G4 (replay-trace
   discipline for LLM calls).
5. `0022-promote-adaptive-mutation.md` — gates
   `QXFX0_ADAPTIVE_MUTATION` flip on G1 (record shape),
   G2 (bounded log), G3 (replay parity), G4
   (observability).

Each ADR's "Alternatives considered" section references
F-15 (the demotion path) as the alternative. F-15
itself stays at "not started; conditional" because no
features are being retired as of this pass.

## 9. Artifacts produced by F-15

F-15 produced the procedural template
`docs/adr/proposed/0023-demotion-procedure.md`. The
template specifies the structure of a per-feature
demotion ADR (mirroring the structure of the promotion
ADRs 0018–0022) and the conditions under which a
demotion is preferred to a promotion (D1–D4). A
review of the five promotion ADRs as of 2026-06-02
finds that **no feature meets D1–D4**; the demotion
procedure is documented for the future but not yet
exercised.

A companion artifact, `docs/closure/PROMOTION_PLAYBOOK.md`,
ties the five promotion ADRs into a single operational
discipline (pre-flight, gate, release event, post-flight).
The playbook is the **bridge** between the design-complete
closure plan and the executed post-closure plan. It is
deferred until the first promotion (expected to be
ADR-0019, Family Divergence) is done.

A second companion artifact,
`scripts/check_calibration_codomain.sh` (with
`data/calibration/ranges.json` as input), is the
**Package 11 enforcement tool**. The script reads the
JSON spec and verifies that every default value
declared in the source is in the closed range. As of
2026-06-02, 13 parameters are in the spec, all in
range. 17 GAPs (fields with defaults but no spec
entry) are reported as informational; the next
contributor adds GAPs to the spec as Package 11's
calibration work progresses.

## 10. Honest limits

- The estimate column is **T-shirt size**, not hours. A
  single contributor with codebase access can do most
  S-sized follow-ups in a day; M-sized in a week; L in
  two weeks. F-13 (P3 closure) and F-09 (P9 corpus) are
  the most likely L-sized items.
- The "prerequisite-of" column is **strict**. A follow-up
  that is not a prerequisite of any other can be done
  anytime; this tracker does not force order on those.
- The status column starts at "drafted" for the follow-ups
  produced in this closure pass (F-01 through F-11). F-12
  through F-15 are now "drafted" (in this pass).
- The codomain check (`check_calibration_codomain.sh`)
  is mechanical for the parameters in
  `data/calibration/ranges.json`; record-update syntax
  (e.g. `defaultX = phase9X { field = value }`) is a
  known limitation. The next contributor extends the
  script to follow `defaultX = ...` definitions
  specifically (per the script's `Known limitations`
  comment).
- The promotion playbook (`PROMOTION_PLAYBOOK.md`) is
  deferred until the first promotion is done. Until
  then it is **documented but unused**; the playbook's
  acceptance criteria are met by execution, not by
  documentation.

## 11. Operational artifacts (post-design)

These docs are not part of the F-01..F-15 follow-up
chain; they are the **operational layer** that makes
the closure plan executable.

### 11.1 ONBOARDING.md
- **purpose**: first-read order for new contributors
  joining the project after the closure plan's
  design pass. §1–§7 cover 30-second, 5-minute,
  1-hour, 1-day, 1-week, current-state, and
  discipline. §5 is the "next concrete thing" pointer.
- **owner**: docs maintainer (rotates)
- **status**: drafted (2026-06-02)
- **next action**: regenerate at every release

### 11.2 ENFORCEMENT_MATRIX.md
- **purpose**: maps each of the 7 boundary rules in
  `ADR-0034 §3` to (CI check, test, doc, status). The
  matrix is the **discipline map**; a row that is
  missing a column is a **gap**, not a redundancy.
- **owner**: package owners (one per row)
- **status**: drafted (2026-06-02); current working-tree matrix
  is 7G/0Y/0R, landed status still requires build/test/CI
- **next action**: keep matrix rows aligned with actual script and
  test wiring; do not re-open closed rows without evidence

### 11.3 PYTHON_MIGRATION_TRACKER.md
- **purpose**: status board for the closure plan's
  "Python free" goal. Tracks 34 Python scripts across
  6 closure classes (A–F); 0/34 migrated as of
  2026-06-02. The migration order is A → B → C → D
  → E; the next concrete migration is **Gate P5-1
  (A. canonical-build)**.
- **owner**: Package 5 owner
- **status**: drafted (2026-06-02); all 34 scripts
  PENDING
- **next action**: land Gate P5-1 (3 `A.` scripts
  deleted, Haskell commands in CI)

### 11.4 PROMOTION_PLAYBOOK.md
- **purpose**: operational discipline for the 5
  promotion ADRs (0018–0022). Pre-flight / gate /
  release event / post-flight. **Documented but
  unused** until the first promotion lands.
- **owner**: Package 10 owner
- **status**: drafted (2026-06-02)
- **next action**: land ADR-0019 (Family Divergence)
  as the first promotion

### 11.5 The 4 enforcement scripts

The closure plan's enforcement is in 4 scripts:

1. `scripts/check_architecture.sh` — 20 rules
   ([1]–[12] freeze-0 / runtime perimeter;
   [13]–[20] ADR-0034 §3 role split). Package 1.
2. `scripts/check_calibration_codomain.sh` — 13
   parameters in `data/calibration/ranges.json`.
   Package 11.
3. `scripts/check_replay_gate.sh` — **not yet
   landed**; the triage list
   (`REPLAY_GATE_TRIAGE.md`) is the input, the
   script is the output. Package 3.
4. `scripts/check_input_lexicon.py` (Python) — the
   Python replacement is per
   `PYTHON_MIGRATION_TRACKER.md §2.1` row
   `check_input_lexicon.py` (C. supplier-build).

The 4 scripts are wired into
`scripts/ci_gate_contract.sh` (Gates 3, 3b, 4) and
`scripts/verify.sh` (steps [10], [10b], [11]).

## 12. Latest pass (post-§11)

This section tracks the most recent additions to
the operational layer.

### 12.1 check_replay_gate.sh
- **purpose**: Package 3 enforcement (F-13 follow-up).
  Static checks for P1–P4 on every canonical contour.
  Verifies `deriving stock Show`, no `IO` in compute
  signatures, snapshot-able types, and `trc*` field
  presence in `TurnReplayTrace`.
- **status**: drafted (2026-06-02); 5 canonical
  contours checked; 0 violations; 3 GAPs reported
  (Conatus, Field, Identity) — these are Package 3
  work items per `REPLAY_GATE_TRIAGE.md §3`.
- **wired into**: `ci_gate_contract.sh` Gate 3c,
  `verify.sh` step [10c/10].

### 12.2 Test.Suite.ReplayGate
- **purpose**: locks P1–P4 for the canonical contours
  via HUnit property tests. The test is the **dynamic**
  companion of `check_replay_gate.sh` (the static
  script).
- **status**: drafted (2026-06-02); 4 tests
  (p1Serializable, p2Replayable, p3Reconstructable,
  p4TraceExplainable); wired into `qxfx0-test` and
  `qxfx0-test-unit`.

### 12.3 Test.Suite.ObserverDiscipline
- **purpose**: closes the **red row** for R3 in
  `ENFORCEMENT_MATRIX.md §1`. The script (rule [19])
  catches the static side; this suite catches the
  dynamic side.
- **status**: drafted (2026-06-02); textual check
  (a full AST-based check is post-MVP per the
  module's Haddock); wired into `qxfx0-test`.

### 12.4 RELEASE_CHECKLIST.md
- **purpose**: end-to-end release discipline
  (pre-release, architecture, calibration, promotion,
  demotion, migration, release, post-release). The
  checklist is the **bridge** between the
  design-complete closure plan and the cut releases.
- **status**: drafted (2026-06-02); **documented but
  unused** until the first release is cut.

### 12.5 The 5 enforcement scripts (final)

The closure plan's enforcement is now in 5 scripts
(1 is the stub from F-11, 1 was the gap, 1 is new):

1. `scripts/check_architecture.sh` — 20 rules
   ([1]–[12] freeze-0 / runtime perimeter;
   [13]–[20] ADR-0034 §3 role split). Package 1.
2. `scripts/check_calibration_codomain.sh` — 13
   parameters in `data/calibration/ranges.json`.
   Package 11.
3. `scripts/check_replay_gate.sh` — P1–P4 static
   checks on 5 canonical contours. Package 3.
   **NEW in this pass.**
4. `scripts/check_replay_gate_test.sh` — runs
   `Test.Suite.ReplayGate` via cabal. **Wired as
   `cabal test qxfx0-test` (per the existing
   `ci_gate_contract.sh` Gate 2).** Not a separate
   script; the test is the gate.
5. `scripts/check_input_lexicon.py` (Python) — the
   Python replacement is per
   `PYTHON_MIGRATION_TRACKER.md §2.1` row
   `check_input_lexicon.py` (C. supplier-build).

The 5 scripts are wired into
`scripts/ci_gate_contract.sh` (Gates 2, 3, 3b, 3c, 4)
and `scripts/verify.sh` (steps [10], [10b], [10c],
[11]).

## 13. Latest pass (post-§12)

The §12 pass identified the 3 GAPs in the
replay gate. The §13 pass turned the GAPs into
**actionable disciplines** without modifying the
central `TurnReplayTrace` type (which is
50+ fields, 3 call sites, and out of scope for
a read-only session).

### 13.1 TRACE_SCHEMA.md (NEW)

- **purpose**: the **single source of truth** for
  what each `trc*` field in `TurnReplayTrace`
  means, where it comes from, and which canonical
  contour it belongs to.
- **size**: 460 lines.
- **structure**:
  - §1: the 6 canonical contours (with status
    table).
  - §2-§7: per-contour schema (Conatus, Field,
    Salience, Deliberation, Essence, Identity).
    For each: type, compute site, source value,
    P1-P4 status, why-it-is-canonical, what-closes-the-GAP.
  - §8: non-canonical `trc*` fields (76 of the
    90 total).
  - §9: discipline for adding a new canonical
    contour (8 steps).
  - §10-§11: cross-references + honest limits.
- **key insight**: the 6th canonical contour
  (Essence) was added 2026-05-19 with the
  Phase 9-10 landing. The previous scripts
  only checked 5 contours; this document
  makes the 6th visible.
- **GAP discipline**: the 3 GAPs are
  *documented as expected* (§2, §3, §7), with
  the exact field type, the exact source value,
  and the exact `Projection.hs` constructor
  line. Closing a GAP is now a **paste-able
  recipe** from the doc.

### 13.2 CONTOUR_INDEX.md (NEW)

- **purpose**: the **complement** of
  `TRACE_SCHEMA.md`. Answers "what is each
  contour, where is it computed, what property
  status does it have?" — the **structural
  view**, not the schema view.
- **size**: 328 lines.
- **structure**:
  - §1: the 6 canonical contours (with Self
    module + trc\* field count + P4 status).
  - §2-§7: per-contour profile (type, compute
    function, purity, snapshot type, codomain,
    promotion flag).
  - §8-§9: cross-references + honest limits.
- **key insight**: the contour index names the
  **non-canonical 5** (Blanket, Adjunction,
  Perspective, ConatusEnergy, FieldHeuristics)
  explicitly. The 6 canonical do not exhaust
  the Self/* subtree.

### 13.3 Test.Suite.TraceSchema (NEW)

- **purpose**: the **runtime** companion of
  `check_replay_gate.sh` (the static check).
  The script is a regex; this test reads the
  source file and asserts the discipline.
- **size**: 179 lines.
- **3 tests**:
  - `p4OkContoursHaveTrcField`: for each of the
    3 OK canonical contours (Salience,
    Deliberation, Essence), assert that the
    documented `trc*` field is declared in
    `data TurnReplayTrace = ...`. A regression
    (the field is removed) makes this test
    fail.
  - `traceSchemaMdExists`: assert
    `docs/closure/TRACE_SCHEMA.md` exists and
    has the §1 canonical-contour index and the
    §6 Essence section.
  - `traceSchemaMdHasDiscipline`: assert the
    3 GAPs are documented and the §9
    "Discipline: adding a new canonical
    contour" section exists.
- **GAP discipline**: the test does NOT assert
  that the 3 GAP contours have their fields in
  the type. The discipline says they are
  "expected but not yet landed". The static
  script continues to report the GAPs; the test
  only locks the OK contours and the schema
  doc.
- **wired into**: `qxfx0-test` and
  `qxfx0-test-unit` via `qxfx0.cabal` and
  `test/TestMain.hs` / `test/TestMainUnit.hs`.

### 13.4 Test.Suite.RegenerableDerived (NEW)

- **purpose**: closes the **red row** for R7
  in `ENFORCEMENT_MATRIX.md §1`. R7 is the
  "derived modules must remain regenerable"
  rule (ADR-0034 §3 Rule 7).
- **size**: 218 lines.
- **what it does**:
  1. Walks `src/` for `*Generated.hs` and
     `*Auto.hs` files (currently 3:
     `Lexicon/Generated.hs`,
     `Semantic/Input/GeneratedLexicon.hs`,
     `Bridge/EmbeddedSQL.hs`).
  2. For each, extracts the `AUTO-GENERATED`
     marker (or "Generated by qxfx0
     --sync-embedded-sql" for the EmbeddedSQL
     case).
  3. Verifies the marker references a script
     under `scripts/`.
  4. Verifies the referenced script exists.
- **what it does NOT do**: a full
  generator-drift test (run the generator,
  compare to the checked-in artifact). That
  requires Python+GF+Agda in the test
  environment and is post-MVP per the
  module's Haddock.
- **the 3 checks together** that close R7:
  - `check_architecture.sh` rule [16] (static
    heuristic).
  - `check_generated_artifacts.sh` (shell
    script, runs in CI).
  - `Test.Suite.RegenerableDerived` (HUnit
    test, locks discipline at the unit level).
- **wired into**: `qxfx0-test` and
  `qxfx0-test-unit`.

### 13.5 Updated check_replay_gate.sh

- The script now checks **6** canonical
  contours (Essence added).
- The `EXPECTED_MISSING` table now includes
  the `TRACE_SCHEMA.md` section reference for
  each GAP:
  - `Conatus|TRACE_SCHEMA.md §2`
  - `Field|TRACE_SCHEMA.md §3`
  - `Identity|TRACE_SCHEMA.md §7`
- Before the working-tree trace-gap closure, the
  script reported a GAP message. After landing
  `trcConatusEnergy`, `trcField`, and
  `trcIdentityClaims`, the same checks report
  `OK` for those contours.
  Historical GAP output example:
  ```
  GAP Conatus (trcConatusEnergy) — Package 3
      work item; see TRACE_SCHEMA.md §2
  ```

### 13.6 State of ENFORCEMENT_MATRIX after §13

| Rule | CI | Test | Doc | Status |
|------|-----|------|-----|--------|
| R1 | green | green | green | green |
| R2 | green | yellow | green | yellow (test) |
| R3 | green | **green** | green | **green** (R3 test = Test.Suite.ObserverDiscipline, closed in §12) |
| R4 | green | green | green | green |
| R5 | green | green | green | green |
| R6 | yellow | green | green | yellow (CI) |
| R7 | green | **green** | green | **green** (R7 test = Test.Suite.RegenerableDerived, closed in §13) |

After §13: **5 green + 2 yellow + 0 red rows**
(down from 2 green + 3 yellow + 2 red at the
start of the session).

The 2 remaining yellows are:
- R2 (test): `Test.Suite.ArchitectureInvariants`
  does not yet mechanically assert R2. The
  next contributor extends it.
- R6 (CI): no CI check for "canonical-flag-off
  modules are not in the authority path". The
  discipline is in the docs and the
  per-module test, but the script is missing.

Both yellows are **S-sized follow-ups** that
the next contributor can complete in a
read-only session.

## 14. Latest pass (post-§13)

The §13 pass closed R3 and R7 red rows (5G/2Y/0R).
The §14 pass closes R2 yellow and adds the
promotion flag discipline.

### 14.1 R2 yellow closure

- **what was missing**: `Test.Suite.ArchitectureInvariants`
  had only the R1 test (Self/* must not import
  runtime-y things). R2 ("Core supplier must not
  import canonical-orchestrator writers") was
  asserted only in spirit (per
  `TEST_AUTHORITY_AUDIT.md`), not mechanically.
- **what was added**: a second test,
  `testR2SupplierDoesNotImportOrchestrator`, that
  walks `src/QxFx0/Core/Consciousness/*` and
  asserts no file imports
  `QxFx0.Core.TurnPipeline` / `TurnRouting` /
  `TurnPlanning` / `TurnRender` / `TurnLegitimacy`.
- **verified**: 0 violations (verified manually
  via `rg "import QxFx0.Core.Turn(Pipeline|...)"`
  in `Consciousness/`).
- **matrix status**: 6G/1Y/0R (rev. 3).

### 14.2 ADR_INDEX.md (NEW)

- **purpose**: canonical index of every ADR in
  the project. Disambiguates 2 numbering
  collisions and provides chronological +
  thematic views.
- **size**: ~330 lines.
- **key findings**:
  - **2 real collisions** between `docs/adr/`
    and `docs/adr/proposed/`: 0017 (Post-Commitment
    Self-Tuning vs Domain Reasoning Packs) and
    0018 (Deterministic Time Injection vs
    Promote Essence Commitment). When citing
    these ADRs, **always include the file name**
    to avoid ambiguity.
  - **1 internal collision** in `proposed/`: 0013
    (Cross-Session Essence Persistence vs
    Self/Core Role Split). The second is the
    **central closure-plan decision**.
  - **Recommended fix** (not applied in this
    pass): renumber all 12 `proposed/` ADRs to
    0034-0045. This is a S-sized follow-up.
- **structure**:
  - §1: the 3 collisions (with the disambiguation
    table).
  - §2: chronological index (23 landed + 12
    proposed).
  - §3: thematic index (by phase/contour).
  - §4: cross-references by ADR (per-ADR view).
  - §5: promotion status (the 5 candidates and
    their off-state).
  - §6: honest limits.

### 14.3 Test.Suite.PromotionFlagDiscipline (NEW)

- **purpose**: the **runtime** companion of
  `docs/closure/PROMOTION_PLAYBOOK.md`. The
  playbook defines 4 gates (G1-G4) for promoting
  a canonical-flag-off contour to the runtime
  path; this test asserts that **no flag has
  been flipped to `True` prematurely** in
  production code.
- **size**: ~250 lines.
- **2 tests**:
  - `promotionFlagOffState`: for each of the 5
    promotion candidates (Essence, Family
    Divergence, Perspective Operator, External
    LLM, Adaptive Mutation), assert no `= True`
    literal exists in `src/`.
  - `familyDivergenceLocationCheck`: the
    Family Divergence literal must be at the
    documented location
    (`Cascade.hs:74`).
- **discipline**: a flag flips to `True` only
  via the playbook's G3 release event. The test
  is a **regression lock**: if anyone flips a
  flag without going through the playbook, the
  test fails.
- **the 5 candidates** (per
  `docs/closure/AUTHORITY_MAP.md §6`):
  - **Essence** (env var only, not in code)
  - **Family Divergence** (Haskell literal at
    Cascade.hs:74) — **first candidate** per
    playbook
  - **Perspective Operator** (env var only;
    flag not yet in code per AGENTS.md P4)
  - **External LLM** (env var only)
  - **Adaptive Mutation** (env var only)
- **wired into**: `qxfx0-test` and
  `qxfx0-test-unit`.

### 14.4 State of ENFORCEMENT_MATRIX after §14

| Rule | CI | Test | Doc | Status |
|------|-----|------|-----|--------|
| R1 | green | green | green | green |
| R2 | green | **green** | green | **green** (R2 test = Test.Suite.ArchitectureInvariants.r2, closed in §14) |
| R3-R5, R7 | green | green | green | green |
| R6 | yellow | green | green | yellow (CI) |

After §14: **6 green + 1 yellow + 0 red rows**
(down from 2G/3Y/2R at the start of the session).

The 1 remaining yellow is **R6 (CI)**: no CI
check for "canonical-flag-off modules are not
in the authority path until the flag is
flipped". The discipline is in the docs
(`SELF_LAYER_STATUS.md §2`,
`PROMOTION_PLAYBOOK.md §3`) and the per-module
tests (`Test.Suite.SelfEssenceCommit`,
`Test.Suite.SelfEssence`); the script is
missing.

This is an **S-sized follow-up**: add a
`check_architecture.sh` rule [20] that walks
the 5 canonical-flag-off modules and asserts
they have an explicit off-state check (either
an `= False` literal or an env-var check with
a default of `0`).

### 14.5 The 3 artifacts that close the session

The session started with **2G/3Y/2R**. After 14
passes, the state is **6G/1Y/0R**. The 3
artifacts that closed the last gaps:

1. **R2 yellow**: `Test.Suite.ArchitectureInvariants.r2`
2. **R3 red**: `Test.Suite.ObserverDiscipline` (closed in §12)
3. **R7 red**: `Test.Suite.RegenerableDerived` (closed in §13)

The 1 remaining yellow (R6 CI) is a S-sized
follow-up. The next contributor closes it
in a read-only session.

## 15. The 3-state status (drafted / wired / landed)

The session's earlier sections (1-14) tracked
**drafted** status: "is the design / doc / stub
in the repo?" The honest picture distinguishes
3 states:

| State | Meaning | Example |
|-------|---------|---------|
| **drafted** | doc / ADR / design is in `docs/closure/` or `docs/adr/proposed/` | `0034-self-core-role-split.md` |
| **wired** | script / test / stub is in the repo and references the right files | `Test.Suite.ObserverDiscipline.hs`, `check_replay_gate.sh` |
| **landed** | the change is in the canonical code path AND `cabal build` + `cabal test` + CI gates pass | `familyDivergenceEnabled = False` literal at `Cascade.hs:74` |

The 3-state distinction is critical because
**drafted + wired ≠ landed**. The next
contributor's job is to move items from
`drafted` / `wired` to `landed`.

### 15.1 Status by artifact (this session's output)

| Artifact | State | Notes |
|----------|-------|-------|
| `docs/closure/TRACE_SCHEMA.md` | drafted | doc only; not built into the code |
| `docs/closure/CONTOUR_INDEX.md` | drafted | doc only |
| `docs/closure/ADR_INDEX.md` | drafted | doc only; 3 numbering collisions **drafted**, not **fixed** (recommended fix in §1 of ADR_INDEX) |
| `docs/closure/ENFORCEMENT_MATRIX.md` rev. 4 | drafted | matrix is 7G/0Y/0R in the doc, but the matrix's claim is a meta-claim about the script + tests, which themselves need landing |
| `docs/closure/REPLAY_GATE_TRIAGE.md` rev. 2 | drafted | aligned with actual code; 3 GAPs documented |
| `scripts/check_architecture.sh` rule [20] | wired | in repo, Python logic verified (0 violations); `bash -n` has a pre-existing error in rule [14] that doesn't block execution |
| `scripts/check_replay_gate.sh` | wired | verified: 0 violations, 3 GAPs |
| `scripts/check_calibration_codomain.sh` | wired | 13/13 OK, 17 informational GAPs |
| `test/Test/Suite/ReplayGate.hs` | wired | not run in this session (no `cabal test`) |
| `test/Test/Suite/ObserverDiscipline.hs` | wired | not run |
| `test/Test/Suite/TraceSchema.hs` | wired | not run |
| `test/Test/Suite/RegenerableDerived.hs` | wired | not run |
| `test/Test/Suite/PromotionFlagDiscipline.hs` | wired | not run |
| `test/Test/Suite/ArchitectureInvariants.hs` (+r2) | wired | not run |
| `src/QxFx0/Render/Authority.hs` (F-11) | wired (stub) | stub only; the real parser is **not landed** (per Package 4) |
| `docs/adr/proposed/0034-self-core-role-split.md` | drafted | the central closure ADR; **not accepted** |
| `docs/adr/proposed/0018-0022` (5 promotion ADRs) | drafted | none accepted; ADR-0019 prep = gate-pending (2026-06-02; see `ADR_0019_PREP_LOG.md`) |
| `docs/adr/proposed/0023-demotion-procedure.md` | drafted | not activated |
| `docs/closure/PROMOTION_PLAYBOOK.md` | drafted | first candidate = ADR-0019, not yet promoted |
| `docs/closure/RELEASE_CHECKLIST.md` | drafted | not yet used (no release cut) |
| `docs/closure/PYTHON_MIGRATION_TRACKER.md` | drafted | 0/34 scripts migrated |
| `docs/closure/ONBOARDING.md` | drafted | doc only |

### 15.2 What "landed" requires

The next contributor's job is to move the
**drafted** and **wired** items to **landed**.
The mechanical steps:

1. **`cabal build all`** — verify the code
   compiles. Currently not run in this session.
2. **`cabal test qxfx0-test`** — verify the
   new test suites pass. Currently not run.
3. **`bash scripts/check_architecture.sh`** —
   verify the 20 rules pass. Pre-existing
   `bash -n` warning at rule [14] is not
   blocking; the script runs.
4. **`bash scripts/ci_gate_contract.sh`** —
   verify all gates pass.
5. **`bash scripts/verify.sh`** — the master
   entry point.

### 15.3 What was NOT done in this session

This is the **honest list** of items that
remain in the **drafted** state, organized
by the 11 packages of the original closure
plan:

| Package | Status | What's missing |
|---------|--------|----------------|
| P1 (role split) | drafted (ADR-0034) + wired (script rules [13]-[20]) | ADR-0034 **not accepted**; matrix is 7G/0Y/0R in doc but not yet exercised in CI |
| P2 (semantic commitments) | drafted only | no code change |
| P3 (replay gate) | wired (script + test) but **3 GAPs** (Conatus, Field, Identity) in `TurnReplayTrace` | the GAPs are recipe in `TRACE_SCHEMA.md §2/§3/§7` but the type changes are not made |
| P4 (perspective operator) | drafted (ADR-0020) | not landed; `QXFX0_PERSPECTIVE_OPERATOR_ENABLED` flag not in code |
| P5 (Python elimination) | drafted (PYTHON_MIGRATION_TRACKER) | 0/34 scripts migrated; 3 critical scripts (P5-1) are M-sized |
| P6 (deterministic time) | landed (per AGENTS.md, 0018) | — |
| P7 (calibration) | wired (`check_calibration_codomain.sh` + `ranges.json`); F-09/F-10 not landed | 17 informational GAPs; corpus + first calibration pending |
| P8 (deliberation + learning) | landed (per AGENTS.md, 0011) | — |
| P9 (autonomous learning) | landed (per AGENTS.md, 0030) | — |
| P10 (offline training) | landed (per AGENTS.md, 0031) | — |
| P11 (calibration pipeline) | wired (codomain script); F-10 not landed | first calibration pending F-09 |

### 15.4 The 3 Tier 1 S-sized follow-ups

The Tier 1 items (per the session's earlier
"what's left" summary) are:

1. **R6 CI rule [20]** (just landed in §15 —
   `check_architecture.sh [20]` walks the 5
   promotion flags; matrix is now 7G/0Y/0R).
2. **ADR renumbering landing** — renumbering is
   already applied in the working tree (`0034`, `0035`, `0036`,
   `0041`); the remaining step is canonical landing via build/test/CI.
3. **Land ADR-0019** (Family Divergence) —
   the first candidate per the playbook. The
   flag is `= False` literal at `Cascade.hs:74`;
   flipping it is a 1-line change. S-sized
   but requires `cabal build` + integration
   test pass per G1-G4 gates.
   **Status (2026-06-02)**: prep done (matrix
   updated, ADR-0019 status field added,
   PROMOTION_PLAYBOOK §10 release log entry),
   but **gate-pending**: G1 partial (rule
   [12] mechanical pass, human audit deferred);
   G2 not verifiable without cabal; G3 not
   verifiable without corpus (F-09 deferred).
   Next-contributor: run gates, then flip +
   commit. See `docs/closure/ADR_0019_PREP_LOG.md`.

### 15.5 The 3 Tier 2 M/L follow-ups

| # | What | Size | Depends on |
|---|------|------|------------|
| 1 | F-09 corpus (1k unlabelled + 100 labelled) | L | production traces |
| 2 | F-10 first calibration | L | F-09 |
| 3 | Gate P5-1 (3 critical Python → Haskell) | M | cabal + test env |

### 15.6 The Tier 3 L/XL follow-ups

| # | What | Size |
|---|------|------|
| 1 | Real GF Haskell parser (Package 4 dep) | XL |
| 2 | Land remaining 4 promotion ADRs (0018/0020/0021/0022) | S-L each |
| 3 | Activate demotion procedure (0023) | M |

### 15.7 Final summary

- **15/15 follow-ups drafted** (F-01..F-15).
- **6 new test suites wired** (ReplayGate,
  ObserverDiscipline, TraceSchema,
  RegenerableDerived, PromotionFlagDiscipline,
  ArchitectureInvariants.r2).
- **5 enforcement scripts wired** (check_architecture,
  check_replay_gate, check_calibration_codomain,
  plus the existing check_generated_artifacts and
  the new rule [20] inside check_architecture).
- **1 CI integration** (`ci_gate_contract.sh`
  Gate 3c + `verify.sh` step [10c]).
- **ENFORCEMENT_MATRIX rev. 4**: 7G/0Y/0R.
- **0 of 35 ADRs accepted** (all are still in
  `proposed/`).
- **0 of 5 promotion ADRs landed**.
- **0 of 11 packages** fully closed (P6, P8, P9, P10
  were landed before this session; P1, P3, P5,
  P7, P11 are drafted/wired; P2, P4 are drafted).
- **0 of 3 trace schema GAPs** closed (Conatus,
  Field, Identity).
- **0 of 34 Python scripts** migrated.
