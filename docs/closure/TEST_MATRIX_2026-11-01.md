# Test matrix — 2026-11-01/02 (post-M7 verification)

- **Tree**: working tree at `c2383d9` (docs) over code `bcceee6` — the same code
  tree the M7 confirmatory run used on 2026-10-31. No source, spec or data file
  changed during the run.
- **Why**: the M7 result was produced with `[skip ci]` docs pushes after the last
  green CI, so the current tree had no full-matrix evidence of its own. This run
  closes that gap; it is verification, not a new gate.
- **How**: one sequential script, each step recorded its own exit code, the chain
  continued regardless. Logs were captured per step. Heap caps follow the
  project convention (`-M6G` unit/integration, `-M10G` fast/property/slow-state,
  `-M12G` runtime/http/lifecycle).

## Results

| step | command | cases | exit | wall |
|---|---|---:|---:|---:|
| unit | `cabal test qxfx0-test-unit` | 1821 | 0 | 79 s |
| fast | `cabal test qxfx0-test-fast` | 1918 | 0 | 3 744 s |
| property | `cabal test qxfx0-test-property` | 244 | 0 | 38 s |
| integration | `cabal test qxfx0-test-integration` | 47 | 0 | 630 s |
| main-runtime | `QXFX0_AGGREGATE_GROUP=runtime` | 106 | 0 | 5 500 s |
| main-http | `QXFX0_AGGREGATE_GROUP=http` | 23 | 0 | 537 s |
| slow-runtime | `QXFX0_SLOW_GROUP=runtime` | 106 | 0 | 5 413 s |
| slow-state | `QXFX0_SLOW_GROUP=state` | 50 | 0 | 3 834 s |
| slow-http | `QXFX0_SLOW_GROUP=http` | 23 | 0 | 537 s |
| slow-lifecycle | `QXFX0_SLOW_GROUP=lifecycle` | 11 | 0 | 453 s |

Every step reported `Errors: 0  Failures: 0` on its final `Cases:` line. Total
wall time 18:21 → 00:07, i.e. 5 h 46 min.

Aggregate: **4 349 executed cases, 0 failures** across the four suites
(unit 1821 + fast 1918 + property 244 + integration 47 + aggregate runtime/http
129 + slow 190 = 4 349).

Not run: the 1 254-case **core** slice of `qxfx0-test`. The full single-process
`qxfx0-test` is still unsupported on this box with the substrate active (the
documented OOM hazard), and the core slice is covered by the dedicated unit and
fast suites above. This is the same coverage shape as the 2026-10-25/26 matrix.

## Caveats

- Timings are indicative, not benchmark figures: the box also ran three
  allocation probes and several one-turn CLI probes during the first hour, and
  the substrate (`brain_kb.jsonl`, 53 146 entries) is active. CI's fast suite
  takes ~25 min; here it took 62.
- `qxfx0-test-fast` spent >6 minutes on a single late case; it completed, so this
  is the known slow-bootstrap class, not the known hang (that one is a runtime
  group case, `testComputeReadinessModeReady`).
- No code, spec or data file was modified between the run start and finish, so
  the exit codes describe `c2383d9` exactly.

## What this does and does not establish

- **Does**: the current tree is green on every suite the project runs routinely,
  with the counts recorded in `AGENTS.md` (unit 1821, fast 1918, property 244,
  integration 47, slow 190, main runtime+http 129).
- **Does not**: re-open or re-verify M7. The M7 gate result stands on its own
  pre-registered run (`M7_CONFIRM_RESULT_2026-10-31.md`); this matrix only says
  the tree that carries it still passes everything else.
- **Does not**: cover the 1 254-case core slice, or any behaviour changed by the
  pending slot-coverage work.
