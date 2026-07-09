#!/usr/bin/env python3
"""Check that module paths referenced in docs exist under src/.

Usage:
    python3 scripts/check_doc_module_paths.py [docs_dir] [src_dir]

Defaults:
    docs_dir = docs
    src_dir  = src

The script extracts potential module references from Markdown files in docs_dir:
  - backtick-quoted text: `QxFx0.Module.Path`
  - bare QxFx0.X.Y.Z tokens

A reference is considered stale when the module path it denotes cannot be found
in src_dir.  Trailing lowercase components (function/value names) are stripped,
so `QxFx0.Self.Salience.renderSalienceDriver` is checked as `QxFx0.Self.Salience`.

Exit codes:
    0  All references resolve (or are explicitly allowed as removed/external).
    1  One or more stale/unresolved module references were found.
"""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path
from typing import Dict, List, Set, Tuple


# Known historical renames.  If a doc still uses the old path, it is reported
# as stale with the suggested replacement.
KNOWN_RENAMES: Dict[str, str] = {
    "QxFx0.Semantic.AuthorityParse": "QxFx0.Runtime.AuthorityParse",
    "QxFx0.Lexicon.Morphology": "QxFx0.Semantic.Morphology",
    "QxFx0.Runtime.PGFStatus": "QxFx0.Lexicon.PGFStatus",
    "QxFx0.Core.GenericPropositionAdmission": "QxFx0.Types.Admission.GenericPropositionAdmission",
    "QxFx0.Self.Will": "(module removed)",
    "QxFx0.Self.Holistic": "(module removed)",
    "QxFx0.Self.Formal": "(module removed)",
    "QxFx0.Evaluation.ModelComparison": "(module removed)",
    "QxFx0.Internal.Process": "(module removed)",
    "QxFx0.Bridge.SQLite.SchemaContractCheck": "QxFx0.Bridge.SQLite.SchemaContract",
    "QxFx0.Bridge.SQLite.SchemaConsistency": "(module removed)",
    "QxFx0.Core.DialogueOutcomeLearning": "QxFx0.Learning.DialogueDevelopment",
    "QxFx0.Core.Spectral": "QxFx0.Core.ContentCluster",
    "QxFx0.Lexicon.Morphology": "QxFx0.Semantic.Morphology",
}

# References that are intentionally not expected to exist in src/ (design
# placeholders, future modules, regex prefixes, etc.).
ALLOWED_MISSING: Set[str] = {
    "QxFx0.Learning.Contour",
    "QxFx0.Types.TopicDrift",
    "QxFx0.Types.Admission",
    "QxFx0.Types.PGF",
    "QxFx0.PropositionXxxAdmission",
    "QxFx0.Left",
    "QxFx0.Core.X",
    "QxFx0.Core.Turn",
    "QxFx0.Core.GFParityHarness",
}

# Phrases that indicate a reference is intentionally to a removed or never-created
# module.  Matching is case-insensitive.
_REMOVAL_HINTS = ("module removed", "never created")


def collect_modules(src_root: Path) -> Tuple[Set[str], Set[str]]:
    """Return (module_paths, directory_prefixes) found under src_root."""
    modules: Set[str] = set()
    dirs: Set[str] = set()

    for path in src_root.rglob("*.hs"):
        rel = path.relative_to(src_root).with_suffix("")
        parts = rel.parts
        if not parts or parts[0] != "QxFx0":
            continue
        modules.add(".".join(parts))
        # Register all parent directories as prefixes.
        for i in range(1, len(parts)):
            dirs.add(".".join(parts[:i]))

    return modules, dirs


def candidate_module(token: str) -> str:
    """Strip trailing lowercase components that are value/function names."""
    parts = token.split(".")
    # Keep at least QxFx0.X
    while len(parts) > 2 and parts[-1][0].islower():
        parts.pop()
    return ".".join(parts)


def longest_existing_module(candidate: str, modules: Set[str]) -> str | None:
    """Return the longest prefix of candidate that is an existing module."""
    parts = candidate.split(".")
    for i in range(len(parts), 1, -1):
        prefix = ".".join(parts[:i])
        if prefix in modules:
            return prefix
    return None


def line_number(text: str, pos: int) -> int:
    return text.count("\n", 0, pos) + 1


def is_intentional(text: str, start: int, end: int) -> bool:
    """Check whether the surrounding text marks the reference as removed/external."""
    snippet = text[end : end + 60].lower()
    return any(hint in snippet for hint in _REMOVAL_HINTS)


def find_references(text: str) -> List[Tuple[str, int, int]]:
    """Return list of (token, start, end) for potential module references."""
    refs: List[Tuple[str, int, int]] = []
    pattern = re.compile(r"`?(QxFx0(?:\.[A-Za-z0-9_]+)*)`?")
    for m in pattern.finditer(text):
        token = m.group(1)
        refs.append((token, m.start(), m.end()))
    return refs


def main() -> int:
    docs_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("docs")
    src_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("src")

    modules, dir_prefixes = collect_modules(src_dir)

    # Categorised findings: list of (file, line, token, category, suggestion)
    stale: List[Tuple[str, int, str, str, str]] = []
    intentional: List[Tuple[str, int, str, str]] = []

    for doc_path in sorted(docs_dir.rglob("*.md")):
        text = doc_path.read_text(encoding="utf-8", errors="ignore")
        for token, start, end in find_references(text):
            if token == "QxFx0":
                continue

            candidate = candidate_module(token)

            # Exact directory prefix (e.g. QxFx0.Self, QxFx0.Memory) is fine.
            if candidate in dir_prefixes and candidate not in modules:
                continue

            line = line_number(text, start)
            rel_file = str(doc_path.relative_to(docs_dir.parent if docs_dir.is_absolute() else Path(".")))

            if candidate in modules:
                continue

            # References explicitly marked as removed/never-created are fine,
            # even if they also appear in the known-renames map.
            if is_intentional(text, start, end):
                intentional.append((rel_file, line, token, "INTENTIONAL (removed/never-created)"))
                continue

            if candidate in KNOWN_RENAMES:
                suggestion = KNOWN_RENAMES[candidate]
                stale.append((rel_file, line, token, "STALE (known rename)", suggestion))
                continue

            if candidate in ALLOWED_MISSING:
                intentional.append((rel_file, line, token, "INTENTIONAL (allowed missing)"))
                continue

            # If the longest existing module prefix covers the whole candidate,
            # treat the trailing component as a value/type reference inside that
            # module (e.g. QxFx0.Types.TurnProjection.TurnReplayTrace).
            longest = longest_existing_module(candidate, modules)
            if longest == candidate:
                continue
            if longest is not None and len(longest.split(".")) >= 2:
                # Candidate extends an existing module, but the extension is not
                # itself a module.  This is usually a type/value reference.
                continue

            stale.append((rel_file, line, token, "STALE (unresolved)", ""))

    if intentional:
        print("Intentional / allowed missing references:")
        for file, line, token, category in intentional:
            print(f"  {file}:{line}: {token}  ({category})")
        print()

    if stale:
        print("Stale module references:")
        for file, line, token, category, suggestion in stale:
            suffix = f" -> {suggestion}" if suggestion else ""
            print(f"  {file}:{line}: {token}  ({category}){suffix}")
        return 1

    print("No stale module references found.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
