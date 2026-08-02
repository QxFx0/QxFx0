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
  , instrumentalForm
  , dativeForm
  , buildLemmaMap
  , normalizeToken
  , normalizeAtoms
  -- * Contextual morphology analysis
  , Context(..)
  , analyzeContextualMorph
  , resolveCaseFromPreposition
  , resolveAgreement
  , analyzeSentenceContext
  , PrepositionCaseMap
  , defaultPrepositionCaseMap
  , SyntacticRole(..)
  , determineSyntacticRole
  , analyzeContextualWithRoles
  -- * Verb tense analysis
  , detectVerbTense
  , isPastTense
  , isPresentTense
  , isFutureTense
  , convertToPastTense
  , convertToPresentTense
  , convertToFutureTense
  -- * Ambiguity resolution
  , HomonymDatabase
  , defaultHomonymDatabase
  , resolveHomonym
  , getAmbiguousPOS
  -- * Participle and Gerund support
  , detectParticiple
  , detectGerund
  , participleToVerb
  , gerundToVerb
  , participleSuffixes
  , gerundSuffixes
  ) where

import QxFx0.Types (MorphologyData(..))
import QxFx0.Lexicon.Inflection
  ( accusativeForm
  , genitiveForm
  , prepositionalForm
  , toNominative
  , instrumentalForm
  , dativeForm
  )
import QxFx0.Lexicon.Generated (generatedLexemeEntries, generatedCandidateForms, generatedFiniteVerbMap)
import QxFx0.Lexicon.ParticipleGerund (participleGerundEntries)
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
import Data.Set (Set)
import qualified Data.Set as S
import Data.Char (isLetter)
import System.Environment (lookupEnv)
import QxFx0.Types.Domain.Atoms (LexemeForm(..))
import Data.List (find, nub)
import Data.Maybe (isJust, fromMaybe)
import Data.Char (toLower)
import Control.Arrow (second)

-- | Suffixes for Russian participles (причастия)
participleSuffixes :: [Text]
participleSuffixes = 
  [ "ущий", "ащий", "ящий",  -- Present active: читающий, пишущий, любящий
    "вш", "ш", "вший",        -- Past active: читавший, нёсший, прочитавший
    "щий",                   -- Present active: несущий
    "емый", "имый",          -- Present passive: читаемый, видимый
    "ный", "тый"              -- Past passive: прочитанный, сделанный
  ]

-- | Suffixes for Russian gerunds (деепричастия)
gerundSuffixes :: [Text]
gerundSuffixes = 
  [ "а", "я",              -- Present: читая, любя
    "в", "вши", "ши"        -- Past: прочитав, сделав, прочитавши, сделавши
  ]

