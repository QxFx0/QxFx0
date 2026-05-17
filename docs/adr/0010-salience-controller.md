# ADR-0010: Salience Controller

- **Status**: Proposed (Phase-5 design, not yet implemented)
- **Date**: 2026-05-17
- **Refines**:
  - [ADR-0007 — Dual-mode conatus-aware architecture](./0007-dual-mode-conatus.md)
  - [ADR-0008 — Left ⊣ Right adjunction as dual-mode backbone](./0008-left-right-adjunction.md)
  - [ADR-0009 — Right-hemisphere Field components](./0009-right-hemisphere-field.md)
- **Related**:
  - [`docs/THEORY.md`](../THEORY.md) §4.2 (the dual-mode thesis)
  - Phase 4 (`Self.Field`), shipped in commit `036f70f`.

## 1. Context

Phase 3 (ADR-0008) shipped the algebra of the dual-mode runtime —
the adjunction `Holistic ⊣ Formal`. Phase 4 (ADR-0009) shipped its
right-hemispheric parameter — the five-component `Field` record.
Both phases stopped short of /deciding/, in any concrete situation,
which mode should lead.

That decision is the work of the **salience controller**. ADR-0007
named the controller without committing its types or its decision
rule:

> The salience controller decides which mode leads per turn,
> based on ambiguity / novelty / formal-failure / time-pressure
> signals.

Phase 5 makes the controller precise: a pure morphism

```
Field × ConatusEnergy → Salience
```

together with a way to /use/ the resulting `Salience` to choose
between two branches through the Phase-3 adjunction. As with
Phases 1–4, this ADR commits to the algebraic shape and the
acceptance criteria; the Phase-5 implementation PR ships the pure
module and its property tests, without touching the turn pipeline.
Re-shaping the existing call sites (`Core.Intuition`,
`Core.ConsciousnessLoop`, `RouteEffects`) so they actually consult
the controller is **Phase 5.5** and is staged separately to keep
the Phase-5 PR reviewable and recompilable in isolation.

## 2. Decision

We add a single new module `QxFx0.Self.Salience`. Like the rest of
the `Self.*` subtree, it is a pure module with `base`-only
dependencies, and it does /not/ leak into Core or Runtime. It
introduces three named values:

```haskell
-- The controller's verdict for a single turn.
data Salience = Salience
  { salienceHolisticBias :: !Double          -- in [0, 1]: 0 = pure formal, 1 = pure holistic
  , salienceConfidence   :: !Double          -- in [0, 1]: how trustworthy the verdict is
  , salienceDriver       :: !SalienceDriver  -- which input dominated the decision
  } deriving stock (Eq, Show)

-- A discrete tag identifying the dominant driver, for tracing.
data SalienceDriver
  = DrivenByResonance
  | DrivenByAtmosphere
  | DrivenByConsolidation
  | DrivenByCounterfactual
  | DrivenByFieldConfidence
  | DrivenByConatusGate     -- low Conatus forced Formal
  | DrivenByDefault         -- no signal exceeded threshold
  deriving stock (Eq, Show)

-- Tunable coefficients of the decision rule.
-- Phase 5 ships defaultSalienceWeights; Phase 7 calibrates.
data SalienceWeights = SalienceWeights
  { weightResonance      :: !Double
  , weightAtmosphere     :: !Double
  , weightConsolidation  :: !Double          -- inverse: high Consolidation → Formal
  , weightCounterfactual :: !Double
  , weightFieldConfidence :: !Double         -- inverse: low FieldConfidence → Formal
  , conatusGateThreshold :: !Double          -- Conatus below this → force Formal
  , verdictThreshold     :: !Double          -- bias outside [0.5 ± t] → clear preference
  } deriving stock (Eq, Show)

defaultSalienceWeights :: SalienceWeights
```

The controller itself is

```haskell
computeSalience
  :: SalienceWeights
  -> ConatusEnergy
  -> Field
  -> Salience
```

