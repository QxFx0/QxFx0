{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.ResponsePlan
  ( responsePlanTests
  ) where

import Test.HUnit
import Data.Aeson (decode, encode)
import qualified Data.Map.Strict as M
import Data.Maybe (maybeToList)
import qualified Data.Text as T
import System.Directory (doesFileExist)

import QxFx0.Core.Guard
  ( GuardSurface(..)
  , QualityVerdict(..)
  , RenderSegment(..)
  , RenderSegmentKind(..)
  , SafetyStatus(..)
  , evaluateContentQualityWithTopic
  , postRenderSafetyCheckSurface
  )
import QxFx0.Core.TurnLegitimacy (finalizeOutputWithTopic)
import QxFx0.Semantic.ResponsePlan
  ( buildGenerativeResponsePlan
  , buildGenerativeResponsePlanWithActiveQuestion
  , buildResponseSemanticPlan
  , buildResponseSemanticPlanWithActiveQuestion
  , isGenerativeRequestText
  , renderResponseSemanticPlan
  , responsePlanQualityIssues
  )
import QxFx0.Semantic.ResponsePlan.GF (responsePlanToGfExpr, semanticPropositionToGfExpr)
import QxFx0.Lexicon.Generated.SemanticSlots
  ( arguedLeafSlotCount
  , curatedPredicateSlotCount
  , lookupArguedLeafConstructor
  )
import qualified QxFx0.Runtime.PGF as RuntimePGF
import QxFx0.Types (AssemblyPath(..), AuthorityClass(..), GfLinearizationResult(..), SurfaceProvenance(..))
import QxFx0.Semantic.Content.Argued (arguedPredicates, dutyPreds, freedomPreds, justicePreds)
import QxFx0.Semantic.ContentSelector.Types (ContentSelector(..), emptyContentSelector)
import QxFx0.Semantic.Frame.Types
  ( FrameAuthority(..)
  , FrameDepth(..)
  , FrameScope(..)
  , FrameStrength(..)
  , SemanticFrame(..)
  )
import QxFx0.Semantic.Intent.Classifier (SemanticIntent(..))
import QxFx0.Self.Field (emptyField)
import QxFx0.Types.Semantic.Content (PredicateRole(..), SemanticPredicate(..))
import QxFx0.Types.Semantic.ResponsePlan
import QxFx0.Types.Semantic.SurfaceRealizer

responsePlanTests :: [Test]
responsePlanTests =
  [ TestLabel "generative request without topic asks for topic" testNoTopic
  , TestLabel "unknown explicit generative topic is governed" testUnknownExplicitTopic
  , TestLabel "thought experiment request is generative" testThoughtExperimentRequest
  , TestLabel "response plan grounds a counterpoint" testCounterpoint
  , TestLabel "response plan returns to the active dialogue question" testActiveQuestionNextMove
  , TestLabel "bounded composer covers core dialogue acts" testPlanCorpus
  , TestLabel "response plan renders epistemic status" testPlanRendering
   , TestLabel "response plan survives JSON round trip" testPlanRoundTrip
   , TestLabel "curated response plan maps to generator-owned GF slots" testGfSlotAdapter
   , TestLabel "unmapped response plan cannot enter GF" testGfSlotAdapterRejectsUnmapped
    , TestLabel "curated GF slot catalog covers the definition corpus baseline" testDefinitionCorpusGfCoverage
    , TestLabel "curated response plan linearizes through compiled GF" testGfPlanLinearization
    , TestLabel "argued freedom plan linearizes through compiled GF" testArguedFreedomPlanGfLinearization
     , TestLabel "argued duty GF surface passes exact GuardSurface pipeline" testArguedDutyPlanGfGuardSurface
     , TestLabel "argued leaf overlay exhaustively covers literal leaves" testArguedLeafOverlayCoverage
     , TestLabel "argued leaves linearize through compiled GF" testArguedLeafGfLinearization
     , TestLabel "GF catalog closes corpus smoke fallback surfaces" testCorpusSmokeFallbackSurfaceCoverage
     , TestLabel "cataloged argued question leaves preserve their exact question mark" testCatalogedQuestionLeafPreserved
  , TestLabel "invalid plan is rejected" testPlanAdmission
  , TestLabel "surface realizer cannot drop approved claim" testRealizerContract
  , TestLabel "surface realizer cannot add claim refs" testRealizerCannotAddClaim
  , TestLabel "old generic generative paragraph is blocked" testGenericParagraphBlocked
  , TestLabel "adjacent discourse markers are blocked" testRepeatedMarkersBlocked
  ]

testNoTopic :: Test
testNoTopic = TestCase $ do
  let plan = buildGenerativeResponsePlan emptyContentSelector emptyField "придумай логичный тезис" Nothing
  assertEqual "missing topic must be explicit" (Just NoTopicProvided) (rspFallbackReason plan)
  assertEqual "fallback must ask for a topic"
    "Укажи тему, и я сформулирую тезис из доступных смысловых оснований."
     (renderResponseSemanticPlan plan)

testUnknownExplicitTopic :: Test
testUnknownExplicitTopic = TestCase $ do
  let input = "придумай логичный тезис о кванторном тумане"
      plan = buildGenerativeResponsePlan emptyContentSelector emptyField input Nothing
  assertBool "raw generation shape must be recognized" (isGenerativeRequestText input)
  assertEqual "uncovered explicit topic must not receive a generic thesis"
    (Just TopicNotCovered)
    (rspFallbackReason plan)

testThoughtExperimentRequest :: Test
testThoughtExperimentRequest = TestCase $
  assertBool "thought experiment must reach the governed generative path"
    (isGenerativeRequestText "придумай мысленный эксперимент о свободе")

testCounterpoint :: Test
testCounterpoint = TestCase $ do
  let predicate = SemanticPredicate
        RoleProperty
        "свобода предполагает возможность выбора"
        "freedom presupposes the possibility of choice"
        "свобода"
        Nothing
        Nothing
        (Just "свобода ограничена ответственностью")
        Nothing
      selector = emptyContentSelector
        { csTopicPredicates = M.singleton "свобода" [predicate] }
      plan = buildGenerativeResponsePlan selector emptyField "придумай тезис о свободе" Nothing
  assertEqual "counterpoint must remain grounded in curated predicate material"
    (Just "свобода ограничена ответственностью")
    (pcText <$> rspCounterpoint plan)
  assertBool "counterpoint must remain a question, not a new factual claim"
    (maybe False ((== ClaimQuestion) . pcMode) (rspCounterpoint plan))
  assertBool "rendered plan must expose its countercheck"
    ("Контрпроверка:" `T.isInfixOf` renderResponseSemanticPlan plan)

testActiveQuestionNextMove :: Test
testActiveQuestionNextMove = TestCase $ do
  let predicate = SemanticPredicate
        RoleProperty
        "свобода предполагает возможность выбора"
        "freedom presupposes the possibility of choice"
        "свобода"
        Nothing Nothing Nothing Nothing
      selector = emptyContentSelector
        { csTopicPredicates = M.singleton "свобода" [predicate] }
      plan = buildGenerativeResponsePlanWithActiveQuestion
        selector emptyField "придумай тезис о свободе" Nothing
        (Just "Какая свобода совместима с ответственностью?")
  assertEqual "the current dialogue question must take precedence over generic next moves"
    (Just "вернуться к открытому вопросу: «Какая свобода совместима с ответственностью?»")
    (rspNextMove plan)

testPlanRendering :: Test
testPlanRendering = TestCase $ do
  let claim = PlannedClaim "claim-1" ClaimHypothetical "свобода предполагает возможность выбора" ["свобода предполагает возможность выбора"] EvidenceSelectedPredicate 0.8
      plan = planWith claim (Just "свобода")
        [PropositionPredicate "" "свобода предполагает возможность выбора" ""]
        Nothing
        (Just "проверить тезис на контрпример")
      rendered = renderResponseSemanticPlan plan
  assertBool "rendered response must expose thesis" ("Тезис:" `T.isInfixOf` rendered)
  assertBool "rendered response must expose next move" ("Следующий ход:" `contains` rendered)
  assertEqual "valid plan has no quality issues" [] (responsePlanQualityIssues plan)
  where
     contains needle haystack = needle `elem` T.words haystack || needle `T.isInfixOf` haystack

testPlanRoundTrip :: Test
testPlanRoundTrip = TestCase $ do
  let claim = PlannedClaim "claim-1" ClaimHypothetical "тезис" ["predicate"] EvidenceSelectedPredicate 0.7
      plan = planWith claim (Just "тема") [PropositionPredicate "" "тезис" ""] Nothing Nothing
  assertEqual "versioned response plan must decode after encoding"
    (Just plan)
    (decode (encode plan))

testGfSlotAdapter :: Test
testGfSlotAdapter = TestCase $ do
  let predicate = PropositionPredicate "свобода" "предполагает" "возможность выбора"
      plan = planWith
        (PlannedClaim "claim-1" ClaimKnown "свобода предполагает возможность выбора" ["свобода предполагает возможность выбора"] EvidenceCuratedPredicate 0.9)
        (Just "свобода")
        [predicate, PropositionQuestion predicate]
        Nothing
        Nothing
      statementPlan = plan { rspPropositions = [predicate, PropositionConjunction predicate predicate] }
  assertEqual "exact curated predicate must resolve to GF constructors"
    (Right "MkSemanticPredicate SubjectSvoboda RelationPredpolagaet ObjectVozmozhnostVybora")
    (semanticPropositionToGfExpr predicate)
  assertEqual "nested plan structure must remain typed in the GF expression"
    (Right "MoveFromDiscourse (DiscourseSequence (DiscourseThesis (MkSemanticPredicate SubjectSvoboda RelationPredpolagaet ObjectVozmozhnostVybora)) (DiscourseCheck (MkSemanticPredicate SubjectSvoboda RelationPredpolagaet ObjectVozmozhnostVybora)))")
    (responsePlanToGfExpr plan)
  assertEqual "other top-level propositions must remain discourse statements"
    (Right "MoveFromDiscourse (DiscourseSequence (DiscourseThesis (MkSemanticPredicate SubjectSvoboda RelationPredpolagaet ObjectVozmozhnostVybora)) (DiscourseStatement (PropositionConjunction (MkSemanticPredicate SubjectSvoboda RelationPredpolagaet ObjectVozmozhnostVybora) (MkSemanticPredicate SubjectSvoboda RelationPredpolagaet ObjectVozmozhnostVybora))))")
    (responsePlanToGfExpr statementPlan)

testGfSlotAdapterRejectsUnmapped :: Test
testGfSlotAdapterRejectsUnmapped = TestCase $
  assertBool "GF adapter must not inject an unmapped predicate as raw text"
    (case semanticPropositionToGfExpr (PropositionPredicate "" "неизвестный предикат" "") of
       Left "unmapped_curated_predicate:неизвестный предикат" -> True
       _ -> False)

testDefinitionCorpusGfCoverage :: Test
testDefinitionCorpusGfCoverage = TestCase $
  assertEqual "the definition corpus baseline plus corpus-smoke primary slots must remain cataloged" 71 curatedPredicateSlotCount

testGfPlanLinearization :: Test
testGfPlanLinearization = TestCase $ do
  let predicate = PropositionPredicate "свобода" "предполагает" "возможность выбора"
      plan = planWith
        (PlannedClaim "claim-1" ClaimKnown "свобода предполагает возможность выбора" ["свобода предполагает возможность выбора"] EvidenceCuratedPredicate 0.9)
        (Just "свобода")
        [predicate]
        Nothing
        Nothing
      pgfPath = "spec/gf/QxFx0Syntax.pgf"
  exists <- doesFileExist pgfPath
  assertBool "generated PGF must be present for the GF plan contract" exists
  result <- RuntimePGF.linearizeResponseSemanticPlanGf (Just pgfPath) plan
  case result of
    Left err -> assertFailure ("GF plan linearization failed: " <> T.unpack err)
    Right rendered -> do
      assertEqual "response plans use canonical PGF rather than the Russian compatibility shim"
        AuthorityCanonical
        (glrAuthorityClass rendered)
      assertEqual "GF must realize the generated curated predicate slots"
        "Тезис: свобода предполагает возможность выбора."
        (glrText rendered)

testArguedFreedomPlanGfLinearization :: Test
testArguedFreedomPlanGfLinearization = TestCase $ do
  let selector = emptyContentSelector { csTopicPredicates = M.singleton "свобода" [head freedomPreds] }
      frame = DefinitionFrame "свобода" GeneralScope Known
      input = "что такое свобода?"
      pgfPath = "spec/gf/QxFx0Syntax.pgf"
      expectedSurface =
        "Тезис: свобода предполагает возможность выбора. "
          <> "Контрпункт: не любой выбор свободен: выбор под принуждением, страхом или незнанием не делает действие свободным. "
          <> "Следствие: свобода требует осознанности — только выбор, понятый как свой, превращает возможность в свободу. "
          <> "Проверка: верно ли это?"
  case buildResponseSemanticPlanWithActiveQuestion
         selector emptyField input Nothing (Just input) frame (IntentDefine "свобода") of
    Nothing -> assertFailure "argued freedom must build a response plan"
    Just plan -> do
      assertEqual "the active user question remains a dialogue obligation"
        (Just (ObligationContinue input))
        (rspObligation plan)
      result <- RuntimePGF.linearizeResponseSemanticPlanGf (Just pgfPath) plan
      case result of
        Left err -> assertFailure ("argued freedom GF plan linearization failed: " <> T.unpack err)
        Right rendered -> do
          assertEqual "argued freedom must use canonical PGF authority"
            AuthorityCanonical
            (glrAuthorityClass rendered)
          assertEqual "argued freedom must use the plan PGF route"
            PgfClaimRoute
            (glrAssemblyPath rendered)
          assertEqual "argued freedom must not require a GF fallback"
            Nothing
            (glrFallbackReason rendered)
          assertEqual "argued freedom GF surface must remain deterministic"
            expectedSurface
            (glrText rendered)

testArguedDutyPlanGfGuardSurface :: Test
testArguedDutyPlanGfGuardSurface = TestCase $ do
  let selector = emptyContentSelector { csTopicPredicates = M.singleton "долг" dutyPreds }
      frame = DefinitionFrame "долг" GeneralScope Known
      input = "что такое долг?"
      localRecovery =
        "Я удержу только устойчивую часть ответа и не буду достраивать непроверенные выводы."
      expectedSurface =
        "Тезис: долг предписывает действие независимо от желания. "
          <> "Контрпункт: долг, лишённый внутреннего согласия, превращается в принуждение — и перестаёт быть моральным. "
          <> "Следствие: зрелый долг — не подчинение внешнему правилу, а принятие правила как своего. "
          <> "Проверка: верно ли это?"
  case buildResponseSemanticPlanWithActiveQuestion
         selector emptyField input Nothing (Just input) frame (IntentDefine "долг") of
    Nothing -> assertFailure "argued duty must build a response plan"
    Just plan -> do
      result <- RuntimePGF.linearizeResponseSemanticPlanGf (Just "spec/gf/QxFx0Syntax.pgf") plan
      case result of
        Left err -> assertFailure ("argued duty GF plan linearization failed: " <> T.unpack err)
        Right rendered -> do
          assertEqual "argued duty GF surface must remain deterministic"
            expectedSurface
            (glrText rendered)
          let preSafetyText = glrText rendered <> "\n" <> localRecovery
              preSafetySurface =
                GuardSurface
                  { gsRenderedText = preSafetyText
                  , gsSegments =
                      [ RenderSegment SegmentTemplate (glrText rendered)
                      , RenderSegment SegmentLocalRecovery localRecovery
                      ]
                  , gsQuestionLike = False
                  }
              (guardedSurface, provenance) =
                finalizeOutputWithTopic preSafetySurface [] "долг"
          assertEqual "exact argued duty GuardSurface must pass structural safety"
            InvariantOK
            (postRenderSafetyCheckSurface preSafetySurface [])
          assertEqual "exact argued duty GuardSurface must pass content quality"
            QualityPass
            (evaluateContentQualityWithTopic "долг" preSafetyText)
          assertEqual "exact argued duty GuardSurface must retain canonical provenance"
            FromDB
            provenance
          assertEqual "exact argued duty GuardSurface must not be replaced by recovery"
            preSafetyText
            (gsRenderedText guardedSurface)

testArguedLeafOverlayCoverage :: Test
testArguedLeafOverlayCoverage = TestCase $ do
  let leaves = arguedLeaves
  assertEqual "every hand-authored counter and synthesis leaf must be cataloged"
    74
    (length leaves)
  assertEqual "the generated overlay must contain every argued leaf"
    (length leaves)
    arguedLeafSlotCount
  mapM_ assertMapped leaves
  case semanticPropositionToGfExpr (PropositionPredicate "" " не любой выбор свободен: выбор под принуждением, страхом или незнанием не делает действие свободным" "") of
    Left _ -> pure ()
    Right constructor -> assertFailure ("argued leaf lookup must not normalize source text: " <> T.unpack constructor)
  where
    assertMapped leaf = do
      constructor <- case lookupArguedLeafConstructor leaf of
        Nothing -> assertFailure ("missing exact argued leaf: " <> T.unpack leaf) >> pure ""
        Just value -> pure value
      assertEqual "GF adapter must use the generated typed leaf constructor"
        (Right constructor)
        (semanticPropositionToGfExpr (PropositionPredicate "" leaf ""))

testArguedLeafGfLinearization :: Test
testArguedLeafGfLinearization = TestCase $ do
  let pgfPath = "spec/gf/QxFx0Syntax.pgf"
  exists <- doesFileExist pgfPath
  assertBool "generated PGF must be present for argued leaf coverage" exists
  cache <- RuntimePGF.newPgfCache
  mapM_ (assertLinearizes cache pgfPath) arguedLeaves
  where
    assertLinearizes cache pgfPath leaf = do
      let claim = PlannedClaim "argued-leaf" ClaimKnown leaf [leaf] EvidenceCuratedPredicate 1
          plan = planWith claim Nothing [PropositionPredicate "" leaf ""] Nothing Nothing
      result <- RuntimePGF.linearizeResponseSemanticPlanGfWithCache cache (Just pgfPath) plan
      case result of
        Left err -> assertFailure ("argued leaf GF linearization failed: " <> T.unpack leaf <> ": " <> T.unpack err)
        Right rendered -> do
          assertEqual "argued leaf must use canonical PGF authority" AuthorityCanonical (glrAuthorityClass rendered)
          assertEqual "compiled GF must preserve the exact curated leaf"
            (expectedThesisSurface leaf)
             (glrText rendered)

testCorpusSmokeFallbackSurfaceCoverage :: Test
testCorpusSmokeFallbackSurfaceCoverage = TestCase $ do
  mapM_ assertPrimary primarySurfaces
  assertEqual "the argued justice counter must retain its typed leaf constructor"
    (Right "ArguedCounterJustice1Counter")
    (semanticPropositionToGfExpr (PropositionPredicate "" justiceQuestionLeaf ""))
  cache <- RuntimePGF.newPgfCache
  mapM_ (assertLinearizes cache) (map fst primarySurfaces <> [justiceQuestionLeaf])
  where
    assertPrimary (surface, expected) =
      assertEqual ("selected primary must use explicit slots: " <> T.unpack surface)
        (Right expected)
        (semanticPropositionToGfExpr (PropositionPredicate "" surface ""))

    primarySurfaces =
      [ ( "долг предписывает действие независимо от желания"
        , "MkSemanticPredicate SubjectDolg RelationPredpisyvaet ObjectDeystvieNezavisimo"
        )
      , ( "страх указывает на то, что имеет значение"
        , "MkSemanticPredicate SubjectStrah RelationUkazyvaet ObjectNaToChtoImeetZnachenie"
        )
      , ( "произвол выражает отсутствие ограничений"
        , "MkSemanticPredicate SubjectProizvol RelationVyrazhaet ObjectOtsutstvieOgranicheniy"
        )
      , ( "воля это способность человека сознательно управлять своим поведением"
        , "MkSemanticPredicate SubjectVolya RelationEto ObjectSposobnostChelovekaSoznatelnoUpravlyatPovedeniem"
        )
      , ( "правда претендует на соответствие фактам"
        , "MkSemanticPredicate SubjectPravda RelationPretenduet ObjectNaSootvetstvieFaktam"
        )
      , ( "память это процесс запоминания хранения и воспроизведения информации"
        , "MkSemanticPredicate SubjectPamyat RelationEto ObjectProtsessZapominaniyaHraneniyaIVosproizvedeniyaInformatsii"
        )
      , ( "воспоминание восстанавливает пережитое в новой рамке"
        , "MkSemanticPredicate SubjectVospominanie RelationVosstanavlivaet ObjectPerezhitoeVNovoyRamke"
        )
      , ( "сознание это способность осознавать окружающий мир и самого себя"
        , "MkSemanticPredicate SubjectSoznanie RelationEto ObjectSposobnostOsoznavatOkruzhayushchiyMirISamogoSebya"
        )
      , ( "самосознание выражает рефлексивность субъекта"
        , "MkSemanticPredicate SubjectSamosoznanie RelationVyrazhaet ObjectRefleksivnostSubekta"
        )
      ]

    justiceQuestionLeaf =
      "соразмерность трудно измерить: как взвесить страдание или измерить ущерб намерению?"

    assertLinearizes cache surface = do
      let claim = PlannedClaim "corpus-smoke" ClaimKnown surface [surface] EvidenceCuratedPredicate 1
          plan = planWith claim Nothing [PropositionPredicate "" surface ""] Nothing Nothing
      result <- RuntimePGF.linearizeResponseSemanticPlanGfWithCache cache (Just "spec/gf/QxFx0Syntax.pgf") plan
      case result of
        Left err -> assertFailure ("corpus smoke surface must linearize through GF: " <> T.unpack surface <> ": " <> T.unpack err)
        Right rendered -> do
          assertEqual "corpus smoke surface must use canonical GF authority" AuthorityCanonical (glrAuthorityClass rendered)
          assertEqual "compiled GF must preserve the cataloged source surface"
            (expectedThesisSurface surface)
            (glrText rendered)

expectedThesisSurface :: T.Text -> T.Text
expectedThesisSurface surface =
  let terminal = T.takeEnd 1 (T.stripEnd surface)
      suffix = if terminal `elem` [".", "!", "?"] then "" else "."
  in "Тезис: " <> surface <> suffix

testCatalogedQuestionLeafPreserved :: Test
testCatalogedQuestionLeafPreserved = TestCase $ do
  let selector = emptyContentSelector { csTopicPredicates = M.singleton "справедливость" justicePreds }
      frame = DefinitionFrame "справедливость" GeneralScope Known
  case buildResponseSemanticPlan selector emptyField "что такое справедливость?" Nothing frame (IntentDefine "справедливость") of
    Nothing -> assertFailure "argued justice must build a response plan"
    Just plan -> do
      assertBool "the planned counterpoint must retain its cataloged question mark"
        (PropositionContrast
          (PropositionPredicate "" "справедливость требует соразмерности между деянием и воздаянием" "")
          (PropositionPredicate "" "соразмерность трудно измерить: как взвесить страдание или измерить ущерб намерению?" "")
          `elem` rspPropositions plan)
      assertBool "the plan must remain GF-addressable through the exact argued leaf"
        (case responsePlanToGfExpr plan of
           Right expression -> "ArguedCounterJustice1Counter" `T.isInfixOf` expression
           Left _ -> False)

arguedLeaves :: [T.Text]
arguedLeaves =
  [ leaf
  | (_, predicates) <- arguedPredicates
  , predicate <- predicates
  , leaf <- maybeToList (spCounter predicate) <> maybeToList (spSynthesis predicate)
  ]

testPlanAdmission :: Test
testPlanAdmission = TestCase $ do
  let plan = planWith
        (PlannedClaim "claim-1" ClaimHypothetical "" [] EvidenceNone 2)
        (Just "свобода") [] Nothing Nothing
  assertBool "invalid plan must fail admission" (not (responsePlanIsAdmissible plan))
  assertBool "quality issue must be visible" ("plan_not_admissible" `elem` responsePlanQualityIssues plan)

testRealizerContract :: Test
testRealizerContract = TestCase $ do
  let claim = PlannedClaim "claim-1" ClaimHypothetical "тезис" ["predicate"] EvidenceSelectedPredicate 0.7
      plan = planWith claim (Just "тема") [PropositionPredicate "" "тезис" ""] Nothing Nothing
      request = SurfaceRealizerRequest "ru" plan [] [] 500
      response = SurfaceRealizerResponse "текст" [] [] "ru"
  assertBool "realizer must include every approved claim reference" (not (surfaceResponseIsAdmissible request response))

testRealizerCannotAddClaim :: Test
testRealizerCannotAddClaim = TestCase $ do
  let claim = PlannedClaim "claim-1" ClaimHypothetical "тезис" ["predicate"] EvidenceSelectedPredicate 0.7
      plan = planWith claim (Just "тема") [PropositionPredicate "" "тезис" ""] Nothing Nothing
      request = SurfaceRealizerRequest "ru" plan [] [] 500
      response = SurfaceRealizerResponse "текст" ["claim-1", "unapproved-claim"] [] "ru"
  assertBool "realizer must reject unapproved claim references"
    (not (surfaceResponseIsAdmissible request response))

testGenericParagraphBlocked :: Test
testGenericParagraphBlocked = TestCase $
  assertEqual "generic generative paragraph must be blocked"
    (QualityBlock "generic_generative_paragraph")
    (evaluateContentQualityWithTopic "мысль" "Одна мысль: смысл. Другая мысль: различие.")

testRepeatedMarkersBlocked :: Test
testRepeatedMarkersBlocked = TestCase $
  assertEqual "adjacent discourse markers must be blocked"
    (QualityBlock "repeated_discourse_marker")
    (evaluateContentQualityWithTopic "жизнь" "Но вместе с тем жизнь требует уточнения.")

planWith :: PlannedClaim -> Maybe T.Text -> [SemanticProposition] -> Maybe PlannedClaim -> Maybe T.Text -> ResponseSemanticPlan
planWith claim topic propositions counterpoint nextMove = ResponseSemanticPlan
  { rspVersion = responsePlanVersion
  , rspGoal = GoalGenerateThesis
  , rspTopic = topic
  , rspClaims = [claim]
  , rspPropositions = propositions
  , rspCounterpoint = counterpoint
  , rspObligation = Nothing
  , rspNextMove = nextMove
  , rspDerivation = []
  , rspFallbackReason = Nothing
  , rspDiscourse = DiscoursePlan DiscourseQualification (Just "Ограничение") 3
  }

testPlanCorpus :: Test
testPlanCorpus = TestCase $ do
  let freedom = predicate "свобода" "свобода предполагает возможность выбора" (Just "свобода ограничена ответственностью")
      responsibility = predicate "ответственность" "ответственность связывает выбор с последствиями" Nothing
      selector = emptyContentSelector
        { csTopicPredicates = M.fromList
            [ ("свобода", [freedom])
            , ("ответственность", [responsibility])
            ]
        }
      cases =
        [ ( "define"
          , "что такое свобода?"
          , DefinitionFrame "свобода" GeneralScope Known
          , IntentDefine "свобода"
          , GoalDefine
          )
        , ( "explain"
          , "объясни свободу"
          , GroundFrame "свобода" Shallow
          , IntentGround "свобода"
          , GoalExplain
          )
        , ( "compare"
          , "сравни свободу и ответственность"
          , DistinctionFrame "свобода" "ответственность" []
          , IntentDistinguish "свобода" "ответственность"
          , GoalCompare
          )
        , ( "objection"
          , "я возражаю против свободы"
          , ChallengeFrame "свобода" "возражение" Soft "я возражаю"
          , IntentChallenge
          , GoalChallenge
          )
        , ( "clarify"
          , "уточни свободу"
          , GroundFrame "свобода" Shallow
          , IntentUnknown "уточни свободу"
          , GoalClarify
          )
        , ( "generate"
          , "придумай тезис о свободе"
          , ExploratoryFrame
          , IntentExploratory
          , GoalGenerateThesis
          )
        ]
  mapM_ (assertPlanCase selector) cases
  where
    predicate topic surface counter = SemanticPredicate
      RoleProperty surface surface topic Nothing Nothing counter Nothing
    assertPlanCase selector (label, input, frame, intent, expectedGoal) =
      case buildResponseSemanticPlan selector emptyField input Nothing frame intent of
        Nothing -> assertFailure (label <> " must produce a plan")
        Just plan -> do
          assertEqual (label <> " goal") expectedGoal (rspGoal plan)
          assertBool (label <> " must be admissible") (responsePlanIsAdmissible plan)
          assertBool (label <> " must retain typed propositions") (not (null (rspPropositions plan)))
          assertBool (label <> " must retain bounded derivation") (length (rspDerivation plan) <= 8)
