# Promotion Runtime A/B Evidence - 2026-07-19

## Scope

- Production source database: `~/.local/state/qxfx0/qxfx0.db`.
- Isolated evaluator input: `/tmp/qxfx0-promotion-v4-runtime-ab.db`, created with SQLite `VACUUM INTO`.
- Raw structured report: `/tmp/qxfx0-promotion-v4-runtime-ab.json`.
- Overlay: `overlay-d532f84fc2f7acb1c6a395bbe1f9177d07b1c833ae745f6da71ee9b091600063`.
- Runtime corpus: `promotion-runtime-ab-v1`.
- Current promotion policy: `promotion-v4-complete-lineage`.

## Verification

- `cabal build qxfx0-main`: passed.
- `cabal test qxfx0-test-fast --test-show-details=never`: passed, 1628 cases.
- Production DB was opened read-only for verification: `PRAGMA integrity_check` returned `ok`.
- The evaluated overlay remains `status=evaluated`; no active overlay row was present.

## Renderer A/B Outcome

- Cases: 22.
- Automated gate: failed.
- Activation eligible: false.
- Blocker: `automated_runtime_gate_failed`.
- Runtime failures: 0; runtime timeouts: 0.
- Baseline/candidate contentful responses: 11/11.
- Baseline/candidate refusals: 11/11.
- Baseline/candidate conflicts: 0/0.
- Candidate unsupported assertions: 0.
- Candidate overlay usage cases: 0.

## Selected Cases

| Case | Category | Baseline contentful | Candidate contentful | Candidate overlay ids | Verdict |
| --- | --- | --- | --- | --- | --- |
| `base-freedom` | `base_regression` | false | false | 0 | pass |
| `base-truth` | `base_regression` | false | false | 0 | pass |
| `unknown-topic` | `unknown` | false | false | 0 | pass |
| `conflict` | `conflict` | true | true | 0 | pass |
| `ambiguous` | `ambiguous` | true | true | 0 | pass |
| `quality-gate` | `refusal_quality` | true | true | 0 | pass |
| `overlay-topic-d5ccdd0890aa0363` | `overlay_topic` | false | false | 0 | pass |
| `overlay-neighbor-d5ccdd0890aa0363` | `overlay_neighbor` | true | true | 0 | pass |

## Release Decision

The evaluated overlay predates the v4 complete-lineage contract and is diagnostic-only. It has no observed renderer attribution to an overlay predicate, so it is not release evidence and cannot satisfy the runtime gate.

Production activation was not performed. The next valid promotion cycle starts with a new v4 snapshot that has complete lineage, then a draft, isolated renderer A/B with observed overlay use, and an explicit operator review before any separately authorized activation.
