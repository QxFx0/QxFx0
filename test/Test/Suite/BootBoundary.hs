{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

{-| Audit 2026-10-16 п.12/26 anti-rot: boot-loader catch boundaries.

Pins the rule that a boot resource boundary catches exactly the two
expected failure classes ('QxFx0Exception' from a loader, 'IOException'
from a read), degrades to the documented fallback, and never swallows
async cancellation or a programming error.
-}
module Test.Suite.BootBoundary
  ( bootBoundaryTests
  ) where

import Control.Exception
  ( AsyncException(..)
  , ErrorCall(..)
  , throwIO
  , try
  )
import qualified Data.Text as T
import System.Directory
  ( Permissions(..)
  , getPermissions
  , setPermissions
  )
import System.Posix.User (getEffectiveUserID)
import Test.HUnit

import QxFx0.ExceptionPolicy
  ( mkRuntimeInitError
  , throwQxFx0
  , tryBootResource
  )
import QxFx0.Runtime.Session.Bootstrap
  ( initializeAutonomousStorageWith
  , loadBootstrapDefinitionCorpusFrom
  , loadOntologyForBootstrap
  , mergeSelfPlayRelationsForBootstrap
  )
import QxFx0.Runtime.Session.SelfConfig
  ( loadConfigOrBuiltinIO
  , loadTunedOrDefaultIO
  )
import QxFx0.Self.Salience (defaultSalienceWeights)
import QxFx0.Semantic.Content (definitionCorpus)
import QxFx0.Semantic.Lexicon.RuntimeParadigms
  ( emptyRuntimeParadigms
  , loadRuntimeParadigmsFrom
  )
import QxFx0.Semantic.Network.Substrate (loadBrainKB)
import QxFx0.Semantic.Network.Types (emptySemanticNetwork)
import QxFx0.Semantic.Ontology (emptyOntology)
import Test.Support (freshTestPath, removeIfExists)

bootBoundaryTests :: [Test]
bootBoundaryTests =
  [ testAsyncCancellationPropagates
  , testSyncInitFailureIsContained
  , testTryBootResourceClasses
  , testMalformedOntologyFallsBack
  , testMalformedCuratedFallsBackToSeed
  , testMalformedSelfPlayKeepsBaseNetwork
  , testUnreadableBrainKBIsEmpty
  , testUnreadableAndMalformedParadigmsAreEmpty
  , testUnreadableSelfConfigFallsBackToBuiltin
  ]

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

writeTemp :: String -> String -> IO FilePath
writeTemp stem content = do
  path <- freshTestPath stem
  writeFile path content
  pure path

removeDbArtifacts :: FilePath -> IO ()
removeDbArtifacts dbPath =
  mapM_ removeIfExists [dbPath, dbPath <> "-wal", dbPath <> "-shm"]

-- | Permissions-based pins need a non-root uid: root bypasses the mode
-- bits, so the read would succeed. Root is the only skipped case.
whenNotRoot :: IO () -> IO ()
whenNotRoot action = do
  uid <- getEffectiveUserID
  if uid == 0
    then pure ()
    else action

withUnreadableFile :: FilePath -> IO a -> IO a
withUnreadableFile path action = do
  perms <- getPermissions path
  setPermissions path perms { readable = False }
  result <- action
  setPermissions path perms
  pure result

--------------------------------------------------------------------------------
-- п.26: async cancellation through the storage bootstrap boundary
--------------------------------------------------------------------------------

testAsyncCancellationPropagates :: Test
testAsyncCancellationPropagates = TestCase $ do
  dbPath <- freshTestPath "qxfx0_boot_async.db"
  result <- try @AsyncException
    (initializeAutonomousStorageWith (\_ -> throwIO ThreadKilled) dbPath)
  removeDbArtifacts dbPath
  case result of
    Left ThreadKilled -> pure ()
    Left e -> assertFailure ("expected ThreadKilled, got " <> show e)
    Right (Left err) ->
      assertFailure ("async cancellation was swallowed into Left Text: " <> T.unpack err)
    Right (Right _) ->
      assertFailure "async cancellation was swallowed (init reported success)"

testSyncInitFailureIsContained :: Test
testSyncInitFailureIsContained = TestCase $ do
  dbPath <- freshTestPath "qxfx0_boot_sync.db"
  result <- initializeAutonomousStorageWith
    (\_ -> throwIO (userError "boom")) dbPath
  removeDbArtifacts dbPath
  case result of
    Left err ->
      assertBool
        ("synchronous failure must stay contained with its detail, got: " <> T.unpack err)
        ("boom" `T.isInfixOf` err)
    Right _ ->
      assertFailure "a synchronous schema-init failure must not report success"

testTryBootResourceClasses :: Test
testTryBootResourceClasses = TestCase $ do
  caughtIO <- tryBootResource (throwIO (userError "io"))
  case caughtIO of
    Left _ -> pure ()
    Right () -> assertFailure "IOException must be caught at a boot boundary"

  caughtQx <- tryBootResource
    (throwQxFx0 (mkRuntimeInitError "boot_boundary" "probe" "BOOT_TEST" mempty))
  case caughtQx of
    Left _ -> pure ()
    Right () -> assertFailure "QxFx0Exception must be caught at a boot boundary"

  bug <- try @ErrorCall (tryBootResource (throwIO (ErrorCall "bug")))
  case bug of
    Left (ErrorCall msg) ->
      assertEqual "ErrorCall must propagate" "bug" msg
    Right _ ->
      assertFailure "a programming error must not be swallowed at a boot boundary"

  killed <- try @AsyncException (tryBootResource (throwIO ThreadKilled))
  case killed of
    Left ThreadKilled -> pure ()
    Left e -> assertFailure ("expected ThreadKilled, got " <> show e)
    Right _ ->
      assertFailure "async cancellation must not be swallowed at a boot boundary"

--------------------------------------------------------------------------------
-- п.12: loaders degrade to their documented fallbacks
--------------------------------------------------------------------------------

testMalformedOntologyFallsBack :: Test
testMalformedOntologyFallsBack = TestCase $ do
  path <- writeTemp "qxfx0_boot_ontology.jsonl" "not json at all\n"
  ont <- loadOntologyForBootstrap path
  removeIfExists path
  assertEqual
    "malformed ontology must fall back to emptyOntology (classifier degrades)"
    emptyOntology ont

testMalformedCuratedFallsBackToSeed :: Test
testMalformedCuratedFallsBackToSeed = TestCase $ do
  path <- writeTemp "qxfx0_boot_curated.jsonl" "not json at all\n"
  corpus <- loadBootstrapDefinitionCorpusFrom path
  removeIfExists path
  assertEqual
    "malformed curated predicates must fall back to the seed corpus"
    definitionCorpus corpus

testMalformedSelfPlayKeepsBaseNetwork :: Test
testMalformedSelfPlayKeepsBaseNetwork = TestCase $ do
  path <- writeTemp "qxfx0_boot_selfplay.jsonl" "not json at all\n"
  network <- mergeSelfPlayRelationsForBootstrap path emptySemanticNetwork
  removeIfExists path
  assertEqual
    "malformed self-play relations must leave the base network unchanged"
    emptySemanticNetwork network

testUnreadableBrainKBIsEmpty :: Test
testUnreadableBrainKBIsEmpty = TestCase $ whenNotRoot $ do
  path <- writeTemp "qxfx0_boot_brain_kb.jsonl"
    "{\"text\":\"x\",\"triggers\":[\"свобода\"],\"layer\":\"ontology\",\"kind\":\"claim\"}\n"
  entries <- withUnreadableFile path (loadBrainKB path)
  removeIfExists path
  assertEqual
    "an unreadable brain_kb must degrade to an empty substrate, not throw"
    [] entries

testUnreadableAndMalformedParadigmsAreEmpty :: Test
testUnreadableAndMalformedParadigmsAreEmpty = TestCase $ do
  malformed <- writeTemp "qxfx0_boot_paradigms_bad.json" "not json at all"
  rpMalformed <- loadRuntimeParadigmsFrom malformed malformed
  removeIfExists malformed
  assertEqual
    "malformed runtime paradigms must degrade to emptyRuntimeParadigms"
    emptyRuntimeParadigms rpMalformed

  whenNotRoot $ do
    unreadable <- writeTemp "qxfx0_boot_paradigms.json" "{}"
    rpUnreadable <- withUnreadableFile unreadable
      (loadRuntimeParadigmsFrom unreadable unreadable)
    removeIfExists unreadable
    assertEqual
      "unreadable runtime paradigms must degrade to emptyRuntimeParadigms"
      emptyRuntimeParadigms rpUnreadable

testUnreadableSelfConfigFallsBackToBuiltin :: Test
testUnreadableSelfConfigFallsBackToBuiltin = TestCase $ whenNotRoot $ do
  unreadable <- writeTemp "qxfx0_boot_salience_weights.json"
    "{\"weightResonance\":0.9}"
  weights <- withUnreadableFile unreadable
    (loadConfigOrBuiltinIO unreadable defaultSalienceWeights)
  tuned <- withUnreadableFile unreadable
    (loadTunedOrDefaultIO unreadable (unreadable <> ".missing") defaultSalienceWeights)
  removeIfExists unreadable
  assertEqual
    "an unreadable SelfConfig file must fall back to the builtin"
    defaultSalienceWeights weights
  assertEqual
    "an unreadable tuned SelfConfig must fall back through to the builtin"
    defaultSalienceWeights tuned
