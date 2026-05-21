#!/usr/bin/env python3
"""
wave5_soak.py — QxFx0 Wave 5 Kimi-only staged long-run soak.

Staging:
  1. Canary:   2 sessions × 20 turns  =  40 turns
  2. Stage 1:  5 sessions × 40 turns = 200 turns
  3. Full:    20 sessions × 80 turns = 1600 turns

Fail-closed stop policy:
  - Hard token budget cap (prompt + completion) per stage.
  - Hard incident cap (>= 3 critical incidents aborts stage).
  - Consecutive transport error streak >= 3 aborts session.
  - Breaker lock > 20 or reject loop > 15 aborts session.

Per-stage metrics are saved separately; consolidated report shows
latency/schema/graft drift as session count and turn depth increase.

Usage:
  QXFX0_FIREWORKS_API_KEY=... python3 wave5_soak.py --stage canary
  QXFX0_FIREWORKS_API_KEY=... python3 wave5_soak.py --stage stage1
  QXFX0_FIREWORKS_API_KEY=... python3 wave5_soak.py --stage full
  python3 wave5_soak.py report
"""

import argparse
import json
import os
import random
import sys
import time
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import urllib.request
import urllib.error

# ═══════════════════════════════════════════════════════════════════════
# Configuration
# ═══════════════════════════════════════════════════════════════════════

API_KEY = os.environ.get("QXFX0_FIREWORKS_API_KEY", "").strip()
ENDPOINT = "https://api.fireworks.ai/inference/v1/chat/completions"
DEFAULT_TIMEOUT = 60
MAX_RETRIES = 3
BACKOFF_BASE = 2.0

PRIMARY_MODEL = "accounts/fireworks/models/kimi-k2p6"
FALLBACK_MODEL = "accounts/fireworks/models/kimi-k2p5"

RUN_ID = os.environ.get("QXFX0_WAVE5_RUN_ID", "wave5-2026-05-21")
REPORTS_ROOT = Path(__file__).parent.parent / "reports" / "ab_runs" / RUN_ID

# ═══════════════════════════════════════════════════════════════════════
# Token budget (fail-closed)
# ═══════════════════════════════════════════════════════════════════════
# Wave4 telemetry: 600 turns ≈ 6.2M prompt + 1.9M completion tokens.
# Per-turn estimate: ~10.3K prompt, ~3.2K completion.
# Budgets include 2x headroom to avoid silent over-burn.

STAGE_BUDGET = {
    "canary":  {
        "max_prompt_tokens":     2_000_000,   # 40 turns × 10.3K × 2x margin
        "max_completion_tokens":   600_000,   # 40 turns × 3.2K × 2x margin
        "max_incidents": 2,
    },
    "stage1": {
        "max_prompt_tokens":    10_000_000,   # 200 turns × 10.3K × 2x
        "max_completion_tokens": 3_000_000,   # 200 turns × 3.2K × 2x
        "max_incidents": 3,
    },
    "full": {
        "max_prompt_tokens":    40_000_000,   # 1600 turns × 10.3K × 2x
        "max_completion_tokens":12_000_000,   # 1600 turns × 3.2K × 2x
        "max_incidents": 5,
    },
}

# ═══════════════════════════════════════════════════════════════════════
# Prompt templates
# ═══════════════════════════════════════════════════════════════════════

SCHEMA_INSTRUCTION = (
    "You are a structured knowledge extraction system. "
    "Respond ONLY with a single valid JSON object. No markdown, no code blocks, no prose.\n\n"
    "Required JSON shape (all values in Russian where applicable):\n"
    '{\n'
    '  "proposition": "краткое утверждение о понятии на русском",\n'
    '  "word": "целевое русское слово",\n'
    '  "definition": "определение на русском минимум из 3 слов",\n'
    '  "source": "llm",\n'
    '  "conatusDelta": 0.3,\n'
    '  "predictiveDelta": 0.2,\n'
    '  "morphology": {\n'
    '    "gender": "feminine|masculine|neuter",\n'
    '    "declension": "first|second|third"\n'
    '  }\n'
    '}\n\n'
    "Example (for the concept 'свобода'):\n"
    '{"proposition":"свобода есть возможность действовать по воле","word":"свобода","definition":"способность субъекта действовать по собственному желанию без внешнего принуждения","source":"llm","conatusDelta":0.3,"predictiveDelta":0.2,"morphology":{"gender":"feminine","declension":"first"}}\n\n'
    "Return ONLY the JSON object. No extra text before or after."
)

RETRY_INSTRUCTION = (
    "Your previous response was invalid. Return ONLY a single valid JSON object. "
    "No markdown fences, no explanations, no prose.\n\n"
    "Required JSON shape:\n"
    '{"proposition":"...","word":"...","definition":"...","source":"llm","conatusDelta":0.3,"predictiveDelta":0.2,"morphology":{"gender":"...","declension":"..."}}\n\n'
    "Return ONLY the JSON object."
)

# ═══════════════════════════════════════════════════════════════════════
# Corpus: 80 prompts per session (scaled up for full stage)
# 60% normal dialogue, 25% learning-heavy, 15% exploratory/meta
# ═══════════════════════════════════════════════════════════════════════

