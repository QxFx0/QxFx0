# Pre-registration — fsync barrier for the atomic writers (2026-11-11)

- **Status**: PRE-REGISTERED; implementation and verification recorded below.
- **Trigger**: P3 tech-debt item `tmp-fsync` (audit 2026-10-16; operator note
  "В техдолге остаются tmp-fsync и `Prepare/Resolve` fallback").
- **Scope**: one new helper module, three call sites, cabal bounds, one new
  test suite. No runtime semantics, no corpus, no GF, no prompt-file change.
- **Owner decision**: 2026-11-11, item 3 of the follow-up list.

## Problem

Three writers replace a file atomically by writing a temp file, closing the
handle and renaming it:

| site | file | content |
|---|---|---|
| `Semantic/Network/Feedback/Persist.hs` (`writeMirrorAtomically`) | feedback mirror JSONL | runtime data, self-healing |
| `Learning/Tuning.hs` (`writeJson`) | `resources/config/tuned_*.json` | calibration output read at startup |
| `Bridge/AgdaWitness.hs` (`atomicWriteWitness`) | `agda-witness.json` | bootstrap freshness witness |

`hClose` flushes user-space buffers into the page cache; it does **not** force
the bytes to the device. After a crash or power loss the rename (a metadata
operation, journaled by the filesystem) can survive while the file content does
not, leaving an empty or truncated file where a valid one was. The window is
small, but the failure mode is silent: the next reader parses a valid-looking
path and gets nothing.

`rename(2)` gives *atomic visibility*, not *durability*. The barrier is
`fsync` on the temp file before the rename, plus `fsync` on the directory after
it (so the rename itself survives).

## Change

- New `QxFx0.Internal.AtomicFile.atomicWriteFile`: temp file in the target
  directory (same template as today, `<name>-tmp`), write, flush, `fsync`
  the file, close, `rename`, `fsync` the directory (best effort — see
  residual risks). Failure before the rename removes the temp file and leaves
  the target untouched.
- The three call sites call it instead of their local write+rename code.
  Paths, bytes, permissions and call order are unchanged.
- `unix` lower bound raised to `>=2.8` in the three stanzas: the code already
  uses the 3-argument `openFd` (unix-2.8 API) in `Runtime/Wiring/Handlers.hs`
  and `Runtime/AutonomousSmoke.hs`, so `>=2.7` was already untrue.

## Bars

| # | Bar | Measure |
|---|---|---|
| B1 | Scope is exactly the three sites | `rg "renameFile"` in the three modules returns nothing; each imports `QxFx0.Internal.AtomicFile`; no other file writes change |
| B2 | The barrier is real | `strace -f -e trace=fsync,rename,openat` on a probe: one `fsync` on the temp fd **before** `rename`, one `fsync` on the directory fd after it; probe log recorded below |
| B3 | Atomicity invariants hold | new `Test.Suite.AtomicFile` (5 cases): content round-trip incl. 5 MB, overwrite changes the inode, no `-tmp` leftovers on success, a failed rename (target is a directory) leaves the target intact and removes the temp, a missing parent directory is created |
| B4 | Existing behaviour unchanged | `FeedbackMirror` 5/5, `CorpusTuning` and `TuningRuntimeIntegration` green; unit + fast suites green |
| B5 | Red checks fail on the unfixed path | (a) direct write without rename → inode pin fails; (b) no temp cleanup on failure → leftover pin fails. Removing `fileSynchronise` is **not** observable by any test — it is covered by B2 only, stated here so the suite is not over-trusted |
| B6 | Landing matrix | full matrix on the landing tree (unit / fast / property / integration / main runtime+http / slow groups) |

## Residual risks (accepted, documented)

1. Directory `fsync` is **best effort**: on filesystems that reject it
   (`EINVAL`/`ENOTSUP`, some network mounts) the rename may not survive a
   power loss even though the content does. The write itself still fails
   loudly if the file `fsync` fails.
2. `Learning/Tuning.writeJson` still keeps a non-atomic `.bak` copy
   (`copyFile`). The backup is a manual-recovery aid, not a read path; making
   it atomic is out of scope for this item.
