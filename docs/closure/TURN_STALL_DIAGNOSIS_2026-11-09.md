# 4 987 s turn — diagnosis (2026-11-09)

- **Status**: diagnosed **to the phase and to the cost model**; the root cause of
  the 100× slowdown is **not** determined from the surviving artifacts. No code
  change, no behaviour change.
- **Subject**: `gf-rel-010` («что такое вера?») in run
  `reports/eval_runs/m7-gf-batch-20261108c` took 4 986.7 s (harness
  `latency_ms`) / 4 960 404 ms (runtime `duration_ms`).
- **Correction to the group-2 result doc**: the earlier sentence "the process
  was alive and progressing (observed in `ps` during the stall)" is **not
  backed by any artifact** — no `ps` monitor log exists for that window. It is
  removed from
  `docs/closure/GF_SLOT_BATCH_GROUP2_RESULT_2026-11-09.md`. What is true is
  narrower: the process **completed normally** and produced the correct result.

## 1. Where the time went (hard evidence)

`reports/eval_runs/m7-gf-batch-20261108c/raw/gf-rel-010.log`:

```
19:58:48.901 [DEBUG] Turn pipeline: rendering turn
21:21:26.354 [DEBUG] Turn pipeline: finalizing turn
21:21:29.174 [DEBUG] Turn pipeline phases completed
                    finalize_ms=2820 plan_ms=47 prepare_ms=82
                    render_ms=4957452 total_ms=4960402
```

The wall gap between the two log lines (4 957 453 ms) equals `render_ms`
(4 957 452 ms) to within 1 ms. So **99.94 % of the turn is inside
`renderTurn`**, and inside it the whole span is inside
`resolveRenderEffects` (the timeline's start stamp is taken at that function's
first statement).

## 2. The render phase is CPU-bound by design, not an idle wait

Measured on 2026-11-09 on the same prompt, same code tree, fresh session, with
RTS statistics (`reports/eval_runs/_logs/rts-probe-20261109/`):

| process | wall | MUT | GC | allocated | max residency | peak |
|---|---:|---:|---:|---:|---:|---:|
| `--state-json` (bootstrap only, no turn) | 23.4 s | 17.7 s | 4.2 s | 26.8 GB | 495 MB | 649 MiB |
| one turn (`--input "что такое вера?"`) | 72.7 s | 43.6 s | 27.1 s | **95.6 GB** | 762 MB | 1 258 MiB |

So a definitional turn allocates **≈ 69 GB** (95.6 − 26.8) and burns
**≈ 49 s of CPU** (26 s mutator + 23 s GC) to produce one answer. `render_ms`
for that probe: **44 881 ms**.

The phase is not special to this turn: across all four runs the render phase is
the dominant cost of every turn —

| run | render median | render min | render max |
|---|---:|---:|---:|
| a | 42.2 s | 27.6 s | 55.3 s |
| b | 42.1 s | 27.8 s | 55.1 s |
| c | 43.7 s | 28.8 s | **4 957.5 s** |
| d | 45.3 s | 33.7 s | 69.4 s |

The stalled turn is ~101× its own run's median. **Run c's other 29 turns are
normal** (median 43.7 s), so the machine was not globally loaded during the run;
the event is confined to that one turn.

## 3. What the render phase actually does

`renderTurn` = `planRenderEffectsForRuntime` (pure) + `resolveRenderEffects`
(IO) + `buildTurnArtifacts` (pure). `resolveRenderEffects` (`Route/Render.hs`
~:671) contains **all** of the following, and nothing else:

1. `getCurrentTime` ×2 (phase stamps);
2. four `TurnReqReadEnv` reads (`QXFX0_WARN_MORPHOLOGY_FALLBACK`,
   `QXFX0_GF_RUNTIME`, `QXFX0_GF_LANG`, `QXFX0_GF_PGF_PATH`) → handler is
   `lookupEnv`, plus a `Set.member` allow-list check;
3. `doesFileExist` on `spec/gf/QxFx0Syntax.pgf`, then `cachedReadPGF`
   (`IORef` `Map` lookup — the grammar is preloaded at bootstrap,
   `pgf_preload_ms=42`), `PGF.readExpr`, `PGF.linearize` — all in-process,
   `pgf2` library, no subprocess;
4. `retrieveLegalFact` — a pure `Map.lookup` over a static table;
5. `forConcurrently []` — external learning is permanently off
   (`legacyExternalLearningEnabled = False`, `Learning/Loop.hs:135`), so the
   request list is empty.

