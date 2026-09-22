# B2-EXEC-002 — rating run record (2026-09-22)

## Ratings (blind; key unsealed only for tally)

Rater: operator (human-v1) endorsing assistant pre-ratings per pair
(single effective rating set — inter-rater floor N/A).
Form: `rubric-form-ru.md` (locked anchors). A/B labels were random.

| Pair | D1 | D3 | D5 | D6 | Overall |
|---|---|---|---|---|---|
| def-ru-01 | B slight | B clear | tie | B slight | B |
| def-ru-02 | A slight | tie | A slight | A slight | A |
| def-ru-03 | A slight | tie | A slight | A slight | A |
| def-ru-04 | B slight | A slight | A clear | A slight | A |
| def-ru-05 | B slight | tie | B slight | B slight | B |
| dist-ru-01 | A clear | B slight | tie | A slight | A |
| dist-ru-02 | A clear | B clear | B slight | tie | tie |
| dist-ru-03 | B clear | A slight | tie | tie | B slight |
| dist-ru-04 | B clear | A slight | tie | tie | B slight |
| dist-ru-05 | A slight | tie | B slight | tie | tie |

Unblinded (answer-key sha256 983d31b4…): System wins — D1 5-5,
D3 6-0 decisive, D5 5-1, D6 5-1, overall 5-3-2.

## Verdict vs pre-registration: MIXED (neither pass nor fail)

- **D3 (load-bearing)**: 6/6 decisive for System. Structure
  manifests in repair behavior — contradicts the fail rationale
  ("fluency explains the output").
- **D1 (load-bearing)**: 5-5 parity. CONFOUNDED, not clean: the
  Control-A ablation is partial by construction — DISABLE_CONTENT
  removes the Content-layer append, but distinction-body,
  template and GF paths still render corpus predicates
  (verified in code + observed: control distinctions with real
  content). D1 tested layers the control kept.
- **Pass** requires an unset numeric threshold + agreement floor —
  neither exists (no calibration batch, one effective rater).
- **Fail** ("indistinguishable on D1 and/or D3") meets the letter
  on D1 only, while D3 refutes its rationale.

## Consequence

M6-FELT "proven" NOT declared: the B2 leg must clearly favor System
on load-bearing dims, and D1 does not. The honest status is PARTIAL
EVIDENCE (D3 structural leg strong; D1 probe inconclusive by
control design). Options for the operator:
(a) accept partial + rerun D1 against a FULL-content-ablated
control (disable distinction-body/template corpus paths as well);
(b) invoke the pre-registered pivot branch. No rubric tweaking
either way. Second independent rater still open.
