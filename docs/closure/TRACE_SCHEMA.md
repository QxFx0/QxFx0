# Trace Schema Reference

**Status:** drafted 2026-06-02 (post-§11 follow-up pass)
**Module:** `QxFx0.Types.TurnProjection.TurnReplayTrace`
**Enforced by:** `scripts/check_replay_gate.sh` (static),
                 `test/Test/Suite/ReplayGate.hs` (dynamic)
**Total `trc*` fields:** 90 (as of Phase 5.5e + Phase 8 + Phase 9-10)

This document is the **single source of truth** for what
each `trc*` field in `TurnReplayTrace` means, where it
comes from, and which contour it belongs to.

It is the schema reference that
`scripts/check_replay_gate.sh` checks against
(P4 property: "every canonical contour has a named
`trc*` field in `TurnReplayTrace`"). The script's
GAPs point at the §N sections of this document.

It is also the schema reference that
`test/Test/Suite/TraceSchema.hs` (planned, see
FOLLOWUPS.md §12.5) locks to the actual code: a
discrepancy between this document and the field list
of `src/QxFx0/Types/TurnProjection.hs` is a bug in
either the code or the doc.

---

## 1. The 6 canonical contours

A **canonical contour** is a unit of the
`QxFx0.Self.*` runtime that participates in
replay/P1-P4 discipline. Six contours are currently
canonical. The discipline says: **every canonical
contour must have at least one `trc*` field in
`TurnReplayTrace`.** Three of the six contours do
not yet have their fields landed; these are the
3 GAPs reported by `check_replay_gate.sh`.

| # | Contour | trc\* fields | Status | § |
|---|---------|--------------|--------|---|
| 1 | **Conatus** | (none) | GAP | §2 |
| 2 | **Field** | (none) | GAP | §3 |
| 3 | **Salience** | 3 | OK (Phase 5.5e) | §4 |
| 4 | **Deliberation** | 4 | OK (Phase 8 Package B) | §5 |
| 5 | **Essence** | 4 | OK (Phase 9-10, 2026-05-19) | §6 |
| 6 | **Identity** | (none) | GAP | §7 |

The P4 check in `check_replay_gate.sh` reports:

- **OK Salience, Deliberation, Essence** (5 fields)
- **GAP Conatus, Field, Identity** (0 fields)

`Essence` was added to the canonical contour list
on 2026-05-19 with the Phase 9-10 landing. It is
the most recent addition.

The script's `EXPECTED_MISSING` table (see
`scripts/check_replay_gate.sh §1`) names the 3
GAPs. Closing a GAP is **Package 3 work** per
`docs/closure/REPLAY_GATE_TRIAGE.md §3`.

---

## 2. Conatus (GAP)

**Module:** `QxFx0.Self.Conatus` (Phase 1-2)
**Compute sites:** `QxFx0.Core.TurnPipeline.Prepare.Build`
  (computes `tiConatusEnergy` and `tiConatusGateFired`)
**Codomain:** `[~5, ~20+]` in production
  (per ADR-0012 §15.1)
**Calibration:** `emConatusStructuralFloor` 0.5 → 7.0

### Expected fields (not yet landed)

The two values that `PrepareStatic` already computes
for the rest of the pipeline are:

```
trcConatusEnergy    :: !ConatusEnergy
trcConatusGateFired :: !Bool
```

- `trcConatusEnergy` — the `ConatusEnergy` record
  with `ceScalar :: !Double` and
  `ceComponents :: !ConatusComponents`. Both
  fields are `Show`-deriving.
- `trcConatusGateFired` — `True` when the structural
  floor gates the salience controller (the
  `tiConatusGateFired` value the `Route/Render.buildLocalRecoveryPlan`
  reads).

### Source values

In `QxFx0.Core.TurnPipeline.Finalize.Projection`
(line 75 takes `ti :: TurnInput`):

