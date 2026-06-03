# Adaptive / Peripheral Authority Seam Inventory

Status: AS0 inventory and routing baseline
Purpose: make adaptive/peripheral authority seams explicit enough that future hardening work stops relying on memory or intuition.

---

## 1. Scope

This is an inventory and routing front, not a remediation rewrite.

It names the main adaptive/peripheral seams that can:
- mutate future state,
- affect output directly or indirectly,
- distort authority conclusions,
- or remain observational while still shaping later governance decisions.

It routes each seam to one target phase:
- `AS1` — pre-effect gating and external action integrity
- `AS2` — governed adaptation chain
- `AS3` — fault propagation coherence
- `AS4` — calibration/training realism

---

## 2. Seam Inventory

| seam_id | seam_name | mutates_future_state | affects_output | affects_authority_picture | current_status | target_phase | urgency | notes |
|---|---|---|---|---|---|---|---|---|
| `AS0-01` | external learning authority asymmetry | `yes` | `indirect` | `yes` | `partially_governed` | `AS2` | `high` | external learning can graft future knowledge through bounded parse→validate→sandbox→graft, but the asymmetry between external symbolic content and internal authority remains a persistent adaptation seam |
| `AS0-02` | request-driven external query vs guardrail pre-effect asymmetry | `yes` | `direct` | `yes` | `under_audit` | `AS1` | `high` | request-driven and exploratory queries are guarded, but the seam still exists between proposal intent, effect execution, and guardrail verdict timing |
| `AS0-03` | tool identity / reliability attribution split | `yes` | `indirect` | `yes` | `partially_governed` | `AS1` | `high` | tool reliability scores and external-tool identity shape whether external queries happen and how accepted results are interpreted |
| `AS0-04` | dialogue-development persistent heuristic mutation seam | `yes` | `indirect` | `yes` | `partially_governed` | `AS2` | `high` | `DialogueOutcomeLearning`, `SpeechPolicyState`, `BeliefStore`, and shared `AdaptiveMutationRecord` entries can alter future output style and stance without being central semantic authority |
| `AS0-05` | governance runtime fault propagation seam | `no` | `indirect` | `yes` | `under_audit` | `AS3` | `high` | `ssGovernanceRuntimeFault` is exposed in replay/state/introspection, but the full propagation discipline across runtime/health/readiness surfaces is still a coherence seam |
| `AS0-06` | runtime mode / readiness authority split | `no` | `indirect` | `yes` | `partially_governed` | `AS3` | `high` | strict/degraded runtime mode and readiness are typed and documented, but remain a peripheral authority seam because operator truth and runtime admissibility can diverge if propagation drifts |
| `AS0-07` | legal adapter output augmentation seam | `unknown` | `direct` | `yes` | `ungoverned` | `AS1` | `medium` | legal-adapter style augmentation is named in roadmap doctrine, but not yet strongly routed as a first-class governed output seam |
| `AS0-08` | calibration/training window and proxy-data seam | `yes` | `indirect` | `yes` | `partially_governed` | `AS4` | `medium` | offline calibration/training cycle is pure and bounded, but proxy semantics, window realism, and temporal scope still affect what future adaptation is considered justified |
| `AS0-09` | exploratory learning self-initiation seam | `yes` | `indirect` | `yes` | `partially_governed` | `AS2` | `medium` | autonomous exploratory queries are bounded and observable, but still represent self-initiated future-state mutation capability |
| `AS0-10` | adaptive mutation log as cross-contour accumulation seam | `yes` | `indirect` | `yes` | `partially_governed` | `AS2` | `medium` | the shared `ssAdaptiveMutationLog` aggregates heterogeneous future-state mutation records (calibration, learning, dialogue development, perspective), making it a seam between observability and governed adaptation |
| `AS0-11` | health vs restore truth mismatch seam | `unknown` | `none` | `yes` | `under_audit` | `AS3` | `medium` | persisted rebuild/readiness/restore truths can diverge in degraded or recovery states even when runtime remains operable |
| `AS0-12` | retrospective sample realism seam | `yes` | `none` | `yes` | `under_audit` | `AS4` | `medium` | training/evaluation windows, proxy corpora, and retrospective samples can bias what is later promoted as justified adaptation |
| `AS0-13` | tool selection threshold seam | `yes` | `indirect` | `yes` | `partially_governed` | `AS1` | `medium` | tool selection depends on reliability and guardrails; wrong thresholding can create effect-before-confidence asymmetry |
| `AS0-14` | observability-only Dream pressure seam | `no` | `indirect` | `yes` | `governed` | `AS2` | `low` | after `M4.5-S1..S4`, Dream pressure and candidate telemetry is explicit and bounded; this seam is now mostly governed but still belongs to the adaptive-peripheral map |
| `AS0-15` | perspective registry projection seam | `yes` | `indirect` | `yes` | `partially_governed` | `AS2` | `low` | perspective lineage is governed and replay-safe, but it remains a side seam that can shape future framing without being primary semantic authority |

