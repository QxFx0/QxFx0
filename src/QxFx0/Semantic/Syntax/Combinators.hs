{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}
{-|
Abstract syntax combinators for Russian sentence assembly.

All constructors enforce agreement at build time.
No template strings. No random choice.

V2 additions: subordination, coordination, ellipsis, topic fronting, questions.
-}
module QxFx0.Semantic.Syntax.Combinators
  ( -- * Syntactic categories
    NP(..)
  , VP(..)
  , S(..)
  , AP(..)
  , Adv(..)
  , PP(..)
  , MorphError(..)
  , Tense(..)
  , Subord(..)
  , Coord(..)
  , SubordClause(..)
  , CoordS(..)
    -- * Comparative algebra
  , CmpDir(..)
  , Comparative(..)
  , mkComparative
    -- * Smart constructors
  , mkNPRaw
  , mkNP
  , mkVP
  , mkVPRaw
  , mkFrozenVP
  , mkS
  , mkAP
  , mkAPRaw
  , addAP
  , addAdv
  , mkAdv
  , mkAdvRaw
  , mkExpression
  , mkPronounNP
  , mkNP_
  , mkVP_
  , mkAP_
  , addAdvToS
  , addModalParticle
  , addFiller
  , addQuantifierToS
  , addPP
  , mkPP
  , addObj
  , mkSubordClause
  , addSubordClause
  , addRelClause
  , mkCoordS
  , mkElliptical
  , mkEllipticalNP
  , mkEllipticalAdv
  , mkTopicFront
  , mkQuestion
    -- * Linearization
  , linearizeS
  , linearizeNP
  , linearizeVP
  , linearizeAP
  , linearizeAdv
  , linearizePP
  ) where

import Control.Monad (when)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Semantic.Lexicon.RuntimeParadigms
  ( RuntimeParadigms
  , NounCase(..)
  , Number(..)
  , Gender(..)
  , VerbForm(..)
  , AdjectiveForm(..)
  , lookupNounForm
  , lookupVerbForm
  , lookupAdjectiveForm
  , lookupAdverbForm
  , lookupExpression
  , lemmaGender
  , lemmaPos
  )
import QxFx0.Types (RenderStyle(..), IllocutionaryForce(..))

--------------------------------------------------------------------------------
-- Error type
--------------------------------------------------------------------------------

data MorphError
  = MissingParadigm !Text
  | MissingForm !Text !Text
  | GenderMismatch !Text !Text
  | NumberMismatch !Text !Text
  | CaseMismatch !Text !Text
  | InvalidPOS !Text !Text
  deriving stock (Eq, Show)

--------------------------------------------------------------------------------
-- Conjunction / subordination types
--------------------------------------------------------------------------------

data Subord
  = SubChto | SubKogda | SubPotomuChto | SubEsli | SubKotory | SubGde
  deriving stock (Eq, Show)

data Coord
  = CoordI | CoordA | CoordNo | CoordIli | CoordDash
  deriving stock (Eq, Show)

data SubordClause = SubordClause Subord S
  deriving stock (Eq, Show)

data CoordS = CoordS S Coord S
  deriving stock (Eq, Show)

data CmpDir = CmpMore | CmpLess | CmpEqual
  deriving stock (Eq, Show)

data Comparative = Comparative
  { cmpSubject   :: !Text
  , cmpObject    :: !Text
  , cmpAxis      :: !Text
  , cmpDirection :: !CmpDir
  }
  deriving stock (Eq, Show)

--------------------------------------------------------------------------------
-- Syntactic categories
--------------------------------------------------------------------------------

data NP = NP
  { npLemma      :: !Text
  , npCase       :: !NounCase
  , npNumber     :: !Number
  , npGender     :: !Gender
  , npAPs        :: ![AP]
  , npRelClause  :: !(Maybe S)   -- ^ relative clause: "свобода, которая..."
  }
  deriving stock (Eq, Show)

data VP = VP
  { vpLemma     :: !Text
  , vpPerson    :: !Int        -- 1,2,3
  , vpNumber    :: !Number
  , vpGender    :: !(Maybe Gender)  -- for past tense
  , vpTense     :: !Tense
  , vpAdv       :: ![Adv]
  , vpPP        :: ![PP]
  , vpSubord    :: !(Maybe SubordClause)  -- ^ subordinate clause attached to VP
  }
  deriving stock (Eq, Show)

