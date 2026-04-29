{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Runtime.PGF
  ( astToGfExpr
  , linearizeClaimAstGf
  ) where

import Data.Char (isSpace)
import Data.Maybe (fromMaybe, listToMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import System.Directory (doesFileExist)
import System.Exit (ExitCode(..))
import System.Process (readProcessWithExitCode)

import QxFx0.Lexicon.GfMap (topicToGfLexemeId)
import QxFx0.Types (ClaimAst(..), GfMechanism(..), GfModifier(..), GfNP(..), GfNumber(..), GfRelation(..), GfVP(..))

defaultPgfPath :: FilePath
defaultPgfPath = "spec/gf/QxFx0Syntax.pgf"

linearizeClaimAstGf :: Maybe FilePath -> ClaimAst -> IO (Either Text Text)
linearizeClaimAstGf mPgfPath ast =
  case astToGfExpr ast of
    Left err -> pure (Left err)
    Right expr -> do
      let pgfPath = fromMaybe defaultPgfPath mPgfPath
      exists <- doesFileExist pgfPath
      if not exists
        then pure (Left ("pgf_missing:" <> T.pack pgfPath))
        else do
          (exitCode, stdoutText, stderrText) <-
            readProcessWithExitCode "gf" ["-run", pgfPath] (T.unpack expr <> "\n")
          case exitCode of
            ExitSuccess ->
              case extractLinearization (T.pack stdoutText) of
                Just rendered -> pure (Right rendered)
                Nothing -> pure (Left "gf_empty_output")
            ExitFailure _ ->
              let err = summarizeGfFailure (T.pack stderrText) (T.pack stdoutText)
              in pure (Left err)

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

extractLinearization :: Text -> Maybe Text
extractLinearization rawOutput =
  let linesNoEmpty = filter (not . T.null) (map T.strip (T.lines rawOutput))
      pick =
        listToMaybe
          ( reverse
              [ normalizeQuoted line
              | line <- linesNoEmpty
              , not (">" `T.isPrefixOf` line)
              ]
          )
  in pick

normalizeQuoted :: Text -> Text
normalizeQuoted line =
  case T.uncons line of
    Just ('"', rest) ->
      case T.unsnoc rest of
        Just (middle, '"') -> middle
        _ -> line
    _ -> line

summarizeGfFailure :: Text -> Text -> Text
summarizeGfFailure stderrText stdoutText =
  let stderrLine = firstUsefulLine stderrText
      stdoutLine = firstUsefulLine stdoutText
      merged =
        case (stderrLine, stdoutLine) of
          (Just e, _) -> e
          (Nothing, Just o) -> o
          _ -> "gf_failed"
  in "gf_failed:" <> merged

firstUsefulLine :: Text -> Maybe Text
firstUsefulLine =
  listToMaybe
    . filter (not . T.null)
    . map (T.take 160 . T.dropAround isSpace)
    . T.lines

sanitizeLegacyLexemeId :: Text -> Text
sanitizeLegacyLexemeId = topicToGfLexemeId
