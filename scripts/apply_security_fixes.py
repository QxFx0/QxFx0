#!/usr/bin/env python3
"""Apply F1/F2/F4 security fixes to release-smoke.sh"""
import re
import sys

path = "scripts/release-smoke.sh"
with open(path, "r") as f:
    content = f.read()

# ── Fix F2 (P2): TMPDIR symlink/TOCTOU vulnerability ──
# Replace [ -O "$TMPDIR" ] with readlink -f resolution before ownership check
old_tmpdir = '''        *)
            if [ -d "$TMPDIR" ] && [ -O "$TMPDIR" ]; then
                :
            else
                echo "SECURITY: TMPDIR not /tmp and not user-owned" >&2
                TMPDIR=/tmp
            fi
            ;;'''

new_tmpdir = '''        *)
            # F2 fix: Resolve symlinks before ownership check to prevent TOCTOU/symlink attacks
            local _resolved_tmpdir
            _resolved_tmpdir="$(readlink -f "$TMPDIR" 2>/dev/null || echo "")"
            if [ -n "$_resolved_tmpdir" ] && [ -d "$_resolved_tmpdir" ] && [ -O "$_resolved_tmpdir" ]; then
                TMPDIR="$_resolved_tmpdir"
            else
                echo "SECURITY: TMPDIR not /tmp and not user-owned (symlink-resolved check failed)" >&2
                TMPDIR=/tmp
            fi
            ;;'''

if old_tmpdir not in content:
    print("ERROR: Could not find TMPDIR fallback block", file=sys.stderr)
    sys.exit(1)
content = content.replace(old_tmpdir, new_tmpdir)

# ── Fix F4 (P2): CABAL_LOCK_FILE glob pattern fragility ──
# Replace glob-based case check with realpath containment verification
old_cabal = '''# C1 fix: Per-run isolated lock file — prevents race conditions and symlink attacks.
# C1/D1 fix: Per-run isolated lock file with external override guard.
if [ -n "$CABAL_LOCK_FILE" ]; then
  case "$CABAL_LOCK_FILE" in
    "$RELEASE_HOME"/*)
      ;;
    *)
      echo "SECURITY: External CABAL_LOCK_FILE outside RELEASE_HOME" >&2
      CABAL_LOCK_FILE=""
      ;;
  esac
fi'''

new_cabal = '''# C1 fix: Per-run isolated lock file — prevents race conditions and symlink attacks.
# C1/D1 fix: Per-run isolated lock file with external override guard.
# F4 fix: Replace glob-based prefix check with realpath containment verification.
if [ -n "$CABAL_LOCK_FILE" ]; then
  local _resolved_lock _resolved_release
  _resolved_lock="$(readlink -f "$CABAL_LOCK_FILE" 2>/dev/null || echo "")"
  _resolved_release="$(readlink -f "$RELEASE_HOME" 2>/dev/null || echo "")"
  if [ -n "$_resolved_lock" ] && [ -n "$_resolved_release" ] && \
     case "$_resolved_lock" in "$_resolved_release"/*) true;; *) false;; esac; then
    CABAL_LOCK_FILE="$_resolved_lock"
  else
    echo "SECURITY: External CABAL_LOCK_FILE outside RELEASE_HOME (realpath containment check failed)" >&2
    CABAL_LOCK_FILE=""
  fi
fi'''

if old_cabal not in content:
    print("ERROR: Could not find CABAL_LOCK_FILE validation block", file=sys.stderr)
    sys.exit(1)
content = content.replace(old_cabal, new_cabal)

# ── Fix F1 (P0): Wire nix_eval_is_allowlisted into nix_eval_expr ──
# Also fix --restricted → --option restrict-eval true for nix 2.34.6 compatibility
old_nix_eval = '''# C2 fix: Fail-closed in ALL modes — no unrestricted fallback.
nix_eval_expr() {
    local expr="$1"
    NIX_EVAL_OUT="$(nix-instantiate --restricted --eval -E "$expr" 2>&1)"
    NIX_EVAL_STATUS=$?
    NIX_EVAL_MODE="restricted"
    if [ "$NIX_EVAL_STATUS" -ne 0 ] && \\
       printf '%s' "$NIX_EVAL_OUT" | grep -Eqi 'unrecogni[sz]ed flag' && \\
       printf '%s' "$NIX_EVAL_OUT" | grep -q -- '--restricted'; then
        # C2 fix: Fail-closed in ALL modes — no unrestricted fallback.
        echo "SECURITY: nix-instantiate --restricted unavailable — refusing unrestricted fallback (fail-closed)" >&2
        return "$NIX_EVAL_STATUS"
    fi
    return "$NIX_EVAL_STATUS"
}'''

new_nix_eval = '''# C2 fix: Fail-closed in ALL modes — no unrestricted fallback.
# F1 fix: Wire nix_eval_is_allowlisted as mandatory pre-check before nix-instantiate invocation.
# P0 fix: Also use --option restrict-eval true instead of --restricted for nix 2.34.6 compatibility.
nix_eval_expr() {
    local expr="$1"
    # F1 fix: Mandatory allowlist pre-check — fail-closed if expression is not allowlisted.
    if ! nix_eval_is_allowlisted "$expr"; then
        echo "SECURITY: nix_eval_expr rejected non-allowlisted expression (fail-closed)" >&2
        NIX_EVAL_OUT=""
        NIX_EVAL_STATUS=1
        NIX_EVAL_MODE="allowlisted"
        return 1
    fi
    NIX_EVAL_OUT="$(nix-instantiate --option restrict-eval true --eval -E "$expr" 2>&1)"
    NIX_EVAL_STATUS=$?
    NIX_EVAL_MODE="restricted"
    if [ "$NIX_EVAL_STATUS" -ne 0 ] && \\
       printf '%s' "$NIX_EVAL_OUT" | grep -Eqi 'unrecogni[sz]ed flag|restrict-eval' && \\
       printf '%s' "$NIX_EVAL_OUT" | grep -q -- 'restrict'; then
        # C2 fix: Fail-closed in ALL modes — no unrestricted fallback.
        echo "SECURITY: nix-instantiate restrict-eval unavailable — refusing unrestricted fallback (fail-closed)" >&2
        return "$NIX_EVAL_STATUS"
    fi
    return "$NIX_EVAL_STATUS"
}'''

if old_nix_eval not in content:
    print("ERROR: Could not find nix_eval_expr function block", file=sys.stderr)
    sys.exit(1)
content = content.replace(old_nix_eval, new_nix_eval)

with open(path, "w") as f:
    f.write(content)

print("All 3 fixes applied successfully: F1 (P0 allowlist wiring), F2 (P2 TMPDIR symlink), F4 (P2 CABAL_LOCK glob)")
print("Bonus: --restricted → --option restrict-eval true for nix 2.34.6 compatibility")
