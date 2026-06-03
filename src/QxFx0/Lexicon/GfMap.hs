{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE LambdaCase #-}

module QxFx0.Lexicon.GfMap
  ( GfLexemeForms(..)
  , GfMapLoadStatus(..)
  , defaultGfLexemeId
  , gfMapFallbackReason
  , gfMapProvenanceTag
  , topicToGfLexemeDecision
  , lookupTopicGfLexemeId
  , topicToGfLexemeId
  , lookupGfLexemeForms
  , gfMapLoadStatus
  , loadGfMapFromContent
  , loadGfMapStatusFromPath
  ) where

import Control.Applicative ((<|>))
import Data.Maybe (listToMaybe)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Data.Map.Strict as M
import Paths_qxfx0 (getDataFileName)
import QxFx0.ExceptionPolicy (catchIO)
import System.Environment (lookupEnv)
import System.FilePath ((</>))
import System.IO.Unsafe (unsafePerformIO)

data GfLexemeForms = GfLexemeForms
  { glfNom :: !Text
  , glfGen :: !Text
  , glfPrep :: !Text
  , glfAcc :: !Text
  , glfIns :: !Text
  } deriving stock (Eq, Show)

data GfMapData = GfMapData
  { gmdFormToFun :: !(M.Map Text Text)
  , gmdFunToForms :: !(M.Map Text GfLexemeForms)
  }

-- | Structured status of the GF lexicon map load at startup.
-- Consumers must check this if they need to distinguish a healthy
-- lexicon from a degraded/failed load.
data GfMapLoadStatus
  = GfMapLoaded !Int
    -- ^ Successfully loaded with the given number of form→fun entries.
  | GfMapLoadFailed !Text
    -- ^ Failed to load; the 'Text' carries a machine-readable reason tag.
  deriving stock (Eq, Show)

defaultGfLexemeId :: Text
defaultGfLexemeId = "ponyatie_N"

lookupTopicGfLexemeId :: Text -> Maybe Text
lookupTopicGfLexemeId rawTopic =
  let normalized = normalizeText rawTopic
      candidates = normalized : maybeToList (stripTopicMarker normalized)
      lookupFirst [] = Nothing
      lookupFirst (x:xs) = M.lookup x (gmdFormToFun gfMapData) <|> lookupFirst xs
  in lookupFirst candidates
  where
    maybeToList = maybe [] pure

topicToGfLexemeId :: Text -> Text
topicToGfLexemeId = fst . topicToGfLexemeDecision

topicToGfLexemeDecision :: Text -> (Text, Maybe Text)
topicToGfLexemeDecision topic =
  case gfMapFallbackReason gfMapLoadStatus of
    Just reason -> (defaultGfLexemeId, Just reason)
    Nothing ->
      case lookupTopicGfLexemeId topic of
        Just lexemeId -> (lexemeId, Nothing)
        Nothing -> (defaultGfLexemeId, Just "gf_default_lexeme")

lookupGfLexemeForms :: Text -> Maybe GfLexemeForms
lookupGfLexemeForms funId = M.lookup funId (gmdFunToForms gfMapData)

stripTopicMarker :: Text -> Maybe Text
stripTopicMarker txt =
  listToMaybe
    [ rest
    | marker <- ["о ", "об ", "обо ", "про "]
    , Just restRaw <- [T.stripPrefix marker txt]
    , let rest = T.strip restRaw
    , not (T.null rest)
    ]

normalizeText :: Text -> Text
normalizeText = T.toLower . T.replace "ё" "е" . T.strip

-- | Read-only immutable GF lexicon map loaded once from the canonical
-- GF lexicon funmap. The runtime surface remains pure while the load
-- status stays explicit and operator-visible.
gfMapLoadResult :: (GfMapData, GfMapLoadStatus)
gfMapLoadResult = unsafePerformIO loadCanonicalGfMap
{-# NOINLINE gfMapLoadResult #-}

gfMapData :: GfMapData
gfMapData = fst gfMapLoadResult

gfMapLoadStatus :: GfMapLoadStatus
gfMapLoadStatus = snd gfMapLoadResult

gfMapProvenanceTag :: Text
gfMapProvenanceTag =
  case gfMapLoadStatus of
    GfMapLoaded count -> "gf_map_loaded:" <> T.pack (show count)
    GfMapLoadFailed reason -> "gf_map_failed:" <> reason

gfMapFallbackReason :: GfMapLoadStatus -> Maybe Text
gfMapFallbackReason status =
  case status of
    GfMapLoaded _ -> Nothing
    GfMapLoadFailed reason -> Just ("gf_map_unavailable:" <> reason)

-- | Pure, total loader from optional file content.
-- Separated from IO so the failure paths are unit-testable.
loadGfMapFromContent :: Maybe Text -> (GfMapData, GfMapLoadStatus)
loadGfMapFromContent Nothing =
  (emptyGfMapData, GfMapLoadFailed "resource_missing_or_unreadable")
loadGfMapFromContent (Just content) =
  let parsed = parseGfMapData content
      entryCount = M.size (gmdFormToFun parsed)
  in if entryCount == 0
       then (parsed, GfMapLoadFailed "resource_empty_or_unparseable")
       else (parsed, GfMapLoaded entryCount)

loadCanonicalGfMap :: IO (GfMapData, GfMapLoadStatus)
loadCanonicalGfMap = do
  mContent <- readCanonicalFunmap
  pure (loadGfMapFromContent mContent)

loadGfMapStatusFromPath :: FilePath -> IO GfMapLoadStatus
loadGfMapStatusFromPath path = do
  mContent <- catchIO (Just . T.pack <$> readFile path) (const (pure Nothing))
  pure (snd (loadGfMapFromContent mContent))

readCanonicalFunmap :: IO (Maybe Text)
readCanonicalFunmap = do
  mResourceRoot <- lookupEnv "QXFX0_RESOURCE_ROOT"
  mRoot <- lookupEnv "QXFX0_ROOT"
  let mExplicitRoot = mResourceRoot <|> mRoot
  explicitContent <- case mExplicitRoot of
    Just root ->
      catchIO
        (Just . T.pack <$> readFile (root </> "spec" </> "gf" </> "lexicon_funmap.tsv"))
        (const (pure Nothing))
    Nothing -> pure Nothing
  case explicitContent of
    Just content -> pure (Just content)
    Nothing -> do
      dataPath <- catchIO (Just <$> getDataFileName "spec/gf/lexicon_funmap.tsv") (const (pure Nothing))
      case dataPath of
        Just path ->
          catchIO
            (Just . T.pack <$> readFile path)
            (const readRepoFallback)
        Nothing ->
          readRepoFallback
  where
    readRepoFallback =
      catchIO
        (Just . T.pack <$> readFile ("spec" </> "gf" </> "lexicon_funmap.tsv"))
        (const (pure Nothing))

parseGfMapData :: Text -> GfMapData
parseGfMapData content =
  foldl insertRow emptyGfMapData parsedRows
  where
    parsedRows = mapMaybeRow (T.lines content)
    mapMaybeRow = foldr (\line acc -> maybe acc (:acc) (parseRow line)) []

insertRow :: GfMapData -> (Text, Text, GfLexemeForms) -> GfMapData
insertRow acc (funId, lemma, forms) =
  let formKeys =
        [ lemma
        , glfNom forms
        , glfGen forms
        , glfPrep forms
        , glfAcc forms
        , glfIns forms
        ]
      formToFun' =
        foldr
          (\k m -> M.insertWith (\_ old -> old) (normalizeText k) funId m)
          (gmdFormToFun acc)
          formKeys
      funToForms' = M.insertWith (\_ old -> old) funId forms (gmdFunToForms acc)
  in GfMapData formToFun' funToForms'

parseRow :: Text -> Maybe (Text, Text, GfLexemeForms)
parseRow row =
  case T.splitOn "\t" row of
    [funId, lemma, _pos, nominative, genitive, prepositional] ->
      let forms =
            GfLexemeForms
              { glfNom = normalizeText nominative
              , glfGen = normalizeText genitive
              , glfPrep = normalizeText prepositional
              , glfAcc = normalizeText nominative
              , glfIns = normalizeText nominative
              }
      in Just (T.strip funId, normalizeText lemma, forms)
    [funId, lemma, _pos, nominative, genitive, prepositional, accusative, instrumental] ->
      let forms =
            GfLexemeForms
              { glfNom = normalizeText nominative
              , glfGen = normalizeText genitive
              , glfPrep = normalizeText prepositional
              , glfAcc = normalizeText accusative
              , glfIns = normalizeText instrumental
              }
      in Just (T.strip funId, normalizeText lemma, forms)
    _ ->
      Nothing

emptyGfMapData :: GfMapData
emptyGfMapData =
  GfMapData
    { gmdFormToFun = M.empty
    , gmdFunToForms = M.empty
    }
