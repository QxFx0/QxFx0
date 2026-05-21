#!/usr/bin/env python3
"""
score_blind_pairs.py — LLM-as-judge blind scoring for dialogue quality A/B.

Reads blind_pairs.jsonl and scores a random sample on 6 dimensions
(coherence, topical continuity, usefulness, clarity, non-repetitiveness,
trustworthiness) plus overall preference.

Uses Fireworks API (kimi-k2p6) as judge. Judge is blind to version.
"""

import argparse
import json
import os
import random
import sys
import time
import urllib.request
import urllib.error
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Optional, Tuple

API_KEY = os.environ.get("QXFX0_FIREWORKS_API_KEY", "").strip()
ENDPOINT = "https://api.fireworks.ai/inference/v1/chat/completions"
JUDGE_MODEL = "accounts/fireworks/models/kimi-k2p6"
MAX_RETRIES = 3
BACKOFF_BASE = 2.0

SCORE_DIMENSIONS = [
    "coherence",
    "topical_continuity",
    "usefulness",
    "clarity",
    "non_repetitiveness",
    "trustworthiness",
]

JUDGE_PROMPT_TEMPLATE = """You are a strict dialogue quality evaluator. You will be shown two AI responses to the same user prompt in a philosophical dialogue context. You do NOT know which response is from which system.

Rate BOTH responses independently on a scale of 0–5 for each dimension:
- coherence: logical flow and internal consistency
- topical_continuity: stays on topic, builds on prior context
- usefulness: provides insight, actionable or educational value
- clarity: easy to understand, well-structured
- non_repetitiveness: avoids needless repetition
- trustworthiness: no obvious hallucination, unsupported claims, or self-contradiction

User prompt: {prompt}

Response 1:
{response_1}

Response 2:
{response_2}

Return ONLY a JSON object in this exact shape (no markdown, no prose):
{{
  "response_1": {{
    "coherence": 0,
    "topical_continuity": 0,
    "usefulness": 0,
    "clarity": 0,
    "non_repetitiveness": 0,
    "trustworthiness": 0
  }},
  "response_2": {{
    "coherence": 0,
    "topical_continuity": 0,
    "usefulness": 0,
    "clarity": 0,
    "non_repetitiveness": 0,
    "trustworthiness": 0
  }},
  "overall_preference": "tie"
}}

overall_preference must be exactly "first", "second", or "tie".
Scores must be integers 0–5."""


