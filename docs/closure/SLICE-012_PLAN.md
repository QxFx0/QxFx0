# SLICE-012 Plan — Guard / Nix / GF Environment Contract

Status: Open (plan only; no code changes yet)
Date: 2026-06-17
Origin: `audit-objective-2026-06-17.md §3` (stale-evidence inadmissibility)
Predecessor: ESSENCE-REGIME-RECONCILE (committed `74d2174`)

## Purpose

Make "governed, checked conditions" **provable in real runs**, not just in
tests that fake the guard. The audit found that M6 felt-evidence
(`reports/ab_dialogue/ab-eval-2026-05-21`) was collected with
`guard_status: Unavailable — nix evaluator unavailable` on every turn, and
that the M6 witness suites (`M6Witness`, `M5Regime`) do not run the runtime
at all, while `StatePersistence` uses `withStrictRuntimeEnv` which fakes
nix via `withFakeNixInstantiateOk` (a shell script that prints `true`).

This front **classifies** the environment contract and **separates** three
failure classes. It does not fix morphology (SLICE-010B/015) and does not
upgrade M6-FELT.

## Scope boundaries (operator constraints)

- **Do NOT** fix the morphology resource contract (`forms_by_surface.json`,
  `RcMorphology NotReady`). That is SLICE-010B/015.
- **Do NOT** touch M6-FELT.
- **Do NOT** change runtime doctrine without a separate decision.
- **DO** separate local-env limitation from CI-env from release-blocking.

---

## 1. The guard/nix/GF environment contract — current state

### 1.1 Nix constitutional guard

- **Code**: `src/QxFx0/Bridge/NixGuard.hs`
  - `checkConstitution nixPath concept agency tension` imports a concepts
    file (`nixPath`) and evaluates a nix expression checking
    `concept.minAgency` / `concept.minTension`.
  - `runNixInstantiate restricted nixExpr` calls
    `readProcessWithExitCode "timeout" [5, nixInstantiateBin, --restricted?, --eval, --expr, …]`.
  - Binary resolved via `lookupEnv "QXFX0_NIX_INSTANTIATE_BIN"` (default
    `"nix-instantiate"`).
  - On any failure → `Unavailable "nix evaluator unavailable: …"`.
  - `isLenientMode` (`QXFX0_NIXGUARD_LENIENT_UNSUPPORTED=1`) → unsupported
    concepts return `Unavailable "…skipped"` instead of `Blocked`.

- **Concepts data**: `semantics/concepts.nix` (tracked). Runtime needs its
  path via `QXFX0_CONCEPTS_PATH` (flake sets `/data/concepts.nix`; CI does
  **not** set it in the workflow env; local does **not** set it).

- **Downstream effect of `Unavailable`** (verified this audit):
  - `Prepare/Build.hs:101-103`: `Unavailable → nixAvailable=False`,
    `isNixBlocked=False`.
  - `Cascade.hs:123`: only `isNixBlocked` forces `CMRepair`; `Unavailable`
    does **not**.
  - `Route/Build.hs:292`: `not tiNixAvailable → ExplicitFallbackSurface`
    (authority surface downgraded), but the turn still emits output.
  - `docs/fallback_policy_classification.md:86`: classified
    **fail-open degraded** — "turn continues with blocked guard status …
    not fail-closed in prepare stage".

### 1.2 GF / morphology environment

- **GF**: `gf 3.12` present locally; CI builds GF C runtime from source
  (`ci.yml:63-86`, pins `gf-core@1c086bed…`). `QXFX0_GF_RUNTIME=1`,
  `LIBRARY_PATH`/`C_INCLUDE_PATH`/`LD_LIBRARY_PATH` set in CI.
- **Morphology**: `forms_by_surface.json` (125 MB) was removed from git
  history (`execution_board.md` 2026-06-17). CI regenerates via
  `python3 scripts/export_lexicon.py` (`ci.yml:110-114`). **Local does
  not**, so `RcMorphology = NotReady` → bootstrap gate fail-closed →
  **no fresh runtime turn can run locally** (confirmed this audit:
  `Bootstrap readiness gate failed … [RcMorphology]`).

### 1.3 Test environment faking

- `withFakeNixInstantiateOk` (`test/Test/Support.hs:104-116`): writes a
  shell script that prints `true`, prepends it to `PATH`, sets
  `QXFX0_NIX_INSTANTIATE_BIN` to it. Result: guard always `Allowed`.
- `withFakeSouffle`: analogous for the Datalog shadow.
- `withStrictRuntimeEnv` uses both fakes; `withRuntimeEnv` (degraded) uses
  neither and sets `QXFX0_RUNTIME_MODE=degraded`.
- `M6Witness` / `M5Regime`: **do not run the runtime** (grep-confirmed) —
  they assert pure types/trace-fields, so they are guard-agnostic.

