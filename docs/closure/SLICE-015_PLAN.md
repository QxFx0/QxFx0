# SLICE-015 Plan — Runtime Summary Observability Gaps

Status: Deferred
Purpose: track the two runtime-state-summary observability fields that remain as deferred feature gaps after SLICE-014. Not in active scope.

## Origin

SLICE-014 closed the regression portion of the SLICE-013 deferred runtime failures. The remaining two failures are purely observability/summary enrichment and were intentionally kept out of the regression scope so SLICE-014 would not expand into feature work.

## Deferred feature gaps

| Case | Test | Location | Gap | Notes |
|---|---|---|---|---|
| 50 | `testStateSummaryShowsTypedPreActorFailure` | `RuntimeInfrastructure.hs:1921` | Typed pre-actor failure event is not surfaced in `Runtime.stateSummaryLines`. | The test runs a turn that triggers a `PreActorTransportFailure` and expects the summary to contain `external_action.pre_actor_failure.kind` and `external_action.pre_actor_failure.action`. |
| 51 | `testStateSummaryShowsRestartAuthorityStatus` | `RuntimeInfrastructure.hs:1942` | `restart_capped_non_authoritative` status is not surfaced in `Runtime.stateSummaryLines` after a non-authoritative or compatibility-marker restore. | The test persists a state with `LegacyIncompleteSurface` and restores it, expecting the summary to contain `restart_authority_status: restart_capped_non_authoritative`. |

## Constraints

- Do **not** reopen the SLICE-013 policy: strict rejects corruption, not compatibility.
- Do **not** touch `forms_by_surface.json` / SLICE-010B artifacts.
- Do **not** delete `origin/feat/cts-44-promotion`.
- This is an observability feature slice, not a persistence correctness slice.

## Next steps

1. Decide whether to implement the summary fields or keep them deferred.
2. If implemented, add the fields to the state summary output without changing core persistence contracts.
3. Re-run the `runtime` group and confirm cases 50/51 pass while the rest of the suite stays green.

## Evidence

- SLICE-014 plan: `docs/closure/SLICE-014_PLAN.md`.
- SLICE-013 plan: `docs/closure/SLICE-013_PLAN.md`.
- Gate log: `/home/liskil/slice014-fix-runtime.log`.
