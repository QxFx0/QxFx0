#!/usr/bin/env python3
"""Unit tests for import_ru_opencorpora.py filter and scoring functions."""

import sys
import unittest
from pathlib import Path

# Ensure we can import the module
SCRIPT_DIR = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPT_DIR))

from import_ru_opencorpora import (  # noqa: E402
    DOMAIN_SEED,
    PATRONYMIC_ENDINGS,
    P1_ADJ_MAX_LEN,
    P1_MAX_HYPHENS,
    P1_NOUN_MAX_LEN,
    P2_ADJ_MAX_LEN,
    P2_MAX_HYPHENS,
    P2_NOUN_MAX_LEN,
    PROPER_ALLOWLIST,
    TECHNICAL_PREFIXES,
    TECHNICAL_SUFFIXES,
    LemmaGroup,
    ParsedForm,
    compute_p1_score,
    compute_p2_score,
    has_excessive_hyphens,
    is_auto_eligible,
    is_domain_seed,
    is_mostly_proper_noun,
    is_patronymic_like,
    is_p1_eligible,
    is_p1_rejected,
    is_p2_eligible,
    is_p2_rejected,
    is_proper_allowlisted,
    is_technical_compound,
    score_paradigm_completeness,
    select_p1_p2_groups,
)


class TestIsPatronymicLike(unittest.TestCase):
    """Tests for patronymic detection."""

    def test_male_patronymic(self):
        self.assertTrue(is_patronymic_like("иванович"))
        self.assertTrue(is_patronymic_like("петрович"))
        self.assertTrue(is_patronymic_like("сергеевич"))

    def test_female_patronymic(self):
        self.assertTrue(is_patronymic_like("ивановна"))
        self.assertTrue(is_patronymic_like("петровна"))
        self.assertTrue(is_patronymic_like("сергеевна"))

    def test_short_patronymic_ending(self):
        self.assertTrue(is_patronymic_like("ильич"))
        self.assertTrue(is_patronymic_like("даниич"))

    def test_common_noun_not_patronymic(self):
        self.assertFalse(is_patronymic_like("человек"))
        self.assertFalse(is_patronymic_like("свобода"))
        self.assertFalse(is_patronymic_like("дом"))
        self.assertFalse(is_patronymic_like("большой"))

    def test_short_lemma_not_patronymic(self):
        # Even if it ends with "ич", too short to be patronymic
        self.assertFalse(is_patronymic_like("ич"))


class TestIsTechnicalCompound(unittest.TestCase):
    """Tests for technical compound adjective detection."""

    def test_hyphenated_technical(self):
        self.assertTrue(is_technical_compound("электро-механический"))
        self.assertTrue(is_technical_compound("термо-изоляционный"))

    def test_multiple_hyphens(self):
        self.assertTrue(is_technical_compound("а-б-в"))

    def test_long_technical_prefix(self):
        self.assertTrue(is_technical_compound("электромагнитно-акустический"))

    def test_common_noun_not_technical(self):
        self.assertFalse(is_technical_compound("человек"))
        self.assertFalse(is_technical_compound("свобода"))
        self.assertFalse(is_technical_compound("дом"))

    def test_short_technical_word_not_technical(self):
        # "авто" is a technical prefix but short word shouldn't trigger
        self.assertFalse(is_technical_compound("авто"))


class TestHasExcessiveHyphens(unittest.TestCase):
    """Tests for hyphen threshold detection."""

    def test_p1_single_hyphen_ok(self):
        self.assertFalse(has_excessive_hyphens("кто-то", P1_MAX_HYPHENS))

    def test_p1_two_hyphens_rejected(self):
        self.assertTrue(has_excessive_hyphens("а-б-в", P1_MAX_HYPHENS))

    def test_p2_two_hyphens_ok(self):
        self.assertFalse(has_excessive_hyphens("а-б-в", P2_MAX_HYPHENS))

    def test_p2_three_hyphens_rejected(self):
        self.assertTrue(has_excessive_hyphens("а-б-в-г", P2_MAX_HYPHENS))

    def test_no_hyphens_ok(self):
        self.assertFalse(has_excessive_hyphens("человек", P1_MAX_HYPHENS))


