#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/src"
APP="$ROOT/app"
VIOLATIONS=0
CORE_SEMANTIC_PORT_PREFIX="src/QxFx0/Core/Semantic/"
CORE_RENDER_PORT_PREFIX="src/QxFx0/Core/Render/"
CORE_POLICY_PORT_PREFIX="src/QxFx0/Core/Policy/"

fail_violation() {
  echo "VIOLATION: $1"
  VIOLATIONS=$((VIOLATIONS + 1))
}

is_core_semantic_port_module() {
  local candidate="$1"
  [[ "$candidate" == "$CORE_SEMANTIC_PORT_PREFIX"* ]]
}

is_core_render_port_module() {
  local candidate="$1"
  [[ "$candidate" == "$CORE_RENDER_PORT_PREFIX"* ]]
}

is_core_policy_port_module() {
  local candidate="$1"
  [[ "$candidate" == "$CORE_POLICY_PORT_PREFIX"* ]]
}

echo "Architecture checks:"

echo "  [1] Types modules must not import Core/Bridge/Semantic..."
while IFS= read -r file; do
  if rg -n '^\s*import\s+QxFx0\.(Core|Bridge|Semantic)' "$file" >/dev/null 2>&1; then
    fail_violation "$file imports forbidden layer from Types"
  fi
done < <(
  { find "$SRC/QxFx0" -path "$SRC/QxFx0/Types.hs" -type f 2>/dev/null || true; \
    find "$SRC/QxFx0/Types" -name "*.hs" -type f 2>/dev/null || true; } | sort -u
)

echo "  [2] Semantic modules must not import Bridge/Core/Runtime..."
while IFS= read -r file; do
  if rg -n '^\s*import\s+QxFx0\.(Bridge|Core|Runtime)' "$file" >/dev/null 2>&1; then
    fail_violation "$file imports Bridge/Core/Runtime from Semantic"
  fi
done < <(find "$SRC/QxFx0/Semantic" -name "*.hs" 2>/dev/null || true)

echo "  [2b] Render modules must not import Core/Bridge/Runtime..."
while IFS= read -r file; do
  if rg -n '^\s*import\s+(qualified\s+)?QxFx0\.(Core|Bridge|Runtime)' "$file" >/dev/null 2>&1; then
    fail_violation "$file imports Core/Bridge/Runtime from Render"
  fi
done < <(find "$SRC/QxFx0/Render" -name "*.hs" 2>/dev/null || true)

echo "  [2c] Core→Semantic imports must stay inside Core semantic port modules..."
while IFS= read -r file; do
  if rg -n '^\s*import\s+(qualified\s+)?QxFx0\.Semantic' "$file" >/dev/null 2>&1; then
    rel="${file#$ROOT/}"
    if ! is_core_semantic_port_module "$rel"; then
      fail_violation "$rel imports Semantic directly (use QxFx0.Core.Semantic.* port)"
    fi
  fi
done < <(
  { find "$SRC/QxFx0" -path "$SRC/QxFx0/Core.hs" -type f 2>/dev/null || true; \
    find "$SRC/QxFx0/Core" -name "*.hs" 2>/dev/null || true; } | sort -u
)

echo "  [2d] Core→Render imports must stay inside Core render port modules..."
while IFS= read -r file; do
  if rg -n '^\s*import\s+(qualified\s+)?QxFx0\.Render' "$file" >/dev/null 2>&1; then
    rel="${file#$ROOT/}"
    if ! is_core_render_port_module "$rel"; then
      fail_violation "$rel imports Render directly (use QxFx0.Core.Render.* port)"
    fi
  fi
done < <(
  { find "$SRC/QxFx0" -path "$SRC/QxFx0/Core.hs" -type f 2>/dev/null || true; \
    find "$SRC/QxFx0/Core" -name "*.hs" 2>/dev/null || true; } | sort -u
)

echo "  [2e] Core→Policy imports must stay inside Core policy port modules..."
while IFS= read -r file; do
  if rg -n '^\s*import\s+(qualified\s+)?QxFx0\.Policy' "$file" >/dev/null 2>&1; then
    rel="${file#$ROOT/}"
    if ! is_core_policy_port_module "$rel"; then
      fail_violation "$rel imports Policy directly (use QxFx0.Core.Policy.* port)"
    fi
  fi
done < <(
  { find "$SRC/QxFx0" -path "$SRC/QxFx0/Core.hs" -type f 2>/dev/null || true; \
    find "$SRC/QxFx0/Core" -name "*.hs" 2>/dev/null || true; } | sort -u
)

echo "  [3] Bridge modules must not hardcode spec paths..."
while IFS= read -r file; do
  if rg -n '"spec/|"semantic_rules\.dl"' "$file" | rg -v ':[0-9]+:\s*--' >/dev/null 2>&1; then
    fail_violation "$file contains hardcoded spec path"
  fi
