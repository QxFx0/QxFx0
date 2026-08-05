# Historical Selector Preflight Audit - 2026-07-19

## Scope

- Target: 36 historical `edge_rejected` rows with `reason=selector_preflight_rejected`.
- Input: persisted `learning_events` edge endpoints plus persisted `learning_responses` bodies.
- Execution: offline deterministic CLI command `--autonomous-preflight-audit`.
- Transaction: one `BEGIN IMMEDIATE`; no LLM calls, runtime learning, snapshot, or activation.

## Result

- Audited rows: `36`.
- `relation=unknown`: `0` after token-overlap recovery for normalized response endpoints.
- `score=unknown`: `0`.
- `OOV=unknown`: `0`.
- Zero selector score: `0`.
- Non-zero topic relevance: `36` (`0.8342` to `0.8643`).
- Final score range: `1.0844` to `1.1236`.
- Zero field affinity: `36`.
- Zero activation bonus: `0` (`activation=1.0` across the audited rows).
- Zero ontology contribution: `36`.
- OOV atoms: `0` for all rows.
- Reasons: `lost_to_higher_score` for all rows; these were eligible in the temporary relevance space but not top-1 against the base predicate set.

## Interpretation

The 36 candidates were not rejected because of missing atoms, duplicate evidence, or relation parsing. With topic relevance as the base signal and the candidate edge inserted only into a temporary network copy, all 36 receive non-zero topic relevance and activation. Field affinity remains zero, while the candidates lose to stronger base top-1 predicates. This separates the former cold-start failure from the remaining base-corpus ranking decision. No threshold lowering or overlay boost was applied.

Production remains safe: database integrity is `ok`, no active overlay exists, and no learning process remains running.