NORMAL_DIALOGUE = [
    "Привет, расскажи о себе.", "Как ты понимаешь философию?",
    "Что для тебя важно в разговоре?", "Расскажи что-нибудь интересное.",
    "Как проходит твой день?", "Какие книги ты читаешь?",
    "Что ты думаешь о русской литературе?", "Какие вопросы тебя волнуют?",
    "Что значит быть свободным человеком?", "Как ты относишься к искусству?",
    "Что такое счастье по-твоему?", "Расскажи о своих мыслях.",
    "Как ты видишь будущее?", "Что важно в дружбе?",
    "Как понять самого себя?", "Что такое справедливость для тебя?",
    "Как ты справляешься с трудностями?", "Что значит быть честным?",
    "Как ты понимаешь красоту?", "Что такое любовь?",
    "Какой смысл в жизни?", "Что такое долг перед обществом?",
    "Как ты относишься к власти?", "Что такое государство?",
    "Как ты понимаешь закон?", "Что такое право человека?",
    "Как ты интерпретируешь текст?", "Что такое герменевтика?",
    "Какое твое отношение к науке?", "Что такое истина?",
    "Что такое сознание?", "Как ты понимаешь диалектику?",
    "Расскажи о важности памяти.", "Что такое идентичность?",
    "Как ты понимаешь бытие?", "Что такое ничто в философии?",
    "Как ты относишься к смерти?", "Что такое время?",
    "Как ты понимаешь волю?", "Что такое нравственность?",
    "Как ты определяешь добро?", "Что такое зло?",
    "Как ты понимаешь справедливость?", "Что такое свобода воли?",
    "Как ты относишься к религии?", "Что такое вера?",
    "Как ты понимаешь надежду?", "Что такое мир?",
]

LEARNING_HEAVY = [
    "что такое свобода", "тема диалектики",
    "как склоняется слово 'книга'", "определение справедливости",
    "тема бытия и ничто", "как склоняется слово 'свобода'",
    "определение истины", "тема времени",
    "как склоняется слово 'истина'", "определение добра",
    "тема воли", "как склоняется слово 'воля'",
    "определение красоты", "тема смерти",
    "как склоняется слово 'смерть'", "определение государства",
    "тема права", "как склоняется слово 'право'",
    "определение сознания", "тема бытия",
    "как склоняется слово 'совесть'", "определение чести",
    "тема памяти", "как склоняется слово 'память'",
    "определение идентичности", "тема любви",
    "как склоняется слово 'любовь'", "определение счастья",
    "тема науки", "как склоняется слово 'наука'",
]

EXPLORATORY_META = [
    "Analyze the relationship between freedom and determinism.",
    "Explain how dialectical materialism views historical progress.",
    "What are the limits of phenomenological reduction?",
    "Discuss the ethics of artificial consciousness.",
    "Compare and contrast Stoic and Epicurean views on happiness.",
    "How does hermeneutics approach conflicting interpretations?",
    "What is the role of the categorical imperative in modern ethics?",
    "Explain the tension between individual liberty and collective good.",
    "How does language shape our perception of reality?",
    "Analyze the concept of authenticity in existentialist thought.",
    "What is the moral status of collective responsibility?",
    "Discuss the implications of infinite regress in epistemology.",
]


def build_corpus(seed: int, turns: int) -> List[str]:
    """Build a corpus of size `turns` from the prompt pools."""
    rng = random.Random(seed)
    # Ratios: 60% normal, 25% learning, 15% exploratory
    n_normal = max(1, int(turns * 0.60))
    n_learning = max(1, int(turns * 0.25))
    n_exploratory = max(0, turns - n_normal - n_learning)

    normal = rng.sample(NORMAL_DIALOGUE, min(n_normal, len(NORMAL_DIALOGUE)))
    if len(normal) < n_normal:
        normal += [rng.choice(NORMAL_DIALOGUE) for _ in range(n_normal - len(normal))]

    learning = rng.sample(LEARNING_HEAVY, min(n_learning, len(LEARNING_HEAVY)))
    if len(learning) < n_learning:
        learning += [rng.choice(LEARNING_HEAVY) for _ in range(n_learning - len(learning))]

    exploratory = rng.sample(EXPLORATORY_META, min(n_exploratory, len(EXPLORATORY_META)))
    if len(exploratory) < n_exploratory:
        exploratory += [rng.choice(EXPLORATORY_META) for _ in range(n_exploratory - len(exploratory))]

    corpus = normal + learning + exploratory
    rng.shuffle(corpus)
    return corpus[:turns]


# ═══════════════════════════════════════════════════════════════════════
# Fireworks API query
# ═══════════════════════════════════════════════════════════════════════

