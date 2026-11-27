{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.StateIntegrityWire
Description : P4 (2026-11-23) wire-freeze pins for the Conatus → StateIntegrity rename.

The rename changed Haskell identifiers only.  Persisted stores and replay
traces keep the historical @ce*@, @cw*@, @cg*@, @ftMinConatus@,
@scConatusTrend@, @conatusGateThreshold@ and constructor spellings, so an
old store still decodes and an old trace still replays.  These pins fail
the moment a derived instance starts emitting a new key.
-}
module Test.Suite.StateIntegrityWire
  ( stateIntegrityWireTests
  ) where

import Data.Aeson (decode, encode)
import qualified Data.ByteString.Lazy as BL
import Data.Sequence (fromList)
import qualified Data.Text.Lazy as LT
import qualified Data.Text.Lazy.Encoding as LTE
import Test.HUnit (Test (..), assertBool, assertEqual)

import QxFx0.Self.Field (emptyField)
import QxFx0.Self.Salience (defaultSalienceWeights)
import QxFx0.Runtime.StateDefaults (emptySelfState)
import QxFx0.Types.Domain (CanonicalMoveFamily (..))
import QxFx0.Types.Learning.Signal (SignalComponents (..))
import QxFx0.Types.Self.Deliberation (Agreement (..), ReconcileRule (..))
import QxFx0.Types.Self.Essence
  ( CommitmentTrigger (..)
  , EssenceTrajectory (..)
  , EssenceWitness (..)
  , FieldBand (..)
  , FieldSignature (..)
  , TrajectoryHash (..)
  , ValenceBand (..)
  )
import QxFx0.Types.Self.FamilyTargets (FamilyTarget (..))
import QxFx0.Types.Self.Salience (SalienceDriver (..), SalienceWeights (..))
import QxFx0.Types.Self.StateIntegrity
  ( StateIntegrity (..)
  , StateIntegrityComponents (..)
  , StateIntegrityGradient (..)
  , StateIntegrityWeights (..)
  )

hasKey :: String -> BL.ByteString -> Bool
hasKey key blob = ("\"" <> LT.pack key <> "\"") `LT.isInfixOf` LTE.decodeUtf8 blob

hasText :: String -> BL.ByteString -> Bool
hasText needle blob = LT.pack needle `LT.isInfixOf` LTE.decodeUtf8 blob

sampleComponents :: StateIntegrityComponents
sampleComponents = StateIntegrityComponents
  { sicMorphology = 1.0
  , sicIdentity = 2.0
  , sicTurns = 3.0
  , sicPenalty = 0.0
  , sicSelfDivergence = 0.0
  }

sampleWitness :: EssenceWitness
sampleWitness = EssenceWitness
  { ewTurnOrdinal = 1
  , ewSalienceDriver = DrivenByStateIntegrityGate
  , ewReconcileRule = RuleStateIntegrityOverride
  , ewAgreement = Agree
  , ewDivergence = 0.1
  , ewStateIntegrityScalar = 7.0
  , ewFieldSignature = FieldSignature BandLow BandMid ValenceNeutral BandHigh BandLow
  }