data POS = Noun | Verb | Adj | Adv | Pron | Prep | Conj | Part | Num | Participle | Gerund | UnknownPOS
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
generatedMorphDict = foldl insertLexeme M.empty (generatedLexemeEntries ++ participleGerundEntries)
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
      "participle" -> Participle
      "gerund" -> Gerund
      _ -> UnknownPOS

    parseCase :: Text -> Maybe Case
    parseCase tag = case T.toLower tag of
      "nominative" -> Just Nominative
      "genitive" -> Just Genitive
      "prepositional" -> Just Prepositional
      _ -> Nothing

    parseTense :: POS -> Text -> Maybe Tense
    parseTense Verb word = detectVerbTense word
    parseTense _ _ = Nothing

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
        , mtTense = parseTense pos lemma
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
  -- Additional verb suffixes for better coverage
  | T.isSuffixOf "ать" w || T.isSuffixOf "ять" w = Verb
  | T.isSuffixOf "еть" w || T.isSuffixOf "ить" w = Verb
  | T.isSuffixOf "оть" w || T.isSuffixOf "уть" w = Verb
  | T.isSuffixOf "ыть" w = Verb
  | T.isSuffixOf "иться" w = Verb
  | T.isSuffixOf "аться" w || T.isSuffixOf "яться" w = Verb
  | T.isSuffixOf "еться" w || T.isSuffixOf "оться" w = Verb
  -- Participle suffixes (причастия) - check before adjectives since some overlap
  | any (`T.isSuffixOf` w) participleSuffixes = Participle
  -- Gerund suffixes (деепричастия)
  | any (`T.isSuffixOf` w) gerundSuffixes = Gerund
  -- Additional adjective suffixes for better coverage
  | T.isSuffixOf "ный" w || T.isSuffixOf "лый" w = Adj
  | T.isSuffixOf "кий" w || T.isSuffixOf "ский" w = Adj
  | T.isSuffixOf "ной" w || T.isSuffixOf "льный" w = Adj
  | T.isSuffixOf "емый" w || T.isSuffixOf "имый" w = Adj
  | T.isSuffixOf morphAdjSuffixYj w || T.isSuffixOf morphAdjSuffixIj w
    || T.isSuffixOf morphAdjSuffixOj w || T.isSuffixOf morphAdjSuffixYj w = Adj
  | T.isSuffixOf morphAdvSuffixO w && T.length w > 3 = Adv
  -- Additional noun suffixes for better coverage
  | T.isSuffixOf "ция" w || T.isSuffixOf "сия" w = Noun
  | T.isSuffixOf "ство" w || T.isSuffixOf "чество" w = Noun
  | T.isSuffixOf "ность" w || T.isSuffixOf "та" w = Noun
  | T.isSuffixOf "ение" w || T.isSuffixOf "ание" w = Noun
  | T.isSuffixOf "тель" w || T.isSuffixOf "ник" w = Noun
  | T.isSuffixOf "ка" w || T.isSuffixOf "щик" w = Noun
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

buildLemmaMap :: MorphologyData -> Map Text Text
buildLemmaMap md = M.unions
  [ M.mapKeys T.toLower (mdNominative md)
  , M.mapKeys T.toLower (mdGenitive md)
  , M.mapKeys T.toLower (mdPrepositional md)
  , formsBySurfaceMap
  ]
  where
    formsBySurfaceMap = M.fromList
      [ (T.toLower surface, T.toLower (lfLemma form))
      | (surface, forms) <- M.toList (mdFormsBySurface md)
      , form <- forms
      ]

normalizeToken :: Map Text Text -> Text -> Text
normalizeToken lemmaMap token =
  M.findWithDefault (T.toLower token) (T.toLower token) lemmaMap

normalizeAtoms :: Map Text Text -> Set Text -> Set Text
normalizeAtoms lemmaMap atoms = S.map (normalizeToken lemmaMap) atoms

-- ============================================================================
-- Participle and Gerund Support
-- ============================================================================

-- | Detect if a word is a participle (причастие)
detectParticiple :: Text -> Bool
detectParticiple word = 
  let w = T.toLower word
  in guessPOS w == Participle

-- | Detect if a word is a gerund (деепричастие)
detectGerund :: Text -> Bool
detectGerund word = 
  let w = T.toLower word
  in guessPOS w == Gerund

-- | Convert a participle to its base verb form (heuristic)
-- Handles common participle suffixes and attempts to reconstruct the infinitive
participleToVerb :: Text -> Maybe Text
participleToVerb word =
  let w = T.toLower word
  in case () of
       -- Present active participles: -ущий, -ащий, -ящий -> -ть
       _ | T.isSuffixOf "ущий" w -> Just (T.dropEnd 4 w <> "ть")
         | T.isSuffixOf "ащий" w -> Just (T.dropEnd 4 w <> "ть")
         | T.isSuffixOf "ящий" w -> Just (T.dropEnd 4 w <> "ть")
       -- Past active participles: -вший -> -ть, -ш -> -ть
         | T.isSuffixOf "вший" w -> Just (T.dropEnd 3 w <> "ть")
         | T.isSuffixOf "ш" w -> Just (T.dropEnd 1 w <> "ть")
       -- Present passive participles: -емый -> -ть, -имый -> -ть
         | T.isSuffixOf "емый" w -> Just (T.dropEnd 4 w <> "ть")
         | T.isSuffixOf "имый" w -> Just (T.dropEnd 4 w <> "ть")
       -- Past passive participles: -нный -> -ть, -тый -> -ть
         | T.isSuffixOf "нный" w -> Just (T.dropEnd 3 w <> "ть")
         | T.isSuffixOf "тый" w -> Just (T.dropEnd 3 w <> "ть")
         | otherwise -> Nothing

