{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

module QxFx0.Semantic.Input.Normalize
  ( NormalizedInput(..)
  , normalizeInput
  ) where

import Data.Char (isAlphaNum)
import Data.Text (Text)
import qualified Data.Text as T

data NormalizedInput = NormalizedInput
  { niRawText :: !Text
  , niNormalizedText :: !Text
  , niTokens :: ![Text]
  , niIsQuestion :: !Bool
  } deriving stock (Eq, Show)

normalizeInput :: Text -> NormalizedInput
normalizeInput rawText =
  let stripped = T.strip rawText
      lower = T.toLower stripped
      normalized = normalizeOrthography lower
      tokens =
        filter (not . T.null)
          (map trimToken (T.words (T.map normalizeChar normalized)))
      isQuestion = T.isSuffixOf "?" stripped || isQuestionByCue tokens
  in NormalizedInput
       { niRawText = rawText
       , niNormalizedText = normalized
       , niTokens = tokens
       , niIsQuestion = isQuestion
       }

isQuestionByCue :: [Text] -> Bool
isQuestionByCue [] = False
isQuestionByCue (firstToken:rest) =
  firstToken `elem`
    [ "что", "кто", "где", "когда", "почему", "зачем", "как"
    , "какой", "какая", "какое", "каков", "какова", "каковы"
    , "чем", "сколько", "ли", "чей", "чья", "чье", "чьё"
    ]
  || [firstToken, secondToken] `elem` [["для", "чего"], ["в", "чем"], ["в", "чём"]]
  where
    secondToken =
      case rest of
        [] -> ""
        (x:_) -> x

normalizeOrthography :: Text -> Text
normalizeOrthography = T.replace "ё" "е"

normalizeChar :: Char -> Char
normalizeChar c
  | isAlphaNum c = c
  | c == '-' = c
  | otherwise = ' '

trimToken :: Text -> Text
trimToken = T.dropAround (\c -> not (isAlphaNum c) && c /= '-')