a /total/ pure function. Given identical inputs it produces an
identical `Salience`; identity holds even at the bit level for
the `salienceDriver` tag, so traces are reproducible across runs.

### 2.1 Why this shape

We considered three alternative output types (§9). The structured
record was chosen because it satisfies three constraints
simultaneously:

- **Decisions are not just bits.** A binary "Holistic vs Formal"
  flag throws away how strongly the controller leans, and
  everything downstream (recovery, render style, intuition gate)
  benefits from a continuous bias.
- **Decisions need attribution.** The system already commits to
  reproducible recovery traces (`trcLocalRecoveryPolicy`,
  `trcRecoveryCause`, `trcRecoveryStrategy`,
  `trcRecoveryEvidence`). The salience controller is, in spirit,
  another local-recovery-shaped decision; its verdict should
  carry the same kind of /why/ alongside the /what/.
  `SalienceDriver` is that /why/, in a closed enum that fits a
  trace record without further serialisation work.
- **Decisions need their own confidence.** The controller can be
  internally sure of a clear preference (one driver dominates
  decisively) or unsure (signals balance). Downstream consumers —
  especially the planned Phase-6 effect interpreter — should be
  able to read `salienceConfidence` and decide whether to commit
  to the bias or to defer to the formal contract by default.

### 2.2 Why these inputs

`Field × ConatusEnergy → Salience`. Both inputs are pinned by
prior ADRs:

- `Field` (ADR-0009) is the right-hemispheric observation summary.
  Its five components are the substantive evidence for any
  holistic preference.
- `ConatusEnergy` (Phase 2, `Self.Conatus`) is the system's
  scalar self-preservation functional. When `Conatus` falls below
  a threshold (§5), the system is structurally at risk and must
  default to Formal — the contract-driven, type-checked,
  predictable mode — regardless of what `Field` reports. This
  realises the Phase-0 thesis that "conatus is the precondition
  under which every other process makes sense."

We are deliberately /not/ feeding `SelfBlanket` into the
controller. The blanket is a binary categorical predicate
("`IdentityRupture` or not"); a system that has lost its
self-blanket is no longer a system in the sense the controller
operates over, and salience-level reasoning is inappropriate.
Blanket-rupture handling is a hard fail-stop, not a salience
question.

## 3. Decision rule

The controller computes a raw score in `[-∞, +∞]`, gates it on
Conatus, then projects to `[0, 1]`:

```
raw =
    weightResonance      * fieldResonance      f
  + weightAtmosphere     * atmosphereArousal (fieldAtmosphere f)
  - weightConsolidation  * fieldConsolidation  f      -- inverse
  + weightCounterfactual * fieldCounterfactual f
  - weightFieldConfidence * fieldConfidence    f      -- inverse
```

(`fieldResonance` etc. denote the `Double`-valued projections of
the `Field` newtype components.)

The Conatus gate then short-circuits:

```
if conatusEnergy < conatusGateThreshold:
    return Salience { holisticBias = 0.0
                    , confidence    = 1.0
                    , driver        = DrivenByConatusGate }
```

Otherwise the raw score is squashed to `[0, 1]` by a logistic
function, and the dominant driver is the input whose absolute
contribution to `raw` was largest. Confidence is a separate
function of the spread of contributions: high when one driver
clearly dominates, low when contributions cancel.

```
holisticBias = sigmoid (raw)                        -- in (0, 1)
confidence   = normalisedDispersion contributions   -- in [0, 1]
driver       = argmax |contribution_i|              -- in SalienceDriver
```

The exact functional forms are pinned in the implementation PR
(§7); what this ADR pins is the /shape/:

- `holisticBias` is monotone in each contribution direction (more
  Resonance → more bias toward Holistic, more Consolidation → more
  bias toward Formal, etc.);
- the rule is total (no partial application, no division by zero,
  no NaN paths);
- it is deterministic (pure function of its inputs);
- the Conatus gate has priority over every Field-derived signal.

### 3.1 Default weights

