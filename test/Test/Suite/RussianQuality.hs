{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.RussianQuality
  ( russianQualityTests
  ) where

import Test.HUnit
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Set as Set

import QxFx0.Types
import qualified QxFx0.Core.TurnPlanning as TurnPlanning
import qualified QxFx0.Semantic.Proposition as Proposition
import QxFx0.Semantic.Input.Parse (emptyParsedInput)
import QxFx0.Resources (loadMorphologyData)
import QxFx0.Render.Dialogue
  ( renderDialogueArtifact
  , renderArtifactViaAssembly
  , hasStructuredDialogueSurface
  , draRenderedText
  , draFallbackReason
  , draLinearizationOk
  )
import QxFx0.Semantic.Lexicon.RuntimeParadigms (emptyRuntimeParadigms)

russianQualityTests :: [Test]
russianQualityTests =
  [ TestLabel "RU structured prompts produce non-empty surfaces" testStructuredPromptsNonEmpty
  , TestLabel "RU generative prompts are not single canned sentence" testGenerativeDiversity
  , TestLabel "RU assembly path avoids gf_no_output fallback" testAssemblyAvoidsNoOutput
  , TestLabel "RU fallback reason keeps branch tag for linearization failure" testTaggedFallbackReason
  ]

testStructuredPromptsNonEmpty :: Test
testStructuredPromptsNonEmpty = TestCase $ do
  md <- loadMorphologyData
  let prompts =
        [ "поговорим о логике?"
        , "что ты знаешь о себе?"
        , "в чём функция стола?"
        , "почему небо голубое?"
        , "следующий шаг?"
        ]
  mapM_ (assertPromptRenders md) prompts

testGenerativeDiversity :: Test
testGenerativeDiversity = TestCase $ do
  md <- loadMorphologyData
  let prompts =
        [ "скажи интересную мысль"
        , "а ещё одну мысль"
        , "скажи логичную мысль"
        ]
      rendered = map (renderForPrompt md) prompts
      uniqueRendered = Set.fromList rendered
  assertBool "all generative outputs must be non-empty"
    (all (not . T.null . T.strip) rendered)
  assertBool "generative outputs should not collapse to one canned phrase"
    (Set.size uniqueRendered >= 2)

testAssemblyAvoidsNoOutput :: Test
testAssemblyAvoidsNoOutput = TestCase $ do
  md <- loadMorphologyData
  let prompts =
        [ "поговорим о логике?"
        , "что ты знаешь о себе?"
        , "в чём функция стола?"
        ]
  mapM_ (assertAssemblyNotEmpty md) prompts

testTaggedFallbackReason :: Test
testTaggedFallbackReason = TestCase $ do
  md <- loadMorphologyData
  let frame = emptyInputPropositionFrame
        { ipfRawText = "ты работаешь?"
        , ipfPropositionType = "OperationalStatusQ"
        , ipfFocusEntity = "система"
        , ipfSemanticSubject = "система"
        , ipfCanonicalFamily = CMGround
        }
      rmp0 = TurnPlanning.buildRMP CMGround frame "система" emptyEgoState emptyAtomTrace True
      rcp = TurnPlanning.buildRCP CMGround rmp0
      rmpBroken = rmp0 { rmpPrimaryClaimAst = Just (ClaimPurpose "") }
      artifact = renderDialogueArtifact frame rmpBroken rcp "система" [] md
  assertBool "forced broken AST should trigger linearization fallback"
    (not (draLinearizationOk artifact))
  assertEqual "fallback reason should preserve exact branch tag"
    (Just "gf_linearization_failed:operational_status")
    (draFallbackReason artifact)

assertPromptRenders :: MorphologyData -> Text -> Assertion
assertPromptRenders md prompt = do
  let frame = Proposition.parseProposition prompt
      family = ipfCanonicalFamily frame
      topic = nonEmpty (ipfFocusEntity frame) "тема"
      rmp = TurnPlanning.buildRMP family frame topic emptyEgoState emptyAtomTrace True
      rcp = TurnPlanning.buildRCP family rmp
      artifact = renderDialogueArtifact frame rmp rcp topic [] md
      rendered = draRenderedText artifact
  assertBool ("rendered text must be non-empty for prompt: " <> T.unpack prompt)
    (not (T.null (T.strip rendered)))
  assertBool ("structured prompts must avoid hard no-output fallback: " <> T.unpack prompt)
    (not (hasStructuredDialogueSurface frame && draFallbackReason artifact == Just "gf_no_output"))

assertAssemblyNotEmpty :: MorphologyData -> Text -> Assertion
assertAssemblyNotEmpty md prompt = do
  let frame = Proposition.parseProposition prompt
      family = ipfCanonicalFamily frame
      topic = nonEmpty (ipfFocusEntity frame) "тема"
      rmp = TurnPlanning.buildRMP family frame topic emptyEgoState emptyAtomTrace True
      rcp = TurnPlanning.buildRCP family rmp
      artifact =
        renderArtifactViaAssembly
          emptyRuntimeParadigms
          emptySystemState
          frame
          rmp
          rcp
          topic
          []
          md
          (rcpStyle rcp)
          (emptyParsedInput prompt)
          Nothing
          Nothing
  assertBool ("assembly output must be non-empty for prompt: " <> T.unpack prompt)
    (not (T.null (T.strip (draRenderedText artifact))))
  assertBool ("assembly path must not end with gf_no_output for prompt: " <> T.unpack prompt)
    (draFallbackReason artifact /= Just "gf_no_output")

renderForPrompt :: MorphologyData -> Text -> Text
renderForPrompt md prompt =
  let frame = Proposition.parseProposition prompt
      family = ipfCanonicalFamily frame
      topic = nonEmpty (ipfFocusEntity frame) "тема"
      rmp = TurnPlanning.buildRMP family frame topic emptyEgoState emptyAtomTrace True
      rcp = TurnPlanning.buildRCP family rmp
      artifact = renderDialogueArtifact frame rmp rcp topic [] md
  in T.strip (draRenderedText artifact)

nonEmpty :: Text -> Text -> Text
nonEmpty preferred fallback
  | T.null (T.strip preferred) = fallback
  | otherwise = preferred
