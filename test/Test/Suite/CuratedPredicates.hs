{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.CuratedPredicates
Description : P1.2 — curated predicate corpus loading and admission.
-}
module Test.Suite.CuratedPredicates
  ( curatedPredicatesTests
  ) where

import qualified Data.Map.Strict as M
import Data.Maybe (isJust)
import qualified Data.Text as T
import System.Directory (doesFileExist)
import Test.HUnit

import QxFx0.Semantic.Content
  ( DefinitionContent(..)
  , definitionCorpus
  , spRu
  )
import QxFx0.Semantic.Content.Curated
  ( curatedPredicatesPath
  , extendedDefinitionCorpus
  , loadCuratedPredicates
  , mergeCuratedIntoDefinitionCorpus
  )
import QxFx0.Semantic.ContentSelector (buildContentSelector, ContentSelector(..), csTopicPredicates)
import QxFx0.Semantic.Network.Ingest (admitRelationEndpoint, normalizeRelationText)
import QxFx0.Semantic.Space (emptySemanticSpace)

-- | The curated predicates file must exist and contain the top 20 gap
-- topics from @docs/GAPS.md@, each with at least two predicates.
testCuratedPredicatesLoad :: Test
testCuratedPredicatesLoad = TestLabel "curated predicates load with top 20 gaps" $ TestCase $ do
  exists <- doesFileExist curatedPredicatesPath
  assertBool "curated_predicates.jsonl must exist" exists
  curated <- loadCuratedPredicates curatedPredicatesPath
  let expectedTopics = [ "смысл", "идентичность", "граница", "ремонт", "цифра"
                       , "доказательство", "становление", "сущность"
                       , "целостность жизни", "соотнесённость с целым"
                       , "различение внутри и снаружи", "условие формы"
                       , "дискретность и точность", "формализация опыта"
                       , "преемственность я", "нарратив о себе"
                       , "восстановление функции", "диагностика поломки"
                       , "осознанность выбора", "самоопределение"
                       ]
      missing = filter (\t -> not (M.member t curated)) expectedTopics
  assertEqual "all top 20 gap topics must be present in curated predicates"
    [] missing
  mapM_ (\t ->
           case M.lookup t curated of
             Nothing -> assertFailure ("topic " ++ T.unpack t ++ " missing")
             Just dc -> assertBool ("topic " ++ T.unpack t ++ " must have >=2 predicates")
                                   (length (dcPredicates dc) >= 2))
        expectedTopics

-- | P1.4: Verify that batch 21-50 concepts are curated
testCuratedPredicatesBatch21To50 :: Test
testCuratedPredicatesBatch21To50 = TestLabel "curated predicates batch 21-50" $ TestCase $ do
  curated <- loadCuratedPredicates curatedPredicatesPath
  let batch21To50 = [ "автономия суждения", "аксиома", "акт доверия"
                     , "акт обращения к личному прошлому", "актуализация прошлого"
                     , "алгоритм", "асимметрия отношений", "аспект от первого лица"
                     , "беспристрастность", "будущее как возможность"
                     , "верность", "вечность в мгновении", "вина и заслуга"
                     , "внутренний закон", "возвращение к работоспособности"
                     , "воздаяние по заслугам", "восприятие и рефлексию"
                     , "воспроизводимость", "встреча с собой"
                     , "выбор", "выбор цели", "выражение позиции"
                     , "гармония формы", "глубина невыразимого"
                     , "глубина тишины", "государство"
                     , "готовность к ответу", "готовность к риску"
                     , "граница выразимого", "благодарность"
                     ]
      missing = filter (\t -> not (M.member t curated)) batch21To50
  assertEqual "all batch 21-50 topics must be present in curated predicates"
    [] missing
  mapM_ (\t ->
           case M.lookup t curated of
             Nothing -> assertFailure ("batch 21-50 topic " ++ T.unpack t ++ " missing")
             Just dc -> assertBool ("batch 21-50 topic " ++ T.unpack t ++ " must have >=2 predicates")
                                   (length (dcPredicates dc) >= 2))
        batch21To50

-- | Merging curated predicates into the seed corpus extends coverage: a
-- hardcoded topic and a curated topic are both reachable.
testCuratedMergeExtendsDefinitionCorpus :: Test
testCuratedMergeExtendsDefinitionCorpus = TestLabel "extended corpus covers seed and curated topics" $ TestCase $ do
  curated <- loadCuratedPredicates curatedPredicatesPath
  let extended = mergeCuratedIntoDefinitionCorpus curated definitionCorpus
  assertBool "seed topic 'свобода' must still be present"
    (isJust (M.lookup "свобода" extended))
  assertBool "curated topic 'смысл' must be present"
    (isJust (M.lookup "смысл" extended))

