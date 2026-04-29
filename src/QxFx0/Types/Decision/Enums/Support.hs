{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Types.Decision.Enums.Support
  ( normalizeDecisionText
  , parseTextEnum
  , withTextEnum
  ) where

import Data.Aeson (Value, withText)
import Data.Aeson.Types (Parser)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T

normalizeDecisionText :: Text -> Text
normalizeDecisionText = T.toLower . T.strip

parseTextEnum :: a -> [(Text, a)] -> Text -> a
parseTextEnum fallback table rawText =
  fromMaybe fallback (lookup (normalizeDecisionText rawText) table)

withTextEnum :: String -> (Text -> a) -> Value -> Parser a
withTextEnum label parser = withText label (pure . parser)
