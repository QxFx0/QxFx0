{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

{-| Audit 2026-10-16 п.9 anti-rot: the feedback mirror self-heals from
malformed lines and is rewritten atomically (temp + rename), while a
read failure leaves the existing mirror untouched.
-}
module Test.Suite.FeedbackMirror
  ( feedbackMirrorTests
  ) where

import Control.Exception (SomeException, try)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BL
import Data.Either (isLeft)
import Data.List (isPrefixOf)
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import Data.Text (Text)
import qualified Data.Text as T
import System.Directory
  ( Permissions(..)
  , createDirectoryIfMissing
  , getPermissions
  , listDirectory
  , removePathForcibly
  , setPermissions
  )
import System.FilePath (takeDirectory, takeFileName)
import System.Posix.Files (fileID, getFileStatus)
import System.Posix.User (getEffectiveUserID)
import Test.HUnit

import QxFx0.Semantic.Content.AtomStore (RelationType(..))
import QxFx0.Semantic.Network.Feedback.Persist (persistFeedbackNetwork)
import QxFx0.Semantic.Network.Ingest (LoadedRelation(..))
import QxFx0.Semantic.Network.Types
  ( EdgeProvenance(..)
  , EdgeSource(..)
  , SemanticEdge(..)
  , SemanticNetwork(..)
  , emptySemanticNetwork
  )
import Test.Support (freshTestPath, removeIfExists)

-- Local copy of the root-skip used by the permissions-based pins (root
-- bypasses the mode bits, so the read would succeed).
whenNotRoot :: IO () -> IO ()
whenNotRoot action = do
  uid <- getEffectiveUserID
  if uid == 0
    then pure ()
    else action

feedbackMirrorTests :: [Test]
feedbackMirrorTests =
  [ TestLabel "malformed lines are skipped and the mirror self-heals"
      testMalformedLinesSelfHeal
  , TestLabel "a read failure leaves the mirror untouched"
      testReadFailureLeavesMirrorUntouched
  , TestLabel "a missing mirror is created"
      testMissingMirrorIsCreated
  , TestLabel "the rewrite replaces the file via rename (atomic)"
      testRewriteReplacesFileAtomically
  , TestLabel "a failed write cleans up the temp file"
      testFailedWriteCleansUpTemp
  ]

--------------------------------------------------------------------------------
-- Fixtures
--------------------------------------------------------------------------------

mkEdge :: Double -> SemanticEdge
mkEdge confidence = SemanticEdge
  { seFrom          = "a"
  , seTo            = "b"
  , seWeight        = 0.5
  , seCoOccurrence  = 1
  , seSource        = ExplicitEdge
  , seRelationType  = Just RelRequires
  , seVerb          = Nothing
  , seRationale     = Nothing
  , seCounter       = Nothing
  , seSynthesis     = Nothing
  , seConfidence    = confidence
  , seProvenance    = ProvenanceDialogueFeedback
  , seDomain        = Nothing
  , seTemporalScope = Nothing
  , seNamespace     = Nothing
  , seLineage       = Nothing
  }

mkNetwork :: [SemanticEdge] -> SemanticNetwork
mkNetwork edges = emptySemanticNetwork
  { snNodes = S.fromList (concatMap (\e -> [seFrom e, seTo e]) edges)
  , snEdges = M.fromList [ ((seFrom e, seTo e), e) | e <- edges ]
  }

-- | Previous network with edge a→b at 0.5; updated network changes it
-- to 0.6 and adds c→d. Both are "changed" edges for the mirror.
previousNetwork :: SemanticNetwork
previousNetwork = mkNetwork [mkEdge 0.5]

updatedNetwork :: SemanticNetwork
updatedNetwork = mkNetwork [mkEdge 0.6, (mkEdge 0.4) { seFrom = "c", seTo = "d" }]

relationLine :: Text -> Text -> BS.ByteString
relationLine from_ to_ =
  BL.toStrict $
    Aeson.encode
      (LoadedRelation from_ to_ RelRequires
        Nothing Nothing Nothing Nothing 0.5 "curated" 1)

parseMirror :: FilePath -> IO [LoadedRelation]
parseMirror path = do
  bytes <- BS.readFile path
  let rawLines = filter (not . BS.null) (BS.split 0x0A bytes)
      decoded = map (Aeson.eitherDecodeStrict :: BS.ByteString -> Either String LoadedRelation) rawLines
  case sequence decoded of
    Left err -> assertFailure ("mirror must parse cleanly, got: " <> err) >> pure []
    Right rels -> pure rels

keysOf :: [LoadedRelation] -> S.Set (Text, Text)
keysOf rels = S.fromList [ (lrFrom r, lrTo r) | r <- rels ]

--------------------------------------------------------------------------------
-- Pins
--------------------------------------------------------------------------------

testMalformedLinesSelfHeal :: Test
testMalformedLinesSelfHeal = TestCase $ do
  path <- freshTestPath "qxfx0_feedback_mirror_corrupt.jsonl"
  BS.writeFile path $
    BS.intercalate "\n"
      [ relationLine "x" "y"
      , "not json at all"
      , relationLine "z" "w"
      ]
      <> "\n"
  persistFeedbackNetwork path previousNetwork updatedNetwork
  rels <- parseMirror path
  removeIfExists path
  assertEqual
    "the rewrite must keep valid rows, merge changed rows, and drop the malformed line"
    (S.fromList [("x", "y"), ("z", "w"), ("a", "b"), ("c", "d")])
    (keysOf rels)

testReadFailureLeavesMirrorUntouched :: Test
testReadFailureLeavesMirrorUntouched = TestCase $ whenNotRoot $ do
  path <- freshTestPath "qxfx0_feedback_mirror_unreadable.jsonl"
  BS.writeFile path (relationLine "x" "y" <> "\n")
  before <- BS.readFile path
  perms <- getPermissions path
  setPermissions path perms { readable = False }
  result <- try @SomeException
    (persistFeedbackNetwork path previousNetwork updatedNetwork)
  setPermissions path perms
  after <- BS.readFile path
  removeIfExists path
  case result of
    Left err ->
      assertFailure ("a read failure must not escape into the best-effort caller: " <> show err)
    Right () -> pure ()
  assertEqual "a read failure must not clobber the mirror" before after

testMissingMirrorIsCreated :: Test
testMissingMirrorIsCreated = TestCase $ do
  path <- freshTestPath "qxfx0_feedback_mirror_new.jsonl"
  persistFeedbackNetwork path emptySemanticNetwork updatedNetwork
  rels <- parseMirror path
  removeIfExists path
  assertEqual
    "the new mirror must contain exactly the changed relations"
    (S.fromList [("a", "b"), ("c", "d")])
    (keysOf rels)
  assertBool "the changed relation must carry the updated confidence"
    (any (\r -> lrFrom r == "a" && lrConfidence r == 0.6) rels)

testRewriteReplacesFileAtomically :: Test
testRewriteReplacesFileAtomically = TestCase $ do
  path <- freshTestPath "qxfx0_feedback_mirror_atomic.jsonl"
  BS.writeFile path (relationLine "x" "y" <> "\n")
  beforeStatus <- getFileStatus path
  persistFeedbackNetwork path previousNetwork updatedNetwork
  afterStatus <- getFileStatus path
  leftovers <- listDirectory (takeDirectory path)
  removeIfExists path
  assertBool
    "the rewrite must replace the file via rename (inode must change)"
    (fileID beforeStatus /= fileID afterStatus)
  assertBool
    "no temp file may remain after a successful rewrite"
    (not (any ((takeFileName path <> "-tmp") `isPrefixOf`) leftovers))

testFailedWriteCleansUpTemp :: Test
testFailedWriteCleansUpTemp = TestCase $ do
  dir <- freshTestPath "qxfx0_feedback_mirror_target_dir"
  createDirectoryIfMissing True dir
  result <- try @SomeException
    (persistFeedbackNetwork dir previousNetwork updatedNetwork)
  leftovers <- listDirectory (takeDirectory dir)
  removePathForcibly dir
  assertBool "a directory target must fail the rewrite" (isLeft result)
  assertBool
    "a failed write must not leave a temp file behind"
    (not (any ((takeFileName dir <> "-tmp") `isPrefixOf`) leftovers))