-- | A curated topic contains the expected Russian predicate surface form.
testCuratedPredicatesAdmitted :: Test
testCuratedPredicatesAdmitted = TestLabel "curated topic contains expected Russian predicate" $ TestCase $ do
  extended <- extendedDefinitionCorpus
  case M.lookup "смысл" extended of
    Nothing -> assertFailure "смысл should be present in extended corpus"
    Just dc -> do
      let ruPreds = map spRu (dcPredicates dc)
      assertBool "смысл predicate should mention 'понимание'"
        (any ("понимание" `T.isInfixOf`) ruPreds)

-- | A relation-rationale endpoint that corresponds to a curated gap concept
-- must pass the admission gate after normalization.
testCuratedConceptAdmittedByRelationGate :: Test
testCuratedConceptAdmittedByRelationGate = TestLabel "curated gap concept admitted through relation gate" $ TestCase $ do
  let normalized = normalizeRelationText "смысл"
  assertEqual "смысл normalizes to itself" "смысл" normalized
  assertBool "смысл must be admitted as a relation endpoint"
    (isJust (admitRelationEndpoint "смысл"))

-- | P1.3: ContentSelector coverage test - verify that all Top-20 curated
-- topics are visible to the selector and can be selected.
testContentSelectorCoverage :: Test
testContentSelectorCoverage = TestLabel "ContentSelector sees all Top-20 curated topics" $ TestCase $ do
  -- Load curated predicates
  curated <- loadCuratedPredicates curatedPredicatesPath
  let extended = mergeCuratedIntoDefinitionCorpus curated definitionCorpus
      topicPredicates = M.map dcPredicates extended
      -- Build a minimal ContentSelector with the extended corpus
      selector = buildContentSelector
        emptySemanticSpace
        M.empty  -- topicAtoms
        topicPredicates
        M.empty  -- lemmaMap
        Nothing  -- ontology
  
  -- Check that all Top-20 topics are in the selector
  let expectedTopics = [ "смысл", "идентичность", "граница", "ремонт", "цифра"
                       , "доказательство", "становление", "сущность"
                       , "целостность жизни", "соотнесённость с целым"
                       , "различение внутри и снаружи", "условие формы"
                       , "дискретность и точность", "формализация опыта"
                       , "преемственность я", "нарратив о себе"
                       , "восстановление функции", "диагностика поломки"
                       , "осознанность выбора", "самоопределение"
                       ]
  
  mapM_ (\t -> 
           assertBool ("Topic '" ++ T.unpack t ++ "' must be in ContentSelector")
             (M.member t (csTopicPredicates selector)))
        expectedTopics
  
  -- Check that we can find predicates for curated topics in the selector
  case M.lookup "смысл" (csTopicPredicates selector) of
    Nothing -> assertFailure "смысл should be in selector"
    Just preds -> 
      assertBool "Topic 'смысл' should have predicates in selector"
        (not (null preds))

-- | P1.5: Verify that batch 51-100 concepts are curated
testCuratedPredicatesBatch51To100 :: Test
testCuratedPredicatesBatch51To100 = TestLabel "curated predicates batch 51-100" $ TestCase $ do
  curated <- loadCuratedPredicates curatedPredicatesPath
  let batch51To100 = [ "актом отказа или знаком присутствия", "восстановление функции"
                     , "граница", "граница смысла", "границу между я и другими"
                     , "границу, через которую жизнь обретает конечную форму", "данные"
                     , "дар без расчёта", "действие в условиях неопределённости"
                     , "действие к выбранной цели", "действие независимо от желания"
                     , "делегирование и контроль", "доверие между субъектами"
                     , "доверием к источнику или опыту", "доверием к тому, что не может быть проверено"
                     , "договор", "долг памяти", "долженствование", "достоверность и искажение"
                     , "дух", "душа", "единство поля опыта", "жизни неотменимость"
                     , "жизнь", "забывание как условие", "закон", "защита и ограничение"
                     , "защитная реакция", "игнорирование последствий", "идентификация с собой"
                     , "идентичность через время", "из событий и их интерпретации"
                     , "избрано или навязано обстоятельствами", "изоляция или уединение"
                     , "инстинкт", "интенциональность", "интерпретация прошлого"
                     , "искренность рассказа", "искусство", "исполнение обещания"
                     , "к обобщению и абстракции", "к полезности", "как условие возможности любого суждения"
                     , "длительность", "для восстановления и интеграции опыта", "избирательность и реконструкция"
                     ]
      missing = filter (\t -> not (M.member t curated)) batch51To100
  assertEqual "all batch 51-100 topics must be present in curated predicates"
    [] missing
  mapM_ (\t ->
           case M.lookup t curated of
             Nothing -> assertFailure ("batch 51-100 topic " ++ T.unpack t ++ " missing")
             Just dc -> assertBool ("batch 51-100 topic " ++ T.unpack t ++ " must have >=2 predicates")
                                   (length (dcPredicates dc) >= 2))
        batch51To100

