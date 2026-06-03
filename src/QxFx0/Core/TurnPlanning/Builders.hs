{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

{-| Builders for response meaning/control plans from routing context. -}
module QxFx0.Core.TurnPlanning.Builders
  ( buildRMP
  , buildRMPWithTruthContract
  , buildRCP
  ) where

import Data.Text (Text)
import qualified Data.Text as T

import QxFx0.Core.TruthContract (capCommitmentStrengthByTruthContract)
import QxFx0.Lexicon.GfMap (lookupTopicGfLexemeId)
import QxFx0.Core.SensePlan (familySenseBundle)
import QxFx0.Core.TurnPlanning.Modulation
  ( feralDegradation
  , threeStageModulationWithTruthContract
  , threeStageModulation
  )
import QxFx0.Semantic.Proposition (PropositionType(..), propositionTypeFromText)
import QxFx0.Types
import QxFx0.Types.State.Perspective (PerspectiveScope(..), renderPerspectiveScope)

buildRMP :: CanonicalMoveFamily -> DialogueCommitmentLedger -> DialoguePhase -> DialogueThread -> InputPropositionFrame -> SenseVector -> Text -> EgoState -> AtomTrace -> Bool -> ResponseMeaningPlan
buildRMP family ledger phase thread frame senseVector topic ego trace nixAvailable =
  buildRMPWithTruthContract LegacyIncompleteSurface family ledger phase thread frame senseVector topic ego trace nixAvailable

buildRMPWithTruthContract :: TruthContractStatus -> CanonicalMoveFamily -> DialogueCommitmentLedger -> DialoguePhase -> DialogueThread -> InputPropositionFrame -> SenseVector -> Text -> EgoState -> AtomTrace -> Bool -> ResponseMeaningPlan
buildRMPWithTruthContract truthStatus family ledger phase thread frame senseVector topic ego trace nixAvailable =
  let (family', sensePlan, microPlan) = familySenseBundle family ledger phase thread senseVector
      baseStance = familyToStance family'
      baseEpistemic = familyToEpistemic family'
      (feralStance, feralEpistemic) = feralDegradation nixAvailable baseStance baseEpistemic
      plannedTruthStatus = provisionalTruthContractStatus truthStatus family' phase thread ledger nixAvailable
      (finalStance, finalEpistemic) = threeStageModulationWithTruthContract plannedTruthStatus ego trace feralStance feralEpistemic
      plannedTopic =
        let topic0 = topicFromFrame thread ledger phase frame topic
            anchorTxt = unSemanticNodeId (svAnchor senseVector)
        in if T.null (T.strip topic0) then anchorTxt else topic0
      plannedScope = dialogueStructuralScope phase thread ledger plannedTopic
      primaryClaim = primaryClaimFromFrame plannedTruthStatus frame plannedTopic
      baseAst = claimAstFromFrame plannedTruthStatus frame plannedTopic ego
      primaryClaimAst = fmap (applyStanceToAst finalStance) baseAst
      contrastAxis =
        let axis0 = contrastAxisFromFrame frame
        in if T.null axis0 then senseAxisSummary (rspPreservedAxes sensePlan) else axis0
    in ResponseMeaningPlan
        { rmpFamily = family'
        , rmpForce = forceForFamily family'
        , rmpSpeechAct = familyToSpeechAct family'
        , rmpRelation = familyToRelation family'
        , rmpStrategy = familyToStrategy family'
        , rmpStance = finalStance
        , rmpEpistemic = finalEpistemic
        , rmpTopic = plannedTopic
        , rmpPrimaryClaim = primaryClaim
        , rmpPrimaryClaimAst = primaryClaimAst
        , rmpScope = plannedScope
        , rmpContrastAxis = contrastAxis
        , rmpImplicationDirection = implicationDirectionFromScope plannedScope plannedTruthStatus family'
        , rmpProvenance = BuiltClaim
        , rmpTruthContractStatus = plannedTruthStatus
        , rmpCommitmentStrength = capCommitmentStrengthByTruthContract plannedTruthStatus (epistemicConfidence finalEpistemic)
        , rmpDepthMode = familyDefaultDepthMode family'
        , rmpSensePlan = sensePlan
        , rmpMicroPlan = microPlan
        }

provisionalTruthContractStatus :: TruthContractStatus -> CanonicalMoveFamily -> DialoguePhase -> DialogueThread -> DialogueCommitmentLedger -> Bool -> TruthContractStatus
provisionalTruthContractStatus incoming family phase thread ledger nixAvailable
  | family == CMRepair = NonExpansiveRecoverySurface
  | not nixAvailable = ExplicitFallbackSurface
  | scopeConstrained = AssembledSurfacePreserved
  | otherwise =
      case incoming of
        CanonicalSurfacePreserved -> AssembledSurfacePreserved
        LegacyIncompleteSurface -> AssembledSurfacePreserved
        other -> other
  where
    scopeConstrained =
      phase `elem` [Clarifying, Repairing, Grounding, Contesting]
        || any ((`elem` [CsUnresolved, CsContested, CsSuspended]) . dcStatus) (dclItems ledger)
        || not (T.null (T.strip (dtPhaseScope thread)))

topicFromFrame :: DialogueThread -> DialogueCommitmentLedger -> DialoguePhase -> InputPropositionFrame -> Text -> Text
topicFromFrame thread ledger phase frame fallback =
  clampTopicToDialogueScope phase thread ledger rawTopic
  where
    rawTopic =
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

clampTopicToDialogueScope :: DialoguePhase -> DialogueThread -> DialogueCommitmentLedger -> Text -> Text
clampTopicToDialogueScope phase thread ledger proposedTopic =
  let threadFocus = T.strip (dtCurrentFocus thread)
      scopeFocus = T.strip (dtPhaseScope thread)
      canonicalFocus = structuralScopeText thread (nonEmptyOr scopeFocus threadFocus)
      normalizedProposed = T.strip proposedTopic
      inLockedPhase = phase `elem` [Clarifying, Repairing, Grounding, Contesting]
      hasOpenLedger = any ((`elem` [CsUnresolved, CsContested, CsSuspended]) . dcStatus) (dclItems ledger)
      topicEscapesScope =
        not (T.null canonicalFocus)
          && not (T.null normalizedProposed)
          && canonicalFocus /= normalizedProposed
          && normalizeScopeKey canonicalFocus /= normalizeScopeKey normalizedProposed
  in if T.null canonicalFocus
       then normalizedProposed
       else if T.null normalizedProposed
         then canonicalFocus
         else if (inLockedPhase || hasOpenLedger) && topicEscapesScope
            then canonicalFocus
            else normalizedProposed

dialogueStructuralScope :: DialoguePhase -> DialogueThread -> DialogueCommitmentLedger -> Text -> Maybe PerspectiveScope
dialogueStructuralScope phase thread ledger topicText
  | T.null normalizedTopic = dtStructuralScope thread
  | lockedPhase || hasOpenLedger = Just (ScopeTopic scopedTopic)
  | otherwise = Just (ScopeTopic normalizedTopic)
  where
    normalizedTopic = T.strip topicText
    scopedTopic = structuralScopeText thread normalizedTopic
    lockedPhase = phase `elem` [Clarifying, Repairing, Grounding, Contesting]
    hasOpenLedger = any ((`elem` [CsUnresolved, CsContested, CsSuspended]) . dcStatus) (dclItems ledger)

structuralScopeText :: DialogueThread -> Text -> Text
structuralScopeText thread fallback =
  case dtStructuralScope thread of
    Just (ScopeTopic topic) -> nonEmptyOr topic fallback
    Just (ScopeTheme theme) -> nonEmptyOr theme fallback
    Just (ScopeCluster cluster) -> nonEmptyOr cluster fallback
    Nothing -> fallback

normalizeScopeKey :: Text -> Text
normalizeScopeKey = T.unwords . T.words . T.toLower . T.strip

implicationDirectionFromScope :: Maybe PerspectiveScope -> TruthContractStatus -> CanonicalMoveFamily -> Text
implicationDirectionFromScope mScope truthStatus family
  | truthStatus `notElem` [CanonicalSurfacePreserved, AssembledSurfacePreserved] = "bounded"
  | family `elem` [CMNextStep, CMDeepen, CMPurpose] = maybe "bounded" (const "forward") mScope
  | otherwise = "bounded"

primaryClaimFromFrame :: TruthContractStatus -> InputPropositionFrame -> Text -> Text
primaryClaimFromFrame truthStatus frame fallback =
  case propositionTypeFromText (ipfPropositionType frame) of
    Just SelfKnowledgeQ
      | ipfSemanticTarget frame == "user" ->
          if truthStatus == CanonicalSurfacePreserved
            then "Я знаю о тебе только то, что проявлено в текущей сессии."
            else "О тебе я удерживаю только то, что локально проявлено в текущей сессии."
      | ipfSemanticTarget frame == "user_help" ->
          "Я могу помочь, если удерживается локальная рамка задачи и не теряется предмет запроса."
      | ipfSemanticTarget frame == "self_capability" ->
          "Я могу работать с таким действием в пределах текущей сессии, если запрос остаётся локально определимым."
      | otherwise ->
          if truthStatus == CanonicalSurfacePreserved
            then "Я знаю о себе свою роль, состояние и ход текущего диалога."
            else "О себе я удерживаю только локальную рабочую модель роли, состояния и хода текущего диалога."
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

claimAstFromFrame :: TruthContractStatus -> InputPropositionFrame -> Text -> EgoState -> Maybe ClaimAst
claimAstFromFrame truthStatus frame fallback ego =
  let subject0 = nonEmptyOr (ipfSemanticSubject frame) fallback
      scopedSubject = if truthStatus `elem` [CanonicalSurfacePreserved, AssembledSurfacePreserved] then subject0 else fallback
      topicNP = mkTopicNP scopedSubject
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
      Just ExploratoryPrompt ->
        Just familyFallback
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
mkTopicNP topic =
  MkNP $ case lookupTopicGfLexemeId topic of
    Just funId -> funId
    Nothing -> "ponyatie_N"

buildComparisonAst :: InputPropositionFrame -> GfNP -> ClaimAst
buildComparisonAst frame fallbackTopic =
  case ipfSemanticCandidates frame of
    left : right : _ ->
      MoveDistinguish (mkTopicNP left) (mkTopicNP right)
    _ ->
      MoveCompare fallbackTopic (MkNP "ponyatie_N")

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
    CMDistinguish -> MoveDistinguish topicNP (MkNP "ponyatie_N")

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
    , rcpContinuation = continuationMoveForScope meaningPlan
    , rcpStyle = styleForStance (rmpStance meaningPlan)
    }

continuationMoveForScope :: ResponseMeaningPlan -> ContentMove
continuationMoveForScope meaningPlan
  | rmpImplicationDirection meaningPlan /= "forward" = MoveStateBoundary
  | otherwise = senseContinuationMove (rspChosenOperator (rmpSensePlan meaningPlan))

senseContinuationMove :: SenseOperator -> ContentMove
senseContinuationMove op = case op of
  OpDefine -> MoveDefineFrame
  OpGround -> MoveGroundBasis
  OpDistinguish -> MoveShowContrast
  OpExplainCause -> MoveStateBoundary
  OpExplainPurpose -> MovePurposeTeleology
  OpReflect -> MoveReflectMirror
  OpConstrain -> MoveClarifyDisambiguate
  OpRepair -> MoveRepairBridge
  OpClarify -> MoveClarifyDisambiguate
  OpDeepen -> MoveDeepenProbe
  OpNextStep -> MoveNextStep

styleForStance :: StanceMarker -> RenderStyle
styleForStance stance
  | stance `elem` [Firm, Commit] = StyleFormal
  | stance `elem` [Honest, Explore] = StyleStandard
  | otherwise = StyleWarm

familyDefaultDepthMode :: CanonicalMoveFamily -> DepthMode
familyDefaultDepthMode family
  | family `elem` [CMDeepen, CMHypothesis, CMPurpose] = DeepDepth
  | otherwise = SurfaceDepth

senseAxisSummary :: [SenseAxis] -> Text
senseAxisSummary axes =
  case axes of
    [] -> ""
    xs -> T.intercalate "+" (map renderSenseAxis xs)
