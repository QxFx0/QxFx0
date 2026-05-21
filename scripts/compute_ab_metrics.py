#!/usr/bin/env python3
"""
compute_ab_metrics.py — Compute objective metrics from A/B raw JSONL.
"""

import json
import sys
from collections import defaultdict
from pathlib import Path

def load_jsonl(path):
    rows = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except Exception:
                continue
    return rows

def compute_metrics(rows):
    total = len(rows)
    if total == 0:
        return {}
    
    latencies = [r.get("_wall_time_ms", 0) for r in rows]
    lat_sorted = sorted(latencies)
    p50 = lat_sorted[len(lat_sorted)//2] if lat_sorted else 0
    p95_idx = int(len(lat_sorted)*0.95)
    p95 = lat_sorted[min(p95_idx, len(lat_sorted)-1)] if lat_sorted else 0
    
    families = defaultdict(int)
    styles = defaultdict(int)
    forces = defaultdict(int)
    errors = 0
    empty_resp = 0
    legitimacy_scores = []
    agency_scores = []
    tension_scores = []
    response_lengths = []
    
    for r in rows:
        families[r.get("family", "UNKNOWN")] += 1
        styles[r.get("render_style", "")] += 1
        forces[r.get("force", "")] += 1
        if r.get("_error"):
            errors += 1
        resp = r.get("response", "")
        if not resp or not resp.strip():
            empty_resp += 1
        response_lengths.append(len(resp.split()))
        leg = r.get("legitimacy")
        if isinstance(leg, (int, float)):
            legitimacy_scores.append(leg)
        ego = r.get("ego_agency")
        if isinstance(ego, (int, float)):
            agency_scores.append(ego)
        ten = r.get("ego_tension")
        if isinstance(ten, (int, float)):
            tension_scores.append(ten)
    
    return {
        "total_turns": total,
        "avg_latency_ms": sum(latencies)/len(latencies) if latencies else 0,
        "p50_latency_ms": p50,
        "p95_latency_ms": p95,
        "error_count": errors,
        "error_rate": errors/total,
        "empty_response_count": empty_resp,
        "empty_response_rate": empty_resp/total,
        "avg_response_words": sum(response_lengths)/len(response_lengths) if response_lengths else 0,
        "family_distribution": dict(families),
        "style_distribution": dict(styles),
        "force_distribution": dict(forces),
        "avg_legitimacy": sum(legitimacy_scores)/len(legitimacy_scores) if legitimacy_scores else 0,
        "avg_ego_agency": sum(agency_scores)/len(agency_scores) if agency_scores else 0,
        "avg_ego_tension": sum(tension_scores)/len(tension_scores) if tension_scores else 0,
    }

def main():
    if len(sys.argv) < 3:
        print("Usage: compute_ab_metrics.py raw_A.jsonl raw_B.jsonl")
        sys.exit(1)
    
    rows_a = load_jsonl(sys.argv[1])
    rows_b = load_jsonl(sys.argv[2])
    
    m_a = compute_metrics(rows_a)
    m_b = compute_metrics(rows_b)
    
    print("# Objective Metrics: A vs B\n")
    print("| Metric | A (baseline) | B (current) | Delta |")
    print("|--------|--------------|-------------|-------|")
    
    keys = [
        ("total_turns", "{}"),
        ("avg_latency_ms", "{:.1f}"),
        ("p50_latency_ms", "{}"),
        ("p95_latency_ms", "{}"),
        ("error_rate", "{:.4f}"),
        ("empty_response_rate", "{:.4f}"),
        ("avg_response_words", "{:.1f}"),
        ("avg_legitimacy", "{:.4f}"),
        ("avg_ego_agency", "{:.4f}"),
        ("avg_ego_tension", "{:.4f}"),
    ]
    
    for key, fmt in keys:
        a_val = m_a.get(key, 0)
        b_val = m_b.get(key, 0)
        delta = b_val - a_val
        print(f"| {key} | {fmt.format(a_val)} | {fmt.format(b_val)} | {delta:+.3f} |")
    
    # Family drift
    print("\n## Family Distribution Drift\n")
    all_fams = sorted(set(m_a.get("family_distribution", {}).keys()) | set(m_b.get("family_distribution", {}).keys()))
    print("| Family | A count | A % | B count | B % | Delta % |")
    print("|--------|---------|-----|---------|-----|---------|")
    for fam in all_fams:
        a_count = m_a.get("family_distribution", {}).get(fam, 0)
        b_count = m_b.get("family_distribution", {}).get(fam, 0)
        a_pct = a_count / m_a["total_turns"] * 100 if m_a["total_turns"] else 0
        b_pct = b_count / m_b["total_turns"] * 100 if m_b["total_turns"] else 0
        print(f"| {fam} | {a_count} | {a_pct:.1f}% | {b_count} | {b_pct:.1f}% | {b_pct-a_pct:+.1f}% |")

if __name__ == "__main__":
    main()
