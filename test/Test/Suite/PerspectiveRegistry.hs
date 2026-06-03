{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.PerspectiveRegistry
  ( perspectiveRegistryTests
  ) where

import Data.Aeson (decode, encode)
import qualified Data.ByteString.Lazy.Char8 as BL8
import qualified Data.Map.Strict as M
import qualified Data.Text as T
import Test.HUnit

import QxFx0.Self.Perspective
  ( applyPerspectiveDecision
  , buildActivePerspectiveProjections
  , buildPerspectiveProjection
  , opinionCore
  )
import QxFx0.Types.State
  ( ClaimStanceRef(..)
  , ConatusSlice(..)
  , CounterargumentRef(..)
  , EndorsedPerspective(..)
  , EvidenceRef(..)
  , IdentitySlice(..)
  , PerspectiveCandidate(..)
  , PerspectiveInputBundle(..)
  , PerspectiveProjection(..)
  , PerspectivePromotionDecision(..)
  , PerspectiveRegistry(..)
  , PerspectiveRevisionRecord(..)
  , PerspectiveScope(..)
  , PerspectiveStatus(..)
  , PerspectiveThread(..)
  , PerspectiveVersionId(..)
  , activeEndorsedPerspective
  , activePerspectiveProjectionScopes
  , defaultNormativeProfile
  , defaultPerspectiveRegistry
  )

perspectiveRegistryTests :: [Test]
perspectiveRegistryTests =
  [ TestLabel "PerspectiveRegistry observe-only preserves empty lineage" testObserveOnlyUpdatesTurnWithoutThread
  , TestLabel "PerspectiveRegistry promotion creates active canonical thread" testPromotionCreatesCanonicalActiveThread
  , TestLabel "PerspectiveRegistry revision marks prior active version" testRevisionMarksPriorActiveVersion
  , TestLabel "PerspectiveRegistry revision history is bounded" testRevisionHistoryIsBounded
  , TestLabel "PerspectiveRegistry inactive versions are bounded" testInactiveVersionsAreBounded
  , TestLabel "PerspectiveRegistry active cap suspends older scope" testActiveCapSuspendsOlderScope
  , TestLabel "PerspectiveRegistry suspension clears projection" testSuspensionClearsProjection
  , TestLabel "PerspectiveRegistry JSON round-trip is stable" testRegistryJsonRoundTripIsStable
  , TestLabel "PerspectiveRegistry duplicate normative profiles fail decode" testDuplicateNormativeProfilesFailDecode
  , TestLabel "PerspectiveRegistry projection caps public surface" testProjectionCapsPublicSurface
  ]

testObserveOnlyUpdatesTurnWithoutThread :: Test
testObserveOnlyUpdatesTurnWithoutThread = TestCase $ do
  let scope = ScopeTopic "freedom"
      registry = applyDecision 9 PpdObserveOnly defaultPerspectiveRegistry scope "observed only"
  assertEqual "observe-only must not create a lineage thread"
    M.empty (prThreads registry)
  assertEqual "observe-only still records the last evaluated turn"
    9 (prLastUpdatedTurn registry)
  assertEqual "observe-only must not allocate a perspective id"
    1 (prNextPerspectiveOrdinal registry)
  assertEqual "observe-only must not allocate a version id"
    1 (prNextVersionOrdinal registry)
  assertEqual "observe-only must not expose a projection"
    Nothing (buildPerspectiveProjection registry scope)

testPromotionCreatesCanonicalActiveThread :: Test
testPromotionCreatesCanonicalActiveThread = TestCase $ do
  let scope = ScopeTopic "freedom"
      registry = applyDecision 1 PpdPromoteEndorsed defaultPerspectiveRegistry scope "initial promoted thesis"
  thread <- expectJust "expected promoted perspective thread" (M.lookup scope (prThreads registry))
  active <- expectJust "expected active endorsed perspective" (activeEndorsedPerspective thread)
  projection <- expectJust "expected active projection" (buildPerspectiveProjection registry scope)
  assertEqual "first promoted scope receives version 1"
    (Just (PerspectiveVersionId 1)) (ptActiveVersion thread)
  assertEqual "thread status is active"
    PerspectiveActive (ptStatus thread)
  assertEqual "active endorsed perspective is version 1"
    (PerspectiveVersionId 1) (epVersion active)
  assertEqual "active endorsed perspective status is active"
    PerspectiveActive (epStatus active)
  assertEqual "promotion records one revision entry"
    1 (length (ptRevisionHistory thread))
  assertEqual "projection points at the active version"
    (PerspectiveVersionId 1) (ppPerspectiveVersion projection)
  assertEqual "projection is scoped through the registry thread"
    scope (ppScope projection)
  assertEqual "perspective ordinal advances after first new thread"
    2 (prNextPerspectiveOrdinal registry)
  assertEqual "version ordinal advances after first endorsed version"
    2 (prNextVersionOrdinal registry)

testRevisionMarksPriorActiveVersion :: Test
testRevisionMarksPriorActiveVersion = TestCase $ do
  let scope = ScopeTopic "freedom"
      registry1 = applyDecision 1 PpdPromoteEndorsed defaultPerspectiveRegistry scope "initial promoted thesis"
      registry2 = applyDecision 2 PpdReviseActive registry1 scope "revision one"
  thread <- expectJust "expected revised perspective thread" (M.lookup scope (prThreads registry2))
  projection <- expectJust "expected revised active projection" (buildPerspectiveProjection registry2 scope)
  assertEqual "revision makes version 2 active"
    (Just (PerspectiveVersionId 2)) (ptActiveVersion thread)
  assertBool "prior version remains in lineage as revised"
    (any (hasVersionStatus (PerspectiveVersionId 1) PerspectiveRevised) (ptVersions thread))
  assertBool "new version is the only active version"
    (oneActiveVersion (ptVersions thread))
  assertEqual "projection exposes the revised thesis"
    "revision one" (ppSummary projection)
  assertEqual "revision history keeps newest revision first"
    [PerspectiveVersionId 2, PerspectiveVersionId 1] (map prrToVersion (ptRevisionHistory thread))

testRevisionHistoryIsBounded :: Test
testRevisionHistoryIsBounded = TestCase $ do
  let scope = ScopeTopic "freedom"
      cappedRegistry = defaultPerspectiveRegistry { prMaxRevisionsPerScope = 2 }
      registry = applyMany scope cappedRegistry
        [ (1, PpdPromoteEndorsed, "initial")
        , (2, PpdReviseActive, "revision one")
        , (3, PpdReviseActive, "revision two")
        , (4, PpdReviseActive, "revision three")
        ]
  thread <- expectJust "expected bounded revision thread" (M.lookup scope (prThreads registry))
  assertEqual "revision history respects registry cap"
    2 (length (ptRevisionHistory thread))
  assertEqual "bounded history keeps the two newest versions"
    [PerspectiveVersionId 4, PerspectiveVersionId 3] (map prrToVersion (ptRevisionHistory thread))

testInactiveVersionsAreBounded :: Test
testInactiveVersionsAreBounded = TestCase $ do
  let scope = ScopeTopic "freedom"
      cappedRegistry = defaultPerspectiveRegistry { prMaxInactiveVersions = 1 }
      registry = applyMany scope cappedRegistry
        [ (1, PpdPromoteEndorsed, "initial")
        , (2, PpdReviseActive, "revision one")
        , (3, PpdReviseActive, "revision two")
        , (4, PpdReviseActive, "revision three")
        ]
  thread <- expectJust "expected bounded version thread" (M.lookup scope (prThreads registry))
  assertEqual "active plus one inactive version are retained"
    2 (length (ptVersions thread))
  assertEqual "bounded versions keep active newest plus newest inactive"
    [PerspectiveVersionId 4, PerspectiveVersionId 3] (map epVersion (ptVersions thread))
  assertEqual "retained statuses stay active/revised"
    [PerspectiveActive, PerspectiveRevised] (map epStatus (ptVersions thread))

testActiveCapSuspendsOlderScope :: Test
testActiveCapSuspendsOlderScope = TestCase $ do
  let scopeA = ScopeTopic "freedom"
      scopeB = ScopeTopic "responsibility"
      cappedRegistry = defaultPerspectiveRegistry { prMaxActivePerspectives = 1 }
      registry1 = applyDecision 1 PpdPromoteEndorsed cappedRegistry scopeA "freedom thesis"
      registry2 = applyDecision 2 PpdPromoteEndorsed registry1 scopeB "responsibility thesis"
  threadA <- expectJust "expected older thread to remain present" (M.lookup scopeA (prThreads registry2))
  threadB <- expectJust "expected newer thread to remain present" (M.lookup scopeB (prThreads registry2))
  assertEqual "newer scope is the only active projection scope under cap"
    [scopeB] (activePerspectiveProjectionScopes registry2)
  assertEqual "older thread active pointer is cleared, not deleted"
    Nothing (ptActiveVersion threadA)
  assertEqual "older thread is suspended by active cap"
    PerspectiveSuspended (ptStatus threadA)
  assertEqual "newer thread remains active"
    (Just (PerspectiveVersionId 2)) (ptActiveVersion threadB)

testSuspensionClearsProjection :: Test
testSuspensionClearsProjection = TestCase $ do
  let scope = ScopeTopic "freedom"
      registry1 = applyDecision 1 PpdPromoteEndorsed defaultPerspectiveRegistry scope "initial promoted thesis"
      registry2 = applyDecision 2 PpdSuspendActive registry1 scope "suspend candidate"
  thread <- expectJust "expected suspended thread" (M.lookup scope (prThreads registry2))
  assertEqual "suspended thread clears active pointer"
    Nothing (ptActiveVersion thread)
  assertEqual "suspended thread has suspended status"
    PerspectiveSuspended (ptStatus thread)
  assertEqual "suspended perspective does not project"
    Nothing (buildPerspectiveProjection registry2 scope)
  assertEqual "suspended registry has no active projections"
    [] (buildActivePerspectiveProjections registry2)

testRegistryJsonRoundTripIsStable :: Test
testRegistryJsonRoundTripIsStable = TestCase $ do
  let scope = ScopeTopic "freedom"
      registry = applyMany scope defaultPerspectiveRegistry
        [ (1, PpdPromoteEndorsed, "initial")
        , (2, PpdReviseActive, "revision one")
        ]
  assertEqual "registry JSON must round-trip without losing lineage"
    (Just registry) (decode (encode registry) :: Maybe PerspectiveRegistry)

testDuplicateNormativeProfilesFailDecode :: Test
testDuplicateNormativeProfilesFailDecode = TestCase $ do
  let duplicateJson = BL8.pack
        "{\"threads\":[],\"normativeProfiles\":[{\"npId\":\"duplicate\",\"npVersionId\":1,\"npPriorities\":{},\"npConflictPolicy\":\"conservative\",\"npActivationScope\":null},{\"npId\":\"duplicate\",\"npVersionId\":2,\"npPriorities\":{},\"npConflictPolicy\":\"permissive\",\"npActivationScope\":null}],\"activeNormativeProfileId\":\"duplicate\"}"
  assertEqual "duplicate normative profile ids must fail decode instead of overwriting"
    Nothing (decode duplicateJson :: Maybe PerspectiveRegistry)

testProjectionCapsPublicSurface :: Test
testProjectionCapsPublicSurface = TestCase $ do
  let scope = ScopeTopic "freedom"
      bundle = mkRichPerspectiveBundle scope
      candidate = (opinionCore bundle) { pcThesis = T.replicate 220 "x" }
      registry = applyPerspectiveDecision 1 defaultPerspectiveRegistry bundle candidate PpdPromoteEndorsed
  thread <- expectJust "expected rich projection thread" (M.lookup scope (prThreads registry))
  active <- expectJust "expected rich active perspective" (activeEndorsedPerspective thread)
  projection <- expectJust "expected rich active projection" (buildPerspectiveProjection registry scope)
  assertEqual "projection summary is capped"
    180 (T.length (ppSummary projection))
  assertEqual "projection evidence count reflects capped support surface"
    8 (ppEvidenceCount projection)
  assertEqual "projection counterargument count reflects capped counterargument surface"
    8 (ppCounterargumentCount projection)
  assertEqual "endorsed support claims are capped in canonical registry"
    8 (length (epSupportingClaims active))
  assertEqual "endorsed counterarguments are capped in canonical registry"
    8 (length (epCounterarguments active))

applyMany :: PerspectiveScope -> PerspectiveRegistry -> [(Int, PerspectivePromotionDecision, T.Text)] -> PerspectiveRegistry
applyMany scope = foldl step
  where
    step registry (turn, decision, thesis) = applyDecision turn decision registry scope thesis

applyDecision :: Int -> PerspectivePromotionDecision -> PerspectiveRegistry -> PerspectiveScope -> T.Text -> PerspectiveRegistry
applyDecision turn decision registry scope thesis =
  let bundle = mkPerspectiveBundle scope (lineageForScope scope registry)
      candidate = (opinionCore bundle) { pcThesis = thesis }
  in applyPerspectiveDecision turn registry bundle candidate decision

mkPerspectiveBundle :: PerspectiveScope -> [PerspectiveRevisionRecord] -> PerspectiveInputBundle
mkPerspectiveBundle scope lineage = PerspectiveInputBundle
  { pibScope = scope
  , pibEvidence =
      [ EvidenceRef "knowledge:bounded agency"
      , EvidenceRef "dialogue:DialogueOutcomeSuccess:stable topic"
      ]
  , pibStanceSlice = [ClaimStanceRef "stance:BeliefAffirmed:stable topic requires responsibility"]
  , pibIdentitySlice = IdentitySlice
      { isSessionId = "test-session"
      , isIdentityClaims = []
      , isIdentityClaimCount = 0
      , isTurnCount = 1
      }
  , pibConatusSlice = ConatusSlice
      { csEnergy = 10.0
      , csGateFired = False
      , csFieldConfidence = 1.0
      , csStability = 1.0
      }
  , pibNormativeProfile = defaultNormativeProfile
  , pibCounterarguments = []
  , pibRevisionLineage = lineage
  }

mkRichPerspectiveBundle :: PerspectiveScope -> PerspectiveInputBundle
mkRichPerspectiveBundle scope = (mkPerspectiveBundle scope [])
  { pibEvidence = map (EvidenceRef . ("evidence-" <>) . T.pack . show) ([1..12] :: [Int])
  , pibStanceSlice = map (ClaimStanceRef . ("stance-" <>) . T.pack . show) ([1..12] :: [Int])
  , pibCounterarguments = map (CounterargumentRef . ("counter-" <>) . T.pack . show) ([1..12] :: [Int])
  }

lineageForScope :: PerspectiveScope -> PerspectiveRegistry -> [PerspectiveRevisionRecord]
lineageForScope scope registry =
  maybe [] ptRevisionHistory (M.lookup scope (prThreads registry))

hasVersionStatus :: PerspectiveVersionId -> PerspectiveStatus -> EndorsedPerspective -> Bool
hasVersionStatus version status endorsed =
  epVersion endorsed == version && epStatus endorsed == status

oneActiveVersion :: [EndorsedPerspective] -> Bool
oneActiveVersion versions =
  length (filter ((== PerspectiveActive) . epStatus) versions) == 1

expectJust :: String -> Maybe a -> IO a
expectJust label value =
  case value of
    Nothing -> assertFailure label >> fail label
    Just found -> pure found
