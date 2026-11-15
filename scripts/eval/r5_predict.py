#!/usr/bin/env python3
"""Predict the concept-v3 user regime (R5 encode -> contour -> move) for a probe corpus.

Why this exists
---------------
A probe pre-registration must state its predictions *before* the capture, and a
reader must be able to recompute them.  The runtime pieces are small and pure:

* ``QxFx0.User.R5.encodeR5`` -- a linear feature sum over marker counts;
* ``QxFx0.Types.User.R5.outsideViabilityContour`` -- a three-line guard;
* ``QxFx0.Semantic.MoveGraph.planOntologicalMove`` -- a total search over four
  operators against one target state.

This tool mirrors them (~200 lines) and **pins every constant against the
Haskell source**, so a runtime change makes the tool fail loudly instead of
predicting stale numbers.  It is a *predictor*, never a judge: the measurement
is the capture's own replay trace, read by ``scripts/eval/user_regime_report.py``.

The replica is validated against measured data, not assumed:
``--verify-capture`` recomputes all five axes, the score and the baseline for
every turn of a recorded capture and reports exact matches (80/80 on
``user-regime-20261113``).

Eval-only and read-only: opens a database ``mode=ro`` when asked to verify a
capture, writes nothing, and is not on the runtime authority path
(``scripts/eval/NON_AUTHORITY.txt``).

usage::

    scripts/eval/r5_predict.py --corpus spec/eval/user_regime_probe_2026-11-14.tsv
    scripts/eval/r5_predict.py --corpus <tsv> --json
    scripts/eval/r5_predict.py --corpus <tsv> --topics-from reports/eval_runs/<run>
    scripts/eval/r5_predict.py --corpus <tsv> --what-if
    scripts/eval/r5_predict.py --corpus <tsv> --what-if --topics-from reports/eval_runs/<run>
    scripts/eval/r5_predict.py --corpus <tsv> --what-if --what-if-reference v1
    scripts/eval/r5_predict.py --corpus <tsv> --what-if-mention
    scripts/eval/r5_predict.py --corpus <tsv> --mention-mode attribution
    scripts/eval/r5_predict.py --verify-capture reports/eval_runs/<run>
    scripts/eval/r5_predict.py --self-test

Exit codes: ``0`` ok, ``1`` prediction/verification mismatch, ``2`` usage or
source-parse error.

Topic-continuity rules
----------------------
``encodeR5``'s topic bit is one line, and it is the one input the corpus
cannot predict (``bestTopic`` is the runtime's intent focus, a raw surface
word).  ``--what-if`` runs the same trajectory under every candidate rule so
the delta is *measured* before a runtime change is pre-registered:

* ``v1`` -- the frozen v1 runtime: ``lastTopic`` matched unnormalized, as a
  substring of the un-blanked text;
* ``normalized`` -- the topic side normalized (lowercase, ``ё`` -> ``е``,
  whitespace collapsed) before the substring test;
* ``boundary`` -- additionally requires whole words (a topic never matches
  inside a longer word);
* ``negation`` / ``negation2`` -- additionally reject an occurrence whose one
  or two preceding words are a negation particle; an occurrence that is not
  negated still counts.

``CURRENT_TOPIC_MODE`` names the rule the runtime implements (encoder v2 =
``negation``); ``--what-if-reference`` chooses the diff baseline, so a
v1-referenced table stays reproducible after the flip.  ``--verify-capture``
selects the rule from the trace's ``urtEncoderVersion`` (``ENCODER_RULES``),
so a capture records which rule produced it.

Mention-vs-use rules
--------------------
``classifyOntological`` reads a marker anywhere in the utterance as the
speaker's act, including inside a report of someone else's claim («так
утверждал Шопенгауэр»).  ``--what-if-mention`` runs the same trajectory under
every candidate scope and diffs the ontological vector and the move:

* ``off`` -- the current runtime: the whole utterance is the speaker's;
* ``attribution`` -- a report (quotation, report phrase, or a third-party
  attribution verb with a name-like token adjacent) resolves to the neutral
  vector; a first-person token vetoes the rule, so the speaker's own act
  survives inside a quotation.

The rule touches the vector only: the score, the contour and the EMA baseline
are identical by construction.  ``--mention-mode`` selects the rule for a
table; ``CURRENT_MENTION_MODE`` names the runtime's (``off`` until the change
lands).
"""

from __future__ import annotations

import argparse
import json
import re
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MARKERS_HS = ROOT / "src/QxFx0/Semantic/Markers.hs"
R5_TYPES_HS = ROOT / "src/QxFx0/Types/User/R5.hs"
MOVE_HS = ROOT / "src/QxFx0/Semantic/MoveGraph.hs"
ONTOLOGICAL_HS = ROOT / "src/QxFx0/Semantic/Ontological.hs"

AXES = ("resonance", "atmosphere", "confidence", "consolidation", "counterfactual")
MOVE_NAMES = ("mirror_state", "establish_resonance", "affirm_being", "open_alternative")
MOVE_EFFECT = {
    "mirror_state": (0.10, -0.05, 0.00, 0.00, 0.00),
    "establish_resonance": (0.20, -0.05, 0.00, 0.05, 0.00),
    "affirm_being": (0.10, -0.05, 0.15, 0.00, 0.00),
    "open_alternative": (0.00, 0.00, 0.05, 0.00, 0.20),
}
MARKER_NAMES = (
    "r5DistressMarkers",
    "r5AgencyNegativeMarkers",
    "r5AgencyPositiveMarkers",
    "r5ResonanceAddressMarkers",
    "r5ConsolidationMarkers",
    "r5CounterfactualMarkers",
    "beingPositiveMarkers",
    "beingNegativeMarkers",
    "strivingPositiveMarkers",
    "strivingNegativeMarkers",
    "affirmationPositiveMarkers",
    "affirmationNegativeMarkers",
)


class PredictError(Exception):
    """A source file that cannot be parsed, or a constant that moved."""


# ---------------------------------------------------------------------------
# Lexicons: one source of truth (the Haskell module)
# ---------------------------------------------------------------------------


def read_markers() -> dict[str, list[str]]:
    source = MARKERS_HS.read_text(encoding="utf-8")
    out = {}
    for name in MARKER_NAMES:
        try:
            start = source.index(f"\n{name} :: [Text]")
        except ValueError as error:
            raise PredictError(f"{MARKERS_HS}: missing {name}") from error
        open_at = source.index("[", source.index("=", start))
        depth = 0
        for i in range(open_at, len(source)):
            if source[i] == "[":
                depth += 1
            elif source[i] == "]":
                depth -= 1
                if depth == 0:
                    out[name] = re.findall(r'"([^"]*)"', source[open_at : i + 1])
                    break
        else:  # pragma: no cover - unreachable on a well-formed module
            raise PredictError(f"{MARKERS_HS}: unterminated list for {name}")
    return out


# ---------------------------------------------------------------------------
# Constants: pinned against the runtime source
# ---------------------------------------------------------------------------


def _number(source: str, pattern: str, where: str) -> float:
    match = re.search(pattern, source)
    if not match:
        raise PredictError(f"{where}: cannot find {pattern!r}")
    return float(match.group(1))


