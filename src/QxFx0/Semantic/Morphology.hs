{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}
module QxFx0.Semantic.Morphology
  ( MorphToken(..)
  , POS(..)
  , Case(..)
  , Gender(..)
  , Number(..)
  , Tense(..)
  , Mood(..)
  , Person(..)
  , MorphBackend(..)
  , analyzeMorph
  , analyzeMorphWithBackend
  , resolveMorphBackend
  , guessMorph
  , nounFromVerb
  , nounFromAdj
  , extractContentNouns
  , buildMorphologyData
  , hasKnownMorphologyForm
  , toNominative
  , genitiveForm
  , accusativeForm
  , prepositionalForm
  ) where

import QxFx0.Types (MorphologyData(..))
import QxFx0.Lexicon.Inflection
  ( accusativeForm
  , genitiveForm
  , prepositionalForm
  , toNominative
  )
import QxFx0.Lexicon.Generated
  ( generatedLexemeEntries
  , generatedCandidateForms
  )
import QxFx0.Policy.RenderLexicon
  ( morphVerbSuffixT, morphVerbSuffixTi
  , morphAdjSuffixYj, morphAdjSuffixIj, morphAdjSuffixOj
  , morphAdvSuffixO
  , morphNounSuffixOst, morphNounSuffixNost
  , morphNounSuffixEnie, morphNounSuffixNnie
  , morphNounSuffixA, morphNounSuffixIya
  , morphInstrSuffixOm, morphGenSuffixI
  , morphPrepSuffixE, morphDatSuffixU
  , morphAccSuffixUyu
  , morphPluralSuffixY, morphPluralSuffixI, morphPluralSuffixAmi
  , morphFemSuffixA, morphFemSuffixYa
  , morphNeutSuffixO, morphNeutSuffixE
  , morphVerbDerivOvat, morphVerbDerivT, morphVerbDerivTi
  , morphAdjDerivYj, morphAdjDerivIj
  , morphDerivEnie, morphDerivOst
  )
import Data.Text (Text)
import qualified Data.Text as T
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Char (isLetter)
import System.Environment (lookupEnv)

data POS = Noun | Verb | Adj | Adv | Pron | Prep | Conj | Part | Num | UnknownPOS
  deriving stock (Eq, Ord, Show, Read, Bounded, Enum)

data MorphBackend
  = MorphBackendLocal
  | MorphBackendRemote
  deriving stock (Eq, Show)

data Case = Nominative | Genitive | Dative | Accusative | Instrumental | Prepositional
  deriving stock (Eq, Ord, Show, Read, Bounded, Enum)

data Gender = Masculine | Feminine | Neuter | NoGender
  deriving stock (Eq, Ord, Show, Read, Bounded, Enum)

data Number = Singular | Plural | NoNumber
  deriving stock (Eq, Ord, Show, Read, Bounded, Enum)

data Tense = Present | Past | Future | NoTense
  deriving stock (Eq, Ord, Show, Read, Bounded, Enum)

data Mood = Indicative | ImperativeMood | Conditional | NoMood
  deriving stock (Eq, Ord, Show, Read, Bounded, Enum)

data Person = First | Second | Third | NoPerson
  deriving stock (Eq, Ord, Show, Read, Bounded, Enum)

data MorphToken = MorphToken
  { mtSurface :: !Text
  , mtLemma :: !Text
  , mtPOS :: !POS
  , mtCase :: !(Maybe Case)
  , mtNumber :: !(Maybe Number)
  , mtGender :: !(Maybe Gender)
  , mtTense :: !(Maybe Tense)
  , mtMood :: !(Maybe Mood)
  , mtPerson :: !(Maybe Person)
  } deriving stock (Eq, Show)

type MorphDict = Map Text MorphToken

