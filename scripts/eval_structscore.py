#!/usr/bin/env python3
"""structScore vs Jaccard top-1 eval on human-labelled holdout.

Cutover gate (Composition.hs header): structScore top-1 accuracy >=
Jaccard + 0.05 on human-labelled data, else weights stay hand-set.

Method (record-level, honest):
- Eval set: 40 rated records with predicate_relevant in {0,1,2}
  (corpus.jsonl labels joined to rated_responses.json by id).
- Candidates: the topic's definitionCorpus RU predicates, extracted
  from Content.hs `entry` blocks (asserted 120 topics).
- Query: parsePredicateTerm(input) with the runtime lemma map
  (paradigms.json + exceptions.json replica, cf.
  scripts/lemma_verb_coverage.py).
- Used candidate: argmax token-overlap(response, candidate). For
  covered_exact rel=2 turns the predicate renders near-verbatim, so
  the mapping is checkable; low-overlap mappings are flagged.
- Metric: top-1 hit = scorer ranks the used candidate #1
  (ties broken by candidate order, same as production selectPredicates
  top-1 discipline). Reported on covered rel=2 records; rel in {0,1}
  is diagnostic only (the label rejects the production pick, so a
  "hit" there means repeating the mistake).

The pure Composition functions are ported below and cross-checked
against the Haskell unit vectors before any eval runs. Lexicon sets
are parsed from Composition.hs (single source of truth), never
transcribed by hand.
"""
import json
import re
import sys
from itertools import product
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src" / "QxFx0" / "Semantic" / "Composition.hs"
CONTENT = ROOT / "src" / "QxFx0" / "Semantic" / "Content.hs"
MORPH = ROOT / "resources" / "morphology"

PUNCT = set('.,?!:;«»"()')


def parse_str_set(src, name):
    m = re.search(name + r" = S\.fromList\n(.*?)\n  \]", src, re.DOTALL)
    if not m:
        m = re.search(name + r" = S\.fromList \[([^\]]+)\]", src)
    assert m, name
    return set(re.findall(r'"([^"]+)"', m.group(1)))


COMPSRC = SRC.read_text(encoding="utf-8")
REL_LEX = sorted(parse_str_set(COMPSRC, "relationLexicon"))
NEG = parse_str_set(COMPSRC, "negationMarkers")
STOP = parse_str_set(COMPSRC, "compositionStopWords")
m = re.search(r"defaultStructWeights = StructWeights\n(.*?)\n  \}", COMPSRC,
              re.DOTALL)
W = {}
for k in ("swHead", "swRel", "swMod", "swNeg"):
    W[k] = float(re.search(k + r" = ([0-9.]+)", m.group(1)).group(1))
assert abs(sum(W.values()) - 1.0) < 1e-9, W


def build_lemma_map():
    lemma = {}
    for name in ("paradigms", "exceptions"):
        d = json.load(open(MORPH / f"{name}.json", encoding="utf-8"))
        for lem, entry in d.items():
            for _k, surf in entry.get("forms", {}).items():
                s, l = str(surf).lower(), str(lem).lower()
                if s:
                    lemma.setdefault(s, l)
    return lemma


def common_prefix5(a, b):
    if len(a) < 5:
        return False
    n = 0
    for ca, cb in zip(a, b):
        if ca != cb:
            break
        n += 1
    return n >= 4


def rel_lemma_of(t, keys):
    if t in REL_LEX:
        return t
    if t in keys:
        return None
    for v in REL_LEX:
        if common_prefix5(t, v):
            return v
    return None


def parse_term(lemma, text):
    toks = []
    for w in text.lower().split():
        w = "".join(c for c in w if c not in PUNCT)
        if w:
            toks.append(lemma.get(w, w))
    neg = any(t in NEG for t in toks)
    core = [t for t in toks if t not in NEG and t not in STOP]
    keys = set(lemma.keys())
    rel_of = {}
    for t in core:
        rel_of[t] = rel_lemma_of(t, keys)
    concepts = [t for t in core if rel_of[t] is None]
    head = concepts[0] if concepts else None
    rels = set()
    for i, r in enumerate(core):
        verb = rel_of[r]
        if verb is None:
            continue
        foll = [c for c in core[i + 1:] if rel_of[c] is None]
        if foll:
            obj = foll[0]
        elif head is not None:
            obj = head
        else:
            obj = r
        rels.add((verb, obj))
    robjs = {o for _, o in rels}
    mods = {c for c in concepts if c != head and c not in robjs}
    return (head, rels, mods, neg)


