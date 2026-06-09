{-# LANGUAGE OverloadedStrings #-}

{-| Pure parser: GF abstract-syntax expression string → 'ClaimAst'.

    This is the exact inverse of 'astToGfExpr' (in 'Runtime.PGF') —
    each case matches the string produced by the forward pass.

    Returns @Left "no_claimart_mapping:..."@ for expressions with
    unrecognised structure. Two known asymmetries with the forward pass:
      * 'GfRelation'/'GfMechanism' currently have a single inhabitant
        (RelIdentity/MechParse), so MoveDefine/MoveCause reverse-parse
        them as constants. Extending those types requires extending
        the parser here.
      * 'StanceWrapped' forward-accepts any label; reverse only
        recognises "ApplyStanceTentative"/"ApplyStanceFirm". Other
        labels do not round-trip.
-}
module QxFx0.Semantic.Authority.GfExprParse
  ( gfExprToClaimAst
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Types (ClaimAst(..), GfActTopic(..), GfMechanism(..), GfModifier(..), GfNP(..), GfNumber(..), GfRelation(..), GfVP(..))

-- | Convert a GF abstract syntax expression string (as produced by
-- @PGF.showExpr []@) back to a 'ClaimAst'.
gfExprToClaimAst :: Text -> Either Text ClaimAst
gfExprToClaimAst expr =
  let stripped = T.strip expr
  in  go stripped
  where
    go e
      -- Nullary moves
      | e == "MoveSelfState"         = Right MoveSelfState
      | e == "MoveOperationalStatus" = Right MoveOperationalStatus
      | e == "MoveOperationalCause"  = Right MoveOperationalCause
      | e == "MoveSystemLogic"       = Right MoveSystemLogic
      | e == "MoveMisunderstanding"  = Right MoveMisunderstanding
      | e == "MoveGenerativeThought" = Right MoveGenerativeThought
      -- Legacy nullary
      | e == "ClaimSelfState"        = Right ClaimSelfState

      -- Single-NP moves: "MoveXxx (MkNP topic)"
      | Just t <- stripFun1NP "MovePurpose" e       = Right (MovePurpose (MkNP t))
      | Just t <- stripFun1NP "MoveContemplative" e  = Right (MoveContemplative (MkNP t))
      | Just t <- stripFun1NP "MoveGround" e         = Right (MoveGround (MkNP t))
      | Just t <- stripFun1NP "MoveContact" e        = Right (MoveContact (MkNP t))
      | Just t <- stripFun1NP "MoveReflect" e        = Right (MoveReflect (MkNP t))
      | Just t <- stripFun1NP "MoveDescribe" e       = Right (MoveDescribe (MkNP t))
      | Just t <- stripFun1NP "MoveDeepen" e         = Right (MoveDeepen (MkNP t))
      | Just t <- stripFun1NP "MoveConfront" e       = Right (MoveConfront (MkNP t))
      | Just t <- stripFun1NP "MoveAnchor" e         = Right (MoveAnchor (MkNP t))
      | Just t <- stripFun1NP "MoveClarify" e        = Right (MoveClarify (MkNP t))
      | Just t <- stripFun1NP "MoveNextStepLocal" e  = Right (MoveNextStepLocal (MkNP t))
      | Just t <- stripFun1NP "MoveHypothesis" e     = Right (MoveHypothesis (MkNP t))
      -- Legacy single-NP
      | Just t <- stripFun1NP "ClaimPurpose" e       = Right (ClaimPurpose t)

      -- Two-NP moves: "MoveXxx (MkNP l) (MkNP r)"
      | Just (l, r) <- stripFun2NP "MoveCompare" e    = Right (MoveCompare (MkNP l) (MkNP r))
      | Just (l, r) <- stripFun2NP "MoveDistinguish" e = Right (MoveDistinguish (MkNP l) (MkNP r))
      -- Legacy two-NP
      | Just (l, r) <- stripFun2NP "ClaimComparison" e = Right (ClaimComparison l r)

      -- MoveDefine: "MoveDefine (MkNP subj) RelIdentity (MkNP obj)"
      | Just (s, o) <- stripMoveDefine e =
          Right (MoveDefine (MkNP s) RelIdentity (MkNP o))

      -- MoveCause: "MoveCause (MkNP subj) MechParse"
      | Just s <- stripMoveCause e =
          Right (MoveCause (MkNP s) MechParse)

      -- MoveInvite: "MoveInvite (MkNP topic) ModFirst ActDefine obj"
      | Just (topic, modS, actionS) <- stripMoveInvite e = do
          mod' <- parseGfModifier modS
          action <- parseGfVP actionS
          Right (MoveInvite (MkNP topic) mod' action)

      -- Stance wrapping: "ApplyStanceTentative (inner)" / "ApplyStanceFirm (inner)"
      | Just inner <- T.stripPrefix "ApplyStanceTentative (" e >>= stripTrailingParen =
          fmap (StanceWrapped "ApplyStanceTentative") (go inner)
      | Just inner <- T.stripPrefix "ApplyStanceFirm (" e >>= stripTrailingParen =
          fmap (StanceWrapped "ApplyStanceFirm") (go inner)

      -- MoveActOnTopic: "MoveActOnTopic ActXxx"
      | Just act <- stripMoveActOnTopic e = Right (MoveActOnTopic act)

      | otherwise = Left ("no_claimart_mapping:" <> T.take 60 e)

    -- Extract topic from "MoveFun (MkNP topic)"
    stripFun1NP fun e = do
      rest <- T.stripPrefix (fun <> " (MkNP ") e
      t    <- T.stripSuffix ")" rest
      guard (not (T.null t))
      pure t

    -- Extract left/right from "MoveFun (MkNP l) (MkNP r)"
    stripFun2NP fun e = do
      rest  <- T.stripPrefix (fun <> " (MkNP ") e
      -- find the closing ")  (MkNP " boundary
      let (l, tail1) = T.breakOn ") (MkNP " rest
      rest2 <- T.stripPrefix ") (MkNP " tail1
      r     <- T.stripSuffix ")" rest2
      guard (not (T.null l) && not (T.null r))
      pure (l, r)

    -- "MoveDefine (MkNP s) RelIdentity (MkNP o)"
    stripMoveDefine e = do
      rest  <- T.stripPrefix "MoveDefine (MkNP " e
      let (s, tail1) = T.breakOn ") RelIdentity (MkNP " rest
      rest2 <- T.stripPrefix ") RelIdentity (MkNP " tail1
      o     <- T.stripSuffix ")" rest2
      guard (not (T.null s) && not (T.null o))
      pure (s, o)

    -- "MoveCause (MkNP s) MechParse"
    stripMoveCause e = do
      rest <- T.stripPrefix "MoveCause (MkNP " e
      s    <- T.stripSuffix ") MechParse" rest
      guard (not (T.null s))
      pure s

    -- "MoveActOnTopic ActXxx"
    stripMoveActOnTopic e = do
      rest <- T.stripPrefix "MoveActOnTopic " e
      act <- parseGfActTopic (T.strip rest)
      pure act

    -- "MoveInvite (MkNP topic) ModXxx ActionExpr"
    stripMoveInvite e = do
      rest   <- T.stripPrefix "MoveInvite (MkNP " e
      let (topic, tail1) = T.breakOn ") " rest
      rest2  <- T.stripPrefix ") " tail1
      -- rest2 = "ModFirst ActDefine obj" etc.
      let ws = T.words rest2
      guard (length ws >= 2)
      case ws of
        (modS : restWs) -> do
          let actionS = T.unwords restWs
          guard (not (T.null topic))
          pure (topic, modS, actionS)
        _ -> Nothing

    stripTrailingParen t =
      if T.isSuffixOf ")" t then Just (T.dropEnd 1 t) else Nothing

    guard True  = Just ()
    guard False = Nothing

parseGfModifier :: Text -> Either Text GfModifier
parseGfModifier "ModFirst"   = Right ModFirst
parseGfModifier "ModStrictly" = Right ModStrictly
parseGfModifier m = Left ("unknown_modifier:" <> m)

parseGfVP :: Text -> Either Text GfVP
parseGfVP vp
  | Just rest <- T.stripPrefix "ActDefine " vp = Right (ActDefine rest)
  | Just rest <- T.stripPrefix "ActMaintain NumSg " vp = Right (ActMaintain NumSg rest)
  | Just rest <- T.stripPrefix "ActMaintain NumPl " vp = Right (ActMaintain NumPl rest)
  | otherwise = Left ("unknown_gf_vp:" <> T.take 40 vp)

parseGfActTopic :: Text -> Maybe GfActTopic
parseGfActTopic "ActAnswer"    = Just ActAnswer
parseGfActTopic "ActQuestion"  = Just ActQuestion
parseGfActTopic "ActTopicTerm" = Just ActTopicTerm
parseGfActTopic "ActProject"   = Just ActProject
parseGfActTopic "ActResult"    = Just ActResult
parseGfActTopic _              = Nothing
