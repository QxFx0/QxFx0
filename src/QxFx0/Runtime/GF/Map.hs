{-# LANGUAGE OverloadedStrings #-}
{-| Compat glue: provides v2 GfLexemeMap API using target's Lexicon.GfMap.
    Avoids importing Lexicon.Generated (Package C).
-}
module QxFx0.Runtime.GF.Map
  ( GfLexemeMap
  , buildGfLexemeMap
  , lookupTopicGfLexemeId
  , topicToGfLexemeId
  ) where

import Data.Text (Text)
import qualified QxFx0.Lexicon.GfMap as Legacy

data GfLexemeMap = GfLexemeMap

buildGfLexemeMap :: GfLexemeMap
buildGfLexemeMap = GfLexemeMap

lookupTopicGfLexemeId :: GfLexemeMap -> Text -> Maybe Text
lookupTopicGfLexemeId _ = Legacy.lookupTopicGfLexemeId

topicToGfLexemeId :: GfLexemeMap -> Text -> Text
topicToGfLexemeId _ = Legacy.topicToGfLexemeId
