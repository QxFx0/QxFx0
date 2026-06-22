{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StrictData #-}
module QxFx0.Bridge.NixGuard
  ( checkConstitution
  , getNixGuardStatus
  , nixStringLiteral
  , isSafeChar
  , normalizeConceptKey
  ) where

import QxFx0.Types (NixGuardStatus(..))
import Data.Function ((&))
import Data.Text (Text)
import qualified Data.Text as T
import System.Process (readProcessWithExitCode)
import System.Exit (ExitCode(..))
import System.Environment (lookupEnv)
import System.FilePath (takeDirectory)
import QxFx0.ExceptionPolicy (catchIO)
import Data.Char (isAlphaNum, isAscii, isLetter)
import Data.Maybe (fromMaybe)

isSafeChar :: Char -> Bool
isSafeChar c = isAscii c && (isAlphaNum c || c == '-' || c == '_')
           || (not (isAscii c) && isLetter c)

nixStringLiteral :: Text -> Text
nixStringLiteral t =
  let escaped =
        t
          & T.replace "\\" "\\\\"
          & T.replace "\n" "\\n"
          & T.replace "\r" "\\r"
          & T.replace "\t" "\\t"
          & T.replace "\"" "\\\""
          & T.replace "${" "\\${"
  in "\"" <> escaped <> "\""

checkConstitution :: FilePath -> Text -> Double -> Double -> IO NixGuardStatus
checkConstitution nixPath concept agency tension =
  case normalizeConceptKey concept of
    Nothing
      | T.null (T.strip concept) -> return (Blocked "constitution concept is empty")
      | otherwise -> return (Blocked "constitution concept not recognized")
    Just conceptKey -> do
      -- Use --include to allow restrict-eval to import the concepts.nix file.
      -- The nix expression uses <QxFx0Concepts> to reference the file via the include path.
      let nixDir = takeDirectory nixPath
          nixExpr = "let agency = " <> T.pack (show agency)
                   <> "; tension = " <> T.pack (show tension)
                   <> "; data = import <QxFx0Concepts/concepts.nix>"
                   <> "; key = " <> nixStringLiteral conceptKey
                    <> "; match = builtins.filter (c: c.id == key) data.concepts;"
                    <> "  concept = if builtins.length match > 0 then builtins.elemAt match 0 else null;"
                    <> "  agencyOk = concept != null && (concept.minAgency == null || agency >= concept.minAgency);"
                    <> "  tensionOk = concept != null && (concept.minTension == null || tension >= concept.minTension);"
                    <> " in if concept != null then agencyOk && tensionOk else false"
      result <- runNixEvalWithInclude nixDir nixExpr
      case result of
        Right "true"  -> return Allowed
        Right "false" -> return $ Blocked $ "constitution blocked: " <> conceptKey
        Right other   -> return $ Blocked $ "constitution eval unexpected_result: " <> other
        Left err      -> return $ Blocked $ "constitution eval failed: " <> classifyNixEvalError err

getNixGuardStatus :: IO (Either Text NixGuardStatus)
getNixGuardStatus = do
  result <- runNixEval "true"
  case result of
    Right _    -> return (Right Allowed)
    Left  err  -> return (Left err)

runNixEval :: Text -> IO (Either Text Text)
runNixEval nixExpr = do
  -- Н-1: No fallback from restricted to unrestricted mode.
  -- If --restricted is unsupported, fail closed rather than downgrading security.
  runNixInstantiate True [] nixExpr

runNixEvalWithInclude :: FilePath -> Text -> IO (Either Text Text)
runNixEvalWithInclude includeDir nixExpr =
  runNixInstantiate True ["--include", "QxFx0Concepts=" <> includeDir] nixExpr

runNixInstantiate :: Bool -> [String] -> Text -> IO (Either Text Text)
runNixInstantiate restricted extraArgs nixExpr = do
  let timeoutSec :: Int
      timeoutSec = 5
      modeArgs = if restricted then ["--option", "restrict-eval", "true"] else []
      modeLabel = if restricted then "restricted" else "unrestricted"
  nixInstantiateBin <- fromMaybe "nix-instantiate" <$> lookupEnv "QXFX0_NIX_INSTANTIATE_BIN"
  result <- catchIO
    (do (exitCode, stdout, stderr) <- readProcessWithExitCode
          "timeout" ([show timeoutSec, nixInstantiateBin] <> modeArgs <> extraArgs <> ["--eval", "--expr", T.unpack nixExpr]) ""
        case exitCode of
          ExitSuccess ->
            let output = T.strip (T.pack stdout)
            in return (Right output)
          ExitFailure code
            | code == 124 -> return (Left "nix evaluation timed out")
            | otherwise   -> return (Left $ "nix-instantiate failed (" <> T.pack (show code) <> "): mode=" <> modeLabel <> ": " <> T.strip (T.pack stderr)))
    (\e -> return (Left $ "nix exception: " <> T.pack (show e)))
  return result

normalizeConceptKey :: Text -> Maybe Text
normalizeConceptKey raw =
  let normalized = T.toLower (T.strip raw)
  in if T.null normalized
       then Nothing
       else case conceptAlias normalized of
         Just alias -> Just alias
         Nothing -> if T.all isConceptChar normalized
                      then Just normalized
                      else Nothing

isConceptChar :: Char -> Bool
isConceptChar c = isSafeChar c || c == ' '

conceptAlias :: Text -> Maybe Text
conceptAlias k
  | k == "freedom" = Just "svoboda"
  | k == "will" = Just "volya"
  | k == "death" = Just "smert"
  | k == "boundary" = Just "granitsa"
  | k == "digit" = Just "cifra"
  | k == "meaning" = Just "smysl"
  | k == "truth" = Just "istina"
  | k == "love" = Just "lyubov"
  | k == "time" = Just "vremya"
  | k == "language" = Just "yazyk"
  | k == "identity" = Just "identichnost"
  | k == "repair" = Just "remont"
  | otherwise = Nothing

classifyNixEvalError :: Text -> Text
classifyNixEvalError err
  | "unrecognised flag" `T.isInfixOf` err = "unsupported_nix_flag"
  | "access to absolute path" `T.isInfixOf` err = "restricted_path_blocked"
  | "attribute" `T.isInfixOf` err && "missing" `T.isInfixOf` err = "attribute_missing"
  | "timed out" `T.isInfixOf` err = "timeout"
  | "syntax error" `T.isInfixOf` err = "syntax_error"
  | otherwise = "evaluation_failed"
