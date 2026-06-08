{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE BangPatterns #-}

{-| Morphology resource loading and validation.

    forms_by_surface.json (131 MB) is loaded lazily and cached on first
    access to avoid paying the memory cost at startup when morphology
    is not needed (e.g. health checks, readiness probes).
-}
module QxFx0.Resources.Morphology
  ( loadMorphologyData
  , validateMorphologyResources
  , clearFormsCache  -- for testing
  ) where

import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as BL
import Data.IORef
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import QxFx0.ExceptionPolicy
  ( QxFx0Exception(RuntimeInitError)
  , catchIO
  , mkRuntimeInitError
  , throwQxFx0
  )
import QxFx0.Resources.Paths (getMorphologyDir)
import QxFx0.Types (MorphologyData(..), LexemeForm(..))
import System.Directory (canonicalizePath, doesDirectoryExist, doesFileExist)
import System.FilePath ((</>))
import System.IO.Unsafe (unsafePerformIO)

-- | Cached forms_by_surface data. Loaded on first access, then reused.
{-# NOINLINE cachedFormsBySurface #-}
cachedFormsBySurface :: IORef (Maybe (Map.Map Text [LexemeForm]))
cachedFormsBySurface = unsafePerformIO (newIORef Nothing)

-- | Clear the forms cache (for testing only).
clearFormsCache :: IO ()
clearFormsCache = writeIORef cachedFormsBySurface Nothing

loadMorphologyData :: IO MorphologyData
loadMorphologyData = do
  mDirRaw <- getMorphologyDir
  mDir <- canonicalizePath mDirRaw
  prep <- loadMorphologyDict (mDir </> "prepositional.json")
  gen <- loadMorphologyDict (mDir </> "genitive.json")
  nom <- loadMorphologyDict (mDir </> "nominative.json")
  forms <- loadFormsBySurfaceCached (mDir </> "forms_by_surface.json")
  _ <- loadJsonValueStrict (mDir </> "lexicon_quality.json")
  pure (MorphologyData prep gen nom forms)

validateMorphologyResources :: FilePath -> IO (Bool, String)
validateMorphologyResources morphDir = do
  hasMorphDir <- doesDirectoryExist morphDir
  if not hasMorphDir
    then pure (False, "Morphology directory missing: " ++ morphDir)
    else do
      prep <- readMorphologyDict (morphDir </> "prepositional.json")
      gen <- readMorphologyDict (morphDir </> "genitive.json")
      nom <- readMorphologyDict (morphDir </> "nominative.json")
      forms <- readFormsBySurface (morphDir </> "forms_by_surface.json")
      quality <- loadJsonValueChecked (morphDir </> "lexicon_quality.json")
      let problems =
            [err | Left err <- [prep, gen, nom]]
              ++ either (:[]) (const []) forms
              ++ either (:[]) (const []) quality
      pure $
        if null problems
          then (True, "Morphology resources validated")
          else (False, unwordsWith "; " problems)

loadMorphologyDict :: FilePath -> IO (Map.Map Text Text)
loadMorphologyDict path = do
  result <- readMorphologyDict path
  case result of
    Right parsed -> pure parsed
    Left err -> throwMorphologyError err

readMorphologyDict :: FilePath -> IO (Either String (Map.Map Text Text))
readMorphologyDict path = do
  contentResult <- catchIO (Right <$> BL.readFile path) (\_ -> pure (Left ("Morphology file missing or unreadable: " ++ path)))
  case contentResult of
    Left err -> pure (Left err)
    Right content ->
      case Aeson.eitherDecode content of
        Right parsed -> pure (Right parsed)
        Left err -> pure (Left ("Morphology JSON parse failed for " ++ path ++ ": " ++ err))

loadJsonValueStrict :: FilePath -> IO Aeson.Value
loadJsonValueStrict path = do
  result <- loadJsonValueChecked path
  case result of
    Right value -> pure value
    Left err -> throwMorphologyError err

loadJsonValueChecked :: FilePath -> IO (Either String Aeson.Value)
loadJsonValueChecked path = do
  contentResult <- catchIO (Right <$> BL.readFile path) (\_ -> pure (Left ("JSON resource missing or unreadable: " ++ path)))
  case contentResult of
    Left err -> pure (Left err)
    Right content ->
      case Aeson.eitherDecode content of
        Right parsed -> pure (Right parsed)
        Left err -> pure (Left ("JSON parse failed for " ++ path ++ ": " ++ err))

loadFormsBySurface :: FilePath -> IO (Map.Map Text [LexemeForm])
loadFormsBySurface path = do
  result <- readFormsBySurface path
  case result of
    Right parsed -> pure parsed
    Left err -> throwMorphologyError err

-- | Lazy-loading variant: loads forms_by_surface.json on first call,
-- caches the result for subsequent calls. Saves ~131 MB at startup
-- when morphology is not immediately needed.
loadFormsBySurfaceCached :: FilePath -> IO (Map.Map Text [LexemeForm])
loadFormsBySurfaceCached path = do
  mCached <- readIORef cachedFormsBySurface
  case mCached of
    Just forms -> pure forms
    Nothing -> do
      forms <- loadFormsBySurface path
      writeIORef cachedFormsBySurface (Just forms)
      pure forms

readFormsBySurface :: FilePath -> IO (Either String (Map.Map Text [LexemeForm]))
readFormsBySurface path = do
  contentResult <- catchIO (Right <$> BL.readFile path) (\_ -> pure (Left ("forms_by_surface missing or unreadable: " ++ path)))
  case contentResult of
    Left err -> pure (Left err)
    Right content ->
      case Aeson.eitherDecode content of
        Right parsed -> pure (Right (Map.map (map enforceQuality) parsed))
        Left err -> pure (Left ("forms_by_surface JSON parse failed for " ++ path ++ ": " ++ err))
  where
    enforceQuality :: LexemeForm -> LexemeForm
    enforceQuality lf = lf { lfQuality = max 0.0 (min 1.0 (lfQuality lf)) }

unwordsWith :: String -> [String] -> String
unwordsWith _ [] = ""
unwordsWith sep (x:xs) = go x xs
  where
    go acc [] = acc
    go acc (y:ys) = go (acc ++ sep ++ y) ys

throwMorphologyError :: String -> IO a
throwMorphologyError msg = throwQxFx0 $ mkRuntimeInitError "Morphology" "resource_load" "MORPHOLOGY_ERROR" (M.singleton "message" (T.pack msg))