3. `fsync` costs one device flush per write. The mirror is written
   post-commit (best effort) and the tuned config / witness are written once
   per run, so the added latency is not on the per-turn critical path.

## Result (2026-11-11)

**Status: all bars closed. Implemented and verified on `148ec16` + the
change set; not committed at the time of this record.**

### Bars

| # | Bar | Evidence | Verdict |
|---|---|---|---|
| B1 | scope is exactly the three sites | `rg "renameFile\|BL\.writeFile\|openTempFile"` in `Persist.hs`, `Tuning.hs`, `AgdaWitness.hs` → **0 matches**; all three import `QxFx0.Internal.AtomicFile`; no other writer touched | **PASS** |
| B2 | the barrier is real | LD_PRELOAD shim (`gcc -shared`, intercepts `fsync`/`rename`, prints `/proc/self/fd/N`): `fsync fd=4 path=…target96400-0.txt-tmp` → `rename …txt-tmp -> …target.txt` → `fsync fd=4 path=…/fsync-probe` (the directory). `strace`/`perf`/`ltrace` are absent on the box; the shim is the substitute and was compiled in `/tmp/opencode/fsync-probe/` | **PASS** |
| B3 | atomicity invariants | `Test.Suite.AtomicFile` **5/5**: content round-trip incl. 5 MB, overwrite changes the inode, failed rename (target is a directory) leaves the target and removes the temp, missing parents created, repeated writes leave no temp | **PASS** |
| B4 | existing behaviour unchanged | `FeedbackMirror` 5/5; fast slice `AtomicFile,CorpusTuning,TuningRuntimeIntegration,TunedConfigLoading` 27/27; unit 1838/1838; fast 1931/1931 | **PASS** |
| B5 | red checks fail on the unfixed path | (a) `atomicWriteFile` replaced by a direct `BL.writeFile` → **exactly 1** failure (the inode pin); (b) temp cleanup dropped from the error handler → **exactly 1** failure (the leftover pin, listing the actual `…-tmp94061-3` file). As pre-registered, removing `fileSynchronise` alone is not observable by any test | **PASS** |
| B6 | landing matrix | full matrix on the fixed tree — see below | **PASS** |

### B6 — landing matrix

Tree fixed from start to finish: `git status` restricted to
`src|test|spec|app|qxfx0.cabal|resources` is byte-identical at start and end
(`reports/eval_runs/_logs/matrix-20261111/tree-{start,end}.txt`). Only the two
docs of this session were added while the matrix ran; no code, spec, data or
prompt file changed.

| step | cases | exit | wall |
|---|---|---|---|
| unit | 1838 | 0 | 65 s |
| fast | 1931 | 0 | 3 231 s |
| property | 244 | 0 | 16 s |
| integration | 47 | 0 | 612 s |
| main-http | 23 | 0 | 541 s |
| slow-http | 23 | 0 | 522 s |
| slow-lifecycle | 11 | 0 | 434 s |
| main-runtime | 106 | 0 | 5 106 s |
| slow-state | 50 | 0 | 3 752 s |
| slow-runtime | 106 | 0 | 4 974 s |
| **total** | **4 379** | **all 0** | 5 h 21 m wall |

0 errors, 0 failures. The 4 379 total is the 2026-11-10 matrix (4 369) plus
the 5 unit + 5 fast `AtomicFile` cases. Logs:
`reports/eval_runs/_logs/matrix-20261111/`.

### Notes

- The unit and fast runs finished faster than on 2026-11-10 (65 s vs 181 s,
  3 231 s vs 3 310 s) because the binaries were already warm from the
  slice runs; nothing else changed.
- The `fast` run was green on the **first** attempt — the pre-existing
  `testPersistentWorkerRetainsPendingTasks` `SQLITE_BUSY` close race (closed
  2026-11-10/11) did not reappear.
- `unix` bounds: raised `>=2.7` → `>=2.8` in the library, the
  `qxfx0-main` executable and the `qxfx0-test-slow` stanza. The code already
  used the 3-argument `openFd` (a unix-2.8 API) in `Runtime/Wiring/Handlers.hs`
  and `Runtime/AutonomousSmoke.hs`, so the old lower bound was already untrue;
  the toolchain ships `unix-2.8.6.0`.

