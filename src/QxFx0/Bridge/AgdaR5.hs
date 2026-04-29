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
import System.Process (CreateProcess(cwd), proc, readCreateProcessWithExitCode, readProcessWithExitCode)
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
  | AgdaSnapshotMismatch ![(CanonicalMoveFamily, Text)]
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
    checkRow :: Text -> Maybe (CanonicalMoveFamily, Text)
    checkRow line =
      let fields = T.splitOn "\t" line
      in case fields of
        ("family":_) -> Nothing
        (famStr:forceStr:thirdStr:fourthStr:rest) ->
          case parseFamily famStr of
            Nothing -> Nothing
            Just fam ->
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
                             ( fam
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
                             ( fam
                             , "expected(" <> T.intercalate "/" [expectedForce, expectedLayer, expectedWarranted]
                                 <> ") got(" <> T.intercalate "/" [forceStr, layerStr, warrantedStr] <> ")"
                             )
                   _ -> Just (fam, "unrecognized snapshot row: " <> line)
        _ -> Nothing

    parseFamily :: Text -> Maybe CanonicalMoveFamily
    parseFamily "CMGround"     = Just CMGround
    parseFamily "CMDefine"     = Just CMDefine
    parseFamily "CMDistinguish" = Just CMDistinguish
    parseFamily "CMReflect"    = Just CMReflect
    parseFamily "CMDescribe"   = Just CMDescribe
    parseFamily "CMPurpose"    = Just CMPurpose
    parseFamily "CMHypothesis" = Just CMHypothesis
    parseFamily "CMRepair"     = Just CMRepair
    parseFamily "CMContact"    = Just CMContact
    parseFamily "CMAnchor"     = Just CMAnchor
    parseFamily "CMClarify"    = Just CMClarify
    parseFamily "CMDeepen"     = Just CMDeepen
    parseFamily "CMConfront"   = Just CMConfront
    parseFamily "CMNextStep"   = Just CMNextStep
    parseFamily _ = Nothing

verifyR5WithAgda :: IO AgdaVerificationResult
verifyR5WithAgda = do
  paths <- resolveResourcePaths
  let snapshotPath = rpAgdaSnapshot paths
  typeResult <- agdaTypeCheck
  case typeResult of
    AgdaPass -> verifyAgainstSnapshot snapshotPath
    other -> return other
