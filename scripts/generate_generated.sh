#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Wrapper for the real generator of src/QxFx0/Lexicon/Generated.hs
# (called by check_architecture.sh rule [16])
python3 scripts/export_lexicon.py
