# Regime Governance

**Status:** Active (M5 first pass, 2026-06-03)
**Governed by:** `QxFx0.Types.RuntimeRegime`
**Machine-visible via:** `trcRegimeVersion` in `TurnReplayTrace`, `ssCurrentRegime` in `SystemState`

---

## 1. What a regime is

A **regime** is a named, versioned bundle of:
- Mathematical constants (weights, thresholds, update laws)
- Constitution layer version (which CTS seams are active)
- Feature flag state (which promotion ADRs have been applied)

Regime metadata is machine-visible: it is stored in `SystemState.ssCurrentRegime`
and stamped into every `TurnReplayTrace` as `trcRegimeVersion`. This means:

- Replay can select the correct calibration corpus for each turn
- Operators can see which mathematical version was active when a decision was made
- Changes to math constants require a documented regime bump, not silent drift

---

## 2. Current regime (as of 2026-06-03)

**Math version:** 1
**Constitution version:** 40 (CTS-01 through CTS-40, all proposition consumers admitted)
**familyDivergenceActive:** `True` (ADR-0019 promoted 2026-06-02)
**essenceActive:** `False` (ADR-0036 pending production corpus)

See `QxFx0.Types.RuntimeRegime.defaultRuntimeRegime` for the Haskell value.

---

## 3. Versioned dependency contour

| Contour | Version field | Bump trigger | Evidence required |
|---------|--------------|--------------|-------------------|
| Normalization | `rrMathVersion` | Conatus/Salience/Field weight change | replay parity on fixed fixtures |
| Thresholds | `rrMathVersion` | Any threshold change (salience gate, conatus floor) | codomain check + replay parity |
| Update laws | `rrMathVersion` | Change to any update function in Self/* | ablation test showing new behavior |
| Reconstruction | `rrConstitutionVersion` | New CTS seam added or removed | proof run on affected proposition consumer |
| Feature flags | `rrFamilyDivergenceActive`, `rrEssenceActive` | Promotion ADR accepted | per-ADR gate criteria (G1–G4) |

---

## 4. Change-type → evidence requirement table

| Change class | `rrMathVersion` bump | Evidence required | Document |
|--------------|----------------------|-------------------|----------|
| Conatus weight shift (any `ConatusWeights` field) | **yes** | calibration corpus (N≥1k turns) + replay parity | `CALIBRATION_BACKLOG.md §2.5` |
| Salience weight default (any `SalienceWeights` field) | **yes** | corpus + driver distribution check | `CALIBRATION_BACKLOG.md §2.1` |
| Conatus floor change (`emConatusStructuralFloor`) | **yes** | codomain check + trigger rate corpus | `CALIBRATION_BACKLOG.md §2.3` |
| Salience gate threshold (`conatusGateThreshold`) | **yes** | corpus + gate fire rate check | `CALIBRATION_BACKLOG.md §2.1` |
| Field heuristic sourcing | **yes** | corpus + trcField distribution check | `CALIBRATION_BACKLOG.md §2.2` |
| New CTS seam added | **no** (constitution only) | proof run (deterministc, bounded, no-live-override) | `docs/results/CTS-N.md` |
| Promotion ADR accepted (flag flip) | **no** | per-ADR G1–G4 gates | `docs/adr/proposed/ADR-N.md` |
| GF grammar/lexicon update | **no** | GF quality gate (`scripts/gf_quality_gate.sh`) | `docs/results/GF-*.md` |
| Schema version bump (persistence shape) | **no** | migration test + schema consistency check | `docs/results/SR-*.md` |

---

## 5. Fallback-policy classification for major runtime seams

| Seam | Policy | File |
|------|--------|------|
| PGF2 linearization failure | `fail-open degraded` — returns `Left` error, caller uses fallback surface | `Runtime/PGF.hs:linearizeExpr` |
| `RussianCompatShimRoute` | `compatibility-fallback` — explicit compat route, not a failure | `Runtime/PGF.hs:56-58`, `SR-03.md` |
| `PersistenceEnvelope` decode | `compatibility-fallback` — tolerated legacy shape | `Bridge/StatePersistence.hs:400-403`, `SR-05.md` |
| schemaVersion conditional decode | `compatibility-fallback` — safe defaults for missing v1 fields | `Types/State/System.hs:335-413`, `SR-05.md` |
| Bootstrap load failure | `fail-closed` — `throwQxFx0 RuntimeInitError`, no silent continuation | `Runtime/Session/Bootstrap.hs` |
| `demoteNonAuthoritativeRestartCarry` | `fail-open degraded` — explicit demotion, not silent carry | `Bridge/StatePersistence.hs:386-394` |
| Architecture check (CI) | `fail-closed` — exits 1, blocks merge | `scripts/check_architecture.sh` |
| GF quality gate (CI) | `fail-closed` — exits 1 on any error | `scripts/gf_quality_gate.sh` |

---

## 6. Runtime architecture-debt register

| Area | Current state | Open items |
|------|--------------|------------|
| State taxonomy | Explicit (SYSTEM_STATE_AUTHORITY.md) | None |
| Commit/restore protocol | Explicit (commit_restore_state_machine.md) | None |
| Bootstrap phase boundaries | Classified (SR-04) | None |
| Control-plane seams | Explicit (sidecar_control_plane_decomposition.md) | None |
| Singleton lifecycle | Implicit (GF map, morphology data loaded once) | Document load-once contract |
| Docs/config/deploy drift | Bounded (bounded_drift_cleanup.md) | None |
| Legacy decode branches | Classified with windows (SR-05) | Close windows when triggers fire |
| PGF shim | Classified (SR-03) | Close when ClaimAst migrated |

---

## 7. Math change protocol

When you change a mathematical constant:

1. **Check the change type** against the table in §4 above
2. **If `rrMathVersion` bump required:**
   - Increment `currentMathVersion` in `QxFx0.Types.RuntimeRegime`
   - Update `MATH_CHANGE_PROTOCOL.md` with the change record
   - Collect evidence (see §4)
   - Add a calibration test that fails if the parameter drifts
3. **If constitution version bump required:**
   - Increment `currentConstitutionVersion`
   - Create `docs/results/CTS-N.md` with proof
4. **Always:** update `ROADMAP.md` "closed H2" section if the change closes an open item

---

## 8. Acceptance criteria for M5

M5 is **closed** when:

- [x] `RuntimeRegime` type exists and is machine-visible (`ssCurrentRegime`, `trcRegimeVersion`)
- [x] Change-type → evidence requirement table exists (§4 above)
- [x] Fallback-policy classification exists for major runtime seams (§5 above)
- [x] Runtime architecture-debt register exists (§6 above)
- [ ] Math change protocol is exercised at least once (first bump after calibration corpus)
- [x] `Test.Suite.M5Regime` verifies `trcRegimeVersion` is non-zero in a produced trace
- [ ] `currentMathVersion` is wired to a CI check that fails if it's stale
