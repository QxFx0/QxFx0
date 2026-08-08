# M6-FELT Mechanical Evidence Gate

- **Front**: M6-FELT gate (felt-evidence gate)
- **Status**: IMPLEMENTED (2026-08-08) — the mechanical checker exists;
  the gate currently **fails fail-closed** on real data expectations
  (it only proves a session when the runtime record satisfies Gates
  1–5 under governed-evidence conditions)
- **Depends on**: SLICE-012 (`EvidenceAdmissibility`,
  `QXFX0_GOVERNED_EVIDENCE`, `trcEvidenceAdmissibility`) — closed
- **Module**: `QxFx0.Core.M6FeltGate`
- **Tests**: `Test.Suite.M6FeltGate` (13 cases, registered in
  `TestMain`, `TestMainFast`, `TestMainUnit`)

---

## 1. What the gate is

Per `M6_DECLARATION.md` §6(4) and `B3_SEMANTIC_CORE_MVS_GATE.md`:

> M6-FELT is proven means Gate 5 (precondition) ∧ Gate 1 ∧ Gate 2 ∧ Gate 3
> ∧ Gate 4 all pass under governed-evidence conditions
> (`QXFX0_GOVERNED_EVIDENCE=1`, guard Available, trace
> `EvidenceGoverned`), mechanically checked, with the public seed corpus
> — conjunction across both layers, not average.

This module is the **mechanical checker**: a pure, deterministic
function over a session's `[TurnReplayTrace]` that audits a session as
M6-FELT evidence.

## 2. The six gates

| Gate | Criterion (trace evidence) |
|---|---|
| FeltGateGovernedEvidence | every turn `trcEvidenceAdmissibility == EvidenceGoverned` (SLICE-012 precondition) |
| Gate 5 (non-fallback) | `trcAuthorityClass` in {Canonical, Shim}; `trcFallbackReason == Nothing`; `trcLinearizationOk == True`; `trcContentSource` in {covered_exact, covered_generic} |
| Gate 1 (definition) | ≥2 turns with non-empty `trcEmittedPredicates` and non-empty rendered text |
| Gate 2 (distinction) | ≥2 distinct `trcDialogueFocus` values on semantic turns |
| Gate 3 (repair) | some turn with `trcCommitmentEngaged > 0` ∧ (`trcCommitmentContradicted` ∨ `trcCommitmentStoreDecision ≠ CsaAdmitCanonical`) |
| Gate 4 (commitment) | ≥10 turns; final `trcSemanticCommitmentCount ≥ 1`; count never drops without a typed retraction turn |

## 3. Fail-closed discipline

- An **empty session** fails all six gates.
- A session where **any** turn is ungoverned fails the whole gate —
  no averaging, no partial credit.
- A gate that **cannot be mechanically established** from the trace
  fields is reported failed; the checker never manufactures evidence.
- The verdict type names every failed gate (`M6FeltNotProven [FeltGate]`)
  — diagnostics, not a boolean alone.

## 4. Relationship to B3 and B2

- `Test.Suite.B3MechanicalGateExecution` checks the **data-level
  substrate** (the content layer exists for all covered topics).
  This module checks the **runtime-level record** (a specific session's
  traces satisfy the gates under governed conditions).
- Per B3 Decision 4 and the B2 hard guard, this gate passing for a
  session still does **not** prove M6-FELT — B2 human-eval must also
  run and pass. This gate is the mechanical floor that B2 finally
  evaluates.

## 5. Status: NOT PROVEN

The gate currently fails fail-closed — as intended. Real sessions have
not yet produced traces that pass all six gates under governed-evidence
conditions. The measure by which a session becomes "M6-FELT evidence" is
now mechanical and public.