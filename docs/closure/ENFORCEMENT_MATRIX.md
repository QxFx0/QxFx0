# Enforcement Matrix (QxFx0_v3) — boundary rule → check rule → test → doc

- **Status**: Active (closure-phase work product)
- **Date**: 2026-06-02 (rev. 4 — R6 CI yellow closed via `check_architecture.sh` rule [20])
- **Status counts**: 7 green + 0 yellow + 0 red rows
- **Refines**:
  - `docs/adr/proposed/0034-self-core-role-split.md` §3
    (the 7 boundary rules)
  - `docs/closure/AUTHORITY_MAP.md` §7 (the per-rule
    summary)
  - `scripts/check_architecture.sh` rules [1]–[19]
- **Related**:
  - `docs/closure/ONBOARDING.md` §7 (the discipline)
  - `docs/closure/TEST_AUTHORITY_AUDIT.md` (per-test
    classification)

## 0. What this matrix is

The closure plan's ADR-0034 §3 has 7 boundary rules.
The plan's enforcement is **mechanical** (where
possible) and **declarative** (where mechanical
enforcement is impractical). The CI script
`scripts/check_architecture.sh` has 19 rules; the
mapping from ADR-0034 §3's 7 rules to the CI rules
is implicit. This matrix makes the mapping explicit
and adds the **test** and **doc** columns, so the
discipline is visible end-to-end.

A row is **green** when the CI check passes and the
test exists. A row is **yellow** when the CI check
is in place but the test is a placeholder. A row is
**red** when neither is in place (a gap).

## 1. The matrix

| ADR-0034 rule | CI check | Test | Doc | Status |
|---|---|---|---|---|
| **R1** — `Self/*` is canonical-only; no downward writes to `Core.TurnPipeline.*` or `Bridge.*` | `check_architecture.sh` [13] (import ban) + [17] (Haddock role declaration) | `Test.Suite.SelfEssence`, `Test.Suite.SelfPerspective` (per AGENTS.md P4) | `AUTHORITY_MAP.md §3.1`, `SELF_LAYER_STATUS.md §2` | green |
| **R2** — `Core/*` supplier modules must not import canonical-orchestrator writers | `check_architecture.sh` [14] (Haddock role + import check) | `Test.Suite.ArchitectureInvariants.r2SupplierDoesNotImportOrchestrator` (closed 2026-06-02) | `AUTHORITY_MAP.md §3.2` | green |
| **R3** — `Core/*` observer modules emit into trace only | `check_architecture.sh` [19] (Observability + Haddock `observer`) | `Test.Suite.ObserverDiscipline` (textual check, closed 2026-06-02) | `AUTHORITY_MAP.md §3.3` | green |
| **R4** — `Render/*` is the only outbound text producer | `check_architecture.sh` [18] (heuristic: `render*` / `build*` functions import the orchestrator) | `Test.Suite.RenderDialogueCoverage` (per `TEST_AUTHORITY_AUDIT.md`) | `GF_AUTHORITY_SUBSET.md §2` | green (heuristic); green (test) |
| **R5** — `Bridge.ExternalLLM` is the only authority-bearing supplier that is opt-in by feature flag | `check_architecture.sh` [15] (Bridge `QXFX0_*_ENABLED` allowlist) | `Test.Suite.RenderAuthorityStub` (per F-11) | `ADR-0021` (LLM promotion), `AUTHORITY_MAP.md §6` | green |
| **R6** — `canonical-flag-off` modules are not in the authority path until the flag is flipped | `check_architecture.sh` [20] (5 promotion flags must not have `= True` literal in `src/`; Family Divergence must be at `= False`) | `Test.Suite.SelfEssenceCommit`, `Test.Suite.SelfEssence`, `Test.Suite.PromotionFlagDiscipline` (closed 2026-06-02) | `SELF_LAYER_STATUS.md §2`, `PROMOTION_PLAYBOOK.md §3` | green |
| **R7** — Derived modules must remain regenerable | `check_architecture.sh` [16] (heuristic: `*Generated.hs` has a generator in `scripts/`) + `check_generated_artifacts.sh` (full script) | `Test.Suite.RegenerableDerived` (closed 2026-06-02) | `AUTHORITY_MAP.md §3.5` | green |