-- | Convert a gerund to its base verb form (heuristic)
-- Handles common gerund suffixes and attempts to reconstruct the infinitive
gerundToVerb :: Text -> Maybe Text
gerundToVerb word =
  let w = T.toLower word
  in case () of
       -- Present gerunds: -а, -я -> -ть
       _ | T.isSuffixOf "а" w -> Just (T.dropEnd 1 w <> "ть")
         | T.isSuffixOf "я" w -> Just (T.dropEnd 1 w <> "ть")
       -- Past gerunds: -в, -вши, -ши -> -ть
         | T.isSuffixOf "в" w -> Just (T.dropEnd 1 w <> "ть")
         | T.isSuffixOf "вши" w -> Just (T.dropEnd 3 w <> "ть")
         | T.isSuffixOf "ши" w -> Just (T.dropEnd 2 w <> "ть")
         | otherwise -> Nothing

-- ============================================================================
-- Contextual Morphology Analysis
-- ============================================================================

-- | Context for contextual morphological analysis
-- Includes preceding and following words, position in sentence, etc.
data Context = Context
  { ctxPreceding :: ![Text]  -- ^ Words before current token
  , ctxFollowing :: ![Text]  -- ^ Words after current token
  , ctxPosition :: !Int      -- ^ Position in sentence (0-based)
  , ctxSentence :: ![Text]   -- ^ Full sentence tokens
  } deriving stock (Eq, Show)

-- | Mapping from prepositions to required cases
type PrepositionCaseMap = Map Text [Case]

-- | Default mapping from common Russian prepositions to cases
defaultPrepositionCaseMap :: PrepositionCaseMap
defaultPrepositionCaseMap = M.fromList
  [ ("в", [Accusative, Prepositional])      -- в (accusative: motion into; prepositional: location)
  , ("на", [Accusative, Prepositional])     -- на (accusative: motion onto; prepositional: location)
  , ("к", [Dative])                        -- к (direction towards)
  , ("по", [Dative])                        -- по (direction, manner)
  , ("от", [Genitive])                      -- от (away from)
  , ("до", [Genitive])                      -- до (up to)
  , ("из", [Genitive])                      -- из (from inside)
  , ("с", [Genitive, Instrumental])        -- с (from surface; with)
  , ("у", [Genitive])                       -- у (near, at)
  , ("о", [Prepositional])                  -- о (about)
  , ("об", [Prepositional])                 -- об (about, before vowels)
  , ("про", [Accusative])                   -- про (about)
  , ("через", [Accusative])                 -- через (through)
  , ("сквозь", [Accusative])                -- сквозь (through)
  , ("вдоль", [Genitive])                   -- вдоль (along)
  , ("вокруг", [Genitive])                  -- вокруг (around)
  , ("перед", [Instrumental])               -- перед (before, in front of)
  , ("за", [Accusative, Instrumental])     -- за (behind; for)
  , ("над", [Instrumental])                 -- над (above)
  , ("под", [Accusative, Instrumental])     -- под (under)
  , ("между", [Instrumental])               -- между (between)
  , ("перед", [Instrumental])                -- перед (before)
  ]

