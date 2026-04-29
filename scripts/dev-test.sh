#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${QXFX0_TEST_BUILD_DIR:-dist-test}"
CABAL_STATE_DIR="${QXFX0_TEST_CABAL_DIR:-$ROOT/.cabal-dev-test}"

cd "$ROOT"
mkdir -p "$CABAL_STATE_DIR"
if [ ! -f "$CABAL_STATE_DIR/config" ] && [ -f "$HOME/.cabal/config" ]; then
  cp "$HOME/.cabal/config" "$CABAL_STATE_DIR/config"
fi
export CABAL_DIR="$CABAL_STATE_DIR"
cabal test qxfx0-test --builddir="$BUILD_DIR"