There is **no** retry loop, `threadDelay`, MVar/STM, subprocess, network call
or DB access on this path (`unsafePerformIO` does not occur in
`src/QxFx0/Semantic` or `src/QxFx0/Core/TurnPipeline/Route`). The remaining
~49 s of CPU is the pure computation behind those steps (composition, retrieval,
selector scoring, artifact assembly) being forced inside the window.

## 4. The result is identical to a fast run

| artifact | run c (stalled) | run d (fast, 86 s) |
|---|---|---|
| replay trace | 3 846 787 B, 157 keys | 3 846 787 B, 157 keys |
| surface | «Тезис: вера требует принятия…» | byte-identical |
| `trcAuthorityClass` | `AuthorityCanonical` | same |
| `trcRecoveryCause` / `trcRecoveryStrategy` | `null` | `null` |
| `trcEssenceResetEvent` | `null` | `null` |
| `trcFallbackReason` | `null` | `null` |
| `trcDoubtScore` | 0.3192764769057714 | same |

Same input, same state, same output. The stall is a **wait or a slowdown**, not
a different code path and not a semantic defect.

## 5. Environment checks (all negative)

- `journalctl` for 19:55–21:25 UTC: no OOM, no hung task, no I/O error, no
  kernel message, no swap event. Only the periodic
  `qxfx0-local-monitor.service` (1.2 s CPU / 285 MB every ~5.5 min),
  `wpa_supplicant`, one `tor` line, and idle `grid-daemon`/`ollama` chatter.
- `turn_quality.created_at` for the window: **only** the run-c sessions. No
  other QxFx0 session was running (so no other eval competed for the DB or the
  CPU).
- Swap is zram, 4 GB, currently 0 B used; 11 GB available now.

## 6. Hypotheses, ranked

1. **CPU starvation / descheduling of that one process** (most likely). A
   deterministic ~49 s CPU-bound computation stretched to 4 957 s is ≈1 % of one
   core for 83 minutes. Consistent with: identical output, normal neighbouring
   turns, no kernel events, no other session. Cause outside the runtime (a
   co-tenant process, a cgroup/CPU-quota event, thermal/power state) — the
   artifacts do not record CPU time, so this cannot be confirmed.
2. **RTS/GC pathology not captured** (possible). The harness records no RTS
   statistics, so a 100× allocation or GC blow-up that still converges to the
   same answer cannot be excluded. The 762 MB residency makes swap-thrash
   unlikely, but not a pathological allocation pattern.
3. **OS-level syscall stall** on one of the five render IO calls (unlikely).
   `lookupEnv`/`doesFileExist`/cache-hit read are microseconds; a stall there
   would be an OS/filesystem event, and none was logged.

**Ruled out**: an external query or sidecar (permanently off on this path), a DB
lock (no DB access in the phase), a retry/backoff loop (none exists), a
time-budgeted search (no such construct in the render path), and a semantic
divergence (trace byte-identical).

## 7. Cheapest next diagnostic

**Instrument, do not guess.** Re-run the 30-prompt packet with
`+RTS -s -RTS` (optionally `-S`) appended to the per-turn invocation so each
turn's log carries `MUT`, `GC`, allocated bytes, max residency and peak. Zero
code change; ~40 min for the packet at current latency.

Re-measured 2026-11-11 on the same tree through the now-committed harness
(`QXFX0_EVAL_RTS_ARGS="+RTS -s -RTS"`), fresh sessions:

| process | wall | MUT | GC | allocated | max residency | peak |
|---|---:|---:|---:|---:|---:|---:|
| `--state-json` (bootstrap only) | 26.1 s | 18.5 s | 4.9 s | 26.8 GB | 495 MB | 651 MiB |
| one turn («что такое вера?») | 83.1 s | 44.7 s | 28.3 s | **95.6 GB** | 801 MB | 1 314 MiB |

Turn-only delta: **26.2 s MUT + 23.4 s GC = 49.6 s CPU**, 68.8 GB allocated —
the 2026-11-09 cost model reproduces to the digit. Logs:
`reports/eval_runs/_logs/rts-probe-20261111/`.

Then a recurrence is decisive:

- low `MUT`/`GC` totals with a long wall → **starvation** (hypothesis 1);
- huge `GC` or huge allocation → **RTS pathology** (hypothesis 2);
- normal CPU totals and a long wall → **blocked syscall** (hypothesis 3).

At the time of the original diagnosis the harness that produced runs a–d was
**not committed** (it lived in `/tmp` and was lost), so the instrumentation had
to be re-added to a re-created harness. That is itself a gap worth closing: a
committed harness is the precondition for any reproducible latency work.