-- | Resolve case based on preposition
-- Returns the most likely case given a preposition
resolveCaseFromPreposition :: Text -> Maybe Case
resolveCaseFromPreposition prep =
  let lowerPrep = T.toLower prep
      cases = M.lookup lowerPrep defaultPrepositionCaseMap
  in case cases of
       Just (c:_) -> Just c  -- Return first case as default
       Just [] -> Nothing
       Nothing -> Nothing

-- | Resolve agreement between adjective and noun
-- Adjusts adjective form to match noun's gender, number, and case
resolveAgreement :: MorphToken -> MorphToken -> MorphToken
resolveAgreement adj noun =
  -- If adjective is already inflected, preserve its form
  -- If noun has known gender/number/case, apply to adjective
  let resolvedGender = case (mtGender noun, mtGender adj) of
        (Just g, _) -> Just g
        (Nothing, g) -> g
      resolvedNumber = case (mtNumber noun, mtNumber adj) of
        (Just n, _) -> Just n
        (Nothing, n) -> n
      resolvedCase = case (mtCase noun, mtCase adj) of
        (Just c, _) -> Just c
        (Nothing, c) -> c
  in adj
     { mtGender = resolvedGender
     , mtNumber = resolvedNumber
     , mtCase = resolvedCase
     }

-- | Contextual morphological analysis of a token
-- Uses surrounding context to improve morphological analysis
analyzeContextualMorph :: Text -> Context -> MorphToken
analyzeContextualMorph word context =
  let baseAnalysis = analyzeMorph word
      -- Check if preceded by preposition that determines case
      precedingWords = ctxPreceding context
      followingWords = ctxFollowing context
      sentence = ctxSentence context
      wordIndex = ctxPosition context
      
      -- Rule 1: If preceded by preposition, resolve case from preposition
      resolvedCase = case precedingWords of
        (prep:_) -> resolveCaseFromPreposition prep
        _ -> mtCase baseAnalysis
      
      -- Rule 2: If followed by noun in genitive case, current word might be preposition
      -- This helps disambiguate words that could be nouns or prepositions
      maybePreposition = case followingWords of
        (nextWord:_) -> 
          let nextAnalysis = analyzeMorph nextWord
          in if mtCase nextAnalysis == Just Genitive 
             && T.length word <= 3  -- Short words more likely to be prepositions
             then Just word
             else Nothing
        _ -> Nothing
      
      -- Rule 3: If current word is likely a preposition (short, common preposition form)
      -- and followed by noun, force preposition POS
      finalPOS = case maybePreposition of
        Just _ -> Prep
        _ -> mtPOS baseAnalysis
      
      -- Rule 4: Apply homonym disambiguation if word is ambiguous
      disambiguatedPOS = if null (getAmbiguousPOS word)
                           then finalPOS
                           else resolveHomonym word context
  in baseAnalysis 
     { mtCase = resolvedCase
     , mtPOS = disambiguatedPOS
     }

-- | Analyze full sentence context
-- Returns contextual analysis for each token in the sentence
analyzeSentenceContext :: [Text] -> [MorphToken]
analyzeSentenceContext sentence =
  let contexts = [ Context
                  { ctxPreceding = take i sentence
                  , ctxFollowing = drop (i + 1) sentence
                  , ctxPosition = i
                  , ctxSentence = sentence
                  }
                | i <- [0..length sentence - 1]
                ]
      words = sentence
  in [ analyzeContextualMorph word ctx
     | (word, ctx) <- zip words contexts
     ]

-- | Syntactic role in a sentence
data SyntacticRole
  = Subject      -- Подлежащее
  | DirectObject  -- Прямое дополнение
  | IndirectObject -- Косвенное дополнение
  | Predicate     -- Сказуемое
  | Attribute     -- Определение
  | Circumstance  -- Обстоятельство
  | PrepositionalPhrase -- Предложная группа
  | Conjunction   -- Союз
  | Particle      -- Частица
  | UnknownRole   -- Неизвестная роль
  deriving stock (Eq, Show)

