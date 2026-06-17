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
The promotion candidates are:

  * **Family Divergence** (ADR-0019 accepted 2026-06-02) —
    @salienceGuardDivergenceEnabled = True@ literal at
    @src/QxFx0/Core/TurnRouting/Cascade.hs@.
    **PROMOTED** — flag is in the live authority path.
  * **Essence Commitment** (ADR-0036, Policy A 2026-06-17) —
    law-driven, not flag-gated. @rrEssenceActive = True@ in
    @RuntimeRegime.hs@ matches the unconditional @shouldCommit@
    runtime law. The @essenceCommitmentEnabled@ flag designed in
    ADR-0012 §10.1 was **never implemented**; this test verifies
    the actual mechanism, not the historical design.
    **PROMOTED (structural law; not M6-FELT evidence).**
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

For each of the 3 not-yet-promoted env-var candidates:

  1. search 'src/' for the flag name;
  2. assert the flag is either absent (not yet
     in code) or set to @False@ literal;
  3. assert no @= True@ literal exists in
     production code.

For Family Divergence (ADR-0019, **promoted**), the
test asserts that the @salienceGuardDivergenceEnabled = True@
literal is at the documented location (Cascade.hs).

For Essence Commitment (ADR-0036, Policy A **promoted as
law-driven**), the test asserts two things that must hold
together:
  1. @rrEssenceActive = True@ in @RuntimeRegime.hs@;
  2. the @shouldCommit@ call site in @Finalize/State.hs@
     is unconditional (the "no feature flag" comment is
     present), confirming the regime stamp matches the
     runtime law rather than a flag that does not exist.

It also asserts the historical @essenceCommitmentEnabled@
flag is **absent** from 'src/' (it was designed in ADR-0012
§10.1 but never implemented).

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

-- | The 3 not-yet-promoted env-var candidates. Essence was removed from
-- this list on 2026-06-17 (Policy A: promoted as law-driven, verified by
-- 'essenceLawDrivenPromotedCheck' instead). Family Divergence is verified
-- by 'familyDivergencePromotedCheck'.
promotionCandidates :: [PromotionCandidate]
promotionCandidates =
  [ PromotionCandidate
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

-- | The runtime check: the 3 not-yet-promoted env-var candidates are at
-- off-state. (Essence was removed 2026-06-17 Policy A — verified by
-- 'essenceLawDrivenPromotedCheck' instead.)
promotionFlagOffState :: Test
promotionFlagOffState = TestLabel "3 not-yet-promoted env-var candidates are at their documented off-state" $
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

-- | Essence Commitment promoted check (ADR-0036, Policy A 2026-06-17).
-- Essence is law-driven, not flag-gated. This test verifies the two
-- facts that must hold together for the regime to be honest:
--
-- 1. @rrEssenceActive = True@ in @RuntimeRegime.hs@ (the regime stamp).
-- 2. The @shouldCommit@ call site in @Finalize/State.hs@ carries the
--    "no feature flag" comment, confirming the regime stamp matches an
--    unconditional runtime law rather than a flag that does not exist.
--
-- It also asserts the historical @essenceCommitmentEnabled@ flag is
-- absent from 'src/' (designed in ADR-0012 §10.1, never implemented).
essenceLawDrivenPromotedCheck :: Test
essenceLawDrivenPromotedCheck = TestLabel "Essence is law-driven (rrEssenceActive=True matches unconditional shouldCommit; historical flag absent) (ADR-0036 Policy A)" $
  TestCase $ do
    -- 1. regime stamp
    let regimePath = "src/QxFx0/Types/RuntimeRegime.hs"
    regimeContents <- readFileOrEmpty regimePath
    let regimeTrue = filter
          (\line -> "rrEssenceActive" `L.isInfixOf` line && "= True" `L.isInfixOf` line)
          (L.lines regimeContents)
    assertBool
      ("rrEssenceActive = True not found in " <> regimePath
       <> ": ADR-0036 Policy A (2026-06-17) requires the regime to stamp Essence active.")
      (not (null regimeTrue))
    -- 2. unconditional shouldCommit (the "no feature flag" marker)
    let finalizePath = "src/QxFx0/Core/TurnPipeline/Finalize/State.hs"
    finalizeContents <- readFileOrEmpty finalizePath
    let noFlagMarker = filter
          (\line -> "no feature flag" `L.isInfixOf` line)
          (L.lines finalizeContents)
    assertBool
      ("The 'no feature flag' marker was not found in " <> finalizePath
       <> ": rrEssenceActive=True must match an unconditional shouldCommit, not a gate.")
      (not (null noFlagMarker))
    -- 3. historical flag absent from src/
    files <- listHsFilesRecursive "src"
    fileContents <- mapM (\f -> do c <- readFileOrEmpty f; return (f, c)) files
    let flagRefs = concat
          [ [ f <> ":" <> show lineNo <> ": " <> line
            | (lineNo, line) <- zip [1 :: Int ..] (L.lines c)
            , "essenceCommitmentEnabled" `L.isInfixOf` line
            ]
          | (f, c) <- fileContents
          ]
    assertBool
      ("essenceCommitmentEnabled (historical, ADR-0012 §10.1) should be ABSENT from src/ "
       <> "but was found: " <> unlines flagRefs)
      (null flagRefs)

-- ---------------------------------------------------------------------------
-- The test group
-- ---------------------------------------------------------------------------

promotionFlagDisciplineTests :: [Test]
promotionFlagDisciplineTests =
  [ promotionFlagOffState
  , familyDivergencePromotedCheck
  , essenceLawDrivenPromotedCheck
  ]

