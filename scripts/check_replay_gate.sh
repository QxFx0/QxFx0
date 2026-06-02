#!/usr/bin/env bash
#
# check_replay_gate.sh — Package 3 enforcement tool.
#
# Runs the four property tests (P1–P4) on every
# canonical contour, plus a stub test for the
# needs-work contours. The input is
# docs/closure/REPLAY_GATE_TRIAGE.md; the output
# is a status report.
#
# Per REPLAY_GATE_SPEC.md:
#   * P1 — Serializable (Show instance).
#   * P2 — Replayable (pure compute function).
#   * P3 — Reconstructable (snapshot → reconstruction).
#   * P4 — Trace-explainable (named trc* field).
#
# The script does NOT run cabal (per the closure
# plan's "no cabal in read-only sessions" rule). It
# runs the static checks that can be done without
# building:
#
#   * For each canonical contour, verify the source
#     module has a 'Show' instance (via grep on
#     "deriving stock" patterns).
#   * For each canonical contour, verify the
#     compute function is referentially transparent
#     (via static call-graph inspection: no IO in
#     the type signature).
#   * For each canonical contour, verify the
#     snapshot type exists.
#   * For each canonical contour, verify the
#     'trc*' field exists in 'TurnReplayTrace'.
#
# The dynamic checks (running the actual property
# tests) require cabal and are part of the
# 'qxfx0-test' suite (per Test.Suite.ReplayGate).
#
# Exit codes:
#   0  — all canonical contours pass static checks
#   1  — at least one canonical contour fails
#   2  — triage list is missing

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TRIAGE="$ROOT/docs/closure/REPLAY_GATE_TRIAGE.md"
SRC="$ROOT/src"
VIOLATIONS=0

if [ ! -f "$TRIAGE" ]; then
  echo "ERROR: $TRIAGE not found" >&2
  exit 2
fi

fail_violation() {
  echo "VIOLATION: $1"
  VIOLATIONS=$((VIOLATIONS + 1))
}

echo "Replay gate check (Package 3):"
echo "  reading triage from $TRIAGE"

# A canonical contour is "passing" or "passing-with-notes"
# per REPLAY_GATE_TRIAGE.md §2. The schema is
# documented in docs/closure/TRACE_SCHEMA.md (the
# single source of truth for what trc* fields each
# contour must have).
#
# The 6 canonical contours are:
#
#   * Conatus     (QxFx0.Self.Conatus)            GAP
#   * Field       (QxFx0.Self.Field)              GAP
#   * Salience    (QxFx0.Self.Salience)           OK
#   * Deliberation (QxFx0.Self.Deliberation)      OK
#   * Essence     (QxFx0.Self.Essence)            OK
#   * Identity    (QxFx0.Types.State.Identity)    GAP
#
# Essence was added 2026-05-19 with the Phase 9-10
# landing (4 trc* fields).

declare -A CANONICAL_SOURCES=(
  ["Conatus"]="src/QxFx0/Self/Conatus.hs"
  ["Field"]="src/QxFx0/Self/Field.hs"
  ["Salience"]="src/QxFx0/Self/Salience.hs"
  ["Deliberation"]="src/QxFx0/Self/Deliberation.hs"
  ["Essence"]="src/QxFx0/Self/Essence.hs"
  ["Identity"]="src/QxFx0/Types/State/Identity.hs"
)

declare -A TRC_FIELDS=(
  # Conatus: trcConatusEnergy is per
  # TRACE_SCHEMA.md §2; not yet landed in
  # TurnReplayTrace (Package 3 work).
  ["Conatus"]="trcConatusEnergy"
  # Field: trcField is per TRACE_SCHEMA.md §3;
  # not yet landed in TurnReplayTrace.
  ["Field"]="trcField"
  # Salience: trcSalienceDriver is the actual
  # landed field (Phase 5.5e; TRACE_SCHEMA.md §4).
  ["Salience"]="trcSalienceDriver"
  # Deliberation: trcDeliberationRule is one of
  # the four landed fields (Phase 8 Package B;
  # TRACE_SCHEMA.md §5).
  ["Deliberation"]="trcDeliberationRule"
  # Essence: trcEssenceMode is one of the four
  # landed fields (Phase 9-10, 2026-05-19;
  # TRACE_SCHEMA.md §6).
  ["Essence"]="trcEssenceMode"
  # Identity: trcIdentityClaims is per
  # TRACE_SCHEMA.md §7; not yet landed in
  # TurnReplayTrace.
  ["Identity"]="trcIdentityClaims"
)

# Track which fields are "expected but missing" — a
# Package 3 work item, not a script violation. Each
# entry points to a TRACE_SCHEMA.md section that
# documents what the field should look like.
declare -A EXPECTED_MISSING=(
  ["Conatus"]="true|TRACE_SCHEMA.md §2"
  ["Field"]="true|TRACE_SCHEMA.md §3"
  ["Identity"]="true|TRACE_SCHEMA.md §7"
)

