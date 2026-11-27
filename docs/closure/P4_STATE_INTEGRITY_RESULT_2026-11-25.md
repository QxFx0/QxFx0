# P4 — StateIntegrity rename + trace-only contour (result)

- **Date**: 2026-11-25
- **Pre-registration**: `docs/closure/P4_STATE_INTEGRITY_PREREG_2026-11-23.md`
- **Status**: working tree, pending owner approval. No commit, no push.
- **Owner decision this implements (2026-11-20)**: the audit recommendation —
  the scalar is renamed to `StateIntegrity`; `Conatus` survives only as a
  typed contour of four measured self-maintenance facts; no philosophical
  claim until the contour is measured.

This document records what was read, what changed, the equivalence evidence,
the measurement, the deviations, and the bars.

---

## 1. What was read (with citations)

| Site | What it is |
|---|---|
| `src/QxFx0/Self/Conatus.hs` @ `88389c2` | the scalar functional: `C(b,v) = Σ w·log(1+·) − λ·|v|`, two named default bindings, no philosophical claim in the code itself |
| `src/QxFx0/Types/Self/Conatus.hs` @ `88389c2` | `ConatusEnergy`/`ConatusComponents`/`ConatusGradient`; derived JSON instances (`ce*`, `cc*`, `cg*` are therefore **wire**, not Haskell detail) |
| `src/QxFx0/Types/Thresholds/Conatus.hs` @ `88389c2` | the four weight constants (`1.0`, `0.5`, `0.25`, `10.0`) and `conatusLowEnergy = 3.0` |
| `src/QxFx0/Core/TurnPipeline/Finalize/Projection.hs:229–236` | `computeConatusContour` call site (new); sources are `tiBlanketViolationCount`, `taLocalRecoveryCause`, post-turn `selfEssence`, `crisisResourcesRu` |
| `src/QxFx0/Types/Recovery.hs:133` | `RecoveryStateIntegrityGate` renders the **frozen** tag `conatus_gate` |
| `src/QxFx0/Self/Deliberation.hs:447` | `RuleStateIntegrityOverride` renders `conatus_override` |
| `src/QxFx0/Self/Salience.hs:418` | `DrivenByStateIntegrityGate` renders `conatus_gate` |
| `src/QxFx0/Learning/Loop.hs:438`, `Sandbox.hs:259`, `TrainingCycle.hs:560` | `degrading_conatus`, `regression_conatus` unchanged |
| `src/QxFx0/Runtime/Session/SelfConfig.hs:108` + `resources/config/conatus_weights.json` | bootstrap reads `resources/config/conatus_weights.json`; the file carries `cwMorphology`/`cwIdentity`/`cwTurns`/`cwViolation` |
| `src/QxFx0/Runtime/Wiring/Handlers.hs:267` + `Finalize/Precommit.hs:74` | allowlist and read of `QXFX0_ABLATE_CONATUS_STABILITY` (frozen value) |

The decisive reading: the JSON keys are produced by **derived** instances in
the scalar types, and by the persisted `SelfState`/`Essence`/`FamilyTarget`/
`SignalComponents`/`SalienceWeights` records. A blind identifier rename would
therefore have silently changed the store and trace schema. That is why the
landing is a rename **plus** hand-written instances (§2.3) and a pin suite
(§2.5).

---

## 2. What changed

### 2.1 Rename (mechanical + reviewed)

`git status --porcelain` before staging: 127 modified + 5 renamed + 9 new
entries. The commit touches **146 paths** (143 `git show --stat` entries:
11 added, 2 deleted, 127 modified, 3 renames — git re-detected two of the
five `git mv` renames as delete+add once the wire-compat instances dropped
their similarity below 50%). `git mv` for the five moved modules/suites:

`QxFx0.Self.Conatus` → `QxFx0.Self.StateIntegrity`,
`QxFx0.Types.Self.Conatus` → `QxFx0.Types.Self.StateIntegrity`,
`QxFx0.Types.Thresholds.Conatus` → `QxFx0.Types.Thresholds.StateIntegrity`,
`Test.Suite.SelfConatus` → `Test.Suite.SelfStateIntegrity`,
`Test.Suite.ConatusGate` → `Test.Suite.StateIntegrityGate`.

