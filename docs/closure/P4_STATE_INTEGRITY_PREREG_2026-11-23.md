# Pre-registration — P4: `StateIntegrity` rename + trace-only `ConatusContour` (2026-11-23)

- **Status**: PRE-REGISTERED. Predictions below are written **before**
  the rename, the contour census and the equivalence comparison. A miss
  is a finding and is reported as a miss; it is not patched in place.
- **Trigger**: P2 measured that the Conatus scalar (`ceScalar`) has one
  continuous consumer (`csStability`, weight 0.20) and seven floor
  consumers that never fired on a 200-turn corpus
  (`docs/closure/P2_ABLATION_RESULT_2026-11-19.md`). The scalar's name
  therefore carries a philosophical claim ("conatus") that the runtime
  does not support. P4 separates the name from the claim.
- **Owner decisions**:
  - 2026-11-20 (P4 fork): the scalar is renamed to `StateIntegrity`;
    the name `Conatus` survives only as a typed contour
    `ConatusContour = { blanketIntegrity, recoveryEvents,
    essenceCommitments, crisisAvailability }`; no philosophical claim
    until the contour is measured.
  - 2026-11-23: (a) **freeze all persisted JSON keys** — the rename is
    Haskell-side only, old traces and stores decode without migration;
    (b) **trace-only contour** — per-component ablation hooks are
    deferred until a consumer exists, because an ablation hook on a
    write-only field is provably inert (the P2/P4-vacuum lesson).
- **Scope**: a mechanical rename, one new pure contour record, one new
  trace field, one 200-turn census, one equivalence comparison. **No**
  threshold, weight, corpus lexicon, crisis resource or routing
  behaviour changes. No `currentMathVersion` bump: no constant and no
  consumed quantity changes.

## 1. What P4 asks

Two questions:

> (A) Does renaming the scalar change any observable behaviour?
>
> (B) On the 200-turn P2 corpus, which of the four self-maintenance
> facts the contour records are actually present?

P4 does **not** ask whether the contour should drive routing. It does
not, yet. The contour is an honest, typed observation; wiring it without
a measured reason would repeat the defect P2 exposed.

## 2. P4-A — the rename

### 2.1 Renamed

| Old | New |
|---|---|
| `ConatusEnergy` | `StateIntegrity` |
| `ConatusComponents` | `StateIntegrityComponents` |
| `ConatusWeights` | `StateIntegrityWeights` |
| `ConatusGradient` | `StateIntegrityGradient` |
| `ceScalar` / `ceComponents` | `siScalar` / `siComponents` |
| `ccMorphology` … `ccSelfDivergence` | `sicMorphology` … `sicSelfDivergence` |
| `cwMorphology` … `cwViolation` | `siwMorphology` … `siwViolation` |
| `cgMorphology` … `cgTurns` | `sigMorphology` … `sigTurns` |
| `computeConatusEnergy[With]` | `computeStateIntegrityEnergy[With]` |
| `computeConatusGradient[With]` | `computeStateIntegrityGradient[With]` |
| `conatusComponentSum`, `conatusViolationPenalty`, `conatusGateFires`, `conatusLowEnergy` | `stateIntegrity*` |
| `builtinConatusWeights`, `defaultConatusWeights` | `builtinStateIntegrityWeights`, `defaultStateIntegrityWeights` |
| `ConatusAnalysis` | `StateIntegrityAnalysis` |
| `tiConatusEnergy`, `tiConatusGateFired` | `tiStateIntegrity`, `tiStateIntegrityGateFired` |
| `psConatusEnergy`, `psConatusGateFired` | `psStateIntegrity`, `psStateIntegrityGateFired` |
| `selfConatusWeights`, `sbcConatusWeights` | `selfStateIntegrityWeights`, `sbcStateIntegrityWeights` |
| `emConatusStructuralFloor`, `emConatusFloorWindow` | `emStateIntegrityStructuralFloor`, `emStateIntegrityFloorWindow` |
| `RecoveryConatusGate`, `DrivenByConatusGate` | `RecoveryStateIntegrityGate`, `DrivenByStateIntegrityGate` |
| `TriggerConatusErosion`, `CollapseConatusExhausted`, `RuleConatusOverride`, `SbrDegradingConatus` | `TriggerStateIntegrityErosion`, `CollapseStateIntegrityExhausted`, `RuleStateIntegrityOverride`, `SbrDegradingStateIntegrity` |
| `QxFx0.Self.Conatus`, `QxFx0.Types.Self.Conatus`, `QxFx0.Types.Thresholds.Conatus` | `…StateIntegrity` |
| `Test.Suite.SelfConatus`, `Test.Suite.ConatusGate` | `Test.Suite.SelfStateIntegrity`, `Test.Suite.StateIntegrityGate` |

The full mapping is the union of the identifier census in the commit
diff. Every remaining occurrence of `Conatus` in `src/` is deliberate:
`AntiConatus*` (a move that weakens the system's position — a different
concept), `userConatusScore` / `UserConatusWeights` (the user-side R5
viability contour, not the system scalar), and the frozen wire names
below.

### 2.2 Frozen wire keys (no schema change)

These strings stay byte-identical; only the Haskell accessors around
them change:

- `trcConatusEnergy`, `trcConatusGateFired` — `TurnReplayTrace` derives
  `ToJSON`, so the **field names** stay too. The field type becomes
  `StateIntegrity`.
- `ceScalar`, `ceComponents`, `ccMorphology`, `ccIdentity`, `ccTurns`,
  `ccPenalty`, `ccSelfDivergence` — custom instances in
  `Types/Self/StateIntegrity.hs` keep the old keys.
- `cwMorphology`, `cwIdentity`, `cwTurns`, `cwViolation` — the renamed
  `StateIntegrityWeights` gets a hand-written instance with the old keys
  (the previous instance was derived).
