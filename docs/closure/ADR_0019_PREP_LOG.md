# ADR-0019 Prep Log (Family Divergence)

**Date**: 2026-06-02
**Status**: gate-pending; release event deferred
**Source session**: no-cabal closure-plan import session

---

## What was done in this session

The user asked for "ADR-0019 prep" — preparing the
release event for the Family Divergence flag flip
per the PROMOTION_PLAYBOOK.

After the recon, three gates (G1/G2/G3) per
ADR-0019 §2.1 were found to be **not met** in
this session:

- **G1 (caller audit)**: partial. Rule [12]
  mechanical check is verifiable; the human
  audit (reading `src/QxFx0/Core/TurnRouting.hs`
  and `Cascade.hs` to confirm `holisticFamily` /
  `formalFamily` go through `Self.Adjunction`)
  is **deferred**.
- **G2 (replay parity)**: requires `cabal run` of
  a fixed-fixture replay with
  `familyDivergenceEnabled = True` and comparison
  against the `False` baseline. The no-cabal
  session **cannot run this**.
- **G3 (corpus observability)**: requires the
  production-trace corpus (per F-09), which is
  not harvested yet. **Cannot run this without
  F-09 first**.

Per the user's option **(b) prep without flip**,
the actual code change at
`src/QxFx0/Core/TurnRouting/Cascade.hs:74`
(`familyDivergenceEnabled = False` → `= True`)
was **NOT** made. The flag stays at `= False`.

The following doc changes were made (none
committed; all in working tree, ready for
next-contributor review):

| File | Change |
|------|--------|
| `docs/closure/ENFORCEMENT_MATRIX.md` | rev. 5 header; R6 row updated with "ADR-0019 prep, gate-pending"; new "Rev. 5 prep log" entry |
| `docs/closure/FOLLOWUPS.md` §15.1 | "drafted (gate-pending, prep done 2026-06-02)" |
| `docs/closure/FOLLOWUPS.md` §15.4 | "Land ADR-0019" entry expanded with gate status |
| `docs/adr/proposed/0019-promote-family-divergence.md` | new §6 "Gate status (2026-06-02)" with G1/G2/G3 marked as partial/deferred |
| `docs/closure/PROMOTION_PLAYBOOK.md` | new §10 "Release log" with the 2026-06-02 attempt and the next-contributor procedure |
| `docs/closure/ADR_0019_PREP_LOG.md` | **this file** (handoff for next-contributor) |

## What was NOT done (and why)

- **Cascade.hs:74 flip**: deferred. The flip
  requires the gates to pass first per
  PROMOTION_PLAYBOOK §2.
- **check_architecture.sh rule [20] update**:
  not needed yet. The rule still correctly
  enforces `familyDivergenceEnabled = False`;
  when the flag is flipped, rule [20] needs
  Family Divergence removed from the `in_code`
  enforcement (so the new `= True` literal is
  allowed). This is a 1-line change in the
  rule's Python list.
- **SELF_LAYER_STATUS.md / AUTHORITY_MAP.md
  updates**: not yet. These get updated as
  part of the release event (per
  PROMOTION_PLAYBOOK §3 steps 5-6).
- **Changelog entry**: not yet. Added during
  the release event.
- **qxfx0.cabal test-common migration**: not
  yet. The relevant test suite is currently
  wired; whether to move to canonical depends
  on post-flight.
- **ADR-0019 status field update ("Accepted")**:
  not yet. ADR-0019 stays in `proposed/` until
  the release event lands.

## State per §15 (3-state)

| Item | Before this prep | After this prep | Reason |
|------|------------------|-----------------|--------|
| ADR-0019 (Family Divergence) | drafted (in `proposed/`) | drafted + gate-pending (in `proposed/`) | The prep is a documentation step; no source change. The flip is still required for "landed". |
| ENFORCEMENT_MATRIX.md R6 row | green | green + gate-pending sub-state | R6 status semantics unchanged (discipline still in place for 4 other flags). |
| Cascade.hs:74 | `= False` literal | `= False` literal (unchanged) | No flip in this session. |
| check_architecture.sh rule [20] | enforces `= False` | enforces `= False` (unchanged) | Still correct; will need update at release event. |

