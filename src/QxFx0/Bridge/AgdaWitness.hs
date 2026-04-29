{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Bridge.AgdaWitness
  ( AgdaWitnessReport(..)
  , resolveAgdaWitnessPath
  , readAgdaWitnessReport
  , writeAgdaWitness
  , verifyAgdaWitnessFresh
  ) where

import QxFx0.Bridge.AgdaR5
  ( AgdaVerificationResult(..)
  , verifyR5WithAgda
  )
import QxFx0.ExceptionPolicy (QxFx0Exception(RuntimeInitError), throwQxFx0)
import QxFx0.Resources
  ( ResourcePaths(..)
  , resolveResourcePaths
  )
import QxFx0.Types.Readiness
  ( AgdaVerificationStatus(..)
  , agdaVerificationReady
  )

import Data.Aeson (FromJSON, ToJSON, eitherDecode, encode)
import qualified Crypto.Hash.SHA256 as SHA256
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BL
import qualified Data.Map.Strict as Map
import Data.List (sortOn)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Word (Word8)
import GHC.Generics (Generic)
import Numeric (showHex)
import System.Directory (createDirectoryIfMissing, doesFileExist)
import System.Environment (lookupEnv)
import System.FilePath ((</>), normalise, takeDirectory)

data AgdaWitness = AgdaWitness
  { awVersion :: !Int
  , awFiles   :: !(Map.Map Text Text)
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

data AgdaWitnessReport = AgdaWitnessReport
  { awrPath   :: !FilePath
  , awrStatus :: !AgdaVerificationStatus
  , awrFresh  :: !Bool
  , awrIssues :: ![Text]
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

witnessVersion :: Int
witnessVersion = 1

resolveAgdaWitnessPath :: IO FilePath
resolveAgdaWitnessPath = do
  mExplicit <- lookupEnv "QXFX0_AGDA_WITNESS"
  case fmap normalise mExplicit of
    Just path -> pure path
    Nothing -> do
      stateDir <- resolveQxFx0StateDir
      pure (stateDir </> "agda-witness.json")

writeAgdaWitness :: IO FilePath
writeAgdaWitness = do
  verifyResult <- verifyR5WithAgda
  case verifyResult of
    AgdaPass -> do
      paths <- resolveResourcePaths
      hashes <- currentWitnessHashes paths
      witnessPath <- resolveAgdaWitnessPath
      createDirectoryIfMissing True (takeDirectory witnessPath)
      BL.writeFile witnessPath (encode AgdaWitness { awVersion = witnessVersion, awFiles = hashes })
      pure witnessPath
    other ->
      throwQxFx0 (RuntimeInitError ("Cannot write Agda witness: " <> T.pack (renderAgdaFailure other)))

verifyAgdaWitnessFresh :: IO Bool
verifyAgdaWitnessFresh = awrFresh <$> readAgdaWitnessReport

readAgdaWitnessReport :: IO AgdaWitnessReport
readAgdaWitnessReport = do
  witnessPath <- resolveAgdaWitnessPath
  witnessExists <- doesFileExist witnessPath
  if not witnessExists
    then pure AgdaWitnessReport
      { awrPath = witnessPath
      , awrStatus = AgdaMissingWitness
      , awrFresh = False
      , awrIssues = ["missing_witness"]
      }
    else do
      body <- BL.readFile witnessPath
      case eitherDecode body of
        Left err ->
          pure AgdaWitnessReport
            { awrPath = witnessPath
            , awrStatus = AgdaDecodeFailed
            , awrFresh = False
            , awrIssues = ["decode_failed:" <> T.pack err]
            }
        Right witness
          | awVersion witness /= witnessVersion ->
              pure AgdaWitnessReport
                { awrPath = witnessPath
                , awrStatus = AgdaVersionMismatch
                , awrFresh = False
                , awrIssues =
                    [ "version_mismatch:expected="
                        <> T.pack (show witnessVersion)
                        <> ",got="
                        <> T.pack (show (awVersion witness))
                    ]
                }
          | otherwise -> do
              paths <- resolveResourcePaths
              currentHashes <- currentWitnessHashes paths
              let issues = compareWitnessHashes (awFiles witness) currentHashes
                  status =
                    if null issues
                      then AgdaVerified
                      else classifyAgdaIssues issues
              pure AgdaWitnessReport
                { awrPath = witnessPath
                , awrStatus = status
                , awrFresh = agdaVerificationReady status
                , awrIssues = issues
                }

classifyAgdaIssues :: [Text] -> AgdaVerificationStatus
classifyAgdaIssues issues
  | any (== "missing_witness") issues = AgdaMissingWitness
  | any (T.isPrefixOf "decode_failed:") issues = AgdaDecodeFailed
  | any (T.isPrefixOf "version_mismatch:") issues = AgdaVersionMismatch
  | any (T.isPrefixOf "missing_input:") issues = AgdaMissingInput
  | any (T.isPrefixOf "hash_mismatch:") issues = AgdaHashMismatch
  | any (T.isPrefixOf "unexpected_input:") issues = AgdaUnexpectedInput
  | otherwise = AgdaInvalid

resolveQxFx0StateDir :: IO FilePath
resolveQxFx0StateDir = do
  mStateDir <- lookupEnv "QXFX0_STATE_DIR"
  case fmap normalise mStateDir of
    Just dir -> pure dir
    Nothing -> do
      mXdgStateHome <- lookupEnv "XDG_STATE_HOME"
      mHome <- lookupEnv "HOME"
      pure $
        case fmap normalise mXdgStateHome of
          Just xdgStateHome -> xdgStateHome </> "qxfx0"
          Nothing -> fromMaybe "." ((</> ".local/state/qxfx0") . normalise <$> mHome)

currentWitnessHashes :: ResourcePaths -> IO (Map.Map Text Text)
currentWitnessHashes paths = do
  hashedEntries <- mapM hashWitnessInput (witnessInputs paths)
  pure (Map.fromList hashedEntries)

witnessInputs :: ResourcePaths -> [(Text, FilePath)]
witnessInputs paths =
  let root = rpResourceDir paths
      specDir = takeDirectory (rpAgdaSpec paths)
      specLabel file = T.pack ("spec" </> file)
  in sortOn fst
      [ (specLabel "R5Core.agda", rpAgdaSpec paths)
      , (specLabel "Sovereignty.agda", specDir </> "Sovereignty.agda")
      , (specLabel "Legitimacy.agda", specDir </> "Legitimacy.agda")
      , (specLabel "LexiconContract.agda", specDir </> "LexiconContract.agda")
      , (specLabel "LexiconData.agda", specDir </> "LexiconData.agda")
      , (specLabel "LexiconProof.agda", specDir </> "LexiconProof.agda")
      , (specLabel "r5-snapshot.tsv", rpAgdaSnapshot paths)
      , ("src/QxFx0/Types/Domain.hs", root </> "src" </> "QxFx0" </> "Types" </> "Domain.hs")
      ]

hashWitnessInput :: (Text, FilePath) -> IO (Text, Text)
hashWitnessInput (label, path) = do
  exists <- doesFileExist path
  if not exists
    then throwQxFx0 (RuntimeInitError ("Witness input missing: " <> T.pack path))
    else do
      contents <- BL.readFile path
      pure (label, hashBytes contents)

hashBytes :: BL.ByteString -> Text
hashBytes bytes =
  T.pack . concatMap byteToHex . BS.unpack $ SHA256.hashlazy bytes

byteToHex :: Word8 -> String
byteToHex byte =
  let raw = showHex byte ""
  in if length raw == 1 then '0' : raw else raw

compareWitnessHashes :: Map.Map Text Text -> Map.Map Text Text -> [Text]
compareWitnessHashes recorded current =
  missingIssues ++ mismatchIssues ++ unexpectedIssues
  where
    missingIssues =
      [ "missing_input:" <> label
      | label <- Map.keys current
      , Map.notMember label recorded
      ]
    mismatchIssues =
      [ "hash_mismatch:" <> label
      | (label, currentHash) <- Map.toList current
      , Just recordedHash <- [Map.lookup label recorded]
      , recordedHash /= currentHash
      ]
    unexpectedIssues =
      [ "unexpected_input:" <> label
      | label <- Map.keys recorded
      , Map.notMember label current
      ]

renderAgdaFailure :: AgdaVerificationResult -> String
renderAgdaFailure AgdaPass = "unexpected success state"
renderAgdaFailure (AgdaTypeCheckFailed detail) = T.unpack detail
renderAgdaFailure (AgdaNotAvailable detail) = T.unpack detail
renderAgdaFailure (AgdaSnapshotMismatch mismatches) =
  "snapshot mismatch: "
    <> T.unpack
      (T.intercalate "; " [T.pack (show fam) <> " -> " <> detail | (fam, detail) <- mismatches])
