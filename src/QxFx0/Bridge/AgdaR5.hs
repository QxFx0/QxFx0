{-# LANGUAGE DerivingStrategies, OverloadedStrings, ScopedTypeVariables #-}
{-# LANGUAGE StrictData #-}
module QxFx0.Bridge.AgdaR5
  ( agdaTypeCheck
  , verifyAgainstSnapshot
  , verifyR5WithAgda
  , AgdaVerificationResult(..)
  ) where

import QxFx0.Types (CanonicalMoveFamily(..), forceForFamily, clauseFormForIF, layerForFamily, warrantedForFamily)
import QxFx0.Resources (resolveResourcePaths, rpAgdaSpec, rpAgdaSnapshot)
import QxFx0.Types.Thresholds (agdaTypecheckTimeoutMsDefault)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Text.IO as TIO
import System.Environment (lookupEnv)
import System.Process (CreateProcess(cwd), proc, readCreateProcessWithExitCode)
import System.Exit (ExitCode(..))
import System.FilePath (takeDirectory, takeFileName)
import System.Timeout (timeout)
import QxFx0.ExceptionPolicy (catchIO)
import Data.Maybe (catMaybes)
import Text.Read (readMaybe)

data AgdaVerificationResult
  = AgdaPass
  | AgdaTypeCheckFailed !Text
  | AgdaNotAvailable !Text
  | AgdaSnapshotMismatch ![(Text, Text)]
  deriving stock (Eq, Show)

agdaTypeCheck :: IO AgdaVerificationResult
agdaTypeCheck = do
  paths <- resolveResourcePaths
  let agdaFile = rpAgdaSpec paths
      agdaDir = takeDirectory agdaFile
      agdaModule = takeFileName agdaFile
  timeoutMicros <- resolveAgdaTimeoutMicros
  result <- catchIO
    (do mProcessResult <- timeout timeoutMicros
          (readCreateProcessWithExitCode (proc "agda" [agdaModule]) { cwd = Just agdaDir } "")
        case mProcessResult of
          Nothing ->
            return
              (AgdaTypeCheckFailed
                ( "agda typecheck timed out after "
                    <> T.pack (show (timeoutMicros `div` 1000))
                    <> "ms"
                ))
          Just (exitCode, _stdout, stderr) ->
            case exitCode of
              ExitSuccess -> return AgdaPass
              ExitFailure code
                | code == 127 -> return (AgdaNotAvailable "agda not found in PATH")
                | otherwise -> return (AgdaTypeCheckFailed $ T.pack stderr))
    (\e -> return (AgdaNotAvailable $ "agda exception: " <> T.pack (show e)))
  return result

resolveAgdaTimeoutMicros :: IO Int
resolveAgdaTimeoutMicros = do
  mConfigured <- lookupEnv "QXFX0_AGDA_TIMEOUT_MS"
  let timeoutMs =
        case mConfigured >>= readMaybe of
          Just ms | ms > 0 -> ms
          _ -> agdaTypecheckTimeoutMsDefault
  pure (timeoutMs * 1000)

verifyAgainstSnapshot :: FilePath -> IO AgdaVerificationResult
verifyAgainstSnapshot snapshotPath = do
  contents <- catchIO (TIO.readFile snapshotPath)
    (\e -> return $ "ERROR: " <> T.pack (show e))
  if T.isPrefixOf "ERROR:" contents
    then return $ AgdaNotAvailable $ "cannot read snapshot: " <> contents
    else do
      let rows = filter (not . T.null) $ T.lines contents
          mismatches = catMaybes $ map checkRow rows
      if null mismatches
        then return AgdaPass
        else return $ AgdaSnapshotMismatch mismatches
  where
    checkRow :: Text -> Maybe (Text, Text)
    checkRow line =
      let fields = T.splitOn "\t" line
      in case fields of
        ("family":_) -> Nothing
        (famStr:forceStr:thirdStr:fourthStr:rest) ->
          (case parseFamily famStr of
            Left err -> Just (famStr, err)
            Right fam ->
              let expectedForce = T.pack (show (forceForFamily fam))
                  expectedClause = T.pack (show (clauseFormForIF (forceForFamily fam)))
                  expectedLayer = T.pack (show (layerForFamily fam))
                  expectedWarranted = T.pack (show (warrantedForFamily fam))
                  layerNames = ["ContentLayer", "MetaLayer", "ContactLayer"]
              in case (thirdStr, fourthStr, rest) of
                   (clauseStr, layerStr, warrantedStr:_)
                     | clauseStr `elem` ["Declarative", "Interrogative", "Hortative", "Imperative"] ->
                         if forceStr == expectedForce
                              && clauseStr == expectedClause
                              && layerStr == expectedLayer
                              && warrantedStr == expectedWarranted
                           then Nothing
                           else Just
                             ( famStr
                             , "expected(" <> T.intercalate "/" [expectedForce, expectedClause, expectedLayer, expectedWarranted]
                                 <> ") got(" <> T.intercalate "/" [forceStr, clauseStr, layerStr, warrantedStr] <> ")"
                             )
                   (layerStr, warrantedStr, _)
                     | layerStr `elem` layerNames ->
                         if forceStr == expectedForce
                              && layerStr == expectedLayer
                              && warrantedStr == expectedWarranted
                           then Nothing
                           else Just
                             ( famStr
                             , "expected(" <> T.intercalate "/" [expectedForce, expectedLayer, expectedWarranted]
                                 <> ") got(" <> T.intercalate "/" [forceStr, layerStr, warrantedStr] <> ")"
                             )
                   _ -> Just (famStr, "unrecognized snapshot row format: " <> line))
        [famStr] -> Just (famStr, "malformed snapshot row (too few fields): " <> line)
        (_:_)    -> Just ("<unknown>", "malformed snapshot row (too few fields): " <> line)
        [] -> Nothing

    parseFamily :: Text -> Either Text CanonicalMoveFamily
    parseFamily txt = case readMaybe (T.unpack txt) of
      Just fam -> Right fam
      Nothing  -> Left ("unrecognized_family: " <> txt)

verifyR5WithAgda :: IO AgdaVerificationResult
verifyR5WithAgda = do
  paths <- resolveResourcePaths
  let snapshotPath = rpAgdaSnapshot paths
  typeResult <- agdaTypeCheck
  case typeResult of
    AgdaPass -> verifyAgainstSnapshot snapshotPath
    other -> return other