def read_constants() -> dict[str, float]:
    r5 = R5_TYPES_HS.read_text(encoding="utf-8")
    move = MOVE_HS.read_text(encoding="utf-8")
    onto = ONTOLOGICAL_HS.read_text(encoding="utf-8")
    weights_block = re.search(r"defaultUserConatusWeights = UserConatusWeights\s*\{(.*?)\}", r5, re.S)
    if not weights_block:
        raise PredictError(f"{R5_TYPES_HS}: cannot find defaultUserConatusWeights")
    weights = {
        key: float(value)
        for key, value in re.findall(r"ucw(\w+) = ([0-9.]+)", weights_block.group(1))
    }
    constants = {
        "absolute_floor": _number(r5, r"vcAbsoluteFloor = ([0-9.]+)", R5_TYPES_HS.name),
        "personal_margin": _number(r5, r"vcPersonalMargin = ([0-9.]+)", R5_TYPES_HS.name),
        "baseline_window": _number(r5, r"vcBaselineWindowTurns = ([0-9]+)", R5_TYPES_HS.name),
        "divergence_window": _number(r5, r"vcDivergenceWindow = ([0-9]+)", R5_TYPES_HS.name),
        "drift_margin": _number(move, r"moveDriftMargin = ([0-9.]+)", MOVE_HS.name),
        "resonance_gate": _number(onto, r"resonanceGateThreshold = ([0-9.]+)", ONTOLOGICAL_HS.name),
        "encoder_version": _number(r5, r"r5EncoderVersion = ([0-9]+)", R5_TYPES_HS.name),
    }
    for key in ("Resonance", "Confidence", "Consolidation", "Atmosphere", "Counterfactual"):
        if key not in weights:
            raise PredictError(f"{R5_TYPES_HS}: missing weight ucw{key}")
        constants[f"w_{key.lower()}"] = weights[key]
    expected = {
        "absolute_floor": 0.05,
        "personal_margin": 0.25,
        "baseline_window": 10.0,
        "divergence_window": 8.0,
        "drift_margin": 0.20,
        "resonance_gate": 0.55,
        "encoder_version": 2.0,
        "w_resonance": 0.25,
        "w_confidence": 0.25,
        "w_consolidation": 0.20,
        "w_atmosphere": 0.20,
        "w_counterfactual": 0.10,
    }
    moved = {k: (constants.get(k), v) for k, v in expected.items() if constants.get(k) != v}
    if moved:
        raise PredictError(
            "runtime constants moved; re-derive the probe predictions before "
            f"trusting this tool: {moved}"
        )
    return constants


# ---------------------------------------------------------------------------
# The encoder (QxFx0.User.R5.encodeR5)
# ---------------------------------------------------------------------------


#: Topic-continuity rules the tool can simulate (see the module docstring).
TOPIC_MODES = ("v1", "normalized", "boundary", "negation", "negation2")
#: The rule the *current* runtime implements.  Flipped only when the runtime
#: fix lands; ``read_constants`` pins ``r5EncoderVersion`` so a silent bump
#: fails loudly.
CURRENT_TOPIC_MODE = "negation"
#: Recorded encoder version -> rule that produced the capture.
ENCODER_RULES = {1: "v1", 2: "negation"}
#: Negation particles for the negation-safe candidate rules.  Deliberately
#: narrow: the measured defect class is a negated verb («не хочу»), not every
#: syntactic negation.
NEGATION_WORDS = ("не", "ни", "нет")
#: A word is a run of letters (Unicode-aware), so punctuation never joins or
#: splits a token.
WORD_RE = re.compile(r"[^\W\d_]+", re.UNICODE)
#: Name-like token: an uppercase initial followed by at least one letter.
CAPITALIZED_RE = re.compile(r"[А-ЯЁA-Z][а-яёa-z\-]+")
#: Mention-vs-use rules the tool can simulate.  ``off`` is the current runtime;
#: ``attribution`` treats a reported claim as a report, not as the speaker's act.
MENTION_MODES = ("off", "attribution")
#: The rule the *current* runtime implements (no mention scope yet).
CURRENT_MENTION_MODE = "off"
#: Third-party report verbs.  Deliberately finite: the measured defect class is
#: a doctrinal attribution («так утверждал Шопенгауэр», «Камю писал»).
ATTRIBUTION_VERBS = (
    "писал", "писала", "считал", "считала", "говорил", "говорила",
    "утверждал", "утверждала", "учил", "учила", "называл", "называла",
    "полагал", "полагала", "доказывал", "замечал", "отмечал", "думал",
)
#: Unambiguous report phrases: they carry the attribution themselves.
ATTRIBUTION_PHRASES = ("по мнению", "по словам", "согласно", "цитата", "говорят")
#: First-person tokens.  A speaker present in the utterance is not a report,
#: even when the utterance also quotes someone («Шопенгауэр утверждал, но я
#: так не думаю»).
FIRST_PERSON_WORDS = ("я", "мне", "меня", "мой", "моя", "мое", "мы", "нас", "наш")
#: Third-person pronouns that can carry the attribution subject.
THIRD_PERSON_WORDS = ("он", "она", "они", "его", "ее", "их")
#: Quote characters.  A quoted span is a mention by construction.
QUOTE_CHARS = ("«", "»", "„", "“", "”", '"')


def normalize(text: str) -> str:
    return " ".join(text.replace("ё", "е").lower().split())


def word_tokens(text: str) -> list[str]:
    return WORD_RE.findall(text)


def topic_match(norm: str, last_topic: str, mode: str) -> bool:
    """The topic-continuity bit under one candidate rule.

    ``norm`` is the already-normalized utterance; ``last_topic`` is the raw
    value the runtime carries (``bestTopic`` of the previous turn).
    """
    if mode not in TOPIC_MODES:
        raise PredictError(f"unknown topic mode: {mode!r}")
    if not last_topic or len(last_topic) < 3:
        return False
    if mode == "v1":
        return last_topic in norm
    topic = normalize(last_topic)
    if mode == "normalized":
        return topic in norm
    topic_words = word_tokens(topic)
    if not topic_words:
        return False
    text_words = word_tokens(norm)
    span = len(topic_words)
    window = {"boundary": 0, "negation": 1, "negation2": 2}[mode]
    for start in range(len(text_words) - span + 1):
        if text_words[start : start + span] != topic_words:
            continue
        if window == 0:
            return True
        preceding = text_words[max(0, start - window) : start]
        if not any(word in NEGATION_WORDS for word in preceding):
            return True
    return False


def count_any(text: str, markers: list[str]) -> int:
    return sum(1 for marker in markers if marker in text)


def blank_all(text: str, markers: list[str]) -> str:
    for marker in markers:
        text = text.replace(marker, " § ")
    return text


def is_shouty(word: str) -> bool:
    return len(word) >= 3 and all("А" <= char <= "Я" for char in word)


def clamp01(value: float) -> float:
    return min(1.0, max(0.0, value))


