{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}
{-| Lexeme candidate resolver policy: curated > auto-verified > auto-coverage,
    exact match preferred, higher quality wins, dangerous ambiguity falls back.
-}
module QxFx0.Lexicon.Resolver
  ( resolveLexemeForm
  , resolveLexemeFormRawFallback
  , tierPriority
  ) where

import Data.List (sortOn)
import qualified Data.Map.Strict as M
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Types.Domain.Atoms
  ( LexemeForm(..)
  , LexemeCase(..)
  , LexemeNumber(..)
  , SourceTier(..)
  , MorphologyData(..)
  )

tierPriority :: SourceTier -> Int
tierPriority CuratedTier = 3
tierPriority AutoVerifiedTier = 2
tierPriority AutoCoverageTier = 1

resolveLexemeForm
  :: MorphologyData
  -> Text
  -> Maybe LexemeCase
  -> Maybe LexemeNumber
  -> Maybe LexemeForm
resolveLexemeForm md surface mCase mNumber =
  let lower = T.toLower surface
      candidates = M.lookup lower (mdFormsBySurface md)
  in case candidates of
       Nothing -> Nothing
       Just forms ->
         let filtered = filterMatches mCase mNumber forms
             ranked = sortOn rankingKey filtered
         in pickUnambiguous ranked

filterMatches :: Maybe LexemeCase -> Maybe LexemeNumber -> [LexemeForm] -> [LexemeForm]
filterMatches Nothing Nothing forms = forms
filterMatches (Just c) Nothing forms = [f | f <- forms, lfCase f == c]
filterMatches Nothing (Just n) forms = [f | f <- forms, lfNumber f == n]
filterMatches (Just c) (Just n) forms = [f | f <- forms, lfCase f == c, lfNumber f == n]

rankingKey :: LexemeForm -> (Int, Double, Text)
rankingKey f =
  ( negate (tierPriority (lfTier f))
  , negate (lfQuality f)
  , lfLemma f
  )

-- | Pick the top candidate only if it is unambiguous at the tier level.
-- If the top two candidates have the same tier and quality, treat as
-- dangerous ambiguity and return Nothing (fallback to raw surface).
pickUnambiguous :: [LexemeForm] -> Maybe LexemeForm
pickUnambiguous [] = Nothing
pickUnambiguous [f] = Just f
pickUnambiguous (f1:f2:_)
  | lfTier f1 == lfTier f2 && lfQuality f1 == lfQuality f2 = Nothing
  | otherwise = Just f1

-- | Convenience: resolve and return the raw surface on failure.
resolveLexemeFormRawFallback
  :: MorphologyData
  -> Text
  -> Maybe LexemeCase
  -> Maybe LexemeNumber
  -> Text
resolveLexemeFormRawFallback md surface mCase mNumber =
  maybe surface lfSurface (resolveLexemeForm md surface mCase mNumber)