The matrix is a **discipline map**, not a **test
plan**. A green row means the discipline is in place
across all four columns; a yellow row means the
discipline is in place in 2–3 columns; a red row
means a gap.

## 2. The non-R rules

The 12 rules in `check_architecture.sh` that are
**not** in ADR-0034 §3 are the freeze-0 rules
(`AUTHORITY_BOUNDARY.md §4`) and the runtime
perimeter rules (`ci_gate_contract.sh`).

| CI check | Source | What it enforces |
|---|---|---|
| [1] | Freeze-0 | `Types/*` must not import `Core/Bridge/Semantic`. |
| [2] | Freeze-0 | `Semantic/*` must not import `Bridge/Core/Runtime`. |
| [2b] | Freeze-0 | `Render/*` must not import `Core/Bridge/Runtime`. |
| [3] | Freeze-0 | `Bridge/*` must not hardcode spec paths. |
| [4] | Freeze-0 | `Core/*` must not import `Bridge` or `Runtime`; `Bridge/*` must not import `Core`. |
| [4b] | Freeze-0 | `Runtime/*` must not import top-level `QxFx0.Core` aggregator. |
| [5] | Freeze-0 | No `SomeException` in `Bridge/Semantic/Core/Resources/app`. |
| [6] | Freeze-0 | No partial `read` in source. |
| [7] | Freeze-0 | No bare `head/tail/init/last`. |
| [8] | Freeze-0 | No bare `fail` in IO context. |
| [8b] | Freeze-0 | No raw `userError`. |
| [9] | Freeze-0 | Runtime code must import templates from `Policy`, not `Lexicon`. |
| [10] | Runtime | `EmbeddedSQL.hs` must be in sync with `spec/sql`. |
| [10b] | Runtime | HTTP perimeter invariants (bind, auth, input, script, embedding). |
| [10c] | Runtime | Acceptance gates reflect local-recovery architecture. |
| [11] | Runtime | Exposed `QxFx0.Core.*` modules must be reachable from `Runtime/TurnPipeline`. |
| [12] | ADR-0008 | Pipeline call sites must access `Holistic/Formal` only through `Self.Adjunction`. |

These 17 rules are **out of scope** for this matrix
(they are the freeze-0 and runtime-perimeter
discipline, not the role-split discipline). The
matrix above covers the **7 role-split rules** of
ADR-0034 §3.

## 3. The gaps

The matrix has 0 yellow and 0 red rows (rev. 4,
2026-06-02). The matrix is **fully green**:
**7G/0Y/0R**.

This is the **end state** for the R1-R7
discipline. The next contributor's job is
**land** the items marked "drafted" in
`FOLLOWUPS.md §15` (the 3-state status section),
not to add more rules.

### Rev. 4 closure log

| Rule | Closed by | When |
|------|-----------|------|
| R3 (test) | `Test.Suite.ObserverDiscipline` | §12 (2026-06-02) |
| R7 (test) | `Test.Suite.RegenerableDerived` | §13 (2026-06-02) |
| R2 (test) | `Test.Suite.ArchitectureInvariants.r2SupplierDoesNotImportOrchestrator` | §14 (2026-06-02) |
| R6 (CI) | `check_architecture.sh` rule [20] | §15 (2026-06-02) |

## 5. The discipline

The discipline of this matrix is:

- **Every rule has 4 columns.** A row that is
  missing a column is a **gap**, not a
  **redundancy**.
- **The matrix is regenerated** at every release.
  A rule that is no longer enforced (e.g. the
  flag-off module has been promoted) is marked
  as `closed` in the matrix and the CI check is
  removed.
- **The matrix is the discipline map.** The
  test plan is the `Test.Suite.*` directory;
  the CI plan is `check_architecture.sh`; the
  doc plan is `docs/closure/`. The matrix is
  the **join**.

## 6. Acceptance criteria for this matrix

This matrix is **closed** when:

- [ ] Every ADR-0034 §3 rule has all 4 columns
      filled (CI, test, doc, status).
- [ ] The 3 yellow rows (R2 test, R3 test, R7
      test) are closed (per §4).
- [ ] The 2 red rows (R3 test, R7 test) are
      closed (per §4).
- [ ] The non-R rules (§2) are mapped to their
      source (Freeze-0 / Runtime).

The matrix is **deferred** until all 4 criteria
are met.
