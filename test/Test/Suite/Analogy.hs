{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.Analogy (analogyTests) where

import Test.HUnit
import qualified Data.Text as T
import QxFx0.Semantic.Analogy
import QxFx0.Semantic.Content

analogyTests :: Test
analogyTests = TestList
  [ testAdaptPredicate
  , testReplaceFirst
  , testAnalogicalResponse
  , testFallbackSimilarity
  , testFindNearestCoveredTopic
  , testFindNearestCoveredTopicThreshold
  , testAnalogicalResponseIntegration
  ]

testAdaptPredicate :: Test
testAdaptPredicate = TestCase $ do
  let pred = SemanticPredicate
        { spRole = RoleProperty
        , spRu = "свобода предполагает выбор"
        , spEn = "freedom presupposes choice"
        , spTopicForm = "свобода"
        }
      adapted = adaptPredicate "ответственность" pred
  assertEqual "адаптация предиката"
    "ответственность предполагает выбор"
    adapted

testReplaceFirst :: Test
testReplaceFirst = TestCase $ do
  let result1 = replaceFirst "мир" "вселенная" "мир прекрасен"
      result2 = replaceFirst "x" "y" "abc"
      result3 = replaceFirst "test" "demo" "no match here"
  assertEqual "замена первого вхождения" "вселенная прекрасен" result1
  assertEqual "отсутствие вхождения" "abc" result2
  assertEqual "нет совпадений" "no match here" result3

testAnalogicalResponse :: Test
testAnalogicalResponse = TestCase $ do
  let response = analogicalResponse "долг" "свобода"
  case response of
    Nothing -> assertFailure "ожидался аналогический ответ"
    Just text -> assertBool "ответ содержит новую тему"
      ("долг" `T.isInfixOf` text)

testFallbackSimilarity :: Test
testFallbackSimilarity = TestCase $ do
  let sim1 = fallbackSimilarity "свобода" "свобода"
      sim2 = fallbackSimilarity "свобода" "свободы"
      sim3 = fallbackSimilarity "свобода" "выбора"
      sim4 = fallbackSimilarity "долг" "воля"
      sim5 = fallbackSimilarity "" ""
  assertBool "идентичные темы" (sim1 > 0.99)
  assertBool "общий префикс" (sim2 > 0.8 && sim2 < 0.9)
  assertBool "нет общего префикса" (sim3 < 0.1)
  assertBool "разные слова" (sim4 < 0.1)
  assertEqual "пустые строки" 1.0 sim5

testFindNearestCoveredTopic :: Test
testFindNearestCoveredTopic = TestCase $ do
  let result1 = findNearestCoveredTopic "свободы"
      result2 = findNearestCoveredTopic "сознания"
      result3 = findNearestCoveredTopic "xyz123"
  assertEqual "свободы -> свобода" (Just "свобода") result1
  assertEqual "сознания -> сознание" (Just "сознание") result2
  assertEqual "несуществующий топик" Nothing result3

testFindNearestCoveredTopicThreshold :: Test
testFindNearestCoveredTopicThreshold = TestCase $ do
  let sim1 = fallbackSimilarity "созерцание" "сознание"
      result1 = findNearestCoveredTopic "созерцание"
      sim2 = fallbackSimilarity "достоинство" "долг"
      result2 = findNearestCoveredTopic "достоинство"
  assertBool "созерцание-сознание >= 0.3" (sim1 >= 0.3)
  assertEqual "созерцание -> сознание" (Just "сознание") result1
  assertBool "достоинство-долг < 0.3" (sim2 < 0.3)
  assertEqual "достоинство -> Nothing" Nothing result2

testAnalogicalResponseIntegration :: Test
testAnalogicalResponseIntegration = TestCase $ do
  let response = analogicalResponse "созерцание" "сознание"
  case response of
    Nothing -> assertFailure "ожидался аналогический ответ для созерцание"
    Just text -> do
      assertBool "ответ содержит созерцание" ("созерцание" `T.isInfixOf` text)
      assertBool "ответ не содержит сознание" (not $ "сознание" `T.isInfixOf` text)
