# QxFx0 Operator Notes

- Decision and response generation are local-first and deterministic.
- Runtime recovery is represented via local recovery trace fields (`trcLocalRecoveryPolicy`, `trcRecoveryCause`, `trcRecoveryStrategy`, `trcRecoveryEvidence`).
- Verification/release gates must keep replay envelope fields aligned with runtime contracts.
- The `QxFx0.Self.*` subtree is the pure self-layer of the dual-mode runtime. Landed phases:
  - **Phases 1–2** — `SelfBlanket` invariants and the `Conatus` functional (commits `62d0338`, `a5fad49`).
  - **Phase 3** — `Holistic ⊣ Formal` adjunction (ADR-0008, commit `20d5611`).
  - **Phase 4** — right-hemispheric `Field` record with five components (ADR-0009, commit `036f70f`).
  - **Phase 5** — salience controller (ADR-0010); **Phases 5.5d/5.5e** wire the pre-turn `Field` and trace observability.
  - **Phase 6 / M6.1** — single-source-of-truth Conatus refactor: `tiConatusEnergy` / `tiConatusGateFired` / `tiField` are computed once in `PrepareStatic` and shared across the turn.
  - **Phase 8** (Packages A/B/C/D) — deliberation framework (ADR-0011): `reconcile` replaces priority-switching in routing; Package C introduced observability-grade tone divergence; Package D corrected the adjunction caller mapping, removed `applySalienceEscalation`, and added the `familyDivergenceEnabled` feature flag (default `False`).
  - **Phase 9–10 (essence commitment) landed 2026-05-19**: pure
    `QxFx0.Self.Essence` module with `Essence` Σ-type, `witness` /
    `shouldCommit` / `extractMode` / `commit` morphisms,
    `EssenceModulation` tunables, `validatePlan` post-commitment guard,
    trajectory threading through `SystemState` / `TurnInput` /
    `PrepareStatic`, four nullable trace fields in `TurnReplayTrace`,
    `EssenceRupture` exception in `QxFx0.ExceptionPolicy`,
    reconcile-time courtesy via optional predicate to `reconcile`.
    Default `essenceCommitmentEnabled = False`; flag-on integration
    replay confirms zero spurious ruptures.

  **Phase 7 (structural calibration infrastructure) completed 2026-05-18**:
  `FieldHeuristics` + 3 compute functions extracted from Phase-5.5d
  inline constants; `defaultSalienceWeights` lifeness property tests
  (range, monotonicity, Conatus-priority) landed in
  `Test.Suite.SelfField` and `Test.Suite.SelfSalience`.
  Empirical tuning against production trace corpora remains deferred.
