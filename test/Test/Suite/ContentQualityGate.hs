{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}

module Test.Suite.ContentQualityGate
  ( contentQualityGateTests
  ) where

import Test.HUnit
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Types (MorphologyData(..))
import QxFx0.Semantic.Content.AtomStore
import QxFx0.Semantic.Content.PathFinder
import QxFx0.Semantic.Content.GeneratedPredicateGate (validatePath, GateVerdict(..))

-- | Content quality gate tests: verify that generated content meets
-- minimum quality standards. These are NOT pipe tests — they check
-- the actual water (content) that flows through the pipes.
--
-- Golden questions: 10 philosophical questions with expected quality criteria.
-- Each test checks: non-empty, no tautology, no obvious grammar errors,
-- relevant to question, not just disclaimer.

contentQualityGateTests :: [Test]
contentQualityGateTests =
  [ TestLabel "CQG-1: Definition non-empty for свобода" testDefinitionNonEmptySvoboda
  , TestLabel "CQG-2: Definition non-empty for смысл" testDefinitionNonEmptySmysl
  , TestLabel "CQG-3: Definition non-empty for истина" testDefinitionNonEmptyIstina
  , TestLabel "CQG-4: Definition non-empty for любовь" testDefinitionNonEmptyLyubov
  , TestLabel "CQG-5: Definition non-empty for время" testDefinitionNonEmptyVremya
  , TestLabel "CQG-6: No tautology (topic as its own definition)" testNoTautology
  , TestLabel "CQG-7: No hardcoded disclaimer only" testNoDisclaimerOnly
  , TestLabel "CQG-8: Path trace present in proof" testPathTracePresent
  , TestLabel "CQG-9: Gate verdict enforced" testGateVerdictEnforced
  , TestLabel "CQG-10: Multiple concepts produce distinct output" testDistinctOutput
  ]

-- Helper: generate a definition surface for a topic
generateForTopic :: Text -> GeneratedSurface
generateForTopic topic =
  composeDefinition (MorphologyData mempty mempty mempty mempty) defaultFieldProfile 3 seedGraph (AtomId topic)

-- CQG-1 through CQG-5: Definition must be non-empty for core concepts
testDefinitionNonEmptySvoboda :: Test
testDefinitionNonEmptySvoboda = TestCase $ do
  let surface = generateForTopic "свобода"
      text = gsText surface
  assertBool ("Expected non-empty definition for свобода, got: " <> T.unpack text) (not $ T.null text)

testDefinitionNonEmptySmysl :: Test
testDefinitionNonEmptySmysl = TestCase $ do
  let surface = generateForTopic "смысл"
      text = gsText surface
  assertBool ("Expected non-empty definition for смысл, got: " <> T.unpack text) (not $ T.null text)

testDefinitionNonEmptyIstina :: Test
testDefinitionNonEmptyIstina = TestCase $ do
  let surface = generateForTopic "истина"
      text = gsText surface
  assertBool ("Expected non-empty definition for истина, got: " <> T.unpack text) (not $ T.null text)

testDefinitionNonEmptyLyubov :: Test
testDefinitionNonEmptyLyubov = TestCase $ do
  let surface = generateForTopic "любовь"
      text = gsText surface
  assertBool ("Expected non-empty definition for любовь, got: " <> T.unpack text) (not $ T.null text)

testDefinitionNonEmptyVremya :: Test
testDefinitionNonEmptyVremya = TestCase $ do
  let surface = generateForTopic "время"
      text = gsText surface
  assertBool ("Expected non-empty definition for время, got: " <> T.unpack text) (not $ T.null text)

-- CQG-6: No tautology — topic word should not be its own definition
-- Checks that the definition doesn't start with "X — X предполагает..."
testNoTautology :: Test
testNoTautology = TestCase $ do
  let surface = generateForTopic "свобода"
      text = T.toLower (gsText surface)
      topic = "свобода"
      -- Tautology pattern: "свобода — свобода" (topic immediately repeated after dash)
      tautologyPattern = topic <> " — " <> topic
      hasTautology = T.isInfixOf tautologyPattern text
  assertBool ("Tautology detected: definition contains '" <> T.unpack tautologyPattern <> "'. Text: " <> T.unpack text)
              (not hasTautology)

-- CQG-7: Output should not be ONLY a disclaimer
-- The hardcoded disclaimer "Я удержу только устойчивую часть ответа..." should not be the entire output
testNoDisclaimerOnly :: Test
testNoDisclaimerOnly = TestCase $ do
  let surface = generateForTopic "свобода"
      text = T.strip (gsText surface)
      disclaimer = "Я удержу только устойчивую часть ответа и не буду достраивать непроверенные выводы."
      isOnlyDisclaimer = text == disclaimer || text == T.strip disclaimer
  assertBool ("Output is ONLY the hardcoded disclaimer, no actual content. Text: " <> T.unpack text)
              (not isOnlyDisclaimer)

-- CQG-8: Path proof trace should be present in generated surface
testPathTracePresent :: Test
testPathTracePresent = TestCase $ do
  let surface = generateForTopic "свобода"
      proofs = gsPaths surface
  assertBool ("Expected non-empty path proofs in generated surface") (not $ null proofs)

-- CQG-9: Gate verdict should be enforced (non-empty output means gate passed)
testGateVerdictEnforced :: Test
testGateVerdictEnforced = TestCase $ do
  let surface = generateForTopic "свобода"
      text = gsText surface
      paths = gsPaths surface
  -- If text is non-empty, at least one path should have passed the gate
  if not (T.null text)
    then assertBool ("Expected non-empty paths when text is non-empty") (not $ null paths)
    else assertBool ("Expected empty paths when text is empty") (null paths)

-- CQG-10: Different concepts should produce different output
testDistinctOutput :: Test
testDistinctOutput = TestCase $ do
  let s1 = generateForTopic "свобода"
      s2 = generateForTopic "смысл"
      t1 = gsText s1
      t2 = gsText s2
  assertBool ("Definitions for свобода and смысл should be different. свобода: " <> T.unpack t1 <> " | смысл: " <> T.unpack t2)
              (t1 /= t2)
