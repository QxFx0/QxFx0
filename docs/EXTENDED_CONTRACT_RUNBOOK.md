# Extended Contract High-Mem Runbook

**Version:** v1-transferred  
**Branch:** `feature/glm-fixes-audit-round1`  
**Purpose:** Step-by-step execution guide for `FULL_SCIENTIFIC_GO` on a high-memory runner (>=32 GB RAM).  
**Prerequisite:** `PROD_GO` already achieved in source repo (see `reports/baseline_v2/final_gates/CANONICAL_EVIDENCE_INDEX.md`). Target evidence pending.

---

## 1. Runner Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| RAM | 32 GB | 48 GB |
| CPU cores | 4 | 8 |
| Disk | 40 GB free | 60 GB |
| OS | Ubuntu 24.04 LTS | Ubuntu 24.04 LTS |
| Timeout | 45 min | 60 min |

---

## 2. Pre-Flight Checklist

### 2.1 Environment

```bash
# Verify GHC 9.6.6 is default (not 9.8.x)
ghc --version  # Must report 9.6.6

# Verify cabal
cabal --version  # >= 3.10.3.0

# Verify nix (for Agda fallback)
nix --version  # >= 2.18

# Verify spaCy + ru_core_news_sm
python3 -c "import spacy; spacy.load('ru_core_news_sm')"

# Verify souffle
souffle --version  # >= 2.4

# Verify agda
agda --version  # >= 2.6.4

# Verify GF runtime libs
ls /tmp/gf-install/lib/libpgf.so* /tmp/gf-install/lib/libgu.so*
# If missing, rebuild:
#   git clone --depth 1 https://github.com/GrammaticalFramework/gf-core /tmp/gf-core-src
#   cd /tmp/gf-core-src && autoreconf -i && ./configure --prefix=/tmp/gf-install && make && make install
```

### 2.2 Clean State

```bash
# Ensure no stale lock
cat /tmp/qxfx0-cabal.lock 2>/dev/null && rm -f /tmp/qxfx0-cabal.lock

# Ensure clean working tree (no uncommitted changes)
git status --short  # must be empty

# Warm cabal store cache (if available from prior core run)
# The extended job depends on core-contract in CI; ensure cache key matches.
```

---

## 3. One-Shot Execution

### 3.1 Export Environment

```bash
export QXFX0_CONTRACT_PROFILE=extended
export QXFX0_RUN_SLOW_TESTS=1
export QXFX0_ENABLE_COVERAGE_GATE=1
export QXFX0_REQUIRE_STRICT_RUNTIME=1
export QXFX0_RELEASE_SMOKE_MODE=strict
export QXFX0_SKIP_AGDA=0
export QXFX0_GF_RUNTIME=1
export LD_LIBRARY_PATH="/tmp/gf-install/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export QXFX0_CABAL_LOCK_FILE=/tmp/qxfx0-cabal.lock
export PATH="/tmp/ghc-wrapper:$PATH"  # If using GHC wrapper workaround
```

### 3.2 Run Extended Contract

```bash
cd /path/to/QxFx0_v2
bash scripts/ci_gate_contract.sh \
  > reports/baseline_v2/final_gates/extended_run_$(date +%Y%m%d-%H%M%S).log \
  2>&1
```

Or with tee for live monitoring:

```bash
bash scripts/ci_gate_contract.sh 2>&1 | tee reports/baseline_v2/final_gates/extended_run_$(date +%Y%m%d-%H%M%S).log
```

---

## 4. Expected Pass Criteria

After the run completes, verify **all** of the following:

### 4.1 Contract Verdict

```bash
grep "CONTRACT_VERDICT:" reports/baseline_v2/final_gates/_gate_results_*_extended.md
```
**Expected:** `CONTRACT_VERDICT: FULL_SCIENTIFIC_GO`

### 4.2 Slow Tests (Gate 11)

```bash
grep "cabal test slow" reports/baseline_v2/final_gates/_gate_results_*_extended.md
```
**Expected:** Verdict `PASS`, details `0 errors, 0 failures`.

If you see `INFRA`, the runner has insufficient RAM or timed out.

### 4.3 Coverage (Gate 12)

```bash
grep "test_coverage.sh" reports/baseline_v2/final_gates/_gate_results_*_extended.md
```
**Expected:** Verdict `PASS`, details `overall XX.X% >= 51%`.

If you see `INFRA`, the `--enable-coverage` rebuild exceeded timeout. Mitigation: increase timeout or ensure warm cache.

### 4.4 Release-Smoke Strict (Gate 13)

```bash
grep "release-smoke strict" reports/baseline_v2/final_gates/_gate_results_*_extended.md
```
**Expected:** Verdict `PASS`, details `ACCEPT, Failed=0, no skips`.

Also verify the release-smoke log directly:

```bash
grep "VERDICT:" reports/baseline_v2/final_gates/13_release_smoke_*_extended.log
```
**Expected:** `VERDICT: ACCEPT` (not `ACCEPT_WITH_SKIPS`, not `REJECT`).

### 4.5 No Failures Anywhere

```bash
grep -i "FAIL" reports/baseline_v2/final_gates/_gate_results_*_extended.md
```
**Expected:** No matches (or only in superseded/historical context).

---

## 5. Post-Run Artifact Collection

