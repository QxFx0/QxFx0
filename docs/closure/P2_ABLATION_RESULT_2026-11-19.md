# P2 — Conatus-consumer ablation: result (2026-11-19)

- **Status**: MEASURED. Every number below was produced by the two
  captures named in §2 and the report tool in §7. Predictions were
  fixed in `P2_ABLATION_PREREG_2026-11-18.md` before the ablation arm
  ran; misses are reported as misses (§5), not patched.
- **Pre-registration**: `docs/closure/P2_ABLATION_PREREG_2026-11-18.md`.
- **Scope**: one env-gated ablation of the only *continuous* Conatus
  consumer, one 200-turn capture per arm, one offline census. No
  threshold, trace field, lexicon, crisis resource or math version
  changed.

## 1. What was measured

`csStability = clampUnit (fieldConf + min 0.25 (ceScalar / 80.0))`
feeds `computeNormativeAlignment` with weight `0.20`
(`Self/Perspective.hs:607`). The hook
`QXFX0_ABLATE_CONATUS_STABILITY` removes **only** the `ceScalar / 80.0`
term; `csEnergy`, `csGateFired` and `csFieldConfidence` stay truthful,
so `trcConatusEnergy` is identical by construction. The question is
whether that one term changes anything observable.

## 2. Setup

| item | baseline arm | ablate arm |
|---|---|---|
| run id | `p2-baseline-20261118` | `p2-ablate-20261118` |
| env | flag unset | `QXFX0_ABLATE_CONATUS_STABILITY=1` |
| started / last turn (UTC) | 10:38:44 / 12:25:09 | 10:38:48 / 12:25:23 |
| turns | 200/200 | 200/200 |
| `driver_error` | 0 | 0 |

- Corpus `spec/eval/p2_baseline_2026-11-18.tsv`, sha256
  `49b6d6c395f0000875cb8c3e9db6ed0fba764b08e15b323944ba4945067444b7`,
  200 rows = 20 dialogues × 10 turns, 200 unique prompts, contiguous
  turn order, 0 overlap with the 2026-11-13/14 corpora.
- Both arms ran the **same binary**, sha256
  `db38b94c301e3125727ba06181b81da1400e138986e2f4882e0d873ce4053d9c`
  (`meta.env` in both run directories). The ablate arm inherits the
  variable through `env` (no `-i`), so the shell function still sees
  the runtime environment.
- Tree: HEAD `085d0b0` + the P2 change set (`git_dirty_files=8` as
  recorded by the capture driver).
- Runtime mode: `degraded` in both arms (no external LLM).

The capture gate was green in both arms: 200 turns persisted, 200
regime records, 0 missing, 0 hard-trigger Protocol B, 0 contour exits,
encoder `[2]`, 180 residual samples, 180 window samples.

## 3. Bars

| bar | condition | result |
|---|---|---|
| B1 | corpus hash / row count; CrisisGuard pin | **PASS** — sha256 matches; `Test.Suite.CrisisGuard` "P2 baseline corpus stays in Protocol A" green (slice 23/23) |
| B2 | equivalence lock, 12 turns, surface + full trace | **PASS** — see §4 |
| B3 | P1: 200/200 surface identity | **PASS** — 200/200 |
| B4 | P2–P5 identity | **PASS, with P2 and P4 vacuous** — see §5.3, §5.4 |
| B5 | P6: 200/200 dead channel | **PASS** — 200/200 in both arms |
| B6 | P7: 0/200 threshold reachability | **PASS** — 0/200 on all seven |
| B7 | landing matrix | see §8 |

## 4. Equivalence lock (B2)

Three arms: `pre` = binary built before the hook
(`/tmp/opencode/qxfx0-main-prehook`, sha256 `af157943…`), `post` =
current binary with the flag unset, `ablat` = current binary with the
flag set. Same session id `p2-strict12` in all three, so `trcSessionId`
must match too; only `esCurrentTime` and `trcRequestId` are exempt.

- 3-turn leg: surface `pre == post == ablat`; trace `pre vs post`
  **0 differing paths**; `pre vs ablat` **0**.
- 12-turn leg (first 12 prompts of the corpus): 12 turns × 3 arms;
  surface identical; trace `pre vs post` **0 differing paths**;
  `pre vs ablat` **0**; session ids `{p2-strict12}` in all arms.

The flag-off tree is byte-identical to the pre-hook tree, so the hook
is a measurement instrument, not a behaviour change.

## 5. Predictions

