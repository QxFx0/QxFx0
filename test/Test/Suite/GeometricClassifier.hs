{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.GeometricClassifier (geometricClassifierTests) where

import Test.HUnit
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import qualified Data.Vector as V

import QxFx0.Semantic.Space.Types
import QxFx0.Semantic.Space (cosineSimilarity, projectAtoms)
import QxFx0.Semantic.Intent.GeometricClassifier
import QxFx0.Semantic.Intent.Metrics
import QxFx0.Types.PropositionType (PropositionType(..))
import QxFx0.Types (CanonicalMoveFamily(..))

geometricClassifierTests :: [Test]
geometricClassifierTests =
  [ cosineSimilarityTests
  , projectAtomsTests
  , buildClassifierTests
  , classifyIntentTests
  , intentToFamilyTests
  , metricsTests
  ]

mkTestSpace :: SemanticSpace
mkTestSpace = SemanticSpace
  { ssDimensionCount = 4
  , ssAtomIndex = M.fromList [("a", 0), ("b", 1), ("c", 2), ("d", 3)]
  , ssPrototypes = M.empty
  , ssPredicateVectors = M.empty
  , ssFactVectors = M.empty
  }

cosineSimilarityTests :: Test
cosineSimilarityTests = TestLabel "CosineSimilarity" $ TestList
  [ TestCase $ do
      let v1 = AtomVector (V.fromList [1.0, 0.0, 0.0])
          v2 = AtomVector (V.fromList [1.0, 0.0, 0.0])
          sim = cosineSimilarity v1 v2
      assertBool "identical vectors should have similarity 1.0" (abs (sim - 1.0) < 0.001)

  , TestCase $ do
      let v1 = AtomVector (V.fromList [1.0, 0.0])
          v2 = AtomVector (V.fromList [0.0, 1.0])
          sim = cosineSimilarity v1 v2
      assertBool "orthogonal vectors should have similarity 0.0" (abs sim < 0.001)

  , TestCase $ do
      let v1 = AtomVector (V.fromList [0.0, 0.0])
          v2 = AtomVector (V.fromList [1.0, 1.0])
          sim = cosineSimilarity v1 v2
      assertBool "zero vector should have similarity 0.0" (abs sim < 0.001)
  ]

projectAtomsTests :: Test
projectAtomsTests = TestLabel "ProjectAtoms" $ TestList
  [ TestCase $ do
      let space = mkTestSpace
          atoms = S.fromList ["a", "c"]
          vec = projectAtoms atoms space
      assertEqual "vector length" 4 (V.length (unAtomVector vec))
      assertBool "atom 'a' at index 0" (unAtomVector vec V.! 0 > 0.5)
      assertBool "atom 'b' at index 1 is 0" (unAtomVector vec V.! 1 < 0.5)
      assertBool "atom 'c' at index 2" (unAtomVector vec V.! 2 > 0.5)
      assertBool "atom 'd' at index 3 is 0" (unAtomVector vec V.! 3 < 0.5)

  , TestCase $ do
      let space = mkTestSpace
          atoms = S.fromList ["unknown"]
          vec = projectAtoms atoms space
      assertBool "unknown atom produces zero vector" (V.sum (unAtomVector vec) < 0.001)
  ]

buildClassifierTests :: Test
buildClassifierTests = TestLabel "BuildClassifier" $ TestList
  [ TestCase $ do
      let space = mkTestSpace
          labeled = M.fromList [(ConceptKnowledgeQ, S.fromList ["a", "b"])]
          classifier = buildClassifier space labeled
      assertEqual "one cluster" 1 (M.size (icClusters classifier))
      assertEqual "k=3" 3 (icK classifier)
      assertBool "min similarity > 0" (icMinSimilarity classifier > 0)

  , TestCase $ do
      let space = mkTestSpace
          labeled = M.empty
          classifier = buildClassifier space labeled
      assertEqual "empty labeled -> no clusters" 0 (M.size (icClusters classifier))
  ]

classifyIntentTests :: Test
classifyIntentTests = TestLabel "ClassifyIntent" $ TestList
  [ TestCase $ do
      let space = mkTestSpace
          labeled = M.fromList [(ConceptKnowledgeQ, S.fromList ["a", "b"])]
          classifier = buildClassifier space labeled
          result = classifyIntent classifier (S.fromList ["a", "b"])
      case result of
        Classified intent sim -> do
          assertEqual "intent" ConceptKnowledgeQ intent
          assertBool "similarity > 0.5" (sim > 0.5)
        Unclassified -> assertFailure "expected Classified"

  , TestCase $ do
      let space = mkTestSpace
          labeled = M.fromList [(ConceptKnowledgeQ, S.fromList ["a", "b"])]
          classifier = buildClassifier space labeled
          result = classifyIntent classifier (S.fromList ["unknown1", "unknown2"])
      assertEqual "unknown atoms -> Unclassified" Unclassified result

  , TestCase $ do
      let space = mkTestSpace
          classifier = buildClassifier space M.empty
          result = classifyIntent classifier (S.fromList ["a"])
      assertEqual "empty classifier -> Unclassified" Unclassified result
  ]

intentToFamilyTests :: Test
intentToFamilyTests = TestLabel "IntentToFamily" $ TestList
  [ TestCase $ do
      let allTypes = [minBound..maxBound] :: [PropositionType]
          mapped = map intentToFamily allTypes
          expectedMapped = [Just CMDefine, Just CMDistinguish, Just CMGround, Nothing, Nothing,
                           Just CMPurpose, Nothing, Just CMRepair, Just CMContact, Nothing,
                           Nothing, Just CMDeepen, Just CMConfront, Just CMNextStep, Nothing,
                           Nothing, Nothing, Nothing, Nothing, Nothing, Nothing, Nothing,
                           Nothing, Just CMReflect, Nothing, Just CMDefine, Just CMHypothesis,
                           Nothing, Nothing, Nothing, Nothing, Nothing, Nothing, Nothing]
      assertEqual "all PropositionType constructors mapped" expectedMapped mapped
  , TestCase $ assertEqual "DefinitionalQ" (Just CMDefine) (intentToFamily DefinitionalQ)
  , TestCase $ assertEqual "SelfKnowledgeQ" (Just CMReflect) (intentToFamily SelfKnowledgeQ)
  , TestCase $ assertEqual "ConceptKnowledgeQ" (Just CMDefine) (intentToFamily ConceptKnowledgeQ)
  , TestCase $ assertEqual "DistinctionQ" (Just CMDistinguish) (intentToFamily DistinctionQ)
  , TestCase $ assertEqual "ConfrontQ" (Just CMConfront) (intentToFamily ConfrontQ)
  , TestCase $ assertEqual "GroundQ" (Just CMGround) (intentToFamily GroundQ)
  , TestCase $ assertEqual "RepairSignal" (Just CMRepair) (intentToFamily RepairSignal)
  , TestCase $ assertEqual "ContactSignal" (Just CMContact) (intentToFamily ContactSignal)
  , TestCase $ assertEqual "PurposeQ" (Just CMPurpose) (intentToFamily PurposeQ)
  , TestCase $ assertEqual "WorldCauseQ" (Just CMHypothesis) (intentToFamily WorldCauseQ)
  , TestCase $ assertEqual "DeepenQ" (Just CMDeepen) (intentToFamily DeepenQ)
  , TestCase $ assertEqual "NextStepQ" (Just CMNextStep) (intentToFamily NextStepQ)
  , TestCase $ assertEqual "PlainAssert" Nothing (intentToFamily PlainAssert)
  ]

metricsTests :: Test
metricsTests = TestLabel "IntentClassifierMetrics" $ TestList
  [ TestCase $ do
      let m = emptyIntentClassifierMetrics
      assertEqual "total" 0 (icmTotalClassifications m)
      assertEqual "classified" 0 (icmClassifiedCount m)
      assertEqual "unclassified" 0 (icmUnclassifiedCount m)
      assertEqual "agree" 0 (icmAgreementCount m)
      assertEqual "disagree" 0 (icmDisagreementCount m)

  , TestCase $ do
      let space = mkTestSpace
          labeled = M.fromList [(ConceptKnowledgeQ, S.fromList ["a", "b"])]
          classifier = buildClassifier space labeled
          result = classifyIntent classifier (S.fromList ["a", "b"])
          m0 = emptyIntentClassifierMetrics
          m1 = recordABValidation m0 result CMDefine
      assertEqual "total=1" 1 (icmTotalClassifications m1)
      assertEqual "classified=1" 1 (icmClassifiedCount m1)
      assertEqual "agree=1" 1 (icmAgreementCount m1)
      assertEqual "disagree=0" 0 (icmDisagreementCount m1)

  , TestCase $ do
      let space = mkTestSpace
          labeled = M.fromList [(ConceptKnowledgeQ, S.fromList ["a", "b"])]
          classifier = buildClassifier space labeled
          result = classifyIntent classifier (S.fromList ["a", "b"])
          m0 = emptyIntentClassifierMetrics
          m1 = recordABValidation m0 result CMConfront
      assertEqual "total=1" 1 (icmTotalClassifications m1)
      assertEqual "agree=0" 0 (icmAgreementCount m1)
      assertEqual "disagree=1" 1 (icmDisagreementCount m1)

  , TestCase $ do
      let m0 = emptyIntentClassifierMetrics
          m1 = recordABValidation m0 Unclassified CMGround
      assertEqual "total=1" 1 (icmTotalClassifications m1)
      assertEqual "unclassified=1" 1 (icmUnclassifiedCount m1)
      assertEqual "agree=0" 0 (icmAgreementCount m1)
  ]
