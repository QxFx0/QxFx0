{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

{-| In-process PGF linearization via the @pgf2@ Haskell library.
    Replaces the old out-of-process @gf -run@ CLI bridge.

    COMPAT GLUE: astToGfExpr uses old target ClaimAst constructors
    (MoveDefine, MoveGround, etc.) to avoid changing Types.ClaimAst.
-}
module QxFx0.Runtime.PGF
  ( astToGfExpr
  , linearizeClaimAstGf
  , linearizeClaimAstGfLang
  , dialogAtomsToGfExpr
  , linearizeDialogAtomsGf
  , linearizeDialogAtomsGfLang
  ) where

import Control.Exception (try, SomeException)
import Data.Char (isSpace)
import Data.Maybe (fromMaybe, listToMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Map.Strict as Map
import System.Directory (doesFileExist)
import qualified PGF2 as PGF

import QxFx0.Types (ClaimAst(..), GfMechanism(..), GfModifier(..), GfNP(..), GfNumber(..), GfRelation(..), GfVP(..))
import QxFx0.Runtime.GF.Map (topicToGfLexemeId, buildGfLexemeMap)
import qualified QxFx0.Lexicon.GfMap as LegacyGfMap
import QxFx0.Semantic.DialogAtom (DialogAtoms, daTopicNominative, hasTag, headAtomValue, AtomTag(..))

defaultPgfPath :: FilePath
defaultPgfPath = "spec/gf/QxFx0Syntax.pgf"

-- COMPAT GLUE: Old target wiring expects 2-arg interface (no explicit language).
-- We default to the Russian concrete syntax shipped in the repo.
linearizeClaimAstGf :: Maybe FilePath -> ClaimAst -> IO (Either Text Text)
linearizeClaimAstGf mPgfPath ast = linearizeClaimAstGfLang mPgfPath "QxFx0SyntaxRus" ast

linearizeClaimAstGfLang :: Maybe FilePath -> Text -> ClaimAst -> IO (Either Text Text)
linearizeClaimAstGfLang mPgfPath lang ast =
  case astToGfExpr ast of
    Left err -> pure (Left err)
    Right expr -> linearizeExpr mPgfPath lang expr

linearizeDialogAtomsGf :: Maybe FilePath -> DialogAtoms -> IO (Either Text Text)
linearizeDialogAtomsGf mPgfPath da = linearizeDialogAtomsGfLang mPgfPath "QxFx0SyntaxRus" da

linearizeDialogAtomsGfLang :: Maybe FilePath -> Text -> DialogAtoms -> IO (Either Text Text)
linearizeDialogAtomsGfLang mPgfPath lang da =
  case dialogAtomsToGfExpr da of
    Left err -> pure (Left err)
    Right expr -> linearizeExpr mPgfPath lang expr

linearizeExpr :: Maybe FilePath -> Text -> Text -> IO (Either Text Text)
linearizeExpr mPgfPath lang expr = do
  let pgfPath = fromMaybe defaultPgfPath mPgfPath
  exists <- doesFileExist pgfPath
  if not exists
    then pure (Left ("pgf_missing:" <> T.pack pgfPath))
    else do
      result <- try $ do
        pgf <- PGF.readPGF pgfPath
        let langs = PGF.languages pgf
        case Map.lookup (T.unpack lang) langs of
          Nothing -> pure (Left ("pgf_lang_not_found:" <> lang <> ":available=" <> T.pack (show (Map.keys langs))))
          Just concr -> case PGF.readExpr (T.unpack expr) of
            Nothing -> pure (Left ("pgf_parse_expr_failed:" <> expr))
            Just pgfExpr ->
              let raw = T.pack (PGF.linearize concr pgfExpr)
              in pure (Right raw)
      case result of
        Left (e :: SomeException) -> pure (Left ("pgf_exception:" <> T.pack (show e)))
        Right r -> pure r

astToGfExpr :: ClaimAst -> Either Text Text
astToGfExpr ast =
  case ast of
    MoveInvite (MkNP topic) modifier action ->
      do
        actionExpr <- gfActionExpr action
        Right ("MoveInvite (MkNP " <> topic <> ") " <> gfModifierExpr modifier <> " " <> actionExpr)
    MoveDefine (MkNP subj) rel (MkNP obj) ->
      Right ("MoveDefine (MkNP " <> subj <> ") " <> gfRelationExpr rel <> " (MkNP " <> obj <> ")")
    MoveCause (MkNP subj) mech ->
      Right ("MoveCause (MkNP " <> subj <> ") " <> gfMechanismExpr mech)
    MovePurpose (MkNP topic) ->
      Right ("MovePurpose (MkNP " <> topic <> ")")
    MoveSelfState ->
      Right "MoveSelfState"
    MoveCompare (MkNP left) (MkNP right) ->
      Right ("MoveCompare (MkNP " <> left <> ") (MkNP " <> right <> ")")
    MoveOperationalStatus ->
      Right "MoveOperationalStatus"
    MoveOperationalCause ->
      Right "MoveOperationalCause"
    MoveSystemLogic ->
      Right "MoveSystemLogic"
    MoveMisunderstanding ->
      Right "MoveMisunderstanding"
    MoveGenerativeThought ->
      Right "MoveGenerativeThought"
    MoveContemplative (MkNP topic) ->
      Right ("MoveContemplative (MkNP " <> topic <> ")")
    MoveGround (MkNP topic) ->
      Right ("MoveGround (MkNP " <> topic <> ")")
    MoveContact (MkNP topic) ->
      Right ("MoveContact (MkNP " <> topic <> ")")
    MoveReflect (MkNP topic) ->
      Right ("MoveReflect (MkNP " <> topic <> ")")
    MoveDescribe (MkNP topic) ->
      Right ("MoveDescribe (MkNP " <> topic <> ")")
    MoveDeepen (MkNP topic) ->
      Right ("MoveDeepen (MkNP " <> topic <> ")")
    MoveConfront (MkNP topic) ->
      Right ("MoveConfront (MkNP " <> topic <> ")")
    MoveAnchor (MkNP topic) ->
      Right ("MoveAnchor (MkNP " <> topic <> ")")
    MoveClarify (MkNP topic) ->
      Right ("MoveClarify (MkNP " <> topic <> ")")
    MoveNextStepLocal (MkNP topic) ->
      Right ("MoveNextStepLocal (MkNP " <> topic <> ")")
    MoveHypothesis (MkNP topic) ->
      Right ("MoveHypothesis (MkNP " <> topic <> ")")
    MoveDistinguish (MkNP left) (MkNP right) ->
      Right ("MoveDistinguish (MkNP " <> left <> ") (MkNP " <> right <> ")")
    StanceWrapped "ApplyStanceTentative" inner ->
      ("ApplyStanceTentative (" <>) . (<> ")") <$> astToGfExpr inner
    StanceWrapped "ApplyStanceFirm" inner ->
      ("ApplyStanceFirm (" <>) . (<> ")") <$> astToGfExpr inner
    StanceWrapped _ inner ->
      astToGfExpr inner
    ClaimPurpose subject ->
      Right ("MovePurpose (MkNP " <> sanitizeLegacyLexemeId subject <> ")")
    ClaimSelfState ->
      Right "MoveSelfState"
    ClaimComparison left right ->
      Right
        ( "MoveCompare (MkNP "
            <> sanitizeLegacyLexemeId left
            <> ") (MkNP "
            <> sanitizeLegacyLexemeId right
            <> ")"
        )

gfModifierExpr :: GfModifier -> Text
gfModifierExpr ModFirst = "ModFirst"
gfModifierExpr ModStrictly = "ModStrictly"

gfRelationExpr :: GfRelation -> Text
gfRelationExpr RelIdentity = "RelIdentity"

gfMechanismExpr :: GfMechanism -> Text
gfMechanismExpr MechParse = "MechParse"

gfNumberExpr :: GfNumber -> Text
gfNumberExpr NumSg = "NumSg"
gfNumberExpr NumPl = "NumPl"

gfActionExpr :: GfVP -> Either Text Text
gfActionExpr action =
  case action of
    ActMaintain number obj -> Right ("ActMaintain " <> gfNumberExpr number <> " " <> obj)
    ActDefine obj -> Right ("ActDefine " <> obj)

dialogAtomsToGfExpr :: DialogAtoms -> Either Text Text
dialogAtomsToGfExpr da =
  let topicStr = daTopicNominative da
      gfTopic = topicToGfLexemeId buildGfLexemeMap topicStr
      intent = if hasTag TUserIntent da then headAtomValue TUserIntent da else ""
  in if intent == "define"
     then Right ("MoveDefine (MkNP " <> gfTopic <> ") (MkNP " <> gfTopic <> ")")
     else if intent == "ground"
     then Right ("MoveGround (MkNP " <> gfTopic <> ")")
     else Right ("MoveGround (MkNP " <> gfTopic <> ")")

sanitizeLegacyLexemeId :: Text -> Text
sanitizeLegacyLexemeId = LegacyGfMap.topicToGfLexemeId
