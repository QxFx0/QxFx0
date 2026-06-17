# ESSENCE-REGIME-RECONCILE — Read-Only Audit + Decision Doc

- **Front ID**: ESSENCE-REGIME-RECONCILE
- **Type**: Policy / contract front (not a code-fix front)
- **Status**: Audit complete; policy choice pending operator decision
- **Date**: 2026-06-17
- **Constraint**: No behavior change before policy choice. This document
  does not modify code, flags, ADRs, or docs. It consolidates evidence and
  presents two admissible policies.
- **Do-not-mix**: SLICE-010B (morphology resource contract) is a separate
  front; this front does not touch it.

---

## 1. Why this front exists

`audit-objective-2026-06-17.md §5.1` identified a triple drift in Essence
commitment status across code, regime, and docs. On gathering all sources,
the drift is **wider and older than initially reported**: the feature flag
designed in ADR-0012 §10.1 was **never implemented in code**, Essence has
been **fully and unconditionally active** in the runtime pipeline since
landing, and 12+ documents + one discipline test continue to certify it as
flag-off. This is the exact "claim ≠ reality" seam the project doctrine
declares inadmissible, sitting on the most load-bearing subjecthood
assertion.

---

## 2. Consolidated evidence table

Every source that speaks about Essence commitment status, what it says,
and whether it matches runtime reality.

### 2.1 Runtime code (the ground truth)

| Source | Location | What it says | Essence active? |
|---|---|---|---|
| `shouldCommit` invocation | `Finalize/State.hs:344-371` | Comment: "`shouldCommit` is always evaluated; **no feature flag**". `shouldCommit defaultEssenceModulation trajectory'` runs unconditionally every turn. `EssenceCommitted` is sticky, never reverted. | **YES (unconditional)** |
| `validatePlan` invocation | `Finalize/State.hs:169`, `Route/Effects.hs:61` | `validatePlan commitment (delibReconciled delib)` called in finalize; `courtesyPred` uses `validatePlan` in route effects. No flag guard. | **YES (unconditional)** |
| `EssenceRupture` exception | `Commit.hs:91`, `Engine.hs:71,198` | `Left (EssenceViolation …)` → `EssenceRupture` raised at commit; caught and handled in engine. A real, reachable exception. | **YES (reachable)** |
| Regime stamp | `RuntimeRegime.hs:81` | `rrEssenceActive = True  -- ADR-0036 promoted 2026-06-04`. Field declared at `:56`. | **Stamps "active"** |
| `rrEssenceActive` read sites | (grep: none) | The field is **write-only**: set at `:81`, never read anywhere in `src/` or `test/`. It stamps `trcRegime` / `TurnReplayTrace` but gates nothing. | **Stamp only, no gate** |
| `essenceCommitmentEnabled` flag | (grep: absent from `src/`) | The flag designed in ADR-0012 §10.1 **does not exist in code**. Searched: 0 matches in `src/`. | **Flag never implemented** |
| `QXFX0_ESSENCE_COMMITMENT_ENABLED` env var | (grep: absent from `src/`) | The env var named in ADR-0036 §2.3 and `PromotionFlagDiscipline` **does not exist in code**. Searched: 0 matches. | **Env var never implemented** |

**Operational reality: Essence is fully active — `shouldCommit` evaluates,
`commit` fires, `validatePlan` checks, `EssenceRupture` can raise — and has
been since landing 2026-05-19. There is no flag and no env var. The regime
stamps `True` but does not gate.**

### 2.2 ADRs

