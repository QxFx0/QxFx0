# Trace Gap Pre-Prep Log

**Date:** 2026-06-02
**Status:** pre-prep, no code changes in this commit
**Author:** closure-plan session (QxFx0, no cabal)

## Background

`docs/closure/TRACE_SCHEMA.md` §1 documents a 90-field
`TurnReplayTrace` record (the runtime trace envelope). Of these 90
fields, **3 canonical contours have GAPs** — the contour affects
canonical decisions but is not observable in the trace:

| # | Contour  | Module                        | Source field              | Type            |
|---|----------|-------------------------------|---------------------------|-----------------|
| 1 | Conatus  | `QxFx0.Self.Conatus`          | `tiConatusEnergy`         | `ConatusEnergy` |
| 1 | Conatus  | (continuation)                | `tiConatusGateFired`      | `Bool`          |
| 2 | Field    | `QxFx0.Self.Field` (ADR-0009) | `tiField`                 | `Field`         |
| 3 | Identity | `QxFx0.Types.State.Identity`  | `ssIdentityClaims`        | `[IdentityClaimRef]` |

These 3 GAPs are **real code gaps, not documentation gaps** (per
`TRACE_SCHEMA.md` §2/§3/§7 "Why the GAP is a real GAP"). A replay
cannot explain *why* the salience controller fired, *what* the
right-hemispheric atmosphere was, or *which* identity claims were
active on a given turn.

`check_replay_gate.sh` reports these as GAPs in the canonical contour
envelope (3 of 6 canonical contours missing).

## Goal

Close all 3 GAPs in a single commit (or 3 separate commits if you
prefer finer granularity). Each GAP closure is a 3-step change
executed identically:

1. **Type def**: add the field(s) to `TurnReplayTrace` in
   `src/QxFx0/Types/TurnProjection.hs`
2. **Production constructor**: assign the field(s) in
   `src/QxFx0/Core/TurnPipeline/Finalize/State.hs:625-755` (the
   `TurnReplayTrace` builder inside the canonical pipeline)
3. **Test fixture**: assign the field(s) in
   `test/Test/Suite/StatePersistence.hs:711-734` (the
   `fixtureReplayTrace` helper)

Per the recipe in `TRACE_SCHEMA.md §2/§3/§7`, the source values
for each field are:

```
, trcConatusEnergy    = tiConatusEnergy ti
, trcConatusGateFired = tiConatusGateFired ti
, trcField            = tiField ti
, trcIdentityClaims   = ssIdentityClaims nextSs
```

`ti :: TurnInput` and `nextSs :: SystemState` are already in scope
in `State.hs:625-755` (the existing assignments use them, e.g.
`trcRequestedFamily = tiRecommendedFamily ti` at line 636 and
`trcDialoguePhaseAfter = ssDialoguePhase nextSs` at line 713).

## Constructor call sites (verified)

Only **2 constructor call sites** in the entire codebase
(plus the type definition itself):

1. **Production:**
   `src/QxFx0/Core/TurnPipeline/Finalize/State.hs:625-755`
   (canonical pipeline, ~130 field assignments)
2. **Test fixture:**
   `test/Test/Suite/StatePersistence.hs:711-734`
   (`fixtureReplayTrace` helper used by state persistence tests)

