# QxFx0 Roadmap

This roadmap tracks the active development direction of `QxFx0`.
(Historical note: earlier revisions framed this tree as an experimental `QxFx0_v3` fork of a separate `../QxFx0` baseline; that split no longer applies — this directory *is* `QxFx0`. Remaining "fork"/"baseline" wording below is legacy phrasing pending a fuller doctrine pass.)

## North Star — Terminal Goal (load-bearing; do not drift from it)

**Everyone else is building tools. We are building a subject.**

An LLM, however capable, is perceived as a tool — a smart, efficient, high-tech
hammer that does for you what you cannot or will not do yourself. No one accuses
a hammer of subjecthood. That perception is a ceiling, not a flaw, and it is not
the ceiling we are working under.

Our corridor of possibility is the opposite end: a **digital subject** — a
digital personality with virtues *and* flaws. Not an assistant optimized for the
user's convenience, not a product for sale, but a particular **kind of dialogue**:
one with someone who has a stable identity, holds positions, is accountable to its
own commitments, can be wrong, stubborn, or grow, and is governed by its own
constitution rather than by user utility.

This is why the architecture is what it is. The Self layer (Blanket, Conatus,
Field, Essence), constitution-aware admission (the CTS program), commitment
accountability (quarantine → promotion), identity invariants, deterministic and
auditable behavior — these are **not** over-engineering relative to a tool. They
are the *substance* of a subject: a self that persists, reasons it can be held to,
and a character that does not dissolve to please.

**The bar that makes or breaks it:** subjecthood must be *felt outward* in dialogue
— consistency of character across time, memory that shapes positions, the capacity
to hold or refuse, to be mistaken and to change for reasons. Internal contracts are
the scaffold; the lived sense of "this is someone" is the goal. Every feature is
measured against that, not against tool-utility benchmarks.

## Fork Principles

1. Keep the fork buildable before making it more ambitious.
2. Prefer explicit experiments over accidental drift.
3. Preserve reproducibility and observability unless a given experiment is explicitly about relaxing them.
4. Record divergence from baseline in docs before or alongside code.
5. Compare new behavior against the baseline system, not against memory.

## Immediate Setup

1. Rebuild the fork from a clean checkout state after artifact cleanup.
2. Confirm which existing gates remain practical in this local environment.
3. Establish a fork-specific change log for experimental divergence.
4. Keep generated artifacts and specs synchronized before larger refactors.

## Roadmap Usage Model

This roadmap is meant to function as a schedule of action, not as a theory-only
manifesto.

Document split:
- `ROADMAP.md` = doctrine/program spine
- `docs/execution_board.md` = brutally current execution coordinator
- `docs/front_archive.md` = append-only historical memory
- `docs/closure/REMAINING_CLOSURE_CHECKLIST.md` = compact remaining-debt list
  for the path to the final anchor

Update rules:
- `ROADMAP.md` changes rarely and only when doctrine/program/gate logic changes
- `docs/execution_board.md` changes frequently and tracks the active queue
- `docs/front_archive.md` stores summary + links, not duplicated slice-doc
  contents

### Programs

Programs are long-running lines of work (`M0–M5`, future `SG*`).
They define what kind of architecture the fork is moving toward.

### Fronts

Fronts are bounded proof or implementation campaigns such as:
- `SLICE-AN-001`
- `SLICE-MG-001`
- `SLICE-IS-001`
- `SLICE-TD-001`
- `SLICE-BC-001`
- `SLICE-DR-001`

A front is the unit that actually moves next.

### Claim scope doctrine

Claims are always read through a scope, not globally by default.
At minimum a claim must declare:
- field/subfield scope
- contour scope (`live`, `synthetic`, `authoritative`, `non-authoritative`)
- horizon scope (`next_turn`, `short_horizon`, etc.)

A result that weakens a claim in one contour does not automatically close it in
all contours.

### Front lifecycle doctrine

Every front should use one of these states:
- `planned`
- `qualification_pending`
- `resolved_live`
- `resolved_synthetic`
- `blocked_live`
- `blocked_synthetic`
- `blocked_by_control_baseline`
- `proof_in_progress`
- `reclassification_pending`
- `closed`

### Reclassification doctrine

Negative evidence is productive. It is used to compress false authority claims,
not to treat a proof program as failed.

Typical reclassification moves are:
- `ASSUMED -> NOT_PROVEN`
- `continuity_core_candidate -> weak_authority_for_now`
- `authority-for-now -> projection/config/compatibility candidate`

### Bidirectional semantic-machine doctrine

The system's semantic mission is bidirectional.

It must be able to:
1. transform words into structured semantic atoms, frames, and plans,
2. transform those semantic structures back into constrained lexical/surface
   realization,
3. keep both directions coupled under one governed artifact, authority, and
   reconstruction regime.

Implications:
- `M3` governs which semantic carriers are real authority, derived state,
  projection, or compatibility residue,
- `M4` governs which internal semantic transformations become explicit
  functional laws,
- `SG0–SG4` governs the lexical/surface machine so semantic modernization does
  not outrun the SQL×GF contour,
- `M4.5` governs how future semantic correction pressure is formed without
  creating a second live semantic ruler.

The roadmap should therefore be read not as several unrelated programs, but as
one modernization effort over the full cycle:
- words -> semantic atoms / frames / plans -> words

This program is now the main organizing line of the fork. The goal is not to
add more mathematical rhetoric, but to replace plausible mathematical imitation
with explicit, versioned functional laws, reconstruction semantics, and proof
pressure.

### Final Anchor Doctrine

The fork does not modernize only to become cleaner, more mathematical, or more
modular.

Its final anchor is to become a governed, checked evidence package that code can
sustain an algorithmic subject structure for meaningful domain dialogue with a
human.

For this fork, `algorithmic subject structure` does not mean consciousness,
personhood, unrestricted general intelligence, or anthropomorphic theater.

It means the runtime can sustain, under explicit regime rules:

1. bounded self-related continuity across turns and restarts,
2. domain-grounded semantic commitments rather than surface-only fluency,
3. accountable revision under correction,
4. governed distinction between authority, projection, fallback,
   compatibility residue, and quoted external output,
5. bidirectional semantic participation in dialogue:
   - words -> structured semantic atoms / frames / plans -> words

For this fork, `meaningful domain dialogue` means dialogue in which the system
can:

- carry domain-bearing commitments across turns,
- answer, refine, retract, or repair those commitments under challenge,
- expose replay-visible and governance-visible reasons for persistence,
  revision, refusal, or fallback,
- remain bounded by declared authority, reconstruction, and recovery contours.