## Residual backlog (unchanged)

1. **ADR-0019 release event** (the actual flip
   + 8 release-event sub-steps) — depends on
   G1/G2/G3 passing.
2. **G1 human audit** — `cabal test` permission
   + reading the routing code.
3. **G2 replay parity** — `cabal` + fixed-fixture
   corpus.
4. **G3 corpus observability** — F-09 corpus
   first.
5. **F-09 corpus** (1k unlabelled + 100 labelled)
   — L-sized, requires production traces.
6. **F-10 first calibration** — depends on F-09.
7. **4 remaining promotion landings** (ADR-0020,
   0021, 0022, 0036) — same gate structure.
8. **Demotion activation** (ADR-0023) — M-sized.
9. **Real GF parser** — XL.
10. **Python P5-1** — M-sized.

## Next-contributor checklist

For the **next-contributor with cabal
permission** to actually land ADR-0019:

1. **Verify pre-flight** (per PROMOTION_PLAYBOOK
   §1): flag is `= False`, ADR is in `proposed/`,
   test is non-canonical, trace fields are in
   `TurnReplayTrace`. All currently true.
2. **Run G1** (caller audit):
   - Run `bash scripts/check_architecture.sh` and
     verify rule [12] passes.
   - Read `src/QxFx0/Core/TurnRouting.hs` and
     `src/QxFx0/Core/TurnRouting/Cascade.hs` and
     confirm `holisticFamily` / `formalFamily`
     go through `Self.Adjunction.reconcile`.
   - Mark G1 as `met` in
     `0019-promote-family-divergence.md §2.1`.
3. **Run G2** (replay parity):
   - `cabal run qxfx0-main -- --replay-flag-on familyDivergenceEnabled`
     on the canonical fixed-fixture set.
   - Compare trace JSON against the `False`
     baseline; verify byte-identical on cases
     where the modulation does not fire.
   - Mark G2 as `met` if byte-identical.
4. **Run G3** (corpus observability) — **only
   after F-09 is harvested**:
   - Run a corpus case.
   - Verify `trcDeliberationDivergence` is
     non-`Neutral` on at least one case.
   - Mark G3 as `met` if non-Neutral observed.
5. **Release event** (per PROMOTION_PLAYBOOK §3
   8 sub-steps):
   - Edit `src/QxFx0/Core/TurnRouting/Cascade.hs:74`:
     `familyDivergenceEnabled = False` → `= True`.
   - Update `check_architecture.sh` rule [20]:
     remove Family Divergence from the
     `in_code=True` list (so `= True` literal
     is no longer a violation).
   - Update `SELF_LAYER_STATUS.md §2`: mark
     Family Divergence as `production-flag-on`.
   - Update `AUTHORITY_MAP.md §6`: mark
     Family Divergence as `promoted` (or remove
     the row).
   - Add a changelog entry under "Flag flips".
   - Update ADR-0019 status: move from
     `proposed/` to `docs/adr/` (accepted) and
     mark §2.1 gates as `met`.
   - Update ENFORCEMENT_MATRIX.md R6 row:
     note Family Divergence as `released`;
     status still green.
   - Update PROMOTION_PLAYBOOK.md §10 release
     log: add the release event entry.
6. **Commit** (single commit or small set, per
   §3): the diff references ADR-0019.
7. **Post-flight** (per §4): monitor 1k
   production turns; revert if any misfire
   (per ADR-0019 §3.2 risk: wrong family
   choice on miscalibrated
   `smModulationHolisticBiasFloor`).

If any of G1/G2/G3 fails, **stop**; the
playbook's discipline is to revert / defer,
not to force the flip.
