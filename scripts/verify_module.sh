#!/bin/sh
# Typecheck a set of qxfx0 library modules (or a subtree) without a cabal build.
# Usage: verifymod.sh <file.hs> [file2.hs ...]
set -e
cd "$(dirname "$0")/.."
BUILD="dist-newstyle/build/x86_64-linux/ghc-9.6.6/qxfx0-0.1.0.0/build"
ARGS=""
while read -r u; do ARGS="$ARGS -package-id $u"; done < /tmp/opencode/qxfx0_units.txt
exec /home/liskil/.ghcup/bin/ghc-9.6.6 -fno-code -fforce-recomp \
  -package-db dist-newstyle/packagedb/ghc-9.6.6 \
  -package-db /home/liskil/.cabal/store/ghc-9.6.6/package.db \
  $ARGS -package-id qxfx0-0.1.0.0-inplace \
  -i/tmp/opencode/stub -i"$BUILD" -isrc "$@"