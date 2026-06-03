{-# LANGUAGE OverloadedStrings #-}

module CLI where

import CLI.Health (handleHealthcheck)
import CLI.Health (handleRuntimeReady)
import CLI.Http (handleServeHttp)
import CLI.Protocol (RuntimeOutputMode(..))
import CLI.State (handleStateJson)
import CLI.Turn (runTurnJson)
import CLI.Worker (runWorkerStdio)

import Data.Aeson (encode)
import Data.Text (Text)
import qualified Data.Text as T
import QxFx0.Render.Text (textShow)
import qualified Data.Text.IO as T
import System.Directory (createDirectoryIfMissing)
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.FilePath (takeDirectory)
import System.IO (BufferMode(..), hPutStrLn, hSetBuffering, stderr, stdout)
import qualified Data.ByteString.Lazy.Char8 as BLC
import Control.Exception (try)

import qualified QxFx0.Bridge.EmbeddedSQLSync as EmbeddedSQLSync
import qualified QxFx0.Runtime as Runtime
import qualified QxFx0.Resources as Resources
import qualified QxFx0.Bridge.NativeSQLite as NSQL
import qualified QxFx0.Bridge.SQLite.SchemaContractCheck as SchemaContractCheck
import qualified QxFx0.Bridge.SQLite.SchemaConsistency as SchemaConsistency
import QxFx0.CLI.Parser (extractSessionArgs)
import QxFx0.ExceptionPolicy (QxFx0Exception)

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering
  args <- getArgs
  sessionId0 <- Runtime.resolveSessionId
  let (sessionId, restArgs) = extractSessionArgs sessionId0 args
  case restArgs of
    []                        -> interactiveMain sessionId
    ["--help"]                -> Runtime.printHelp >> printMachineHelp
    ["--healthcheck"]         -> handleHealthcheck sessionId
    ["--health"]              -> handleHealthcheck sessionId
    ["--runtime-ready"]       -> handleRuntimeReady
    ["--write-agda-witness"]  -> handleWriteAgdaWitness
    ["--state-json"]          -> handleStateJson sessionId
    ["--worker-stdio"]        -> handleWorkerStdio sessionId
    ("--serve-http":portArgs) -> handleServeHttp sessionId portArgs
    ("--turn-json":textParts) -> handleTurnJson sessionId (filter (/= "--json") textParts)
    ("--input":textParts)     -> handleTurnJson sessionId (filter (/= "--json") textParts)
    ["--json"]                -> handleStateJson sessionId
    ["--init-db-only"]        -> handleInitDb
    ["--check-embedded-sql"]  -> handleCheckEmbeddedSql
    ["--sync-embedded-sql"]   -> handleSyncEmbeddedSql
    ["--check-schema-consistency"] -> handleCheckSchemaConsistency
    ["--check-schema-contract"] -> handleCheckSchemaContract
    _                         -> do
      hPutStrLn stderr "Unsupported arguments. Use --help."
      exitFailure

printMachineHelp :: IO ()
printMachineHelp = do
  T.putStrLn ""
  T.putStrLn "Machine flags:"
  T.putStrLn "  --session-id <id>             select isolated runtime session"
  T.putStrLn "  --session <id>               alias for --session-id"
  T.putStrLn "  --healthcheck, --health      emit runtime health JSON"
  T.putStrLn "  --runtime-ready              emit side-effect free runtime readiness JSON"
  T.putStrLn "  --write-agda-witness         persist fresh Agda witness into runtime state dir"
  T.putStrLn "  --state-json                 emit runtime state JSON"
  T.putStrLn "  --json                       alias for --state-json"
  T.putStrLn "  --turn-json <text>           run one dialogue turn, emit JSON"
  T.putStrLn "  --turn-json --semantic <text> run one semantic turn, emit JSON"
  T.putStrLn "  --input <text>               alias for --turn-json"
  T.putStrLn "  --worker-stdio               run as JSON-over-stdio worker"
  T.putStrLn "  --serve-http [port]          start HTTP sidecar"
  T.putStrLn "  --check-embedded-sql         verify EmbeddedSQL.hs matches spec/sql"
  T.putStrLn "  --sync-embedded-sql          rewrite EmbeddedSQL.hs from spec/sql"
  T.putStrLn "  --check-schema-consistency   verify cumulative migrations match canonical schema.sql"
  T.putStrLn "  --check-schema-contract      verify runtime schema contract manifest against schema.sql and SchemaContract.hs"

handleTurnJson :: Text -> [String] -> IO ()
handleTurnJson sessionId args =
  let (mode, inputText) = case args of
        ("--semantic":rest) -> (SemanticIntrospectionMode, T.unwords (map T.pack rest))
        rest                -> (DialogueMode, T.unwords (map T.pack rest))
  in if T.null inputText
     then do
       hPutStrLn stderr "Error: --turn-json requires input text"
       exitFailure
     else do
       response <- runTurnJson sessionId mode inputText
       BLC.putStrLn (encode response)

handleInitDb :: IO ()
handleInitDb = do
  dbPath <- Runtime.resolveDbPath
  createDirectoryIfMissing True (takeDirectory dbPath)
  mDb <- NSQL.open dbPath
  case mDb of
    Left err -> hPutStrLn stderr $ "Cannot open database: " <> T.unpack err
    Right db -> do
      Runtime.ensureSchemaMigrations db
      NSQL.close db
      hPutStrLn stderr $ "DB initialized at: " ++ dbPath

handleCheckEmbeddedSql :: IO ()
handleCheckEmbeddedSql = do
  paths <- Resources.resolveResourcePaths
  result <- EmbeddedSQLSync.checkEmbeddedSqlSync paths "src/QxFx0/Bridge/EmbeddedSQL.hs"
  case result of
    Right () -> T.putStrLn "EmbeddedSQL.hs is in sync with spec/sql"
    Left err -> hPutStrLn stderr (T.unpack err) >> exitFailure

handleSyncEmbeddedSql :: IO ()
handleSyncEmbeddedSql = do
  paths <- Resources.resolveResourcePaths
  EmbeddedSQLSync.writeEmbeddedSqlModule paths "src/QxFx0/Bridge/EmbeddedSQL.hs"
  T.putStrLn "wrote src/QxFx0/Bridge/EmbeddedSQL.hs"

handleCheckSchemaConsistency :: IO ()
handleCheckSchemaConsistency = do
  paths <- Resources.resolveResourcePaths
  result <- SchemaConsistency.checkSchemaConsistency (Resources.rpMigrationDir paths) (Resources.rpSchemaSql paths)
  case result of
    Right ok -> T.putStrLn ok
    Left err -> T.putStrLn err >> exitFailure

handleCheckSchemaContract :: IO ()
handleCheckSchemaContract = do
  result <- SchemaContractCheck.checkSchemaContractManifest
    "spec/sql/runtime_critical_contract.tsv"
    "spec/sql/schema.sql"
  case result of
    Right ok -> T.putStrLn ok
    Left err -> T.putStrLn err >> exitFailure

handleWorkerStdio :: Text -> IO ()
handleWorkerStdio sessionId = runWorkerStdio sessionId

handleWriteAgdaWitness :: IO ()
handleWriteAgdaWitness = do
  result <- try Runtime.writeAgdaWitness
  case result of
    Right witnessPath -> T.putStrLn (T.pack witnessPath)
    Left err -> do
      hPutStrLn stderr $ "Error writing Agda witness: " ++ show (err :: QxFx0Exception)
      exitFailure

interactiveMain :: Text -> IO ()
interactiveMain sessionId =
  Runtime.withBootstrappedSession False sessionId $ \session -> do
    T.putStrLn ""
    T.putStrLn "QxFx0 - Flagship Philosophical Dialogue System"
    T.putStrLn "Semantic.Logic routing + threshold intuition + meaning graph + dream rewiring"
    T.putStrLn "Commands: :help, :state, :dialogue, :semantic, :quit"
    T.putStrLn $ "Session: " <> Runtime.sessSessionId session
    T.putStrLn $ "State: " <> textShow (Runtime.sessStateOrigin session)
    Runtime.loop session
