{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.TopicSpan
Description : Corpus-level pins for the multiword topic-span rule.

Pre-registered 2026-11-03, signed 2026-11-04 (D-1).  Bars B1/B2/B3 from
the signed document:

  * B1 — every multiword merged-corpus key is a 'canonicalTopic' fixpoint
    (before the change only 16 of 624 were).
  * B2 — every key that was already a fixpoint under the pre-change rule
    stays one.
  * B3 — every single-word key canonicalizes byte-identically to the
    pre-change rule (the single-token branch is unchanged).

The population is the merged corpus (definitionCorpus + curated
overlay), measured at signing time as 4 070 keys: 624 multiword,
3 446 single-word.  Counts are asserted as non-empty bands, not exact
numbers, so corpus growth does not turn the pins red for the wrong
reason; the per-key properties are the actual bars.
-}
module Test.Suite.TopicSpan
  ( topicSpanTests
  ) where

import Test.HUnit (Test(..), assertBool, assertEqual)

import Data.Maybe (fromMaybe)
import qualified Data.Map.Strict as M
import qualified Data.Text as T

import QxFx0.Resources (loadMorphologyData)
import QxFx0.Semantic.Content (definitionCorpus)
import QxFx0.Semantic.Content.Curated
  ( curatedPredicatesPath
  , loadCuratedPredicates
  , mergeCuratedIntoDefinitionCorpus
  )
import QxFx0.Semantic.Intent.Classifier (canonicalTopic)
import QxFx0.Semantic.Morphology (extractContentNouns)
import QxFx0.Types.Domain.Atoms (MorphologyData(..))

-- | The pre-2026-11-03 rule, reproduced verbatim: first content noun,
-- then the whole-phrase nominative lookup.  Used only as the B3
-- oracle; production no longer contains it.
legacyCanonical :: MorphologyData -> T.Text -> T.Text
legacyCanonical morph topic =
  case extractContentNouns topic of
    (lemma:_) -> lemma
    [] -> fromMaybe topic (M.lookup (T.toLower (T.strip topic)) (mdNominative morph))

-- | The four measured substitution compounds (pre-registration §2/§6,
-- B4).  They are OOV relative to the merged corpus, so B1 cannot see
-- them; this pin keeps the exact defect class named even if the corpus
-- later absorbs one of them.
measuredCompounds :: [T.Text]
measuredCompounds =
  [ "цифровая свобода"
  , "коллективная память"
  , "термоядерный синтез"
  , "гравитационная волна"
  ]

topicSpanTests :: [Test]
topicSpanTests =
  [ TestLabel "multiword corpus keys survive canonicalTopic (B1/B2)" testMultiwordFixpoints
  , TestLabel "single-word corpus keys canonicalize as before (B3)" testSingleWordLegacy
  , TestLabel "span rule is whitespace-normalized and case-preserving" testSpanShape
  ]

-- | B1 + B2 over the merged corpus, loaded once.
testMultiwordFixpoints :: Test
testMultiwordFixpoints = TestCase $ do
  md <- loadMorphologyData
  curated <- loadCuratedPredicates curatedPredicatesPath
  let merged = mergeCuratedIntoDefinitionCorpus curated definitionCorpus
      multiword = [ k | k <- M.keys merged, length (T.words k) >= 2 ]
      b1 = [ (k, canonicalTopic md k)
           | k <- multiword
           , canonicalTopic md k /= k
           ]
      b2 = [ (k, canonicalTopic md k)
           | k <- multiword
           , legacyCanonical md k == k
           , canonicalTopic md k /= k
           ]
  assertBool "the merged corpus must still carry multiword keys"
    (not (null multiword))
  assertEqual
    ("B1: multiword keys must be canonicalTopic fixpoints; first failures: "
      <> show (take 10 b1))
    [] b1
  assertEqual
    ("B2: keys preserved before must stay preserved; first failures: "
      <> show (take 10 b2))
    [] b2
  -- The pre-registration (§2) named three mixed-case rows as the reason case
  -- folding is forbidden.  Measured 2026-11-05: the loader normalizes keys
  -- (`normalizeTopic = T.toLower . T.strip`), so the loaded population has
  -- **no** mixed-case keys and the clause is vacuous.  The signed rule still
  -- preserves case (pinned in `testSpanShape`); the cost is the opposite of
  -- the original rationale — a capitalised span («Смысл жизни») is not a
  -- member of the lowercase key set and abstains.  Recorded, not re-scoped.
  let mixedCase = [ k | k <- multiword, k /= T.toLower k ]
  assertEqual
    ("loaded keys are lowercase-normalized; unexpected mixed-case keys: "
      <> show (take 10 mixedCase))
    [] mixedCase
  -- The residual itself, pinned by name so the cost cannot be silently
  -- claimed as "protected": the capitalised span is preserved verbatim and
  -- therefore misses the lowercase key.
  assertEqual "capitalised span is preserved, not folded"
    "Смысл жизни"
    (canonicalTopic md "Смысл жизни")

-- | B3: the single-token branch is byte-identical to the old rule.
testSingleWordLegacy :: Test
testSingleWordLegacy = TestCase $ do
  md <- loadMorphologyData
  curated <- loadCuratedPredicates curatedPredicatesPath
  let merged = mergeCuratedIntoDefinitionCorpus curated definitionCorpus
      single = [ k | k <- M.keys merged, length (T.words k) == 1 ]
      mismatches = [ (k, legacyCanonical md k, canonicalTopic md k)
                   | k <- single
                   , canonicalTopic md k /= legacyCanonical md k
                   ]
  assertBool "the merged corpus must still carry single-word keys"
    (not (null single))
  assertEqual
    ("B3: single-word keys must canonicalize byte-identically; first failures: "
      <> show (take 10 mismatches))
    [] mismatches

-- | Shape of the span rule itself: whitespace normalized, case and
-- tokens untouched.  Uses an empty morphology on purpose — the span
-- branch must not consult it.
testSpanShape :: Test
testSpanShape = TestCase $ do
  let morph = MorphologyData M.empty M.empty M.empty M.empty
  mapM_
    (\span_ ->
       assertEqual
         ("measured compound must be preserved verbatim: " <> T.unpack span_)
         span_
         (canonicalTopic morph span_))
    measuredCompounds
  assertEqual "leading/trailing/double whitespace collapses"
    "анализ данных"
    (canonicalTopic morph "  анализ   данных ")
  assertEqual "case is preserved, never folded"
    "Raspberry Pi"
    (canonicalTopic morph "Raspberry Pi")
  assertEqual "single token keeps the lemma rule"
    "свобода"
    (canonicalTopic morph "свобода")
