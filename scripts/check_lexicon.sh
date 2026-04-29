#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MIN_SCORE="${QXFX0_LEXICON_MIN_SCORE:-8.0}"

# Auto-source quality thresholds — scale-step (P1=3000-5000, P2=15000-20000)
P1_MIN="${QXFX0_P1_MIN:-3000}"
P1_MAX="${QXFX0_P1_MAX:-5000}"
P2_MIN="${QXFX0_P2_MIN:-15000}"
P2_MAX="${QXFX0_P2_MAX:-20000}"
P1_MOSTLY_PROPER_MAX="${QXFX0_P1_MOSTLY_PROPER_MAX:-0}"
P1_PATRONYMIC_LIKE_MAX="${QXFX0_P1_PATRONYMIC_LIKE_MAX:-0}"
P1_LONG_LEMMA_MAX="${QXFX0_P1_LONG_LEMMA_MAX:-15}"
P1_TECHNICAL_COMPOUND_MAX="${QXFX0_P1_TECHNICAL_COMPOUND_MAX:-15}"
P2_PATRONYMIC_LIKE_MAX="${QXFX0_P2_PATRONYMIC_LIKE_MAX:-50}"
P1_DOMAIN_SEED_HIT_MIN="${QXFX0_P1_DOMAIN_SEED_HIT_MIN:-100}"
DANGEROUS_COLLISION_MAX="${QXFX0_DANGEROUS_COLLISION_MAX:-0}"
NOUN_INS_EQ_NOM_MAX="${QXFX0_NOUN_INS_EQ_NOM_MAX:-0}"
FEM_ACC_EQ_NOM_MAX="${QXFX0_FEM_ACC_EQ_NOM_MAX:-0}"
SOFT_INS_EQ_NOM_MAX="${QXFX0_SOFT_INS_EQ_NOM_MAX:-0}"

cd "$ROOT"

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required for lexical gate" >&2
  exit 1
fi

if [ "${1:-}" = "--fix" ]; then
  python3 scripts/export_lexicon.py --min-score "$MIN_SCORE"
else
  python3 scripts/export_lexicon.py --check --min-score "$MIN_SCORE"
fi

