# Extended Lexicon for English Support

## Current Status

The English concrete syntax (`QxFx0SyntaxEng.gf`) currently works with the core lexicon of 162 entries (ending at `yakor_N`). This is sufficient for basic dual-mode operation.

## Extended Lexicon Entries

The bilingual TSV (`lexicon_bilingual.tsv`) contains 383 unique fun_ids, of which 227 are NOT in the current abstract lexicon. These include:

### Nouns (~180 entries)
- absolyut_N, analiz_N, antinomiya_N, apriori_N, arhitektura_N, atribut_N, autentichnost_N
- beskonechnost_N, bezuslovnost_N, celostnost_N, cennost_N, chastica_N, chastnost_N
- chuvstvo_N, cikl_N, dedukciya_N, dialektika_N, differenciya_N, dinamika_N
- disciplina_N, doktrina_N, dominanta_N, dostizhenie_N, edinstvo_N, effek_N
- ekran_N, ekzemplar_N, ekzistenciya_N, element_N, emergenciya_N, emociya_N
- empiriya_N, energiya_N, entropiya_N, epistemologiya_N, epoha_N, erudiciya_N
- esencia_N, estestvo_N, etika_N, forma_N, funkciya_N, glubina_N
- gran_N, gravitaciya_N, ideologiya_N, illuziya_N, immanenciya_N, impuls_N
- individ_N, informaciya_N, instinkt_N, intellekt_N, intenciya_N, intuiciya_N
- inversiya_N, iskusstvo_N, issledovanie_N, istoriya_N, kachestvo_N, kategoriya_N
- klassifikaciya_N, kod_N, kolichestvo_N, kollektiv_N, kommunikaciya_N
- kompleks_N, koncepciya_N, koncept_N, konkretnost_N, konstrukt_N, kontekst_N
- kontinuum_N, kontrakt_N, koordinata_N, korelaciya_N, kosmos_N, krasota_N
- kreativnost_N, krizis_N, kulminaciya_N, kultura_N, lokalnost_N, masshtab_N
- metafizika_N, metoda_N, metodologiya_N, model_N, moment_N, morale_N
- nablyudenie_N, napravlenie_N, naskok_N, nastroenie_N, nauka_N, neposredstvennost_N
- nevezhestvo_N, obekt_N, oblast_N, obraz_N, obrazovanie_N, obshestvo_N
- obuslovlennost_N, odinakovost_N, opasnost_N, opredelennost_N, optimism_N
- organism_N, orientaciya_N, osnova_N, osoznanie_N, otkrytie_N, otnoshenie_N
- otsutstvie_N, paradigma_N, parametr_N, patern_N, perspektiva_N, pitanie_N
- pluralizm_N, pole_N, polnost_N, porjadok_N, potencial_N, poznanie_N
- praktika_N, predel_N, predstavlenie_N, preemstvennost_N, princip_N
- prioritet_N, problema_N, process_N, prostranstvo_N, psihika_N, puls_N
- rabota_N, realnost_N, refleksiya_N, rezonans_N, ritm_N, rol_N
- scena_N, silnyj_A, sistema_N, slojnost_N, slovo_N, sobytie_N
- soderzhanie_N, sostoyanie_N, sovet_N, spektr_N, spiral_N, sreda_N
- ssylka_N, stadiya_N, standart_N, struktura_N, subekt_N, sud_N
- suschestvo_N, suschestvovanie_N, taktika_N, tekst_N, temp_N, tendenciya_N
- teoriya_N, tip_N, tochka_N, ton_N, tradiciya_N, transformaciya_N
- trudnost_N, uchebnik_N, universalnost_N, uporjadochennost_N, usilennost_N
- ustanovlenie_N, variant_N, vkluchenie_N, vlast_N, vneshnost_N
- vnutrennost_N, vosprinimanie_N, vospriyatie_N, vozdejstvie_N, vozniknovenie_N
- vremennost_N, vselennaya_N, vyzov_N, vzaimodejstvie_N, vzaimosvyaz_N
- yadro_N, yavlenie_N, zhelaniye_N, znaniye_N, zrelnost_N

### Adjectives (6 entries)
- bolshoj_A, novyj_A, silnyj_A, slabyj_A, staryj_A, vazhnyj_A

### Adverbs (5 entries)
- bystro_Adv, medlenno_Adv, nikogda_Adv, sejchas_Adv, vsegda_Adv

### Verbs (15 entries)
- chuvstvovat_V, dokazyvat_V, ispolzovat_V, issledovat_V, izmenyat_V
- nabljudat_V, obshchatysya_V, poznavat_V, razvivat_V, soznavat_V
- vospriyamat_V, vydelyat_V, vyraghat_V

### Conjunctions (3 entries)
- i_Conj, ili_Conj, no_Conj

### Prepositions (3 entries)
- na_Prep, o_Prep, v_Prep

## Implementation Steps

To add the extended lexicon:

1. **Update `QxFx0Lexicon.gf` (abstract)**
   - Add all 227 missing fun declarations
   - Format: `fun absolyut_N : Lexeme ;` etc.

2. **Update `QxFx0LexiconRus.gf` (concrete)**
   - Add Russian case forms for nouns (nom, gen, prep, acc, ins)
   - Add verb conjugations (v1sg, v2sg, v3sg, v1pl, v2pl, v3pl)
   - Add adjective forms
   - Data available in `lexicon_bilingual.tsv`

3. **Update `QxFx0LexiconEng.gf` (concrete)**
   - Add English translations
   - Format: `lin absolyut_N = { s = "absolute" } ;`
   - Data available in `lexicon_bilingual.tsv`

4. **Update morphology system**
   - Ensure `paradigms.json` and `exceptions.json` cover new entries
   - Or use the TSV data directly via `export_lexicon.py`

5. **Recompile PGF**
   - Run GF compilation with updated lexicons

6. **Test**
   - Verify linearization works for all new entries
   - Run test suite

## Alternative Approach

Modify `export_lexicon.py` to:
1. Read the bilingual TSV
2. Generate all three GF files (abstract, Rus concrete, Eng concrete) from the TSV
3. This would be more maintainable and keep the three files in sync

## Priority

This is a **medium-priority enhancement**. The current 162-entry lexicon is sufficient for:
- Basic dual-mode operation (RU/EN)
- Core philosophical dialogue
- Testing and development

The extended lexicon would enable:
- More nuanced English expressions
- Richer vocabulary for philosophical concepts
- Better coverage of the Russian lexicon

## Notes

- The bilingual TSV contains full Russian morphology data
- English entries only have the base form (lemma)
- Some entries (like conjunctions, prepositions) may need special handling in the concrete syntax