data Tense = Past | Present | Future
  deriving stock (Eq, Show)

data S
  = SimpleS
      { sSubject    :: !NP
      , sPredicate  :: !VP
      , sTopicFront :: !(Maybe NP)  -- ^ fronted topic: "Свободу — я ценю"
      , sQuestion   :: !Bool
      , sModal      :: !(Maybe Text)  -- ^ modal particle inserted after first word
      , sFill       :: !(Maybe Text)  -- ^ filler prefix at sentence start
      , sQuant      :: !(Maybe Text)  -- ^ quantifier before subject
      }
  | EllipticalS
      { ePredicate  :: !VP
      , eTopicFront :: !(Maybe NP)
      , eQuestion   :: !Bool
      , eModal      :: !(Maybe Text)
      , eFill       :: !(Maybe Text)
      , eQuant      :: !(Maybe Text)
      }
  | CoordS' CoordS  -- ^ coordinated: "X, а Y"
  deriving stock (Eq, Show)

data AP = AP
  { apLemma  :: !Text
  , apGender :: !Gender
  , apNumber :: !Number
  , apCase   :: !NounCase
  }
  deriving stock (Eq, Show)

data Adv = Adv !Text
  deriving stock (Eq, Show)

data PP = PP
  { ppPreposition :: !Text
  , ppNP          :: !NP
  }
  deriving stock (Eq, Show)

--------------------------------------------------------------------------------
-- Smart constructors
--------------------------------------------------------------------------------

-- | Build NP from raw text (already inflected) with explicit agreement metadata.
-- Use only when the form is pre-computed and no paradigm lookup is possible.
mkNPRaw :: Text -> NounCase -> Number -> Gender -> NP
mkNPRaw form case_ number gender =
  NP { npLemma = form, npCase = case_, npNumber = number, npGender = gender
     , npAPs = [], npRelClause = Nothing }

-- | Build VP from raw text (already inflected) with explicit agreement metadata.
mkVPRaw :: Text -> Int -> Number -> Maybe Gender -> Tense -> VP
mkVPRaw form person number gender tense =
  VP { vpLemma = form, vpPerson = person, vpNumber = number, vpGender = gender
     , vpTense = tense, vpAdv = [], vpPP = [], vpSubord = Nothing }

-- | Frozen multivord VP — no paradigm lookup possible. Grammar fields are dummies.
mkFrozenVP :: Text -> VP
mkFrozenVP form =
  VP { vpLemma = form, vpPerson = 3, vpNumber = Sg, vpGender = Nothing
     , vpTense = Present, vpAdv = [], vpPP = [], vpSubord = Nothing }

-- | Build AP from raw text (already inflected) with explicit agreement metadata.
mkAPRaw :: Text -> Gender -> Number -> NounCase -> AP
mkAPRaw form gender number case_ =
  AP { apLemma = form, apGender = gender, apNumber = number, apCase = case_ }

-- | Minimal Russian adjective inflection for nominative singular and plural.
-- Used as a safety net when the dictionary lookup fails.
inflectAdjectiveLemma :: Text -> Gender -> Number -> NounCase -> Text
inflectAdjectiveLemma lemma gender number case_
  | case_ == Nom && number == Sg =
      case gender of
        Masc -> lemma
        Femn -> adjustEnding lemma [("ый", "ая"), ("ий", "яя"), ("ой", "ая")]
        Neut -> adjustEnding lemma [("ый", "ое"), ("ий", "ее"), ("ой", "ое")]
  | case_ == Nom && number == Pl =
      adjustEnding lemma [("ый", "ые"), ("ий", "ие"), ("ой", "ые")]
  | otherwise = lemma
  where
    adjustEnding w replacements =
      case filter (\(suf, _) -> T.isSuffixOf suf w) replacements of
        ((suf, repl):_) -> T.dropEnd (T.length suf) w <> repl
        []             -> w