class TestIsDomainSeed(unittest.TestCase):
    """Tests for domain seed membership."""

    def test_common_words_in_seed(self):
        self.assertTrue(is_domain_seed("человек"))
        self.assertTrue(is_domain_seed("жизнь"))
        self.assertTrue(is_domain_seed("свобода"))
        self.assertTrue(is_domain_seed("дом"))

    def test_rare_words_not_in_seed(self):
        self.assertFalse(is_domain_seed("аавович"))
        self.assertFalse(is_domain_seed("экзистенциализм"))


class TestIsProperAllowlisted(unittest.TestCase):
    """Tests for proper noun allowlist."""

    def test_allowlisted_words(self):
        self.assertTrue(is_proper_allowlisted("бог"))
        self.assertTrue(is_proper_allowlisted("мир"))
        self.assertTrue(is_proper_allowlisted("воля"))

    def test_non_allowlisted_words(self):
        self.assertFalse(is_proper_allowlisted("человек"))
        self.assertFalse(is_proper_allowlisted("свобода"))


class TestIsMostlyProperNoun(unittest.TestCase):
    """Tests for mostly-proper-noun detection."""

    def test_mostly_proper(self):
        forms = [
            ParsedForm("иванов", "иванов", "noun", "genitive", "plural", "masc", "inan", {"Name", "Surn"}),
            ParsedForm("иванова", "иванов", "noun", "nominative", "singular", "femn", "anim", {"Name", "Surn"}),
            ParsedForm("иванову", "иванов", "noun", "dative", "singular", "masc", "anim", {"Name", "Surn"}),
        ]
        group = LemmaGroup("иванов", "noun", forms)
        self.assertTrue(is_mostly_proper_noun(group))

    def test_not_mostly_proper(self):
        forms = [
            ParsedForm("свобода", "свобода", "noun", "nominative", "singular", "femn", "anim", set()),
            ParsedForm("свободы", "свобода", "noun", "genitive", "singular", "femn", "anim", set()),
        ]
        group = LemmaGroup("свобода", "noun", forms)
        self.assertFalse(is_mostly_proper_noun(group))

    def test_mixed_proper_common(self):
        # "любовь" is both a name and common noun - 50% proper should NOT trigger
        forms = [
            ParsedForm("любовь", "любовь", "noun", "nominative", "singular", "femn", "anim", set()),
            ParsedForm("любви", "любовь", "noun", "genitive", "singular", "femn", "anim", {"Name"}),
        ]
        group = LemmaGroup("любовь", "noun", forms)
        self.assertFalse(is_mostly_proper_noun(group))


class TestIsAutoEligible(unittest.TestCase):
    """Tests for base auto-tier eligibility."""

    def test_noun_eligible(self):
        forms = [ParsedForm("дом", "дом", "noun", "nominative", "singular", "masc", "inan", set())]
        group = LemmaGroup("дом", "noun", forms)
        self.assertTrue(is_auto_eligible(group))

    def test_adjective_eligible(self):
        forms = [ParsedForm("большой", "большой", "adjective", "nominative", "singular", "masc", "inan", set())]
        group = LemmaGroup("большой", "adjective", forms)
        self.assertTrue(is_auto_eligible(group))

    def test_verb_not_eligible(self):
        forms = [ParsedForm("делать", "делать", "verb", "infinitive", None, None, None, set())]
        group = LemmaGroup("делать", "verb", forms)
        self.assertFalse(is_auto_eligible(group))

    def test_abbreviation_not_eligible(self):
        forms = [ParsedForm("ссср", "ссср", "noun", "nominative", "singular", "masc", "inan", {"Abbr"})]
        group = LemmaGroup("ссср", "noun", forms)
        self.assertFalse(is_auto_eligible(group))

    def test_short_lemma_not_eligible(self):
        forms = [ParsedForm("я", "я", "noun", "nominative", "singular", None, None, set())]
        group = LemmaGroup("я", "noun", forms)
        self.assertFalse(is_auto_eligible(group))


