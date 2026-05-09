{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE LambdaCase #-}
{-|
Dialog assembly V2: pure combinator-based Russian sentence generation.

No template strings. No random pickV.
Each step builds a syntactic tree (NP/VP/S) and linearizes it.
-}
module QxFx0.Semantic.DialogAssembly
  ( assembleTurn
  , assembleTurnWithGraph
  , planAssembly
  , planAssemblyWithTransition
  , StepId(..)
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import Control.Monad (foldM)
import Data.Maybe (fromMaybe, listToMaybe, mapMaybe, maybeToList)

import QxFx0.Semantic.DialogAtom
import QxFx0.Semantic.Lexicon.RuntimeParadigms
  ( RuntimeParadigms, NounCase(..), Number(..), Gender(..)
  , emptyRuntimeParadigms, lookupMetaphor
  , guessGenderOr
  )
import QxFx0.Semantic.Syntax.Combinators
  ( NP(..), VP(..), S(..), AP(..), Adv(..)
  , MorphError(..)
  , Tense(..)
  , Coord(..)
  , mkNPRaw, mkNP, mkVPRaw, mkFrozenVP, mkS, mkAP, addAP, addPP, mkPP
  , mkTopicFront, mkElliptical, mkEllipticalNP, mkEllipticalAdv, mkCoordS, mkQuestion
  , mkAdv, mkAdvRaw, addAdvToS, addModalParticle, addFiller, addQuantifierToS
  , linearizeS, linearizeNP, mkPronounNP, mkNP_, mkVP_, mkAP_, addObj
  )
import QxFx0.Types (RenderStyle(..), IllocutionaryForce(..), GeodesicPlan(..))
import QxFx0.Types.State.Discourse
  ( DiscourseState(..)
  , EngagementLevel(..), DialogPhase(..)
  , recomputeDiscourse
  )


--------------------------------------------------------------------------------
-- Main entry
--------------------------------------------------------------------------------

assembleTurn :: RuntimeParadigms -> DialogAtoms -> RenderStyle -> DiscourseState -> Either MorphError Text
assembleTurn rp da style ds = assembleTurnWithGraph rp da style ds Nothing

assembleTurnWithGraph :: RuntimeParadigms -> DialogAtoms -> RenderStyle -> DiscourseState -> Maybe GeodesicPlan -> Either MorphError Text
assembleTurnWithGraph rp da style ds mGeodesicPlan =
  let recomputed = recomputeDiscourse ds
      usePoliteness = dscEngagement recomputed == LowEngagement && topicHash da `mod` 10 < 5
      useEmphatic = hasTag TEmphatic da && topicHash da `mod` 10 < 4
      plan = planAssemblyWithTransition da ds mGeodesicPlan
  in case plan of
    []       -> Right ""
    [step]   -> do
      s <- runStep rp da style step
      let withEmph = if useEmphatic
                     then addFiller (headAtomValue TEmphatic da) s
                     else s
          withModal = if hasTag TModal da
                      then addModalParticle (headAtomValue TModal da) withEmph
                      else withEmph
          withFiller = if hasTag TFiller da
                       then addFiller (headAtomValue TFiller da) withModal
                       else withModal
          withPolite = if usePoliteness
                       then addFiller "если можно" withFiller
                       else withFiller
      Right (linearizeS withPolite)
    (firstStep:restSteps) -> do
      let planLen = length restSteps + 1
          useSelfCorrect = planLen >= 3 && topicHash da `mod` 10 < 3
      firstSent <- runStep rp da style firstStep
      let withEmph = if useEmphatic
                     then addFiller (headAtomValue TEmphatic da) firstSent
                     else firstSent
          withModal = if hasTag TModal da
                      then addModalParticle (headAtomValue TModal da) withEmph
                      else withEmph
          withFiller = if hasTag TFiller da
                       then addFiller (headAtomValue TFiller da) withModal
                       else withModal
          withPolite = if usePoliteness
                       then addFiller "если можно" withFiller
                       else withFiller
      if useSelfCorrect && planLen >= 2
        then do
          let (initSteps, [lastStep]) = splitAt (planLen - 1) (firstStep:restSteps)
          initSents <- mapM (runStep rp da style) initSteps
          lastSent <- runStep rp da style lastStep
          let corrected = addFiller "то есть" lastSent
          combined <- foldM (\acc s -> mkCoordS CoordA acc s) withPolite (initSents ++ [corrected])
          Right (linearizeS combined)
        else do
          restSents <- mapM (runStep rp da style) restSteps
          combined <- foldM (\acc s -> mkCoordS CoordA acc s) withPolite restSents
          Right (linearizeS combined)
data StepId = SAcknowledge | SStance | SEngage | SReflect
  | SIdentity    | SConstraint | SRepair
  | SContact     | SGround | SClarify | SDeepen
  | SNext | SGreet | SFarewell
  | SHedge | SConnect
  | SDefine | SPurpose | SDistinguish
  | SAgree | SDisagree | SRelated
  | SModal | SQuantify | SSelfCorrect | SEmphatic | SNarrative | SMetaphor
  deriving (Eq, Ord, Show, Bounded, Enum)

type AssemblyPlan = [StepId]

planAssembly :: DialogAtoms -> DiscourseState -> AssemblyPlan
planAssembly da ds =
  let recomputed = recomputeDiscourse ds
      intent = headAtomValue TUserIntent da
      topic = headAtomValue TTopic da
      isGreet = hasTag TGreeting da
      isFarewell = hasTag TFarewell da
      isDistress = emotionIs "distress" da
      topicRepeated = topic `elem` dscTopicChain ds
      turnDepth = length (dscTurnMemory ds)
      primary = case () of
        _ | isGreet                    -> SGreet
        _ | isFarewell                 -> SFarewell
        _ | intent == "define"         -> SDefine
        _ | intent == "clarify"        -> SClarify
        _ | intent == "deepen"         -> SDeepen
        _ | intent == "ask_purpose"    -> SPurpose
        _ | intent == "hypothesize"    -> SDeepen
        _ | intent == "next"           -> SNext
        _ | intent == "complain"       -> SRepair
        _ | intent == "distinguish"    -> SDistinguish
        _ | intent == "reflect"        -> SReflect
        _ | intent == "describe"       -> if hasTag TScale da then SNarrative else SAcknowledge
        _ | intent == "ground"         -> SGround
        _ | intent == "connect"        -> SEngage
        _ | intent == "anchor"         -> SGround
        _ | isDistress                 -> SReflect
        _ | otherwise                  -> SEngage
      hasTopic = hasTag TTopic da
      hasRelated = hasTag TRelatedTopic da
      planLen = case dscEngagement recomputed of
        HighEngagement   -> 4
        MediumEngagement -> 3
        LowEngagement    -> 2
      -- Suppress grounding in deep phase
      needGround = hasTopic && not topicRepeated && dscPhase recomputed /= PhaseDeep
      secondary = case primary of
        SGround -> Nothing
        _ | needGround                   -> Just SGround
        _ | hasTopic && turnDepth < 3    -> Just SGround
        _ -> Nothing
      tertiary = if topicRepeated && hasRelated then Just SRelated else Nothing
      hasProps = hasTag TProperty da
      qStep = if hasProps then Just SQuantify else Nothing
      allSteps = primary : maybeToList qStep ++ maybeToList secondary ++ maybeToList tertiary
  in take planLen allSteps

planAssemblyWithTransition :: DialogAtoms -> DiscourseState -> Maybe GeodesicPlan -> AssemblyPlan
planAssemblyWithTransition da ds mGeodesicPlan =
  let basePlan = planAssembly da ds
      topic = headAtomValue TTopic da
      prevTopic = case dscTopicChain ds of
                    (prev:_) | prev /= topic && not (T.null prev) && not (T.null topic) -> Just prev
                    _ -> Nothing
      transitionSteps = case (prevTopic, mGeodesicPlan) of
        (Just _, Just (BridgedJump _)) -> [SContact]
        _ -> []
  in if null transitionSteps then basePlan else transitionSteps ++ basePlan

emotionIs :: Text -> DialogAtoms -> Bool
emotionIs tag da = any ((tag ==) . asValue) (atomValue TEmotion da)

--------------------------------------------------------------------------------
-- Step implementations (combinators)
--------------------------------------------------------------------------------

runStep :: RuntimeParadigms -> DialogAtoms -> RenderStyle -> StepId -> Either MorphError S
runStep rp da style = \case
  SAcknowledge -> ackStep rp da style
  SStance      -> stStep rp da style
  SEngage      -> engStep rp da style
  SReflect     -> refStep rp da style
  SIdentity    -> idStep rp da style
  SConstraint  -> conStep rp da style
  SRepair      -> repStep rp da style
  SContact     -> con2Step rp da style
  SGround      -> gndStep rp da style
  SClarify     -> clarStep rp da style
  SDeepen      -> dStep rp da style
  SNext        -> nStep rp da style
  SGreet       -> greStep rp da style
  SFarewell    -> farStep rp da style
  SHedge       -> hedgeStep rp da style
  SConnect     -> connectStep rp da style
  SDefine      -> defStep rp da style
  SPurpose     -> purpStep rp da style
  SDistinguish -> distStep rp da style
  SAgree       -> agreeStep rp da style
  SDisagree    -> disagreeStep rp da style
  SRelated     -> relatedStep rp da style
  SModal       -> modalStep rp da style
  SQuantify    -> quantifyStep rp da style
  SSelfCorrect  -> selfCorrectStep rp da style
  SEmphatic     -> emphaticStep rp da style
  SNarrative    -> narrativeStep rp da style
  SMetaphor     -> metaphorStep rp da style

-- | Helper: deterministic topic-based hash for variant selection
topicHash :: DialogAtoms -> Int
topicHash da = T.length (headAtomValue TTopic da)

-- | ACKNOWLEDGE (3 variants)
ackStep :: RuntimeParadigms -> DialogAtoms -> RenderStyle -> Either MorphError S
ackStep rp da _style = do
  let intent = headAtomValue TUserIntent da
      fillers = atomValues TFiller da
      useFiller = not (null fillers) && (T.length (daUserRaw da) `mod` 10 < 3)
      v = topicHash da `mod` 3
  base <- case intent of
    "define" -> case v of
      0 -> do
        subj <- pure (mkPronounNP "я" Nom)
        vp <- mkVP_ rp "слышать" 1 Sg Nothing Present
        topic <- topicNP rp da Acc
        let pp = mkPP "о" topic
        vp2 <- addPP vp pp
        s <- mkS subj vp2
        pure (mkQuestion s IFAsk)
      1 -> do
        subj <- pure (mkPronounNP "я" Nom)
        vp <- mkVP_ rp "слышать" 1 Sg Nothing Present
        topic <- topicNP rp da Gen
        vp2 <- addPP vp (mkPP "про" topic)
        s <- mkS subj vp2
        pure (mkQuestion s IFAsk)
      _ -> do
        tf <- mkNP_ rp "вопрос" Nom Sg Masc
        topic <- topicNP rp da Gen
        vp <- mkVP_ rp "касаться" 3 Sg Nothing Present
        vp2 <- addObj vp topic
        s1 <- mkS tf vp2
        subj <- pure (mkPronounNP "я" Nom)
        vpI <- mkVP_ rp "слышать" 1 Sg Nothing Present
        s2 <- mkS subj vpI
        mkCoordS CoordDash s1 s2
    _ -> case v of
      0 -> do
        subj <- pure (mkPronounNP "я" Nom)
        vp <- mkVP_ rp "слышать" 1 Sg Nothing Present
        mkS subj vp
      1 -> do
        subj <- pure (mkPronounNP "я" Nom)
        vp <- mkVP_ rp "слышать" 1 Sg Nothing Present
        adv <- mkAdv rp "хорошо"
        pure (addAdvToS (mkElliptical vp) adv)
      _ -> do
        subj <- pure (mkPronounNP "я" Nom)
        vp <- mkVP_ rp "слышать" 1 Sg Nothing Present
        mkS subj vp
  pure (if useFiller then addFiller (fromMaybe "" (listToMaybe fillers)) base else base)

-- | STANCE (2 variants)
stStep :: RuntimeParadigms -> DialogAtoms -> RenderStyle -> Either MorphError S
stStep rp da _style = do
  let stance = headAtomValue TStance da
      v = topicHash da `mod` 2
  case stance of
    "firm" -> case v of
      0 -> adjAsPredicateS rp (mkPronounNP "я" Nom) "уверенный" Masc
      _ -> do
        subj <- pure (mkPronounNP "я" Nom)
        vp <- mkVP_ rp "быть" 1 Sg Nothing Present
        predNP <- mkNP_ rp "уверенность" Nom Sg Femn
        mkS subj vp >>= mkTopicFront predNP
    _ -> case v of
      0 -> do
        subj <- pure (mkPronounNP "я" Nom)
        vp <- mkVP_ rp "думать" 1 Sg Nothing Present
        mkS subj vp
      _ -> do
        subj <- pure (mkPronounNP "я" Nom)
        vp <- mkVP_ rp "полагать" 1 Sg Nothing Present
        mkS subj vp

-- | ENGAGE (7 variants including colloquial questions)
engStep :: RuntimeParadigms -> DialogAtoms -> RenderStyle -> Either MorphError S
engStep rp da _style = do
  topic <- topicNP rp da Loc
  let v = topicHash da `mod` 7
  case v of
    0 -> do
      subj <- pure (mkPronounNP "ты" Nom)
      vp <- mkVP_ rp "думать" 2 Sg Nothing Present
      let pp = mkPP "о" topic
      mkS subj =<< addPP vp pp
    1 -> do
      subj <- pure (mkPronounNP "ты" Nom)
      vp <- mkVP_ rp "считать" 2 Sg Nothing Present
      let pp = mkPP "насчёт" topic
      mkS subj =<< addPP vp pp
    2 -> do
      h <- mkNP_ rp "ход" Nom Sg Masc
      a <- mkAP_ rp "твой" Masc Sg Nom
      h' <- addAP h a
      mkTopicFront topic (mkEllipticalNP h')
    3 -> do
      adv <- mkAdv rp "серьёзно"
      mkTopicFront topic (mkEllipticalAdv adv)
    4 -> do
      let vp = mkFrozenVP "это вообще"
      let pp = mkPP "о" (mkPronounNP "что" Loc)
      vp' <- addPP vp pp
      mkS (mkPronounNP "это" Nom) vp'
    5 -> do
      let vp = mkFrozenVP "а что насчёт"
      obj <- topicNP rp da Gen
      vp' <- addObj vp obj
      pure (mkElliptical vp')
    _ -> do
      subj <- pure (mkPronounNP "ты" Nom)
      vp <- mkVP_ rp "хотеть" 2 Sg Nothing Present
      obj <- topicNP rp da Gen
      vp' <- addObj vp obj
      mkS subj vp'

-- | REFLECT (2 variants)
refStep :: RuntimeParadigms -> DialogAtoms -> RenderStyle -> Either MorphError S
refStep rp da _style = do
  topic <- topicNP rp da Acc
  let subj = mkPronounNP "это" Nom
  case topicHash da `mod` 2 of
    0 -> do
      _ <- mkAP_ rp "непростой" Neut Sg Nom
      vp <- mkVP_ rp "быть" 3 Sg Nothing Present
      s <- mkS subj vp
      mkTopicFront topic s
    _ -> do
      subj2 <- pure (mkPronounNP "я" Nom)
      vp <- mkVP_ rp "чувствовать" 1 Sg Nothing Present
      s <- mkS subj2 vp
      mkTopicFront topic s

-- | IDENTITY
idStep :: RuntimeParadigms -> DialogAtoms -> RenderStyle -> Either MorphError S
idStep rp _da _style = do
  subj <- pure (mkPronounNP "я" Nom)
  predNP <- pure (mkNPRaw "диалоговая система" Nom Sg Femn)
  vp <- mkVP_ rp "быть" 1 Sg Nothing Present
  s <- mkS subj vp
  mkTopicFront predNP s

-- | CONSTRAINT
conStep :: RuntimeParadigms -> DialogAtoms -> RenderStyle -> Either MorphError S
conStep rp _da _style = do
  subj <- pure (mkPronounNP "я" Nom)
  vp <- mkVP_ rp "работать" 1 Sg Nothing Present
  ramki <- mkNP_ rp "рамка" Loc Pl Femn
  let pp = mkPP "в" ramki
  mkS subj =<< addPP vp pp

-- | CONTACT
con2Step :: RuntimeParadigms -> DialogAtoms -> RenderStyle -> Either MorphError S
con2Step rp _da _style = do
  subj <- pure (mkPronounNP "я" Nom)
  vp <- mkVP_ rp "быть" 1 Sg Nothing Present
  let pp = mkPP "с" (mkPronounNP "ты" Ins)
  mkS subj =<< addPP vp pp

-- | REPAIR (3 variants)
repStep :: RuntimeParadigms -> DialogAtoms -> RenderStyle -> Either MorphError S
repStep rp da _style = do
  topic <- topicNP rp da Loc
  let v = topicHash da `mod` 3
  case v of
    0 -> do
      subj <- pure (mkPronounNP "я" Nom)
      vp <- mkVP_ rp "возвращаться" 1 Sg Nothing Present
      let pp = mkPP "к" topic
      mkS subj =<< addPP vp pp
    1 -> do
      subj <- pure (mkPronounNP "я" Nom)
      vp <- mkVP_ rp "понимать" 1 Sg Nothing Present
      mkS subj vp
    _ -> do
      vp <- mkVP_ rp "вернуться" 1 Pl Nothing Future
      mkTopicFront topic (mkElliptical vp)

-- | GROUND (2 variants)
gndStep :: RuntimeParadigms -> DialogAtoms -> RenderStyle -> Either MorphError S
gndStep rp da _style = do
  topic <- topicNP rp da Nom
  let v = topicHash da `mod` 2
      quants = atomValues TQuantifier da
      useQuant = T.length (daTopicNominative da) `mod` 10 < 4
  base <- case v of
    0 -> do
      linkNP <- mkNP_ rp "связь" Nom Sg Femn
      vp <- mkVP_ rp "быть" 3 Sg Nothing Present
      ap <- mkAP_ rp "опорный" (npGender topic) Sg Nom
      topic2 <- addAP topic ap
      s <- mkS topic2 vp
      mkTopicFront linkNP s
    _ -> do
      linkNP <- mkNP_ rp "связь" Nom Sg Femn
      ap <- mkAP_ rp "опорный" Femn Sg Nom
      link2 <- addAP linkNP ap
      ap2 <- mkAP_ rp "опорный" (npGender topic) Sg Nom
      topic2 <- addAP topic ap2
      vp <- mkVP_ rp "быть" 3 Sg Nothing Present
      s1 <- mkS link2 vp
      s2 <- mkS topic2 vp
      mkCoordS CoordDash s1 s2
  pure (if useQuant && not (null quants) then addQuantifierToS (fromMaybe "" (listToMaybe quants)) base else base)

-- | CLARIFY (2 variants)
clarStep :: RuntimeParadigms -> DialogAtoms -> RenderStyle -> Either MorphError S
clarStep rp da _style = do
  topic <- topicNP rp da Acc
  let v = topicHash da `mod` 2
  case v of
    0 -> do
      subj <- pure (mkPronounNP "ты" Nom)
      vp <- mkVP_ rp "вкладывать" 2 Sg Nothing Present
      let pp = mkPP "в" topic
      s <- mkS subj =<< addPP vp pp
      pure s { sQuestion = True }
    _ -> do
      subj <- pure (mkPronounNP "ты" Nom)
      vp <- mkVP_ rp "иметь" 2 Sg Nothing Present
      vp2 <- addPP vp (mkPP "в" topic)
      s <- mkS subj vp2
      pure s { sQuestion = True }

-- | DEEPEN (3 variants)
dStep :: RuntimeParadigms -> DialogAtoms -> RenderStyle -> Either MorphError S
dStep rp da _style = do
  topic <- topicNP rp da Acc
  subj <- pure (mkPronounNP "мы" Nom)
  let v = topicHash da `mod` 3
  case v of
    0 -> do
      vp <- mkVP_ rp "копнуть" 1 Pl Nothing Future
      let pp = mkPP "в" topic
      s <- mkS subj =<< addPP vp pp
      let s1 = s { sQuestion = True }
      props <- propertyAPs rp da subj
      if length props >= 2
        then do
          vp2 <- mkVP_ rp "разобраться" 1 Pl Nothing Present
          mkCoordS CoordA s1 (mkElliptical vp2)
        else pure s1
    1 -> do
      vp <- mkVP_ rp "углубляться" 1 Pl Nothing Present
      let pp = mkPP "в" topic
      s <- mkS subj =<< addPP vp pp
      pure (s { sQuestion = True })
    _ -> do
      tf <- pure (mkNPRaw "глубже" Acc Sg Neut)
      vp <- mkVP_ rp "копнуть" 1 Pl Nothing Future
      s <- mkS subj vp
      mkTopicFront tf s

-- | NEXT (2 variants)
nStep :: RuntimeParadigms -> DialogAtoms -> RenderStyle -> Either MorphError S
nStep rp da _style = do
  topic <- topicNP rp da Ins
  let v = topicHash da `mod` 2
  case v of
    0 -> do
      frontNP <- mkNP_ rp "ход" Nom Sg Masc
      subj <- mkNP_ rp "шаг" Nom Sg Masc
      vp <- mkVP_ rp "состоять" 3 Sg Nothing Present
      let pp = mkPP "в" topic
      s <- mkS subj =<< addPP vp pp
      mkTopicFront frontNP s
    _ -> do
      frontNP <- mkNP_ rp "ход" Nom Sg Masc
      subj <- mkNP_ rp "шаг" Nom Sg Masc
      vp <- mkVP_ rp "вести" 3 Sg Nothing Present
      let pp = mkPP "к" (mkNPRaw (headAtomValue TTopic da) Dat Sg (guessGenderOr rp Masc (headAtomValue TTopic da)))
      s <- mkS subj =<< addPP vp pp
      mkTopicFront frontNP s

-- | GREET (3 variants)
greStep :: RuntimeParadigms -> DialogAtoms -> RenderStyle -> Either MorphError S
greStep rp da _style = do
  let v = T.length (daUserRaw da) `mod` 3
  case v of
    0 -> do
      subj <- pure (mkPronounNP "я" Nom)
      vp <- mkVP_ rp "радоваться" 1 Sg Nothing Present
      vstrecha <- mkNP_ rp "встреча" Loc Sg Femn
      let pp = mkPP "о" vstrecha
      mkS subj =<< addPP vp pp
    1 -> do
      vp <- mkVP_ rp "начать" 1 Pl Nothing Future
      pure (mkElliptical vp)
    _ -> do
      p <- mkNP_ rp "привет" Nom Sg Masc
      pure (mkEllipticalNP p)

-- | FAREWELL (2 variants)
farStep :: RuntimeParadigms -> DialogAtoms -> RenderStyle -> Either MorphError S
farStep rp da _style = do
  let v = T.length (daUserRaw da) `mod` 2
  case v of
    0 -> do
      subj <- pure (mkPronounNP "мы" Nom)
      vp <- mkVP_ rp "встретиться" 1 Pl Nothing Future
      mkS subj vp
    _ -> do
      vstrecha <- mkNP_ rp "встреча" Gen Sg Femn
      let pp = mkPP "до" vstrecha
      vp <- addPP (mkVPRaw "" 1 Pl Nothing Present) pp
      pure (mkElliptical vp)

-- | EMPHATIC: inserted into first sentence for emphasis
emphaticStep :: RuntimeParadigms -> DialogAtoms -> RenderStyle -> Either MorphError S
emphaticStep rp da _style = do
  let emphatics = atomValues TEmphatic da
      particle = fromMaybe "именно" (listToMaybe emphatics)
  topic <- topicNP rp da Nom
  subj <- pure topic
  vp <- mkVP_ rp "быть" 3 Sg Nothing Present
  s <- mkS subj vp
  let advUnsafe = mkAdvRaw particle
  pure (addAdvToS s advUnsafe)

-- | NARRATIVE: "представь себе..." / "однажды..."
narrativeStep :: RuntimeParadigms -> DialogAtoms -> RenderStyle -> Either MorphError S
narrativeStep rp da _style = do
  let v = topicHash da `mod` 3
  case v of
    0 -> do
      vp <- mkVP_ rp "представить" 2 Sg Nothing Present
      pure (mkElliptical vp)
    1 -> do
      topicFront <- topicNP rp da Nom
      subj <- pure (mkPronounNP "я" Nom)
      vp <- mkVP_ rp "рассказывать" 1 Sg Nothing Present
      s <- mkS subj vp
      mkTopicFront topicFront s
    _ -> do
      frontAdv <- mkAdv rp "однажды"
      subj <- pure (mkPronounNP "это" Nom)
      vp <- mkVP_ rp "быть" 3 Sg Nothing Present
      s <- mkS subj vp
      pure (addAdvToS s frontAdv)

-- | METAPHOR: "если вдуматься, X — это как Y..."
metaphorStep :: RuntimeParadigms -> DialogAtoms -> RenderStyle -> Either MorphError S
metaphorStep rp da _style = do
  let topic = headAtomValue TTopic da
  case lookupMetaphor rp topic Nothing of
    Just (_, source) -> do
      let subj = mkNPRaw topic Nom Sg (guessGenderOr rp Masc topic)
      let advUnsafe = mkAdvRaw "вдуматься"
      vp <- mkVP_ rp "быть" 3 Sg Nothing Present
      let pp = mkPP "как" (mkNPRaw source Nom Sg Neut)
      vp' <- addPP vp pp
      s <- mkS subj vp'
      pure (addAdvToS s advUnsafe)
    Nothing -> do
      subj <- pure (mkNPRaw topic Nom Sg Masc)
      vp <- mkVP_ rp "быть" 3 Sg Nothing Present
      mkS subj vp

-- | SELFCORRECT: "то есть... вернее..." self-correction step
selfCorrectStep :: RuntimeParadigms -> DialogAtoms -> RenderStyle -> Either MorphError S
selfCorrectStep rp da _style = do
  let v = topicHash da `mod` 2
  case v of
    0 -> do
      subj <- pure (mkPronounNP "это" Nom)
      vp <- mkVP_ rp "быть" 3 Sg Nothing Present
      mkS subj vp
    _ -> do
      vp <- mkVP_ rp "уточнить" 1 Pl Nothing Present
      pure (mkElliptical vp)

-- | HEDGE: softening prefix before assertion
hedgeStep :: RuntimeParadigms -> DialogAtoms -> RenderStyle -> Either MorphError S
hedgeStep rp _da _style = do
  subj <- pure (mkPronounNP "это" Nom)
  vp <- mkVP_ rp "быть" 3 Sg Nothing Present
  -- Build a sentence that carries the hedge as adverb-like prefix
  -- Simplified: "это, в некотором смысле, так"
  pure SimpleS { sSubject = subj, sPredicate = vp, sTopicFront = Nothing, sQuestion = False, sModal = Nothing, sFill = Nothing, sQuant = Nothing }

-- | CONNECT: discourse linker between steps
connectStep :: RuntimeParadigms -> DialogAtoms -> RenderStyle -> Either MorphError S
connectStep rp _da _style = do
  subj <- pure (mkPronounNP "мы" Nom)
  vp <- mkVP_ rp "делать" 1 Pl Nothing Present
  pure SimpleS { sSubject = subj, sPredicate = vp, sTopicFront = Nothing, sQuestion = False, sModal = Nothing, sFill = Nothing, sQuant = Nothing }

-- | DEFINE

defStep :: RuntimeParadigms -> DialogAtoms -> RenderStyle -> Either MorphError S
defStep rp da _style = do
  topic <- topicNP rp da Nom
  predNP <- mkNP_ rp "смысл" Nom Sg Masc
  vp <- mkVP_ rp "быть" 3 Sg Nothing Present
  s <- mkS predNP vp
  mkTopicFront topic s

-- | PURPOSE
purpStep :: RuntimeParadigms -> DialogAtoms -> RenderStyle -> Either MorphError S
purpStep rp da _style = do
  topic <- topicNP rp da Nom
  predNP <- mkNP_ rp "функция" Nom Sg Femn
  vp <- mkVP_ rp "быть" 3 Sg Nothing Present
  s <- mkS predNP vp
  mkTopicFront topic s

-- | DISTINGUISH
distStep :: RuntimeParadigms -> DialogAtoms -> RenderStyle -> Either MorphError S
distStep rp da _style = do
  topic <- topicNP rp da Nom
  predNP <- mkNP_ rp "отличие" Nom Sg Neut
  vp <- mkVP_ rp "быть" 3 Sg Nothing Present
  s <- mkS predNP vp
  mkTopicFront topic s

-- | AGREE
agreeStep :: RuntimeParadigms -> DialogAtoms -> RenderStyle -> Either MorphError S
agreeStep rp da _style = do
  topic <- topicNP rp da Nom
  subj <- pure (mkPronounNP "я" Nom)
  vp <- mkVP_ rp "соглашаться" 1 Sg Nothing Present
  let pp = mkPP "с" topic
  s <- mkS subj =<< addPP vp pp
  adv <- mkAdv rp "верно"
  pure (addAdvToS s adv)

-- | DISAGREE
disagreeStep :: RuntimeParadigms -> DialogAtoms -> RenderStyle -> Either MorphError S
disagreeStep rp da _style = do
  topic <- topicNP rp da Gen
  subj <- pure (mkPronounNP "я" Nom)
  vp <- mkVP_ rp "сомневаться" 1 Sg Nothing Present
  let pp = mkPP "в" topic
  s <- mkS subj =<< addPP vp pp
  adv <- mkAdv rp "осторожно"
  pure (addAdvToS s adv)

-- | RELATED
relatedStep :: RuntimeParadigms -> DialogAtoms -> RenderStyle -> Either MorphError S
relatedStep rp da _style = do
  let rels = atomValues TRelatedTopic da
  related <- case rels of
    (r:_) -> Right (mkNPRaw r Acc Sg Neut)
    []    -> mkNP_ rp "тема" Acc Sg Femn
  subj <- pure (mkPronounNP "это" Nom)
  vp <- mkVP_ rp "связать" 3 Sg (Just Neut) Past
  let pp = mkPP "с" related
  mkS subj =<< addPP vp pp

-- | MODAL particle step (injected in assembleTurn, not via plan)
modalStep :: RuntimeParadigms -> DialogAtoms -> RenderStyle -> Either MorphError S
modalStep rp _da _style = do
  subj <- pure (mkPronounNP "это" Nom)
  vp <- mkVP_ rp "быть" 3 Sg Nothing Present
  mkS subj vp

-- | QUANTIFY number step
quantifyStep :: RuntimeParadigms -> DialogAtoms -> RenderStyle -> Either MorphError S
quantifyStep rp da _style = do
  let numbers = atomValues TNumber da
      num = fromMaybe "три" (listToMaybe numbers)
  topic <- topicNP rp da Nom
  numNP <- pure (mkNPRaw num Nom Sg Masc)
  vp <- mkVP_ rp "быть" 3 Sg Nothing Present
  s <- mkS numNP vp
  mkTopicFront topic s

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

topicNP :: RuntimeParadigms -> DialogAtoms -> NounCase -> Either MorphError NP
topicNP rp da case_ =
  let raw = headAtomValue TTopic da
      nom = if T.null raw then "тема" else raw
  in case mkNP rp nom case_ Sg of
       Right np -> Right np
       Left _ ->
         -- Graceful degradation: placeholder NP preserves surface text
         let g = guessGenderOr rp Masc nom
         in Right (mkNPRaw nom case_ Sg g)

adjAsPredicateS :: RuntimeParadigms -> NP -> Text -> Gender -> Either MorphError S
adjAsPredicateS rp subj lemma gender = do
  ap <- mkAP_ rp lemma gender (npNumber subj) (npCase subj)
  subj2 <- addAP subj ap
  vp <- mkVP_ rp "быть" (case npNumber subj of Sg -> 3; Pl -> 3) (npNumber subj) Nothing Present
  mkS subj2 vp

-- | Build APs from TProperty atoms (up to 3)
propertyAPs :: RuntimeParadigms -> DialogAtoms -> NP -> Either MorphError [AP]
propertyAPs rp da _subj =
  let props = atomValues TProperty da
      tryMakeAP p = mkAP_ rp p Masc Sg Nom
  in Right (mapMaybe (eitherToMaybe . tryMakeAP) (take 3 props))
  where
    eitherToMaybe (Right x) = Just x
    eitherToMaybe (Left _)   = Nothing