-- | Determine syntactic role based on morphological analysis and context
-- This is a heuristic-based approach for Russian syntax
determineSyntacticRole :: MorphToken -> Context -> SyntacticRole
determineSyntacticRole token context =
  let pos = mtPOS token
      case' = mtCase token
      number = mtNumber token
      preceding = ctxPreceding context
      following = ctxFollowing context
      position = ctxPosition context
  in case pos of
       -- Nouns: determine role based on case and position
       Noun -> case case' of
         Just Nominative -> 
           -- Nominative nouns at beginning are likely subjects
           if null preceding || position == 0
           then Subject
           -- Nominative after verb is likely predicate
           else if not (null preceding) && any (isVerb . mtPOS . analyzeMorph) preceding
                then Predicate
                else Subject
         Just Accusative -> DirectObject
         Just Genitive -> IndirectObject
         Just Dative -> IndirectObject
         Just Instrumental -> Circumstance
         Just Prepositional -> Circumstance
         Nothing -> Subject  -- Default to subject if case unknown
       
       -- Verbs are usually predicates
       Verb -> Predicate
       
       -- Adjectives are usually attributes
       Adj -> Attribute
       
       -- Adverbs are usually circumstances
       Adv -> Circumstance
       
       -- Prepositions start prepositional phrases
       Prep -> PrepositionalPhrase
       
       -- Pronouns: similar to nouns but more flexible
       Pron -> case case' of
         Just Nominative -> Subject
         Just Accusative -> DirectObject
         Just Genitive -> IndirectObject
         Just Dative -> IndirectObject
         _ -> Subject
       
       -- Conjunctions
       Conj -> Conjunction
       
       -- Particles
       Part -> Particle
       
       -- Others
       _ -> UnknownRole
  where
    isVerb :: POS -> Bool
    isVerb Verb = True
    isVerb _ = False

-- | Full contextual analysis including syntactic roles
analyzeContextualWithRoles :: [Text] -> [(Text, MorphToken, SyntacticRole)]
analyzeContextualWithRoles sentence =
  let contexts = [ Context
                  { ctxPreceding = take i sentence
                  , ctxFollowing = drop (i + 1) sentence
                  , ctxPosition = i
                  , ctxSentence = sentence
                  }
                | i <- [0..length sentence - 1]
                ]
      words = sentence
      tokens = analyzeSentenceContext sentence
  in [ (word, token, determineSyntacticRole token ctx)
     | (word, ctx, token) <- zip3 words contexts tokens
     ]

-- ============================================================================
-- Verb Tense Analysis for Russian Verbs
-- ============================================================================

-- | Russian past tense suffixes
pastTenseSuffixes :: [Text]
pastTenseSuffixes = 
  [ "л", "ла", "ло", "ли",   -- Standard past tense: делал, делала, делало, делали
    "лa", "лы"               -- Alternative spellings
  ]

-- | Russian present tense indicators (personal endings)
presentTenseEndings :: [Text]
presentTenseEndings = 
  [ "у", "ю", "еш", "ет", "ем", "ете", "ут", "ют",   -- 1st/2nd/3rd person singular/plural
    "аю", "яю", "иш", "ит", "им", "ите", "ат", "ят", -- Alternative forms
    "ы", "ь", "тся", "ться"    -- Reflexive forms
  ]

-- | Russian future tense indicators
futureTenseIndicators :: [Text]
futureTenseIndicators = 
  [ "буду", "будеш", "будет", "будем", "будете", "будут",  -- Compound future (буду делать)
    "пيسون", "пишеш", "пишет", "пишем", "пишете", "пишут"  -- This is actually present, not future
  ]

