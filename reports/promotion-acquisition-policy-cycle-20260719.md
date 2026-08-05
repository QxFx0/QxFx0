# Promotion Acquisition Policy Cycle - 2026-07-19

## Acquisition Changes

- Starving topics are now ranked by lowest density first.
- Gap-aware prompts include bounded existing base predicates, explicitly forbid paraphrase, and request missing typed slots: `causes`, `presupposes`, `requires`, `dependsOn`, `limitedBy`, `partOf`, `contrastsWith`.
- Parser support was extended for `causes` and `partOf`.
- Local acquisition preflight runs after parser admission and before runtime queueing/corroboration. Non-positive shapes are durable `edge_rejected` with selector-preflight provenance.
- The preflight seam is now selector-backed: it builds a transient canonical predicate against the loaded topic predicate pool and semantic space, requiring non-zero selector relevance plus marginal gain; the recorded acquisition window below used the preceding local gate and remains diagnostic evidence, not proof of the new selector-backed branch.

## Targeted Window

- Weak topics: `надежда`, `власть`, `одиночество`.
- Fresh jobs: 12, all completed.
- Preflight-positive admitted shapes included:
  - `власть limited_by автономия суждения`, 2 requests;
  - `власть presupposes лидерство`, 2 requests;
  - `надежда presupposes как условие возможности любого суждения`, 2 requests.
- Targeted event totals: 5 admissions, 4 corroborations, 3 duplicate rejections, 24 quarantines.

## Promotion and A/B

- Snapshot: `promotion-snapshot-06ead3fb4b90a82d4fc0d6dbfbbdf9df6e84194d1fb12f3ab6753221a42c8d29`.
- Candidates: `23`.
- Informativeness/local-gate eligible: `2`.
- Draft: `overlay-759988cf292f65a87fdd9acfd0c177cf3f4a5e715ece7ac468c6731e5b88fed8`.
- A/B report: `/tmp/qxfx0-v4-runtime-ab-acquisition-20260719.json`.
- Automated gate: `false`; overlay usage `0`; runtime failures/timeouts/conflicts/unsupported `0/0/0/0`.
- Both eligible predicates lost to base primary/secondary composition and were marked `human_rejected_not_useful_vs_base`; draft status is `rejected`.

## Decision

Acquisition now spends corroboration budget only after local preflight, and the targeted window produced three preflight-positive shapes. The resulting predicates still did not improve renderer selection over the base corpus, so no overlay reached human review or activation. No broad learning run or production activation was performed.