Phase 5 ships `defaultSalienceWeights` with values that make the
property tests pass and the operational mapping (§6) plausible.
We do **not** claim these are calibrated:

- The weights are bikeshedding-eligible.
- Phase 7 (validation gates) will replace them with empirically
  tuned values when the lifeness suite is in place.
- Calibration is an open problem (ADR-0007 §6); §11 below is
  honest about that.

## 4. Verdict and adjunction-aware dispatch

The `Salience` record alone does not commit code to a branch. The
verdict step is

```haskell
data SalienceVerdict
  = PreferHolistic !Double   -- bias > 0.5 + verdictThreshold; magnitude in (0, 1]
  | PreferFormal   !Double   -- bias < 0.5 − verdictThreshold; magnitude in (0, 1]
  | Tied                     -- |bias − 0.5| ≤ verdictThreshold
  deriving stock (Eq, Show)

salienceVerdict :: SalienceWeights -> Salience -> SalienceVerdict
```

A small dead band around `0.5` produces the `Tied` verdict. This
matters: a system that flips between modes on every tiny
fluctuation is failing the anti-correlation discipline
(§5). `Tied` lets the consumer fall back to a default policy
(typically Formal — the contract-driven mode is the safe default).

The dispatch step is what actually couples the controller to the
Phase-3 adjunction:

```haskell
chooseBranch
  :: Salience
  -> (Holistic a -> b)   -- holistic-first branch
  -> (a -> Formal b)     -- formal-first branch
  -> (Holistic a -> b)   -- final morphism
chooseBranch s holistic formal = case salienceVerdict defaultSalienceWeights s of
  PreferHolistic _ -> holistic
  PreferFormal _   -> rightAdjunct formal
  Tied             -> rightAdjunct formal       -- safe default
```

Two observations:

- Both inputs to `chooseBranch` are /always/ provided by the
  caller. The adjunction guarantees they are inter-translatable.
  The controller picks which one to /use/; the other one remains
  a well-typed value the caller can evaluate for tracing.
- The function returns a `Holistic a -> b`, not an `Either`.
  Downstream code does not branch on the verdict; it composes
  with the result. This is the algebraic content of "the salience
  controller selects a branch": the consumer's call site is
  morphism composition, regardless of which branch the controller
  preferred.

## 5. Anti-correlation discipline

ADR-0007 mandates that "the non-leading mode listens but does not
emit." We translate this into three concrete operational rules:

1. **Single output channel.** `chooseBranch` returns one morphism,
   not two. Whichever branch the controller selects is the one
   whose /value/ reaches the caller. The other branch is not
   discarded — the caller may evaluate it for diagnostics or
   trace material — but its value does not flow into the output.

2. **Stability via the dead band.** `verdictThreshold` keeps the
   verdict from oscillating on near-tied fields. A turn whose
   `Salience` is on the edge produces `Tied`, which is dispatched
   deterministically to the same default branch (Formal). This
   prevents pathological flapping under noise.

3. **Conatus gate priority.** When Conatus is low, the controller
   refuses to weigh Field components against each other and
   forces Formal. The non-leading mode (Holistic) does not even
   contribute to the verdict in that case. This realises the
   Phase-0 thesis on its own terms: when the system is
   structurally at risk, the formal contract has uncontested
   priority.

These three rules are testable and are required of the Phase-5
implementation (§7).

## 6. Operational mapping (Phase-5.5 preview)

Phase 5 itself does **not** wire the controller into any call
site. The table below describes how Phase 5.5 will wire it; this
ADR is descriptive of intent, not prescriptive of code:

| Call site (today)              | Today's shape                    | Phase-5.5 shape via salience          |
|--------------------------------|----------------------------------|---------------------------------------|
| `Core.Intuition.IntuitiveFlash`| Computed once, frozen            | `chooseBranch` over the flash channel |
| `Core.ConsciousnessLoop`       | Mutable narrative                | Salience-weighted contribution        |
| `RouteEffects` intuition path  | Multiplied by hand-tuned scalar  | `salienceHolisticBias` is the scalar  |
| `RenderStyle` selection        | Plain enum dispatch              | `salienceVerdict`-driven choice       |
| `Recovery` driver selection    | Conatus-gradient (Phase 2.5)     | Falls back to Formal under Conatus gate; otherwise unchanged |

