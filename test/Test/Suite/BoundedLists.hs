{-# LANGUAGE OverloadedStrings #-}
module Test.Suite.BoundedLists
  ( boundedListsTests
  ) where

import Test.HUnit (Test(..), assertFailure)
import Test.QuickCheck
  ( Gen
  , Property
  , choose
  , chooseInt
  , elements
  , forAll
  , maxSuccess
  , quickCheckWithResult
  , stdArgs
  )
import Test.QuickCheck.Test (isSuccess)

import qualified Data.Text as T

import QxFx0.Learning.Calibration (CalibrationId(..))
import QxFx0.Learning.Guardrails
  ( GuardrailState(..)
  , recordProposalSubmission
  , quarantineProposal
  , maxQuarantineEntries
  )
import QxFx0.Learning.KnowledgeTree
  ( KnowledgeSource(..)
  , KnowledgeFruit(..)
  , KnowledgeTree(..)
  , emptyKnowledgeTree
  , quarantineFruit
  , promoteFromQuarantine
  , maxKnowledgeQuarantineSize
  )
import QxFx0.Semantic.AtomAccretion
  ( observeNovelAtom
  , decayProvisionalAtoms
  , promoteProvisionalAtoms
  )
import QxFx0.Types.Domain.Atoms
  ( AtomTag(..)
  , defaultProvisionalAtomTTL
  )

-- Matching the constant in QxFx0.Core.TurnPipeline.Finalize.State
maxProvisionalAtoms :: Int
maxProvisionalAtoms = 1000

boundedListsTests :: [Test]
boundedListsTests =
  [ TestLabel "gsQuarantine: recordProposalSubmission never exceeds maxQuarantineSize" $
      quickCheckProperty "gsQuarantine record cap" prop_gsQuarantine_record_cap
  , TestLabel "gsQuarantine: quarantineProposal never exceeds maxQuarantineSize" $
      quickCheckProperty "gsQuarantine quarantine cap" prop_gsQuarantine_quarantine_cap
  , TestLabel "ssProvisionalAtoms: observeNovelAtom loop capped by maxProvisionalAtoms" $
      quickCheckProperty "ssProvisionalAtoms cap" prop_ssProvisionalAtoms_cap
  , TestLabel "ktQuarantine: quarantineFruit never exceeds maxKnowledgeQuarantineSize" $
      quickCheckProperty "ktQuarantine quarantineFruit cap" prop_ktQuarantine_quarantineFruit_cap
  , TestLabel "ktQuarantine: promoteFromQuarantine keeps quarantine bounded" $
      quickCheckProperty "ktQuarantine promote cap" prop_ktQuarantine_promote_cap
  ]

quickCheckProperty :: String -> Property -> Test
quickCheckProperty label prop =
  TestCase $ do
    result <- quickCheckWithResult stdArgs { maxSuccess = 200 } prop
    unless (isSuccess result) $
      assertFailure (label <> ": QuickCheck failed")
  where
    unless p action = if p then pure () else action

----------------------------------------------------------------------
-- gsQuarantine generators
----------------------------------------------------------------------

arbitraryCalibrationId :: Gen CalibrationId
arbitraryCalibrationId = CalibrationId <$> chooseInt (0, 1000000)

arbitraryGuardrailState :: Gen GuardrailState
arbitraryGuardrailState = do
  lastProposal <- chooseInt (0, 1000)
  proposalsWindow <- chooseInt (0, 10)
  windowStart <- chooseInt (0, lastProposal)
  consecRejections <- chooseInt (0, 5)
  cooldownExpiry <- chooseInt (0, 1000)
  qLen <- chooseInt (0, maxQuarantineEntries * 2)
  tags <- vectorOf qLen arbitraryCalibrationId
  turns <- vectorOf qLen (chooseInt (0, 1000))
  pure GuardrailState
    { gsLastProposalTurn = lastProposal
    , gsProposalsThisWindow = proposalsWindow
    , gsWindowStart = windowStart
    , gsConsecutiveRejections = consecRejections
    , gsCooldownExpiry = cooldownExpiry
    , gsQuarantine = zip turns tags
      }

prop_gsQuarantine_record_cap :: Property
prop_gsQuarantine_record_cap =
  forAll arbitraryGuardrailState $ \gs ->
  forAll (chooseInt (0, 10000)) $ \turn ->
  forAll arbitraryCalibrationId $ \cid ->
    let gs' = recordProposalSubmission gs turn cid
    in length (gsQuarantine gs') <= maxQuarantineEntries

prop_gsQuarantine_quarantine_cap :: Property
prop_gsQuarantine_quarantine_cap =
  forAll arbitraryGuardrailState $ \gs ->
  forAll (chooseInt (0, 10000)) $ \turn ->
  forAll arbitraryCalibrationId $ \cid ->
    let gs' = quarantineProposal gs turn cid
    in length (gsQuarantine gs') <= maxQuarantineEntries

----------------------------------------------------------------------
-- ssProvisionalAtoms generators
----------------------------------------------------------------------

-- | Generate a list of unique atom tags, each with a distinct label
-- so they never collide during observation.
arbitraryUniqueAtomTags :: Int -> Gen [AtomTag]
arbitraryUniqueAtomTags n = do
  labels <- vectorOf n (chooseInt (0, 1000000))
  kind <- elements
    [ \l -> Searching (T.pack $ show l)
    , \l -> Exhaustion (T.pack $ show l)
    , \l -> Verification (T.pack $ show l)
    , \l -> Doubt (T.pack $ show l)
    , \l -> NeedContact (T.pack $ show l)
    , \l -> NeedMeaning (T.pack $ show l)
    , \l -> Anchoring (T.pack $ show l)
    ]
  pure $ map kind labels

----------------------------------------------------------------------
-- ssProvisionalAtoms properties
----------------------------------------------------------------------

prop_ssProvisionalAtoms_cap :: Property
prop_ssProvisionalAtoms_cap =
  forAll (chooseInt (maxProvisionalAtoms, maxProvisionalAtoms * 2)) $ \numObserved ->
  forAll (arbitraryUniqueAtomTags numObserved) $ \tags ->
  forAll (chooseInt (1, defaultProvisionalAtomTTL)) $ \turn ->
    let observed = foldr (\tag acc -> observeNovelAtom tag turn acc) [] tags
        decayed = decayProvisionalAtoms (turn + defaultProvisionalAtomTTL + 1) observed
        (remaining, _promoted) = promoteProvisionalAtoms turn decayed
        capped = take maxProvisionalAtoms remaining
    in length capped <= maxProvisionalAtoms

----------------------------------------------------------------------
-- ktQuarantine generators
----------------------------------------------------------------------

arbitraryKnowledgeSource :: Gen KnowledgeSource
arbitraryKnowledgeSource = elements [SourceInternal, SourceLLM, SourceHuman, SourceScript]

arbitraryKnowledgeFruit :: Gen KnowledgeFruit
arbitraryKnowledgeFruit = do
  prop <- T.pack . show <$> chooseInt (0, 1000)
  word <- T.pack . show <$> chooseInt (0, 100)
  src <- arbitraryKnowledgeSource
  validated <- elements [True, False]
  cd <- choose (-0.35, 0.40)
  pd <- choose (-0.40, 0.50)
  obs <- chooseInt (0, 1000)
  pure KnowledgeFruit
    { kfProposition = prop
    , kfWord = word
    , kfSource = src
    , kfValidated = validated
    , kfConatusDelta = cd
    , kfPredictiveDelta = pd
    , kfGraftedTurn = Nothing
    , kfObservedTurn = obs
    }

-- | Generate a KnowledgeTree with an arbitrary quarantine list.
arbitraryKnowledgeTree :: Gen KnowledgeTree
arbitraryKnowledgeTree = do
  qLen <- chooseInt (0, maxKnowledgeQuarantineSize * 3)
  fruits <- vectorOf qLen arbitraryKnowledgeFruit
  pure emptyKnowledgeTree { ktQuarantine = fruits }

----------------------------------------------------------------------
-- ktQuarantine properties
----------------------------------------------------------------------

prop_ktQuarantine_quarantineFruit_cap :: Property
prop_ktQuarantine_quarantineFruit_cap =
  forAll arbitraryKnowledgeTree $ \kt ->
  forAll arbitraryKnowledgeFruit $ \fruit ->
    let kt' = quarantineFruit fruit kt
    in length (ktQuarantine kt') <= maxKnowledgeQuarantineSize

prop_ktQuarantine_promote_cap :: Property
prop_ktQuarantine_promote_cap =
  forAll arbitraryKnowledgeTree $ \kt ->
  forAll (chooseInt (1, 1000)) $ \turn ->
  forAll (chooseInt (1, 50)) $ \minAge ->
  forAll (elements ["rule_a", "rule_b", "rule_c"]) $ \rule ->
    let (kt', _, _) = promoteFromQuarantine turn minAge rule kt
    in length (ktQuarantine kt') <= maxKnowledgeQuarantineSize

----------------------------------------------------------------------
-- Utilities (for older QuickCheck without built-in vectorOf)
----------------------------------------------------------------------

vectorOf :: Int -> Gen a -> Gen [a]
vectorOf n g
  | n <= 0 = pure []
  | otherwise = sequence (replicate n g)