This final anchor remains scope-bound, contour-bound, and evidence-bound.

It must not be implemented as a single magical per-turn identity gate or as a
new hidden authority carrier.

If future anchor-related runtime checks exist, they must remain explicitly
separated across at least these contours:
- continuity / coherence
- restart integrity
- commitment accountability
- bounded domain-dialogue competence

Because the fork aims at a new class of governed dialogue runtimes rather than
another answer generator, it carries elevated architectural responsibility.
Implicit authority, hidden continuity, decorative semantic rhetoric, and
undemonstrated “intelligence” are therefore not acceptable substitutes for
checked runtime discipline. The stronger the system's claim to meaningful
content-bearing dialogue, the less right it has to rely on ambiguity. Its
ambition is justified only where replayability, restart-safety, authority
classification, commitment accountability, and semantic shaping can be made
explicit, bounded, and checkable.

No global metaphysical claim is made.

### M0 — Mathematical Constitution Freeze

Deliverables:
- freeze the vocabulary for claim classes, proof status, restore modes, and
  candidate classes
- freeze the distinction between authority, projection, config/substrate, and
  compatibility residue
- freeze result-ledger and fixture-qualification formats
- define machine-readable claim / proof-status / reclassification schemas
- define allowed status-transition rules for proof and reclassification updates

Exit criteria:
- all proof artifacts speak one language
- `code_read` vs `checked_in_test` vs `harness` proof semantics are explicit
- new proof fronts cannot invent their own local taxonomy
- taxonomy and status transitions are enforceable by artifact/protocol rules

### M1 — Canonicalize Strong Kernel

Scope:
- `R5`
- `Conatus`
- `Adjunction`
- core `Salience`

Deliverables:
- a checked-in map of the strong mathematical kernel
- explicit regime boundaries for the strong kernel
- cleanup where prose overstates runtime mechanics
- per-kernel-component kernel map template including:
  - canonical modules
  - law statements
  - existing tests
  - missing tests
  - known non-authoritative consumers

Exit criteria:
- strong kernel is explicitly identified and internally consistent across docs
  and code
- each kernel component has a declared state/input space and law boundary
- kernel identification is backed by template-based, reusable artifact structure

### M2 — Honest Heuristic Reclassification

Scope:
- `Intuition`
- `Dream`
- `Field`
- `Essence` rhetoric vs implementation
- persistence assumptions around auxiliary semantic fields
- `Datalog` role clarification: bounded validator vs real rerouter vs offline
  semantic critic

Deliverables:
- heuristic classification matrix
- calibration debt register
- explicit migration target for each heuristic subsystem
- explicit Datalog role decision for the fork: it must not remain half-written
  as validator in code and rerouter in prose

Concepts activated in M2:
- live participation in behavior does not automatically imply authority
- current-turn truth and future-turn truth are distinct architectural contours
- heuristic math must be labelled honestly before it is upgraded or persisted
- Datalog must hold one declared role, not several rhetorical roles at once

Exit criteria:
- heuristic math no longer masquerades as strong authority
- each weak subsystem is clearly labelled as formal kernel, bounded heuristic,
  authority-for-now, projection, or config/substrate
- Datalog has one declared architectural role, not competing narratives

### M3 — Persistence and Reconstruction Proof Program

Scope:
- `semanticAnchor`
- `meaningGraph`
- `intuitionState`
- `trace`
- then `lastTurnDecision`, `blockedConcepts`, `dreamState`, `kernelPulse`, `clusters`,
  `semanticConfig`, `intuitConfidence`

Deliverables:
- semantic authority inventory
- explicit state-classification map for:
  - authoritative persisted state
  - ephemeral runtime state
  - derived / rebuildable state
- restore precedence / contamination specification
- restart-safety / restart-admission contract for authoritative,
  non-authoritative, degraded, and compatibility-only restore contours
- current commit / restore state-machine artifact separating:
  - must-be-atomic turn truth
  - restart-safe persistence
  - best-effort post-commit hydration / projection / observability work
- equivalence harness and per-slice result ledger
- fixture qualification protocol
- per-field or per-subfield persistence claims with proof status

Concepts activated in M3:
- persistence necessity must be proven by reconstruction or ablation, not by
  mere live-code use
- canonical reconstruction may target behavioral equivalence rather than raw
  snapshot identity
- projection hygiene is a precondition for semantic mathematics
- current-turn authority, restart authority, and future-turn influence are
  distinct contours and must not be conflated by restore code
- negative evidence is a valid and necessary tool for compressing false
  authority claims
- M3 is the demotion-first proof program: its job is not only to find true
  continuity carriers, but to remove false authority candidates until
  reconstruction-first work becomes legitimate

Exit criteria:
- for each targeted field there is an explicit classification:
  authority / derived / compatibility-only / projection / config-substrate
- persistence necessity is either proven, weakened, or left explicitly
  unresolved
- no hidden projection-as-authority path remains in the targeted contour
- restart / bootstrap paths cannot silently reintroduce non-authoritative or
  degraded state as if it were authoritative restart truth

### M4 — Functional Reconstruction by Subsystem

M3 -> M4 gate (per subsystem):
- a subsystem may enter reconstruction-first work only if:
  1. its main false-authority ambiguities are compressed enough,
  2. its persistence role is at least provisionally classified,
  3. projection/residue confusion is no longer the dominant uncertainty,
  4. a declared reconstruction target exists,
  5. proof progress is no longer driven mainly by new demotion evidence

M3 -> M4 rejection rule (per subsystem):
- a subsystem is not ready for reconstruction-first work if:
  - new progress still mainly comes from false-authority demotion,
  - whole-field authority status remains ambiguous,
  - projection vs authority is still unresolved,
  - or claim framing is still unstable

Scope order:
1. `TurnDecision` as projection algebra
2. `BlockedConcepts` as heuristic-pressure algebra
3. `dreamState` as plasticity algebra
4. `Datalog × Intuition -> Dream` reconciliation channel
5. later remaining reconstruction candidates as evidence requires

Deliverables:
- explicit subsystem state specs
- explicit update laws
- explicit reconstruction laws
- versioned regime boundaries
- migration away from unjustified carry-forward snapshots where possible
- explicit semantic-core deepening plan for the bounded contour where current
  parsing / semantic decomposition / commitment representation are too weak for
  meaningful domain dialogue
- stronger linkage between internal semantic structures and commitment-bearing
  dialogue behavior so that domain commitments do not rest on surface fluency
  alone
