=== QxFx0 CI Gate Contract ===
Profile:  core
Run ID:   ci-20260509-194300
Timestamp: 2026-05-09T19:43:00+03:00

| Gate | Exit | Verdict | Details |
|------|------|---------|---------|
| cabal build all | 0 | PASS | clean compile |
| cabal test fast | 0 | PASS | 0 errors, 0 failures |
| check_architecture.sh | 0 | PASS | boundary checks ok |
| gf_quality_gate.sh | 1 | FAIL | GF quality check failed |

**CI Gate Contract REJECTED: Gate 4 (GF quality)**

=== CI Gate Contract VERDICT ===
Profile:    core
Run ID:     ci-20260509-194300
Commit:     fffefaa375054018a21b896e037ff9978012ccf2
Timestamp:  2026-05-09T19:46:25+03:00
CONTRACT_VERDICT: REJECT (Gate 4 (GF quality))