| Source | Location | What it says | Matches reality? |
|---|---|---|---|
| ADR-0012 §10.1 | `docs/adr/0012-essence-commitment.md:394` | Designs `essenceCommitmentEnabled :: Bool` (default `False`) "gating the `shouldCommit`/`commit` invocation in the prepare stage". | **NO** — the gate was designed but never built. |
| ADR-0012 §10.1 test | same | "under flag-on, a hand-built trajectory crossing the angst threshold yields `EssenceCommitted` exactly once and never reverts". | Test exists but the flag-on/flag-off distinction is meaningless — there is no flag. |
| ADR-0036 §1-§5 | `docs/adr/proposed/0036-…md:1-155` | Status: **Proposed**. "gated by `essenceCommitmentEnabled :: Bool` defaulted to `False`". Acceptance criteria G1-G3 all unchecked. "The ADR is **deferred** (not closed) … Until then, the flag stays at `False`." | **NO** — says flag stays False; reality is unconditional-on. |
| ADR-0036 §6 | `docs/adr/proposed/0036-…md:158-211` | Added 2026-06-04: "Promotion (Track-I P0 Stage 7)". "`rrEssenceActive = False` → `True`". "Promoted (Track-I), Acceptance criteria (§5) still pending". G1 (1k corpus) **deferred**, G2 (angst calibration) **deferred**, G3 **partially met**. | **Partially** — stamps True (matches reality) but calls itself "promoted" while §1-§5 say "deferred" and the flag it claims to flip doesn't exist. **ADR is internally contradictory.** |

### 2.3 Governance / closure docs

| Source | Location | What it says | Matches reality? |
|---|---|---|---|
| `AGENTS.md` | `:23` | "Default `essenceCommitmentEnabled = False`; flag-on integration replay confirms zero spurious ruptures." | **NO** — flag doesn't exist; "flag-on" is meaningless. |
| `SELF_LAYER_STATUS.md §3` | `:59` | `Self.Essence` = `production-flag-off`, flag `essenceCommitmentEnabled :: Bool` default `False`. Promotion requires 1k+ turns, angst verification, E1-E5. | **NO** |
| `SELF_LAYER_STATUS.md §6` | `:117` | "`Self.Essence` | **no** | `essenceCommitmentEnabled = False` default." (Binary "core runtime today?" = no.) | **NO** — Essence IS in the runtime path. |
| `AUTHORITY_MAP.md §3` | `:63` | `Self.Essence` = **canonical-flag-off**. | **NO** — should be `canonical`. |
| `AUTHORITY_MAP.md §6` | `:142` | "Essence commitment | `QXFX0_ESSENCE_COMMITMENT_ENABLED` | `False` | …". | **NO** |
| `AUTHORITY_MAP.md §8` | `:171` | "`ssEssence :: Essence` — **canonical-flag-off** (essence not active by default)." | **NO** |
| `SYSTEM_STATE_AUTHORITY.md` | `:45,138` | "`ssEssence` = `canonical-flag-off` … gated by `essenceCommitmentEnabled`". "The runtime gate is `essenceCommitmentEnabled`." | **NO** — there is no gate. |
| `M6_DECLARATION.md §6` | `:198-199` | "Full essence commitment — `essenceCommitmentEnabled = False`; the Essence contour is flag-off; it is **not counted** as active subject evidence." | **NO** |
| `M6_DECLARATION.md §10` | `:304` | "essenceActive | False (pending corpus)". | **NO** — regime stamps True. |
| `M6_DECLARATION.md §4` | `:169` | Negative criteria: "System has an Essence commitment — Flag-off, not yet promoted; not counted." | **NO** |
| `REGIME_GOVERNANCE.md` | `:30` | "**essenceActive:** `False` (ADR-0036 pending production corpus)". | **NO** — contradicts `:44` which lists `rrEssenceActive` as a feature flag, and contradicts `RuntimeRegime.hs:81`. |
| `flag_promotion_registry.tsv` | `:2` | `essenceCommitmentEnabled	off	-	ADR-0036`. File column = `-` (not in code). | **NO** — says off and not-in-code; reality is on and the regime-stamp is in code. |
| `CONTOUR_INDEX.md` | `:224` | "`essenceCommitmentEnabled` (default `False`)." | **NO** |
| `REPLAY_GATE_TRIAGE.md` | `:123,215` | "the contour is **flag-off** (`essenceCommitmentEnabled = False`)". | **NO** |
| `TEST_AUTHORITY_AUDIT.md` | `:75` | "not part of the **canonical runtime** regression lock until `essenceCommitmentEnabled` flips to `True`." | **NO** |
| `PROMOTION_PLAYBOOK.md` | `:138` | Essence commitment row: gate = "`essenceCommitmentEnabled = True`", criteria = "1k turns, 0 ruptures". | **NO** — gate never built. |
| `ADR_INDEX.md` | `:310` | "Essence | `essenceCommitmentEnabled` | off | no (depends on calibration data)". | **NO** |
| `FOLLOWUPS.md` | `:339` | "`essenceCommitmentEnabled` flip on G1 (corpus replay …)". | **NO** |