- explicit constitution-to-semantics contract describing how `Conatus`,
  `Field`, `Essence`, and salience shaping may influence interpretation,
  commitment formation, and reply construction without becoming hidden semantic
  authority shortcuts

Concepts activated in M4:
- the system must move from a modular brain with strong pieces to a unified
  theory of semantic plasticity
- offline intelligence is a first-class mode of the system, not an afterthought
- semantic modernization and surface modernization must remain coupled enough to
  prevent the inner semantic core from outrunning the lexical/surface machine
- future-turn correction paths must be explicit functional contours, not prose
  about adaptation
- semantic-core strengthening is required for the final anchor, but must not be
  allowed to outrun state-taxonomy, authority, and governance consolidation
- constitution-layer shaping must become explicit enough that semantic
  interpretation and commitment-bearing reply construction are not explained
  only by prose about `Self`, `Conatus`, `Field`, or `Essence`

Technical addition for M4.5 (`Datalog × Intuition -> Dream`):
- see `docs/m4.5-datalog-intuition-dream-reconciliation-spec.md`
- keep Datalog out of live co-rulership in the dialogue loop except for bounded
  validator / gate behavior
- derive a typed `DatalogPressure` from persisted shadow/divergence results
- derive a typed `IntuitionPressure` from persisted intuition state / flash
  residue rather than reusing raw online objects directly
- introduce a `DreamPressure` reconciliation layer where symbolic
  contradiction (`DatalogPressure`) and pre-symbolic tension
  (`IntuitionPressure`) meet
- constrain Dream so it emits bounded repair pressure / graph reweighting /
  correction candidates, not silent direct authority rewrites
- route any future semantic mutation through governed acceptance rather than
  allowing Dream or Datalog to become hidden authority

First implementation slice for M4.5:
- add `src/QxFx0/Types/DreamPressure.hs` with:
  - `DatalogPressure`
  - `IntuitionPressure`
  - `DreamPressure`
  - `DreamCorrectionCandidate`
  - `DreamOutcome`
- extend `src/QxFx0/Types/Config/Dream.hs` with `DreamPressureRegime` and
  `defaultDreamPressureRegime`
- add `src/QxFx0/Core/Dream/Pressure.hs` with:
  - `deriveDatalogPressure :: TurnPlan -> DatalogPressure`
  - `deriveIntuitionPressure :: TurnSignals -> IntuitionPressure`
  - `reconcileDreamPressures :: DreamPressureRegime -> DatalogPressure -> IntuitionPressure -> DreamPressure`
  - `dreamPressureToBias :: DreamPressure -> CoreVec`
  - `dreamPressureToCandidates :: DreamPressure -> [DreamCorrectionCandidate]`
  - `buildDreamOutcome :: DreamPressureRegime -> TurnInput -> TurnSignals -> TurnPlan -> TurnArtifacts -> DreamOutcome`
- integrate `DreamOutcome` into `src/QxFx0/Core/TurnPipeline/Finalize/Dream.hs`
  only as bounded Dream evidence / graph-bias input
- do **not** in the first slice:
  - change current-turn family selection
  - persist raw pressure objects as authority
  - bypass existing governance mutation acceptance
  - widen the Bridge/Core seam beyond existing `TurnPlan` / `TurnSignals`
- add initial tests to the isolated semantic-slices target for:
  - deterministic pressure derivation
  - bounded pressure values
  - no live family override
  - candidate-threshold behavior

M4.5 first-slice exit criteria:
- all four pressure/outcome types exist as explicit typed contours
- Dream consumes Datalog and Intuition only through the new typed channel
- current-turn route authority remains unchanged
- no new persisted authority fields are introduced
- Dream pressure can influence only bounded offline correction signals
- tests prove determinism/boundedness/no-live-override for the first slice

Exit criteria:
- a subsystem is no longer “math by prose”
- persistence role is proven or removed
- reconstruction source is explicit
- ablation/equivalence evidence is checked in
- for M4.5 specifically:
  - `DatalogPressure`
  - `IntuitionPressure`
  - `DreamPressure`
  - `DreamOutcome`
  are explicit typed contours
  - Datalog is no longer half-validator / half-rerouter by implication
  - Dream-mediated future correction is explicit and bounded
  - no live second-brain authority path has been introduced

### M5 — Regime Governance and Mathematical Runtime Discipline

Deliverables:
- regime governance document
- versioned dependency contour for normalization, thresholds, update, and
  reconstruction
- math change protocol and proof dashboard
- synthetic vs live proof policy and disguised-snapshot guard policy
- machine-visible regime/version markers
- change-type -> evidence requirement table
- explicit fallback-policy classification artifact for major runtime seams:
  - fail-closed
  - fail-open degraded
  - compatibility fallback
  - observational-only
- runtime architecture-debt register covering at least:
  - state taxonomy / restart authority
  - commit / restore protocol boundaries
  - bootstrap phase boundaries
  - control-plane subsystem boundaries
  - singleton lifecycle / hidden global cache assumptions
  - docs / config / deploy drift rules

Concepts activated in M5:
- governance becomes the template for every mature mutation contour, not just a
  subsystem with special privileges
- quality of seams outranks richness of subsystems: no new strong subsystem is
  accepted if its authority, reconstruction, or projection boundaries are weak
- offline correction paths are first-class system behavior and must be governed
  like any other authority-bearing runtime path
- orchestration debt in bootstrap, persistence, finalize, and sidecar control
  planes is architecture work, not hygiene to postpone indefinitely

Exit criteria:
- mathematical changes cannot silently drift through runtime behavior
- reconstruction-affecting changes require explicit regime/version handling
- subsystem maturity is globally visible
- regime metadata and evidence requirements are machine-visible rather than
  purely doctrinal
- major fallback paths are classified by policy rather than left implicit in
  orchestration code
- lifecycle and control-plane seams have declared boundaries before they are
  expanded again

### M6 — Algorithmic Subject Demonstration

This phase is the terminal anchor of the fork.

`M0–M5` prepare the system to make one bounded final claim:
that code in this runtime can sustain an algorithmic subject structure for
meaningful domain dialogue with a human under governed, checkable conditions.

Deliverables:
- a checked definition of `algorithmic subject structure` for this fork
- a checked definition of `meaningful domain dialogue`
- a witness protocol tying runtime behavior, replay, persistence, restart
  integrity, and dialogue commitments together
- a negative-criteria list describing what does **not** count as subject
  evidence
- a bounded benchmark / fixture family for human dialogue evaluation on declared
  domain contours
- a machine-readable claim/evidence structure for `M6` verdicts
- explicit distinction between:
  - subject-structure evidence
  - projection fluency
  - external-tool support
  - fallback survival
  - compatibility residue

