{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for cutover Stage 1a micro-grammar detectors
-- (ADR-0055, pre-registered 2026-10-07): pure cores only.
-- Live gate behavior is verified by the gate battery; these pin
-- the fire/decline matrix and the trace round-trip.
module Test.Suite.OwnershipDetect
  ( ownershipDetectTests
  ) where

import Test.HUnit
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as BL
import qualified Data.Text as T
import Data.Aeson (encode, decode)

import QxFx0.Semantic.Ownership.Detect
import QxFx0.Types.TurnProjection (OwnershipCompareTrace(..))
import QxFx0.Types.Semantic.Ownership (FileOwnershipRow(..))

ownershipDetectTests :: [Test]
ownershipDetectTests =
  [ TestLabel "give fires on canonical shape" $ TestCase $ do
      let (found, reason) = detectOwnershipEvent "Аня подарила книгу Боре"
      assertEqual "gate fires" GateFired reason
      case found of
        Nothing -> assertFailure "give must detect"
        Just det -> do
          assertEqual "event id" "give" (odEventId det)
          assertEqual "agent" "Аня" (odAgent det)
          assertEqual "recipient" "Боре" (odRecipient det)
          assertEqual "object" "книгу" (odObject det)
  , TestLabel "all seven events fire" $ TestCase $ do
      mapM_ (\(input, eid) ->
               case detectOwnershipEvent input of
                 (Just det, GateFired) ->
                   assertEqual ("event " <> T.unpack eid) eid (odEventId det)
                 _ -> assertFailure ("must fire: " <> T.unpack input))
        [ ("Аня одолжила книгу Боре", "lend")
        , ("Аня показала книгу Боре", "show")
        , ("Боря взял книгу у Ани", "take")
        , ("Боря украл книгу у Ани", "steal")
        ]
  , TestLabel "no verb match closes the gate" $ TestCase $ do
      assertEqual "strangers walking"
        (Nothing, GateNoEventMatch)
        (detectOwnershipEvent "Аня и Боря гуляли")
  , TestLabel "ambiguous events close the gate" $ TestCase $ do
      case detectOwnershipEvent "Аня подарила и одолжила книгу Боре" of
        (Nothing, GateAmbiguousEvents _) -> pure ()
        other -> assertFailure ("ambiguity must close: " <> show other)
  , TestLabel "capitalized pronoun closes the gate" $ TestCase $ do
      assertEqual "pronoun agent"
        (Nothing, GatePronounParticipant)
        (detectOwnershipEvent "Мне Аня одолжила книгу")
  , TestLabel "single party closes the gate" $ TestCase $ do
      assertEqual "lone borrower"
        (Nothing, GateMissingParties)
        (detectOwnershipEvent "Я одолжил книгу")
  , TestLabel "pronoun inventory covers cases" $ TestCase $ do
      mapM_ (\w -> assertBool ("pronoun: " <> T.unpack w)
               (w `elem` ownershipPronouns))
        ["я", "мне", "его", "нее", "ними", "себя"]
  , TestLabel "compare trace round-trips" $ TestCase $ do
      let rec = OwnershipCompareTrace True "event-matched:lend"
            (Just "lend") (Just "Аня") (Just "Боре") (Just "книгу")
            (Just "Entails") ["asserted:lend"]
      assertEqual "json round trip" (Just rec)
        (decode (encode rec) :: Maybe OwnershipCompareTrace)
  , TestLabel "ownership row JSON round-trips short keys" $ TestCase $ do
      content <- BL.readFile "data/semantic_ir/ownership.jsonl"
      let rows = [ r | line <- BL.split 10 content
                     , not (BL.null line)
                     , Just r <- [Aeson.decode line :: Maybe FileOwnershipRow] ]
      assertEqual "8 library rows" 8 (length rows)
      mapM_ (\row -> assertEqual ("row round trip: " <> T.unpack (foId row))
               (Just row) (decode (encode row) :: Maybe FileOwnershipRow)) rows
  ]