The salience controller is a /multiplexer/, not a content
generator: it never produces new claims, never overrides type
signatures, never emits text on its own. It only chooses, per
turn, which of the two adjoint paths through the runtime carries
the value forward. Phase 5.5 is responsible for ensuring each
call site honours that constraint.

## 7. Phase-5 implementation plan

The Phase-5 PR will be intentionally narrow. Order of operations:

1. **`src/QxFx0/Self/Salience.hs`** (new) —
   `Salience`, `SalienceDriver`, `SalienceWeights`,
   `defaultSalienceWeights`, `SalienceVerdict`, `computeSalience`,
   `salienceVerdict`, `chooseBranch`. Imports limited to
   `QxFx0.Self.Adjunction`, `QxFx0.Self.Conatus`,
   `QxFx0.Self.Field`, and `base`.
2. **`test/Test/Suite/SelfSalience.hs`** (new) — QuickCheck
   property suite covering:
   - `computeSalience` is total (no exception path on any
     well-formed input);
   - `salienceHolisticBias ∈ [0, 1]` for any well-formed input;
   - monotonicity in each Field component along its rule
     direction (more Resonance → no decrease in bias; more
     Consolidation → no increase in bias; etc.);
   - the Conatus gate fires at and below `conatusGateThreshold`
     and returns `DrivenByConatusGate`;
   - `salienceVerdict` produces `Tied` exactly within the
     `[0.5 − t, 0.5 + t]` dead band;
   - `chooseBranch` dispatches `PreferHolistic` and
     `PreferFormal` to the corresponding branch, and dispatches
     `Tied` to the documented default (Formal);
   - determinism: identical inputs ⇒ identical `Salience`,
     including the discrete `salienceDriver` tag.
3. **Cabal + TestMain wiring**, exactly as we did for
   `SelfBlanket`, `SelfConatus`, `SelfAdjunction`, `SelfField`.
4. **Architecture-check rules**, no new boundary rules expected.
   Rule [12] (planned) is **still planned** — Phase 5.5 is when
   pipeline call sites first touch `Holistic` / `Formal`, and
   only then will we have the ground state required to enforce
   "consumers must access them only through `Self.Adjunction`."

Phase 5 deliberately does **not** touch `Core.Intuition`,
`Core.ConsciousnessLoop`, `RouteEffects`, `RenderStyle`, or
`Recovery`. Those changes belong to Phase 5.5 and will live in
their own PRs.

## 8. Open design questions

Resolved in the Phase-5 PR; flagged here so the reviewer can
challenge the implementer rather than re-litigate the design.

### 8.1 Functional form of the squash

`sigmoid` is the obvious choice for projecting `raw ∈ ℝ` to
`(0, 1)`. The choice of slope is bikeshed-eligible. We commit to
`sigmoid (raw / temperature)` with `temperature = 1.0` as the
Phase-5 default, exposed through `SalienceWeights` so Phase 7 can
calibrate.

### 8.2 What is `normalisedDispersion`?

The exact formula for `salienceConfidence` is the largest
remaining open question. Two reasonable choices:

- (a) `1 - (sum of |contribution_i| / |max contribution|)` —
  high when one driver dominates, low when contributions are
  equal magnitude.
- (b) Logarithmic spread of contributions — symmetric and scale-
  invariant, but more expensive.

Phase 5 ships choice (a) with explicit Haddock; (b) is a Phase-7
calibration option.

### 8.3 Is `defaultSalienceWeights` user-overridable at runtime?

Yes, but **not** in Phase 5. The `SalienceWeights` argument to
`computeSalience` is plumbing for Phase 7. Phase 5 itself has only
one consumer of `computeSalience` — the Phase-5 test suite — and
that consumer always uses `defaultSalienceWeights`.

