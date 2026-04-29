{-# LANGUAGE OverloadedStrings #-}

{-| Morphology resource loading and validation. -}
module QxFx0.Resources.Morphology
  ( loadMorphologyData
  , validateMorphologyResources
  ) where

import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as BL
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import QxFx0.ExceptionPolicy
  ( QxFx0Exception(RuntimeInitError)
  , throwQxFx0
  )
import QxFx0.Resources.Paths (getMorphologyDir)
import QxFx0.Types (MorphologyData(..), LexemeForm(..))
import System.Directory (canonicalizePath, doesDirectoryExist, doesFileExist)
import System.FilePath ((</>))
import System.IO.Unsafe (unsafePerformIO)
import Control.Concurrent.MVar (MVar, newMVar, modifyMVar)

{-# NOINLINE morphologyCache #-}
morphologyCache :: MVar (Map.Map FilePath MorphologyData)
morphologyCache = unsafePerformIO (newMVar Map.empty)

loadMorphologyData :: IO MorphologyData
loadMorphologyData = do
  mDirRaw <- getMorphologyDir
  mDir <- canonicalizePath mDirRaw
  modifyMVar morphologyCache $ \cache ->
    case Map.lookup mDir cache of
      Just md -> pure (cache, md)
      Nothing -> do
        prep <- loadMorphologyDict (mDir </> "prepositional.json")
        gen <- loadMorphologyDict (mDir </> "genitive.json")
        nom <- loadMorphologyDict (mDir </> "nominative.json")
        forms <- loadFormsBySurface (mDir </> "forms_by_surface.json")
        _ <- loadJsonValueStrict (mDir </> "lexicon_quality.json")
        let md = MorphologyData prep gen nom forms
        pure (Map.insert mDir md cache, md)

validateMorphologyResources :: FilePath -> IO (Bool, String)
validateMorphologyResources morphDir = do
  hasMorphDir <- doesDirectoryExist morphDir
  if not hasMorphDir
    then pure (False, "Morphology directory missing: " ++ morphDir)
    else do
      prep <- readMorphologyDict (morphDir </> "prepositional.json")
      gen <- readMorphologyDict (morphDir </> "genitive.json")
      nom <- readMorphologyDict (morphDir </> "nominative.json")
      -- forms_by_surface.json can be very large (>100 MB); validate
      -- presence only to keep readiness checks fast. Full parsing is
      -- deferred to loadMorphologyData at runtime.
      formsExist <- doesFileExist (morphDir </> "forms_by_surface.json")
      let forms = if formsExist then Right Map.empty else Left "forms_by_surface.json missing"
      quality <- loadJsonValueChecked (morphDir </> "lexicon_quality.json")
      let problems =
            [err | Left err <- [prep, gen, nom]]
              ++ either (:[]) (const []) forms
              ++ either (:[]) (const []) quality
      pure $
        if null problems
          then (True, "Morphology resources validated (forms_by_surface deferred to runtime)")
          else (False, unwordsWith "; " problems)

loadMorphologyDict :: FilePath -> IO (Map.Map Text Text)
loadMorphologyDict path = do
  result <- readMorphologyDict path
  case result of
    Right parsed -> pure parsed
    Left err -> throwMorphologyError err

readMorphologyDict :: FilePath -> IO (Either String (Map.Map Text Text))
readMorphologyDict path = do
  exists <- doesFileExist path
  if not exists
    then pure (Left ("Morphology file missing: " ++ path))
    else do
      content <- BL.readFile path
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
  exists <- doesFileExist path
  if not exists
    then pure (Left ("JSON resource missing: " ++ path))
    else do
      content <- BL.readFile path
      case Aeson.eitherDecode content of
        Right parsed -> pure (Right parsed)
        Left err -> pure (Left ("JSON parse failed for " ++ path ++ ": " ++ err))

loadFormsBySurface :: FilePath -> IO (Map.Map Text [LexemeForm])
loadFormsBySurface path = do
  result <- readFormsBySurface path
  case result of
    Right parsed -> pure parsed
    Left err -> throwMorphologyError err

readFormsBySurface :: FilePath -> IO (Either String (Map.Map Text [LexemeForm]))
readFormsBySurface path = do
  exists <- doesFileExist path
  if not exists
    then pure (Right Map.empty)
    else do
      content <- BL.readFile path
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
throwMorphologyError = throwQxFx0 . RuntimeInitError . T.pack
