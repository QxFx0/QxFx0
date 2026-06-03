{-# LANGUAGE OverloadedStrings #-}

-- | Test suite for the Package 4 'AuthoritySurface' parser and renderer.
--
-- Uses only library dependencies (no tasty) so it can live in
-- the library's other-modules section alongside the other test
-- suites. When the test infrastructure is refactored, these
-- should move to a proper test stanza.
module Test.Suite.RenderAuthorityStub (tests) where

import Prelude

import qualified QxFx0.Render.Authority as Auth
import QxFx0.Types.State.SemanticCommitment
  ( FactualClaimPayload(..)
  , CommitmentOrigin(..)
  , TurnSeq(..)
  )

-- | Trivial test list (mimics TestTree without tasty dependency).
-- The closure plan's Package 4 test suite should migrate to a
-- proper test stanza when the test infrastructure is refactored.
data TestTree = TestTree [TestCase]
data TestCase = TestCase String (IO ())

testGroup :: String -> [TestCase] -> TestTree
testGroup _name = TestTree

testCase :: String -> IO () -> TestCase
testCase = TestCase

assertBool :: String -> Bool -> IO ()
assertBool msg True  = pure ()
assertBool msg False = error ("FAIL: " ++ msg)

(@?=) :: (Eq a, Show a) => a -> a -> IO ()
actual @?= expected
  | actual == expected = pure ()
  | otherwise          = error ("FAIL: expected " ++ show expected ++ ", got " ++ show actual)

canonicalPayload :: FactualClaimPayload
canonicalPayload = FactualClaimPayload
  { fcpStatement = "User is a software developer."
  , fcpConfidence = 0.95
  , fcpOrigin = OriginParser "en:UserIs"
  , fcpTurnSeq = TurnSeq 0
  , fcpDeps = []
  }

tests :: TestTree
tests = testGroup "Render.Authority (Package 4)"
  [ testCase "empty surface is stub" $
      Auth.isStubAuthoritySurface Auth.emptyAuthoritySurface @?= True

  , testCase "parser recognises en:UserIs" $ do
      let surface = Auth.AuthoritySurface "User is a software developer."
      case Auth.parseAuthoritySurface surface of
        Just p  -> fcpStatement p @?= "User is a software developer."
        Nothing -> assertBool "expected parse success" False

  , testCase "parser recognises ru:UserIs" $ do
      let surface = Auth.AuthoritySurface "Пользователь — разработчик."
      case Auth.parseAuthoritySurface surface of
        Just p  -> fcpStatement p @?= "Пользователь — разработчик."
        Nothing -> assertBool "expected parse success" False

  , testCase "parser recognises en:TopicIs" $ do
      let surface = Auth.AuthoritySurface "Topic is closure plan."
      case Auth.parseAuthoritySurface surface of
        Just p  -> fcpStatement p @?= "Topic is closure plan."
        Nothing -> assertBool "expected parse success" False

  , testCase "parser recognises ru:TopicIs" $ do
      let surface = Auth.AuthoritySurface "Тема — план закрытия."
      case Auth.parseAuthoritySurface surface of
        Just p  -> fcpStatement p @?= "Тема — план закрытия."
        Nothing -> assertBool "expected parse success" False

  , testCase "parser returns Nothing for non-commitment text" $
      Auth.parseAuthoritySurface (Auth.AuthoritySurface "Hello, world!")
        @?= Nothing

  , testCase "renderer round-trips canonical payload" $ do
      let surface = Auth.renderAuthoritySurface canonicalPayload
      case Auth.parseAuthoritySurface surface of
        Just p  -> fcpStatement p @?= fcpStatement canonicalPayload
        Nothing -> assertBool "expected round-trip" False

  , testCase "round-trip property holds" $
      Auth.roundTripProperty canonicalPayload @?= True

  , testCase "non-round-trippable surface fails property" $ do
      let bad = canonicalPayload { fcpOrigin = OriginParser "en:Unknown" }
      Auth.roundTripProperty bad @?= False
  ]
