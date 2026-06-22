import sys

path = sys.argv[1]
with open(path, 'r') as f:
    lines = f.readlines()

out = []
i = 0
while i < len(lines):
    line = lines[i]
    out.append(line)
    # D1: Replace C1 lock guard - match by startswith since line has em-dash suffix
    if line.strip().startswith('# C1 fix: Per-run isolated lock file') and i + 2 < len(lines):
        i += 3  # skip the 3-line old guard block
        out.append('# C1/D1 fix: Per-run isolated lock file with external override guard.\n')
        out.append('if [ -n "$CABAL_LOCK_FILE" ]; then\n')
        out.append('  case "$CABAL_LOCK_FILE" in\n')
        out.append('    "$RELEASE_HOME"/*)\n')
        out.append('      ;;\n')
        out.append('    *)\n')
        out.append('      echo "SECURITY: External CABAL_LOCK_FILE outside RELEASE_HOME" >&2\n')
        out.append('      CABAL_LOCK_FILE=""\n')
        out.append('      ;;\n')
        out.append('  esac\n')
        out.append('fi\n')
        out.append('if [ -z "$CABAL_LOCK_FILE" ]; then\n')
        out.append('  CABAL_LOCK_FILE="$RELEASE_HOME/cabal.lock"\n')
        out.append('fi\n')
        i += 1
        continue
    # F2: Replace allowlist function - match by function name, skip preceding comments
    if 'nix_eval_is_allowlisted()' in line:
        # Remove preceding comment lines we already added
        while out and out[-1].strip().startswith('#'):
            out.pop()
        out.append('# F2 fix: Validate CONCEPTS before interpolation - fail-closed if empty or unsafe\n')
        out.append('nix_eval_is_allowlisted() {\n')
        out.append('    local expr="$1"\n')
        out.append('    if [ -z "${CONCEPTS:-}" ]; then\n')
        out.append('        return 1\n')
        out.append('    fi\n')
        out.append('    case "$CONCEPTS" in\n')
        out.append('        *[!A-Za-z0-9._/$"-]*)\n')
        out.append('            return 1\n')
        out.append('            ;;\n')
        out.append('    esac\n')
        out.append('    [ "$expr" = "let c = import $CONCEPTS; in builtins.length c.concepts" ] && return 0\n')
        out.append('    [ "$expr" = "let c = import $CONCEPTS; in c.constitutionalThresholds.agencyFloor" ] && return 0\n')
        out.append('    [ "$expr" = "let c = import $CONCEPTS; in c.constitutionalThresholds.tensionCeiling" ] && return 0\n')
        out.append('    return 1\n')
        out.append('}\n')
        # Skip old function body until closing brace
        i += 1
        while i < len(lines) and lines[i].strip() != '}':
            i += 1
        i += 1
        continue
    i += 1

with open(path, 'w') as f:
    f.writelines(out)

print('Fixes applied: D1 (lock guard), F2 (CONCEPTS validation)')
