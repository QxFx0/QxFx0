=== QxFx0 CI Gate Contract ===
Profile:  core
Run ID:   ci-20260509-234041
Timestamp: 2026-05-09T23:40:41+03:00

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

| release-smoke degraded-local | 0 | PASS | ACCEPT_WITH_SKIPS, Failed=0 |

=== CI Gate Contract VERDICT ===
Profile:    core
Run ID:     ci-20260509-234041
Commit:     b9ed410e08f07d8fc22bf50cf1bf8e5dcbc61141
Timestamp:  2026-05-09T23:55:00+03:00
CONTRACT_VERDICT: PROD_GO
