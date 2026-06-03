# M6 Witness Protocol

**Status:** Active (first slice, 2026-06-03)
**Governed by:** ROADMAP.md §M6
**Activation gate:** H1 ✅, H2 ✅ (materially satisfied), H3 in-progress

---

## 1. What "algorithmic subject structure" means in this fork

**Definition (checked, not metaphysical):**

An algorithmic subject structure is a runtime that can sustain, under explicit
regime rules:

1. **Bounded self-related continuity** across turns and restarts — the system
   can describe its own state (Conatus energy, Field, Salience verdict, Essence
   mode) in a replay-visible way; restarts do not silently reintroduce
   non-authoritative state as authority
2. **Domain-grounded semantic commitments** — the system makes, revises, retracts,
   and repairs semantic commitments through typed operations (`commit`, `revise`,
   `contradict`, `retract`), not through surface-only fluency
3. **Accountable revision under correction** — the system's commitment changes
   are recorded in `ssSemanticCommitments` and visible in `TurnReplayTrace`
4. **Governed distinction between authority, projection, fallback, compatibility
   residue, and quoted external output** — enforced by architecture rules, not
   by prose alone
5. **Bidirectional semantic participation** — words → atoms → families → words,
   with each stage having an explicit admission seam (CTS-01 through CTS-40)

**What this is NOT:**
- Not consciousness, personhood, or general intelligence
- Not surface fluency (fluency alone is not subject structure)
- Not persistence alone (persistence alone is not subject structure)
- Not heuristic adaptation alone

---

## 2. What "meaningful domain dialogue" means in this fork

**Definition (checked):**

Meaningful domain dialogue is dialogue in which the system can:

1. **Carry domain-bearing commitments across turns** — via `ssSemanticCommitments`
   and the `DialogueCommitmentLedger`
2. **Answer, refine, retract, or repair those commitments under challenge** — via
   typed `SemanticCommitmentStore` operations
3. **Expose replay-visible and governance-visible reasons** for persistence,
   revision, refusal, or fallback — via `TurnReplayTrace.trc*` fields
4. **Remain bounded** by declared authority, reconstruction, and recovery contours
   — enforced by `check_architecture.sh` 20 rules and `check_replay_gate.sh`

---

## 3. The 4 explicit evidence contours

M6 evidence is **not** a single claim. It is distributed across 4 separate contours:

### Contour C1: Continuity and coherence
- **What it proves:** the system's self-description (Conatus, Field, Essence)
  is stable across turns and visible in replay
- **How to check:** `trcConatusEnergy`, `trcField`, `trcEssenceMode` in
  `TurnReplayTrace` are non-trivial and consistent with the turn's routing decision
- **Current status:** fields present (P4 OK for all 6 canonical contours)

### Contour C2: Restart integrity
- **What it proves:** restarts do not silently re-admit non-authoritative state
  as authority
- **How to check:** `demoteNonAuthoritativeRestartCarry` fires on non-authoritative
  restart contours; `trcRegimeVersion` is present so replay knows which math
  version was active
- **Current status:** code exists; `trcRegimeVersion` added 2026-06-03

### Contour C3: Commitment accountability
- **What it proves:** semantic commitments are typed, versioned, and traceable
- **How to check:** `ssSemanticCommitments` is a `Maybe SemanticCommitmentStore`;
  `trcSemanticCommitment` trace field exists (Package 2 promotes this)
- **Current status:** `SemanticCommitmentStore` type exists; `trcSemanticCommitment`
  trace field is Package 2 work (needs-work per REPLAY_GATE_TRIAGE.md §2.13)

### Contour C4: Bounded domain-dialogue competence
- **What it proves:** the system participates bidirectionally in a declared domain
  under governed conditions
- **How to check:** GF dual-surface architecture (5 topics × 3 languages),
  CTS-01 through CTS-40 admission chain, `familyDivergenceActive` routing
- **Current status:** GF-E1b proven; CTS-40 closed; familyDivergenceActive = True

---

## 4. Negative criteria — what does NOT constitute M6 evidence

The following are **explicitly rejected** as sufficient evidence of M6:

- Surface fluency (producing grammatical Russian/English output)
- Vague anthropomorphic prose about "consciousness" or "self-awareness"
- Hidden singleton continuity (non-authoritative restart carry)
- Untracked fallback behavior (compatibility routes without explicit classification)
- External-tool paraphrase mistaken for subject continuity (LLM output ≠ system commitment)
- Persistence alone (a field being persisted does not make it authoritative)

---

## 5. Witness schema — what a proof package must contain

A complete M6 evidence package for a bounded domain dialogue session must include:

1. **`TurnReplayTrace` records** for each turn — showing C1 (trcConatusEnergy,
   trcField, trcRegimeVersion) and C4 (trcFinalFamily, trcSalienceDriver)
2. **`ssSemanticCommitments` snapshot** — showing which commitments were made,
   revised, or retracted across the session
3. **`check_replay_gate.sh` passing** — static proof that all 6 canonical contours
   have trace fields
4. **`check_architecture.sh` passing** — 20 rules confirm no authority boundary
   violations
5. **At least one commitment revision** — the system must have revised or repaired
   a commitment under challenge (not just repeated the same surface output)
6. **No non-authoritative restart carry** — a session interrupted and resumed must
   produce the same family/force routing on the same input (within the regime)

---

## 6. Current M6 activation gate status

| Gate | Criterion | Status |
|------|-----------|--------|
| H1 | SLICE-NA-001 closed | ✅ closed |
| H2 | Deferred arch queue materially satisfied | ✅ SR-03/SR-04/SR-05 classified |
| H3 | M5 as live governed regime | ⬜ in-progress (REGIME_GOVERNANCE.md created, trcRegimeVersion wired) |
| C1 | All 6 canonical contours P4 OK | ✅ |
| C2 | Restart integrity code exists + trcRegimeVersion present | ✅ |
| C3 | SemanticCommitmentStore typed + trace field | ⬜ trace field (Package 2) |
| C4 | GF proven + CTS complete + familyDivergence live | ✅ GF-E1b + CTS-40 + ADR-0019 |

**M6 activation rule:** H1 ✅ + H2 ✅ + H3 (needs M5 regime test) + C3 (needs Package 2)

---

## 7. Next steps toward M6 activation

1. **H3 / M5 completion:** Add `Test.Suite.M5Regime` that verifies `trcRegimeVersion > 0`
   in a produced turn trace — this makes M5 a tested regime, not just documented
2. **C3 / Package 2:** Promote `ssSemanticAnchor` to typed `SemanticCommitments`;
   add `trcSemanticCommitment` to `TurnReplayTrace`
3. **Bounded benchmark:** Create a fixture family that exercises multi-turn domain
   dialogue with at least one commitment revision
4. **M6 declaration:** Once H3 and C3 are closed, write the bounded claim package
   (`docs/closure/M6_CLAIM_PACKAGE.md`) with the evidence references