### 2.4 Implementation specs

| Source | Location | What it says | Matches reality? |
|---|---|---|---|
| `phase-10-essence-commitment-implementation-spec.md` | `:9,24,128,346` | "Default of `essenceCommitmentEnabled` is `False`." Wire it "the way `familyDivergenceEnabled` was wired in Phase 8 Package D." | **NO** — the wiring was never done. |
| `phase-10-step-10-corpus-replay-spec.md` | `:15` | **Critical**: "with `essenceCommitmentEnabled = False`, `validatePlan` is never invoked, so zero ruptures is a **tautology**. The actual contract from ADR-0012 §9 lock E8 — *zero ruptures on the corpus under flag-on* — has not been exercised." | **Stale premise** — the spec assumes the flag exists and is off. In reality the flag doesn't exist and `validatePlan` IS invoked unconditionally. So the "0 ruptures" evidence is **not** tautological (it's real, because `validatePlan` runs) — but the spec's reasoning was built on a flag that was never there. |
| `phase-9-essence-implementation-spec.md` | `:676` | "`essenceCommitmentEnabled` feature flag." | **NO** |

### 2.5 Tests

| Source | Location | What it says / does | Matches reality? |
|---|---|---|---|
| `PromotionFlagDiscipline.hs` | `:96-101` | Lists Essence as not-yet-promoted: `pcFlagName = "essenceCommitmentEnabled"`, `pcInCode = False` ("not in code at the Haskell level"). | **Correct that flag is absent**, but the test interprets absence as "off/disciplined" — it does not detect that Essence is **on via a different mechanism** (unconditional `shouldCommit` + `rrEssenceActive=True`). |
| `PromotionFlagDiscipline.hs` logic | `:147-176` | Searches `src/` for `"essenceCommitmentEnabled"`. Finds 0 matches → `trueLiterals = []` → no failure → **test passes**. | **Green, but certifies a fiction**: it certifies "essence is off" while Essence is fully active under a name the test doesn't search for (`rrEssenceActive`, `shouldCommit` unconditional). |
| `Test.Suite.SelfEssence` | — | Property tests for Essence module. Run on CI. | Tests the pure module, not the operational gate. |
| `Test.Suite.SelfEssenceCommit` | — | Tests `shouldCommit`/`commit` under constructed trajectories. | Per ADR-0012 §10.1, these were supposed to test flag-on behavior. Since there is no flag, they test unconditional behavior. |

### 2.6 Summary count

- **Sources saying Essence is flag-off / not active / not counted**: 19
  (AGENTS.md, SELF_LAYER_STATUS §3+§6, AUTHORITY_MAP §3+§6+§8,
  SYSTEM_STATE_AUTHORITY, M6_DECLARATION §4+§6+§10, REGIME_GOVERNANCE,
  flag_promotion_registry, CONTOUR_INDEX, REPLAY_GATE_TRIAGE,
  TEST_AUTHORITY_AUDIT, PROMOTION_PLAYBOOK, ADR_INDEX, FOLLOWUPS,
  phase-10-spec, phase-9-spec, ADR-0036 §1-§5)
