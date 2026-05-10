=== QxFx0 CI Gate Contract ===
Profile:  extended-lowram
Run ID:   ci-20260510-031314
Timestamp: 2026-05-10T03:13:14+03:00

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
| cabal test fast (extended proxy) | 0 | PASS | 0 errors, 0 failures |