| # | prediction | measured |
|---|---|---|
| P1 | 200/200 surface identity | **200/200** identical |
| P2 | 200/200 `trcPerspectiveProjections` identity | **vacuous** — 0 non-empty projections in both arms (0/200 each) |
| P3 | routing identity | **holds** as a corollary of P5: full trace identical; `trcFamilyDerivationChain` non-empty on 200/200, 12 distinct `trcFinalFamily` values, same `trcRecoveryCause`/`trcRecoveryStrategy` sets |
| P4 | persisted `PerspectiveRegistry` identical | **vacuous** as written; the substantive rebuild differs in one thread's confidence by `0.012128` (see §5.3) |
| P5 | 200/200 full-trace identity | **200/200** identical (clock, request id exempt; `trcSessionId` normalized to the dialogue id) |
| P6 | 200/200 dead self-divergence channel | **200/200** in both arms: `PredictionActive=0`, total null 0, window null 0, penalty non-zero 0 |
| P7 | 0/200 threshold reachability, min scalar > 7.0 | **0/200** on all seven thresholds; `ceScalar` n=200, min `14.094952299387305`, median `14.542892166694319`, max `14.670598572635816`; 200/200 above the 7.0 Essence floor; 0 Essence windows fire |
| P8 | baseline shows no hard Protocol B | **holds** — 0 hard triggers, 0 contour exits, 0 moves, residual n=180 mean `0.0492` max `0.160`, window max `0.134` |

### 5.1 Miss M1 — `csStability` *is* persisted

Pre-reg §4.4 says the numeric `csStability` is "not trace-visible" and
that the measurement must therefore be on derived fields. The first
half is true of `replay_trace_json`; the conclusion is false. The value
is persisted in the governance audit history:

```
governanceHistory[*].gePayload.contents.ppPerspectiveInput
  .pibConatusSlice.csStability
```

31/31 events differ between arms. Mean Δ `-0.179945`, min `-0.183382`,
max `-0.176187`; baseline min/mean/max `0.3245 / 0.5587 / 0.8046`,
ablate `0.1423 / 0.3787 / 0.6284`. The delta is exactly
`ceScalar / 80.0` per turn, as designed. This channel is **post hoc**:
it is not a pre-registered bar and does not enter B4.

### 5.2 Miss M2 — the sensitivity bound is wrong by a sign

Pre-reg §2 derives `∂conf/∂na = 0.25 − 0.20 × 0.45 = 0.16`. The code
(`Self/Perspective.hs:144–146`) is

```
it   = 0.55·cp + 0.45·(1 − na)
conf = 0.18 + support + 0.25·na − 0.35·cp − 0.20·it
```

so `∂it/∂na = −0.45` and `∂conf/∂na = 0.25 + 0.20 × 0.45 = 0.34`, not
`0.16`. The pre-reg subtracted the internal-tension term instead of
adding it. Consequences:

- predicted maximum `Δconf` `0.0056`; actual `0.34 × Δna` = up to
  `0.0125`;
- measured max `|Δconf| = 0.012470008786740427`, max
  `|Δna| = 0.036676496431589545`;
- recomputing `conf` from the recorded `na`, `cp`, `it` reproduces the
  recorded value exactly in both arms (checked on the first two
  events: `0.3314687018084732` / `0.319340698578125`).

The error is in the prediction, not in the runtime.

### 5.3 Miss M3 — P4 is vacuous, and the rebuild would miss

