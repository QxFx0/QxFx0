{-# LANGUAGE OverloadedStrings #-}
module Test.Suite.DialogueSemanticSelection
  ( dialogueSemanticSelectionTests
  , dialogueSemanticSelectionRegressionTests
  ) where

import Test.HUnit
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import qualified Data.Vector as V

import QxFx0.Render.Dialogue
  ( generateFromFrame
  , formatSelectedPredicates
  , appendSupplement
  , semanticSupplement
  , frameSupplement
  )
import QxFx0.Semantic.SurfaceAccumulator (VerbalizationMode(..))
import QxFx0.Semantic.Content.Base (mkPred, PredicateRole(..))
import QxFx0.Semantic.Network (emptySemanticNetwork, spreadingActivationActive)
import QxFx0.Semantic.Network.Types (SemanticNetwork(..), SemanticEdge(..), EdgeSource(..))
import QxFx0.Semantic.ContentSelector
  ( ContentSelector(..)
  , buildContentSelector
  , emptyContentSelector
  , SelectedPredicate(..)
  , selectPredicates
  )
import QxFx0.Semantic.Content (SemanticPredicate(..))
import QxFx0.Semantic.Space.Types
  ( SemanticSpace(..)
  , DimensionPrototype(..)
  , FieldDimension(..)
  , emptySemanticSpace
  )
import QxFx0.Semantic.Content.AtomStore (AtomGraph, seedGraph)
import QxFx0.Self.Field
  ( Field
  , emptyField
  , fieldResonance
  , fieldConfidence
  , fieldConsolidation
  , Resonance(..)
  , FieldConfidence(..)
  , Consolidation(..)
  )
import QxFx0.Types.State.System (SystemState, emptySystemState)
import QxFx0.Types (MorphologyData(..))
import qualified QxFx0.Semantic.Frame.Types as FT

emptyMorphologyData :: MorphologyData
emptyMorphologyData = MorphologyData M.empty M.empty M.empty M.empty

-- | Build a ContentSelector that covers a single topic with one predicate.
mkTestSelector :: Text -> Text -> Text -> ContentSelector
mkTestSelector topic ruText enText =
  let atoms = S.fromList ["связана", "субъекта", "действие"]
      space = emptySemanticSpace
        { ssDimensionCount = 3
        , ssAtomIndex = M.fromList [("связана", 0), ("субъекта", 1), ("действие", 2)]
        , ssPrototypes = M.fromList
            [ (FdResonance, DimensionPrototype FdResonance (S.fromList ["связана"]) (V.fromList [1.0, 0.0, 0.0]))
            , (FdConfidence, DimensionPrototype FdConfidence (S.fromList ["субъекта"]) (V.fromList [0.0, 1.0, 0.0]))
            , (FdConsolidation, DimensionPrototype FdConsolidation (S.fromList ["действие"]) (V.fromList [0.0, 0.0, 1.0]))
            ]
        }
      topicAtoms = M.singleton topic atoms
      topicPreds = M.singleton topic [mkPred RoleProperty ruText enText]
  in buildContentSelector space topicAtoms topicPreds M.empty

testField :: Field
testField = emptyField
  { fieldResonance = Resonance 1.0
  , fieldConfidence = FieldConfidence 1.0
  , fieldConsolidation = Consolidation 1.0
  }

runFrame :: FT.SemanticFrame -> ContentSelector -> T.Text
runFrame frame cs =
  generateFromFrame cs testField Nothing seedGraph emptySystemState frame emptyMorphologyData

-- | Network with a single explicit edge used to exercise spreading activation.
-- The edge connects the atom shared by the seed topic to the atom shared by a
-- related topic, so composeFromActivation can surface the related predicate.
testNetwork :: SemanticNetwork
testNetwork = emptySemanticNetwork
  { snNodes = S.fromList ["связана", "субъекта"]
  , snEdges = M.singleton ("связана", "субъекта") (SemanticEdge "связана" "субъекта" 1.0 1 ExplicitEdge)
  }

-- | Run a frame with a supplied semantic network.
runFrameWithNetwork :: FT.SemanticFrame -> ContentSelector -> SemanticNetwork -> T.Text
runFrameWithNetwork frame cs net =
  generateFromFrame cs testField (Just net) seedGraph emptySystemState frame emptyMorphologyData

-- | Semantic space that matches the atoms used by mkTestSelector, reused for
-- spreading-activation selectors so that predicate scoring succeeds.
testSpace :: SemanticSpace
testSpace =
  emptySemanticSpace
    { ssDimensionCount = 3
    , ssAtomIndex = M.fromList [("связана", 0), ("субъекта", 1), ("действие", 2)]
    , ssPrototypes = M.fromList
        [ (FdResonance, DimensionPrototype FdResonance (S.fromList ["связана"]) (V.fromList [1.0, 0.0, 0.0]))
        , (FdConfidence, DimensionPrototype FdConfidence (S.fromList ["субъекта"]) (V.fromList [0.0, 1.0, 0.0]))
        , (FdConsolidation, DimensionPrototype FdConsolidation (S.fromList ["действие"]) (V.fromList [0.0, 0.0, 1.0]))
        ]
    }

-- | Build a ContentSelector where the seed topic has no predicates but a
-- network-connected topic does, so spreading activation can yield predicates.
mkSpreadingSelector :: ContentSelector
mkSpreadingSelector =
  let atomsLogic = S.fromList ["связана"]
      atomsThought = S.fromList ["субъекта"]
      topicAtoms = M.fromList [("логика", atomsLogic), ("мышление", atomsThought)]
      pThought = mkPred RoleProperty "связана с субъекта действие" "connected to subject action"
      topicPreds = M.fromList [("мышление", [pThought])]
  in buildContentSelector testSpace topicAtoms topicPreds M.empty

-- | Build a ContentSelector with topic atoms but no predicates, so
-- composeFromActivation returns an empty list and the fallback path is taken.
mkEmptySpreadingSelector :: ContentSelector
mkEmptySpreadingSelector =
  let atomsLogic = S.fromList ["связана"]
      atomsThought = S.fromList ["субъекта"]
      topicAtoms = M.fromList [("логика", atomsLogic), ("мышление", atomsThought)]
  in buildContentSelector testSpace topicAtoms M.empty M.empty

dialogueSemanticSelectionTests :: [Test]
dialogueSemanticSelectionTests =
  [ TestLabel "formatSelectedPredicates empty list returns empty text" testFormatSelectedPredicatesEmpty
  , TestLabel "formatSelectedPredicates returns English text joined by period" testFormatSelectedPredicatesEnglish
  , TestLabel "formatSelectedPredicates returns Russian text joined by period" testFormatSelectedPredicatesRussian
  , TestLabel "appendSupplement identity on empty supplement" testAppendSupplementEmpty
  , TestLabel "appendSupplement appends both parts" testAppendSupplementNonEmpty
  , TestLabel "GroundFrame shallow preserves template with empty selector" testGroundFrameEmpty
  , TestLabel "GroundFrame shallow enriches with selected predicate" testGroundFrameEnriched
  , TestLabel "GroundFrame detailed preserves template with empty selector" testGroundFrameDetailedEmpty
  , TestLabel "GroundFrame detailed enriches with selected predicate" testGroundFrameDetailedEnriched
  , TestLabel "LearnFrame shallow preserves template with empty selector" testLearnFrameEmpty
  , TestLabel "LearnFrame shallow enriches with selected predicate" testLearnFrameEnriched
  , TestLabel "HelpFrame preserves template with empty selector" testHelpFrameEmpty
  , TestLabel "HelpFrame enriches with selected predicate" testHelpFrameEnriched
  , TestLabel "PurposeFrame preserves template with empty selector" testPurposeFrameEmpty
  , TestLabel "PurposeFrame enriches with selected predicate" testPurposeFrameEnriched
  , TestLabel "WorldCauseFrame preserves template with empty selector" testWorldCauseFrameEmpty
  , TestLabel "WorldCauseFrame enriches with selected predicate" testWorldCauseFrameEnriched
  , TestLabel "DeepenFrame preserves template with empty selector" testDeepenFrameEmpty
  , TestLabel "DeepenFrame enriches with selected predicate" testDeepenFrameEnriched
  , TestLabel "DefinitionFrame preserves template with empty selector" testDefinitionFrameEmpty
  , TestLabel "DefinitionFrame enriches with selected predicate" testDefinitionFrameEnriched
  , TestLabel "ReflectFrame preserves template with empty selector" testReflectFrameEmpty
  , TestLabel "ReflectFrame enriches with selected predicate" testReflectFrameEnriched
  , TestLabel "ChallengeFrame Soft preserves template with empty selector" testChallengeFrameSoftEmpty
  , TestLabel "ChallengeFrame Soft enriches with selected predicate" testChallengeFrameSoftEnriched
  , TestLabel "ChallengeFrame Firm preserves template with empty selector" testChallengeFrameFirmEmpty
  , TestLabel "ChallengeFrame Firm enriches with selected predicate" testChallengeFrameFirmEnriched
  , TestLabel "DistinctionFrame preserves template with empty selector" testDistinctionFrameEmpty
  , TestLabel "DistinctionFrame enriches with selected predicate" testDistinctionFrameEnriched
  , TestLabel "spreading activation flag is enabled" testSpreadingActivationFlagEnabled
  , TestLabel "spreading activation disabled falls back to semanticSupplement" testSpreadingActivationFlagDisabledFallback
  , TestLabel "DefinitionFrame without network falls back to semanticSupplement/template" testDefinitionFrameFallbackWhenNetworkAbsent
  , TestLabel "DefinitionFrame uses spreading-activation supplement when network active" testDefinitionFrameSpreading
  , TestLabel "ReflectFrame uses spreading-activation supplement when network active" testReflectFrameSpreading
  , TestLabel "ChallengeFrame Soft uses spreading-activation supplement when network active" testChallengeFrameSoftSpreading
  , TestLabel "DistinctionFrame uses spreading-activation supplement for both sides" testDistinctionFrameSpreading
  , TestLabel "DefinitionFrame falls back to template when spreading activation yields no predicates" testDefinitionFrameSpreadingEmptyFallback
  , TestLabel "DistinctionFrame falls back to template when spreading activation yields no predicates" testDistinctionFrameSpreadingEmptyFallback
  , dialogueSemanticSelectionRegressionTests
  ]

testFormatSelectedPredicatesEmpty :: Test
testFormatSelectedPredicatesEmpty = TestCase $ do
  assertEqual "empty list should produce empty text"
    "" (formatSelectedPredicates True [])
  assertEqual "empty list in Russian should also produce empty text"
    "" (formatSelectedPredicates False [])

testFormatSelectedPredicatesEnglish :: Test
testFormatSelectedPredicatesEnglish = TestCase $ do
  let p1 = mkPred RoleProperty "утверждение" "statement"
      p2 = mkPred RoleRelation "связь" "connection"
      sp = SelectedPredicate "logic" 1.0 [p1, p2]
      result = formatSelectedPredicates True [sp]
  assertEqual "English predicates should be joined by '. '"
    "statement. connection" result

testFormatSelectedPredicatesRussian :: Test
testFormatSelectedPredicatesRussian = TestCase $ do
  let p1 = mkPred RoleProperty "утверждение" "statement"
      p2 = mkPred RoleRelation "связь" "connection"
      sp = SelectedPredicate "логика" 1.0 [p1, p2]
      result = formatSelectedPredicates False [sp]
  assertEqual "Russian predicates should be joined by '. '"
    "утверждение. связь" result

testAppendSupplementEmpty :: Test
testAppendSupplementEmpty = TestCase $ do
  let base = "Base text"
  assertEqual "empty supplement should leave base unchanged"
    base (appendSupplement base "")

testAppendSupplementNonEmpty :: Test
testAppendSupplementNonEmpty = TestCase $ do
  let base = "Base text"
      supplement = "Extra information"
      result = appendSupplement base supplement
  assertBool "result should contain the base text" (T.isInfixOf base result)
  assertBool "result should contain the supplement text" (T.isInfixOf supplement result)

testGroundFrameEmpty :: Test
testGroundFrameEmpty = TestCase $ do
  let result = runFrame (FT.GroundFrame "логика" FT.Shallow) emptyContentSelector
      expected = "Держу логика как устойчивую опору для дальнейшего разбора."
  assertEqual "GroundFrame shallow with empty selector should equal template"
    expected result

testGroundFrameEnriched :: Test
testGroundFrameEnriched = TestCase $ do
  let cs = mkTestSelector "логика" "связана с субъектом действия" "connected to subject action"
      result = runFrame (FT.GroundFrame "логика" FT.Shallow) cs
      expected = "Держу логика как устойчивую опору для дальнейшего разбора."
  assertBool "enriched GroundFrame should contain base template" (T.isInfixOf expected result)
  assertBool "enriched GroundFrame should contain selected predicate" (T.isInfixOf "связана" result)

testGroundFrameDetailedEmpty :: Test
testGroundFrameDetailedEmpty = TestCase $ do
  let result = runFrame (FT.GroundFrame "логика" FT.Detailed) emptyContentSelector
      expected = "Конкретизирую логика: фиксирую это как рабочую опору и продолжаю от неё."
  assertEqual "GroundFrame detailed with empty selector should equal template"
    expected result

testGroundFrameDetailedEnriched :: Test
testGroundFrameDetailedEnriched = TestCase $ do
  let cs = mkTestSelector "логика" "связана с субъектом действия" "connected to subject action"
      result = runFrame (FT.GroundFrame "логика" FT.Detailed) cs
      expected = "Конкретизирую логика: фиксирую это как рабочую опору и продолжаю от неё."
  assertBool "enriched GroundFrame detailed should contain base template" (T.isInfixOf expected result)
  assertBool "enriched GroundFrame detailed should contain selected predicate" (T.isInfixOf "связана" result)

testLearnFrameEmpty :: Test
testLearnFrameEmpty = TestCase $ do
  let result = runFrame (FT.LearnFrame "логика" FT.Shallow) emptyContentSelector
      expected = "Если говорить о логика, зафиксирую рабочее определение."
  assertEqual "LearnFrame shallow with empty selector should equal template"
    expected result

testLearnFrameEnriched :: Test
testLearnFrameEnriched = TestCase $ do
  let cs = mkTestSelector "логика" "связана с субъектом действия" "connected to subject action"
      result = runFrame (FT.LearnFrame "логика" FT.Shallow) cs
      expected = "Если говорить о логика, зафиксирую рабочее определение."
  assertBool "enriched LearnFrame should contain base template" (T.isInfixOf expected result)
  assertBool "enriched LearnFrame should contain selected predicate" (T.isInfixOf "связана" result)

testHelpFrameEmpty :: Test
testHelpFrameEmpty = TestCase $ do
  let result = runFrame (FT.HelpFrame "логика") emptyContentSelector
      expected = "Помогу с логика. Лучше всего я работаю, когда задача задана явно и можно удержать локальную рамку."
  assertEqual "HelpFrame with empty selector should equal template"
    expected result

testHelpFrameEnriched :: Test
testHelpFrameEnriched = TestCase $ do
  let cs = mkTestSelector "логика" "связана с субъектом действия" "connected to subject action"
      result = runFrame (FT.HelpFrame "логика") cs
      expected = "Помогу с логика. Лучше всего я работаю, когда задача задана явно и можно удержать локальную рамку."
  assertBool "enriched HelpFrame should contain base template" (T.isInfixOf expected result)
  assertBool "enriched HelpFrame should contain selected predicate" (T.isInfixOf "связана" result)

testPurposeFrameEmpty :: Test
testPurposeFrameEmpty = TestCase $ do
  let result = runFrame (FT.PurposeFrame "логика") emptyContentSelector
      expected = "Функция логика проявляется через повторяемую роль в действии."
  assertEqual "PurposeFrame with empty selector should equal template"
    expected result

testPurposeFrameEnriched :: Test
testPurposeFrameEnriched = TestCase $ do
  let cs = mkTestSelector "логика" "связана с субъектом действия" "connected to subject action"
      result = runFrame (FT.PurposeFrame "логика") cs
      expected = "Функция логика проявляется через повторяемую роль в действии."
  assertBool "enriched PurposeFrame should contain base template" (T.isInfixOf expected result)
  assertBool "enriched PurposeFrame should contain selected predicate" (T.isInfixOf "связана" result)

testWorldCauseFrameEmpty :: Test
testWorldCauseFrameEmpty = TestCase $ do
  let result = runFrame (FT.WorldCauseFrame "логика") emptyContentSelector
      expected = "Если говорить о причине логика, различаю локальное рассуждение о механизме и полноценное знание о внешнем мире."
  assertEqual "WorldCauseFrame with empty selector should equal template"
    expected result

testWorldCauseFrameEnriched :: Test
testWorldCauseFrameEnriched = TestCase $ do
  let cs = mkTestSelector "логика" "связана с субъектом действия" "connected to subject action"
      result = runFrame (FT.WorldCauseFrame "логика") cs
      expected = "Если говорить о причине логика, различаю локальное рассуждение о механизме и полноценное знание о внешнем мире."
  assertBool "enriched WorldCauseFrame should contain base template" (T.isInfixOf expected result)
  assertBool "enriched WorldCauseFrame should contain selected predicate" (T.isInfixOf "связана" result)

testDeepenFrameEmpty :: Test
testDeepenFrameEmpty = TestCase $ do
  let result = runFrame (FT.DeepenFrame "логика") emptyContentSelector
      expected = "Углубимся в логика через одно устойчивое фокусирование."
  assertEqual "DeepenFrame with empty selector should equal template"
    expected result

testDeepenFrameEnriched :: Test
testDeepenFrameEnriched = TestCase $ do
  let cs = mkTestSelector "логика" "связана с субъектом действия" "connected to subject action"
      result = runFrame (FT.DeepenFrame "логика") cs
      expected = "Углубимся в логика через одно устойчивое фокусирование."
  assertBool "enriched DeepenFrame should contain base template" (T.isInfixOf expected result)
  assertBool "enriched DeepenFrame should contain selected predicate" (T.isInfixOf "связана" result)

testDefinitionFrameEmpty :: Test
testDefinitionFrameEmpty = TestCase $ do
  let result = runFrame (FT.DefinitionFrame "логика" FT.GeneralScope FT.Known) emptyContentSelector
      expected = "Известно, что логика — содержание не прошло проверку качества и не может быть представлено без проверки."
  assertEqual "DefinitionFrame with empty selector should equal fallback template"
    expected result

testDefinitionFrameEnriched :: Test
testDefinitionFrameEnriched = TestCase $ do
  let cs = mkTestSelector "логика" "связана с субъектом действия" "connected to subject action"
      result = runFrame (FT.DefinitionFrame "логика" FT.GeneralScope FT.Known) cs
      expected = "Известно, что логика — содержание не прошло проверку качества и не может быть представлено без проверки."
  assertBool "enriched DefinitionFrame should contain base template" (T.isInfixOf expected result)
  assertBool "enriched DefinitionFrame should contain selected predicate" (T.isInfixOf "связана" result)

testReflectFrameEmpty :: Test
testReflectFrameEmpty = TestCase $ do
  let result = runFrame (FT.ReflectFrame "логика") emptyContentSelector
      expected = "Когда я думаю о логика, я слышу в нём не только предмет, но и поле смыслов. Здесь можно идти через память, утрату, близость и способ удерживать форму жизни."
  assertEqual "ReflectFrame with empty selector should equal fallback template"
    expected result

testReflectFrameEnriched :: Test
testReflectFrameEnriched = TestCase $ do
  let cs = mkTestSelector "логика" "связана с субъектом действия" "connected to subject action"
      result = runFrame (FT.ReflectFrame "логика") cs
      expected = "Когда я думаю о логика, я слышу в нём не только предмет, но и поле смыслов. Здесь можно идти через память, утрату, близость и способ удерживать форму жизни."
  assertBool "enriched ReflectFrame should contain base template" (T.isInfixOf expected result)
  assertBool "enriched ReflectFrame should contain selected predicate" (T.isInfixOf "связана" result)

testChallengeFrameSoftEmpty :: Test
testChallengeFrameSoftEmpty = TestCase $ do
  let result = runFrame (FT.ChallengeFrame "логика" "основание" FT.Soft "логика") emptyContentSelector
      expected = "Слышу возражение. Я не буду превращать его в определение: логика нужно проверить по явному критерию. Если основание, я уточняю рамку и отделяю тезис от контрпримера."
  assertEqual "ChallengeFrame Soft with empty selector should equal fallback template"
    expected result

testChallengeFrameSoftEnriched :: Test
testChallengeFrameSoftEnriched = TestCase $ do
  let cs = mkTestSelector "логика" "связана с субъектом действия" "connected to subject action"
      result = runFrame (FT.ChallengeFrame "логика" "основание" FT.Soft "логика") cs
      expected = "Слышу возражение. Я не буду превращать его в определение: логика нужно проверить по явному критерию. Если основание, я уточняю рамку и отделяю тезис от контрпримера."
  assertBool "enriched ChallengeFrame Soft should contain base template" (T.isInfixOf expected result)
  assertBool "enriched ChallengeFrame Soft should contain selected predicate" (T.isInfixOf "связана" result)

testChallengeFrameFirmEmpty :: Test
testChallengeFrameFirmEmpty = TestCase $ do
  let result = runFrame (FT.ChallengeFrame "логика" "основание" FT.Firm "логика") emptyContentSelector
      expected = "Возражение принято как проверка тезиса. основание не отменяет логика, но требует явно назвать критерий и границу утверждения."
  assertEqual "ChallengeFrame Firm with empty selector should equal fallback template"
    expected result

testChallengeFrameFirmEnriched :: Test
testChallengeFrameFirmEnriched = TestCase $ do
  let cs = mkTestSelector "логика" "связана с субъектом действия" "connected to subject action"
      result = runFrame (FT.ChallengeFrame "логика" "основание" FT.Firm "логика") cs
      expected = "Возражение принято как проверка тезиса. основание не отменяет логика, но требует явно назвать критерий и границу утверждения."
  assertBool "enriched ChallengeFrame Firm should contain base template" (T.isInfixOf expected result)
  assertBool "enriched ChallengeFrame Firm should contain selected predicate" (T.isInfixOf "связана" result)

testDistinctionFrameEmpty :: Test
testDistinctionFrameEmpty = TestCase $ do
  let result = runFrame (FT.DistinctionFrame "логика" "мышление" []) emptyContentSelector
      expected = "Различим логика и мышление в одной рамке критериев. логика и мышление различаются по набору признаков. Без явной рамки сравнение остаётся зависимым от принятых допущений."
  assertEqual "DistinctionFrame with empty selector should equal template"
    expected result

testDistinctionFrameEnriched :: Test
testDistinctionFrameEnriched = TestCase $ do
  let cs = mkTestSelector "логика" "связана с субъектом действия" "connected to subject action"
      result = runFrame (FT.DistinctionFrame "логика" "мышление" []) cs
      expected = "Различим логика и мышление в одной рамке критериев. логика и мышление различаются по набору признаков. Без явной рамки сравнение остаётся зависимым от принятых допущений."
  assertBool "enriched DistinctionFrame should contain base template" (T.isInfixOf expected result)
  assertBool "enriched DistinctionFrame should contain selected predicate" (T.isInfixOf "связана" result)

-- | Wired frames used for regression coverage of determinism and fallback
-- preservation. Each tuple carries a display label, the frame constructor, and
-- the exact fallback template produced with 'emptyContentSelector'.
wiredRegressionFrames :: [(String, FT.SemanticFrame, Text)]
wiredRegressionFrames =
  [ ("GroundFrame shallow", FT.GroundFrame "логика" FT.Shallow, "Держу логика как устойчивую опору для дальнейшего разбора.")
  , ("GroundFrame detailed", FT.GroundFrame "логика" FT.Detailed, "Конкретизирую логика: фиксирую это как рабочую опору и продолжаю от неё.")
  , ("LearnFrame", FT.LearnFrame "логика" FT.Shallow, "Если говорить о логика, зафиксирую рабочее определение.")
  , ("HelpFrame", FT.HelpFrame "логика", "Помогу с логика. Лучше всего я работаю, когда задача задана явно и можно удержать локальную рамку.")
  , ("PurposeFrame", FT.PurposeFrame "логика", "Функция логика проявляется через повторяемую роль в действии.")
  , ("WorldCauseFrame", FT.WorldCauseFrame "логика", "Если говорить о причине логика, различаю локальное рассуждение о механизме и полноценное знание о внешнем мире.")
  , ("DeepenFrame", FT.DeepenFrame "логика", "Углубимся в логика через одно устойчивое фокусирование.")
  , ("DefinitionFrame", FT.DefinitionFrame "логика" FT.GeneralScope FT.Known, "Известно, что логика — содержание не прошло проверку качества и не может быть представлено без проверки.")
  , ("ReflectFrame", FT.ReflectFrame "логика", "Когда я думаю о логика, я слышу в нём не только предмет, но и поле смыслов. Здесь можно идти через память, утрату, близость и способ удерживать форму жизни.")
  , ("ChallengeFrame Soft", FT.ChallengeFrame "логика" "основание" FT.Soft "логика", "Слышу возражение. Я не буду превращать его в определение: логика нужно проверить по явному критерию. Если основание, я уточняю рамку и отделяю тезис от контрпримера.")
  , ("ChallengeFrame Firm", FT.ChallengeFrame "логика" "основание" FT.Firm "логика", "Возражение принято как проверка тезиса. основание не отменяет логика, но требует явно назвать критерий и границу утверждения.")
  , ("DistinctionFrame", FT.DistinctionFrame "логика" "мышление" [], "Различим логика и мышление в одной рамке критериев. логика и мышление различаются по набору признаков. Без явной рамки сравнение остаётся зависимым от принятых допущений.")
  ]

-- | Determinism: identical inputs must yield identical outputs.
testDeterminism :: FT.SemanticFrame -> Test
testDeterminism frame = TestCase $ do
  let cs = mkTestSelector "логика" "связана с субъектом действия" "connected to subject action"
      result1 = runFrame frame cs
      result2 = runFrame frame cs
  result1 @=? result2

-- | Empty selector must preserve the original fallback template exactly.
testEmptySelectorFallback :: FT.SemanticFrame -> Text -> Test
testEmptySelectorFallback frame expected = TestCase $ do
  let result = runFrame frame emptyContentSelector
  expected @=? result

-- | Running the generator must not mutate the supplied ContentSelector.
testContentSelectorNoMutation :: Test
testContentSelectorNoMutation = TestCase $ do
  let cs = mkTestSelector "логика" "связана с субъектом действия" "connected to subject action"
      originalAtoms = csTopicAtoms cs
      originalPredicates = csTopicPredicates cs
      originalLemmas = csLemmaMap cs
      _ = runFrame (FT.GroundFrame "логика" FT.Shallow) cs
  originalAtoms @=? csTopicAtoms cs
  originalPredicates @=? csTopicPredicates cs
  originalLemmas @=? csLemmaMap cs

testSpreadingActivationFlagEnabled :: Test
testSpreadingActivationFlagEnabled = TestCase $
  assertBool "spreadingActivationActive should be True by default" spreadingActivationActive

-- | The spreading-activation feature flag is a compile-time 'Bool' constant and
-- is not mutable at runtime.  The disabled-flag branch in 'frameSupplement'
-- shares the same fallback code path as the "no network" case, so we verify
-- that path directly and confirm that 'generateFromFrame' still follows the
-- semanticSupplement / template behaviour.
testSpreadingActivationFlagDisabledFallback :: Test
testSpreadingActivationFlagDisabledFallback = TestCase $ do
  let cs = mkTestSelector "свобода" "свобода предполагает выбор" "freedom implies choice"
      topic = "свобода"
      supplement = frameSupplement VmDefinition emptyMorphologyData cs testField topic Nothing False
  assertEqual "frameSupplement with no network should fall back to semanticSupplement"
    (semanticSupplement cs testField topic Nothing False) supplement

testDefinitionFrameFallbackWhenNetworkAbsent :: Test
testDefinitionFrameFallbackWhenNetworkAbsent = TestCase $ do
  let cs = mkTestSelector "свобода" "свобода предполагает выбор" "freedom implies choice"
      frame = FT.DefinitionFrame "свобода" FT.GeneralScope FT.Known
      result = generateFromFrame cs testField Nothing seedGraph emptySystemState frame emptyMorphologyData
      expected = appendSupplement
        "Известно, что свобода — содержание не прошло проверку качества и не может быть представлено без проверки."
        (semanticSupplement cs testField "свобода" Nothing False)
  assertEqual "DefinitionFrame without network should fall back to semanticSupplement/template behavior"
    expected result

testDefinitionFrameSpreading :: Test
testDefinitionFrameSpreading = TestCase $ do
  let result = runFrameWithNetwork (FT.DefinitionFrame "логика" FT.GeneralScope FT.Known) mkSpreadingSelector testNetwork
  assertBool "spreading DefinitionFrame should contain base template" (T.isInfixOf "логика — содержание не прошло проверку качества" result)
  assertBool "spreading DefinitionFrame should contain predicate surfaced from connected topic" (T.isInfixOf "субъекта действие" result)

testReflectFrameSpreading :: Test
testReflectFrameSpreading = TestCase $ do
  let result = runFrameWithNetwork (FT.ReflectFrame "логика") mkSpreadingSelector testNetwork
  assertBool "spreading ReflectFrame should contain base template" (T.isInfixOf "Когда я думаю о логика" result)
  assertBool "spreading ReflectFrame should contain predicate surfaced from connected topic" (T.isInfixOf "субъекта действие" result)

testChallengeFrameSoftSpreading :: Test
testChallengeFrameSoftSpreading = TestCase $ do
  let result = runFrameWithNetwork (FT.ChallengeFrame "логика" "основание" FT.Soft "логика") mkSpreadingSelector testNetwork
  assertBool "spreading ChallengeFrame Soft should contain base template" (T.isInfixOf "Слышу возражение" result)
  assertBool "spreading ChallengeFrame Soft should contain predicate surfaced from connected topic" (T.isInfixOf "субъекта действие" result)

testDistinctionFrameSpreading :: Test
testDistinctionFrameSpreading = TestCase $ do
  let result = runFrameWithNetwork (FT.DistinctionFrame "логика" "мышление" []) mkSpreadingSelector testNetwork
  assertBool "spreading DistinctionFrame should contain base template" (T.isInfixOf "Различим логика и мышление" result)
  assertBool "spreading DistinctionFrame left side should surface connected predicate" (T.isInfixOf "логика с субъекта" result)
  assertBool "spreading DistinctionFrame right side should surface its own predicate" (T.isInfixOf "мышление с субъекта" result)

testDefinitionFrameSpreadingEmptyFallback :: Test
testDefinitionFrameSpreadingEmptyFallback = TestCase $ do
  let result = runFrameWithNetwork (FT.DefinitionFrame "логика" FT.GeneralScope FT.Known) mkEmptySpreadingSelector testNetwork
      expected = "Известно, что логика — содержание не прошло проверку качества и не может быть представлено без проверки."
  assertEqual "empty spreading activation should preserve fallback template" expected result

testDistinctionFrameSpreadingEmptyFallback :: Test
testDistinctionFrameSpreadingEmptyFallback = TestCase $ do
  let result = runFrameWithNetwork (FT.DistinctionFrame "логика" "мышление" []) mkEmptySpreadingSelector testNetwork
      expected = "Различим логика и мышление в одной рамке критериев. логика и мышление различаются по набору признаков. Без явной рамки сравнение остаётся зависимым от принятых допущений."
  assertEqual "empty spreading activation should preserve fallback template" expected result

-- | Language surface gating: English vs Russian predicate text.
testLanguageGating :: Test
testLanguageGating = TestCase $ do
  let cs = mkTestSelector "logic" "связана с субъектом действия" "connected to subject action"
      selected = selectPredicates cs testField "logic" Nothing
      enResult = formatSelectedPredicates True selected
      ruResult = formatSelectedPredicates False selected
  "connected to subject action" @=? enResult
  "связана с субъектом действия" @=? ruResult

-- | Consolidated regression TestList for semantic-selection wiring.
dialogueSemanticSelectionRegressionTests :: Test
dialogueSemanticSelectionRegressionTests = TestList $
  map (\(label, frame, _) -> TestLabel ("determinism: " ++ label) (testDeterminism frame)) wiredRegressionFrames
  ++ map (\(label, frame, expected) -> TestLabel ("empty selector fallback: " ++ label) (testEmptySelectorFallback frame expected)) wiredRegressionFrames
  ++ [ TestLabel "ContentSelector is not mutated by generateFromFrame" testContentSelectorNoMutation
     , TestLabel "formatSelectedPredicates gates English and Russian surfaces" testLanguageGating
     ]
