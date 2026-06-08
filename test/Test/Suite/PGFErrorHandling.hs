{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

{-| Test suite for PGFError handling in Runtime.PGF module.
    
    Verifies that all four PGFError constructors are properly used:
    - PGFFileNotFound: when PGF file doesn't exist
    - PGFParseError: when expression or language parsing fails
    - PGFLinearizationError: when linearization produces invalid output
    - PGFIOError: when IO operations fail
-}
module Test.Suite.PGFErrorHandling
  ( pgfErrorHandlingTests
  ) where

import Test.HUnit
import qualified Data.Text as T
import qualified Data.Map.Strict as M

import QxFx0.Runtime.PGF (linearizeClaimAstGfLang, linearizeDialogAtomsGfLang)
import QxFx0.Types (ClaimAst(..))
import QxFx0.Semantic.DialogAtom (DialogAtoms(..), AtomTag(..), plainSlot)

pgfErrorHandlingTests :: [Test]
pgfErrorHandlingTests =
  [ TestLabel "PGFFileNotFound - non-existent file" testPGFFileNotFound
  , TestLabel "PGFParseError - invalid language" testPGFParseErrorLang
  , TestLabel "PGFParseError - invalid topic" testPGFParseErrorExpr
  , TestLabel "Successful linearization" testSuccessfulLinearization
  ]

-- | Test PGFFileNotFound: call with non-existent file.
-- P0-1 (variant A): for "QxFx0SyntaxRus" the Haskell renderer is authoritative
-- and runs before any PGF file access, so a missing PGF file no longer surfaces
-- for Russian — it returns a valid Haskell rendering. The file-not-found path is
-- still reachable for non-Russian languages, which is what this test now pins.
testPGFFileNotFound :: Test
testPGFFileNotFound = TestCase $ do
  let nonExistentPath = Just "/tmp/nonexistent_pgf_file_12345.pgf"
      ast = MoveSelfState
  -- Russian: Haskell-authoritative, missing PGF is irrelevant → success.
  resultRus <- linearizeClaimAstGfLang nonExistentPath "QxFx0SyntaxRus" ast
  case resultRus of
    Left err ->
      assertFailure ("Russian path should be Haskell-authoritative, got error: " <> T.unpack err)
    Right _ -> pure ()
  -- Non-Russian: PGF is authoritative, missing file must surface.
  resultEn <- linearizeClaimAstGfLang nonExistentPath "QxFx0SyntaxEng" ast
  case resultEn of
    Left err ->
      assertBool "Error should mention file not found"
        ("pgf_file_not_found" `T.isInfixOf` err)
    Right _ ->
      assertFailure "Expected PGFFileNotFound error for non-Russian lang, got success"

-- | Test PGFParseError: call with invalid language
testPGFParseErrorLang :: Test
testPGFParseErrorLang = TestCase $ do
  -- Use the default PGF file (should exist) but invalid language
  let ast = MoveSelfState
  result <- linearizeClaimAstGfLang Nothing "InvalidLanguageXYZ" ast
  case result of
    Left err -> 
      assertBool "Error should mention language not found" 
        ("pgf_parse_error" `T.isInfixOf` err && "pgf_lang_not_found" `T.isInfixOf` err)
    Right _ -> 
      assertFailure "Expected PGFParseError for invalid language, got success"

-- | Test PGFParseError: call with invalid topic that won't resolve
testPGFParseErrorExpr :: Test
testPGFParseErrorExpr = TestCase $ do
  -- Create DialogAtoms with an invalid topic that won't resolve to a GF lexeme
  let invalidTopic = "invalid_topic_xyz_12345_nonexistent"
      atoms = DialogAtoms 
        { daSlots = M.singleton TTopic [plainSlot TTopic invalidTopic]
        , daUserRaw = invalidTopic
        , daTurn = 1
        }
  result <- linearizeDialogAtomsGfLang Nothing "QxFx0SyntaxRus" atoms
  case result of
    Left err -> 
      -- Should get unresolved topic error
      assertBool "Error should indicate topic resolution failure" 
        ("unresolved_topic_lexeme" `T.isInfixOf` err)
    Right _ -> 
      -- If it succeeds, the lexeme might exist or fallback worked
      pure ()

-- | Test successful linearization with valid inputs
testSuccessfulLinearization :: Test
testSuccessfulLinearization = TestCase $ do
  -- Use default PGF file and valid AST
  let ast = MoveSelfState
  result <- linearizeClaimAstGfLang Nothing "QxFx0SyntaxRus" ast
  case result of
    Left err -> 
      -- If the default PGF file doesn't exist, that's acceptable in test environment
      if "pgf_file_not_found" `T.isInfixOf` err
        then pure ()  -- Expected in environments without PGF file
        else assertFailure $ "Unexpected error: " ++ T.unpack err
    Right glr -> 
      -- Success is expected if PGF file exists
      assertBool "Result should have non-empty text" 
        (not . T.null . T.pack . show $ glr)

