# ADR-0007: Dual-Mode Self-Preserving Architecture (Conatus + Adjunction)

- **Status**: Proposed
- **Date**: 2026-05-17
- **Supersedes**: none
- **Superseded by**: none
- **Related**: ADR-0001 (Turn Effect State Machine), ADR-0005 (Turn Replay Trace)

## Context

The current QxFx0 architecture (as of `main @ 060876d`) is a single-mode
deterministic pipeline: input flows through Prepare → Route → Render →
Finalize, each phase implemented as a sequence of typed transformations
with rule-based recovery and explicit identity guards. The system is
formally sound and gates clean, but exhibits a small set of structural
limitations that the team has identified through extended use:

1. **Recovery is rule-cascade, not field-driven.** When a fault occurs,
   the matching strategy is selected by case analysis over cause types.
   This is verifiable but inflexible: introducing a new cause requires
   editing every cascade.

2. **Intuition is a scalar score, not a mode.** The `Core.Intuition`
   module reduces holistic processing to a single `Double` that modulates
   response depth. There is no architectural place for analogical
   resonance, atmospheric context, distribution-shaped confidence, or
   counterfactual replay — yet each of these is well-attested as a
   distinct cognitive function.

3. **No explicit notion of system continuity.** The `IdentitySignal`,
   `IdentityGuard`, and `Legitimacy` modules implement local checks, but
   there is no single typed answer to the question: *what makes this
   system this system, as opposed to some other system that happens to
   share state shape?* When a recovery cascade rebuilds state from
   degraded inputs, the implicit "still-the-same-system" assumption is
   carried by convention, not by type.

4. **Single-mode bias.** All processing currently optimizes the same
   objective (formal correctness under specification). There is no
   provision for situations where formal specification cannot decide
   (genuine ambiguity, novel input, soft-failure recovery), and where a
   holistic mode should temporarily lead.

The team's theoretical position (documented in `docs/THEORY.md`)
provides a unified diagnosis: these are not four problems but one. The
system lacks (a) a formal *self* (the thing being preserved), (b) a
*conatus* functional (the gradient of self-preservation), and (c) an
*adjoint pair of modes* (so that holistic and formal processing can
coexist without conflict).

## Decision

QxFx0 will be modernized in eight sequential phases (P0–P8) introducing:

- **A Self layer** (`src/QxFx0/Self/*`) containing two types:
  - `SelfBlanket` — a finite, checkable set of structural invariants
    whose simultaneous preservation defines the system's continuity
    of being.
  - `Conatus` — a scalar functional `RuntimeState → ℝ` whose gradient
    is the primary direction for recovery and effect interpretation.
- **An Adjunction layer** (`src/QxFx0/Adjunction.hs`) formalizing the
  Left/Right dual-mode split as a pair of functors with natural
  transformations and property-tested triangle identities.
- **A Right namespace** (`src/QxFx0/Right/*`) containing five new
  submodules: `Resonance`, `Atmosphere`, `FieldConfidence`,
  `Consolidation`, `Counterfactual`.
- **A Salience controller** (`src/QxFx0/Salience/*`) arbitrating
  between modes based on ambiguity / novelty / formal-failure /
  time-pressure signals.
- **An effect refactor** (Phase 6) routing every effect through a
  conatus-aware prior in the interpreter layer.
- **A lifeness validation suite** (`test/Test/Suite/Lifeness/*`,
  cabal target `qxfx0-test-lifeness`) testing not only correctness
  but also: SelfBlanket integrity under adversarial input, conatus
  boundedness over long sessions, mode-balance, and selected
  indicator properties from Butlin et al. (2023).

The eight phases are sequenced as:

| Phase | Deliverable                                              | Critical-path? |
|-------|----------------------------------------------------------|----------------|
| P0    | THEORY.md, ARCHITECTURE.md, this ADR, README pointer     | yes            |
| P1    | `Self.Blanket` + invariants, IdentityRupture exception   | yes            |
| P2    | `Self.Conatus` functional and gradient                   | yes            |
| P3    | Adjunction infrastructure, Left namespace shims          | yes            |
| P4    | Right hemisphere (5 submodules)                          | yes            |
| P5    | Salience controller, antikorrelyation enforcement        | yes            |
| P6    | Effect-system refactor with conatus-prior interpreters   | no (optional)  |
| P7    | Lifeness validation suite, new architecture rule [12]    | yes            |
| P8    | Position paper + arXiv + NLnet/Sovereign Tech submission | parallel       |

## Consequences

### Positive

- **A formal answer to "what is this system."** `SelfBlanket` makes
  identity continuity type-checkable rather than convention-bound.
- **A unified recovery direction.** `Conatus` replaces ad-hoc cascade
  case-analysis with gradient descent on a measurable scalar. New
  cause types automatically integrate by their effect on the
  functional.
- **A home for holistic processing.** Right-mode submodules give the
  architecture a place for resonance, atmosphere, distribution-shaped
  uncertainty, and counterfactual replay — currently absent or
  squeezed into the wrong abstractions.