-- | P1.6: Verify that batch 101-150 concepts are curated
testCuratedPredicatesBatch101To150 :: Test
testCuratedPredicatesBatch101To150 = TestLabel "curated predicates batch 101-150" $ TestCase $ do
  curated <- loadCuratedPredicates curatedPredicatesPath
  let batch101To150 = [ "наперекор очевидности", "направление вектора жизни"
                      , "направленность усилия", "нарратив и факт"
                      , "насилие или забота", "настоящее как точка"
                      , "нация", "независимость от наблюдателя"
                      , "нейрон", "необратимо и неравномерно"
                      , "необратимо — прошлое недоступно для изменения"
                      , "необратимое прекращение существования"
                      , "необходимость и случайность", "об угрозе целостности"
                      , "об угрозе целостности субъекта", "обещание себе"
                      , "обоснованность и вес", "обоснованность не доказательством"
                      , "объективность"
                      ]
      missing = filter (\t -> not (M.member t curated)) batch101To150
  assertEqual "all batch 101-150 topics must be present in curated predicates"
    [] missing
  mapM_ (\t ->
           case M.lookup t curated of
             Nothing -> assertFailure ("batch 101-150 topic " ++ T.unpack t ++ " missing")
             Just dc -> assertBool ("batch 101-150 topic " ++ T.unpack t ++ " must have >=2 predicates")
                                   (length (dcPredicates dc) >= 2))
        batch101To150

-- | P1.7: Verify that batch 121-150 concepts are curated
testCuratedPredicatesBatch121To150 :: Test
testCuratedPredicatesBatch121To150 = TestLabel "curated predicates batch 121-150" $ TestCase $ do
  curated <- loadCuratedPredicates curatedPredicatesPath
  let batch121To150 = [ "бытие", "вера", "власть", "воля"
                      , "воспоминание", "время", "доверие", "долг"
                      , "истина", "история", "красота", "любовь"
                      , "мнение", "молчание", "надежда"
                      , "обязательства перед другими", "одиночество"
                      , "ожидание угрозы", "опора на другого"
                      , "опыт через различение и именование"
                      , "ориентация на будущее", "осмысление конечности"
                      , "основание всего", "осознание последствий"
                      , "остановка и осмысление"
                      , "от воспринимающего и культурной рамки"
                      , "от интуиции потребностью в доказательстве"
                      , "от точки зрения рассказчика"
                      , "ответ на вопрос кто я", "ответ перед другими"
                      , "ответственность", "ответственность власти"
                      ]
      missing = filter (\t -> not (M.member t curated)) batch121To150
  assertEqual "all batch 121-150 topics must be present in curated predicates"
    [] missing
  mapM_ (\t ->
           case M.lookup t curated of
             Nothing -> assertFailure ("batch 121-150 topic " ++ T.unpack t ++ " missing")
             Just dc -> assertBool ("batch 121-150 topic " ++ T.unpack t ++ " must have >=2 predicates")
                                   (length (dcPredicates dc) >= 2))
        batch121To150

curatedPredicatesTests :: [Test]
curatedPredicatesTests =
  [ testCuratedPredicatesLoad
  , testCuratedMergeExtendsDefinitionCorpus
  , testCuratedPredicatesAdmitted
  , testCuratedConceptAdmittedByRelationGate
  , testContentSelectorCoverage
  , testCuratedPredicatesBatch21To50
  , testCuratedPredicatesBatch51To100
  , testCuratedPredicatesBatch101To150
  , testCuratedPredicatesBatch121To150
  ]
