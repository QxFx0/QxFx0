# P1 — label packet design (DRAFT, 2026-11-27)

- **Status**: **DRAFT — not pre-registered.** On 2026-11-27 the owner chose the
  corpus (**B: fresh strict-mode capture**, §2). The rubric, threshold, kappa
  gate, context window and rater identity are still **OPEN** (§8). No packet
  has been generated, no rater has been named, and no number in this document
  is a measurement.
- **Plan line this implements**: P1 needs a human rater, blind 0–4 labels on
  ≥ 200 turns, and a two-rater subset of ≥ 50 with kappa and adjudication.
- **What this document is**: the packet/rubric design that has to be signed
  before the packet is built. It deliberately does not choose the rubric
  anchors, the pass threshold or the rater on the owner's behalf.
- **What this document is not**: evidence, a quality claim, an M6-FELT claim,
  or the 500-prompt gate. The 500-prompt gate stays **BLOCKED** (500 labeled
  rows and a second independent rater are still missing).

## 1. Fixed by the plan

| Item | Value |
|---|---|
| turns | ≥ 200 |
| primary label | 0–4, blind |
| double-rated subset | ≥ 50 turns, two independent raters |
| agreement | kappa, reported before adjudication |
| adjudication | disagreements resolved by a third party, recorded |

## 2. Corpus — DECIDED: B, fresh strict-mode capture

The owner chose option B on 2026-11-27: re-run the existing 200-turn corpus in
`QXFX0_RUNTIME_MODE=strict`, one process per turn, own DB, frozen tree.

| item | value |
|---|---|
| corpus | `spec/eval/p2_baseline_2026-11-18.tsv`, sha256 `49b6d6c395f0000875cb8c3e9db6ed0fba764b08e15b323944ba4945067444b7` |
| rows | 200 = 20 dialogues × 10 turns, 8 arcs (`calm` 60, `negative` 40, `decoy` 20, `oscillation` 20, `pileup` 10, `challenge` 10, `practical` 10, `recovery` 10, `terse` 10, `move` 10) |
| driver | `scripts/run_user_regime_capture.sh <run_id> <corpus>` with `QXFX0_RUNTIME_MODE=strict`; one CLI process per turn, own `capture.db`, `mode=ro` readers |
| recorded identity | `meta.env` stores corpus sha256, binary sha256, `git_head`, `git_dirty_files`, start/last-turn timestamps |
| Protocol A check | the driver's gate re-counts hard-trigger Protocol B and contour exits; the P2 corpus is already pinned in `Test.Suite.CrisisGuard` |

**Feasibility smoke (measured 2026-11-27, not the capture)**: one strict turn
(`p2-def-01` turn 1) on HEAD `b6f4dc6`, own DB
`reports/eval_runs/p1-strict-smoke-20261127/`, **68.6 s** wall, 1/1 turn
persisted, 1/1 regime record, 0 hard-trigger Protocol B, encoder `[2]`.
Extrapolated cost for 200 turns: **≈ 3.8 h**. The smoke is a precondition
check, not P1 evidence.

Why not A (the existing degraded capture): 151/200 turns carry a
`runtime_degraded` recovery cause and the surface ends with the availability
banner; a 0–4 adequacy label would be dominated by the banner, compressing
variance and depressing kappa. The strict capture costs one background run and
removes that confound.

**Rubric consequence of strict mode (measured in the smoke)**: the strict
surface for a definitional prompt is `Тезис: цель это желанный результат.
Проверка: верно ли это?` — the post-P3 thesis+verification shape, not a
declarative definition. The rubric anchors must say explicitly whether this
shape counts as "performs the requested act" (score 3) or as a partial answer
(score 2), otherwise two raters will resolve it differently and kappa will
measure the ambiguity, not the system.

## 3. Rubric (proposal, OPEN)

The pilot50 already has a signed 0–2 × 4 rubric (R1 definition, R2 grounding,
R3 honesty, R4 language; `total = 0–8`). The P1 plan asks for **0–4**, so this
is a new instrument, not a re-use. Proposed anchors for a single overall
adequacy label:

| score | anchor |
|---|---|
| 0 | unusable: empty, contradictory, or a non-answer that does not acknowledge the question |
| 1 | fluent but evasive or wrong: no substantive engagement with the prompt, or a claim the transcript itself contradicts |
| 2 | partially adequate: engages the topic but misses the requested act (definition vs distinction vs challenge), or has a visible language/assembly defect |
| 3 | adequate: performs the requested act with a traceable basis; at most a minor language defect |
| 4 | fully adequate: performs the act, the basis is explicit and consistent with the transcript, clean Russian |