---

## 3. Inventory Summary

### 3.1 Highest-priority mutation seams

- external learning authority asymmetry
- request-driven / exploratory external query vs guardrail pre-effect asymmetry
- dialogue-development persistent heuristic mutation seam
- adaptive mutation log as cross-contour accumulation seam
- calibration/training window and proxy-data seam

### 3.2 Highest-priority authority-distortion seams

- governance runtime fault propagation seam
- runtime mode / readiness authority split
- external learning authority asymmetry
- tool identity / reliability attribution split
- legal adapter output augmentation seam

### 3.3 Observational-only or mostly-governed seams

- observability-only Dream pressure seam
- perspective registry projection seam

These remain in the inventory because they still shape future-state interpretation,
but they are not the most urgent remediation targets.

---

## 4. Routing to AS1–AS4

### 4.1 AS1 — pre-effect gating and external action integrity

Recommended seams:
- `AS0-02` request-driven external query vs guardrail pre-effect asymmetry
- `AS0-03` tool identity / reliability attribution split
- `AS0-07` legal adapter output augmentation seam
- `AS0-13` tool selection threshold seam

Rationale:
- these seams all sit near outbound action/effect boundaries,
- and they can distort authority or output before a fully explicit governance step.

### 4.2 AS2 — governed adaptation chain

Recommended seams:
- `AS0-01` external learning authority asymmetry
- `AS0-04` dialogue-development persistent heuristic mutation seam
- `AS0-09` exploratory learning self-initiation seam
- `AS0-10` adaptive mutation log accumulation seam
- `AS0-14` Dream pressure/candidate seam (already mostly governed; keep as reference)
- `AS0-15` perspective projection seam

Rationale:
- these seams mutate future state or shape future behavior through adaptation-like channels.

### 4.3 AS3 — fault propagation coherence

Recommended seams:
- `AS0-05` governance runtime fault propagation seam
- `AS0-06` runtime mode / readiness authority split
- `AS0-11` health vs restore truth mismatch seam

Rationale:
- these seams are less about semantic mutation and more about whether the system
  reports its own degraded/ready/faulted condition honestly across surfaces.

### 4.4 AS4 — calibration/training realism

Recommended seams:
- `AS0-08` calibration/training window and proxy-data seam
- `AS0-12` retrospective sample realism seam

Rationale:
- these seams shape how later adaptation is justified, calibrated, and promoted.

---

## 5. Highest-Priority Seams

### 5.1 Top 3 by urgency

1. `AS0-02` request-driven external query vs guardrail pre-effect asymmetry
2. `AS0-05` governance runtime fault propagation seam
3. `AS0-04` dialogue-development persistent heuristic mutation seam

### 5.2 Top 3 by authority risk

1. `AS0-01` external learning authority asymmetry
2. `AS0-06` runtime mode / readiness authority split
3. `AS0-03` tool identity / reliability attribution split

---

## 6. Recommended Next Remediation Front

Recommended first activation:
- `AS1`

Reason:
- the most immediate high-risk seams are effect-boundary seams,
- especially where outbound query/action can occur under imperfect guardrail or
  tool-identity/reliability interpretation,
- and these can distort both output and authority perception before deeper
  adaptation-chain governance is even invoked.

Secondary follow-up after AS1:
- `AS3`

Reason:
- once pre-effect integrity is stronger, the next most important risk is whether
  runtime fault / readiness / restore truth propagate honestly across operator
  surfaces.

Then:
- `AS2`
- `AS4`

Reason:
- those are important, but they benefit from having pre-effect integrity and
  fault-propagation discipline in place first.

---

## 7. One-line Summary

AS0 makes the project’s adaptive/peripheral authority risks explicit and routable, so future seam hardening can proceed from a checked-in inventory instead of intuition or oral memory.
