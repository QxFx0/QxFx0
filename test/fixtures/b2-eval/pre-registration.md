# B2 Pre-Registration — Fail/Pivot Conditions (LOCKED)

**Status**: LOCKED — must not be modified after transcript generation.
**Date**: 2026-06-17
**Front**: B2-EXEC-001 (packet) → B2-EXEC-002 (rating run)

## Pre-registered conditions

These conditions are locked **before** any human rater sees a transcript.
They must not be modified after transcript generation or during rating.

### Pass condition (PLACEHOLDER — no numeric threshold set)

System is preferred over Control-A on the **load-bearing dimensions**
(D1, D3) at a rate exceeding chance by a **calibration-pending margin**,
with inter-rater agreement above a **calibration-pending** floor.

No numeric threshold is set in this pre-registration. The threshold will
be set in B2-EXEC-002 after the first calibration batch, and **must be
set before the main rating run begins**. The threshold-setting process
itself must be pre-registered separately.

### Fail condition (PRE-REGISTERED — binding)

If System is **statistically indistinguishable from Control-A** on D1
(semantic depth) and/or D3 (repair/revision under challenge), then:

> **M6-FELT is not evidenced.** The structural investment does not
> manifest outward in dialogue. Fluency explains the output.

This is a real outcome the protocol can return, by construction.

### Pivot branch (PRE-COMMITTED)

On fail, one of two paths — **not both, not a mix**:

1. **Redesign target**: the implemented structure is not the structure
   that produces felt subjecthood. M4 semantic-core deepening must
   change approach. The B3 gates may need revision (new gates, higher
   thresholds, or different content).

2. **Terminal-thesis reclassification**: the North Star "felt" claim
   must be reframed or bounded. This escalates to the Final Anchor
   Doctrine's already-anticipated reclassification path.

**No rubric tweaking**: the rubric dimensions and anchors are locked.
If the system fails, the rubric is not modified to make it pass. This
is the core anti-falsification guard.

### No-averaging rule (B3 Decision 4, binding)

Pass on D5/D6 (supporting dimensions) **cannot** mask fail on D1/D3
(load-bearing). The overall pass requires D1 ∧ D3 to pass independently.
D5/D6 are supporting evidence but cannot carry a pass alone.

## Evidence admissibility

All transcripts in the rating packet must carry
`trcEvidenceAdmissibility = EvidenceGoverned` (SLICE-012). Transcripts
with `EvidenceDegradedGuardUnavailable` or `EvidenceInadmissible` are
**excluded** from the packet. The packet generation script must verify
this and record the admissibility status in `packet-metadata.json`.

## What this pre-registration does NOT do

- It does **not** declare the protocol valid — validity is established
  by the rating run, not by this document.
- It does **not** set numeric thresholds — those are calibration-pending.
- It does **not** claim M6-FELT is proven — M6-FELT remains NOT PROVEN
  until human results exist AND the pass condition is met.
- It does **not** allow post-hoc rubric modification.