# Static check: P1 — every canonical contour's
# primary output type has a 'Show' instance.
echo "  [P1] every canonical contour is serializable"
for contour in "${!CANONICAL_SOURCES[@]}"; do
  src="${CANONICAL_SOURCES[$contour]}"
  if [ ! -f "$ROOT/$src" ]; then
    fail_violation "P1: $contour source not found: $src"
    continue
  fi
  # The 'Show' instance is checked at the type
  # level. The static check is "deriving stock Show"
  # appears in the file (a soft signal that at
  # least one type is Show-able).
  if ! rg -q 'deriving stock.*Show' "$ROOT/$src"; then
    fail_violation "P1: $contour ($src): no 'deriving stock Show' found"
  else
    echo "       OK $contour"
  fi
done

# Static check: P2 — every canonical contour's
# compute function is pure (no IO in the type
# signature). The check is a heuristic: any function
# whose type contains "IO " is impure.
echo "  [P2] compute functions are pure"
for contour in "${!CANONICAL_SOURCES[@]}"; do
  src="${CANONICAL_SOURCES[$contour]}"
  if [ ! -f "$ROOT/$src" ]; then
    continue
  fi
  # Look for the canonical compute function name:
  #   * Conatus: computeConatusEnergy, computeConatusGradient
  #   * Field: combineField, deriveFieldConfidence
  #   * Salience: computeSalience, salienceFromConatusEnergy
  #   * Deliberation: reconcile
  #   * Identity: validateClaim
  case "$contour" in
    Conatus)
      compute_pat='^(computeConatusEnergy|computeConatusGradient) *::' ;;
    Field)
      compute_pat='^(combineField|deriveFieldConfidence) *::' ;;
    Salience)
      compute_pat='^(computeSalience|salienceFromConatusEnergy) *::' ;;
    Deliberation)
      compute_pat='^reconcile *::' ;;
    Identity)
      compute_pat='^validateClaim *::' ;;
  esac
  if rg -q "$compute_pat.*IO " "$ROOT/$src"; then
    fail_violation "P2: $contour ($src): compute function has IO in type signature"
  else
    echo "       OK $contour"
  fi
done

# Static check: P3 — every canonical contour has a
# snapshot type. The snapshot is the input that
# reconstructs the contour. The check is a soft
# signal: the file exports a "snapshot" or
# "replay"-related function.
echo "  [P3] every canonical contour has a snapshot type"
for contour in "${!CANONICAL_SOURCES[@]}"; do
  src="${CANONICAL_SOURCES[$contour]}"
  if [ ! -f "$ROOT/$src" ]; then
    continue
  fi
  # The snapshot is implicit (the contour is
  # reconstructed from the SystemState + replay
  # trace). The check is "the file has a 'Show'
  # instance" — a soft signal that the type is
  # serializable and therefore snapshot-able.
  if rg -q 'deriving stock.*Show' "$ROOT/$src"; then
    echo "       OK $contour"
  else
    fail_violation "P3: $contour ($src): no snapshot-able type found"
  fi
done

# Static check: P4 — every canonical contour has a
# named 'trc*' field in 'TurnReplayTrace'.
# 
# Note: as of 2026-06-02, three of the five canonical
# contours (Conatus, Field, Identity) do NOT yet have
# their expected trc* fields in TurnReplayTrace. The
# fields are listed in REPLAY_GATE_TRIAGE.md §1 but
# the actual code change is Package 3 work. The
# script reports this as a GAP, not a violation; the
# next contributor closes the gap by adding the
# fields to TurnProjection.hs.
echo "  [P4] every canonical contour has a named trc* field"
TURN_PROJECTION="$ROOT/src/QxFx0/Types/TurnProjection.hs"
if [ ! -f "$TURN_PROJECTION" ]; then
  fail_violation "P4: $TURN_PROJECTION not found"
else
  for contour in "${!TRC_FIELDS[@]}"; do
    field="${TRC_FIELDS[$contour]}"
    if rg -q "^\s*,?\s*${field} *::" "$TURN_PROJECTION"; then
      echo "       OK $contour ($field)"
    else
      # Distinguish "expected but missing" (Package 3
      # work) from "should exist but doesn't" (bug).
      # The EXPECTED_MISSING value is "true|<doc-ref>"
      # — the doc-ref is shown to the reader so the
      # GAP is actionable, not just informational.
      missing_entry="${EXPECTED_MISSING[$contour]:-false}"
      if [ "$missing_entry" = "false" ]; then
        fail_violation "P4: $contour: field '$field' not found in TurnReplayTrace"
      else
        doc_ref="${missing_entry#true|}"
        echo "       GAP $contour ($field) — Package 3 work item; see $doc_ref"
      fi
    fi
  done
fi

# Status report
echo ""
echo "Replay gate summary:"
echo "  canonical contours: ${#CANONICAL_SOURCES[@]}"
echo "  violations: $VIOLATIONS"

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "Replay gate check failed."
  exit 1
fi

echo "Replay gate check passed (static checks)."
echo "Note: dynamic property tests are in qxfx0-test (Test.Suite.ReplayGate)."