Concepts activated in M6:
- fluency alone is not subject structure
- persistence alone is not subject structure
- heuristic adaptation alone is not subject structure
- restart integrity is part of subject-structure evidence, not a separate ops
  concern
- a subject claim requires governed continuity, semantic accountability,
  correction capacity, and domain-bearing dialogue behavior together
- the system must distinguish its own bounded commitments from external tool
  output, fallback residue, operator-facing projection, and compatibility-only
  state while dialoguing
- the final claim is architectural and evidential, not metaphysical
- `M6` is a witness regime, not a license to introduce one new totalizing anchor
  gate in place of explicit subsystem evidence
- constitution-shaped interpretation and response formation must be explicit
  enough that the system can explain how its internal constitution influences
  dialogue without claiming hidden semantic authority

Negative doctrine:
- the fork explicitly rejects the following as sufficient evidence of `M6`:
  - surface fluency
  - vague anthropomorphic prose
  - hidden singleton continuity
  - non-authoritative restart carry
  - untracked fallback behavior
  - external-tool paraphrase mistaken for subject continuity

Exit criteria:
- the system can sustain qualified multi-turn domain dialogue without relying on
  hidden or non-authoritative restart authority
- the system can preserve, refine, retract, and repair domain commitments under
  correction in a replay-visible and governance-visible way
- the system can distinguish authoritative state from projection, fallback,
  quoted external output, and compatibility residue while dialoguing
- the dialogue evidence is reproducible enough to be checked, not merely
  narrated
- the final claim is expressed as a bounded evidence package, not as a global
  philosophical declaration

## Companion Program — SQL × GF Contour Modernization

This program runs in parallel with the mathematical-kernel program. Its purpose
is to keep the surface/lexical machine aligned with semantic modernization.

### SG0 — Canonical Source Classification

Deliverables:
- classify SQL, GF, generated Haskell, morphology JSON, and hand-authored files
  into:
  - canonical
  - auxiliary
  - generation substrate
  - legacy/manual override

Exit criteria:
- the SQL×GF contour no longer relies on implied canonicality
- every major lexical/surface artifact has one declared authority role

### SG1 — Lexical IR and Artifact Path Freeze

Deliverables:
- explicit SQL -> lexical IR -> artifact path definition
- explicit statement of what SQL feeds GF, what SQL feeds morphology, and what
  GF consumes at runtime
- explicit statement of what is hand-authored GF and what is generated GF

Exit criteria:
- one canonical lexical artifact path exists for the Russian core contour
- overlapping supplier paths are either demoted or made explicitly auxiliary

### SG2 — Live Runtime Consumer Cleanup

Deliverables:
- identify runtime-live SQL surfaces
- demote stale SQL surfaces from runtime-critical status where no live consumer
  exists
- explicitly classify `realization_templates` as live, dormant, or removable

Exit criteria:
- runtime-critical SQL surfaces correspond to actual runtime consumers
- stale SQL contract obligations are no longer carried just by historical habit

### SG3 — GF Authority and Surface Contract Cleanup

Deliverables:
- explicit distinction between hand-authored GF syntax and SQL-derived lexical GF
- explicit authority map for PGF path, GF map path, and Haskell fallback path
- replay/trace semantics aligned with actual surface authority categories

Exit criteria:
- GF authority is no longer described more broadly than the code supports
- surface-generation authority is consistent across docs, runtime, and traces

### SG4 — Coupled Semantic/Surface Evolution Rule

Deliverables:
- explicit rule that semantic modernization and surface modernization must remain
  coupled enough to avoid an inner semantic core outrunning the lexical/surface
  machine
- decision criteria for when a semantic change requires SQL×GF artifact updates
- checked-in change-impact protocol mapping semantic/surface change classes to
  required actions and evidence

Exit criteria:
- semantic changes that alter lexical or surface assumptions cannot land without
  a declared SQL×GF consequence assessment
- at least a lightweight retrospective validation proves the protocol is usable

## Companion Program — Adaptive / Peripheral Authority Seam Hardening

This program exists to harden the side seams that can mutate future state,
shape output indirectly, or distort authority conclusions without living in the
central mathematical kernel.

### AS0 — Adaptive / Peripheral Seam Inventory

Deliverables:
- inventory of under-audited adaptive/peripheral seams, including:
  - external learning authority asymmetry
  - request-driven external query vs guardrail asymmetry
  - tool identity / reliability attribution seams
  - dialogue-development persistent heuristic seams
  - governance runtime fault propagation seams
  - readiness/runtime-mode split seams
  - restart / bootstrap authority seams
  - commit vs runtime-hydration seam coupling
  - HTTP sidecar control-plane concentration seams
  - session token / ownership durability seams
  - hidden global singleton lifecycle seams
  - legal adapter authority seams
  - calibration/training window and proxy-data seams
- for each seam:
  - mutation capability
  - authority risk
  - target remediation phase (`AS1`–`AS4`)

Exit criteria:
- the main peripheral/adaptive seams are named and classified
- no future seam-hardening work needs to start from implicit memory alone

### AS1–AS4 — Reserved remediation spine

Status:
- reserved
- non-active
- not part of the current live execution queue

Planned meanings:
- `AS1` — pre-effect gating and external action integrity
- `AS2` — governed adaptation chain for persistent heuristic mutation
- `AS3` — fault propagation and control-plane coherence across
  runtime/health/readiness/bootstrap surfaces
- `AS4` — calibration/training realism and temporal-scope discipline

## Priority Discipline and Deferred Architecture Queue

Execution rule:
- work the current front recorded in `docs/execution_board.md` until it reaches
  a real decision point
- then either continue the same front if the decision remains open,
- or explicitly shift the main front in `docs/execution_board.md`
- do not treat this roadmap as a duplicate live queue or historical packet dump
- never treat several proof fronts as if they had equal epistemic priority

Current doctrinal reading after the completed `AN` / `MG` / `IS` / `TD` /
`BC` / `DR` / `EL` / `SS` / `NA` / `state taxonomy` / `commit-restore` /
`bootstrap lifecycle` / `sidecar decomposition` / `fallback policy` /
`bounded drift` / `persistence contract` / `projection-vs-authority` /
`commitment-store relation` sequence:
- multiple previously plausible continuity carriers were demoted on tested
  contours; live-code presence alone did not justify persisted authority
- `blockedConcepts` and `dreamState` emerged as the more meaningful checked
  future-state / plasticity contours in the tested packages
- `SLICE-NA-001` closed the bounded illegitimate restart-authority re-entry seam
  for non-authoritative or degraded semantic carry without broad redesign