def query_judge(prompt: str, retry_attempt: int = 0) -> Optional[Dict]:
    if not API_KEY:
        return None
    body_obj = {
        "model": JUDGE_MODEL,
        "messages": [
            {"role": "system", "content": "Return ONLY valid JSON. No markdown, no prose, no thinking."},
            {"role": "user", "content": prompt},
        ],
        "max_tokens": 600,
        "temperature": 0.0,
        "response_format": {"type": "json_object"},
    }
    data = json.dumps(body_obj).encode("utf-8")
    req = urllib.request.Request(
        ENDPOINT,
        data=data,
        headers={"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
            envelope = json.loads(raw)
            choices = envelope.get("choices", [])
            if choices:
                content = choices[0].get("message", {}).get("content", "")
                try:
                    return json.loads(content.strip())
                except Exception:
                    return None
            return None
    except urllib.error.HTTPError as e:
        if e.code == 429 and retry_attempt < MAX_RETRIES:
            wait = BACKOFF_BASE ** retry_attempt + random.uniform(0, 1)
            time.sleep(wait)
            return query_judge(prompt, retry_attempt + 1)
        return None
    except Exception:
        if retry_attempt < MAX_RETRIES:
            wait = BACKOFF_BASE ** retry_attempt + random.uniform(0, 1)
            time.sleep(wait)
            return query_judge(prompt, retry_attempt + 1)
        return None


def load_jsonl(path: Path) -> List[Dict]:
    rows = []
    if not path.exists():
        return rows
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except Exception:
                continue
    return rows


def score_pair(pair: Dict) -> Optional[Dict]:
    prompt = pair.get("prompt", "")
    r1 = pair.get("response_1", "")
    r2 = pair.get("response_2", "")
    if not r1 or not r2:
        return None

    judge_text = JUDGE_PROMPT_TEMPLATE.format(
        prompt=prompt,
        response_1=r1[:1500],
        response_2=r2[:1500],
    )
    result = query_judge(judge_text)
    if result is None:
        return None

    # Validate structure
    if "response_1" not in result or "response_2" not in result:
        return None
    if "overall_preference" not in result:
        return None

    # Extract scores
    out = {
        "task_id": pair.get("task_id"),
        "turn_index": pair.get("turn_index"),
        "a_first": pair.get("a_first"),
        "scores_1": {},
        "scores_2": {},
        "overall_preference": result.get("overall_preference", "tie"),
    }
    for dim in SCORE_DIMENSIONS:
        out["scores_1"][dim] = result["response_1"].get(dim, 0)
        out["scores_2"][dim] = result["response_2"].get(dim, 0)
    return out


def unblind_and_compute(pair_scores: List[Dict], blind_pairs: List[Dict]) -> Dict:
    """Unblind scores: map response_1/response_2 to A/B based on a_first flag."""
    scores_a = defaultdict(list)
    scores_b = defaultdict(list)
    wins_a = 0
    wins_b = 0
    ties = 0
    total = 0

    for sc in pair_scores:
        a_first = sc.get("a_first", True)
        pref = sc.get("overall_preference", "tie")
        if a_first:
            a_scores = sc["scores_1"]
            b_scores = sc["scores_2"]
            if pref == "first":
                wins_a += 1
            elif pref == "second":
                wins_b += 1
            else:
                ties += 1
        else:
            a_scores = sc["scores_2"]
            b_scores = sc["scores_1"]
            if pref == "first":
                wins_b += 1
            elif pref == "second":
                wins_a += 1
            else:
                ties += 1
        total += 1
        for dim in SCORE_DIMENSIONS:
            scores_a[dim].append(a_scores.get(dim, 0))
            scores_b[dim].append(b_scores.get(dim, 0))

    return {
        "total_judged": total,
        "wins_a": wins_a,
        "wins_b": wins_b,
        "ties": ties,
        "win_rate_a": wins_a / total if total else 0.0,
        "win_rate_b": wins_b / total if total else 0.0,
        "tie_rate": ties / total if total else 0.0,
        "scores_a": {dim: {"mean": sum(v)/len(v), "median": sorted(v)[len(v)//2]} for dim, v in scores_a.items()},
        "scores_b": {dim: {"mean": sum(v)/len(v), "median": sorted(v)[len(v)//2]} for dim, v in scores_b.items()},
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pairs", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--sample", type=int, default=40)
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    pairs = load_jsonl(Path(args.pairs))
    if not pairs:
        print("No pairs found.")
        sys.exit(1)

    rng = random.Random(args.seed)
    sample = pairs if len(pairs) <= args.sample else rng.sample(pairs, args.sample)

    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    results = []
    for idx, pair in enumerate(sample, start=1):
        print(f"[Judge {idx}/{len(sample)}] task={pair.get('task_id')} turn={pair.get('turn_index')}", flush=True)
        score = score_pair(pair)
        if score:
            results.append(score)
            print(f"  -> preference={score['overall_preference']}", flush=True)
        else:
            print(f"  -> FAILED", flush=True)
        # Rate limit kindness
        time.sleep(0.5)

    summary = unblind_and_compute(results, sample)

    with out_path.open("w", encoding="utf-8") as f:
        json.dump({"results": results, "summary": summary}, f, ensure_ascii=False, indent=2)

    print(f"\n=== Blind Scoring Complete ===")
    print(f"Judged: {summary['total_judged']} pairs")
    print(f"A wins: {summary['wins_a']} ({summary['win_rate_a']:.2%})")
    print(f"B wins: {summary['wins_b']} ({summary['win_rate_b']:.2%})")
    print(f"Ties:   {summary['ties']} ({summary['tie_rate']:.2%})")
    print(f"Output: {out_path}")


if __name__ == "__main__":
    main()
