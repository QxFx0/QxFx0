#!/usr/bin/env python3
import sys

path = "/home/liskil/my-haskell-project/QxFx0/scripts/release-smoke.sh"
with open(path, "r") as f:
    lines = f.readlines()

# Find and replace the nix_eval_is_allowlisted and nix_eval_expr functions
start = None
end = None
for i, line in enumerate(lines):
    if line.startswith("# C2 fix: Allowlist for vetted nix expressions"):
        start = i
    if start is not None and i > start and line.strip() == "}" and lines[i-1].strip() == 'return "$NIX_EVAL_STATUS"':
        end = i + 1
        break

if start is None or end is None:
    print("ERROR: Could not find functions to replace")
    sys.exit(1)

print(f"Found functions at lines {start+1}-{end} (0-indexed {start}-{end-1})")

new_funcs = """# C1/D1 fix: Exact string comparison \u2014 no glob matching.
# Only the three vetted expressions are permitted.
nix_eval_is_allowlisted() {
    local expr="$1"
    [ "$expr" = "let c = import ${CONCEPTS:-}; in builtins.length c.concepts" ] && return 0
    [ "$expr" = "let c = import ${CONCEPTS:-}; in c.constitutionalThresholds.agencyFloor" ] && return 0
    [ "$expr" = "let c = import ${CONCEPTS:-}; in c.constitutionalThresholds.tensionCeiling" ] && return 0
    return 1
}

# C2 fix: Fail-closed in ALL modes \u2014 no unrestricted fallback.
nix_eval_expr() {
    local expr="$1"
    NIX_EVAL_OUT="$(nix-instantiate --restricted --eval -E "$expr" 2>&1)"
    NIX_EVAL_STATUS=$?
    NIX_EVAL_MODE="restricted"
    if [ "$NIX_EVAL_STATUS" -ne 0 ] && \\
       printf '%s' "$NIX_EVAL_OUT" | grep -Eqi 'unrecogni[sz]ed flag' && \\
       printf '%s' "$NIX_EVAL_OUT" | grep -q -- '--restricted'; then
        # C2 fix: Fail-closed in ALL modes \u2014 no unrestricted fallback.
        echo "SECURITY: nix-instantiate --restricted unavailable \u2014 refusing unrestricted fallback (fail-closed)" >&2
        return "$NIX_EVAL_STATUS"
    fi
    return "$NIX_EVAL_STATUS"
}
"""

lines[start:end] = [new_funcs]

# Find and add ERR trap after "trap cleanup EXIT"
found_trap = False
for i, line in enumerate(lines):
    if line.strip() == "trap cleanup EXIT":
        err_trap = """trap cleanup EXIT
# C3 fix: ERR trap \u2014 catch unexpected failures and ensure fail-closed.
on_error() {
    local exit_code=$?
    local line=$1
    echo "ERROR: Unexpected failure at line $line (exit code: $exit_code) \u2014 failing closed" >&2
    FAIL=$((FAIL+1))
}
trap 'on_error $LINENO' ERR
"""
        lines[i] = err_trap
        found_trap = True
        break

if not found_trap:
    print("WARNING: Could not find 'trap cleanup EXIT' to add ERR trap")

with open(path, "w") as f:
    f.writelines(lines)

print("All three fixes applied successfully")
