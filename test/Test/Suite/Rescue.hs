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
      assertBool "no line decorates; all re-take"
        (all ("переформулирую" `T.isInfixOf`)
          [renderRescueLine r | r <- [RescueTautology, RescueDefaultLexeme, RescueEmptyCompose]])

  , TestLabel "rescue tags are stable trace tokens" $ TestCase $ do
      assertEqual "tautology tag" "tautology" (rescueTag RescueTautology)
      assertEqual "lexeme tag" "default_lexeme" (rescueTag RescueDefaultLexeme)
      assertEqual "compose tag" "empty_compose" (rescueTag RescueEmptyCompose)
  ]
