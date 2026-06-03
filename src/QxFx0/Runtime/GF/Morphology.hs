{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}

{-| Morphology utilities: case/number/verb conjugation lookups.
    Replaces the old Inflection.hs with resolver-based morphology.
-}
module QxFx0.Runtime.GF.Morphology
  ( toNominative
  , genitiveForm
  , accusativeForm
  , prepositionalForm
  , conjugateVerb
  , VerbPerson(..)
  , pluralNominative
  , pluralGenitive
  , pluralAccusative
  , pluralPrepositional
  ) where

import Data.Text (Text)
import qualified Data.Map.Strict as M
import qualified Data.Text as T

import QxFx0.Policy.RenderLexicon
  ( morphFemSuffixA
  , morphFemSuffixYa
  , morphNeutSuffixE
  , morphNeutSuffixO
  , morphNounSuffixA
  , morphNounSuffixIya
  )
import QxFx0.Types (MorphologyData(..))
import QxFx0.Types.Domain.Atoms (LexemeForm(..), LexemeCase(..), LexemeNumber(..))
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
            (Feminine, Inanimate) -> feminineAccusativeByRule w
            _ -> genitiveForm md w

resolveCandidateAccusative :: MorphologyData -> Text -> Maybe Text
resolveCandidateAccusative md surface =
  lfSurface <$> resolveLexemeForm md surface (Just AccusativeCase) Nothing

data Animacy = Animate | Inanimate
  deriving stock (Eq, Show)

data Gender = Masculine | Feminine | Neuter
  deriving stock (Eq, Show)

guessAnimacy :: Text -> Animacy
guessAnimacy _ = Inanimate

guessGender :: Text -> Gender
guessGender w
  | T.toLower w `elem` feminineSoftSignExceptions = Feminine
  | T.isSuffixOf morphFemSuffixA lower = Feminine
  | T.isSuffixOf morphFemSuffixYa lower = Feminine
  | T.isSuffixOf morphNounSuffixA lower = Feminine
  | T.isSuffixOf morphNounSuffixIya lower = Feminine
  | T.isSuffixOf morphNeutSuffixO lower = Neuter
  | T.isSuffixOf morphNeutSuffixE lower = Neuter
  | otherwise = Masculine
  where
    lower = T.toLower w

feminineSoftSignExceptions :: [Text]
feminineSoftSignExceptions =
  [ "дверь", "мышь", "ночь", "речь", "вещь", "часть", "грудь"
  , "кость", "лестница", "постель", "тень", "цель", "чь", "цепь"
  , "боль", "роль", "сталь", "соль", "мать", "дочь"
  , "любовь", "морковь", "пыль", "медь", "гроз", "кровь"
  , "область", "гавань", "мелочь"
  ]

feminineAccusativeByRule :: Text -> Text
feminineAccusativeByRule w
  | T.isSuffixOf morphFemSuffixA lower = T.dropEnd 1 lower <> "у"
  | T.isSuffixOf morphFemSuffixYa lower = T.dropEnd 1 lower <> "ю"
  | T.isSuffixOf morphNounSuffixA lower = T.dropEnd 1 lower <> "у"
  | T.isSuffixOf morphNounSuffixIya lower = T.dropEnd 2 lower <> "ию"
  | otherwise = w
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

data VerbPerson
  = Person1Sg
  | Person2Sg
  | Person3Sg
  | Person1Pl
  | Person2Pl
  | Person3Pl
  deriving stock (Eq, Show)

conjugateVerb :: MorphologyData -> Text -> VerbPerson -> Text
conjugateVerb md infinitive person =
  case resolveLexemeForm md infinitive (Just NominativeCase) (case person of
    Person1Pl -> Just PluralNumber
    Person2Pl -> Just PluralNumber
    Person3Pl -> Just PluralNumber
    _ -> Just SingularNumber) of
    Just form -> lfSurface form
    Nothing -> conjugateByRule infinitive person

conjugateByRule :: Text -> VerbPerson -> Text
conjugateByRule infinitive person =
  let stem = infinitiveStem infinitive
      conjClass = classifyVerb infinitive
  in case conjClass of
       FirstConj ->
         case person of
           Person1Sg -> stem <> first1SgEnding infinitive
           Person2Sg -> stem <> "ешь"
           Person3Sg -> stem <> "ет"
           Person1Pl -> stem <> "ем"
           Person2Pl -> stem <> "ете"
           Person3Pl -> stem <> "ют"
       SecondConj ->
         case person of
           Person1Sg -> stem <> second1SgEnding infinitive
           Person2Sg -> stem <> "ишь"
           Person3Sg -> stem <> "ит"
           Person1Pl -> stem <> "им"
           Person2Pl -> stem <> "ите"
           Person3Pl -> stem <> "ат"

infinitiveStem :: Text -> Text
infinitiveStem infinitive =
  let lower = T.toLower infinitive
  in case () of
       _
         | Just s <- T.stripSuffix "ивать" lower -> s
         | Just s <- T.stripSuffix "евать" lower -> s
         | Just s <- T.stripSuffix "овать" lower -> s
         | Just s <- T.stripSuffix "ывать" lower -> s
         | Just s <- T.stripSuffix "ать" lower -> s
         | Just s <- T.stripSuffix "ять" lower -> s
         | Just s <- T.stripSuffix "еть" lower -> s
         | Just s <- T.stripSuffix "ить" lower -> s
         | Just s <- T.stripSuffix "чь" lower -> s <> "г"
         | Just s <- T.stripSuffix "ти" lower -> s
         | otherwise -> lower

