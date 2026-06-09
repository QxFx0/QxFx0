{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

{-| In-process PGF linearization via the @pgf2@ Haskell library.
    Replaces the old out-of-process @gf -run@ CLI bridge.

    COMPAT GLUE: astToGfExpr uses old target ClaimAst constructors
    (MoveDefine, MoveGround, etc.) to avoid changing Types.ClaimAst.

    F-11: parseClaimAstGf / gfExprToClaimAst implement the reverse
    direction: rendered text → GF Expr → ClaimAst, using PGF.parse.
-}
module QxFx0.Runtime.PGF
  ( astToGfExpr
  , linearizeClaimAstGf
  , linearizeClaimAstGfLang
  , dialogAtomsToGfExpr
  , linearizeDialogAtomsGf
  , linearizeDialogAtomsGfLang
  , parseClaimAstGf
  , parseClaimAstGfLang
  , gfExprToClaimAst
  ) where

import Control.Exception (try, IOException)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Map.Strict as Map
import System.Directory (doesFileExist)
import System.IO.Error (isDoesNotExistError)
import System.IO.Unsafe (unsafePerformIO)
import Data.IORef (IORef, newIORef, readIORef, modifyIORef')
import qualified PGF2 as PGF
import Data.Bits (xor)
import Data.Word (Word64)
import Numeric (showHex)

import QxFx0.Types (ArtifactManifest(..), AssemblyPath(..), AuthorityClass(..), ClaimAst(..), GfActTopic(..), GfLinearizationResult(..), GfMechanism(..), GfModifier(..), GfNP(..), GfNumber(..), GfRelation(..), GfVP(..), MorphologyData(..))
import QxFx0.ExceptionPolicy (PGFError(..))
import QxFx0.Types.Decision.Enums.Render (RenderStyle(..))
import QxFx0.Runtime.GF.Map (lookupTopicGfLexemeId, buildGfLexemeMap)
import qualified QxFx0.Lexicon.GfMap as LegacyGfMap
import QxFx0.Lexicon.GfMap (gfMapProvenanceTag)
import QxFx0.Semantic.DialogAtom (DialogAtoms, daTopicNominative, hasTag, headAtomValue, AtomTag(..))
import QxFx0.Semantic.Input.Lexicon (inputGeneratedLexiconProvenanceTag)
import QxFx0.Render.Dialogue (linearizeClaimAstRus)
import QxFx0.Semantic.Lexicon.RuntimeParadigms (emptyRuntimeParadigms)

defaultPgfPath :: FilePath
defaultPgfPath = "spec/gf/QxFx0Syntax.pgf"

-- P1-1: session-scoped PGF cache keyed by path. 'PGF.readPGF' reads a 312KB
-- binary on every call; without this it ran once per linearize/parse per turn
-- (~3GB I/O over 10k turns). Pattern mirrors 'PGFStatus.pgfLoadResult'
-- (unsafePerformIO + NOINLINE). The IORef holds a path->PGF map populated
-- lazily on first use of each path.
pgfCacheRef :: IORef (Map.Map FilePath PGF.PGF)
pgfCacheRef = unsafePerformIO (newIORef Map.empty)
{-# NOINLINE pgfCacheRef #-}

-- | Load a PGF for the given path, caching the result. Subsequent calls for
--   the same path return the cached grammar without touching disk.
cachedReadPGF :: FilePath -> IO PGF.PGF
cachedReadPGF pgfPath = do
  cache <- readIORef pgfCacheRef
  case Map.lookup pgfPath cache of
    Just pgf -> pure pgf
    Nothing -> do
      pgf <- PGF.readPGF pgfPath
      modifyIORef' pgfCacheRef (Map.insert pgfPath pgf)
      pure pgf

-- COMPAT GLUE: Old target wiring expects 2-arg interface (no explicit language).
-- We default to the Russian concrete syntax shipped in the repo.
linearizeClaimAstGf :: Maybe FilePath -> ClaimAst -> IO (Either Text GfLinearizationResult)
linearizeClaimAstGf mPgfPath ast = linearizeClaimAstGfLang mPgfPath "QxFx0SyntaxRus" ast

linearizeClaimAstGfLang :: Maybe FilePath -> Text -> ClaimAst -> IO (Either Text GfLinearizationResult)
linearizeClaimAstGfLang mPgfPath lang ast
  -- P0-1 (variant A): for Russian the Haskell renderer 'linearizeClaimAstRus'
  -- is the sole authoritative path. Compute it directly instead of running
  -- PGF.linearize and discarding the result. PGF is consulted only as an
  -- emergency fallback when the Haskell renderer yields nothing (<0.1%).
  | lang == "QxFx0SyntaxRus" =
      case linearizeClaimAstRus emptyRuntimeParadigms ast StyleStandard emptyMorphologyData of
        Just text ->
          pure (Right (mkGfLinearizationResult mPgfPath lang RussianCompatShimRoute AuthorityShim (Just "russian_haskell_authoritative") text (artifactManifestFor mPgfPath lang RussianCompatShimRoute AuthorityShim text)))
        Nothing ->
          case astToGfExpr ast of
            Left err -> pure (Left err)
            Right expr -> do
              result <- linearizeExpr mPgfPath lang expr
              pure $ case result of
                Left pgfErr -> Left (renderPGFError pgfErr)
                Right raw ->
                  Right (mkGfLinearizationResult mPgfPath lang RussianCompatShimRoute AuthorityShim (Just "russian_gf_emergency_fallback") raw (artifactManifestFor mPgfPath lang RussianCompatShimRoute AuthorityShim raw))
  | otherwise =
      case astToGfExpr ast of
        Left err -> pure (Left err)
        Right expr -> do
          result <- linearizeExpr mPgfPath lang expr
          pure $ case result of
            Left pgfErr -> Left (renderPGFError pgfErr)
            Right raw ->
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
        Left pgfErr -> Left (renderPGFError pgfErr)
        Right raw
          | lang == "QxFx0SyntaxRus" ->
              Right (mkGfLinearizationResult mPgfPath lang RussianCompatShimRoute AuthorityShim (Just "russian_compatibility_shim") raw (artifactManifestFor mPgfPath lang RussianCompatShimRoute AuthorityShim raw))
          | otherwise ->
              Right (mkGfLinearizationResult mPgfPath lang PgfAtomsRoute AuthorityCanonical Nothing raw (artifactManifestFor mPgfPath lang PgfAtomsRoute AuthorityCanonical raw))

linearizeExpr :: Maybe FilePath -> Text -> Text -> IO (Either PGFError Text)
linearizeExpr mPgfPath lang expr = do
  let pgfPath = fromMaybe defaultPgfPath mPgfPath
  exists <- doesFileExist pgfPath
  if not exists
    then pure (Left (PGFFileNotFound pgfPath))
    else do
      result <- try @IOException $ do
        pgf <- cachedReadPGF pgfPath
        let langs = PGF.languages pgf
        case Map.lookup (T.unpack lang) langs of
          Nothing -> pure (Left (PGFParseError ("pgf_lang_not_found:" <> lang <> ":available=" <> T.pack (show (Map.keys langs)))))
          Just concr -> case PGF.readExpr (T.unpack expr) of
            Nothing -> pure (Left (PGFParseError ("pgf_parse_expr_failed:" <> expr)))
            Just pgfExpr ->
              let raw = T.pack (PGF.linearize concr pgfExpr)
              in pure (Right raw)
      case result of
        Left e ->
          if isDoesNotExistError e
            then pure (Left (PGFFileNotFound pgfPath))
            else pure (Left (PGFIOError e))
        Right r -> pure r

-- | Convert PGFError to Text for backward compatibility with existing error handling
renderPGFError :: PGFError -> Text
renderPGFError (PGFFileNotFound path) = "pgf_file_not_found:" <> T.pack path
renderPGFError (PGFParseError msg) = "pgf_parse_error:" <> msg
renderPGFError (PGFLinearizationError msg) = "pgf_linearization_error:" <> msg
renderPGFError (PGFIOError e) = "pgf_io_error:" <> T.pack (show e)

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
    , amPgfSourceManifestHash = Just "gf_source_manifest:gf2"
    , amGeneratedInputLexiconHash = Just (inputGeneratedLexiconProvenanceTag <> ":required")
    , amGfMapHash = Just (gfMapProvenanceTag <> ":required")
    , amToolchainIdentity = Just "gf-compiler:pgf2"
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
    MoveActOnTopic act ->
      Right ("MoveActOnTopic " <> gfActTopicExpr act)
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

gfActTopicExpr :: GfActTopic -> Text
gfActTopicExpr ActAnswer    = "ActAnswer"
gfActTopicExpr ActQuestion  = "ActQuestion"
gfActTopicExpr ActTopicTerm = "ActTopicTerm"
gfActTopicExpr ActProject   = "ActProject"
gfActTopicExpr ActResult    = "ActResult"

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

-- ---------------------------------------------------------------------------
-- F-11: Bidirectional GF parsing — text → Expr → ClaimAst
-- ---------------------------------------------------------------------------

-- | Parse a natural-language surface string back to a 'ClaimAst' using the
-- in-process PGF2 parser. Uses the same @spec\/gf\/QxFx0Syntax.pgf@ grammar
-- as the linearizer so that the full round-trip
-- @ast → linearize → parse → ast@ is closed.
--
-- Returns @Left err@ on any parse failure; the caller should fall back to
-- the pattern-matching parser in 'QxFx0.Render.Authority'.
parseClaimAstGf :: Maybe FilePath -> Text -> IO (Either Text ClaimAst)
parseClaimAstGf mPgfPath = parseClaimAstGfLang mPgfPath "QxFx0SyntaxRus"

parseClaimAstGfLang :: Maybe FilePath -> Text -> Text -> IO (Either Text ClaimAst)
parseClaimAstGfLang mPgfPath lang surface = do
  let pgfPath = fromMaybe defaultPgfPath mPgfPath
  exists <- doesFileExist pgfPath
  if not exists
    then pure (Left ("pgf_missing:" <> T.pack pgfPath))
    else do
      result <- try $ do
        pgf <- cachedReadPGF pgfPath
        let langs = PGF.languages pgf
        case Map.lookup (T.unpack lang) langs of
          Nothing ->
            pure (Left ("pgf_lang_not_found:" <> lang))
          Just concr ->
            let startType = PGF.startCat pgf          -- "Move" in QxFx0Syntax
                parseOut  = PGF.parse concr startType (T.unpack surface)
            in case parseOut of
                 PGF.ParseOk ((expr, _) : _) ->
                   pure (gfExprToClaimAst (T.pack (PGF.showExpr [] expr)))
                 PGF.ParseOk [] ->
                   pure (Left "pgf_parse_empty_result")
                 PGF.ParseFailed _ msg ->
                   pure (Left ("pgf_parse_failed:" <> T.pack msg))
                 PGF.ParseIncomplete ->
                   pure (Left "pgf_parse_incomplete")
      case result of
        Left (e :: IOException) ->
          pure (Left ("pgf_exception:" <> T.pack (show e)))
        Right r -> pure r

-- | Convert a GF abstract syntax expression string (as produced by
-- @PGF.showExpr []@) back to a 'ClaimAst'. This is the exact inverse of
-- 'astToGfExpr' — each case matches the string produced by the forward pass.
--
-- Returns @Left "no_claimart_mapping:..."@ for expressions with unrecognised
-- structure. Two known asymmetries with the forward pass:
--   * 'GfRelation'/'GfMechanism' currently have a single inhabitant
--     (RelIdentity/MechParse), so MoveDefine/MoveCause reverse-parse them as
--     constants. Extending those types requires extending the parser here.
--   * 'StanceWrapped' forward-accepts any label; reverse only recognises
--     "ApplyStanceTentative"/"ApplyStanceFirm". Other labels do not round-trip.
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


