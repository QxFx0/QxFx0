{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE DerivingStrategies #-}
{-|
Meaning assembly V2: combinator-based Russian sentence generation from FactAtoms.

No template strings. No pickVariant. Each step builds a syntactic tree (S).
FactAtoms already carry inflected forms; we use mkNPRaw with explicit
agreement metadata extracted from the lemma + RuntimeParadigms where possible.
-}
module QxFx0.Semantic.MeaningAssembly
  ( assembleExplanation
  , planAssembly
  , StepId(..)
  ) where

import Control.Monad (foldM)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Maybe (fromMaybe, listToMaybe, mapMaybe, isNothing)

import QxFx0.Semantic.MeaningAtom
  ( FactAtoms, AtomSlot(..), MeaningAtom(..)
  , slotValue, hasAtom, asValue, asGen, asPrep, asAcc, asIns, asPlural
  )
import QxFx0.Semantic.Lexicon.RuntimeParadigms
  ( RuntimeParadigms, NounCase(..), Number(..), Gender(..)
  , guessGender, guessGenderOr, lemmaGender, lookupMetaphor, lookupNounForm
  )
import QxFx0.Semantic.Syntax.Combinators
  ( NP(..), VP(..), S(..), AP(..), PP(..), Adv(..)
  , MorphError(..)
  , Tense(..)
  , Coord(..), Subord(..), SubordClause(..)
  , mkNPRaw, mkVP, mkVPRaw, mkS, mkAP, mkAPRaw, mkAP_, addAP, addPP, mkPP, addAdv
  , mkSubordClause, addSubordClause, mkCoordS, mkElliptical
  , linearizeS, mkVP_, mkNP_, mkPronounNP, addObj
  )
import QxFx0.Types (RenderStyle(..))

rightToMaybe :: Either e a -> Maybe a
rightToMaybe (Right a) = Just a
rightToMaybe (Left _)  = Nothing

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

data StepId
  = SIntroduce | SContext | SQuantify | SMechanism
  | SEffect | SAnalogy | SImplicate | SDiscoverer | SRelate
  | SVerbObject
  deriving (Eq, Ord, Show, Bounded, Enum)

type AssemblyPlan = [StepId]

--------------------------------------------------------------------------------
-- Entry point
--------------------------------------------------------------------------------

assembleExplanation :: RuntimeParadigms -> FactAtoms -> RenderStyle -> Either MorphError Text
assembleExplanation rp fact _style =
  let plan = planAssembly fact
  in buildComplex rp fact plan

buildComplex :: RuntimeParadigms -> FactAtoms -> AssemblyPlan -> Either MorphError Text
buildComplex rp fact plan = go plan []
  where
    go [] acc = Right (T.intercalate " " (reverse acc))
    go (step:rest) acc = case step of
      SIntroduce | SContext `elem` rest -> do
        sent <- introduceWithContext rp fact
        go (filter (/= SContext) rest) (linearizeS sent : acc)
      SMechanism | SEffect `elem` rest -> do
        sent <- mechanismWithEffect rp fact
        go (filter (/= SEffect) rest) (linearizeS sent : acc)
      SDiscoverer | SImplicate `elem` rest -> do
        sent <- discovererWithImplicate rp fact
        go (filter (/= SImplicate) rest) (linearizeS sent : acc)
      _ -> do
        sent <- stepToSentence rp fact step
        go rest (linearizeS sent : acc)

planAssembly :: FactAtoms -> AssemblyPlan
planAssembly fact = filter (available fact)
  [ SIntroduce, SVerbObject, SContext, SQuantify, SMechanism
  , SEffect, SAnalogy, SRelate, SDiscoverer, SImplicate ]

available :: FactAtoms -> StepId -> Bool
available fact = \case
  SIntroduce  -> hasAtom AtomSubject fact
  SContext    -> hasAtom AtomContext fact || hasAtom AtomRelation fact
  SQuantify   -> hasAtom AtomQuantity fact
  SMechanism  -> hasAtom AtomMechanism fact
  SEffect     -> hasAtom AtomEffect fact
  SAnalogy    -> hasAtom AtomAnalogy fact || hasAtom AtomScale fact
  SRelate     -> hasAtom AtomRelation fact
  SDiscoverer -> hasAtom AtomDiscoverer fact || hasAtom AtomYear fact
  SImplicate  -> hasAtom AtomReason fact || hasAtom TVerbReason fact
  SVerbObject -> hasAtom TVerb fact && hasAtom TObject fact

--------------------------------------------------------------------------------
-- Step → Sentence
--------------------------------------------------------------------------------

stepToSentence :: RuntimeParadigms -> FactAtoms -> StepId -> Either MorphError S
stepToSentence rp fact = \case
  SIntroduce  -> introduceSentence rp fact
  SContext    -> contextSentence rp fact
  SQuantify   -> quantifySentence rp fact
  SMechanism  -> mechanismSentence rp fact
  SEffect     -> effectSentence rp fact
  SAnalogy    -> analogySentence rp fact
  SRelate     -> relateSentence rp fact
  SDiscoverer -> discovererSentence rp fact
  SImplicate  -> implicateSentence rp fact
  SVerbObject -> verbObjectStep rp fact

--------------------------------------------------------------------------------
-- INTRODUCE: Subject + "является" + property NP (instrumental)
-- "Сердце является полым мышечным органом."
--------------------------------------------------------------------------------

introduceSentence :: RuntimeParadigms -> FactAtoms -> Either MorphError S
introduceSentence rp fact = do
  subj <- subjectNP rp fact Nom
  let num = npNumber subj
      g   = npGender subj
  let aps = propertyAPs rp fact g num Ins
  propNoun <- propertyNounNP rp fact num g
  vp <- mkVP_ rp "являться" 3 num (Just g) Present
  case propNoun of
    Just pn -> do
      pn2 <- foldM addAP pn aps
      vp2 <- addObj vp pn2
      mkS subj vp2
    Nothing ->
      if null aps
        then mkS subj vp
        else do
          let adjText = T.unwords (map apLemma aps)
              adjNP = mkNPRaw adjText Ins num g
          vp2 <- addObj vp adjNP
          mkS subj vp2

--------------------------------------------------------------------------------
-- CONTEXT: "В [context] [relation]."
--------------------------------------------------------------------------------

contextSentence :: RuntimeParadigms -> FactAtoms -> Either MorphError S
contextSentence rp fact = do
  ctx <- contextNP rp fact
  rel <- relationNP rp fact
  subj <- subjectNP rp fact Nom
  vp <- mkVP_ rp "работать" 3 (npNumber subj) (Just (npGender subj)) Present
  let pp1 = mkPP "в" ctx
  vp2 <- addPP vp pp1
  vp3 <- case rel of
           Nothing -> pure vp2
           Just r  -> addPP vp2 (mkPP "как" r)
  mkS subj vp3

--------------------------------------------------------------------------------
-- QUANTIFY: "[Subject] составляет ≈ [Q] [Unit] [Period]."
--------------------------------------------------------------------------------

quantifySentence :: RuntimeParadigms -> FactAtoms -> Either MorphError S
quantifySentence rp fact = do
  subj <- subjectNP rp fact Nom
  (qNP, perPP) <- quantityNP rp fact
  vp <- mkVP_ rp "составлять" 3 (npNumber subj) (Just (npGender subj)) Present
  vp2 <- addPP vp (mkPP "≈" qNP)
  vp3 <- case perPP of
           Nothing -> pure vp2
           Just pp -> addPP vp2 pp
  mkS subj vp3

--------------------------------------------------------------------------------
-- MECHANISM: "[Subject] [verb-mechanism]."
--------------------------------------------------------------------------------

mechanismSentence :: RuntimeParadigms -> FactAtoms -> Either MorphError S
mechanismSentence rp fact = do
  subj <- subjectNP rp fact Nom
  mech <- mechanismVP rp fact
  mkS subj mech

--------------------------------------------------------------------------------
-- EFFECT: "[Subject] [verb-effect]."
--------------------------------------------------------------------------------

effectSentence :: RuntimeParadigms -> FactAtoms -> Either MorphError S
effectSentence rp fact = do
  subj <- subjectNP rp fact Nom
  eff <- effectVP rp fact
  mkS subj eff

--------------------------------------------------------------------------------
-- ANALOGY: "[Subject] — это как [analogy]."
--------------------------------------------------------------------------------

analogySentence :: RuntimeParadigms -> FactAtoms -> Either MorphError S
analogySentence rp fact = do
  subj <- subjectNP rp fact Nom
  ana <- analogyNP rp fact
  vp <- mkVP_ rp "быть" 3 (npNumber subj) (Just (npGender subj)) Present
  let pp = mkPP "как" ana
  vp2 <- addPP vp pp
  mkS subj vp2

--------------------------------------------------------------------------------
-- RELATE: "[Subject] [relation-verb]."
--------------------------------------------------------------------------------

relateSentence :: RuntimeParadigms -> FactAtoms -> Either MorphError S
relateSentence rp fact = do
  subj <- subjectNP rp fact Nom
  rel <- relationVP rp (npNumber subj) fact
  mkS subj rel

--------------------------------------------------------------------------------
-- DISCOVERER: "Открыт [Ins] в [Year] году."
--------------------------------------------------------------------------------

discovererSentence :: RuntimeParadigms -> FactAtoms -> Either MorphError S
discovererSentence rp fact = do
  disc <- discovererNP rp fact
  yr   <- yearNP rp fact
  let subj = mkPronounNP "это" Nom
  vp   <- mkVP_ rp "открываться" 3 Sg Nothing Past
  vp2  <- addPP vp (mkPP "" disc)  -- preposition omitted for instrumental subject
  vp3  <- addPP vp2 (mkPP "в" yr)
  mkS subj vp3

--------------------------------------------------------------------------------
-- IMPLICATE: "Поэтому [Subject] [reason-verb]."
--------------------------------------------------------------------------------

implicateSentence :: RuntimeParadigms -> FactAtoms -> Either MorphError S
implicateSentence rp fact = do
  subj <- subjectNP rp fact Nom
  reason <- reasonVP rp (npNumber subj) fact
  mkS subj reason

-------------------------------------------------------------------------------
-- VERBOBJECT: verb + object clause
-------------------------------------------------------------------------------

verbObjectStep :: RuntimeParadigms -> FactAtoms -> Either MorphError S
verbObjectStep rp fact = do
  subj <- subjectNP rp fact Nom
  let verbs = slotValue TVerb fact
      objs = slotValue TObject fact
      -- [fallback] Slot extraction failed — use dictionary-backed defaults.
      verbText = fromMaybe "делать" (listToMaybe (map asValue verbs))
      objLemma = fromMaybe "нечто" (listToMaybe (map asValue objs))
  vp <- mkVP_ rp verbText 3 (npNumber subj) (Just (npGender subj)) Present
  let g = fromMaybe Masc (guessGender rp objLemma)
  objNP <- mkNP_ rp objLemma Acc Sg g
  vp2 <- addObj vp objNP
  mkS subj vp2

--------------------------------------------------------------------------------
-- Helpers: build NPs/VPs from FactAtoms slots
--------------------------------------------------------------------------------

introduceWithContext :: RuntimeParadigms -> FactAtoms -> Either MorphError S
introduceWithContext rp fact = do
  subj <- subjectNP rp fact Nom
  let num = npNumber subj
      g   = npGender subj
  let aps = propertyAPs rp fact g num Ins
  propNoun <- propertyNounNP rp fact num g
  vp <- mkVP_ rp "являться" 3 num (Just g) Present
  let (subjFinal, vpFinal) = case propNoun of
        Just pn | Right pn2 <- foldM addAP pn aps ->
          (subj, case addObj vp pn2 of Right v2 -> v2; Left _ -> vp)
        _ ->
          if null aps
            then (subj, vp)
            else (subj, case addObj vp (mkNPRaw (T.unwords (map apLemma aps)) Ins num g) of Right v2 -> v2; Left _ -> vp)
  ctxNP <- contextNP rp fact
  ctxRel <- relationNP rp fact
  ctxVP <- mkVP_ rp "работать" 3 num (Just g) Present
  ctxVP2 <- addPP ctxVP (mkPP "в" ctxNP)
  ctxVP3 <- case ctxRel of
    Nothing -> pure ctxVP2
    Just r  -> addPP ctxVP2 (mkPP "как" r)
  let ctxEll = mkElliptical ctxVP3
  subord <- mkSubordClause SubKotory ctxEll
  vpFinal2 <- addSubordClause vpFinal subord
  mkS subjFinal vpFinal2

mechanismWithEffect :: RuntimeParadigms -> FactAtoms -> Either MorphError S
mechanismWithEffect rp fact = do
  mechS <- mechanismSentence rp fact
  effVP <- effectVP rp fact
  let effS = mkElliptical effVP
  mkCoordS CoordI mechS effS

discovererWithImplicate :: RuntimeParadigms -> FactAtoms -> Either MorphError S
discovererWithImplicate rp fact = do
  discS <- discovererSentence rp fact
  impS <- implicateSentence rp fact
  mkCoordS CoordI discS impS

subjectNP :: RuntimeParadigms -> FactAtoms -> NounCase -> Either MorphError NP
subjectNP rp fact case_ =
  let slots = slotValue AtomSubject fact
  in case slots of
       (s:_) ->
         let isPlural = not (T.null (asPlural s)) && asValue s == asPlural s
             num = if isPlural then Pl else Sg
             g = fromMaybe Masc (guessGender rp (asValue s))
         in Right (slotToNP rp s case_ num g)
       [] -> Left (MissingParadigm "subject")

propertyAPs :: RuntimeParadigms -> FactAtoms -> Gender -> Number -> NounCase -> [AP]
propertyAPs rp fact g num case_ =
  let slots = slotValue AtomProperty fact
      isMod s = asAtom s == TModifier
      mods = filter isMod slots
      tryMake apLemma = rightToMaybe (mkAP_ rp apLemma g num case_)
  in mapMaybe (tryMake . asValue) mods

propertyNounNP :: RuntimeParadigms -> FactAtoms -> Number -> Gender -> Either MorphError (Maybe NP)
propertyNounNP rp fact num g =
  let slots = slotValue AtomProperty fact
      isNounProp s = asAtom s /= TModifier
      nounSlots = filter isNounProp slots
  in case nounSlots of
       (s:_) -> Right (Just (slotToNP rp s Ins num g))
       []    -> Right Nothing

-- | Best-effort NP from AtomSlot: try paradigm lookup via mkNP_,
--   fall back to the pre-inflected form stored in the slot.
slotToNP :: RuntimeParadigms -> AtomSlot -> NounCase -> Number -> Gender -> NP
slotToNP rp s case_ num g =
  case mkNP_ rp (asValue s) case_ num g of
    Right np -> np
    Left _   ->
      let form = case case_ of
                   Nom -> asValue s; Gen -> asGen s; Dat -> asGen s
                   Acc -> asAcc s; Ins -> asIns s; Loc -> asPrep s
      in mkNPRaw form case_ num g

contextNP :: RuntimeParadigms -> FactAtoms -> Either MorphError NP
contextNP rp fact =
  let allSlots = slotValue AtomContext fact
      nounSlots = filter (\s -> asAtom s /= TModifier) allSlots
      modSlots = filter (\s -> asAtom s == TModifier) allSlots
   in case nounSlots of
       (s:_) -> do
         let g = guessGenderOr rp Masc (asValue s)
             num = if not (T.null (asPlural s)) && asValue s == asPlural s then Pl else Sg
             np = slotToNP rp s Loc num g
         aps <- mapM (\m -> mkAP_ rp (asValue m) g num Loc) modSlots
         foldM addAP np aps
       []    -> Left (MissingParadigm "context")

relationNP :: RuntimeParadigms -> FactAtoms -> Either MorphError (Maybe NP)
relationNP rp fact =
  let allSlots = slotValue AtomRelation fact
      nounSlots = filter (\s -> asAtom s /= TModifier) allSlots
      modSlots = filter (\s -> asAtom s == TModifier) allSlots
   in case nounSlots of
        [] -> Right Nothing
        (s:_) -> do
          let g = guessGenderOr rp Masc (asValue s)
              num = if not (T.null (asPlural s)) && asValue s == asPlural s then Pl else Sg
              np = slotToNP rp s Nom num g
          aps <- mapM (\m -> mkAP_ rp (asValue m) g num Nom) modSlots
          np2 <- foldM addAP np aps
          Right (Just np2)

quantityNP :: RuntimeParadigms -> FactAtoms -> Either MorphError (NP, Maybe PP)
quantityNP rp fact =
  let quants = slotValue AtomQuantity fact
      units  = slotValue AtomUnit fact
      period = slotValue AtomPeriod fact
      padSlot = AtomSlot AtomUnit "" "" "" "" "" ""
      unitForm u qVal = case numberAgreement qVal of
        NumNomSg  -> asValue u
        NumGenSg  -> asGen u
        NumGenPl  -> fromMaybe (asGen u) (lookupNounForm rp (asValue u) Gen Pl)
      qText  = T.unwords (zipWith (\q u -> asValue q <> " " <> unitForm u (asValue q))
                                  (take 1 quants) (take 1 units ++ repeat padSlot))
      perPP  = case period of
                 (p:_) ->
                   let fallback = mkNPRaw (asValue p) Acc Pl Femn
                       perNP  = case mkNP_ rp (asValue p) Acc Pl Femn of
                                  Right np -> np
                                  Left _   -> fallback
                   in Just (mkPP "за" perNP)
                 []    -> Nothing
  in Right (mkNPRaw qText Acc Sg Neut, perPP)

mechanismVP :: RuntimeParadigms -> FactAtoms -> Either MorphError VP
mechanismVP rp fact = do
  subj <- subjectNP rp fact Nom
  let verbs = slotValue TVerb fact
      objs  = slotValue TObject fact
      verbText = fromMaybe "работать" (listToMaybe (map asValue verbs))
  mkVP_ rp verbText 3 (npNumber subj) Nothing Present

effectVP :: RuntimeParadigms -> FactAtoms -> Either MorphError VP
effectVP rp fact = do
  subj <- subjectNP rp fact Nom
  let verbs = slotValue TVerb fact
      verbText = fromMaybe "дать" (listToMaybe (map asValue verbs))
  mkVP_ rp verbText 3 (npNumber subj) Nothing Present

analogyNP :: RuntimeParadigms -> FactAtoms -> Either MorphError NP
analogyNP rp fact =
  let anas  = slotValue AtomAnalogy fact
      scales = slotValue AtomScale fact
      allItems = anas ++ scales
      text = T.intercalate " или " (map asValue allItems)
      fallback = mkNPRaw text Acc Sg Neut
  in Right (case mkNP_ rp text Acc Sg Neut of
              Right np -> np
              Left _   -> fallback)

relationVP :: RuntimeParadigms -> Number -> FactAtoms -> Either MorphError VP
relationVP rp num fact =
  let allSlots = slotValue AtomRelation fact
      nounSlots = filter (\s -> asAtom s /= TModifier) allSlots
      modSlots = filter (\s -> asAtom s == TModifier) allSlots
  in case nounSlots of
        (s:_) -> do
          let g = guessGenderOr rp Masc (asValue s)
          aps <- mapM (\m -> mkAP_ rp (asValue m) g num Ins) modSlots
          if isComparative (asValue s)
            then do
              vp <- mkVP_ rp "являться" 3 num Nothing Present
              addPP vp (mkPP "" (slotToNP rp s Nom Sg g))
            else do
              let objNP = slotToNP rp s Ins num g
              objNP2 <- foldM addAP objNP aps
              vp <- mkVP_ rp "являться" 3 num Nothing Present
              addObj vp objNP2
        []    -> Left (MissingParadigm "relation")

isComparative :: Text -> Bool
isComparative t = any (`T.isPrefixOf` t)
  ["выше","ниже","длиннее","короче","быстрее","медленнее","больше","меньше","сильнее","слабее"]


discovererNP :: RuntimeParadigms -> FactAtoms -> Either MorphError NP
discovererNP rp fact =
  let slots = slotValue AtomDiscoverer fact
  in case slots of
       (s:_) -> let g = guessGenderOr rp Masc (asValue s)
                    num = if not (T.null (asPlural s)) && asValue s == asPlural s then Pl else Sg
                 in Right (slotToNP rp s Ins num g)
       []    -> Left (MissingParadigm "discoverer")

yearNP :: RuntimeParadigms -> FactAtoms -> Either MorphError NP
yearNP rp fact =
  let slots = slotValue AtomYear fact
      fallback t = mkNPRaw t Acc Sg Neut
      tryNP t = case mkNP_ rp t Acc Sg Neut of
                  Right np -> np
                  Left _   -> fallback t
  in case slots of
       (s:_) -> Right (tryNP (asValue s))
       []    -> Right (fallback "")

reasonVP :: RuntimeParadigms -> Number -> FactAtoms -> Either MorphError VP
reasonVP rp num fact =
  let rVerbs = slotValue TVerbReason fact
      rObjs  = slotValue TObjectReason fact
  in case (rVerbs, rObjs) of
       (v:_, o:_) -> do
         vp <- mkVP_ rp (asValue v) 3 num Nothing Present
         let g = fromMaybe Masc (guessGender rp (asValue o))
         objNP <- mkNP_ rp (asValue o) Acc num g
         addObj vp objNP
       _ ->
         let slots = slotValue AtomReason fact
         in case slots of
              (s:_) -> do
                let g = guessGenderOr rp Masc (asValue s)
                objNP <- mkNP_ rp (asValue s) Ins num g
                vp <- mkVP_ rp "являться" 3 num Nothing Present
                addObj vp objNP
              [] -> Left (MissingParadigm "reason")

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

data NumAgreement = NumNomSg | NumGenSg | NumGenPl
  deriving stock (Eq, Show)

numberAgreement :: Text -> NumAgreement
numberAgreement qVal
  | T.any (`elem` [',', '.']) qVal = NumGenSg
  | otherwise = case parseLastDigits qVal of
      Just (lastTwo, lastOne)
        | lastTwo `elem` [11,12,13,14] -> NumGenPl
        | lastOne == 1                 -> NumNomSg
        | lastOne `elem` [2,3,4]       -> NumGenSg
        | otherwise                    -> NumGenPl
      Nothing -> NumGenPl
  where
    parseLastDigits t =
      let digits = T.filter (`elem` ('0':'1':'2':'3':'4':'5':'6':'7':'8':'9':[])) t
      in if T.null digits then Nothing
         else case reads (T.unpack (T.takeEnd 2 digits)) of
                [(n,"")] -> Just (n, n `mod` 10)
                [(n,_)]  -> Just (n, n `mod` 10)
                _        -> Nothing