class TestScoreParadigmCompleteness(unittest.TestCase):
    """Tests for paradigm completeness scoring."""

    def test_noun_complete_paradigm(self):
        forms = [
            ParsedForm("дом", "дом", "noun", "nominative", "singular", "masc", "inan", set()),
            ParsedForm("дома", "дом", "noun", "genitive", "singular", "masc", "inan", set()),
            ParsedForm("дому", "дом", "noun", "dative", "singular", "masc", "inan", set()),
            ParsedForm("доме", "дом", "noun", "prepositional", "singular", "masc", "inan", set()),
            ParsedForm("домом", "дом", "noun", "instrumental", "singular", "masc", "inan", set()),
            ParsedForm("дома", "дом", "noun", "nominative", "plural", "masc", "inan", set()),
            ParsedForm("домов", "дом", "noun", "genitive", "plural", "masc", "inan", set()),
            ParsedForm("домам", "дом", "noun", "dative", "plural", "masc", "inan", set()),
            ParsedForm("домах", "дом", "noun", "prepositional", "plural", "masc", "inan", set()),
            ParsedForm("домами", "дом", "noun", "instrumental", "plural", "masc", "inan", set()),
        ]
        group = LemmaGroup("дом", "noun", forms)
        score, ratio = score_paradigm_completeness(group)
        self.assertGreaterEqual(ratio, 0.8)

    def test_noun_partial_paradigm(self):
        forms = [
            ParsedForm("дом", "дом", "noun", "nominative", "singular", "masc", "inan", set()),
            ParsedForm("дома", "дом", "noun", "genitive", "singular", "masc", "inan", set()),
        ]
        group = LemmaGroup("дом", "noun", forms)
        score, ratio = score_paradigm_completeness(group)
        self.assertLess(ratio, 0.5)


class TestP1Rejection(unittest.TestCase):
    """Tests for P1 hard rejection filters."""

    def test_patronymic_rejected_from_p1(self):
        forms = [ParsedForm("иванович", "иванович", "noun", "nominative", "singular", "masc", "anim", {"Patr"})]
        group = LemmaGroup("иванович", "noun", forms)
        self.assertTrue(is_p1_rejected(group))

    def test_technical_compound_rejected_from_p1(self):
        forms = [ParsedForm("электро-механический", "электро-механический", "adjective", "nominative", "singular", "masc", "inan", set())]
        group = LemmaGroup("электро-механический", "adjective", forms)
        self.assertTrue(is_p1_rejected(group))

    def test_common_noun_not_rejected_from_p1(self):
        forms = [
            ParsedForm("дом", "дом", "noun", "nominative", "singular", "masc", "inan", set()),
            ParsedForm("дома", "дом", "noun", "genitive", "singular", "masc", "inan", set()),
        ]
        group = LemmaGroup("дом", "noun", forms)
        self.assertFalse(is_p1_rejected(group))

    def test_allowlisted_proper_not_rejected_from_p1(self):
        forms = [
            ParsedForm("бог", "бог", "noun", "nominative", "singular", "masc", "anim", set()),
            ParsedForm("бога", "бог", "noun", "genitive", "singular", "masc", "anim", set()),
        ]
        group = LemmaGroup("бог", "noun", forms)
        self.assertFalse(is_p1_rejected(group))


class TestP2Rejection(unittest.TestCase):
    """Tests for P2 hard rejection filters."""

    def test_patronymic_rejected_from_p2(self):
        forms = [ParsedForm("иванович", "иванович", "noun", "nominative", "singular", "masc", "anim", {"Patr"})]
        group = LemmaGroup("иванович", "noun", forms)
        self.assertTrue(is_p2_rejected(group))

    def test_allowlisted_patronymic_not_rejected_from_p2(self):
        # This tests the allowlist logic for proper nouns that are also common words
        forms = [
            ParsedForm("мир", "мир", "noun", "nominative", "singular", "masc", "inan", set()),
            ParsedForm("мира", "мир", "noun", "genitive", "singular", "masc", "inan", set()),
        ]
        group = LemmaGroup("мир", "noun", forms)
        self.assertFalse(is_p2_rejected(group))

    def test_common_noun_not_rejected_from_p2(self):
        forms = [
            ParsedForm("человек", "человек", "noun", "nominative", "singular", "masc", "anim", set()),
            ParsedForm("человека", "человек", "noun", "genitive", "singular", "masc", "anim", set()),
        ]
        group = LemmaGroup("человек", "noun", forms)
        self.assertFalse(is_p2_rejected(group))


