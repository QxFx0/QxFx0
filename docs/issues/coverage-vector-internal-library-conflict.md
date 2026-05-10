# Coverage gate blocked on low-RAM runner: vector-0.13.2.0 internal-library conflict with --enable-coverage

## Summary
`test_coverage.sh` cannot complete on the current 10–11 GB runner because Cabal hits a `vector-0.13.2.0` internal-library conflict when coverage instrumentation is enabled.
This is infra/toolchain-related and not a functional regression in QxFx0 runtime logic.

## Current status
- Core contract: `PROD_GO` achieved
- Canonical run: `ci-20260511-000108`
- Build/tests/gates 1–11: PASS in core profile
- Coverage threshold (`>=51%`) cannot be measured on this runner due to the conflict

## Reproduction
Environment:
- Low-RAM workstation (10–11 GB free RAM)
- Current branch: `main`
- Toolchain: see `cabal --version`, `ghc --version`

Command:
```bash
bash scripts/test_coverage.sh
```

Observed:
- Coverage build path fails before producing stable overall %.
- Conflict references `vector-0.13.2.0` internal library during coverage-enabled build plan.

## Expected
Coverage run should complete and produce:
- overall coverage %
- pass/fail against threshold

## Impact
- Blocks `FULL_SCIENTIFIC_GO` evidence on this runner.
- Does not block `PROD_GO` core contract.

## Proposed next steps
1. Reproduce on high-mem runner with warm cabal cache.
2. Pin/adjust build plan to avoid vector internal-library conflict under `--enable-coverage`.
3. Add a documented fallback path for coverage evidence collection when local runner is constrained.
4. Keep strict semantics: INFRA remains INFRA, never treated as PASS.

## Related evidence
- `reports/baseline_v2/final_gates/_gate_results_ci-20260511-000108_core.md`
- `reports/baseline_v2/final_gates/CANONICAL_EVIDENCE_INDEX.md`
- `reports/baseline_v2/wp13_wp1_wp3_completion_report.md`
