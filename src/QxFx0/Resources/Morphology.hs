{-# LANGUAGE OverloadedStrings #-}

{-| Morphology resource loading and validation.

    The canonical runtime morphology substrate is the compact checked-in pair
    @resources/morphology/paradigms.json@ plus @resources/morphology/exceptions.json@.
    From these we derive the legacy 'MorphologyData' view in memory, avoiding the
    need to ship or depend on the generated 131 MB @forms_by_surface.json@ blob.

    This is a backwards-compatible shim: the exported 'MorphologyData' has the
    same shape as before, so existing consumers (inflection, resolution, GF
    morphology, learning, etc.) continue to work without changes.
-}
module QxFx0.Resources.Morphology
  ( loadMorphologyData
  , validateMorphologyResources
  , clearFormsCache  -- for testing; no-op because there is no mutable cache
  , morphologyDataFromParadigms  -- exported for testing / incremental migration
  ) where

import qualified Data.Aeson as Aeson
import qualified Data.ByteString as BS
import qualified Data.Map.Strict as M
import Data.Text (Text)
import qualified Data.Text as T
import QxFx0.ExceptionPolicy
  ( catchIO
  , mkRuntimeInitError
  , throwQxFx0
  )
import QxFx0.Resources.Paths (getMorphologyDir)
import QxFx0.Semantic.Lexicon.RuntimeParadigms (RuntimeParadigms(..))
import QxFx0.Types
  ( LexemeCase(..)
  , LexemeForm(..)
  , LexemeNumber(..)
  , MorphologyData(..)
  , SourceTier(AutoVerifiedTier)
  )
import QxFx0.Types.Lexicon.RuntimeParadigms
  ( ParadigmEntry(..)
  , PartOfSpeech(..)
  , partOfSpeechText
  )
import System.Directory (canonicalizePath, doesDirectoryExist)
import System.FilePath ((</>))

-- | Clear the derived morphology cache (for testing only).
--
-- There is no longer a mutable in-memory cache because the substrate is now
-- derived from the compact checked-in paradigms. This function is kept as a
-- no-op so callers that clear the cache between tests do not need to change.
clearFormsCache :: IO ()
clearFormsCache = pure ()

loadMorphologyData :: IO MorphologyData
loadMorphologyData = do
  mDirRaw <- getMorphologyDir
  mDir <- canonicalizePath mDirRaw
  rp <- loadRuntimeParadigmsFromDir mDir
  pure (morphologyDataFromParadigms rp)

validateMorphologyResources :: FilePath -> IO (Bool, String)
validateMorphologyResources morphDir = do
  hasMorphDir <- doesDirectoryExist morphDir
  if not hasMorphDir
    then pure (False, "Morphology directory missing: " ++ morphDir)
    else do
      paradigms <- readParadigmsMap (morphDir </> "paradigms.json")
      exceptions <- readParadigmsMap (morphDir </> "exceptions.json")
      let problems = [err | Left err <- [paradigms, exceptions]]
      pure $
        if null problems
          then (True, "Morphology resources validated")
          else (False, unwordsWith "; " problems)

loadRuntimeParadigmsFromDir :: FilePath -> IO RuntimeParadigms
loadRuntimeParadigmsFromDir dir = do
  paradigms <- loadParadigmsMap (dir </> "paradigms.json")
  exceptions <- loadParadigmsMap (dir </> "exceptions.json")
  pure RuntimeParadigms { rpMap = paradigms, rpExceptions = exceptions }

loadParadigmsMap :: FilePath -> IO (M.Map Text ParadigmEntry)
loadParadigmsMap path = do
  result <- readParadigmsMap path
  case result of
    Right mp -> pure mp
    Left err -> throwMorphologyError err

readParadigmsMap :: FilePath -> IO (Either String (M.Map Text ParadigmEntry))
readParadigmsMap path = do
  contentResult <- catchIO (Right <$> BS.readFile path) (\_ -> pure (Left ("Morphology file missing or unreadable: " ++ path)))
  case contentResult of
    Left err -> pure (Left err)
    Right content ->
      case Aeson.eitherDecodeStrict content of
        Right parsed -> pure (Right parsed)
        Left err -> pure (Left ("Morphology JSON parse failed for " ++ path ++ ": " ++ err))

-- | Derive a legacy 'MorphologyData' view from compact 'RuntimeParadigms'.
--
-- The result is semantically equivalent to the old checked-in/generated JSON
-- files:
--
-- * 'mdNominative' is a broad surface -> lemma reverse index over every stored
--   form.
-- * 'mdGenitive' and 'mdPrepositional' map a nominative surface to the
--   corresponding genitive / prepositional form in the same number.
-- * 'mdFormsBySurface' is the full form inventory.
--
-- Nouns get accurate case/number tags; non-noun keys that do not match the
-- known noun case/number pattern are defaulted to nominative singular, which
-- matches the behaviour of the previous generated @forms_by_surface.json@.
morphologyDataFromParadigms :: RuntimeParadigms -> MorphologyData
morphologyDataFromParadigms rp =
  MorphologyData
    { mdPrepositional = nomSurfaceToCase PrepositionalCase
    , mdGenitive      = nomSurfaceToCase GenitiveCase
    , mdNominative    = allSurfaceToLemma
    , mdFormsBySurface = formsBySurface
    }
  where
    allEntries = M.toList (rpMap rp) ++ M.toList (rpExceptions rp)

    allSurfaceToLemma =
      M.fromList
        [ (surface, lemma)
        | (lemma, entry) <- allEntries
        , (_, surface) <- M.toList (peForms entry)
        ]

    nomSurfaceToCase targetCase =
      M.fromList
        [ (nomSurface, targetSurface)
        | (lemma, entry) <- allEntries
        , pePos entry == PosNoun
        , let formByKey = M.fromList
                [ (parseParadigmKey key, surface)
                | (key, surface) <- M.toList (peForms entry)
                ]
        , ((NominativeCase, number), nomSurface) <- M.toList formByKey
        , Just targetSurface <- [M.lookup (targetCase, number) formByKey]
        ]

    formsBySurface =
      M.fromListWith (++)
        [ (surface, [LexemeForm surface lemma posText caseTag numberTag AutoVerifiedTier 1.0])
        | (lemma, entry) <- allEntries
        , let posText = partOfSpeechText (pePos entry)
        , (key, surface) <- M.toList (peForms entry)
        , let (caseTag, numberTag) = parseParadigmKey key
        ]

-- | Parse a paradigm form key into a case/number pair. Known noun keys are
-- "NomSg", "GenPl", etc. Other keys (verbs, adjectives, fixed expressions)
-- default to nominative/singular, which is what the previous generated
-- @forms_by_surface.json@ used for non-noun entries.
parseParadigmKey :: Text -> (LexemeCase, LexemeNumber)
parseParadigmKey key =
  let (number, maybeCasePrefix) = extractNumber key
      caseTag = maybe NominativeCase parseCasePrefix maybeCasePrefix
  in (caseTag, number)
  where
    extractNumber k
      | "Sg" `T.isSuffixOf` k = (SingularNumber, stripSuffix "Sg" k)
      | "Pl" `T.isSuffixOf` k = (PluralNumber, stripSuffix "Pl" k)
      | otherwise = (SingularNumber, Just k)

    stripSuffix suffix k
      | suffix `T.isSuffixOf` k = Just (T.dropEnd (T.length suffix) k)
      | otherwise = Just k

    parseCasePrefix p =
      case p of
        _ | "Nom" `T.isSuffixOf` p -> NominativeCase
          | "Gen" `T.isSuffixOf` p -> GenitiveCase
          | "Dat" `T.isSuffixOf` p -> DativeCase
          | "Acc" `T.isSuffixOf` p -> AccusativeCase
          | "Ins" `T.isSuffixOf` p -> InstrumentalCase
          | "Loc" `T.isSuffixOf` p -> PrepositionalCase
          | otherwise -> NominativeCase

unwordsWith :: String -> [String] -> String
unwordsWith _ [] = ""
unwordsWith sep (x:xs) = go x xs
  where
    go acc [] = acc
    go acc (y:ys) = go (acc ++ sep ++ y) ys

throwMorphologyError :: String -> IO a
throwMorphologyError msg = throwQxFx0 $ mkRuntimeInitError "Morphology" "resource_load" "MORPHOLOGY_ERROR" (M.singleton "message" (T.pack msg))
