{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.ChallengeMarkers
Description : Audit 2026-10-16 (п.17) anti-rot: the single challenge-marker lexicon.

Five routing sites used to carry five divergent copies of the
challenge-marker lexicon (Effects 20, Build/Render/Cascade the same 17,
Anomaly 11 of its own).  'QxFx0.Semantic.Markers' is now the single
source: the canonical union list, the Anomaly suppression list built
from it, and one shared matching rule.  These pins make a re-divergence
(a private copy, a dropped marker, a broken suppression) fail loudly.

Bar (7) of the audit-2026-10-16 fix registrations.
-}
module Test.Suite.ChallengeMarkers
  ( challengeMarkersTests
  ) where

import Data.List (sort)
import Data.Maybe (isJust, isNothing)
import qualified Data.Text as T
import qualified Data.Vector as V
import Test.HUnit (Test (..), assertBool, assertEqual)

import QxFx0.Core.TurnPipeline.Route.Anomaly (detectUnclassifiableInput)
import QxFx0.Core.TurnPipeline.Types (TurnInput(..))
import QxFx0.Runtime.StateDefaults (emptySystemState)
import QxFx0.Semantic.Markers
  ( challengeMarkers
  , containsAnyOf
  , unclassifiableSuppressionMarkers
  )
import QxFx0.Types (AtomSet(..), AtomTag(..), InputPropositionFrame(..), MeaningAtom(..), Register(..))
import QxFx0.Types.Domain (CanonicalMoveFamily(..))
import QxFx0.Types.PropositionType (PropositionType(..))
import Test.Support.TurnPipelineFixtures (buildPreparedFixture)

challengeMarkersTests :: [Test]
challengeMarkersTests =
  [ testCanonicalUnion
  , testSuppressionListExtendsChallengeMarkers
  , testContainsAnyOfMatching
  , testAnomalySuppressionUsesCanonicalList
  ]

-- | The union of the five pre-unification copies, written in any order
-- (the pin compares sorted lists): the 20 from
-- @Effects.hasChallengeMarker@ plus «считаю иначе» from the Anomaly
-- list.
expectedChallengeUnion :: [T.Text]
expectedChallengeUnion =
  [ -- disagreement group (all five sites)
    "разве", "не согласен", "не согласна", "противореч", "неверно"
  , "ошибаешься", "не прав", "спорю", "возраж", "сомневаюсь"
  , "ты говоришь", "оспариваю"
  , "считаю иначе"
    -- softening group (Effects / Build / Render / Cascade)
  , "это просто", "не более чем", "сводится к"
  , "всего лишь", "это лишь"
    -- evidential trio (Effects and the classifier only, pre-unification)
  , "контрпример", "докажи", "что если"
  ]

-- | Audit п.17 pin: the canonical lexicon is the union — every site
-- gained markers, none lost any.
testCanonicalUnion :: Test
testCanonicalUnion = TestLabel "п.17: the canonical challenge lexicon is the five-copy union" $ TestCase $ do
  assertEqual "21 entries — the union, nothing dropped"
    21 (length challengeMarkers)
  assertEqual "content is the union (sorted comparison)"
    (sort expectedChallengeUnion) (sort challengeMarkers)

-- | Audit п.17 pin: the Anomaly gate list is the challenge list plus
-- the contrastive connective, and the connective never enters the
-- family-flipping list.
testSuppressionListExtendsChallengeMarkers :: Test
testSuppressionListExtendsChallengeMarkers = TestLabel "п.17: the Anomaly suppression list extends the canonical challenge list" $ TestCase $ do
  assertEqual "«но » : challengeMarkers"
    (("но " :: T.Text) : challengeMarkers) unclassifiableSuppressionMarkers
  assertBool "the connective stays out of the family-override lexicon"
    ("но " `notElem` challengeMarkers)

-- | Audit п.17 pin: one matching rule for every consumer — substring
-- containment over the caller-lowered input.
testContainsAnyOfMatching :: Test
testContainsAnyOfMatching = TestLabel "п.17: containsAnyOf is the single matching rule" $ TestCase $ do
  let fires = containsAnyOf challengeMarkers . T.toLower
  assertBool "disagreement group" (fires "НЕВЕРНО, ты ошибаешься")
  assertBool "courtesy group" (fires "я сомневаюсь в этом")
  assertBool "softening group" (fires "это просто слова")
  assertBool "evidential group" (fires "Приведи контрпример")
  assertBool "«считаю иначе» (Anomaly-only before the unification)"
    (fires "я считаю иначе")
  assertBool "no false positive on a plain request"
    (not (fires "расскажи про свободу"))
  assertBool "the bare connective is not a challenge"
    (not (fires "но это так"))
  assertBool "«нет» is not in the challenge lexicon"
    (not (fires "нет"))

-- | Audit п.17 pin: the exposed Unclassifiable detector reads the
-- canonical suppression list — the evidential trio («контрпример»,
-- «что если») and «но » suppress the anomaly (the pre-unification
-- Anomaly copy knew none of the trio), while a marker-less unknown
-- input still fires it.
testAnomalySuppressionUsesCanonicalList :: Test
testAnomalySuppressionUsesCanonicalList = TestLabel "п.17: Unclassifiable suppression reads the canonical list" $ TestCase $ do
  (_ss0, ti0, _ts) <- buildPreparedFixture "свобода предполагает выбор"
  let ss = emptySystemState
      -- The fixture's own atom set is empty in this environment, so the
      -- detector pin injects one synthetic atom that is unknown to the
      -- empty space (ratio 0 < threshold, total count 1).
      unknownAtom = MeaningAtom
        { maText = "ксилорптронныйвальд"
        , maTag = CustomAtom "audit_p17" "ксилорптронныйвальд"
        , maEmbedding = V.empty
        }
      tiBase = ti0
        { tiAtomSet = AtomSet
            { asAtoms = [unknownAtom]
            , asLoad = 0.0
            , asRegister = Neutral
            }
        , tiBestTopic = "ксилорптронная-тема"
        , tiRecommendedFamily = CMGround
        , tiFrame =
            (tiFrame ti0)
              { ipfRawText = "ксилорптронный вальд"
              , ipfPropositionType = PlainAssert
              }
        }
      withText txt = tiBase { tiFrame = (tiFrame tiBase) { ipfRawText = txt } }
  assertBool "a marker-less unknown input still fires Unclassifiable"
    (isJust (detectUnclassifiableInput ss tiBase))
  assertBool "«контрпример» suppresses the anomaly (canonical-only marker)"
    (isNothing (detectUnclassifiableInput ss (withText "ксилорптронный вальд, контрпример")))
  assertBool "«что если» suppresses the anomaly (canonical-only marker)"
    (isNothing (detectUnclassifiableInput ss (withText "а что если ксилорптронный вальд")))
  assertBool "«но » suppresses the anomaly (suppression-only connective)"
    (isNothing (detectUnclassifiableInput ss (withText "но ксилорптронный вальд")))