**Closed 2026-11-11.** The three heavy pieces were already in the tree
(`scripts/run_dialogue_eval_200.sh`, `scripts/m7_gate_check.py`,
`scripts/eval/gf_slot_realizability.py`); what was missing was the thin driver
and the corpus-dump writer, both now committed:

- `scripts/run_m7_batch.sh <run_id> [prompts]` — strict mode, isolated
  sessions, eval → gate → realizability in one pass, tree identity (git HEAD,
  dirty flag, prompts/dump sha256) appended to `meta.env`.
  `QXFX0_M7_REPLICA=1` runs a second pass and diffs predicate choice and
  surface per row (mechanizes bar 5: **0/30** and **0/30** on runs c/d);
  `QXFX0_M7_SKIP_EVAL=1` re-runs only the checks; `QXFX0_M7_DUMP=<path>`
  reuses an existing dump.
- `QXFX0_EVAL_RTS_ARGS` in `run_dialogue_eval_200.sh` — the per-turn RTS
  instrumentation, appended to the runtime argv (the RTS report lands in
  `raw/<id>.log`, which the JSON payload parser skips).
- `scripts/eval/gf_slot_gap.py --write-dump` — writes the 12 325-line corpus
  dump that the realizability check consumes (it was a lost `/tmp` file).

Verified 2026-11-11: dump 12 325 lines (309 anchor rows, 305 mapped, 4
unmapped), realizability **305/305**, gate **30/30** on a reused run, and the
determinism comparator's red checks (predicate, surface, row-set) each fail
exactly the mutated row.

### Packet re-run with instrumentation (2026-11-11)

The full 30-prompt packet through `scripts/run_m7_batch.sh` with
`QXFX0_EVAL_RTS_ARGS="+RTS -s -RTS"`
(`reports/eval_runs/m7-harness-20261111`):

- gate **30/30**, realizability **305/305**, dump 12 325 lines;
  `gf_mapped_fallback` **0/30**, `AuthorityCanonical` 30/30, 0 errors,
  average latency **70.5 s** (run d: 77 s) — the group-2 numbers reproduce;
- per-turn RTS (n = 30): median wall 70.8 s, MUT 41.9 s, GC 26.2 s,
  allocation 92.9 GB (max 111.1 GB), max residency 891 MB, peak 1 333 MiB;
- **no outlier**: wall/(MUT+GC) median **1.04**, max **1.06**. The stall did
  not recur, so this run does not explain 2026-11-08 — it establishes the
  instrument and the baseline band (per-turn table:
  `reports/eval_runs/_logs/harness-20261111/rts-summary.txt`).

The recurrence rule is now readable off one log line: wall/(MUT+GC) ≫ 1 with
normal totals → starvation (hypothesis 1); large GC/allocation → RTS pathology
(hypothesis 2); normal totals and a long wall → blocked syscall
(hypothesis 3).

## 8. Product note (not a change)

Two independent facts:

- the render phase costs ~49 s of CPU and ~69 GB of allocation **per
  definitional turn** — that is the real lever (allocation reduction in
  composition/retrieval would help every turn, not just outliers);
- a 500-prompt M7 run at the current ~70 s/turn is ~10 h of wall clock before
  any labeling.

One adjacent observation, **not** a cause of the stall and not fully
characterised (single mid-process sample from `/proc/<pid>/io` on 2026-11-09,
53 s into a turn): the runtime process had written ~260 MB
(`wchar 260 364 113`, `write_bytes 264 134 656`) and the runtime DB is
**2.5 GiB** (`~/.local/state/qxfx0/qxfx0.db`). Per-turn write volume of that
order matters for two things this document does not settle: the cost of a
500-prompt run (~130 GB written) and any latency work on the persistence path.
It is recorded as an open measurement, not as a finding.

An 83-minute user-visible wait is unacceptable regardless of cause, so a
per-turn watchdog with a bounded degraded surface is the product-level guard.
That is a **behaviour change** and needs pre-registration; it is not part of
this diagnosis.

## Artifacts

- `reports/eval_runs/m7-gf-batch-20261108c/raw/gf-rel-010.log` — the stalled turn.
- `reports/eval_runs/m7-gf-batch-20261108d/raw/gf-rel-010.log` — fast replica.
- `reports/eval_runs/_logs/rts-probe-20261109/` — today's RTS probe
  (`err.log` turn, `err-noload.log` bootstrap-only).
