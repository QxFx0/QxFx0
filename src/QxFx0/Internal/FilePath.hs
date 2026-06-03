module QxFx0.Internal.FilePath
  ( isPathWithin
  ) where

import Data.List (isPrefixOf)
import System.Directory (canonicalizePath)
import System.FilePath (splitDirectories, addTrailingPathSeparator)

isPathWithin :: FilePath -> FilePath -> IO Bool
isPathWithin root candidate = do
  canonicalRoot <- canonicalizePath root
  canonicalCandidate <- canonicalizePath candidate
  let rootParts = splitDirectories (addTrailingPathSeparator canonicalRoot)
      pathParts = splitDirectories canonicalCandidate
  pure (rootParts `isPrefixOf` pathParts)
