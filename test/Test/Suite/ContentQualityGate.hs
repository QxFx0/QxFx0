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
  , TestLabel "CQG-11: Semantic — свобода mentions выбор or ответственность" testSemanticSvoboda
  , TestLabel "CQG-12: Semantic — истина mentions проверяем or воспроизводим" testSemanticIstina
  , TestLabel "CQG-13: Semantic — сознание mentions самоотчёт or первый" testSemanticSoznanie
  , TestLabel "CQG-14: Dialectical — answer contains Потому что or Но or Именно" testDialecticalStructure
  , TestLabel "CQG-15: Semantic — ответственность mentions долг or обязательства" testSemanticOtvetstvennost
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

-- CQG-11: Semantic — answer about свобода must mention выбор or ответственность
testSemanticSvoboda :: Test
testSemanticSvoboda = TestCase $ do
  let surface = generateForTopic "свобода"
      text = T.toLower (gsText surface)
      hasChoice = "выбор" `T.isInfixOf` text
      hasResponsibility = "ответственност" `T.isInfixOf` text
  assertBool ("Answer about свобода must mention выбор or ответственность. Text: " <> T.unpack text)
              (hasChoice || hasResponsibility)

-- CQG-12: Semantic — answer about истина must mention проверяем or воспроизводим
testSemanticIstina :: Test
testSemanticIstina = TestCase $ do
  let surface = generateForTopic "истина"
      text = T.toLower (gsText surface)
      hasVerify = "проверя" `T.isInfixOf` text
      hasReproducible = "воспроизвод" `T.isInfixOf` text
  assertBool ("Answer about истина must mention проверяем or воспроизводимость. Text: " <> T.unpack text)
              (hasVerify || hasReproducible)

-- CQG-13: Semantic — answer about сознание must mention самоотчёт or первый
testSemanticSoznanie :: Test
testSemanticSoznanie = TestCase $ do
  let surface = generateForTopic "сознание"
      text = T.toLower (gsText surface)
      hasSelfReport = "самоотч" `T.isInfixOf` text
      hasFirstPerson = "первого лица" `T.isInfixOf` text || "перв лиц" `T.isInfixOf` text
  assertBool ("Answer about сознание must mention самоотчёт or первый. Text: " <> T.unpack text)
              (hasSelfReport || hasFirstPerson)

-- CQG-14: Dialectical — answer must contain dialectical structure markers
testDialecticalStructure :: Test
testDialecticalStructure = TestCase $ do
  let surface = generateForTopic "свобода"
      text = T.toLower (gsText surface)
      hasBecause = "потому что" `T.isInfixOf` text
      hasBut = "но " `T.isInfixOf` text || "но не" `T.isInfixOf` text
      hasTherefore = "именно поэтому" `T.isInfixOf` text
      dialecticalMarkers = length (filter id [hasBecause, hasBut, hasTherefore])
  assertBool ("Answer should contain >=2 dialectical markers (Потому что/Но/Именно поэтому). Found " <> show dialecticalMarkers <> ". Text: " <> T.unpack text)
              (dialecticalMarkers >= 2)

-- CQG-15: Semantic — answer about ответственность must mention долг or обязательства
testSemanticOtvetstvennost :: Test
testSemanticOtvetstvennost = TestCase $ do
  let surface = generateForTopic "ответственность"
      text = T.toLower (gsText surface)
      hasDuty = "долг" `T.isInfixOf` text
      hasObligations = "обязательств" `T.isInfixOf` text
  assertBool ("Answer about ответственность must mention долг or обязательства. Text: " <> T.unpack text)
              (hasDuty || hasObligations)