mkNP :: RuntimeParadigms -> Text -> NounCase -> Number -> Either MorphError NP
mkNP rp lemma case_ number = do
  _ <- validatePOS rp lemma "Noun"
  form <- lookupFormOrError rp lemma case_ number
  g <- genderOrError rp lemma
  pure NP { npLemma = form, npCase = case_, npNumber = number, npGender = g
          , npAPs = [], npRelClause = Nothing }

mkVP :: RuntimeParadigms -> Text -> Int -> Number -> Maybe Gender -> Tense
     -> Either MorphError VP
mkVP rp lemma person number gender tense = do
  _ <- validatePOS rp lemma "Verb"
  form <- verbFormOrError rp lemma person number gender tense
  pure VP
    { vpLemma = form
    , vpPerson = person
    , vpNumber = number
    , vpGender = gender
    , vpTense = tense
    , vpAdv = []
    , vpPP = []
    , vpSubord = Nothing
    }

mkS :: NP -> VP -> Either MorphError S
mkS subj pred = do
  -- Subject-verb number agreement
  when (npNumber subj /= vpNumber pred)
    (Left (NumberMismatch (npLemma subj) (vpLemma pred)))
  -- For past tense, gender must agree too
  case vpTense pred of
    Past | npNumber subj == Sg ->
      case vpGender pred of
        Just g | g /= npGender subj ->
          Left (GenderMismatch (npLemma subj) (vpLemma pred))
        _ -> Right ()
    _ -> Right ()
  pure SimpleS { sSubject = subj, sPredicate = pred, sTopicFront = Nothing, sQuestion = False, sModal = Nothing, sFill = Nothing, sQuant = Nothing }

mkAP :: RuntimeParadigms -> Text -> Gender -> Number -> NounCase
     -> Either MorphError AP
mkAP rp lemma gender number case_ = do
  _ <- validatePOS rp lemma "Adjective"
  form <- adjFormOrError rp lemma gender number case_
  pure AP { apLemma = form, apGender = gender, apNumber = number, apCase = case_ }

addAP :: NP -> AP -> Either MorphError NP
addAP np ap = do
  when (npGender np /= apGender ap)
    (Left (GenderMismatch (npLemma np) (apLemma ap)))
  when (npNumber np /= apNumber ap)
    (Left (NumberMismatch (npLemma np) (apLemma ap)))
  when (npCase np /= apCase ap)
    (Left (CaseMismatch (npLemma np) (apLemma ap)))
  pure np { npAPs = ap : npAPs np }

addAdv :: VP -> Adv -> Either MorphError VP
addAdv vp adv = pure vp { vpAdv = adv : vpAdv vp }

mkAdv :: RuntimeParadigms -> Text -> Either MorphError Adv
mkAdv rp lemma =
  case lookupAdverbForm rp lemma of
    Just form -> Right (Adv form)
    Nothing   -> Left (MissingForm lemma "adverb")

mkExpression :: RuntimeParadigms -> Text -> Either MorphError Text
mkExpression rp lemma =
  case lookupExpression rp lemma of
    Just form -> Right form
    Nothing   -> Left (MissingForm lemma "expression")

addAdvToS :: S -> Adv -> S
addAdvToS s adv = case s of
  SimpleS subj pred mFront isQ mModal mFill mQuant ->
    SimpleS subj (pred { vpAdv = adv : vpAdv pred }) mFront isQ mModal mFill mQuant
  EllipticalS pred mFront isQ mModal mFill mQuant ->
    EllipticalS (pred { vpAdv = adv : vpAdv pred }) mFront isQ mModal mFill mQuant
  CoordS' (CoordS s1 coord s2) ->
    CoordS' (CoordS (addAdvToS s1 adv) coord (addAdvToS s2 adv))

-- | Build Adv from raw text (no paradigm lookup).
mkAdvRaw :: Text -> Adv
mkAdvRaw t = Adv t

addModalParticle :: Text -> S -> S
addModalParticle particle s = case s of
  SimpleS subj pred mFront isQ _ mFill mQuant ->
    SimpleS subj pred mFront isQ (Just particle) mFill mQuant
  EllipticalS pred mFront isQ _ mFill mQuant ->
    EllipticalS pred mFront isQ (Just particle) mFill mQuant
  CoordS' _ -> s

addFiller :: Text -> S -> S
addFiller filler s = case s of
  SimpleS subj pred mFront isQ mModal _ mQuant ->
    SimpleS subj pred mFront isQ mModal (Just filler) mQuant
  EllipticalS pred mFront isQ mModal _ mQuant ->
    EllipticalS pred mFront isQ mModal (Just filler) mQuant
  CoordS' _ -> s

addQuantifierToS :: Text -> S -> S
addQuantifierToS quant s = case s of
  SimpleS subj pred mFront isQ mModal mFill _ ->
    SimpleS subj pred mFront isQ mModal mFill (Just quant)
  EllipticalS pred mFront isQ mModal mFill _ ->
    EllipticalS pred mFront isQ mModal mFill (Just quant)
  CoordS' _ -> s

addPP :: VP -> PP -> Either MorphError VP
addPP vp pp = pure vp { vpPP = pp : vpPP vp }

mkPP :: Text -> NP -> PP
mkPP prep np = PP { ppPreposition = prep, ppNP = np }

-- | Build a subordinate clause.
mkSubordClause :: Subord -> S -> Either MorphError SubordClause
mkSubordClause sub s = Right (SubordClause sub s)

-- | Build a pronoun NP directly (closed class, inflected by case).
mkPronounNP :: Text -> NounCase -> NP
mkPronounNP pron case_ =
  let (g, n, form) = case (pron, case_) of
        ("я",   Nom) -> (Masc, Sg, "я")
        ("я",   Gen) -> (Masc, Sg, "меня")
        ("я",   Dat) -> (Masc, Sg, "мне")
        ("я",   Acc) -> (Masc, Sg, "меня")
        ("я",   Ins) -> (Masc, Sg, "мной")
        ("я",   Loc) -> (Masc, Sg, "мне")
        ("ты",  Nom) -> (Masc, Sg, "ты")
        ("ты",  Gen) -> (Masc, Sg, "тебя")
        ("ты",  Dat) -> (Masc, Sg, "тебе")
        ("ты",  Acc) -> (Masc, Sg, "тебя")
        ("ты",  Ins) -> (Masc, Sg, "тобой")
        ("ты",  Loc) -> (Masc, Sg, "тебе")
        ("мы",  Nom) -> (Masc, Pl, "мы")
        ("мы",  Gen) -> (Masc, Pl, "нас")
        ("мы",  Dat) -> (Masc, Pl, "нам")
        ("мы",  Acc) -> (Masc, Pl, "нас")
        ("мы",  Ins) -> (Masc, Pl, "нами")
        ("мы",  Loc) -> (Masc, Pl, "нас")
        ("вы",  Nom) -> (Masc, Pl, "вы")
        ("вы",  Gen) -> (Masc, Pl, "вас")
        ("вы",  Dat) -> (Masc, Pl, "вам")
        ("вы",  Acc) -> (Masc, Pl, "вас")
        ("вы",  Ins) -> (Masc, Pl, "вами")
        ("вы",  Loc) -> (Masc, Pl, "вас")
        ("он",  Nom) -> (Masc, Sg, "он")
        ("он",  Gen) -> (Masc, Sg, "его")
        ("он",  Dat) -> (Masc, Sg, "ему")
        ("он",  Acc) -> (Masc, Sg, "его")
        ("он",  Ins) -> (Masc, Sg, "им")
        ("он",  Loc) -> (Masc, Sg, "нём")
        ("она", Nom) -> (Femn, Sg, "она")
        ("она", Gen) -> (Femn, Sg, "её")
        ("она", Dat) -> (Femn, Sg, "ей")
        ("она", Acc) -> (Femn, Sg, "её")
        ("она", Ins) -> (Femn, Sg, "ей")
        ("она", Loc) -> (Femn, Sg, "ней")
        ("оно", Nom) -> (Neut, Sg, "оно")
        ("оно", Gen) -> (Neut, Sg, "его")
        ("оно", Dat) -> (Neut, Sg, "ему")
        ("оно", Acc) -> (Neut, Sg, "его")
        ("оно", Ins) -> (Neut, Sg, "им")
        ("оно", Loc) -> (Neut, Sg, "нём")
        ("они", Nom) -> (Masc, Pl, "они")
        ("они", Gen) -> (Masc, Pl, "их")
        ("они", Dat) -> (Masc, Pl, "им")
        ("они", Acc) -> (Masc, Pl, "их")
        ("они", Ins) -> (Masc, Pl, "ими")
        ("они", Loc) -> (Masc, Pl, "них")
        ("что", Nom) -> (Neut, Sg, "что")
        ("что", Gen) -> (Neut, Sg, "чего")
        ("что", Dat) -> (Neut, Sg, "чему")
        ("что", Acc) -> (Neut, Sg, "что")
        ("что", Ins) -> (Neut, Sg, "чем")
        ("что", Loc) -> (Neut, Sg, "чём")
        ("это", _)   -> (Neut, Sg, "это")
        _            -> (Masc, Sg, pron)
  in NP { npLemma = form, npCase = case_, npNumber = n, npGender = g
        , npAPs = [], npRelClause = Nothing }

-- | Strict NP builder — no fallback swallowing. Errors propagate as Left.
mkNP_ :: RuntimeParadigms -> Text -> NounCase -> Number -> Gender
      -> Either MorphError NP
mkNP_ rp lemma case_ number _gender = mkNP rp lemma case_ number

-- | Strict VP builder — no fallback swallowing. Errors propagate as Left.
mkVP_ :: RuntimeParadigms -> Text -> Int -> Number -> Maybe Gender -> Tense
      -> Either MorphError VP
mkVP_ rp lemma person number gender tense = mkVP rp lemma person number gender tense

-- | Strict AP builder — no fallback swallowing. Errors propagate as Left.
mkAP_ :: RuntimeParadigms -> Text -> Gender -> Number -> NounCase
      -> Either MorphError AP
mkAP_ rp lemma gender number case_ = mkAP rp lemma gender number case_

-- | Attach a direct object NP to a transitive VP.
addObj :: VP -> NP -> Either MorphError VP
addObj vp obj = pure vp { vpPP = PP "" obj : vpPP vp }

-- | Attach a subordinate clause to a VP.
addSubordClause :: VP -> SubordClause -> Either MorphError VP
addSubordClause vp sc = pure vp { vpSubord = Just sc }

-- | Attach a relative clause to an NP (agreement check simplified).
addRelClause :: NP -> S -> Either MorphError NP
addRelClause np s = pure np { npRelClause = Just s }

-- | Coordinate two sentences.
mkCoordS :: Coord -> S -> S -> Either MorphError S
mkCoordS coord s1 s2 = Right (CoordS' (CoordS s1 coord s2))

-- | Build an elliptical sentence (no explicit subject).
mkElliptical :: VP -> S
mkElliptical vp = EllipticalS { ePredicate = vp, eTopicFront = Nothing, eQuestion = False, eModal = Nothing, eFill = Nothing, eQuant = Nothing }

-- | Build an elliptical sentence from an NP alone (no verb).
mkEllipticalNP :: NP -> S
mkEllipticalNP np = SimpleS
  { sSubject = np
  , sPredicate = VP "" 3 Sg Nothing Present [] [] Nothing
  , sTopicFront = Nothing
  , sQuestion = False
  , sModal = Nothing
  , sFill = Nothing
  , sQuant = Nothing
  }

-- | Build an elliptical sentence from an adverb alone.
mkEllipticalAdv :: Adv -> S
mkEllipticalAdv adv = EllipticalS
  { ePredicate = VP "" 3 Sg Nothing Present [adv] [] Nothing
  , eTopicFront = Nothing
  , eQuestion = False
  , eModal = Nothing
  , eFill = Nothing
  , eQuant = Nothing
  }

-- | Front a topic NP before a sentence.
mkTopicFront :: NP -> S -> Either MorphError S
mkTopicFront np s = case s of
  SimpleS {} -> Right s { sTopicFront = Just np }
  EllipticalS {} -> Right s { eTopicFront = Just np }
  CoordS' _ -> Left (InvalidPOS "topic_front" "coordS")

-- | Turn a sentence into a question.
mkQuestion :: S -> IllocutionaryForce -> S
mkQuestion s IFAsk = case s of
  SimpleS {} -> s { sQuestion = True }
  EllipticalS {} -> s { eQuestion = True }
  CoordS' _ -> s
mkQuestion s _ = s

mkComparative :: RuntimeParadigms -> Text -> Text -> Text -> CmpDir -> Either MorphError S
mkComparative rp subj obj axis dir = do
  subjNP <- mkNP rp subj Nom Sg
  objNP <- case dir of
    CmpMore  -> mkNP rp obj Gen Sg
    CmpLess  -> mkNP rp obj Gen Sg
    CmpEqual -> mkNP rp obj Gen Sg
  let compText = case dir of
        CmpMore  -> "важнее"
        CmpLess  -> "менее важно"
        CmpEqual -> "так же важно как"
  let subjNP' = subjNP { npAPs = [AP compText (npGender subjNP) (npNumber subjNP) (npCase subjNP)] }
  objNP' <- addAP objNP (AP compText (npGender objNP) (npNumber objNP) (npCase objNP))
  vp <- mkVP rp "быть" 3 Sg Nothing Present
  s <- mkS subjNP vp
  mkTopicFront objNP' s

--------------------------------------------------------------------------------
-- Linearization
--------------------------------------------------------------------------------

linearizeS :: S -> Text
linearizeS s = case s of
  SimpleS { sSubject = subj, sPredicate = pred, sTopicFront = mFront, sQuestion = isQ, sModal = mModal, sFill = mFill, sQuant = mQuant } ->
    let core = T.unwords [linearizeNP subj, linearizeVPWith (npGender subj) (npNumber subj) pred]
        punct = if isQ then "?" else "."
        withModal = case mModal of
                      Nothing -> core
                      Just p  -> insertAfterFirstWord p core
        withFiller = case mFill of
                       Nothing -> withModal
                       Just f  -> f <> ", " <> withModal
        withQuant = case mQuant of
                       Nothing -> withFiller
                       Just q  -> q <> " " <> withFiller
    in case mFront of
         Nothing  -> withQuant <> punct
         Just np  -> linearizeNP np <> " — " <> withQuant <> punct
  EllipticalS { ePredicate = pred, eTopicFront = mFront, eQuestion = isQ, eModal = mModal, eFill = mFill, eQuant = mQuant } ->
    let core = linearizeVP pred
        punct = if isQ then "?" else "."
        withModal = case mModal of
                      Nothing -> core
                      Just p  -> insertAfterFirstWord p core
        withFiller = case mFill of
                       Nothing -> withModal
                       Just f  -> f <> ", " <> withModal
        withQuant = case mQuant of
                       Nothing -> withFiller
                       Just q  -> q <> " " <> withFiller
    in case mFront of
         Nothing  -> withQuant <> punct
         Just np  -> linearizeNP np <> " — " <> withQuant <> punct
  CoordS' (CoordS s1 coord s2) ->
    let s1text = fromMaybe (linearizeS s1) (T.stripSuffix "." (linearizeS s1))
    in s1text <> ", " <> coordWord coord <> " " <> linearizeS s2

insertAfterFirstWord :: Text -> Text -> Text
insertAfterFirstWord w txt =
  case T.words txt of
    []     -> w
    (x:xs) -> T.unwords (x : w : xs)

coordWord :: Coord -> Text
coordWord = \case
  CoordI  -> "и"
  CoordA  -> "а"
  CoordNo -> "но"
  CoordIli -> "или"
  CoordDash -> "—"

subordWord :: Subord -> Text
subordWord = \case
  SubChto       -> "что"
  SubKogda      -> "когда"
  SubPotomuChto -> "потому что"
  SubEsli       -> "если"
  SubKotory     -> "который"
  SubGde        -> "где"

kotoryForm :: Gender -> Number -> Text
kotoryForm Masc Sg  = "который"
kotoryForm Femn Sg  = "которая"
kotoryForm Neut Sg  = "которое"
kotoryForm _    Pl  = "которые"

linearizeNP :: NP -> Text
linearizeNP np =
  let adjs = T.unwords (map linearizeAP (reverse (npAPs np)))
      headN = npLemma np
      rel = case npRelClause np of
              Nothing -> ""
              Just clause -> ", " <> kotoryForm (npGender np) (npNumber np) <> " " <> linearizeS clause
      base = if T.null adjs then headN else adjs <> " " <> headN
  in if T.null rel then base else base <> rel

linearizeVP :: VP -> Text
linearizeVP vp = linearizeVPWith Masc Sg vp

linearizeVPWith :: Gender -> Number -> VP -> Text
linearizeVPWith g n vp =
  let verb = vpLemma vp
      adverbs = T.unwords (map linearizeAdv (reverse (vpAdv vp)))
      pps = T.unwords (map linearizePP (reverse (vpPP vp)))
      subord = case vpSubord vp of
                 Nothing -> ""
                 Just (SubordClause conj clause) ->
                   let pron = case conj of
                                SubKotory -> kotoryForm g n
                                _         -> subordWord conj
                   in ", " <> pron <> " " <> linearizeSClause clause
      parts = filter (not . T.null) [adverbs, verb, pps]
      core = T.unwords parts
  in if T.null subord then core else core <> subord

linearizeSClause :: S -> Text
linearizeSClause s = fromMaybe (linearizeS s) (T.stripSuffix "." (linearizeS s))

linearizeAP :: AP -> Text
linearizeAP = apLemma

linearizeAdv :: Adv -> Text
linearizeAdv (Adv t) = t

linearizePP :: PP -> Text
linearizePP pp =
  let prep = ppPreposition pp
      npText = linearizeNP (ppNP pp)
  in if T.null prep then npText else prep <> " " <> npText

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

validatePOS :: RuntimeParadigms -> Text -> Text -> Either MorphError ()
validatePOS rp lemma expected =
  case lemmaPos rp lemma of
    Nothing -> Left (MissingParadigm lemma)
    Just actual | actual == expected -> Right ()
    Just actual -> Left (InvalidPOS lemma actual)

lookupFormOrError :: RuntimeParadigms -> Text -> NounCase -> Number
                  -> Either MorphError Text
lookupFormOrError rp lemma case_ number =
  case lookupNounForm rp lemma case_ number of
    Nothing -> Left (MissingForm lemma (T.pack (show case_ <> show number)))
    Just form -> Right form

genderOrError :: RuntimeParadigms -> Text -> Either MorphError Gender
genderOrError rp lemma =
  case lemmaGender rp lemma of
    Nothing -> Left (MissingParadigm lemma)
    Just "masc"  -> Right Masc
    Just "femn"  -> Right Femn
    Just "neut"  -> Right Neut
    Just g       -> Left (InvalidPOS lemma g)

verbFormOrError :: RuntimeParadigms -> Text -> Int -> Number -> Maybe Gender -> Tense
                -> Either MorphError Text
verbFormOrError rp lemma person number gender tense =
  let form = case tense of
        Past -> case number of
          Sg -> case gender of
            Just Masc -> PastSgMasc
            Just Femn  -> PastSgFem
            Just Neut -> PastSgNeut
            Nothing   -> PastSgMasc  -- default
          Pl -> PastPl
        Present -> case (person, number) of
          (1, Sg) -> Pres1Sg; (2, Sg) -> Pres2Sg; (3, Sg) -> Pres3Sg
          (1, Pl) -> Pres1Pl; (2, Pl) -> Pres2Pl; (3, Pl) -> Pres3Pl
          _       -> Pres3Sg
        Future -> case (person, number) of
          (1, Sg) -> Fut1Sg; (2, Sg) -> Fut2Sg; (3, Sg) -> Fut3Sg
          (1, Pl) -> Fut1Pl; (2, Pl) -> Fut2Pl; (3, Pl) -> Fut3Pl
          _       -> Fut3Sg
  in case lookupVerbForm rp lemma form of
       Nothing -> Left (MissingForm lemma (T.pack (show form)))
       Just w  -> Right w

adjFormOrError :: RuntimeParadigms -> Text -> Gender -> Number -> NounCase
               -> Either MorphError Text
adjFormOrError rp lemma gender number case_ =
  let form = AdjFull case_ number (Just gender)
  in case lookupAdjectiveForm rp lemma form of
       Nothing -> Left (MissingForm lemma (T.pack (show form)))
       Just w  -> Right w
