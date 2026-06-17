# SLICE-012 Plan: GF/Toolchain Environment Contract

Status: OPEN  
Owner: agent  
Branch: `slice-012-toolchain-contract`  

## Goal

Define and document the intended development/CI toolchain for the fast unit gate (`cabal test qxfx0-test-fast`) so that local environment limitations are clearly separated from release-blocking failures. This front does **not** change morphology or runtime logic; it only fixes the build environment contract.

## Current state

- Local environment: GHC 9.6.7, `base-4.18.3.0`.
- `cabal.project.freeze` pins `base ==4.18.2.1` and core packages from GHC 9.6.6 (e.g., `array ==0.5.6.0`, `bytestring ==0.11.5.3`, `filepath ==1.4.300.1`, `ghc-boot-th ==9.6.6`, `unix ==2.8.4.0`).
- Result: `cabal` cannot resolve dependencies locally without modifying the freeze.
- In addition, the `pgf2` Haskell package requires the GF C runtime (`libpgf`, `libgu`), which is not installed locally. This blocks the library from building even after the freeze is aligned.
- `cabal.project.freeze` is a release/build contract, not a local convenience file. It is intentionally not modified in unrelated fronts (e.g., SLICE-010B).

## Scope

1. Document the intended GHC version and the rationale for the freeze.
2. Document the GF C runtime dependency, including the required system packages and how to verify them.
3. Decide whether the freeze should be updated to GHC 9.6.7 or whether the intended CI environment should remain on GHC 9.6.6.
4. Separate local env limitations from release-blocking failures:
   - A missing local GF runtime is a local env limitation, not a release blocker.
   - A freeze/core-package mismatch is a toolchain contract issue, not a runtime bug.
5. Provide a reproducible check (e.g., a script or documented steps) that a maintainer can run to verify the toolchain is correctly provisioned.

## Constraints

- Do not change morphology or runtime logic.
- Do not modify `cabal.project.freeze` without an explicit repo-owner decision recorded in this plan.
- Do not track `forms_by_surface.json`.
- Do not run SLICE-010B work inside this front.
- Do not add Python pre-test steps or other runtime dependencies.

## Evidence / Verification

- Documented contract exists in `docs/closure/SLICE-012_PLAN.md`.
- `docs/execution_board.md` and `docs/closure/REMAINING_CLOSURE_CHECKLIST.md` updated to reflect SLICE-012 as the active front.
- Once the intended CI/dev environment is provisioned, `cabal test qxfx0-test-fast` should run and produce a clean summary except for any genuinely pre-existing failures.

## Exit criteria

1. Intended GHC version and freeze policy are documented.
2. GF C runtime dependency and verification steps are documented.
3. `cabal.project.freeze` decision is recorded (keep for GHC 9.6.6 or update for GHC 9.6.7).
4. `docs/closure/REMAINING_CLOSURE_CHECKLIST.md` and `docs/execution_board.md` updated.
5. Branch fast-forward merged to `origin/main` (only after the contract is accepted by repo-owner).
