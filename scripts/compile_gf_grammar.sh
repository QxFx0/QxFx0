#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REQUIRE_GF="${QXFX0_REQUIRE_GF:-1}"
SYNTAX_CONCRETE="$ROOT/spec/gf/QxFx0SyntaxRus.gf"
OUT_PGF="$ROOT/spec/gf/QxFx0Syntax.pgf"

if [ ! -f "$SYNTAX_CONCRETE" ]; then
  echo "GF_GRAMMAR_INPUT_MISSING: $SYNTAX_CONCRETE" >&2
  exit 1
fi

compile_with_gf() {
  cd "$ROOT"
  gf -make -f pgf "spec/gf/QxFx0SyntaxRus.gf" >/dev/null
}

compile_with_nix_shell() {
  nix --option warn-dirty false --extra-experimental-features "nix-command flakes" \
    develop "$ROOT" --command gf -make -f pgf "spec/gf/QxFx0SyntaxRus.gf" >/dev/null
}

if command -v gf >/dev/null 2>&1; then
  compile_with_gf
else
  if [ "$REQUIRE_GF" != "1" ]; then
    echo "SKIP: gf compiler is not installed; PGF compile step not enforced."
    exit 0
  fi
  if command -v nix >/dev/null 2>&1 && [ -f "$ROOT/flake.nix" ]; then
    if ! compile_with_nix_shell; then
      echo "GF_INFRA_UNAVAILABLE: gf compiler is required, and nix-based fallback failed." >&2
      exit 1
    fi
  else
    echo "GF_INFRA_UNAVAILABLE: gf compiler is required (QXFX0_REQUIRE_GF=1), but 'gf' and nix fallback were not available." >&2
    exit 1
  fi
fi

if [ ! -f "$OUT_PGF" ]; then
  echo "GF_GRAMMAR_COMPILE_FAILED: GF compile finished but PGF output was not created: $OUT_PGF" >&2
  exit 1
fi

echo "OK: compiled $OUT_PGF"
