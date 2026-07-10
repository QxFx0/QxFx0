{-# LANGUAGE OverloadedStrings #-}

-- | ADR-0053 regression tests: runtime LLM external-query responses
-- are parsed into relations, admitted through the selfplay gate, and
-- merged into the runtime semantic network.
module Test.Suite.RuntimeLLMToNetwork
  ( runtimeLLMToNetworkTests
  ) where

import qualified Data.Map.Strict as M
import Data.Maybe (isJust)
import Data.Text (Text)
import Test.HUnit

import QxFx0.Learning.Loop (applyLLMResponseToSemanticNetwork)
import QxFx0.Learning.Need (LearningNeed(..))
import QxFx0.Semantic.Content.AtomStore (RelationType(..))
import QxFx0.Semantic.Network.Types (SemanticNetwork(..), SemanticEdge(..))
import QxFx0.Types.ExternalQuery (ExternalQueryResponse(..))

mkResponse :: Text -> ExternalQueryResponse
mkResponse body = ExternalQueryResponse
  { eqrRawBody    = body
  , eqrStructured = ""
  , eqrToolName   = "test_tool"
  , eqrLatencyMs  = 0
  }

testAdmittedRelationBecomesEdge :: Test
testAdmittedRelationBecomesEdge = TestLabel "admitted LLM relation becomes semantic edge" $ TestCase $
  let body = "свобода | предполагает | выбор | presupposes\n"
      sn = applyLLMResponseToSemanticNetwork NeedKeywordEnrichment (mkResponse body)
  in do
    assertBool "edge key should exist" (isJust (M.lookup ("свобода", "выбор") (snEdges sn)))
    let Just edge = M.lookup ("свобода", "выбор") (snEdges sn)
    assertEqual "relation type" (Just RelPresupposes) (seRelationType edge)
    assertEqual "confidence seeded low" 0.6 (seConfidence edge)

testUnknownEndpointIsRejected :: Test
testUnknownEndpointIsRejected = TestLabel "unknown relation endpoint is rejected" $ TestCase $
  let body = "свобода | предполагает | несуществующий_атом_12345 | presupposes\n"
      sn = applyLLMResponseToSemanticNetwork NeedKeywordEnrichment (mkResponse body)
  in assertBool "no edges should be admitted" (M.null (snEdges sn))

testStructuredBodyPreferred :: Test
testStructuredBodyPreferred = TestLabel "structured body preferred over raw body" $ TestCase $
  let rawBody    = "свобода | связана | долг | relatedto\n"
      structured = "ответственность | требует | выбор | requires\n"
      sn = applyLLMResponseToSemanticNetwork NeedKeywordEnrichment
             (mkResponse rawBody) { eqrStructured = structured }
  in assertBool "structured relation should be present" (isJust (M.lookup ("ответственность", "выбор") (snEdges sn)))

runtimeLLMToNetworkTests :: [Test]
runtimeLLMToNetworkTests =
  [ testAdmittedRelationBecomesEdge
  , testUnknownEndpointIsRejected
  , testStructuredBodyPreferred
  ]
