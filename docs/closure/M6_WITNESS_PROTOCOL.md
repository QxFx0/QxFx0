# M6 Witness Protocol

**Status:** Active — reconciled 2026-06-16 (consistent with `M6_DECLARATION.md`)
**Governed by:** ROADMAP.md §M6
**Activation gate:** H1 ✅, H2 ⏳ (records private), H3 ✅ (M5Regime public)

> This protocol and `M6_DECLARATION.md` are reconciled to one public truth: a
> contour is marked ✅ only when a real, in-repo public test/script targets it;
> otherwise ⏳ *pending public evidence*. Test pass/fail is not asserted (suites
> not re-run this revision).

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
   with each stage having an explicit admission seam

**What this is NOT:**
- Not consciousness, personhood, or general intelligence
- Not surface fluency (fluency alone is not subject structure)
- Not persistence alone (persistence alone is not subject structure)
- Not heuristic adaptation alone
- Not a privately-held result record (a record without a public test is ⏳, not ✅)

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
   — enforced by `scripts/check_architecture.sh` and `scripts/check_replay_gate.sh`

---

## 3. The 4 explicit evidence contours

M6 evidence is **not** a single claim. It is distributed across 4 separate contours,
each with a publicly-evidenced core and (some) pending rows:

### Contour C1: Continuity and coherence — **publicly evidenced**
- **What it proves:** the system's self-description (Conatus, Field, Essence,
  regime version) is present and visible in replay across turns
- **Public check:** `trcConatusEnergy`, `trcField`, `trcRegimeVersion` in
  `TurnReplayTrace` — `Test.Suite.TraceSchema`, `Test.Suite.M5Regime`,
  `scripts/check_replay_gate.sh`
- **Status:** ✅ public

### Contour C2: Restart integrity — **core publicly evidenced**
- **What it proves:** restarts do not silently re-admit non-authoritative state
  as authority
- **Public check:** `Test.Suite.StatePersistence.testBootstrapRejectsNonAuthoritativePersistedState`
  (non-auth persisted state rejected at bootstrap); `trcRegimeVersion` via
  `Test.Suite.M5Regime`
- **Status:** ✅ core public; ⏳ SR-04 bootstrap-phase classification record is private

### Contour C3: Commitment accountability — **publicly evidenced**
- **What it proves:** semantic commitments are typed, versioned, traceable, and
  admitted / quarantined / promoted under the constitution
- **Public check:** `Test.Suite.SemanticCommitmentCorpus` (store populated turn 1,
  grows multi-turn, `trcSemanticCommitmentCount` matches store, 3-turn corpus);
  `Test.Suite.CommitmentStoreAdmission` (CTS-42); `Test.Suite.CommitmentQuarantine`
  (CTS-43 + CTS-44 promotion: `unitPromoteMatchingQuarantine`, `unitPromoteNormalizedMatch`, `unitPromoteNoMatch`, `unitPromoteEmptyQuarantine`)
- **Status:** ✅ public (store + corpus + CTS-42/43/44)

### Contour C4: Bounded domain-dialogue competence — **core publicly evidenced**
- **What it proves:** the system participates bidirectionally in a declared domain
  under governed conditions
- **Public check:** `Test.Suite.AuthoritySurface` (24 GF round-trips, ≥99% coverage,
  negative corpus); `Test.Suite.M5Regime.m5FamilyDivergenceActiveIsStamped`
- **Status:** ✅ core public (bidirectional GF round-trip + live family divergence);
  ⏳ "5 topics × 3 languages" topic-matrix (GF-E1b record private, no public test)
  and the CTS-01–40 aggregate record (private)

---

## 4. Negative criteria — what does NOT constitute M6 evidence

The following are **explicitly rejected** as sufficient evidence of M6:

- Surface fluency (producing grammatical Russian/English output)
- Vague anthropomorphic prose about "consciousness" or "self-awareness"
- Hidden singleton continuity (non-authoritative restart carry)
- Untracked fallback behavior (compatibility routes without explicit classification)
- External-tool paraphrase mistaken for subject continuity (LLM output ≠ system commitment)
- Persistence alone (a field being persisted does not make it authoritative)
- A privately-held result record with no public test (marked ⏳, never ✅)

---

## 5. Witness schema — what a proof package must contain

A complete M6 evidence package for a bounded domain dialogue session must include:

1. **`TurnReplayTrace` records** for each turn — showing C1 (trcConatusEnergy,
   trcField, trcRegimeVersion) and C4 (trcFinalFamily, trcSalienceDriver)
2. **`ssSemanticCommitments` snapshot** — showing which commitments were made,
   revised, or retracted across the session
3. **`scripts/check_replay_gate.sh` passing** — static proof that canonical contours
   have trace fields
4. **`scripts/check_architecture.sh` passing** — authority-boundary rules confirm
   no violations
5. **At least one commitment revision** — the system must have revised or repaired
   a commitment under challenge (not just repeated the same surface output). The
   promotion/repair path (CTS-44) is publicly tested by `Test.Suite.CommitmentQuarantine`.
6. **No non-authoritative restart carry** — a session interrupted and resumed must
   produce the same family/force routing on the same input (within the regime)

---

## 6. Current M6 activation gate status

| Gate | Criterion | Status |
|------|-----------|--------|
| H1 | SLICE-NA-001 closed (non-auth restart re-entry) | ✅ `Test.Suite.StatePersistence` |
| H2 | Deferred arch queue (SR-03/04/05) classified | ⏳ records held privately — no public artifact |
| H3 | M5 as live governed regime | ✅ `Test.Suite.M5Regime` (public) |
| C1 | Canonical contours carry trace fields | ✅ `TraceSchema` + `M5Regime` + `check_replay_gate.sh` |
| C2 | Restart non-auth rejection + trcRegimeVersion | ✅ core (`StatePersistence`, `M5Regime`); ⏳ SR-04 record |
| C3 | Commitment store + corpus + CTS admission/quarantine/promotion | ✅ (`SemanticCommitmentCorpus`, CTS-42/43/44 via `CommitmentQuarantine`) |
| C4 | GF bidirectional + familyDivergence live | ✅ core (`AuthoritySurface`, `M5Regime`); ⏳ 5×3 topic-matrix + CTS aggregate |

**Reconciled activation reading:** the **publicly-evidenced core** of all four
contours holds (H1 ✅, H3 ✅, C1 ✅, C3 ✅, C2/C4 core ✅). A **total** M6 claim is
**not** yet supportable in public: it is blocked on the C4 topic-matrix test and
the public status of the H2 / GF-E1b / CTS-aggregate records. The declaration is
therefore made as **bounded/partial** (see
`M6_DECLARATION.md` §1, §3).

---

## 7. Next steps toward a total (non-partial) M6 claim

1. **C4 / topic-matrix public test:** a public fixture exercising the 5-topic ×
   3-language GF dual-surface, replacing reliance on the private GF-E1b record.
2. **H2 / records decision:** either publish public summaries of SR-03/04/05 and the
   CTS-01–40 aggregate, or leave them ⏳ and keep the claim bounded — do **not**
   cite them as ✅ while they are private.
3. **Bounded benchmark:** a multi-turn domain-dialogue fixture with at least one
   commitment revision, tying C1–C4 together in one replay-visible session.

> Done (no longer blocking): H3 `Test.Suite.M5Regime` is public; the C3
> `trcSemanticCommitmentCount` trace field is tested by `Test.Suite.SemanticCommitmentCorpus`;
> and CTS-44 promotion is publicly tested by `Test.Suite.CommitmentQuarantine` (`unitPromote*`).
