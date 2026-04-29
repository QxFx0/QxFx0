{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DerivingStrategies #-}

module Test.Suite.SemanticCorpus
  ( semanticCorpusTests
  ) where

import Control.Monad (forM_, unless, when)
import Data.Aeson (FromJSON(..), eitherDecodeStrict', withObject, (.:))
import Data.Char (isAlphaNum)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Text.IO as TIO
import System.FilePath ((</>))
import Test.HUnit

import qualified QxFx0.Bridge.NixGuard as NixGuard
import QxFx0.Semantic.Logic (runSemanticLogic)
import QxFx0.Semantic.MeaningAtoms (collectAtoms)
import QxFx0.Semantic.Proposition (parseProposition)
import QxFx0.Types (ClusterDef(..), NixGuardStatus(..), ipfCanonicalFamily, ipfFocusEntity, ipfFocusNominative)

data SemanticCorpusCase = SemanticCorpusCase
  { sccId :: !Text
  , sccTier :: !Text
  , sccLang :: !Text
  , sccClass :: !Text
  , sccInput :: !Text
  , sccMustNotFamily :: ![Text]
  , sccExpectedFamilyAnyOf :: ![Text]
  , sccMustNotFocus :: ![Text]
  , sccMustNotGuardReasonContains :: ![Text]
  , sccRequiresReplayEnvelope :: !Bool
  } deriving stock (Show)

instance FromJSON SemanticCorpusCase where
  parseJSON = withObject "SemanticCorpusCase" $ \o ->
    SemanticCorpusCase
      <$> o .: "id"
      <*> o .: "tier"
      <*> o .: "lang"
      <*> o .: "class"
      <*> o .: "input"
      <*> o .: "must_not_family"
      <*> o .: "expected_family_any_of"
      <*> o .: "must_not_focus"
      <*> o .: "must_not_guard_reason_contains"
      <*> o .: "requires_replay_envelope"

semanticCorpusTests :: [Test]
semanticCorpusTests =
  [ TestLabel "semantic corpus file has expected shape" (TestCase testSemanticCorpusShape)
  , TestLabel "semantic corpus P0/P1 pure invariants hold" (TestCase testSemanticCorpusPureInvariants)
  , TestLabel "semantic corpus NixGuard degradation is not semantic repair" (TestCase testNixGuardCorpusDiagnostics)
  ]

testSemanticCorpusShape :: Assertion
testSemanticCorpusShape = do
  corpusCases <- readSemanticCorpus
  assertEqual "semantic corpus case count" 110 (length corpusCases)
  assertEqual "P0 case count" 5 (tierCount "P0" corpusCases)
  assertEqual "P1 case count" 88 (tierCount "P1" corpusCases)
  assertEqual "P2 case count" 17 (tierCount "P2" corpusCases)
  forM_ corpusCases $ \c -> do
    assertBool (caseLabel c <> " has id") (not (T.null (sccId c)))
    assertBool (caseLabel c <> " has lang") (sccLang c `elem` ["ru", "en"])
    assertBool (caseLabel c <> " has class") (not (T.null (sccClass c)))
    assertBool (caseLabel c <> " requires replay envelope") (sccRequiresReplayEnvelope c)

testSemanticCorpusPureInvariants :: Assertion
testSemanticCorpusPureInvariants = do
  corpusCases <- readSemanticCorpus
  forM_ (filter isEnforcedTier corpusCases) $ \c -> do
    let frame = parseProposition (sccInput c)
        focus = normalizeFocus (firstNonEmpty [ipfFocusNominative frame, ipfFocusEntity frame])
        atoms = collectAtoms (sccInput c) semanticCorpusClusters
        families = map (textShow . fst) (runSemanticLogic atoms)
        canonicalFamily = textShow (ipfCanonicalFamily frame)
    forM_ (sccMustNotFocus c) $ \badFocus ->
      unless (T.null focus) $
        assertBool
          (caseLabel c <> " focus must not be " <> T.unpack badFocus <> "; actual=" <> T.unpack focus)
          (focus /= normalizeFocus badFocus)
    forM_ (sccMustNotFamily c) $ \badFamily ->
      assertBool
        (caseLabel c <> " semantic logic must not rank " <> T.unpack badFamily <> "; ranked=" <> show families)
        (badFamily `notElem` families)
    when (sccTier c == "P0" && not (null (sccExpectedFamilyAnyOf c))) $
      assertBool
        (caseLabel c <> " canonical family must stay in expected routing band; actual=" <> T.unpack canonicalFamily)
        (canonicalFamily `elem` sccExpectedFamilyAnyOf c)

testNixGuardCorpusDiagnostics :: Assertion
testNixGuardCorpusDiagnostics = do
  corpusCases <- readSemanticCorpus
  forM_ (filter ((== "P0") . sccTier) corpusCases) $ \c -> do
    let frame = parseProposition (sccInput c)
        concept = firstNonEmpty [ipfFocusNominative frame, ipfFocusEntity frame]
    status <- NixGuard.checkConstitution "semantics/concepts.nix" concept 0.0 0.0
    let rendered = T.toLower (textShow status)
    forM_ (sccMustNotGuardReasonContains c) $ \needle ->
      assertBool
        (caseLabel c <> " guard diagnostic must not contain " <> T.unpack needle <> "; status=" <> T.unpack rendered)
        (not (T.toLower needle `T.isInfixOf` rendered))
    case status of
      Blocked reason ->
        assertBool
          (caseLabel c <> " explicit policy block must not be caused by unsupported ordinary prose; reason=" <> T.unpack reason)
          (not ("unsupported" `T.isInfixOf` T.toLower reason))
      _ -> pure ()

readSemanticCorpus :: IO [SemanticCorpusCase]
readSemanticCorpus = do
  raw <- TIO.readFile corpusPath
  let nonEmptyLines = filter (not . T.null . T.strip) (T.lines raw)
  case traverse decodeLine (zip [(1 :: Int)..] nonEmptyLines) of
    Left err -> assertFailure err >> pure []
    Right corpusCases -> pure corpusCases
  where
    decodeLine (lineNo, lineText) =
      case eitherDecodeStrict' (TE.encodeUtf8 lineText) of
        Left err -> Left ("invalid semantic corpus JSONL line " <> show lineNo <> ": " <> err)
        Right c -> Right c

corpusPath :: FilePath
corpusPath = "test" </> "golden" </> "semantic_corpus.jsonl"

semanticCorpusClusters :: [ClusterDef]
semanticCorpusClusters =
  [ ClusterDef
      { cdName = "exhaustion"
      , cdKeywords = ["устал", "устала", "выгорел", "выгорела", "нет сил"]
      , cdPriority = 1.0
      }
  , ClusterDef
      { cdName = "verification"
      , cdKeywords = ["доказательство", "докажи", "verify", "proof"]
      , cdPriority = 1.0
      }
  , ClusterDef
      { cdName = "doubt"
      , cdKeywords = ["разница", "отличие", "отличается", "distinguish", "difference"]
      , cdPriority = 1.0
      }
  , ClusterDef
      { cdName = "logicalinference"
      , cdKeywords = ["следует из", "не следует из", "влечёт", "вытекает из", "follows from", "does not follow"]
      , cdPriority = 1.0
      }
  , ClusterDef
      { cdName = "proofrequest"
      , cdKeywords = ["доказательство", "обоснование", "докажи", "обоснуй", "proof", "justify"]
      , cdPriority = 1.0
      }
  , ClusterDef
      { cdName = "distinctionrequest"
      , cdKeywords = ["необходимое условие", "достаточное условие", "чем отличается", "necessary condition", "sufficient condition"]
      , cdPriority = 1.0
      }
  , ClusterDef
      { cdName = "counterexamplerequest"
      , cdKeywords = ["контрпример", "опровержение", "противоречие", "counterexample", "refutation", "contradiction"]
      , cdPriority = 1.0
      }
  , ClusterDef
      { cdName = "obligationduty"
      , cdKeywords = ["должен", "обязан", "нужно", "must", "should"]
      , cdPriority = 1.0
      }
  , ClusterDef
      { cdName = "permissionright"
      , cdKeywords = ["имеет право", "не имеет права", "вправе", "allowed to", "has the right"]
      , cdPriority = 1.0
      }
  , ClusterDef
      { cdName = "temporalordering"
      , cdKeywords = ["когда", "пока", "прежде чем", "после того как", "before", "after", "while"]
      , cdPriority = 1.0
      }
  , ClusterDef
      { cdName = "contrastcorrection"
      , cdKeywords = ["не доказательство а объяснение", "не причина а основание", "however", "although", "not proof but explanation"]
      , cdPriority = 1.0
      }
  ]

isEnforcedTier :: SemanticCorpusCase -> Bool
isEnforcedTier c = sccTier c `elem` ["P0", "P1"]

tierCount :: Text -> [SemanticCorpusCase] -> Int
tierCount tier = length . filter ((== tier) . sccTier)

normalizeFocus :: Text -> Text
normalizeFocus raw =
  case simpleTokens raw of
    (token:_) -> token
    [] -> T.toLower (T.strip raw)

simpleTokens :: Text -> [Text]
simpleTokens =
  filter (not . T.null)
    . T.words
    . T.map (\c -> if isAlphaNum c || c == '_' || c == '-' then c else ' ')
    . T.toLower

firstNonEmpty :: [Text] -> Text
firstNonEmpty = foldr (\candidate acc -> if T.null (T.strip candidate) then acc else candidate) ""

caseLabel :: SemanticCorpusCase -> String
caseLabel c = T.unpack (sccId c)

textShow :: Show a => a -> Text
textShow = T.pack . show