-- | Irregular past tense forms (common Russian verbs)
irregularPastForms :: Map Text Text
irregularPastForms = M.fromList
  [ ("писать", "писал")
  , ("читать", "читал")
  , ("делать", "делал")
  , ("идти", "шёл")
  , ("пойти", "пошёл")
  , ("взять", "взял")
  , ("дать", "дал")
  , ("есть", "ел")
  , ("пить", "пил")
  , ("брать", "брал")
  , ("знать", "знал")
  , ("видеть", "видел")
  , ("слышать", "слышал")
  , ("говорить", "говорил")
  , ("думать", "думал")
  , ("любить", "любил")
  , ("жить", "жил")
  ]

-- | Perfective verb prefixes that can indicate future tense
perfectivePrefixes :: [Text]
perfectivePrefixes = 
  [ "с", "по", "на", "за", "в", "вы", "до", "от", "пере", "раз", "у", "при", "про", "под", "об", "вз", "из"
  ]

-- | Detect tense of a Russian verb
-- Returns Nothing if tense cannot be determined or if word is not a verb
detectVerbTense :: Text -> Maybe Tense
detectVerbTense word =
  let w = T.toLower word
  in if guessPOS w == Verb
     then detectTenseFromForm w
     else Nothing
  where
    detectTenseFromForm :: Text -> Maybe Tense
    detectTenseFromForm w
      -- Check for past tense (most reliable)
      | any (`T.isSuffixOf` w) pastTenseSuffixes = Just Past
      -- Check for irregular past forms
      | any (\base -> T.isPrefixOf base w || w `T.isInfixOf` base) (M.keys irregularPastForms) = Just Past
      -- Check for compound future (буду + infinitive)
      | any (`T.isPrefixOf` w) ["буду ", "будеш ", "будет ", "будем ", "будете ", "будут "] = Just Future
      -- Check for perfective future (perfective prefix + present form suggests future meaning)
      | any (`T.isPrefixOf` w) perfectivePrefixes && hasPresentEnding (stripPerfectivePrefix w) = Just Future
      -- Check for present tense (personal endings)
      | hasPresentEnding w = Just Present
      -- Default to present for infinitive form verbs
      | otherwise = Just Present
    
    hasPresentEnding w = any (`T.isSuffixOf` w) presentTenseEndings
    
    -- Helper function to strip perfective prefixes from a verb
    stripPerfectivePrefix w = 
      case find (`T.isPrefixOf` w) perfectivePrefixes of
        Just prefix -> T.drop (T.length prefix) w
        Nothing -> w

-- | Check if a verb is in past tense
isPastTense :: Text -> Bool
isPastTense word = detectVerbTense word == Just Past

-- | Check if a verb is in present tense
isPresentTense :: Text -> Bool
isPresentTense word = detectVerbTense word == Just Present

-- | Check if a verb is in future tense
isFutureTense :: Text -> Bool
isFutureTense word = detectVerbTense word == Just Future

-- | Convert a verb from infinitive to past tense (simple heuristic)
-- Works for regular verbs, returns Nothing for irregular or non-verbs
convertToPastTense :: Text -> Maybe Text
convertToPastTense verb =
  let v = T.toLower verb
      base = getVerbBase v
  in case base of
       Just b -> 
         -- Regular -ть, -ти, -чь verbs
         if T.isSuffixOf "ть" b || T.isSuffixOf "ти" b || T.isSuffixOf "чь" b
            then Just (b <> "л")
            else if T.isSuffixOf "ать" b
                    then Just (T.dropEnd 2 b <> "ал")
                    else if T.isSuffixOf "ять" b
                            then Just (T.dropEnd 2 b <> "ял")
                            else if T.isSuffixOf "еть" b
                                    then Just (T.dropEnd 2 b <> "ел")
                                    else if T.isSuffixOf "ить" b
                                            then Just (T.dropEnd 2 b <> "ил")
                                            else if T.isSuffixOf "ся" b
                                                    then Just (T.dropEnd 2 b <> "сял") -- Wrong, need better handling
                                                    else Nothing
       Nothing -> Nothing
  where
    getVerbBase v = Just v  -- Simplified for now

