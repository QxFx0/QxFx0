{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StrictData #-}
module QxFx0.Bridge.NixGuard
  ( checkConstitution
  , getNixGuardStatus
  , nixStringLiteral
  , isSafeChar
  ) where

import QxFx0.Types (NixGuardStatus(..))
import Data.Function ((&))
import Data.Text (Text)
import qualified Data.Text as T
import System.Process (readProcessWithExitCode)
import System.Exit (ExitCode(..))
import System.Environment (lookupEnv)
import QxFx0.ExceptionPolicy (catchIO)
import Data.Char (isAlphaNum, isAscii, isLetter)
import Data.Maybe (isJust)

isSafeChar :: Char -> Bool
isSafeChar c = isAscii c && (isAlphaNum c || c == '-' || c == '_' || c == '/')
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
      | T.null (T.strip concept) -> return Allowed
      | otherwise -> do
          lenient <- isLenientMode
          if lenient
            then return (Unavailable "constitution concept unsupported; policy check skipped")
            else return (Blocked "constitution concept unsupported")
    Just conceptKey -> do
      let nixExpr = "let agency = " <> T.pack (show agency)
                   <> "; tension = " <> T.pack (show tension)
                   <> "; data = import " <> nixStringLiteral (T.pack nixPath)
                   <> "; key = " <> nixStringLiteral conceptKey
                   <> "; match = builtins.filter (c: c.name == key) data.concepts;"
                   <> "  concept = if builtins.length match > 0 then builtins.elemAt match 0 else null;"
                   <> "  agencyOk = concept != null && (concept.minAgency == null || agency >= concept.minAgency);"
                   <> "  tensionOk = concept != null && (concept.minTension == null || tension >= concept.minTension);"
                   <> " in if concept != null then agencyOk && tensionOk else true"
      result <- runNixEval nixExpr
      case result of
        Right "true"  -> return Allowed
        Right "false" -> return $ Blocked $ "constitution blocked: " <> conceptKey
        Right other   -> return $ Unavailable $ "nix evaluator unavailable: unexpected_result:" <> other
        Left err      -> return $ Unavailable $ "nix evaluator unavailable: " <> classifyNixEvalError err

getNixGuardStatus :: IO (Either Text NixGuardStatus)
getNixGuardStatus = do
  result <- runNixEval "true"
  case result of
    Right _    -> return (Right Allowed)
    Left  err  -> return (Left err)

runNixEval :: Text -> IO (Either Text Text)
runNixEval nixExpr = do
  restrictedResult <- runNixInstantiate True nixExpr
  case restrictedResult of
    Left err
      | isRestrictedFlagUnsupported err ->
          runNixInstantiate False nixExpr
    _ ->
      pure restrictedResult

runNixInstantiate :: Bool -> Text -> IO (Either Text Text)
runNixInstantiate restricted nixExpr = do
  let timeoutSec :: Int
      timeoutSec = 5
      modeArgs = if restricted then ["--restricted"] else []
      modeLabel = if restricted then "restricted" else "unrestricted"
  result <- catchIO
    (do (exitCode, stdout, stderr) <- readProcessWithExitCode
          "timeout" ([show timeoutSec, "nix-instantiate"] <> modeArgs <> ["--eval", "--expr", T.unpack nixExpr]) ""
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
       else if T.all isConceptChar normalized
         then Just normalized
         else Nothing

isConceptChar :: Char -> Bool
isConceptChar c =
  (isAscii c && (isAlphaNum c || c == '-' || c == '_'))
    || (not (isAscii c) && isLetter c)

isLenientMode :: IO Bool
isLenientMode = do
  mEnv <- lookupEnv "QXFX0_NIXGUARD_LENIENT_UNSUPPORTED"
  return (isJust mEnv && mEnv == Just "1")

classifyNixEvalError :: Text -> Text
classifyNixEvalError err
  | isRestrictedFlagUnsupported err = "restricted_eval_unsupported"
  | "nix evaluation timed out" `T.isInfixOf` err = "timeout"
  | "nix exception:" `T.isPrefixOf` err = "process_exception"
  | "nix-instantiate failed" `T.isPrefixOf` err = "evaluation_failed"
  | otherwise = "evaluation_failed"

isRestrictedFlagUnsupported :: Text -> Bool
isRestrictedFlagUnsupported err =
  ("--restricted" `T.isInfixOf` err)
    && (("unrecognised flag" `T.isInfixOf` err) || ("unrecognized flag" `T.isInfixOf` err))