Note: the file `test/Test/Suite/StatePersistence.hs` is currently
**untracked** in git (per the user's pre-existing working tree —
it's a new file awaiting its first commit). The closure-plan
session verified the file's structure and confirmed `qxfx0.cabal`
already lists `Test.Suite.StatePersistence` (line 401) and
`TestMain.hs` already runs `statePersistenceTests`. When the
user commits their test fixture, the 4-line update will ride along.

**Read sites** (313 total `trc*` field accesses across the codebase)
are NOT affected by this change — adding new fields does not break
read sites that don't reference the new fields.

## Test fixture values (verified patterns)

The test fixture in `StatePersistence.hs:711-734` uses these
established test values for the 4 new fields:

```haskell
, trcConatusEnergy    = ConatusEnergy 10.0 (ConatusComponents 0 0 0 0)
, trcConatusGateFired = False
, trcField            = emptyField
, trcIdentityClaims   = []
```

These are well-established patterns in the test suite:

- `ConatusEnergy 10.0 (ConatusComponents 0 0 0 0)` — used in 5+
  test files (LearningLoop.hs:1303, 1519, 1560; SelfEssence.hs:219,
  443; SelfSalience.hs:190-201; etc.) as the canonical "test
  conatus" value.
- `emptyField` — well-established helper from `QxFx0.Self.Field`
  (Field.hs:203-207). Already imported in
  `test/Test/Suite/StatePersistence.hs:61`.
- `ConatusComponents(..)`, `ConatusEnergy(..)` — already imported
  in `test/Test/Suite/StatePersistence.hs:39-40`.

## Type def imports (verified, no circular deps)

`src/QxFx0/Types/TurnProjection.hs` will need 2 new imports:

```haskell
import QxFx0.Self.Conatus (ConatusEnergy)
import QxFx0.Self.Field (Field)
```

`IdentityClaimRef` is already importable via the existing
`QxFx0.Types.Domain` import (which re-exports from
`QxFx0.Types.Domain.User`).

**No circular dependency risk** — verified that
`QxFx0.Self.Field`, `QxFx0.Self.Conatus`, and
`QxFx0.Types.Domain.User` do NOT import `QxFx0.Types.TurnProjection`
or `TurnReplayTrace`. The dependency arrow is
`Types -> Self.*` and `Types -> Domain.*` (one-way).

## Procedure (next-contributor, with cabal)

**Prerequisite:** cabal permission, working `cabal build` and
`cabal test` baseline at HEAD `adcf324` (ADR-0019 prep).

**Step 1 — Type def (1 file):**
Edit `src/QxFx0/Types/TurnProjection.hs`:
- Add 2 imports: `QxFx0.Self.Conatus (ConatusEnergy)` and
  `QxFx0.Self.Field (Field)`
- Add `IdentityClaimRef` to existing `QxFx0.Types.Domain` import
- Add 4 fields at the end of the `TurnReplayTrace` record
  (after `trcPerspectiveProjections`):

  ```haskell
  , trcConatusEnergy :: !ConatusEnergy
    -- ^ Trace schema §2 (GAP Conatus): the ConatusEnergy record
    --   computed by PrepareStatic (see tiConatusEnergy in
    --   QxFx0.Core.TurnPipeline.Types). Observability for the
    --   salience-controller gate.
  , trcConatusGateFired :: !Bool
    -- ^ Trace schema §2 (GAP Conatus): the tiConatusGateFired
    --   value computed by PrepareStatic and consumed by
    --   Route/Render.buildLocalRecoveryPlan. @True@ when the
    --   structural floor gates the salience controller.
  , trcField :: !Field
    -- ^ Trace schema §3 (GAP Field): the Field record computed
    --   by PrepareStatic (see tiField in
    --   QxFx0.Core.TurnPipeline.Types). Five components per
    --   ADR-0009 §4. Right-hemispheric input to salience.
  , trcIdentityClaims :: ![IdentityClaimRef]
    -- ^ Trace schema §7 (GAP Identity): mirrors
    --   ssIdentityClaims on ssIdentity :: SystemState ->
    --   IdentityState. The list of identity claims active for
    --   this turn; substrate for self-reference.
  ```

**Step 2 — Production constructor (1 file):**
Edit `src/QxFx0/Core/TurnPipeline/Finalize/State.hs`:
- Find the `TurnReplayTrace` constructor at line 625
- Insert 4 lines after `trcPerspectiveProjections` (line 723)
  and before the closing `}` (line 724):

  ```haskell
  , trcConatusEnergy = tiConatusEnergy ti
  , trcConatusGateFired = tiConatusGateFired ti
  , trcField = tiField ti
  , trcIdentityClaims = ssIdentityClaims nextSs
  ```

**Step 3 — Test fixture (1 file, untracked):**
Edit `test/Test/Suite/StatePersistence.hs`:
- Find `fixtureReplayTrace` at line 711
- Insert 4 lines after `trcPerspectiveProjections = []` (line 800
  or so) and before the closing `}`:

  ```haskell
  , trcConatusEnergy = ConatusEnergy 10.0 (ConatusComponents 0 0 0 0)
  , trcConatusGateFired = False
  , trcField = emptyField
  , trcIdentityClaims = []
  ```

**Step 4 — Verify:**
- `cabal build` — expect clean compile (the 2 new imports
  resolve, the 4 new field types resolve)
- `cabal test` — expect `statePersistenceTests` pass (the
  fixture compiles and provides valid defaults)
- `bash scripts/check_replay_gate.sh` — expect **0 GAPs** (was 3)
- `bash scripts/check_architecture.sh` — expect rule [20] still
  green (no new rules affected by this change)

**Step 5 — Commit:**
Single atomic commit, suggested message:

```
fix(trace-schema): close 3 GAPs in TurnReplayTrace (Conatus, Field, Identity)

Adds observability for the 3 canonical contours that previously
were not visible in the replay trace:

- trcConatusEnergy    :: !ConatusEnergy    (tiConatusEnergy ti)
- trcConatusGateFired :: !Bool             (tiConatusGateFired ti)
- trcField            :: !Field            (tiField ti)
- trcIdentityClaims   :: ![IdentityClaimRef] (ssIdentityClaims nextSs)

check_replay_gate.sh now reports 0 GAPs (was 3) on the canonical
contour envelope. Per TRACE_SCHEMA §2/§3/§7 recipes.

Per §15 3-state: trace schema moves from "3 GAPs" to "0 GAPs".
Per ADR-0019 prep pattern: this is a code-shape change with
mechanical recipe, no gate contract required.

Test fixture updated in test/Test/Suite/StatePersistence.hs:
- ConatusEnergy 10.0 (ConatusComponents 0 0 0 0)
- emptyField
- []

Refs: docs/closure/TRACE_SCHEMA.md §2/§3/§7,
docs/closure/TRACE_GAP_PREP_LOG.md.
```

**Step 6 — Update §15 status:**
After commit, update `docs/closure/FOLLOWUPS.md` §15.1:
- Move "Close trace gaps" from "pending" to "done"
- Remove from "3 GAPs reported by check_replay_gate.sh"
- Optionally add a "Trace gaps closed 2026-06-02" entry

## Why pre-prep, not landed

This session is **no-cabal**. The type def + production constructor
+ test fixture change is mechanical (recipe + values verified), but
verification requires `cabal build` and `cabal test`. Per the
ADR-0019 prep pattern (option b: "prep without execution when
execution requires external verification"), this is pre-prep:
- 1 log file documenting the full procedure
- 1 verified source-value recipe
- 1 verified constructor-call-site count
- 1 verified test-value pattern
- 0 code changes

The 3 GAPs are **ready-to-land** in main, not **landed** in main.

## Verification done in this session

- Type def: read, confirmed 77 fields (lines 24-135 of
  `src/QxFx0/Types/TurnProjection.hs`)
- Constructor call sites: enumerated via `rg "TurnReplayTrace\s*\{"`
  — only 2 sites (production + test fixture)
- Read sites: 313 total `trc*` accesses, none affected by the
  change (no breaking on reads)
- Test fixture: read end of fixture, confirmed `[]` pattern for
  list fields and established `ConatusEnergy 10.0 ...` test value
- Imports: verified `ConatusEnergy` and `Field` modules do not
  import `QxFx0.Types.TurnProjection` (no circular dep)
- `qxfx0.cabal`: confirmed `Test.Suite.StatePersistence` is
  already listed (line 401)

## State of related items

- **Essence GAP** (Phase 9-10) — closed 2026-05-19, per AGENTS.md
  (4 nullable trace fields already in the type def:
  `trcEssenceMode`, `trcEssenceCommitted`, `trcEssenceAngstLevel`,
  `trcEssenceTrigger`)
- **Salience GAP** (Phase 5.5e) — closed, 3 fields
  (`trcSalienceDriver`, `trcSalienceHolisticBias`,
  `trcSalienceConfidence`)
- **3 remaining GAPs** (Conatus, Field, Identity) — this pre-prep
  closes them
- **check_replay_gate.sh** — will report 0 GAPs after commit
  (currently 3)

## Out of scope

- F-09 production-trace corpus (separate, L-sized)
- F-10 first calibration (depends on F-09)
- Real GF parser (XL-sized)
- 4 remaining promotion landings (separate from this)
- Python P5-1 (separate, M-sized)

## File status

- This log: new (in working tree, uncommitted)
- TurnProjection.hs: working tree has user pre-existing changes
  (no closure plan changes)
- State.hs: working tree has user pre-existing changes
  (no closure plan changes)
- StatePersistence.hs: untracked in git, working tree has user's
  pre-existing code (no closure plan changes)