done < <(find "$SRC/QxFx0/Bridge" -name "*.hs" 2>/dev/null || true)

echo "  [4] Bridge modules must not import Core... Core modules must not import Bridge or Runtime..."
while IFS= read -r file; do
  if rg -n '^\s*import\s+(qualified\s+)?QxFx0\.Core' "$file" >/dev/null 2>&1; then
    fail_violation "$file imports Core from Bridge (shims removed)"
  fi
done < <(find "$SRC/QxFx0/Bridge" -name "*.hs" 2>/dev/null || true)
while IFS= read -r file; do
  if rg -n '^\s*import\s+(qualified\s+)?QxFx0\.(Bridge|Runtime)' "$file" >/dev/null 2>&1; then
    fail_violation "$file imports Bridge/Runtime from Core module (use PipelineIO / Runtime boundary)"
  fi
done < <(
  { find "$SRC/QxFx0" -path "$SRC/QxFx0/Core.hs" -type f 2>/dev/null || true; \
    find "$SRC/QxFx0/Core" -name "*.hs" 2>/dev/null || true; } | sort -u
)

echo "  [4b] Runtime modules must not import top-level QxFx0.Core aggregator..."
while IFS= read -r file; do
  if rg -n '^\s*import\s+(qualified\s+)?QxFx0\.Core(\s|$)' "$file" >/dev/null 2>&1; then
    fail_violation "$file imports top-level QxFx0.Core from Runtime (depend on focused Core modules)"
  fi
done < <(find "$SRC/QxFx0/Runtime" -name "*.hs" 2>/dev/null || true)
if [ -f "$SRC/QxFx0/Runtime.hs" ]; then
  if rg -n '^\s*import\s+(qualified\s+)?QxFx0\.Core(\s|$)' "$SRC/QxFx0/Runtime.hs" >/dev/null 2>&1; then
    fail_violation "$SRC/QxFx0/Runtime.hs imports top-level QxFx0.Core from Runtime facade"
  fi
fi

echo "  [5] No SomeException in Bridge/Semantic/Core/Resources/app source (use IOException/ExceptionPolicy)..."
while IFS= read -r file; do
  if rg -n 'SomeException' "$file" | rg -v ':[0-9]+:\s*--' >/dev/null 2>&1; then
    fail_violation "$file uses SomeException (use IOException/ExceptionPolicy instead)"
  fi
done < <(find "$SRC/QxFx0/Bridge" "$SRC/QxFx0/Semantic" "$SRC/QxFx0/Core" "$SRC/QxFx0/Resources" "$APP" -name "*.hs" 2>/dev/null || true)

echo "  [6] No partial read in source (use readMaybe/parseTimeM)..."
while IFS= read -r file; do
  if rg -n '\bread\s+\S+::\s*Int\b|\bread\s+"' "$file" | rg -v ':[0-9]+:\s*--' >/dev/null 2>&1; then
    fail_violation "$file uses partial read (use readMaybe/parseTimeM)"
  fi
done < <(find "$SRC" "$APP" -name "*.hs" 2>/dev/null || true)

echo "  [7] No bare head/tail/init/last in source (use safe alternatives)..."
while IFS= read -r file; do
  if rg -n '\b(head|tail|init|last)\s+\S' "$file" | rg -v ':[0-9]+:\s*--|readMaybe|takeBaseName|import' >/dev/null 2>&1; then
    fail_violation "$file uses bare partial functions (head/tail/init/last)"
  fi
done < <(find "$SRC" "$APP" -name "*.hs" 2>/dev/null || true)

echo "  [8] No bare fail in IO context in source (use throwQxFx0 from ExceptionPolicy)..."
while IFS= read -r file; do
  if rg -n '\bfail\s+"' "$file" | rg -v ':[0-9]+:\s*--|FromJSON|ToJSON|Parser|Value' >/dev/null 2>&1; then
    fail_violation "$file uses bare fail in IO context (use throwQxFx0)"
  fi
done < <(find "$SRC" "$APP" -name "*.hs" 2>/dev/null || true)

