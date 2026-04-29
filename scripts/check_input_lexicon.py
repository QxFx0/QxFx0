#!/usr/bin/env python3
import json
import os
import re
import sys
from typing import Any


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, ".."))

LEXICON_PATH = os.path.join(REPO_ROOT, "resources", "input_lexicon", "lexicon.json")
GENERATED_HS_PATH = os.path.join(REPO_ROOT, "src", "QxFx0", "Semantic", "Input", "GeneratedLexicon.hs")
COVERAGE_PATH = os.path.join(REPO_ROOT, "reports", "input_coverage_report.json")
COLLISION_PATH = os.path.join(REPO_ROOT, "reports", "input_collision_report.json")
UNKNOWN_PATH = os.path.join(REPO_ROOT, "reports", "input_unknown_candidates.json")

ALLOWED_POS = {
    "PosNoun",
    "PosAdjective",
    "PosVerb",
    "PosAdverb",
    "PosPronoun",
    "PosNumeral",
    "PosPreposition",
    "PosConjunction",
    "PosParticle",
    "PosInterjection",
    "PosUnknown",
}

ALLOWED_SEM = {
    "SemWorldObject",
    "SemPhysicalObject",
    "SemWorldPhenomenon",
    "SemMentalObject",
    "SemAbstractConcept",
    "SemQualityProperty",
    "SemPurposeFunction",
    "SemRelation",
    "SemAction",
    "SemState",
    "SemCause",
    "SemComparison",
    "SemIdentity",
    "SemKnowledge",
    "SemDialogueRepair",
    "SemDialogueInvitation",
    "SemSelfReference",
    "SemUserReference",
    "SemContemplative",
    "SemUnknown",
}

REQUIRED_LEMMAS = {
    "логика",
    "смысл",
    "правда",
    "субъектность",
    "функция",
    "стол",
    "думать",
    "скрываться",
    "поговорить",
}

REQUIRED_FORMS = {
    "логике",
    "функции",
    "стола",
    "поговорим",
}


def read_json(path: str) -> Any:
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def fail(errors: list[str]) -> int:
    for msg in errors:
        print(f"FAIL: {msg}")
    return 1


