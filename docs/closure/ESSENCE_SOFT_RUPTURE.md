# Essence Soft Rupture (B-slice BD2)

**Status:** landed 2026-08-07 (B-slice)
**Scope:** single canonical collapse branch + replay-visible soft
rupture for the Essence contour.
**Cross-refs:** `CONTOUR_INDEX.md §6` (Essence P4 OK),
`ADR-0012`, `phase-10-essence-commitment-implementation-spec.md`,
`QxFx0.Self.Essence` (`collapseEssence` / `collapseEssenceAt`),
`docs/closure/ESSENCE-REGIME-RECONCILE.md` (Policy A).

---

## 1. The problem: two reset branches

Before the B-slice, the runtime could reset the Essence trajectory
through **two independent code paths**, each calling the trajectory
level `collapseEssence` directly:

```
                 ┌─────────────────────────────────────────────┐
                 │  two reset branches (pre-B-slice)           │
                 └─────────────────────────────────────────────┘

  SelfReferentialCollapse        Pentagon collapse
  (Route/Anomaly.hs)             (Finalize/State.hs "Phase F")
        │                                │
        │  case essence of …             │  case essence of …
        │  collapseEssence turn traj     │  collapseEssence turn traj
        │  ResetEssence resetTraj ev     │  (resetTraj, _ev)  ← event
        ▼                                ▼                      DROPPED
  EssenceUncommitted resetTraj     EssenceUncommitted resetTraj
```

Problems:

* the reset event of the pentagon path was discarded
  (`_resetEvent`), so the soft rupture was **not replay-visible**;
* the trajectory-extraction (`case Essence of …`) was duplicated,
  so a future third path could diverge silently;
* nothing forced the two branches to agree on post-reset semantics.

## 2. The single canonical branch (BD2)

The canonical entry point is

```
collapseEssenceAt :: Int -> Essence -> (Essence, EssenceResetEvent)
```

in `QxFx0.Self.Essence`. It is **total on both constructors**
(`EssenceUncommitted` / `EssenceCommitted`), extracts the trajectory
once, and repacks the result as `EssenceUncommitted` alongside the
`EssenceResetEvent`. The rule: **every runtime reset goes through
`collapseEssenceAt` — a reset is either visible as an
`EssenceResetEvent` or it never happened.**

```
        ┌────────────────────────────────────────────┐
        │  single reset branch (post-B-slice)        │
        └────────────────────────────────────────────┘

  SelfReferentialCollapse          Pentagon collapse
  (Route/Anomaly.hs)               (Finalize/State.hs "Phase F")
        │                                  │
        └──────────────┬───────────────────┘
                       ▼
        collapseEssenceAt turn essence   (canonical morphism)
                       │
        ┌──────────────┴───────────────────┐
        ▼                                  ▼
  EssenceUncommitted resetTraj     EssenceResetEvent
  (reset turn: no witness, no      { ereTurn, erePreviousAngst,
   shouldCommit that turn)          erePreviousWitnessCount }
                                          │
                                          ▼
                              SelfState.selfLastEssenceResetEvent
                                          │
                                          ▼
                              trcEssenceResetEvent (replay trace)
```

Consumers:

| Site | Before | After |
|------|--------|-------|
| `Route/Anomaly.hs` `detectSelfReferentialCollapse` | manual `case` + `collapseEssence`; event carried in `ResetEssence` | `collapseEssenceAt`; `ResetEssence` now carries the full `Essence` |
| `Finalize/State.hs` Phase F (pentagon collapse) | manual `case` + `collapseEssence`; event **dropped** | `collapseEssenceAt`; event stored in `selfLastEssenceResetEvent` |
| `computeNextEssence` | repack of trajectory | consumes the carried `Essence` directly |
| `Finalize/Projection.hs` | — | `trcEssenceResetEvent = selfLastEssenceResetEvent (ssSelfState nextSs)` |

## 3. Soft vs hard rupture

There are two distinct failure semantics; they must not be conflated:

| | Soft rupture | Hard rupture |
|---|---|---|
| Trigger | SelfReferentialCollapse (Anomaly-3, angst > 0.9); pentagon collapse (`defendOrAdapt` → `Left`) | post-commitment plan violation (`validatePlan`) |
| Mechanism | `collapseEssenceAt` → `EssenceUncommitted` reset trajectory | `throwQxFx0 (EssenceRupture …)` in `Finalize/Commit.hs` |
| Persistence | turn continues; reset is recorded on the trace | turn aborts **before** persistence (`IdentityRupture` is co-located) |
| Replay | `trcEssenceResetEvent` is `Just` | no trace record (turn never reached projection) |
| Meaning | the system "loses what it has been through" but stays alive — visible, honest amnesia | the system refuses a state that is no longer itself |

The soft rupture is **never silent**: the `EssenceResetEvent` carries
the turn, the previous angst, and the previous witness count, and is
surfaced through `SelfState.selfLastEssenceResetEvent` onto the
replay trace.

## 4. State and trace changes

* `SelfState` gains `selfLastEssenceResetEvent :: Maybe EssenceResetEvent`
  (JSON backward-compatible, defaults to `Nothing`).
* `TurnReplayTrace` gains `trcEssenceResetEvent :: Maybe EssenceResetEvent`
  (FromJSON optional, defaults to `Nothing`).
* `AnomalyStateEffect` becomes
  `ResetEssence !Essence !EssenceResetEvent` — the canonical result is
  carried whole, finalize never re-derives it.

## 5. Anti-rot

`Test.Suite.EssenceCollapse` (registered in cabal and all three
TestMains):

* BD2: `collapseEssenceAt` total on both constructors; uncommitted and
  committed collapses agree; the canonical event equals the
  trajectory-level `collapseEssence` event.
* BD3: sustained hemispheric advantage with out-of-envelope divergence
  crosses the 0.75 angst threshold **on turn 15 exactly** and never
  before turn 14 — commitment is reachable inside the 14-15 window.
* BD3: zero-divergence agreement never commits inside the window.
* BD3: after a soft collapse the trajectory recommits within the same
  14-15 window (the rupture does not poison the loop).
