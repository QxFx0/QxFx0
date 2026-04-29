{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.CLI.Parser
  ( RuntimeOutputMode(..)
  , WorkerCommand(..)
  , decodeWorkerCommand
  , parseWorkerArgs
  , parseMode
  , parseJsonStringArray
  , extractSessionArgs
  ) where

import Data.Char (isHexDigit, digitToInt, chr)
import Data.Text (Text)
import qualified Data.Text as T
import Text.ParserCombinators.ReadP
  ( ReadP
  , readP_to_S
  , char
  , satisfy
  , many
  , sepBy
  , skipSpaces
  , eof
  , (<++)
  )
import Text.Read (readMaybe)

data RuntimeOutputMode = DialogueMode | SemanticIntrospectionMode
  deriving stock (Eq, Show)

data WorkerCommand
  = WorkerShutdown
  | WorkerPing
  | WorkerHealth !Text
  | WorkerState !Text
  | WorkerTurn !Text !RuntimeOutputMode !Text
  deriving stock (Eq, Show)

decodeWorkerCommand :: Text -> Either Text WorkerCommand
decodeWorkerCommand line =
  case parseJsonStringArray line of
    Just values -> parseWorkerArgs values
    Nothing ->
      case readMaybe (T.unpack line) :: Maybe [String] of
        Just legacy -> parseWorkerArgs (map T.pack legacy)
        Nothing -> Left "Malformed worker command: expected JSON array command"

parseWorkerArgs :: [Text] -> Either Text WorkerCommand
parseWorkerArgs values =
  case values of
    ["shutdown"] -> Right WorkerShutdown
    ["ping"] -> Right WorkerPing
    ["health", sid] -> Right (WorkerHealth sid)
    ["state", sid] -> Right (WorkerState sid)
    ["turn", sid, modeTxt, inputTxt] ->
      case parseMode modeTxt of
        Right mode -> Right (WorkerTurn sid mode inputTxt)
        Left err -> Left err
    _ -> Left "Malformed worker command: unsupported shape"

parseMode :: Text -> Either Text RuntimeOutputMode
parseMode modeTxt =
  case T.toLower (T.strip modeTxt) of
    "semantic" -> Right SemanticIntrospectionMode
    "dialogue" -> Right DialogueMode
    other -> Left ("Unsupported worker mode: " <> other)

parseJsonStringArray :: Text -> Maybe [Text]
parseJsonStringArray raw =
  case readP_to_S parser (T.unpack raw) of
    [] -> Nothing
    xs -> case [values | (values, rest) <- xs, null rest] of
            [] -> Nothing
            (c:_) -> Just c
  where
    parser = skipSpaces *> jsonStringArrayP <* skipSpaces <* eof

jsonStringArrayP :: ReadP [Text]
jsonStringArrayP = do
  _ <- char '['
  skipSpaces
  values <- jsonStringP `sepBy` jsonCommaP
  skipSpaces
  _ <- char ']'
  pure values

jsonCommaP :: ReadP ()
jsonCommaP = skipSpaces *> char ',' *> skipSpaces

jsonStringP :: ReadP Text
jsonStringP = do
  _ <- char '"'
  chars <- many jsonStringCharP
  _ <- char '"'
  pure (T.pack chars)

jsonStringCharP :: ReadP Char
jsonStringCharP = escaped <++ plain
  where
    plain = satisfy (\c -> c /= '"' && c /= '\\' && c >= ' ')
    escaped = char '\\' *> parseEscape
    parseEscape =
      (char '"' >> pure '"')
      <++ (char '\\' >> pure '\\')
      <++ (char '/' >> pure '/')
      <++ (char 'b' >> pure '\b')
      <++ (char 'f' >> pure '\f')
      <++ (char 'n' >> pure '\n')
      <++ (char 'r' >> pure '\r')
      <++ (char 't' >> pure '\t')
      <++ parseUnicodeEscape
    parseUnicodeEscape = do
      _ <- char 'u'
      a <- hexDigitP
      b <- hexDigitP
      c <- hexDigitP
      d <- hexDigitP
      pure (chr ((((a * 16) + b) * 16 + c) * 16 + d))
    hexDigitP = digitToInt <$> satisfy isHexDigit

extractSessionArgs :: Text -> [String] -> (Text, [String])
extractSessionArgs defaultSid args = case args of
  ("--session-id":sid:rest) | not (null sid) -> (T.pack sid, rest)
  ("--session":sid:rest) | not (null sid)     -> (T.pack sid, rest)
  _ -> (defaultSid, args)