```
, trcConatusEnergy    = tiConatusEnergy ti
, trcConatusGateFired = tiConatusGateFired ti
```

### Why the GAP is a real GAP

The discipline of P1-P4 says: a contour that affects
the canonical decision must be visible in the
replay trace. Conatus affects the salience
controller (the gate), which affects routing, which
is the canonical decision. Without a `trc*` field,
a replay cannot explain *why* salience fired or
didn't fire on this turn. This is a real
observability hole.

### What closes the GAP

Add the two fields to `TurnReplayTrace` and the
two lines to the constructor in
`Projection.hs:142-199`. Also update the two test
call sites in
`test/Test/Suite/RuntimeInfrastructure.hs:1500,1978`.

**Effort:** S (one source change in two files).

---

## 3. Field (GAP)

**Module:** `QxFx0.Self.Field` (Phase 4, ADR-0009)
**Compute sites:** `QxFx0.Core.TurnPipeline.Prepare.Build`
  (computes `tiField` from `FieldHeuristics`)
**Type:** record with 5 components (see ADR-0009 §4)

### Expected field (not yet landed)

The `Field` record is a single value (not a list
or option). A single `trc*` field suffices:

```
trcField :: !Field
```

- `trcField` — the `Field` record
  (`fieldResonance`, `fieldAtmosphere`,
  `fieldConfidence`, `fieldConsolidation`,
  `fieldCounterfactual`).

### Source value

```
, trcField = tiField ti
```

### Why the GAP is a real GAP

Field is the right-hemispheric input to salience
(see Phase 5 / Phase 5.5d). Without a `trc*`
field, a replay cannot explain the salience
controller's *atmosphere* and *consolidation*
inputs. This is the same observability hole as
Conatus.

### What closes the GAP

Add `trcField` to `TurnReplayTrace` and one line
to the constructor in
`Projection.hs:142-199`. Also update the two test
call sites.

**Effort:** S.

---

## 4. Salience (OK)

**Module:** `QxFx0.Self.Salience` (Phase 5,
  ADR-0010)
**Compute sites:** `turnInputSalience` in
  `Projection.hs:60-61` (extracts
  `svSalience . tiSelfVerdict`)
**Phase:** 5.5e

### Landed fields

```
trcSalienceDriver       :: !Text     -- closed enum tag
trcSalienceHolisticBias :: !Double   -- in [0, 1]
trcSalienceConfidence   :: !Double   -- in [0, 1]
```

- `trcSalienceDriver` — rendered snake_case tag
  for the dominant `SalienceDriver` on this turn.
  Closed enum; stable across builds.
- `trcSalienceHolisticBias` — `salienceHolisticBias`
  in `[0, 1]`. `0` = pure formal, `1` = pure
  holistic, `0.5` = neutral.
- `trcSalienceConfidence` — `salienceConfidence`
  in `[0, 1]`. `1` = one driver dominates,
  `0` = contributions cancel.

### Source values

```
, trcSalienceDriver       = renderSalienceDriver (salienceDriver traceSalience)
, trcSalienceHolisticBias = salienceHolisticBias traceSalience
, trcSalienceConfidence   = salienceConfidence traceSalience
```

(see `Projection.hs:189-191`)

### P1-P4 status

- P1 (serializable): OK
- P2 (compute pure): OK
- P3 (snapshot type): OK
- P4 (trc\* field): OK (this section)

---

## 5. Deliberation (OK)

**Module:** `QxFx0.Self.Deliberation` (Phase 8,
  ADR-0011)
**Phase:** 8 Package B

### Landed fields

```
trcDeliberationRule         :: !(Maybe Text)
trcDeliberationAgreement    :: !(Maybe Text)
trcDeliberationDivergence   :: !(Maybe Double)
trcDeliberationNarrativeTone :: !(Maybe Text)
```

