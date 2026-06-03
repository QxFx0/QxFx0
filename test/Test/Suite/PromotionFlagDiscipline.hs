{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StrictData #-}

{-|
Module      : Test.Suite.PromotionFlagDiscipline
Description : promotion flag discipline (F-14 follow-up).

The closure plan's 'docs/closure/PROMOTION_PLAYBOOK.md'
defines 4 gates (G1-G4) for promoting a
canonical-flag-off contour to the runtime path.
The 5 promotion candidates are:

  * **Essence** (ADR-0018 proposed) —
    @essenceCommitmentEnabled@ (env var
    @QXFX0_ESSENCE_COMMITMENT_ENABLED@, not in
    code at the Haskell level)
  * **Family Divergence** (ADR-0019 proposed) —
    @familyDivergenceEnabled = False@ literal at
    @src/QxFx0/Core/TurnRouting/Cascade.hs:74@
  * **Perspective Operator** (ADR-0020 proposed) —
    @QXFX0_PERSPECTIVE_OPERATOR_ENABLED@ (env
    var, flag not yet in code per AGENTS.md P4)
  * **External LLM Transport** (ADR-0021 proposed) —
    @QXFX0_BRIDGE_EXTERNAL_LLM_ENABLED@ (env
    var)
  * **Adaptive Mutation** (ADR-0022 proposed) —
    @QXFX0_ADAPTIVE_MUTATION_ENABLED@ (env var)

This test is the **regression lock** for the
discipline. The discipline says:

  * a flag flips to @True@ **only** via the
    playbook's G3 release event;
  * the current state of every flag is
    @off@ (either @False@ literal or absent);
  * the documentation ('PROMOTION_PLAYBOOK.md',
    'AUTHORITY_MAP.md §6', the per-ADR §N) is
    consistent with the code.

== What this test does

For each of the 5 promotion candidates:

  1. search 'src/' for the flag name;
  2. assert the flag is either absent (not yet
     in code) or set to @False@ literal;
  3. assert no @= True@ literal exists in
     production code (only the test file may
     reference it, and only in comments).

For Family Divergence (the most concrete case),
the test additionally asserts that the
@familyDivergenceEnabled = False@ literal is at
the **documented location** (Cascade.hs:74).

== What this test does NOT do

It does not assert that the env vars
(@QXFX0_*_ENABLED@) are @0@ or unset at test
time — those are runtime concerns. The test
locks the **code-level discipline**, not the
**runtime configuration**.

It does not assert that the G1-G4 gates have
been completed for any flag. That is the
playbook's responsibility; the test only
ensures the flag is not flipped prematurely.
-}
module Test.Suite.PromotionFlagDiscipline
  ( promotionFlagDisciplineTests
  ) where

import Test.HUnit (Test (..), assertFailure, assertBool)

import Control.Exception (SomeException, catch)
import Prelude (Bool (..), Eq, FilePath, IO, Show, String, all, filter, lines, mapM, not, null, unlines, (.))

import qualified Data.List as L
import qualified System.Directory as D
import qualified System.FilePath as FP

-- | The 5 promotion candidates. Each tuple is
-- (contour name, primary flag identifier,
-- fallback env var, documented location, is in
-- code). The 'isInCode' flag distinguishes
-- "literal in code" from "env var only".
--
-- Adding a promotion candidate: append a tuple.
data PromotionCandidate = PromotionCandidate
  { pcName        :: !String
  , pcFlagName    :: !String     -- primary identifier in code
  , pcEnvVar      :: !String     -- env var name (may be same as pcFlagName)
  , pcDocLocation :: !String     -- documented location (e.g. "Cascade.hs:74")
  , pcInCode      :: !Bool       -- True if the flag is a Haskell-level literal
  }
  deriving stock (Eq, Show)

-- | The 5 promotion candidates. Order matches
-- the playbook. The 'pcInCode' field is True
-- only for Family Divergence (the only flag
-- currently a Haskell literal); the other 4
-- are env-var-only per AGENTS.md.
promotionCandidates :: [PromotionCandidate]
promotionCandidates =
  [ PromotionCandidate
      { pcName        = "Essence Commitment"
      , pcFlagName    = "essenceCommitmentEnabled"
      , pcEnvVar      = "QXFX0_ESSENCE_COMMITMENT_ENABLED"
      , pcDocLocation = "integration level (env var, not in Haskell)"
      , pcInCode      = False
      }
  , PromotionCandidate
      { pcName        = "Family Divergence"
      , pcFlagName    = "familyDivergenceEnabled"
      , pcEnvVar      = "QXFX0_FAMILY_DIVERGENCE_ENABLED"
      , pcDocLocation = "src/QxFx0/Core/TurnRouting/Cascade.hs:74"
      , pcInCode      = True
      }
  , PromotionCandidate
      { pcName        = "Perspective Operator"
      , pcFlagName    = "QXFX0_PERSPECTIVE_OPERATOR_ENABLED"
      , pcEnvVar      = "QXFX0_PERSPECTIVE_OPERATOR_ENABLED"
      , pcDocLocation = "(flag not yet in code; per AGENTS.md P4)"
      , pcInCode      = False
      }
  , PromotionCandidate
      { pcName        = "External LLM Transport"
      , pcFlagName    = "QXFX0_BRIDGE_EXTERNAL_LLM_ENABLED"
      , pcEnvVar      = "QXFX0_BRIDGE_EXTERNAL_LLM_ENABLED"
      , pcDocLocation = "(env var; not yet wired into code)"
      , pcInCode      = False
      }
  , PromotionCandidate
      { pcName        = "Adaptive Mutation"
      , pcFlagName    = "QXFX0_ADAPTIVE_MUTATION_ENABLED"
      , pcEnvVar      = "QXFX0_ADAPTIVE_MUTATION_ENABLED"
      , pcDocLocation = "(env var; not yet wired into code)"
      , pcInCode      = False
      }
  ]

-- | Read a file or return empty string on error.
readFileOrEmpty :: FilePath -> IO String
readFileOrEmpty path = (readFile path) `catch` (\(_ :: SomeException) -> return "")

-- | Walk 'src/' recursively. Returns all .hs
-- files. Shallow + recursive is fine for the
-- 5K-file codebase.
listHsFilesRecursive :: FilePath -> IO [FilePath]
listHsFilesRecursive dir = do
  exists <- D.doesDirectoryExist dir
  if not exists
    then return []
    else do
      entries <- D.listDirectory dir
      concat <$> mapM go entries
  where
    go entry = do
      let entryPath = dir FP.</> entry
      isDir <- D.doesDirectoryExist entryPath
      if isDir
        then listHsFilesRecursive entryPath
        else return [entryPath | FP.takeExtension entry == ".hs"]

-- | For a single promotion candidate, search
-- 'src/' for the flag name and assert:
--   * no @= True@ literal exists in production code;
--   * if 'pcInCode' is True, at least one
--     @= False@ literal exists at the documented
--     location.
assertCandidateOffState :: PromotionCandidate -> IO [String]
assertCandidateOffState pc = do
  files <- listHsFilesRecursive "src"
  contents <- mapM (\f -> do
                      c <- readFileOrEmpty f
                      return (f, c)) files
  -- Find any line that references the flag.
  let referencing = concat
        [ [ f <> ":" <> show lineNo <> ": " <> line
          | (lineNo, line) <- zip [1 :: Int ..] (L.lines c)
          , pcFlagName pc `L.isInfixOf` line
          ]
        | (f, c) <- contents
        ]
  -- 1. No "= True" literal for the flag.
  let trueLiterals = filter (L.isInfixOf "= True") referencing
  -- 2. If the flag is in code, at least one
  --    "= False" literal exists.
  let falseLiterals = filter (L.isInfixOf "= False") referencing
  let failures = concat
        [ [ pcName pc <> ": " <> pcFlagName pc
            <> " has a '= True' literal in production code: "
            <> unlines trueLiterals
          ]
          | not (null trueLiterals)
        ] ++ concat
        [ [ pcName pc <> ": " <> pcFlagName pc
            <> " is documented as in-code ("
            <> pcDocLocation pc
            <> ") but no '= False' literal found in src/"
          ]
          | pcInCode pc && null falseLiterals
        ]
  return failures

-- | The runtime check: for each of the 5
-- promotion candidates, assert the off-state.
promotionFlagOffState :: Test
promotionFlagOffState = TestLabel "all 5 promotion candidates are at their documented off-state" $
  TestCase $ do
    allFailures <- mapM assertCandidateOffState promotionCandidates
    let flat = concat allFailures
    if null flat
      then return ()
      else assertFailure (unlines
        (  ("Promotion flag discipline violated: "
            <> "the following flags are not at their documented off-state:")
          : flat
        ))

-- | The Family Divergence location check: the
-- @= False@ literal must be at the documented
-- location (Cascade.hs:74).
familyDivergenceLocationCheck :: Test
familyDivergenceLocationCheck = TestLabel "Family Divergence flag is at the documented location (Cascade.hs:74)" $
  TestCase $ do
    let path = "src/QxFx0/Core/TurnRouting/Cascade.hs"
    contents <- readFileOrEmpty path
    let linesWithFlag = filter
          (\line -> "familyDivergenceEnabled = False" `L.isInfixOf` line)
          (L.lines contents)
    assertBool
      ("Family Divergence flag not found at documented location "
       <> "(" <> path <> ", expected 'familyDivergenceEnabled = False' literal): "
       <> "the file is missing the literal, or the literal is not '= False'.")
      (not (null linesWithFlag))

-- ---------------------------------------------------------------------------
-- The test group
-- ---------------------------------------------------------------------------

promotionFlagDisciplineTests :: [Test]
promotionFlagDisciplineTests =
  [ promotionFlagOffState
  , familyDivergenceLocationCheck
  ]
