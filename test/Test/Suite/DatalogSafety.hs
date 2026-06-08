{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.DatalogSafety
  ( datalogSafetyTests
  ) where

import Test.HUnit
import qualified Data.Text as T
import Data.Text (Text)
import QxFx0.Bridge.Datalog.Support (escapeSymbol)

datalogSafetyTests :: [Test]
datalogSafetyTests =
  [ TestLabel "Datalog escapes left paren" testEscapesLeftParen
  , TestLabel "Datalog escapes right paren" testEscapesRightParen
  , TestLabel "Datalog escapes period" testEscapesPeriod
  , TestLabel "Datalog escapes percent" testEscapesPercent
  , TestLabel "Datalog escapes backslash" testEscapesBackslash
  , TestLabel "Datalog escapes double quote" testEscapesDoubleQuote
  , TestLabel "Datalog escapes newline" testEscapesNewline
  , TestLabel "Datalog escapes carriage return" testEscapesCarriageReturn
  , TestLabel "Datalog escapes tab" testEscapesTab
  , TestLabel "Datalog escapes multiple special chars" testEscapesMultipleSpecialChars
  , TestLabel "Datalog escapes parentheses pair" testEscapesParenthesesPair
  , TestLabel "Datalog escapes rule syntax" testEscapesRuleSyntax
  , TestLabel "Datalog escapes comment syntax" testEscapesCommentSyntax
  , TestLabel "Datalog blocks rule termination injection" testBlocksRuleTerminationInjection
  , TestLabel "Datalog blocks comment injection" testBlocksCommentInjection
  , TestLabel "Datalog blocks nested parentheses injection" testBlocksNestedParenthesesInjection
  , TestLabel "Datalog blocks period-based rule injection" testBlocksPeriodBasedRuleInjection
  , TestLabel "Datalog handles empty string" testHandlesEmptyString
  , TestLabel "Datalog handles only special chars" testHandlesOnlySpecialChars
  , TestLabel "Datalog preserves safe characters" testPreservesSafeCharacters
  , TestLabel "Datalog handles unicode characters" testHandlesUnicodeCharacters
  , TestLabel "Datalog handles mixed safe and unsafe" testHandlesMixedSafeAndUnsafe
  , TestLabel "Datalog no unescaped parens in output" testNoUnescapedParensInOutput
  , TestLabel "Datalog no unescaped periods in output" testNoUnescapedPeriodsInOutput
  , TestLabel "Datalog no unescaped percent in output" testNoUnescapedPercentInOutput
  , TestLabel "Datalog escapes atom tag name with parens" testEscapesAtomTagNameWithParens
  , TestLabel "Datalog escapes detail with period" testEscapesDetailWithPeriod
  , TestLabel "Datalog escapes payload with comment char" testEscapesPayloadWithCommentChar
  , TestLabel "Datalog escapes complex atom detail" testEscapesComplexAtomDetail
  ]

-- Basic escaping tests
testEscapesLeftParen :: Test
testEscapesLeftParen = TestCase $
  assertEqual "must escape left paren"
    "test\\(value"
    (escapeSymbol "test(value")

testEscapesRightParen :: Test
testEscapesRightParen = TestCase $
  assertEqual "must escape right paren"
    "test\\)value"
    (escapeSymbol "test)value")

testEscapesPeriod :: Test
testEscapesPeriod = TestCase $
  assertEqual "must escape period"
    "test\\.value"
    (escapeSymbol "test.value")

testEscapesPercent :: Test
testEscapesPercent = TestCase $
  assertEqual "must escape percent"
    "test\\%value"
    (escapeSymbol "test%value")

testEscapesBackslash :: Test
testEscapesBackslash = TestCase $
  assertEqual "must escape backslash"
    "test\\\\value"
    (escapeSymbol "test\\value")

testEscapesDoubleQuote :: Test
testEscapesDoubleQuote = TestCase $
  assertEqual "must escape double quote"
    "test\\\"value"
    (escapeSymbol "test\"value")

testEscapesNewline :: Test
testEscapesNewline = TestCase $
  assertEqual "must escape newline"
    "test\\nvalue"
    (escapeSymbol "test\nvalue")

testEscapesCarriageReturn :: Test
testEscapesCarriageReturn = TestCase $
  assertEqual "must escape carriage return"
    "test\\rvalue"
    (escapeSymbol "test\rvalue")

testEscapesTab :: Test
testEscapesTab = TestCase $
  assertEqual "must escape tab"
    "test\\tvalue"
    (escapeSymbol "test\tvalue")

-- Multiple special characters tests
testEscapesMultipleSpecialChars :: Test
testEscapesMultipleSpecialChars = TestCase $
  assertEqual "must escape multiple special chars"
    "test\\(\\.\\)\\%value"
    (escapeSymbol "test(.)%value")

testEscapesParenthesesPair :: Test
testEscapesParenthesesPair = TestCase $
  assertEqual "must escape parentheses pair"
    "func\\(arg\\)"
    (escapeSymbol "func(arg)")

testEscapesRuleSyntax :: Test
testEscapesRuleSyntax = TestCase $
  assertEqual "must escape Datalog rule syntax"
    "rule\\(X\\)\\."
    (escapeSymbol "rule(X).")

testEscapesCommentSyntax :: Test
testEscapesCommentSyntax = TestCase $
  assertEqual "must escape comment syntax"
    "\\% comment"
    (escapeSymbol "% comment")

-- Injection vector tests
testBlocksRuleTerminationInjection :: Test
testBlocksRuleTerminationInjection = TestCase $
  assertEqual "must block rule termination injection"
    "innocent\\)\\. EvilRule\\(\\\"attack"
    (escapeSymbol "innocent). EvilRule(\"attack")

testBlocksCommentInjection :: Test
testBlocksCommentInjection = TestCase $
  assertEqual "must block comment injection"
    "value\\% rest of line ignored"
    (escapeSymbol "value% rest of line ignored")

testBlocksNestedParenthesesInjection :: Test
testBlocksNestedParenthesesInjection = TestCase $
  assertEqual "must block nested parentheses injection"
    "outer\\(inner\\(deep\\)\\)"
    (escapeSymbol "outer(inner(deep))")

testBlocksPeriodBasedRuleInjection :: Test
testBlocksPeriodBasedRuleInjection = TestCase $
  assertEqual "must block period-based rule injection"
    "fact\\. NewRule\\(X\\)"
    (escapeSymbol "fact. NewRule(X)")

-- Edge case tests
testHandlesEmptyString :: Test
testHandlesEmptyString = TestCase $
  assertEqual "must handle empty string"
    ""
    (escapeSymbol "")

testHandlesOnlySpecialChars :: Test
testHandlesOnlySpecialChars = TestCase $
  assertEqual "must handle string with only special chars"
    "\\(\\)\\.\\%"
    (escapeSymbol "().%")

testPreservesSafeCharacters :: Test
testPreservesSafeCharacters = TestCase $
  assertEqual "must preserve safe characters"
    "SafeValue123_ABC"
    (escapeSymbol "SafeValue123_ABC")

testHandlesUnicodeCharacters :: Test
testHandlesUnicodeCharacters = TestCase $
  assertEqual "must handle unicode characters"
    "тест\\(значение\\)"
    (escapeSymbol "тест(значение)")

testHandlesMixedSafeAndUnsafe :: Test
testHandlesMixedSafeAndUnsafe = TestCase $
  assertEqual "must handle mixed safe and unsafe"
    "safe\\(unsafe\\)safe"
    (escapeSymbol "safe(unsafe)safe")

-- Property-style tests (manual verification)
testNoUnescapedParensInOutput :: Test
testNoUnescapedParensInOutput = TestCase $ do
  let inputs = ["test(value", "test)value", "func(arg)", "((nested))"]
      outputs = map escapeSymbol inputs
  mapM_ (\out -> do
    assertBool "output must not contain unescaped left paren" (not (hasUnescaped '(' out))
    assertBool "output must not contain unescaped right paren" (not (hasUnescaped ')' out))
    ) outputs

testNoUnescapedPeriodsInOutput :: Test
testNoUnescapedPeriodsInOutput = TestCase $ do
  let inputs = ["test.value", "rule(X).", "a.b.c"]
      outputs = map escapeSymbol inputs
  mapM_ (\out ->
    assertBool "output must not contain unescaped period" (not (hasUnescaped '.' out))
    ) outputs

testNoUnescapedPercentInOutput :: Test
testNoUnescapedPercentInOutput = TestCase $ do
  let inputs = ["test%value", "% comment", "100%"]
      outputs = map escapeSymbol inputs
  mapM_ (\out ->
    assertBool "output must not contain unescaped percent" (not (hasUnescaped '%' out))
    ) outputs

-- Helper function to check if a character appears unescaped (not preceded by backslash)
hasUnescaped :: Char -> Text -> Bool
hasUnescaped ch txt = go (T.unpack txt)
  where
    go [] = False
    go [c] = c == ch
    go (c1:c2:rest)
      | c1 == '\\' && c2 == ch = go rest  -- escaped, skip both
      | c1 == ch = True  -- unescaped match
      | otherwise = go (c2:rest)

-- Real-world scenario tests
testEscapesAtomTagNameWithParens :: Test
testEscapesAtomTagNameWithParens = TestCase $
  assertEqual "must escape atom tag name with parens"
    "CustomAtom:test\\(value\\)"
    (escapeSymbol "CustomAtom:test(value)")

testEscapesDetailWithPeriod :: Test
testEscapesDetailWithPeriod = TestCase $
  assertEqual "must escape detail with period"
    "sentence\\.end"
    (escapeSymbol "sentence.end")

testEscapesPayloadWithCommentChar :: Test
testEscapesPayloadWithCommentChar = TestCase $
  assertEqual "must escape payload with comment char"
    "payload\\%20encoded"
    (escapeSymbol "payload%20encoded")

testEscapesComplexAtomDetail :: Test
testEscapesComplexAtomDetail = TestCase $
  assertEqual "must escape complex atom detail"
    "Searching\\(query\\.term\\)\\%detail"
    (escapeSymbol "Searching(query.term)%detail")