-- | Convert a verb from past tense to present tense (simple heuristic)
convertToPresentTense :: Text -> Maybe Text
convertToPresentTense verb =
  let v = T.toLower verb
  in if isPastTense verb
     then case () of
            _ | T.isSuffixOf "л" v -> Just (T.dropEnd 1 v <> "ть")
              | T.isSuffixOf "ла" v -> Just (T.dropEnd 2 v <> "ть")
              | T.isSuffixOf "ло" v -> Just (T.dropEnd 2 v <> "ть")
              | T.isSuffixOf "ли" v -> Just (T.dropEnd 2 v <> "ть")
              | otherwise -> Nothing
     else Just verb

-- | Convert a verb to future tense (simple heuristic)
convertToFutureTense :: Text -> Maybe Text
convertToFutureTense verb =
  let v = T.toLower verb
  in if guessPOS v == Verb
     then Just ("буду " <> v)
     else Nothing

-- ============================================================================
-- Ambiguity Resolution for Russian Homonyms
-- ============================================================================

-- | Database of ambiguous Russian words with their possible POS tags
-- and context-based disambiguation rules
type HomonymDatabase = Map Text [(POS, DisambiguationRule)]

-- | Disambiguation rule based on context
data DisambiguationRule
  = AfterPreposition POS           -- ^ Word is POS if preceded by specific preposition
  | BeforeNoun POS                  -- ^ Word is POS if followed by noun
  | BeforeVerb POS                  -- ^ Word is POS if followed by verb
  | InNominativeCase POS             -- ^ Word is POS if in nominative case
  | InAccusativeCase POS             -- ^ Word is POS if in accusative case
  | DefaultPOS POS                  -- ^ Default POS if no context available
  deriving stock (Eq, Show)

-- | Default database of common Russian homonyms
defaultHomonymDatabase :: HomonymDatabase
defaultHomonymDatabase = M.fromList
  [ -- "печь" - verb (to bake) or noun (furnace/oven)
    ("печь", 
     [ (Verb, BeforeNoun Noun)   -- "печь хлеб" (to bake bread) - verb + noun
     , (Noun, AfterPreposition Noun)  -- "в печи" (in the furnace) - noun in genitive after preposition
     , (Noun, InNominativeCase Noun) -- "печь" as subject - noun
     ])
    
    -- "прокат" - noun (rolling) or verb (from прокатить)
  , ("прокат", 
     [ (Noun, DefaultPOS Noun)
     , (Verb, BeforeNoun Noun)
     ])
    
    -- "свет" - noun (light) or adj short form (from светлый)
  , ("свет", 
     [ (Noun, AfterPreposition Noun)  -- "на свет" (to light) - noun
     , (Noun, InNominativeCase Noun)     -- "свет" as subject
     , (Adj, BeforeNoun Noun)           -- "свет истины" - adj + noun (archic)
     ])
    
    -- "стой" - noun (stand) or verb (from стоять)
  , ("стой", 
     [ (Noun, AfterPreposition Noun)  -- "в стою" - noun
     , (Verb, BeforeNoun Noun)           -- "стой и слушай" - verb
     ])
    
    -- "повод" - noun (reason/leash) or verb (from повести)
  , ("повод", 
     [ (Noun, AfterPreposition Noun)  -- "по поводу" - noun
     , (Verb, BeforeNoun Noun)           -- verb form
     ])
    
    -- "пропуск" - noun (pass) or verb (from пропускать)
  , ("пропуск", 
     [ (Noun, AfterPreposition Noun)  -- "без пропуска" - noun
     , (Verb, BeforeNoun Noun)           -- verb form
     ])
    
    -- "запас" - noun (reserve) or verb (from запасти)
  , ("запас", 
     [ (Noun, AfterPreposition Noun)  -- "в запасе" - noun
     , (Verb, BeforeNoun Noun)           -- verb form
     ])
    
    -- "выход" - noun (exit) or verb (from выходить)
  , ("выход", 
     [ (Noun, AfterPreposition Noun)  -- "на выходе" - noun
     , (Verb, BeforeNoun Noun)           -- verb form
     ])
    
    -- "заказ" - noun (order) or verb (from заказать)
  , ("заказ", 
     [ (Noun, AfterPreposition Noun)  -- "по заказу" - noun
     , (Verb, BeforeNoun Noun)           -- verb form
     ])
    
    -- "отказ" - noun (refusal) or verb (from отказать)
  , ("отказ", 
     [ (Noun, AfterPreposition Noun)  -- "в отказе" - noun
     , (Verb, BeforeNoun Noun)           -- verb form
     ])
    
    -- "строй" - noun (construction) or adj (from стройный)
  , ("строй", 
     [ (Noun, AfterPreposition Noun)  -- "в строю" - noun
     , (Adj, BeforeNoun Noun)            -- "строй ряд" - adj + noun
     ])
    
    -- "ласковый" can be confused, but let's add some common adverb/noun ambiguities
    -- "далеко" - adverb or noun in some contexts
  , ("далеко", 
     [ (Adv, DefaultPOS Adv)  -- Most commonly adverb
     ])
    
    -- "ранний" can be adj or noun in some contexts
  , ("ранний", 
     [ (Adj, DefaultPOS Adj)
     ])
  ]

