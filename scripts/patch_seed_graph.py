#!/usr/bin/env python3
"""Patch AtomStore.hs using seed_data.txt to reach 500+ edges."""
import sys

R=[("RelPresupposes","CaseAccusative","предполагает","presupposes"),("RelMeans","CaseAccusative","означает","means"),("RelRequires","CaseGenitive","требует","requires"),("RelIncludes","CaseAccusative","включает","includes"),("RelIsA","CaseNominative","есть","is"),("RelEvokes","CaseAccusative","вызывает","evokes"),("RelDetermines","CaseAccusative","определяет","determines"),("RelReliesOn","CaseAccusative","опирается на","relies on"),("RelGives","CaseAccusative","придаёт","gives"),("RelReveals","CaseAccusative","обнаруживает","reveals"),("RelStructures","CaseAccusative","структурирует","structures"),("RelUnifies","CaseAccusative","объединяет","unifies"),("RelDenotes","CaseAccusative","обозначает","denotes"),("RelDirectedAt","CaseAccusative","направлена на","is directed at"),("RelSignals","CasePrepositional","сигнализирует о","signals"),("RelContrastsWith","CaseInstrumental","контрастирует с","contrasts with"),("RelBuiltThrough","CaseAccusative","строится через","is built through"),("RelPreserves","CaseAccusative","сохраняет","preserves"),("RelOrientsToward","CaseAccusative","ориентирует на","orients toward"),("RelPrescribes","CaseAccusative","предписывает","prescribes"),("RelNotReducibleTo","CaseDative","не сводится к","is not reducible to"),("RelNecessaryFor","CaseGenitive","необходим для","is necessary for"),("RelTransforms","CaseAccusative","преобразует","transforms"),("RelTransformsInto","CaseAccusative","превращается в","transforms into"),("RelSupports","CaseAccusative","поддерживает","supports")]

topics=[]; concepts={}; cross=[]; cc=[]
for line in open("scripts/seed_data.txt"):
    line=line.strip()
    if not line or line.startswith("#"): continue
    p=line.split("|")
    if p[0]=="T": topics.append(p[1])
    elif p[0]=="C":
        t=p[1]
        if t not in concepts: concepts[t]=[]
        concepts[t].append((p[2],p[3],p[4]))
    elif p[0]=="X": cross.append((p[1],p[2],int(p[3])))
    elif p[0]=="P": cc.append((p[1],p[2],int(p[3])))

DISP={}
for t in concepts:
    for a,d,h in concepts[t]: DISP[a]=d

A=["  -- NEW TOPICS"]
for t in topics: A.append(f'  , mkTopic "{t}"')
for t in concepts:
    A.append(f"  -- NEW CONCEPTS: {t}")
    for a,d,h in concepts[t]: A.append(f'  , mkConcept "{a}" "{d}" "{h}"')

E=[]; idx=0
for t in concepts:
    E.append(f"  -- TOPIC EDGES: {t}")
    for i,(a,d,h) in enumerate(concepts[t]):
        rt,cs,rv,ev=R[(idx+i)%len(R)]; idx+=1
        ru=f"{t} {rv} {d}"; en=f"{t} {ev} {d}"
        E.append(f'  , rel "{t}" "{a}" {rt} {cs} "{d}"')
        E.append(f'      "{ru}" "{en}"')
E.append("  -- CROSS-TOPIC EDGES")
for f,to,ri in cross:
    rt,cs,rv,ev=R[ri%len(R)]
    ru=f"{f} {rv} {to}"; en=f"{f} {ev} {to}"
    wv=rv if rt in ("RelContrastsWith","RelRelatedTo","RelDirectedAt") else None
    E.append(f'  , rel "{f}" "{to}" {rt} {cs} "{to}"')
    E.append(f'      "{ru}" "{en}"')
    if wv: E.append(f'      `withVerb` "{wv}"')
E.append("  -- REVERSE MESH EDGES")
idx=0
for t in concepts:
    for a,d,h in concepts[t]:
        rt,cs,rv,ev=R[(idx+5)%len(R)]; idx+=1
        ru=f"{d} {rv} {t}"; en=f"{d} {ev} {t}"
        E.append(f'  , rel "{a}" "{t}" {rt} {cs} "{t}"')
        E.append(f'      "{ru}" "{en}"')
E.append("  -- CONCEPT-CONCEPT EDGES")
for f,to,ri in cc:
    rt,cs,rv,ev=R[ri%len(R)]
    fd=DISP.get(f,f); td=DISP.get(to,to)
    ru=f"{fd} {rv} {td}"; en=f"{fd} {ev} {td}"
    E.append(f'  , rel "{f}" "{to}" {rt} {cs} "{td}"')
    E.append(f'      "{ru}" "{en}"')

na=sum(len(v) for v in concepts.values())+len(topics)
ne=sum(1 for e in E if ", rel " in e)
print(f"New atoms: {na}",file=sys.stderr)
print(f"New edges: {ne}",file=sys.stderr)
print(f"Total edges: 117+{ne}={117+ne}",file=sys.stderr)

with open("src/QxFx0/Semantic/Content/AtomStore.hs") as f: src=f.read()
atoms_str="\n".join(A)
src=src.replace(
    '  , mkConcept "акт_отказа_или_присутствия" "актом отказа или знаком присутствия" "актом"\n  ]',
    '  , mkConcept "акт_отказа_или_присутствия" "актом отказа или знаком присутствия" "актом"\n'+atoms_str+'\n  ]',1)
edges_str="\n".join(E)
src=src.replace(
    '      `withVerb` "направлена на"\n  ]',
    '      `withVerb` "направлена на"\n'+edges_str+'\n  ]',1)
with open("src/QxFx0/Semantic/Content/AtomStore.hs","w") as f: f.write(src)
print("Patched AtomStore.hs",file=sys.stderr)