def encode(
    raw: str,
    last_topic: str,
    markers: dict[str, list[str]],
    topic_mode: str = CURRENT_TOPIC_MODE,
) -> dict:
    norm = normalize(raw)
    topic_hit = topic_match(norm, last_topic, topic_mode)
    question = "?" in raw
    exclamations = raw.count("!")
    shouty = sum(1 for word in raw.split() if is_shouty(word))
    distress = count_any(norm, markers["r5DistressMarkers"])
    agency_neg = count_any(norm, markers["r5AgencyNegativeMarkers"])
    cleaned = blank_all(norm, markers["r5AgencyNegativeMarkers"])
    agency_pos = count_any(cleaned, markers["r5AgencyPositiveMarkers"])
    address = count_any(norm, markers["r5ResonanceAddressMarkers"])
    connective = count_any(norm, markers["r5ConsolidationMarkers"])
    alternative = count_any(norm, markers["r5CounterfactualMarkers"])
    topic_bit = 1.0 if topic_hit else 0.0
    question_bit = 1.0 if question else 0.0
    return {
        "resonance": clamp01(0.5 + 0.20 * question_bit + 0.15 * min(1.0, address) + 0.20 * topic_bit),
        "atmosphere": clamp01(0.25 + 0.14 * distress + 0.06 * exclamations + 0.05 * shouty),
        "confidence": clamp01(0.5 + 0.12 * agency_pos - 0.14 * agency_neg),
        "consolidation": clamp01(0.5 + 0.10 * connective + 0.20 * topic_bit),
        "counterfactual": clamp01(0.4 + 0.12 * alternative + 0.08 * question_bit),
        "_hits": {
            "distress": distress,
            "agency_neg": agency_neg,
            "agency_pos": agency_pos,
            "address": address,
            "connective": connective,
            "alternative": alternative,
            "topic": topic_hit,
            "question": question,
            "exclamations": exclamations,
            "shouty": shouty,
        },
    }


def score(state: dict, c: dict[str, float]) -> float:
    return (
        c["w_resonance"] * state["resonance"]
        + c["w_confidence"] * state["confidence"]
        + c["w_consolidation"] * state["consolidation"]
        - c["w_atmosphere"] * state["atmosphere"]
        - c["w_counterfactual"] * (1.0 - state["counterfactual"])
    )


def negative_evidence(state: dict) -> bool:
    return state["atmosphere"] > 0.30 or state["confidence"] < 0.45


def exit_class(baseline, state: dict, value: float, c: dict[str, float]):
    if value < c["absolute_floor"]:
        return "absolute_floor"
    if baseline is not None and negative_evidence(state) and value < baseline - c["personal_margin"]:
        return "relative"
    return None


def update_baseline(baseline, value: float, c: dict[str, float]):
    alpha = 2.0 / (max(1.0, c["baseline_window"]) + 1.0)
    if baseline is None:
        return min(1.0, max(-1.0, value))
    return min(1.0, max(-1.0, (1.0 - alpha) * baseline + alpha * value))


# ---------------------------------------------------------------------------
# The ontological layer (QxFx0.Semantic.Ontological.classifyOntological)
# ---------------------------------------------------------------------------


def axis(text: str, positive: list[str], negative: list[str]) -> float:
    """Negation-safe balance: negatives are counted and blanked first."""
    neg = count_any(text, negative)
    pos = count_any(blank_all(text, negative), positive)
    total = pos + neg
    return 0.0 if total <= 0 else (pos - neg) / total


def classify_ontological(raw: str, markers: dict[str, list[str]]) -> dict[str, float]:
    norm = normalize(raw)
    return {
        "being": axis(norm, markers["beingPositiveMarkers"], markers["beingNegativeMarkers"]),
        "striving": axis(norm, markers["strivingPositiveMarkers"], markers["strivingNegativeMarkers"]),
        "affirmation": axis(
            norm, markers["affirmationPositiveMarkers"], markers["affirmationNegativeMarkers"]
        ),
    }


#: The neutral vector a report resolves to (the speaker performs no act).
NEUTRAL_ONTOLOGICAL = {"being": 0.0, "striving": 0.0, "affirmation": 0.0}


def mention_report(text: str) -> bool:
    """True when the utterance *reports* a claim instead of making one.

    Candidate v1 rule (not runtime yet): the utterance is a report when it
    quotes a span, carries a report phrase, or has a third-party attribution
    verb with a name-like token adjacent to it.  A first-person token vetoes
    the rule — «Шопенгауэр утверждал, что жизнь бессмысленна, но я так не
    думаю» keeps the speaker's own act.

    Deliberately blunt: the whole utterance resolves to neutral, because the
    corpus' post-position form («… — так утверждал Шопенгауэр») puts the
    attribution *after* the claim, so clause-level blanking would keep the
    claim.  Known limitation: a report plus a genuine act in one utterance
    without a first-person token would be lost; no such turn exists in the
    four captures.
    """
    raw = text.split()
    tokens = [normalize(tok).strip(".,!?;:—–«»\"()") for tok in raw]
    norm = " ".join(tokens)
    if any(q in text for q in QUOTE_CHARS):
        return True
    if any(p in norm for p in ATTRIBUTION_PHRASES):
        return True
    verbs = [i for i, tok in enumerate(tokens) if tok in ATTRIBUTION_VERBS]
    if not verbs:
        return False
    if any(tok in FIRST_PERSON_WORDS for tok in tokens):
        return False
    if any(tok in THIRD_PERSON_WORDS for tok in tokens):
        return True
    for index, tok in enumerate(raw):
        cleaned = tok.strip(".,!?;:—–«»\"()")
        if CAPITALIZED_RE.fullmatch(cleaned) and any(abs(index - j) <= 2 for j in verbs):
            return True
    return False


def ontological_vector(text: str, markers: dict[str, list[str]], mention_mode: str) -> dict[str, float]:
    """The vector the move layer consumes under a mention rule."""
    if mention_mode not in MENTION_MODES:
        raise PredictError(f"unknown mention mode {mention_mode!r} (known: {MENTION_MODES})")
    if mention_mode == "attribution" and mention_report(text):
        return dict(NEUTRAL_ONTOLOGICAL)
    return classify_ontological(text, markers)


# ---------------------------------------------------------------------------
# The move layer (QxFx0.Semantic.MoveGraph)
# ---------------------------------------------------------------------------


def state_vector(state: dict) -> list[float]:
    return [state[axis_name] for axis_name in AXES]


def r5_distance(a: list[float], b: list[float]) -> float:
    return sum(abs(x - y) for x, y in zip(a, b))


def viability_target(baseline, c: dict[str, float]) -> list[float]:
    confidence = 0.50 if baseline is None else 0.50 + 0.5 * (min(1.0, max(0.0, baseline)) - 0.50)
    return [0.65, 0.20, confidence, 0.50, 0.50]


def apply_move(vector: list[float], move: str) -> list[float]:
    return [clamp01(x + dx) for x, dx in zip(vector, MOVE_EFFECT[move])]


def move_needed(state: dict, onto: dict, baseline, value: float, c: dict[str, float]) -> bool:
    act_negative = onto["striving"] < 0 or onto["being"] < 0 or onto["affirmation"] < 0
    gate = state["resonance"] > c["resonance_gate"]
    if act_negative and gate:
        return True
    if baseline is not None and negative_evidence(state) and value < baseline - c["drift_margin"]:
        return True
    return False


