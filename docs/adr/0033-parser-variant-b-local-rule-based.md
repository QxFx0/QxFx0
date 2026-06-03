# ADR-0033: Parser Variant B - Local Rule-Based Production Parser

- Status: Accepted
- Date: 2026-05-25
- Owner: runtime-hardening

## Decision

QxFx0 adopts parser variant `B` for the current hardening milestone:
the production parser backend is the local rule-based parser.

The historical Python `spaCy` bridge path is not part of the supported
production runtime contract in this milestone.

## Rationale

- The Python `spaCy` bridge was not packaged as a supported runtime artifact.
- The repository/runtime contract had drifted into a dishonest state where a
  checkout-only path could silently degrade.
- The primary production turn pipeline already uses the local
  `InputPropositionFrame` proposition path as the canonical parser input.
- The hardening goal for this milestone is runtime honesty and contract
  coherence, not resurrection of an unbounded optional parser seam.

## Consequences

- `QxFx0.Semantic.Input.Parse` is local-only and deterministic.
- Verification, release-smoke, CI docs, and interop docs must no longer imply
  that `spaCy` availability is part of the production parser contract.
- Parser trace fields must describe the actual local parser backend and any
  parser degradation semantics without implying a hidden Python fallback.

## Rollback Or Revisit Trigger

Revisit this decision only if all of the following are true:

1. a Python parser backend is explicitly reintroduced as a supported production
   surface,
2. its runtime artifact packaging is hermetic and checkout-independent,
3. its health/readiness/degradation semantics are machine-readable and tested,
4. installed-artifact acceptance passes without repository-path assumptions.