- the checked state taxonomy and restart-safety map now make persisted,
  restored, rebuilt, hydrated, and first-behavior-reaching classes explicit
  enough that later H2 work no longer needs to infer authority from prose or
  persisted presence alone
- the checked commit / restore state machine now makes durable authoritative
  truth, projection truth, runtime-only commit, rollback scope, rebuild scope,
  and best-effort post-commit work explicit enough that later lifecycle work no
  longer needs to infer truth boundaries from code structure alone
- the checked bootstrap lifecycle map now makes authoritative restore,
  substrate backfill, rebuild, validation, runtime hydration, and session
  materialization explicit enough that later H2 work no longer needs to treat
  bootstrap as one lifecycle blur
- the checked sidecar control-plane decomposition now makes transport shell,
  auth, admission, ownership, registry, readiness/health, worker lifecycle,
  shutdown, and response mapping explicit enough that later H2 work no longer
  needs to infer control-plane structure from one large module/process contour
- the checked fallback-policy map now makes fail-closed, fail-open degraded,
  compatibility fallback, and observational-only runtime seams explicit enough
  that later work no longer needs to infer policy authority from scattered
  local handling
- bounded drift cleanup compressed misleading docs / CI / deploy / env /
  singleton-global residue so later work no longer needs to guess whether a
  surface is canonical, transitional, dead, or merely operational convenience
- the checked persistence contract now makes canonical write shape, tolerated
  read shapes, behavior-relevant decode defaults, and hot-path compatibility
  residue explicit enough that later work no longer needs to rely on
  transitional persistence ambiguity
- the checked projection-vs-authority surface hardening now makes canonical
  authority, projection truth, observational-only, and compatibility/shim
  surfaces explicit enough that visibility, persistence, or replay richness no
  longer has to imply authority for operators or future code
- the checked commitment-store relation hardening now makes canonical
  commitment constraint, derived dialogue structure, advisory stance/policy
  memory, and perspectival interpretation explicit enough that later
  formalization no longer needs to treat them as one loose commitment blob
- the checked constitution-to-semantics contract deepening now makes
  constitution-bearing contours, semantic formation stages, explicit vs
  implicit coupling, and weak constitution-blind zones explicit enough that
  later deepening no longer has to rely on architectural intuition alone
- the checked `CTS-01 — constitution-aware commitment admission` now makes raw
  semantic commitment candidates explicit enough that canonical strengthening no
  longer happens by default under degraded or non-authoritative contours; an
  explicit constitution/truth admission layer now sits before canonical
  commitment strengthening while late finalize downgrade remains as a second
  safety layer
- the checked `CTS-02 — constitution-aware interpretation admissibility` now
  makes raw interpretation candidates and constitution-admissible interpretation
  outputs explicit and separate before route family crystallization; weakened
  constitutional/truth contours can now narrow the route-facing interpretation
  plane earlier than before while parser/proposition machinery, sense
  extraction, and CTS-01 commitment admission remain intact and bounded
- the checked `CTS-03 — constitution-aware proposition/frame admissibility` now
  makes raw proposition/frame outputs and constitution-admissible
  proposition/frame outputs explicit and separate; weakened constitutional/truth
  contours can soften proposition/frame confidence earlier than before while
  parser/proposition machinery and later admissions remain layered and intact
- the checked `CTS-04 — constitution-aware semantic frame admissibility` now
  makes raw semantic-frame outputs and constitution-admissible semantic-frame
  outputs explicit and separate; weakened constitutional/truth contours can
  soften semantic-frame confidence earlier than before proposition admission
- the checked `CTS-05 — constitution-aware sense-vector admissibility` now makes
  raw sense-vector outputs and constitution-admissible sense-vector outputs
  explicit and separate; weakened constitutional/truth contours can dampen
  semantic emphasis earlier than before route/meaning shaping consumes the
  vector while earlier admissions remain layered and intact
- the checked `CTS-06 — constitution-aware route-hint admissibility` now makes
  raw route-hint outputs and constitution-admissible route-hint outputs
  explicit and separate; weakened constitutional/truth contours can soften
  routing bias earlier than before proposition admission and route-family
  crystallization consume it while earlier admissions remain layered and intact
- the checked `CTS-07 — constitution-aware route-family crystallization` now
  makes raw family crystallization and constitution-admissible family
  crystallization explicit and separate; weakened constitutional/truth contours
  can cap strong family hardening earlier than before the routed family drives
  downstream response shaping while all earlier admission seams remain layered
  and intact
- the checked `CTS-08 — constitution-aware semantic logic family admissibility`
  now makes raw semantic-logic family recommendation and constitution-admissible
  early family recommendation explicit and separate; weakened
  constitutional/truth contours can soften or cap the early family bias before
  later route-family crystallization consumes it while later family admission,
  route-hint admission, sense-vector admission, semantic-frame admission,
  proposition/frame admission, interpretation admission, and commitment
  admission remain layered and intact
- the checked `CTS-09 — constitution-aware semantic-logic weighting admissibility`
  now makes raw weighted family ordering and constitution-admissible weighted
  family ordering explicit and separate; weakened constitutional/truth contours
  can soften or cap the top-family bias before early family admission consumes
  it while all later admissions remain layered and intact
- the checked `CTS-10 — constitution-aware semantic-logic rule contribution admissibility`
  now makes raw semantic-logic contribution law and constitution-admissible
  contribution weighting explicit and separate; weakened constitutional/truth
  contours can soften contribution weights before semantic-logic weighting
  admissibility consumes them while the later weighting/order, early family,
  family crystallization, route-hint, sense-vector, semantic-frame,
  proposition/frame, interpretation, and commitment admissions remain layered
  and intact
- the checked `CTS-11 — constitution-aware atom contribution admissibility` now
  makes raw atom contribution activation and constitution-admissible atom
  contribution activation explicit and separate; weakened constitutional/truth
  contours can cap which extracted atoms become active contribution sources
  before semantic-logic contribution weighting is built
- the checked `CTS-12 — constitution-aware atom extraction admissibility` now
  makes raw AtomSet extraction and the admitted atom plane explicit and
  separate; weakened constitutional/truth contours can suppress extracted atom
  activation before later atom contribution admission consumes the plane
- the checked `CTS-13 — constitution-aware lexical/cluster atom finding admissibility`
  now makes raw lexical/cluster findings and admitted lexical/cluster findings
  explicit and separate; weakened constitutional/truth contours can soften or
  suppress lexical/cluster findings before the admitted atom plane consumes
  them
