{-# LANGUAGE OverloadedStrings #-}

-- | Unit tests for render-phase rescue (D2): pure cores only.
-- Wiring (detectRescue orchestration) is verified live; these pin
-- the tautology detector and the repair-line contract.
module Test.Suite.Rescue
  ( rescueTests
  ) where

import Test.HUnit
import qualified Data.Text as T

import QxFx0.Core.TurnPipeline.Route.Render
  ( RescueReason(..)
  , claimAstTautology
  , claimAstCopulaSubjectResolved
  , emptyHoldFires
  , mentionedCoveredTopics
  , renderRescueLine
  , rescueTag
  )
import QxFx0.Types.ClaimAst (ClaimAst(..), GfNP(..), GfRelation(..))

rescueTests :: [Test]
rescueTests =
  [ TestLabel "tautology detects X-is-X claims" $ TestCase $ do
      assertBool "ponyatie is ponyatie"
        (claimAstTautology (Just (MoveDefine (MkNP "ponyatie_N") RelIdentity (MkNP "ponyatie_N"))))
      assertBool "case-insensitive match"
        (claimAstTautology (Just (MoveDefine (MkNP "Свобода") RelIdentity (MkNP "свобода"))))

  , TestLabel "tautology rejects distinct and empty sides" $ TestCase $ do
      assertBool "distinct terms are not tautology"
        (not (claimAstTautology (Just (MoveDefine (MkNP "свобода") RelIdentity (MkNP "ответственность")))))

  , TestLabel "resolved-subject copula suppresses default-lexeme rescue" $ TestCase $ do
      assertBool "real subject, default object"
        (claimAstCopulaSubjectResolved (Just (MoveDefine (MkNP "otvetstvennost_N") RelIdentity (MkNP "ponyatie_N"))))
      assertBool "default subject still rescuable"
        (not (claimAstCopulaSubjectResolved (Just (MoveDefine (MkNP "ponyatie_N") RelIdentity (MkNP "ponyatie_N")))))
      assertBool "identical real lexemes owned by tautology detector"
        (not (claimAstCopulaSubjectResolved (Just (MoveDefine (MkNP "svoboda_N") RelIdentity (MkNP "svoboda_N")))))
      assertBool "non-definitional moves unaffected"
        (not (claimAstCopulaSubjectResolved (Just MoveMisunderstanding)))
      assertBool "absent claim unaffected"
        (not (claimAstCopulaSubjectResolved Nothing))
      assertBool "empty sides are not tautology"
        (not (claimAstTautology (Just (MoveDefine (MkNP "") RelIdentity (MkNP "")))))
      assertBool "Nothing is not tautology"
        (not (claimAstTautology Nothing))
      assertBool "non-define moves are not tautology"
        (not (claimAstTautology (Just (MoveGround (MkNP "свобода")))))

  , TestLabel "repair lines re-take the turn" $ TestCase $ do
      assertBool "tautology line names the failure"
        ("тавтология" `T.isInfixOf` renderRescueLine RescueTautology)
      assertBool "lexeme line asks for topic"
        ("тему" `T.isInfixOf` renderRescueLine RescueDefaultLexeme)
      assertBool "compose line asks for criterion"
        ("критерий" `T.isInfixOf` renderRescueLine RescueEmptyCompose)
      assertBool "hold line admits empty content"
        ("содержания" `T.isInfixOf` renderRescueLine RescueEmptyHold)
      assertBool "no line decorates; all re-take"
        (all ("переформулирую" `T.isInfixOf`)
          [renderRescueLine r | r <- [RescueTautology, RescueDefaultLexeme, RescueEmptyCompose, RescueEmptyHold]])

  , TestLabel "rescue tags are stable trace tokens" $ TestCase $ do
      assertEqual "tautology tag" "tautology" (rescueTag RescueTautology)
      assertEqual "lexeme tag" "default_lexeme" (rescueTag RescueDefaultLexeme)
      assertEqual "compose tag" "empty_compose" (rescueTag RescueEmptyCompose)
      assertEqual "hold tag" "empty_hold" (rescueTag RescueEmptyHold)

  , TestLabel "empty hold fires only on plan-less covered turns" $ TestCase $ do
      assertBool "covered engaged topic named, all empty"
        (emptyHoldFires ["добро"] ["добро"] True True True True)
      assertBool "verb bestTopic salvaged by named focus"
        (emptyHoldFires ["связано", "добро"] ["добро"] True True True True)
      assertBool "incidental mention without engaged match stays silent"
        (not (emptyHoldFires ["привет", "контакт"] ["время"] True True True True))
      assertBool "uncovered never fires"
        (not (emptyHoldFires ["связано"] ["связано"] True True True True))
      assertBool "a carried plan (abstain included) never fires"
        (not (emptyHoldFires ["добро"] ["добро"] False True True True))
      assertBool "an emitted predicate never fires"
        (not (emptyHoldFires ["добро"] ["добро"] True True False True))
      assertBool "a rendered claim never fires"
        (not (emptyHoldFires ["добро"] ["добро"] True False True True))
      assertBool "a selection never fires"
        (not (emptyHoldFires ["добро"] ["добро"] True True True False))

  , TestLabel "mentioned topics name the held noun" $ TestCase $ do
      assertEqual "stub hold names добро"
        ["добро"]
        (mentionedCoveredTopics "Держу добро как устойчивую опору для дальнейшего разбора.")
      assertBool "punctuation does not break the match"
        ("добро" `elem` mentionedCoveredTopics "Держу добро. Я удержу только устойчивую часть ответа.")
      assertEqual "verb bestTopic is not a topic"
        []
        (mentionedCoveredTopics "Как связано?")
      assertEqual "honest abstain names nothing covered"
        []
        (mentionedCoveredTopics "Я вижу тему, но в локальной модели нет достаточного основания для содержательного тезиса.")
  ]