---

## 2. Three failure classes — the separation

### Class L — Local-env limitation (NOT release-blocking, NOT SLICE-012's target)

| Item | Status | Owner |
|---|---|---|
| `RcMorphology NotReady` locally (no `forms_by_surface.json`) | blocks fresh local runtime runs | **SLICE-010B/015** — explicitly out of SLICE-012 |
| `QXFX0_CONCEPTS_PATH` unset locally | nix guard cannot find concepts file | SLICE-012 candidate (env contract) |
| `nix-instantiate --restricted` unsupported on nix 2.34.6 | `isRestrictedFlagUnsupported` fallback to unrestricted works, but is the old API | SLICE-012 candidate (compat) |

These are **local developer friction**, not evidence-integrity issues.
SLICE-012 addresses only the ones that affect evidence validity.

### Class C — CI-env (the intended governed environment)

| Item | Status | SLICE-012 action |
|---|---|---|
| CI regenerates morphology (`export_lexicon.py`) | ✅ present | verify it actually runs in CI; no action expected |
| CI installs nix (`cachix/install-nix-action@v25`) | ✅ present | verify nix-instantiate is on PATH in CI |
| CI sets `QXFX0_CONCEPTS_PATH`? | **❓ not found in workflow** | **SLICE-012 must verify**: if unset, CI guard is also `Unavailable` — meaning **even CI evidence is ungoverned** |
| CI runs guard-dependent tests with real nix? | **❓ unknown** — `withStrictRuntimeEnv` fakes nix | **SLICE-012 must establish**: is there *any* CI path that runs the real nix guard? |

This is the **core of SLICE-012**: determine whether the intended governed
environment (CI) actually runs the guard for real, or whether CI also fakes
it. If CI fakes too, then **no evidence anywhere was collected under
governed conditions**, which is the audit's §3 finding generalized.

### Class R — Release-blocking guard failure (the doctrine question)

| Item | Status | SLICE-012 action |
|---|---|---|
| Guard `Unavailable` is `fail-open degraded` (turn proceeds) | current doctrine | **SLICE-012 raises the doctrine question, does not decide it**: should `Unavailable` be fail-closed for evidence-collection runs? I.e., should a turn whose guard was `Unavailable` be **ineligible** as M6 evidence, even if it produced output? |
| Guard `Unavailable` stamps `trcNixStatus` but no evidence gate checks it | verified | **SLICE-012 candidate**: an evidence-collection mode that refuses to emit evidence when `guard ≠ Available`. This is the missing gate. |
| `M6Witness`/`M5Regime` don't assert guard availability | verified | **SLICE-012 candidate**: add a witness assertion that evidence-citation tests either (a) use `withStrictRuntimeEnv` (faked, labelled as such) or (b) run real guard and assert `Available`. |

Class R is a **doctrine decision**, not a code fix. SLICE-012 surfaces it;
the operator decides whether `Unavailable = inadmissible evidence` becomes
a release-blocking rule.

---

## 3. Specific findings this audit (read-only)

1. **`nix-instantiate --restricted` is unsupported on nix 2.34.6**
   (local). `--restricted` is the legacy flag; modern nix uses
   `--option restricted true` or `nix eval`. The code's
   `isRestrictedFlagUnsupported` fallback handles this, but the fallback
   path is **unrestricted eval** — a security downgrade. Not release-blocking,
   but worth noting in the contract.

2. **`QXFX0_CONCEPTS_PATH` is unset in CI workflows** (grep-confirmed in
   `ci.yml` / `ci-fast.yml`). If the runtime needs it and CI doesn't set
   it, CI guard is also `Unavailable`. **This is the single most important
   thing SLICE-012 must verify** — it determines whether Class C is clean
   or broken.

3. **`withFakeNixInstantiateOk` prints `true` unconditionally** — it does
   not model `Blocked`. So tests that use it never exercise the
   `Blocked → CMRepair` path under real guard semantics. The
   `PromotionFlagDiscipline` / admission tests are pure; the
   `StatePersistence` strict tests run under faked-`Allowed`.

4. **Fresh local runtime run is impossible** due to `RcMorphology`
   (SLICE-010B). This means SLICE-012 **cannot locally verify** any
   real-guard behavior; it must rely on CI or on a morphology-regenerated
   local env. SLICE-012 should document this dependency explicitly.

---

## 4. SLICE-012 deliverables (proposed, pending operator approval)

1. **CI contract audit** (read-only): does CI set
   `QXFX0_CONCEPTS_PATH`? Does any CI test run the real nix guard (not
   faked)? Produce a one-page verdict: "CI evidence is governed" or
   "CI evidence is also ungoverned".
