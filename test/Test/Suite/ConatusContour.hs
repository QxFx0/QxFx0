{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Test.Suite.ConatusContour
Description : P4 (2026-11-23) pins for the trace-only self-maintenance contour.

The contour is observational: four facts the turn already carries.  These
pins fix the mapping (violation count, recovery cause, essence commitment,
crisis availability), the JSON round-trip and the key names.  They do not
claim that anything reads the contour — nothing does.
-}
module Test.Suite.ConatusContour
  ( conatusContourTests
  ) where

import Data.Aeson (decode, encode)
import qualified Data.ByteString.Lazy as BL
import qualified Data.Text.Lazy as LT
import qualified Data.Text.Lazy.Encoding as LTE
import Test.HUnit (Test (..), assertBool, assertEqual)

import QxFx0.Self.ConatusContour
  ( computeConatusContour
  , crisisPackAvailable
  )
import QxFx0.Self.Essence
  ( CommitmentTrigger (..)
  , Essence (..)
  , EssenceCommitment (..)
  , EssenceMode (..)
  , TrajectoryHash (..)
  , emptyEssence
  , emptyTrajectory
  )
import QxFx0.Safety.CrisisGuard (crisisResourcesRu)
import QxFx0.Types.Recovery (LocalRecoveryCause (..))
import QxFx0.Types.Safety.Crisis (CrisisResources (..))
import QxFx0.Types.Self.ConatusContour
  ( BlanketIntegrity (..)
  , ConatusContour (..)
  )

committedEssence :: Essence
committedEssence = EssenceCommitted emptyTrajectory EssenceCommitment
  { ecMode = EssenceWitnessing
  , ecTrigger = TriggerAngstThreshold
  , ecCommittedAt = 1
  , ecWitnessHash = TrajectoryHash "abc"
  }

hasKey :: String -> BL.ByteString -> Bool
hasKey key blob = ("\"" <> LT.pack key <> "\"") `LT.isInfixOf` LTE.decodeUtf8 blob

conatusContourTests :: [Test]
conatusContourTests =
  [ TestLabel "contour: zero violations hold" $ TestCase $ do
      let c = computeConatusContour 0 Nothing emptyEssence True
      assertEqual "invariants" (BlanketIntegrity True 0) (ctcBlanketIntegrity c)

  , TestLabel "contour: violations are counted" $ TestCase $ do
      let c = computeConatusContour 3 Nothing emptyEssence True
      assertEqual "invariants" (BlanketIntegrity False 3) (ctcBlanketIntegrity c)

  , TestLabel "contour: no recovery cause yields an empty list" $ TestCase $
      assertEqual "events" [] (ctcRecoveryEvents
        (computeConatusContour 0 Nothing emptyEssence True))

  , TestLabel "contour: recovery cause is carried" $ TestCase $
      assertEqual "events" [RecoveryRuntimeDegraded] (ctcRecoveryEvents
        (computeConatusContour 0 (Just RecoveryRuntimeDegraded) emptyEssence True))

  , TestLabel "contour: uncommitted essence contributes zero" $ TestCase $
      assertEqual "commitments" 0 (ctcEssenceCommitments
        (computeConatusContour 0 Nothing emptyEssence True))

  , TestLabel "contour: committed essence contributes one" $ TestCase $
      assertEqual "commitments" 1 (ctcEssenceCommitments
        (computeConatusContour 0 Nothing committedEssence True))

  , TestLabel "contour: crisis availability is carried" $ TestCase $ do
      assertBool "available" (ctcCrisisAvailability
        (computeConatusContour 0 Nothing emptyEssence True))
      assertBool "unavailable" (not (ctcCrisisAvailability
        (computeConatusContour 0 Nothing emptyEssence False)))

  , TestLabel "contour: the real crisis pack is available" $ TestCase $
      assertBool "pack" (crisisPackAvailable crisisResourcesRu)

  , TestLabel "contour: a zero-version pack is unavailable" $ TestCase $
      assertBool "zero version" (not (crisisPackAvailable crisisResourcesRu
        { crVersion = 0 }))

  , TestLabel "contour: an empty pack is unavailable" $ TestCase $
      assertBool "empty lines" (not (crisisPackAvailable crisisResourcesRu
        { crLines = [] }))

  , TestLabel "contour: JSON round-trip" $ TestCase $ do
      let c = computeConatusContour 1 (Just RecoveryStateIntegrityGate) committedEssence True
      assertEqual "round-trip" (Just c) (decode (encode c))

  , TestLabel "contour: JSON keys" $ TestCase $ do
      let blob = encode (computeConatusContour 0 Nothing emptyEssence True)
      assertBool "blanket" (hasKey "ctcBlanketIntegrity" blob)
      assertBool "recovery" (hasKey "ctcRecoveryEvents" blob)
      assertBool "essence" (hasKey "ctcEssenceCommitments" blob)
      assertBool "crisis" (hasKey "ctcCrisisAvailability" blob)
      assertBool "hold" (hasKey "biInvariantsHold" blob)
      assertBool "count" (hasKey "biViolationCount" blob)
  ]
