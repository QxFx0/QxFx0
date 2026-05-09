{-# LANGUAGE OverloadedStrings #-}
{-|
Manual decomposition of knowledge-base facts into MeaningAtom slots.

Each fact is decomposed into structured slots with full morphological forms.
This is the "understanding" layer — the bridge between flat text and
assembly operations.

Module structure:
  MeaningDecompose         — facade (re-exports)
  MeaningDecompose.Core    — lookup API (factBySubject, decomposedFacts)
  MeaningDecompose.Domains — all FactAtoms definitions by domain
-}
module QxFx0.Semantic.MeaningDecompose
  ( decomposedFacts
  , factBySubject
  , heartFacts
  , bloodFacts
  ) where

import QxFx0.Semantic.MeaningDecompose.Core
