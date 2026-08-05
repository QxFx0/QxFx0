{-# LANGUAGE OverloadedStrings #-}

module Test.Suite.NetworkTypes
  ( networkTypesTests
  ) where

import qualified Data.ByteString.Lazy.Char8 as BL8
import Data.Aeson (eitherDecodeStrict, encode)
import Test.HUnit

import QxFx0.Semantic.Content.AtomStore (RelationType(..))
import QxFx0.Semantic.Network.Types

-- | Old-format persisted SemanticEdge with only the original five fields.
oldFormatJSON :: BL8.ByteString
oldFormatJSON =
  "{\"seFrom\":\"a\",\"seTo\":\"b\",\"seWeight\":0.5,\"seCoOccurrence\":3,\"seSource\":\"ExplicitEdge\"}"

networkTypesTests :: [Test]
networkTypesTests =
  [ TestLabel "old-format 5-field SemanticEdge JSON decodes with defaults" $ TestCase $
      case eitherDecodeStrict (BL8.toStrict oldFormatJSON) :: Either String SemanticEdge of
        Left err -> assertFailure ("decode failed: " ++ err)
        Right edge -> do
          assertEqual "seFrom" "a" (seFrom edge)
          assertEqual "seTo" "b" (seTo edge)
          assertEqual "seWeight" 0.5 (seWeight edge)
          assertEqual "seCoOccurrence" 3 (seCoOccurrence edge)
          assertEqual "seSource" ExplicitEdge (seSource edge)
          assertEqual "seRelationType" Nothing (seRelationType edge)
          assertEqual "seVerb" Nothing (seVerb edge)
          assertEqual "seRationale" Nothing (seRationale edge)
          assertEqual "seCounter" Nothing (seCounter edge)
          assertEqual "seSynthesis" Nothing (seSynthesis edge)
          assertEqual "seConfidence" 1.0 (seConfidence edge)
          assertEqual "seProvenance" ProvenanceCurated (seProvenance edge)
          assertEqual "seDomain" Nothing (seDomain edge)
          assertEqual "seTemporalScope" Nothing (seTemporalScope edge)
          assertEqual "seNamespace" Nothing (seNamespace edge)
          assertEqual "seLineage" Nothing (seLineage edge)
  , TestLabel "new-format SemanticEdge JSON round-trips" $ TestCase $
      let edge = SemanticEdge
            { seFrom         = "x"
            , seTo           = "y"
            , seWeight       = 0.9
            , seCoOccurrence = 2
            , seSource       = ExplicitEdge
            , seRelationType = Just RelIsA
            , seVerb         = Just "является"
            , seRationale    = Just "rationale"
            , seCounter      = Just "counter"
            , seSynthesis    = Just "synthesis"
            , seConfidence   = 0.8
            , seProvenance   = ProvenanceIngested
            , seDomain       = Nothing
            , seTemporalScope = Nothing
            , seNamespace    = Nothing
            , seLineage      = Nothing
            }
      in case eitherDecodeStrict (BL8.toStrict (encode edge)) :: Either String SemanticEdge of
           Left err -> assertFailure ("round-trip failed: " ++ err)
           Right decoded -> assertEqual "round-trip" edge decoded
  , TestLabel "new-format SemanticEdge encodes all fields" $ TestCase $
      let edge = SemanticEdge
            { seFrom         = "x"
            , seTo           = "y"
            , seWeight       = 0.9
            , seCoOccurrence = 2
            , seSource       = ExplicitEdge
            , seRelationType = Just RelIsA
            , seVerb         = Just "является"
            , seRationale    = Just "rationale"
            , seCounter      = Just "counter"
            , seSynthesis    = Just "synthesis"
            , seConfidence   = 0.8
            , seProvenance   = ProvenanceIngested
            , seDomain       = Nothing
            , seTemporalScope = Nothing
            , seNamespace    = Nothing
            , seLineage      = Nothing
            }
          jsonText = BL8.unpack (encode edge)
      in do
        assertBool "must contain relation_type" ("\"relation_type\"" `isInfixOf` jsonText)
        assertBool "must contain verb" ("\"verb\"" `isInfixOf` jsonText)
        assertBool "must contain rationale" ("\"rationale\"" `isInfixOf` jsonText)
        assertBool "must contain counter" ("\"counter\"" `isInfixOf` jsonText)
        assertBool "must contain synthesis" ("\"synthesis\"" `isInfixOf` jsonText)
        assertBool "must contain confidence" ("\"confidence\"" `isInfixOf` jsonText)
        assertBool "must contain provenance" ("\"provenance\"" `isInfixOf` jsonText)
        assertBool "must contain seDomain" ("\"seDomain\"" `isInfixOf` jsonText)
        assertBool "must contain seTemporalScope" ("\"seTemporalScope\"" `isInfixOf` jsonText)
        assertBool "must contain seNamespace" ("\"seNamespace\"" `isInfixOf` jsonText)
        assertBool "must contain seLineage" ("\"seLineage\"" `isInfixOf` jsonText)
        assertBool "must contain seFrom" ("\"seFrom\"" `isInfixOf` jsonText)
  ]
  where
    isInfixOf :: String -> String -> Bool
    isInfixOf needle haystack = any (isPrefixOf needle) (tails haystack)

    isPrefixOf :: String -> String -> Bool
    isPrefixOf [] _ = True
    isPrefixOf _ [] = False
    isPrefixOf (x:xs) (y:ys) = x == y && isPrefixOf xs ys

    tails :: String -> [String]
    tails [] = [[]]
    tails xs@(_:xs') = xs : tails xs'
