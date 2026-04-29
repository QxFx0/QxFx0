{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

module QxFx0.Bridge.Datalog.Support
  ( DatalogExecution(..)
  , createShadowTempFiles
  , renderRuntimeFacts
  , buildShadowSnapshot
  , parseShadowOutput
  , compactDiagnostic
  ) where

import Data.List (nub, sort)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import QxFx0.ExceptionPolicy (catchIO)
import QxFx0.Types
  ( AtomTag(..)
  , CanonicalMoveFamily
  , IllocutionaryForce
  , R5Verdict(..)
  )
import QxFx0.Types.ShadowDivergence (ShadowSnapshot(..))
import System.Directory
  ( createDirectory
  , doesFileExist
  , getTemporaryDirectory
  , removeDirectoryRecursive
  , removeFile
  )
import System.FilePath ((</>))
import System.IO (hClose, openTempFile)
import Text.Read (readMaybe)

data DatalogExecution = DatalogExecution
  { deVerdict :: !R5Verdict
  , deDiagnostics :: ![Text]
  } deriving stock (Eq, Show)

createShadowTempFiles :: IO (FilePath, FilePath, IO ())
createShadowTempFiles = do
  tmpDir <- getTemporaryDirectory
  (dlFile, handle) <- openTempFile tmpDir "qxfx0_shadow_rules.dl"
  hClose handle
  let outDir = dlFile <> ".out"
  createDirectory outDir
  pure (dlFile, outDir, cleanup dlFile outDir)
  where
    cleanup dlFile outDir = do
      ignoreCleanup (removeFile dlFile)
      ignoreCleanup (removeDirectoryRecursive outDir)
    ignoreCleanup action =
      catchIO action (\_ -> pure ())

renderRuntimeFacts :: ShadowSnapshot -> Text
renderRuntimeFacts snapshot =
  T.unlines $
    [ "RequestedFamily(\"" <> escapeSymbol (renderShow (ssRequestedFamily snapshot)) <> "\")."
    , "InputForce(\"" <> escapeSymbol (renderShow (ssInputForce snapshot)) <> "\")."
    ]
    ++ map (\atomName -> "InputAtom(\"" <> escapeSymbol atomName <> "\").") (ssInputAtoms snapshot)
    ++ map renderAtomDetail (ssInputAtomDetails snapshot)

buildShadowSnapshot :: CanonicalMoveFamily -> IllocutionaryForce -> [AtomTag] -> ShadowSnapshot
buildShadowSnapshot requestedFamily inputForce tags =
  let atomNames = sort (nub (map atomTagName tags))
      atomDetails = sort (nub (concatMap atomTagDetails tags))
  in ShadowSnapshot
      { ssRequestedFamily = requestedFamily
      , ssInputForce = inputForce
      , ssInputAtoms = atomNames
      , ssInputAtomDetails = atomDetails
      , ssSourceAtomTags = tags
      }

renderAtomDetail :: (Text, Text) -> Text
renderAtomDetail (tagName, detail) =
  "InputAtomDetail(\""
    <> escapeSymbol tagName
    <> "\", \""
    <> escapeSymbol detail
    <> "\")."

atomTagName :: AtomTag -> Text
atomTagName tag = case tag of
  Searching _ -> "Searching"
  Exhaustion _ -> "Exhaustion"
  Verification _ -> "Verification"
  Doubt _ -> "Doubt"
  NeedContact _ -> "NeedContact"
  NeedMeaning _ -> "NeedMeaning"
  AgencyLost _ -> "AgencyLost"
  AgencyFound _ -> "AgencyFound"
  Anchoring _ -> "Anchoring"
  Contradiction _ _ -> "Contradiction"
  CustomAtom label _ -> "CustomAtom:" <> compactDiagnostic label
  AffectiveAtom label _ -> "AffectiveAtom:" <> compactDiagnostic label

atomTagDetails :: AtomTag -> [(Text, Text)]
atomTagDetails tag = case tag of
  Searching payload -> [("Searching", compactDetail payload)]
  Exhaustion payload -> [("Exhaustion", compactDetail payload)]
  Verification payload -> [("Verification", compactDetail payload)]
  Doubt payload -> [("Doubt", compactDetail payload)]
  NeedContact payload -> [("NeedContact", compactDetail payload)]
  NeedMeaning payload -> [("NeedMeaning", compactDetail payload)]
  AgencyLost value -> [("AgencyLost", compactDetail (T.pack (show value)))]
  AgencyFound value -> [("AgencyFound", compactDetail (T.pack (show value)))]
  Anchoring payload -> [("Anchoring", compactDetail payload)]
  Contradiction left right -> [("ContradictionLeft", compactDetail left), ("ContradictionRight", compactDetail right)]
  CustomAtom label payload -> [("CustomAtom", compactDetail label), ("CustomPayload", compactDetail payload)]
  AffectiveAtom label value -> [("AffectiveAtom", compactDetail label), ("AffectiveValence", compactDetail (T.pack (show value)))]

compactDetail :: Text -> Text
compactDetail = T.take 24 . compactDiagnostic

parseShadowOutput :: FilePath -> IO (Either Text DatalogExecution)
parseShadowOutput outDir = do
  verdictRows <- readRelationRows outDir "R5Verdict.csv"
  alertRows <- readRelationRows outDir "ShadowAlert.csv"
  case parseVerdictRows verdictRows of
    Left err -> pure (Left err)
    Right verdict ->
      pure (Right (DatalogExecution verdict (map renderDiagnostic alertRows)))

readRelationRows :: FilePath -> FilePath -> IO [[Text]]
readRelationRows outDir fileName = do
  let fullPath = outDir </> fileName
  exists <- doesFileExist fullPath
  if not exists
    then pure []
    else do
      content <- TIO.readFile fullPath
      pure
        [ map unquoteCell (splitRelationLine line)
        | line <- T.lines content
        , not (T.null (T.strip line))
        ]

splitRelationLine :: Text -> [Text]
splitRelationLine line =
  let tabParts = map T.strip (T.splitOn "\t" line)
  in if length tabParts > 1
       then tabParts
       else map T.strip (T.splitOn "," line)

parseVerdictRows :: [[Text]] -> Either Text R5Verdict
parseVerdictRows [] = Left "shadow produced no R5Verdict rows"
parseVerdictRows (row:_) = case row of
  [famText, forceText, clauseText, layerText, warrantedText] ->
    R5Verdict
      <$> parseEnumText "family" famText
      <*> parseEnumText "force" forceText
      <*> parseEnumText "clause" clauseText
      <*> parseEnumText "layer" layerText
      <*> parseEnumText "warranted" warrantedText
  _ ->
    Left ("unexpected R5Verdict row: " <> T.intercalate "|" row)

parseEnumText :: Read a => Text -> Text -> Either Text a
parseEnumText label raw =
  case readMaybe (T.unpack cleaned) of
    Just value -> Right value
    Nothing -> Left ("invalid " <> label <> " from shadow: " <> cleaned)
  where
    cleaned = T.strip raw

renderDiagnostic :: [Text] -> Text
renderDiagnostic [] = "shadow_alert"
renderDiagnostic [kind] = kind
renderDiagnostic [kind, detail] = kind <> ":" <> detail
renderDiagnostic values = T.intercalate ":" values

unquoteCell :: Text -> Text
unquoteCell raw =
  let stripped = T.strip raw
  in case T.uncons stripped of
       Just ('"', rest) -> case T.unsnoc rest of
         Just (inner, '"') -> inner
         _ -> stripped
       _ -> stripped

renderShow :: Show a => a -> Text
renderShow = T.pack . show

escapeSymbol :: Text -> Text
escapeSymbol =
  T.concatMap $ \ch -> case ch of
    '\\' -> "\\\\"
    '"' -> "\\\""
    '\n' -> " "
    '\r' -> " "
    '\t' -> " "
    _ -> T.singleton ch

compactDiagnostic :: Text -> Text
compactDiagnostic =
  T.intercalate " " . filter (not . T.null) . T.words
