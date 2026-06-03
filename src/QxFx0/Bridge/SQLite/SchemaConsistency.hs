{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module QxFx0.Bridge.SQLite.SchemaConsistency
  ( checkSchemaConsistency
  ) where

import Control.Exception (IOException, catch, finally)
import Data.List (sort)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import qualified QxFx0.Bridge.NativeSQLite as NSQL
import QxFx0.ExceptionPolicy
  ( QxFx0Exception
  , QxFx0Exception(RuntimeInitError)
  , throwQxFx0
  , tryQxFx0
  )
import System.Directory (createDirectoryIfMissing, listDirectory, removeFile)
import System.FilePath ((</>))

checkSchemaConsistency :: FilePath -> FilePath -> IO (Either Text Text)
checkSchemaConsistency migrationsDir canonicalSchemaPath = do
  result <- tryQxFx0 (checkSchemaConsistencyUnsafe migrationsDir canonicalSchemaPath)
  pure $
    case result of
      Right ok -> Right ok
      Left err -> Left ("FAIL: " <> T.pack (show (err :: QxFx0Exception)))

checkSchemaConsistencyUnsafe :: FilePath -> FilePath -> IO Text
checkSchemaConsistencyUnsafe migrationsDir canonicalSchemaPath = do
  migrationFiles <- migrationFileList migrationsDir
  if null migrationFiles
    then pure ("FAIL: no migration files in " <> T.pack migrationsDir)
    else do
      canonicalSchema <- TIO.readFile canonicalSchemaPath
      let tmpDir = ".test-tmp/schema-consistency"
          dbMigrations = tmpDir </> "migrations.db"
          dbCanonical = tmpDir </> "canonical.db"
      createDirectoryIfMissing True tmpDir
      ignoreRemove dbMigrations
      ignoreRemove dbCanonical
      migrationsResult <- withDb dbMigrations $ \db -> do
        mapM_ (applySqlFile db) migrationFiles
        dumpSchemaSignature db
      canonicalResult <- withDb dbCanonical $ \db -> do
        execSqlOrThrow db canonicalSchema "canonical schema"
        dumpSchemaSignature db
      let migrationSig = sort migrationsResult
          canonicalSig = sort canonicalResult
      pure $
        if migrationSig == canonicalSig
          then
            "OK: cumulative migrations ("
              <> T.pack (show (length migrationFiles))
              <> " files) match canonical schema ("
              <> T.pack (show (length canonicalSig))
              <> " objects)"
          else renderSchemaMismatch migrationSig canonicalSig

migrationFileList :: FilePath -> IO [FilePath]
migrationFileList migrationsDir = do
  entries <- listDirectory migrationsDir
  pure
    [ migrationsDir </> entry
    | entry <- sort entries
    , ".sql" `T.isSuffixOf` T.pack entry
    ]

withDb :: FilePath -> (NSQL.Database -> IO a) -> IO a
withDb dbPath action = do
  mDb <- NSQL.open dbPath
  case mDb of
    Left err -> failText ("sqlite open failed: " <> err)
    Right db -> action db `finally` NSQL.close db

applySqlFile :: NSQL.Database -> FilePath -> IO ()
applySqlFile db path = do
  sqlText <- TIO.readFile path
  execSqlOrThrow db sqlText (T.pack path)

execSqlOrThrow :: NSQL.Database -> Text -> Text -> IO ()
execSqlOrThrow db sqlText label = do
  result <- NSQL.execSql db sqlText
  case result of
    Left err -> failText ("schema consistency exec failed for " <> label <> ": " <> err)
    Right _ -> pure ()

dumpSchemaSignature :: NSQL.Database -> IO [(Text, Text, Text, Text)]
dumpSchemaSignature db = do
  mStmt <- NSQL.prepare db "SELECT type, name, tbl_name, sql FROM sqlite_master WHERE type IN ('table','index','trigger','view') AND name NOT LIKE 'sqlite_%' ORDER BY type, name"
  case mStmt of
    Left err -> failText ("schema signature prepare failed: " <> err)
    Right stmt -> go stmt []
  where
    go stmt acc = do
      hasRow <- NSQL.stepRow stmt
      if not hasRow
        then do
          NSQL.finalize stmt
          pure (reverse acc)
        else do
          objType <- NSQL.columnText stmt 0
          objName <- NSQL.columnText stmt 1
          tableName <- NSQL.columnText stmt 2
          sqlText <- NSQL.columnText stmt 3
          go stmt ((T.strip objType, T.strip objName, T.strip tableName, normalizeSql sqlText) : acc)

normalizeSql :: Text -> Text
normalizeSql sqlText
  | T.null sqlText = ""
  | otherwise = T.dropWhileEnd (== ';') (T.unwords (T.words sqlText))

renderSchemaMismatch :: [(Text, Text, Text, Text)] -> [(Text, Text, Text, Text)] -> Text
renderSchemaMismatch migrationSig canonicalSig =
  T.unlines
    (["FAIL: cumulative migrations schema differs from spec/sql/schema.sql"]
      <> renderOnlyIn "Objects only in migrations result:" migrationOnly
      <> renderOnlyIn "Objects only in canonical schema:" canonicalOnly)
  where
    migrationOnly = take 20 (filter (`notElem` canonicalSig) migrationSig)
    canonicalOnly = take 20 (filter (`notElem` migrationSig) canonicalSig)

    renderOnlyIn _ [] = []
    renderOnlyIn header rows =
      header : map ("  " <>) (map renderRow rows)

    renderRow (objType, objName, tableName, sqlText) =
      T.pack (show (objType, objName, tableName, sqlText))

ignoreRemove :: FilePath -> IO ()
ignoreRemove path = removeFile path `catchIoIgnore` pure ()

catchIoIgnore :: IO a -> IO a -> IO a
catchIoIgnore action fallback = action `catch` \(_ :: IOException) -> fallback

failText :: Text -> IO a
failText = throwQxFx0 . RuntimeInitError
