{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-| Predicate-to-surface verbalizer for spreading-activation output.

Implements Phase 1 of ADR-0050.  Takes a ranked list of
'SemanticPredicate's, resolves topic forms, applies 'Field'-driven
stance modulation, deduplicates, and joins the results into a flat
Russian surface text according to the requested 'VerbalizationMode'.
-}
module QxFx0.Semantic.SurfaceAccumulator
  ( VerbalizationMode(..)
  , accumulateSurface
    -- * Helpers exposed for testing
  , resolveTopicForm
  , applyStanceModulation
  , modeIncludesRationale
  , modeIncludesSynthesis
  , modeMaxPredicates
  , framingPrefix
  , joinPredicates
  ) where

import Data.List (sortOn)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Maybe (isJust, listToMaybe)
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Lexicon.Resolver (resolveLexemeFormRawFallback, tierPriority)
import QxFx0.Semantic.Analogy (replaceFirst)
import QxFx0.Semantic.Content.Base (SemanticPredicate(..))
import QxFx0.Self.Field
  ( Field(..)
  , FieldConfidence(..)
  , Counterfactual(..)
  , Resonance(..)
  )
import QxFx0.Types (MorphologyData(..))
import QxFx0.Types.Domain.Atoms (LexemeCase(..), LexemeForm(..))

-- | Discourse framing mode for 'accumulateSurface'.
data VerbalizationMode
  = VmDefinition
  | VmChallenge
  | VmReflection
  | VmDistinction
  deriving stock (Eq, Show)

-- | Maximum number of predicates rendered for each mode.
modeMaxPredicates :: VerbalizationMode -> Int
modeMaxPredicates VmDefinition  = 3
modeMaxPredicates VmChallenge   = 2
modeMaxPredicates VmReflection  = 2
modeMaxPredicates VmDistinction = 1

-- | Whether a mode should render predicate rationales.
modeIncludesRationale :: VerbalizationMode -> Bool
modeIncludesRationale VmDefinition = True
modeIncludesRationale VmReflection = True
modeIncludesRationale _            = False

-- | Whether a mode should render predicate syntheses.
modeIncludesSynthesis :: VerbalizationMode -> Bool
modeIncludesSynthesis VmDefinition = True
modeIncludesSynthesis VmReflection = True
modeIncludesSynthesis _            = False

-- | Strip and return the Russian surface text of a predicate.
predicateText :: SemanticPredicate -> Text
predicateText = T.strip . spRu

-- | Main entry point from ADR-0050 Phase 1.
accumulateSurface
  :: MorphologyData
  -> Field
  -> VerbalizationMode
  -> Text        -- ^ topic (for framing prefix and topic-form resolution)
  -> [SemanticPredicate]
  -> Text
accumulateSurface _md _field _mode _topic [] = ""
accumulateSurface md field mode topic preds =
  let limited   = take (modeMaxPredicates mode) preds
      joined    = joinPredicates mode md field topic limited
      syntheses = [ s | p <- limited
                      , modeIncludesSynthesis mode
                      , Just s <- [spSynthesis p]
                      ]
  in if null syntheses
       then framingPrefix mode topic <> joined
       else framingPrefix mode topic <> joined <> ". " <> T.intercalate ". " syntheses

-- | Frame-specific opening prefix.
framingPrefix :: VerbalizationMode -> Text -> Text
framingPrefix VmDefinition _  = ""
framingPrefix VmChallenge _   = "Я вижу это так: "
framingPrefix VmReflection t  = "Когда я думаю о " <> t <> ", "
framingPrefix VmDistinction t = "Различая " <> t <> ": "

-- | Join predicates with the appropriate discourse connector.
joinPredicates
  :: VerbalizationMode
  -> MorphologyData
  -> Field
  -> Text
  -> [SemanticPredicate]
  -> Text
joinPredicates mode md field topic = go "" Nothing
  where
    go :: Text -> Maybe Text -> [SemanticPredicate] -> Text
    go _acc _prevTopic [] = ""
    go acc prevTopic (p:ps)
      | isDuplicate p acc = go acc prevTopic ps
      | otherwise =
          let segment   = verbalizeSegment mode field md topic p
              connector = case prevTopic of
                            Nothing -> ""
                            Just prev
                              | modeIncludesSynthesis mode && isJust (spSynthesis p)
                                  -> ". Однако "
                              | spTopicForm p == prev -> ". Кроме того, "
                              | otherwise             -> ". Вместе с тем, "
          in connector <> segment <> go (acc <> connector <> segment) (Just (spTopicForm p)) ps

    isDuplicate p acc =
      let emitted = T.toLower acc
          needle  = T.toLower (predicateText p)
      in not (T.null needle) && needle `T.isInfixOf` emitted

-- | Build a single predicate's surface segment.
verbalizeSegment
  :: VerbalizationMode
  -> Field
  -> MorphologyData
  -> Text
  -> SemanticPredicate
  -> Text
verbalizeSegment mode field md topic p =
  let base = resolveTopicForm md topic p
      withRationale = case (modeIncludesRationale mode, spRationale p) of
        (True, Just rationale) -> base <> " — " <> rationale
        _                      -> base
  in applyStanceModulation field withRationale

-- | Substitute the predicate's topic form into its Russian surface text,
-- using 'MorphologyData' to inflect the supplied topic into the same case
-- as the original topic form when possible.
resolveTopicForm :: MorphologyData -> Text -> SemanticPredicate -> Text
resolveTopicForm md topic p
  | T.null (spTopicForm p) = predicateText p
  | otherwise = replaceFirst (spTopicForm p) resolved (predicateText p)
  where
    resolved = case inferTopicCase md (spTopicForm p) of
                 Nothing -> topic
                 Just c  -> resolveLexemeFormRawFallback md topic (Just c) Nothing

-- | Infer the grammatical case of a surface word from the morphology data.
inferTopicCase :: MorphologyData -> Text -> Maybe LexemeCase
inferTopicCase md t =
  case M.lookup (T.toLower t) (mdFormsBySurface md) of
    Nothing   -> Nothing
    Just []   -> Nothing
    Just forms -> lfCase <$> bestForm forms

-- | Pick the highest-quality candidate form; ties are left to the resolver.
bestForm :: [LexemeForm] -> Maybe LexemeForm
bestForm forms = listToMaybe (sortOn rankingKey forms)
  where
    rankingKey f =
      ( negate (tierPriority (lfTier f))
      , negate (lfQuality f)
      , lfLemma f
      )

-- | Apply 'Field'-driven stance prefixes.
applyStanceModulation :: Field -> Text -> Text
applyStanceModulation field t =
  let conf   = unFieldConfidence   (fieldConfidence   field)
      counter = unCounterfactual  (fieldCounterfactual field)
      angst   = unResonance       (fieldResonance      field)
      prefixes = concat
        [ if conf   > 0.7 then ["Известно, что "]      else []
        , if counter > 0.6 then ["Но вместе с тем "]   else []
        , if angst   > 0.7 then ["возможно, "]         else []
        ]
  in T.concat prefixes <> t