def main() -> int:
    errors: list[str] = []

    for required_path in [LEXICON_PATH, GENERATED_HS_PATH, COVERAGE_PATH, COLLISION_PATH, UNKNOWN_PATH]:
        if not os.path.exists(required_path):
            errors.append(f"missing artifact: {os.path.relpath(required_path, REPO_ROOT)}")

    if errors:
        return fail(errors)

    lexicon = read_json(LEXICON_PATH)
    coverage = read_json(COVERAGE_PATH)
    collisions = read_json(COLLISION_PATH)
    unknown = read_json(UNKNOWN_PATH)

    form_to_lemma = lexicon.get("form_to_lemma")
    lemma_to_pos = lexicon.get("lemma_to_pos")
    lemma_to_sem = lexicon.get("lemma_to_sem")

    if not isinstance(form_to_lemma, dict):
        errors.append("lexicon.form_to_lemma must be an object")
        form_to_lemma = {}
    if not isinstance(lemma_to_pos, dict):
        errors.append("lexicon.lemma_to_pos must be an object")
        lemma_to_pos = {}
    if not isinstance(lemma_to_sem, dict):
        errors.append("lexicon.lemma_to_sem must be an object")
        lemma_to_sem = {}

    if len(form_to_lemma) < 300:
        errors.append(f"lexicon too small: forms={len(form_to_lemma)} (expected >= 300)")
    if len(lemma_to_pos) < 100:
        errors.append(f"lexicon too small: lemmas={len(lemma_to_pos)} (expected >= 100)")

    for lemma in sorted(REQUIRED_LEMMAS):
        if lemma not in lemma_to_pos:
            errors.append(f"required lemma missing: {lemma}")
    for form in sorted(REQUIRED_FORMS):
        if form not in form_to_lemma:
            errors.append(f"required form missing: {form}")

    if lemma_to_sem.get("функция") and "SemPurposeFunction" not in lemma_to_sem["функция"]:
        errors.append("lemma `функция` must include SemPurposeFunction")
    if lemma_to_sem.get("правда") and "SemAbstractConcept" not in lemma_to_sem["правда"]:
        errors.append("lemma `правда` must include SemAbstractConcept")

    for form, lemma in form_to_lemma.items():
        if not isinstance(form, str) or not form:
            errors.append("form_to_lemma contains non-string/empty key")
            continue
        if not isinstance(lemma, str) or not lemma:
            errors.append(f"invalid lemma mapping for form `{form}`")
            continue
        if lemma not in lemma_to_pos:
            errors.append(f"form `{form}` points to missing lemma in lemma_to_pos: `{lemma}`")
        if lemma not in lemma_to_sem:
            errors.append(f"form `{form}` points to missing lemma in lemma_to_sem: `{lemma}`")

    for lemma, pos in lemma_to_pos.items():
        if pos not in ALLOWED_POS:
            errors.append(f"lemma `{lemma}` has invalid POS: {pos}")

    for lemma, sem_list in lemma_to_sem.items():
        if not isinstance(sem_list, list) or not sem_list:
            errors.append(f"lemma `{lemma}` has empty/non-list semantic classes")
            continue
        bad_sem = [sem for sem in sem_list if sem not in ALLOWED_SEM]
        if bad_sem:
            errors.append(f"lemma `{lemma}` has invalid semantic classes: {bad_sem}")

    total_forms = coverage.get("total_forms")
    total_lemmas = coverage.get("total_lemmas")
    if total_forms != len(form_to_lemma):
        errors.append(f"coverage.total_forms mismatch: {total_forms} vs {len(form_to_lemma)}")
    if total_lemmas != len(lemma_to_pos):
        errors.append(f"coverage.total_lemmas mismatch: {total_lemmas} vs {len(lemma_to_pos)}")
    if not isinstance(coverage.get("pos_distribution"), dict):
        errors.append("coverage.pos_distribution must be an object")
    if not isinstance(coverage.get("sem_distribution"), dict):
        errors.append("coverage.sem_distribution must be an object")

    collision_count = collisions.get("collisions")
    collision_samples = collisions.get("samples")
    if not isinstance(collision_count, int) or collision_count < 0:
        errors.append("collision report field `collisions` must be non-negative integer")
        collision_count = 0
    if not isinstance(collision_samples, list):
        errors.append("collision report field `samples` must be a list")
        collision_samples = []
    if collision_count > len(form_to_lemma):
        errors.append("collision count exceeds form count")
    for sample in collision_samples[:30]:
        if not isinstance(sample, dict):
            errors.append("collision sample entry must be an object")
            continue
        if "form" not in sample or "options" not in sample:
            errors.append("collision sample entry must include `form` and `options`")
            continue
        if not isinstance(sample["options"], list):
            errors.append("collision sample `options` must be a list")

    unknown_candidates = unknown.get("unknown_candidates")
    total_unknown = unknown.get("total_unknown_candidates")
    if not isinstance(unknown_candidates, list):
        errors.append("unknown report field `unknown_candidates` must be a list")
        unknown_candidates = []
    if not isinstance(total_unknown, int) or total_unknown < 0:
        errors.append("unknown report field `total_unknown_candidates` must be a non-negative integer")
    elif total_unknown < len(unknown_candidates):
        errors.append("unknown report total_unknown_candidates is less than list length")

    with open(GENERATED_HS_PATH, "r", encoding="utf-8") as handle:
        generated_hs = handle.read()

    hs_form_entries = len(re.findall(r'^\s+"[^"]+"\s+->\s+Just\s+"[^"]+"$', generated_hs, flags=re.MULTILINE))
    hs_pos_entries = len(re.findall(r'^\s+"[^"]+"\s+->\s+Just\s+Pos[A-Za-z]+$', generated_hs, flags=re.MULTILINE))
    hs_sem_entries = len(re.findall(r'^\s+"[^"]+"\s+->\s+\[[^\]]*\]$', generated_hs, flags=re.MULTILINE))

    if hs_form_entries != len(form_to_lemma):
        errors.append(f"GeneratedLexicon form entries mismatch: {hs_form_entries} vs {len(form_to_lemma)}")
    if hs_pos_entries != len(lemma_to_pos):
        errors.append(f"GeneratedLexicon POS entries mismatch: {hs_pos_entries} vs {len(lemma_to_pos)}")
    if hs_sem_entries != len(lemma_to_sem):
        errors.append(f"GeneratedLexicon semantic entries mismatch: {hs_sem_entries} vs {len(lemma_to_sem)}")

    if errors:
        return fail(errors)

    print(
        "OK: input lexicon artifacts are consistent "
        f"(forms={len(form_to_lemma)} lemmas={len(lemma_to_pos)} collisions={collision_count} unknown_total={total_unknown})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