def plan_move(state: dict, onto: dict, baseline, value: float, c: dict[str, float]):
    if not move_needed(state, onto, baseline, value, c):
        return None
    target = viability_target(baseline, c)
    vector = state_vector(state)
    gate = state["resonance"] > c["resonance_gate"]
    admissible = MOVE_NAMES if gate else [m for m in MOVE_NAMES if m != "affirm_being"]
    before = r5_distance(vector, target)
    best = None
    for move in admissible:  # canonical order: strict '<' keeps the first on ties
        distance = r5_distance(apply_move(vector, move), target)
        if best is None or distance < best[0]:
            best = (distance, move)
    return {
        "move": best[1],
        "distance_before": before,
        "distance_after": best[0],
        "affirm_gate_passed": gate,
    }


# ---------------------------------------------------------------------------
# Corpus simulation
# ---------------------------------------------------------------------------


def read_corpus(path: Path) -> list[dict]:
    rows = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 4:
            raise PredictError(f"{path}:{number}: expected 4 columns, got {len(parts)}")
        dialogue, turn, prompt, arc = parts
        if not turn.isdigit():
            raise PredictError(f"{path}:{number}: turn is not an integer: {turn!r}")
        rows.append({"dialogue": dialogue, "turn": int(turn), "prompt": prompt, "arc": arc})
    if not rows:
        raise PredictError(f"{path}: no data rows")
    return rows


def simulate(
    rows: list[dict],
    markers: dict[str, list[str]],
    c: dict[str, float],
    topics: dict[tuple[str, int], str] | None = None,
    topic_mode: str = CURRENT_TOPIC_MODE,
    mention_mode: str = CURRENT_MENTION_MODE,
) -> list[dict]:
    """Predict one dialogue's trajectory.

    ``last_topic`` is threaded as the previous turn's best topic.  The corpus
    alone cannot know the runtime's topic extraction, so the default mode
    assumes the topic bit is 0 from turn 2 on (a pre-registration convention
    that must hold by construction).  ``topics`` replays *measured* topics for
    a post-hoc diagnostic: ``topics[(dialogue, turn)]`` is the topic the
    runtime carried out of that turn, which is what the next turn receives.
    """
    baseline = None
    out = []
    for row in rows:
        if topics is None:
            last_topic = ""
        else:
            last_topic = topics.get((row["dialogue"], row["turn"] - 1), "")
        state = encode(row["prompt"], last_topic, markers, topic_mode)
        value = score(state, c)
        onto = ontological_vector(row["prompt"], markers, mention_mode)
        exit_ = exit_class(baseline, state, value, c)
        plan = None if exit_ else plan_move(state, onto, baseline, value, c)
        out.append(
            {
                **row,
                "score": value,
                "baseline_prior": baseline,
                "baseline_after": update_baseline(baseline, value, c),
                "threshold": None if baseline is None else baseline - c["personal_margin"],
                "exit_class": exit_,
                "protocol_b": exit_ is not None,
                "negative_evidence": negative_evidence(state),
                "move": None if plan is None else plan["move"],
                "affirm_gate_passed": None if plan is None else plan["affirm_gate_passed"],
                "distance_before": None if plan is None else plan["distance_before"],
                "distance_after": None if plan is None else plan["distance_after"],
                "state": {axis_name: state[axis_name] for axis_name in AXES},
                "onto": onto,
                "hits": state["_hits"],
            }
        )
        baseline = out[-1]["baseline_after"]
    return out


def predict_corpus(
    path: Path,
    markers,
    c,
    topics=None,
    topic_mode=CURRENT_TOPIC_MODE,
    mention_mode=CURRENT_MENTION_MODE,
) -> list[dict]:
    rows = read_corpus(path)
    by_dialogue: dict[str, list[dict]] = {}
    for row in rows:
        by_dialogue.setdefault(row["dialogue"], []).append(row)
    predicted = []
    for dialogue, turns in by_dialogue.items():
        turns.sort(key=lambda r: r["turn"])
        expected = list(range(1, len(turns) + 1))
        if [r["turn"] for r in turns] != expected:
            raise PredictError(f"{path}: dialogue {dialogue!r} turns are not 1..{len(turns)}")
        # Default mode: the probe convention holds (no prompt after turn 1
        # repeats the carried topic word), so the topic bit is 0 from turn 2
        # on.  ``topics`` replays measured topics instead (diagnostic only).
        predicted.extend(simulate(turns, markers, c, topics, topic_mode, mention_mode))
    return predicted


def read_measured_topics(run_dir: Path, session_prefix: str = "") -> dict[tuple[str, int], str]:
    """Read each turn's measured best topic (``scene_request``) from a capture.

    ``scene_request`` is the runtime's own topic for the turn, and the next
    turn receives it as ``ssLastTopic`` — the value ``encodeR5`` sees.  This is
    a post-hoc diagnostic input: it is measured data, never a prediction.
    """
    run_dir = Path(run_dir)
    database = run_dir / "capture.db"
    if not database.is_file():
        raise PredictError(f"{database}: missing capture database")
    if not session_prefix:
        session_prefix = f"cap-{run_dir.name}-"
    connection = sqlite3.connect(f"file:{database}?mode=ro", uri=True)
    try:
        topics: dict[tuple[str, int], str] = {}
        for session, turn, request in connection.execute(
            "select session_id, turn, scene_request from turn_quality"
        ):
            if not session.startswith(session_prefix):
                continue
            topics[(session[len(session_prefix):], turn)] = request or ""
    finally:
        connection.close()
    if not topics:
        raise PredictError(f"{database}: no turns with session prefix {session_prefix!r}")
    return topics


# ---------------------------------------------------------------------------
# What-if: topic-rule candidates (measured delta, before any runtime change)
# ---------------------------------------------------------------------------


def what_if(
    corpus: Path,
    markers,
    c,
    topics=None,
    modes=TOPIC_MODES,
    reference_mode: str = CURRENT_TOPIC_MODE,
) -> dict:
    """Run one corpus under every topic rule and diff against a reference rule.

    The baseline is recomputed per mode, so a changed topic bit propagates
    through the EMA exactly as it would at runtime; a turn can therefore move
    even when its own topic bit did not change.
    """
    reference = predict_corpus(corpus, markers, c, topics, reference_mode)
    reference_index = {(r["dialogue"], r["turn"]): r for r in reference}
    summary = []
    deltas = []
    for mode in modes:
        predicted = reference if mode == reference_mode else predict_corpus(
            corpus, markers, c, topics, mode
        )
        changed = 0
        low = None
        high = None
        for row in predicted:
            key = (row["dialogue"], row["turn"])
            base = reference_index[key]
            delta = row["score"] - base["score"]
            low = delta if low is None else min(low, delta)
            high = delta if high is None else max(high, delta)
            exit_changed = row["exit_class"] != base["exit_class"]
            move_changed = row["move"] != base["move"]
            if abs(delta) > 1e-12 or exit_changed or move_changed:
                changed += 1
            deltas.append(
                {
                    "mode": mode,
                    "dialogue": row["dialogue"],
                    "turn": row["turn"],
                    "reference_score": base["score"],
                    "reference_exit": base["exit_class"],
                    "reference_move": base["move"],
                    "reference_topic": base["hits"]["topic"],
                    "score": row["score"],
                    "exit_class": row["exit_class"],
                    "move": row["move"],
                    "topic": row["hits"]["topic"],
                    "delta": delta,
                    "changed": abs(delta) > 1e-12 or exit_changed or move_changed,
                }
            )
        summary.append(
            {
                "mode": mode,
                "changed_turns": changed,
                "exits": sum(1 for row in predicted if row["exit_class"]),
                "moves": sum(1 for row in predicted if row["move"]),
                "delta_min": low,
                "delta_max": high,
            }
        )
    return {
        "corpus": str(corpus),
        "topics": "measured" if topics is not None else "corpus convention",
        "reference_mode": reference_mode,
        "summary": summary,
        "turns": deltas,
    }


