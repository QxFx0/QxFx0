{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.StateSanitization
Description : Audit 2026-10-16 (p.11) anti-rot: fail-closed clamps on persisted JSON.

Persisted JSON is a trust boundary.  'sanitizePersistedState' clamps the
named value invariants on every successful state decode and reports each
adjustment; 'ConatusEnergy' re-derives 'ceScalar' from the component sum
in its 'FromJSON'.  These pins make a regression (silent trust of a
corrupted store, non-finite poisoning, a broken scalar invariant) fail
loudly.

Bar (6) of the audit-2026-10-16 fix registrations.
-}
module Test.Suite.StateSanitization
  ( stateSanitizationTests
  ) where

import qualified Data.Aeson as Aeson
import qualified Data.Text as T
import Test.HUnit (Test (..), assertBool, assertEqual)

import QxFx0.Bridge.StateSanitization (sanitizePersistedState)
import QxFx0.Runtime.StateDefaults (emptySystemState)
import QxFx0.Types.Self.Conatus
  ( ConatusComponents(..)
  , ConatusEnergy(..)
  , conatusComponentSum
  )
import QxFx0.Types.ShadowDivergence (ShadowVetoState(..))
import QxFx0.Types.State (DialogueState(..))
import QxFx0.Types.State.SelfState (SelfState(..))
import QxFx0.Types.State.System (SystemState(..), ssTurnCount)
import QxFx0.Types.User.R5 (UserR5ContourState(..))

stateSanitizationTests :: [Test]
stateSanitizationTests =
  [ testShadowVetoClamped
  , testShadowVetoValidUnchanged
  , testSelfDivergenceWindowDropsNonFinite
  , testSelfDivergenceWindowTrimsToNewestBound
  , testUserBaselineSanitized
  , testUserDivergenceWindowSanitized
  , testCleanStateIsIdentity
  , testConatusScalarDerivedOnDecode
  ]

-- | A system state with the dialogue turn counter pinned (the
-- @svsWindowStart@ clamp upper bound is @ssTurnCount@).
baseState :: SystemState
baseState =
  emptySystemState
    { ssDialogue = (ssDialogue emptySystemState) { dsTurnCount = 42 }
    }

-- | Audit p.11 pin (a): negative veto counts and a future window
-- start are clamped; both adjustments are reported.
testShadowVetoClamped :: Test
testShadowVetoClamped = TestLabel "p.11: shadow-veto fields are clamped and reported" $ TestCase $ do
  let ss0 = baseState { ssShadowVetoState = ShadowVetoState (-5) 999999 }
      (ss1, notes) = sanitizePersistedState ss0
      veto = ssShadowVetoState ss1
  assertEqual "svsCount negative clamps to zero" 0 (svsCount veto)
  assertEqual "svsWindowStart future clamps to the turn count"
    42 (svsWindowStart veto)
  assertEqual "ssTurnCount is the clamp bound" 42 (ssTurnCount ss1)
  assertBool ("both adjustments are reported, got: " <> show notes)
    (length notes == 2)

-- | Audit p.11 pin (a), stable case: a valid veto state passes
-- through value-unchanged with no notes.
testShadowVetoValidUnchanged :: Test
testShadowVetoValidUnchanged = TestLabel "p.11: valid veto state is unchanged" $ TestCase $ do
  let ss0 = baseState { ssShadowVetoState = ShadowVetoState 2 7 }
      (ss1, notes) = sanitizePersistedState ss0
  assertEqual "valid veto state unchanged"
    (ssShadowVetoState ss0) (ssShadowVetoState ss1)
  assertEqual "no notes for a clean veto state" [] notes

-- | Audit p.11 pin (b): non-finite divergence samples never survive
-- the decode.
testSelfDivergenceWindowDropsNonFinite :: Test
testSelfDivergenceWindowDropsNonFinite = TestLabel "p.11: self divergence window drops non-finite samples" $ TestCase $ do
  let window = [0.1, 0 / 0, 0.2, 1 / 0, 0.3]
      ss0 = baseState
        { ssSelfState = (ssSelfState baseState) { selfDivergenceWindow = window } }
      (ss1, notes) = sanitizePersistedState ss0
  assertEqual "only the finite samples remain"
    [0.1, 0.2, 0.3] (selfDivergenceWindow (ssSelfState ss1))
  assertBool "the drop is reported"
    (any (T.isInfixOf "selfDivergenceWindow: dropped 2 non-finite") notes)

-- | Audit p.11 pin (b): an over-long window is truncated to the
-- newest-first @sdtWindow@ head.
testSelfDivergenceWindowTrimsToNewestBound :: Test
testSelfDivergenceWindowTrimsToNewestBound = TestLabel "p.11: self divergence window trims to the newest bound" $ TestCase $ do
  let window = [1.0 .. 10.0]
      ss0 = baseState
        { ssSelfState = (ssSelfState baseState) { selfDivergenceWindow = window } }
      (ss1, notes) = sanitizePersistedState ss0
  assertEqual "the newest sdtWindow (8) head is kept"
    [1.0 .. 8.0] (selfDivergenceWindow (ssSelfState ss1))
  assertBool "the trim is reported"
    (any (T.isInfixOf "selfDivergenceWindow: 10 -> 8 samples") notes)

