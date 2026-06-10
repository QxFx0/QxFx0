#!/usr/bin/env bash
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/src"
APP="$ROOT/app"
VIOLATIONS=0
CORE_SEMANTIC_PORT_PREFIX="src/QxFx0/Core/Semantic/"
CORE_POLICY_PORT_PREFIX="src/QxFx0/Core/Policy/"

fail_violation() {
  echo "VIOLATION: $1"
  VIOLATIONS=$((VIOLATIONS + 1))
}

is_core_semantic_port_module() {
  local candidate="$1"
  [[ "$candidate" == "$CORE_SEMANTIC_PORT_PREFIX"* ]]
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
  if rg -n '^\s*import\s+QxFx0\.(Bridge|Core|Runtime)' "$file" \
       | rg -v 'Runtime\.GF\.Morphology' \
       | rg -v 'Core\.Proposition[A-Za-z]*Admission' >/dev/null 2>&1; then
    fail_violation "$file imports Bridge/Core/Runtime from Semantic"
  fi
done < <(find "$SRC/QxFx0/Semantic" -name "*.hs" 2>/dev/null || true)

echo "  [2b] Render modules must not import Core/Bridge/Runtime..."
while IFS= read -r file; do
  if rg -n '^\s*import\s+(qualified\s+)?QxFx0\.(Core|Bridge|Runtime)' "$file" | rg -v 'Runtime\.GF\.Morphology' >/dev/null 2>&1; then
    fail_violation "$file imports Core/Bridge/Runtime from Render"
  fi
done < <(find "$SRC/QxFx0/Render" -name "*.hs" 2>/dev/null || true)

echo "  [2c] Core→Semantic imports — port modules removed; direct imports allowed..."
# (Core.Semantic.* facade modules were consolidated into direct QxFx0.Semantic.* imports)

echo "  [2d] Core→Render imports — port modules removed; direct imports allowed..."
# (Core.Render.* facade modules were consolidated into direct QxFx0.Render.* imports)

echo "  [2e] Core→Policy imports — port modules removed; direct imports allowed..."
# (Core.Policy.* facade modules were consolidated into direct QxFx0.Policy.* imports)

echo "  [3] Bridge modules must not hardcode spec paths..."
while IFS= read -r file; do
  if rg -n '"spec/|"semantic_rules\.dl"' "$file" | rg -v '[0-9]+:\s*--' >/dev/null 2>&1; then
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
  if rg -n 'SomeException' "$file" | rg -v '[0-9]+:\s*--' >/dev/null 2>&1; then
    fail_violation "$file uses SomeException (use IOException/ExceptionPolicy instead)"
  fi
done < <(find "$SRC/QxFx0/Bridge" "$SRC/QxFx0/Semantic" "$SRC/QxFx0/Core" "$SRC/QxFx0/Resources" "$APP" -name "*.hs" 2>/dev/null || true)

echo "  [6] No partial read in source (use readMaybe/parseTimeM)..."
while IFS= read -r file; do
  if rg -n '\bread\s+\S+::\s*Int\b|\bread\s+"' "$file" | rg -v '[0-9]+:\s*--' >/dev/null 2>&1; then
    fail_violation "$file uses partial read (use readMaybe/parseTimeM)"
  fi
done < <(find "$SRC" "$APP" -name "*.hs" 2>/dev/null || true)

echo "  [7] No bare head/tail/init/last in source (use safe alternatives)..."
while IFS= read -r file; do
  if rg -n '\b(head|tail|init|last)\s+\S' "$file" | rg -v '[0-9]+:\s*--|readMaybe|takeBaseName|import' >/dev/null 2>&1; then
    fail_violation "$file uses bare partial functions (head/tail/init/last)"
  fi
done < <(find "$SRC" "$APP" -name "*.hs" 2>/dev/null || true)

echo "  [8] No bare fail in IO context in source (use throwQxFx0 from ExceptionPolicy)..."
while IFS= read -r file; do
  if rg -n '\bfail\s+"' "$file" | rg -v '[0-9]+:\s*--|FromJSON|ToJSON|Parser|Value' >/dev/null 2>&1; then
    fail_violation "$file uses bare fail in IO context (use throwQxFx0)"
  fi
done < <(find "$SRC" "$APP" -name "*.hs" 2>/dev/null || true)

echo "  [8b] No raw userError in source (use throwQxFx0 from ExceptionPolicy)..."
while IFS= read -r file; do
  if rg -n '\bioError\s*\(\s*userError\b|\bthrowIO\s*\(\s*userError\b' "$file" | rg -v '[0-9]+:\s*--' >/dev/null 2>&1; then
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
if ! cabal run qxfx0-main -- --check-embedded-sql >/dev/null 2>&1; then
  fail_violation "EmbeddedSQL.hs/migration are out of sync with spec/sql (run: cabal run qxfx0-main -- --sync-embedded-sql)"
fi

echo "  [10b] HTTP perimeter invariants must stay closed..."
# Perimeter is split — loopback bind guard in app/CLI/Http.hs (Haskell launcher),
# auth/session/sanitize in scripts/http_runtime.py (Python sidecar).
if ! python3 - "$ROOT" >/dev/null 2>&1 <<'PY'; then
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
http_hs = (root / "app/CLI/Http.hs").read_text(encoding="utf-8")
http_runtime_py = (root / "scripts/http_runtime.py").read_text(encoding="utf-8")

# Haskell launcher: loopback guard
for forbidden in (
    '|| h == "0.0.0.0"',
    'http_runtime.py',
):
    if forbidden in http_hs:
        raise SystemExit(1)

for required in (
    'QXFX0_HTTP_HOST',
    'QXFX0_HTTP_PORT',
    'QXFX0_ALLOW_NON_LOOPBACK_HTTP',
    'isLoopbackHost',
):
    if required not in http_hs:
        raise SystemExit(1)

# Python sidecar: auth, session, sanitize, endpoints
for forbidden in (
    '0.0.0.0',
):
    if forbidden in http_runtime_py:
        raise SystemExit(1)

for required in (
    'QXFX0_API_KEY',
    'QXFX0_REQUIRE_SESSION_TOKEN',
    'def sanitize_input',
    'hmac.compare_digest',
    '"unauthorized"',
    '401',
    'points outside trusted roots',
    '"/sidecar-health"',
    '"/runtime-ready"',
):
    if required not in http_runtime_py:
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

echo "  [11] Exposed QxFx0.Core.* modules must be reachable from Runtime/TurnPipeline..."
if ! python3 - "$ROOT" >/dev/null 2>&1 <<'PY'; then
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
cabal = (root / "qxfx0.cabal").read_text(encoding="utf-8")

exposed_core: list[str] = []
in_library = False
in_exposed = False
for line in cabal.splitlines():
    if line.startswith("library"):
        in_library = True
    if in_library and line.startswith("executable"):
        break
    if in_library and line.strip() == "exposed-modules:":
        in_exposed = True
        continue
    if in_library and in_exposed:
        stripped = line.strip()
        if stripped == "other-modules:" or stripped.startswith("hs-source-dirs:"):
            in_exposed = False
            continue
        if stripped.startswith("QxFx0.Core."):
            exposed_core.append(stripped)

import_re = re.compile(
    r"^\s*import\s+(?:qualified\s+)?(QxFx0\.(?:Core|Runtime)[A-Za-z0-9.]*)",
    re.MULTILINE,
)

def module_path(mod: str) -> pathlib.Path:
    return root / "src" / (mod.replace("QxFx0.", "QxFx0/").replace(".", "/") + ".hs")

roots = [
    * (root / "src/QxFx0/Runtime").rglob("*.hs"),
    * (root / "src/QxFx0/Core/TurnPipeline").rglob("*.hs"),
]
reachable: set[str] = set()
visited_files: set[pathlib.Path] = set()
queue = [p for p in roots if p.is_file()]

while queue:
    path = queue.pop()
    if path in visited_files:
        continue
    visited_files.add(path)
    text = path.read_text(encoding="utf-8")
    for mod in import_re.findall(text):
        if not mod.startswith("QxFx0.Core."):
            continue
        reachable.add(mod)
        mod_path = module_path(mod)
        if mod_path.is_file() and mod_path not in visited_files:
            queue.append(mod_path)

def allowed(mod: str) -> bool:
    if mod == "QxFx0.Core":
        return True
    if mod == "QxFx0.Core.TurnPipeline" or mod.startswith("QxFx0.Core.TurnPipeline."):
        return True
    # CTS-admission modules (Proposition*Admission, *Admission) are consumed by
    # QxFx0.Semantic.Proposition — they form the Semantic/Core admission boundary.
    if mod.startswith("QxFx0.Core.Proposition") and mod.endswith("Admission"):
        return True
    if mod.endswith("Admission") and mod.startswith("QxFx0.Core."):
        return True
    return mod in reachable

orphans = [m for m in sorted(exposed_core) if not allowed(m)]
if orphans:
    for mod in orphans:
        print(f"orphan exposed core module: {mod}", file=sys.stderr)
    raise SystemExit(1)
PY
  fail_violation "exposed Core module not reachable from Runtime/TurnPipeline"
fi

echo "  [12] Pipeline call sites must access Holistic/Formal only through Self.Adjunction..."
while IFS= read -r file; do
  if rg -n '^\s*import\s+(qualified\s+)?QxFx0\.Self\.(Holistic|Formal)(\s|$)' "$file" >/dev/null 2>&1; then
    fail_violation "$file imports QxFx0.Self.Holistic or QxFx0.Self.Formal directly (use QxFx0.Self.Adjunction)"
  fi
done < <(find "$SRC/QxFx0/Core/TurnPipeline" -name "*.hs" 2>/dev/null || true)

# ---------------------------------------------------------------------------
# Boundary rules from ADR-0013 §3 (Self/Core role split). Each rule
# below has an explicit "enforce" and a "review" section; the
# enforcement is the mechanical part, the review is the human part.
# Reference: docs/adr/proposed/0013-self-core-role-split.md
# ---------------------------------------------------------------------------

echo "  [13] ADR-0013 §3 Rule 1: Self/* must be canonical-only; no downward writes to Core.TurnPipeline.* or Bridge.*..."
while IFS= read -r file; do
  if rg -n '^\s*import\s+(qualified\s+)?QxFx0\.(Core\.TurnPipeline|Bridge)' "$file" >/dev/null 2>&1; then
    fail_violation "$file (Self/*) imports Core.TurnPipeline.* or Bridge.* (ADR-0013 Rule 1)"
  fi
done < <(find "$SRC/QxFx0/Self" -name "*.hs" 2>/dev/null || true)

echo "  [14] ADR-0013 §3 Rule 2: Core/* supplier modules must not import canonical-orchestrator writers..."
# Canonical-orchestrator writers are the modules that write to
# SystemState. The closure plan's role split puts these in
# Core.TurnPipeline.Finalize.* and Core.TurnPipeline.Effects.
# Supplier modules are those that import nothing under
# Core.TurnPipeline.* and are tagged "supplier" in their Haddock.
# Mechanical enforcement: any module under Core/* that does NOT
# declare "observer" or "supplier" in its module Haddock header
# (the line beginning "Description :") must not import
# Core.TurnPipeline.Finalize.* or Core.TurnPipeline.Effects.
if ! python3 - "$ROOT" >/dev/null 2>&1 <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
core_root = root / "src/QxFx0/Core"
if not core_root.is_dir():
    raise SystemExit(0)

forbidden = (
    "QxFx0.Core.TurnPipeline.Finalize",
    "QxFx0.Core.TurnPipeline.Effects",
    "QxFx0.Core.TurnPipeline.Route.Render",
)
finalize_mods = re.compile(r"^\s*import\s+(?:qualified\s+)?(QxFx0\.Core\.TurnPipeline\.Finalize(?:\.[A-Za-z0-9]+)*)\b", re.MULTILINE)
effects_mods  = re.compile(r"^\s*import\s+(?:qualified\s+)?(QxFx0\.Core\.TurnPipeline\.Effects(?:\.[A-Za-z0-9]+)*)\b", re.MULTILINE)
route_render  = re.compile(r"^\s*import\s+(?:qualified\s+)?(QxFx0\.Core\.TurnPipeline\.Route\.Render)\b", re.MULTILINE)

violations: list[str] = []
for path in core_root.rglob("*.hs"):
    text = path.read_text(encoding="utf-8")
    # Skip the orchestrator modules themselves; they are the writers.
    rel = str(path.relative_to(root))
    if rel.startswith("src/QxFx0/Core/TurnPipeline/") or rel == "src/QxFx0/Core/TurnPipeline.hs":
        continue
    # Skip observer modules; observers emit into trace only and are
    # allowed to import Core.Observability (but not the writers).
    # The role is declared in the module Haddock; we look for a
    # "Description" line that names "observer" or "supplier".
    haddock = re.search(r"Description\s*:\s*([^\n]*)", text)
    role = (haddock.group(1) if haddock else "").lower()
    if "observer" in role or "supplier" in role:
        continue
    for pat in (finalize_mods, effects_mods, route_render):
        m = pat.search(text)
        if m:
            violations.append(f"{rel} imports {m.group(1)} (must declare role in Haddock or move to TurnPipeline)")

if violations:
    for v in violations:
        print(v, file=sys.stderr)
    raise SystemExit(1)
PY
then
  fail_violation "Core/* module imports canonical-orchestrator writer without declaring supplier/observer role (ADR-0013 Rule 2)"
fi

echo "  [15] ADR-0013 §3 Rule 5: only Bridge.ExternalLLM may be opt-in by feature flag..."
# A new Bridge/* module that uses a feature flag (QXFX0_*_ENABLED)
# is rejected unless it is Bridge/ExternalLLM.hs. The check
# enumerates Bridge/*.hs and looks for QXFX0_*_ENABLED lookups.
if ! python3 - "$ROOT" >/dev/null 2>&1 <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
bridge_root = root / "src/QxFx0/Bridge"
if not bridge_root.is_dir():
    raise SystemExit(0)

flag_re = re.compile(r"\bQXFX0_[A-Z][A-Z0-9_]*ENABLED\b")

violations: list[str] = []
for path in bridge_root.rglob("*.hs"):
    rel = str(path.relative_to(root))
    if rel == "src/QxFx0/Bridge/ExternalLLM.hs":
        continue
    text = path.read_text(encoding="utf-8")
    if flag_re.search(text):
        violations.append(f"{rel} uses a QXFX0_*_ENABLED feature flag (only Bridge.ExternalLLM may; ADR-0013 Rule 5)")

if violations:
    for v in violations:
        print(v, file=sys.stderr)
    raise SystemExit(1)
PY
then
  fail_violation "Bridge/* module uses a feature flag without explicit ADR (ADR-0013 Rule 5)"
fi

echo "  [16] ADR-0013 §3 Rule 7: derived modules must have a regenerator referenced from scripts/..."
# Lexicon.Generated.hs and any other derived module under
# Resources/ or top-level *Generated.hs must be producible by
# a script under scripts/. The script must be referenced in
# scripts/verify.sh or scripts/ci_gate_contract.sh (the canonical
# CI entry point). This is a heuristic: we check that the
# generator script exists.
if ! python3 - "$ROOT" >/dev/null 2>&1 <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
scripts = root / "scripts"
if not scripts.is_dir():
    raise SystemExit(0)

derived = list((root / "src").rglob("*Generated.hs")) + list((root / "src").rglob("*/Resources/*Generated*"))
violations: list[str] = []
for path in derived:
    stem = path.stem
    candidates = [
        scripts / f"build_{stem.lower()}.sh",
        scripts / f"generate_{stem.lower()}.sh",
        scripts / f"build_{stem.lower()}.py",
    ]
    if not any(c.is_file() for c in candidates):
        violations.append(f"{path.relative_to(root)} has no obvious generator script under scripts/ (ADR-0013 Rule 7)")

if violations:
    for v in violations:
        print(v, file=sys.stderr)
    raise SystemExit(1)
PY
then
  fail_violation "derived module has no generator script (ADR-0013 Rule 7)"
fi

echo "  [17] ADR-0013 §3 Rule 1 (declarative): Self/* modules must declare role in module Haddock..."
# A new Self/* module is canonical by construction. We require
# every Self/*.hs to have a Description line that names the role
# (canonical, canonical-flag-off, or supplier — supplier is
# permitted only for Self/* adapters; not for the self-layer
# proper).
if ! python3 - "$ROOT" >/dev/null 2>&1 <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
self_root = root / "src/QxFx0/Self"
if not self_root.is_dir():
    raise SystemExit(0)

allowed = ("canonical", "canonical-flag-off", "supplier")
violations: list[str] = []
for path in self_root.rglob("*.hs"):
    text = path.read_text(encoding="utf-8")
    haddock = re.search(r"Description\s*:\s*([^\n]*)", text)
    if not haddock:
        violations.append(f"{path.relative_to(root)}: missing 'Description :' line in module Haddock")
        continue
    role = haddock.group(1).lower()
    if not any(a in role for a in allowed):
        violations.append(
            f"{path.relative_to(root)}: Haddock does not declare one of {allowed} (got: {haddock.group(1).strip()!r})"
        )

if violations:
    for v in violations:
        print(v, file=sys.stderr)
    raise SystemExit(1)
PY
then
  fail_violation "Self/* module missing canonical/canonical-flag-off/supplier role in Haddock (ADR-0013 Rule 1)"
fi

echo "  [18] ADR-0013 §3 Rule 4 (review): Render/* must route through Route/Render.buildTurnArtifacts..."
# Static check: every Render/*.hs that defines a top-level
# function whose name starts with "render" should import
# QxFx0.Core.TurnPipeline.Route.Render (or be a renderer
# orchestrator itself). This is a heuristic: it flags modules
# that look like they bypass the orchestrator.
if ! python3 - "$ROOT" >/dev/null 2>&1 <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
render_root = root / "src/QxFx0/Render"
if not render_root.is_dir():
    raise SystemExit(0)

orchestrator = re.compile(r"QxFx0\.Core\.TurnPipeline\.Route\.Render")
def_render = re.compile(r"^(?:render|build)\w*\s*::", re.MULTILINE)
import_re  = re.compile(r"^\s*import\s+(?:qualified\s+)?QxFx0\.([A-Za-z0-9.]+)\b", re.MULTILINE)

violations: list[str] = []
for path in render_root.rglob("*.hs"):
    text = path.read_text(encoding="utf-8")
    # The orchestrator module itself is allowed to skip the import.
    rel = str(path.relative_to(root))
    if "Route/Render.hs" in rel or "Route.Render" in rel:
        continue
    # Utility/legacy surface renderers are excluded from this rule:
    #   Render.Semantic    — observability helper, not turn-pipeline renderer
    #   Render.Authority   — authority surface stub, not turn-pipeline renderer
    #   Render.Dialogue    — legacy surface renderer using DialogAssembly, not Route.Render
    excluded_modules = ("Render/Semantic.hs", "Render/Authority.hs", "Render/Dialogue.hs")
    if any(excl in rel for excl in excluded_modules):
        continue
    if not def_render.search(text):
        continue
    # Does the module import the orchestrator or one of its
    # focused submodules (e.g. Route.Render.BuildArtifacts)?
    imports = set(import_re.findall(text))
    if not any(i.startswith("Core.TurnPipeline.Route.Render") for i in imports):
        violations.append(
            f"{rel}: defines a render*/build* function but does not import QxFx0.Core.TurnPipeline.Route.Render (ADR-0013 Rule 4)"
        )

if violations:
    for v in violations:
        print(v, file=sys.stderr)
    raise SystemExit(1)
PY
then
  fail_violation "Render/* module defines a render*/build* function without importing the orchestrator (ADR-0013 Rule 4)"
fi

echo "  [19] ADR-0013 §3 Rule 3 (review): Core/* observer modules declare role and emit trace-only..."
# Observers are modules that import QxFx0.Core.Observability. They
# must declare "observer" in their Haddock and must not define
# any function that returns a SystemState or writes to ss*.
# Heuristic: any module that imports Core.Observability but does
# not have "observer" in its Haddock Description is a violation.
if ! python3 - "$ROOT" >/dev/null 2>&1 <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
core_root = root / "src/QxFx0/Core"
if not core_root.is_dir():
    raise SystemExit(0)

obs_import = re.compile(r"^\s*import\s+(?:qualified\s+)?QxFx0\.Core\.Observability\b", re.MULTILINE)
haddock_re = re.compile(r"Description\s*:\s*([^\n]*)")

violations: list[str] = []
for path in core_root.rglob("*.hs"):
    text = path.read_text(encoding="utf-8")
    if not obs_import.search(text):
        continue
    h = haddock_re.search(text)
    role = (h.group(1) if h else "").lower()
    if "observer" not in role:
        violations.append(
            f"{path.relative_to(root)}: imports QxFx0.Core.Observability but Haddock does not declare 'observer' role (ADR-0013 Rule 3)"
        )

if violations:
    for v in violations:
        print(v, file=sys.stderr)
    raise SystemExit(1)
PY
then
  fail_violation "Core/* module imports Observability without declaring observer role (ADR-0013 Rule 3)"
fi

echo "  [20] ADR-0013 §3 Rule 6: canonical-flag-off modules are not in the authority path..."
# Per docs/closure/PROMOTION_PLAYBOOK.md, flags not yet promoted must not
# have '= True' in production code. Promoted flags must have '= True'.
#
# Current state (2026-06-10, post-ADR-0034/0045/0046/0047/0048 promotions):
#   PROMOTED  — Family Divergence (ADR-0019, salienceGuardDivergenceEnabled = True)
#               Episodic Recall (ADR-0034, episodicRecallActive = True)
#               Doubt Loop (ADR-0045, doubtLoopActive = True)
#               Affect Decoupled (ADR-0046, affectDecoupledActive = True)
#               Content Salience (ADR-0047, contentSalienceActive = True)
#               Derived Inference (ADR-0048, derivedInferenceActive = True)
#   FLAG-OFF  — Essence, Perspective Operator, External LLM, Adaptive Mutation,
#               User Model, Runtime Morphology
#
# The check has two parts:
#   (a) The 6 not-yet-promoted flags must not have '= True' in src/.
#   (b) Promoted flags must have '= True' at their declared paths.
if ! python3 - "$ROOT" >/dev/null 2>&1 <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
src_root = root / "src"
if not src_root.is_dir():
    raise SystemExit(0)

# Not-yet-promoted flags: must NOT have '= True' in src/.
# (flag_name, in_code) — in_code=True means also check '= False' exists.
FLAG_OFF_FLAGS = [
    ("Essence",              "essenceCommitmentEnabled",                False),
    ("Perspective Operator", "QXFX0_PERSPECTIVE_OPERATOR_ENABLED",       False),
    ("External LLM",         "QXFX0_BRIDGE_EXTERNAL_LLM_ENABLED",        False),
    ("Adaptive Mutation",    "QXFX0_ADAPTIVE_MUTATION_ENABLED",          False),
    ("User Model",           "userModelActive",                          False),
    ("Runtime Morphology",   "runtimeMorphologyActive",                  False),
]

# Promoted flags: must have '= True' in src/.
PROMOTED_FLAGS = [
    ("Family Divergence",    "salienceGuardDivergenceEnabled",   "src/QxFx0/Core/TurnRouting/Cascade.hs"),
    ("Episodic Recall",      "episodicRecallActive",             "src/QxFx0/Memory/Episodic.hs"),
    ("Doubt Loop",           "doubtLoopActive",                  "src/QxFx0/Core/ConsciousnessLoop.hs"),
    ("Affect Decoupled",     "affectDecoupledActive",            "src/QxFx0/Self/Field.hs"),
    ("Content Salience",     "contentSalienceActive",            "src/QxFx0/Core/ContentCluster.hs"),
    ("Derived Inference",    "derivedInferenceActive",           "src/QxFx0/Semantic/Logic.hs"),
]

true_lit_re = re.compile(r"\b\w+\s*=\s*True\b")
false_lit_re = re.compile(r"\b\w+\s*=\s*False\b")

violations: list[str] = []

# Part (a): flag-off checks
for (contour, flag, in_code) in FLAG_OFF_FLAGS:
    true_files: list[str] = []
    false_files: list[str] = []
    for path in src_root.rglob("*.hs"):
        text = path.read_text(encoding="utf-8")
        for line_no, line in enumerate(text.splitlines(), 1):
            if flag not in line:
                continue
            if true_lit_re.search(line):
                true_files.append(f"{path.relative_to(root)}:{line_no}")
            if in_code and false_lit_re.search(line):
                false_files.append(f"{path.relative_to(root)}:{line_no}")
    if true_files:
        violations.append(
            f"{contour} ({flag}): '= True' literal found in production code (not yet promoted): "
            + ", ".join(true_files)
        )
    if in_code and not false_files:
        violations.append(
            f"{contour} ({flag}): in-code flag is missing '= False' literal in src/"
        )

# Part (b): promoted flag checks
for (contour, flag, expected_path) in PROMOTED_FLAGS:
    target = root / expected_path
    if not target.is_file():
        violations.append(
            f"{contour} ({flag}): promoted flag file not found at {expected_path}"
        )
        continue
    text = target.read_text(encoding="utf-8")
    found_true = any(
        flag in line and true_lit_re.search(line)
        for line in text.splitlines()
    )
    if not found_true:
        violations.append(
            f"{contour} ({flag}): promoted flag must have '= True' in {expected_path} (ADR-0019)"
        )

if violations:
    for v in violations:
        print(v, file=sys.stderr)
    raise SystemExit(1)
PY
then
  fail_violation "canonical-flag-off discipline violated (ADR-0013 Rule 6)"
fi

echo "  [21] Anti-rot registry: every registered guard test exists in test/ (ADR-0042)..."
ANTI_ROT_REGISTRY="$ROOT/docs/anti_rot_registry.tsv"
if [ -f "$ANTI_ROT_REGISTRY" ]; then
  while IFS=$'\t' read -r artifact _kind _site test_name wp _adr _notes; do
    case "$artifact" in ''|'#'*|'artifact') continue ;; esac
    [ -z "$test_name" ] && continue
    if ! rg -F -q -- "$test_name" "$ROOT/test" 2>/dev/null; then
      fail_violation "anti-rot: registered test '$test_name' ($artifact, $wp) absent from test/ (ADR-0042)"
    fi
  done < "$ANTI_ROT_REGISTRY"
fi

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "Architecture check failed: $VIOLATIONS violation(s)"
  exit 1
fi

echo "Architecture check passed."
