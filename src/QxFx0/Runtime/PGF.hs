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
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Map.Strict as Map
import System.Directory (doesFileExist)
import qualified PGF2 as PGF
import Data.Bits (xor)
import Data.Word (Word64)
import Numeric (showHex)

import QxFx0.Types (ArtifactManifest(..), AssemblyPath(..), AuthorityClass(..), ClaimAst(..), GfLinearizationResult(..), GfMechanism(..), GfModifier(..), GfNP(..), GfNumber(..), GfRelation(..), GfVP(..), MorphologyData(..))
import QxFx0.Types.Decision.Enums.Render (RenderStyle(..))
import QxFx0.Runtime.GF.Map (lookupTopicGfLexemeId, buildGfLexemeMap)
import qualified QxFx0.Lexicon.GfMap as LegacyGfMap
import QxFx0.Lexicon.GfMap (gfMapProvenanceTag)
import QxFx0.Semantic.DialogAtom (DialogAtoms, daTopicNominative, hasTag, headAtomValue, AtomTag(..))
import QxFx0.Semantic.Input.Lexicon (inputGeneratedLexiconProvenanceTag)
import QxFx0.Render.Dialogue (linearizeClaimAstRus)

defaultPgfPath :: FilePath
defaultPgfPath = "spec/gf/QxFx0Syntax.pgf"

-- COMPAT GLUE: Old target wiring expects 2-arg interface (no explicit language).
-- We default to the Russian concrete syntax shipped in the repo.
linearizeClaimAstGf :: Maybe FilePath -> ClaimAst -> IO (Either Text GfLinearizationResult)
linearizeClaimAstGf mPgfPath ast = linearizeClaimAstGfLang mPgfPath "QxFx0SyntaxRus" ast

linearizeClaimAstGfLang :: Maybe FilePath -> Text -> ClaimAst -> IO (Either Text GfLinearizationResult)
linearizeClaimAstGfLang mPgfPath lang ast =
  case astToGfExpr ast of
    Left err -> pure (Left err)
    Right expr -> do
      result <- linearizeExpr mPgfPath lang expr
      pure $ case result of
        Left err -> Left err
        Right raw
          | lang == "QxFx0SyntaxRus" ->
              Right (mkGfLinearizationResult mPgfPath lang RussianCompatShimRoute AuthorityShim (Just "russian_compatibility_shim") (fallbackSurfaceText ast raw) (artifactManifestFor mPgfPath lang RussianCompatShimRoute AuthorityShim (fallbackSurfaceText ast raw)))
          | otherwise ->
              Right (mkGfLinearizationResult mPgfPath lang PgfClaimRoute AuthorityCanonical Nothing raw (artifactManifestFor mPgfPath lang PgfClaimRoute AuthorityCanonical raw))

linearizeDialogAtomsGf :: Maybe FilePath -> DialogAtoms -> IO (Either Text GfLinearizationResult)
linearizeDialogAtomsGf mPgfPath da = linearizeDialogAtomsGfLang mPgfPath "QxFx0SyntaxRus" da

linearizeDialogAtomsGfLang :: Maybe FilePath -> Text -> DialogAtoms -> IO (Either Text GfLinearizationResult)
linearizeDialogAtomsGfLang mPgfPath lang da =
  case dialogAtomsToGfExpr da of
    Left err -> pure (Left err)
    Right expr -> do
      result <- linearizeExpr mPgfPath lang expr
      pure $ case result of
        Left err -> Left err
        Right raw
          | lang == "QxFx0SyntaxRus" ->
              Right (mkGfLinearizationResult mPgfPath lang RussianCompatShimRoute AuthorityShim (Just "russian_compatibility_shim") raw (artifactManifestFor mPgfPath lang RussianCompatShimRoute AuthorityShim raw))
          | otherwise ->
              Right (mkGfLinearizationResult mPgfPath lang PgfAtomsRoute AuthorityCanonical Nothing raw (artifactManifestFor mPgfPath lang PgfAtomsRoute AuthorityCanonical raw))

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