The mapping is the prereg §2.1 table. Implementation detail beyond the table,
reported rather than silently absorbed:

- `apStateIntegrityEnergy`, `ctStateIntegrityEnergy`,
  `rtsStateIntegrityEnergy` — the `CorpusTrace`/`TraceAnalysisSummary`
  accessors produced by the same rule (`*ConatusEnergy` → `*StateIntegrityEnergy`
  → simplified to `*StateIntegrity` at the first two, kept at the third so the
  generic JSON key `rtsStateIntegrityEnergy` is *not* used: `tasConatus` is the
  frozen key that the summary actually emits).
- `fppStateIntegrity` — follows the `ti*`/`ps*` rule in the table; the table
  did not list the `fpp*` projection-field family explicitly.
- Haskell record fields of the three scalar records are `si*`/`sic*`/`sig*`
  (`siScalar`, `sicMorphology`, `sigTurns`, …); their **JSON** keys stay
  `ce*`/`cc*`/`cg*`.

### 2.2 Frozen wire (verified against the running artifacts)

Frozen keys are byte-identical and pinned by tests: `trcConatusEnergy`,
`trcConatusGateFired`, `ceScalar`, `ceComponents`, `cc*`, `cw*`, `cg*`,
`selfConatusWeights`, `ftMinConatus`, `scConatusTrend`, `etConatusFloor`,
`ewConatusScalar`, `conatusGateThreshold`, `conatusDelta`, `tasConatus`,
enum values `conatus_gate`/`conatus_erosion`/`conatus_override`/
`degrading_conatus`/`regression_conatus`, the constructor spellings
`DrivenByConatusGate`/`RuleConatusOverride`/`TriggerConatusErosion`/
`RecoveryConatusGate`, the config filename `resources/config/conatus_weights.json`,
the fixture `conatus-erosion.jsonl`, and the env **value**
`QXFX0_ABLATE_CONATUS_STABILITY`.

### 2.3 Hand-written instances (eight nested surfaces)

`Types/Self/StateIntegrity.hs` (`StateIntegrity`, `…Components`, `…Gradient`,
`…Weights`), `Types/Self/Essence.hs` (`EssenceTrajectory`, `EssenceWitness`),
`Types/Self/FamilyTargets.hs` (`FamilyTarget`), `Types/Learning/Signal.hs`
(`SignalComponents`), `Types/Self/Salience.hs` (`SalienceWeights`,
`SalienceDriver`), `Types/Self/Deliberation.hs` (`ReconcileRule`),
`Runtime/StateDefaults.hs` (`SelfState`). The shared mapping helper is
`QxFx0.Internal.WireCompat.legacyConatusLabel`
(`StateIntegrity`/`stateIntegrity` → `Conatus`/`conatus`, verbatim elsewhere),
used as `fieldLabelModifier` on both encode and decode.

### 2.4 Trace-only contour

`QxFx0.Types.Self.ConatusContour` + `QxFx0.Self.ConatusContour`:

```
trcConatusContour :: !(Maybe ConatusContour)
  ctcBlanketIntegrity   = BlanketIntegrity { biInvariantsHold, biViolationCount }
  ctcRecoveryEvents     = [LocalRecoveryCause]
  ctcEssenceCommitments = Int      -- 1 when the post-turn essence is committed
  ctcCrisisAvailability = Bool     -- version > 0 and at least one resource line
```

Decoded with `.:?` (pre-P4 traces yield `Nothing`). `TRACE_SCHEMA.md` §15
documents it; §2 carries a rename note. **Nothing reads it** — `rg` finds the
write site (`Finalize/Projection.hs:425`) and the type modules only. The
per-component ablation hooks are deferred: an ablation of a write-only field
is provably inert, which is the P2/P4 vacuity lesson.

### 2.5 Pins (25 new cases)

- `Test.Suite.ConatusContour` (12): violation counting, recovery cause
  carrying, essence mapping, crisis-pack availability, JSON keys and
  round-trip.
- `Test.Suite.StateIntegrityWire` (13): `ce*`/`cc*`/`cw*`/`cg*`,
  `conatusGateThreshold`, `ftMinConatus`, `scConatusTrend`,
  `DrivenByConatusGate`, `RuleConatusOverride`, `TriggerConatusErosion`,
  `ewConatusScalar`, `etConatusFloor`, `selfConatusWeights` — each pin
  asserts the old key **and** the absence of a new one.

