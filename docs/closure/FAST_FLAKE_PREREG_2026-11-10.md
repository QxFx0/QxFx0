# Pre-registration — fast-suite `SQLITE_BUSY` close flake (2026-11-10)

- **Status**: **SIGNED (2026-11-10)** — §6.1–§6.3 and bars B1a–B5 as written.
  Implementation is complete in the working tree; the batch lands under this
  document.
- **Owner signature**: 2026-11-10, total close + permanent stderr WARN +
  fixture stops the worker before the persisted-count assertions.
- **Trigger**: `testPersistentWorkerRetainsPendingTasks`
  (`Test.Suite.AutonomousIntegration`) intermittently errors with
  `category=SQLiteError, operation=close, code=rc=5`. First seen in the
  2026-11-08 matrix run (`reports/eval_runs/_logs/matrix-20261108/fast.log:1589`),
  reproduced on the pre-batch tree `3f6c3da` (3 errors in 28 isolated slice
  runs), and reproduced again on 2026-11-10: 1 failure in 6 and 1 in 8 isolated
  `QXFX0_FAST_SUITE=AutonomousIntegration` runs (~1 in 7).
- **Scope**: the connection-lifecycle path only —
  `QxFx0.Bridge.NativeSQLite.close`, the test helper `queryCount`, and the
  fixture of the affected test. No routing, scoring, corpus, GF, trace-schema
  or persisted-state change.

## 1. What is known (measured, not inferred)

`sqlite3_close` returns `SQLITE_BUSY` (rc=5) **only** while the handle still
owns unfinalized prepared statements (no blob/backup handles exist in this
codebase). Two facts bound the search:

1. every `withDB` path opens a *fresh* connection and closes it with
   `safeClose`, which swallows non-async exceptions — so a leak there is
   invisible and leaks the handle plus its file descriptor;
2. the shared test handle is touched only through `queryCount`, and the old
   `queryCount` finalized its statement on the success path only.

The leak is therefore conditional, and the exception that caused it is what
gets lost.

## 2. Diagnostic (landed with the batch)

`QxFx0.Bridge.NativeSQLite.close` walks `sqlite3_next_stmt` on rc=5 and prints
the SQL text of every statement still attached to the connection
(`[sqlite] close rc=5: finalizing N leaked statement(s): …`). The same SQL is
attached to the structured error context when the retry still fails. This is
what turned a bare `rc=5` into two named statements.

## 3. Root cause (measured 2026-11-10)

Two statements were leaked on two different connections, and both are
cancellation/exception shapes:

```
[sqlite] close rc=5 leaked: UPDATE learning_jobs SET state='failed',
  lease_until=NULL, lease_token=NULL, last_error='lease_attempts_exhausted',
  active_key=NULL, updated_at=? WHERE state='leased' AND … attempts >= max_atte…
[sqlite] close rc=5 leaked: SELECT COUNT(*) FROM learning_events WHERE kind = 'llm_edge_proposed'
```

1. **Worker side** (`Learning/JobQueue.hs:236`, inside `withDB`). The worker
   thread was stopped while `failExhaustedLearningLeases` was mid-statement.
   `sqlite3_prepare_v2`/`sqlite3_step` are `safe` FFI calls, so `ThreadKilled`
   lands between `prepare` and `finalize`; the fresh connection then cannot
   close, and `safeClose` swallows the rc=5. The handle and fd leak silently.
2. **Test side** (`queryCount` on the shared handle). The step threw (the only
   plausible failure for that `SELECT` on a rollback-journal handle with
   `busy_timeout=0` while the worker commits is `SQLITE_BUSY`), the statement
   was never finalized, and the fixture's `finally closeDb` then failed with
   rc=5 — replacing the real error with the close error.

So the flake is not a data race in the runtime: it is statement hygiene under
cancellation plus one fixture that queried a connection while the worker was
still writing to the same file.

## 4. Fix shape (implemented)