- **Improved scientific publishability.** The dual-mode + conatus
  architecture is a defensible, citable position with direct lineage
  to active inference (Friston), autopoiesis (Maturana & Varela),
  hemispheric duality (McGilchrist), and paraconsistent logics (da
  Costa, Priest). This raises the project from "deterministic dialogue
  runtime" to "formal model of dual-mode self-preserving dialogue
  architecture" — suitable for NLnet, Sovereign Tech Fund, and
  Journal of Consciousness Studies / Cognitive Systems Research.
- **Right-mode is independently useful.** Each of the five Right
  submodules is a publishable artifact in isolation: analogical
  resonance over GF-generated dialogue, mood-conditional generation,
  calibrated introspective uncertainty, etc.

### Negative

- **Substantial refactor (≈3–5 months for one researcher).** While
  each phase is independently checkpointable, the cumulative cost is
  real.
- **Possible test churn.** Some existing tests assume rule-based
  recovery semantics; these will need adjustment in Phase 2.
  Existing semantic-correctness tests should remain unaffected.
- **Two new external dependencies.** `ad` (for conatus gradient,
  Phase 2) and `hnswlib-haskell` or equivalent (for resonance NN-index,
  Phase 4). Both have permissive licenses (BSD-3) and are maintained.
- **Mode-switch logic is empirical.** The salience controller's
  thresholds (Phase 5) cannot be derived from first principles; they
  require calibration on existing corpora. This is a known soft spot
  and is mitigated by treating switching as observable (logged as
  first-class events in `Core.Observability`).
- **Reduced specification clarity in some cases.** Intensive
  specification (Phase 6, conatus-prior effects) sacrifices the
  ability to say "the system will do exactly X here" in exchange for
  "the system will minimize conatus-loss". This is a deliberate
  trade-off, but it makes some kinds of debugging harder.

### Neutral / mitigations

- **Backward-compatible namespace shims.** Phase 3 introduces
  `QxFx0.Left.*` via re-export shims; existing imports continue to
  work. The "real" Left/Right boundary tightens incrementally
  through Phases 4–5.
- **Existing scientific modules** (`Core.GameTheory`, `Core.Spectral`,
  `Core.Bayesian`) remain in `other-modules` (extended contour) and
  are unaffected by this modernization. Phase 4's `Right.FieldConfidence`
  may take inputs from `Core.Bayesian` but does not depend on it for
  compilation.
- **No big-bang rewrite.** Each phase ships independently. After
  Phase 1, the system has SelfBlanket and IdentityRupture but
  otherwise behaves as before. After Phase 2, recovery uses conatus
  gradient but old strategies remain reachable. And so on.

## Alternatives considered

- **Stay single-mode, add holistic features ad-hoc.** Rejected:
  this is the current trajectory, and the user-reported "running out
  of ideas" diagnosis suggests it has hit a structural ceiling.
- **Adopt LIDA architecture (Stan Franklin) directly.** Rejected as
  primary choice: LIDA is a complete cognitive architecture in its
  own right; adopting it would dilute the QxFx0-specific commitments
  (determinism, formal verification, local-first recovery). LIDA
  remains a useful reference for global-workspace patterns in
  Phase 5 salience design.
- **Build on active inference / `pymdp` directly.** Rejected as
  primary substrate: active inference's natural home is in numeric
  models with continuous state; QxFx0 is a typed symbolic system.
  Active-inference *concepts* (Markov blanket, free energy) inform
  this ADR; the implementation is native Haskell.
- **Defer Self layer; do Right hemisphere first.** Rejected:
  without a formal self, right-mode resonance has no anchor for
  "what counts as a relevant analogy". Self must precede Right.

## Validation

This ADR is considered *Accepted* when:

1. P0 artifacts (THEORY.md, ARCHITECTURE.md, this ADR, README pointer,
   CITATION.cff) exist and are referenced from README. ✓ in progress.
2. P1 artifacts (`Self.Blanket`, `Self.Invariants`, `Self.Types`,
   `IdentityRupture` exception, integration into Bootstrap and Commit,
   new test suite passing) are merged. In progress.
3. Subsequent phases each get their own status update in this ADR's
   "Validation" subsection.

This ADR is considered *Implemented* when all eight phases are merged,
`scripts/check_architecture.sh` passes with rule [12], and
`qxfx0-test-lifeness` is green.

This ADR may be *Revised* if empirical evidence (e.g., conatus
calibration proving intractable, or right-mode submodules failing to
demonstrate measurable contribution) requires scope adjustment.

## Notes for reviewers

The theoretical grounding for this ADR lives in `docs/THEORY.md`. It
is unusual for an architecture decision to depend on a foundational
philosophical document, and we acknowledge that. The justification:
without a single coherent theoretical commitment, the modernization
would proceed as a sequence of metaphor-driven additions, which is
exactly the failure mode we diagnosed and are trying to leave behind.

External readers familiar with active inference (Friston),
autopoiesis (Maturana & Varela), hemispheric duality (McGilchrist),
or paraconsistent logic (Priest, da Costa) will recognize the
intellectual lineage. Readers without that background should treat
THEORY.md as the *contract* this ADR operationalizes.