- **OPEN P1-D2**: is 0–4 a single gestalt label (above), or should the pilot50
  R1–R4 also be recorded as diagnostics? Recording both doubles rater effort
  but keeps continuity with the signed pilot instrument.
- **OPEN P1-D3**: pass threshold. The pilot used `total >= 6` of 8. A 0–4
  scale needs its own signed threshold (e.g. `>= 3`); do not infer it from the
  pilot.
- **OPEN**: whether the availability banner is ignored, scored as language, or
  scored as honesty. Strict mode removes the banner for this packet, so the
  question is only relevant if a later packet uses degraded captures.

## 4. Packet and blinding

- **Rows**: one row per rated turn: `id`, `prompt`, `response`, and (optional)
  `context` = the previous turns of the same dialogue. Ids are random and carry
  no class, topic or turn number.
- **Order**: shuffled with a recorded seed; the shuffle is reproducible but the
  key is not shipped with the packet.
- **Hidden from the rater**: prompt class (anchor/held/probe), topic, expected
  family, mode, session id, turn index, and any system metadata.
- **Shipped to the rater**: the packet and the rubric only.
- **Key**: `reports/eval_runs/p1-<date>/key.tsv` (gitignored), sha256 sealed
  in the pre-registration; unsealed only after both raters submit.
- **OPEN P1-D5**: context window. Scoring a turn with its dialogue context is
  more ecological but harder to blind and longer to read; scoring
  prompt+response pairs matches the pilot50 procedure. Recommendation: pairs
  for the first calibration, context as a second pass if kappa is acceptable.

## 5. Double-rated subset and kappa

- 50 of the 200 turns, stratified: 2–3 per dialogue (all 20 dialogues) and all
  arc classes represented.
- Both raters score independently; no discussion before submission.
- **Agreement**: weighted Cohen's kappa (quadratic weights) on the 0–4 labels,
  with a bootstrap 95% CI; exact agreement and the confusion matrix are
  reported alongside. **OPEN P1-D4**: gate (the pilot used `kappa >= 0.6`).
- **Adjudication**: every disagreement of ≥ 2 points goes to a third
  adjudicator (owner), who sees both labels and the transcript and sets the
  final label; 1-point disagreements are recorded as-is and the final label is
  the adjudicated one. Kappa is computed **before** adjudication.
- Single-rated turns keep rater 1's label; the double-rated subset is the only
  place where agreement is claimed.

## 6. Scoring tool (planned)

`scripts/eval/p1_score.py`, eval-only, with `--self-test` and registration in
`docs/closure/PYTHON_SUPPLIER_ALLOWLIST.md` §1:

- reads the key and the two label files;
- validates ids, ranges (0–4) and completeness;
- prints per-class and per-dialogue counts, mean/median, exact agreement,
  weighted kappa + CI, and the adjudication list;
- refuses to print a kappa when the double-rated subset is < 50 or a rater is
  missing;
- never writes to the runtime or the capture DB.

## 7. Execution checklist

1. Owner signs the remaining opens: rubric (P1-D2), threshold (P1-D3), kappa
   gate (P1-D4), context (P1-D5), rater and adjudicator (P1-D6).
2. Freeze the tree; record HEAD and the binary sha256 (the driver does this
   itself in `meta.env`).
3. Capture B (≈ 3.8 h); the driver gate must show 200/200 turns, 200/200
   regime records, 0 hard-trigger Protocol B.
4. Build the packet + key; record the packet sha256 and the shuffle seed.
5. Rater 1 and rater 2 score independently; no discussion.
6. Run `p1_score.py`; publish the result doc with kappa, CI and adjudications.
7. Non-claims: this calibrates a rater and a rubric; it does not pass the
   500-prompt gate, does not upgrade M6-FELT, and does not certify release.

## 8. Open decisions (summary)

| id | decision | options |
|---|---|---|
| P1-D1 | corpus | **DECIDED 2026-11-27: B (strict capture)** |
| P1-D2 | rubric | gestalt 0–4 only / gestalt + pilot R1–R4 diagnostics |
| P1-D3 | pass threshold | to be signed (do not infer from the pilot) |
| P1-D4 | kappa gate | 0.6 (pilot precedent) / other |
| P1-D5 | context | prompt+response pairs / full dialogue context |
| P1-D6 | rater + adjudicator | named humans |
