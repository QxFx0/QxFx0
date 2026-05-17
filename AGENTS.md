# QxFx0 Operator Notes

- Decision and response generation are local-first and deterministic.
- Runtime recovery is represented via local recovery trace fields (`trcLocalRecoveryPolicy`, `trcRecoveryCause`, `trcRecoveryStrategy`, `trcRecoveryEvidence`).
- Verification/release gates must keep replay envelope fields aligned with runtime contracts.
- The `QxFx0.Self.*` subtree is the pure self-layer of the dual-mode runtime: Phases 1–2 ship `SelfBlanket` invariants and the `Conatus` functional (commits `62d0338`, `a5fad49`); Phase 3 ships the `Holistic ⊣ Formal` adjunction (ADR-0008, commit `20d5611`); Phase 4 ships the right-hemispheric `Field` record with five components (ADR-0009, commit `036f70f`). Phases 5–8 (salience controller, effect refactor, lifeness gates, publication) remain planned.
