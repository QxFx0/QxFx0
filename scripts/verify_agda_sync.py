#!/usr/bin/env python3
"""Verify Agda↔Haskell constructor sync for core R5/legitimacy constructors."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent

AGDA_CANONICAL_FILE = ROOT / "spec" / "Sovereignty.agda"
AGDA_R5CORE_FILE = ROOT / "spec" / "R5Core.agda"
AGDA_LEGIT_FILE = ROOT / "spec" / "Legitimacy.agda"

HS_CANONICAL_FILES = [
    ROOT / "src" / "QxFx0" / "Types.hs",
    ROOT / "src" / "QxFx0" / "Types" / "Domain.hs",
    ROOT / "src" / "QxFx0" / "Types" / "Domain" / "R5.hs",
    ROOT / "src" / "QxFx0" / "Types" / "Decision.hs",
]
HS_R5_TRACE_FILES = [
    ROOT / "src" / "QxFx0" / "Types" / "Domain.hs",
    ROOT / "src" / "QxFx0" / "Types" / "Domain" / "R5.hs",
    ROOT / "src" / "QxFx0" / "Types.hs",
]
HS_LEGIT_FILES = [
    ROOT / "src" / "QxFx0" / "Types" / "Decision" / "Model.hs",
    ROOT / "src" / "QxFx0" / "Types" / "Decision.hs",
    ROOT / "src" / "QxFx0" / "Types.hs",
]
HS_DECISION_ENUM_FILES = [
    ROOT / "src" / "QxFx0" / "Types" / "Decision" / "Enums.hs",
    ROOT / "src" / "QxFx0" / "Types" / "Decision" / "Enums" / "Conversation.hs",
    ROOT / "src" / "QxFx0" / "Types" / "Decision" / "Enums" / "Render.hs",
    ROOT / "src" / "QxFx0" / "Types" / "Decision" / "Enums" / "Governance.hs",
    ROOT / "src" / "QxFx0" / "Types" / "Decision.hs",
    ROOT / "src" / "QxFx0" / "Types.hs",
]


def normalize_ctor(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9_']", "", name)


def parse_agda_data_constructors(path: Path, data_name: str) -> set[str]:
    if not path.exists():
        return set()
    in_type = False
    ctors: set[str] = set()
    for line in path.read_text().splitlines():
        if re.search(rf"\bdata\s+{re.escape(data_name)}\b", line):
            in_type = True
            continue
        if not in_type:
            continue
        m = re.match(r"\s+([A-Za-z][A-Za-z0-9_-]*)\s*:", line)
        if m:
            ctors.add(normalize_ctor(m.group(1)))
            continue
        stripped = line.strip()
        if not stripped or stripped.startswith("--"):
            continue
        if stripped.startswith("{-#") or stripped.startswith("data ") or stripped.startswith("record "):
            break
    return ctors


def parse_haskell_data_constructors(paths: list[Path], data_name: str) -> set[str]:
    ctors: set[str] = set()
    for path in paths:
        if not path.exists():
            continue
        lines = path.read_text().splitlines()
        i = 0
        while i < len(lines):
            line = lines[i]
            if not re.match(rf"^\s*data\s+{re.escape(data_name)}\b", line):
                i += 1
                continue

            saw_eq = False
            body_lines: list[str] = []
            j = i
            while j < len(lines):
                current = lines[j]
                if not saw_eq and "=" in current:
                    saw_eq = True
                    body_lines.append(current.split("=", 1)[1])
                elif saw_eq:
                    if re.match(r"^\s*deriving\b", current):
                        break
                    body_lines.append(current)
                j += 1

            if saw_eq:
                body = "\n".join(body_lines)
                for ctor in re.findall(r"(?:^|\|)\s*([A-Z][A-Za-z0-9_']*)\b", body):
                    ctors.add(normalize_ctor(ctor))
            i = j + 1
    return ctors


def parse_agda_r5core_using_constructors(path: Path) -> set[str]:
    if not path.exists():
        return set()
    text = path.read_text()
    m = re.search(r"open\s+import\s+R5Core\s+using\s*\((.*?)\)", text, re.S)
    if not m:
        return set()
    using_body = m.group(1)
    return {normalize_ctor(token) for token in re.findall(r"\bCM[A-Za-z0-9_-]*\b", using_body)}


def parse_agda_function_mapping(path: Path, function_name: str) -> dict[str, str]:
    if not path.exists():
        return {}
    mapping: dict[str, str] = {}
    pattern = re.compile(
        rf"^\s*{re.escape(function_name)}\s+([A-Za-z][A-Za-z0-9_-]*)\s*=\s*([A-Za-z][A-Za-z0-9_-]*)\s*$"
    )
    for line in path.read_text().splitlines():
        m = pattern.match(line)
        if not m:
            continue
        lhs = normalize_ctor(m.group(1))
        rhs = normalize_ctor(m.group(2))
        mapping[lhs] = rhs
    return mapping


def parse_haskell_function_mapping(paths: list[Path], function_name: str) -> dict[str, str]:
    mapping: dict[str, str] = {}
    pattern = re.compile(
        rf"^\s*{re.escape(function_name)}\s+([A-Z][A-Za-z0-9_']*)\s*=\s*([A-Z][A-Za-z0-9_']*)\s*$"
    )
    for path in paths:
        if not path.exists():
            continue
        for line in path.read_text().splitlines():
            m = pattern.match(line)
            if not m:
                continue
            lhs = normalize_ctor(m.group(1))
            rhs = normalize_ctor(m.group(2))
            if lhs in mapping and mapping[lhs] != rhs:
                mapping[lhs] = "__conflict__"
            else:
                mapping[lhs] = rhs
    return mapping


def verify_pair(label: str, agda_ctors: set[str], hs_ctors: set[str]) -> bool:
    ok = True
    if not agda_ctors:
        print(f"FAIL[{label}]: no Agda constructors found")
        return False
    if not hs_ctors:
        print(f"FAIL[{label}]: no Haskell constructors found")
        return False
    missing_hs = agda_ctors - hs_ctors
    missing_ag = hs_ctors - agda_ctors
    if missing_hs:
        print(f"FAIL[{label}]: in Agda but not Haskell: {sorted(missing_hs)}")
        ok = False
    if missing_ag:
        print(f"FAIL[{label}]: in Haskell but not Agda: {sorted(missing_ag)}")
        ok = False
    if ok:
        print(f"OK[{label}]: {len(agda_ctors)} constructors in sync: {sorted(agda_ctors)}")
    return ok


def verify_mapping_pair(label: str, agda_map: dict[str, str], hs_map: dict[str, str]) -> bool:
    ok = True
    if not agda_map:
        print(f"FAIL[{label}]: no Agda mapping entries found")
        return False
    if not hs_map:
        print(f"FAIL[{label}]: no Haskell mapping entries found")
        return False

    agda_keys = set(agda_map.keys())
    hs_keys = set(hs_map.keys())
    missing_hs = agda_keys - hs_keys
    missing_ag = hs_keys - agda_keys
    if missing_hs:
        print(f"FAIL[{label}]: Agda keys missing in Haskell mapping: {sorted(missing_hs)}")
        ok = False
    if missing_ag:
        print(f"FAIL[{label}]: Haskell keys missing in Agda mapping: {sorted(missing_ag)}")
        ok = False

    shared = sorted(agda_keys & hs_keys)
    mismatches: list[tuple[str, str, str]] = []
    for key in shared:
        hs_value = hs_map[key]
        if hs_value == "__conflict__":
            mismatches.append((key, agda_map[key], "CONFLICT"))
            continue
        if agda_map[key] != hs_value:
            mismatches.append((key, agda_map[key], hs_value))

    if mismatches:
        for key, agda_value, hs_value in mismatches:
            print(f"FAIL[{label}]: {key}: Agda={agda_value}, Haskell={hs_value}")
        ok = False

    if ok:
        print(f"OK[{label}]: {len(shared)} mapping entries in sync")
    return ok


def main() -> int:
    canonical_agda = parse_agda_data_constructors(AGDA_CANONICAL_FILE, "CanonicalMoveFamily")
    if not canonical_agda:
        canonical_agda = parse_agda_r5core_using_constructors(AGDA_CANONICAL_FILE)
    canonical_hs = parse_haskell_data_constructors(HS_CANONICAL_FILES, "CanonicalMoveFamily")
    canonical_r5_agda = parse_agda_data_constructors(AGDA_R5CORE_FILE, "CanonicalMoveFamily")
    force_r5_agda = parse_agda_data_constructors(AGDA_R5CORE_FILE, "IllocutionaryForce")
    layer_r5_agda = parse_agda_data_constructors(AGDA_R5CORE_FILE, "SemanticLayer")
    clause_r5_agda = parse_agda_data_constructors(AGDA_R5CORE_FILE, "ClauseForm")
    warranted_r5_agda = parse_agda_data_constructors(AGDA_R5CORE_FILE, "WarrantedMoveMode")
    force_hs = parse_haskell_data_constructors(HS_R5_TRACE_FILES, "IllocutionaryForce")
    layer_hs = parse_haskell_data_constructors(HS_R5_TRACE_FILES, "SemanticLayer")
    clause_hs = parse_haskell_data_constructors(HS_R5_TRACE_FILES, "ClauseForm")
    warranted_hs = parse_haskell_data_constructors(HS_R5_TRACE_FILES, "WarrantedMoveMode")
    legit_agda = parse_agda_data_constructors(AGDA_LEGIT_FILE, "IsLegit")
    legit_hs = parse_haskell_data_constructors(HS_LEGIT_FILES, "IsLegit")
    legitimacy_reason_agda = parse_agda_data_constructors(AGDA_LEGIT_FILE, "LegitimacyReason")
    legitimacy_reason_hs = parse_haskell_data_constructors(HS_DECISION_ENUM_FILES, "LegitimacyReason")
    disposition_agda = parse_agda_data_constructors(AGDA_LEGIT_FILE, "DecisionDisposition")
    disposition_hs = parse_haskell_data_constructors(HS_DECISION_ENUM_FILES, "DecisionDisposition")
    force_map_agda = parse_agda_function_mapping(AGDA_R5CORE_FILE, "forceForFamily")
    force_map_hs = parse_haskell_function_mapping(HS_R5_TRACE_FILES, "forceForFamily")
    clause_map_agda = parse_agda_function_mapping(AGDA_R5CORE_FILE, "clauseFormForIF")
    clause_map_hs = parse_haskell_function_mapping(HS_R5_TRACE_FILES, "clauseFormForIF")
    layer_map_agda = parse_agda_function_mapping(AGDA_R5CORE_FILE, "layerForFamily")
    layer_map_hs = parse_haskell_function_mapping(HS_R5_TRACE_FILES, "layerForFamily")
    warranted_map_agda = parse_agda_function_mapping(AGDA_R5CORE_FILE, "warrantedForFamily")
    warranted_map_hs = parse_haskell_function_mapping(HS_R5_TRACE_FILES, "warrantedForFamily")

    checks = [
        verify_pair("CanonicalMoveFamily[Sovereignty]", canonical_agda, canonical_hs),
        verify_pair("CanonicalMoveFamily[R5Core]", canonical_r5_agda, canonical_hs),
        verify_pair("CanonicalMoveFamily[Sovereignty↔R5Core]", canonical_agda, canonical_r5_agda),
        verify_pair("IllocutionaryForce[Trace]", force_r5_agda, force_hs),
        verify_pair("SemanticLayer[Trace]", layer_r5_agda, layer_hs),
        verify_pair("ClauseForm[Trace]", clause_r5_agda, clause_hs),
        verify_pair("WarrantedMoveMode[Legitimacy]", warranted_r5_agda, warranted_hs),
        verify_pair("IsLegit[Legitimacy]", legit_agda, legit_hs),
        verify_pair("LegitimacyReason[Legitimacy]", legitimacy_reason_agda, legitimacy_reason_hs),
        verify_pair("DecisionDisposition[Legitimacy]", disposition_agda, disposition_hs),
        verify_mapping_pair("forceForFamily", force_map_agda, force_map_hs),
        verify_mapping_pair("clauseFormForIF", clause_map_agda, clause_map_hs),
        verify_mapping_pair("layerForFamily", layer_map_agda, layer_map_hs),
        verify_mapping_pair("warrantedForFamily", warranted_map_agda, warranted_map_hs),
    ]
    return 0 if all(checks) else 1


if __name__ == "__main__":
    sys.exit(main())
