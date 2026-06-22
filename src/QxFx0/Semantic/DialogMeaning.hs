{-# LANGUAGE OverloadedStrings #-}
{-|
Dialog meaning extraction: convert turn context into DialogAtoms.

Takes the raw turn pipeline data (InputPropositionFrame, ResponseMeaningPlan,
SystemState) and produces structured DialogAtoms ready for assembly.
-}
module QxFx0.Semantic.DialogMeaning
  ( buildDialogAtoms
  , narrativeSlot
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as M
import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Types.Consciousness (ConsciousnessNarrative(..))
import QxFx0.Runtime.GF.Morphology (genitiveForm, prepositionalForm, accusativeForm)
import QxFx0.Semantic.DialogAtom
import QxFx0.Semantic.Input.Parse (ParsedInput(..), ParsedToken(..))
import QxFx0.Types hiding (AtomTag)
import QxFx0.Types.SemanticConfig (SemanticConfig(..))
import QxFx0.Types.TruthContract (capByTruthContract)

buildDialogAtoms :: InputPropositionFrame -> ResponseMeaningPlan -> SystemState
                  -> MorphologyData -> ParsedInput -> Maybe ConsciousnessNarrative
                  -> DialogAtoms
buildDialogAtoms frame rmp ss morph parsed mnarr =
  let raw = ipfRawText frame
      topic = nonEmptyOr (rmpTopic rmp) (nonEmptyOr (ipfFocusEntity frame) "тема")
      turn = ssTurnCount ss + 1
      cappedEpistemic = capByTruthContract (rmpTruthContractStatus rmp) (rmpEpistemic rmp)
      slots = [ userIntentSlot frame
              , topicSlot topic morph
              , stanceSlot (rmpStance rmp)
              , emotionSlot frame
              , knowledgeSlot cappedEpistemic
              , phaseSlot ss
              , turnGoalSlot (rmpFamily rmp)
                , identitySlot
                , constraintSlot (rmpTruthContractStatus rmp) frame
              , greetingSlot frame
              , farewellSlot frame
              , hedgeSlot cappedEpistemic
              , connectorSlot
              , softenerSlot frame
               , parseSubjectSlot parsed
               , parseObjectSlot parsed
                , parseNegationSlot (ssSemanticConfig ss) parsed
                , parseModifierSlot (ssSemanticConfig ss) parsed
                , parseVerbSlot parsed
                , parseAgreementSlot (ssSemanticConfig ss) parsed
                , modalSlot
                , fillerSlot
                 , emphaticSlot
                 , numberSlot
                 , quantifierSlot
                 , dreamAxiomSlot ss
                 , narrativeSlot mnarr
                ]
  in DialogAtoms (mergeSlots (concat slots)) raw turn

mergeSlots :: [(AtomTag, [AtomSlot])] -> Map AtomTag [AtomSlot]
mergeSlots = foldr (\(tag, vals) acc ->
  M.insertWith (++) tag vals acc) M.empty

-- | Tag user intent: one of define, clarify, ground, reflect, complain, greet, leave...
userIntentSlot :: InputPropositionFrame -> [(AtomTag, [AtomSlot])]
userIntentSlot frame = case ipfCanonicalFamily frame of
  CMGround    -> [(TUserIntent, [plainSlot TUserIntent "ground"])]
  CMDefine    -> [(TUserIntent, [plainSlot TUserIntent "define"])]
  CMClarify   -> [(TUserIntent, [plainSlot TUserIntent "clarify"])]
  CMReflect   -> [(TUserIntent, [plainSlot TUserIntent "reflect"])]
  CMContact   -> [(TUserIntent, [plainSlot TUserIntent "connect"])]
  CMPurpose   -> [(TUserIntent, [plainSlot TUserIntent "ask_purpose"])]
  CMHypothesis ->[(TUserIntent, [plainSlot TUserIntent "hypothesize"])]
  CMDistinguish->[(TUserIntent, [plainSlot TUserIntent "distinguish"])]
  CMRepair    -> [(TUserIntent, [plainSlot TUserIntent "complain"])]
  CMDeepen    -> [(TUserIntent, [plainSlot TUserIntent "deepen"])]
  CMConfront  -> [(TUserIntent, [plainSlot TUserIntent "confront"])]
  CMNextStep  -> [(TUserIntent, [plainSlot TUserIntent "next"])]
  CMAnchor    -> [(TUserIntent, [plainSlot TUserIntent "anchor"])]
  CMDescribe  -> [(TUserIntent, [plainSlot TUserIntent "describe"])]

-- | Topic — the conversation subject
topicSlot :: Text -> MorphologyData -> [(AtomTag, [AtomSlot])]
topicSlot raw morph =
  let t = T.strip raw
      nom = t
      gen = genitiveForm morph t
      prep = prepositionalForm morph t
      acc = accusativeForm morph t
      ins = t
      pl = t
  in if T.null t then [] else
       [(TTopic, [nounSlot TTopic nom gen prep acc ins pl])]

-- | System stance
stanceSlot :: StanceMarker -> [(AtomTag, [AtomSlot])]
stanceSlot Firm    = [(TStance, [plainSlot TStance "firm"])]
stanceSlot Honest  = [(TStance, [plainSlot TStance "honest"])]
stanceSlot Tentative = [(TStance, [plainSlot TStance "tentative"])]
stanceSlot Explore  = [(TStance, [plainSlot TStance "explore"])]
stanceSlot Commit   = [(TStance, [plainSlot TStance "commit"])]
stanceSlot Observe  = [(TStance, [plainSlot TStance "observe"])]
stanceSlot HoldBack = [(TStance, [plainSlot TStance "hold_back"])]
stanceSlot Curated  = [(TStance, [plainSlot TStance "curated"])]

-- | Emotional tone
emotionSlot :: InputPropositionFrame -> [(AtomTag, [AtomSlot])]
emotionSlot frame = case ipfEmotionalTone frame of
  ToneDistress       -> [(TEmotion, [plainSlot TEmotion "distress"])]
  ToneHopeful        -> [(TEmotion, [plainSlot TEmotion "hopeful"])]
  ToneCurious        -> [(TEmotion, [plainSlot TEmotion "curious"])]
  ToneConfrontational -> [(TEmotion, [plainSlot TEmotion "confront"])]
  ToneNeutral        -> [(TEmotion, [plainSlot TEmotion "neutral"])]

-- | Epistemic status
knowledgeSlot :: EpistemicStatus -> [(AtomTag, [AtomSlot])]
knowledgeSlot (Known _)      = [(TKnowledge, [plainSlot TKnowledge "known"])]
knowledgeSlot (Probable _)   = [(TKnowledge, [plainSlot TKnowledge "probable"])]
knowledgeSlot (Uncertain _)  = [(TKnowledge, [plainSlot TKnowledge "uncertain"])]
knowledgeSlot (Unknown _)    = [(TKnowledge, [plainSlot TKnowledge "unknown"])]
knowledgeSlot (Speculative _)= [(TKnowledge, [plainSlot TKnowledge "speculative"])]

-- | Dialog phase
phaseSlot :: SystemState -> [(AtomTag, [AtomSlot])]
phaseSlot ss
  | turn <= 1 = [(TPhase, [plainSlot TPhase "opening"])]
  | consecReflect >= 3 = [(TPhase, [plainSlot TPhase "stuck"])]
  | consecReflect >= 1 = [(TPhase, [plainSlot TPhase "reflect"])]
  | otherwise = [(TPhase, [plainSlot TPhase "dialogue"])]
  where
    turn = ssTurnCount ss
    consecReflect = ssConsecutiveReflect ss

-- | Turn goal
turnGoalSlot :: CanonicalMoveFamily -> [(AtomTag, [AtomSlot])]
turnGoalSlot family = case family of
  CMGround   -> [(TTurnGoal, [plainSlot TTurnGoal "anchor"])]
  CMDefine   -> [(TTurnGoal, [plainSlot TTurnGoal "define"])]
  CMClarify  -> [(TTurnGoal, [plainSlot TTurnGoal "clarify"])]
  CMReflect  -> [(TTurnGoal, [plainSlot TTurnGoal "reflect"])]
  CMContact  -> [(TTurnGoal, [plainSlot TTurnGoal "connect"])]
  CMRepair   -> [(TTurnGoal, [plainSlot TTurnGoal "repair"])]
  CMDeepen   -> [(TTurnGoal, [plainSlot TTurnGoal "deepen"])]
  CMAnchor   -> [(TTurnGoal, [plainSlot TTurnGoal "stabilize"])]
  CMConfront -> [(TTurnGoal, [plainSlot TTurnGoal "challenge"])]
  CMNextStep -> [(TTurnGoal, [plainSlot TTurnGoal "proceed"])]
  _          -> [(TTurnGoal, [plainSlot TTurnGoal "respond"])]

-- | Identity: who the system is
identitySlot :: [(AtomTag, [AtomSlot])]
identitySlot =
  [ (TIdentity,  [plainSlot TIdentity "диалоговая система"])
  , (TCapability,[plainSlot TCapability "могу анализировать, определять, различать и собирать ответы"])]

-- | Constraint: what limits apply
constraintSlot :: TruthContractStatus -> InputPropositionFrame -> [(AtomTag, [AtomSlot])]
constraintSlot truthStatus frame =
  case (truthStatus, ipfSemanticTarget frame) of
    (CanonicalSurfacePreserved, "user") -> [(TConstraint, [plainSlot TConstraint "я знаю только то, что проявлено в этой сессии"])]
    (_, "user") -> [(TConstraint, [plainSlot TConstraint "я удерживаю только локально проявленный контекст этой сессии"])]
    (CanonicalSurfacePreserved, _) -> [(TConstraint, [plainSlot TConstraint "я работаю в рамках текущего диалога"])]
    _ -> [(TConstraint, [plainSlot TConstraint "я держусь локальной рамки текущего диалога и не усиливаю её сверх фактической опоры"])]

-- | Hedge: triggered by uncertain / speculative epistemic status
hedgeSlot :: EpistemicStatus -> [(AtomTag, [AtomSlot])]
hedgeSlot (Uncertain _)  = [(THedge, [plainSlot THedge "в некотором смысле"])]
hedgeSlot (Speculative _) = [(THedge, [plainSlot THedge "как бы"])]
hedgeSlot (Unknown _)    = [(THedge, [plainSlot THedge "пожалуй"])]
hedgeSlot (Probable _)   = [(THedge, [plainSlot THedge "скорее всего"])]
hedgeSlot (Known _)      = [(THedge, [plainSlot THedge "насколько я понимаю"])]

-- | Modal particles: always available
modalSlot :: [(AtomTag, [AtomSlot])]
modalSlot =
  [ (TModal, [plainSlot TModal "ведь"])
  , (TModal, [plainSlot TModal "же"])
  , (TModal, [plainSlot TModal "разве"])
  , (TModal, [plainSlot TModal "всё-таки"])
  , (TModal, [plainSlot TModal "вообще-то"])
  ]

-- | Conversational fillers: always available
fillerSlot :: [(AtomTag, [AtomSlot])]
fillerSlot =
  [ (TFiller, [plainSlot TFiller "ну"])
  , (TFiller, [plainSlot TFiller "так"])
  , (TFiller, [plainSlot TFiller "значит"])
  , (TFiller, [plainSlot TFiller "слушай"])
  , (TFiller, [plainSlot TFiller "смотри"])
  , (TFiller, [plainSlot TFiller "понимаешь"])
  ]

-- | Emphatic particles: always available
emphaticSlot :: [(AtomTag, [AtomSlot])]
emphaticSlot =
  [ (TEmphatic, [plainSlot TEmphatic "именно"])
  , (TEmphatic, [plainSlot TEmphatic "даже"])
  , (TEmphatic, [plainSlot TEmphatic "просто"])
  , (TEmphatic, [plainSlot TEmphatic "всего лишь"])
  , (TEmphatic, [plainSlot TEmphatic "хотя бы"])
  , (TEmphatic, [plainSlot TEmphatic "уж"])
  , (TEmphatic, [plainSlot TEmphatic "хоть"])
  ]

-- | Numbers: always available
numberSlot :: [(AtomTag, [AtomSlot])]
numberSlot =
  [ (TNumber, [plainSlot TNumber "один"])
  , (TNumber, [plainSlot TNumber "два"])
  , (TNumber, [plainSlot TNumber "три"])
  , (TNumber, [plainSlot TNumber "несколько"])
  , (TNumber, [plainSlot TNumber "первый"])
  , (TNumber, [plainSlot TNumber "оба"])
  ]

-- | Quantifiers: always available
quantifierSlot :: [(AtomTag, [AtomSlot])]
quantifierSlot =
  [ (TQuantifier, [plainSlot TQuantifier "все"])
  , (TQuantifier, [plainSlot TQuantifier "каждый"])
  , (TQuantifier, [plainSlot TQuantifier "любой"])
  , (TQuantifier, [plainSlot TQuantifier "некоторые"])
  , (TQuantifier, [plainSlot TQuantifier "многие"])
  , (TQuantifier, [plainSlot TQuantifier "ни один"])
  , (TQuantifier, [plainSlot TQuantifier "большинство"])
  ]

-- | Connector: discourse linkers
connectorSlot :: [(AtomTag, [AtomSlot])]
connectorSlot =
  [ (TConnector, [plainSlot TConnector "кстати"])
  , (TConnector, [plainSlot TConnector "впрочем"])
  , (TConnector, [plainSlot TConnector "более того"])
  , (TConnector, [plainSlot TConnector "с другой стороны"])
  , (TConnector, [plainSlot TConnector "при этом"])
  , (TConnector, [plainSlot TConnector "если вернуться к теме"])
  , (TConnector, [plainSlot TConnector "как было сказано ранее"])
  , (TConnector, [plainSlot TConnector "переходя к следующему"])
  , (TConnector, [plainSlot TConnector "забегая вперёд"])
  , (TConnector, [plainSlot TConnector "подводя итог"])
  , (TConnector, [plainSlot TConnector "резюмируя сказанное"])
  , (TConnector, [plainSlot TConnector "обобщая вышесказанное"])
  , (TConnector, [plainSlot TConnector "если подытожить"])
  , (TConnector, [plainSlot TConnector "возвращаясь к теме"])
  ]

-- | Softener: tone-softening phrases
softenerSlot :: InputPropositionFrame -> [(AtomTag, [AtomSlot])]
softenerSlot frame
  | isConfrontationalLike frame = [(TSoftener, [plainSlot TSoftener "давай попробуем"])]
  | otherwise =
      [ (TSoftener, [plainSlot TSoftener "если хочешь"])
      , (TSoftener, [plainSlot TSoftener "может быть"])
      , (TSoftener, [plainSlot TSoftener "в какой-то мере"])
      ]

isConfrontationalLike :: InputPropositionFrame -> Bool
isConfrontationalLike frame =
  any (`T.isInfixOf` T.toLower (ipfRawText frame))
    ["почему","зачем","ты не","ты никогда","ты всегда"]

-- | Greeting
greetingSlot :: InputPropositionFrame -> [(AtomTag, [AtomSlot])]
greetingSlot frame
  | isGreetingLike frame = [(TGreeting, [plainSlot TGreeting "initial"])]
  | otherwise = []

-- | Farewell
farewellSlot :: InputPropositionFrame -> [(AtomTag, [AtomSlot])]
farewellSlot frame
  | isFarewellLike frame = [(TFarewell, [plainSlot TFarewell "goodbye"])]
  | otherwise = []

isGreetingLike :: InputPropositionFrame -> Bool
isGreetingLike frame =
  any (`T.isInfixOf` T.toLower (ipfRawText frame))
    ["привет","здравствуй","здравствуйте","салют","хай","hello","hi"]

isFarewellLike :: InputPropositionFrame -> Bool
isFarewellLike frame =
  any (`T.isInfixOf` T.toLower (ipfRawText frame))
    ["пока","прощай","до свидания","до встречи","увидимся"]

nonEmptyOr :: Text -> Text -> Text
nonEmptyOr preferred fallback
  | T.null (T.strip preferred) = fallback
  | otherwise = preferred

--------------------------------------------------------------------------------
-- ParsedInput extraction slots
--------------------------------------------------------------------------------

parseSubjectSlot :: ParsedInput -> [(AtomTag, [AtomSlot])]
parseSubjectSlot parsed =
  case filter (\t -> ptDep t `elem` ["nsubj", "nsubj:pass"]) (piTokens parsed) of
    (t:_) -> [(TTopic, [plainSlot TTopic (ptLemma t)])]
    []    -> []

parseObjectSlot :: ParsedInput -> [(AtomTag, [AtomSlot])]
parseObjectSlot parsed =
  case filter (\t -> ptDep t `elem` ["obj", "iobj", "obl"]) (piTokens parsed) of
    (t:_) -> [(TProperty, [plainSlot TProperty (ptLemma t)])]
    []    -> []

parseNegationSlot :: SemanticConfig -> ParsedInput -> [(AtomTag, [AtomSlot])]
parseNegationSlot cfg parsed =
  case filter (\t -> ptDep t == "advmod" && ptLemma t `elem` scDialogNegationKeywords cfg) (piTokens parsed) of
    (_:_) -> [(TEmotion, [plainSlot TEmotion "negated"])]
    []    -> []

parseModifierSlot :: SemanticConfig -> ParsedInput -> [(AtomTag, [AtomSlot])]
parseModifierSlot cfg parsed =
  let known = scDialogModifierKeywords cfg
      mods = filter (\t ->
        (ptDep t `elem` ["advmod","amod"]) &&
        ptLemma t `elem` known) (piTokens parsed)
  in if null mods then [] else
       [(TModifier, map (\t -> plainSlot TModifier (ptLemma t)) mods)]

parseVerbSlot :: ParsedInput -> [(AtomTag, [AtomSlot])]
parseVerbSlot parsed =
  case filter (\t -> ptDep t == "ROOT") (piTokens parsed) of
    (t:_) -> [(TUserIntent, [plainSlot TUserIntent (ptLemma t)])]
    []    -> []

parseAgreementSlot :: SemanticConfig -> ParsedInput -> [(AtomTag, [AtomSlot])]
parseAgreementSlot cfg parsed =
  let words_ = map ptLemma (piTokens parsed)
  in if any (`elem` scDialogAgreementKeywords cfg) words_
     then [(TAgreement, [plainSlot TAgreement "agree"])]
     else if any (`elem` scDialogDisagreementKeywords cfg) words_
           then [(TDisagreement, [plainSlot TDisagreement "disagree"])]
           else []

dreamAxiomSlot :: SystemState -> [(AtomTag, [AtomSlot])]
dreamAxiomSlot ss =
  let axiom = ssDreamAxiom ss
  in if T.null axiom
     then []
     else [(TConnector, [plainSlot TConnector ("кстати, связь: " <> axiom)])]

narrativeSlot :: Maybe ConsciousnessNarrative -> [(AtomTag, [AtomSlot])]
narrativeSlot Nothing = []
narrativeSlot (Just narr) =
  let conflictAtom = if T.null (cnConflict narr) then [] else [(TEmphatic, [plainSlot TEmphatic (cnConflict narr)])]
      limitAtom    = if T.null (cnLimitation narr) then [] else [(THedge, [plainSlot THedge (cnLimitation narr)])]
      -- TModifier / TConnector are not consumed by DialogAssembly;
      -- emitting them here would be dishonest (the assembler silently drops them).
  in conflictAtom ++ limitAtom
