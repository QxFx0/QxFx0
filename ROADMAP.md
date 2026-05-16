# Roadmap

This roadmap tracks engineering priorities, not marketing milestones.

## Near term

1. Harden core contract reproducibility from clean checkout.
2. Reduce fallback surfaces in RU/EN rendering while preserving deterministic
   gating.
3. Expand and validate lexicon coverage with collision-safe generation.

## Mid term

1. Split oversized modules (`Semantic.Proposition`, `Render.Dialogue`,
   `Semantic.Input.Assemble`) into reviewable units.
2. Improve property-based testing depth for routing and rendering invariants.
3. Stabilize extended contract runs on high-memory infrastructure.

## Long term

1. Domain-specific constrained reasoning packs (e.g. legal/medical corpora)
   with explicit uncertainty boundaries.
2. Stronger release artifact reproducibility and evidence index discipline.
3. Broader interoperability documentation for external integrators.
