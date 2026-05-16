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

def load_existing_data():
    lemmas = set()
    surfaces = set()
    transliterations = set()
    
    with open(TSV_BILINGUAL, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f, delimiter='\t')
        for row in reader:
            if row.get('lang') == 'ru':
                lemma = row.get('lemma','').strip().lower()
                lemmas.add(lemma)
                transliterations.add(transliterate(lemma))
                for k in ['nominative', 'genitive', 'prepositional', 'accusative', 'instrumental']:
                    if row.get(k): surfaces.add(row[k].strip().lower())
                    
    with open(SQL_CURATED, 'r', encoding='utf-8') as f:
        for line in f:
            match = re.search(r"\('ru',\s*'([^']+)'", line)
            if match:
                lemma = match.group(1).lower().strip()
                lemmas.add(lemma)
                transliterations.add(transliterate(lemma))
    return lemmas, surfaces, transliterations

def get_candidates():
    candidates = {}
    with open(AUTO_TSV, 'r', encoding='utf-8') as f:
        headers = f.readline().strip().split('\t')
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) < 6: continue
            surface = parts[0].strip().lower()
            lemma = parts[1].strip().lower()
            pos = parts[2]
            case_tag = parts[3]
            number_tag = parts[4]
            tier = parts[5] if len(parts) > 5 else "auto-coverage"
            
            if pos != 'noun' or number_tag != 'singular': continue
            if tier not in ('auto-verified', 'auto-coverage'): continue
            if len(lemma) < 4 or len(lemma) > 15 or '-' in lemma: continue
            if not re.match(r'^[а-яё]+$', lemma): continue
            
            if lemma not in candidates:
                candidates[lemma] = {}
            candidates[lemma][case_tag] = surface

    valid = []
    for lemma, cases in candidates.items():
        if 'nominative' in cases and 'genitive' in cases and 'prepositional' in cases and 'accusative' in cases and 'instrumental' in cases:
            valid.append((lemma, cases['nominative'], cases['genitive'], cases['prepositional'], cases['accusative'], cases['instrumental']))
    
    valid.sort()
    return valid

def main():
    target_add = int(sys.argv[1]) if len(sys.argv) > 1 else 30
    existing_lemmas, existing_surfaces, used_transliterations = load_existing_data()
    candidates = get_candidates()
    
    new_entries = []
    for c in candidates:
        lemma, nom, gen, prep, acc, ins = c
        if lemma in existing_lemmas: continue
        
        c_surfaces = {nom, gen, prep, acc, ins}
        if c_surfaces.intersection(existing_surfaces): continue
        
        t = transliterate(lemma)
        if t in used_transliterations: continue
        
        en_lemma = t
        fun_id = t + "_N"
        
        ru_row = [fun_id, lemma, 'ru', 'noun', nom, gen, prep, acc, ins, '', '', '', '', '', '', '', '', '', '', '']
        en_row = [fun_id, en_lemma, 'en', 'noun', en_lemma, '', '', '', '', '', '', '', '', '', '', '', '', '', '', '']
        sql_line = f"('ru', '{lemma}', 'noun', '{nom}', '{gen}', '{prep}', '{acc}', '{ins}', 'curated', 'curated', 0.99)"
        
        new_entries.append((ru_row, en_row, sql_line))
        existing_lemmas.add(lemma)
        existing_surfaces.update(c_surfaces)
        used_transliterations.add(t)
        
        if len(new_entries) >= target_add:
            break

    print(f'Adding {len(new_entries)} lemmas.')
    if not new_entries: return
            
    with open(TSV_BILINGUAL, 'a', encoding='utf-8') as f:
        for ru_row, en_row, sql_line in new_entries:
            f.write('\t'.join(ru_row) + '\n')
            f.write('\t'.join(en_row) + '\n')

    with open(SQL_CURATED, 'r', encoding='utf-8') as f:
        sql_content = f.read()
    
    sql_lines = sql_content.strip().split('\n')
    if sql_lines[-1].endswith(';'):
        sql_lines[-1] = sql_lines[-1][:-1] + ','
    else:
        sql_lines[-1] = sql_lines[-1] + ','
        
    for i, (_, _, sql_line) in enumerate(new_entries):
        if i == len(new_entries) - 1:
            sql_lines.append(sql_line + ';')
        else:
            sql_lines.append(sql_line + ',')
            
    with open(SQL_CURATED, 'w', encoding='utf-8') as f:
        f.write('\n'.join(sql_lines) + '\n')

if __name__ == '__main__':
    main()