-- | Audit p.11 pin (c): the baseline is either dropped (non-finite)
-- or clamped with the runtime's own score clamp; valid values stay.
testUserBaselineSanitized :: Test
testUserBaselineSanitized = TestLabel "p.11: u5Baseline is dropped or clamped, never trusted" $ TestCase $ do
  let withBaseline v = baseState
        { ssUserR5Contour = (ssUserR5Contour baseState) { u5Baseline = v } }
      baselineOf ss = u5Baseline (ssUserR5Contour ss)
      notesOf ss = snd (sanitizePersistedState ss)

  assertEqual "NaN baseline becomes Nothing"
    Nothing (baselineOf (fst (sanitizePersistedState (withBaseline (Just (0 / 0))))))
  assertEqual "infinite baseline becomes Nothing"
    Nothing (baselineOf (fst (sanitizePersistedState (withBaseline (Just (1 / 0))))))
  assertEqual "out-of-range baseline clamps to the score bound"
    (Just 1.0) (baselineOf (fst (sanitizePersistedState (withBaseline (Just 1.7)))))
  assertEqual "negative baseline clamps to the score bound"
    (Just (-1.0)) (baselineOf (fst (sanitizePersistedState (withBaseline (Just (-3.0))))))
  assertEqual "valid baseline is unchanged"
    (Just 0.4) (baselineOf (fst (sanitizePersistedState (withBaseline (Just 0.4)))))
  assertEqual "valid baseline yields no note" [] (notesOf (withBaseline (Just 0.4)))

-- | Audit p.11 pin (c): the residual window follows the same
-- drop/trim policy as the self window.
testUserDivergenceWindowSanitized :: Test
testUserDivergenceWindowSanitized = TestLabel "p.11: u5 divergence window drops non-finite and trims" $ TestCase $ do
  let window = [0 / 0, 0.5, 1 / 0] <> [1.0 .. 8.0]
      ss0 = baseState
        { ssUserR5Contour =
            (ssUserR5Contour baseState) { u5DivergenceWindow = window }
        }
      (ss1, notes) = sanitizePersistedState ss0
      kept = u5DivergenceWindow (ssUserR5Contour ss1)
  assertEqual "the newest-first head survives the drop and trim"
    [0.5, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0] kept
  assertBool "no non-finite sample survives" (all (\x -> not (isNaN x) && not (isInfinite x)) kept)
  assertBool "the drop is reported"
    (any (T.isInfixOf "u5DivergenceWindow: dropped 2 non-finite") notes)

-- | Audit p.11: the sanitizer is a total identity on a clean state.
testCleanStateIsIdentity :: Test
testCleanStateIsIdentity = TestLabel "p.11: a clean state is the identity" $ TestCase $ do
  let (ss1, notes) = sanitizePersistedState emptySystemState
  assertEqual "clean state is value-unchanged" emptySystemState ss1
  assertEqual "clean state yields no notes" [] notes

-- | Audit p.11 (c): 'ConatusEnergy' re-derives 'ceScalar' on decode;
-- the key stays mandatory, the value is not trusted, and legacy
-- four-component blobs keep their old semantics.
testConatusScalarDerivedOnDecode :: Test
testConatusScalarDerivedOnDecode = TestLabel "p.11: ceScalar is re-derived on decode" $ TestCase $ do
  let inconsistent =
        "{\"ceScalar\":99.0,\"ceComponents\":{\"ccMorphology\":1.0,\"ccIdentity\":2.0,\"ccTurns\":3.0,\"ccPenalty\":-1.0,\"ccSelfDivergence\":-0.5}}"
      consistent =
        "{\"ceScalar\":4.5,\"ceComponents\":{\"ccMorphology\":1.0,\"ccIdentity\":2.0,\"ccTurns\":3.0,\"ccPenalty\":-1.0,\"ccSelfDivergence\":-0.5}}"
      legacy =
        "{\"ceScalar\":6.0,\"ceComponents\":{\"ccMorphology\":1.0,\"ccIdentity\":2.0,\"ccTurns\":3.0,\"ccPenalty\":0.0}}"
      missingScalar =
        "{\"ceComponents\":{\"ccMorphology\":1.0,\"ccIdentity\":2.0,\"ccTurns\":3.0,\"ccPenalty\":-1.0}}"
  assertEqual "inconsistent scalar is replaced by the component sum"
    (Just 4.5) (ceScalar <$> (Aeson.decode inconsistent :: Maybe ConatusEnergy))
  assertEqual "consistent scalar is unchanged"
    (Just 4.5) (ceScalar <$> (Aeson.decode consistent :: Maybe ConatusEnergy))
  assertEqual "legacy four-component blob keeps its scalar"
    (Just 6.0) (ceScalar <$> (Aeson.decode legacy :: Maybe ConatusEnergy))
  assertEqual "the ceScalar key stays mandatory"
    Nothing (Aeson.decode missingScalar :: Maybe ConatusEnergy)
  assertEqual "the component sum is the definition"
    5.75 (conatusComponentSum (ConatusComponents 1.0 2.0 3.0 (-0.5) 0.25))