class TestP1Eligibility(unittest.TestCase):
    """Tests for P1 tier eligibility."""

    def test_common_noun_eligible_for_p1(self):
        forms = [
            ParsedForm("человек", "человек", "noun", "nominative", "singular", "masc", "anim", set()),
            ParsedForm("человека", "человек", "noun", "genitive", "singular", "masc", "anim", set()),
            ParsedForm("человеку", "человек", "noun", "dative", "singular", "masc", "anim", set()),
            ParsedForm("человеком", "человек", "noun", "instrumental", "singular", "masc", "anim", set()),
            ParsedForm("человеке", "человек", "noun", "prepositional", "singular", "masc", "anim", set()),
            ParsedForm("люди", "человек", "noun", "nominative", "plural", "masc", "anim", set()),
            ParsedForm("людей", "человек", "noun", "genitive", "plural", "masc", "anim", set()),
        ]
        group = LemmaGroup("человек", "noun", forms)
        self.assertTrue(is_p1_eligible(group))

    def test_patronymic_not_eligible_for_p1(self):
        forms = [ParsedForm("иванович", "иванович", "noun", "nominative", "singular", "masc", "anim", {"Patr"})]
        group = LemmaGroup("иванович", "noun", forms)
        self.assertFalse(is_p1_eligible(group))


class TestP2Eligibility(unittest.TestCase):
    """Tests for P2 tier eligibility."""

    def test_partial_noun_eligible_for_p2(self):
        forms = [
            ParsedForm("слово", "слово", "noun", "nominative", "singular", "neut", "inan", set()),
            ParsedForm("слова", "слово", "noun", "genitive", "singular", "neut", "inan", set()),
        ]
        group = LemmaGroup("слово", "noun", forms)
        self.assertTrue(is_p2_eligible(group))

    def test_patronymic_not_eligible_for_p2(self):
        forms = [ParsedForm("иванович", "иванович", "noun", "nominative", "singular", "masc", "anim", {"Patr"})]
        group = LemmaGroup("иванович", "noun", forms)
        self.assertFalse(is_p2_eligible(group))


class TestP1Scoring(unittest.TestCase):
    """Tests for P1 scoring priority."""

    def test_must_include_prioritized(self):
        forms_common = [
            ParsedForm("человек", "человек", "noun", "nominative", "singular", "masc", "anim", set()),
            ParsedForm("человека", "человек", "noun", "genitive", "singular", "masc", "anim", set()),
        ]
        forms_must = [
            ParsedForm("сталь", "сталь", "noun", "nominative", "singular", "femn", "inan", set()),
            ParsedForm("стали", "сталь", "noun", "genitive", "singular", "femn", "inan", set()),
        ]
        group_common = LemmaGroup("человек", "noun", forms_common)
        group_must = LemmaGroup("сталь", "noun", forms_must)

        score_common = compute_p1_score(group_common)
        score_must = compute_p1_score(group_must)

        # "человек" is in both PILOT_MUST_INCLUDE and DOMAIN_SEED, so it scores
        # better than "сталь" which is only in PILOT_MUST_INCLUDE
        self.assertLess(score_common, score_must)

    def test_noun_prioritized_over_adjective(self):
        forms_noun = [
            ParsedForm("дом", "дом", "noun", "nominative", "singular", "masc", "inan", set()),
            ParsedForm("дома", "дом", "noun", "genitive", "singular", "masc", "inan", set()),
        ]
        forms_adj = [
            ParsedForm("большой", "большой", "adjective", "nominative", "singular", "masc", "inan", set()),
            ParsedForm("большого", "большой", "adjective", "genitive", "singular", "masc", "inan", set()),
        ]
        group_noun = LemmaGroup("дом", "noun", forms_noun)
        group_adj = LemmaGroup("большой", "adjective", forms_adj)

        score_noun = compute_p1_score(group_noun)
        score_adj = compute_p1_score(group_adj)

        self.assertLess(score_noun, score_adj)

    def test_shorter_lemma_prioritized(self):
        forms_short = [
            ParsedForm("дом", "дом", "noun", "nominative", "singular", "masc", "inan", set()),
            ParsedForm("дома", "дом", "noun", "genitive", "singular", "masc", "inan", set()),
        ]
        forms_long = [
            ParsedForm("здание", "здание", "noun", "nominative", "singular", "neut", "inan", set()),
            ParsedForm("здания", "здание", "noun", "genitive", "singular", "neut", "inan", set()),
        ]
        group_short = LemmaGroup("дом", "noun", forms_short)
        group_long = LemmaGroup("здание", "noun", forms_long)

        score_short = compute_p1_score(group_short)
        score_long = compute_p1_score(group_long)

        self.assertLess(score_short, score_long)