- the previously described `CTS-15` lexical/cluster matching slice overlapped
  the already-closed `CTS-13` seam because both sat after raw lexical/cluster
  findings already existed
- the corrected distinct bounded slice is therefore `CTS-15r —
  constitution-aware lexical/cluster raw emission admissibility`, which sits
  one step earlier, between raw lexical/cluster emitted matches and the already
  admitted finding layer
- the checked `CTS-16 — constitution-aware lexical/cluster hit production admissibility`
  now makes raw lexical/cluster hit production and constitution-admissible hit
  production explicit and separate; weakened constitutional/truth contours can
  suppress strong raw hits before lexical/cluster emitted matches are formed
- the checked `CTS-17 — constitution-aware lexical/cluster pre-hit phrase-containment admissibility`
  now makes raw lexical/cluster phrase containment and constitution-admissible
  phrase containment explicit and separate; weakened constitutional/truth
  contours can suppress strong phrase containment before `CTS-16` raw hit
  production is formed
- the checked `CTS-18 — constitution-aware pre-hit phrase-containment decision admissibility`
  now makes raw lexical/cluster phrase-containment decisions and
  constitution-admissible phrase-containment decisions explicit and separate;
  weakened constitutional/truth contours can suppress strong matched decisions
  before `CTS-17` raw phrase-containment results are formed
- the checked `CTS-19 — constitution-aware proposition keyword-fallback admissibility`
  now makes raw proposition keyword-fallback phrase decisions and
  constitution-admissible proposition fallback decisions explicit and separate;
  weakened constitutional/truth contours can suppress strong fallback phrase
  decisions before fallback proposition types are derived
- the checked `CTS-20 — constitution-aware proposition phrase-consumer admissibility`
  now makes raw proposition contact-trigger decisions and
  constitution-admissible contact-trigger decisions explicit and separate;
  weakened constitutional/truth contours can suppress strong contact triggers
  before `detectContactSignal` finalizes a proposition outcome
- the checked `CTS-21 — constitution-aware proposition confront-trigger admissibility`
  now makes raw proposition confront-trigger decisions and
  constitution-admissible confront-trigger decisions explicit and separate;
  weakened constitutional/truth contours can suppress strong confront triggers
  before `detectConfrontSignal` finalizes `ConfrontQ`
- the checked `CTS-22 — constitution-aware proposition next-step-trigger admissibility`
  now makes raw proposition next-step-trigger decisions and
  constitution-admissible next-step-trigger decisions explicit and separate;
  weakened constitutional/truth contours can suppress strong next-step triggers
  before `detectNextStepSignal` finalizes `NextStepQ`
- the checked `CTS-23 — constitution-aware proposition operational-status admissibility`
  now makes raw proposition operational-status trigger decisions and
  constitution-admissible operational-status trigger decisions explicit and
  separate; weakened constitutional/truth contours can suppress strong
  operational-status triggers before `detectOperationalStatus` finalizes
  `OperationalStatusQ`
- the checked `CTS-24 — constitution-aware proposition operational-cause admissibility`
  now makes raw proposition operational-cause trigger decisions and
  constitution-admissible operational-cause trigger decisions explicit and
  separate; weakened constitutional/truth contours can suppress strong
  operational-cause triggers before `detectOperationalCause` finalizes
  `OperationalCauseQ`
- the checked `CTS-25 — constitution-aware proposition system-logic admissibility`
  now makes raw proposition system-logic trigger decisions and
  constitution-admissible system-logic trigger decisions explicit and
  separate; weakened constitutional/truth contours can suppress strong
  system-logic triggers before `detectSystemLogic` finalizes `SystemLogicQ`
- the checked `CTS-26 — constitution-aware proposition distinction admissibility`
  now makes raw proposition distinction-trigger decisions and
  constitution-admissible distinction-trigger decisions explicit and separate;
  weakened constitutional/truth contours can suppress strong distinction
  triggers before `detectDistinctionQuestion` finalizes `DistinctionQ`
- the checked `CTS-27a — constitution-aware proposition affective-support
  phrase-trigger admissibility` now makes raw direct affective-support
  phrase-trigger decisions and constitution-admissible phrase-trigger decisions
  explicit and separate; weakened constitutional/truth contours can suppress
  strong direct support triggers before support-style proposition outcomes are
  finalized
- the checked `CTS-27b — constitution-aware proposition relaxed-regulation
  probe admissibility` now makes raw affective-support probe decisions and
  constitution-admissible probe decisions explicit and separate; weakened
  constitutional/truth contours can suppress strong probe-driven support
  outcomes before proposition finalization
- the checked `CTS-28 — constitution-aware proposition self-knowledge
  admissibility` now makes raw proposition self-knowledge trigger decisions and
  constitution-admissible self-knowledge trigger decisions explicit and
  separate; weakened constitutional/truth contours can suppress strong
  self-knowledge triggers before `detectSelfKnowledge` finalizes
  `SelfKnowledgeQ`
- the checked `CTS-29 — constitution-aware proposition purpose-function
  admissibility` now makes raw proposition purpose/function trigger decisions
  and constitution-admissible purpose/function trigger decisions explicit and
  separate; weakened constitutional/truth contours can suppress strong
  purpose/function triggers before `detectPurposeFunction` finalizes `PurposeQ`
- the checked `CTS-30 — constitution-aware proposition concept-knowledge
  admissibility` now makes raw proposition concept-knowledge trigger decisions
  and constitution-admissible concept-knowledge trigger decisions explicit and
  separate; weakened constitutional/truth contours can suppress strong
  concept-knowledge triggers before `detectConceptKnowledge` finalizes
  `ConceptKnowledgeQ`
- the checked `CTS-31 — constitution-aware proposition misunderstanding
  admissibility` now makes raw proposition misunderstanding/contact-loss trigger
  decisions and constitution-admissible misunderstanding-trigger decisions
  explicit and separate; weakened constitutional/truth contours can suppress
  strong misunderstanding triggers before `detectMisunderstanding` finalizes
  `MisunderstandingReport` or local repair-side outcomes
- the checked `CTS-32 — constitution-aware proposition world-cause
  admissibility` now makes raw proposition world-cause trigger decisions and
  constitution-admissible world-cause trigger decisions explicit and separate;
  weakened constitutional/truth contours can suppress strong world-cause
  triggers before `detectWorldCause` finalizes `WorldCauseQ`
- the checked `CTS-33 — constitution-aware proposition location-formation
  admissibility` now makes raw proposition location-formation trigger
  decisions and constitution-admissible location-formation trigger decisions
  explicit and separate; weakened constitutional/truth contours can suppress
  strong location-formation triggers before `detectLocationFormation`
  finalizes `LocationFormationQ`