1. `close` is **total** on `SQLITE_BUSY`: enumerate the leftovers, report them
   on stderr, finalize each, retry `sqlite3_close`, and throw only if the retry
   fails (or if rc=5 with no leftovers). A leaked statement can no longer turn
   a close into a silent handle/fd leak, and it can no longer mask the
   exception that caused it.
2. `queryCount` finalizes in `finally` — a failed step no longer strands its
   statement.
3. `testPersistentWorkerRetainsPendingTasks` stops the worker before reading
   persisted counts. Production never queries that connection while another
   writer commits, and this fixture's handle is a plain rollback-journal
   connection without `busy_timeout`.

## 5. Bars

| bar | statement | required | measured |
|---|---|---|---|
| **B1a** | red check: the new leak-recovery pins fail on the unfixed `close` | exactly the 2 recovery pins | **2/4 failed** (clean-close and diagnostic pins green) |
| **B1b** | red check: the `queryCount` pin fails without the `finally` | exactly 1 pin | **1/5 failed** (`a query that fails at step leaves no statement behind`) |
| **B2** | `AutonomousIntegration` slice passes 40 consecutive runs on the fixed tree | 40/40 | **40/40** (`loop4.out`) |
| **B3** | no `close` fails anywhere in the full matrix; the finalize WARN appears only where a leak is induced or a cancellation interrupts a statement, and is counted | 0 `operation=close` errors | **0** errors in all suites; 2 WARN lines, both the new suite's deliberate leaks |
| **B4** | success path unchanged: a clean handle owns no statements and closes without touching `next_stmt` | yes | pinned by `clean close succeeds and owns no statements` |
| **B5** | matrix green; the only case-count change is the new suite (+5 unit, +5 fast) | green | **green**: unit 1833, fast 1926, property 244, integration 47, main 106+23, slow 190 — 4 369 cases, 0 errors |

## 6. Decisions (signed 2026-11-10)

1. **Total close.** Approve `close` finalizing leaked statements and reporting
   them instead of failing. Rejected alternative: keep throwing and require
   every caller to repair its own leak — `safeClose` swallows, so the handle
   and fd leak silently and the original exception is lost.
2. **Observability.** Approve the permanent stderr WARN on the finalize path
   (it is the artifact that named both leaks). It is not a trace field and not
   a user-facing surface.
3. **Fixture change.** Approve stopping the worker before the persisted-count
   assertions in `testPersistentWorkerRetainsPendingTasks`.
4. **Bars.** Approve B1a–B5 as written.

## 7. Rollback

Revert `src/QxFx0/Bridge/NativeSQLite.hs`, `test/Test/Support.hs` and
`test/Test/Suite/AutonomousIntegration.hs`. The new pins in
`Test.Suite.NativeSQLiteClose` then fail exactly as in B1a/B1b, which is the
intended red state. No data migration, no schema change, no persisted-state
compatibility surface.

## 8. Reproduction evidence (2026-11-10)

Logs: `reports/eval_runs/_logs/flake-20261110/` (gitignored).

| run set | tree | runs | failures |
|---|---|---|---|
| `loop.out` | pre-fix + diagnostic | 6 | 1 (`run-6.log`) |
| `loop2.out` | pre-fix + diagnostic WARN | 8 | 1 (`run-8.log`, both leaks named) |
| `loop3.out` | probe build (killed for the fix) | 17 started | 0 |
| `loop4.out` | **fixed** | 40 | **0** |

The failure rate on the unfixed tree is ~1 in 7 runs; the fixed tree passed
40/40. B2 is a reliability bar, not a statistical proof of absence.

Full matrix (2026-11-10/11, tree = this working tree, logs in
`reports/eval_runs/_logs/matrix-20261110/`): unit 1833/1833 (181s),
fast 1926/1926 (3 310s), property 244/244 (19s), integration 47/47 (612s),
main runtime 106/106 (5 226s) + http 23/23 (526s), slow runtime 106/106
(4 992s) + state 50/50 (3 834s) + http 23/23 (524s) + lifecycle 11/11
(436s) — 4 369 cases, 0 errors, 0 `operation=close` errors.
