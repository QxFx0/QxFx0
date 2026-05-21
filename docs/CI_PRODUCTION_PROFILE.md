# QxFx0 Production CI Profile (Two-Tier Release Model)

**Version:** v2-gf-production-tiered-transferred  
**Date:** 2026-05-09  
**Branch:** `feature/glm-fixes-audit-round1`  
**Baseline:** Transferred from `stabilize-v2-gf`; target evidence pending validation

---

## Two-Tier Release Model

| Tier | Name | When | Runner | Contract Verdict | Gates |
|------|------|------|--------|------------------|-------|
| **Core** | Production Contract | Every push / PR | `ubuntu-latest` (16 GB) | `PROD_GO` | Build, fast tests, architecture, GF quality, haddock, SQL sync, schema consistency/contract, generated artifacts, lexicon, release-smoke degraded-local |
| **Extended** | Full Scientific Contract | Nightly/weekly + manual dispatch + `main` only | High-mem (>=32 GB) | `FULL_SCIENTIFIC_GO` | Core gates + slow tests, coverage >=51%, release-smoke strict (ACCEPT + Failed=0, no skips) |

**Rule:** `FULL_SCIENTIFIC_GO` implies `PROD_GO` already passed. The extended tier is a superset, not an alternative.

---

## Runner Requirements

### Core Contract Runner (PROD_GO)

| Resource | Minimum | Notes |
|----------|---------|-------|
| OS | Ubuntu 22.04/24.04 LTS | Or equivalent Linux x86_64 |
| RAM | 8 GB | For `cabal build all` + fast tests |
| Disk | 20 GB | Cabal store + build artifacts |
| Timeout | 25 min | Per job |
| GHC | 9.6.6 | `haskell-actions/setup@v2` |
| Cabal | 3.10.3.0 | Bundled with GHC action |
| Python | 3.10+ | For schema/lexicon scripts |
| SQLite | 3.x | `libsqlite3-dev` |

### Extended Contract Runner (FULL_SCIENTIFIC_GO)

| Resource | Production | Notes |
|----------|------------|-------|
| OS | Ubuntu 24.04 LTS | x86_64 |
| RAM | **32 GB** | Slow tests + coverage + strict smoke peak at ~16-20 GB |
| Disk | 40 GB | Full nix store + cabal store + HPC artifacts |
| Timeout | **45 min** | Extended contract needs ~30-40 min with warm cache |
| GHC | 9.6.6 | With `-rtsopts` for `+RTS -M16G -RTS` |
| Cabal | 3.10.3.0 | |
| Nix | 2.18+ | `cachix/install-nix-action@v25` |
| Agda | 2.6.4+ | Via nix or `apt-get install agda agda-stdlib` |
| GF | 3.11+ | Via nix or `apt-get install gf` |
| Soufflé | 2.4+ | `apt-get install souffle` |
| spaCy + ru_core_news_sm | 3.7+ | `python -m spacy download ru_core_news_sm` |
| pgf2 Haskell lib | 1.3 | Links against `libpgf.so.0` / `libgu.so.0` |

---

## Environment Variables

### Required (both tiers)

| Variable | Value | Purpose |
|----------|-------|---------|
| `QXFX0_ROOT` | `${{ github.workspace }}` | Project root for runtime scripts |
| `LD_LIBRARY_PATH` | `/tmp/gf-install/usr/lib` | Runtime linking for `pgf2` Haskell package |
| `QXFX0_CABAL_LOCK_FILE` | `/tmp/qxfx0-cabal.lock` | Prevents concurrent cabal races |

### Profile-specific

| Variable | Core default | Extended default | Purpose |
|----------|--------------|------------------|---------|
| `QXFX0_CONTRACT_PROFILE` | `core` | `extended` | Selects contract tier in `ci_gate_contract.sh` |
| `QXFX0_RUN_SLOW_TESTS` | `0` | `1` | Enable slow test suite |
| `QXFX0_ENABLE_COVERAGE_GATE` | `0` | `1` | Enable HPC coverage threshold gate |
| `QXFX0_REQUIRE_STRICT_RUNTIME` | `0` | `1` | Enforce strict runtime readiness |
| `QXFX0_RELEASE_SMOKE_MODE` | `degraded-local` | `strict` | Smoke test mode |
| `QXFX0_SKIP_AGDA` | `1` (implied) | `0` | Run Agda typecheck |
| `QXFX0_GF_RUNTIME` | `1` | `1` | Enable GF primary render path |
| `QXFX0_SHARED_CABAL_STORE` | `~/.cabal/store` | `~/.cabal/store` | Shared cabal store for parallel jobs |

