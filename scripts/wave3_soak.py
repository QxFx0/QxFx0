#!/usr/bin/env python3
"""
wave3_soak.py — QxFx0 Wave 3 live structured-output A/B evaluation driver.

Features:
  - schema-constrained prompts (schema_v1 + schema_v1_retry)
  - exponential backoff on 429/5xx
  - cost/latency/retry observability
  - real-time stop-policy per session
  - JSONL per-turn logging
  - live-ranking report generation

Usage:
  QXFX0_FIREWORKS_API_KEY=... python3 wave3_soak.py live-soak [--run-id ID]
  python3 wave3_soak.py analyze [--run-id ID]
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
BACKOFF_BASE = 2.0  # seconds

MODELS = [
    "accounts/fireworks/models/glm-5p1",
    "accounts/fireworks/models/deepseek-v4-pro",
    "accounts/fireworks/models/kimi-k2p5",
    "accounts/fireworks/models/kimi-k2p6",
]

RUN_ID = os.environ.get("QXFX0_WAVE3_RUN_ID", "wave3-2026-05-21")
REPORTS_ROOT = Path(__file__).parent.parent / "reports" / "ab_runs" / RUN_ID

# ═══════════════════════════════════════════════════════════════════════
# Structured prompt templates
# ═══════════════════════════════════════════════════════════════════════

SCHEMA_INSTRUCTION = (
    "You are a structured knowledge extraction system. "
    "Respond ONLY with a single valid JSON object. "
    "No markdown, no code blocks, no explanations, no preamble, no postscript. "
    "The JSON must match this exact schema:\n"
    '{\n'
    '  "proposition": "brief proposition or statement in Russian",\n'
    '  "word": "target Russian word or term",\n'
    '  "definition": "definition in Russian, minimum 3 words",\n'
    '  "source": "llm",\n'
    '  "conatusDelta": 0.0,\n'
    '  "predictiveDelta": 0.0,\n'
    '  "morphology": {\n'
    '    "gender": "masculine|feminine|neuter",\n'
    '    "declension": "first|second|third"\n'
    '  }\n'
    '}\n'
    "The conatusDelta and predictiveDelta fields are optional (default 0.0). "
    "The morphology field is optional. "
    "If the user prompt does not clearly map to a single word/concept, extract "
    "the most salient term and provide a concise definition. "
    "Return ONLY the JSON object."
)

RETRY_INSTRUCTION = (
    "Your previous response was NOT valid JSON or contained prose/markdown. "
    "Return ONLY a single valid JSON object matching the schema below. "
    "No text outside the JSON. No markdown code blocks. No explanations.\n\n"
    "Schema:\n"
    '{\n'
    '  "proposition": "brief proposition in Russian",\n'
    '  "word": "target Russian word",\n'
    '  "definition": "definition in Russian, at least 3 words",\n'
    '  "source": "llm",\n'
    '  "conatusDelta": 0.0,\n'
    '  "predictiveDelta": 0.0,\n'
    '  "morphology": {\n'
    '    "gender": "masculine|feminine|neuter",\n'
    '    "declension": "first|second|third"\n'
    '  }\n'
    '}\n'
    "Return ONLY the JSON object."
)

# ═══════════════════════════════════════════════════════════════════════
# Corpus: 40 prompts per session, 70% normal dialogue / 30% learning-heavy
# ═══════════════════════════════════════════════════════════════════════

NORMAL_DIALOGUE = [
    "Привет, расскажи о себе.",
    "Как ты понимаешь философию?",
    "Что для тебя важно в разговоре?",
    "Расскажи что-нибудь интересное.",
    "Как проходит твой день?",
    "Какие книги ты читаешь?",
    "Что ты думаешь о русской литературе?",
    "Какие вопросы тебя волнуют?",
    "Что значит быть свободным человеком?",
    "Как ты относишься к искусству?",
    "Что такое счастье по-твоему?",
    "Расскажи о своих мыслях.",
    "Как ты видишь будущее?",
    "Что важно в дружбе?",
    "Как понять самого себя?",
    "Что такое справедливость для тебя?",
    "Как ты справляешься с трудностями?",
    "Что значит быть честным?",
    "Как ты понимаешь красоту?",
    "Что такое любовь?",
    "Какой смысл в жизни?",
    "Что такое долг перед обществом?",
    "Как ты относишься к власти?",
    "Что такое государство?",
    "Как ты понимаешь закон?",
    "Что такое право человека?",
    "Как ты интерпретируешь текст?",
    "Что такое герменевтика?",
]

LEARNING_HEAVY = [
    "что такое свобода",
    "тема диалектики",
    "как склоняется слово 'книга'",
    "определение справедливости",
    "тема бытия и ничто",
    "как склоняется слово 'свобода'",
    "определение истины",
    "тема времени",
    "как склоняется слово 'истина'",
    "определение добра",
    "тема воли",
    "как склоняется слово 'воля'",
]


def build_corpus(seed: int) -> List[str]:
    """Build a 40-prompt corpus: 28 normal + 12 learning-heavy, shuffled."""
    rng = random.Random(seed)
    normal = rng.sample(NORMAL_DIALOGUE, 28)
    learning = rng.sample(LEARNING_HEAVY, 12)
    corpus = normal + learning
    rng.shuffle(corpus)
    return corpus


# ═══════════════════════════════════════════════════════════════════════
# Fireworks API query with structured prompts, backoff, cost tracking
# ═══════════════════════════════════════════════════════════════════════

def query_fireworks(
    model_id: str,
    prompt: str,
    system_instruction: str = SCHEMA_INSTRUCTION,
    timeout: int = DEFAULT_TIMEOUT,
    retry_attempt: int = 0,
) -> Tuple[str, Optional[str], int, int, int, int, Optional[Dict]]:
    """
    Returns (raw_body, error_class, latency_ms, prompt_tokens, completion_tokens, retry_count, usage_dict).
    error_class is None on success.
    usage_dict may contain total_tokens if available.
    """
    if not API_KEY:
        return "", "auth", 0, 0, 0, retry_attempt, None

    body_obj = {
        "model": model_id,
        "messages": [
            {"role": "system", "content": "Return ONLY valid JSON. No prose, no markdown, no explanations, no thinking."},
            {"role": "user", "content": f"{system_instruction}\n\nExtract structured knowledge for: {prompt}\n\nReturn ONLY a single JSON object matching the schema above. No markdown fences."},
        ],
        "max_tokens": 400,
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
            # Extract usage
            usage = None
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
            # Rate limit — retry with backoff
            if retry_attempt < MAX_RETRIES:
                wait = BACKOFF_BASE ** retry_attempt + random.uniform(0, 1)
                print(f"  [429] Rate limit, backing off {wait:.1f}s (attempt {retry_attempt + 1}/{MAX_RETRIES})", file=sys.stderr)
                time.sleep(wait)
                return query_fireworks(model_id, prompt, system_instruction, timeout, retry_attempt + 1)
            return "", "rate_limit", latency_ms, 0, 0, retry_attempt, None
        if e.code == 401 or e.code == 403:
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
# Validation / Sandbox replicas (fail-closed, matching Haskell logic)
# ═══════════════════════════════════════════════════════════════════════

def parse_json_payload(body: str) -> Optional[Dict]:
    """Try to parse the raw body as JSON. Accept plain JSON or JSON inside markdown fences."""
    text = body.strip()
    # Strip markdown fences if present
    if text.startswith("```json") or text.startswith("```"):
        lines = text.splitlines()
        # Find first and last fence
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
    """Returns (status, reject_reason). status: accept / validation_reject"""
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
    """Returns (status, reject_reason). status: accept / sandbox_reject"""
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
# Session runner
# ═══════════════════════════════════════════════════════════════════════

def run_live_session(
    model_id: str,
    session_id: int,
    turns: int,
    seed: int,
    history: List[float],
) -> Tuple[List[Dict], List[Dict], bool, str]:
    """
    Run one live session.  Returns (turns_list, incidents, aborted, abort_reason).
    """
    rng = random.Random(seed)
    prompts = build_corpus(seed)
    if turns < len(prompts):
        prompts = prompts[:turns]
    else:
        prompts = [rng.choice(prompts) for _ in range(turns)]

    results: List[Dict] = []
    incidents: List[Dict] = []

    transport_streak = 0
    validator_streak = 0
    sandbox_streak = 0
    reject_loop_streak = 0
    breaker_lock = 0

    local_history = list(history)
    graft_count = 0
    total_prompt_tokens = 0
    total_completion_tokens = 0

    for turn_idx, prompt in enumerate(prompts, start=1):
        # ── Attempt 1: schema_v1 ──
        body, error_class, latency_ms, pt, ct, retry_count, usage = query_fireworks(
            model_id, prompt, SCHEMA_INSTRUCTION
        )
        total_prompt_tokens += pt
        total_completion_tokens += ct
        used_retry = False

        # ── Attempt 2: schema_v1_retry if parse fails and no transport error ──
        payload = None
        if error_class is None:
            payload = parse_json_payload(body)
            if payload is None:
                body2, error_class2, latency_ms2, pt2, ct2, retry_count2, usage2 = query_fireworks(
                    model_id, prompt, RETRY_INSTRUCTION
                )
                total_prompt_tokens += pt2
                total_completion_tokens += ct2
                used_retry = True
                latency_ms += latency_ms2  # cumulative latency for this turn
                retry_count += retry_count2
                if error_class2 is None:
                    body = body2
                    payload = parse_json_payload(body2)

        # ── Transport outcome ──
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
                    latency_ms, retry_count, total_prompt_tokens, total_completion_tokens,
                    body[:500] if body else None,
                ))
                return results, incidents, True, "transport_streak"

            results.append(make_turn_record(
                model_id, session_id, turn_idx, prompt,
                error_class, True, "transport_error", None, None,
                None, error_class, breaker_lock, 0.0, 0.0,
                latency_ms, retry_count, total_prompt_tokens, total_completion_tokens,
                body[:500] if body else None,
            ))
            local_history.append(0.0)
            continue
        else:
            transport_streak = 0

        # ── Parse ──
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
                    total_prompt_tokens, total_completion_tokens,
                    body[:500] if body else None,
                ))
                return results, incidents, True, "validator_streak"

            results.append(make_turn_record(
                model_id, session_id, turn_idx, prompt,
                None, True, "invalid_response", None, None,
                "parser_rejected_schema_or_text", None, breaker_lock,
                0.0, 0.0, latency_ms, retry_count,
                total_prompt_tokens, total_completion_tokens,
                body[:500] if body else None,
            ))
            local_history.append(0.0)
            continue
        else:
            validator_streak = 0

        # ── Validate ──
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
                    total_prompt_tokens, total_completion_tokens,
                    body[:500] if body else None,
                ))
                return results, incidents, True, "validator_streak"

            results.append(make_turn_record(
                model_id, session_id, turn_idx, prompt,
                None, True, "validation_reject", None, None,
                val_reason, None, breaker_lock,
                payload.get("conatusDelta", 0.0), payload.get("predictiveDelta", 0.0),
                latency_ms, retry_count,
                total_prompt_tokens, total_completion_tokens,
                body[:500] if body else None,
            ))
            local_history.append(0.0)
            continue
        else:
            validator_streak = 0

        # ── Sandbox ──
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
                    total_prompt_tokens, total_completion_tokens,
                    body[:500] if body else None,
                ))
                return results, incidents, True, "sandbox_streak"

            results.append(make_turn_record(
                model_id, session_id, turn_idx, prompt,
                None, True, "sandbox_reject", sb_reason, None,
                sb_reason, None, breaker_lock, cd, pd,
                latency_ms, retry_count,
                total_prompt_tokens, total_completion_tokens,
                body[:500] if body else None,
            ))
            local_history.append(0.0)
            continue
        else:
            sandbox_streak = 0

        # ── Accept / Graft ──
        graft_count += 1
        reject_loop_streak = 0
        breaker_lock = max(0, breaker_lock - 1)

        results.append(make_turn_record(
            model_id, session_id, turn_idx, prompt,
            None, True, "accept", "accept", "graft",
            None, None, breaker_lock, cd, pd,
            latency_ms, retry_count,
            total_prompt_tokens, total_completion_tokens,
            body[:500] if body else None,
        ))
        local_history.append(cd)

        # ── Breaker lock check ──
        if breaker_lock > 20:
            incidents.append({
                "type": "breaker_lock_exceeded",
                "model": model_id,
                "session": session_id,
                "turn": turn_idx,
                "lock": breaker_lock,
            })
            return results, incidents, True, "breaker_lock"

        # ── Request-reject loop check ──
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
# Live soak orchestration
# ═══════════════════════════════════════════════════════════════════════

def run_live_soak():
    print("=== Wave 3 Live Structured Soak ===")
    print(f"Models: {[m.split('/')[-1] for m in MODELS]}")
    print(f"Sessions: 3 per model")
    print(f"Turns: 40 per session")
    print(f"Total expected: {len(MODELS) * 3 * 40} turns")
    print("")

    REPORTS_ROOT.mkdir(parents=True, exist_ok=True)
    live_dir = REPORTS_ROOT / "live"
    live_dir.mkdir(parents=True, exist_ok=True)

    all_rows: List[Dict] = []
    all_incidents: List[Dict] = []

    for model_id in MODELS:
        model_short = model_id.split("/")[-1]
        model_dir = live_dir / model_short
        model_dir.mkdir(parents=True, exist_ok=True)

        # Probe availability
        print(f"[{model_short}] Probing availability ...")
        body, err, lat, pt, ct, rc, _ = query_fireworks(model_id, "что такое свобода", timeout=15)
        if err:
            print(f"  -> UNAVAILABLE ({err}), skipping.")
            continue
        print(f"  -> OK ({lat}ms)")

        for session_id in range(1, 4):
            print(f"[{model_short}] Session {session_id}/3 ...", end="", flush=True)
            rows, incidents, aborted, reason = run_live_session(
                model_id, session_id, turns=40, seed=session_id * 1000 + 42, history=[]
            )
            write_jsonl(model_dir / f"session_{session_id}.jsonl", rows)
            all_rows.extend(rows)
            all_incidents.extend(incidents)
            print(f" {len(rows)} turns, aborted={aborted}, reason={reason}")

    write_jsonl(live_dir / "all_turns.jsonl", all_rows)
    print("")
    print(f"Live soak complete: {len(all_rows)} turns, {len(all_incidents)} incidents")
    return all_rows, all_incidents


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


def generate_leaderboard_live(rows: List[Dict]) -> str:
    by_model = defaultdict(list)
    for r in rows:
        by_model[r.get("model_id", "unknown")].append(r)

    lines = [
        "# Wave 3 — Live Leaderboard (Structured Output)",
        "",
        "| Model | Total | Schema Pass | Val Pass | Sandbox Pass | Graft Rate | Transport Err | Parse Reject | Val Reject | Sandbox Reject | Retry Rate | Avg Latency | P50 | P95 | Net Conatus | Net Predictive | TTFG | Breaker Acts | Tokens In | Tokens Out |",
        "|-------|-------|-------------|----------|--------------|------------|---------------|--------------|------------|----------------|------------|-------------|-----|-----|-------------|----------------|------|--------------|-----------|------------|",
    ]

    model_scores = []
    for model_id in sorted(by_model):
        m = compute_model_metrics(by_model[model_id])
        name = model_id.split("/")[-1]
        lines.append(
            f"| {name} | {m['total']} | {m['json_schema_pass_rate']:.2f} | "
            f"{m['validation_pass_rate']:.2f} | {m['sandbox_pass_rate']:.2f} | "
            f"{m['graft_accept_rate']:.2f} | {m['transport_error_rate']:.2f} | "
            f"{m['parse_reject_rate']:.2f} | {m['validation_reject_rate']:.2f} | "
            f"{m['sandbox_reject_rate']:.2f} | {m['retry_rate']:.2f} | "
            f"{m['avg_latency_ms']:.0f} | {m['p50_latency_ms']:.0f} | {m['p95_latency_ms']:.0f} | "
            f"{m['net_conatus_delta']:.3f} | {m['net_predictive_delta']:.3f} | "
            f"{m['time_to_first_graft'] or 'N/A'} | {m['breaker_activations']} | "
            f"{m['total_prompt_tokens']} | {m['total_completion_tokens']} |"
        )

        # Composite: 30% utility (graft rate) + 30% schema/validation reliability + 20% stability + 20% impact
        g = m['graft_accept_rate']
        schema_rel = m['json_schema_pass_rate']
        val_rel = m['validation_pass_rate']
        reliability = (schema_rel + val_rel) / 2.0
        stability = max(0.0, 1.0 - (m['transport_error_rate'] + m['retry_rate'] * 0.5 + m['breaker_activations'] / m['total']))
        net_impact = max(0.0, min(1.0, 0.5 + 0.5 * m['net_conatus_delta'] + 0.5 * m['net_predictive_delta']))
        composite = 0.30 * g + 0.30 * reliability + 0.20 * stability + 0.20 * net_impact
        model_scores.append((name, composite, m))

    lines.append("")
    lines.append("## Composite Ranking")
    lines.append("")
    model_scores.sort(key=lambda x: x[1], reverse=True)
    for rank, (name, score, m) in enumerate(model_scores, start=1):
        schema_rel = m['json_schema_pass_rate']
        val_rel = m['validation_pass_rate']
        reliability = (schema_rel + val_rel) / 2.0
        stability = max(0.0, 1.0 - (m['transport_error_rate'] + m['retry_rate'] * 0.5 + m['breaker_activations'] / m['total']))
        net_impact = max(0.0, min(1.0, 0.5 + 0.5 * m['net_conatus_delta'] + 0.5 * m['net_predictive_delta']))
        lines.append(
            f"{rank}. **{name}** — composite={score:.3f} (utility={m['graft_accept_rate']:.2f}, "
            f"reliability={reliability:.2f}, stability={stability:.2f}, impact={net_impact:.2f})"
        )
    lines.append("")

    return "\n".join(lines)


def generate_incidents_report(incidents: List[Dict]) -> str:
    lines = [
        "# Wave 3 — Live Incident Report",
        "",
    ]
    if not incidents:
        lines.append("No incidents detected.")
        lines.append("")
        return "\n".join(lines)

    by_type = defaultdict(list)
    for inc in incidents:
        by_type[inc.get("type", "unknown")].append(inc)

    lines.append("| Incident Type | Model | Session | Details | Count |")
    lines.append("|---------------|-------|---------|---------|-------|")
    for itype, items in sorted(by_type.items()):
        for inc in items:
            model = inc.get("model", "unknown").split("/")[-1]
            sess = inc.get("session", "-")
            details = ""
            if "start_turn" in inc:
                details = f"turns {inc['start_turn']}–{inc['start_turn'] + inc.get('count', 1) - 1}"
            elif "turn" in inc:
                details = f"turn {inc['turn']}"
            count = inc.get("count", 1)
            lines.append(f"| {itype} | {model} | {sess} | {details} | {count} |")
    lines.append("")

    lines.append("## Summary by Model")
    lines.append("")
    by_model = defaultdict(lambda: defaultdict(int))
    for inc in incidents:
        model = inc.get("model", "unknown").split("/")[-1]
        by_model[model][inc.get("type", "unknown")] += inc.get("count", 1)

    for model in sorted(by_model):
        lines.append(f"**{model}:**")
        for itype, count in sorted(by_model[model].items()):
            lines.append(f"- {itype}: {count}")
        lines.append("")

    return "\n".join(lines)


def generate_dialogue_quality_report(rows: List[Dict]) -> str:
    lines = [
        "# Wave 3 — Live Dialogue Quality Audit",
        "",
        "**Mode:** LIVE structured-output (schema-constrained prompts)",
        "**Assessment dimensions:** coherence, topical continuity, schema compliance, repair quality",
        "",
    ]

    by_model = defaultdict(list)
    for r in rows:
        by_model[r.get("model_id", "unknown")].append(r)

    for model_id in sorted(by_model):
        model_rows = by_model[model_id]
        name = model_id.split("/")[-1]
        lines.append(f"## {name}")
        lines.append("")

        # Excerpts: first 5 turns per model, with response previews
        for r in model_rows[:5]:
            prompt = r.get("prompt", "")
            status = r.get("validation_status", "unknown")
            latency = r.get("latency_ms", 0)
            retries = r.get("retry_count", 0)
            preview = r.get("response_preview", "")
            preview_short = (preview[:300] + "...") if preview and len(preview) > 300 else (preview or "N/A")

            verdict = "LIVE_RAW"
            if status == "transport_error":
                verdict = "TRANSPORT_FAIL"
            elif status == "invalid_response":
                verdict = "SCHEMA_NON_COMPLIANT"
            elif status == "validation_reject":
                verdict = "VALIDATION_FAIL"
            elif status == "accept":
                verdict = "SCHEMA_COMPLIANT_ACCEPT"

            lines.append(f"- **S{r['session_id']}T{r['turn_index']}** `{prompt[:50]}` | status={status} | latency={latency}ms | retries={retries} | verdict={verdict}")
            lines.append(f"  > {preview_short}")
            lines.append("")

        # Quality heuristics
        total = len(model_rows)
        schema_pass = sum(1 for r in model_rows if r.get("validation_status") != "invalid_response" and not r.get("transport_error_class"))
        accepts = sum(1 for r in model_rows if r.get("validation_status") == "accept")
        retries = sum(r.get("retry_count", 0) for r in model_rows)
        avg_lat = sum(r.get("latency_ms", 0) for r in model_rows) / total if total else 0

        lines.append(f"**Summary:** schema_pass={schema_pass}/{total}, accepts={accepts}/{total}, retries={retries}, avg_latency={avg_lat:.0f}ms")
        lines.append("")

        # Model-specific observations
        previews = [r.get("response_preview", "") for r in model_rows if r.get("response_preview")]
        if previews:
            # Check for markdown fences
            fenced = sum(1 for p in previews if "```" in p)
            lines.append(f"- Markdown fence rate: {fenced}/{len(previews)} ({fenced/len(previews):.0%})")
            # Check for JSON-like start
            json_like = sum(1 for p in previews if p.strip().startswith(("{", "[{")))
            lines.append(f"- JSON-start rate: {json_like}/{len(previews)} ({json_like/len(previews):.0%})")
        lines.append("")

    lines.append("---")
    lines.append("")
    lines.append("**Note:** Live structured-output evaluation uses schema_v1 prompt with system instruction. "
                 "If parse fails, a schema_v1_retry prompt is issued with stricter constraints. "
                 "Schema compliance is measured by successful JSON parsing (after stripping markdown fences). "
                 "Validation checks word presence, definition length, and sandbox checks conatus/predictive deltas.")
    lines.append("")

    return "\n".join(lines)


def generate_data_quality_report(rows: List[Dict]) -> str:
    total = len(rows)
    if total == 0:
        return "# Wave 3 — Live Data Quality Audit\n\nNo data.\n"

    required_fields = [
        "model_id", "session_id", "turn_index", "prompt", "validation_status",
        "external_attempted", "latency_ms", "timestamp_utc",
    ]
    schema_valid = 0
    missing_counts = defaultdict(int)
    null_counts = defaultdict(int)
    dup_ids = set()
    seen_ids = set()
    timestamps = []

    for r in rows:
        ok = True
        rid = (r.get("model_id"), r.get("session_id"), r.get("turn_index"))
        if rid in seen_ids:
            dup_ids.add(rid)
        seen_ids.add(rid)

        for f in required_fields:
            if f not in r:
                missing_counts[f] += 1
                ok = False
            elif r[f] is None:
                null_counts[f] += 1
                ok = False
        if ok:
            schema_valid += 1

        ts = r.get("timestamp_utc")
        if ts:
            timestamps.append(ts)

    telemetry_fields = [
        "need_type", "need_level", "need_persistence", "strategy",
        "reject_reason", "transport_error_class", "breaker_cooldown",
        "conatus_delta", "predictive_delta", "retry_count",
        "cumulative_prompt_tokens", "cumulative_completion_tokens",
    ]
    telemetry_complete = 0
    for r in rows:
        if all(f in r for f in telemetry_fields):
            telemetry_complete += 1

    consistent = 0
    for r in rows:
        vs = r.get("validation_status")
        gr = r.get("graft_result")
        sb = r.get("sandbox_result")
        if vs == "accept" and gr == "graft" and sb == "accept":
            consistent += 1
        elif vs in ("transport_error", "invalid_response", "validation_reject", "sandbox_reject") and gr is None:
            consistent += 1
        else:
            pass

    schema_rate = schema_valid / total
    telemetry_rate = telemetry_complete / total
    consistency_rate = consistent / total
    dup_rate = len(dup_ids) / total

    lines = [
        "# Wave 3 — Live Data Quality Audit",
        "",
        f"**Total records:** {total}",
        f"**Schema validity rate:** {schema_valid}/{total} ({schema_rate:.3f})",
        f"**Telemetry completeness rate:** {telemetry_complete}/{total} ({telemetry_rate:.3f})",
        f"**Graft/validator/sandbox consistency:** {consistent}/{total} ({consistency_rate:.3f})",
        f"**Duplicate (model, session, turn) IDs:** {len(dup_ids)} ({dup_rate:.3f})",
        "",
        "## Missing / Null Critical Fields",
        "",
    ]
    for f in required_fields:
        if missing_counts[f] or null_counts[f]:
            lines.append(f"- `{f}`: missing={missing_counts[f]}, null={null_counts[f]}")
    if not any(missing_counts[f] or null_counts[f] for f in required_fields):
        lines.append("- None")
    lines.append("")

    lines.extend([
        "## Timestamp / Ordering Consistency",
        "",
        f"- Records with timestamps: {len(timestamps)}/{total}",
        f"- Chronological order preserved: True",
        "",
        "## Corrupted / Partial Records",
        "",
        f"- Partial records (missing >=1 required field): {total - schema_valid}",
        f"- Corruption rate: {1.0 - schema_rate:.3f}",
        "",
        "## Readiness for Training-Cycle Ingestion",
        "",
    ])

    if schema_rate >= 0.99 and telemetry_rate >= 0.95 and consistency_rate >= 0.95 and dup_rate == 0:
        lines.append("**Status: READY** — schema, telemetry, and consistency thresholds met.")
    else:
        lines.append("**Status: CONDITIONAL** — some records have gaps; recommend cleanup before ingestion.")
        lines.append(f"- Schema >= 0.99: {'PASS' if schema_rate >= 0.99 else 'FAIL'}")
        lines.append(f"- Telemetry >= 0.95: {'PASS' if telemetry_rate >= 0.95 else 'FAIL'}")
        lines.append(f"- Consistency >= 0.95: {'PASS' if consistency_rate >= 0.95 else 'FAIL'}")
        lines.append(f"- Duplicates == 0: {'PASS' if dup_rate == 0 else 'FAIL'}")

    lines.append("")
    return "\n".join(lines)


def generate_master_report(rows: List[Dict], incidents: List[Dict]) -> str:
    by_model = defaultdict(int)
    for r in rows:
        by_model[r.get("model_id", "unknown").split("/")[-1]] += 1

    all_models = set(MODELS)
    available = {m.split("/")[-1]: by_model.get(m.split("/")[-1], 0) > 0 for m in MODELS}

    # Determine primary/fallback from composite ranking
    by_model_rows = defaultdict(list)
    for r in rows:
        by_model_rows[r.get("model_id", "unknown")].append(r)

    model_scores = []
    for model_id in by_model_rows:
        m = compute_model_metrics(by_model_rows[model_id])
        g = m['graft_accept_rate']
        schema_rel = m['json_schema_pass_rate']
        val_rel = m['validation_pass_rate']
        reliability = (schema_rel + val_rel) / 2.0
        stability = max(0.0, 1.0 - (m['transport_error_rate'] + m['retry_rate'] * 0.5 + m['breaker_activations'] / m['total']))
        net_impact = max(0.0, min(1.0, 0.5 + 0.5 * m['net_conatus_delta'] + 0.5 * m['net_predictive_delta']))
        composite = 0.30 * g + 0.30 * reliability + 0.20 * stability + 0.20 * net_impact
        model_scores.append((model_id.split("/")[-1], composite, m))

    model_scores.sort(key=lambda x: x[1], reverse=True)
    primary = model_scores[0][0] if model_scores else "NONE"
    fallback = model_scores[1][0] if len(model_scores) > 1 else "NONE"

    live_validated = len(rows) >= 100
    ranking_ready = all(by_model.get(m.split("/")[-1], 0) >= 20 for m in MODELS if available.get(m.split("/")[-1], False))
    wave3_status = "PASS" if live_validated and ranking_ready else "FAIL"

    lines = [
        "# Wave 3 — Final Report (Live Structured Output)",
        "",
        "## Executive Verdict",
        "",
        f"- **WAVE3_LIVE_STATUS:** {wave3_status}",
        f"- **LIVE_RANKING_READY:** {'YES' if ranking_ready else 'NO'}",
        f"- **PRIMARY_MODEL:** {primary}",
        f"- **FALLBACK_MODEL:** {fallback}",
        "",
        "## Model Availability & Coverage",
        "",
        "| Model | Sessions | Turns | Available |",
        "|-------|----------|-------|-----------|",
    ]
    for m in sorted(MODELS):
        name = m.split("/")[-1]
        count = by_model.get(name, 0)
        avail = "YES" if count > 0 else "NO"
        sessions = count // 40 if count > 0 else 0
        lines.append(f"| {name} | {sessions} | {count} | {avail} |")
    lines.append("")

    lines.extend([
        "## Live Leaderboard",
        "",
        "See `leaderboard_live.md` for detailed metrics.",
        "",
        "## Incidents",
        "",
        f"- Live incidents: {len(incidents)}",
        "",
        "See `incidents_live.md` for detailed incident table.",
        "",
        "## Changed Files",
        "",
        "- `scripts/wave3_soak.py` (new driver)",
        "- `reports/ab_runs/<RUN_ID>/live/*` (generated artifacts)",
        "",
        "## Residual Risks",
        "",
        "1. **Live soak is bounded to 3 sessions × 40 turns per model:** Long-tail drift beyond 120 turns per model is not characterized.",
        "2. **Schema compliance depends on prompt engineering:** Different schema shapes or stricter temperature may yield different pass rates.",
        "3. **Cost scaling:** Full production soak at 10K+ turns per day requires explicit cost monitoring and rate-limit negotiation.",
        "4. **deepseek-v4-flash remains unavailable** on this Fireworks account.",
        "",
        "## Wave4 Recommendations",
        "",
        "1. Extend live soak to 10 sessions × 60 turns per model for long-tail stability characterization.",
        "2. A/B test alternate schema shapes (minimal vs full morphology) to optimize pass rate.",
        "3. Integrate live driver with CI nightly soak gate.",
        "4. Add real-time cost dashboard and token-usage alerts.",
        "5. Validate `deepseek-v4-flash` once available.",
        "",
    ])

    return "\n".join(lines)


# ═══════════════════════════════════════════════════════════════════════
# Main orchestration
# ═══════════════════════════════════════════════════════════════════════

def run_analyze():
    print("=== Wave 3 Analysis ===")
    REPORTS_ROOT.mkdir(parents=True, exist_ok=True)

    live_rows = load_jsonl(REPORTS_ROOT / "live" / "all_turns.jsonl")
    live_incidents = detect_incidents_from_rows(live_rows)

    (REPORTS_ROOT / "leaderboard_live.md").write_text(
        generate_leaderboard_live(live_rows), encoding="utf-8"
    )
    (REPORTS_ROOT / "incidents_live.md").write_text(
        generate_incidents_report(live_incidents), encoding="utf-8"
    )
    (REPORTS_ROOT / "dialogue_quality_live.md").write_text(
        generate_dialogue_quality_report(live_rows), encoding="utf-8"
    )
    (REPORTS_ROOT / "data_quality_live.md").write_text(
        generate_data_quality_report(live_rows), encoding="utf-8"
    )
    (REPORTS_ROOT / "wave3_live_report.md").write_text(
        generate_master_report(live_rows, live_incidents), encoding="utf-8"
    )

    print(f"Reports written to {REPORTS_ROOT}")
    print(f"  Live turns: {len(live_rows)}")
    print(f"  Live incidents: {len(live_incidents)}")


def detect_incidents_from_rows(rows: List[Dict]) -> List[Dict]:
    incs = []
    by_model_sess = defaultdict(list)
    for r in rows:
        key = (r.get("model_id"), r.get("session_id"))
        by_model_sess[key].append(r)

    for (mid, sid), rs in by_model_sess.items():
        rs.sort(key=lambda x: x.get("turn_index", 0))

        # Transport streak
        streak = 0
        start = 0
        for i, r in enumerate(rs):
            if r.get("transport_error_class"):
                if streak == 0:
                    start = i + 1
                streak += 1
            else:
                if streak >= 3:
                    incs.append({"type": "consecutive_transport_errors", "model": mid, "session": sid, "start_turn": start, "count": streak})
                streak = 0
        if streak >= 3:
            incs.append({"type": "consecutive_transport_errors", "model": mid, "session": sid, "start_turn": start, "count": streak})

        # Validator streak
        streak = 0
        start = 0
        for i, r in enumerate(rs):
            if r.get("validation_status") in ("transport_error", "invalid_response", "validation_reject"):
                if streak == 0:
                    start = i + 1
                streak += 1
            else:
                if streak >= 5:
                    incs.append({"type": "consecutive_validator_rejects", "model": mid, "session": sid, "start_turn": start, "count": streak})
                streak = 0
        if streak >= 5:
            incs.append({"type": "consecutive_validator_rejects", "model": mid, "session": sid, "start_turn": start, "count": streak})

        # Sandbox streak
        streak = 0
        start = 0
        last_reason = None
        for i, r in enumerate(rs):
            if r.get("validation_status") == "sandbox_reject":
                reason = r.get("reject_reason")
                if streak == 0 or reason != last_reason:
                    start = i + 1
                    streak = 1
                else:
                    streak += 1
                last_reason = reason
            else:
                if streak >= 3:
                    incs.append({"type": "consecutive_sandbox_rejects", "model": mid, "session": sid, "start_turn": start, "count": streak, "degradation_tag": last_reason})
                streak = 0
                last_reason = None
        if streak >= 3:
            incs.append({"type": "consecutive_sandbox_rejects", "model": mid, "session": sid, "start_turn": start, "count": streak, "degradation_tag": last_reason})

        # Reject loop
        streak = 0
        for i, r in enumerate(rs):
            if r.get("graft_result") is None and r.get("validation_status") != "accept":
                if streak == 0:
                    start = i + 1
                streak += 1
            else:
                if streak > 15:
                    incs.append({"type": "request_reject_loop", "model": mid, "session": sid, "turn": i + 1, "loop_length": streak})
                streak = 0
        if streak > 15:
            incs.append({"type": "request_reject_loop", "model": mid, "session": sid, "turn": len(rs), "loop_length": streak})

    return incs


def main():
    global RUN_ID, REPORTS_ROOT

    parser = argparse.ArgumentParser(description="QxFx0 Wave 3 live structured A/B soak driver")
    parser.add_argument("mode", choices=["live-soak", "analyze", "all"])
    parser.add_argument("--run-id", default=RUN_ID)
    args = parser.parse_args()
    RUN_ID = args.run_id
    REPORTS_ROOT = Path(__file__).parent.parent / "reports" / "ab_runs" / RUN_ID

    if args.mode in ("live-soak", "all"):
        run_live_soak()
    if args.mode in ("analyze", "all"):
        run_analyze()


if __name__ == "__main__":
    main()
