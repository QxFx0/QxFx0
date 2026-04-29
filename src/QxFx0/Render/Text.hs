{-# LANGUAGE OverloadedStrings #-}
module QxFx0.Render.Text
  ( finalizeForce
  , ensureQuestion
  , ensureSentence
  , lowerFirst
  , stripStancePrefix
  , fmtPct
  , textShow
  ) where

import Data.Char (toLower)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import QxFx0.Types.Text
  ( ensureQuestion
  , ensureSentence
  , finalizeForce
  , fmtPct
  , textShow
  )

lowerFirst :: Text -> Text
lowerFirst t = case T.uncons t of
  Just (c, rest) -> T.cons (toLower c) rest
  Nothing        -> t

stripStancePrefix :: Text -> Text
stripStancePrefix t =
  let prefixes = ["\1088\1077\1092\1083\1077\1082\1089\1080\1103:", "\1091\1090\1086\1095\1085\1077\1085\1080\1077:", "\1086\1087\1088\1077\1076\1077\1083\1077\1085\1080\1077:", "\1087\1086\1076\1090\1074\1077\1088\1078\1077\1085\1086:", "\1082\1086\1085\1090\1072\1082\1090:", "\1103\1082\1086\1088\1100:"]
  in foldl (\acc p -> fromMaybe acc (T.stripPrefix p acc)) t prefixes