- **Sources saying Essence is active / promoted**: 2
  (RuntimeRegime.hs:81, ADR-0036 §6)
- **Sources that are the operational reality**: 4 code sites
  (Finalize/State.hs:344, Finalize/State.hs:169, Route/Effects.hs:61,
  Commit.hs:91 + Engine.hs:71)
- **Sources that are internally contradictory**: 2
  (ADR-0036 §1-§5 vs §6; REGIME_GOVERNANCE.md:30 vs :44)

---

## 3. The two admissible policies

The operator's constraint: "This is not necessarily 'turn the code off'.
There are two admissible policies." Both are legitimate; they differ in
which direction they reconcile the drift.

### Policy A — Promote reality

**Accept that Essence is law-driven / default-active.** The flag was never
built; Essence has been unconditional since 2026-05-19; the regime already
stamps `True`. Reconcile all docs to match.

**What this policy does:**
- Accept `rrEssenceActive = True` and `shouldCommit` unconditional as the
  intended state.
- Move ADR-0036 from `proposed/` to `accepted/`; mark §1-§5 as superseded
  by §6; rewrite §6 to state the actual operational mechanism (law-driven,
  no flag — not "flag flip").
- Reclassify `Self.Essence` from `canonical-flag-off` to `canonical` in
  AUTHORITY_MAP, SELF_LAYER_STATUS, SYSTEM_STATE_AUTHORITY.
- Update `flag_promotion_registry.tsv`: `essenceCommitmentEnabled` →
  remove row (flag never existed); or mark `rrEssenceActive` as `promoted`.
- Update M6_DECLARATION: remove "essence flag-off / not counted" from §4
  negative criteria and §6 scope limits; Essence **is** counted as active
  subject evidence.
- Fix `PromotionFlagDiscipline`: remove Essence from not-yet-promoted list.
- Update AGENTS.md, CONTOUR_INDEX, REPLAY_GATE_TRIAGE, TEST_AUTHORITY_AUDIT,
  PROMOTION_PLAYBOOK, ADR_INDEX, FOLLOWUPS, phase-9/10 specs.
- Either remove `rrEssenceActive` (write-only, gates nothing) or wire it as
  a real read site — but that is a code change, deferred to the
  implementation phase after policy choice.

**Consequences:**
- (+) Honest about what the code actually does.
- (+) No behavior change — nothing breaks.
- (−) **Accepts Essence into production without G1 (1k+ turn corpus), G2
  (angst calibration), or G3 (coherence locks on corpus)** — the
  promotion criteria the project set for itself. ADR-0036 §6 already
  deferred these; Policy A makes that deferrence permanent.
- (−) M6_DECLARATION's negative criteria ("Flag-off, not yet promoted; not
  counted") must be removed — meaning Essence **becomes** part of the M6
  subject-structure evidence. But the guard-unavailable finding
  (`audit-objective-2026-06-17.md §3`) means the evidence was collected in
  ungoverned mode, so adding Essence to M6 evidence inherits that
  inadmissibility unless SLICE-012 lands first.
- (−) Retroactively legitimizes a silent promotion — the doctrine says "no
  silent flips", but the flip was silent (the flag was silently absent
  from the start). Policy A says "the silence is the answer".

### Policy B — Restore flag-off

**Implement the gate ADR-0012 §10.1 designed, set it to False, and revert
the premature promotion.** Essence goes dark until G1-G3 are met.

**What this policy does:**
- Implement `essenceCommitmentEnabled :: Bool` in the prepare stage (or
  `Finalize/State.hs`), gating `shouldCommit` / `commit` / `validatePlan`,
  defaulted to `False` — as ADR-0012 §10.1 specified.
- Implement the `QXFX0_ESSENCE_COMMITMENT_ENABLED` env var opt-out path
  (ADR-0036 §2.3) so operators can opt in for corpus replay.
- Set `rrEssenceActive = False` in `RuntimeRegime.hs`.
- Revert ADR-0036 §6; mark it as a premature promotion; restore §1-§5 as
  the active text. ADR stays in `proposed/`.