## 9. Alternatives considered

### 9.1 Binary verdict (`Holistic | Formal`)

Rejected (§2.1). Loses bias magnitude and confidence; would
require parallel `intuitionStrength`-style scalars hand-rolled at
each call site, defeating the point of having a single algebraic
verdict.

### 9.2 Pure scalar (`newtype Salience = Salience Double`)

Rejected (§2.1). Loses driver attribution; would need a parallel
trace channel for /why/ at every consumer.

### 9.3 Salience as a function `Field -> SalienceVerdict`

Rejected. The intermediate `Salience` record is consumed by more
than one downstream operation: `salienceVerdict` is one of them,
but trace serialisation, recovery diagnostics, and the planned
Phase-7 lifeness gates also need the full structured form.
Collapsing to `SalienceVerdict` at the controller's boundary
would force every consumer to recompute internal information.

### 9.4 Replace Conatus gate with a soft penalty

We considered subtracting `(1 - normalisedConatus)` from the raw
score instead of the hard gate. Rejected for two reasons: (i) the
Phase-0 thesis ranks Conatus as a /precondition/, not as just
another input — its violation should /override/ Field, not blend
with it; (ii) the soft-penalty option produces a smoother surface
that is harder to test for the "low Conatus forces Formal"
property the rule is supposed to guarantee.

### 9.5 Make `chooseBranch` part of `Self.Adjunction`

Rejected. `chooseBranch` is genuinely about salience — it consumes
a `Salience` value to decide. Putting it in `Self.Adjunction`
would force `Self.Adjunction` to know about `Self.Field` and
`Self.Conatus`, breaking the dependency-light discipline that
Phase 3 deliberately maintained. Keeping `chooseBranch` in
`Self.Salience` keeps the algebraic core (Phase 3) clean.

## 10. Acceptance criteria for the Phase-5 PR

The Phase-5 implementation will be considered complete when:

1. `cabal build lib:qxfx0` is clean with the new module exposed.
2. `scripts/check_architecture.sh` passes (no boundary violations
   introduced).
3. `Test.Suite.SelfSalience` ships with at least one property for
   /each/ of the items listed in §7 step 2.
4. The new module exports exactly the surface listed in §7
   step 1 (no incidental exports leaking implementation details).
5. No call site outside `Self.*` and the new test module imports
   the salience controller; pipeline integration is the explicit
   non-goal of P5 and is deferred to P5.5.
6. The Phase-3 and Phase-4 test suites
   (`Test.Suite.SelfAdjunction`, `Test.Suite.SelfField`) pass
   unchanged in their assertions; `Self.Salience`'s introduction
   does not require any modification to the prior algebraic
   layers.

## 11. Honest limits

- **The decision rule is not calibrated.** The default weights
  are pinned to make the property tests pass and the operational
  mapping plausible; they are not derived from any empirical
  ground truth. Phase 7 (lifeness gates) is the calibration step,
  and it is a separately-scoped problem (ADR-0007 §6). What this
  ADR pins is /the shape of the rule and the laws it must
  satisfy/, not the constants.
- **The five-component decomposition is inherited.** Salience
  reads `Field`; if a future ADR (ADR-0011, hypothetical) revises
  the Field decomposition, the controller's rule must be revised
  to match. The interface here treats `Field` opaquely enough
  that the revision should be local.
- **Anti-correlation is enforced operationally, not statically.**
  We rely on `chooseBranch` returning a single morphism rather
  than on a type-system enforcement that the non-leading mode is
  unreachable. A future iteration could wrap the two branches in
  an opaque `SaliencePair` ADT, but for Phase 5 we accept the
  operational discipline as sufficient.
- **No claim is made about consciousness.** The "salience"
  language is borrowed from cognitive neuroscience because it
  describes the function this module performs (selecting which
  input modality dominates a decision); we do not claim the
  module reproduces, models, or has anything to say about the
  biological mechanisms that underlie attentional salience in
  living systems. The borrow is operational, not theoretical.
