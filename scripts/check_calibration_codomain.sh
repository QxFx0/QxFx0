#!/usr/bin/env bash
#
# check_calibration_codomain.sh — Package 11 enforcement tool.
#
# Reads data/calibration/ranges.json and verifies that every
# default value declared in the source is in the closed range
# recorded in the JSON. This is the **mechanical** part of
# the codomain check (per ADR-0012 §15.3 "methodology lesson");
# the empirical part is in CALIBRATION_REPORT.md (F-10).
#
# Per CALIBRATION_BACKLOG.md §1: every parameter must be
# sanity-checked against the actual codomain of the signal
# it gates, not against a unit-test generator. This script
# makes the sanity-check part of CI.
#
# Exit codes:
#   0  — all parameters in range (or no parameters to check)
#   1  — at least one parameter is out of range
#   2  — JSON is malformed or missing
#
# The script does NOT run cabal, does NOT build, does NOT
# test. It is a pure source-level check.
#
# Known limitations (Package 11 work):
#
#   * When a field is defined in multiple records (e.g.
#     `phase9EssenceModulation` vs `defaultEssenceModulation`
#     in `QxFx0.Self.Essence`), the script picks the **last**
#     declaration in the file, not necessarily the active
#     default. The active default may use Haskell record
#     update syntax (`expr { field = value }`), which the
#     script does not currently follow. For Package 11 the
#     next contributor should extend the script to follow
#     `defaultX = ...` definitions specifically.
#
#   * The "GAP" report (fields with defaults but no
#     codomain spec entry) is informational, not a
#     violation. The next contributor adds GAPs to the
#     spec as Package 11's calibration work progresses.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RANGES_JSON="$ROOT/data/calibration/ranges.json"
SRC="$ROOT/src"
VIOLATIONS=0

if [ ! -f "$RANGES_JSON" ]; then
  echo "ERROR: $RANGES_JSON not found (Package 11 requires the codomain spec)" >&2
  exit 2
fi

if ! python3 -c "import json; json.load(open('$RANGES_JSON'))" 2>/dev/null; then
  echo "ERROR: $RANGES_JSON is not valid JSON" >&2
  exit 2
fi

fail_violation() {
  echo "VIOLATION: $1"
  VIOLATIONS=$((VIOLATIONS + 1))
}

echo "Calibration codomain check (Package 11):"
echo "  reading ranges from $RANGES_JSON"

# Read every parameter and verify the default value is in [lo, hi].
# We use Python for the JSON parse and the source scan; the
# source pattern is:
#
#   defaultX = X
#     { fieldA = 1.0
#     , fieldB = 0.5
#     , ...
#     }
#
# The script finds the record literal, extracts each field's
# value, and compares against the JSON's [lo, hi] for that
# field. A field that is in the JSON but not in the source
# is a **gap** (the field is declared but the default is
# missing); a field that is in the source but not in the
# JSON is a **gap** (the field has a default but no codomain
# spec yet). Both are violations.

python3 - "$RANGES_JSON" "$SRC" <<'PY'
import json
import pathlib
import re
import sys

ranges_path = pathlib.Path(sys.argv[1])
src_root = pathlib.Path(sys.argv[2])

with ranges_path.open() as f:
    spec = json.load(f)

params = spec.get("parameters", [])
if not params:
    print("  no parameters in spec; codomain check is a no-op")
    sys.exit(0)

# Group by source file for efficiency.
by_source: dict[str, list[dict]] = {}
for p in params:
    by_source.setdefault(p["source"], []).append(p)

# Pattern: a record literal of the form
#   { fieldA = 1.0
#   , fieldB = 0.5
#   }
# We strip trailing "-- ..." comments from each line, then
# match "field = <number>" with an optional leading "{" or
# "," (or no prefix, for record updates). The first field of
# a record has a leading "{"; subsequent fields have a
# leading ",". Record updates look like
#   expr { field = value }.
field_pat = re.compile(r"^\s*[,{]?\s*([A-Za-z][A-Za-z0-9_]*)\s*=\s*([+-]?[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)\s*$")
comment_pat = re.compile(r"\s*--.*$")

violations: list[str] = []

for source_rel, params_list in by_source.items():
    source_path = src_root.parent / source_rel if not pathlib.Path(source_rel).is_absolute() else pathlib.Path(source_rel)
    if not source_path.is_file():
        violations.append(f"{source_rel}: source file not found")
        continue
    text = source_path.read_text(encoding="utf-8")
    declared: dict[str, float] = {}
    for line in text.splitlines():
        # Strip trailing line comments.
        stripped = comment_pat.sub("", line)
        m = field_pat.match(stripped)
        if m:
            field, value = m.group(1), float(m.group(2))
            declared[field] = value

    for p in params_list:
        field = p["field"]
        lo, hi = p["lo"], p["hi"]
        if field not in declared:
            violations.append(
                f"{p['name']}: field '{field}' not found in {source_rel} (codomain check requires the default)"
            )
            continue
        value = declared[field]
        if value < lo or value > hi:
            violations.append(
                f"{p['name']}: default {value} is out of range [{lo}, {hi}] (source: {source_rel})"
            )
        else:
            print(f"  OK   {p['name']} = {value} (in [{lo}, {hi}])")

# Cross-check: scan for fields in source that are NOT in the
# JSON spec. These are candidates for adding to the spec.
# This is a **gap report**, not a violation. We scan the
# source files in the spec and report any field declarations
# that have a numeric value but no entry in the spec.
spec_fields: set[tuple[str, str]] = {(p["source"], p["field"]) for p in params}
gap_files = {p["source"] for p in params}
for source_rel in gap_files:
    source_path = src_root.parent / source_rel
    if not source_path.is_file():
        continue
    text = source_path.read_text(encoding="utf-8")
    seen: set[str] = set()
    for line in text.splitlines():
        stripped = comment_pat.sub("", line)
        m = field_pat.match(stripped)
        if m:
            seen.add(m.group(1))
    for f in sorted(seen):
        if (source_rel, f) not in spec_fields:
            # Skip fields that are clearly not "tunable parameters":
            # type-level field names with "::" or field names with
            # type signatures. The regex only matches the
            # "<field> = <number>" pattern, so type signatures
            # are already excluded. We just need to skip
            # fields that look like constants, e.g. "<0" or
            # "Just 0.5" — but the regex excludes those too.
            print(f"  GAP  {source_rel}: field '{f}' has a default but no codomain spec entry")

if violations:
    for v in violations:
        print(f"VIOLATION: {v}", file=sys.stderr)
    sys.exit(1)
PY
rc=$?

if [ "$rc" -ne 0 ]; then
  if [ "$rc" -eq 1 ]; then
    echo "Calibration codomain check failed: at least one parameter is out of range" >&2
  fi
  exit "$rc"
fi

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "Calibration codomain check failed: $VIOLATIONS violation(s)"
  exit 1
fi

echo "Calibration codomain check passed."