- Leave all 19 docs as-is (they already say flag-off) — they become
  **correct** once the gate exists.
- `PromotionFlagDiscipline` becomes correct (it already searches for
  `essenceCommitmentEnabled`; once the flag exists as `= False`, the test
  passes for the right reason instead of the wrong reason).

**Consequences:**
- (+) Restores the designed behavior and the promotion gate the project
  set for itself.
- (+) Makes 19 docs correct with no doc rewrite (they already describe
  flag-off).
- (+) Enables honest corpus replay under flag-on vs flag-off (the
  comparison ADR-0012 §10.1 and `phase-10-step-10-corpus-replay-spec.md`
  require).
- (−) **Behavior change**: turns off something that has been silently on
  since 2026-05-19. `trcEssence*` trace fields stop populating. Any
  session that relied on Essence commitment (unknowingly) loses it.
- (−) Requires a code change (implementing the gate), which is more work
  than doc updates.
- (−) Admits the project shipped Essence active for ~5 weeks without
  realizing it — a discipline failure either way, but Policy B makes the
  failure visible and reversible rather than permanent.

### Doctrine tension (applies to both)

The project doctrine (`ROADMAP` M5, ADR-0036 §2.3) says:
- "no silent flips"
- "a change to the default must be a commit, not a hotfix"
- "the flag flips to `True` **only** via the playbook's G3 release event"

Both policies violate this doctrine **retroactively**: the flag was
silently absent from the start. Policy A accepts the violation as
permanent; Policy B reverses it. Neither can undo that the project
ran Essence ungoverned for 5 weeks without knowing. The choice is
whether that period becomes "Essence was always active" (A) or "Essence
was accidentally active and is now corrected" (B).

---

## 4. What this front does NOT do (per operator constraints)

- Does **not** change `rrEssenceActive` alone.
- Does **not** add or remove the env var without a policy decision.
- Does **not** declare Essence as M6-FELT evidence.
- Does **not** mix with SLICE-010B.
- Does **not** modify any code, flag, ADR, doc, or test — this is the
  read-only audit + decision doc only.

---

## 5. Output — policy choice required

The operator must choose:

- **[ ] Policy A — Promote reality**: Essence is law-driven/default-active;
  reconcile all docs to match; accept uncalibrated Essence into production.
- **[ ] Policy B — Restore flag-off**: implement the designed gate, default
  False, revert ADR-0036 §6; Essence goes dark until G1-G3 are met.

Either choice unblocks the next front. Neither choice is a code change by
itself — both are followed by an implementation phase that executes the
chosen policy. This document is the decision record; the implementation
plan is a separate artifact after the choice.

---

## 6. Provenance

| Item | Value |
|---|---|
| Evidence gathered | 2026-06-17, read-only (no code/doc/ADR/test modified) |
| Sources audited | 9 required + 10 additional discovered (29 total entries in §2) |
| Code verified | `Finalize/State.hs:344-375`, `:169`, `Route/Effects.hs:61`, `Commit.hs:91`, `Engine.hs:71,198`, `RuntimeRegime.hs:56,81`, `ExceptionPolicy.hs:104`, grep for `essenceCommitmentEnabled` (0 in src/), grep for `QXFX0_ESSENCE_COMMITMENT_ENABLED` (0 in src/), grep for `rrEssenceActive` read-sites (0) |
| Test verified | `PromotionFlagDiscipline.hs:96-176` — confirmed green despite `rrEssenceActive=True` (searches wrong name) |
| Key discovery beyond initial audit | The flag was never implemented (not "drift between True and False" but "the flag doesn't exist"); `validatePlan` and `EssenceRupture` are reachable; `phase-10-step-10-corpus-replay-spec.md:15` calls the "0 ruptures" evidence tautological under a false premise; 19 sources say off, 2 say on, 2 are self-contradictory |
