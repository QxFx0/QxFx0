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
import QxFx0.Semantic.Content.AtomStore (allTopics)

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
    let (left', right') = case distinctionPairFromRaw rawText of
          Just pair -> pair
          Nothing -> (left, right)
    in
    DistinctionFrame
      { distLeft = left'
      , distRight = right'
      , distCriteria = []
      }

  IntentChallenge ->
    ChallengeFrame
      { chTarget = extractTarget rawText
      , chBasis = extractBasis rawText
      , chStrength = classifyStrength rawText
      , chRawText = rawText
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
      raw = if "что такое " `T.isPrefixOf` lower
            then T.drop 10 stripped
            else if "расскажи о " `T.isPrefixOf` lower
                 then T.drop 11 stripped
                 else if "помоги с " `T.isPrefixOf` lower
                      then T.drop 9 stripped
                      else stripped
  in stripTrailingPunctuation raw

-- | Strip trailing punctuation marks (?, !, ., etc.) from topic.
stripTrailingPunctuation :: Text -> Text
stripTrailingPunctuation = T.dropWhileEnd (`elem` ("?!.,;:" :: String))

distinctionPairFromRaw :: Text -> Maybe (Text, Text)
distinctionPairFromRaw rawText =
  let normalized = T.unwords (T.words (T.toLower rawText))
      clean = stripTrailingPunctuation . T.strip
  in case T.breakOn "между " normalized of
       (_, afterBetween)
         | not (T.null afterBetween) -> do
             rest <- T.stripPrefix "между " afterBetween
             let (left, rightRaw) = T.breakOn " и " rest
             right <- T.stripPrefix " и " rightRaw
             let leftClean = clean left
                 rightClean = clean right
             if T.null leftClean || T.null rightClean
               then Nothing
               else Just (leftClean, rightClean)
       _ -> Nothing

-- | Extract the target of a challenge from raw text.
-- E.g., "это неверно" → "это"
extractTarget :: Text -> Text
extractTarget rawText =
  let lowered = T.toLower rawText
      -- Check all known topics from AtomStore, not just hardcoded subset
      matchTopic topic = if T.take 5 topic `T.isInfixOf` lowered
                           then Just topic
                           else Nothing
      matchedTopic = case [ t | t <- allTopics, matchTopic t /= Nothing ] of
        (t:_) -> Just t
        [] -> Nothing
  in case matchedTopic of
       Just t -> t
       Nothing ->
         -- Fallback: generic patterns
         if "противореч" `T.isInfixOf` lowered
           then "возможное противоречие"
         else if "произвол" `T.isInfixOf` lowered
           then "границу между свободой и произволом"
         else if "мнение" `T.isInfixOf` lowered
           then "границу между истиной и мнением"
         else "исходный тезис"

-- | Extract the basis of a challenge from raw text.
-- E.g., "противоречит опыту" → "противоречит опыту"
extractBasis :: Text -> Text
extractBasis rawText =
  let lower = T.toLower rawText
  in if "не соглас" `T.isInfixOf` lower
       then "контрпример не сводится к исходному тезису"
     else if "разве" `T.isInfixOf` lower || "противореч" `T.isInfixOf` lower
       then "возражение указывает на возможный контрпример"
     else if "неверно" `T.isInfixOf` lower
       then "утверждение оспаривается"
     else "возражение требует проверки рамки"

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