---

## Job Orchestration

### Job 1: Core Contract (`core-contract`)

**Trigger:** push, pull_request, manual dispatch with `profile=core`  
**Runner:** `ubuntu-latest` (8 GB sufficient)  
**Timeout:** 25 minutes  
**Contract verdict target:** `PROD_GO`

**Steps:**
1. Checkout
2. Setup Haskell (GHC 9.6.6, Cabal 3.10)
3. Cache cabal store + dist-newstyle
4. Install Python deps
5. `bash scripts/ci_gate_contract.sh` (profile=core, includes `check_gf_render_path.sh`)

**Semantics:**
- `release-smoke.sh` runs in `degraded-local` mode.
- `ACCEPT_WITH_SKIPS` is **allowed** for infra-only skips (e.g., nix/souffle unavailable).
- Any `FAIL` → contract `REJECT`.

**Artifacts:**
- `core-gate-logs-{run_id}` → `reports/baseline_v2/final_gates/_gate_results_*.md`

### Job 2: Extended Contract (`extended-contract`)

**Trigger:**
- Schedule: weekly cron (`0 2 * * 1`)
- Manual dispatch with `profile=extended`
- Push to `main` branch only

**Runner:** `ubuntu-latest` with high-mem label (>=32 GB)  
**Timeout:** 45 minutes  
**Depends on:** `core-contract` (must pass first)  
**Contract verdict target:** `FULL_SCIENTIFIC_GO`

**Steps:**
1. Checkout
2. Setup Haskell (GHC 9.6.6, Cabal 3.10)
3. Cache cabal store + dist-newstyle (warm from core job)
4. Install Python deps + spaCy model
5. Install system deps (`agda`, `gf`, `souffle`, `libsqlite3-dev`)
6. Install Nix
7. `bash scripts/ci_gate_contract.sh` (profile=extended)

**Semantics:**
- `release-smoke.sh` runs in `strict` mode.
- `ACCEPT_WITH_SKIPS` is **NOT allowed** — any skip → `REJECT`.
- Slow tests are **hard required**; INFRA (timeout/OOM) → honest `REJECT` with reason.
- Coverage >= 51% is **hard required**; INFRA → honest `REJECT`.

**Artifacts:**
- `extended-gate-logs-{run_id}` → `reports/baseline_v2/final_gates/_gate_results_*.md` + `.tsv`

### Job 3: Granular Fast Gates (`build-test`)

**Trigger:** push, pull_request (legacy, kept for PR step visibility)  
**Runner:** `ubuntu-latest`  
**Timeout:** 15 minutes  

**Steps:** Individual cabal build/test steps + architecture/lexicon/haddock checks.

**Note:** This job is redundant with `core-contract` but provides per-step failure visibility in PR checks. It does **not** run `ci_gate_contract.sh`.

---

## Coverage Configuration

The `vector` package (dependency) uses internal libraries which conflict with GHC's program coverage when per-component builds are enabled.

**Option A (recommended for production):**
Use `cabal` 3.12+ which may handle `--enable-coverage` with internal libraries more gracefully. If unavailable, use:

```bash
# Fresh build with coverage only on qxfx0 package
cabal configure --enable-coverage --disable-optimization
cabal build all --keep-going
cabal test qxfx0-test --enable-coverage
```

**Option B (fallback):**
If coverage build still fails, run coverage in a nix shell with patched cabal or use `--ghc-option=-fno-profiling` to reduce build overhead.

**Option C (last resort):**
Measure coverage locally on a machine with more RAM and commit the `.tix` + report as an artifact. The CI job validates the committed report is newer than the source commit.

---

## Memory Limits

| Command | RTS Flags | Peak RAM | Tier |
|---------|-----------|----------|------|
| `cabal build all` | `-j2` | ~4 GB | Core |
| `cabal test qxfx0-test-fast` | `-j1` | ~3 GB | Core |
| `cabal test qxfx0-test-slow` | `+RTS -M16G -RTS` | ~14 GB | Extended |
| `cabal test qxfx0-test` (full) | `+RTS -M16G -RTS` | ~16 GB | Extended |
| `bash scripts/release-smoke.sh` strict | `+RTS -M16G -RTS` | ~14 GB | Extended |
| `bash scripts/test_coverage.sh` | — | ~12 GB | Extended |

---

## Verification Commands (local production-like run)

