# Promotion V4 Release Cycle - 2026-07-19

## Targeted Smoke

- Governed targeted smoke passed in the fast integration suite (`1632` cases total).
- Assertions passed: one runtime edge, persisted `co_occurrence=2`, one `edge_admitted`, one `edge_corroborated`, two complete request/response identities, `support_count=2`, no quarantine for the non-conflicting path, and duplicate request/response evidence rejected.
- A real provider two-request diagnostic on an isolated copy produced different canonical shapes and was not counted as release evidence.
- Snapshot checksum regression passed: changing a lineage identity while keeping edge count and co-occurrence unchanged changes both checksum and snapshot id.

## Bounded Broad Learning

- Source DB: `~/.local/state/qxfx0/qxfx0.db`.
- Window: 300 seconds, forced bounded audit threshold `100.0`, queue cap `8`, request budget `10` per minute/hour/day, retries disabled, self-play disabled.
- Production integrity after the run: `ok`.
- Runtime LLM edges: `17700`.
- Complete admitted/corroborated events: `137`.
- Distinct complete request/response identities: `31`.
- `edge_corroborated` events: `2`.
- Final durable queue state: `7 pending`, `3 retry_scheduled`, `0 leased`; no evidence was discarded by activation or rollback.

## Promotion Chain

- Snapshot: `promotion-snapshot-aa7e60d4f85574e76a9262ac0cd2a4948f608765f67335e1d9a09443121bc380`.
- Snapshot edge count: `17700`.
- Candidate count: `9`.
- Gate-eligible candidates: `1`.
- Draft overlay: `overlay-42c1335bbefc5d6bfe78ad359e685b6f8ca6517c29cd0da7a840c4d7bf430125`.
- Draft status: `draft`.

## Renderer A/B

- Report: `/tmp/qxfx0-v4-runtime-ab-selector-final-20260719.json`.
- Cases: `8`.
- Automated runtime gate: `true`.
- Activation eligible: `false`.
- Blocker: `human_review_required`.
- Runtime failures/timeouts: `0/0`.
- Baseline/candidate contentful: `4/4`.
- Baseline/candidate refusals: `4/4`.
- Baseline/candidate conflicts: `0/0`.
- Overlay usage cases: `1`.
- Overlay predicate selected: `история связана с прошлым` (`b597843143137551d6ebff0653f04c79c795db5cdd05aa3be1bdb3f28e2869e4`).
- Selector score: `0.14358956193926717` (`fieldAffinity=0.09158665769821862`, `activationBonus=1`, `ontologyContribution=0.206`, `OOV=[]`).

## Release Decision

The renderer now selects and attributes the overlay predicate, and the automated runtime gate passes. The draft remains inactive because the evaluator cannot attest human review. Production activation was not performed.
