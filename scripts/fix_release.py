import sys

path = sys.argv[1]
with open(path, 'r') as f:
    lines = f.readlines()

out = []
i = 0
while i < len(lines):
    line = lines[i]
    out.append(line)
    # F1: After umask 077, add TMPDIR validation
    if line.strip() == 'umask 077':
        out.append('\n')
        out.append('# F1 fix: Validate TMPDIR\n')
        out.append('if [ -n "${TMPDIR:-}" ]; then\n')
        out.append('    case "$TMPDIR" in\n')
        out.append('        /tmp|/tmp/|/var/tmp|/var/tmp/)\n')
        out.append('            ;;\n')
        out.append('        *)\n')
        out.append('            if [ -d "$TMPDIR" ] && [ -O "$TMPDIR" ]; then\n')
        out.append('                :\n')
        out.append('            else\n')
        out.append('                echo "SECURITY: TMPDIR not /tmp and not user-owned" >&2\n')
        out.append('                TMPDIR=/tmp\n')
        out.append('            fi\n')
        out.append('            ;;\n')
        out.append('    esac\n')
        out.append('fi\n')
    # D1: Replace C1 lock guard with D1 guard
    if line.strip() == '# C1 fix: Per-run isolated lock file' and i + 2 < len(lines):
        i += 3
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
    # F2: Replace allowlist function
    if 'nix_eval_is_allowlisted()' in line and i > 0 and 'C1/D1 fix' in lines[i-1]:
        out.pop()
        out.pop()
        out.append('# F2 fix: Validate CONCEPTS before interpolation\n')
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
        i += 1
        while i < len(lines) and lines[i].strip() != '}':
            i += 1
        i += 1
        continue
    i += 1

with open(path, 'w') as f:
    f.writelines(out)

print('Fixes applied: F1 (umask+TMPDIR), D1 (lock guard), F2 (CONCEPTS validation)')