generatedMorphDict :: MorphDict
generatedMorphDict = foldl insertLexeme M.empty generatedLexemeEntries
  where
    insertLexeme :: MorphDict -> (Text, Text, Text, Text) -> MorphDict
    insertLexeme acc (surface, lemma, posTag, caseTag) =
      let key = T.toLower surface
          token = mkToken surface lemma posTag caseTag
      in M.insertWith pickPreferred key token acc

    pickPreferred :: MorphToken -> MorphToken -> MorphToken
    pickPreferred new old
      | tokenPriority new > tokenPriority old = new
      | otherwise = old

    tokenPriority :: MorphToken -> Int
    tokenPriority tok = case mtCase tok of
      Just Nominative -> 3
      Just Genitive -> 2
      Just Prepositional -> 1
      _ -> 0

    parsePOS :: Text -> POS
    parsePOS tag = case T.toLower tag of
      "noun" -> Noun
      "verb" -> Verb
      "adj" -> Adj
      "adjective" -> Adj
      "adv" -> Adv
      _ -> UnknownPOS

    parseCase :: Text -> Maybe Case
    parseCase tag = case T.toLower tag of
      "nominative" -> Just Nominative
      "genitive" -> Just Genitive
      "prepositional" -> Just Prepositional
      _ -> Nothing

    parseTense :: POS -> Maybe Tense
    parseTense Verb = Just Present
    parseTense _ = Nothing

    mkToken :: Text -> Text -> Text -> Text -> MorphToken
    mkToken surface lemma posTag caseTag =
      let pos = parsePOS posTag
      in MorphToken
        { mtSurface = surface
        , mtLemma = lemma
        , mtPOS = pos
        , mtCase = parseCase caseTag
        , mtNumber = Just Singular
        , mtGender = Nothing
        , mtTense = parseTense pos
        , mtMood = Nothing
        , mtPerson = Nothing
        }

analyzeMorph :: Text -> MorphToken
analyzeMorph word =
  let low = T.toLower word
  in case M.lookup low generatedMorphDict of
    Just tok -> tok { mtSurface = word }
    Nothing -> guessMorph word

resolveMorphBackend :: IO MorphBackend
resolveMorphBackend = do
  raw <- lookupEnv "QXFX0_MORPH_BACKEND"
  pure $ case fmap (T.toLower . T.pack) raw of
    Just "remote" -> MorphBackendRemote
    _ -> MorphBackendLocal

analyzeMorphWithBackend :: MorphBackend -> Text -> IO MorphToken
analyzeMorphWithBackend backend word =
  case backend of
    MorphBackendLocal -> pure (analyzeMorph word)
    -- Local-first runtime: remote morphology flag is accepted but still
    -- resolved to local analysis in the semantic layer.
    MorphBackendRemote -> pure (analyzeMorph word)

guessMorph :: Text -> MorphToken
guessMorph word =
  let w = T.toLower word
  in MorphToken word w (guessPOS w) (guessCase w) (guessNumber w) (guessGender w) Nothing Nothing Nothing

guessPOS :: Text -> POS
guessPOS w
  | T.isSuffixOf morphVerbSuffixT w || T.isSuffixOf morphVerbSuffixTi w = Verb
  | T.isSuffixOf morphAdjSuffixYj w || T.isSuffixOf morphAdjSuffixIj w
    || T.isSuffixOf morphAdjSuffixOj w || T.isSuffixOf morphAdjSuffixYj w = Adj
  | T.isSuffixOf morphAdvSuffixO w && T.length w > 3 = Adv
  | T.isSuffixOf morphNounSuffixOst w || T.isSuffixOf morphNounSuffixNost w
    || T.isSuffixOf morphNounSuffixEnie w || T.isSuffixOf morphNounSuffixNnie w = Noun
  | T.isSuffixOf morphNounSuffixA w || T.isSuffixOf morphNounSuffixIya w = Noun
  | otherwise = Noun

guessCase :: Text -> Maybe Case
guessCase w
  | T.isSuffixOf morphInstrSuffixOm w && T.length w > 3 = Just Instrumental
  | T.isSuffixOf morphGenSuffixI w && not (T.isSuffixOf morphVerbSuffixTi w) = Just Genitive
  | T.isSuffixOf morphPrepSuffixE w && T.length w > 4 = Just Prepositional
  | T.isSuffixOf morphDatSuffixU w = Just Dative
  | T.isSuffixOf morphAccSuffixUyu w = Just Accusative
  | otherwise = Just Nominative