Both suites are registered in `qxfx0-test`, `qxfx0-test-unit` and
`qxfx0-test-fast`.

### 2.6 Docs and tooling

`TRACE_SCHEMA.md` (§2 note, §15), `CONTOUR_INDEX.md` (§2 note),
`SELF_LAYER_STATUS.md` (two rows), and the tooling blast radius in §4.

---

## 3. Equivalence evidence (E1–E3)

- **E1 (surfaces)** — `python3 scripts/eval/render_snapshots.py --check`:
  **11/11 match** against `spec/golden/render_snapshots_2026-11-21.tsv`
  (re-run on the final binary, §7 B2).
- **E2 (traces)** — a pre-rename binary built from `88389c2` in a detached
  worktree (sha256 `857050a28bcee69093124ebda7b0b3f798c249e4916e6ccfb4140ad974bcf0f6`)
  and the post-rename binary ran the same 11 golden-corpus prompts as one
  session. **11/11 traces identical** after removing
  `trcRequestId`, `trcSessionId`, `trcReplayEnvelope`, `trcConatusContour`,
  `trcEffectSnapshot.esCurrentTime`.
  The ad-hoc driver for that run lived in `/tmp` and was lost with the
  temporary worktree, so the committed `scripts/eval/trace_equivalence.py`
  (§4.1) replaces it. A supplementary 200-turn comparison is reported in
  §5.3; it is reproducible from two capture databases but is **not**
  rename-only (the only 200-turn pre-rename DB available predates P3), so
  the 11-turn comparison above remains the clean E2 measurement.
- **E3 (suites)** — §7 B4/B6.

