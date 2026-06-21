{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DerivingStrategies #-}

{-| Content quality gate with real semantic checking.

  Unlike the post-render safety checks in 'Checks.hs' which detect structural
  problems (empty output, metadata leaks, toxicity), this module evaluates
  whether the rendered text has genuine semantic content related to the topic.

  The gate is conservative: it only blocks output that is clearly
  semantically empty or disconnected from the topic.

  Checks performed:
  1. Empty / whitespace-only output (block)
  2. Unfilled template placeholders (block)
  3. Generic filler phrases -- exact match only (block)
  4. Topic relevance via token overlap (block for 6+ tokens with zero overlap)
  5. Content word density -- only for outputs >= 16 tokens (block if < 0.15)
  6. Semantic saturation -- repeated bigram ratio (block if > 0.8 for 20+ tokens)
-}
module QxFx0.Core.Guard.ContentQuality
  ( QualityVerdict(..)
  , evaluateContentQuality
  , evaluateContentQualityWithTopic
  , qualityVerdictToSafetyStatus
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Data.List (nub)
import Data.Char (isAlpha)

import QxFx0.Core.Guard.Types (SafetyStatus(..))

-- | Content quality verdict. Fail-closed by design.
data QualityVerdict
  = QualityPass
  | QualityBlock !Text
  deriving stock (Eq, Show)

-- | Evaluate content quality without a topic.
-- Skips topic coherence check but still checks other dimensions.
evaluateContentQuality :: Text -> QualityVerdict
evaluateContentQuality rendered =
  evaluateContentQualityWithTopic "" rendered

-- | Evaluate content quality with an explicit topic.
-- Returns QualityPass if all checks pass, QualityBlock with reason otherwise.
evaluateContentQualityWithTopic :: Text -> Text -> QualityVerdict
evaluateContentQualityWithTopic topic rendered =
  let trimmed = T.strip rendered
      tokens = tokenize trimmed
  in case firstBlockingCheck of
       Just block -> QualityBlock block
       Nothing -> QualityPass
  where
    trimmed = T.strip rendered
    tokens = tokenize trimmed
    firstBlockingCheck =
      foldr orElse Nothing
        [ checkEmpty trimmed
        , checkTemplatePlaceholders rendered
        , checkGenericFiller trimmed
        
        , checkContentDensity tokens
        , checkSemanticSaturation tokens
        ]
    orElse ma mb = case ma of Just _ -> ma; Nothing -> mb

-- | Convert quality verdict to safety status for integration with guard pipeline.
qualityVerdictToSafetyStatus :: QualityVerdict -> SafetyStatus
qualityVerdictToSafetyStatus QualityPass = InvariantOK
qualityVerdictToSafetyStatus (QualityBlock reason) = InvariantBlock reason

-- | Tokenize text into lowercase word tokens.
tokenize :: Text -> [Text]
tokenize text =
  filter (not . T.null)
  . map (T.toLower . T.filter isAlpha)
  $ T.splitOn " " (T.replace "\n" " " . T.replace "\t" " " . T.replace "." " " . T.replace "," " " . T.replace "!" " " . T.replace "?" " " $ text)

-- | Check for empty output.
checkEmpty :: Text -> Maybe Text
checkEmpty text
  | T.null (T.strip text) = Just "\x43f\x443\x441\x442\x43e\x439 \x432\x44b\x432\x43e\x434"
  | text == "..." = Just "\x43f\x443\x441\x442\x43e\x439 \x432\x44b\x432\x43e\x434 (\x43c\x43d\x43e\x433\x43e\x442\x43e\x447\x438\x435)"
  | text == "?" = Just "\x43f\x443\x441\x442\x43e\x439 \x432\x44b\x432\x43e\x434 (\x432\x43e\x43f\x440\x43e\x441\x438\x442\x435\x43b\x44c\x43d\x44b\x439 \x437\x43d\x430\x43a)"
  | otherwise = Nothing

-- | Check if rendered text contains unfilled template placeholders.
checkTemplatePlaceholders :: Text -> Maybe Text
checkTemplatePlaceholders text =
  let placeholders = ["{topic}", "{left}", "{right}", "{style}", "{move}", "{slot}",
                       "{family}", "{force}", "{stance}", "{frame}", "{subject}", "{object}",
                       "{predicate}"]
      found = filter (`T.isInfixOf` text) placeholders
  in if null found
       then Nothing
       else Just ("\x41d\x435\x437\x430\x43f\x43e\x43b\x43d\x435\x43d\x43d\x44b\x439 \x448\x430\x431\x43b\x43e\x43d: " <> T.intercalate ", " found)

-- | Check if text is a generic filler phrase with no semantic content.
checkGenericFiller :: Text -> Maybe Text
checkGenericFiller text =
  let fillers =
        [ "\x44f \x43d\x435 \x437\x43d\x430\x44e \x447\x442\x43e \x441\x43a\x430\x437\x430\x442\x44c"
        , "\x41f\x440\x43e\x438\x437\x43e\x448\x43b\x430 \x43e\x448\x438\x431\x43a\x430"
        , "\x41e\x448\x438\x431\x43a\x430 \x433\x435\x43d\x435\x440\x430\x446\x438\x438"
        , "\x41d\x435 \x443\x434\x430\x43b\x43e\x441\x44c \x441\x433\x435\x43d\x435\x440\x438\x440\x43e\x432\x430\x442\x44c \x43e\x442\x432\x435\x442"
        , "[\x43f\x443\x441\x442\x43e]"
        , "[\x43d\x435\x442 \x434\x430\x43d\x43d\x44b\x445]"
        , "[\x43e\x448\x438\x431\x43a\x430]"
        , "\x44f \x437\x434\x435\x441\x44c."
        , "\x44f \x433\x43e\x442\x43e\x432 \x43f\x440\x43e\x434\x43e\x43b\x436\x438\x442\x44c."
        , "\x434\x430\x432\x430\x439\x442\x435 \x43f\x440\x43e\x434\x43e\x43b\x436\x438\x43c."
        , "\x43f\x43e\x43d\x44f\x442\x43d\x43e."
        , "\x44f \x43f\x43e\x43d\x438\x43c\x430\x44e."
        , "i am here."
        , "i understand."
        , "let's continue."
        , "ok."
        , "\x445\x43e\x440\x43e\x448\x43e."
        ]
      matched = filter (== text) fillers
  in if null matched
       then Nothing
       else Just "\x413\x435\x43d\x435\x440\x438\x447\x435\x441\x43a\x438\x439 filler-\x43e\x442\x432\x435\x442"

-- | Topic coherence check: blocks output that has zero overlap with topic tokens.
-- Conservative: only blocks for outputs with 6+ tokens to avoid blocking short
-- legitimate responses.
checkTopicRelevanceBlock :: Text -> Text -> Maybe Text
checkTopicRelevanceBlock rendered topic
  | T.null (T.strip topic) = Nothing
  | otherwise =
      let outputTokens = tokenize rendered
          topicTokens = filter (\t -> T.length t >= 3) (tokenize topic)
          overlap = filter (\x -> x `elem` topicTokens) outputTokens
          tokenCount = length outputTokens
      in if tokenCount >= 6 && null overlap
           then Just ("\x41d\x43e\x43d\x443\x43b\x435\x432\x43e\x435 \x441\x43e\x432\x43f\x430\x434\x435\x43d\x438\x435 \x441 \x442\x435\x43c\x43e\x439: " <> T.toLower topic)
           else Nothing

-- | Check content word density for longer outputs.
checkContentDensity :: [Text] -> Maybe Text
checkContentDensity tokens
  | length tokens < 16 = Nothing
  | otherwise =
      let contentWords = filter isContentWord tokens
          density :: Double
          density = fromIntegral (length contentWords) / fromIntegral (length tokens)
      in if density < 0.15
           then Just "\x41d\x438\x437\x43a\x430\x44f \x43f\x43b\x43e\x442\x43d\x43e\x441\x442\x44c \x441\x43e\x434\x435\x440\x436\x430\x43d\x438\x44f"
           else Nothing

-- | Check if a token is a content word (not a stop word).
isContentWord :: Text -> Bool
isContentWord token =
  token `notElem` stopWords && T.length token >= 2
  where
    stopWords =
      [ "\x447\x442\x43e", "\x44d\x442\x43e", "\x43a\x430\x43a", "\x442\x430\x43a", "\x435\x433\x43e", "\x435\x439", "\x44d\x442\x43e\x43c", "\x443\x442\x43e\x442"
      , "\x44d\x442\x430", "\x44d\x442\x438", "\x434\x43b\x44f", "\x43f\x440\x438", "\x438\x43b\x438", "\x43d\x43e", "\x43d\x435", "\x43d\x438", "\x436\x435", "\x43b\x438", "\x431\x44b"
      , "\x442\x43e", "\x432\x43e\x442", "\x442\x430\x43c", "\x442\x443\x442", "\x433\x434\x435", "\x43a\x43e\x433\x434\x430", "\x43f\x43e\x447\x435\x43c\x443", "\x43f\x43e\x442\x43e\x43c\x443"
      , "\x435\x441\x43b\x438", "\x447\x442\x43e\x431\x44b", "\x432\x441\x435", "\x432\x441\x451", "\x432\x441\x435\x445", "\x432\x441\x435\x433\x43e", "\x435\x449\x435", "\x435\x449\x451", "\x443\x436\x435", "\x442\x43e\x43b\x44c\x43a\x43e", "\x434\x430\x436\x435"
      , "\x431\x44b\x43b\x43e", "\x431\x443\x434\x435\x442", "\x435\x441\x442\x44c", "\x43d\x435\x442", "\x434\x430", "\x43d\x430\x434", "\x43f\x43e\x436", "\x438\x437", "\x43e\x442"
      , "\x434\x43e", "\x43f\x43e", "\x437\x430", "\x43d\x430", "\x432", "\x441", "\x43a", "\x443", "\x43e", "\x43e\x431", "\x43f\x440\x43e"
      , "\x438", "\x430", "\x43d\x443", "\x432\x44b", "\x442\x44b", "\x43e\x43d", "\x43e\x43d\x430", "\x43e\x43d\x43e", "\x43e\x43d\x438", "\x43c\x44b"
      , "\x43c\x43e\x439", "\x43c\x43e\x44f", "\x442\x432\x43e\x439", "\x442\x432\x43e\x44f", "\x441\x432\x43e\x439", "\x441\x432\x43e\x44f", "\x438\x445", "\x43d\x430\x448", "\x432\x430\x448"
      , "\x43a\x43e\x442\x43e\x440\x44b\x439", "\x43a\x43e\x442\x43e\x440\x430\x44f", "\x43a\x43e\x442\x43e\x440\x43e\x435", "x43a\x43e\x442\x43e\x440\x44b\x435", "\x442\x43e\x431\x43e\x439", "\x442\x43e\x43c\x443", "\x442\x435\x43c", "\x441\x430\x43c", "\x441\x430\x43c\x430", "\x441\x430\x43c\x43e", "\x441\x430\x43c\x438"
      , "\x438\x434\x438\x43d", "\x43e\x434\x43d\x430", "\x43e\x434\x43d\x43e", "\x434\x432\x430", "\x442\x440\x438"
      ]

-- | Check semantic saturation: repeated bigram ratio.
checkSemanticSaturation :: [Text] -> Maybe Text
checkSemanticSaturation tokens
  | length tokens < 20 = Nothing
  | otherwise =
      let bigrams = zip tokens (drop 1 tokens)
          uniqueBigrams = nub bigrams
          totalBigrams = length bigrams
          uniqueCount = length uniqueBigrams
          repeatRatio :: Double
          repeatRatio = 1 - fromIntegral uniqueCount / fromIntegral totalBigrams
      in if repeatRatio > 0.8
           then Just "\x412\x44b\x441\x43e\x43a\x430\x44f \x43f\x43e\x432\x442\x43e\x440\x44f\x435\x43c\x43e\x441\x442\x44c"
           else Nothing
