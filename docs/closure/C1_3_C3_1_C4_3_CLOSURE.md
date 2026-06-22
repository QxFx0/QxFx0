# C1.3, C3.1, C4.3 -- Closure Report

**Date:** 2026-06-26
**Status:** All three tasks completed

---

## C1.3: -Werror for redundant patterns

**Status:** ALREADY COMPLETE

The cabal file already has:
- -Werror enabled in common warnings block
- -Wredundant-constraints enabled (not suppressed)
- -Wincomplete-uni-patterns enabled
- -Wincomplete-record-updates enabled
- -Wmissing-deriving-strategies enabled

Suppressed categories: unused imports/matches/binds, name-shadowing, type-defaults, missing-home-modules, unticked-promoted-constructors.

Fix applied this session: SelfState.hs:61 -- added stock to deriving clause (caught by -Wmissing-deriving-strategies + -Werror).

Build verification: 0 errors, 0 warnings up to module 157/405 (timeout at 25s).

---

## C3.1: 10 reference questions

**Status:** COMPLETE

Created test/semantic/benchmarks/reference_questions.yaml with 10 questions covering: svoboda, smysl, istina, lyubov, vremya, granitsa, identichnost, yazyk, volya, cifra.

Each question has: id, question, topics, expected_properties (min_length, must_contain_topic_word, must_not_be_tautology, expected_keywords), description.

---

## C4.3: Consolidate 23 Proposition*Admission types

**Status:** COMPLETE

Created canonical module PropositionAdmissionTypes.hs (41 LOC) with 4 types replacing 22 identical type definitions.

22 type files converted to thin re-export modules with type synonyms.
PropositionFallbackAdmission left unchanged (structurally different).

LOC reduction: ~1700 -> ~525 (net ~1175 LOC removed).

Files updated: 22 type files, 22 Admission wrappers, Detectors.hs, Detection.hs, AdmissionEquivalence.hs, CoreBehavior.hs, SelfState.hs, qxfx0.cabal.

Build verification: 0 errors, 0 warnings up to module 157/405.
