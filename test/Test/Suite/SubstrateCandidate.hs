{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.SubstrateCandidate (substrateCandidateTests) where

import Test.HUnit
import Data.Text (Text)
import qualified Data.Text as T
import QxFx0.Semantic.Content.AtomStore
import QxFx0.Semantic.Content.SubstrateCandidate
import QxFx0.Semantic.Content.GeneratedPredicateGate
import QxFx0.Semantic.Network.Substrate (BrainKBEntry(..))

substrateCandidateTests :: [Test]
substrateCandidateTests =
  [ TestLabel "Substrate extraction" extractionTests
  , TestLabel "Substrate admission" admissionTests
  , TestLabel "Substrate promotion" promotionTests
  , TestLabel "Substrate gate enforcement" gateEnforcementTests
  , TestLabel "Substrate determinism" determinismTests
  ]

-- Helper: sample brain_kb entry with philosophical content
sampleEntry :: BrainKBEntry
sampleEntry = BrainKBEntry
  { beText = "свобода требует ответственности перед другими"
  , beTopics = ["freedom", "responsibility"]
  , beTriggers = ["свобода", "ответственность", "требует"]
  , beLayer = "ontology"
  , beKind = "relation"
  }

sampleEntry2 :: BrainKBEntry
sampleEntry2 = BrainKBEntry
  { beText = "истина предполагает соответствие реальности"
  , beTopics = ["truth"]
  , beTriggers = ["истина", "соответствие"]
  , beLayer = "ontology"
  , beKind = "relation"
  }

sampleEntryNoTopic :: BrainKBEntry
sampleEntryNoTopic = BrainKBEntry
  { beText = "что-то происходит"
  , beTopics = []
  , beTriggers = ["что-то"]
  , beLayer = "other"
  , beKind = "note"
  }

ourTopics :: [Text]
ourTopics = allTopics

knownAtomIds :: [AtomId]
knownAtomIds = map AtomId ourTopics

extractionTests :: Test
extractionTests = TestList
  [ TestCase $ do
      let cands = extractCandidatesFromEntry ourTopics sampleEntry
      assertBool ("extraction produces >= 1 candidate, got " <> show (length cands))
                 (length cands >= 1)

  , TestCase $ do
      let cands = extractCandidatesFromEntry ourTopics sampleEntry
          -- свобода and ответственность are both philosophical topics in triggers
          allValidTopics = all (\c -> scFromTopic c == "свобода" || scFromTopic c == "ответственность") cands
      assertEqual "all candidates have valid philosophical topic" True allValidTopics

  , TestCase $ do
      let cands = extractCandidatesFromEntry ourTopics sampleEntryNoTopic
      assertEqual "no-topic entry produces 0 candidates" 0 (length cands)

  , TestCase $ do
      let cands = extractCandidates [sampleEntry, sampleEntry2] ourTopics
      assertBool ("batch extraction >= 2, got " <> show (length cands))
                 (length cands >= 2)

  , TestCase $ do
      let cands = extractCandidatesFromEntry ourTopics sampleEntry
          allHaveSpan = all (\c -> ssLayer (scSourceSpan c) == "ontology") cands
      assertEqual "all candidates carry source span" True allHaveSpan
  ]

admissionTests :: Test
admissionTests = TestList
  [ TestCase $ do
      let cand = SubstrateCandidate
            { scFromTopic = "свобода"
            , scToAtomSurface = "ответственность"
            , scRelTypeGuess = "требует"
            , scConfidence = 0.5
            , scSourceSpan = SourceSpan "test" "ontology" "relation"
            , scRawText = "свобода требует ответственности"
            }
          status = admitCandidate defaultAdmissionConfig knownAtomIds cand
      assertEqual "valid candidate admitted" Admitted status

  , TestCase $ do
      let cand = SubstrateCandidate
            { scFromTopic = "несуществующий"
            , scToAtomSurface = "что-то"
            , scRelTypeGuess = "требует"
            , scConfidence = 0.5
            , scSourceSpan = SourceSpan "test" "ontology" "relation"
            , scRawText = "test"
            }
          status = admitCandidate defaultAdmissionConfig knownAtomIds cand
      case status of
        Rejected _ -> assertBool "unknown topic rejected" True
        Admitted  -> assertFailure "unknown topic should be rejected"

  , TestCase $ do
      let cand = SubstrateCandidate
            { scFromTopic = "свобода"
            , scToAtomSurface = "ответственность"
            , scRelTypeGuess = "неизвестный_глагол"
            , scConfidence = 0.5
            , scSourceSpan = SourceSpan "test" "ontology" "relation"
            , scRawText = "test"
            }
          status = admitCandidate defaultAdmissionConfig knownAtomIds cand
      case status of
        Rejected _ -> assertBool "unknown verb rejected" True
        Admitted  -> assertFailure "unknown verb should be rejected"

  , TestCase $ do
      let cand = SubstrateCandidate
            { scFromTopic = "свобода"
            , scToAtomSurface = "свобода"  -- self-referential
            , scRelTypeGuess = "требует"
            , scConfidence = 0.5
            , scSourceSpan = SourceSpan "test" "ontology" "relation"
            , scRawText = "test"
            }
          status = admitCandidate defaultAdmissionConfig knownAtomIds cand
      case status of
        Rejected _ -> assertBool "self-referential rejected" True
        Admitted  -> assertFailure "self-referential should be rejected"

  , TestCase $ do
      let cand = SubstrateCandidate
            { scFromTopic = "свобода"
            , scToAtomSurface = "ответственность"
            , scRelTypeGuess = "требует"
            , scConfidence = 0.1  -- below threshold
            , scSourceSpan = SourceSpan "test" "ontology" "relation"
            , scRawText = "test"
            }
          status = admitCandidate defaultAdmissionConfig knownAtomIds cand
      case status of
        Rejected _ -> assertBool "low confidence rejected" True
        Admitted  -> assertFailure "low confidence should be rejected"
  ]

promotionTests :: Test
promotionTests = TestList
  [ TestCase $ do
      let cand = SubstrateCandidate
            { scFromTopic = "свобода"
            , scToAtomSurface = "ответственность"
            , scRelTypeGuess = "требует"
            , scConfidence = 0.5
            , scSourceSpan = SourceSpan "test" "ontology" "relation"
            , scRawText = "свобода требует ответственности"
            }
          rel = promoteToRelation cand
      assertEqual "promoted source is PromotedSubstrate" PromotedSubstrate (relSource rel)
      assertEqual "promoted from is свобода" (AtomId "свобода") (relFrom rel)
      assertEqual "promoted relType is RelRequires" RelRequires (relType rel)

  , TestCase $ do
      let cands = [ SubstrateCandidate
                      { scFromTopic = "истина"
                      , scToAtomSurface = "истина"
                      , scRelTypeGuess = "претендует"
                      , scConfidence = 0.5
                      , scSourceSpan = SourceSpan "test" "ontology" "relation"
                      , scRawText = "test"
                      }
                  ]
          rels = promoteAll cands
      assertEqual "1 promoted relation" 1 (length rels)
      assertEqual "source is PromotedSubstrate" PromotedSubstrate (relSource (head rels))
  ]

gateEnforcementTests :: Test
gateEnforcementTests = TestList
  [ TestCase $ do
      -- Promoted substrate relations should pass Gate G4
      let cand = SubstrateCandidate
            { scFromTopic = "свобода"
            , scToAtomSurface = "ответственность"
            , scRelTypeGuess = "требует"
            , scConfidence = 0.5
            , scSourceSpan = SourceSpan "test" "ontology" "relation"
            , scRawText = "test"
            }
          rel = promoteToRelation cand
          proof = PathProof [rel] "свобода"
          g4 = gateSourceWhitelist proof
      assertEqual "PromotedSubstrate passes G4" GatePass g4

  , TestCase $ do
      -- SubstrateExtractedRaw should fail Gate G4
      let rel = Relation
            { relFrom = AtomId "свобода"
            , relTo = AtomId "выбор"
            , relType = RelPresupposes
            , relObjectCase = CaseAccusative
            , relObjectText = "выбор"
            , relVerbText = Nothing
            , relRuOriginal = "test"
            , relEnOriginal = ""
            , relSource = SubstrateExtractedRaw
            , relTopic = "свобода"
            }
          proof = PathProof [rel] "свобода"
          g4 = gateSourceWhitelist proof
      case g4 of
        GateFail _ -> assertBool "SubstrateExtractedRaw fails G4" True
        GatePass  -> assertFailure "SubstrateExtractedRaw should fail G4"
  ]

determinismTests :: Test
determinismTests = TestList
  [ TestCase $ do
      let c1 = extractCandidates [sampleEntry] ourTopics
          c2 = extractCandidates [sampleEntry] ourTopics
      assertEqual "extraction is deterministic" c1 c2

  , TestCase $ do
      let c1 = promoteAll (fst (admitCandidates defaultAdmissionConfig knownAtomIds
                                (extractCandidates [sampleEntry] ourTopics)))
          c2 = promoteAll (fst (admitCandidates defaultAdmissionConfig knownAtomIds
                                (extractCandidates [sampleEntry] ourTopics)))
      assertEqual "promotion is deterministic" c1 c2
  ]