```bash
# Core contract (16 GB compatible)
export QXFX0_CONTRACT_PROFILE=core
export QXFX0_RUN_SLOW_TESTS=0
export QXFX0_ENABLE_COVERAGE_GATE=0
export QXFX0_RELEASE_SMOKE_MODE=degraded-local
export LD_LIBRARY_PATH=/tmp/gf-install/usr/lib
export QXFX0_CABAL_LOCK_FILE=/tmp/qxfx0-cabal.lock
bash scripts/ci_gate_contract.sh
# Expected: CONTRACT_VERDICT: PROD_GO

# Extended contract (>=32 GB required)
export QXFX0_CONTRACT_PROFILE=extended
export QXFX0_RUN_SLOW_TESTS=1
export QXFX0_ENABLE_COVERAGE_GATE=1
export QXFX0_REQUIRE_STRICT_RUNTIME=1
export QXFX0_RELEASE_SMOKE_MODE=strict
export LD_LIBRARY_PATH=/tmp/gf-install/usr/lib
export QXFX0_CABAL_LOCK_FILE=/tmp/qxfx0-cabal.lock
bash scripts/ci_gate_contract.sh
# Expected on high-mem runner: CONTRACT_VERDICT: FULL_SCIENTIFIC_GO
# Expected on undersized runner: CONTRACT_VERDICT: REJECT (INFRA)
```

---

## Verdict Semantics

### `PROD_GO` (Core)
- All 10 common gates PASS.
- `release-smoke` in `degraded-local` returns `ACCEPT` or `ACCEPT_WITH_SKIPS`.
- No FAIL in any gate.
- **Does NOT require:** slow tests, coverage, strict smoke, Agda.

### `FULL_SCIENTIFIC_GO` (Extended)
- All core gates PASS.
- Slow tests PASS (0 errors, 0 failures).
- Coverage >= 51%.
- `release-smoke` strict returns `ACCEPT` with `Failed=0` and `Skipped=0`.
- Agda typecheck + witness PASS.
- No FAIL, no INFRA, no SKIP in any gate.

### `REJECT`
- Any gate FAIL → `REJECT` (regardless of profile).
- Extended profile: any INFRA in slow tests or coverage → `REJECT` with honest reason.
- Extended profile: any SKIP in strict smoke → `REJECT`.
- Core profile: `release-smoke` degraded-local returning non-ACCEPT → `REJECT`.

---

## Artifacts Retention

| Artifact | Retention | Purpose |
|----------|-----------|---------|
| `core-gate-logs-{run_id}` | 30 days | Core contract evidence |
| `extended-gate-logs-{run_id}` | 90 days | Extended contract evidence |
| `reports/coverage/` | 30 days | HPC reports |
| `dist-newstyle/` | 7 days (cache) | Build artifacts |

---

## Validated Live Envelope (Wave 5)

As of 2026-05-21, the following live-soak envelope has been validated on `main` (SHA `cf3de87`):

| Parameter | Validated Value | Model |
|-----------|----------------|-------|
| Max sessions | 20 | `accounts/fireworks/models/kimi-k2p6` |
| Max turns/session | 80 | (primary) |
| Total turns validated | 1840 | `kimi-k2p5` fallback not exercised at scale |
| Schema pass rate | 1.000 | |
| Graft accept rate | 1.000 | |
| Incidents | 0 | |
| Avg latency | ~3458ms | |
| P95 latency | ~9771ms | |

**Notes:**
- This validates the *production learning-loop envelope* (structured-output prompt → JSON parse → validate → sandbox → graft) at depth.
- It does **not** constitute `FULL_SCIENTIFIC_GO` (extended contract gates remain INFRA-DEFERRED on low-RAM runner).
- Production deployments should adhere to the staged rollout pattern (canary → stage1 → full) and respect the token/incident caps defined in `scripts/wave5_soak.py`.

---

## Rollback Criteria

If ANY of the following occurs in production CI:
- `ci_gate_contract.sh` (core) exits non-zero or does not print `CONTRACT_VERDICT: PROD_GO`
- `ci_gate_contract.sh` (extended) exits non-zero or does not print `CONTRACT_VERDICT: FULL_SCIENTIFIC_GO`
- `release-smoke.sh` strict returns `VERDICT: REJECT` or `ACCEPT_WITH_SKIPS`
- Coverage < 51% in extended contract
- Agda typecheck fails in extended contract
- `gf_quality_gate.sh` FAIL in any tier

→ **NO-GO**. Do not merge to `main`.
