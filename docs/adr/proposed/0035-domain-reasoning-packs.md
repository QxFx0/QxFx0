# ADR-0035 (proposed): Domain-Specific Reasoning Packs

- **Status**: Proposed (triage stub, not yet a full ADR)
- **Date**: 2026-05-19
- **Refines**:
  - [ADR-0012 — Essence Commitment](../0012-essence-commitment.md)
  - [ADR-0007 — Dual-Mode Conatus](../0007-dual-mode-conatus.md)

## 1. Problem statement

The current `runSemanticLogic` (`src/QxFx0/Semantic/Logic.hs:58-59`) and
`reconcile` (`src/QxFx0/Self/Deliberation.hs:428-440`) operate on a single,
universal domain model: `AtomSet` → `CanonicalMoveFamily`, and the
`Plan` payload (family, style, tone, recovery cause) is drawn from a closed
enumeration (`QxFx0.Types.Domain`).  This is correct for general-purpose
dialogue, but the QxFx0 research programme envisions deployment in
specialised contexts — clinical counselling, legal reasoning, pedagogical
tutoring, scientific hypothesis generation — where domain-specific
knowledge shapes not only the content but the *admissible move structure*.

A "domain pack" would be a module (or package) that contributes:
- Specialised `AtomSet` expansion rules (e.g. medical symptom atoms).
- Domain-specific `CanonicalMoveFamily` variants or sub-families.
- Custom `ConatusWeights` that reflect what self-preservation means in
  that domain (a clinical system may weight `cwIdentity` higher because
  ethical consistency is structurally load-bearing).
- Uncertainty boundaries that inform `validatePlan`
  (`src/QxFx0/Self/Essence.hs:507-508`) when a pack-specific move is
  proposed under an `EssenceCommitment`.

There is currently no architectural place for such packs.  Adding them
ad-hoc would violate the closed-world assumptions of `reconcile`,
`validatePlan`, and the trace schema (`TurnReplayTrace`).

## 2. Current architecture (what would change)

- `src/QxFx0/Semantic/Logic.hs:58` — `runSemanticLogic` is a pure
  function `AtomSet -> [RankedFamily]`.  A domain pack would need to
  inject additional logic between atom collection and family ranking,
  or extend `AtomTag` with domain-specific constructors.
- `src/QxFx0/Self/Deliberation.hs:178-184` — `Plan` is a closed record
  with `CanonicalMoveFamily` from `QxFx0.Types.Domain`.  Domain packs
  might need new family constructors (e.g. `CMClinicalAssess`,
  `CMPedagogicalScaffold`) or might map domain-specific tags onto the
  existing holistic/formal family sets via a pack-specific
  `DomainAdapter`.
- `src/QxFx0/Self/Essence.hs:507-508` — `validatePlan` checks the
  reconciled `Plan` against `admissibleFamilies` for the committed
  `EssenceMode`.  A domain pack might widen or narrow the admissible
  set: e.g. a `EssenceContemplative` clinical pack might admit
  `CMClinicalAssess` where the generic system would not.
- `src/QxFx0/Self/Conatus.hs:102-111` — `ConatusWeights` are global
  constants.  A domain pack would need either:
  - a per-pack weight override loaded at bootstrap, or
  - a `ConatusWeights -> ConatusWeights` pack morphism applied after
    the base computation.
- `src/QxFx0/Core/TurnPipeline/Effects.hs:52-71` — `TurnEffectRequest`
  enumerates 18 effect constructors.  Domain packs may need new
  constructors (e.g. `TurnReqDomainPackConsult !PackId !Text`) or may
  piggyback on `TurnReqEmbedding` with domain-tuned embedding models.
- `src/QxFx0/Core/TurnPipeline/Prepare/Build.hs` — the prepare stage
  currently builds a single `SemanticInput` and `PrepareEffectPlan`.  A
  pack-aware prepare stage might consult the pack before selecting the
  embedding model or before running `runSemanticLogic`.

## 3. Open design questions

1. What is the contract between the core runtime and a domain pack?
   Does the pack expose a record of typed functions (compile-time
   dependency), a dynamic dispatch table (runtime plugin), or a
   declarative config file (data-driven)?
2. How does a pack express its uncertainty boundaries to `validatePlan`
   and safety guards?  Is it a whitelist of admissible `Plan` fields, a
   blacklisted set, or a probabilistic confidence threshold that
   overrides `planConfidence`?
3. Are packs hot-pluggable (loaded at runtime without recompilation) or
   compile-time Haskell modules?  Hot-pluggability requires a stable
   plugin ABI and versioning discipline; compile-time packs are simpler
   but require rebuilding the runtime for every domain.
4. How does pack composition interact with `Essence` commitment?  If
   a session commits to `EssenceContemplative` under the generic pack
   and later a clinical pack is activated, does the commitment remain
   valid, or does the pack switch constitute an `EssenceRupture`?
5. What is the calibration story for pack-specific `ConatusWeights`?
   Each domain may need its own long-session corpus and its own
   `EssenceModulation` / `ConatusWeights` defaults.  Does the runtime
   maintain one modulation per pack, or one global modulation with
   pack-specific delta adjustments?
6. Should domain packs be allowed to introduce new `CommitmentTrigger`
   constructors (e.g. `TriggerClinicalRiskThreshold`), or must they map
   their domain events onto the two existing triggers
   (`TriggerAngstThreshold`, `TriggerConatusErosion`)?
7. How does the trace schema (`TurnReplayTrace`) accommodate
   pack-specific fields without breaking the JSON schema contract?
   Are pack fields namespaced (e.g. `trcPackClinical_riskScore`), or
   is there a single `trcPackMetadata :: Maybe Object` blob?
8. What is the fallback when a pack is unavailable at runtime (e.g.
   model file missing, licence expired)?  Does the runtime degrade to
   the generic pack, or does it raise a new `PackUnavailable`
   exception variant?

## 4. Estimated complexity

**XL** — domain packs touch every layer of the architecture:
semantic (atom logic), deliberation (plan space), essence (validation
and commitment), conatus (self-preservation weights), effects (new
request types), and persistence (trace schema).  Each pack requires its
own labelled corpus, calibration protocol, and safety review process.
The implementation is not engineering-feasible to spec without:
- at least one concrete domain partner (e.g. clinical, legal, or
  educational) providing annotated data,
- a published pack ABI/versioning contract,
- an explicit safety review process for pack-admissible `Plan` moves,
- and a separate calibration corpus per pack (minimum 100 sessions).

Estimated 3–6 months for the first pack, with significant ongoing
maintenance as the core runtime evolves.

## 5. Why this is not in scope yet

Phase 11+ — requires domain-expert collaboration, labelled corpus per
domain, and explicit safety review process; not engineering-feasible to
spec without those prerequisites.  The current generic architecture
(`CanonicalMoveFamily`, `defaultConatusWeights`, `defaultEssenceModulation`)
is a deliberately closed world that admits finite test coverage and
deterministic replay.  Opening it to domain packs before the core
commitment and conatus dynamics are production-validated would
multiply the calibration surface beyond what the current telemetry
and regression suite can track.

— end of proposed ADR-0035 —