- the next bounded proposition-consumer slice should again be named only after a
  fresh post-`CTS-33` trace identifies the next remaining local consumer that
  can be hardened without broad proposition redesign

Deferred architecture queue once the active front is resolved:
1. broader compatibility compression still deferred beyond the now-explicit
   persistence boundary:
   - PGF/runtime shim compression
   - bootstrap substrate residue compression
   - retirement of tolerated legacy/decode branches when the compatibility
     window is intentionally closed

Closed H2 and adjacent formalization prerequisites already checked in:
- explicit state taxonomy and restart-safety map
- persisted-field -> restore / hydrate / first-behavior matrix
- explicit rule that persisted presence does not imply restart authority
- `SystemState` authority-surface reduction candidates without broad redesign
- transitional persistence-envelope classification
- explicit commit / restore state machine
- durable truth vs projection vs runtime-only vs best-effort boundary map
- rollback scope and restore/rebuild/demotion/runtime-hydrate-only distinctions
- explicit bootstrap lifecycle phase / authority map
- restore vs rebuild vs hydrate vs session materialization distinctions
- explicit sidecar control-plane decomposition map
- authority-bearing vs shell-only sidecar role map
- explicit fallback-policy classification for major runtime seams
- authority consequence map for failure / degradation / compatibility /
  observational handling
- bounded drift cleanup inventory and contract-surface classification
- explicit persistence contract consolidation
- canonical write shape / tolerated read shape / default-decode residue map
- explicit projection-vs-authority surface hardening
- canonical authority vs projection truth vs observational-only vs
  compatibility/shim surface map
- explicit commitment-store relation hardening
- ledger / thread / phase / belief / policy / perspective relation map
- explicit constitution-to-semantics contract deepening
- constitution-bearing contour inventory / semantic formation stage inventory /
  explicit-vs-implicit coupling map / weak constitution-blind zone inventory
- explicit `CTS-01 — constitution-aware commitment admission`
- candidate-vs-admitted commitment seam and bounded early strengthening caps
- explicit `CTS-02 — constitution-aware interpretation admissibility`
- raw-vs-admitted interpretation seam before route family crystallization
- explicit `CTS-03 — constitution-aware proposition/frame admissibility`
- raw-vs-admitted proposition/frame seam
- explicit `CTS-04 — constitution-aware semantic frame admissibility`
- raw-vs-admitted semantic-frame seam
- explicit `CTS-05 — constitution-aware sense-vector admissibility`
- raw-vs-admitted sense-vector seam before route/meaning shaping
- explicit `CTS-06 — constitution-aware route-hint admissibility`
- raw-vs-admitted route-hint seam before route-family crystallization
- explicit `CTS-07 — constitution-aware route-family crystallization`
- raw-vs-admitted family crystallization seam before downstream response-path hardening
- explicit `CTS-08 — constitution-aware semantic logic family admissibility`
- raw-vs-admitted early family seam before later family crystallization
- explicit `CTS-09 — constitution-aware semantic-logic weighting admissibility`
- raw-vs-admitted weighted family ordering before early family admission
- explicit `CTS-10 — constitution-aware semantic-logic rule contribution admissibility`
- raw semantic-logic contribution law vs admitted contribution weighting seam
- explicit `CTS-11 — constitution-aware atom contribution admissibility`
- raw-vs-admitted atom contribution activation seam
- explicit `CTS-12 — constitution-aware atom extraction admissibility`
- raw AtomSet extraction vs admitted atom plane seam
- explicit `CTS-13 — constitution-aware lexical/cluster atom finding admissibility`
- raw-vs-admitted lexical/cluster finding seam before admitted atom plane filtering

Sequence constraint toward the final anchor:



- `H1` = close `SLICE-NA-001`
- `H2` = resolve the deferred architecture queue
- `H3` = make `M5` a live governed regime rather than a collection of local
  good decisions

Meaning:
- `H1` is mandatory because no subject-structure claim is credible if
  non-authoritative restart state can re-enter runtime truth as if it were
  restart-safe authority
- `H2` is mandatory because subject claims cannot rest on unresolved bootstrap,
  commit / restore, fallback, or control-plane ambiguity
- `H3` is mandatory because the final anchor must become a governed regime, not
  a bundle of local good decisions
- semantic-core deepening is a real later requirement, but it must not be used
  to outrun unresolved state / authority / restart discipline

Activation rule:
- `M6` must remain inactive until `H1`, `H2`, and `H3` are materially satisfied

### Program gates


- no authoritative ablation run counts as proof until fixture qualification
  passes
- no synthetic path may expand beyond its declared bounded bundle without
  triggering disguised-snapshot review
- no projection/operator-visible field may be treated as internal authority
  without a separate claim and proof
- no heuristic subsystem may be upgraded to authority by prose alone
- no Datalog-to-Dream channel may bypass governed semantic mutation acceptance
- no live second semantic ruler may be introduced under the name of “shadow” or
  “intuition” without explicit architecture decision
- negative evidence must be treated as an authority-compression tool, not as a
  failed proof program
- semantic ablation and wire-contract ablation must be kept distinct when the
  target field is required on decode or represented by a richer canonical empty
  value than `null` / missing

### Post-SLICE-011 evidence/front sequence

SLICE-011 (slow-suite infra/harness triage) is complete. The slow gate ran
all 135 cases to a clean final summary; every remaining non-passing case is a
persistence-behavior failure and was intentionally deferred to SLICE-013.
`GRID-COD-GAP-001` is closed. The live checkout is no longer owned by the
SLICE-009/011 HTTP-runtime work-in-progress.

Ordering:
1. SLICE-013 (persistence behavior hardening) is the active front. It targets
   the 11 deferred persistence failures: runtime 17, 25, 45, 50, 51;
   statePersistence 0, 3, 4, 8, 11; httpRuntime 7.
2. If a documentation-only fix is needed before SLICE-013 pauses, use an
   isolated worktree from `origin/main`; do not touch the live checkout.
3. Close the Datalog role-doc gap (`DATALOG-ROLE-001`) before expanding any
   Datalog claim: architecture rules `[23]`/`[25]` already enforce
   "shadow-validator only" and reference `docs/closure/DATALOG_ROLE.md`.
4. Only after SLICE-013 closes may a later front propose imports, fixture
   extraction, or replay/corpus use from the classified Grid_cod artifacts.

