#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SMOKE_DIR="$(mktemp -d)"
trap 'rm -rf "$SMOKE_DIR"' EXIT

MOCK_CABAL_DIR="$SMOKE_DIR/mock-bin"
mkdir -p "$MOCK_CABAL_DIR"

# Helper: create a mock cabal that writes given stderr text and exits with given code
mk_mock_cabal() {
  local exit_code="$1"
  local stderr_text="$2"
  cat > "$MOCK_CABAL_DIR/cabal" <<EOF
#!/usr/bin/env bash
if [[ "\$*" == *"test -v0 --enable-coverage qxfx0-test"* ]]; then
  echo "$stderr_text" >&2
  exit $exit_code
fi
# fallback: delegate to real cabal for any other invocation
exec $(command -v cabal) "\$@"
EOF
  chmod +x "$MOCK_CABAL_DIR/cabal"
}

run_coverage() {
  PATH="$MOCK_CABAL_DIR:$PATH" bash "$ROOT/scripts/test_coverage.sh" 2>&1 || true
}

echo "=== Smoke test 1: known infrastructure incompatibility must yield SKIP ==="
mk_mock_cabal 1 "Error:\n    Internal libraries only supported with per-component builds.\n    Per-component builds were disabled because program coverage is enabled\n    In the package 'vector-0.13.2.0'"
OUT1="$(run_coverage)"
RC1=0
PATH="$MOCK_CABAL_DIR:$PATH" bash "$ROOT/scripts/test_coverage.sh" >/dev/null 2>&1 || RC1=$?
if [ "$RC1" -ne 2 ]; then
  echo "FAIL: expected exit code 2 (SKIP), got $RC1"
  echo "Output: $OUT1"
  exit 1
fi
if ! echo "$OUT1" | grep -q 'COVERAGE_STATUS=SKIP'; then
  echo "FAIL: expected COVERAGE_STATUS=SKIP in output"
  echo "Output: $OUT1"
  exit 1
fi
echo "PASS"

echo "=== Smoke test 2: normal test failure must NOT be masked as SKIP ==="
mk_mock_cabal 1 "test suite qxfx0-test: FAIL\nSome tests failed."
OUT2="$(run_coverage)"
RC2=0
PATH="$MOCK_CABAL_DIR:$PATH" bash "$ROOT/scripts/test_coverage.sh" >/dev/null 2>&1 || RC2=$?
if [ "$RC2" -eq 2 ]; then
  echo "FAIL: expected exit code != 2 (not SKIP), got $RC2"
  echo "Output: $OUT2"
  exit 1
fi
if [ "$RC2" -ne 1 ]; then
  echo "FAIL: expected exit code 1 (FAIL), got $RC2"
  echo "Output: $OUT2"
  exit 1
fi
if ! echo "$OUT2" | grep -q 'COVERAGE_STATUS=FAIL'; then
  echo "FAIL: expected COVERAGE_STATUS=FAIL in output"
  echo "Output: $OUT2"
  exit 1
fi
echo "PASS"

echo "=== Smoke test 3: coverage gate must not silently succeed on missing script ==="
# This is handled by verify.sh, but we can at least ensure the script is executable
if [ ! -x "$ROOT/scripts/test_coverage.sh" ]; then
  echo "FAIL: test_coverage.sh is not executable"
  exit 1
fi
echo "PASS"

echo "=== All coverage-gate smoke tests passed ==="