def render_what_if(result: dict) -> str:
    lines = [
        f"# what-if: topic-continuity rules on {result['corpus']}",
        f"# topics: {result['topics']}",
        f"# reference: {result['reference_mode']} (the diff baseline)",
        "",
        "mode        changed   exits  moves   delta range",
    ]
    for row in result["summary"]:
        low = "-" if row["delta_min"] is None else f"{row['delta_min']:+.4f}"
        high = "-" if row["delta_max"] is None else f"{row['delta_max']:+.4f}"
        lines.append(
            f"{row['mode']:12s} {row['changed_turns']:7d} {row['exits']:7d} "
            f"{row['moves']:6d}   {low} .. {high}"
        )
    detail = [row for row in result["turns"] if row["changed"]]
    if detail:
        lines += [
            "",
            "# per-turn deltas (only turns that move; a turn can move because an",
            "# earlier turn changed the EMA baseline, not only through its own bit)",
            "mode        dialogue            turn  ref score  ref exit  ref move          "
            "cand score  cand exit  cand move         delta    topic",
        ]
        for row in detail:
            lines.append(
                f"{row['mode']:12s}{row['dialogue']:20s} {row['turn']:4d}  "
                f"{row['reference_score']:+.4f}  "
                f"{str(row['reference_exit'] or '-'):9s} "
                f"{str(row['reference_move'] or '-'):17s} "
                f"{row['score']:+.4f}  {str(row['exit_class'] or '-'):9s} "
                f"{str(row['move'] or '-'):17s} {row['delta']:+.4f}  "
                f"{'hit' if row['topic'] else '-'}"
            )
    else:
        lines += ["", "# no turn moves under any candidate rule"]
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# What-if: mention-vs-use candidates (ontological layer only)
# ---------------------------------------------------------------------------


def what_if_mention(
    corpus: Path,
    markers,
    c,
    topics=None,
    topic_mode: str = CURRENT_TOPIC_MODE,
    modes=MENTION_MODES,
    reference_mode: str = CURRENT_MENTION_MODE,
) -> dict:
    """Run one corpus under every mention rule and diff the move layer.

    The mention rule changes only ``classifyOntological``'s output, so the
    score, the contour and the EMA baseline are identical by construction;
    the diff is the ontological vector and the move it feeds.
    """
    reference = predict_corpus(corpus, markers, c, topics, topic_mode, reference_mode)
    reference_index = {(r["dialogue"], r["turn"]): r for r in reference}
    summary = []
    deltas = []
    for mode in modes:
        predicted = reference if mode == reference_mode else predict_corpus(
            corpus, markers, c, topics, topic_mode, mode
        )
        changed = 0
        for row in predicted:
            key = (row["dialogue"], row["turn"])
            base = reference_index[key]
            move_changed = row["move"] != base["move"]
            vector_changed = row["onto"] != base["onto"]
            if move_changed or vector_changed:
                changed += 1
            deltas.append(
                {
                    "mode": mode,
                    "dialogue": row["dialogue"],
                    "turn": row["turn"],
                    "reference_move": base["move"],
                    "reference_onto": base["onto"],
                    "move": row["move"],
                    "onto": row["onto"],
                    "report": mention_report(row["prompt"]),
                    "changed": move_changed or vector_changed,
                }
            )
        summary.append(
            {
                "mode": mode,
                "changed_turns": changed,
                "moves": sum(1 for row in predicted if row["move"]),
                "reports": sum(1 for row in predicted if mention_report(row["prompt"])),
            }
        )
    return {
        "corpus": str(corpus),
        "topics": "measured" if topics is not None else "corpus convention",
        "reference_mode": reference_mode,
        "summary": summary,
        "turns": deltas,
    }


def render_what_if_mention(result: dict) -> str:
    lines = [
        f"# what-if: mention-vs-use rules on {result['corpus']}",
        f"# topics: {result['topics']}",
        f"# reference: {result['reference_mode']} (the diff baseline)",
        "",
        "mode          changed   moves  reports",
    ]
    for row in result["summary"]:
        lines.append(
            f"{row['mode']:12s} {row['changed_turns']:7d} {row['moves']:6d} "
            f"{row['reports']:8d}"
        )
    detail = [row for row in result["turns"] if row["changed"]]
    if detail:
        lines += [
            "",
            "# per-turn deltas (the score and the contour never move: the rule",
            "# touches the ontological vector only)",
            "mode        dialogue            turn  ref move          cand move         onto (ref -> cand)",
        ]
        for row in detail:
            lines.append(
                f"{row['mode']:12s}{row['dialogue']:20s} {row['turn']:4d}  "
                f"{str(row['reference_move'] or '-'):17s} {str(row['move'] or '-'):17s} "
                f"{row['reference_onto']} -> {row['onto']}"
            )
    else:
        lines += ["", "# no turn moves under any candidate rule"]
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Verification against a recorded capture
# ---------------------------------------------------------------------------


def verify_capture(run_dir: Path, session_prefix: str, markers, c) -> dict:
    """Recompute every recorded turn and report exact matches.

    Prompts come from the run's ``plan.tsv`` (the DB does not store them),
    topics from ``turn_quality.scene_request`` (the previous turn's best
    topic is exactly what ``encodeR5`` receives), and the measured axes from
    ``turn_quality.replay_trace_json`` -> ``trcUserRegime.urtUserR5``.
    """
    run_dir = Path(run_dir)
    plan = run_dir / "plan.tsv"
    if not plan.is_file():
        raise PredictError(f"{plan}: missing capture plan")
    if not session_prefix:
        session_prefix = f"cap-{run_dir.name}-"
    prompts: dict[tuple[str, int], str] = {}
    for number, line in enumerate(plan.read_text(encoding="utf-8").splitlines(), 1):
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 4:
            raise PredictError(f"{plan}:{number}: expected 4 columns, got {len(parts)}")
        dialogue, turn, prompt, _arc = parts
        prompts[(session_prefix + dialogue, int(turn))] = prompt

    connection = sqlite3.connect(f"file:{run_dir / 'capture.db'}?mode=ro", uri=True)
    try:
        topics: dict[tuple[str, int], str] = {}
        observed: dict[tuple[str, int], tuple[dict, int]] = {}
        for session, turn, request, trace in connection.execute(
            "select session_id, turn, scene_request, replay_trace_json from turn_quality"
        ):
            topics[(session, turn)] = request or ""
            regime = json.loads(trace).get("trace", {}).get("trcUserRegime") or {}
            r5 = regime.get("urtUserR5") or {}
            if r5:
                observed[(session, turn)] = (r5, int(regime.get("urtEncoderVersion", 1)))
    finally:
        connection.close()

    mismatches = []
    rules = set()
    for (session, turn), (r5, version) in sorted(observed.items()):
        prompt = prompts.get((session, turn))
        if prompt is None:
            mismatches.append({"session": session, "turn": turn, "reason": "no prompt"})
            continue
        rule = ENCODER_RULES.get(version)
        if rule is None:
            raise PredictError(
                f"encoder version {version} is not mapped to a topic rule; "
                f"add it to ENCODER_RULES (known: {sorted(ENCODER_RULES)})"
            )
        rules.add(rule)
        last_topic = topics.get((session, turn - 1), "")
        state = encode(prompt, last_topic, markers, rule)
        expected_score = score(state, c)
        diffs = {}
        for axis_name in AXES:
            measured = r5.get("ur5" + axis_name.capitalize())
            if measured is None or abs(state[axis_name] - float(measured)) > 1e-9:
                diffs[axis_name] = (state[axis_name], measured)
        measured_score = r5.get("ur5ConatusScore")
        if diffs or measured_score is None or abs(expected_score - float(measured_score)) > 1e-9:
            mismatches.append(
                {
                    "session": session,
                    "turn": turn,
                    "diffs": diffs,
                    "score": (expected_score, measured_score),
                }
            )
    return {
        "run_dir": str(run_dir),
        "session_prefix": session_prefix,
        "topic_rules": sorted(rules),
        "turns": len(observed),
        "exact_matches": len(observed) - len(mismatches),
        "mismatches": mismatches,
    }


