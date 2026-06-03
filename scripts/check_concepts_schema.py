#!/usr/bin/env python3
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONCEPTS = ROOT / "semantics" / "concepts.nix"

CANONICAL_FAMILIES = {
    "CMGround": "ContentLayer",
    "CMDefine": "ContentLayer",
    "CMDistinguish": "ContentLayer",
    "CMReflect": "MetaLayer",
    "CMDescribe": "ContentLayer",
    "CMPurpose": "ContentLayer",
    "CMHypothesis": "MetaLayer",
    "CMRepair": "MetaLayer",
    "CMContact": "ContactLayer",
    "CMAnchor": "ContentLayer",
    "CMClarify": "MetaLayer",
    "CMDeepen": "MetaLayer",
    "CMConfront": "MetaLayer",
    "CMNextStep": "MetaLayer",
}

ALLOWED_STANCES = {
    "grounded",
    "exploratory",
    "honest",
    "firm",
    "analytical",
    "tentative",
    "direct",
}


def load_concepts() -> dict:
    expr = f"builtins.toJSON (import {json.dumps(str(CONCEPTS))})"
    proc = subprocess.run(
        ["nix-instantiate", "--eval", "--json", "-E", expr],
        check=False,
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise SystemExit(f"failed to evaluate concepts.nix: {proc.stderr.strip()}")
    try:
        decoded = json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"failed to decode concepts.nix JSON: {exc}") from exc
    if isinstance(decoded, str):
        try:
            decoded = json.loads(decoded)
        except json.JSONDecodeError as exc:
            raise SystemExit(f"failed to decode nested concepts.nix JSON: {exc}") from exc
    if not isinstance(decoded, dict):
        raise SystemExit(f"unexpected concepts.nix payload type: {type(decoded).__name__}")
    return decoded


def require(condition: bool, message: str, errors: list[str]) -> None:
    if not condition:
        errors.append(message)


def main() -> None:
    payload = load_concepts()
    errors: list[str] = []

    thresholds = payload.get("constitutionalThresholds")
    require(isinstance(thresholds, dict), "missing constitutionalThresholds object", errors)
    if isinstance(thresholds, dict):
        require("agencyFloor" in thresholds, "constitutionalThresholds.agencyFloor missing", errors)
        require("tensionCeiling" in thresholds, "constitutionalThresholds.tensionCeiling missing", errors)

    concepts = payload.get("concepts")
    require(isinstance(concepts, list) and len(concepts) > 0, "concepts must be a non-empty list", errors)
    if not isinstance(concepts, list):
        concepts = []

    ids: list[str] = []
    for idx, concept in enumerate(concepts):
        prefix = f"concept[{idx}]"
        require(isinstance(concept, dict), f"{prefix} must be an attribute set", errors)
        if not isinstance(concept, dict):
            continue
        for field in ["id", "name", "layer", "family", "stance", "prohibitedIf", "minAgency", "minTension"]:
            require(field in concept, f"{prefix}.{field} missing", errors)
        concept_id = concept.get("id")
        if isinstance(concept_id, str):
            ids.append(concept_id)
        else:
            errors.append(f"{prefix}.id must be a string")
        require(isinstance(concept.get("name"), str) and concept.get("name"), f"{prefix}.name must be a non-empty string", errors)
        family = concept.get("family")
        layer = concept.get("layer")
        stance = concept.get("stance")
        require(family in CANONICAL_FAMILIES, f"{prefix}.family invalid: {family!r}", errors)
        require(layer in set(CANONICAL_FAMILIES.values()), f"{prefix}.layer invalid: {layer!r}", errors)
        if family in CANONICAL_FAMILIES:
            require(layer == CANONICAL_FAMILIES[family], f"{prefix}.layer must equal canonical layer {CANONICAL_FAMILIES[family]} for family {family}", errors)
        require(stance in ALLOWED_STANCES, f"{prefix}.stance invalid: {stance!r}", errors)
        for numeric_field in ["minAgency", "minTension"]:
            value = concept.get(numeric_field)
            require(value is None or isinstance(value, (int, float)), f"{prefix}.{numeric_field} must be null or numeric", errors)
        prohibited = concept.get("prohibitedIf")
        require(isinstance(prohibited, list), f"{prefix}.prohibitedIf must be a list", errors)
        if isinstance(prohibited, list):
            for item in prohibited:
                require(isinstance(item, str) and item, f"{prefix}.prohibitedIf entries must be non-empty strings", errors)

    if len(ids) != len(set(ids)):
        errors.append("concept ids must be unique")
    id_set = set(ids)
    for idx, concept in enumerate(concepts):
        prohibited = concept.get("prohibitedIf", [])
        if isinstance(prohibited, list):
            for ref in prohibited:
                if isinstance(ref, str):
                    require(ref in id_set, f"concept[{idx}].prohibitedIf references unknown id {ref!r}", errors)

    if errors:
        raise SystemExit("concepts schema invalid:\n- " + "\n- ".join(errors))

    print(f"concepts schema OK ({len(concepts)} concepts)")


if __name__ == "__main__":
    main()
