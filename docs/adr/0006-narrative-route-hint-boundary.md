# ADR 0006: Narrative As Route Hint (Bounded)

## Status

Accepted (2026-04-23).

## Context

Narrative/intuition signals are useful for route quality, but they must not silently bypass constitutional guards (shadow gate, legitimacy gate).
Without explicit boundary policy, route behavior can drift into implicit precedence rules.

## Decision

1. Narrative and intuition are allowed as route hints.
2. They are never allowed to bypass hard gates:
   - strict shadow policy (`ShadowBlockOnUnavailableOrDivergence`)
   - strict Agda/runtime gates.
3. Narrative/intuition hints are persisted in replay envelope (`TurnReplayTrace`) for auditability.
4. Tests enforce boundary invariant: narrative hint cannot override hard shadow gate outcome.

## Consequences

- Route remains adaptive while constitutional safeguards keep final authority.
- Postmortem replay can distinguish "hint influence" from "gate decision".
- Future tuning can change hint weights without weakening hard safety constraints.