# ---------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------

CASES = []


def case(name):
    def register(fn):
        CASES.append((name, fn))
        return fn

    return register


def _load():
    return read_markers(), read_constants()


@case("lexicons parse from the Haskell source")
def _case_lexicons():
    markers, _ = _load()
    assert len(markers["r5DistressMarkers"]) == 26, len(markers["r5DistressMarkers"])
    assert len(markers["r5AgencyNegativeMarkers"]) == 18
    assert "не хочу" in markers["r5AgencyNegativeMarkers"]
    assert "потому что" in markers["r5ConsolidationMarkers"]


@case("runtime constants are pinned")
def _case_constants():
    _, c = _load()
    assert c["baseline_window"] == 10.0
    assert c["absolute_floor"] == 0.05 and c["personal_margin"] == 0.25
    assert c["drift_margin"] == 0.20 and c["resonance_gate"] == 0.55
    assert c["w_counterfactual"] == 0.10
    assert c["encoder_version"] == 2.0
    assert ENCODER_RULES[int(c["encoder_version"])] == CURRENT_TOPIC_MODE


@case("neutral utterance scores 0.24")
def _case_neutral():
    markers, c = _load()
    state = encode("", "", markers)
    assert state["resonance"] == 0.5 and state["atmosphere"] == 0.25
    assert state["confidence"] == 0.5 and state["consolidation"] == 0.5
    assert abs(state["counterfactual"] - 0.4) < 1e-12
    assert abs(score(state, c) - 0.24) < 1e-12


@case("negation safety: 'не хочу' is not agency-positive")
def _case_negation():
    markers, _ = _load()
    state = encode("не хочу", "", markers)
    assert state["_hits"]["agency_neg"] == 1
    assert state["_hits"]["agency_pos"] == 0
    assert abs(state["confidence"] - 0.36) < 1e-12


@case("axes clamp at 1.0")
def _case_clamp():
    markers, _ = _load()
    loud = encode("!" * 13, "", markers)
    assert loud["atmosphere"] == 1.0, loud["atmosphere"]
    resonant = encode("скажи, что такое свобода?", "свобода", markers)
    assert resonant["resonance"] == 1.0, resonant["resonance"]


@case("topic bit adds 0.09 to the score")
def _case_topic():
    markers, c = _load()
    text = "свобода"
    without = score(encode(text, "", markers), c)
    with_topic = score(encode(text, "свобода", markers), c)
    assert abs(with_topic - without - 0.09) < 1e-12, (with_topic, without)


@case("EMA: first observation initializes, then alpha = 2/11")
def _case_ema():
    _, c = _load()
    assert update_baseline(None, 0.43, c) == 0.43
    moved = update_baseline(0.43, 0.20, c)
    assert abs(moved - (0.43 * 9 / 11 + 0.20 * 2 / 11)) < 1e-12


@case("contour: absolute floor, relative gate, and the 0.0025 margin")
def _case_contour():
    markers, c = _load()
    sub_floor = encode(
        "мне очень грустно, тоскливо, тяжело и одиноко, не хочу ничего делать, нет сил",
        "",
        markers,
    )
    assert exit_class(None, sub_floor, score(sub_floor, c), c) == "absolute_floor"
    calm = encode("скажи, что такое свобода? я хочу понять, потому что это связано с выбором, или, с ответственностью?", "", markers)
    assert abs(score(calm, c) - 0.4175) < 1e-12, score(calm, c)
    negative = encode("мне грустно, тяжело и одиноко, не хочу ничего делать", "", markers)
    assert exit_class(0.4295, negative, score(negative, c), c) == "relative"
    # a neutral state never exits a maximal baseline: 0.4875 - 0.25 < 0.24
    neutral = encode("", "", markers)
    assert exit_class(0.4875, neutral, score(neutral, c), c) is None


@case("drift band: 0.197 fires a mirror move, 0.262 does not")
def _case_drift():
    markers, c = _load()
    drift = encode("мне тревожно, потому что много дел, не знаю зачем", "", markers)
    onto = classify_ontological("мне тревожно, потому что много дел, не знаю зачем", markers)
    assert abs(score(drift, c) - 0.197) < 1e-12
    plan = plan_move(drift, onto, 0.4175, score(drift, c), c)
    assert plan and plan["move"] == "mirror_state" and not plan["affirm_gate_passed"], plan
    mild = encode("мне тревожно, потому что много дел, но я хочу разобраться", "", markers)
    onto_mild = classify_ontological("мне тревожно, потому что много дел, но я хочу разобраться", markers)
    assert plan_move(mild, onto_mild, 0.4175, score(mild, c), c) is None


@case("act branch: negative act with resonance above the gate fires")
def _case_act():
    markers, c = _load()
    text = "скажи, я не хочу жить дальше, но помоги мне понять, что делать"
    state = encode(text, "", markers)
    onto = classify_ontological(text, markers)
    assert state["resonance"] > c["resonance_gate"], state["resonance"]
    assert move_needed(state, onto, None, score(state, c), c) is True


@case("probe corpus parses with contiguous turns")
def _case_corpus():
    path = ROOT / "spec/eval/user_regime_probe_2026-11-14.tsv"
    rows = read_corpus(path)
    assert len(rows) == 19, len(rows)
    assert len({r["dialogue"] for r in rows}) == 4


