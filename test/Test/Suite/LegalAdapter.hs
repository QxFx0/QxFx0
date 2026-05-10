{-# LANGUAGE OverloadedStrings #-}
module Test.Suite.LegalAdapter
  ( legalAdapterTests
  ) where

import Test.HUnit
import qualified Data.Text as T

import QxFx0.Legal.Adapter
  ( LegalFact(..)
  , retrieveLegalFact
  , legalDisclaimer
  , legalFactToKnowledgeFragment
  )

legalAdapterTests :: [Test]
legalAdapterTests =
  [ TestLabel "legal fact retrieval for known keyword" testRetrieveKnown
  , TestLabel "legal fact retrieval returns Nothing for unknown" testRetrieveUnknown
  , TestLabel "legal fragment contains disclaimer" testFragmentHasDisclaimer
  , TestLabel "legal fragment contains source trace" testFragmentHasSource
  , TestLabel "legal fragment reflects uncertainty" testFragmentUncertainty
  , TestLabel "legal fragment reflects high confidence" testFragmentHighConfidence
  ]

testRetrieveKnown :: Test
testRetrieveKnown = TestCase $ do
  mFact <- retrieveLegalFact "право"
  case mFact of
    Nothing -> assertFailure "should find fact for 'право'"
    Just fact -> do
      assertEqual "sourceId" "ru.civil.code.art1" (lfSourceId fact)
      assertEqual "section" "Общие положения" (lfSection fact)

testRetrieveUnknown :: Test
testRetrieveUnknown = TestCase $ do
  mFact <- retrieveLegalFact "физика"
  assertEqual "should return Nothing for 'физика'" Nothing mFact

testFragmentHasDisclaimer :: Test
testFragmentHasDisclaimer = TestCase $ do
  mFact <- retrieveLegalFact "закон"
  case legalFactToKnowledgeFragment <$> mFact of
    Nothing -> assertFailure "expected legal fact for 'закон'"
    Just frag -> assertBool "fragment should contain disclaimer"
                   (legalDisclaimer `T.isInfixOf` frag)

testFragmentHasSource :: Test
testFragmentHasSource = TestCase $ do
  mFact <- retrieveLegalFact "хартия"
  case legalFactToKnowledgeFragment <$> mFact of
    Nothing -> assertFailure "expected legal fact for 'хартия'"
    Just frag -> do
      assertBool "fragment should contain source trace"
        ("[источник:" `T.isInfixOf` frag)
      assertBool "fragment should contain section trace"
        ("| раздел:" `T.isInfixOf` frag)

testFragmentUncertainty :: Test
testFragmentUncertainty = TestCase $ do
  mFact <- retrieveLegalFact "хартия"
  case legalFactToKnowledgeFragment <$> mFact of
    Nothing -> assertFailure "expected legal fact for 'хартия'"
    Just frag -> assertBool "uncertain fact should mention uncertainty"
                   ("неопределенность" `T.isInfixOf` frag)

testFragmentHighConfidence :: Test
testFragmentHighConfidence = TestCase $ do
  mFact <- retrieveLegalFact "презумпция"
  case legalFactToKnowledgeFragment <$> mFact of
    Nothing -> assertFailure "expected legal fact for 'презумпция'"
    Just frag -> assertBool "high-confidence fact should mention high confidence"
                   ("высокая достоверность" `T.isInfixOf` frag)

