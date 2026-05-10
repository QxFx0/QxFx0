=== QxFx0 CI Gate Contract ===
Profile:  core
Run ID:   ci-20260510-214705
Timestamp: 2026-05-10T21:47:06+03:00

| Gate | Exit | Verdict | Details |
|------|------|---------|---------|
| cabal build all | 0 | PASS | clean compile |
| cabal test fast | 0 | PASS | 0 errors, 0 failures |
| check_architecture.sh | 0 | PASS | boundary checks ok |
| gf_quality_gate.sh | 0 | PASS | GF grammar quality OK |
| check_haddock.sh | 0 | PASS | module headers ok |
| sync_embedded_sql.py | 0 | PASS | EmbeddedSQL.hs in sync |
| check_schema_consistency.py | 0 | PASS | cumulative migrations match schema |
| check_schema_contract.py | 0 | PASS | runtime contract manifest valid |
| check_generated_artifacts.sh | 0 | PASS | artifacts in sync |
| check_lexicon.sh | 0 | PASS | lexicon contour OK |
| release-smoke degraded-local | 0 | FAIL | Failed=3, verdict= REJECT[0m — 3 gate(s) failed |

**CI Gate Contract REJECTED: Gate 11 (release-smoke degraded-local)**

=== CI Gate Contract VERDICT ===
Profile:    core
Run ID:     ci-20260510-214705
Commit:     016a75a132674632826f4c6d92ca8f669858f7de
Timestamp:  2026-05-10T22:04:38+03:00
CONTRACT_VERDICT: REJECT (Gate 11 (release-smoke degraded-local))
