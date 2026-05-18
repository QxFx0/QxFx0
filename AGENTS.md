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

  Remaining planned: **Phase 7** (lifeness gates / calibration of `defaultSalienceWeights` and the four Phase-5.5d heuristics).
