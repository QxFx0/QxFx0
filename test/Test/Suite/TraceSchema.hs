{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DerivingStrategies #-}
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

  * the static check reports P4 status (OK or GAP)
    and links GAPs to TRACE_SCHEMA.md sections.
  * the runtime test asserts that the **OK** contours
    remain OK (a regression lock) and that the
    discipline doc is present and current.

== What this test does

For each of the 3 OK canonical contours (Salience,
Deliberation, Essence), it reads the
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

It does not assert that the 3 GAP contours (Conatus,
Field, Identity) have their fields in the type —
the discipline says they are "expected but not yet
landed" (Package 3 work). When the GAPs are closed,
this test is updated to add new OK-contour tests.

The static @check_replay_gate.sh@ continues to
report the GAPs; this test only locks the OK
contours and the schema doc.
-}
module Test.Suite.TraceSchema
  ( traceSchemaTests
  ) where

import Test.HUnit (Test (..), assertFailure, assertBool)

import Control.Exception (SomeException, catch)
import Prelude (Bool (..), IO, String, all, elem, filter, isInfixOf, lines, mapM_, not, null, unlines, (.))

import qualified Data.List as L

-- | The list of OK canonical contours and their
-- expected trc* fields. These are the contours that
-- currently pass P4 (see TRACE_SCHEMA.md §1).
--
-- Adding a contour: append a (contour, field) pair.
-- Closing a GAP: move the pair from
-- 'expectedMissingFields' to 'okTrcFields'.
okTrcFields :: [(String, String)]
okTrcFields =
  [ ("Salience",     "trcSalienceDriver")
  , ("Deliberation", "trcDeliberationRule")
  , ("Essence",      "trcEssenceMode")
  ]

-- | The 3 GAP contours and their expected trc* fields.
-- The test does NOT assert these are present in the
-- type; the discipline says they are "expected but
-- not yet landed" (Package 3 work).
--
-- Listed here for documentation; the static
-- @check_replay_gate.sh@ script uses this list.
expectedMissingFields :: [(String, String)]
expectedMissingFields =
  [ ("Conatus",  "trcConatusEnergy")
  , ("Field",    "trcField")
  , ("Identity", "trcIdentityClaims")
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

-- | The runtime check: for each OK contour, assert
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

-- | The discipline check: the 3 GAPs are documented
-- in TRACE_SCHEMA.md and the discipline section
-- explains how to add a new contour.
traceSchemaMdHasDiscipline :: Test
traceSchemaMdHasDiscipline = TestLabel "TRACE_SCHEMA.md documents the 3 GAPs and the discipline for new contours" $
  TestCase $ do
    let docPath = "docs/closure/TRACE_SCHEMA.md"
    contents <- readFileOrEmpty docPath
    -- Each GAP contour must have a §N section.
    let gapContours = map fst expectedMissingFields
    let missingSections = filter
          (\c -> not (any (\line -> L.isInfixOf ("## ") c line) (lines contents)))
          gapContours
    -- We do an "infix of name in section header" check,
    -- which is a weak but sufficient discipline signal.
    let hasDisciplineSection = any
          (\line -> L.isInfixOf "Discipline: adding a new canonical contour" line)
          (lines contents)
    assertBool
      ("TRACE_SCHEMA.md is missing GAP sections for: " <> show missingSections
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
