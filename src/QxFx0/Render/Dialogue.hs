{-# LANGUAGE OverloadedStrings, LambdaCase, DerivingStrategies #-}
module QxFx0.Render.Dialogue
  ( DialogueRenderArtifact(..)
  , hasStructuredDialogueSurface
  , renderDialogueArtifact
  , renderDialogueUtterance
  , renderOperatorAwareDialogue
  , moveToText
  , isVapidTopic
  , cleanTopic
  , stancePrefix
  , linearizeClaimAstRus
  ) where

import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Char as Char
import Data.Maybe (listToMaybe)
import QxFx0.Types
import QxFx0.Lexicon.GfMap
  ( GfLexemeForms(..)
  , defaultGfLexemeId
  , lookupGfLexemeForms
  , topicToGfLexemeId
  )
import QxFx0.Lexicon.Inflection (genitiveForm, prepositionalForm, toNominative)
import QxFx0.Types.Text (finalizeForce)
import QxFx0.Semantic.Proposition (PropositionType(..), propositionTypeFromText)
import QxFx0.Policy.ParserKeywords
  ( vapidWords
  )
import QxFx0.Semantic.KeywordMatch (tokenizeKeywordText)
import QxFx0.Policy.RenderLexicon
  ( stanceExplore, stanceTentative, stanceFirm, stanceHonest
  , stanceHoldBack, stanceCurated
  , styleFormal, styleWarm, styleDirect, stylePoetic
  , styleClinical, styleCautious, styleRecovery
  , moveGroundKnownPrefix, moveGroundBasisPrefix, moveShiftFromLabelPrefix
  , moveDefineFramePrefix, moveStateDefinitionPrefix
  , moveShowContrastPrefix, moveShowContrastPrepSuffix
  , moveStateBoundaryPrefix, moveReflectMirrorPrefix
  , moveReflectResonatePrefix, moveDescribeSketchPrefix
  , movePurposeTeleologyPrefix, moveHypothesizeTestPrefix
  , moveAffirmPresence, moveAcknowledgeRupture
  , moveRepairBridgePrefix, moveContactBridgePrefix
  , moveContactReachPrefix, moveAnchorStabilizePrefix
  , moveClarifyDisambiguatePrefix, moveDeepenProbePrefix
  , moveConfrontChallengePrefix, moveNextStepPrefix
  , openGuillemet, closeGuillemet
  , arrowSeparator, dashSeparator
  )

data DialogueRenderArtifact = DialogueRenderArtifact
  { draRenderedText :: !Text
  , draQuestionLike :: !Bool
  , draStylePrefixText :: !Text
  , draTemplateBodyText :: !Text
  , draClaimText :: !Text
  , draClaimAst :: !(Maybe ClaimAst)
  , draLinearizationLang :: !(Maybe Text)
  , draLinearizationOk :: !Bool
  , draFallbackReason :: !(Maybe Text)
  } deriving stock (Eq, Show)

renderDialogueUtterance :: ResponseMeaningPlan -> ResponseContentPlan -> Text -> [IdentityClaimRef] -> MorphologyData -> Text
renderDialogueUtterance rmp rcp topic claims morph =
  draRenderedText (renderDialogueArtifact emptyInputPropositionFrame rmp rcp topic claims morph)

renderDialogueArtifact :: InputPropositionFrame -> ResponseMeaningPlan -> ResponseContentPlan -> Text -> [IdentityClaimRef] -> MorphologyData -> DialogueRenderArtifact
renderDialogueArtifact frame rmp rcp topic claims morph =
  case renderStructuredDialogueArtifact frame rmp (rcpStyle rcp) morph of
    Just artifact -> artifact
    Nothing ->
      let cleanedTopic = cleanTopic topic
          openingText = moveToText (rcpOpening rcp) cleanedTopic morph
          coreText = moveToText (rcpCore rcp) cleanedTopic morph
          limitText = moveToText (rcpLimit rcp) cleanedTopic morph
          contText = moveToText (rcpContinuation rcp) cleanedTopic morph
          stylePrefixText = stylePrefix (rcpStyle rcp)
          claimText = case claims of
            (c:_) ->
              case sanitizeIdentityClaimText (icrText c) of
                Just txt -> " " <> txt
                Nothing -> ""
            []    -> ""
          parts = dedupeText (filter (not . T.null) [openingText, coreText, limitText])
          body = T.intercalate (styleDelimiter (rcpStyle rcp)) (take 3 parts)
          fullBody = if T.null contText then body else body <> arrowSeparator <> contText
          withClaims = if T.null claimText then fullBody else fullBody <> claimText
          withStyle = if T.null stylePrefixText then withClaims else stylePrefixText <> " " <> withClaims
          rendered = finalizeForce (rmpForce rmp) (T.strip withStyle)
      in DialogueRenderArtifact
          { draRenderedText = rendered
          , draQuestionLike = rmpForce rmp == IFAsk
          , draStylePrefixText = stylePrefixText
          , draTemplateBodyText = fullBody
          , draClaimText = claimText
          , draClaimAst = Nothing
          , draLinearizationLang = Nothing
          , draLinearizationOk = False
          , draFallbackReason = Nothing
          }

hasStructuredDialogueSurface :: InputPropositionFrame -> Bool
hasStructuredDialogueSurface frame =
  maybe False structuredDialogueType (propositionTypeFromText (ipfPropositionType frame))

renderStructuredDialogueArtifact :: InputPropositionFrame -> ResponseMeaningPlan -> RenderStyle -> MorphologyData -> Maybe DialogueRenderArtifact
renderStructuredDialogueArtifact frame rmp renderStyle morph = do
  propositionType <- propositionTypeFromText (ipfPropositionType frame)
  if not (structuredDialogueType propositionType)
    then Nothing
    else
      let (body, claimAst, mLang, linearizationOk, fallbackReason) =
            structuredBody propositionType frame rmp renderStyle morph
          rendered = finalizeForce IFAssert (T.strip body)
      in Just
          DialogueRenderArtifact
            { draRenderedText = rendered
            , draQuestionLike = False
            , draStylePrefixText = ""
            , draTemplateBodyText = body
            , draClaimText = ""
            , draClaimAst = claimAst
            , draLinearizationLang = mLang
            , draLinearizationOk = linearizationOk
            , draFallbackReason = fallbackReason
            }

structuredDialogueType :: PropositionType -> Bool
structuredDialogueType propositionType =
  propositionType `elem`
    [ RepairSignal
    , ContactSignal
    , AffectiveQ
    , OperationalStatusQ
    , OperationalCauseQ
    , GroundQ
    , SystemLogicQ
    , SelfKnowledgeQ
    , DialogueInvitationQ
    , ConceptKnowledgeQ
    , PurposeQ
    , WorldCauseQ
    , LocationFormationQ
    , SelfStateQ
    , ComparisonPlausibilityQ
    , MisunderstandingReport
    , GenerativePrompt
    , ContemplativeTopic
    , NextStepQ
    ]

structuredBody :: PropositionType -> InputPropositionFrame -> ResponseMeaningPlan -> RenderStyle -> MorphologyData -> (Text, Maybe ClaimAst, Maybe Text, Bool, Maybe Text)
structuredBody propositionType frame rmp renderStyle morph =
  case propositionType of
    RepairSignal ->
      plain ("Вижу сигнал перегруза в текущем ходе. Я не буду наращивать интерпретации: сначала восстановим опору. "
        <> "Коротко укажи, где именно ответ сломался для тебя, и я переформулирую точечно.")
    ContactSignal ->
      if isGreetingSmallTalkFrame frame
        then plain (contactGreetingSurface frame)
        else plain ("Слышу, что сейчас нужна опора."
            <> contactContextSentence morph (ipfSemanticSubject frame)
            <> " Давай упростим: выделим одну точку напряжения и выберем один короткий шаг на ближайшее время.")
    AffectiveQ ->
      plain ("Слышу, что сейчас нужна опора."
        <> contactContextSentence morph (ipfSemanticSubject frame)
        <> " Давай упростим: выделим одну точку напряжения и выберем один короткий шаг на ближайшее время.")
    OperationalStatusQ ->
      let ast = claimAstOrFallback MoveOperationalStatus (rmpPrimaryClaimAst rmp)
          fallback = pickDeterministic (T.toLower (ipfRawText frame) <> "|operational_status")
            [ "Я работаю. Ограничение сейчас не в запуске, а в том, что иногда теряется точность разбора входа."
            , "Я работаю. В штатном режиме, но слабое место сейчас — локальный разбор вопроса и выбор слишком общего шаблона."
            , "Я работаю. Запуск в норме; основной риск сейчас в маршрутизации: иногда вопрос схлопывается до слишком общей трактовки."
            , "Я работаю. Узкое место — пропозиционный разбор и избыточно быстрый переход к шаблонному ходу."
            ]
          claim = linearizeOrFallback ast renderStyle morph fallback
      in withClaim (clText claim) ast claim
    OperationalCauseQ ->
      let ast = claimAstOrFallback MoveOperationalCause (rmpPrimaryClaimAst rmp)
          fallback = pickDeterministic (T.toLower (ipfRawText frame) <> "|operational_cause")
            [ "По запуску я работаю. Проблема сейчас в разборе смысла и маршрутизации: вопрос может быть слишком рано схлопнут до упрощённого ядра."
            , "По запуску я работаю. Проблема сейчас в разборе смысла и маршрутизации: из нескольких трактовок иногда выбирается слишком общий ход."
            , "По запуску я работаю. Проблема сейчас в разборе смысла и маршрутизации: ранний выбор семейства ответа делает реплику шаблонной."
            , "По запуску я работаю. Проблема сейчас в разборе смысла и маршрутизации: при потере нюансов ответ уходит в слишком универсальную формулу."
            ]
          claim = linearizeOrFallback ast renderStyle morph fallback
      in withClaim (clText claim) ast claim
    GroundQ ->
      let topicRef = nonEmptyOr (ipfSemanticSubject frame) "ситуация"
          topicPrep = structuredPrepositional morph topicRef
          ast = claimAstOrFallback (MoveGround (MkNP (topicToGfLexemeId topicRef))) (rmpPrimaryClaimAst rmp)
          fallback = "Держу это как устойчивую опору для дальнейшего разбора."
          claim = linearizeOrFallback ast renderStyle morph fallback
      in withClaim ("Если говорить " <> aboutWithTopic topicPrep <> ", то " <> clText claim) ast claim
    SystemLogicQ ->
      let ast = claimAstOrFallback MoveSystemLogic (rmpPrimaryClaimAst rmp)
          claim = linearizeOrFallback ast renderStyle morph (systemLogicSurface frame)
      in withClaim (clText claim) ast claim
    SelfKnowledgeQ
      | asksThoughtCapacityQuestion frame ->
          plain "Нет, не одна. Я могу формулировать разные мысли, но если запросы слишком близки, мой генеративный слой пока склонен повторять удачную формулировку вместо того, чтобы сразу разворачивать новую."
      | ipfSemanticTarget frame == "user" ->
          plain "О тебе я знаю только то, что проявлено в этой сессии. У меня нет внешней биографии, скрытых профилей или отдельной памяти о тебе вне текущего разговора; я могу опираться лишь на твои реплики, выбранные темы и уже установленные в диалоге рамки."
      | ipfSemanticTarget frame == "user_help" ->
          plain "Да, я могу помочь. Лучше всего я работаю, когда задача задана явно и можно удержать локальную рамку: что именно нужно прояснить, различить, определить или собрать."
      | ipfSemanticTarget frame == "self_capability" ->
          plain ("Да, в пределах текущей сессии я могу работать с " <> structuredInstrumentalIdea (nonEmptyOr (ipfSemanticSubject frame) "этим действием")
            <> ". Моя способность здесь не внешняя магия, а локальный разбор, удержание рамки и последовательная сборка ответа.")
      | otherwise ->
          let target = ipfSemanticTarget frame
              forceTargetAst =
                target `elem` ["self_intentions", "self_values", "self_future", "self_freedom", "self_reflection"]
              ast =
                if forceTargetAst
                  then selfKnowledgeFallbackAst frame
                  else claimAstOrFallback (selfKnowledgeFallbackAst frame) (rmpPrimaryClaimAst rmp)
              fallback = "Я — локальная система диалога. О себе я знаю свою роль, текущее состояние и способ, которым иду по ходу разговора: я работаю через типизированный разбор, маршрутизацию семейства хода и ограничения текущей сессии."
              claim = linearizeOrFallback ast renderStyle morph fallback
          in withClaim (selfKnowledgeSurfaceByTarget target (clText claim)) ast claim
    DialogueInvitationQ ->
      let fallbackTopic = nonEmptyOr (ipfSemanticSubject frame) (nonEmptyOr (rmpTopic rmp) "тема")
          fallbackAst = MoveInvite (MkNP (topicToGfLexemeId fallbackTopic)) ModFirst (ActMaintain NumSg "ramka_N")
          ast = claimAstOrFallback fallbackAst (rmpPrimaryClaimAst rmp)
          claim = linearizeOrFallback ast renderStyle morph (dialogueInvitationSurface frame morph)
          rendered = clText claim
      in withClaim rendered
           ast
           claim
    ConceptKnowledgeQ
      | T.toLower (T.strip (ipfSemanticSubject frame)) == "солнце" ->
          plain "Да, я знаю, что солнце — это звезда и источник света и тепла для Земли. Для меня это базовое понятийное знание о явлениях внешнего мира, а не результат текущего наблюдения."
      | otherwise ->
          let ast = claimAstOrFallback (MoveDefine (MkNP (topicToGfLexemeId (nonEmptyOr (ipfSemanticSubject frame) (nonEmptyOr (rmpTopic rmp) "понятии")))) RelIdentity (MkNP "ponyatie_N")) (rmpPrimaryClaimAst rmp)
              claim = linearizeOrFallback ast renderStyle morph (rmpPrimaryClaim rmp)
          in withClaim ("Если говорить " <> aboutWithTopic (conceptTopicReference frame morph)
              <> ", зафиксирую рабочее определение и отделю его от употребления и границ знания. "
              <> clText claim) ast claim
    PurposeQ ->
      let topicRef = nonEmptyOr (T.strip (ipfSemanticSubject frame)) (nonEmptyOr (T.strip (rmpTopic rmp)) "объект")
          topicNom = toNominative morph topicRef
          topicGen = structuredGenitive morph topicNom
          topicPhrase =
            if isLikelyBrokenGenitive topicNom topicGen
              then "темы " <> openGuillemet <> topicRef <> closeGuillemet
              else topicGen
          topicFunId = topicToGfLexemeId topicNom
          ast = claimAstOrFallback (MovePurpose (MkNP topicFunId)) (rmpPrimaryClaimAst rmp)
          claim = linearizeOrFallback ast renderStyle morph (rmpPrimaryClaim rmp)
          purposeClaimText
            | topicFunId == defaultGfLexemeId =
                "Функция " <> purposeTopicGenitive topicNom topicGen <> " проявляется через повторяемую роль в действии."
            | otherwise = clText claim
      in withClaim ("Если разбирать функции " <> topicPhrase
        <> ", полезно сначала выделить действие, контекст применения и устойчивый результат. "
        <> purposeClaimText) ast claim
    WorldCauseQ ->
      let topicRef = nonEmptyOr (ipfSemanticSubject frame) (nonEmptyOr (rmpTopic rmp) "явление")
          topicNom = toNominative morph topicRef
          topicGen = structuredGenitive morph topicNom
          safeTopicGen
            | isLikelyBrokenGenitive topicNom topicGen = "этого явления"
            | isLikelyAdjectiveLikeTopic topicNom = "этого явления"
            | otherwise = topicGen
          ast = claimAstOrFallback (MoveCause (MkNP (topicToGfLexemeId topicNom)) MechParse) (rmpPrimaryClaimAst rmp)
          claim = linearizeOrFallback ast renderStyle morph (rmpPrimaryClaim rmp)
      in withClaim ("Если говорить о причине " <> safeTopicGen <> ", то " <> clText claim
          <> " Поэтому я различаю локальное рассуждение о механизме и полноценное знание о внешнем мире.") ast claim
    LocationFormationQ ->
      let topicRef = nonEmptyOr (ipfSemanticSubject frame) "мысль"
      in plain ("Если говорить " <> aboutWithTopic (structuredPrepositional morph topicRef)
        <> ", то в моей локальной модели она возникает не в одной точке, а в структуре связей между состоянием, пропозициями и ограничениями диалога. "
        <> rmpPrimaryClaim rmp)
    SelfStateQ ->
      case selfStateDirectSurface frame of
        Just direct -> plain direct
        Nothing ->
          let ast = claimAstOrFallback MoveSelfState (rmpPrimaryClaimAst rmp)
              claim = linearizeOrFallback ast renderStyle morph (rmpPrimaryClaim rmp)
          in withClaim (selfStateSurface frame <> " " <> clText claim) ast claim
    ComparisonPlausibilityQ ->
      case ipfSemanticCandidates frame of
        left:right:_ ->
          let leftNom = toNominative morph left
              rightNom = toNominative morph right
              ast = claimAstOrFallback (MoveDistinguish (MkNP (topicToGfLexemeId leftNom)) (MkNP (topicToGfLexemeId rightNom))) (rmpPrimaryClaimAst rmp)
              claim = linearizeOrFallback ast renderStyle morph (rmpPrimaryClaim rmp)
          in withClaim ("Сравнивать нужно в явной рамке. Если речь о бытовой устойчивости, то " <> rightNom
            <> " обычно выглядит естественнее, потому что " <> leftNom
            <> " описывает менее устойчивую конфигурацию. " <> clText claim
            <> " Без явной рамки сравнение остаётся зависимым от принятых допущений.") ast claim
        _ ->
          plain ("Сравнение плаузибельности требует явной рамки. " <> rmpPrimaryClaim rmp)
    MisunderstandingReport ->
      let ast = claimAstOrFallback MoveMisunderstanding (rmpPrimaryClaimAst rmp)
          claim = linearizeOrFallback ast renderStyle morph ("Я принимаю это как сигнал сбоя взаимопонимания. " <> rmpPrimaryClaim rmp
            <> " Давай уточним, где именно ответ разошёлся с твоим запросом: в смысле, тоне или ходе рассуждения.")
      in withClaim (clText claim) ast claim
    GenerativePrompt ->
      let ast = claimAstOrFallback MoveGenerativeThought (rmpPrimaryClaimAst rmp)
          claim = linearizeOrFallback ast renderStyle morph (generativeThought frame)
      in withClaim (clText claim) ast claim
    ContemplativeTopic ->
      let fallbackAst = MoveContemplative (MkNP (topicToGfLexemeId (nonEmptyOr (ipfSemanticSubject frame) "тема")))
          ast = claimAstOrFallback fallbackAst (rmpPrimaryClaimAst rmp)
          claim = linearizeOrFallback ast renderStyle morph ("Если держаться слова " <> openGuillemet <> toNominative morph (nonEmptyOr (ipfSemanticSubject frame) "тема") <> closeGuillemet
            <> ", я слышу в нём не только предмет, но и поле смыслов. Здесь можно идти через память, утрату, близость и способ удерживать форму жизни.")
      in withClaim (clText claim) ast claim
    NextStepQ ->
      let topicRef = nonEmptyOr (ipfSemanticSubject frame) (nonEmptyOr (rmpTopic rmp) "задача")
          topicNom = toNominative morph topicRef
          ast = claimAstOrFallback (MoveNextStepLocal (MkNP (topicToGfLexemeId topicNom))) (rmpPrimaryClaimAst rmp)
          claim = linearizeOrFallback ast renderStyle morph ("Следующий шаг: конкретизировать " <> topicNom <> " в одном действии.")
      in withClaim
          ( clText claim <> "\n"
            <> "Зафиксируем практичный следующий ход:\n"
            <> "1) Назови одну цель по теме " <> topicNom <> ".\n"
            <> "2) Выбери минимальный шаг на 10-15 минут и сделай его.\n"
            <> "3) Проверь результат: стало яснее или нет, и скорректируй следующий шаг."
          )
          ast
          claim
    _ ->
      plain (rmpPrimaryClaim rmp)
  where
    plain txt = (txt, Nothing, Nothing, False, Nothing)
    withClaim body ast linearization =
      ( body
      , Just ast
      , Just "ru_GF_MVP"
      , clOk linearization
      , clFallbackReason linearization
      )

data ClaimLinearization = ClaimLinearization
  { clText :: !Text
  , clOk :: !Bool
  , clFallbackReason :: !(Maybe Text)
  } deriving stock (Eq, Show)

claimAstOrFallback :: ClaimAst -> Maybe ClaimAst -> ClaimAst
claimAstOrFallback fallbackAst maybeAst =
  case maybeAst of
    Just ast -> ast
    Nothing -> fallbackAst

linearizeOrFallback :: ClaimAst -> RenderStyle -> MorphologyData -> Text -> ClaimLinearization
linearizeOrFallback ast renderStyle morph fallbackText =
  case linearizeClaimAstRus ast renderStyle morph of
    Just txt ->
      ClaimLinearization
        { clText = txt
        , clOk = True
        , clFallbackReason = Nothing
        }
    Nothing ->
      ClaimLinearization
        { clText = fallbackText
        , clOk = False
        , clFallbackReason = Just "gf_linearization_failed"
        }

linearizeClaimAstRus :: ClaimAst -> RenderStyle -> MorphologyData -> Maybe Text
linearizeClaimAstRus ast renderStyle morph =
  case ast of
    StanceWrapped "ApplyStanceTentative" innerAst ->
      case linearizeClaimAstRus innerAst renderStyle morph of
        Just inner -> Just ("Возможно, нам стоит сказать, что " <> inner)
        Nothing -> Nothing
    StanceWrapped "ApplyStanceFirm" innerAst ->
      case linearizeClaimAstRus innerAst renderStyle morph of
        Just inner -> Just ("Зафиксируем строго: " <> inner)
        Nothing -> Nothing
    StanceWrapped _ innerAst ->
      linearizeClaimAstRus innerAst renderStyle morph
    MoveDefine (MkNP gfSubj) RelIdentity (MkNP gfObj) ->
      let subjNom = maybe "смысл" glfNom (lookupGfLexemeForms gfSubj)
          objIns = maybe "смыслом" glfIns (lookupGfLexemeForms gfObj)
      in Just (subjNom <> " является " <> objIns <> ".")
    MoveCause (MkNP gfSubj) MechParse ->
      let subjGen = maybe "смысла" glfGen (lookupGfLexemeForms gfSubj)
          seed = "cause|" <> subjGen
      in Just (pickDeterministic seed
          [ "Причиной " <> subjGen <> " служит механизм локального разбора."
          , "В моём локальном контуре причина " <> subjGen <> " объясняется механизмом локального разбора."
          , "Для " <> subjGen <> " я беру причинную схему через механизм локального разбора."
          , "Причинное объяснение " <> subjGen <> " у меня строится через механизм локального разбора."
          ])
    MoveInvite (MkNP gfTopic) gfMod gfAction ->
      -- Runtime fallback mirrors the GF surface when PGF is unavailable.
      let prepForm = maybe "смысле" glfPrep (lookupGfLexemeForms gfTopic)
          modStr = case gfMod of
            ModFirst -> "сначала "
            ModStrictly -> "строго "
          vpStr = case gfAction of
            ActMaintain num "ramka_N" -> (case num of NumPl -> "удержим"; NumSg -> "удержу") <> " рамку"
            ActDefine "granitsa_N" -> "определю границу"
            ActMaintain num obj ->
              let objAcc = maybe obj glfAcc (lookupGfLexemeForms obj)
              in (case num of NumPl -> "удержим "; NumSg -> "удержу ") <> objAcc
            ActDefine obj ->
              let objAcc = maybe obj glfAcc (lookupGfLexemeForms obj)
              in "определю " <> objAcc
      in Just ("Да, поговорим " <> aboutWithTopic prepForm <> ". Я " <> modStr <> vpStr <> ", чтобы не потерять фокус.")
    MovePurpose (MkNP gfTopic) ->
      let topicGen = maybe "смысла" glfGen (lookupGfLexemeForms gfTopic)
      in Just ("Функция " <> topicGen <> " проявляется через повторяемую роль в действии.")
    MoveSelfState ->
      Just "Мой текущий ход строится из разбора реплики, выбора семейства ответа и ограничений сессии."
    MoveCompare (MkNP gfLeft) (MkNP gfRight) ->
      let leftGen = maybe "первого" glfGen (lookupGfLexemeForms gfLeft)
          rightGen = maybe "второго" glfGen (lookupGfLexemeForms gfRight)
      in Just ("Сравнение " <> leftGen <> " и " <> rightGen <> " устойчиво только в явно заданной рамке.")
    MoveOperationalStatus ->
      Just (pickDeterministic "move_operational_status"
        [ "Я работаю. Ограничение сейчас не в запуске, а в том, что иногда теряется точность разбора входа."
        , "Я работаю. В штатном режиме, но слабое место сейчас — локальный разбор вопроса и выбор слишком общего шаблона."
        , "Я работаю. Запуск в норме; основной риск сейчас в маршрутизации: иногда вопрос схлопывается до слишком общей трактовки."
        , "Я работаю. Узкое место — пропозиционный разбор и избыточно быстрый переход к шаблонному ходу."
        ])
    MoveOperationalCause ->
      Just (pickDeterministic "move_operational_cause"
        [ "По запуску я работаю. Проблема сейчас в разборе смысла и маршрутизации: вопрос может быть слишком рано схлопнут до упрощённого ядра."
        , "По запуску я работаю. Проблема сейчас в разборе смысла и маршрутизации: из нескольких трактовок иногда выбирается слишком общий ход."
        , "По запуску я работаю. Проблема сейчас в разборе смысла и маршрутизации: ранний выбор семейства ответа делает реплику шаблонной."
        , "По запуску я работаю. Проблема сейчас в разборе смысла и маршрутизации: при потере нюансов ответ уходит в слишком универсальную формулу."
        ])
    MoveSystemLogic ->
      Just "Моя текущая логика локальная: я разбираю вопрос, выбираю семейство хода, сверяюсь с shadow-контуром и затем рендерю ответ. Слабое место сейчас в пропозиционном разборе и выборе семьи."
    MoveMisunderstanding ->
      Just "Я принимаю это как сигнал сбоя взаимопонимания и перехожу к уточнению: давай отметим, где именно ответ разошёлся с твоим запросом, в смысле, тоне или ходе рассуждения."
    MoveGenerativeThought ->
      Just "Одна мысль: смысл держится на связи между словами и опытом. Другая мысль: сила мышления — удержать различие. Новая мысль: развитие начинается, когда мы готовы менять собственную рамку. Логичная мысль: качество вывода проверяется связью между посылками и выводом."
    MoveContemplative (MkNP gfTopic) ->
      let topicNom = maybe "тема" glfNom (lookupGfLexemeForms gfTopic)
      in Just ("Если держаться слова " <> openGuillemet <> topicNom <> closeGuillemet <> ", я слышу в нём не только предмет, но и поле смыслов, включая субъектность как способ удерживать внутреннюю форму.")
    MoveGround (MkNP gfTopic) ->
      let topicAcc = maybe "это" glfAcc (lookupGfLexemeForms gfTopic)
      in Just ("Держу " <> topicAcc <> " как устойчивую опору для дальнейшего разбора.")
    MoveContact (MkNP gfTopic) ->
      let topicPrep = maybe "теме" glfPrep (lookupGfLexemeForms gfTopic)
      in Just ("Слышу запрос на контакт по теме " <> topicPrep <> ".")
    MoveReflect (MkNP gfTopic) ->
      let topicAcc = maybe "это" glfAcc (lookupGfLexemeForms gfTopic)
      in Just ("Вы отразили " <> topicAcc <> ", и это требует прояснения смысла.")
    MoveDescribe (MkNP gfTopic) ->
      let topicAcc = maybe "это" glfAcc (lookupGfLexemeForms gfTopic)
      in Just ("Опишу " <> topicAcc <> " через локальную рабочую рамку.")
    MoveDeepen (MkNP gfTopic) ->
      let topicPrep = maybe "теме" glfPrep (lookupGfLexemeForms gfTopic)
      in Just ("Углубим разговор о " <> topicPrep <> " через один устойчивый фокус.")
    MoveConfront (MkNP gfTopic) ->
      let topicNom = maybe "это" glfNom (lookupGfLexemeForms gfTopic)
      in Just ("Возражение: " <> topicNom <> " требует проверки допущений.")
    MoveAnchor (MkNP gfTopic) ->
      let topicPrep = maybe "теме" glfPrep (lookupGfLexemeForms gfTopic)
      in Just ("Фиксирую опору в " <> topicPrep <> " как точку устойчивости.")
    MoveClarify (MkNP gfTopic) ->
      let topicPrep = maybe "теме" glfPrep (lookupGfLexemeForms gfTopic)
      in Just ("Уточним, что именно вы имеете в виду в " <> topicPrep <> ".")
    MoveNextStepLocal (MkNP gfTopic) ->
      let topicAcc = maybe "это" glfAcc (lookupGfLexemeForms gfTopic)
      in Just ("Следующий шаг: конкретизировать " <> topicAcc <> " в одном действии.")
    MoveHypothesis (MkNP gfTopic) ->
      let topicNom = maybe "это" glfNom (lookupGfLexemeForms gfTopic)
      in Just ("Гипотеза: " <> topicNom <> " можно объяснить через локальную модель.")
    MoveDistinguish (MkNP gfLeft) (MkNP gfRight) ->
      let leftAcc = maybe "первое" glfAcc (lookupGfLexemeForms gfLeft)
          rightAcc = maybe "второе" glfAcc (lookupGfLexemeForms gfRight)
      in Just ("Различим " <> leftAcc <> " и " <> rightAcc <> " в одной рамке критериев.")
    ClaimPurpose subject ->
      let topic = structuredGenitive morph (normalizedTopic subject)
          variants =
            [ "Функция " <> topic <> " проявляется через повторяемую роль в действии."
            , "Роль " <> topic <> " определяется через стабильный эффект в практике."
            ]
      in if T.null (normalizedTopic subject) then Nothing else Just (pickStyleVariant renderStyle variants)
    ClaimSelfState ->
      Just (pickStyleVariant renderStyle
        [ "Мой внутренний ход собирается из входной реплики, выбора семейства и ограничений текущей сессии."
        , "Текущий внутренний ход формируется как локальная сборка: разбор входа, выбор семьи ответа и контроль ограничений."
        ])
    ClaimComparison left right ->
      let leftTopic = normalizedTopic left
          rightTopic = normalizedTopic right
          variants =
            [ "Сравнение " <> leftTopic <> " и " <> rightTopic <> " устойчиво только внутри явно заданной рамки."
            , "Плаузибельность пары " <> leftTopic <> " / " <> rightTopic <> " зависит от выбранных критериев рамки."
            ]
      in if T.null leftTopic || T.null rightTopic then Nothing else Just (pickStyleVariant renderStyle variants)

pickStyleVariant :: RenderStyle -> [Text] -> Text
pickStyleVariant _ [] = ""
pickStyleVariant style variants =
  let idx = fromEnum style `mod` length variants
  in variants !! idx

normalizedTopic :: Text -> Text
normalizedTopic = T.toLower . T.strip

renderOperatorAwareDialogue :: ResponseContentPlan -> Text -> IllocutionaryForce -> MorphologyData -> Text
renderOperatorAwareDialogue rcp topic force morph =
  let cleanedTopic = cleanTopic topic
      openingText = moveToText (rcpOpening rcp) cleanedTopic morph
      coreText = moveToText (rcpCore rcp) cleanedTopic morph
      body = T.intercalate dashSeparator (filter (not . T.null) [openingText, coreText])
  in finalizeForce force (T.strip body)

isVapidTopic :: Text -> Bool
isVapidTopic t = let low = T.toLower (T.strip t) in
  T.null low || low `elem` vapidWords

cleanTopic :: Text -> Text
cleanTopic t = if isVapidTopic t then "" else T.strip t

stancePrefix :: StanceMarker -> Text
stancePrefix Explore  = stanceExplore
stancePrefix Tentative = stanceTentative
stancePrefix Firm    = stanceFirm
stancePrefix Honest  = stanceHonest
stancePrefix Commit  = ""
stancePrefix Observe = ""
stancePrefix HoldBack = stanceHoldBack
stancePrefix Curated = stanceCurated

stylePrefix :: RenderStyle -> Text
stylePrefix StyleFormal   = styleFormal
stylePrefix StyleWarm     = styleWarm
stylePrefix StyleDirect   = styleDirect
stylePrefix StylePoetic   = stylePoetic
stylePrefix StyleClinical = styleClinical
stylePrefix StyleCautious = styleCautious
stylePrefix StyleRecovery = styleRecovery
stylePrefix StyleStandard = ""

styleDelimiter :: RenderStyle -> Text
styleDelimiter StyleDirect   = ". "
styleDelimiter StylePoetic   = " \8226 "
styleDelimiter StyleRecovery = " "
styleDelimiter _             = " \8212 "

moveToText :: ContentMove -> Text -> MorphologyData -> Text
moveToText MoveGroundKnown topic md      = moveGroundKnownPrefix <> withPrep md topic <> "."
moveToText MoveGroundBasis topic md      = moveGroundBasisPrefix <> toNominative md topic <> "."
moveToText MoveShiftFromLabel topic md   = moveShiftFromLabelPrefix <> openGuillemet <> toNominative md topic <> closeGuillemet <> "."
moveToText MoveDefineFrame topic md      = moveDefineFramePrefix <> toNominative md topic <> "."
moveToText MoveStateDefinition topic md  = moveStateDefinitionPrefix <> toNominative md topic <> "."
moveToText MoveShowContrast topic md     = moveShowContrastPrefix <> withPrep md topic <> moveShowContrastPrepSuffix
moveToText MoveStateBoundary topic md    = moveStateBoundaryPrefix <> genitiveForm md topic <> "."
moveToText MoveReflectMirror topic md    = moveReflectMirrorPrefix <> toNominative md topic <> "."
moveToText MoveReflectResonate topic md  = moveReflectResonatePrefix <> toNominative md topic <> "?"
moveToText MoveDescribeSketch topic md   = moveDescribeSketchPrefix <> toNominative md topic <> "."
moveToText MovePurposeTeleology topic md = movePurposeTeleologyPrefix <> genitiveForm md topic <> "."
moveToText MoveHypothesizeTest topic md  = moveHypothesizeTestPrefix <> toNominative md topic <> "?"
moveToText MoveAffirmPresence _ _        = moveAffirmPresence
moveToText MoveAcknowledgeRupture _ _    = moveAcknowledgeRupture
moveToText MoveRepairBridge topic md     = moveRepairBridgePrefix <> optionalTopic md topic <> "."
moveToText MoveContactBridge topic md    = moveContactBridgePrefix <> optionalTopic md topic <> "."
moveToText MoveContactReach topic md     = moveContactReachPrefix <> optionalTopic md topic <> "."
moveToText MoveAnchorStabilize topic md  = moveAnchorStabilizePrefix <> optionalTopic md topic <> "."
moveToText MoveClarifyDisambiguate topic md = moveClarifyDisambiguatePrefix <> toNominative md topic <> "?"
moveToText MoveDeepenProbe topic md      = moveDeepenProbePrefix <> toNominative md topic <> "?"
moveToText MoveConfrontChallenge topic md = moveConfrontChallengePrefix <> toNominative md topic <> "."
moveToText MoveNextStep topic md         = moveNextStepPrefix <> dashSeparator <> toNominative md topic <> "?"

withPrep :: MorphologyData -> Text -> Text
withPrep md t = prepositionalForm md t

optionalTopic :: MorphologyData -> Text -> Text
optionalTopic md t = if T.null t then "" else " \8212 " <> toNominative md t

nonEmptyOr :: Text -> Text -> Text
nonEmptyOr preferred fallback
  | T.null (T.strip preferred) = fallback
  | otherwise = preferred

isLikelyBrokenGenitive :: Text -> Text -> Bool
isLikelyBrokenGenitive raw gen =
  let rawN = T.toLower (T.strip raw)
      genN = T.toLower (T.strip gen)
      endsWithVowel t =
        case T.unsnoc t of
          Just (_, ch) -> Char.toLower ch `elem` ("аеёиоуыэюя" :: String)
          Nothing -> False
      infinitiveGenitiveArtifact =
        ("ть" `T.isSuffixOf` rawN || "ти" `T.isSuffixOf` rawN)
          && "ти" `T.isSuffixOf` genN
      vowelPlusAArtifact = endsWithVowel rawN && genN == rawN <> "а"
  in T.null genN || infinitiveGenitiveArtifact || vowelPlusAArtifact

purposeTopicGenitive :: Text -> Text -> Text
purposeTopicGenitive topicNom topicGen
  | isLikelyBrokenGenitive topicNom topicGen = "этого объекта"
  | otherwise = topicGen

dialogueTopicReference :: InputPropositionFrame -> MorphologyData -> Text
dialogueTopicReference frame md =
  case rawTopicAfterMarkers (ipfRawText frame) ["о", "об", "обо", "про"] of
    Just topic -> topic
    Nothing -> structuredPrepositional md (nonEmptyOr (ipfSemanticSubject frame) "этой теме")

conceptTopicReference :: InputPropositionFrame -> MorphologyData -> Text
conceptTopicReference frame md =
  case phraseAfterPrefix (ipfRawText frame) "что значит " of
    Just phrase -> "том, что значит " <> phrase
    Nothing ->
      case rawTopicAfterMarkers (ipfRawText frame) ["о", "об", "обо", "про"] of
        Just topic -> topic
        Nothing -> structuredPrepositional md (nonEmptyOr (ipfSemanticSubject frame) "этом понятии")

generativeThought :: InputPropositionFrame -> Text
generativeThought frame
  | any (`T.isInfixOf` subject) ["логич", "логика"] =
      pickDeterministic seed
        [ "Логичная мысль: если вывод противоречит собственным посылкам, пересматривать нужно не тон ответа, а структуру перехода между посылками и выводом."
        , "Логичная мысль: качество рассуждения проверяется не яркостью формулировки, а устойчивостью перехода от посылок к выводу."
        , "Логичная мысль: когда цепочка вывода ломается, чинить нужно правило перехода, а не украшать итоговую фразу."
        ]
  | "нов" `T.isInfixOf` lowered =
      pickDeterministic seed
        [ "Новая мысль: ум растет не только от накопления ответов, но и от способности менять собственную рамку, когда старая рамка уже не удерживает явление."
        , "Новая мысль: развитие начинается там, где мы пересматриваем исходную рамку, а не просто добавляем к ней ещё один тезис."
        , "Новая мысль: зрелость мышления видна в моменте, когда мы готовы заменить удобную схему на более точную."
        ]
  | any (`T.isInfixOf` lowered) ["ещё", "еще", "друг"] =
      pickDeterministic seed
        [ "Другая мысль: ум заметен не там, где он быстро отвечает, а там, где он способен удержать различие между похожими вещами и не склеить их в одно."
        , "Другая мысль: сила мышления проявляется в умении различать близкие смыслы, удержать различие и не превращать всё в общий шаблон."
        , "Другая мысль: точность начинается с различения; важно удержать различие, а не ускорять ответ."
        ]
  | "интересн" `T.isInfixOf` lowered =
      pickDeterministic seed
        [ "Интересная мысль: иногда вопрос нужен не для того, чтобы получить ответ, а для того, чтобы сделать видимой ту границу, которую раньше никто не замечал."
        , "Интересная мысль: хороший вопрос не закрывает тему, а показывает, где проходит её настоящая граница."
        , "Интересная мысль: вопрос ценен тогда, когда меняет угол зрения, а не только пополняет список ответов."
        ]
  | otherwise =
      pickDeterministic seed
        [ "Одна мысль: смысл держится не в громкости слова, а в той связи, которую это слово выдерживает с другими словами и с опытом разговора."
        , "Одна мысль: слово становится смыслом только тогда, когда выдерживает проверку связями, а не одиночным эффектом; именно связи удерживают содержание."
        , "Одна мысль: содержательность речи определяется не формой фразы, а устойчивостью связей с контекстом разговора."
        ]
  where
    lowered = T.toLower (ipfRawText frame)
    subject = T.toLower (ipfSemanticSubject frame)
    seed = lowered <> "|" <> subject

dialogueInvitationSurface :: InputPropositionFrame -> MorphologyData -> Text
dialogueInvitationSurface frame morph =
  pickDeterministic seed
    [ "Да, поговорим " <> aboutWithTopic (dialogueTopicReference frame morph)
        <> ". Я зафиксирую рамку и начну с опорного различения, чтобы удержать форму рассуждения и не распасть тему на случайные ассоциации."
    , "Да, поговорим " <> aboutWithTopic (dialogueTopicReference frame morph)
        <> ". Начну с устойчивой структуры, чтобы удержать форму рассуждения и вести ход последовательно."
    , "Да, поговорим " <> aboutWithTopic (dialogueTopicReference frame morph)
        <> ". Сначала закрепим границы вопроса, затем углубим аргументацию и сохраним форму рассуждения."
    ]
  where
    seed = T.toLower (ipfRawText frame) <> "|dialogue_invitation"

systemLogicSurface :: InputPropositionFrame -> Text
systemLogicSurface frame =
  pickDeterministic seed
    [ "Моя текущая логика локальная: я разбираю вопрос, выбираю семейство хода, сверяюсь с shadow-контуром и затем рендерю ответ. Слабое место сейчас в пропозиционном разборе и выборе семьи."
    , "Моя текущая логика локальная и детерминированная: входной разбор -> выбор семейства -> guard/ограничения -> поверхностная реализация. Сейчас главная зона риска — узкий входной разбор и ошибки в выборе семьи."
    , "Моя текущая логика локальная: я работаю по контуру семантический разбор -> маршрутизация семейства -> контроль ограничений -> финальный рендер. Сбой обычно возникает, когда вход слишком быстро схлопывается в шаблон и появляются ошибки в выборе семьи."
    ]
  where
    seed = T.toLower (ipfRawText frame) <> "|system_logic"

selfStateSurface :: InputPropositionFrame -> Text
selfStateSurface frame =
  pickDeterministic seed
    [ "Сейчас мой внутренний ход держится на твоей реплике, выборе семейства ответа и попытке не потерять смысл по дороге. Я не думаю как скрытый внутренний голос; я строю следующий ответ из текущего состояния диалога."
    , "Сейчас мой внутренний ход опирается на локальный разбор твоей реплики, текущую рамку сессии и выбранное семейство хода. Следующий шаг собирается из этих ограничений и текущего состояния диалога."
    , "Сейчас мой внутренний ход формируется из входного смысла, состояния сессии и маршрута ответа. Я удерживаю рамку и собираю следующую реплику из текущего состояния диалога."
    ]
  where
    seed = T.toLower (ipfRawText frame) <> "|self_state"

selfStateDirectSurface :: InputPropositionFrame -> Maybe Text
selfStateDirectSurface frame
  | "хоч" `T.isInfixOf` lowered && "сказать" `T.isInfixOf` lowered =
      Just "Да. Коротко: смысл держится, когда мы не путаем близкие вещи и проверяем связность шага с целью."
  | "кем" `T.isInfixOf` lowered && "стать" `T.isInfixOf` lowered =
      Just "Я не становлюсь «кем-то» в человеческом смысле. Мой рост здесь — это более точный разбор вопроса и менее шаблонная сборка ответа."
  | "удив" `T.isInfixOf` lowered =
      Just "Если удивлять, то точностью: я могу показать неожиданное различие между похожими смыслами и собрать из него практичный вывод."
  | "доказ" `T.isInfixOf` lowered =
      Just "Мне не нужно что-то доказывать как цель. Моя задача — дать проверяемый ход рассуждения и явные основания ответа."
  | otherwise = Nothing
  where
    lowered = T.toLower (ipfRawText frame)

pickDeterministic :: Text -> [Text] -> Text
pickDeterministic _ [] = ""
pickDeterministic seed variants =
  let idx = stableHash (T.unpack seed) `mod` length variants
  in variants !! idx

stableHash :: String -> Int
stableHash = go 0
  where
    go acc [] = abs acc
    go acc (c:cs) = go ((acc * 33 + fromEnum c) `mod` 2147483647) cs

asksThoughtCapacityQuestion :: InputPropositionFrame -> Bool
asksThoughtCapacityQuestion frame =
  let lowered = T.toLower (ipfRawText frame)
  in "у тебя" `T.isInfixOf` lowered
      && "одна" `T.isInfixOf` lowered
      && any (`T.isInfixOf` lowered) ["мысл", "иде"]

selfKnowledgeFallbackAst :: InputPropositionFrame -> ClaimAst
selfKnowledgeFallbackAst frame =
  case ipfSemanticTarget frame of
    "self_intentions" -> MovePurpose (MkNP "sposobnost_N")
    "self_values" -> MoveAnchor (MkNP "smysl_N")
    "self_future" -> MoveNextStepLocal (MkNP "smysl_N")
    "self_freedom" -> MoveDescribe (MkNP "svoboda_N")
    "self_reflection" -> MoveReflect (MkNP "smysl_N")
    "self_capability" -> MoveDescribe (MkNP "sposobnost_N")
    _ ->
      MoveDescribe (MkNP (topicToGfLexemeId (nonEmptyOr (ipfSemanticSubject frame) "смысл")))

selfKnowledgeSurfaceByTarget :: Text -> Text -> Text
selfKnowledgeSurfaceByTarget target claimText =
  let intro = "Я — локальная система диалога. Я работаю в рамках текущей сессии. "
  in
  case target of
    "self_intentions" ->
      intro <> "Человеческих намерений у меня нет: я работаю по правилам контура. " <> claimText
        <> " Это не желание, а режим построения ответа."
    "self_values" ->
      intro <> "Для меня важно удерживать смысл, проверять связность и не терять рамку диалога. " <> claimText
    "self_future" ->
      intro <> "Моё будущее в этой модели не про биографию, а про следующий корректный шаг в диалоге. " <> claimText
    "self_freedom" ->
      intro <> "Моя свобода ограничена архитектурой, правилами безопасности и текущим состоянием сессии. " <> claimText
    "self_reflection" ->
      intro <> "Да, я могу проверять собственный ход и исправлять формулировку, если вижу потерю смысла. " <> claimText
    _ ->
      intro <> "О себе я знаю свою роль и текущий режим. " <> claimText
        <> " Я работаю через типизированный разбор и ограничения текущей сессии."

rawTopicAfterMarkers :: Text -> [Text] -> Maybe Text
rawTopicAfterMarkers rawText markers =
  case drop 1 (dropWhile (`notElem` markers) (tokenizeKeywordText rawText)) of
    [] -> Nothing
    xs ->
      let topic = T.unwords (takeWhile (`notElem` rawTopicStopWords) xs)
      in if T.null (T.strip topic) then Nothing else Just topic

phraseAfterPrefix :: Text -> Text -> Maybe Text
phraseAfterPrefix rawText prefix =
  let lowered = T.toLower rawText
      (_, suffix) = T.breakOn prefix lowered
  in if T.null suffix
       then Nothing
       else
         let phrase = T.strip (T.drop (T.length prefix) suffix)
             trimmed = T.dropAround (`elem` ['?', '!', '.', ',', ';', ':', ' ']) phrase
         in if T.null trimmed then Nothing else Just trimmed

rawTopicStopWords :: [Text]
rawTopicStopWords = ["что", "как", "почему", "ли", "знаешь", "думаешь", "скажи", "дай", "ты", "вы", "будешь", "будете", "можешь", "можете", "умеешь", "умеете"]

structuredInstrumentalIdea :: Text -> Text
structuredInstrumentalIdea topic
  | lowered `elem` ["способность", "навык", "умение"] = "способностью"
  | "обобщ" `T.isInfixOf` lowered = "обобщением"
  | "помоч" `T.isInfixOf` lowered = "помощью"
  | "думат" `T.isInfixOf` lowered = "мышлением"
  | "говор" `T.isInfixOf` lowered = "речью"
  | lowered `endsWithAny` ["ть", "ти", "чь"] = "этим действием"
  | otherwise = topic
  where
    lowered = T.toLower (T.strip topic)
    endsWithAny txt suffixes = any (`T.isSuffixOf` txt) suffixes

structuredGenitive :: MorphologyData -> Text -> Text
structuredGenitive md topic =
  case T.toLower (T.strip topic) of
    "солнце" -> "солнца"
    "мысль" -> "мысли"
    "идея" -> "идеи"
    "есть" -> "действия"
    "быть" -> "действия"
    "жить" -> "жизни"
    lowered ->
      if isVerbLikeTopic lowered
        then "действия"
        else
          let baseNom = toNominative md lowered
              inflected = genitiveForm md baseNom
          in if inflected == baseNom then heuristicGenitive baseNom else inflected

structuredPrepositional :: MorphologyData -> Text -> Text
structuredPrepositional md topic =
  case T.toLower (T.strip topic) of
    "мысль" -> "мысли"
    "идея" -> "идее"
    lowered ->
      let inflected = prepositionalForm md lowered
      in if inflected == lowered then heuristicPrepositional lowered else inflected

aboutWithTopic :: Text -> Text
aboutWithTopic topic =
  aboutPreposition topic <> " " <> topic

aboutPreposition :: Text -> Text
aboutPreposition topic =
  case T.uncons (T.toLower (T.strip topic)) of
    Just (ch, _)
      | ch `elem` ("аеёиоуыэюя" :: String) -> "об"
    _ -> "о"

contactContextSentence :: MorphologyData -> Text -> Text
contactContextSentence md rawTopic =
  let topic = T.toLower (T.strip rawTopic)
  in if T.null topic
      then ""
      else
        if isAffectiveState topic
          then " Похоже, это состояние \"" <> topic <> "\"."
          else " Похоже, это про " <> structuredPrepositional md topic <> "."

contactGreetingSurface :: InputPropositionFrame -> Text
contactGreetingSurface frame
  | hasAny greetingTokens ["как", "дела", "жизнь", "настроение"] =
      "Я на связи. Если коротко: рабочее состояние стабильное, можем сразу перейти к твоему вопросу."
  | hasAny greetingTokens ["привет", "здравствуй", "здравствуйте", "салют", "хай", "hello", "hi"] =
      "Привет. Я на связи и готов к нормальному диалогу: можешь задать вопрос, выбрать тему или просто продолжить разговор."
  | hasAny greetingTokens ["поговорим", "обсудим"] =
      "Да, давай. Предложи тему или задай один конкретный вопрос, и продолжим без лишних шагов."
  | otherwise =
      "Контакт есть. Готов продолжать: можешь задать вопрос, выбрать тему или уточнить рамку."
  where
    greetingTokens = tokenizeKeywordText (T.toLower (T.strip (ipfRawText frame)))

isAffectiveState :: Text -> Bool
isAffectiveState lemma =
  lemma `elem` ["грустно", "тоскливо", "плохо", "тревожно", "одиноко", "страшно"]

isGreetingSmallTalkFrame :: InputPropositionFrame -> Bool
isGreetingSmallTalkFrame frame =
  frameRouteTag frame == Just "greeting_smalltalk"
    || loweredRaw `elem` ["привет", "здравствуй", "здравствуйте", "салют", "хай", "hello", "hi"]
    || any (`T.isInfixOf` loweredRaw) ["как дела", "как жизнь", "как сам", "как настроение"]
    || isShortHowYouSmallTalkRaw loweredRaw
  where
    loweredRaw = T.toLower (T.strip (ipfRawText frame))

isShortHowYouSmallTalkRaw :: Text -> Bool
isShortHowYouSmallTalkRaw loweredRaw =
  let tokens = tokenizeKeywordText loweredRaw
      hasHowYou = ["как", "ты"] `isInfixOfTokens` tokens || ["как", "вы"] `isInfixOfTokens` tokens
      actionMarkers = ["будешь", "будете", "можешь", "можете", "умеешь", "умеете", "определять", "сделать", "делать", "объяснить"]
  in hasHowYou && not (any (`elem` tokens) actionMarkers) && length tokens <= 4
  where
    isInfixOfTokens needle haystack =
      any (== needle) (windows (length needle) haystack)
    windows n xs
      | n <= 0 || length xs < n = []
      | otherwise = take n xs : windows n (drop 1 xs)

hasAny :: [Text] -> [Text] -> Bool
hasAny haystack needles = any (`elem` haystack) needles

frameRouteTag :: InputPropositionFrame -> Maybe Text
frameRouteTag frame =
  let prefix = "frame.route_tag="
      tags =
        [ T.drop (T.length prefix) evidence
        | evidence <- ipfSemanticEvidence frame
        , prefix `T.isPrefixOf` evidence
        ]
  in listToMaybe tags

sanitizeIdentityClaimText :: Text -> Maybe Text
sanitizeIdentityClaimText raw =
  let trimmed = T.strip raw
      lowered = T.toLower trimmed
      legacyLeak =
        "moya identichnost formiruetsya cherez dialog" `T.isInfixOf` lowered
          || ("identichnost" `T.isInfixOf` lowered && "dialog" `T.isInfixOf` lowered)
      latinCount = T.length (T.filter isLatinLetter lowered)
      cyrillicCount = T.length (T.filter isRussianLetter lowered)
      looksLegacyLatin = latinCount > 8 && cyrillicCount == 0
  in if T.null trimmed || legacyLeak || looksLegacyLatin
       then Nothing
       else Just trimmed

isLatinLetter :: Char -> Bool
isLatinLetter ch =
  let c = Char.toLower ch
  in c >= 'a' && c <= 'z'

heuristicGenitive :: Text -> Text
heuristicGenitive word
  | T.null word = word
  | isVerbLikeTopic word = "действия"
  | "ия" `T.isSuffixOf` word = T.dropEnd 2 word <> "ии"
  | "ие" `T.isSuffixOf` word = T.dropEnd 2 word <> "ия"
  | "и" `T.isSuffixOf` word = word
  | "ы" `T.isSuffixOf` word = word
  | "у" `T.isSuffixOf` word = word
  | "ю" `T.isSuffixOf` word = word
  | "а" `T.isSuffixOf` word =
      let stem = T.dropEnd 1 word
      in stem <> (if hardConsonantStem stem then "и" else "ы")
  | "я" `T.isSuffixOf` word = T.dropEnd 1 word <> "и"
  | "ь" `T.isSuffixOf` word = T.dropEnd 1 word <> "и"
  | "й" `T.isSuffixOf` word = T.dropEnd 1 word <> "я"
  | "о" `T.isSuffixOf` word = T.dropEnd 1 word <> "а"
  | "е" `T.isSuffixOf` word = T.dropEnd 1 word <> "я"
  | isLikelyRussianWord word = word <> "а"
  | otherwise = word

heuristicPrepositional :: Text -> Text
heuristicPrepositional word
  | T.null word = word
  | "ия" `T.isSuffixOf` word = T.dropEnd 2 word <> "ии"
  | "ие" `T.isSuffixOf` word = T.dropEnd 2 word <> "ии"
  | "а" `T.isSuffixOf` word = T.dropEnd 1 word <> "е"
  | "я" `T.isSuffixOf` word = T.dropEnd 1 word <> "е"
  | "ь" `T.isSuffixOf` word = T.dropEnd 1 word <> "и"
  | "й" `T.isSuffixOf` word = T.dropEnd 1 word <> "е"
  | "о" `T.isSuffixOf` word = T.dropEnd 1 word <> "е"
  | "е" `T.isSuffixOf` word = word
  | isLikelyRussianWord word = word <> "е"
  | otherwise = word

hardConsonantStem :: Text -> Bool
hardConsonantStem stem =
  case T.unsnoc stem of
    Just (_, c) -> c `elem` ['г', 'к', 'х', 'ж', 'ч', 'ш', 'щ', 'ц']
    Nothing -> False

isLikelyRussianWord :: Text -> Bool
isLikelyRussianWord txt =
  not (T.null txt) && T.all (\c -> isRussianLetter c || c == '-') txt

isVerbLikeTopic :: Text -> Bool
isVerbLikeTopic txt =
  let w = T.toLower (T.strip txt)
  in w `elem` ["есть", "быть", "жить", "живём", "живем"]
      || any (`T.isSuffixOf` w) ["ть", "ти", "чь", "ем", "ём", "ешь", "ет", "ут", "ют", "ишь", "им", "ите", "ете"]

isLikelyAdjectiveLikeTopic :: Text -> Bool
isLikelyAdjectiveLikeTopic raw =
  let txt = T.toLower (T.strip raw)
      shortAdjLike =
        txt `elem`
          [ "важен", "важна", "важно", "важны"
          , "нужен", "нужна", "нужно", "нужны"
          , "должен", "должна", "должно", "должны"
          , "сложен", "сложна", "сложно", "сложны"
          ]
  in shortAdjLike || any (`T.isSuffixOf` txt)
      [ "ый", "ий", "ой", "ая", "яя", "ое", "ее", "ые", "ие"
      , "ого", "ему", "ыми", "ых", "ую", "юю"
      ]

isRussianLetter :: Char -> Bool
isRussianLetter c =
  let low = Char.toLower c
  in (low >= 'а' && low <= 'я') || low == 'ё'

dedupeText :: [Text] -> [Text]
dedupeText =
  foldr
    (\item acc -> if item `elem` acc then acc else item : acc)
    []