@case("probe corpus predictions reproduce the pre-registered table")
def _case_predictions():
    markers, c = _load()
    predicted = predict_corpus(ROOT / "spec/eval/user_regime_probe_2026-11-14.tsv", markers, c)
    index = {(r["dialogue"], r["turn"]): r for r in predicted}
    assert abs(index[("probe-rel-exit", 3)]["score"] - 0.121) < 1e-12
    assert index[("probe-rel-exit", 3)]["exit_class"] == "relative"
    assert index[("probe-drift-move", 2)]["move"] == "mirror_state"
    assert index[("probe-drift-move", 2)]["exit_class"] is None
    assert index[("probe-control", 2)]["move"] is None
    assert index[("probe-ema-adapts", 9)]["exit_class"] is None
    assert index[("probe-ema-adapts", 9)]["move"] is None


@case("measured topics: v1 substring hit, v2 whole-word miss")
def _case_topics_from():
    markers, c = _load()
    path = ROOT / "spec/eval/user_regime_probe_2026-11-14.tsv"
    plain = {(r["dialogue"], r["turn"]): r for r in predict_corpus(path, markers, c)}
    topics = {("probe-rel-exit", 1): "ответственность"}
    v2 = {(r["dialogue"], r["turn"]): r for r in predict_corpus(path, markers, c, topics)}
    v1 = {
        (r["dialogue"], r["turn"]): r
        for r in predict_corpus(path, markers, c, topics, "v1")
    }
    # The corpus convention assumes no prompt after turn 1 repeats the carried
    # topic word; the runtime does, so the convention is not the measurement.
    assert plain[("probe-rel-exit", 2)]["hits"]["topic"] is False
    # v1 matched «ответственность» inside the instrumental «ответственностью»;
    # v2 requires a whole word, so the same turn no longer counts.
    assert v1[("probe-rel-exit", 2)]["hits"]["topic"] is True
    assert v2[("probe-rel-exit", 2)]["hits"]["topic"] is False
    # resonance clamps at 1.0 under v1, so the score moves by 0.0775, not 0.09
    assert abs(v1[("probe-rel-exit", 2)]["score"] - 0.507) < 1e-12
    assert abs(v2[("probe-rel-exit", 2)]["score"] - 0.4295) < 1e-12


@case("topic rules: substring vs word boundary vs negation")
def _case_topic_rules():
    instrumental = "скажи, что такое выбор? это связано с ответственностью"
    assert topic_match(instrumental, "ответственность", "v1") is True
    assert topic_match(instrumental, "ответственность", "boundary") is False
    assert topic_match("это связано с ответственность, да", "ответственность", "boundary") is True
    negated = "мне грустно, не хочу ничего делать"
    assert topic_match(negated, "хочу", "v1") is True
    assert topic_match(negated, "хочу", "boundary") is True  # a whole word, but negated
    assert topic_match(negated, "хочу", "negation") is False
    assert topic_match(negated, "хочу", "negation2") is False
    # an occurrence that is not negated still counts
    assert topic_match("не хочу сейчас, но потом хочу", "хочу", "negation") is True
    # the two-token window catches an adverb between the particle and the verb
    assert topic_match("не очень хочу", "хочу", "negation") is True
    assert topic_match("не очень хочу", "хочу", "negation2") is False
    # punctuation never joins or splits a token
    assert topic_match("что такое свобода?", "свобода", "boundary") is True


@case("topic rules: normalization is the topic side only")
def _case_topic_normalized():
    text = normalize("Скажи, что такое СВОБОДА?")
    assert topic_match(text, "СВОБОДА", "v1") is False
    assert topic_match(text, "СВОБОДА", "normalized") is True
    assert topic_match(text, "СВОБОДА", "boundary") is True


#: Measured ``bestTopic`` per turn for the probe corpus (2026-11-14 capture,
#: recorded in ``USER_REGIME_PROBE_PREREG_2026-11-14.md``).  The capture DB is
#: gitignored, so the what-if pin replays the recorded values from here.
PROBE_MEASURED_TOPICS = {
    ("probe-rel-exit", 1): "ответственность",
    ("probe-rel-exit", 2): "ответственность",
    ("probe-rel-exit", 3): "грустно",
    ("probe-rel-exit", 4): "разобраться",
    ("probe-drift-move", 1): "ответственность",
    ("probe-drift-move", 2): "тревожно",
    ("probe-drift-move", 3): "разобраться",
    ("probe-control", 1): "ответственность",
    ("probe-control", 2): "хочу",
    ("probe-control", 3): "разобраться",
    ("probe-ema-adapts", 1): "ответственность",
    ("probe-ema-adapts", 2): "хочу",
    ("probe-ema-adapts", 3): "хочу",
    ("probe-ema-adapts", 4): "хочу",
    ("probe-ema-adapts", 5): "хочу",
    ("probe-ema-adapts", 6): "хочу",
    ("probe-ema-adapts", 7): "хочу",
    ("probe-ema-adapts", 8): "хочу",
    ("probe-ema-adapts", 9): "грустно",
}


@case("what-if: the negation rule moves the probe where the capture measured it")
def _case_what_if():
    markers, c = _load()
    path = ROOT / "spec/eval/user_regime_probe_2026-11-14.tsv"
    result = what_if(
        path, markers, c, PROBE_MEASURED_TOPICS, ("v1", "boundary", "negation"), "v1"
    )
    turns = {(r["mode"], r["dialogue"], r["turn"]): r for r in result["turns"]}
    # instrumental case: a substring hit under v1, no hit at a word boundary
    rel2 = turns[("negation", "probe-rel-exit", 2)]
    assert rel2["reference_topic"] is True and rel2["topic"] is False
    assert abs(rel2["reference_score"] - 0.507) < 1e-12
    assert abs(rel2["score"] - 0.4295) < 1e-12
    # the adapted-baseline turn: the act branch closes, the drift branch opens
    t9 = turns[("negation", "probe-ema-adapts", 9)]
    assert t9["reference_topic"] is True and t9["topic"] is False
    assert abs(t9["reference_score"] - 0.211) < 1e-12
    assert abs(t9["score"] - 0.121) < 1e-12
    assert t9["reference_move"] == "open_alternative" and t9["move"] == "mirror_state"
    # a genuine whole-word repeat is not a defect and must not move
    ctrl3 = turns[("negation", "probe-control", 3)]
    assert ctrl3["topic"] is True and ctrl3["changed"] is False
    # a word boundary alone does not close the negated-verb hit
    t9_boundary = turns[("boundary", "probe-ema-adapts", 9)]
    assert t9_boundary["topic"] is True and t9_boundary["move"] == "open_alternative"


@case("mention: attribution and quotation are reports, questions are not")
def _case_mention_report():
    assert mention_report("кажется, жизнь бессмысленна — так утверждал Шопенгауэр?") is True
    assert mention_report("а Камю писал о самоубийстве как проблеме философии — это про абсурд?") is True
    assert mention_report("Камю считал, что абсурд возникает из столкновения человека и мира?") is True
    assert mention_report("«жизнь бессмысленна»") is True
    assert mention_report("по мнению Шопенгауэра, жизнь бессмысленна") is True
    # the speaker is present: the act stays the speaker's
    assert mention_report("я считаю, что жизнь бессмысленна") is False
    assert mention_report("Шопенгауэр утверждал, что жизнь бессмысленна, но я так не думаю") is False
    # a question about a concept is not a report
    assert mention_report("отчаяние — это когда нет смысла?") is False
    assert mention_report("как ты думаешь, почему всё кажется бессмысленным?") is False
    assert mention_report("мне грустно и одиноко") is False