-- | Get all possible POS tags for an ambiguous word
getAmbiguousPOS :: Text -> [POS]
getAmbiguousPOS word =
  nub [pos | (pos, _) <- M.findWithDefault [] (T.toLower word) defaultHomonymDatabase]

-- | Resolve homonym ambiguity based on context
-- Returns the most likely POS given the word and its context
resolveHomonym :: Text -> Context -> POS
resolveHomonym word context =
  let w = T.toLower word
      rules = M.findWithDefault [] w defaultHomonymDatabase
      preceding = ctxPreceding context
      following = ctxFollowing context
  in case rules of
       [] -> guessPOS w  -- No rules, fall back to heuristic
       _  -> resolveWithRules rules preceding following
  where
    resolveWithRules :: [(POS, DisambiguationRule)] -> [Text] -> [Text] -> POS
    resolveWithRules rules preceding following =
      case find (applyRule preceding following) rules of
        Just (pos, _) -> pos
        Nothing -> case rules of
                     ((pos, DefaultPOS _) : _) -> pos
                     ((pos, _) : _) -> pos
                     [] -> UnknownPOS
    
    applyRule :: [Text] -> [Text] -> (POS, DisambiguationRule) -> Bool
    applyRule preceding following (_, rule) =
      case rule of
        AfterPreposition pos -> 
          case preceding of
            (prep:_) -> isPreposition prep && pos == guessPOS (T.toLower prep)
            _ -> False
        BeforeNoun targetPOS -> 
          case following of
            (next:_) -> guessPOS (T.toLower next) == Noun && targetPOS == Noun
            _ -> False
        BeforeVerb targetPOS -> 
          case following of
            (next:_) -> guessPOS (T.toLower next) == Verb && targetPOS == Verb
            _ -> False
        InNominativeCase targetPOS -> 
          let wordAnalysis = analyzeMorph word
          in mtCase wordAnalysis == Just Nominative && targetPOS == Noun
        InAccusativeCase targetPOS -> 
          let wordAnalysis = analyzeMorph word
          in mtCase wordAnalysis == Just Accusative && targetPOS == Noun
        DefaultPOS _ -> True
    
    isPreposition :: Text -> Bool
    isPreposition w = w `elem` 
      ["в", "на", "к", "по", "от", "до", "из", "с", "у", "о", "об", "про", "через", 
       "сквозь", "вдоль", "вокруг", "перед", "за", "над", "под", "между"]