Supporting static readings (no behaviour claim beyond "the arithmetic did not
change"): the four weight constants and `stateIntegrityLowEnergy` are
byte-identical to `88389c2`; the scalar/gradient expressions differ only in
record-field names (`cwMorphology` → `siwMorphology`, `ccSelfDivergence` →
`sicSelfDivergence`, `cg*` → `sig*`).

---

## 4. Tooling blast radius

### 4.1 New: `scripts/eval/trace_equivalence.py` (17 self-test cases)

Compares two trace streams (capture DBs `mode=ro`, or JSONL) path by path with
an explicit ignore list; a length mismatch is FAIL, not equivalence. Registered
in `PYTHON_SUPPLIER_ALLOWLIST.md` §1 (fifteen tools). It reproduces the known
P2 result on real data: baseline vs ablation arms, **200 traces, 0 differing
traces**, which is what the P2 report independently records as "trace identity
200/200".

### 4.2 Updated: `scripts/eval/p2_ablation_report.py`

The threshold pins pointed at pre-rename paths/identifiers. Updated to
`stateIntegrityGateThreshold` (`Self/Salience.hs`), `cpStateIntegrityFloor`
(`Types/State/Stance.hs`), `stateIntegrityLowEnergy`
(`Types/Thresholds/StateIntegrity.hs`), `emStateIntegrityStructuralFloor`
(`Self/Essence.hs`), ladder `siScalar stateIntegrity`. Self-test 19/19; a real
run on the P2 arms reproduces the recorded P2 readings exactly (200/200
surface and trace identity, 31/31 governance events, mean Δ −0.179945, 0/200
reachability on all seven floors).

### 4.3 Fixed while in scope: `data/calibration/ranges.json` + codomain gate

`bash scripts/check_calibration_codomain.sh` was **red on `88389c2`**
(4 violations: the spec pointed `cwMorphology`/`cwIdentity`/`cwTurns`/
`cwViolation` at `Self/Conatus.hs`, where those are record-pattern bindings,
not numeric defaults). The rename made the same entries red for a second
reason. The entries now point at
`src/QxFx0/Types/Thresholds/StateIntegrity.hs` and the numeric constants
(`stateIntegrityWeight*`, `siw*` labels). Gate: **rc=0**.
This is a pre-existing red repaired, not a new behaviour change; the extended
(nightly) profile's gate 3b is the only consumer.

### 4.4 Updated: `docs/closure/HADDOCK_STACKING_BASELINE.tsv`

Three salience declaration signatures carried `ConatusEnergy`; updated to the
current signatures. Rule [25]: 21 baselined sites, 0 new.

### 4.5 Reverted in the rename pass (wire/documentation defects it had introduced)

The mechanical pass had renamed three strings that are **not** Haskell
identifiers:

1. `Learning/Parser.hs:30` — the documented LLM schema said
   `"stateIntegrityDelta"` while the parser and `KnowledgeTree` read
   `conatusDelta`. Reverted to `conatusDelta`.
2. `Learning/Parser.hs:131` — the rigid text format said `StateIntegrityDelta:`
   while the parser lower-cases keys and looks up `conatusdelta`; an LLM
   following the doc would have had its delta silently read as `0.0`.
   Reverted to `ConatusDelta:`.
3. `Observability/TraceAnalysis.hs:677` — the operator log prefix had become
   `"State-integrity anomaly: "`. Reverted to `"Conatus anomaly: "`: P4-A
   freezes observable strings, and the rename table does not cover log prose.

Left as-is deliberately: `Semantic/Stance.hs:76` collapse reason
`"conatus energy exhausted while defending"` (prose, and an anomaly surface
input), and the JSON error-context labels (`withObject "StateIntegrity…"`),
which are exception text, not keys.

### 4.6 CI docs gate: `scripts/check_doc_module_paths.py` (failed on the first push, fixed)

The first pushed tip `176b476` failed **CI Core Contract** at the
`Check docs module paths` step: 18 references to `QxFx0.Self.Conatus` in
historical documents (`THEORY.md`, ADRs 0010/0045, the calibration report,
`CONTOUR_INDEX.md`, `TRACE_SCHEMA.md`, the trace-gap log, the two effect/
essence specs, and the rename table in the prereg/result) were reported
`STALE (unresolved)`. The rename decision keeps the old name in exactly
those documents, so the gate was taught the exception rather than the
record being edited.

A new `HISTORICAL_RENAMES` set covers the three pre-rename module paths
(`QxFx0.Self.Conatus`, `QxFx0.Types.Self.Conatus`,
`QxFx0.Types.Thresholds.Conatus`) and reports them
`INTENTIONAL (historical name kept)`; new documents must use
`StateIntegrity`, and any other missing module still fails.

Verification: the full `docs/` scan is **rc=0** and accepts 23 historical
references (18 `Self.Conatus` + 2 `Types.Self.Conatus` + 3
`Types.Thresholds.Conatus`; the five `Types.*` spellings were previously
accepted silently by the longest-prefix heuristic, not by an explicit
decision). Red check: a temp doc with a nonexistent module under the self
tree (`Self.NonexistentModule`, no `QxFx0.` prefix so this sentence itself
is not a reference) is **rc=1** `STALE (unresolved)`; a temp doc with only
the old `Conatus` path is **rc=0**.

This gate runs in CI only — it is not part of `check_architecture.sh`, which
is why the local B7 run was green. That is a verification-scope miss of this
landing, recorded here rather than hidden.

---

## 5. Measurement — 200-turn contour census (P4-B)

Corpus: `spec/eval/p2_baseline_2026-11-18.tsv` (20 dialogues × 10 turns,
sha256 `49b6d6c3…444b7`), `QXFX0_RUNTIME_MODE=degraded`, one process per
turn, own DB.
Run directory: `reports/eval_runs/p4-contour-20261126/` (gitignored).
Census tool: `scripts/eval/p4_contour_census.py` (read-only, 12 self-test cases).

Run identity: binary sha256 `63b62802…` (built from the P4 working tree;
`git_head=88389c2`, `git_dirty_files=140`, so this is **not** a clean-tree
run), started `2026-11-26T17:38:41Z`, last turn `19:26:46Z`. The first
attempt (`p4-contour-20261123`) was discarded: its executable was rebuilt
four minutes into the run (`bd75b145…` → `63b62802…`), so its 57 turns are
not a single-binary sample. It remains under
`p4-contour-20261123-aborted/` and is not used.

Driver gate: **8/8 PASS** — 200 turns persisted, 200 regime records, 0
missing regime, 0 hard-trigger Protocol B, protocol B == 0 contour exits,
encoder versions `[2]`, 180 residual samples, 180 window samples.
Measured regime: 0 contour exits, 0 moves, residual mean 0.0492 / max
0.160, window mean 0.0505 / max 0.134, 0 over-threshold.

| Prediction | Measured | Verdict |
|---|---|---|
| **C1** contour present 200/200 | 200/200 | **PASS** |
| **C2** blanket holds 200/200, violation count 0 | 200/200, `{0: 200}` | **PASS** |
| **C3** `ctcEssenceCommitments == 1` on ≥ 180/200 | **0/200** | **FAIL (prediction miss)** |
| **C4** recovery events non-empty ≥ 1/200; `conatus_gate` 0/200 | 200/200; 0/200 | **PASS** (the non-empty leg is trivial in degraded mode) |
| **C5** crisis availability 200/200 | 200/200 | **PASS** |
| **C6** hard-trigger Protocol B 0/200 | 0/200 (0 contour exits) | **PASS** |

**C3 is a real prediction miss.** In degraded mode the essence never
commits: the trace records `trcEssenceMode = "witnessing"` and
`trcEssenceCommitted = false` on every turn. The pre-rename P2 baseline DB
(same corpus, same mode) shows exactly the same 0/200 in both of its arms,
so this is not a regression and not a rename effect — it is the prereg's
assumption about degraded-mode essence committing that was wrong. The
contour faithfully records `ctcEssenceCommitments = 0`; the count is
correct, the prediction is not.

**C4's non-empty leg is met trivially.** The causes are `runtime_degraded`
151, `learning_need` 45, `render_blocked` 4. The prereg's substantive leg —
`RecoveryStateIntegrityGate` (frozen tag `conatus_gate`) on 0/200 — holds.
A non-empty recovery list in degraded mode is not evidence of recovery
activity; the degraded marker is stamped by the mode itself.

### 5.3 Supplementary 200-turn trace comparison

`scripts/eval/trace_equivalence.py --old reports/eval_runs/p2-baseline-20261118/capture.db
--new reports/eval_runs/p4-contour-20261126/capture.db`: 200 vs 200 traces,
aligned by `(dialogue, turn)`; **170/200 identical** after the prereg ignore
set; **30/200 differ**, and every differing path is a **P3** change, not the
rename:

- 29 traces differ only in `trcPreSafetyRenderedRaw` and
  `trcRenderedAfterRebind`: the P3-1 basis suffix (`основание: X` became
  `основание совпадает с тезисом; нужен внешний критерий` /
  `Основание совпало с тезисом дословно…`), which exists at `88389c2`
  (`ResponsePlan.hs:638–639,672`) and not before P3.
- 1 trace (`p2-terse-01` t1) additionally differs in `trcGenerationTrace`
  (a `contentless_guard` step), `trcDerivationTags.0`
  (`surface=contentless_filler`) and `trcArtifactManifest.amPgfHash`. Both
  strings exist at `88389c2` (`Render.hs:463–465`) and are absent at
  `b674a65`, so this is P3's contentless guard, including its fix of the
  glued `Образно:` line.

No other trace field differs on any of the 200 turns. The comparison is
therefore **rename-inert on 200 turns**, but it is not a pure
pre-rename/post-rename measurement: the only 200-turn pre-rename DB
available was produced on the P2 working tree (`git_head=085d0b0`), before
P3. A rename-only 200-turn leg would require rebuilding `88389c2` and
re-running the corpus; it was not run, and the 11-turn E2 (§3) remains the
direct rename-only evidence.

---

## 6. Deviations and scope boundaries

- **Scope boundaries (not renamed, by decision)**: `AntiConatus*` /
  `antiConatusMove` / `mkAntiConatus` / `detectAntiConatusChoice` (a move that
  weakens the system's position — a different concept), and
  `userConatusScore` / `UserConatusWeights` / `ur5ConatusScore`
  (`User/R5.hs` — the user-side viability contour, deliberately not the
  system scalar). `r5_predict.py` pins `defaultUserConatusWeights` by name and
  still runs.
- **Historical documents keep the old name** (ADRs, `THEORY.md`, dated
  closure reports). Rewriting them would falsify the record.
- **Operator log prefixes** keep `Conatus` (§4.5.3); only source comments and
  Haddock describe the new name.
- **Test assertion labels**: most keep the historical constructor spellings
  (`"… RecoveryConatusGate"`), because those are wire values; four labels that
  named identifiers which no longer exist were updated
  (`emStateIntegrityStructuralFloor`, `TrRegressionStateIntegrity`,
  `ReplayStateIntegrity`, `psStateIntegrity`,
  `propStateIntegrityOverridesEverything`).
- **Predictions**: reported as measured, misses included, in §5. No
  prediction was edited after measurement.

---

## 7. Bars

| Bar | Check | Status |
|---|---|---|
| B1 | `cabal build` green with `-Werror`; no new warnings | PASS (§7.1) |
| B2 | golden snapshots 11/11 | PASS (§7.2) |
| B3 | E2 trace comparison: 0 differing paths outside the excluded set | PASS (§3) |
| B4 | unit / fast / property / integration green | PASS (§7.3) |
| B5 | 200-turn census C1–C6 measured and reported | PASS (§5; C3 is a reported miss) |
| B6 | matrix 10/10 exit 0, tree byte-identical start→end | PASS (§7.4) |
| B7 | `check_architecture.sh` green, including rule [24] and [25] | PASS locally; the CI docs gate failed on `176b476` and is green after the §4.6 follow-up |

### 7.1 Build

`cabal build all -j2` from the final working tree: **exit 0**, 1 min 21 s
(mostly cached; the six test suites relinked), no `warning:`/`error:`
lines in the log. The library stanza carries `-Werror`
(`qxfx0.cabal:45`). `cabal build qxfx0-main` reports the executable
content-hash up to date at `sha256 63b62802…`.

### 7.2 Golden snapshots

`python3 scripts/eval/render_snapshots.py --check` on the final binary:
`render snapshots: 11/11 match` (the success line is printed only in the
no-mismatch branch, which returns 0; a mismatch prints the diff and returns 1).

### 7.3 Suites

Matrix `matrix-20261126` (`reports/eval_runs/_logs/matrix-20261126/`,
gitignored), ten steps, every step **exit 0** and no non-zero
`Errors:`/`Failures:` line in any log:

| Step | Cases | Wall |
|---|---|---|
| unit | 1 890 | 67 s |
| fast | 1 992 | 3 623 s |
| property | 245 | 19 s |
| integration | 47 | 633 s |
| main-http | 23 | 542 s |
| slow-http | 23 | 551 s |
| slow-lifecycle | 11 | 458 s |
| main-runtime | 106 | 5 813 s |
| slow-state | 50 | 3 959 s |
| slow-runtime | 106 | 4 762 s |

Total **4 493** cases. `unit` and `fast` are each +25 over the P3 matrix
(1 865→1 890 and 1 967→1 992): the two P4 pin suites. The main *core*
slice is not run by the matrix on this box (the documented OOM contour);
the two P4 suites were exercised through it directly with
`QXFX0_AGGREGATE_GROUP=core QXFX0_CORE_SUITE=ConatusContour,StateIntegrityWire`
— **25/25, exit 0**.

### 7.4 Matrix

`matrix-20261126`: start `2026-11-26T19:37:49Z`, end
`2026-11-27T01:18:17Z` (5 h 40 min), **10/10 exit 0**. Tree identity is a
content hash over every tracked + untracked non-ignored file plus
`git status --porcelain`: `eb56f413…` before and after — **byte-identical**.
The tree was frozen for the whole window; `cabal build all -j2` (§7.1) ran
before it started.

### 7.5 CI

First push `176b476` (2026-11-27T08:52Z): **CI Fast green**; **CI Core
Contract red** at `Check docs module paths` — 18 historical
`QxFx0.Self.Conatus` references (§4.6). The fix is the follow-up commit on
top of `176b476`; the re-run IDs are recorded in `AGENTS.md` once green.
This landing is not closed until both CI runs are green.

---

## 8. Non-claims

- This is **not** evidence that the contour matters. It records four facts; no
  decision reads them.
- This is **not** a claim about answer quality, M6-FELT, M7, the 500-prompt
  gate or release readiness. The 500-prompt gate stays BLOCKED.
- No philosophical claim is made about "conatus". The word names a typed
  contour now, not a vitality.
