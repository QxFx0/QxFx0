{-| Suite-name filtering for the HUnit mains.

Lets operators re-run a slice of a large suite without rebuilding
or re-running everything:

  QXFX0_FAST_SUITE=crisis         run every suite whose name contains "crisis"
  QXFX0_UNIT_SUITE=guard,admission  comma-separated, case-insensitive

With the variable unset or empty the run is byte-identical to the
unfiltered one (flat concatenation, same order, same counts).
An unknown filter fails loudly (lists available suites) instead of
passing zero tests.
-}
module Test.Support.SuiteFilter
  ( selectSuites
  ) where

import Data.Char (isSpace, toLower)
import Data.List (intercalate, isInfixOf, nub)
import System.Environment (lookupEnv)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)
import Test.HUnit (Test (..))

-- | Resolve the suite selection for one test binary.
selectSuites :: String -> [(String, [Test])] -> IO Test
selectSuites envName suites = do
  mRaw <- lookupEnv envName
  let wants = case mRaw of
        Nothing -> []
        Just raw -> filter (not . null) (map (map toLower . trim) (splitComma raw))
  case wants of
    [] -> pure (TestList (concatMap snd suites))
    _ -> do
      let hit w = [n | (n, _) <- suites, w `isInfixOf` map toLower n]
          unknown = filter (null . hit) wants
      if not (null unknown)
        then do
          hPutStrLn stderr ("Unknown " ++ envName ++ " suite filter(s): " ++ intercalate "," unknown)
          hPutStrLn stderr ("Available suites: " ++ intercalate "," (map fst suites))
          exitFailure
        else do
          let picked = nub [n | w <- wants, n <- hit w]
              chosen = [(n, t) | (n, t) <- suites, n `elem` picked]
          hPutStrLn stderr ("[" ++ envName ++ "] running " ++ show (length chosen) ++ " of " ++ show (length suites) ++ " suites: " ++ intercalate "," (map fst chosen))
          pure (TestList [TestLabel n (TestList t) | (n, t) <- chosen])

splitComma :: String -> [String]
splitComma s = case break (== ',') s of
  (w, []) -> [w]
  (w, _ : rest) -> w : splitComma rest

trim :: String -> String
trim = reverse . dropWhile isSpace . reverse . dropWhile isSpace