class TestP2Scoring(unittest.TestCase):
    """Tests for P2 scoring priority."""

    def test_domain_seed_prioritized(self):
        forms_seed = [
            ParsedForm("жизнь", "жизнь", "noun", "nominative", "singular", "femn", "inan", set()),
            ParsedForm("жизни", "жизнь", "noun", "genitive", "singular", "femn", "inan", set()),
        ]
        forms_rare = [
            ParsedForm("экзистенциализм", "экзистенциализм", "noun", "nominative", "singular", "masc", "inan", set()),
            ParsedForm("экзистенциализма", "экзистенциализм", "noun", "genitive", "singular", "masc", "inan", set()),
        ]
        group_seed = LemmaGroup("жизнь", "noun", forms_seed)
        group_rare = LemmaGroup("экзистенциализм", "noun", forms_rare)

        score_seed = compute_p2_score(group_seed)
        score_rare = compute_p2_score(group_rare)

        self.assertLess(score_seed, score_rare)


class TestSelectP1P2Groups(unittest.TestCase):
    """Tests for P1/P2 group selection."""

    def test_p1_excludes_patronymics(self):
        groups = {
            "человек:noun": LemmaGroup("человек", "noun", [
                ParsedForm("человек", "человек", "noun", "nominative", "singular", "masc", "anim", set()),
                ParsedForm("человека", "человек", "noun", "genitive", "singular", "masc", "anim", set()),
            ]),
            "иванович:noun": LemmaGroup("иванович", "noun", [
                ParsedForm("иванович", "иванович", "noun", "nominative", "singular", "masc", "anim", {"Patr"}),
            ]),
        }
        p1, p2 = select_p1_p2_groups(groups, 10, 10)
        p1_lemmas = {g.lemma for g in p1}
        p2_lemmas = {g.lemma for g in p2}
        self.assertNotIn("иванович", p1_lemmas)
        self.assertNotIn("иванович", p2_lemmas)

    def test_p1_excludes_technical_compounds(self):
        groups = {
            "дом:noun": LemmaGroup("дом", "noun", [
                ParsedForm("дом", "дом", "noun", "nominative", "singular", "masc", "inan", set()),
                ParsedForm("дома", "дом", "noun", "genitive", "singular", "masc", "inan", set()),
            ]),
            "электро-механический:adjective": LemmaGroup("электро-механический", "adjective", [
                ParsedForm("электро-механический", "электро-механический", "adjective", "nominative", "singular", "masc", "inan", set()),
            ]),
        }
        p1, _ = select_p1_p2_groups(groups, 10, 10)
        p1_lemmas = {g.lemma for g in p1}
        self.assertNotIn("электро-механический", p1_lemmas)

    def test_p1_prioritizes_domain_seed(self):
        # Need enough forms to meet P1 threshold (ratio >= 0.55 for nouns = ~7 distinct case/number combos)
        groups = {
            "человек:noun": LemmaGroup("человек", "noun", [
                ParsedForm("человек", "человек", "noun", "nominative", "singular", "masc", "anim", set()),
                ParsedForm("человека", "человек", "noun", "genitive", "singular", "masc", "anim", set()),
                ParsedForm("человеку", "человек", "noun", "dative", "singular", "masc", "anim", set()),
                ParsedForm("человеком", "человек", "noun", "instrumental", "singular", "masc", "anim", set()),
                ParsedForm("человеке", "человек", "noun", "prepositional", "singular", "masc", "anim", set()),
                ParsedForm("люди", "человек", "noun", "nominative", "plural", "masc", "anim", set()),
                ParsedForm("людей", "человек", "noun", "genitive", "plural", "masc", "anim", set()),
            ]),
            "редкость:noun": LemmaGroup("редкость", "noun", [
                ParsedForm("редкость", "редкость", "noun", "nominative", "singular", "femn", "inan", set()),
                ParsedForm("редкости", "редкость", "noun", "genitive", "singular", "femn", "inan", set()),
                ParsedForm("редкости", "редкость", "noun", "dative", "singular", "femn", "inan", set()),
                ParsedForm("редкостью", "редкость", "noun", "instrumental", "singular", "femn", "inan", set()),
                ParsedForm("редкости", "редкость", "noun", "prepositional", "singular", "femn", "inan", set()),
                ParsedForm("редкости", "редкость", "noun", "nominative", "plural", "femn", "inan", set()),
                ParsedForm("редкостей", "редкость", "noun", "genitive", "plural", "femn", "inan", set()),
            ]),
        }
        p1, _ = select_p1_p2_groups(groups, 10, 10)
        p1_lemmas = {g.lemma for g in p1}
        # "человек" is in DOMAIN_SEED, should be prioritized over "редкость"
        self.assertIn("человек", p1_lemmas)
        # Both should be in P1 since both meet the threshold and limit is 10
        self.assertIn("редкость", p1_lemmas)

    def test_p1_p2_no_overlap(self):
        groups = {
            "дом:noun": LemmaGroup("дом", "noun", [
                ParsedForm("дом", "дом", "noun", "nominative", "singular", "masc", "inan", set()),
                ParsedForm("дома", "дом", "noun", "genitive", "singular", "masc", "inan", set()),
            ]),
            "слово:noun": LemmaGroup("слово", "noun", [
                ParsedForm("слово", "слово", "noun", "nominative", "singular", "neut", "inan", set()),
                ParsedForm("слова", "слово", "noun", "genitive", "singular", "neut", "inan", set()),
            ]),
        }
        p1, p2 = select_p1_p2_groups(groups, 1, 1)
        p1_lemmas = {g.lemma for g in p1}
        p2_lemmas = {g.lemma for g in p2}
        self.assertEqual(p1_lemmas & p2_lemmas, set())