def struct_with(w, q, p):
    qh, qr, qm, qn = q
    ph, pr, pm, pn = p
    hs = 1.0 if (qh is not None and qh == ph) else 0.0
    rs = len(qr & pr) / len(qr) if qr else 0.0
    ms = len(qm & pm) / len(qm) if qm else 0.0
    ns = 1.0 if qn == pn else 0.0
    return w["swHead"] * hs + w["swRel"] * rs + w["swMod"] * ms + w["swNeg"] * ns


def jaccard(a, b):
    def conc(t):
        h, r, m, _n = t
        return ({h} if h is not None else set()) | {o for _, o in r} | set(m)
    sa, sb = conc(a), conc(b)
    u = len(sa | sb)
    return len(sa & sb) / u if u else 0.0


def self_check():
    lm = {"требует": "требовать", "ответственности": "ответственность",
          "свободы": "свобода", "исключает": "исключать"}
    t = parse_term(lm, "свобода требует осознанной ответственности")
    assert struct_with(W, t, t) == 1.0, "identity must be 1.0"
    fwd = parse_term(lm, "свобода требует ответственности")
    bwd = parse_term(lm, "ответственность требует свободы")
    j = jaccard(fwd, bwd)
    s = struct_with(W, fwd, bwd)
    assert j == 1.0, j
    assert s < 0.5, s
    assert s < j
    plain = parse_term(lm, "хочу жить")
    neg = parse_term(lm, "не хочу жить")
    assert neg[3] and not plain[3]
    assert struct_with(W, plain, neg) < 1.0
    print("self-check: identity/jaccard/converse/negation OK", flush=True)


def load_corpus_entries():
    """Parse definitionCorpus entry blocks -> {topic: [ru, ...]}.
    Block-split on `entry \"...\"`, then take first literals of
    prop/rel/structure lines (the RU surfaces)."""
    src = CONTENT.read_text(encoding="utf-8")
    entries = {}
    parts = re.split(r'[,[] entry "', src)
    assert len(parts) > 100, len(parts)
    for part in parts[1:]:
        topic = part.split('"', 1)[0]
        block = part.split("]", 1)[0]
        rus = re.findall(r'(?:prop|rel|structure) "([^"]+)"', block)
        assert rus, topic
        entries[topic] = rus
    return entries


def toks(s):
    return [w.strip("".join(PUNCT)).lower() for w in s.split()]


def overlap(a, b):
    # Containment of the CANDIDATE (b) in the response (a): covered_exact
    # turns render the selected predicate near-verbatim inside a long
    # composed surface, so Jaccard (symmetric) collapses under surface
    # length while containment stays ~1.0. Call as overlap(response, cand).
    sa, sb = set(toks(a)), set(toks(b))
    if not sb:
        return 0.0
    return len(sa & sb) / len(sb)


