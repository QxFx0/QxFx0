{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : Test.Suite.TraceSchema
Description : P4 discipline lock (TRACE_SCHEMA.md).

The closure plan's Package 3 says: "every canonical
contour has a named @trc*@ field in @TurnReplayTrace@".
The companion 'scripts/check_replay_gate.sh' is the
**static** check (a regex on the type file). This
test is the **runtime** companion.

The two checks together enforce the discipline:

  * the static check reports P4 status for every
    canonical contour.
  * the runtime test asserts that the canonical
    contours remain locked and that the discipline
    doc is present and current.

== What this test does

For each of the 6 canonical contours (Conatus,
Field, Salience, Deliberation, Essence, Identity), it reads the
@src/QxFx0/Types/TurnProjection.hs@ source file and
asserts that the documented @trc*@ field is declared
in the @data TurnReplayTrace = TurnReplayTrace { ... }@
record. A regression (the field is removed) makes
this test fail.

For TRACE_SCHEMA.md, the test asserts:

  * the file exists at @docs/closure/TRACE_SCHEMA.md@;
  * it has a §1 section listing the 6 canonical
    contours;
  * it has a §6 section for Essence (the most
    recent addition, landed 2026-05-19).

== What this test does NOT do

The static @check_replay_gate.sh@ remains the source
of truth for P1-P4 status; this test locks the
canonical field presence and the schema doc.
-}
module Test.Suite.TraceSchema
  ( traceSchemaTests
  ) where

import Test.HUnit (Test (..), assertFailure, assertBool)

import Control.Exception (SomeException, catch)
import Prelude (Bool (..), FilePath, IO, String, all, elem, filter, lines, mapM_, not, null, unlines, (.))

import qualified Data.List as L

-- | The canonical contours and one representative
-- expected trc* field per contour.
okTrcFields :: [(String, String)]
okTrcFields =
  [ ("Conatus",      "trcConatusEnergy")
  , ("Field",        "trcField")
  , ("Salience",     "trcSalienceDriver")
  , ("Deliberation", "trcDeliberationRule")
  , ("Essence",      "trcEssenceMode")
  , ("Identity",     "trcIdentityClaims")
  ]

-- | Read a file or return empty string on error.
readFileOrEmpty :: FilePath -> IO String
readFileOrEmpty path = (readFile path) `catch` (\(_ :: SomeException) -> return "")

-- | Strip the inline Haddock and whitespace from a
-- declaration line, leaving the field name. Used to
-- extract @trc*@ names from the @data TurnReplayTrace@
-- record body.
--
-- Example: @  , trcSalienceDriver :: !Text -- Phase 5.5e ...@
--        -> @trcSalienceDriver@
extractTrcFieldName :: String -> Maybe String
extractTrcFieldName line =
  case L.words (stripComment line) of
    (_ : _ : name : _) | "trc" `L.isPrefixOf` name -> Just name
    _                                                -> Nothing
  where
    stripComment s = case L.breakOn "--" s of
      (before, _) -> before

-- | The runtime check: for each canonical contour, assert
-- that the expected trc* field is declared in
-- @TurnReplayTrace@.
p4OkContoursHaveTrcField :: Test
p4OkContoursHaveTrcField = TestLabel "P4 (runtime): all OK canonical contours have their trc* field in TurnReplayTrace" $
  TestCase $ do
    let typePath = "src/QxFx0/Types/TurnProjection.hs"
    contents <- readFileOrEmpty typePath
    let declared = [ n | line <- lines contents, Just n <- [extractTrcFieldName line] ]
    let missing = filter
          (\(_, field) -> not (field `elem` declared))
          okTrcFields
    assertBool ("P4 (runtime) regression: the following OK contours are missing their trc* field "
                <> "in " <> typePath <> ": " <> show missing)
               (null missing)

-- | The doc check: TRACE_SCHEMA.md exists and has the
-- expected §1 (6 contours) and §6 (Essence) sections.
traceSchemaMdExists :: Test
traceSchemaMdExists = TestLabel "TRACE_SCHEMA.md exists and lists 6 canonical contours" $
  TestCase $ do
    let docPath = "docs/closure/TRACE_SCHEMA.md"
    contents <- readFileOrEmpty docPath
    assertBool ("TRACE_SCHEMA.md not found at " <> docPath)
               (not (null contents))
    let sectionHeaders = filter (L.isPrefixOf "## ") (lines contents)
    -- §1 is the canonical-contour index; §6 is Essence.
    -- Assert both exist.
    let hasSection1 = any (L.isInfixOf "The 6 canonical contours") sectionHeaders
    let hasSection6 = any (L.isInfixOf "Essence") sectionHeaders
    assertBool
      ("TRACE_SCHEMA.md is missing the §1 canonical-contour index "
       <> "or the §6 Essence section. Found headers: " <> show sectionHeaders)
      (hasSection1 && hasSection6)

-- | The discipline check: the canonical contours are documented
-- in TRACE_SCHEMA.md and the discipline section explains how to
-- add a new contour.
traceSchemaMdHasDiscipline :: Test
traceSchemaMdHasDiscipline = TestLabel "TRACE_SCHEMA.md documents the canonical contours and the discipline for new contours" $
  TestCase $ do
    let docPath = "docs/closure/TRACE_SCHEMA.md"
    contents <- readFileOrEmpty docPath
    let canonicalContours = map fst okTrcFields
    let missingSections = filter
          (\c -> not (any (\line -> L.isInfixOf ("## ") c line) (lines contents)))
          canonicalContours
    let hasDisciplineSection = any
          (\line -> L.isInfixOf "Discipline: adding a new canonical contour" line)
          (lines contents)
    assertBool
      ("TRACE_SCHEMA.md is missing canonical contour sections for: " <> show missingSections
       <> "; or the §9 'Discipline' section is missing.")
      (null missingSections && hasDisciplineSection)

-- ---------------------------------------------------------------------------
-- The test group
-- ---------------------------------------------------------------------------

traceSchemaTests :: [Test]
traceSchemaTests =
  [ p4OkContoursHaveTrcField
  , traceSchemaMdExists
  , traceSchemaMdHasDiscipline
  ]