echo "  [8b] No raw userError in source (use throwQxFx0 from ExceptionPolicy)..."
while IFS= read -r file; do
  if rg -n '\bioError\s*\(\s*userError\b|\bthrowIO\s*\(\s*userError\b' "$file" | rg -v ':[0-9]+:\s*--' >/dev/null 2>&1; then
    fail_violation "$file uses raw userError (use throwQxFx0)"
    continue
  fi
  # Multiline fallback for wrapped expressions like ioError \n (userError ...)
  collapsed="$(tr '\n' ' ' < "$file")"
  if [[ "$collapsed" =~ ioError[[:space:]]*\([[:space:]]*userError ]] || [[ "$collapsed" =~ throwIO[[:space:]]*\([[:space:]]*userError ]]; then
    fail_violation "$file uses raw userError (use throwQxFx0)"
  fi
done < <(find "$SRC" "$APP" -name "*.hs" 2>/dev/null || true)

echo "  [9] Runtime code must import operational templates from Policy, not Lexicon..."
while IFS= read -r file; do
  if [[ "$file" == *"/src/QxFx0/Lexicon/"* ]]; then
    continue
  fi
  if rg -n '^\s*import\s+QxFx0\.Lexicon\.Templates' "$file" >/dev/null 2>&1; then
    fail_violation "$file imports QxFx0.Lexicon.Templates outside lexicon compatibility layer"
  fi
done < <(find "$SRC" "$APP" -name "*.hs" 2>/dev/null || true)

echo "  [10] EmbeddedSQL.hs must be in sync with spec/sql..."
if ! command -v python3 &>/dev/null; then
  fail_violation "python3 is required for SQL single-source sync checks"
elif [ ! -x "$ROOT/scripts/sync_embedded_sql.py" ]; then
  fail_violation "scripts/sync_embedded_sql.py is missing or not executable"
elif ! python3 "$ROOT/scripts/sync_embedded_sql.py" --check >/dev/null 2>&1; then
  fail_violation "EmbeddedSQL.hs/migration are out of sync with spec/sql (run: python3 scripts/sync_embedded_sql.py)"
fi

echo "  [10b] HTTP perimeter invariants must stay closed..."
if ! python3 - "$ROOT" >/dev/null 2>&1 <<'PY'; then
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
http_hs = (root / "app/CLI/Http.hs").read_text(encoding="utf-8")
embedding_hs = (root / "src/QxFx0/Semantic/Embedding/Runtime.hs").read_text(encoding="utf-8")
http_py = (root / "scripts/http_runtime.py").read_text(encoding="utf-8")

if '|| h == "0.0.0.0"' in http_hs:
    raise SystemExit(1)
if 'Just (normalise "scripts/http_runtime.py")' in http_hs:
    raise SystemExit(1)
if 'Just url -> EmbeddingSelection EmbeddingBackendRemoteHTTP False' in embedding_hs:
    raise SystemExit(1)
local_start = embedding_hs.index('EmbeddingSelection EmbeddingBackendLocalDeterministic explicit _ ->')
remote_start = embedding_hs.index('EmbeddingSelection EmbeddingBackendRemoteHTTP explicit mUrl ->')
local_block = embedding_hs[local_start:remote_start]
if 'ehStrictReady = True' not in local_block:
    raise SystemExit(1)
for required in (
    'QXFX0_HTTP_HOST',
    'QXFX0_HTTP_PORT',
    'QXFX0_ALLOW_NON_LOOPBACK_HTTP',
    'non_loopback_bind_requires_opt_in',
):
    if required not in http_py:
        raise SystemExit(1)

health_start = http_py.index('if path == "/health":')
health_auth = http_py.index('if API_KEY and not self._check_auth():', health_start)
health_evict = http_py.index('registry.evict_idle()', health_start)
if health_auth > health_evict:
    raise SystemExit(1)

sidecar_start = http_py.index('if path == "/sidecar-health":')
sidecar_auth = http_py.index('if API_KEY and not self._check_auth():', sidecar_start)
sidecar_evict = http_py.index('registry.evict_idle()', sidecar_start)
if sidecar_auth > sidecar_evict:
    raise SystemExit(1)

sanitize_pos = http_py.index('sanitized = sanitize_input(user_input)')
claim_pos = http_py.index('ownership_status, owned_session_token = session_owners.claim_or_validate')
if sanitize_pos > claim_pos:
    raise SystemExit(1)
PY
  fail_violation "HTTP perimeter invariants drifted (bind/auth/input/script/embedding contract)"
fi

echo "  [10c] Acceptance gates and docs must reflect local recovery architecture..."
if ! python3 - "$ROOT" >/dev/null 2>&1 <<'PY'; then
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
verify = (root / "scripts/verify.sh").read_text(encoding="utf-8")
release = (root / "scripts/release-smoke.sh").read_text(encoding="utf-8")
agents = (root / "AGENTS.md").read_text(encoding="utf-8")

for content in (verify, release):
    if "trcLlmFallbackPolicy" in content:
        raise SystemExit(1)
    for field in (
        "trcLocalRecoveryPolicy",
        "trcRecoveryCause",
        "trcRecoveryStrategy",
        "trcRecoveryEvidence",
    ):
        if field not in content:
            raise SystemExit(1)

if "LLM I/O" in agents:
    raise SystemExit(1)
PY
  fail_violation "acceptance gates/docs drifted from local-recovery architecture"
fi

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "Architecture check failed: $VIOLATIONS violation(s)"
  exit 1
fi

echo "Architecture check passed."
