# QxFx0 Dialogue Eval Report (200 Prompts)

## Metadata
- Date:
- Evaluator:
- Commit:
- Runtime mode: `strict` / `degraded`
- Environment profile:

## Summary Metrics
- Total prompts: `200`
- Intent fit count:
- Intent fit rate (`fit/200`):
- Fallback/template drift count:
- Fallback/template drift rate:
- Critical mismatch count:
- Critical mismatch rate:
- Morphology defects count:
- Worker/runtime critical errors count:

## Decision Thresholds
- `intent_fit_rate >= 0.85`
- `fallback_or_template_drift_rate <= 0.10`
- `critical_mismatch_rate <= 0.05`
- malformed morphology = `0` for pass

## Verdict
- Final verdict: `GO` / `NO-GO`
- Rationale (short):

## Family Coverage
- `CMContact`:
- `CMDescribe`:
- `CMDefine`:
- `CMPurpose`:
- `CMGround`:
- `CMReflect`:
- `CMDistinguish`:
- `CMRepair`:
- Other families:

## Must-Route Cases
- `как тебя зовут` -> expected family/intent:
- `кто ты` -> expected family/intent:
- `зачем ты тут` -> expected family/intent:
- `что такое X` -> expected family/intent:
- `как отличить X от Y` -> expected family/intent:
- `X от Y` entity extraction check (`ipfSemanticCandidates`): pass/fail

## Failure Clusters
1. Cluster:
- Symptoms:
- Sample prompt IDs:
- Severity (`P0/P1/P2`):
- Probable cause:
- Fix owner:

2. Cluster:
- Symptoms:
- Sample prompt IDs:
- Severity (`P0/P1/P2`):
- Probable cause:
- Fix owner:

3. Cluster:
- Symptoms:
- Sample prompt IDs:
- Severity (`P0/P1/P2`):
- Probable cause:
- Fix owner:

## Prompt-Level Log Table
Use one line per prompt.

| ID | Prompt | Expected family | Actual family | Intent fit (Y/N) | Fallback drift (Y/N) | Severity | Notes |
|---|---|---|---|---|---|---|---|
| 001 |  |  |  |  |  |  |  |
| 002 |  |  |  |  |  |  |  |
| 003 |  |  |  |  |  |  |  |
| ... |  |  |  |  |  |  |  |
| 200 |  |  |  |  |  |  |  |

## Action Plan (Post-Eval)
1. Blocking fixes required before next release:
- 

2. Non-blocking fixes (backlog):
- 

3. Re-run scope:
- full 200 prompts / targeted subset:

