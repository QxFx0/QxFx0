# Roadmap

This roadmap tracks engineering priorities, not marketing milestones.

## Recently landed (2026-05-17)

1. **Phase 2.5 (M2d) — runtime Conatus as primary recovery driver.**
   Runtime `ConatusEnergy` computed once per turn (replacing the
   placeholder) and threaded through the recovery decision; the
   Conatus gate now priority-overrides shadow, parser, legitimacy,
   and runtime-mode guards in `buildLocalRecoveryPlan`.
2. **Dedicated `RecoveryConatusGate` cause variant.** Splits the
   structural-Conatus event from the environmental
   `RecoveryRuntimeDegraded` event in the trace and JSON schema
   (snake_case tag `"conatus_gate"`).
3. **Phase 5.5e — Salience verdict in `TurnReplayTrace`.** Three
   new strict trace fields (`trcSalienceDriver`,
   `trcSalienceHolisticBias`, `trcSalienceConfidence`) recording
   the post-turn controller verdict. Audit consumers can now
   reconstruct *why* the controller dispatched, not only *what*.
4. **Phase 5.5d — canonical pre-turn `Field`.** Four of five
   Field components now sourced from runtime signals (Resonance,
   Atmosphere, Consolidation, Counterfactual); `FieldConfidence`
   stays at `emptyField` default pending calibration. Sourcing
   decisions documented in ADR-0009 addendum.
5. **Phase 6 — single-source-of-truth Conatus refactor.**
   Eliminated three duplicate `computeSelfBlanket` /
   `checkInitialBlanket` / `computeConatusEnergy` call sites; the
   Prepare stage is the canonical source, downstream consumers
   read from `TurnInput`.
6. **Test coverage.** New unit suite `Test.Suite.PhaseM2d`
   (8 tests) and a pipeline-level integration test
   (`testConatusGateFiresRecoveryConatusGate`) verifying the
   Conatus gate emits the dedicated cause end-to-end.

See `CHANGELOG.md`, ADR-0005 addendum, ADR-0009 addendum, and
ADR-0010 addendum (all dated 2026-05-17) for the detailed
record.

## Near term

1. Verify the post-M2d chain end-to-end on adequate-RAM
   infrastructure: `cabal build lib:qxfx0`, all five test
   variants (fast / unit / property / integration / slow / full),
   `scripts/verify.sh`, and `scripts/release-smoke.sh`. The
   chain was committed in source form but not yet built or run
   on this machine (RAM-budget constraint).
2. Optional wiring of `deriveFieldConfidence` in
   `buildPrepareEffectPlan` once Phase 7 calibration data is
   available (currently `fieldConfidence` stays at the
   `emptyField` default of `1.0`).
3. Harden core contract reproducibility from clean checkout.
4. Reduce fallback surfaces in RU/EN rendering while preserving
   deterministic gating.
5. Expand and validate lexicon coverage with collision-safe
   generation.

## Mid term

1. Split oversized modules (`Semantic.Proposition`, `Render.Dialogue`,
   `Semantic.Input.Assemble`) into reviewable units.
2. Improve property-based testing depth for routing and rendering
   invariants. The M2d/5.5e/6 chain landed concrete property and
   integration tests; broader coverage of the SelfSalience /
   Conatus interaction surface remains an open invitation.
3. Stabilize extended contract runs on high-memory infrastructure.
4. Symmetric post-turn `Field` construction in
   `Finalize/State.hs` — the trace currently uses `emptyField`
   on the post-turn path, while the pre-turn `tiField` is real;
   making the trace symmetric closes the Phase 5.5d work.

## Long term

1. **Phase 7 — calibration of `defaultSalienceWeights` and the
   four Phase-5.5d heuristics** (Resonance, Consolidation,
   Counterfactual, Atmosphere) against production-grade trace
   corpora. The current weights and formulas are defensible
   per ADR-0009/0010 but not empirically tuned.
2. Domain-specific constrained reasoning packs (e.g.
   legal/medical corpora) with explicit uncertainty boundaries.
3. Stronger release artifact reproducibility and evidence index
   discipline.
4. Broader interoperability documentation for external integrators.
