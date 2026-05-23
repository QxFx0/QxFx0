# ADR-0032: Dialogue Development Contours

- **Status**: Accepted
- **Date**: 2026-05-22
- **Refines**:
  - [ADR-0030 — Phase 9 MVP: Autonomous Exploratory Learning](./0030-autonomous-exploratory-learning.md)
  - [ADR-0031 — Phase 10: Offline Training Cycle Contract](./0031-phase10-offline-training-cycle.md)
- **Related**:
  - `QxFx0.Learning.DialogueDevelopment`
  - `QxFx0.Types.State.DialogueDevelopment`
  - `QxFx0.Core.TurnPipeline.Route.Build`
  - `QxFx0.Core.TurnPipeline.Finalize.Precommit`

## 1. Context

WP6/WP6.1 closed the external-learning and calibration substrate, but the runtime still treated dialogue quality, speech adaptation, and claim revision as one vague future capability. That made the system easy to overstate: it had a real but narrow adaptive-learning contour, not yet a self-developing conversationalist or worldview engine.

The next step is therefore a small, fail-closed split into three separate persistent contours:

1. `DialogueOutcomeLearning` records what kind of turn outcome occurred.
2. `SpeechPolicyState` adapts tone/style pressure from strong outcome evidence.
3. `BeliefStore` records claim stance revisions without merging them into the knowledge tree.

## 2. Decision

### 2.1 Outcome learning is observational first

`DialogueOutcomeLearningState` stores a bounded recent sample window and counters for:

- success
- partial success
- repair requested
- repeated question
- conflict
- degraded
- uncertain

Only distinguishable signals create strong updates. Ambiguous turns are still counted, but they do not mutate speech policy or belief confidence.

### 2.2 Speech policy is stateful but subordinate

`SpeechPolicyState` tracks directness, compression, ambiguity tolerance, repair bias, and style success/failure counts. It may bias future render style toward `StyleRecovery`, `StyleDirect`, or `StyleClinical`.

It is never allowed to override an already forced `StyleRecovery`, preserving hard recovery and Conatus-safety semantics.

### 2.3 Belief storage is not the knowledge tree

`BeliefStore` is a claim/stance memory for user-facing conversational commitments:

- successful confirmations increase confidence;
- conflicts mark claims contested and add counter-evidence;
- uncertain or weak samples do not mutate belief records.

Feedback-only confirmations, such as thanks/acknowledgement turns, revise the previous dialogue topic when one is available. If no prior topic/claim context exists, the belief update is skipped instead of storing the acknowledgement itself as a claim.

This store remains separate from `KnowledgeTree`. The knowledge tree holds validated learned facts; the belief store holds revisable dialogue stance.

### 2.4 Persistence and compatibility

The three contours are persisted in `SystemState` with backward-compatible defaults. Existing state snapshots that do not contain these fields decode to empty contour state.

Adaptive turns also emit shared `AdaptiveMutationRecord` entries into the bounded top-level `SystemState.ssAdaptiveMutationLog`. Dialogue-local JSON names remain accepted for legacy decode, but new runtime emission uses the shared mutation taxonomy.

### 2.5 Turn-pipeline placement

The route phase reads the previous `SpeechPolicyState` and adjusts the future render style before rendering.

The finalize precommit phase applies dialogue development after base state construction and external learning, so the outcome sample reflects the committed turn result while keeping all updates pure and deterministic.

## 3. Consequences

- The system has explicit dialogue-development state without pretending that this is full self-development.
- Speech adaptation is bounded by strong evidence and safety precedence.
- Claim/worldview mutation is separated from validated knowledge acquisition.
- Old persisted state remains loadable.
- The three contours can later grow independently into richer offline training/evaluation loops.

## 4. Acceptance Criteria

- [x] `DialogueOutcomeLearningState`, `SpeechPolicyState`, and `BeliefStore` exist as separate persistent records.
- [x] `SystemState` JSON includes the three records and decodes old snapshots with defaults.
- [x] Finalize precommit updates dialogue-development state from turn artifacts.
- [x] Route planning reads speech policy and preserves forced `StyleRecovery`.
- [x] Regression tests cover outcome counters, speech-policy thresholds, belief mutation, JSON compatibility, and pipeline persistence.

## 5. Residual Risks

- Outcome classification is heuristic and intentionally conservative; richer labelled dialogue corpora are needed before stronger adaptation.
- `BeliefStore` is currently claim/stance scoped, not a general worldview model.
- Speech policy only affects coarse `RenderStyle`; it does not yet select finer lexical or discourse templates.
- No offline training cycle consumes these contours yet; that remains a follow-up to Phase 10.
