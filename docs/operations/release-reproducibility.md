# Release Artifact Reproducibility Audit

Date: 2026-05-19

## Scope

Two release gate scripts are audited for byte-identical output across
consecutive runs from a clean working tree:

- `scripts/verify.sh` — CI verification gate (build + test + Agda + schema)
- `scripts/release-smoke.sh` — 10-step constitutional release gate

## Sources of nondeterminism identified

| # | Source | Script | Impact | Fix applied |
|---|--------|--------|--------|-------------|
| 1 | `cabal build all` without `-j1` | Both | Parallel GHC compilation reorders warnings / progress lines captured in `$BUILD_OUT` and `$TEST_LOG`. | Replaced with `cabal build all -j1` in `run_cabal_check` calls (verify.sh line 216) and `release-smoke.sh` line 420. |
| 2 | `date +%s` for elapsed-time reporting | release-smoke.sh | `START_TIME` and `END_TIME` produce different `ELAPSED` on every run; printed in the final summary block. | Wrapped both reads with `${SOURCE_DATE_EPOCH:-$(date +%s)}`. When `SOURCE_DATE_EPOCH` is exported, elapsed time is deterministic (0 s). |
| 3 | `mktemp -d …XXXXXX` | Both | Temporary directory suffixes are random. verify.sh leaks one path in Agda witness output (`/tmp/qxfx0-verify.XXXXXX/.state/…`). release-smoke.sh does not print temp paths in its happy-path output. | **Not fixed** — the single leaked path in verify.sh is an acceptable infra artifact; the directory is cleaned up on `trap EXIT`. Fixing it would require hard-coding a suffix and risking collision on shared CI runners. |
| 4 | Dynamic port selection (`ALT_PORT`) | release-smoke.sh | HTTP sidecar binds to an OS-allocated port; the port number is printed in step info when `127.0.0.1:19170` is unavailable. | **Not fixed** — this is environmental coupling, not script nondeterminism. In a clean container with port 19170 free the path is constant. |

## Fixes implemented

### verify.sh

```diff
- if BUILD_OUT="$(run_cabal_check "cabal build all 2>&1")"; then
+ if BUILD_OUT="$(run_cabal_check "cabal build all -j1 2>&1")"; then
```

### release-smoke.sh

```diff
- START_TIME="$(date +%s)"
+ START_TIME="${SOURCE_DATE_EPOCH:-$(date +%s)}"
```

```diff
-     END_TIME="$(date +%s)"
+     END_TIME="${SOURCE_DATE_EPOCH:-$(date +%s)}"
```

```diff
- if run_local_cabal cabal build all >"$BUILD_LOG" 2>&1; then
+ if run_local_cabal cabal build all -j1 >"$BUILD_LOG" 2>&1; then
```

## Verification

Two back-to-back runs of `verify.sh` (run 3 and run 4, after an
architecture-checker regex fix that removed a false-positive
`head/tail/init/last` violation on Haddock comments) were captured to
`/tmp/verify-run{3,4}.log`.

```
$ diff /tmp/verify-run3.log /tmp/verify-run4.log
20c20
<   OK (/tmp/qxfx0-verify.4AgwMD/.state/qxfx0/agda-witness.json)
---
>   OK (/tmp/qxfx0-verify.7XtoXv/.state/qxfx0/agda-witness.json)
```

**Result**: all 64 lines are byte-identical except the `mktemp` suffix in
the Agda-witness path (line 20).  This is the only residual
nondeterminism; it is infra-local, transient, and cleaned up by `trap
EXIT`.

### Architecture-checker fix (bonus, not in §6.4 scope but required for
a green gate)

`scripts/check_architecture.sh` used `rg -v ':[0-9]+:\s*--'` to exclude
Haddock comments from partial-function detection.  `rg -n file` outputs
`line:text` (single colon), so the filter never matched and `-- last`
comments were flagged as violations.  Changed to `[0-9]+:\s*--` across
all five occurrences in the script.

## Remaining open items

1. `cabal.project.freeze` drift — not a script issue; tracked separately.
2. `Test.Tasty` test ordering — currently HUnit-based suites; switching to
   `Test.Tasty` with `dependencyOrder = False` would give explicit test
   ordering but is out of scope for a script-only ticket.

## Acceptance

- Documented audit present in `docs/operations/release-reproducibility.md`.
- Fixes local to scripts applied (`-j1`, `SOURCE_DATE_EPOCH`,
  architecture-checker regex).
- Two reproducible `verify.sh` runs diff-identical modulo one
  `mktemp` suffix.  All 64 output lines match byte-for-byte
  otherwise.  Final exit code: PASS on both runs.