```bash
RUN_ID=$(ls -t reports/baseline_v2/final_gates/_gate_results_*_extended.md | head -n 1 | sed 's/.*_\(ci-[^_]*\)_extended.*/\1/')
echo "Canonical RUN_ID: $RUN_ID"

# Update canonical index
sed -i "s/Status: DEFERRED/Status: COMPLETED — RUN_ID: $RUN_ID/" \
  reports/baseline_v2/final_gates/CANONICAL_EVIDENCE_INDEX.md

# Update wp12 report verdict
sed -i 's/\*\*Extended Contract\*\* (`FULL_SCIENTIFIC_GO`) | \*\*BLOCKED — INFRA\*\*/\*\*Extended Contract\*\* (`FULL_SCIENTIFIC_GO`) | \*\*ACHIEVED\*\*/' \
  reports/baseline_v2/wp12_production_hardening_report.md
```

---

## 6. Troubleshooting

### 6.1 OOM / Slow Test Hang

**Symptoms:** Gate 11 (`cabal test slow`) takes >20 min, zero progress, or `Killed` by OOM killer.

**Root cause:** `qxfx0-test-slow` binary requires ~14 GB peak RAM. Runner has <16 GB effective.

**Mitigation:**
- Ensure runner has >=32 GB RAM.
- Run with `+RTS -M16G -RTS` (already default in `ci_gate_contract.sh` extended path).
- Close other memory-heavy processes before running.
- If still OOM, reduce `cabal build -j` parallelism: `cabal build all -j1` before tests.

### 6.2 Coverage Timeout (Gate 12)

**Symptoms:** `test_coverage.sh` exits 124 (timeout) or produces empty `.tix`.

**Root cause:** `--enable-coverage` forces Cabal to rebuild all 229 modules + dependencies with HPC instrumentation. Cold cache + 10–15 min per build phase = >20 min total.

**Mitigation:**
- Ensure warm cabal store cache from prior `core-contract` run.
- Increase `COVERAGE_TIMEOUT` in `ci_gate_contract.sh` (default 1200s = 20 min; try 1800s).
- If `vector` internal-libs conflict persists, use cabal 3.12+ or configure with `--disable-optimization` before coverage.

### 6.3 Cache Miss (Cabal Store)

**Symptoms:** `cabal build all` rebuilds everything from scratch despite prior runs.

**Root cause:** Cabal store path changed, cache key mismatch, or `dist-newstyle` cleaned.

**Mitigation:**
- Verify `CABAL_DIR` / `store-dir` consistency.
- In CI, use `actions/cache@v4` with key matching `cabal.project.freeze` + `qxfx0.cabal` hashes.
- Do not run `cabal clean` between core and extended jobs.

### 6.4 Toolchain Drift (GHC Version Mismatch)

**Symptoms:** `release-smoke.sh` or `verify.sh` fails with `base` version conflict (e.g., `base-4.18.3.0/installed` vs `base ==4.18.2.1` required).

**Root cause:** Host `~/.cabal/config` contains `with-compiler: /path/to/ghc-9.8.2`, or isolated `CABAL_DIR` inherits host config with wrong compiler.

**Mitigation:**
- Strip `with-compiler` from `~/.cabal/config` before run.
- In CI, use container with clean `$HOME` or explicitly override `with-compiler` in job env.
- The `ghc-wrapper` workaround (`/tmp/ghc-wrapper`) is verified for local dev; in CI, pin `ghc-version: '9.6.6'` in `haskell-actions/setup@v2`.

### 6.5 Agda Witness Failure

**Symptoms:** Agda typecheck passes, but `cabal run qxfx0-main -- --write-agda-witness` fails with dependency resolution error.

**Root cause:** `write_agda_witness` prepends Agda bin directory to `PATH`, which may shadow the correct GHC wrapper.

**Mitigation:**
- Ensure `PATH` order: `ghc-wrapper` > `ghcup` > `agda`.
- In `release-smoke.sh`, `write_agda_witness` uses `PATH="$PATH:$(dirname "$agda_path")"` (fixed in `9dbd7b0`).
- If still failing, run witness generation separately with explicit `PATH`.

### 6.6 Nested Flock Deadlock (Historical)

**Symptoms:** `ci_gate_contract.sh` hangs indefinitely at release-smoke gate.

**Root cause:** `run_with_cabal_lock` wrapping `release-smoke.sh`, which also calls `run_local_cabal` with the same flock fd.

**Mitigation:**
- Fixed in `8fb20a8` — `release-smoke.sh` is **not** wrapped in `run_with_cabal_lock` in `ci_gate_contract.sh`.
- If you see this on an old checkout, update to `stabilize-v2-gf` HEAD.

---

## 7. Rollback / Abort Criteria

Stop the run and **do not** declare `FULL_SCIENTIFIC_GO` if any of the following occur:

| Condition | Action |
|-----------|--------|
| Any gate shows `FAIL` (not `INFRA`) | Fix code, re-run from start |
| `release-smoke strict` shows `VERDICT: REJECT` or `ACCEPT_WITH_SKIPS` | Investigate skip source; fix and re-run |
| Coverage < 51% | Add tests or lower threshold only with architectural approval |
| Slow tests show errors/failures (not timeout) | Fix code, re-run |
| `ci_gate_contract.sh` exits non-zero without clear verdict | Check logs for unhandled exception |

---

## 8. References

- `docs/CI_PRODUCTION_PROFILE.md` — Runner requirements and job orchestration
- `reports/baseline_v2/final_gates/CANONICAL_EVIDENCE_INDEX.md` — Canonical vs. superseded evidence
- `reports/baseline_v2/wp12_production_hardening_report.md` — Current status and verdicts
- `scripts/ci_gate_contract.sh` — Contract implementation (gates, profiles, verdicts)
- `scripts/release-smoke.sh` — 10-step smoke test with strict/degraded-local semantics
