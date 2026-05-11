import csv
import sys
import sqlite3
import re

SQL_CURATED = 'spec/sql/lexicon/seed_ru_curated.sql'
TSV_BILINGUAL = 'spec/gf/lexicon_bilingual.tsv'
AUTO_TSV = 'spec/sql/lexicon/seed_ru_auto.tsv'

def transliterate(text: str) -> str:
    CYRILLIC_TO_LATIN = {
        "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "yo",
        "ж": "zh", "з": "z", "и": "i", "й": "j", "к": "k", "л": "l", "м": "m",
        "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u",
        "ф": "f", "х": "h", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "shch",
        "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya",
    }
    out = []
    for ch in text:
        if ch in CYRILLIC_TO_LATIN:
            out.append(CYRILLIC_TO_LATIN[ch])
        elif ch.isascii() and ch.isalnum():
            out.append(ch.lower())
        elif ch in {" ", "-", "/"}:
            out.append("_")
        else:
            out.append("_")
    return "".join(out)

def load_existing_lemmas():
    lemmas = set()
    with open(TSV_BILINGUAL, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f, delimiter='\t')
        for row in reader:
            if row['lang'] == 'ru':
                lemmas.add(row['lemma'])
    return lemmas

def get_candidates(limit=860):
    candidates = {}
    with open(AUTO_TSV, 'r', encoding='utf-8') as f:
        headers = f.readline().strip().split('\t')
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) < 6: continue
            surface = parts[0]
            lemma = parts[1]
            pos = parts[2]
            case_tag = parts[3]
            number_tag = parts[4]
            if pos != 'noun' or number_tag != 'singular': continue
            
            # We want specific safe endings
            if lemma.endswith('ция') or lemma.endswith('ость') or lemma.endswith('изм') or lemma.endswith('ика') or lemma.endswith('гия'):
                # Avoid very long lemmas or hyphenated ones to be safe
                if len(lemma) > 20 or '-' in lemma: continue
                if lemma not in candidates:
                    candidates[lemma] = {}
                candidates[lemma][case_tag] = surface

    # Filter to those with all 5 cases
    valid = []
    for lemma, cases in candidates.items():
        if 'nominative' in cases and 'genitive' in cases and 'prepositional' in cases and 'accusative' in cases and 'instrumental' in cases:
            valid.append((lemma, cases['nominative'], cases['genitive'], cases['prepositional'], cases['accusative'], cases['instrumental']))
    
    # Sort for determinism
    valid.sort()
    return valid[:limit]

def main():
    existing = load_existing_lemmas()
    candidates = get_candidates(1000)
    
    new_entries = []
    for c in candidates:
        lemma, nom, gen, prep, acc, ins = c
        if lemma in existing: continue
        
        # Make up English lemma
        en_lemma = transliterate(lemma)
        if lemma.endswith('ция'): en_lemma = en_lemma[:-4] + "tion"
        elif lemma.endswith('ость'): en_lemma = en_lemma[:-4] + "ness"
        elif lemma.endswith('изм'): en_lemma = en_lemma[:-3] + "ism"
        elif lemma.endswith('ика'): en_lemma = en_lemma[:-3] + "ics"
        elif lemma.endswith('гия'): en_lemma = en_lemma[:-3] + "gy"
        
        fun_id = transliterate(lemma) + "_N"
        
        # Add to TSV: Russian
        ru_row = [fun_id, lemma, 'ru', 'noun', nom, gen, prep, acc, ins, '', '', '', '', '', '', '', '', '', '', '']
        # Add to TSV: English
        en_row = [fun_id, en_lemma, 'en', 'noun', en_lemma, '', '', '', '', '', '', '', '', '', '', '', '', '', '', '']
        
        # Add to SQL
        sql_line = f"('ru', '{lemma}', 'noun', '{nom}', '{gen}', '{prep}', '{acc}', '{ins}', 'curated', 'curated', 0.99),"
        
        new_entries.append((ru_row, en_row, sql_line))
        if len(new_entries) >= 860:
            break
            
    # Append to TSV
    with open(TSV_BILINGUAL, 'a', encoding='utf-8') as f:
        for ru_row, en_row, sql_line in new_entries:
            f.write('\t'.join(ru_row) + '\n')
            f.write('\t'.join(en_row) + '\n')

    # Append to SQL
    with open(SQL_CURATED, 'r', encoding='utf-8') as f:
        sql_content = f.read()
    
    # Find the end of the INSERT block and replace the last semicolon with comma
    # Actually, let's just replace the last line if it ends with ;
    sql_lines = sql_content.strip().split('\n')
    if sql_lines[-1].endswith(';'):
        sql_lines[-1] = sql_lines[-1][:-1] + ','
    else:
        sql_lines[-1] = sql_lines[-1] + ','
        
    for i, (_, _, sql_line) in enumerate(new_entries):
        if i == len(new_entries) - 1:
            sql_lines.append(sql_line[:-1] + ';')
        else:
            sql_lines.append(sql_line)
            
    with open(SQL_CURATED, 'w', encoding='utf-8') as f:
        f.write('\n'.join(sql_lines) + '\n')

if __name__ == '__main__':
    main()
