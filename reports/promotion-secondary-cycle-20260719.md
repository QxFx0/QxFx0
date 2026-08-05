# Promotion Secondary Composition Cycle - 2026-07-19

## Composition Policy

- Top-1 remains the primary predicate.
- At most one secondary predicate is allowed.
- Base and overlay predicates use the same relevance threshold, marginal semantic gain threshold (`0.5`), duplicate check, and response budget (`2` total predicates).
- Selected secondary trace reason: `selected_secondary_semantic_gain`.

## A/B Result

- Draft overlay: `overlay-e320cf2d8184360c1908b5d78f4ee63d9b867ba77938a8083bcc9b0c51c933f1`.
- Report: `/tmp/qxfx0-v4-runtime-ab-secondary-20260719.json`.
- Automated gate: `false`.
- Overlay usage: `0`.
- Runtime failures/timeouts/conflicts/unsupported: `0/0/0/0`.
- Base primary: `надежда ориентирует на возможность будущего`, score `0.38394401303941433`.
- Base secondary: `действие независимо от желания выражает долг`, marginal gain `1.0`, reason `selected_secondary_semantic_gain`.
- Overlay predicate: `надежда предполагает будущее`, score `0`, marginal gain `0.3333333333333333`, reason `below_score_threshold`.

## Decision

The controlled secondary path works and is symmetric for base/overlay candidates. The informative overlay still does not pass ordinary relevance selection, so it does not improve the renderer response over the base corpus. The candidate is rejected as `human_rejected_not_useful_vs_base`; the overlay is not activated.
