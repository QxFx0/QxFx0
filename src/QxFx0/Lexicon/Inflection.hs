{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Lexicon.Inflection
  ( toNominative
  , genitiveForm
  , accusativeForm
  , prepositionalForm
  ) where

import Data.Text (Text)
import qualified Data.Map.Strict as M
import qualified Data.Text as T

import QxFx0.Policy.RenderLexicon
  ( morphFemSuffixA
  , morphFemSuffixYa
  , morphGenSuffixI
  , morphNeutSuffixE
  , morphNeutSuffixO
  , morphNounSuffixA
  , morphNounSuffixIya
  )
import QxFx0.Types (MorphologyData(..))
import QxFx0.Types.Domain.Atoms (LexemeForm(..), LexemeCase(..))
import QxFx0.Lexicon.Resolver (resolveLexemeForm)

toNominative :: MorphologyData -> Text -> Text
toNominative md w =
  case M.lookup w (mdNominative md) of
    Just f -> f
    Nothing -> case M.lookup (T.toLower w) (mdNominative md) of
      Just f -> f
      Nothing -> resolveCandidateNominative md w

resolveCandidateNominative :: MorphologyData -> Text -> Text
resolveCandidateNominative md surface =
  case resolveLexemeForm md surface (Just NominativeCase) Nothing of
    Just form -> lfLemma form
    Nothing -> surface

genitiveForm :: MorphologyData -> Text -> Text
genitiveForm md w = case M.lookup w (mdGenitive md) of
  Just f -> f
  Nothing -> case M.lookup (T.toLower w) (mdGenitive md) of
    Just f -> f
    Nothing -> resolveCandidateGenitive md w

resolveCandidateGenitive :: MorphologyData -> Text -> Text
resolveCandidateGenitive md surface =
  case resolveLexemeForm md surface (Just GenitiveCase) Nothing of
    Just form -> lfSurface form
    Nothing -> surface

accusativeForm :: MorphologyData -> Text -> Text
accusativeForm md w =
  case resolveCandidateAccusative md w of
    Just form -> form
    Nothing ->
      let gender = guessGender w
          animacy = guessAnimacy w
      in case (gender, animacy) of
            (Masculine, Inanimate) -> w
            (Neuter, _) -> w
            _ -> genitiveForm md w

resolveCandidateAccusative :: MorphologyData -> Text -> Maybe Text
resolveCandidateAccusative md surface =
  lfSurface <$> resolveLexemeForm md surface (Just AccusativeCase) Nothing

data Animacy = Animate | Inanimate
  deriving stock (Eq, Show)

data Gender = Masculine | Feminine | Neuter
  deriving stock (Eq, Show)

guessAnimacy :: Text -> Animacy
guessAnimacy w =
  let lower = T.toLower w
      animateSuffixes =
        [ morphFemSuffixA
        , morphFemSuffixYa
        , morphNounSuffixA
        , morphNounSuffixIya
        ]
  in if any (`T.isSuffixOf` lower) animateSuffixes then Animate else Inanimate

guessGender :: Text -> Gender
guessGender w
  | T.isSuffixOf morphFemSuffixA lower = Feminine
  | T.isSuffixOf morphFemSuffixYa lower = Feminine
  | T.isSuffixOf morphNounSuffixA lower = Feminine
  | T.isSuffixOf morphNounSuffixIya lower = Feminine
  | T.isSuffixOf morphNeutSuffixO lower = Neuter
  | T.isSuffixOf morphNeutSuffixE lower = Neuter
  | T.isSuffixOf morphGenSuffixI lower = Feminine
  | otherwise = Masculine
  where
    lower = T.toLower w

prepositionalForm :: MorphologyData -> Text -> Text
prepositionalForm md w = case M.lookup w (mdPrepositional md) of
  Just f -> f
  Nothing -> case M.lookup (T.toLower w) (mdPrepositional md) of
    Just f -> f
    Nothing -> resolveCandidatePrepositional md w

resolveCandidatePrepositional :: MorphologyData -> Text -> Text
resolveCandidatePrepositional md surface =
  case resolveLexemeForm md surface (Just PrepositionalCase) Nothing of
    Just form -> lfLemma form
    Nothing -> surface