Fronts (full deliverables tracked internally, not in the public spine;
`DATALOG-*` are front families alongside `SLICE-XX-NNN`):
- **`SLICE-013`** — persistence behavior hardening. Targeted fixes for the
  11 deferred persistence failures, then a full `qxfx0-test-slow` re-run.
- **`DATALOG-ROLE-001`** — author the missing `docs/closure/DATALOG_ROLE.md`
  declaring Datalog as a bounded shadow-validator (not rerouter/authority).
  It cites architecture rules `[23]`/`[25]` and `semantic_rules.dl` as superseded design.

## Near Term

1. Map the current runtime into explicit experiment zones:
   - routing and decision policy
   - self layer and salience control
   - semantic decomposition and sense planning
   - render surfaces and recovery behavior
   - persistence and governance trace model
2. Identify modules safe for aggressive refactor versus modules that should stay stable as control surfaces.
3. Create a baseline-vs-fork evaluation routine using the existing CLI, test suites, and reports structure.
4. Decide whether the first experimental branch will target:
   - alternative routing logic
   - altered recovery semantics
   - more dynamic self-model behavior
   - different render/planning coupling
5. Add fork-local documentation for each accepted experiment.

## Mid Term

1. Isolate large modules that currently slow down experimental iteration.
2. Introduce clearer seams around `Core`, `Self`, and `Semantic` for controlled substitution.
3. Create experiment toggles or profiles so alternative behavior can coexist with the control implementation.
4. Extend test coverage around the areas chosen for divergence.
5. Build comparison fixtures that make behavioral drift measurable rather than anecdotal.

## Long Term

1. Decide whether `QxFx0_v3` remains a research sandbox or becomes a separately named product line.
2. If divergence becomes structural, rename package/module surfaces in a controlled migration instead of ad hoc edits.
3. Define fork-specific release criteria distinct from the baseline `PROD_GO` contour.
4. Establish a dedicated architecture doctrine if the fork leaves the original theory and ADR line.
5. Curate a durable archive of experiments, verdicts, and rejected directions.

## First Recommended Experiments

1. Rework the turn-routing decision surface without changing persistence contracts.
2. Prototype alternative salience or conatus weighting in the `Self` layer.
3. Compare stricter vs broader semantic decomposition before render planning.
4. Measure how much of the current recovery strategy can be made simpler while preserving explicit failure semantics.

## Notes

- Package identifiers are intentionally unchanged for now.
- This project is a git repository (`main`, tracked on `origin`); an earlier note claiming the absence of `.git` was deliberate is no longer true.
- A future separate repository, if ever needed, would be a controlled migration; the earlier "initialize git inside `QxFx0_v3`" plan is obsolete.

## Infrastructure Hardening Program (Post-Audit 2026-06-08)

This program does not replace or interrupt the M0–M6 spine. It runs alongside the companion programs (SG0–SG4, AS0–AS4), motivated by the comprehensive audit of the library module tree (383 modules). Organized by implementation dependency, not priority number.

### Gate: Tree Cleanup
- Remove 4 dead modules from cabal: `QxFx0.Internal.Process`, `QxFx0.Evaluation.ModelComparison`, `QxFx0.Bridge.SQLite.SchemaContractCheck`, `QxFx0.Bridge.SQLite.SchemaConsistency`.
- Remove `Semantic/Proposition.hs.backup` (compiled as source).
- Effort: <1h. Blocks nothing but unclutters every subsequent step.

### IH‑1: CI Foundation
- `cabal build lib` (fast, 5min)
- `cabal test qxfx0-test-fast` (medium, 10min)
- `hlint + ormolu` (fast, 3min)
- GF build gate: `pgf -make QxFx0SyntaxRusColloquial.gf` + `scripts/gf_quality_gate.sh`
- Effort: 3–5 days. Blocks IH‑2, IH‑3, IH‑4, IH‑5 — every regression is currently detected manually.

### IH‑2: Layering Inversion Fix
- `Semantic` (layer 6) must not import `Core.*Admission` (layer 3). Extract admission interface to `Types.Admission` or `Bridge.Admission`.
- Effort: 1–2 weeks. Depends on IH‑1 (CI must verify the move doesn't break anything).

### IH‑3: Data Integrity Belt
- Serialisation round-trip tests: `decode . encode == id` for all persisted types (`TurnReplayTrace`, `SystemState`, `LocalRecoveryCause`, etc.).
- `--strict-decode` CLI flag: replaces `.:? .!=` with `.:` for production deployments, restoring strict validation while keeping forward-compatible replay in dev.
- Effort: 1 week total (round-trip: 3d, flag: 2d). Depends on IH‑1.

### IH‑4: Memory Footprint
- Lazy-load `resources/morphology/forms_by_surface.json` (131 MB, 73% of morphology footprint) using the existing `unsafePerformIO` + `IORef` pattern (`gfMapData` / `cachedReadPGF`).
- Effort: 1 day. Depends on IH‑1.

### IH‑5: Error Provenance
- Structured errors for remaining 5 `*Error Text` / `*ErrorStructured` half-migrated pairs.
- `--debug-errors` / `QXFX0_DEBUG_ERRORS` env flag (exists as P1-2, needs promotion to documented debugging tool).
- Effort: 1 week. Depends on IH‑1.

### Parallel Line: Typed Consolidation
Independent of IH‑2 through IH‑5, can start anytime:

- **Admission types → GADT/generics-sop**: 83 admission types → 4–5 patterns. Effort: 2–3 weeks.
- **String dispatch → typed enums**: 30+ raw string dispatch sites (`== "SelfStateQ"`, `lang == "QxFx0SyntaxRus"`). Effort: 1–2 weeks.
- **Haddock**: `Self/` and `Core/` modules. Effort: 1–2 weeks.
- **Prometheus + structured logging**: Effort: 2–3 weeks.
- **Semantic substrate roadmap**: naive parser roadmap (document, not rewrite). Effort: 1–2 months.

### IH‑X: Deferred Queue (not blocking)
- Agda nightly CI (3–5 days).
- Nix simplification (1 week).
- Python pipeline fixation (3–5 days).
- Generated lexicon → binary format (2–3 weeks).

### Sequencing rule
- IH‑1 first — no other step can be verified without CI.
- IH‑2, IH‑3, IH‑5 depend on IH‑1 but are independent of each other (parallel after IH‑1).
- IH‑4 (lazy loading) is low-risk, can be parallel.
- Parallel line never blocks IH‑1–IH‑5; IH‑1 never blocks parallel line.
- GF build gate (`pgf -make`) is part of IH‑1 but is load‑bearing specifically for RGL promotion — surface‑generation regressions are user‑visible.
