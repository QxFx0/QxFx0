#!/usr/bin/env python3
"""Fix bash syntax issues in the security fixes applied to release-smoke.sh"""
import sys

path = "scripts/release-smoke.sh"
with open(path, "r") as f:
    content = f.read()

# Fix 1: Remove `local` from TMPDIR section (top-level, not in function)
old_tmpdir = '''        *)
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

new_tmpdir = '''        *)
            # F2 fix: Resolve symlinks before ownership check to prevent TOCTOU/symlink attacks
            _resolved_tmpdir="$(readlink -f "$TMPDIR" 2>/dev/null || echo "")"
            if [ -n "$_resolved_tmpdir" ] && [ -d "$_resolved_tmpdir" ] && [ -O "$_resolved_tmpdir" ]; then
                TMPDIR="$_resolved_tmpdir"
            else
                echo "SECURITY: TMPDIR not /tmp and not user-owned (symlink-resolved check failed)" >&2
                TMPDIR=/tmp
            fi
            ;;'''

if old_tmpdir not in content:
    print("ERROR: Could not find TMPDIR block to fix", file=sys.stderr)
    sys.exit(1)
content = content.replace(old_tmpdir, new_tmpdir)

# Fix 2: Fix CABAL_LOCK section — remove `local`, restructure containment check
old_cabal = '''# F4 fix: Replace glob-based prefix check with realpath containment verification.
if [ -n "$CABAL_LOCK_FILE" ]; then
  local _resolved_lock _resolved_release
  _resolved_lock="$(readlink -f "$CABAL_LOCK_FILE" 2>/dev/null || echo "")"
  _resolved_release="$(readlink -f "$RELEASE_HOME" 2>/dev/null || echo "")"
  if [ -n "$_resolved_lock" ] && [ -n "$_resolved_release" ] &&      case "$_resolved_lock" in "$_resolved_release"/*) true;; *) false;; esac; then
    CABAL_LOCK_FILE="$_resolved_lock"
  else
    echo "SECURITY: External CABAL_LOCK_FILE outside RELEASE_HOME (realpath containment check failed)" >&2
    CABAL_LOCK_FILE=""
  fi
fi'''

new_cabal = '''# F4 fix: Replace glob-based prefix check with realpath containment verification.
if [ -n "$CABAL_LOCK_FILE" ]; then
  _resolved_lock="$(readlink -f "$CABAL_LOCK_FILE" 2>/dev/null || echo "")"
  _resolved_release="$(readlink -f "$RELEASE_HOME" 2>/dev/null || echo "")"
  _lock_contained=false
  if [ -n "$_resolved_lock" ] && [ -n "$_resolved_release" ]; then
    case "$_resolved_lock" in
      "$_resolved_release"/*)
        _lock_contained=true
        ;;
    esac
  fi
  if [ "$_lock_contained" = true ]; then
    CABAL_LOCK_FILE="$_resolved_lock"
  else
    echo "SECURITY: External CABAL_LOCK_FILE outside RELEASE_HOME (realpath containment check failed)" >&2
    CABAL_LOCK_FILE=""
  fi
fi'''

if old_cabal not in content:
    print("ERROR: Could not find CABAL_LOCK block to fix", file=sys.stderr)
    sys.exit(1)
content = content.replace(old_cabal, new_cabal)

# Fix 3: Remove stray NIX_EVAL lines before nix_eval_is_allowlisted if they exist
stray_block = '''
NIX_EVAL_OUT=""
NIX_EVAL_STATUS=1
NIX_EVAL_MODE="restricted"

# F2 fix: Validate CONCEPTS before interpolation - fail-closed if empty or unsafe'''

clean_block = '''
# F2 fix: Validate CONCEPTS before interpolation - fail-closed if empty or unsafe'''

if stray_block in content:
    content = content.replace(stray_block, clean_block)
    print("Fixed: Removed stray NIX_EVAL lines before nix_eval_is_allowlisted")
else:
    print("Info: No stray NIX_EVAL lines found (may have been pre-existing)")

with open(path, "w") as f:
    f.write(content)

print("Syntax fixes applied: removed `local` from top-level, restructured CABAL_LOCK containment check")
