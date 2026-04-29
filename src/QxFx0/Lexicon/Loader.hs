{-# LANGUAGE OverloadedStrings, StrictData #-}
module QxFx0.Lexicon.Loader
  ( loadLexicalRuntimeData
  , buildLexicalRuntimeData
  , fromMorphologyData
  ) where

import QxFx0.Lexicon.Types
import QxFx0.Types (MorphologyData(..))
import QxFx0.Lexicon.Generated (generatedLexemeEntries)
import QxFx0.Resources (loadMorphologyData)
import qualified Data.Map.Strict as Map
import Data.List (foldl')

fromMorphologyData :: MorphologyData -> LexicalRuntimeData
fromMorphologyData md = LexicalRuntimeData
  { lrdLanguage      = LanguageCode "ru"
  , lrdNominative    = mdNominative md
  , lrdGenitive      = mdGenitive md
  , lrdPrepositional = mdPrepositional md
  }

buildLexicalRuntimeData :: LexicalRuntimeData
buildLexicalRuntimeData = foldl' insertGroup (emptyLexicalRuntimeData (LanguageCode "ru")) (Map.toList grouped)
  where
    grouped = foldl' (\acc (surface, lemma, _pos, caseTag) ->
                        Map.insertWith (++) lemma [(surface, caseTag)] acc)
                     Map.empty generatedLexemeEntries
    insertGroup lrd (_lemma, forms) =
      let nom = lookupForm "nominative" forms
          gen = lookupForm "genitive" forms
          prep = lookupForm "prepositional" forms
      in case (nom, gen, prep) of
           (Just n, Just g, Just p) ->
             lrd { lrdNominative    = Map.insert n n $ Map.insert g n $ Map.insert p n $ lrdNominative lrd
                 , lrdGenitive      = Map.insert n g (lrdGenitive lrd)
                 , lrdPrepositional  = Map.insert n p (lrdPrepositional lrd)
                 }
           _ -> lrd
    lookupForm tag = lookup tag . map (\(sf, ct) -> (ct, sf))

loadLexicalRuntimeData :: IO LexicalRuntimeData
loadLexicalRuntimeData = do
  md <- loadMorphologyData
  pure (fromMorphologyData md)
