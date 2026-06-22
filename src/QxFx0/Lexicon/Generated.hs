{-# LANGUAGE OverloadedStrings #-}
-- GENERATED from spec/sql/lexicon/*.sql via scripts/generate_haskell_from_tsv.py
-- This is a thin re-export shim. The actual data lives in three independent modules
-- so that GHC can compile each one separately and the incremental cache survives restarts.
module QxFx0.Lexicon.Generated
  ( generatedLexemeEntries
  , generatedCandidateForms
  , generatedFiniteVerbMap
  ) where

import QxFx0.Lexicon.Generated.LexemeEntries (generatedLexemeEntries)
import QxFx0.Lexicon.Generated.CandidateForms (generatedCandidateForms)
import QxFx0.Lexicon.Generated.FiniteVerbMap (generatedFiniteVerbMap)
