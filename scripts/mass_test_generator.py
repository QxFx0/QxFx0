#!/usr/bin/env python3
"""Mass test scenario generator — 20 scenarios, 30 turns each.

From QxFx4: 6 thematic pools, 20% theme-switching, 30% noise.
"""

import json
import random
import sys
from pathlib import Path

OUTDIR = Path(__file__).resolve().parent.parent / "data" / "scenarios"

THEME_POOLS = {
    "ontology": [
        "Что такое бытие?", "Чем отличается сущее от должного?", "Существует ли небытие?",
        "Что значит 'быть'?", "Является ли время формой бытия?", "Как соотносятся бытие и становление?",
    ],
    "freedom": [
        "Что такое свобода?", "Возможно ли свободное решение?", "Где граница свободы и произвола?",
        "Свобода — это возможность или ответственность?", "Может ли несвободный осознать несвободу?",
        "Совместимы ли свобода и причинность?",
    ],
    "consciousness": [
        "Что такое сознание?", "Может ли машина обладать сознанием?", "Где граница сознательного и бессознательного?",
        "Является ли самосознание необходимым?", "Как возникает квалиа?", "Сознание — субстанция или процесс?",
    ],
    "ethics": [
        "Что такое добро?", "Существуют ли абсолютные моральные нормы?", "Может ли зло быть рациональным?",
        "В чём различие утилитаризма и деонтологии?", "Что такое справедливость?", "Обязана ли личность обществу?",
    ],
    "knowledge": [
        "Что такое истина?", "Возможно ли объективное знание?", "Чем отличается вера от знания?",
        "Что такое эпистемическая честность?", "Существуют ли синтетические априорные суждения?",
        "Как отличить знание от мнения?",
    ],
    "language": [
        "Как язык формирует мысль?", "Что такое значение слова?", "Можно ли мыслить без языка?",
        "В чём суть проблемы私人ного языка?", "Как соотносятся знак и означаемое?",
        "Возможно ли невыразимое?",
    ],
}

NOISE_TURNS = [
    "абвгд", "12345", "...", "???", "а", "ну", "хм", "ок", "ладно", "так",
    "не знаю", "может быть", "да нет", "ну да", "whatever", "привет",
]

def generate_scenario(sid, primary, switching_pct=0.20, noise_pct=0.30):
    turns = []
    for i in range(30):
        r = random.random()
        if r < noise_pct:
            turns.append(random.choice(NOISE_TURNS))
        elif r < noise_pct + switching_pct:
            alt = random.choice([t for t in THEME_POOLS if t != primary])
            turns.append(random.choice(THEME_POOLS[alt]))
        else:
            turns.append(random.choice(THEME_POOLS[primary]))
    return {"scenario_id": sid, "primary_theme": primary, "turns": turns}

def main():
    OUTDIR.mkdir(parents=True, exist_ok=True)
    random.seed(42)
    themes = list(THEME_POOLS.keys())
    for idx in range(20):
        primary = themes[idx % len(themes)]
        scenario = generate_scenario(f"s{idx:03d}", primary)
        out = OUTDIR / f"scenario_{idx:03d}.json"
        out.write_text(json.dumps(scenario, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"  wrote {out} ({len(scenario['turns'])} turns, theme={primary})")
    print(f"Generated 20 scenarios in {OUTDIR}")

if __name__ == "__main__":
    main()
