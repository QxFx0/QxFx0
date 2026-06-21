#!/usr/bin/env bash
# check_adr_coverage.sh — CI check: no merge without accepted ADR
#
# Verifies that PRs touching src/ or test/ reference an accepted ADR.
# Also flags stale proposed ADRs (>14 days).
#
# Usage:
#   ADR_DIR=docs/adr bash scripts/check_adr_coverage.sh
#
# Environment:
#   ADR_DIR           — path to ADR directory (default: docs/adr)
#   ADR_STALE_DAYS    — days before a Proposed ADR is stale (default: 14)
#   ADR_PR_DESC       — PR description text (for CI integration)
#   ADR_CHANGED_FILES — space-separated list of changed files (for CI)

set -euo pipefail

ADR_DIR="${ADR_DIR:-docs/adr}"
ADR_STALE_DAYS="${ADR_STALE_DAYS:-14}"

# ── Helper: extract ADR numbers from text ────────────────────────────────
extract_adr_refs() {
  local text="$1"
  echo "$text" | grep -oE 'ADR-[0-9]+|adr/[0-9]+|00[0-9]{2}' | \
    sed 's/ADR-//;s/adr\///;s/^0*//' | sort -u
}

# ── Helper: check if an ADR is accepted ──────────────────────────────────
is_adr_accepted() {
  local num="$1"
  local found=0
  for f in "$ADR_DIR"/*.md; do
    [ -f "$f" ] || continue
    local prefix
    prefix=$(basename "$f" | grep -oE '^[0-9]+')
    if [ "$prefix" = "$num" ]; then
      if grep -qi 'Status:.*Accepted\|\*\*Status:\*\* Accepted' "$f"; then
        found=1
        break
      fi
    fi
  done
  echo "$found"
}

# ── Check 1: Stale proposed ADRs ─────────────────────────────────────────
check_stale_adrs() {
  local stale=0
  for f in "$ADR_DIR"/*.md; do
    [ -f "$f" ] || continue
    if grep -qi 'Status:.*Proposed\|\*\*Status:\*\* Proposed' "$f"; then
      local age_days
      local file_time
      file_time=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
      local now
      now=$(date +%s)
      age_days=$(( (now - file_time) / 86400 ))
      if [ "$age_days" -gt "$ADR_STALE_DAYS" ]; then
        echo "STALE ADR: $(basename "$f") — Proposed for ${age_days} days (limit: ${ADR_STALE_DAYS})"
        stale=1
      fi
    fi
  done
  return "$stale"
}

# ── Check 2: PR references accepted ADR ──────────────────────────────────
check_pr_adr_ref() {
  local pr_desc="${ADR_PR_DESC:-}"
  local changed_files="${ADR_CHANGED_FILES:-}"

  # If no changed files specified, skip this check (local mode)
  if [ -z "$changed_files" ]; then
    echo "INFO: No changed files specified — skipping PR ADR reference check."
    return 0
  fi

  # Check if any src/ or test/ files changed
  local has_code_changes=0
  for f in $changed_files; do
    case "$f" in
      src/*|test/*) has_code_changes=1; break ;;
    esac
  done

  if [ "$has_code_changes" -eq 0 ]; then
    echo "INFO: No src/ or test/ files changed — ADR not required."
    return 0
  fi

  # Check for exception: small changes (<20 LOC)
  # In CI, this would use git diff --stat. For now, check file count.
  local file_count
  file_count=$(echo "$changed_files" | wc -w)
  if [ "$file_count" -le 2 ]; then
    echo "INFO: Small change (${file_count} files) — ADR may not be required."
    return 0
  fi

  # Extract ADR references from PR description
  local adr_refs
  adr_refs=$(extract_adr_refs "$pr_desc")

  if [ -z "$adr_refs" ]; then
    echo "FAIL: PR touches src/ or test/ but does not reference any ADR."
    echo "      Add 'ADR-NNNN' to the PR description or commit message."
    echo "      If this is a bug fix or small change, use 'ADR-EXEMPT' in the PR description."
    return 1
  fi

  # Check if any referenced ADR is accepted
  local found_accepted=0
  for num in $adr_refs; do
    if [ "$num" = "EXEMPT" ]; then
      echo "INFO: PR is marked ADR-EXEMPT."
      return 0
    fi
    local accepted
    accepted=$(is_adr_accepted "$num")
    if [ "$accepted" = "1" ]; then
      echo "PASS: References accepted ADR-$num."
      found_accepted=1
      break
    fi
  done

  if [ "$found_accepted" -eq 0 ]; then
    echo "FAIL: Referenced ADR(s) are not in Accepted status."
    return 1
  fi

  return 0
}

# ── Main ─────────────────────────────────────────────────────────────────
main() {
  local exit_code=0

  echo "=== ADR Coverage Check ==="
  echo ""

  echo "--- Check 1: Stale Proposed ADRs ---"
  if check_stale_adrs; then
    echo "PASS: No stale proposed ADRs."
  else
    echo "WARN: Stale proposed ADRs found."
    exit_code=1
  fi
  echo ""

  echo "--- Check 2: PR ADR Reference ---"
  if check_pr_adr_ref; then
    echo "PASS: ADR reference check passed."
  else
    echo "FAIL: ADR reference check failed."
    exit_code=1
  fi
  echo ""

  if [ "$exit_code" -ne 0 ]; then
    echo "ADR coverage check: FAIL"
    exit "$exit_code"
  else
    echo "ADR coverage check: PASS"
    exit 0
  fi
}

main "$@"