classifyVerb :: Text -> ConjugationClass
classifyVerb infinitive =
  let lower = T.toLower infinitive
  in case () of
       _
         | lower `elem` secondConjExceptions -> SecondConj
         | T.isSuffixOf "ить" lower -> SecondConj
         | T.isSuffixOf "еть" lower -> FirstConj
         | T.isSuffixOf "ать" lower -> FirstConj
         | T.isSuffixOf "ять" lower -> FirstConj
         | T.isSuffixOf "оть" lower -> FirstConj
         | T.isSuffixOf "уть" lower -> FirstConj
         | T.isSuffixOf "ыть" lower -> FirstConj
         | T.isSuffixOf "чь" lower -> FirstConj
         | T.isSuffixOf "ти" lower -> FirstConj
         | otherwise -> FirstConj

secondConjExceptions :: [Text]
secondConjExceptions =
  [ "смотреть", "видеть", "ненавидеть", "обидеть", "зависеть", "терпеть"
  , "вертеть", "дышать", "держать", "слышать", "гнать"
  ]

data ConjugationClass = FirstConj | SecondConj
  deriving stock (Eq, Show)

first1SgEnding :: Text -> Text
first1SgEnding infinitive =
  let lower = T.toLower infinitive
  in case () of
       _
         | T.isSuffixOf "овать" lower -> "ую"
         | T.isSuffixOf "евать" lower -> "ую"
         | T.isSuffixOf "ивать" lower -> "иваю"
         | T.isSuffixOf "ывать" lower -> "ываю"
         | T.isSuffixOf "ать" lower -> "аю"
         | T.isSuffixOf "ять" lower -> "яю"
         | otherwise -> "у"

second1SgEnding :: Text -> Text
second1SgEnding infinitive =
  let lower = T.toLower infinitive
  in case () of
       _
         | T.isSuffixOf "ить" lower -> "ю"
         | T.isSuffixOf "еть" lower -> "ю"
         | otherwise -> "ю"

pluralNominative :: MorphologyData -> Text -> Text
pluralNominative md w =
  case resolveLexemeForm md w (Just NominativeCase) (Just PluralNumber) of
    Just form -> lfSurface form
    Nothing -> pluralizeByRule w

pluralGenitive :: MorphologyData -> Text -> Text
pluralGenitive md w =
  case resolveLexemeForm md w (Just GenitiveCase) (Just PluralNumber) of
    Just form -> lfSurface form
    Nothing -> pluralizeGenitiveByRule w

pluralAccusative :: MorphologyData -> Text -> Text
pluralAccusative md w =
  case resolveLexemeForm md w (Just AccusativeCase) (Just PluralNumber) of
    Just form -> lfSurface form
    Nothing -> pluralizeByRule w

pluralPrepositional :: MorphologyData -> Text -> Text
pluralPrepositional md w =
  case resolveLexemeForm md w (Just PrepositionalCase) (Just PluralNumber) of
    Just form -> lfLemma form
    Nothing -> pluralPrepositionalByRule w

pluralizeByRule :: Text -> Text
pluralizeByRule w =
  let lower = T.toLower w
  in case () of
       _
         | T.isSuffixOf "а" lower -> T.dropEnd 1 lower <> "ы"
         | T.isSuffixOf "я" lower -> T.dropEnd 1 lower <> "и"
         | T.isSuffixOf "о" lower -> T.dropEnd 1 lower <> "а"
         | T.isSuffixOf "е" lower -> T.dropEnd 1 lower <> "и"
         | T.isSuffixOf "ия" lower -> T.dropEnd 2 lower <> "ии"
         | T.isSuffixOf "ье" lower -> T.dropEnd 2 lower <> "ья"
         | T.isSuffixOf "ь" lower -> lower <> "и"
         | otherwise -> lower <> "ы"

pluralizeGenitiveByRule :: Text -> Text
pluralizeGenitiveByRule w =
  let lower = T.toLower w
  in case () of
       _
         | T.isSuffixOf "а" lower -> T.dropEnd 1 lower <> "ы"
         | T.isSuffixOf "я" lower -> T.dropEnd 1 lower <> "и"
         | T.isSuffixOf "о" lower -> T.dropEnd 1 lower <> "ов"
         | T.isSuffixOf "е" lower -> T.dropEnd 1 lower <> "ей"
         | T.isSuffixOf "ия" lower -> T.dropEnd 2 lower <> "ий"
         | T.isSuffixOf "ь" lower -> T.dropEnd 1 lower <> "ей"
         | otherwise -> lower <> "ов"

pluralPrepositionalByRule :: Text -> Text
pluralPrepositionalByRule w =
  let lower = T.toLower w
  in case () of
       _
         | T.isSuffixOf "а" lower -> T.dropEnd 1 lower <> "ах"
         | T.isSuffixOf "я" lower -> T.dropEnd 1 lower <> "ях"
         | T.isSuffixOf "о" lower -> T.dropEnd 1 lower <> "ах"
         | T.isSuffixOf "е" lower -> T.dropEnd 1 lower <> "ах"
         | T.isSuffixOf "ия" lower -> T.dropEnd 2 lower <> "иях"
         | T.isSuffixOf "ь" lower -> T.dropEnd 1 lower <> "ах"
         | otherwise -> lower <> "ах"
