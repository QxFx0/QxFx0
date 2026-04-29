# Dialogue Eval Run 001

## Goal
Run a semi-automatic 200-prompt evaluation and generate machine-readable metrics plus a short Go/No-Go summary.

## Inputs
- Prompt file: `reports/dialogue_eval_200_prompts.tsv`
- Runner: `scripts/run_dialogue_eval_200.sh`

## Step 1: Baseline Gates
```bash
cabal test qxfx0-test -v0
bash scripts/verify.sh
bash scripts/release-smoke.sh
```

## Step 2: Execute Eval-200
Default run id: `run_001`.
By default, runner uses `isolated` session mode (one session per prompt) for clean intent evaluation.

```bash
bash scripts/run_dialogue_eval_200.sh run_001 reports/dialogue_eval_200_prompts.tsv
```

If strict runtime is available in this environment:
```bash
QXFX0_RUNTIME_MODE=strict bash scripts/run_dialogue_eval_200.sh run_001 reports/dialogue_eval_200_prompts.tsv
```

If strict runtime is blocked by environment constraints:
```bash
QXFX0_RUNTIME_MODE=degraded bash scripts/run_dialogue_eval_200.sh run_001 reports/dialogue_eval_200_prompts.tsv
```

If you explicitly want shared dialogue-context evaluation:
```bash
QXFX0_EVAL_SESSION_MODE=shared bash scripts/run_dialogue_eval_200.sh run_001 reports/dialogue_eval_200_prompts.tsv
```

## Step 3: Output Artifacts
- `reports/eval_runs/run_001/results.jsonl`
- `reports/eval_runs/run_001/summary.json`
- `reports/eval_runs/run_001/summary.md`
- `reports/eval_runs/run_001/raw/*.log`

## Step 4: Fill Final Human Report
Open template and copy computed metrics:
- `reports/dialogue_eval_200_template.md`

Then set:
- `Intent fit count/rate`
- `Fallback/template drift count/rate`
- `Critical mismatch count/rate`
- `Morphology defects count`
- final `GO/NO-GO`.

## Prompt File Format
Tab-separated (`.tsv`):
```text
id<TAB>prompt<TAB>expected_family
```
Example:
```text
001	как тебя зовут?	CMDescribe
002	что такое свобода?	CMDefine
003	зачем ты тут?	CMPurpose
```

`expected_family` can be blank for exploratory prompts, but then `intent_fit_rate` is computed only on rows where expected family is set.