- `trcDeliberationRule` — `Maybe` because
  deliberation may be off-path (the
  `familyDivergenceEnabled = False` flag, see
  `Cascade.hs:74`).
- `trcDeliberationAgreement` — the rendered
  agreement tag.
- `trcDeliberationDivergence` — `dtDivergence` of
  the deliberation trace.
- `trcDeliberationNarrativeTone` — `Maybe`
  because the narrative tone is a per-deliberation
  concern, not a per-turn concern.

### Source values

```
, trcDeliberationRule          = tpDeliberation tp >>= \d -> Just (renderReconcileRule (dtRule (delibTrace d)))
, trcDeliberationAgreement     = tpDeliberation tp >>= \d -> Just (renderAgreement (dtAgreement (delibTrace d)))
, trcDeliberationDivergence    = tpDeliberation tp >>= \d -> Just (dtDivergence (delibTrace d))
, trcDeliberationNarrativeTone = tpDeliberation tp >>= \d -> Just (renderNarrativeTone (planNarrativeTone (delibReconciled d)))
```

(see `Projection.hs:192-195`)

### P1-P4 status

- P1-P4: OK

### Adjacent flag

`familyDivergenceEnabled` (`Cascade.hs:74`) is the
flag for promoting Deliberation to the runtime
path. Currently `False` literal. The first
candidate for promotion per
`docs/closure/PROMOTION_PLAYBOOK.md` is **ADR-0019
(Family Divergence)**.

---

## 6. Essence (OK)

**Module:** `QxFx0.Self.Essence` (Phase 9-10,
  ADR-0014)
**Phase:** landed 2026-05-19
**Flag:** `essenceCommitmentEnabled` (default `False`)

### Landed fields

```
trcEssenceMode       :: !(Maybe Text)
trcEssenceCommitted  :: !(Maybe Bool)
trcEssenceAngstLevel :: !(Maybe Double)
trcEssenceTrigger    :: !(Maybe Text)
```

- `trcEssenceMode` — snake_case
  `renderEssenceMode` tag of the post-turn essence.
  `Just "witnessing"` pre-commit;
  `Just "contemplative" | "dialogical" | "integrative"`
  post-commit (Phase 10). `Nothing` only when the
  essence layer is statically disabled.
- `trcEssenceCommitted` — `Just False` pre-commit,
  `Just True` post-commit (Phase 10). Always
  `Just False` in Phase 9 by contract.
- `trcEssenceAngstLevel` — `etAngstLevel` of the
  post-turn trajectory in `[0, 1]`. Tracks
  accumulated unresolved divergence.
- `trcEssenceTrigger` — snake_case
  `renderCommitmentTrigger` tag set only on the
  turn a commitment fires (Phase 10). Always
  `Nothing` in Phase 9.

### Source values

The 4 fields are local `let`-bindings
(`modeTag`, `committedFlag`, `angst`, `triggerTag`)
computed from `ssEssence nextSs` at
`Projection.hs:125-145`, then bound into the
constructor at `Projection.hs:196-199`.

### P1-P4 status

- P1-P4: OK

---

## 7. Identity (GAP)

**Module:** `QxFx0.Types.State.Identity` (the
  `IdentityState` slice of `SystemState`)
**Source:** `idsIdentityClaims :: ![IdentityClaimRef]`
  on `ssIdentity :: SystemState -> IdentityState`

### Expected field (not yet landed)

```
trcIdentityClaims :: ![IdentityClaimRef]
```

- `trcIdentityClaims` — the list of identity
  claims active for this turn. Mirrors the
  existing `idsIdentityClaims` accessor.

### Source value

```
, trcIdentityClaims = ssIdentityClaims nextSs
```

(or equivalently
`idsIdentityClaims (ssIdentity nextSs)`.)

### Why the GAP is a real GAP

Identity claims are the substrate for self-reference.
Without a `trc*` field, a replay cannot explain
which identity claims were active when the system
responded. This is the third observability hole.

