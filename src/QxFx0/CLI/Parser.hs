{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DerivingStrategies #-}

module QxFx0.CLI.Parser
  ( RuntimeOutputMode(..)
  , WorkerCommand(..)
  , WorkerProtocolError(..)
  , workerProtocolErrorCode
  , workerProtocolErrorMessage
  , decodeWorkerMessage
  , decodeWorkerCommand
  , parseWorkerArgs
  , parseMode
  , parseJsonStringArray
  , extractSessionArgs
  ) where

import Data.Char (isHexDigit, digitToInt, chr)
import Data.Aeson (Value(..), eitherDecodeStrict')
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.KeyMap as AesonKeyMap
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Vector as V
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
  = WorkerHello !Text ![Text]
  | WorkerShutdown
  | WorkerPing
  | WorkerHealth !Text
  | WorkerState !Text
  | WorkerTurn !Text !RuntimeOutputMode !Text
  deriving stock (Eq, Show)

data WorkerProtocolError
  = WorkerMalformedCommand !Text
  | WorkerUnknownCommand !Text
  | WorkerUnsupportedWorkerMode !Text
  deriving stock (Eq, Show)

workerProtocolErrorCode :: WorkerProtocolError -> Text
workerProtocolErrorCode err = case err of
  WorkerMalformedCommand _ -> "malformed_command"
  WorkerUnknownCommand _ -> "unknown_command"
  WorkerUnsupportedWorkerMode _ -> "unsupported_output_mode"

workerProtocolErrorMessage :: WorkerProtocolError -> Text
workerProtocolErrorMessage err = case err of
  WorkerMalformedCommand detail -> detail
  WorkerUnknownCommand cmd -> "Unsupported worker command: " <> cmd
  WorkerUnsupportedWorkerMode modeTxt -> "Unsupported worker mode: " <> modeTxt

decodeWorkerMessage :: Text -> Either WorkerProtocolError WorkerCommand
decodeWorkerMessage line =
  case eitherDecodeStrict' (TE.encodeUtf8 line) of
    Right (Object obj) -> parseWorkerObject obj
    _ -> decodeWorkerArray line

decodeWorkerCommand :: Text -> Either Text WorkerCommand
decodeWorkerCommand = first workerProtocolErrorMessage . decodeWorkerMessage

decodeWorkerArray :: Text -> Either WorkerProtocolError WorkerCommand
decodeWorkerArray line =
  case parseJsonStringArray line of
    Just values -> parseWorkerArgs values
    Nothing ->
      case readMaybe (T.unpack line) :: Maybe [String] of
        Just legacy -> parseWorkerArgs (map T.pack legacy)
        Nothing -> Left (WorkerMalformedCommand "Malformed worker command: expected JSON array command or hello object")

parseWorkerObject :: AesonKeyMap.KeyMap Value -> Either WorkerProtocolError WorkerCommand
parseWorkerObject obj =
  case lookupText "command" of
    Nothing -> Left (WorkerMalformedCommand "Malformed worker command: object is missing command")
    Just "hello" ->
      case lookupText "protocol_version" of
        Nothing -> Left (WorkerMalformedCommand "Malformed hello command: missing protocol_version")
        Just version -> Right (WorkerHello version (lookupTextList "capabilities"))
    Just other -> Left (WorkerUnknownCommand other)
  where
    lookupText key =
      case AesonKeyMap.lookup (AesonKey.fromText key) obj of
        Just (String txt) -> Just txt
        _ -> Nothing
    lookupTextList key =
      case AesonKeyMap.lookup (AesonKey.fromText key) obj of
        Just (Array values) ->
          [ txt | String txt <- V.toList values ]
        _ -> []

parseWorkerArgs :: [Text] -> Either WorkerProtocolError WorkerCommand
parseWorkerArgs values =
  case values of
    ["hello", version] -> Right (WorkerHello version [])
    ["shutdown"] -> Right WorkerShutdown
    ["ping"] -> Right WorkerPing
    ["health", sid] -> Right (WorkerHealth sid)
    ["state", sid] -> Right (WorkerState sid)
    ["turn", sid, modeTxt, inputTxt] ->
      case parseMode modeTxt of
        Right mode -> Right (WorkerTurn sid mode inputTxt)
        Left err -> Left err
    command : _ -> Left (WorkerUnknownCommand command)
    [] -> Left (WorkerMalformedCommand "Malformed worker command: empty command payload")

parseMode :: Text -> Either WorkerProtocolError RuntimeOutputMode
parseMode modeTxt =
  case T.toLower (T.strip modeTxt) of
    "semantic" -> Right SemanticIntrospectionMode
    "dialogue" -> Right DialogueMode
    other -> Left (WorkerUnsupportedWorkerMode other)

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

first :: (a -> b) -> Either a c -> Either b c
first f value = case value of
  Left err -> Left (f err)
  Right ok -> Right ok
