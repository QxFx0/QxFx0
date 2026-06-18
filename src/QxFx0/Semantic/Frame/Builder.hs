{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : QxFx0.Semantic.Frame.Builder
Description : Composes SemanticFrame from SemanticIntent + topic extraction.

Converts classified intents into structured frames that carry enough
semantic information for compositional text generation.
-}
module QxFx0.Semantic.Frame.Builder
  ( buildFrame
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Semantic.Intent.Classifier (SemanticIntent(..))
import QxFx0.Semantic.Frame.Types

-- | Build a SemanticFrame from a classified intent.
--
-- The frame carries the semantic payload needed for generation.
-- Topic extraction is done here (from content nouns or raw text)
-- so that the generator receives pre-resolved content.
buildFrame :: SemanticIntent -> Text -> SemanticFrame
buildFrame intent rawText = case intent of
  IntentDefine topic ->
    DefinitionFrame
      { dfTopic = topic
      , dfScope = GeneralScope
      , dfAuthority = Known
      }

  IntentDistinguish left right ->
    DistinctionFrame
      { distLeft = left
      , distRight = right
      , distCriteria = []
      }

  IntentChallenge ->
    ChallengeFrame
      { chTarget = extractTarget rawText
      , chBasis = extractBasis rawText
      , chStrength = classifyStrength rawText
      }

  IntentGround topic ->
    GroundFrame
      { gfTopic = topic
      , gfDepth = Detailed
      }

  IntentRepair -> RepairFrame

  IntentContact ->
    ContactFrame
      { cfGreeting = extractGreeting rawText
      }

  IntentReflect ->
    ReflectFrame
      { rfTopic = extractTopic rawText
      }

  IntentLearn topic ->
    LearnFrame
      { lfTopic = topic
      , lfDepth = Detailed
      }

  IntentHelp task ->
    HelpFrame
      { hfTask = task
      }

  IntentPurpose topic ->
    PurposeFrame
      { pfTopic = topic
      }

  IntentWorldCause topic ->
    WorldCauseFrame
      { wcTopic = topic
      }

  IntentDeepen topic ->
    DeepenFrame
      { dpTopic = topic
      }

  IntentNextStep -> NextStepFrame

  IntentExploratory -> ExploratoryFrame

  IntentOperational -> OperationalFrame

  IntentSelfReference -> SelfReferenceFrame

  IntentUnknown _ ->
    GenericFrame
      { gfContent = rawText
      }

-- ---------------------------------------------------------------------------
-- Topic extraction helpers (deterministic, not keyword-based)
-- ---------------------------------------------------------------------------

-- | Extract topic from raw text (simple: take content words after common verbs).
extractTopic :: Text -> Text
extractTopic rawText =
  let stripped = T.strip rawText
      lower = T.toLower stripped
  in if "что такое " `T.isPrefixOf` lower
     then T.drop 10 stripped
     else if "расскажи о " `T.isPrefixOf` lower
          then T.drop 11 stripped
          else if "помоги с " `T.isPrefixOf` lower
               then T.drop 9 stripped
               else stripped

-- | Extract the target of a challenge from raw text.
-- E.g., "это неверно" → "это"
extractTarget :: Text -> Text
extractTarget rawText =
  let stripped = T.strip (T.toLower rawText)
  in if "это " `T.isPrefixOf` stripped
     then T.drop 3 stripped
     else stripped

-- | Extract the basis of a challenge from raw text.
-- E.g., "противоречит опыту" → "противоречит опыту"
extractBasis :: Text -> Text
extractBasis rawText =
  let lower = T.toLower rawText
  in if "противоречит " `T.isInfixOf` lower
     then let idx = T.count "противоречит " lower
          in T.take (idx + 20) rawText  -- crude but deterministic
     else if "неверно" `T.isInfixOf` lower
          then "это утверждение неверно"
          else rawText

-- | Classify challenge strength from text markers.
classifyStrength :: Text -> FrameStrength
classifyStrength rawText
  | any (`T.isInfixOf` T.toLower rawText)
      ["спорю", "возраж", "категорически", "абсолютно неверно"]
    = Firm
  | otherwise = Soft

-- | Extract greeting from raw text.
extractGreeting :: Text -> Text
extractGreeting rawText
  | any (`T.isInfixOf` T.toLower rawText) ["привет", "hello", "hi", "хай"]
    = "Привет"
  | any (`T.isInfixOf` T.toLower rawText) ["здравствуй", "добрый день"]
    = "Здравствуй"
  | any (`T.isInfixOf` T.toLower rawText) ["как дела", "как жизнь"]
    = "Привет"
  | otherwise = "Здравствуй"