fallbackSurface :: ClaimAst -> Either Text Text
fallbackSurface ast =
  maybe (Left "pgf_russian_fallback_failed:shim_route") Right (linearizeClaimAstRus ast StyleStandard emptyMorphologyData)

fallbackSurfaceText :: ClaimAst -> Text -> Text
fallbackSurfaceText ast fallbackText =
  maybe fallbackText id (linearizeClaimAstRus ast StyleStandard emptyMorphologyData)

mkGfLinearizationResult :: Maybe FilePath -> Text -> AssemblyPath -> AuthorityClass -> Maybe Text -> Text -> ArtifactManifest -> GfLinearizationResult
mkGfLinearizationResult mPgfPath lang assemblyPath authorityClass fallbackReason text manifest =
  GfLinearizationResult
    { glrText = text
    , glrLanguage = lang
    , glrAuthorityClass = authorityClass
    , glrAssemblyPath = assemblyPath
    , glrArtifactManifest = manifest { amPgfPath = mPgfPath }
    , glrFallbackReason = fallbackReason
    }

artifactManifestFor :: Maybe FilePath -> Text -> AssemblyPath -> AuthorityClass -> Text -> ArtifactManifest
artifactManifestFor mPgfPath lang assemblyPath authorityClass text =
  ArtifactManifest
    { amPgfPath = mPgfPath
    , amPgfHash = Just (fingerprintText (T.pack (show mPgfPath) <> "|" <> lang <> "|" <> T.pack (show assemblyPath) <> "|" <> T.pack (show authorityClass) <> "|" <> text <> "|toolchain=pgf2"))
    , amGeneratedInputLexiconHash = Just (inputGeneratedLexiconProvenanceTag <> ":required")
    , amGfMapHash = Just (gfMapProvenanceTag <> ":required")
    , amToolchainMarker = "runtime_pgf;lang=" <> lang <> ";route=" <> T.pack (show assemblyPath) <> ";authority=" <> T.pack (show authorityClass) <> ";compiler=pgf2"
    }

fingerprintText :: Text -> Text
fingerprintText = T.pack . ("fnv1a64:" ++) . (`showHex` "") . T.foldl' fnv1a64 14695981039346656037
  where
    fnv1a64 :: Word64 -> Char -> Word64
    fnv1a64 h ch = (h `xor` fromIntegral (fromEnum ch)) * 1099511628211

emptyMorphologyData :: MorphologyData
emptyMorphologyData = MorphologyData mempty mempty mempty mempty

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
      Right ("MovePurpose (MkNP " <> fst (sanitizeLegacyLexemeDecision subject) <> ")")
    ClaimSelfState ->
      Right "MoveSelfState"
    ClaimComparison left right ->
      Right
        ( "MoveCompare (MkNP "
            <> sanitizeLegacyLexemeId left
            <> legacyShimSuffix left
            <> ") (MkNP "
            <> sanitizeLegacyLexemeId right
            <> legacyShimSuffix right
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
      intent = if hasTag TUserIntent da then headAtomValue TUserIntent da else ""
  in case lookupTopicGfLexemeId buildGfLexemeMap topicStr of
       Nothing -> Left ("unresolved_topic_lexeme:" <> topicStr)
       Just gfTopic ->
         if intent == "define"
           then Right ("MoveDefine (MkNP " <> gfTopic <> ") (MkNP " <> gfTopic <> ")")
           else if intent == "ground"
             then Right ("MoveGround (MkNP " <> gfTopic <> ")")
             else Right ("MoveGround (MkNP " <> gfTopic <> ")")

sanitizeLegacyLexemeId :: Text -> Text
sanitizeLegacyLexemeId = LegacyGfMap.topicToGfLexemeId

sanitizeLegacyLexemeDecision :: Text -> (Text, Maybe Text)
sanitizeLegacyLexemeDecision = LegacyGfMap.topicToGfLexemeDecision

legacyShimSuffix :: Text -> Text
legacyShimSuffix raw =
  case sanitizeLegacyLexemeDecision raw of
    (_, Just _) -> ""
    _ -> ""
