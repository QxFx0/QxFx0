=== QxFx0 CI Gate Contract ===
Profile:  core
Run ID:   ci-20260509-215454
Timestamp: 2026-05-09T21:54:54+03:00

| Gate | Exit | Verdict | Details |
|------|------|---------|---------|
| cabal build all | 0 | PASS | clean compile |
| cabal test fast | 1 | FAIL | test suite exited non-zero |

**CI Gate Contract REJECTED: Gate 2 (fast tests)**

=== CI Gate Contract VERDICT ===
Profile:    core
Run ID:     ci-20260509-215454
Commit:     21e62749da4b1c14c8ecc5163b626798c2238fce
Timestamp:  2026-05-09T21:54:57+03:00
CONTRACT_VERDICT: REJECT (Gate 2 (fast tests))
