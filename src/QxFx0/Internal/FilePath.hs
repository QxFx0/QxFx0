module QxFx0.Internal.FilePath
  ( isPathWithin
  ) where

import System.FilePath (normalise, splitDirectories)
import Data.List (isPrefixOf)

isPathWithin :: FilePath -> FilePath -> Bool
isPathWithin root candidate =
  let rootParts = splitDirectories (normalise root)
      pathParts = splitDirectories (normalise candidate)
  in rootParts `isPrefixOf` pathParts