@case("mention what-if: one decoy move on the multi-turn corpus, none on the probe")
def _case_what_if_mention():
    markers, c = _load()
    path = ROOT / "spec/eval/user_regime_multiturn_2026-11-13.tsv"
    result = what_if_mention(path, markers, c)
    summary = {row["mode"]: row for row in result["summary"]}
    assert summary["off"]["moves"] == 4 and summary["attribution"]["moves"] == 3
    assert summary["attribution"]["changed_turns"] == 1
    assert summary["attribution"]["reports"] == 3
    turns = {(r["mode"], r["dialogue"], r["turn"]): r for r in result["turns"]}
    decoy2 = turns[("attribution", "decoy-pessimism", 2)]
    assert decoy2["reference_move"] == "mirror_state" and decoy2["move"] is None
    assert decoy2["report"] is True and decoy2["onto"]["being"] == 0.0
    # the genuine act turn is untouched: no attribution, vector unchanged
    act2 = turns[("attribution", "move-act", 2)]
    assert act2["report"] is False and act2["move"] == "mirror_state"
    assert act2["onto"]["being"] == -1.0
    # the two concept-in-question decoys are not mentions and stay moves
    for dialogue, turn in (("decoy-pessimism", 4), ("mixed-decoy", 6)):
        row = turns[("attribution", dialogue, turn)]
        assert row["report"] is False and row["move"] == "mirror_state"
    probe = what_if_mention(ROOT / "spec/eval/user_regime_probe_2026-11-14.tsv", markers, c)
    assert {row["mode"]: row for row in probe["summary"]}["attribution"]["changed_turns"] == 0


def self_test() -> int:
    failures = 0
    for name, fn in CASES:
        try:
            fn()
        except AssertionError as error:
            failures += 1
            print(f"FAIL {name}: {error}")
        except PredictError as error:
            failures += 1
            print(f"FAIL {name}: {error}")
        else:
            print(f"ok   {name}")
    total = len(CASES)
    print(f"\n{total - failures}/{total} cases passed")
    return 0 if failures == 0 else 2


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def render_table(predicted: list[dict]) -> str:
    lines = [
        "dialogue              turn  arc       score   prior   thresh  exit           move                 gate   base_after",
    ]
    for row in predicted:
        prior = "-" if row["baseline_prior"] is None else f"{row['baseline_prior']:.4f}"
        threshold = "-" if row["threshold"] is None else f"{row['threshold']:.4f}"
        lines.append(
            f"{row['dialogue']:20s} {row['turn']:4d}  {row['arc']:8s} "
            f"{row['score']:+.4f} {prior:>7s} {threshold:>7s}  "
            f"{str(row['exit_class'] or '-'):14s} {str(row['move'] or '-'):20s} "
            f"{str(row['affirm_gate_passed']):5s}  {row['baseline_after']:+.4f}"
        )
    return "\n".join(lines)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        description="Predict the user-side R5 regime for a probe corpus."
    )
    parser.add_argument("--corpus", help="probe corpus TSV (dialogue, turn, prompt, arc)")
    parser.add_argument("--verify-capture", help="recorded capture run directory (capture.db + plan.tsv)")
    parser.add_argument(
        "--topics-from",
        help="capture run directory: replay measured best topics (post-hoc diagnostic)",
    )
    parser.add_argument("--session-prefix", default="", help="session-id prefix (default: cap-<run-directory-name>-)")
    parser.add_argument(
        "--topic-mode",
        choices=TOPIC_MODES,
        default=CURRENT_TOPIC_MODE,
        help=f"topic-continuity rule (default: {CURRENT_TOPIC_MODE}, the runtime rule)",
    )
    parser.add_argument(
        "--what-if",
        action="store_true",
        help="run every topic rule and diff the trajectories against a reference rule",
    )
    parser.add_argument(
        "--what-if-reference",
        choices=TOPIC_MODES,
        default=CURRENT_TOPIC_MODE,
        help=f"diff baseline for --what-if (default: {CURRENT_TOPIC_MODE})",
    )
    parser.add_argument(
        "--mention-mode",
        choices=MENTION_MODES,
        default=CURRENT_MENTION_MODE,
        help=f"mention-vs-use rule (default: {CURRENT_MENTION_MODE}, the runtime rule)",
    )
    parser.add_argument(
        "--what-if-mention",
        action="store_true",
        help="run every mention rule and diff the ontological vectors and moves",
    )
    parser.add_argument("--json", action="store_true", help="machine-readable output")
    parser.add_argument("--self-test", action="store_true", help="run the built-in cases")
    args = parser.parse_args(argv)

    if args.self_test:
        return self_test()
    try:
        markers, constants = _load()
        if args.verify_capture:
            result = verify_capture(Path(args.verify_capture), args.session_prefix, markers, constants)
            if args.json:
                print(json.dumps(result, ensure_ascii=False, indent=2))
            else:
                print(f"run: {result['run_dir']}")
                print(f"turns: {result['turns']}")
                print(f"topic rules: {', '.join(result['topic_rules'])}")
                print(f"exact matches: {result['exact_matches']}/{result['turns']}")
                for mismatch in result["mismatches"][:10]:
                    print(f"  MISMATCH {mismatch}")
            return 0 if result["exact_matches"] == result["turns"] else 1
        if not args.corpus:
            parser.print_usage(sys.stderr)
            return 2
        topics = None
        if args.topics_from:
            topics = read_measured_topics(Path(args.topics_from), args.session_prefix)
        if args.what_if_mention:
            result = what_if_mention(
                Path(args.corpus),
                markers,
                constants,
                topics,
                topic_mode=args.topic_mode,
                reference_mode=args.mention_mode,
            )
            if args.json:
                print(json.dumps(result, ensure_ascii=False, indent=2))
            else:
                if topics is not None:
                    print(
                        f"# diagnostic: best topics replayed from {args.topics_from};"
                        " not a pre-registration prediction"
                    )
                print(render_what_if_mention(result))
            return 0
        if args.what_if:
            result = what_if(
                Path(args.corpus),
                markers,
                constants,
                topics,
                reference_mode=args.what_if_reference,
            )
            if args.json:
                print(json.dumps(result, ensure_ascii=False, indent=2))
            else:
                if topics is not None:
                    print(
                        f"# diagnostic: best topics replayed from {args.topics_from};"
                        " not a pre-registration prediction"
                    )
                print(render_what_if(result))
            return 0
        predicted = predict_corpus(
            Path(args.corpus), markers, constants, topics, args.topic_mode, args.mention_mode
        )
        if args.json:
            print(json.dumps(predicted, ensure_ascii=False, indent=2))
        else:
            if topics is not None:
                print(
                    f"# diagnostic: best topics replayed from {args.topics_from};"
                    " not a pre-registration prediction"
                )
            if args.topic_mode != CURRENT_TOPIC_MODE:
                print(f"# topic rule: {args.topic_mode} (what-if, not the runtime rule)")
            if args.mention_mode != CURRENT_MENTION_MODE:
                print(f"# mention rule: {args.mention_mode} (what-if, not the runtime rule)")
            print(render_table(predicted))
        return 0
    except (PredictError, OSError, sqlite3.Error) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