- `cgMorphology`, `cgIdentity`, `cgTurns` — same for
  `StateIntegrityGradient`.
- `selfConatusWeights` — `SelfState` has a hand-written instance; the
  field is renamed, the string stays.
- `conatusDelta` — `KnowledgeTree` has a hand-written instance; the
  field is renamed, the string stays.
- `tasConatus`, `caEnergy`, `caScalar`, `caGateFired`, `caEnergyTrend`,
  `caAnomaly` — `TraceAnalysisSummary` / `StateIntegrityAnalysis`
  derive JSON generically, so these field names stay.
- Enum wire values: `conatus_gate`, `conatus_erosion`,
  `conatus_override`, `degrading_conatus`, `regression_conatus` — all
  produced by explicit render functions, unchanged.
- `QXFX0_ABLATE_CONATUS_STABILITY` — the P2 hook value is frozen so the
  P2 reproduction still runs; only the Haskell constant is renamed.

### 2.3 Not renamed

- Historical documents and ADRs (`docs/adr/0007-dual-mode-conatus.md`,
  `docs/THEORY.md` §4.2, dated closure reports). They record what was
  claimed at the time; rewriting them would falsify the record. The
  current-state documents (`TRACE_SCHEMA.md`, `CONTOUR_INDEX.md`,
  `SELF_LAYER_STATUS.md`) get a short note.
- `AntiConatus*` and `userConatus*` — see §2.1.

## 3. P4-B — the contour

```haskell
data BlanketIntegrity = BlanketIntegrity
  { biInvariantsHold :: !Bool
  , biViolationCount :: !Int
  }

data ConatusContour = ConatusContour
  { ctcBlanketIntegrity   :: !BlanketIntegrity
  , ctcRecoveryEvents     :: ![LocalRecoveryCause]
  , ctcEssenceCommitments :: !Int
  , ctcCrisisAvailability :: !Bool
  }
```

Computed once per turn in `buildTurnProjection` from facts the turn
already carries:

- `ctcBlanketIntegrity` — `tiBlanketViolationCount`
  (`Core/TurnPipeline/Types.hs:157`); `biInvariantsHold = count == 0`.
- `ctcRecoveryEvents` — `taLocalRecoveryCause`
  (`Finalize/Projection.hs:243–250`), the same fact the trace already
  records as `trcRecoveryCause`.
- `ctcEssenceCommitments` — `1` when the post-turn essence is
  `EssenceCommitted`, `0` otherwise (`Finalize/Projection.hs:275–290`).
- `ctcCrisisAvailability` — `crVersion crisisResourcesRu > 0` and the
  resource list is non-empty (`Safety/CrisisGuard.hs:258`). The hard
  gate is lexical and cannot be unavailable; the field makes that
  structural fact machine-visible.

Trace: `trcConatusContour :: !(Maybe ConatusContour)` on
`TurnReplayTrace`, decoded with `.:?` so pre-P4 traces yield `Nothing`.
New turns always carry `Just`.

## 4. Predictions (before measurement)

### P4-A — equivalence

- **E1**: the 11-turn strict golden corpus renders **11/11 identical**
  surfaces against `spec/golden/render_snapshots_2026-11-21.tsv`.
- **E2**: on a fixed 11-turn session, the full replay trace of the
  pre-rename binary and the post-rename binary is identical after
  removing `trcRequestId`, `trcReplayEnvelope`, `trcSessionId`,
  `trcConatusContour` and `esCurrentTime`. (The first four are the known
  per-run identifiers; the last is the recorded clock.)
- **E3**: unit, fast, property, integration and the runtime/http/slow
  groups stay green; the matrix is 10/10 exit 0 and the tree is
  byte-identical start→end.

### P4-B — 200-turn census (`spec/eval/p2_baseline_2026-11-18.tsv`, degraded)

- **C1**: `trcConatusContour` is present on **200/200** turns.
- **C2**: `biInvariantsHold` is `True` and `biViolationCount` is `0` on
  **200/200** turns. (A violated blanket aborts the turn in
  `Finalize/Commit.hs:84–89`, so a persisted turn cannot carry one.)
- **C3**: `ctcEssenceCommitments == 1` on **≥ 180/200** turns. The
  corpus is definitional/challenge dialogue; essence commits early and
  stays committed.
- **C4**: `ctcRecoveryEvents` is non-empty on **≥ 1/200** turns, and
  `RecoveryStateIntegrityGate` is the cause on **0/200**. P2 measured
  the gate at 0/200; other recovery causes are the only candidates.
- **C5**: `ctcCrisisAvailability` is `True` on **200/200** turns.
- **C6** (regression guard, not a prediction): hard-trigger Protocol B
  stays **0/200**; the contour is observational and cannot change the
  protocol verdict.

## 5. Bars

| Bar | Check |
|---|---|
| B1 | `cabal build` green with `-Werror`; no new warnings |
| B2 | golden snapshots 11/11 |
| B3 | E2 trace comparison: 0 differing paths outside the excluded set |
| B4 | unit / fast / property / integration green |
| B5 | 200-turn census C1–C6 measured and reported |
| B6 | matrix 10/10 exit 0, tree byte-identical start→end |
| B7 | `check_architecture.sh` green, including rule [24] and [25] |

## 6. Non-claims

- This is **not** evidence that the contour matters. It is a census of
  what the contour records. No routing, recovery or surface decision
  reads it.
- This is **not** a claim about answer quality, M6-FELT, M7, the
  500-prompt gate or release readiness. The 500-prompt gate stays
  BLOCKED.
- No philosophical claim is made about "conatus". The word now names a
  typed contour of four measurable self-maintenance facts, not a
  vitality scalar.
