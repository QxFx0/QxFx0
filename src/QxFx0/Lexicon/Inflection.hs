{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

module QxFx0.Lexicon.Inflection
  ( toNominative
  , genitiveForm
  , accusativeForm
  , prepositionalForm
  , instrumentalForm
  , dativeForm
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

-- | Instrumental case form. Uses lexicon lookup, then suffix heuristic.
instrumentalForm :: MorphologyData -> Text -> Text
instrumentalForm md w =
  case resolveLexemeForm md w (Just InstrumentalCase) Nothing of
    Just form -> lfSurface form
    Nothing -> instrumentalHeuristic w

-- | Dative case form. Uses lexicon lookup, then suffix heuristic.
dativeForm :: MorphologyData -> Text -> Text
dativeForm md w =
  case resolveLexemeForm md w (Just DativeCase) Nothing of
    Just form -> lfSurface form
    Nothing -> dativeHeuristic w

-- | Suffix-based instrumental form heuristic.
-- Doesn't re-inflect words already in instrumental.
instrumentalHeuristic :: Text -> Text
instrumentalHeuristic word =
  let w = T.toLower word
  in
  if "ой" `T.isSuffixOf` w || "ей" `T.isSuffixOf` w
     || "ом" `T.isSuffixOf` w || "ем" `T.isSuffixOf` w
     || "ью" `T.isSuffixOf` w || "ами" `T.isSuffixOf` w
    then word
  else if "ь" `T.isSuffixOf` w
    then T.init word <> "ью"
  else if "а" `T.isSuffixOf` w
    then T.init word <> "ой"
  else if "я" `T.isSuffixOf` w
    then T.init word <> "ей"
  else if "о" `T.isSuffixOf` w
    then T.init word <> "ом"
  else if "е" `T.isSuffixOf` w
    then T.init word <> "ем"
  else if "й" `T.isSuffixOf` w
    then T.init word <> "ем"
  else if isConsonantEndingInf w
    then word <> "ом"
  else word

-- | Suffix-based dative form heuristic.
dativeHeuristic :: Text -> Text
dativeHeuristic word =
  let w = T.toLower word
  in
  if "у" `T.isSuffixOf` w || "ю" `T.isSuffixOf` w
     || "е" `T.isSuffixOf` w || "и" `T.isSuffixOf` w
    then word
  else if "ь" `T.isSuffixOf` w
    then T.init word <> "и"
  else if "а" `T.isSuffixOf` w
    then T.init word <> "е"
  else if "я" `T.isSuffixOf` w
    then T.init word <> "е"
  else if "о" `T.isSuffixOf` w
    then T.init word <> "у"
  else if "е" `T.isSuffixOf` w
    then T.init word <> "у"
  else if "й" `T.isSuffixOf` w
    then T.init word <> "ю"
  else if isConsonantEndingInf w
    then word <> "у"
  else word

isConsonantEndingInf :: Text -> Bool
isConsonantEndingInf w = case T.last w of
  c -> c `notElem` ("аеёиоуыэюяьй" :: String)
