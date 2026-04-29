# ADR 0003: Datalog Runtime Fact Injection

- Status: accepted
- Date: 2026-04-22

## Context

`spec/datalog/semantic_rules.dl` encodes stable shadow-routing rules.  
Per-turn facts (`RequestedFamily`, `InputForce`, `InputAtom`, `InputAtomDetail`) are not persisted in the spec file and are injected at runtime from `QxFx0.Bridge.Datalog`.

This previously caused ambiguity: "self-contained spec" vs "runtime-injected inputs".

## Decision

We keep a split model:

1. `semantic_rules.dl` is canonical for static rule semantics.
2. turn-specific facts are injected by Haskell runtime at execution time.

This is intentional and required for per-request shadow evaluation.

## Consequences

Positive:
- Rules stay versioned and reviewable as static spec.
- Runtime can evaluate dynamic turn state without mutating spec files.

Tradeoff:
- The `.dl` file alone is not an executable end-to-end scenario without injected facts.

Guardrail:
- `release-smoke.sh` appends minimal synthetic facts to a temp file for parse/compile smoke checks.
