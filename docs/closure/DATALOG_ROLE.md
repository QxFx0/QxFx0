# Datalog Role

**Status:** authoritative role declaration
**Front:** `DATALOG-ROLE-001` (see `ROADMAP.md` §"Post-SLICE-009 evidence/front sequence")
**Enforced by:** `scripts/check_architecture.sh` rules `[23]` and `[25]`
**Program:** closes the `M2` requirement that Datalog hold one declared role

## Declared role

Datalog in QxFx0 is a **bounded shadow-validator / divergence witness**. It is
**not** a live rerouter and **not** an authority source.

Datalog (`src/QxFx0/Bridge/Datalog/`: `Runtime.hs`, `Compare.hs`, `Support.hs`,
`Types.hs`) **may**:

- run as an offline / shadow check that derives its own view and compares it
  against the live pipeline's decisions,
- record divergence as evidence that governed, downstream paths may consume.

Datalog **may not**:

- select or override the current-turn move family or illocutionary force,
- write or gate persistence / commitment authority,
- import routing or finalization code (see Enforcement).

This gives Datalog exactly one declared architectural role — closing the `M2`
requirement that it not "remain half-written as validator in code and rerouter in
prose."

## Enforcement (machine-checked)

Two architecture rules in `scripts/check_architecture.sh` enforce this role, and
both name this document in their violation message:

- **Rule `[23]`** (`scripts/check_architecture.sh:716`) — modules under
  `src/QxFx0/Bridge/Datalog/` must not import state-writing orchestrators
  (`Core.TurnPipeline.Finalize`, `Core.TurnPipeline.Effects`,
  `Bridge.StatePersistence`, `Runtime.Session.Bootstrap`).
- **Rule `[25]`** (`scripts/check_architecture.sh:733`) — modules under
  `src/QxFx0/Bridge/Datalog/` must not import any `Core.TurnPipeline.*`
  routing / finalization module.

A Datalog module that imports the live decision or persistence path fails the
architecture gate. The role is therefore checked, not merely asserted in prose.

## Superseded design (historical reference, not authority)

An earlier version — `Grid_cod/QxFx0_q/semantic_rules.dl`, a 266-line Soufflé
specification — modelled Datalog as a **live rerouter**: it assigned priority
over the planner and parser ("policy > scene > planner > parser > modality
inference"), adjusted the active scene, and filtered policy directly into move
families (e.g. blocked → `CMClarify`).

That design is **explicitly rejected** for QxFx0. The `.dl` spec is retained only
as a historical / superseded reference for the `GRID-COD-GAP-001` gap matrix. It
must **not** be treated as a target the current code should match, and none of
its rules confers runtime authority.

## Permitted future participation (bounded)

Datalog may feed **bounded offline correction pressure**, never live decisions:

- a typed `DatalogPressure` derived from persisted shadow / divergence results
  (`M4.5`), reconciled with `IntuitionPressure` into a `DreamPressure` channel,
- such pressure may bias offline Dream evidence / meaning-graph reweighting under
  hard clamps,
- it may **not** override current-turn family selection, and may **not** become a
  hidden second semantic ruler under the name "shadow" or "intuition" without an
  explicit architecture decision.

See `ROADMAP.md` §`M4.5` and `src/QxFx0/Core/TopicDrift/Pressure.hs`
(`deriveDatalogPressure`, `buildDreamOutcome`).

## Non-goals

- no Datalog module imports `Core.TurnPipeline.*` routing / finalization code
- no Datalog result becomes current-turn truth by prose or hidden plumbing
- no Datalog path writes commitment or persistence authority
- the `semantic_rules.dl` rerouter design is not restored as runtime authority
