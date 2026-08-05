# Acquisition Selector Preflight - 2026-07-19

## Policy

- Gap-ranked topics and gap-aware prompts are active.
- Prompts include existing base predicates and forbid paraphrase.
- Requested slots include causes, presupposes, requires, dependsOn, limitedBy, partOf, and contrastsWith.
- Selector-backed preflight builds a transient canonical predicate against the loaded topic predicate pool and semantic space.
- A shape must pass informativeness, have non-zero selector score, and have sufficient marginal gain before runtime admission/corroboration.

## Final Window

- Topics: `надежда`, `власть`, `одиночество`.
- Fresh requests: `12`.
- Jobs: `12 failed` after local selector preflight.
- Parsed candidate edges rejected: `36`.
- Runtime admissions: `0`.
- Corroborations: `0`.
- Corroboration requests spent: `0`.
- Rejection reason: `selector_preflight_rejected`.

## Decision

The actual selector-backed preflight is stricter than the earlier informativeness-only window and correctly stopped all candidates before runtime graph mutation. The target of three selector-positive predicates was not reached, so no new snapshot, gates, draft, A/B, or activation was attempted after this preflight window.

The admission/priority split is now implemented: knowledge admission no longer requires selector relevance; selector decomposition is recorded as corroboration-priority metadata across fixed Field prototypes. The historical 36 rejection rows predate this metadata schema and remain unchanged rather than being backfilled with invented scores.

Competitive utility now compares a base-only exact-topic winner with a transient candidate selector result. It requires base-primary preservation plus a selected marginal secondary (or a primary only when base has no winner) and a new canonical contribution before assigning non-zero corroboration priority. The current durable worker queue is topic-only, so this priority is recorded as audit evidence; automatic candidate-targeted second requests require a separate durable target-task model and are not simulated by the existing scheduler.

Existing drafts remain rejected and production has no active overlay.