class TestConstants(unittest.TestCase):
    """Tests for filter constant values."""

    def test_domain_seed_not_empty(self):
        self.assertGreater(len(DOMAIN_SEED), 50)

    def test_proper_allowlist_not_empty(self):
        self.assertGreater(len(PROPER_ALLOWLIST), 5)

    def test_patronymic_endings(self):
        self.assertIn("ович", PATRONYMIC_ENDINGS)
        self.assertIn("евна", PATRONYMIC_ENDINGS)

    def test_technical_prefixes(self):
        self.assertIn("электро", TECHNICAL_PREFIXES)
        self.assertIn("термо", TECHNICAL_PREFIXES)

    def test_technical_suffixes(self):
        self.assertIn("строительный", TECHNICAL_SUFFIXES)
        self.assertIn("технический", TECHNICAL_SUFFIXES)

    def test_length_thresholds(self):
        self.assertEqual(P1_NOUN_MAX_LEN, 24)
        self.assertEqual(P1_ADJ_MAX_LEN, 32)
        self.assertEqual(P2_NOUN_MAX_LEN, 30)
        self.assertEqual(P2_ADJ_MAX_LEN, 40)

    def test_hyphen_thresholds(self):
        self.assertEqual(P1_MAX_HYPHENS, 1)
        self.assertEqual(P2_MAX_HYPHENS, 2)


if __name__ == "__main__":
    unittest.main()
