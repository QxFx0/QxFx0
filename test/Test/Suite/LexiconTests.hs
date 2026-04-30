{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Test.Suite.LexiconTests
  ( lexiconTests
  ) where

import Test.HUnit
import Data.Aeson (eitherDecodeStrict')
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import qualified Data.Text.Encoding as TE
import qualified Data.Map.Strict as Map
import System.FilePath ((</>))
import System.Directory (doesFileExist)

import QxFx0.Types (MorphologyData(..))
import QxFx0.Types.Domain.Atoms
  ( LexemeForm(..)
  , LexemeCase(..)
  , LexemeNumber(..)
  , SourceTier(..)
  )
import QxFx0.Lexicon.Inflection (toNominative, genitiveForm, accusativeForm, prepositionalForm)
import QxFx0.Lexicon.Resolver (resolveLexemeForm, tierPriority)

lexiconTests :: [Test]
lexiconTests =
  [ TestLabel "resolver priority: curated beats auto-verified" (TestCase testResolverPriorityCuratedBeatsAutoVerified)
  , TestLabel "resolver priority: brain-kb-reviewed beats auto-verified" (TestCase testResolverPriorityBrainReviewedBeatsAutoVerified)
  , TestLabel "resolver priority: auto-verified beats auto-coverage" (TestCase testResolverPriorityAutoVerifiedBeatsAutoCoverage)
  , TestLabel "resolver priority: curated beats auto-coverage" (TestCase testResolverPriorityCuratedBeatsAutoCoverage)
  , TestLabel "resolver priority: curated beats brain-kb-reviewed" (TestCase testResolverPriorityCuratedBeatsBrainReviewed)
  , TestLabel "resolver priority: higher quality wins within same tier" (TestCase testResolverPriorityHigherQualityWithinTier)
  , TestLabel "ambiguity fallback: same tier and quality returns raw surface" (TestCase testAmbiguityFallbackSameTierQuality)
  , TestLabel "ambiguity fallback: different tier resolves" (TestCase testAmbiguityFallbackDifferentTier)
  , TestLabel "old morphology maps: toNominative uses mdNominative first" (TestCase testOldMorphologyToNominative)
  , TestLabel "old morphology maps: genitiveForm uses mdGenitive first" (TestCase testOldMorphologyGenitive)
  , TestLabel "old morphology maps: prepositionalForm uses mdPrepositional first" (TestCase testOldMorphologyPrepositional)
  , TestLabel "candidate fallback: genitiveForm uses mdFormsBySurface" (TestCase testCandidateGenitiveFallback)
  , TestLabel "candidate fallback: accusativeForm inherits genitive fallback" (TestCase testCandidateAccusativeFallback)
  , TestLabel "JSON backward compatibility: MorphologyData parses without mdFormsBySurface" (TestCase testJsonBackwardCompatibility)
  , TestLabel "generated artifact: forms_by_surface.json is valid JSON" (TestCase testFormsBySurfaceValidJson)
  , TestLabel "generated artifact: forms_by_surface.json has expected object structure" (TestCase testFormsBySurfaceStructure)
  , TestLabel "tierPriority: curated=4, brainReviewed=3, autoVerified=2, autoCoverage=1" (TestCase testTierPriorityValues)
  ]

-- 1. Resolver priority: curated > auto-verified > auto-coverage

testResolverPriorityCuratedBeatsAutoVerified :: Assertion
testResolverPriorityCuratedBeatsAutoVerified = do
  let autoVerifiedForm = LexemeForm "свобода" "свобода" "noun" NominativeCase SingularNumber AutoVerifiedTier 0.9
      curatedForm = LexemeForm "свобода" "свобода" "noun" NominativeCase SingularNumber CuratedTier 0.8
      md = MorphologyData Map.empty Map.empty Map.empty (Map.fromList [("свобода", [autoVerifiedForm, curatedForm])])
      result = resolveLexemeForm md "свобода" (Just NominativeCase) (Just SingularNumber)
  assertEqual "curated tier should beat auto-verified even with lower quality" (Just curatedForm) result

testResolverPriorityBrainReviewedBeatsAutoVerified :: Assertion
testResolverPriorityBrainReviewedBeatsAutoVerified = do
  let autoVerifiedForm = LexemeForm "рамка" "рамка" "noun" NominativeCase SingularNumber AutoVerifiedTier 0.95
      brainReviewedForm = LexemeForm "рамка" "рамка" "noun" NominativeCase SingularNumber BrainKbReviewedTier 0.8
      md = MorphologyData Map.empty Map.empty Map.empty (Map.fromList [("рамка", [autoVerifiedForm, brainReviewedForm])])
      result = resolveLexemeForm md "рамка" (Just NominativeCase) (Just SingularNumber)
  assertEqual "brain-kb-reviewed tier should beat auto-verified" (Just brainReviewedForm) result

testResolverPriorityAutoVerifiedBeatsAutoCoverage :: Assertion
testResolverPriorityAutoVerifiedBeatsAutoCoverage = do
  let autoCoverageForm = LexemeForm "свобода" "свобода" "noun" NominativeCase SingularNumber AutoCoverageTier 0.95
      autoVerifiedForm = LexemeForm "свобода" "свобода" "noun" NominativeCase SingularNumber AutoVerifiedTier 0.85
      md = MorphologyData Map.empty Map.empty Map.empty (Map.fromList [("свобода", [autoCoverageForm, autoVerifiedForm])])
      result = resolveLexemeForm md "свобода" (Just NominativeCase) (Just SingularNumber)
  assertEqual "auto-verified tier should beat auto-coverage even with lower quality" (Just autoVerifiedForm) result

testResolverPriorityCuratedBeatsAutoCoverage :: Assertion
testResolverPriorityCuratedBeatsAutoCoverage = do
  let autoCoverageForm = LexemeForm "свобода" "свобода" "noun" NominativeCase SingularNumber AutoCoverageTier 0.99
      curatedForm = LexemeForm "свобода" "свобода" "noun" NominativeCase SingularNumber CuratedTier 0.5
      md = MorphologyData Map.empty Map.empty Map.empty (Map.fromList [("свобода", [autoCoverageForm, curatedForm])])
      result = resolveLexemeForm md "свобода" (Just NominativeCase) (Just SingularNumber)
  assertEqual "curated tier should beat auto-coverage regardless of quality" (Just curatedForm) result

testResolverPriorityCuratedBeatsBrainReviewed :: Assertion
testResolverPriorityCuratedBeatsBrainReviewed = do
  let brainReviewedForm = LexemeForm "смысл" "смысл" "noun" NominativeCase SingularNumber BrainKbReviewedTier 0.99
      curatedForm = LexemeForm "смысл" "смысл" "noun" NominativeCase SingularNumber CuratedTier 0.7
      md = MorphologyData Map.empty Map.empty Map.empty (Map.fromList [("смысл", [brainReviewedForm, curatedForm])])
      result = resolveLexemeForm md "смысл" (Just NominativeCase) (Just SingularNumber)
  assertEqual "curated tier should beat brain-kb-reviewed tier" (Just curatedForm) result

testResolverPriorityHigherQualityWithinTier :: Assertion
testResolverPriorityHigherQualityWithinTier = do
  let lowQualityForm = LexemeForm "форма" "низкая" "noun" NominativeCase SingularNumber AutoVerifiedTier 0.6
      highQualityForm = LexemeForm "форма" "высокая" "noun" NominativeCase SingularNumber AutoVerifiedTier 0.9
      md = MorphologyData Map.empty Map.empty Map.empty (Map.fromList [("форма", [lowQualityForm, highQualityForm])])
      result = resolveLexemeForm md "форма" (Just NominativeCase) (Just SingularNumber)
  assertEqual "higher quality should win within the same tier" (Just highQualityForm) result

-- 2. Ambiguity fallback: same tier and quality returns raw surface (Nothing from resolver)

testAmbiguityFallbackSameTierQuality :: Assertion
testAmbiguityFallbackSameTierQuality = do
  let form1 = LexemeForm "боли" "боль" "noun" NominativeCase SingularNumber CuratedTier 0.9
      form2 = LexemeForm "боли" "боля" "noun" NominativeCase SingularNumber CuratedTier 0.9
      md = MorphologyData Map.empty Map.empty Map.empty (Map.fromList [("боли", [form1, form2])])
      result = resolveLexemeForm md "боли" (Just NominativeCase) (Just SingularNumber)
  assertEqual "same tier and quality should be ambiguous, returning Nothing" Nothing result

testAmbiguityFallbackDifferentTier :: Assertion
testAmbiguityFallbackDifferentTier = do
  let form1 = LexemeForm "боли" "боль" "noun" NominativeCase SingularNumber CuratedTier 0.9
      form2 = LexemeForm "боли" "боля" "noun" NominativeCase SingularNumber AutoCoverageTier 0.9
      md = MorphologyData Map.empty Map.empty Map.empty (Map.fromList [("боли", [form1, form2])])
      result = resolveLexemeForm md "боли" (Just NominativeCase) (Just SingularNumber)
  assertEqual "different tiers should resolve to curated candidate" (Just form1) result

-- 3. Old morphology maps still work: toNominative, genitiveForm, prepositionalForm
--    use mdNominative/mdGenitive/mdPrepositional first

testOldMorphologyToNominative :: Assertion
testOldMorphologyToNominative = do
  let nomMap = Map.fromList [("свободе", "свобода"), ("диалога", "диалог")]
      md = MorphologyData Map.empty Map.empty nomMap Map.empty
  assertEqual "toNominative should use mdNominative direct lookup" "свобода" (toNominative md "свободе")
  assertEqual "toNominative should use mdNominative direct lookup" "диалог" (toNominative md "диалога")
  assertEqual "toNominative should fallback to surface for unknown" "неизвестно" (toNominative md "неизвестно")

testOldMorphologyGenitive :: Assertion
testOldMorphologyGenitive = do
  let genMap = Map.fromList [("свобода", "свободы"), ("диалог", "диалога")]
      md = MorphologyData Map.empty genMap Map.empty Map.empty
  assertEqual "genitiveForm should use mdGenitive direct lookup" "свободы" (genitiveForm md "свобода")
  assertEqual "genitiveForm should use mdGenitive direct lookup" "диалога" (genitiveForm md "диалог")
  assertEqual "genitiveForm should fallback to surface for unknown" "неизвестно" (genitiveForm md "неизвестно")

testOldMorphologyPrepositional :: Assertion
testOldMorphologyPrepositional = do
  let prepMap = Map.fromList [("свобода", "свободе"), ("диалог", "диалоге")]
      md = MorphologyData prepMap Map.empty Map.empty Map.empty
  assertEqual "prepositionalForm should use mdPrepositional direct lookup" "свободе" (prepositionalForm md "свобода")
  assertEqual "prepositionalForm should use mdPrepositional direct lookup" "диалоге" (prepositionalForm md "диалог")
  assertEqual "prepositionalForm should fallback to surface for unknown" "неизвестно" (prepositionalForm md "неизвестно")

testCandidateGenitiveFallback :: Assertion
testCandidateGenitiveFallback = do
  let genForm = LexemeForm "человека" "человек" "noun" GenitiveCase SingularNumber AutoVerifiedTier 0.9
      md = MorphologyData Map.empty Map.empty Map.empty (Map.fromList [("человек", [genForm])])
  assertEqual "genitiveForm should use candidate forms when flat map misses" "человека" (genitiveForm md "человек")

testCandidateAccusativeFallback :: Assertion
testCandidateAccusativeFallback = do
  let accForm = LexemeForm "человека" "человек" "noun" AccusativeCase SingularNumber AutoVerifiedTier 0.9
      md = MorphologyData Map.empty Map.empty Map.empty (Map.fromList [("человек", [accForm])])
  assertEqual "accusativeForm should prefer explicit candidate accusative form" "человека" (accusativeForm md "человек")

-- 4. JSON backward compatibility: MorphologyData can be parsed from JSON without mdFormsBySurface field

testJsonBackwardCompatibility :: Assertion
testJsonBackwardCompatibility = do
  let jsonWithoutFormsBySurface = T.unlines
        [ "{"
        , "  \"mdPrepositional\": {\"свобода\": \"свободе\"},"
        , "  \"mdGenitive\": {\"свобода\": \"свободы\"},"
        , "  \"mdNominative\": {\"свободе\": \"свобода\"}"
        , "}"
        ]
      jsonWithEmptyFormsBySurface = T.unlines
        [ "{"
        , "  \"mdPrepositional\": {\"свобода\": \"свободе\"},"
        , "  \"mdGenitive\": {\"свобода\": \"свободы\"},"
        , "  \"mdNominative\": {\"свободе\": \"свобода\"},"
        , "  \"mdFormsBySurface\": {}"
        , "}"
        ]
  case eitherDecodeStrict' (TE.encodeUtf8 jsonWithoutFormsBySurface) of
    Left err -> assertFailure ("MorphologyData should parse without mdFormsBySurface: " <> err)
    Right (md :: MorphologyData) -> do
      assertEqual "mdNominative should be populated" (Map.fromList [("свободе", "свобода")]) (mdNominative md)
      assertEqual "mdGenitive should be populated" (Map.fromList [("свобода", "свободы")]) (mdGenitive md)
      assertEqual "mdPrepositional should be populated" (Map.fromList [("свобода", "свободе")]) (mdPrepositional md)
      assertEqual "mdFormsBySurface should default to empty" Map.empty (mdFormsBySurface md)
  case eitherDecodeStrict' (TE.encodeUtf8 jsonWithEmptyFormsBySurface) of
    Left err -> assertFailure ("MorphologyData should parse with empty mdFormsBySurface: " <> err)
    Right (md :: MorphologyData) ->
      assertEqual "mdFormsBySurface should be empty map" Map.empty (mdFormsBySurface md)

-- 5. Generated artifact check: forms_by_surface.json is valid and contains expected structure

testFormsBySurfaceValidJson :: Assertion
testFormsBySurfaceValidJson = do
  let formsPath = "resources" </> "morphology" </> "forms_by_surface.json"
  exists <- doesFileExist formsPath
  if not exists
    then assertFailure ("forms_by_surface.json not found at " <> formsPath)
    else do
      raw <- TIO.readFile formsPath
      case eitherDecodeStrict' (TE.encodeUtf8 raw) of
        Left err -> assertFailure ("forms_by_surface.json is not valid JSON: " <> err)
        Right (_ :: Map.Map Text [LexemeForm]) -> pure ()

testFormsBySurfaceStructure :: Assertion
testFormsBySurfaceStructure = do
  let formsPath = "resources" </> "morphology" </> "forms_by_surface.json"
  exists <- doesFileExist formsPath
  if not exists
    then assertFailure ("forms_by_surface.json not found at " <> formsPath)
    else do
      raw <- TIO.readFile formsPath
      case eitherDecodeStrict' (TE.encodeUtf8 raw) of
        Left err -> assertFailure ("forms_by_surface.json parse error: " <> err)
        Right (m :: Map.Map Text [LexemeForm]) -> do
          assertBool "forms_by_surface.json should be a JSON object (Map)" True
          let allFormsNonEmpty = all (not . null) (Map.elems m)
          assertBool "each surface key should have at least one form" allFormsNonEmpty

-- Additional: tier priority values are correct

testTierPriorityValues :: Assertion
testTierPriorityValues = do
  assertEqual "CuratedTier priority should be 4" 4 (tierPriority CuratedTier)
  assertEqual "BrainKbReviewedTier priority should be 3" 3 (tierPriority BrainKbReviewedTier)
  assertEqual "AutoVerifiedTier priority should be 2" 2 (tierPriority AutoVerifiedTier)
  assertEqual "AutoCoverageTier priority should be 1" 1 (tierPriority AutoCoverageTier)
