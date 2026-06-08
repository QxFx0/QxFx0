{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE StrictData #-}
{-# LANGUAGE ScopedTypeVariables #-}

{-|
Module      : Test.Suite.PromotionFlagDiscipline
Description : promotion flag discipline (F-14 follow-up).

The closure plan's 'docs/closure/PROMOTION_PLAYBOOK.md'
defines 4 gates (G1-G4) for promoting a
canonical-flag-off contour to the runtime path.
The 5 promotion candidates are:

  * **Essence** (ADR-0036 proposed) —
    @essenceCommitmentEnabled@ (env var
    @QXFX0_ESSENCE_COMMITMENT_ENABLED@, not in
    code at the Haskell level)
  * **Family Divergence** (ADR-0019 accepted 2026-06-02) —
    @familyDivergenceEnabled = True@ literal at
    @src/QxFx0/Core/TurnRouting/Cascade.hs:74@
    **PROMOTED** — flag is now in the live authority path.
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
  * flags not yet promoted remain @off@
    (either @False@ literal or absent);
  * the documentation ('PROMOTION_PLAYBOOK.md',
    'AUTHORITY_MAP.md §6', the per-ADR §N) is
    consistent with the code.

== What this test does

For each of the 4 not-yet-promoted candidates:

  1. search 'src/' for the flag name;
  2. assert the flag is either absent (not yet
     in code) or set to @False@ literal;
  3. assert no @= True@ literal exists in
     production code.

For Family Divergence (ADR-0019, **promoted**), the
test asserts that the @familyDivergenceEnabled = True@
literal is at the documented location (Cascade.hs:74).

== What this test does NOT do

It does not assert that the env vars
(@QXFX0_*_ENABLED@) are @0@ or unset at test
time — those are runtime concerns. The test
locks the **code-level discipline**, not the
**runtime configuration**.
-}
module Test.Suite.PromotionFlagDiscipline
  ( promotionFlagDisciplineTests
  ) where

import Test.HUnit (Test (..), assertFailure, assertBool)

import Control.Exception (SomeException, catch)
import Prelude

import Data.List (isInfixOf, isPrefixOf)
import qualified Data.List as L
import qualified System.Directory as D
import qualified System.FilePath as FP

-- | A promotion candidate that is NOT YET promoted.
-- Flag must be absent or False in src/.
data PromotionCandidate = PromotionCandidate
  { pcName        :: !String
  , pcFlagName    :: !String     -- primary identifier in code
  , pcEnvVar      :: !String     -- env var name (may be same as pcFlagName)
  , pcDocLocation :: !String     -- documented location
  , pcInCode      :: !Bool       -- True if the flag is a Haskell-level literal
  }
  deriving stock (Eq, Show)

-- | The 4 not-yet-promoted candidates (Family Divergence is now promoted).
-- Order matches the playbook. The 'pcInCode' field is True
-- only for flags that are Haskell literals; env-var-only flags are False.
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

-- | Walk 'src/' recursively. Returns all .hs files.
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

-- | For a single not-yet-promoted candidate, assert the off-state.
assertCandidateOffState :: PromotionCandidate -> IO [String]
assertCandidateOffState pc = do
  files <- listHsFilesRecursive "src"
  contents <- mapM (\f -> do
                      c <- readFileOrEmpty f
                      return (f, c)) files
  let referencing = concat
        [ [ f <> ":" <> show lineNo <> ": " <> line
          | (lineNo, line) <- zip [1 :: Int ..] (L.lines c)
          , pcFlagName pc `L.isInfixOf` line
          ]
        | (f, c) <- contents
        ]
  let trueLiterals = filter (L.isInfixOf "= True") referencing
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

-- | The runtime check: the 4 not-yet-promoted candidates are at off-state.
promotionFlagOffState :: Test
promotionFlagOffState = TestLabel "4 not-yet-promoted candidates are at their documented off-state" $
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

-- | Family Divergence promoted check (ADR-0019). P2-2 split the original
-- @familyDivergenceEnabled@ into @salienceGuardDivergenceEnabled@ (Cascade.hs)
-- and @reconcileFamilyDivergence@ (TurnRouting.hs); the promoted @= True@
-- literal now lives on the salience-guard flag in Cascade.hs. (Grep by name,
-- not line number, to survive future moves within the file.)
familyDivergencePromotedCheck :: Test
familyDivergencePromotedCheck = TestLabel "Salience-guard divergence flag is promoted (= True) in Cascade.hs (ADR-0019, renamed by P2-2)" $
  TestCase $ do
    let path = "src/QxFx0/Core/TurnRouting/Cascade.hs"
    contents <- readFileOrEmpty path
    let linesWithTrue = filter
          (\line -> "salienceGuardDivergenceEnabled = True" `L.isInfixOf` line)
          (L.lines contents)
    assertBool
      ("Salience-guard divergence flag not found at promoted state "
       <> "(" <> path <> ", expected 'salienceGuardDivergenceEnabled = True' literal): "
       <> "ADR-0019 was accepted 2026-06-02; the flag should be True.")
      (not (null linesWithTrue))

-- ---------------------------------------------------------------------------
-- The test group
-- ---------------------------------------------------------------------------

promotionFlagDisciplineTests :: [Test]
promotionFlagDisciplineTests =
  [ promotionFlagOffState
  , familyDivergencePromotedCheck
  ]