### What closes the GAP

Add `trcIdentityClaims` to `TurnReplayTrace` and
one line to the constructor in
`Projection.hs:142-199`. Also update the two test
call sites.

**Effort:** S.

---

## 8. Other trc\* fields (non-canonical)

The remaining 76 `trc*` fields (90 - 5 - 4 - 0
= 81, accounting for the 3 GAPs) belong to
non-canonical concerns: identity header, runtime
mode, shadow policy, recovery, final decision,
parser, claim/render, truth/authority/surface,
hints, learning, external action, pre-actor,
sense, dialogue, micro-plan, dream pressure,
perspective.

These fields are **not part of the 5 canonical
contours** and are not subject to P4. They are
documented in the source code Haddock and in
`QxFx0.Core.TurnPipeline.Finalize.Projection`
(the constructor site).

This document does not enumerate them. For an
exhaustive list, see
`src/QxFx0/Types/TurnProjection.hs:45-184`.

---

## 9. Discipline: adding a new canonical contour

When a new `QxFx0.Self.*` module becomes canonical
(e.g. when a feature is promoted per
`docs/closure/PROMOTION_PLAYBOOK.md`):

1. **Define** the contour in the Self/* subtree
   (e.g. `QxFx0.Self.Will`).
2. **Compute** its value in
   `QxFx0.Core.TurnPipeline.Prepare.Build` (or
   similar single-source-of-truth location, per
   Phase 6 / M6.1).
3. **Add at least one `trc*` field** to
   `TurnReplayTrace`, with Haddock that names the
   Self/* module, the compute site, and the
   codomain.
4. **Bind** the field in the constructor at
   `Projection.hs:142-199`.
5. **Update this document** — add a §N section.
6. **Update `check_replay_gate.sh`** — add the
   contour and field to `TRC_FIELDS`.
7. **Update the test call sites** — both
   `RuntimeInfrastructure.hs:1500` and `:1978`.
8. **Add a property test** to
   `test/Test/Suite/ReplayGate.hs` if the contour
   has non-trivial snapshot semantics.

A contour that completes steps 1-4 but skips 5-8
is a **regression**: the discipline is broken.

---

## 10. Cross-references

- `docs/closure/REPLAY_GATE_TRIAGE.md §1` — the
  original triage of 13 contours; this document
  is the post-triage schema for the 6 canonical.
- `docs/closure/PROMOTION_PLAYBOOK.md` — when
  a non-canonical contour (e.g. Family Divergence
  in ADR-0019) becomes canonical, steps 1-8 of
  §9 above must be applied.
- `docs/closure/ENFORCEMENT_MATRIX.md §1` — the
  R3 rule (canonical = trc\* discipline) is
  enforced by the P4 check in
  `check_replay_gate.sh`.
- `docs/adr/proposed/0034-self-core-role-split.md`
  — the role-split ADR that defines what
  "canonical" means.
- `audit-round3-final.md §3.1` — the original
  Conatus codomain finding (calibration
  reference).

---

## 11. Honest limits

- This document was authored in a **read-only
  session** (no `cabal build`, no `cabal test`).
  All §N-§N.2 source references were checked
  manually. The exhaustive field list was
  extracted via `rg` on the type definition.
- The 3 GAPs (Conatus, Field, Identity) are
  **real code gaps**, not documentation gaps.
  Closing them requires modifying
  `TurnReplayTrace` (a 90-field record) and
  updating 3 call sites. See §2, §3, §7 for the
  exact changes.
- The discipline of "every canonical contour has
  a `trc*` field" is **P4** of the 4 replay
  properties; see `REPLAY_GATE_TRIAGE.md §2` for
  the formal statement.
- This document does **not** claim that the
  trc\* fields of non-canonical contours (e.g.
  Sense, Dialogue, Dream, Perspective) are
  complete. Those are tracked separately in
  the corresponding Self/* module docs.
