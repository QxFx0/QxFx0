{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DerivingStrategies #-}

module Test.Suite.SurfaceAccumulatorGolden
  ( surfaceAccumulatorGoldenTests
  ) where

import Control.Monad (forM_, unless)
import Data.Aeson (FromJSON(..), eitherDecodeStrict', withObject, (.:))
import qualified Data.Map.Strict as M
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Text.IO as TIO
import System.Directory (getCurrentDirectory)
import System.FilePath ((</>))
import Test.HUnit

import QxFx0.Semantic.Content.Base (SemanticPredicate(..))
import QxFx0.Semantic.SurfaceAccumulator
  ( VerbalizationMode(..)
  , accumulateSurface
  )
import QxFx0.Self.Field
  ( Field(..)
  , emptyField
  , FieldConfidence(..)
  , Counterfactual(..)
  , Resonance(..)
  )
import QxFx0.Types (MorphologyData(..))

data GoldenCase = GoldenCase
  { gcName :: !Text
  , gcMode :: !Text
  , gcTopic :: !Text
  , gcFieldConfidence :: !Double
  , gcFieldCounterfactual :: !Double
  , gcFieldResonance :: !Double
  , gcPredicates :: ![SemanticPredicate]
  , gcExpected :: !Text
  }

instance FromJSON GoldenCase where
  parseJSON = withObject "GoldenCase" $ \o -> do
    modeText <- o .: "mode"
    unless (modeText `elem` ["VmDefinition", "VmChallenge", "VmReflection", "VmDistinction"]) $
      fail ("unknown VerbalizationMode: " ++ T.unpack modeText)
    GoldenCase
      <$> o .: "name"
      <*> pure modeText
      <*> o .: "topic"
      <*> o .: "field_confidence"
      <*> o .: "field_counterfactual"
      <*> o .: "field_resonance"
      <*> o .: "predicates"
      <*> o .: "expected"

emptyMd :: MorphologyData
emptyMd = MorphologyData M.empty M.empty M.empty M.empty

parseMode :: Text -> VerbalizationMode
parseMode "VmDefinition" = VmDefinition
parseMode "VmChallenge"  = VmChallenge
parseMode "VmReflection" = VmReflection
parseMode "VmDistinction" = VmDistinction
parseMode t = error ("unexpected mode in verified set: " ++ T.unpack t)

makeField :: GoldenCase -> Field
makeField c =
  emptyField
    { fieldConfidence = FieldConfidence (gcFieldConfidence c)
    , fieldCounterfactual = Counterfactual (gcFieldCounterfactual c)
    , fieldResonance = Resonance (gcFieldResonance c)
    }

goldenPath :: FilePath
goldenPath = "test" </> "golden" </> "spreading_activation_surface.jsonl"

surfaceAccumulatorGoldenTests :: [Test]
surfaceAccumulatorGoldenTests =
  [ TestLabel "spreading activation surface golden file" $ TestCase runGolden
  ]

runGolden :: IO ()
runGolden = do
  root <- getCurrentDirectory
  raw <- TIO.readFile (root </> goldenPath)
  let nonEmptyLines = filter (not . T.null . T.strip) (T.lines raw)
  cases <- mapM decodeLine (zip [(1 :: Int)..] nonEmptyLines)
  forM_ cases $ \c -> do
    let result = accumulateSurface
                   emptyMd
                   (makeField c)
                   (parseMode (gcMode c))
                   (gcTopic c)
                   (gcPredicates c)
    assertEqual (T.unpack (gcName c)) (gcExpected c) result
  where
    decodeLine (lineNo, lineText) =
      case eitherDecodeStrict' (TE.encodeUtf8 lineText) of
        Left err ->
          assertFailure ("invalid golden JSONL line " ++ show lineNo ++ ": " ++ err)
        Right c -> pure c