`canonicalizePersistedState` empties the derived registry on save
(`Bridge/StatePersistence.hs:505`:

```
selfState' = (ssSelfState ss) { selfPerspectiveRegistry = emptyPerspectiveRegistry }
```

). Restore rebuilds it from `governanceHistory`
(`Governance/Replay.hs:112–155`). Both arms therefore persist
**0 threads**, `nextPerspectiveOrdinal = 1`, `nextVersionOrdinal = 1`
in 20/20 sessions. P4 as written ("the persisted `PerspectiveRegistry`
is identical") is true and says nothing.

The honest substitute is the registry the restore path would rebuild.
The event chain records one thread in both arms: `p2-chal-01`,
`perspective-1`, version 1, status `PerspectiveContested`
(`PerspectiveAdmissibleQuarantined`, turn 2). Because
`epConfidence = pcConfidence` (`Self/Perspective/Reduce.hs:72`), that
thread's rebuilt confidence differs:

- baseline `0.3437228155584733`
- ablate `0.331594812328125`
- Δ `-0.012128003230348`

and its counterargument string embeds the same number
(`revision_pressure:quarantine:confidence=…`). The registry hashes in
the event envelopes agree: `geeAfterRef` differs on 2 events and
`geeBeforeRef` on 1 (`p2-chal-01`). No **assigned** perspective id
differs (`perspective-1` in both arms; the `pending:` ids embed the
session id and differ for that reason alone), and no version id,
status, resolved decision or admissibility tag/reason differs. So a
substantive P4 **misses** by a small, non-decisional amount; the
pre-registered literal P4 passes vacuously.

### 5.4 Miss M4 — P2 is vacuous

Both arms have **0 non-empty `trcPerspectiveProjections` on 200/200
turns**. The single quarantined thread never becomes active:
`PpdQuarantine` passes `ptActiveVersion = Nothing`
(`Self/Perspective/Reduce.hs:27, 95`), and
`buildPerspectiveProjection` requires `activeEndorsedPerspective`
(`Reduce.hs:35–37`). The other 30 events never reach the projection channel: 29 are
`PerspectiveInadmissible "insufficient_evidence"` (0 evidence, empty
stance), which returns before any threshold is evaluated
(`Self/Perspective.hs:167`), and one is
`PerspectiveInadmissible "excessive_counterargument_pressure"`
(`p2-chal-01` turn 9, `cp = 0.75 > 0.74`, guard at `:173`).

P2's "0 flips" is therefore true but empty: the projection channel is
not exercised by this corpus. It cannot be read as "the continuous
channel is inert".

### 5.5 Finding M5 — the ablation crossed the confidence gate twice

Two events moved from above `pcConfidence = 0.30` to below it:

| dialogue | turn | baseline conf | ablate conf | Δ | margin to 0.30 |
|---|---|---|---|---|---|
| `p2-terse-01` | 7 | `0.31096835559842895` | `0.2985741402372754` | `-0.012394215361153538` | `0.010968` |
| `p2-pess-01` | 10 | `0.3110581131523225` | `0.2985881043655821` | `-0.012470008786740427` | `0.011058` |

Both were already `PerspectiveInadmissible "insufficient_evidence"`,
because the evidence guard (`Self/Perspective.hs:167`) precedes the
confidence guard (`:179`). The decision therefore stayed
`PpdObserveOnly`, and the admissibility reason is identical in both
arms. This is a **near miss, not a flip**: the ablation's maximum shift
(`0.01247`) exceeds the corpus's closest margin to the gate
(`0.010968`), and the only reason nothing changed is guard order.

A second single-gate contact exists on the other side: the minimum
`na` is `0.5445078552291132` (`p2-chal-01` turn 9), margin `0.005492`
to the `0.55` conjunct at `:187`, and `Δna` reaches `0.0367`. That
event never reaches the conjunct: its counterargument pressure is
`0.75 > 0.74`, so `:173` returns
`PerspectiveInadmissible "excessive_counterargument_pressure"` in both
arms. The conjunction's other operand is also unmet there
(`conf = 0.2101 < 0.62`).

## 6. What this licenses

Licensed:

- On this corpus, removing the continuous Conatus term changed **no
  surface, no trace field, no routing decision, and no perspective
  decision** (200/200).
- All seven threshold consumers are unreachable by a factor of 2–4
  (`ceScalar` 14.09–14.67 vs floors 0–7.0), so their inertness is a
  property of the scalar's range, not of the corpus.
- The self-divergence channel is dead on a third independent corpus
  (200/200), so the A/C slices remain unmeasurable in production.
- The continuous channel is *live*: it moves candidate confidence by
  up to `0.0125` and came within `0.011` of a confidence-driven
  admissibility change on two turns.

Not licensed:

- "Conatus does not matter." The ablation removes one term of one
  derived quantity; the scalar still feeds every threshold consumer
  and is recorded truthfully.
- Any threshold change. The measurement says the floors are far away,
  not that they are wrong.
- Any claim about answer quality, M6-FELT, M7 or release readiness.
  This is a reachability/sensitivity census on one authored corpus in
  `degraded` mode, with no human evaluation.
- Any statement about the perspective layer in general. Its projection
  channel was never exercised (0/200 in both arms); the one thread it
  created stayed contested.

## 7. Reproduction

```
python3 scripts/eval/p2_ablation_report.py \
  --baseline reports/eval_runs/p2-baseline-20261118 \
  --ablate   reports/eval_runs/p2-ablate-20261118 \
  --root . --json /tmp/p2-report.json
```

The tool opens both databases `mode=ro`, pins every threshold against
the Haskell source (line comments stripped, so the WP-F `0.5` note is
not read as a second definition), normalizes `trcSessionId` by the
literal `cap-<run_id>-` prefix, and prints the vacuity flag when both
arms persist zero threads. Self-test: **19/19**. Registered in
`PYTHON_SUPPLIER_ALLOWLIST.md` §1; `check_architecture.sh` rule [24]
green.

## 8. B7 — landing matrix

**PASS** — `reports/eval_runs/_logs/matrix-20261119/summary.txt`:
10/10 steps exit 0 (`2026-11-19T14:03:42Z` → `19:31:30Z`), tree
byte-identical start→end (`tree-before.txt` == `tree-after.txt`,
11 uncommitted paths), **4 437** cases — unit 1863, fast 1964,
property 244, integration 47, main runtime 106 + http 23, slow 190
(runtime 106 / state 50 / http 23 / lifecycle 11). This line was
filled in from the log after the run (documentation only).

## 9. Follow-ups (not part of this landing)

1. **Guard order masks the confidence gate.** The
   `insufficient_evidence` guard runs first, so a candidate with no
   evidence can never reach the confidence geometry check. If the
   intent is that a low-confidence candidate is inadmissible *for that
   reason*, the guards need an explicit precedence decision. That is a
   behaviour change and needs its own pre-registration.
2. **The projection channel is unexercised.** A corpus that produces
   at least one endorsed active perspective is needed before P2's
   original question ("does the continuous channel move a projection?")
   can be answered. The current corpus produces 1 contested thread in
   200 turns.
3. **The dead self-divergence channel** still needs the follow-up
   recorded in the pre-reg §4.2: the A-slice prediction is never
   written, so neither the penalty nor `RecoverySelfDivergence` can
   fire.
4. **Sensitivity derivation in the pre-reg is wrong** (M2). Any future
   pre-registration that reuses the `0.16` coefficient should use
   `0.34` and state the sign of the internal-tension term.