guessNumber :: Text -> Maybe Number
guessNumber w
  | T.isSuffixOf morphPluralSuffixY w || T.isSuffixOf morphPluralSuffixI w || T.isSuffixOf morphPluralSuffixAmi w = Just Plural
  | otherwise = Just Singular

guessGender :: Text -> Maybe Gender
guessGender w
  | T.isSuffixOf morphFemSuffixA w || T.isSuffixOf morphFemSuffixYa w = Just Feminine
  | T.isSuffixOf morphNeutSuffixO w || T.isSuffixOf morphNeutSuffixE w = Just Neuter
  | otherwise = Just Masculine

nounFromVerb :: Text -> Maybe Text
nounFromVerb v
  | T.isSuffixOf morphVerbDerivOvat v = Just $ T.dropEnd 3 v <> morphDerivEnie
  | T.isSuffixOf morphVerbDerivT v = Just $ T.dropEnd 2 v <> morphDerivEnie
  | T.isSuffixOf morphVerbDerivTi v = Just $ T.dropEnd 2 v <> morphDerivEnie
  | otherwise = Nothing

nounFromAdj :: Text -> Maybe Text
nounFromAdj a
  | T.isSuffixOf morphAdjDerivYj a = Just $ T.dropEnd 2 a <> morphDerivOst
  | T.isSuffixOf morphAdjDerivIj a = Just $ T.dropEnd 2 a <> morphDerivOst
  | T.isSuffixOf morphAdjSuffixOj a = Just $ T.dropEnd 2 a <> morphDerivOst
  | otherwise = Nothing

extractContentNouns :: Text -> [Text]
extractContentNouns input =
  let words' = map normalizeLexeme (T.words input)
      tokens = map analyzeMorph (filter (not . T.null) words')
  in
    [ mtLemma t
    | t <- tokens
    , isContentNoun t
    ]

normalizeLexeme :: Text -> Text
normalizeLexeme = T.dropAround (\ch -> not (isLetter ch) && ch /= '-')

isContentNoun :: MorphToken -> Bool
isContentNoun token =
  let lemma = T.toLower (mtLemma token)
  in mtPOS token == Noun
      && T.length lemma > 3
      && lemma `notElem` contentStopwords

contentStopwords :: [Text]
contentStopwords =
  [ "что", "кто", "как", "где", "когда", "зачем", "почему"
  , "такое", "такой", "такая", "такие", "таков", "такова"
  , "это", "этот", "эта", "эти", "того", "этому"
  , "какой", "какая", "какие", "каково"
  , "ничего", "нечто"
  ]

buildMorphologyData :: [MorphToken] -> MorphologyData
buildMorphologyData tokens =
  let prepPairs = [ (mtSurface t, mtLemma t) | t <- tokens, mtCase t == Just Prepositional ]
      genPairs  = [ (mtSurface t, mtLemma t) | t <- tokens, mtCase t == Just Genitive ]
      nomPairs  = [ (mtSurface t, mtLemma t) | t <- tokens, mtCase t == Just Nominative ]
  in MorphologyData
    { mdPrepositional = M.fromList prepPairs
    , mdGenitive = M.fromList genPairs
    , mdNominative = M.fromList nomPairs
    , mdFormsBySurface = generatedCandidateForms
    }

hasKnownMorphologyForm :: MorphologyData -> Text -> Bool
hasKnownMorphologyForm md w =
  let lower = T.toLower w
      present dict = M.member w dict || M.member lower dict
      presentSurfaceForms = M.member w (mdFormsBySurface md) || M.member lower (mdFormsBySurface md)
  in present (mdNominative md)
      || present (mdGenitive md)
      || present (mdPrepositional md)
      || presentSurfaceForms
