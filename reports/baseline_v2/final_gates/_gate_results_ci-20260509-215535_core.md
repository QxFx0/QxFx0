=== QxFx0 CI Gate Contract ===
Profile:  core
Run ID:   ci-20260509-215535
Timestamp: 2026-05-09T21:55:35+03:00

| Gate | Exit | Verdict | Details |
|------|------|---------|---------|
| cabal build all | 0 | PASS | clean compile |
| cabal test fast | 0 | PASS | 0 errors, 0 failures |
| check_architecture.sh | 1 | FAIL | boundary violation |

**CI Gate Contract REJECTED: Gate 3 (architecture)**

=== CI Gate Contract VERDICT ===
Profile:    core
Run ID:     ci-20260509-215535
Commit:     21e62749da4b1c14c8ecc5163b626798c2238fce
Timestamp:  2026-05-09T21:58:19+03:00
CONTRACT_VERDICT: REJECT (Gate 3 (architecture))
