#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REQUIRE_GF="${QXFX0_REQUIRE_GF:-1}"
GF_TOOLCHAIN_ID="${QXFX0_GF_TOOLCHAIN_ID:-gf2}"
SYNTAX_CONCRETE="$ROOT/spec/gf/QxFx0SyntaxRus.gf"
OUT_PGF="$ROOT/spec/gf/QxFx0Syntax.pgf"
MANIFEST_FILE="$ROOT/spec/gf/QxFx0Syntax.pgf.manifest"

# Add ~/.cabal/bin to PATH to find gf binary (avoid shell alias 'gf=git fetch')
export PATH="$HOME/.cabal/bin:$PATH"

if [ ! -f "$SYNTAX_CONCRETE" ]; then
  echo "GF_GRAMMAR_INPUT_MISSING: $SYNTAX_CONCRETE" >&2
  exit 1
fi

compile_with_gf() {
  cd "$ROOT"
  "$GF_BIN" --make "spec/gf/QxFx0SyntaxRus.gf" >/dev/null
}

compile_with_nix_shell() {
  nix --option warn-dirty false --extra-experimental-features "nix-command flakes" \
    develop "$ROOT" --command gf --make "spec/gf/QxFx0SyntaxRus.gf" >/dev/null
}

# Fast path: if PGF manifest matches current GF sources and toolchain marker, skip compile.
needs_compile() {
  local pgf="$OUT_PGF"
  local manifest="$MANIFEST_FILE"
  if [ ! -f "$pgf" ] || [ ! -f "$manifest" ]; then
    return 0
  fi
  local expected
  expected="$(sha256sum "$ROOT/spec/gf/"*.gf | sha256sum | cut -d' ' -f1):$GF_TOOLCHAIN_ID"
  local recorded
  recorded="$(cut -d' ' -f1 "$manifest" 2>/dev/null || true)"
  [ "$expected" != "$recorded" ]
}

if ! needs_compile; then
  echo "OK: $OUT_PGF is up to date"
  exit 0
fi

# Check for real GF compiler (not shell alias)
GF_BIN=""
for candidate in "$HOME/.cabal/bin/gf" "$(command -v gf 2>/dev/null)"; do
  if [ -x "$candidate" ] && "$candidate" --version 2>/dev/null | grep -q "Grammatical Framework"; then
    GF_BIN="$candidate"
    break
  fi
done

if [ -n "$GF_BIN" ]; then
  compile_with_gf
else
  if [ "$REQUIRE_GF" != "1" ]; then
    if [ -f "$OUT_PGF" ]; then
      echo "GF_INFRA_UNAVAILABLE: gf compiler is not installed; existing $OUT_PGF cannot be treated as current truth." >&2
      exit 1
    fi
    echo "SKIP: gf compiler is not installed and no $OUT_PGF present."
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

manifest_hash="$(sha256sum "$ROOT/spec/gf/"*.gf | sha256sum | cut -d' ' -f1):$GF_TOOLCHAIN_ID"
printf '%s  %s\n' "$manifest_hash" "$OUT_PGF" > "$MANIFEST_FILE"

echo "OK: compiled $OUT_PGF"