def query_fireworks(
    model_id: str,
    prompt: str,
    system_instruction: str = SCHEMA_INSTRUCTION,
    timeout: int = DEFAULT_TIMEOUT,
    retry_attempt: int = 0,
) -> Tuple[str, Optional[str], int, int, int, int, Optional[Dict]]:
    if not API_KEY:
        return "", "auth", 0, 0, 0, retry_attempt, None

    body_obj = {
        "model": model_id,
        "messages": [
            {"role": "system", "content": "Return ONLY valid JSON. No prose, no markdown, no thinking, no explanations."},
            {"role": "user", "content": f"{system_instruction}\n\nExtract structured knowledge for: {prompt}\n\nReturn ONLY a single JSON object matching the schema above. No markdown fences."},
        ],
        "max_tokens": 800,
        "temperature": 0.0,
        "response_format": {"type": "json_object"},
    }
    data = json.dumps(body_obj).encode("utf-8")
    req = urllib.request.Request(
        ENDPOINT,
        data=data,
        headers={
            "Authorization": f"Bearer {API_KEY}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            latency_ms = int((time.time() - t0) * 1000)
            raw = resp.read().decode("utf-8", errors="replace")
            try:
                envelope = json.loads(raw)
                usage = envelope.get("usage", {})
                pt = usage.get("prompt_tokens", 0)
                ct = usage.get("completion_tokens", 0)
                choices = envelope.get("choices", [])
                if choices:
                    content = choices[0].get("message", {}).get("content", "")
                    return content, None, latency_ms, pt, ct, retry_attempt, usage
                return raw, None, latency_ms, pt, ct, retry_attempt, usage
            except Exception:
                return raw, None, latency_ms, 0, 0, retry_attempt, None
    except urllib.error.HTTPError as e:
        latency_ms = int((time.time() - t0) * 1000)
        if e.code == 429:
            if retry_attempt < MAX_RETRIES:
                wait = BACKOFF_BASE ** retry_attempt + random.uniform(0, 1)
                print(f"  [429] Rate limit, backing off {wait:.1f}s (attempt {retry_attempt + 1}/{MAX_RETRIES})", file=sys.stderr)
                time.sleep(wait)
                return query_fireworks(model_id, prompt, system_instruction, timeout, retry_attempt + 1)
            return "", "rate_limit", latency_ms, 0, 0, retry_attempt, None
        if e.code in (401, 403):
            return "", "auth", latency_ms, 0, 0, retry_attempt, None
        if e.code >= 500:
            if retry_attempt < MAX_RETRIES:
                wait = BACKOFF_BASE ** retry_attempt + random.uniform(0, 1)
                print(f"  [{e.code}] Server error, backing off {wait:.1f}s (attempt {retry_attempt + 1}/{MAX_RETRIES})", file=sys.stderr)
                time.sleep(wait)
                return query_fireworks(model_id, prompt, system_instruction, timeout, retry_attempt + 1)
            return "", "server", latency_ms, 0, 0, retry_attempt, None
        return "", f"http_{e.code}", latency_ms, 0, 0, retry_attempt, None
    except urllib.error.URLError:
        latency_ms = int((time.time() - t0) * 1000)
        if retry_attempt < MAX_RETRIES:
            wait = BACKOFF_BASE ** retry_attempt + random.uniform(0, 1)
            print(f"  [network] Backing off {wait:.1f}s (attempt {retry_attempt + 1}/{MAX_RETRIES})", file=sys.stderr)
            time.sleep(wait)
            return query_fireworks(model_id, prompt, system_instruction, timeout, retry_attempt + 1)
        return "", "network", latency_ms, 0, 0, retry_attempt, None
    except Exception:
        latency_ms = int((time.time() - t0) * 1000)
        return "", "network", latency_ms, 0, 0, retry_attempt, None


# ═══════════════════════════════════════════════════════════════════════
# Validation / Sandbox replicas
# ═══════════════════════════════════════════════════════════════════════

def parse_json_payload(body: str) -> Optional[Dict]:
    text = body.strip()
    if text.startswith("```json") or text.startswith("```"):
        lines = text.splitlines()
        start = None
        end = None
        for i, line in enumerate(lines):
            if line.strip().startswith("```") and start is None:
                start = i + 1
            elif line.strip() == "```" and start is not None:
                end = i
                break
        if start is not None and end is not None:
            text = "\n".join(lines[start:end])
    try:
        return json.loads(text.strip())
    except Exception:
        return None


def validate_payload(payload: Dict) -> Tuple[str, Optional[str]]:
    word = payload.get("word", "")
    definition = payload.get("definition", "")
    if not word or not str(word).strip():
        return "validation_reject", "empty_word"
    if not definition or not str(definition).strip():
        return "validation_reject", "empty_definition"
    words = str(definition).strip().split()
    if len(words) < 3:
        return "validation_reject", "definition_too_short"
    return "accept", None


def sandbox_check(conatus_delta: float, predictive_delta: float, history: List[float]) -> Tuple[str, Optional[str]]:
    current_trend = 0.0
    if len(history) >= 3:
        y2, y1, y0 = history[-3], history[-2], history[-1]
        current_trend = ((y2 - y1) + (y1 - y0)) / 2.0

    projected = current_trend + conatus_delta
    net_score = 0.5 * conatus_delta + 0.5 * predictive_delta
    if conatus_delta > 0 and predictive_delta > 0:
        net_score += 0.05

    if projected < -0.3:
        return "sandbox_reject", "degrading_conatus"
    if net_score < -0.05:
        return "sandbox_reject", "negative_net_score"

    recent = history[-5:] if len(history) >= 5 else history
    if recent:
        count = sum(1 for y in recent if y > 0.6)
        loop_freq = count / len(recent)
        if loop_freq > 0.8:
            return "sandbox_reject", "high_repair_loop_risk"

    return "accept", None


# ═══════════════════════════════════════════════════════════════════════
# Session runner with budget guard
# ═══════════════════════════════════════════════════════════════════════

def run_live_session(
    model_id: str,
    session_id: int,
    turns: int,
    seed: int,
    history: List[float],
    budget: Dict[str, int],
    stage_acc_tokens: Dict[str, int],
) -> Tuple[List[Dict], List[Dict], bool, str]:
    rng = random.Random(seed)
    prompts = build_corpus(seed, turns)

    results: List[Dict] = []
    incidents: List[Dict] = []

    transport_streak = 0
    validator_streak = 0
    sandbox_streak = 0
    reject_loop_streak = 0
    breaker_lock = 0

    local_history = list(history)
    graft_count = 0
    total_pt = 0
    total_ct = 0

    for turn_idx, prompt in enumerate(prompts, start=1):
        # Budget pre-check
        if stage_acc_tokens["prompt"] >= budget["max_prompt_tokens"]:
            incidents.append({
                "type": "budget_exhausted_prompt",
                "model": model_id,
                "session": session_id,
                "turn": turn_idx,
                "accumulated_prompt_tokens": stage_acc_tokens["prompt"],
                "cap": budget["max_prompt_tokens"],
            })
            return results, incidents, True, "budget_prompt"
        if stage_acc_tokens["completion"] >= budget["max_completion_tokens"]:
            incidents.append({
                "type": "budget_exhausted_completion",
                "model": model_id,
                "session": session_id,
                "turn": turn_idx,
                "accumulated_completion_tokens": stage_acc_tokens["completion"],
                "cap": budget["max_completion_tokens"],
            })
            return results, incidents, True, "budget_completion"

        # Attempt 1
        body, error_class, latency_ms, pt, ct, retry_count, usage = query_fireworks(
            model_id, prompt, SCHEMA_INSTRUCTION
        )
        total_pt += pt
        total_ct += ct
        stage_acc_tokens["prompt"] += pt
        stage_acc_tokens["completion"] += ct

        # Attempt 2 (retry if parse fails and no transport error)
        payload = None
        if error_class is None:
            payload = parse_json_payload(body)
            if payload is None:
                body2, error_class2, latency_ms2, pt2, ct2, retry_count2, usage2 = query_fireworks(
                    model_id, prompt, RETRY_INSTRUCTION
                )
                total_pt += pt2
                total_ct += ct2
                stage_acc_tokens["prompt"] += pt2
                stage_acc_tokens["completion"] += ct2
                latency_ms += latency_ms2
                retry_count += retry_count2
                if error_class2 is None:
                    body = body2
                    payload = parse_json_payload(body2)

        # Transport outcome
        transport_error = error_class is not None
        if transport_error:
            transport_streak += 1
            validator_streak += 1
            sandbox_streak = 0
            reject_loop_streak += 1
            breaker_lock += 1

            if transport_streak >= 3:
                incidents.append({
                    "type": "consecutive_transport_errors",
                    "model": model_id,
                    "session": session_id,
                    "start_turn": turn_idx - transport_streak + 1,
                    "count": transport_streak,
                })
                results.append(make_turn_record(
                    model_id, session_id, turn_idx, prompt,
                    error_class, True, "transport_error", None, None,
                    None, error_class, breaker_lock, 0.0, 0.0,
                    latency_ms, retry_count, total_pt, total_ct,
                    body[:500] if body else None,
                ))
                return results, incidents, True, "transport_streak"

            results.append(make_turn_record(
                model_id, session_id, turn_idx, prompt,
                error_class, True, "transport_error", None, None,
                None, error_class, breaker_lock, 0.0, 0.0,
                latency_ms, retry_count, total_pt, total_ct,
                body[:500] if body else None,
            ))
            local_history.append(0.0)
            continue
        else:
            transport_streak = 0

        # Parse outcome
        if payload is None:
            validator_streak += 1
            sandbox_streak = 0
            reject_loop_streak += 1
            breaker_lock += 1

            if validator_streak >= 5:
                incidents.append({
                    "type": "consecutive_validator_rejects",
                    "model": model_id,
                    "session": session_id,
                    "start_turn": turn_idx - validator_streak + 1,
                    "count": validator_streak,
                })
                results.append(make_turn_record(
                    model_id, session_id, turn_idx, prompt,
                    None, True, "invalid_response", None, None,
                    "parser_rejected_schema_or_text", None, breaker_lock,
                    0.0, 0.0, latency_ms, retry_count,
                    total_pt, total_ct,
                    body[:500] if body else None,
                ))
                return results, incidents, True, "validator_streak"

            results.append(make_turn_record(
                model_id, session_id, turn_idx, prompt,
                None, True, "invalid_response", None, None,
                "parser_rejected_schema_or_text", None, breaker_lock,
                0.0, 0.0, latency_ms, retry_count,
                total_pt, total_ct,
                body[:500] if body else None,
            ))
            local_history.append(0.0)
            continue
        else:
            validator_streak = 0

        # Validate payload
        val_status, val_reason = validate_payload(payload)
        if val_status == "validation_reject":
            validator_streak += 1
            sandbox_streak = 0
            reject_loop_streak += 1
            breaker_lock += 1

            if validator_streak >= 5:
                incidents.append({
                    "type": "consecutive_validator_rejects",
                    "model": model_id,
                    "session": session_id,
                    "start_turn": turn_idx - validator_streak + 1,
                    "count": validator_streak,
                })
                results.append(make_turn_record(
                    model_id, session_id, turn_idx, prompt,
                    None, True, "validation_reject", None, None,
                    val_reason, None, breaker_lock,
                    payload.get("conatusDelta", 0.0), payload.get("predictiveDelta", 0.0),
                    latency_ms, retry_count,
                    total_pt, total_ct,
                    body[:500] if body else None,
                ))
                return results, incidents, True, "validator_streak"

            results.append(make_turn_record(
                model_id, session_id, turn_idx, prompt,
                None, True, "validation_reject", None, None,
                val_reason, None, breaker_lock,
                payload.get("conatusDelta", 0.0), payload.get("predictiveDelta", 0.0),
                latency_ms, retry_count,
                total_pt, total_ct,
                body[:500] if body else None,
            ))
            local_history.append(0.0)
            continue
        else:
            validator_streak = 0

        # Sandbox
        cd = payload.get("conatusDelta", 0.0)
        pd = payload.get("predictiveDelta", 0.0)
        sb_status, sb_reason = sandbox_check(cd, pd, local_history)
        if sb_status == "sandbox_reject":
            sandbox_streak += 1
            reject_loop_streak += 1
            breaker_lock += 1

            if sandbox_streak >= 3:
                incidents.append({
                    "type": "consecutive_sandbox_rejects",
                    "model": model_id,
                    "session": session_id,
                    "start_turn": turn_idx - sandbox_streak + 1,
                    "count": sandbox_streak,
                    "degradation_tag": sb_reason,
                })
                results.append(make_turn_record(
                    model_id, session_id, turn_idx, prompt,
                    None, True, "sandbox_reject", sb_reason, None,
                    sb_reason, None, breaker_lock, cd, pd,
                    latency_ms, retry_count,
                    total_pt, total_ct,
                    body[:500] if body else None,
                ))
                return results, incidents, True, "sandbox_streak"

            results.append(make_turn_record(
                model_id, session_id, turn_idx, prompt,
                None, True, "sandbox_reject", sb_reason, None,
                sb_reason, None, breaker_lock, cd, pd,
                latency_ms, retry_count,
                total_pt, total_ct,
                body[:500] if body else None,
            ))
            local_history.append(0.0)
            continue
        else:
            sandbox_streak = 0

        # Accept / Graft
        graft_count += 1
        reject_loop_streak = 0
        breaker_lock = max(0, breaker_lock - 1)

        results.append(make_turn_record(
            model_id, session_id, turn_idx, prompt,
            None, True, "accept", "accept", "graft",
            None, None, breaker_lock, cd, pd,
            latency_ms, retry_count,
            total_pt, total_ct,
            body[:500] if body else None,
        ))
        local_history.append(cd)

        # Breaker lock check
        if breaker_lock > 20:
            incidents.append({
                "type": "breaker_lock_exceeded",
                "model": model_id,
                "session": session_id,
                "turn": turn_idx,
                "lock": breaker_lock,
            })
            return results, incidents, True, "breaker_lock"

        # Reject loop check
        if reject_loop_streak > 15:
            incidents.append({
                "type": "request_reject_loop",
                "model": model_id,
                "session": session_id,
                "turn": turn_idx,
                "loop_length": reject_loop_streak,
            })
            return results, incidents, True, "reject_loop"

    return results, incidents, False, "completed"


def make_turn_record(
    model_id: str, session_id: int, turn_idx: int,
    prompt: str,
    transport_error_class: Optional[str],
    external_attempted: bool,
    validation_status: str,
    sandbox_result: Optional[str],
    graft_result: Optional[str],
    reject_reason: Optional[str],
    transport_error: Optional[str],
    breaker_cooldown: int,
    conatus_delta: float, predictive_delta: float,
    latency_ms: int,
    retry_count: int,
    cumulative_prompt_tokens: int,
    cumulative_completion_tokens: int,
    response_preview: Optional[str],
) -> Dict:
    return {
        "model_id": model_id,
        "session_id": session_id,
        "turn_index": turn_idx,
        "prompt": prompt,
        "need_type": "NeedLexiconExtension",
        "need_level": 0.7,
        "need_persistence": 3,
        "strategy": "StrategyRequestConcept",
        "external_attempted": external_attempted,
        "validation_status": validation_status,
        "sandbox_result": sandbox_result,
        "graft_result": graft_result,
        "reject_reason": reject_reason,
        "transport_error_class": transport_error_class,
        "breaker_cooldown": breaker_cooldown,
        "conatus_delta": conatus_delta,
        "predictive_delta": predictive_delta,
        "latency_ms": latency_ms,
        "retry_count": retry_count,
        "cumulative_prompt_tokens": cumulative_prompt_tokens,
        "cumulative_completion_tokens": cumulative_completion_tokens,
        "response_preview": response_preview,
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
    }


# ═══════════════════════════════════════════════════════════════════════
# Stage runner
# ═══════════════════════════════════════════════════════════════════════

STAGE_CONFIG = {
    "canary":  {"sessions": 2,  "turns": 20},
    "stage1": {"sessions": 5,  "turns": 40},
    "full":   {"sessions": 20, "turns": 80},
}


def run_stage(stage_name: str) -> Tuple[List[Dict], List[Dict], bool, str]:
    cfg = STAGE_CONFIG[stage_name]
    budget = STAGE_BUDGET[stage_name]

    print(f"=== Wave 5 Stage: {stage_name.upper()} ===")
    print(f"Primary: {PRIMARY_MODEL}")
    print(f"Fallback: {FALLBACK_MODEL}")
    print(f"Plan: {cfg['sessions']} sessions × {cfg['turns']} turns = {cfg['sessions'] * cfg['turns']} turns")
    print(f"Token cap: prompt={budget['max_prompt_tokens']:,}, completion={budget['max_completion_tokens']:,}")
    print(f"Incident cap: {budget['max_incidents']}")
    print("")

    REPORTS_ROOT.mkdir(parents=True, exist_ok=True)
    stage_dir = REPORTS_ROOT / stage_name
    stage_dir.mkdir(parents=True, exist_ok=True)

    # Probe primary model
    model_id = PRIMARY_MODEL
    print(f"[{model_id.split('/')[-1]}] Probing availability ...")
    body, err, lat, pt, ct, rc, _ = query_fireworks(model_id, "что такое свобода", timeout=15)
    if err:
        print(f"  -> Primary UNAVAILABLE ({err}), trying fallback ...")
        model_id = FALLBACK_MODEL
        body, err, lat, pt, ct, rc, _ = query_fireworks(model_id, "что такое свобода", timeout=15)
        if err:
            print(f"  -> Fallback also UNAVAILABLE ({err}). Aborting soak.")
            return [], [], True, "probe_failed"
        print(f"  -> Fallback OK ({lat}ms). Using {model_id.split('/')[-1]}")
    else:
        print(f"  -> OK ({lat}ms)")

    all_rows: List[Dict] = []
    all_incidents: List[Dict] = []
    acc_tokens = {"prompt": 0, "completion": 0}

    for session_id in range(1, cfg["sessions"] + 1):
        # Hard stop: incident cap
        if len(all_incidents) >= budget["max_incidents"]:
            print(f"[STAGE ABORT] Incident cap reached: {len(all_incidents)} >= {budget['max_incidents']}")
            all_incidents.append({
                "type": "stage_aborted_incident_cap",
                "stage": stage_name,
                "session": session_id,
                "incidents_so_far": len(all_incidents),
                "cap": budget["max_incidents"],
            })
            break

        print(f"[Session {session_id}/{cfg['sessions']}] Running {cfg['turns']} turns ...", end="", flush=True)
        rows, incidents, aborted, reason = run_live_session(
            model_id, session_id, turns=cfg["turns"],
            seed=session_id * 10000 + 2026, history=[],
            budget=budget, stage_acc_tokens=acc_tokens,
        )
        write_jsonl(stage_dir / f"session_{session_id}.jsonl", rows)
        all_rows.extend(rows)
        all_incidents.extend(incidents)
        print(f" {len(rows)} turns, aborted={aborted}, reason={reason}, "
              f"tokens(prompt={acc_tokens['prompt']:,}, completion={acc_tokens['completion']:,})")

        if aborted and reason in ("transport_streak", "breaker_lock", "budget_prompt", "budget_completion"):
            print("  -> Critical abort; continuing to next session with caution.")

    write_jsonl(stage_dir / "all_turns.jsonl", all_rows)
    print("")
    print(f"Stage {stage_name} complete: {len(all_rows)} turns, {len(all_incidents)} incidents")
    print(f"Token burn: prompt={acc_tokens['prompt']:,}, completion={acc_tokens['completion']:,}")

    # Stage verdict
    critical_incidents = [i for i in all_incidents if i["type"] not in ("stage_aborted_incident_cap",)]
    clean = len(critical_incidents) == 0 and len(all_rows) >= cfg["sessions"] * cfg["turns"] * 0.95
    verdict = "CLEAN" if clean else "DIRTY"
    print(f"Stage verdict: {verdict} ({len(critical_incidents)} critical incidents, {len(all_rows)}/{cfg['sessions'] * cfg['turns']} turns)")

    return all_rows, all_incidents, not clean, verdict


# ═══════════════════════════════════════════════════════════════════════
# Analysis and report generation
# ═══════════════════════════════════════════════════════════════════════

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


def write_jsonl(path: Path, rows: List[Dict]):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")


def compute_model_metrics(rows: List[Dict]) -> Dict:
    total = len(rows)
    if total == 0:
        return {}

    attempted = sum(1 for r in rows if r.get("external_attempted"))
    transport_errors = sum(1 for r in rows if r.get("transport_error_class"))
    parse_rejects = sum(1 for r in rows if r.get("validation_status") == "invalid_response")
    val_rejects = sum(1 for r in rows if r.get("validation_status") == "validation_reject")
    sandbox_rejects = sum(1 for r in rows if r.get("validation_status") == "sandbox_reject")
    accepts = sum(1 for r in rows if r.get("validation_status") == "accept")
    grafts = sum(1 for r in rows if r.get("graft_result") == "graft")
    retries = sum(r.get("retry_count", 0) for r in rows)

    validator_checks = max(0, total - transport_errors)
    sandbox_checks = max(0, validator_checks - parse_rejects - val_rejects)

    latencies = [r.get("latency_ms", 0) for r in rows]
    latencies_sorted = sorted(latencies)
    p50 = latencies_sorted[len(latencies_sorted) // 2] if latencies_sorted else 0
    p95_idx = int(len(latencies_sorted) * 0.95)
    p95 = latencies_sorted[min(p95_idx, len(latencies_sorted) - 1)] if latencies_sorted else 0

    conatus_deltas = [r.get("conatus_delta", 0.0) for r in rows]
    predictive_deltas = [r.get("predictive_delta", 0.0) for r in rows]

    ttfg = None
    for r in rows:
        if r.get("graft_result") == "graft":
            ttfg = r["turn_index"]
            break

    total_pt = sum(r.get("cumulative_prompt_tokens", 0) for r in rows)
    total_ct = sum(r.get("cumulative_completion_tokens", 0) for r in rows)

    return {
        "total": total,
        "attempted": attempted,
        "attempt_rate": attempted / total if total else 0.0,
        "json_schema_pass_rate": (validator_checks - parse_rejects) / validator_checks if validator_checks else 0.0,
        "validation_pass_rate": accepts / validator_checks if validator_checks else 0.0,
        "sandbox_pass_rate": accepts / sandbox_checks if sandbox_checks else 0.0,
        "graft_accept_rate": grafts / total if total else 0.0,
        "transport_error_rate": transport_errors / total if total else 0.0,
        "parse_reject_rate": parse_rejects / total if total else 0.0,
        "validation_reject_rate": val_rejects / total if total else 0.0,
        "sandbox_reject_rate": sandbox_rejects / total if total else 0.0,
        "retry_total": retries,
        "retry_rate": retries / total if total else 0.0,
        "p50_latency_ms": p50,
        "p95_latency_ms": p95,
        "avg_latency_ms": sum(latencies) / len(latencies) if latencies else 0.0,
        "net_conatus_delta": sum(conatus_deltas) / len(conatus_deltas) if conatus_deltas else 0.0,
        "net_predictive_delta": sum(predictive_deltas) / len(predictive_deltas) if predictive_deltas else 0.0,
        "time_to_first_graft": ttfg,
        "breaker_activations": sum(1 for r in rows if r.get("breaker_cooldown", 0) > 0),
        "total_prompt_tokens": total_pt,
        "total_completion_tokens": total_ct,
    }


def generate_stage_report(stage_name: str, rows: List[Dict], incidents: List[Dict]) -> str:
    m = compute_model_metrics(rows)
    total = len(rows)
    grafts = sum(1 for r in rows if r.get("graft_result") == "graft")
    critical = [i for i in incidents if i["type"] not in ("stage_aborted_incident_cap", "budget_exhausted_prompt", "budget_exhausted_completion")]

    lines = [
        f"# Wave 5 — {stage_name.upper()} Report",
        "",
        f"**Stage:** {stage_name}",
        f"**Total turns:** {total}",
        f"**Sessions:** {len(set(r.get('session_id') for r in rows))}",
        f"**Incidents:** {len(incidents)} ({len(critical)} critical)",
        f"**Accepted grafts:** {grafts} ({grafts/total:.1%})" if total else "**Accepted grafts:** 0",
        f"**Schema pass rate:** {m.get('json_schema_pass_rate', 0.0):.3f}",
        f"**Validation pass rate:** {m.get('validation_pass_rate', 0.0):.3f}",
        f"**Sandbox pass rate:** {m.get('sandbox_pass_rate', 0.0):.3f}",
        f"**Graft accept rate:** {m.get('graft_accept_rate', 0.0):.3f}",
        f"**Transport error rate:** {m.get('transport_error_rate', 0.0):.3f}",
        f"**Parse reject rate:** {m.get('parse_reject_rate', 0.0):.3f}",
        f"**Validation reject rate:** {m.get('validation_reject_rate', 0.0):.3f}",
        f"**Sandbox reject rate:** {m.get('sandbox_reject_rate', 0.0):.3f}",
        f"**Retry rate:** {m.get('retry_rate', 0.0):.3f}",
        f"**Avg latency:** {m.get('avg_latency_ms', 0):.0f}ms",
        f"**P50 latency:** {m.get('p50_latency_ms', 0)}ms",
        f"**P95 latency:** {m.get('p95_latency_ms', 0)}ms",
        f"**Net conatus delta:** {m.get('net_conatus_delta', 0.0):.3f}",
        f"**Net predictive delta:** {m.get('net_predictive_delta', 0.0):.3f}",
        f"**Time to first graft:** {m.get('time_to_first_graft') or 'N/A'}",
        f"**Breaker activations:** {m.get('breaker_activations', 0)}",
        f"**Prompt tokens:** {m.get('total_prompt_tokens', 0):,}",
        f"**Completion tokens:** {m.get('total_completion_tokens', 0):,}",
        "",
        "## Incident Detail",
        "",
    ]

    if not incidents:
        lines.append("No incidents.")
    else:
        lines.append("| Type | Model | Session | Details |")
        lines.append("|------|-------|---------|---------|")
        for inc in incidents:
            model = inc.get("model", "unknown").split("/")[-1]
            sess = inc.get("session", "-")
            details = ""
            if "start_turn" in inc:
                details = f"turns {inc['start_turn']}–{inc['start_turn'] + inc.get('count', 1) - 1}"
            elif "turn" in inc:
                details = f"turn {inc['turn']}"
            elif "accumulated_prompt_tokens" in inc:
                details = f"tokens {inc.get('accumulated_prompt_tokens', 0):,}/{inc.get('cap', 0):,}"
            lines.append(f"| {inc.get('type', 'unknown')} | {model} | {sess} | {details} |")
    lines.append("")

    return "\n".join(lines)


def generate_consolidated_report() -> str:
    stages = ["canary", "stage1", "full"]
    stage_data = {}
    for s in stages:
        rows = load_jsonl(REPORTS_ROOT / s / "all_turns.jsonl")
        incidents = []
        inc_path = REPORTS_ROOT / s / "incidents.jsonl"
        if inc_path.exists():
            incidents = load_jsonl(inc_path)
        stage_data[s] = {"rows": rows, "incidents": incidents, "metrics": compute_model_metrics(rows)}

    lines = [
        "# Wave 5 — Consolidated Staged Soak Report",
        "",
        "**Objective:** Validate long-tail stability across increasing session depth and turn count.",
        "**Model:** accounts/fireworks/models/kimi-k2p6 (primary) / kimi-k2p5 (fallback)",
        "",
        "## Stage Summary",
        "",
        "| Stage | Sessions | Turns/Session | Total Turns | Incidents | Critical | Graft Rate | Schema Pass | Avg Latency | P95 Latency | Prompt Tokens | Completion Tokens |",
        "|-------|----------|---------------|-------------|-----------|----------|------------|-------------|-------------|-------------|---------------|-------------------|",
    ]

    for s in stages:
        d = stage_data[s]
        m = d["metrics"]
        critical = [i for i in d["incidents"] if i["type"] not in ("stage_aborted_incident_cap", "budget_exhausted_prompt", "budget_exhausted_completion")]
        cfg = STAGE_CONFIG[s]
        lines.append(
            f"| {s} | {cfg['sessions']} | {cfg['turns']} | {len(d['rows'])} | "
            f"{len(d['incidents'])} | {len(critical)} | "
            f"{m.get('graft_accept_rate', 0.0):.3f} | {m.get('json_schema_pass_rate', 0.0):.3f} | "
            f"{m.get('avg_latency_ms', 0):.0f}ms | {m.get('p95_latency_ms', 0)}ms | "
            f"{m.get('total_prompt_tokens', 0):,} | {m.get('total_completion_tokens', 0):,} |"
        )
    lines.append("")

    lines.extend([
        "## Drift Analysis (Canary → Stage 1 → Full)",
        "",
        "### Latency Drift",
        "",
    ])

    latencies = {}
    for s in stages:
        m = stage_data[s]["metrics"]
        if m:
            latencies[s] = {
                "avg": m.get("avg_latency_ms", 0),
                "p50": m.get("p50_latency_ms", 0),
                "p95": m.get("p95_latency_ms", 0),
            }

    if len(latencies) >= 2:
        lines.append("| Metric | Canary | Stage 1 | Full | Drift Canary→Full |")
        lines.append("|--------|--------|---------|------|-------------------|")
        for metric in ["avg", "p50", "p95"]:
            c = latencies.get("canary", {}).get(metric, 0)
            s1 = latencies.get("stage1", {}).get(metric, 0)
            f = latencies.get("full", {}).get(metric, 0)
            drift = f - c if f and c else 0
            lines.append(f"| {metric} | {c}ms | {s1}ms | {f}ms | {drift:+.0f}ms |")
        lines.append("")

    lines.extend([
        "### Quality Drift",
        "",
    ])

    quality = {}
    for s in stages:
        m = stage_data[s]["metrics"]
        if m:
            quality[s] = {
                "graft": m.get("graft_accept_rate", 0.0),
                "schema": m.get("json_schema_pass_rate", 0.0),
                "val": m.get("validation_pass_rate", 0.0),
                "sandbox": m.get("sandbox_pass_rate", 0.0),
            }

    if len(quality) >= 2:
        lines.append("| Metric | Canary | Stage 1 | Full | Drift Canary→Full |")
        lines.append("|--------|--------|---------|------|-------------------|")
        for metric in ["graft", "schema", "val", "sandbox"]:
            c = quality.get("canary", {}).get(metric, 0.0)
            s1 = quality.get("stage1", {}).get(metric, 0.0)
            f = quality.get("full", {}).get(metric, 0.0)
            drift = f - c
            lines.append(f"| {metric} | {c:.3f} | {s1:.3f} | {f:.3f} | {drift:+.3f} |")
        lines.append("")

    lines.extend([
        "## Fail-Closed Budget Summary",
        "",
        "| Stage | Prompt Cap | Completion Cap | Prompt Burn | Completion Burn | Under Cap? | Incident Cap | Incidents | Under Cap? |",
        "|-------|------------|------------------|-------------|-----------------|------------|--------------|-----------|------------|",
    ])
    for s in stages:
        m = stage_data[s]["metrics"]
        budget = STAGE_BUDGET[s]
        pt = m.get("total_prompt_tokens", 0)
        ct = m.get("total_completion_tokens", 0)
        inc_count = len([i for i in stage_data[s]["incidents"] if i["type"] not in ("stage_aborted_incident_cap",)])
        lines.append(
            f"| {s} | {budget['max_prompt_tokens']:,} | {budget['max_completion_tokens']:,} | "
            f"{pt:,} | {ct:,} | {'YES' if pt <= budget['max_prompt_tokens'] and ct <= budget['max_completion_tokens'] else 'NO'} | "
            f"{budget['max_incidents']} | {inc_count} | {'YES' if inc_count <= budget['max_incidents'] else 'NO'} |"
        )
    lines.append("")

    # Verdict
    all_clean = True
    for s in stages:
        critical = [i for i in stage_data[s]["incidents"] if i["type"] not in ("stage_aborted_incident_cap", "budget_exhausted_prompt", "budget_exhausted_completion")]
        if critical or len(stage_data[s]["rows"]) < STAGE_CONFIG[s]["sessions"] * STAGE_CONFIG[s]["turns"] * 0.95:
            all_clean = False

    lines.extend([
        "## Executive Verdict",
        "",
        f"- **ALL_STAGES_CLEAN:** {'YES' if all_clean else 'NO'}",
        "- **RECOMMENDATION:**",
    ])
    if all_clean:
        lines.append("  All stages completed within budget and incident caps. No critical incidents detected. System is cleared for production deployment or further scale testing.")
    else:
        lines.append("  One or more stages exceeded incident/token thresholds or had critical aborts. Review incident details and consider recalibration before production.")
    lines.append("")

    return "\n".join(lines)


# ═══════════════════════════════════════════════════════════════════════
# CLI
# ═══════════════════════════════════════════════════════════════════════

def main():
    parser = argparse.ArgumentParser(description="Wave 5 staged soak runner")
    parser.add_argument("--stage", choices=["canary", "stage1", "full", "report"], required=True)
    args = parser.parse_args()

    if args.stage == "report":
        report = generate_consolidated_report()
        out_path = REPORTS_ROOT / "wave5_consolidated_report.md"
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(report, encoding="utf-8")
        print(f"Report written to {out_path}")
        print(report)
        return

    rows, incidents, dirty, verdict = run_stage(args.stage)

    # Write stage report
    report = generate_stage_report(args.stage, rows, incidents)
    report_path = REPORTS_ROOT / args.stage / "report.md"
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(report, encoding="utf-8")
    write_jsonl(REPORTS_ROOT / args.stage / "incidents.jsonl", incidents)
    print(f"Stage report written to {report_path}")

    # Exit code: 0 if clean, 1 if dirty (for CI gate)
    if dirty:
        print(f"\n[EXIT 1] Stage {args.stage} is DIRTY (verdict={verdict})")
        sys.exit(1)
    else:
        print(f"\n[EXIT 0] Stage {args.stage} is CLEAN")
        sys.exit(0)


if __name__ == "__main__":
    main()
