{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Bridge.SQLite.SchemaContractCheck
  ( checkSchemaContractManifest
  ) where

import qualified Data.Map.Strict as Map
import Data.List (sort)
import Data.Maybe (mapMaybe)
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import QxFx0.Bridge.SQLite.SchemaContract
  ( schemaContractColumns
  , schemaContractFTS
  , schemaContractIndexes
  , schemaContractTables
  , schemaContractTriggers
  )

data ContractItem = ContractItem
  { ciKind :: !Text
  , ciParent :: !Text
  , ciName :: !Text
  } deriving (Eq, Ord, Show)

checkSchemaContractManifest :: FilePath -> FilePath -> IO (Either Text Text)
checkSchemaContractManifest manifestPath schemaPath = do
  manifestText <- TIO.readFile manifestPath
  schemaText <- TIO.readFile schemaPath
  case readManifest manifestPath manifestText of
    Left err -> pure (Left err)
    Right manifest ->
      let manifestSet = Set.fromList manifest
          haskellSet = manifestItemsFromHaskell
          errors =
            validateSqlCoverage manifestSet schemaText
              <> [ "manifest item missing from SchemaContract.hs: " <> renderItem item
                 | item <- sort (Set.toList (manifestSet `Set.difference` haskellSet))
                 ]
              <> [ "SchemaContract.hs item missing from manifest: " <> renderItem item
                 | item <- sort (Set.toList (haskellSet `Set.difference` manifestSet))
                 ]
      in pure $
           if null errors
             then Right
               ( "OK: runtime schema contract manifest matches schema.sql and SchemaContract.hs ("
                   <> T.pack (show (Set.size manifestSet))
                   <> " objects)"
               )
             else Left (T.unlines (map ("ERROR: " <>) errors))

readManifest :: FilePath -> Text -> Either Text [ContractItem]
readManifest manifestPath rawText = traverse parseLine numberedLines
  where
    numberedLines =
      [ (lineno, trimmed)
      | (lineno, line) <- zip [1 :: Int ..] (T.lines rawText)
      , let trimmed = T.strip line
      , not (T.null trimmed)
      , not ("#" `T.isPrefixOf` trimmed)
      ]

    parseLine (lineno, line) =
      case T.splitOn "\t" line of
        [kind, parent, name]
          | kind `elem` validKinds && not (T.null name) -> Right (ContractItem kind parent name)
          | kind `notElem` validKinds -> Left (renderLocation lineno <> "unsupported contract kind: " <> kind)
          | otherwise -> Left (renderLocation lineno <> "empty object name")
        _ -> Left (renderLocation lineno <> "expected 3 tab-separated fields")

    renderLocation lineno = T.pack manifestPath <> ":" <> T.pack (show lineno) <> ": "
    validKinds = ["table", "column", "index", "trigger", "fts"]

manifestItemsFromHaskell :: Set ContractItem
manifestItemsFromHaskell =
  Set.fromList
    ( [ ContractItem "table" "-" name | name <- schemaContractTables ]
      <> [ ContractItem "index" "-" name | name <- schemaContractIndexes ]
      <> [ ContractItem "trigger" "-" name | name <- schemaContractTriggers ]
      <> [ ContractItem "fts" "-" name | name <- schemaContractFTS ]
      <> concatMap columnItems (Map.toList schemaContractColumns)
    )
  where
    columnItems (tableName, cols) = [ ContractItem "column" tableName col | col <- cols ]

validateSqlCoverage :: Set ContractItem -> Text -> [Text]
validateSqlCoverage manifest schemaText = mapMaybe validateOne (sort (Set.toList manifest))
  where
    validateOne item
      | ciKind item == "table" && not (hasSqlTable schemaText (ciName item)) =
          Just ("manifest table missing from schema.sql: " <> ciName item)
      | ciKind item == "column" && not (hasSqlColumn schemaText (ciParent item) (ciName item)) =
          Just ("manifest column missing from schema.sql: " <> ciParent item <> "." <> ciName item)
      | ciKind item == "index" && not (hasSqlIndex schemaText (ciName item)) =
          Just ("manifest index missing from schema.sql: " <> ciName item)
      | ciKind item == "trigger" && not (hasSqlTrigger schemaText (ciName item)) =
          Just ("manifest trigger missing from schema.sql: " <> ciName item)
      | ciKind item == "fts" && not (hasSqlFts schemaText (ciName item)) =
          Just ("manifest fts table missing from schema.sql: " <> ciName item)
      | otherwise = Nothing

hasSqlTable :: Text -> Text -> Bool
hasSqlTable schemaText name =
  T.isInfixOf (normalizeSqlFragment ("CREATE TABLE IF NOT EXISTS " <> name <> " (")) normalizedSchema
  where
    normalizedSchema = normalizeSqlFragment schemaText

hasSqlFts :: Text -> Text -> Bool
hasSqlFts schemaText name =
  T.isInfixOf (normalizeSqlFragment ("CREATE VIRTUAL TABLE IF NOT EXISTS " <> name <> " USING fts5(")) normalizedSchema
  where
    normalizedSchema = normalizeSqlFragment schemaText

hasSqlIndex :: Text -> Text -> Bool
hasSqlIndex schemaText name =
  T.isInfixOf (normalizeSqlFragment ("CREATE INDEX IF NOT EXISTS " <> name <> " ON ")) normalizedSchema
  where
    normalizedSchema = normalizeSqlFragment schemaText

hasSqlTrigger :: Text -> Text -> Bool
hasSqlTrigger schemaText name =
  T.isInfixOf (normalizeSqlFragment ("CREATE TRIGGER IF NOT EXISTS " <> name <> " ")) normalizedSchema
  where
    normalizedSchema = normalizeSqlFragment schemaText

hasSqlColumn :: Text -> Text -> Text -> Bool
hasSqlColumn schemaText tableName columnName =
  case extractCreateTableLines schemaText tableName of
    Nothing -> False
    Just bodyLines -> any (columnLineMatches columnName) bodyLines

extractCreateTableLines :: Text -> Text -> Maybe [Text]
extractCreateTableLines schemaText tableName =
  case dropWhile (not . isTableHeader) (T.lines schemaText) of
    [] -> Nothing
    (_header:rest) -> Just (takeWhile (not . isTableEnd) rest)
  where
    normalizedHeader = normalizeSqlFragment ("CREATE TABLE IF NOT EXISTS " <> tableName <> " (")
    isTableHeader line = normalizeSqlFragment line == normalizedHeader
    isTableEnd line = T.strip line == ");"

columnLineMatches :: Text -> Text -> Bool
columnLineMatches columnName line =
  let trimmed = T.strip line
      candidate = T.takeWhile (\c -> c /= ' ' && c /= '\t' && c /= ',' && c /= '\n' && c /= '\r') trimmed
  in candidate == columnName

renderItem :: ContractItem -> Text
renderItem item = ciKind item <> " " <> ciParent item <> " " <> ciName item

normalizeSqlFragment :: Text -> Text
normalizeSqlFragment = T.unwords . T.words