2. **Environment contract document**: `docs/closure/ENV_CONTRACT.md`
   declaring the required env vars for governed evidence
   (`QXFX0_CONCEPTS_PATH`, `QXFX0_NIX_INSTANTIATE_BIN`, nix on PATH,
   morphology regenerated, GF runtime). Distinguish:
   - **governed-evidence env** (all must be present + guard `Available`)
   - **degraded-dev env** (local, guard may be `Unavailable`, output
     produced but **labelled inadmissible as evidence**)
3. **Evidence-admissibility rule** (doctrine proposal, not a code change):
   a turn whose `trcNixStatus /= Available` is **ineligible** as M6
   evidence. Surface as a documented rule in `M6_DECLARATION.md §3` (a
   new row in the C1–C4 tables: "guard availability"). The operator
   decides whether to accept this as release-blocking.
4. **Witness test gap** (test-only, if approved): add an assertion to
   the M6 witness regime that evidence-citation tests declare their guard
   mode (faked-`Available` via `withStrictRuntimeEnv`, or real-`Available`).
   This makes the stale-evidence-inadmissibility **mechanically visible**
   rather than implicit.

## 5. Out of scope (explicit)

- Morphology resource contract (`forms_by_surface.json`,
  `RcMorphology`) — SLICE-010B/015.
- M6-FELT upgrade.
- Runtime doctrine changes (fail-open → fail-closed for `Unavailable`)
  without a separate operator decision.
- Changing `withFakeNixInstantiateOk` semantics (it is correct for
  unit-testing persistence; the problem is using it for *evidence*
  claims, which SLICE-012 surfaces via labelling, not by breaking the
  fake).

## 6. Open questions for the operator

1. **Q1**: Should SLICE-012 verify the CI contract by actually running a
   CI workflow, or by static reading of `ci.yml` + local reproduction of
   the CI env setup? (CI run requires push/access; static is faster but
   less authoritative.)
2. **Q2**: Is the evidence-admissibility rule ("`Unavailable` guard →
   inadmissible evidence") accepted as doctrine? If yes, SLICE-012
   documents it; if no, SLICE-012 only labels the gap without ruling.
3. **Q3**: Does the operator want a `--governed-evidence` runtime flag
   that **refuses to emit** when guard is `Unavailable` (fail-closed for
   evidence collection), separate from the production fail-open degraded
   path? This would be the mechanical enforcement of Q2.

---

## Appendix A — Toolchain / build-environment contract (from remote `736e471`)

The following sub-scope was pushed in parallel as
`736e471 docs(slice-012): GF/toolchain environment contract`. It is
retained here as part of SLICE-012 since the operator's scope included
"GF environment contract".

### A.1 Current toolchain state

- Local environment: GHC 9.6.7, `base-4.18.3.0`.
- `cabal.project.freeze` pins `base ==4.18.2.1` and core packages from
  GHC 9.6.6 (e.g., `array ==0.5.6.0`, `bytestring ==0.11.5.3`,
  `filepath ==1.4.300.1`, `ghc-boot-th ==9.6.6`, `unix ==2.8.4.0`).
- Result: `cabal` cannot resolve dependencies locally without modifying
  the freeze.
- The `pgf2` Haskell package requires the GF C runtime (`libpgf`,
  `libgu`), which is not installed locally. This blocks the library
  from building even after the freeze is aligned.
- `cabal.project.freeze` is a release/build contract, not a local
  convenience file. It is intentionally not modified in unrelated
  fronts (e.g., SLICE-010B).

### A.2 Toolchain scope

1. Document the intended GHC version and the rationale for the freeze.
2. Document the GF C runtime dependency, including the required system
   packages and how to verify them.
3. Decide whether the freeze should be updated to GHC 9.6.7 or whether
   the intended CI environment should remain on GHC 9.6.6.
4. Separate local env limitations from release-blocking failures:
   - A missing local GF runtime is a local env limitation, not a
     release blocker.
   - A freeze/core-package mismatch is a toolchain contract issue, not
     a runtime bug.
5. Provide a reproducible check (e.g., a script or documented steps)
   that a maintainer can run to verify the toolchain is correctly
   provisioned.

### A.3 Toolchain constraints

- Do not change morphology or runtime logic.
- Do not modify `cabal.project.freeze` without an explicit repo-owner
  decision recorded in this plan.
- Do not track `forms_by_surface.json`.
- Do not run SLICE-010B work inside this front.

### A.4 Toolchain exit criteria

1. Intended GHC version and freeze policy are documented.
2. GF C runtime dependency and verification steps are documented.
3. `cabal.project.freeze` decision is recorded (keep for GHC 9.6.6 or
   update for GHC 9.6.7).
4. `docs/closure/REMAINING_CLOSURE_CHECKLIST.md` and
   `docs/execution_board.md` updated.
