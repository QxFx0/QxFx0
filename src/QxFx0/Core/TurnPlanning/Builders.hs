{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-| Builders for response meaning/control plans from routing context. -}
module QxFx0.Core.TurnPlanning.Builders
  ( buildRMP
  , buildRCP
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Lexicon.GfMap (topicToGfLexemeId)
import QxFx0.Core.TurnPlanning.Modulation
  ( feralDegradation
  , threeStageModulation
  )
import QxFx0.Core.Semantic.Proposition (PropositionType(..), propositionTypeFromText)
import QxFx0.Types

buildRMP :: CanonicalMoveFamily -> InputPropositionFrame -> Text -> EgoState -> AtomTrace -> Bool -> ResponseMeaningPlan
buildRMP family frame topic ego trace nixAvailable =
  let baseStance = familyToStance family
      baseEpistemic = familyToEpistemic family
      (feralStance, feralEpistemic) = feralDegradation nixAvailable baseStance baseEpistemic
      (finalStance, finalEpistemic) = threeStageModulation ego trace feralStance feralEpistemic
      plannedTopic = topicFromFrame frame topic
      primaryClaim = primaryClaimFromFrame frame plannedTopic
      baseAst = claimAstFromFrame frame plannedTopic ego
      primaryClaimAst = fmap (applyStanceToAst feralStance) baseAst
      contrastAxis = contrastAxisFromFrame frame
   in ResponseMeaningPlan
        { rmpFamily = family
        , rmpForce = forceForFamily family
        , rmpSpeechAct = familyToSpeechAct family
        , rmpRelation = familyToRelation family
        , rmpStrategy = familyToStrategy family
        , rmpStance = finalStance
        , rmpEpistemic = finalEpistemic
        , rmpTopic = plannedTopic
        , rmpPrimaryClaim = primaryClaim
        , rmpPrimaryClaimAst = primaryClaimAst
        , rmpContrastAxis = contrastAxis
        , rmpImplicationDirection = "forward"
        , rmpProvenance = BuiltClaim
        , rmpCommitmentStrength = epistemicConfidence finalEpistemic
        , rmpDepthMode = familyDefaultDepthMode family
        }

topicFromFrame :: InputPropositionFrame -> Text -> Text
topicFromFrame frame fallback =
  case propositionTypeFromText (ipfPropositionType frame) of
    Just SelfKnowledgeQ
      | ipfSemanticTarget frame == "user" -> "твой контекст"
      | ipfSemanticTarget frame == "user_help" -> nonEmptyOr (ipfSemanticSubject frame) "помощь"
      | ipfSemanticTarget frame == "self_capability" -> nonEmptyOr (ipfSemanticSubject frame) "способность"
      | otherwise -> "моя роль"
    Just DialogueInvitationQ ->
      nonEmptyOr (ipfSemanticSubject frame) fallback
    Just ConceptKnowledgeQ ->
      nonEmptyOr (ipfSemanticSubject frame) fallback
    Just WorldCauseQ ->
      nonEmptyOr (ipfSemanticSubject frame) fallback
    Just PurposeQ ->
      nonEmptyOr (ipfSemanticSubject frame) fallback
    Just LocationFormationQ ->
      nonEmptyOr (ipfSemanticSubject frame) fallback
    Just SelfStateQ ->
      "мой текущий ход"
    Just ComparisonPlausibilityQ ->
      case ipfSemanticCandidates frame of
        [] -> nonEmptyOr (ipfFocusEntity frame) fallback
        xs -> T.intercalate " / " xs
    Just MisunderstandingReport ->
      "взаимопонимание"
    Just GenerativePrompt ->
      "мысль"
    Just ContemplativeTopic ->
      nonEmptyOr (ipfSemanticSubject frame) fallback
    Just OperationalStatusQ ->
      "работа"
    Just OperationalCauseQ ->
      "разбор смысла"
    Just SystemLogicQ ->
      "логика"
    _ ->
      nonEmptyOr (ipfFocusEntity frame) fallback

primaryClaimFromFrame :: InputPropositionFrame -> Text -> Text
primaryClaimFromFrame frame fallback =
  case propositionTypeFromText (ipfPropositionType frame) of
    Just SelfKnowledgeQ
      | ipfSemanticTarget frame == "user" ->
          "Я знаю о тебе только то, что проявлено в текущей сессии."
      | ipfSemanticTarget frame == "user_help" ->
          "Я могу помочь, если удерживается локальная рамка задачи и не теряется предмет запроса."
      | ipfSemanticTarget frame == "self_capability" ->
          "Я могу работать с таким действием в пределах текущей сессии, если запрос остаётся локально определимым."
      | otherwise ->
          "Я знаю о себе свою роль, состояние и ход текущего диалога."
    Just DialogueInvitationQ ->
      "Можно войти в тему через устойчивую рамку и затем углубить разговор."
    Just ConceptKnowledgeQ ->
      "Я могу дать локальную понятийную рамку, а не внешнее наблюдение."
    Just WorldCauseQ ->
      "Причинное объяснение требует рамки и не равно эмпирическому знанию."
    Just PurposeQ ->
      "Функцию и назначение лучше объяснять через устойчивую роль объекта в действии, а не через одно случайное употребление."
    Just LocationFormationQ ->
      "Мысль лучше описывать через структуру связей, а не через одну точку."
    Just SelfStateQ ->
      "Мой текущий ход строится из разбора твоей реплики, выбора семейства ответа и ограничений сессии."
    Just ComparisonPlausibilityQ ->
      "Сравнение устойчиво только внутри явно заданной рамки."
    Just MisunderstandingReport ->
      "Нужно уточнить место сбоя взаимопонимания."
    Just GenerativePrompt ->
      "Одна мысль может задать рамку всему дальнейшему разговору."
    Just ContemplativeTopic ->
      "Одно слово может открывать не определение, а целое поле смыслов."
    Just OperationalStatusQ ->
      "Сбой сейчас не в запуске, а в разборе вопроса."
    Just OperationalCauseQ ->
      "Проблема сейчас в маршрутизации и схлопывании смысла."
    Just SystemLogicQ ->
      "Моя логика строится вокруг локального разбора и маршрутизации."
    _ ->
      fallback

claimAstFromFrame :: InputPropositionFrame -> Text -> EgoState -> Maybe ClaimAst
claimAstFromFrame frame fallback ego =
  let topicNP = mkTopicNP (nonEmptyOr (ipfSemanticSubject frame) fallback)
      familyFallback = fallbackAstForFamily (ipfCanonicalFamily frame) topicNP
  in case propositionTypeFromText (ipfPropositionType frame) of
      Just DialogueInvitationQ ->
        let gfMod = if egoTension ego > 0.5 then ModStrictly else ModFirst
            gfNum = extractNumber frame
            gfAction = if egoAgency ego > 0.6
                       then ActDefine "granitsa_N"
                       else ActMaintain gfNum "ramka_N"
        in Just (MoveInvite topicNP gfMod gfAction)
      Just ConceptKnowledgeQ ->
        Just (MoveDefine topicNP RelIdentity (MkNP "ponyatie_N"))
      Just WorldCauseQ ->
        Just (MoveCause topicNP MechParse)
      Just PurposeQ ->
        Just (MovePurpose topicNP)
      Just SelfStateQ ->
        Just MoveSelfState
      Just ComparisonPlausibilityQ ->
        Just (buildComparisonAst frame topicNP)
      Just OperationalStatusQ ->
        Just MoveOperationalStatus
      Just OperationalCauseQ ->
        Just MoveOperationalCause
      Just SystemLogicQ ->
        Just MoveSystemLogic
      Just MisunderstandingReport ->
        Just MoveMisunderstanding
      Just GenerativePrompt ->
        Just MoveGenerativeThought
      Just ContemplativeTopic ->
        Just (MoveContemplative topicNP)
      Just ContactSignal ->
        Just (MoveContact topicNP)
      Just AffectiveQ ->
        Just (MoveContact topicNP)
      Just ReflectiveQ ->
        Just (MoveReflect topicNP)
      Just DefinitionalQ ->
        Just (MoveDefine topicNP RelIdentity (MkNP "ponyatie_N"))
      Just DistinctionQ ->
        Just (buildComparisonAst frame topicNP)
      Just GroundQ ->
        Just (MoveGround topicNP)
      Just SelfDescQ ->
        Just (MoveDescribe topicNP)
      Just HypotheticalQ ->
        Just (MoveHypothesis topicNP)
      Just RepairSignal ->
        Just MoveMisunderstanding
      Just AnchorSignal ->
        Just (MoveAnchor topicNP)
      Just ClarifyQ ->
        Just (MoveClarify topicNP)
      Just DeepenQ ->
        Just (MoveDeepen topicNP)
      Just ConfrontQ ->
        Just (MoveConfront topicNP)
      Just NextStepQ ->
        Just (MoveNextStepLocal topicNP)
      Just PlainAssert ->
        Just (MoveGround topicNP)
      Just EpistemicQ ->
        Just (MoveClarify topicNP)
      Just RequestQ ->
        Just (MoveClarify topicNP)
      Just EvaluationQ ->
        Just (buildComparisonAst frame topicNP)
      Just NarrativeQ ->
        Just (MoveDescribe topicNP)
      Just SelfKnowledgeQ ->
        Just (MoveDescribe topicNP)
      Just LocationFormationQ ->
        Just (MoveGround topicNP)
      Nothing ->
        Just familyFallback

mkTopicNP :: Text -> GfNP
mkTopicNP = MkNP . topicToGfLexemeId

buildComparisonAst :: InputPropositionFrame -> GfNP -> ClaimAst
buildComparisonAst frame fallbackTopic =
  case ipfSemanticCandidates frame of
    left : right : _ ->
      MoveDistinguish (mkTopicNP left) (mkTopicNP right)
    _ ->
      MoveCompare fallbackTopic (MkNP "smysl_N")

fallbackAstForFamily :: CanonicalMoveFamily -> GfNP -> ClaimAst
fallbackAstForFamily family topicNP =
  case family of
    CMGround -> MoveGround topicNP
    CMDefine -> MoveDefine topicNP RelIdentity (MkNP "ponyatie_N")
    CMReflect -> MoveReflect topicNP
    CMDescribe -> MoveDescribe topicNP
    CMPurpose -> MovePurpose topicNP
    CMHypothesis -> MoveHypothesis topicNP
    CMRepair -> MoveMisunderstanding
    CMContact -> MoveContact topicNP
    CMAnchor -> MoveAnchor topicNP
    CMClarify -> MoveClarify topicNP
    CMDeepen -> MoveDeepen topicNP
    CMConfront -> MoveConfront topicNP
    CMNextStep -> MoveNextStepLocal topicNP
    CMDistinguish -> MoveDistinguish topicNP (MkNP "smysl_N")

applyStanceToAst :: StanceMarker -> ClaimAst -> ClaimAst
applyStanceToAst Tentative ast = StanceWrapped "ApplyStanceTentative" ast
applyStanceToAst Firm ast      = StanceWrapped "ApplyStanceFirm" ast
applyStanceToAst _ ast               = ast

extractNumber :: InputPropositionFrame -> GfNumber
extractNumber frame =
  let txt = T.toLower (ipfRawText frame)
  in if "мы" `T.isInfixOf` txt || "вы" `T.isInfixOf` txt || "нас" `T.isInfixOf` txt || "вас" `T.isInfixOf` txt
     then NumPl
     else NumSg

contrastAxisFromFrame :: InputPropositionFrame -> Text
contrastAxisFromFrame frame =
  case propositionTypeFromText (ipfPropositionType frame) of
    Just ComparisonPlausibilityQ -> "логичность"
    Just SelfKnowledgeQ
      | ipfSemanticTarget frame == "user" -> "границы знания"
      | ipfSemanticTarget frame == "user_help" -> "рамка помощи"
      | ipfSemanticTarget frame == "self_capability" -> "границы способности"
      | otherwise -> "самоописание"
    Just DialogueInvitationQ -> "рамка разговора"
    Just ConceptKnowledgeQ -> "границы знания"
    Just PurposeQ -> "назначение"
    Just SelfStateQ -> "внутренний ход"
    Just MisunderstandingReport -> "точка разрыва"
    Just GenerativePrompt -> "направление мысли"
    Just ContemplativeTopic -> "смысловой резонанс"
    _ -> ""

nonEmptyOr :: Text -> Text -> Text
nonEmptyOr preferred fallback
  | T.null (T.strip preferred) = fallback
  | otherwise = preferred

buildRCP :: CanonicalMoveFamily -> ResponseMeaningPlan -> ResponseContentPlan
buildRCP family meaningPlan =
  ResponseContentPlan
    { rcpFamily = family
    , rcpOpening = familyToOpeningMove family
    , rcpCore = familyToCoreMove family
    , rcpLimit =
        if family == CMRepair
          then MoveAcknowledgeRupture
          else familyToCoreMove family
    , rcpContinuation = MoveNextStep
    , rcpStyle = styleForStance (rmpStance meaningPlan)
    }

styleForStance :: StanceMarker -> RenderStyle
styleForStance stance
  | stance `elem` [Firm, Commit] = StyleFormal
  | stance `elem` [Honest, Explore] = StyleStandard
  | otherwise = StyleWarm

familyDefaultDepthMode :: CanonicalMoveFamily -> DepthMode
familyDefaultDepthMode family
  | family `elem` [CMDeepen, CMHypothesis, CMPurpose] = DeepDepth
  | otherwise = SurfaceDepth