def main():
    self_check()
    entries = load_corpus_entries()
    print(f"definitionCorpus topics parsed: {len(entries)}", flush=True)
    assert len(entries) == 120, len(entries)
    lemma = build_lemma_map()

    corpus = {}
    for l in open(ROOT / "data/calibration_corpus/corpus.jsonl",
                  encoding="utf-8"):
        r = json.loads(l)
        lab = r.get("labels") or {}
        if lab.get("predicate_relevant") is not None:
            corpus[r["id"]] = r
    rated = {r["id"]: r for r in json.load(
        open(ROOT / "data/calibration_corpus/rated_responses.json",
             encoding="utf-8"))}
    recs = []
    for i, r in corpus.items():
        rr = rated.get(i, {})
        recs.append({"id": i, "input": r["input"], "topic": r["topic"],
                     "response": rr.get("response", ""),
                     "rel": r["labels"]["predicate_relevant"],
                     "acc": r["labels"].get("response_acceptable"),
                     "covered": r["topic"].lower().strip() in entries})
    print(f"labeled records: {len(recs)}", flush=True)

    rows = []
    for r in recs:
        cands = entries.get(r["topic"].lower().strip(), [])
        q = parse_term(lemma, r["input"])
        scored = []
        for ci, c in enumerate(cands):
            p = parse_term(lemma, c)
            scored.append((ci, c, struct_with(W, q, p), jaccard(q, p)))
        # used candidate by response overlap
        best, bestov = None, -1.0
        for ci, c, _s, _j in scored:
            ov = overlap(r["response"], c)
            if ov > bestov:
                best, bestov = ci, ov
        s_rank = sorted(range(len(scored)),
                        key=lambda i: (-scored[i][2], scored[i][0]))
        j_rank = sorted(range(len(scored)),
                        key=lambda i: (-scored[i][3], scored[i][0]))
        rows.append({"id": r["id"], "topic": r["topic"], "rel": r["rel"],
                     "covered": r["covered"], "ncand": len(cands),
                     "used": best, "used_overlap": round(bestov, 3),
                     "s_top": s_rank[0] if s_rank else None,
                     "j_top": j_rank[0] if j_rank else None,
                     "s_hit": bool(s_rank) and s_rank[0] == best,
                     "j_hit": bool(j_rank) and j_rank[0] == best})
    json.dump(rows, open(ROOT / "data/calibration_corpus/structscore_eval.json",
                         "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)

    cov2 = [x for x in rows if x["covered"] and x["rel"] == 2]
    mapped = [x for x in cov2 if x["used_overlap"] >= 0.5]
    unmapped = [x for x in cov2 if x["used_overlap"] < 0.5]
    print(f"\ncovered rel=2 records: {len(cov2)} "
          f"(mapped {len(mapped)}, unmapped {len(unmapped)})", flush=True)
    for x in unmapped:
        print(f'  EXCLUDE {x["id"]} {x["topic"]}: response predicate outside '
              f'candidate set (ov={x["used_overlap"]}, F7-class: rater judges '
              f'construction, trace marks provenance)', flush=True)
    for x in mapped:
        print(f'  {x["id"]} {x["topic"]}: used#{x["used"]} ov={x["used_overlap"]} '
              f's_top={x["s_top"]}{"*" if x["s_hit"] else ""} '
              f'j_top={x["j_top"]}{"*" if x["j_hit"] else ""}',
              flush=True)
    sh = sum(x["s_hit"] for x in mapped)
    jh = sum(x["j_hit"] for x in mapped)
    n = len(mapped)
    b = sum(1 for x in mapped if x["s_hit"] and not x["j_hit"])
    c = sum(1 for x in mapped if x["j_hit"] and not x["s_hit"])
    from math import comb
    mcn = sum(comb(b + c, k) for k in range(max(b, c), b + c + 1)) / 2 ** (b + c) * 2 if (b + c) else 1.0
    print(f"\nstruct top-1: {sh}/{n} = {sh/n if n else 0:.3f}", flush=True)
    print(f"jaccard top-1: {jh}/{n} = {jh/n if n else 0:.3f}", flush=True)
    print(f"delta (struct-jaccard): {(sh-jh)/n if n else 0:+.3f} "
          f"(gate needs >= +0.05)", flush=True)
    print(f"paired discordants: struct-only {b}, jaccard-only {c}; "
          f"McNemar exact two-sided p = {min(mcn, 1.0):.3f}", flush=True)
    print("\nweight sensitivity (delta under hand variants):", flush=True)
    for name, wv in [("default(0.5/0.3/0.15/0.05)", W),
                     ("head-heavy(0.7/0.2/0.05/0.05)",
                      {"swHead": 0.7, "swRel": 0.2, "swMod": 0.05, "swNeg": 0.05}),
                     ("flat-rel-mod(0.34/0.33/0.33/0.0)",
                      {"swHead": 0.34, "swRel": 0.33, "swMod": 0.33, "swNeg": 0.0}),
                     ("uniform(0.25x4)",
                      {"swHead": 0.25, "swRel": 0.25, "swMod": 0.25, "swNeg": 0.25})]:
        ds = dj = 0
        for r in recs:
            if r["id"] not in {x["id"] for x in mapped}:
                continue
            cands = entries[r["topic"].lower().strip()]
            q = parse_term(lemma, r["input"])
            ss = sorted(range(len(cands)),
                        key=lambda i: (-struct_with(wv, q, parse_term(lemma, cands[i])), i))
            js = sorted(range(len(cands)),
                        key=lambda i: (-jaccard(q, parse_term(lemma, cands[i])), i))
            used = next(x["used"] for x in mapped if x["id"] == r["id"])
            if ss[0] == used:
                ds += 1
            if js[0] == used:
                dj += 1
        print(f"  {name}: struct {ds}/{n} jaccard {dj}/{n} "
              f"delta {(ds-dj)/n if n else 0:+.3f}", flush=True)
    disc = [(x["id"], x["rel"], x["s_top"], x["j_top"], x["used"])
            for x in rows if x["covered"] and x["rel"] in (0, 1)]
    print(f"\ncovered rel in {{0,1}} diagnostic (n={len(disc)}):", flush=True)
    for d in disc:
        print(f"  {d[0]} rel={d[1]}: s_top={d[2]} j_top={d[3]} used={d[4]}",
              flush=True)


if __name__ == "__main__":
    sys.exit(main())