stateIntegrityWireTests :: [Test]
stateIntegrityWireTests =
  [ TestLabel "wire: ce* keys survive the rename" $ TestCase $ do
      let blob = encode (StateIntegrity 6.0 sampleComponents)
      assertBool "ceScalar" (hasKey "ceScalar" blob)
      assertBool "ceComponents" (hasKey "ceComponents" blob)
      assertBool "ccMorphology" (hasKey "ccMorphology" blob)
      assertBool "ccIdentity" (hasKey "ccIdentity" blob)
      assertBool "ccTurns" (hasKey "ccTurns" blob)
      assertBool "ccPenalty" (hasKey "ccPenalty" blob)
      assertBool "ccSelfDivergence" (hasKey "ccSelfDivergence" blob)

  , TestLabel "wire: ce* round-trip re-derives the scalar" $ TestCase $
      assertEqual "round-trip" (Just (StateIntegrity 6.0 sampleComponents))
        (decode (encode (StateIntegrity 999.0 sampleComponents)))

  , TestLabel "wire: cw* keys survive the rename" $ TestCase $ do
      let blob = encode (StateIntegrityWeights 1.0 2.0 3.0 4.0)
      assertBool "cwMorphology" (hasKey "cwMorphology" blob)
      assertBool "cwIdentity" (hasKey "cwIdentity" blob)
      assertBool "cwTurns" (hasKey "cwTurns" blob)
      assertBool "cwViolation" (hasKey "cwViolation" blob)

  , TestLabel "wire: cg* keys survive the rename" $ TestCase $ do
      let blob = encode (StateIntegrityGradient 1.0 2.0 3.0)
      assertBool "cgMorphology" (hasKey "cgMorphology" blob)
      assertBool "cgIdentity" (hasKey "cgIdentity" blob)
      assertBool "cgTurns" (hasKey "cgTurns" blob)

  , TestLabel "wire: salience threshold keeps conatusGateThreshold" $ TestCase $ do
      let blob = encode defaultSalienceWeights
      assertBool "old key" (hasKey "conatusGateThreshold" blob)
      assertBool "no new key" (not (hasKey "stateIntegrityGateThreshold" blob))

  , TestLabel "wire: family target keeps ftMinConatus" $ TestCase $ do
      let target = FamilyTarget CMDefine emptyField 5.0 0.5
      assertBool "old key" (hasKey "ftMinConatus" (encode target))
      assertEqual "round-trip" (Just target) (decode (encode target))

  , TestLabel "wire: signal components keep scConatusTrend" $ TestCase $ do
      let comps = SignalComponents 0.1 0.2 0.3 0.4
      assertBool "old key" (hasKey "scConatusTrend" (encode comps))
      assertEqual "round-trip" (Just comps) (decode (encode comps))

  , TestLabel "wire: salience driver keeps DrivenByConatusGate" $ TestCase $ do
      assertEqual "tag" "\"DrivenByConatusGate\"" (encode DrivenByStateIntegrityGate)
      assertEqual "round-trip" (Just DrivenByStateIntegrityGate)
        (decode (encode DrivenByStateIntegrityGate))

  , TestLabel "wire: reconcile rule keeps RuleConatusOverride" $ TestCase $ do
      assertEqual "tag" "\"RuleConatusOverride\"" (encode RuleStateIntegrityOverride)
      assertEqual "round-trip" (Just RuleStateIntegrityOverride)
        (decode (encode RuleStateIntegrityOverride))

  , TestLabel "wire: commitment trigger keeps TriggerConatusErosion" $ TestCase $ do
      assertEqual "tag" "\"TriggerConatusErosion\"" (encode TriggerStateIntegrityErosion)
      assertEqual "round-trip" (Just TriggerStateIntegrityErosion)
        (decode (encode TriggerStateIntegrityErosion))

  , TestLabel "wire: essence witness keeps ewConatusScalar" $ TestCase $ do
      let blob = encode sampleWitness
      assertBool "old key" (hasKey "ewConatusScalar" blob)
      assertBool "old driver" (hasText "DrivenByConatusGate" blob)
      assertBool "old rule" (hasText "RuleConatusOverride" blob)
      assertEqual "round-trip" (Just sampleWitness) (decode (encode sampleWitness))

  , TestLabel "wire: essence trajectory keeps etConatusFloor" $ TestCase $ do
      let trajectory = EssenceTrajectory
            { etWitnesses = fromList [sampleWitness]
            , etAngstLevel = 0.25
            , etStateIntegrityFloor = 7.0
            , etCapacity = 8
            }
          blob = encode trajectory
      assertBool "old key" (hasKey "etConatusFloor" blob)
      assertBool "no new key" (not (hasKey "etStateIntegrityFloor" blob))
      assertBool "kept key" (hasKey "etAngstLevel" blob)
      assertEqual "round-trip" (Just trajectory) (decode blob)

  , TestLabel "wire: persisted self state keeps selfConatusWeights" $ TestCase $ do
      let blob = encode emptySelfState
      assertBool "old key" (hasKey "selfConatusWeights" blob)
      assertBool "no new key" (not (hasKey "selfStateIntegrityWeights" blob))
      assertEqual "round-trip" (Just emptySelfState) (decode blob)
  ]