# Check auto-source quality metrics if the file exists
QUALITY_FILE="resources/morphology/lexicon_quality.json"
if [ -f "$QUALITY_FILE" ]; then
  echo "Checking auto-source quality metrics..."

  if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required for metric checks" >&2
    exit 1
  fi

  # Extract metrics using python3
  METRICS=$(python3 -c "
import json
import sys

with open('$QUALITY_FILE', 'r') as f:
    data = json.load(f)

metrics = data.get('auto_quality_metrics', {})
if not metrics:
    print('NO_METRICS')
    sys.exit(0)

print(f\"p1_lemma_count={metrics.get('p1_lemma_count', 0)}\")
print(f\"p2_lemma_count={metrics.get('p2_lemma_count', 0)}\")
print(f\"p1_mostly_proper_count={metrics.get('p1_mostly_proper_count', 0)}\")
print(f\"p1_patronymic_like_count={metrics.get('p1_patronymic_like_count', 0)}\")
print(f\"p1_long_lemma_count={metrics.get('p1_long_lemma_count', 0)}\")
print(f\"p1_technical_compound_count={metrics.get('p1_technical_compound_count', 0)}\")
print(f\"p2_patronymic_like_count={metrics.get('p2_patronymic_like_count', 0)}\")
print(f\"p1_domain_seed_hit_count={metrics.get('p1_domain_seed_hit_count', 0)}\")

fbs = data.get('forms_by_surface', {})
print(f\"dangerous_collision_count={fbs.get('dangerous_collision_count', 0)}\")

case_metrics = data.get('case_surface_metrics', {})
print(f\"noun_ins_eq_nom_count={case_metrics.get('noun_ins_eq_nom_count', 0)}\")
print(f\"feminine_like_acc_eq_nom_count={case_metrics.get('feminine_like_acc_eq_nom_count', 0)}\")
print(f\"soft_sign_ins_eq_nom_count={case_metrics.get('soft_sign_ins_eq_nom_count', 0)}\")
")

  if [ "$METRICS" = "NO_METRICS" ]; then
    echo "WARNING: No auto_quality_metrics found in $QUALITY_FILE"
  else
    # Evaluate the metrics
    eval "$METRICS"

    FAILED=0

    if [ "$p1_lemma_count" -lt "$P1_MIN" ]; then
      echo "FAIL: p1_lemma_count ($p1_lemma_count) < min ($P1_MIN)"
      FAILED=1
    fi

    if [ "$p1_lemma_count" -gt "$P1_MAX" ]; then
      echo "FAIL: p1_lemma_count ($p1_lemma_count) > max ($P1_MAX)"
      FAILED=1
    fi

    if [ "$p2_lemma_count" -lt "$P2_MIN" ]; then
      echo "FAIL: p2_lemma_count ($p2_lemma_count) < min ($P2_MIN)"
      FAILED=1
    fi

    if [ "$p2_lemma_count" -gt "$P2_MAX" ]; then
      echo "FAIL: p2_lemma_count ($p2_lemma_count) > max ($P2_MAX)"
      FAILED=1
    fi

    if [ "$p1_mostly_proper_count" -gt "$P1_MOSTLY_PROPER_MAX" ]; then
      echo "FAIL: p1_mostly_proper_count ($p1_mostly_proper_count) > max ($P1_MOSTLY_PROPER_MAX)"
      FAILED=1
    fi

    if [ "$p1_patronymic_like_count" -gt "$P1_PATRONYMIC_LIKE_MAX" ]; then
      echo "FAIL: p1_patronymic_like_count ($p1_patronymic_like_count) > max ($P1_PATRONYMIC_LIKE_MAX)"
      FAILED=1
    fi

    if [ "$p1_long_lemma_count" -gt "$P1_LONG_LEMMA_MAX" ]; then
      echo "FAIL: p1_long_lemma_count ($p1_long_lemma_count) > max ($P1_LONG_LEMMA_MAX)"
      FAILED=1
    fi

    if [ "$p1_technical_compound_count" -gt "$P1_TECHNICAL_COMPOUND_MAX" ]; then
      echo "FAIL: p1_technical_compound_count ($p1_technical_compound_count) > max ($P1_TECHNICAL_COMPOUND_MAX)"
      FAILED=1
    fi

    if [ "$p2_patronymic_like_count" -gt "$P2_PATRONYMIC_LIKE_MAX" ]; then
      echo "FAIL: p2_patronymic_like_count ($p2_patronymic_like_count) > max ($P2_PATRONYMIC_LIKE_MAX)"
      FAILED=1
    fi

    if [ "$p1_domain_seed_hit_count" -lt "$P1_DOMAIN_SEED_HIT_MIN" ]; then
      echo "FAIL: p1_domain_seed_hit_count ($p1_domain_seed_hit_count) < min ($P1_DOMAIN_SEED_HIT_MIN)"
      FAILED=1
    fi

    if [ "$dangerous_collision_count" -gt "$DANGEROUS_COLLISION_MAX" ]; then
      echo "FAIL: dangerous_collision_count ($dangerous_collision_count) > max ($DANGEROUS_COLLISION_MAX)"
      FAILED=1
    fi

    if [ "$noun_ins_eq_nom_count" -gt "$NOUN_INS_EQ_NOM_MAX" ]; then
      echo "FAIL: noun_ins_eq_nom_count ($noun_ins_eq_nom_count) > max ($NOUN_INS_EQ_NOM_MAX)"
      FAILED=1
    fi

    if [ "$feminine_like_acc_eq_nom_count" -gt "$FEM_ACC_EQ_NOM_MAX" ]; then
      echo "FAIL: feminine_like_acc_eq_nom_count ($feminine_like_acc_eq_nom_count) > max ($FEM_ACC_EQ_NOM_MAX)"
      FAILED=1
    fi

    if [ "$soft_sign_ins_eq_nom_count" -gt "$SOFT_INS_EQ_NOM_MAX" ]; then
      echo "FAIL: soft_sign_ins_eq_nom_count ($soft_sign_ins_eq_nom_count) > max ($SOFT_INS_EQ_NOM_MAX)"
      FAILED=1
    fi

    if [ "$FAILED" -eq 1 ]; then
      echo "Auto-source quality gate FAILED"
      exit 1
    fi

    echo "Auto-source quality metrics PASSED"
    echo "  p1_lemma_count: $p1_lemma_count (range: $P1_MIN-$P1_MAX)"
    echo "  p2_lemma_count: $p2_lemma_count (range: $P2_MIN-$P2_MAX)"
    echo "  p1_mostly_proper_count: $p1_mostly_proper_count (max: $P1_MOSTLY_PROPER_MAX)"
    echo "  p1_patronymic_like_count: $p1_patronymic_like_count (max: $P1_PATRONYMIC_LIKE_MAX)"
    echo "  p1_long_lemma_count: $p1_long_lemma_count (max: $P1_LONG_LEMMA_MAX)"
    echo "  p1_technical_compound_count: $p1_technical_compound_count (max: $P1_TECHNICAL_COMPOUND_MAX)"
    echo "  p2_patronymic_like_count: $p2_patronymic_like_count (max: $P2_PATRONYMIC_LIKE_MAX)"
    echo "  p1_domain_seed_hit_count: $p1_domain_seed_hit_count (min: $P1_DOMAIN_SEED_HIT_MIN)"
    echo "  dangerous_collision_count: $dangerous_collision_count (max: $DANGEROUS_COLLISION_MAX)"
    echo "  noun_ins_eq_nom_count: $noun_ins_eq_nom_count (max: $NOUN_INS_EQ_NOM_MAX)"
    echo "  feminine_like_acc_eq_nom_count: $feminine_like_acc_eq_nom_count (max: $FEM_ACC_EQ_NOM_MAX)"
    echo "  soft_sign_ins_eq_nom_count: $soft_sign_ins_eq_nom_count (max: $SOFT_INS_EQ_NOM_MAX)"
  fi
fi
